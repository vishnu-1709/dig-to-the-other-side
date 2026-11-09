extends Node2D
## Visual effects for the shaft: additive glow (ores, hazards, headlight) and particles
## (debris chunks per dug block, sparks at the drill bit). Purely cosmetic.

const POOL := 8

var shaft: Node2D

var _glow_tex: Texture2D
var _light_tex: Texture2D
var _debris: Array = []
var _next := 0
var _sparks: CPUParticles2D
var _glow_layer: Node2D
var _low_end := false
var _flyers: Array = []  # ore pulled by the magnet: {from, t, bi}

const FLY_TIME := 0.28


func _ready() -> void:
	_glow_tex = load("res://assets/art/glow.png")
	_light_tex = load("res://assets/art/headlight.png")
	_low_end = OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
	_glow_layer = Node2D.new()
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow_layer.material = mat
	_glow_layer.draw.connect(_draw_glow)
	add_child(_glow_layer)
	var chunk: Texture2D = load("res://assets/art/chunk.png")
	for i in range(POOL):
		var p := CPUParticles2D.new()
		p.texture = chunk
		p.emitting = false
		p.one_shot = true
		p.explosiveness = 1.0
		p.amount = 6 if _low_end else 10
		p.lifetime = 0.7
		p.direction = Vector2(0, -1)
		p.spread = 75.0
		p.initial_velocity_min = 120.0
		p.initial_velocity_max = 280.0
		p.gravity = Vector2(0, 900)
		p.angular_velocity_min = -360.0
		p.angular_velocity_max = 360.0
		p.scale_amount_min = 0.5
		p.scale_amount_max = 1.1
		var fade := Gradient.new()
		fade.set_color(0, Color(1, 1, 1, 1))
		fade.set_color(1, Color(1, 1, 1, 0))
		p.color_ramp = fade
		add_child(p)
		_debris.append(p)
	_sparks = CPUParticles2D.new()
	_sparks.texture = load("res://assets/art/spark.png")
	_sparks.amount = 14 if _low_end else 26
	_sparks.lifetime = 0.35
	_sparks.direction = Vector2(0, -1)
	_sparks.spread = 60.0
	_sparks.initial_velocity_min = 90.0
	_sparks.initial_velocity_max = 260.0
	_sparks.gravity = Vector2(0, 700)
	_sparks.scale_amount_min = 0.4
	_sparks.scale_amount_max = 0.9
	var sg := Gradient.new()
	sg.set_color(0, Color("fff3b0"))
	sg.set_color(1, Color(1.0, 0.6, 0.2, 0.0))
	_sparks.color_ramp = sg
	_sparks.material = mat
	_sparks.emitting = false
	add_child(_sparks)


func on_block_dug(pos: Vector2, kind: int, biome: int) -> void:
	var p: CPUParticles2D = _debris[_next]
	_next = (_next + 1) % POOL
	p.position = pos
	match kind:
		1:
			p.color = Shaft.ORE_COL[biome]
		3:
			p.color = Shaft.HAZARD_COL
		_:
			p.color = Shaft.ROCK_COL[biome].lightened(0.15)
	p.restart()


func on_ore_pulled(from: Vector2, biome: int) -> void:
	_flyers.append({"from": from, "t": 0.0, "bi": biome})


func _flyer_pos(f: Dictionary) -> Vector2:
	var t: float = f["t"]
	var e := t * t * (3.0 - 2.0 * t)  # smoothstep
	var target: Vector2 = shaft.drill_pos()
	var mid := (f["from"] as Vector2).lerp(target, 0.5) + Vector2(0, -40)  # small arc
	return (f["from"] as Vector2).lerp(mid, e).lerp(mid.lerp(target, e), e)


func _process(delta: float) -> void:
	for f in _flyers:
		f["t"] = minf(float(f["t"]) + delta / FLY_TIME, 1.0)
		if f["t"] >= 1.0:
			var p: CPUParticles2D = _debris[_next]
			_next = (_next + 1) % POOL
			p.position = shaft.drill_pos()
			p.color = Shaft.ORE_COL[f["bi"]]
			p.restart()
	_flyers = _flyers.filter(func(f): return f["t"] < 1.0)
	queue_redraw()
	_sparks.position = shaft.drill_pos() + Vector2(0, 38)
	_sparks.emitting = shaft.running
	_glow_layer.queue_redraw()


func _draw() -> void:
	# flying ore sprites (normal blend)
	for f in _flyers:
		var p := _flyer_pos(f)
		var s := lerpf(40.0, 22.0, float(f["t"]))
		draw_texture_rect_region(shaft.tile_atlas(f["bi"]), Rect2(p - Vector2(s, s) * 0.5, Vector2(s, s)), Rect2(5 * 96 + 12, 12, 72, 72))


func _draw_glow() -> void:
	# magnet pull radius around the drill
	var radius := Game.magnet_radius()
	if radius > 0 and shaft.running:
		var dp0: Vector2 = shaft.drill_pos()
		var bi0: int = Game.biome_index(shaft.row)
		var mc: Color = Shaft.ORE_COL[bi0]
		var w := (radius + 0.5) * 64.0
		var pul := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 160.0)
		mc.a = 0.06 + 0.04 * pul
		_glow_layer.draw_rect(Rect2(dp0.x - w, dp0.y - 26, w * 2.0, 52), mc)
		mc.a = 0.35 + 0.25 * pul
		_glow_layer.draw_rect(Rect2(dp0.x - w - 2, dp0.y - 26, 4, 52), mc)
		_glow_layer.draw_rect(Rect2(dp0.x + w - 2, dp0.y - 26, 4, 52), mc)
	# trails behind flying ore
	for f in _flyers:
		var fc: Color = Shaft.ORE_COL[f["bi"]]
		for k in range(4):
			var g: Dictionary = (f as Dictionary).duplicate()
			g["t"] = maxf(float(f["t"]) - k * 0.08, 0.0)
			fc.a = 0.45 - k * 0.1
			var gp := _flyer_pos(g)
			_glow_layer.draw_texture_rect(_glow_tex, Rect2(gp - Vector2(28, 28), Vector2(56, 56)), false, fc)
	var t: float = Time.get_ticks_msec() / 1000.0
	var rows: Vector2i = shaft.view_rows()
	var pulse := 0.75 + 0.25 * sin(t * 3.0)
	for r in range(rows.x, rows.y):
		var bi: int = Game.biome_index(maxi(r, 0))
		for c in range(Shaft.COLS):
			var kind: int = shaft.cell(c, r)
			if kind == Shaft.ORE:
				var col: Color = Shaft.ORE_COL[bi]
				col.a = 0.32 * pulse
				_glow_layer.draw_texture_rect(_glow_tex, Rect2(c * 64 - 40, r * 64 - 40, 144, 144), false, col)
			elif kind == Shaft.HAZARD:
				var hc: Color = Shaft.HAZARD_COL
				hc.a = 0.22 * (0.6 + 0.4 * sin(t * 6.0 + c))
				_glow_layer.draw_texture_rect(_glow_tex, Rect2(c * 64 - 24, r * 64 - 24, 112, 112), false, hc)
	# headlight: stronger the deeper (darker) the biome
	var dp: Vector2 = shaft.drill_pos()
	var depth_k := clampf(0.35 + 0.08 * Game.biome_index(shaft.row), 0.35, 0.85)
	_glow_layer.draw_texture_rect(_light_tex, Rect2(dp.x - 128, dp.y + 20, 256, 384), false, Color(1.0, 0.95, 0.8, depth_k))
	_glow_layer.draw_texture_rect(_glow_tex, Rect2(dp.x - 60, dp.y - 70, 120, 120), false, Color(1.0, 0.8, 0.5, 0.25))
