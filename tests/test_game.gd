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
	_check(g.biomes.size() == 8, "8 biomes loaded")
	_check(g.total_rows > 0, "total rows > 0")
	_check(is_equal_approx(g.cost("fuel"), 10.0), "fuel base cost 10")
	g.coins = 1000.0
	_check(g.buy("fuel"), "can buy fuel")
	_check(g.levels["fuel"] == 1, "fuel level 1")
	_check(is_equal_approx(g.cost("fuel"), 11.5), "fuel cost grows x1.15")
	_check(is_equal_approx(g.fuel_seconds(), 15.0 * 1.12), "fuel seconds x1.12")
	_check(g.biome_index(0) == 0, "row 0 in biome 0")
	_check(g.biome_index(g.biome_start_rows[3]) == 3, "biome 3 start row")
	_check(is_equal_approx(g.depth_km(g.biome_start_rows[1]), 30.0), "fossil starts at 30 km")
	_check(g.depth_km(g.total_rows - 1) > 12000.0, "last row near 12,742 km")
	g.coins = 0.0
	_check(not g.buy("drill"), "cannot buy without coins")
	g.free()
	print("TEST_OK" if _fails == 0 else "TEST_FAILED %d" % _fails)
	quit(0 if _fails == 0 else 1)
