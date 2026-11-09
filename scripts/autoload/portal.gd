extends Node
## Ads + gameplay events + cloud data facade.
## Backends: "crazygames" (CrazyGames HTML5 SDK v3 via JavaScriptBridge) or "fake" (dev,
## GitHub Pages, localhost). The SDK script and init() are started in the HTML head
## (export_presets.cfg head_include) so init runs while the engine downloads.
## Policy (CrazyGames ad requirements): mute + pause only when an ad actually starts,
## unpause on finish/error, never reward on adError.

signal ready_changed
signal ad_started
signal ad_finished
signal _ad_done

const MIDGAME_COOLDOWN_S := 180.0
const NO_MIDGAME_FIRST_S := 120.0
const INIT_TIMEOUT_S := 5.0
const AD_TIMEOUT_S := 90.0

var backend := "fake"
var is_ready := false
var ad_showing := false
var _last_midgame := -1.0e9
var _init_wait := 0.0
var _ad_result := ""
var _ad_pending := false
var _cb_start  # JavaScriptObject callbacks must stay referenced while the ad runs
var _cb_done
var _was_paused := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.has_feature("web"):
		_set_ready("fake")
		return
	JavaScriptBridge.eval("""
		window.__cg = {ready: false, env: 'none'};
		(window.__cgInit || Promise.reject('nosdk')).then(
			function () { try { window.__cg.env = CrazyGames.SDK.environment; } catch (e) {} window.__cg.ready = true; },
			function () { window.__cg.ready = true; });
		window.dttosAd = function (type, onStart, onDone) {
			try {
				CrazyGames.SDK.ad.requestAd(type, {
					adStarted: function () { onStart(); },
					adFinished: function () { onDone('finished'); },
					adError: function (e) { onDone('error:' + (e && e.code ? e.code : 'other')); }
				});
			} catch (err) { onDone('error:exception'); }
		};
	""", true)


func _process(delta: float) -> void:
	if is_ready:
		return
	_init_wait += delta / maxf(Engine.time_scale, 0.001)
	var done = JavaScriptBridge.eval("window.__cg && window.__cg.ready", true)
	if done or _init_wait > INIT_TIMEOUT_S:
		var env := str(JavaScriptBridge.eval("window.__cg ? window.__cg.env : 'none'", true))
		_set_ready("crazygames" if env == "crazygames" else "fake")


func _set_ready(b: String) -> void:
	backend = b
	is_ready = true
	print("PORTAL ready backend=%s" % backend)
	if backend == "crazygames":
		_cg("game.loadingStop()")
	ready_changed.emit()


func _cg(call: String) -> void:
	JavaScriptBridge.eval("try { CrazyGames.SDK.%s; } catch (e) { console.warn('CG', e); }" % call, true)


# ---------------- game events ----------------
func gameplay_start() -> void:
	print("PORTAL gameplay_start")
	if backend == "crazygames":
		_cg("game.gameplayStart()")


func gameplay_stop() -> void:
	print("PORTAL gameplay_stop")
	if backend == "crazygames":
		_cg("game.gameplayStop()")


## Celebration for rare achievements (breakthrough, Reforge). Use sparingly.
func happytime() -> void:
	print("PORTAL happytime")
	if backend == "crazygames":
		_cg("game.happytime()")


# ---------------- ads ----------------
## Rewarded ad. true only when the ad finished. Usage: var ok: bool = await Portal.rewarded("x")
func rewarded(reason: String) -> bool:
	print("PORTAL rewarded ", reason)
	if backend != "crazygames":
		_on_started()
		await get_tree().create_timer(0.6, true, false, true).timeout
		_on_finished()
		return true
	return await _request("rewarded")


## Interstitial at a natural break. Respects cooldown and the new-player grace period.
## Returns true if an ad was actually shown.
func midgame(reason: String) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	if now < NO_MIDGAME_FIRST_S or now - _last_midgame < MIDGAME_COOLDOWN_S:
		print("PORTAL midgame skipped ", reason)
		return false
	_last_midgame = now
	print("PORTAL midgame ", reason)
	if backend != "crazygames":
		_on_started()
		await get_tree().create_timer(0.6, true, false, true).timeout
		_on_finished()
		return true
	return await _request("midgame")


func _request(type: String) -> bool:
	if _ad_pending:
		return false
	_ad_pending = true
	_ad_result = ""
	_cb_start = JavaScriptBridge.create_callback(func(_args): _on_started())
	_cb_done = JavaScriptBridge.create_callback(func(args): _on_done(str(args[0]) if args.size() > 0 else "error:other"))
	var win := JavaScriptBridge.get_interface("window")
	win.dttosAd(type, _cb_start, _cb_done)
	get_tree().create_timer(AD_TIMEOUT_S, true, false, true).timeout.connect(_ad_timeout)
	await _ad_done
	print("PORTAL %s -> %s" % [type, _ad_result])
	return _ad_result == "finished"


func _ad_timeout() -> void:
	if _ad_pending and _ad_result == "":
		_on_done("error:timeout")


func _on_done(result: String) -> void:
	if not _ad_pending:
		return
	_ad_result = result
	_ad_pending = false
	_on_finished()
	_ad_done.emit()


func _on_started() -> void:
	if ad_showing:
		return
	ad_showing = true
	_was_paused = get_tree().paused
	get_tree().paused = true
	ad_started.emit()


func _on_finished() -> void:
	if not ad_showing:
		return
	ad_showing = false
	get_tree().paused = _was_paused
	ad_finished.emit()


# ---------------- cloud data ----------------
func data_get(key: String) -> String:
	if backend != "crazygames":
		return ""
	var v = JavaScriptBridge.eval("(function(){ try { return CrazyGames.SDK.data.getItem(%s); } catch (e) { return null; } })()" % JSON.stringify(key), true)
	return "" if v == null else str(v)


func data_set(key: String, value: String) -> void:
	if backend != "crazygames":
		return
	JavaScriptBridge.eval("try { CrazyGames.SDK.data.setItem(%s, %s); } catch (e) {}" % [JSON.stringify(key), JSON.stringify(value)], true)
