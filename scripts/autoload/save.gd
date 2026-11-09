extends Node
## Persists progress to user:// (IndexedDB on the web). Versioned so later fields can be migrated.
## Saves every 10 s, after runs and purchases. Open the game with ?reset to wipe progress.

const PATH := "user://save.json"
const VERSION := 1
const INTERVAL_S := 10.0

var enabled := true
var _timer := 0.0


func _ready() -> void:
	enabled = not ("--autoplay" in OS.get_cmdline_user_args())
	if not enabled:
		return
	var query := ""
	if OS.has_feature("web"):
		query = str(JavaScriptBridge.eval("location.search"))
	if query.contains("reset"):
		wipe()
	var m := RegEx.create_from_string("biome=(\\d)").search(query)
	if m:
		_preview(int(m.get_string(1)))
		return
	load_game()
	Game.levels_changed.connect(save_game)


func _process(delta: float) -> void:
	if not enabled:
		return
	_timer += delta / maxf(Engine.time_scale, 0.001)
	if _timer >= INTERVAL_S:
		_timer = 0.0
		save_game()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT]:
		save_game()


func save_game() -> void:
	if not enabled:
		return
	var data := {
		"version": VERSION,
		"coins": Game.coins,
		"levels": Game.levels,
		"deepest_biome": Game.deepest_biome,
		"best_row": Game.best_row,
		"muted": Music.muted,
		"shards": Game.shards,
		"reforges": Game.reforges,
		"broke_through": Game.broke_through,
		"overclock_until": Game.overclock_until,
		"play_time": Game.play_time,
		"saved_at": Time.get_unix_time_from_system(),
	}
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_warning("save failed: %s" % FileAccess.get_open_error())
		return
	f.store_string(JSON.stringify(data))


func load_game() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	if not (data is Dictionary):
		push_warning("save unreadable, starting fresh")
		return
	data = _migrate(data)
	Game.coins = float(data.get("coins", 0.0))
	var lv: Dictionary = data.get("levels", {})
	for k in Game.levels:
		Game.levels[k] = int(lv.get(k, 0))
	Game.deepest_biome = clampi(int(data.get("deepest_biome", 0)), 0, Game.biomes.size() - 1)
	Game.best_row = int(data.get("best_row", 0))
	Game.shards = int(data.get("shards", 0))
	Game.reforges = int(data.get("reforges", 0))
	Game.broke_through = bool(data.get("broke_through", false))
	Game.overclock_until = float(data.get("overclock_until", 0.0))
	Game.play_time = float(data.get("play_time", 0.0))
	var saved_at := float(data.get("saved_at", 0.0))
	if saved_at > 0.0:
		Game.offline_seconds = maxf(Time.get_unix_time_from_system() - saved_at, 0.0)
	Music.set_muted.call_deferred(bool(data.get("muted", false)))
	print("SAVE loaded coins=%.0f deepest=%d" % [Game.coins, Game.deepest_biome])


## ?biome=N preview: jump into biome N with fitting upgrades. Never touches the real save.
func _preview(bi: int) -> void:
	enabled = false
	bi = clampi(bi, 0, Game.biomes.size() - 1)
	Game.deepest_biome = bi
	Game.best_row = int(Game.biome_start_rows[bi])
	var hardness := float(Game.biomes[bi]["hardness"])
	Game.levels["drill"] = maxi(int(ceil(log(hardness / 0.25) / log(1.1))), 0)
	Game.levels["fuel"] = 10
	Game.levels["magnet"] = mini(bi / 2, 4)
	Game.coins = 1000.0 * pow(2.0, bi)
	print("SAVE preview biome=%d drill=%d" % [bi, Game.levels["drill"]])


func wipe() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	print("SAVE wiped")


func _migrate(data: Dictionary) -> Dictionary:
	# version 1 is current; future versions add steps here
	return data
