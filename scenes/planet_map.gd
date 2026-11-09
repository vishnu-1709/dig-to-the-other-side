extends Control
## Planet cross-section for the hub: crust-to-core rings on the top half, the far-side
## layers on the bottom half, and the drill's tunnel from the surface to the record depth.

const PLANET_KM := 12742.0
const RADIUS_KM := 6371.0


func _ready() -> void:
	custom_minimum_size = Vector2(240, 240)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var R := minf(size.x, size.y) * 0.5 - 8.0
	# space glow behind the planet
	draw_circle(c, R + 6.0, Color(0.5, 0.4, 1.0, 0.12))
	# top half: biomes 0..5 from crust inward; bottom half: 7 (outer) then 6 (inner)
	for i in range(5, -1, -1):
		var b: Dictionary = Game.biomes[i]
		var r_out := R * (1.0 - float(b["start_km"]) / RADIUS_KM)
		_half_disc(c, r_out, PI, TAU, Shaft.ROCK_COL[i])
	for i in [7, 6]:
		var b: Dictionary = Game.biomes[i]
		var r_out := R * ((float(b["end_km"]) - RADIUS_KM) / RADIUS_KM)
		_half_disc(c, r_out, 0.0, PI, Shaft.ROCK_COL[i])
	draw_circle(c, R * 0.12, Shaft.ORE_COL[5])  # glowing core
	draw_arc(c, R, 0, TAU, 64, Color(1, 1, 1, 0.35), 2.0, true)
	# tunnel to the record depth
	var km := Game.depth_km(Game.best_row) if Game.best_row > 0 else 0.0
	var y := c.y - R + 2.0 * R * clampf(km / PLANET_KM, 0.0, 1.0)
	draw_line(Vector2(c.x, c.y - R - 10.0), Vector2(c.x, y), Color(0.05, 0.03, 0.12), 6.0)
	draw_line(Vector2(c.x, c.y - R - 10.0), Vector2(c.x, y), Color("ffd166"), 2.0)
	var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 250.0)
	draw_circle(Vector2(c.x, y), 8.0, Color(1.0, 0.82, 0.4, pulse))
	draw_circle(Vector2(c.x, y), 4.0, Color.WHITE)
	var font := get_theme_default_font()
	var label := "%s / 12,742 km" % Game.fmt(km)
	draw_string_outline(font, Vector2(0, size.y - 2), label, HORIZONTAL_ALIGNMENT_CENTER, size.x, 18, 6, Color(0.05, 0.03, 0.12))
	draw_string(font, Vector2(0, size.y - 2), label, HORIZONTAL_ALIGNMENT_CENTER, size.x, 18, Color.WHITE)


func _half_disc(c: Vector2, r: float, a0: float, a1: float, col: Color) -> void:
	if r <= 0.5:
		return
	var pts := PackedVector2Array([c])
	var n := 32
	for k in range(n + 1):
		var a := lerpf(a0, a1, float(k) / n)
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(pts, col)
	draw_polyline(pts.slice(1), col.lightened(0.25), 1.5, true)
