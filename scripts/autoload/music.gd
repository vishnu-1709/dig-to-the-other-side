extends Node
## Procedural music. A 16th-note clock drives drums/bass/pad/lead patterns built from tiny
## samples. Ore notes are queued to the next 16th so drilling always lands on the beat.
## More ore in a short time ("heat") adds layers: drums -> +bass -> +pad -> +lead arpeggio.

const VOICES := 16
## Each sample is pitched relative to the note it was recorded at (inst C4, pad C3, bass C2).
const BPM := [100, 104, 96, 110, 120, 90, 92, 116]
const KEYS := [  # [root semitone vs C, scale intervals]
	[0, [0, 2, 4, 5, 7, 9, 11]],      # Topsoil      C major
	[-5, [0, 2, 4, 5, 7, 9, 11]],     # Fossil Beds  G major
	[2, [0, 2, 3, 5, 7, 9, 10]],      # Lost Ruins   D dorian
	[4, [0, 2, 3, 5, 7, 8, 10]],      # Crystal      E minor
	[-3, [0, 1, 3, 5, 7, 8, 10]],     # Magma        A phrygian
	[2, [0, 3, 5, 7, 10]],            # Core         D minor pentatonic
	[5, [0, 2, 4, 6, 7, 9, 11]],      # Mirror       F lydian
	[0, [0, 2, 4, 6, 8, 10]],         # Alien        whole-tone
]
const PROGRESSION := [0, 5, 3, 4]      # I - vi - IV - V (scale degrees)
const MELODY := [0, 2, 4, 7, 4, 2, 7, 9]

var running := false
var muted := false
var biome := 0
var heat := 0.0

var _s := {}
var _inst: Array = []
var _pool: Array = []
var _next := 0
var _acc := 0.0
var _step := 0
var _bar := 0
var _queued_notes := 0
var _ore_idx := 0
var _enabled := true


func _ready() -> void:
	_enabled = DisplayServer.get_name() != "headless"
	if not _enabled:
		return
	for n in ["kick", "snare", "hat", "bass", "pad", "click", "fuel_out", "biome_enter", "coin", "upgrade", "magnet"]:
		_s[n] = load("res://assets/audio/%s.ogg" % n)
	for i in range(8):
		_inst.append(load("res://assets/audio/inst_%d.ogg" % i))
	for i in range(VOICES):
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	Portal.ad_started.connect(func(): AudioServer.set_bus_mute(0, true))
	Portal.ad_finished.connect(func(): AudioServer.set_bus_mute(0, muted))


func set_muted(m: bool) -> void:
	muted = m
	AudioServer.set_bus_mute(0, m)


# ---------------- game hooks ----------------
func start_run(biome_index: int) -> void:
	biome = biome_index
	running = true
	heat = 0.0
	_ore_idx = 0


func stop_run() -> void:
	running = false
	heat = 0.0
	sfx("fuel_out", -6.0)


func set_biome(i: int) -> void:
	biome = i
	sfx("biome_enter", -4.0)


func ore() -> void:
	heat = minf(heat + 1.0, 8.0)
	_queued_notes += 1


func sfx(name: String, db := 0.0, pitch := 1.0) -> void:
	if _enabled and _s.has(name):
		_play(_s[name], pitch, db)


func layers() -> int:
	return clampi(1 + int(heat / 2.0), 1, 4)


# ---------------- clock ----------------
func _process(delta: float) -> void:
	if not _enabled:
		return
	var real := delta / maxf(Engine.time_scale, 0.001)
	heat = maxf(heat - real * 0.6, 0.0)
	if heat < 0.5:
		_ore_idx = 0
	var step_len := 60.0 / float(BPM[biome]) / 4.0
	_acc += real
	while _acc >= step_len:
		_acc -= step_len
		_tick()


func _tick() -> void:
	var s := _step % 16
	if s == 0:
		_bar += 1
	var chord: int = PROGRESSION[_bar % PROGRESSION.size()]
	if running:
		var L := layers()
		if s in [0, 8] or (L >= 3 and s == 10):
			_play(_s["kick"], 1.0, -4.0)
		if s % 2 == 0:
			_play(_s["hat"], 1.0, -16.0 if s % 4 == 0 else -20.0)
		if L >= 2:
			if s in [4, 12]:
				_play(_s["snare"], 1.0, -10.0)
			if s in [0, 3, 6, 10]:
				_note(_s["bass"], chord, -6.0)
		if L >= 3 and s == 0:
			for d in [0, 2, 4]:
				_note(_s["pad"], chord + d, -16.0)
		if L >= 4 and s % 2 == 1:
			var arp := [0, 2, 4, 7]
			_note(_inst[biome], chord + arp[(s / 2) % 4], -18.0)
		if _queued_notes > 0:
			_queued_notes = 0
			var deg: int = chord + MELODY[_ore_idx % MELODY.size()]
			_ore_idx += 1
			_note(_inst[biome], deg, -3.0)
	else:
		if s == 0 and _bar % 2 == 0:
			for d in [0, 2, 4]:
				_note(_s["pad"], chord + d, -20.0)
	_step += 1


func _note(stream: AudioStream, degree: int, db: float) -> void:
	var key: Array = KEYS[biome]
	var scale: Array = key[1]
	var n := scale.size()
	var octave := int(floor(float(degree) / n))
	var semis: int = int(key[0]) + int(scale[posmod(degree, n)]) + 12 * octave
	_play(stream, pow(2.0, float(semis) / 12.0), db)


func _play(stream: AudioStream, pitch: float, db: float) -> void:
	var p: AudioStreamPlayer = _pool[_next]
	_next = (_next + 1) % VOICES
	p.stream = stream
	p.pitch_scale = clampf(pitch, 0.25, 4.0)
	p.volume_db = db
	p.play()
