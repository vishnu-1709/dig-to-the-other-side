extends Node2D
## Milestone 1 pipeline proof: shows a screen, reads tuning data, reports FPS.

var _label: Label
var _frames := 0
var _elapsed := 0.0


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("1a1240")
	bg.size = Vector2(4000, 4000)
	bg.position = Vector2(-2000, -2000)
	add_child(bg)

	_label = Label.new()
	_label.position = Vector2(40, 40)
	_label.add_theme_font_size_override("font_size", 32)
	add_child(_label)

	var biomes := _load_json("res://data/biomes.json")
	var count: int = biomes.get("biomes", []).size()
	_label.text = "Dig to the Other Side\npipeline OK - %d biomes loaded" % count
	print("BOOT_OK biomes=%d" % count)


func _process(delta: float) -> void:
	_frames += 1
	_elapsed += delta
	if _elapsed >= 2.0:
		var fps := _frames / _elapsed
		print("FPS %.1f" % fps)
		_label.text = _label.text.get_slice("\nFPS", 0) + "\nFPS %.0f" % fps
		_frames = 0
		_elapsed = 0.0


func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("missing " + path)
		return {}
	var data = JSON.parse_string(f.get_as_text())
	return data if data is Dictionary else {}
