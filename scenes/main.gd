extends Node2D
## Game flow: HUB (shop) -> RUN (dig) -> RESULT (bank coins) -> HUB.
## Run with `-- --autoplay` for the headless bot playthrough used in CI.

enum State { HUB, RUN, RESULT }

const AUTOPLAY_RUNS := 8

var state := State.HUB
var shaft: Node2D
var autoplay := false
var _autoplay_runs := 0
var _result_ready := false
var _last_earned := 0.0
var _breakthrough := false

var _hub: Control
var _hub_coins: Label
var _hub_record: Label
var _buy_buttons := {}
var _sound_btn: Button
var _hud: Control
var _hud_depth: Label
var _hud_coins: Label
var _fuel_bar: ProgressBar
var _result: Control
var _result_title: Label
var _result_text: Label


func _ready() -> void:
	autoplay = "--autoplay" in OS.get_cmdline_user_args()
	if autoplay:
		Engine.time_scale = 8.0
	if OS.has_feature("web"):
		# iOS: play sound even when the silent switch is on (Safari 16.4+)
		JavaScriptBridge.eval("if (navigator.audioSession) { navigator.audioSession.type = 'playback'; }")
	get_tree().root.size_changed.connect(_apply_layout)
	_apply_layout()
	shaft = preload("res://scenes/shaft.gd").new()
	add_child(shaft)
	shaft.run_ended.connect(_on_run_ended)
	_build_ui()
	_show_hub()
	print("BOOT_OK biomes=%d rows=%d" % [Game.biomes.size(), Game.total_rows])


## Portrait screens use a 720x1280 base so UI stays readable on phones.
func _apply_layout() -> void:
	var win := get_window().size
	var want := Vector2i(720, 1280) if win.y > win.x else Vector2i(1280, 720)
	if get_tree().root.content_scale_size != want:
		get_tree().root.content_scale_size = want


# ---------------- flow ----------------
func _show_hub() -> void:
	state = State.HUB
	shaft.prepare()
	_hub.visible = true
	_hud.visible = false
	_result.visible = false
	_refresh_hub()


func _start_run() -> void:
	if state != State.HUB:
		return
	state = State.RUN
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
	_result_title.text = "YOU BROKE THROUGH!" if breakthrough else "OUT OF FUEL"
	_result_text.text = "+%s coins\nReached %s km  (%s)" % [Game.fmt(earned), Game.fmt(Game.depth_km(end_row)), b["name"]]
	_result.visible = true
	_result_ready = true


func _collect(mult: float) -> void:
	if state != State.RESULT or not _result_ready:
		return
	_result_ready = false
	Game.add_coins(_last_earned * mult)
	Music.sfx("coin", -2.0)
	Save.save_game()
	print("COLLECT %.1f x%.1f total=%.1f" % [_last_earned, mult, Game.coins])
	_show_hub()


func _double() -> void:
	if not _result_ready:
		return
	_result_ready = false
	var ok: bool = await Portal.rewarded("double_run")
	_result_ready = true
	_collect(2.0 if ok else 1.2)


func _buy(key: String) -> void:
	if state == State.HUB and Game.buy(key):
		Music.sfx("upgrade", -4.0)
		_refresh_hub()


# ---------------- per frame ----------------
func _process(_delta: float) -> void:
	if state == State.RUN:
		var b: Dictionary = Game.biomes[Game.biome_index(shaft.row)]
		_hud_depth.text = "%s   %s / 12,742 km" % [String(b["name"]).to_upper(), Game.fmt(Game.depth_km(shaft.row))]
		_hud_coins.text = "%s  (+%s)" % [Game.fmt(Game.coins), Game.fmt(shaft.earned)]
		_fuel_bar.value = 100.0 * shaft.fuel / shaft.fuel_max
	if autoplay:
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
		KEY_1:
			_buy("fuel")
		KEY_2:
			_buy("drill")
		KEY_3:
			_buy("ore")


func _autoplay_tick() -> void:
	match state:
		State.HUB:
			while true:
				var k: String = Game.UPGRADE_KEYS[0]
				for key in Game.UPGRADE_KEYS:
					if Game.cost(key) < Game.cost(k):
						k = key
				if not Game.buy(k):
					break
			if _autoplay_runs >= AUTOPLAY_RUNS:
				_finish_autoplay()
				return
			_autoplay_runs += 1
			_start_run()
		State.RUN:
			shaft.target_col = shaft.best_ore_col()
		State.RESULT:
			if _result_ready:
				_collect(1.0)


func _finish_autoplay() -> void:
	print("AUTOPLAY_OK runs=%d best_row=%d deepest_biome=%d coins=%.0f levels=%s" % [
		_autoplay_runs, Game.best_row, Game.deepest_biome, Game.coins, Game.levels])
	get_tree().quit(0 if Game.best_row > 0 else 1)


# ---------------- UI ----------------
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	theme.default_font_size = 30
	root.theme = theme
	layer.add_child(root)

	# --- hub ---
	_hub = _centered_panel(root)
	var hv: VBoxContainer = _hub.get_meta("box")
	_label(hv, "DIG TO THE OTHER SIDE", 40)
	_hub_record = _label(hv, "", 24)
	_hub_coins = _label(hv, "", 34)
	for key in Game.UPGRADE_KEYS:
		var b := _button(hv, "", _buy.bind(key))
		_buy_buttons[key] = b
	_sound_btn = _button(hv, "", _toggle_sound)
	_update_sound_btn()
	var dig := _button(hv, "DIG!", _start_run)
	dig.custom_minimum_size = Vector2(0, 90)
	dig.add_theme_font_size_override("font_size", 44)

	# --- HUD ---
	_hud = Control.new()
	_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hud)
	var top := HBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 24
	top.offset_right = -24
	top.offset_top = 16
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(top)
	_hud_depth = _label(top, "", 28)
	_hud_depth.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hud_depth.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_hud_coins = _label(top, "", 28)
	_hud_coins.add_theme_color_override("font_color", Color("ffd166"))
	_fuel_bar = ProgressBar.new()
	_fuel_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_fuel_bar.offset_left = 24
	_fuel_bar.offset_right = -24
	_fuel_bar.offset_top = -48
	_fuel_bar.offset_bottom = -20
	_fuel_bar.show_percentage = false
	_fuel_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("ff9f43")
	_fuel_bar.add_theme_stylebox_override("fill", fill)
	_hud.add_child(_fuel_bar)

	# --- result ---
	_result = _centered_panel(root)
	var rv: VBoxContainer = _result.get_meta("box")
	_result_title = _label(rv, "", 40)
	_result_text = _label(rv, "", 30)
	_button(rv, "COLLECT", _collect.bind(1.0))
	var dbl := _button(rv, "DOUBLE IT  (watch ad)", _double)
	dbl.add_theme_color_override("font_color", Color("7ff3ff"))


func _toggle_sound() -> void:
	Music.set_muted(not Music.muted)
	_update_sound_btn()
	Save.save_game()


func _update_sound_btn() -> void:
	_sound_btn.text = "Sound: ON" if not Music.muted else "Sound: OFF"


func _refresh_hub() -> void:
	_update_sound_btn()
	_hub_coins.text = "Coins: %s" % Game.fmt(Game.coins)
	var b: Dictionary = Game.biomes[Game.deepest_biome]
	_hub_record.text = "Deepest: %s  -  record %s km" % [b["name"], Game.fmt(Game.depth_km(Game.best_row))]
	for key in Game.UPGRADE_KEYS:
		var u: Dictionary = Game.upgrades[key]
		var btn: Button = _buy_buttons[key]
		if Game.is_maxed(key):
			btn.text = "%s  MAX" % u["name"]
			btn.disabled = true
		else:
			btn.text = "%s  Lv %d   %s   -  %s" % [u["name"], Game.levels[key], u["desc"], Game.fmt(Game.cost(key))]
			btn.disabled = not Game.can_buy(key)


func _centered_panel(parent: Control) -> Control:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(center)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.03, 0.12, 0.88)
	sb.set_corner_radius_all(24)
	sb.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	center.set_meta("box", box)
	return center


func _label(parent: Control, text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(560, 64)
	b.pressed.connect(func(): Music.sfx("click", -8.0))
	b.pressed.connect(cb)
	parent.add_child(b)
	return b
