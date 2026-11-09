extends SceneTree
## Unit checks for game math. Run: godot --headless --script res://tests/test_game.gd

var _fails := 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_fails += 1
		printerr("FAIL: " + msg)


func _initialize() -> void:
	var g = load("res://scripts/autoload/game.gd").new()
	g.load_data()
	g.reset_levels()
	_check(g.biomes.size() == 8, "8 biomes loaded")
	_check(g.total_rows > 0, "total rows > 0")
	_check(is_equal_approx(g.cost("fuel"), 10.0), "fuel base cost 10")
	g.coins = 1000.0
	_check(g.buy("fuel"), "can buy fuel")
	_check(g.levels["fuel"] == 1, "fuel level 1")
	_check(is_equal_approx(g.cost("fuel"), 12.2), "fuel cost grows x1.22")
	_check(is_equal_approx(g.fuel_seconds(), 15.0 * 1.12), "fuel seconds x1.12")
	_check(g.biome_index(0) == 0, "row 0 in biome 0")
	_check(g.biome_index(g.biome_start_rows[3]) == 3, "biome 3 start row")
	_check(is_equal_approx(g.depth_km(g.biome_start_rows[1]), 30.0), "fossil starts at 30 km")
	_check(g.depth_km(g.total_rows - 1) > 12000.0, "last row near 12,742 km")
	g.coins = 0.0
	_check(not g.buy("drill"), "cannot buy without coins")
	_check(g.magnet_radius() == 0, "magnet starts at 0")
	g.levels["magnet"] = 2
	_check(g.magnet_radius() == 2, "magnet additive")
	g.levels["shield"] = 2
	_check(is_equal_approx(g.hazard_fuel_cost(), 2.0 * 0.85 * 0.85), "shield reduces hazard cost")
	_check(g.miner_rate() == 0.0, "no miners -> no rate")
	g.levels["miners"] = 4
	_check(g.miner_rate() > 0.0, "miners earn")
	g.offline_seconds = 10.0 * 3600.0
	var capped: float = g.offline_earnings()
	g.offline_seconds = 4.0 * 3600.0
	_check(is_equal_approx(capped, g.offline_earnings()), "offline capped at 4h")
	_check(not g.can_reforge(), "no reforge before the Core")
	g.deepest_biome = 6
	g.broke_through = true
	var gain: int = g.reforge()
	_check(gain == 2 * 3 + 10, "reforge gain = 16")
	_check(g.shards == 16 and g.deepest_biome == 0 and g.levels["drill"] == 0, "reforge resets")
	_check(is_equal_approx(g.coin_mult(), 1.0 + 0.05 * 16), "shards boost coins")
	g.free()
	print("TEST_OK" if _fails == 0 else "TEST_FAILED %d" % _fails)
	quit(0 if _fails == 0 else 1)
