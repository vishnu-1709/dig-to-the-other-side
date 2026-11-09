extends Node2D
## One dig run. Blocks are computed from a hash of (col, row) — only dug cells are stored,
## and only on-screen rows are drawn. Drill steps one row at a time, shifting at most one
## column per row toward the steering target.

signal run_ended(earned: float, end_row: int, breakthrough: bool)
signal biome_entered(index: int)

const TILE := 64
const COLS := 9
const ORE_P := 0.12
const HARD_P := 0.08
const EMPTY := -1
const ROCK := 0
const ORE := 1
const HARD := 2

const ROCK_COL := [Color("7a5534"), Color("a08a6a"), Color("6d6a5a"), Color("3c2f6e"),
	Color("4a1f1a"), Color("6b2a10"), Color("2a3a5a"), Color("2f5a3a")]
const ORE_COL := [Color("e08a3c"), Color("ffb52e"), Color("ffd700"), Color("7ff3ff"),
	Color("b04cff"), Color("ff5a1f"), Color("c0e0ff"), Color("9dff6a")]

var running := false
var row := 0
var col := COLS / 2
var target_col := COLS / 2
var progress := 0.0
var fuel := 0.0
var fuel_max := 1.0
var earned := 0.0
var start_row := 0
var blocked := false

var _seed := 0
var _dug := {}
var _drill_pos := Vector2.ZERO
var _popups: Array = []
var _shake := 0.0
var _cam: Camera2D
var _font: Font


func _ready() -> void:
	_cam = Camera2D.new()
	add_child(_cam)
	_cam.make_current()
	_font = ThemeDB.fallback_font
	prepare()


## Place the drill at the checkpoint without starting (hub background).
func prepare() -> void:
	running = false
	_seed = randi()
	_dug.clear()
	start_row = Game.checkpoint_row()
	row = start_row
	col = COLS / 2
	target_col = col
	progress = 0.0
	earned = 0.0
	_dug[Vector2i(col, row)] = true
	_drill_pos = _cell_center(col, row)
	_popups.clear()


func start() -> void:
	prepare()
	fuel_max = Game.fuel_seconds()
	fuel = fuel_max
	running = true
	print("RUN_START row=%d fuel=%.1f power=%.2f" % [row, fuel_max, Game.dig_power()])


func cell(c: int, r: int) -> int:
	if c < 0 or c >= COLS:
		return HARD
	if r < start_row or _dug.has(Vector2i(c, r)):
		return EMPTY
	var v := _rand01(c, r)
	if v < ORE_P:
		return ORE
	if v < ORE_P + HARD_P:
		return HARD
	return ROCK


func _rand01(c: int, r: int) -> float:
	var x: int = (c * 73856093) ^ (r * 19349663) ^ _seed
	x = (x ^ (x >> 13)) * 1274126177
	x = x ^ (x >> 16)
	return float(absi(x) % 100000) / 100000.0


## Nearest ore in the next few rows that the drill can still reach (for the autoplay bot).
func best_ore_col() -> int:
	for dr in range(1, 5):
		var best := -1
		for c in range(COLS):
			if cell(c, row + dr) == ORE and absi(c - col) <= dr:
				if best == -1 or absi(c - col) < absi(best - col):
					best = c
		if best != -1:
			return best
	return col


func _process(delta: float) -> void:
	if running:
		_step(delta)
	var next_col := col + signi(target_col - col)
	var target := _cell_center(col, row).lerp(_cell_center(next_col, row + 1), progress if running else 0.0)
	_drill_pos = _drill_pos.lerp(target, clampf(delta * 18.0, 0.0, 1.0))
	_update_camera(delta)
	for p in _popups:
		p["t"] += delta
		p["pos"] = p["pos"] + Vector2(0, -60.0 * delta)
	_popups = _popups.filter(func(p): return p["t"] < 0.9)
	queue_redraw()


func _step(delta: float) -> void:
	fuel -= delta
	if fuel <= 0.0:
		_end(false)
		return
	var steps := 0
	while steps < 8:
		var next_row := row + 1
		if next_row >= Game.total_rows:
			_end(true)
			return
		var bi := Game.biome_index(next_row)
		var b: Dictionary = Game.biomes[bi]
		blocked = Game.levels["drill"] < int(b["min_drill"])
		if blocked:
			return
		var next_col := col + signi(target_col - col)
		var t := cell(next_col, next_row)
		var hardness := float(b["hardness"]) * (2.0 if t == HARD else 1.0) / Game.dig_power()
		progress += delta / hardness
		delta = 0.0
		if progress < 1.0:
			return
		progress -= 1.0
		delta = progress * hardness
		progress = 0.0
		row = next_row
		col = next_col
		_dug[Vector2i(col, row)] = true
		var value := float(b["ore_value"] if t == ORE else b["rock_value"]) * Game.ore_mult()
		earned += value
		if t == ORE:
			_popup(_cell_center(col, row) + Vector2(30, -20), "+" + Game.fmt(value), ORE_COL[bi % ORE_COL.size()])
			_shake = maxf(_shake, 4.0)
		if row > Game.best_row:
			Game.best_row = row
		if bi > Game.deepest_biome:
			Game.deepest_biome = bi
			Game.pending_midgame = true
			_popup(_cell_center(COLS / 2, row) + Vector2(-140, -60), String(b["name"]).to_upper(), Color.WHITE)
			_shake = 10.0
			biome_entered.emit(bi)
		steps += 1
		if delta <= 0.0:
			return


func _end(breakthrough: bool) -> void:
	running = false
	print("RUN_END earned=%.1f row=%d rows_dug=%d breakthrough=%s" % [earned, row, row - start_row, breakthrough])
	run_ended.emit(earned, row, breakthrough)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_steer_to_mouse()
	elif event is InputEventMouseMotion and event.button_mask != 0:
		_steer_to_mouse()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_LEFT, KEY_A]:
			target_col = clampi(col - 1, 0, COLS - 1)
		elif event.keycode in [KEY_RIGHT, KEY_D]:
			target_col = clampi(col + 1, 0, COLS - 1)
		elif event.keycode in [KEY_DOWN, KEY_S]:
			target_col = col


func _steer_to_mouse() -> void:
	target_col = clampi(int(floor(get_global_mouse_position().x / TILE)), 0, COLS - 1)


func _cell_center(c: int, r: int) -> Vector2:
	return Vector2((c + 0.5) * TILE, (r + 0.5) * TILE)


func _popup(pos: Vector2, text: String, color: Color) -> void:
	_popups.append({"pos": pos, "text": text, "color": color, "t": 0.0})


func _update_camera(delta: float) -> void:
	var vis := get_viewport_rect().size
	var z := minf(vis.x / (COLS * TILE + 96.0), vis.y / (8.5 * TILE))
	z = maxf(z, 0.5)
	_cam.zoom = Vector2(z, z)
	var view_h := vis.y / z
	_cam.position = Vector2(COLS * TILE * 0.5, _drill_pos.y + view_h * 0.18)
	_shake = maxf(_shake - delta * 30.0, 0.0)
	_cam.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake


func _draw() -> void:
	var vis := get_viewport_rect().size / _cam.zoom
	var top := int(floor((_cam.position.y - vis.y * 0.5) / TILE)) - 1
	var bottom := int(ceil((_cam.position.y + vis.y * 0.5) / TILE)) + 1
	var left := -int(ceil((vis.x * 0.5 - COLS * TILE * 0.5) / TILE)) - 1
	# side walls (outside the shaft) drawn dark
	draw_rect(Rect2(left * TILE, top * TILE, -left * TILE, (bottom - top) * TILE), Color("0b0820"))
	draw_rect(Rect2(COLS * TILE, top * TILE, -left * TILE, (bottom - top) * TILE), Color("0b0820"))
	for r in range(top, bottom):
		var bi := Game.biome_index(maxi(r, 0))
		var rock: Color = ROCK_COL[bi % ROCK_COL.size()]
		var ore: Color = ORE_COL[bi % ORE_COL.size()]
		if r >= 0 and r == int(Game.biome_start_rows[bi]) and bi > 0:
			draw_rect(Rect2(0, r * TILE - 3, COLS * TILE, 6), Color(1, 1, 1, 0.5))
		for c in range(COLS):
			var t := cell(c, r)
			var rect := Rect2(c * TILE, r * TILE, TILE, TILE)
			if t == EMPTY or r < 0:
				draw_rect(rect, rock.darkened(0.75))
				continue
			var base := rock.darkened(0.25) if t == HARD else rock
			draw_rect(rect.grow(-2), base)
			draw_rect(Rect2(rect.position + Vector2(2, 2), Vector2(TILE - 4, 5)), base.lightened(0.25))
			if t == HARD:
				draw_rect(rect.grow(-14), base.darkened(0.3))
			elif t == ORE:
				draw_rect(rect.grow(-18), ore)
	# drill
	var p := _drill_pos
	draw_rect(Rect2(p + Vector2(-20, -30), Vector2(40, 40)), Color("ff9f43"))
	draw_rect(Rect2(p + Vector2(-12, -24), Vector2(24, 12)), Color("1b2c48"))
	draw_colored_polygon(PackedVector2Array([p + Vector2(-18, 10), p + Vector2(18, 10), p + Vector2(0, 34)]), Color("d8e2ea"))
	if blocked:
		draw_string(_font, p + Vector2(-90, 70), "TOO HARD - UPGRADE DRILL", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.RED)
	for pp in _popups:
		var a := 1.0 - float(pp["t"]) / 0.9
		var col_a: Color = pp["color"]
		col_a.a = a
		draw_string_outline(_font, pp["pos"], pp["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 30, 6, Color(0, 0, 0, a))
		draw_string(_font, pp["pos"], pp["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 30, col_a)
