extends Node
## Single source of truth: coins, upgrade levels, depth progress. All numbers come from data/*.json.

signal coins_changed
signal levels_changed

const UPGRADE_KEYS := ["fuel", "drill", "ore"]

var upgrades: Dictionary = {}
var biomes: Array = []
var config: Dictionary = {}
var biome_start_rows: Array = []
var total_rows := 0

var coins := 0.0
var levels := {"fuel": 0, "drill": 0, "ore": 0}
var deepest_biome := 0
var best_row := 0
var pending_midgame := false


func _ready() -> void:
	load_data()


func load_data() -> void:
	upgrades = _read_json("res://data/upgrades.json")
	var b := _read_json("res://data/biomes.json")
	biomes = b.get("biomes", [])
	config = b.get("config", {})
	biome_start_rows.clear()
	total_rows = 0
	for bi in biomes:
		biome_start_rows.append(total_rows)
		total_rows += int(bi["rows"])


# ---------- upgrades ----------
func cost(key: String) -> float:
	var u: Dictionary = upgrades[key]
	return float(u["base_cost"]) * pow(float(u["growth"]), levels[key])


func is_maxed(key: String) -> bool:
	return levels[key] >= int(upgrades[key]["max"])


func can_buy(key: String) -> bool:
	return not is_maxed(key) and coins >= cost(key)


func buy(key: String) -> bool:
	if not can_buy(key):
		return false
	coins -= cost(key)
	levels[key] += 1
	print("BUY %s -> %d" % [key, levels[key]])
	levels_changed.emit()
	coins_changed.emit()
	return true


func mult(key: String) -> float:
	return pow(float(upgrades[key]["effect"]), levels[key])


func fuel_seconds() -> float:
	return float(config["base_fuel_s"]) * mult("fuel")


func dig_power() -> float:
	return mult("drill")


func ore_mult() -> float:
	return mult("ore")


func add_coins(v: float) -> void:
	coins += v
	coins_changed.emit()


# ---------- depth ----------
func biome_index(row: int) -> int:
	for i in range(biomes.size() - 1, -1, -1):
		if row >= int(biome_start_rows[i]):
			return i
	return 0


func checkpoint_row() -> int:
	return int(biome_start_rows[deepest_biome])


func depth_km(row: int) -> float:
	var i := biome_index(row)
	var b: Dictionary = biomes[i]
	var t := clampf(float(row - int(biome_start_rows[i])) / float(b["rows"]), 0.0, 1.0)
	return lerpf(float(b["start_km"]), float(b["end_km"]), t)


static func fmt(v: float) -> String:
	if v >= 1e9:
		return "%.2fB" % (v / 1e9)
	if v >= 1e6:
		return "%.2fM" % (v / 1e6)
	if v >= 1e4:
		return "%.1fK" % (v / 1e3)
	return str(int(floor(v)))


func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("missing " + path)
		return {}
	var data = JSON.parse_string(f.get_as_text())
	return data if data is Dictionary else {}
