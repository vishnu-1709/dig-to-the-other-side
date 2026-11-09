extends Node
## Single source of truth: coins, upgrade levels, depth progress, prestige.
## All numbers come from data/*.json.

signal coins_changed
signal levels_changed

const UPGRADE_KEYS := ["fuel", "drill", "ore", "magnet", "shield", "miners"]
const SHARD_BONUS := 0.05
const OVERCLOCK_S := 180.0
const REFORGE_MIN_BIOME := 5  # The Core

var upgrades: Dictionary = {}
var biomes: Array = []
var config: Dictionary = {}
var biome_start_rows: Array = []
var total_rows := 0

var coins := 0.0
var levels := {}
var deepest_biome := 0
var best_row := 0
var shards := 0
var reforges := 0
var broke_through := false
var overclock_until := 0.0
var play_time := 0.0
var pending_midgame := false
var offline_seconds := 0.0


func _ready() -> void:
	load_data()
	reset_levels()


func load_data() -> void:
	upgrades = _read_json("res://data/upgrades.json")
	upgrades.erase("_doc")
	var b := _read_json("res://data/biomes.json")
	biomes = b.get("biomes", [])
	config = b.get("config", {})
	biome_start_rows.clear()
	total_rows = 0
	for bi in biomes:
		biome_start_rows.append(total_rows)
		total_rows += int(bi["rows"])


func reset_levels() -> void:
	levels = {}
	for k in UPGRADE_KEYS:
		levels[k] = 0


func _process(delta: float) -> void:
	play_time += delta
	var r := miner_rate()
	if r > 0.0:
		coins += r * delta


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
	var u: Dictionary = upgrades[key]
	if u.get("additive", false):
		return float(u["effect"]) * levels[key]
	return pow(float(u["effect"]), levels[key])


func fuel_seconds() -> float:
	return float(config["base_fuel_s"]) * mult("fuel")


func overclock_left() -> float:
	return maxf(overclock_until - Time.get_unix_time_from_system(), 0.0)


func dig_power() -> float:
	return mult("drill") * (2.0 if overclock_left() > 0.0 else 1.0)


func coin_mult() -> float:
	return mult("ore") * (1.0 + SHARD_BONUS * shards)


func magnet_radius() -> int:
	return int(mult("magnet"))


func hazard_fuel_cost() -> float:
	return float(config["hazard_fuel_s"]) * mult("shield")


## Coins per second from auto-miners while playing.
func miner_rate() -> float:
	if biomes.is_empty() or levels.get("miners", 0) == 0:
		return 0.0
	return mult("miners") * float(config["miner_rate"]) * float(biomes[deepest_biome]["ore_value"]) * coin_mult()


func offline_earnings() -> float:
	var s := minf(offline_seconds, float(config["offline_cap_h"]) * 3600.0)
	return miner_rate() * float(config["offline_rate"]) * s


func add_coins(v: float) -> void:
	coins += v
	coins_changed.emit()


func start_overclock() -> void:
	overclock_until = Time.get_unix_time_from_system() + OVERCLOCK_S


# ---------- prestige ----------
func can_reforge() -> bool:
	return deepest_biome >= REFORGE_MIN_BIOME or broke_through


func reforge_gain() -> int:
	return maxi(deepest_biome - REFORGE_MIN_BIOME + 1, 0) * 3 + (10 if broke_through else 0)


func reforge() -> int:
	var gain := reforge_gain()
	shards += gain
	reforges += 1
	coins = 0.0
	reset_levels()
	deepest_biome = 0
	best_row = 0
	broke_through = false
	print("REFORGE +%d shards (total %d)" % [gain, shards])
	levels_changed.emit()
	coins_changed.emit()
	return gain


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


static func fmt_time(s: float) -> String:
	var m := int(s) / 60
	if m >= 60:
		return "%dh %dm" % [m / 60, m % 60]
	if m > 0:
		return "%dm %ds" % [m, int(s) % 60]
	return "%ds" % int(s)


func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("missing " + path)
		return {}
	var data = JSON.parse_string(f.get_as_text())
	return data if data is Dictionary else {}
