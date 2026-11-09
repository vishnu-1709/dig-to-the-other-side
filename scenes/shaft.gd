class_name Shaft
extends Node2D
## One dig run. Blocks are computed from a hash of (col, row) — only dug cells are stored,
## and only on-screen rows are drawn. Drill steps one row at a time, shifting at most one
## column per row toward the steering target.

signal run_ended(earned: float, end_row: int, breakthrough: bool)
signal biome_entered(index: int)
signal block_dug(pos: Vector2, kind: int, biome: int)
signal ore_pulled(from: Vector2, biome: int)

const TILE := 64
const COLS := 9
const EMPTY := -1
const ROCK := 0
const ORE := 1
const HARD := 2
const HAZARD := 3

const ROCK_COL := [Color("7a5534"), Color("a08a6a"), Color("6d6a5a"), Color("3c2f6e"),
	Color("4a1f1a"), Color("6b2a10"), Color("2a3a5a"), Color("2f5a3a")]
const ORE_COL := [Color("e08a3c"), Color("ffb52e"), Color("ffd700"), Color("7ff3ff"),
	Color("b04cff"), Color("ff5a1f"), Color("c0e0ff"), Color("9dff6a")]
const HAZARD_COL := Color("ff3b5c")

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
var refueled := false

var _seed := 0
var _dug := {}
var _drill_pos := Vector2.ZERO
var _popups: Array = []
var _shake := 0.0
var _cam: Camera2D
var _font: Font
var _ore_p := 0.12
var _tiles: Array = []
var _bgs: Array = []
var _drill_tex: Texture2D
var _fx: Node2D
var _time := 0.0
var _tilt := 0.0
var _hard_p := 0.08


func _ready() -> void:
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_cam = Camera2D.new()
	add_child(_cam)
	_cam.make_current()
	_font = load("res://assets/fonts/Fredoka-SemiBold.woff2")
	if _font == null:
		_font = ThemeDB.fallback_font
	for i in range(8):
		_tiles.append(load("res://assets/art/tiles_%d.png" % i))
		_bgs.append(load("res://assets/art/bg_%d.png" % i))
	_drill_tex = load("res://assets/art/drill.png")
	_fx = preload("res://scenes/fx.gd").new()
	_fx.shaft = self
	add_child(_fx)
	block_dug.connect(_fx.on_block_dug)
	ore_pulled.connect(_fx.on_ore_pulled)
	_ore_p = float(Game.config.get("ore_p", 0.12))
	_hard_p = float(Game.config.get("hard_p", 0.08))
	prepare()


## Place the drill at the checkpoint without starting (hub background).
func prepare() -> void:
	running = false
	refueled = false
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


## Continue the same run after a rewarded refuel.
func resume(extra_fuel: float) -> void:
	refueled = true
	fuel = extra_fuel
	fuel_max = maxf(fuel_max, extra_fuel)
	running = true
	print("RUN_RESUME +%.0fs" % extra_fuel)


func biome_at(r: int) -> Dictionary:
	return Game.biomes[Game.biome_index(maxi(r, 0))]


func cell(c: int, r: int) -> int:
	if c < 0 or c >= COLS:
		return HARD
	if r < start_row or _dug.has(Vector2i(c, r)):
		return EMPTY
	var v := _rand01(c, r)
	if v < _ore_p:
		return ORE
	v -= _ore_p
	if v < _hard_p:
		return HARD
	v -= _hard_p
	if v < float(biome_at(r)["hazard_p"]):
		return HAZARD
	return ROCK


func _rand01(c: int, r: int) -> float:
	var x: int = (c * 73856093) ^ (r * 19349663) ^ _seed
	x = (x ^ (x >> 13)) * 1274126177
	x = x ^ (x >> 16)
	return float(absi(x) % 100000) / 100000.0


## Steering choice for the autoplay bot: dodge hazards, head for reachable ore.
func bot_target_col() -> int:
	var best := col
	for dr in range(1, 5):
		var found := -1
		for c in range(COLS):
			if cell(c, row + dr) == ORE and absi(c - col) <= dr:
				if found == -1 or absi(c - col) < absi(found - col):
					found = c
		if found != -1:
			best = found
			break
	var next := col + signi(best - col)
	if cell(next, row + 1) == HAZARD:
		for alt in [col, col - 1, col + 1]:
			if alt >= 0 and alt < COLS and cell(alt, row + 1) != HAZARD:
				return alt
	return best


func _process(delta: float) -> void:
	_time += delta
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
	fuel -= delta * float(biome_at(row + 1).get("fuel_drain", 1.0))
	if fuel <= 0.0:
		fuel = 0.0
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
		delta = (progress - 1.0) * hardness
		progress = 0.0
		row = next_row
		col = next_col
		_dig_cell(col, row, t, bi, b)
		_magnet(bi, b)
		if row > Game.best_row:
			Game.best_row = row
		if bi > Game.deepest_biome:
			Game.deepest_biome = bi
			Game.pending_midgame = true
			_shake = 10.0
			Music.set_biome(bi)
			biome_entered.emit(bi)
		if fuel <= 0.0:
			fuel = 0.0
			_end(false)
			return
		steps += 1
		if delta <= 0.0:
			return


func _dig_cell(c: int, r: int, t: int, bi: int, b: Dictionary, pulled := false) -> void:
	_dug[Vector2i(c, r)] = true
	var pos := _cell_center(c, r)
	if t == HAZARD:
		var cost := Game.hazard_fuel_cost()
		fuel -= cost
		_popup(pos + Vector2(26, -10), "-%.1fs FUEL" % cost, HAZARD_COL)
		_shake = maxf(_shake, 12.0)
		Music.sfx("fuel_out", -12.0, 1.8)
	else:
		var value := float(b["ore_value"] if t == ORE else b["rock_value"]) * Game.coin_mult()
		earned += value
		if t == ORE:
			Music.ore()
			var at := _drill_pos + Vector2(30, -40) if pulled else pos + Vector2(30, -20)
			_popup(at, "+" + Game.fmt(value), ORE_COL[bi % ORE_COL.size()])
			_shake = maxf(_shake, 4.0)
	if pulled:
		Music.sfx("magnet", -10.0)
		ore_pulled.emit(pos, bi)
	else:
		block_dug.emit(pos, t, bi)


func _magnet(bi: int, b: Dictionary) -> void:
	var radius := Game.magnet_radius()
	for d in range(1, radius + 1):
		for c in [col - d, col + d]:
			if c >= 0 and c < COLS and cell(c, row) == ORE:
				_dig_cell(c, row, ORE, bi, b, true)


func _end(breakthrough: bool) -> void:
	running = false
	if breakthrough:
		Game.broke_through = true
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


const ATLAS := 96.0
const IDX_HARD := 3
const IDX_HAZARD := 4
const IDX_ORE := 5
const IDX_WALL := 6


func tile_atlas(bi: int) -> Texture2D:
	return _tiles[bi]


func drill_pos() -> Vector2:
	return _drill_pos


func view_rows() -> Vector2i:
	var vis := get_viewport_rect().size / _cam.zoom
	var top := int(floor((_cam.position.y - vis.y * 0.5) / TILE)) - 1
	var bottom := int(ceil((_cam.position.y + vis.y * 0.5) / TILE)) + 1
	return Vector2i(top, bottom)


func _draw() -> void:
	var vis := get_viewport_rect().size / _cam.zoom
	var rows := view_rows()
	var x0 := _cam.position.x - vis.x * 0.5 - TILE
	var w := vis.x + TILE * 2
	# parallax background strips, per row so biome changes line up with the blocks
	for r in range(rows.x, rows.y):
		var bi := Game.biome_index(maxi(r, 0))
		var rect := Rect2(x0, r * TILE, w, TILE)
		var region := Rect2(rect.position.x * 0.5, rect.position.y * 0.5, rect.size.x * 0.5, rect.size.y * 0.5)
		draw_texture_rect_region(_bgs[bi], rect, region)
	# darken outside the shaft so the play area pops
	var side := Color(0, 0, 0, 0.45)
	draw_rect(Rect2(x0, rows.x * TILE, -x0, (rows.y - rows.x) * TILE), side)
	draw_rect(Rect2(COLS * TILE, rows.x * TILE, w, (rows.y - rows.x) * TILE), side)
	for r in range(rows.x, rows.y):
		var bi := Game.biome_index(maxi(r, 0))
		var atlas: Texture2D = _tiles[bi]
		var rim: Color = ORE_COL[bi]
		rim.a = 0.35
		for c in range(COLS):
			var t := cell(c, r)
			var rect := Rect2(c * TILE, r * TILE, TILE, TILE)
			if t == EMPTY:
				draw_texture_rect_region(atlas, rect, Rect2(IDX_WALL * ATLAS, 0, ATLAS, ATLAS), Color(1, 1, 1, 0.85))
				continue
			var idx := posmod(int(_rand01(c + 17, r) * 1000.0), 3)
			match t:
				HARD: idx = IDX_HARD
				HAZARD: idx = IDX_HAZARD
				ORE: idx = IDX_ORE
			draw_texture_rect_region(atlas, rect, Rect2(idx * ATLAS, 0, ATLAS, ATLAS))
			# glowing rim where rock meets the tunnel
			if cell(c - 1, r) == EMPTY:
				draw_line(rect.position + Vector2(2, 8), rect.position + Vector2(2, TILE - 8), rim, 3.0)
			if cell(c + 1, r) == EMPTY:
				draw_line(rect.position + Vector2(TILE - 2, 8), rect.position + Vector2(TILE - 2, TILE - 8), rim, 3.0)
			if cell(c, r - 1) == EMPTY:
				draw_line(rect.position + Vector2(8, 2), rect.position + Vector2(TILE - 8, 2), rim, 3.0)
		# biome border banner painted into the rock
		if r > 0 and r == int(Game.biome_start_rows[bi]):
			var lc: Color = ORE_COL[bi]
			draw_rect(Rect2(0, r * TILE - 3, COLS * TILE, 6), lc)
			var name := String(Game.biomes[bi]["name"]).to_upper()
			draw_string_outline(_font, Vector2(0, r * TILE - 12), name, HORIZONTAL_ALIGNMENT_CENTER, COLS * TILE, 34, 10, Color(0, 0, 0, 0.8))
			draw_string(_font, Vector2(0, r * TILE - 12), name, HORIZONTAL_ALIGNMENT_CENTER, COLS * TILE, 34, lc)
	# shaft frame
	draw_line(Vector2(0, rows.x * TILE), Vector2(0, rows.y * TILE), Color(0, 0, 0, 0.6), 6.0)
	draw_line(Vector2(COLS * TILE, rows.x * TILE), Vector2(COLS * TILE, rows.y * TILE), Color(0, 0, 0, 0.6), 6.0)
	_draw_drill()
	if blocked:
		var p := _drill_pos
		draw_string_outline(_font, p + Vector2(-160, 80), "TOO HARD - UPGRADE DRILL", HORIZONTAL_ALIGNMENT_CENTER, 320, 24, 8, Color.BLACK)
		draw_string(_font, p + Vector2(-160, 80), "TOO HARD - UPGRADE DRILL", HORIZONTAL_ALIGNMENT_CENTER, 320, 24, Color("ff5c5c"))
	for pp in _popups:
		var a := 1.0 - float(pp["t"]) / 0.9
		var col_a: Color = pp["color"]
		col_a.a = a
		var size := 34 if String(pp["text"]).length() > 8 else 30
		draw_string_outline(_font, pp["pos"], pp["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, size, 8, Color(0.05, 0.03, 0.12, a))
		draw_string(_font, pp["pos"], pp["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, size, col_a)


func _draw_drill() -> void:
	var next_col := col + signi(target_col - col)
	var want_tilt := 0.0
	if running:
		want_tilt = -0.28 * signf(next_col - col)
	_tilt = lerpf(_tilt, want_tilt, 0.2)
	var bob := sin(_time * 18.0) * (1.5 if running else 0.6)
	draw_set_transform(_drill_pos + Vector2(0, bob), _tilt, Vector2(0.5, 0.5))
	# bit (frames 1-4), spinning while digging
	var frame := 1 + (int(_time * 24.0) % 4 if running else 0)
	draw_texture_rect_region(_drill_tex, Rect2(-48, 30, 96, 128), Rect2(frame * 96, 0, 96, 128))
	# body (frame 0)
	draw_texture_rect_region(_drill_tex, Rect2(-48, -84, 96, 128), Rect2(0, 0, 96, 128))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
