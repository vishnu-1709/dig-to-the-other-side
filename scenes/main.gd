extends Node2D
## Game flow: HUB (shop) -> RUN (dig) -> RESULT (bank coins) -> HUB.
## `-- --autoplay` = 8-run bot check; `-- --autoplay=full` = bot plays to the breakthrough.

enum State { HUB, RUN, RESULT, POPUP }

const AUTOPLAY_RUNS := 8
const REFUEL_S := 10.0

var state := State.HUB
var shaft: Node2D
var autoplay := ""
var _autoplay_runs := 0
var _result_ready := false
var _last_earned := 0.0
var _breakthrough := false
var _reforge_armed := false
var _reforged_gain := -1
var _ui_timer := 0.0
var _portrait := false

var _root: Control
var _hub: Control
var _hub_box: BoxContainer
var _shop: VBoxContainer
var _side: VBoxContainer
var _hub_coins: Label
var _hub_rate: Label
var _hub_record: Label
var _cards := {}
var _overclock_btn: Button
var _reforge_btn: Button
var _sound_btn: Button
var _hud: Control
var _hud_depth: Label
var _hud_coins: Label
var _hud_boost: Label
var _fuel_bar: ProgressBar
var _result: Control
var _result_title: Label
var _result_text: Label
var _refuel_btn: Button
var _double_btn: Button
var _popup: Control
var _popup_text: Label
var _popup_amount := 0.0
var _planet: Control
var _banner: Label
var _flash: ColorRect
var _count_tween: Tween


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--autoplay"):
			autoplay = "full" if a == "--autoplay=full" else "quick"
	if autoplay != "":
		Engine.time_scale = 40.0 if autoplay == "full" else 8.0
	if OS.has_feature("web"):
		# iOS: play sound even when the silent switch is on (Safari 16.4+)
		JavaScriptBridge.eval("if (navigator.audioSession) { navigator.audioSession.type = 'playback'; }")
	shaft = preload("res://scenes/shaft.gd").new()
	add_child(shaft)
	shaft.run_ended.connect(_on_run_ended)
	shaft.biome_entered.connect(_on_biome_entered)
	_build_ui()
	get_tree().root.size_changed.connect(_apply_layout)
	_apply_layout()
	_show_hub()
	print("BOOT_OK biomes=%d rows=%d" % [Game.biomes.size(), Game.total_rows])
	if autoplay == "" and Game.offline_earnings() >= 1.0 and Game.offline_seconds > 60.0:
		_show_offline_popup()


## Portrait screens use a 720x1280 base so UI stays readable on phones.
func _apply_layout() -> void:
	var win := get_window().size
	_portrait = win.y > win.x
	var want := Vector2i(720, 1280) if _portrait else Vector2i(1280, 720)
	if get_tree().root.content_scale_size != want:
		get_tree().root.content_scale_size = want
	if _hub_box:
		_hub_box.vertical = _portrait
		_hub_box.move_child(_side, 0 if _portrait else 1)
		_planet.custom_minimum_size = Vector2(200, 200) if _portrait else Vector2(180, 180)
		for k in _cards:
			_cards[k].custom_minimum_size = Vector2(560, 64 if _portrait else 72)


# ---------------- flow ----------------
func _show_hub() -> void:
	state = State.HUB
	_reforge_armed = false
	shaft.prepare()
	_hub.visible = true
	_hud.visible = false
	_result.visible = false
	_popup.visible = false
	_refresh_hub()


func _start_run() -> void:
	if state != State.HUB:
		return
	state = State.RUN
	_reforged_gain = -1
	_hub.visible = false
	_hud.visible = true
	shaft.start()
	Music.start_run(Game.biome_index(shaft.row))
	Portal.gameplay_start()


func _on_run_ended(earned: float, end_row: int, breakthrough: bool) -> void:
	state = State.RESULT
	_result_ready = false
	_last_earned = earned
	_breakthrough = breakthrough
	Portal.gameplay_stop()
	Music.stop_run()
	_hud.visible = false
	if Game.pending_midgame:
		Game.pending_midgame = false
		await Portal.midgame("new_biome")
	var b: Dictionary = Game.biomes[Game.biome_index(end_row)]
	if breakthrough:
		_result_title.text = "YOU BROKE THROUGH!"
		_result_text.text = "+%s coins\nYou dug through 12,742 km of planet.\nReforge in the hub for permanent Core Shards." % Game.fmt(earned)
	else:
		_result_title.text = "OUT OF FUEL"
		_result_text.text = "+%s coins\nReached %s km  (%s)" % [Game.fmt(earned), Game.fmt(Game.depth_km(end_row)), b["name"]]
	_refuel_btn.visible = not breakthrough and not shaft.refueled
	_result.visible = true
	_result_ready = true
	_count_up(_result_text, earned)


func _on_biome_entered(bi: int) -> void:
	var b: Dictionary = Game.biomes[bi]
	_banner.text = String(b["name"]).to_upper()
	_banner.add_theme_color_override("font_color", Shaft.ORE_COL[bi])
	var tw := create_tween()
	tw.tween_property(_banner, "modulate:a", 1.0, 0.15)
	tw.tween_interval(1.4)
	tw.tween_property(_banner, "modulate:a", 0.0, 0.5)
	_flash.color = Color(1, 1, 1, 0.55)
	create_tween().tween_property(_flash, "color:a", 0.0, 0.45)


func _collect(mult: float) -> void:
	if state != State.RESULT or not _result_ready:
		return
	_result_ready = false
	Game.add_coins(_last_earned * mult)
	Music.sfx("coin", -2.0)
	print("COLLECT %.1f x%.1f total=%.1f" % [_last_earned, mult, Game.coins])
	Save.save_game()
	_show_hub()


## Animate the "+N coins" line counting up from 0.
func _count_up(label: Label, amount: float) -> void:
	if autoplay != "":
		return
	var full := label.text
	var first := full.get_slice("\n", 0)
	var rest := full.substr(first.length())
	if _count_tween:
		_count_tween.kill()
	_count_tween = create_tween()
	_count_tween.tween_method(func(v: float): label.text = "+%s coins%s" % [Game.fmt(v), rest], 0.0, amount, 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


func _double() -> void:
	if not _result_ready:
		return
	_result_ready = false
	var ok: bool = await Portal.rewarded("double_run")
	_result_ready = true
	_collect(2.0 if ok else 1.2)


func _refuel() -> void:
	if not _result_ready or shaft.refueled:
		return
	_result_ready = false
	var ok: bool = await Portal.rewarded("refuel")
	if not ok:
		_result_ready = true
		return
	_result.visible = false
	_hud.visible = true
	state = State.RUN
	shaft.resume(REFUEL_S)
	Music.start_run(Game.biome_index(shaft.row))
	Portal.gameplay_start()


func _overclock() -> void:
	if state != State.HUB or Game.overclock_left() > 0.0:
		return
	var ok: bool = await Portal.rewarded("overclock")
	if ok:
		Game.start_overclock()
		Music.sfx("upgrade", -2.0, 1.3)
		Save.save_game()
	_refresh_hub()


func _reforge() -> void:
	if state != State.HUB or not Game.can_reforge():
		return
	if not _reforge_armed:
		_reforge_armed = true
		_refresh_hub()
		return
	_reforged_gain = Game.reforge()
	Music.sfx("biome_enter", 0.0)
	Save.save_game()
	await Portal.midgame("reforge")
	_show_hub()


func _buy(key: String) -> void:
	if state == State.HUB and Game.buy(key):
		Music.sfx("upgrade", -4.0)
		_refresh_hub()


func _show_offline_popup() -> void:
	state = State.POPUP
	_popup_amount = Game.offline_earnings()
	var away := minf(Game.offline_seconds, float(Game.config["offline_cap_h"]) * 3600.0)
	_popup_text.text = "Your miners dug for %s\n+%s coins" % [Game.fmt_time(away), Game.fmt(_popup_amount)]
	_hub.visible = false
	_popup.visible = true


func _claim_offline(mult: float) -> void:
	if state != State.POPUP:
		return
	state = State.HUB
	if mult > 1.0:
		var ok: bool = await Portal.rewarded("offline_x3")
		if not ok:
			mult = 1.0
	Game.add_coins(_popup_amount * mult)
	Game.offline_seconds = 0.0
	Music.sfx("coin", -2.0)
	Save.save_game()
	_show_hub()


# ---------------- per frame ----------------
func _process(delta: float) -> void:
	if state == State.RUN:
		var b: Dictionary = Game.biomes[Game.biome_index(shaft.row)]
		_hud_depth.text = "%s   %s / 12,742 km" % [String(b["name"]).to_upper(), Game.fmt(Game.depth_km(shaft.row))]
		_hud_coins.text = "%s  (+%s)" % [Game.fmt(Game.coins), Game.fmt(shaft.earned)]
		_fuel_bar.value = 100.0 * shaft.fuel / maxf(shaft.fuel_max, 0.001)
		var oc := Game.overclock_left()
		_hud_boost.text = ("OVERCLOCK " + Game.fmt_time(oc)) if oc > 0.0 else ""
	elif state == State.HUB:
		_ui_timer += delta
		if _ui_timer > 0.25:
			_ui_timer = 0.0
			_refresh_hub()
	if autoplay != "":
		_autoplay_tick()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_ENTER, KEY_SPACE, KEY_KP_ENTER:
			if state == State.HUB:
				_start_run()
			elif state == State.RESULT:
				_collect(1.0)
			elif state == State.POPUP:
				_claim_offline(1.0)
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
			_buy(Game.UPGRADE_KEYS[event.keycode - KEY_1])


# ---------------- autoplay bot ----------------
func _autoplay_tick() -> void:
	match state:
		State.HUB:
			while true:
				var k := ""
				for key in Game.UPGRADE_KEYS:
					if not Game.is_maxed(key) and (k == "" or Game.cost(key) < Game.cost(k)):
						k = key
				if k == "" or not Game.buy(k):
					break
			if autoplay == "quick" and _autoplay_runs >= AUTOPLAY_RUNS:
				_finish_autoplay()
				return
			if autoplay == "full" and (Game.broke_through or Game.play_time > 3 * 3600):
				_finish_autoplay()
				return
			_autoplay_runs += 1
			_start_run()
		State.RUN:
			shaft.target_col = shaft.bot_target_col()
		State.RESULT:
			if _result_ready:
				_collect(1.0)


func _finish_autoplay() -> void:
	set_process(false)
	if autoplay == "full":
		var ok := Game.broke_through
		var gain := Game.reforge() if ok else 0
		print("AUTOPLAY_FULL broke_through=%s game_min=%.1f runs=%d levels=%s reforge_shards=%d" % [
			ok, Game.play_time / 60.0, _autoplay_runs, Game.levels, gain])
		get_tree().quit(0 if ok and gain > 0 else 1)
		return
	print("AUTOPLAY_OK runs=%d best_row=%d deepest_biome=%d coins=%.0f levels=%s" % [
		_autoplay_runs, Game.best_row, Game.deepest_biome, Game.coins, Game.levels])
	get_tree().quit(0 if Game.best_row > 0 else 1)


# ---------------- UI ----------------
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UiTheme.build()
	layer.add_child(_root)

	# --- hub: shop column + side column (side on top in portrait) ---
	_hub = _full_rect(_root)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	_hub.add_child(margin)
	_hub_box = BoxContainer.new()
	_hub_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_hub_box.add_theme_constant_override("separation", 24)
	_hub_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(_hub_box)

	_shop = VBoxContainer.new()
	_shop.alignment = BoxContainer.ALIGNMENT_CENTER
	_shop.add_theme_constant_override("separation", 8)
	_shop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hub_box.add_child(_shop)
	for key in Game.UPGRADE_KEYS:
		_cards[key] = _upgrade_card(_shop, key)

	_side = VBoxContainer.new()
	_side.alignment = BoxContainer.ALIGNMENT_CENTER
	_side.add_theme_constant_override("separation", 8)
	_side.custom_minimum_size = Vector2(560, 0)
	_side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hub_box.add_child(_side)
	_label(_side, "DIG TO THE OTHER SIDE", "Title")
	_planet = preload("res://scenes/planet_map.gd").new()
	_planet.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_side.add_child(_planet)
	_hub_record = _label(_side, "", "Small")
	_hub_coins = _label(_side, "", "Big")
	_hub_coins.add_theme_color_override("font_color", UiTheme.GOLD)
	_hub_rate = _label(_side, "", "Small")
	var dig := _button(_side, "DIG!", _start_run, "Primary")
	dig.custom_minimum_size = Vector2(0, 96)
	_overclock_btn = _button(_side, "", _overclock, "Ad")
	_reforge_btn = _button(_side, "", _reforge, "Special")
	_sound_btn = _button(_side, "", _toggle_sound)
	_sound_btn.custom_minimum_size = Vector2(0, 48)
	_overclock_btn.custom_minimum_size = Vector2(0, 56)
	_reforge_btn.custom_minimum_size = Vector2(0, 56)

	# --- HUD ---
	_hud = _full_rect(_root)
	var top := HBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 24
	top.offset_right = -24
	top.offset_top = 16
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(top)
	_hud_depth = _label(top, "", "Hud")
	_hud_depth.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hud_depth.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_hud_coins = _label(top, "", "Hud")
	_hud_coins.add_theme_color_override("font_color", UiTheme.GOLD)
	_hud_boost = _label(_hud, "", "Small")
	_hud_boost.position = Vector2(24, 64)
	_hud_boost.add_theme_color_override("font_color", UiTheme.CYAN)
	_banner = _label(_hud, "", "Title")
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_banner.offset_top = 120
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.add_theme_font_size_override("font_size", 56)
	_banner.modulate.a = 0.0
	_flash = ColorRect.new()
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_flash)
	_fuel_bar = ProgressBar.new()
	_fuel_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_fuel_bar.offset_left = 24
	_fuel_bar.offset_right = -24
	_fuel_bar.offset_top = -48
	_fuel_bar.offset_bottom = -20
	_fuel_bar.show_percentage = false
	_fuel_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_fuel_bar)

	# --- result ---
	_result = _centered_panel(_root)
	var rv: VBoxContainer = _result.get_meta("box")
	_result_title = _label(rv, "", "Title")
	_result_text = _label(rv, "", "")
	_button(rv, "COLLECT", _collect.bind(1.0), "Primary")
	_double_btn = _button(rv, "DOUBLE IT  (watch ad)", _double, "Ad")
	_refuel_btn = _button(rv, "REFUEL +10s  (watch ad)", _refuel, "Ad")

	# --- offline earnings popup ---
	_popup = _centered_panel(_root)
	var pv: VBoxContainer = _popup.get_meta("box")
	_label(pv, "WELCOME BACK!", "Title")
	_popup_text = _label(pv, "", "")
	_button(pv, "CLAIM", _claim_offline.bind(1.0), "Primary")
	_button(pv, "CLAIM x3  (watch ad)", _claim_offline.bind(3.0), "Ad")


func _toggle_sound() -> void:
	Music.set_muted(not Music.muted)
	Save.save_game()
	_refresh_hub()


func _refresh_hub() -> void:
	_sound_btn.text = "Sound: ON" if not Music.muted else "Sound: OFF"
	_hub_coins.text = Game.fmt(Game.coins) + " coins"
	var rate := Game.miner_rate()
	var parts: Array = []
	if rate > 0.0:
		parts.append(("Miners: +%s/s" % Game.fmt(rate)) if rate >= 10.0 else ("Miners: +%.1f/s" % rate))
	if Game.shards > 0:
		parts.append("Core Shards: %d (+%d%% coins)" % [Game.shards, int(round(Game.shards * Game.SHARD_BONUS * 100))])
	_hub_rate.text = "   ".join(parts)
	_hub_rate.visible = not parts.is_empty()
	if _reforged_gain >= 0:
		_hub_record.text = "REFORGED!  +%d Core Shards" % _reforged_gain
	else:
		var b: Dictionary = Game.biomes[Game.deepest_biome]
		_hub_record.text = "Deepest: %s  -  record %s km" % [b["name"], Game.fmt(Game.depth_km(Game.best_row))]
	var oc := Game.overclock_left()
	_overclock_btn.text = ("OVERCLOCK ACTIVE  " + Game.fmt_time(oc)) if oc > 0.0 else "OVERCLOCK: 2x dig speed, 3 min  (ad)"
	_overclock_btn.disabled = oc > 0.0
	_reforge_btn.visible = Game.can_reforge()
	if _reforge_armed:
		_reforge_btn.text = "TAP AGAIN: reset all for +%d Shards" % Game.reforge_gain()
	else:
		_reforge_btn.text = "REFORGE: reset for +%d Core Shards" % Game.reforge_gain()
	for key in Game.UPGRADE_KEYS:
		_update_card(key)


func _upgrade_card(parent: Control, key: String) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(560, 72)
	b.theme_type_variation = "Card"
	b.pressed.connect(func(): Music.sfx("click", -8.0))
	b.pressed.connect(_buy.bind(key))
	parent.add_child(b)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 18
	row.offset_right = -18
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.add_theme_constant_override("separation", -2)
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(texts)
	var name_l := _label(texts, "", "CardName")
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var desc_l := _label(texts, "", "Small")
	desc_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var cost_l := _label(row, "", "CardName")
	cost_l.add_theme_color_override("font_color", UiTheme.GOLD)
	b.set_meta("name", name_l)
	b.set_meta("desc", desc_l)
	b.set_meta("cost", cost_l)
	return b


func _update_card(key: String) -> void:
	var b: Button = _cards[key]
	var u: Dictionary = Game.upgrades[key]
	(b.get_meta("name") as Label).text = "%s  Lv %d" % [u["name"], Game.levels[key]]
	(b.get_meta("desc") as Label).text = String(u["desc"])
	var maxed := Game.is_maxed(key)
	(b.get_meta("cost") as Label).text = "MAX" if maxed else Game.fmt(Game.cost(key))
	b.disabled = maxed or not Game.can_buy(key)
	b.modulate.a = 0.55 if b.disabled else 1.0


func _full_rect(parent: Control) -> Control:
	var c := Control.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)
	return c


func _centered_panel(parent: Control) -> Control:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.custom_minimum_size = Vector2(560, 0)
	panel.add_child(box)
	center.set_meta("box", box)
	center.visible = false
	return center


func _label(parent: Control, text: String, variation: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if variation != "":
		l.theme_type_variation = variation
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _button(parent: Control, text: String, cb: Callable, variation := "") -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 64)
	if variation != "":
		b.theme_type_variation = variation
	b.pressed.connect(func(): Music.sfx("click", -8.0))
	b.pressed.connect(cb)
	parent.add_child(b)
	return b
