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
	var R := minf(size.x, size.y) * 0.5 - 14.0
	draw_circle(c, R + 8.0, Color(0.5, 0.4, 1.0, 0.12))
	# rings are equal-width per biome (real km would make the first biomes invisible)
	for i in range(6):
		_half_disc(c, R * (1.0 - i / 6.0), PI, TAU, Shaft.ROCK_COL[i])
	_half_disc(c, R, 0.0, PI, Shaft.ROCK_COL[7])
	_half_disc(c, R * 0.5, 0.0, PI, Shaft.ROCK_COL[6])
	draw_circle(c, R * 0.1, Shaft.ORE_COL[5])
	draw_arc(c, R, 0, TAU, 64, Color(1, 1, 1, 0.35), 2.0, true)
	var y := c.y + _depth_offset(Game.best_row, R)
	draw_line(Vector2(c.x, c.y - R - 8.0), Vector2(c.x, y), Color(0.05, 0.03, 0.12), 6.0)
	draw_line(Vector2(c.x, c.y - R - 8.0), Vector2(c.x, y), Color("ffd166"), 2.0)
	var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 250.0)
	draw_circle(Vector2(c.x, y), 8.0, Color(1.0, 0.82, 0.4, pulse))
	draw_circle(Vector2(c.x, y), 4.0, Color.WHITE)
	var km := Game.depth_km(Game.best_row) if Game.best_row > 0 else 0.0
	var font := get_theme_default_font()
	var label := "%s / 12,742 km" % Game.fmt(km)
	draw_string_outline(font, Vector2(0, size.y), label, HORIZONTAL_ALIGNMENT_CENTER, size.x, 18, 6, Color(0.05, 0.03, 0.12))
	draw_string(font, Vector2(0, size.y), label, HORIZONTAL_ALIGNMENT_CENTER, size.x, 18, Color.WHITE)


## Vertical offset from the planet centre for a row, matching the equal-width rings.
func _depth_offset(row: int, R: float) -> float:
	var bi := Game.biome_index(row)
	var start := int(Game.biome_start_rows[bi])
	var t := clampf(float(row - start) / float(Game.biomes[bi]["rows"]), 0.0, 1.0)
	if bi <= 5:
		return -R + (bi + t) * R / 6.0
	if bi == 6:
		return t * R * 0.5
	return R * 0.5 + t * R * 0.5


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
