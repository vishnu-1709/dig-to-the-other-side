extends Node
## Ads + gameplay events facade. Backend "fake" for development; CrazyGames / Poki
## backends are added in milestone 6 without changing any game code.

signal ad_started
signal ad_finished

const MIDGAME_COOLDOWN_S := 180.0
const NO_MIDGAME_FIRST_S := 120.0

var backend := "fake"
var _last_midgame := -1.0e9


func gameplay_start() -> void:
	print("PORTAL gameplay_start")


func gameplay_stop() -> void:
	print("PORTAL gameplay_stop")


## Rewarded ad. Usage: var ok: bool = await Portal.rewarded("double_run")
func rewarded(reason: String) -> bool:
	print("PORTAL rewarded ", reason)
	ad_started.emit()
	await get_tree().create_timer(0.6, true, false, true).timeout
	ad_finished.emit()
	return true


## Interstitial at a natural break. Respects cooldown and the new-player grace period.
func midgame(reason: String) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now < NO_MIDGAME_FIRST_S or now - _last_midgame < MIDGAME_COOLDOWN_S:
		print("PORTAL midgame skipped ", reason)
		return
	_last_midgame = now
	print("PORTAL midgame ", reason)
	ad_started.emit()
	await get_tree().create_timer(0.6, true, false, true).timeout
	ad_finished.emit()
