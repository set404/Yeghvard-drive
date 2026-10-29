extends RefCounted
## Sounds made in code, for things there is no recording of yet: a gunshot, a
## punch landing, the click of an empty gun. play() puts one in the world.

const RATE := 22050

static var _cache := {}


## A pistol shot: a sharp crack of noise dying away, with a low thump under it.
static func shot() -> AudioStreamWAV:
	return _cached("shot", func() -> AudioStreamWAV:
		return _make(0.45, func(t: float, rng: RandomNumberGenerator) -> float:
			var crack := rng.randf_range(-1.0, 1.0) * exp(-t * 38.0)
			var tail := rng.randf_range(-1.0, 1.0) * exp(-t * 7.0) * 0.25
			var thump := sin(TAU * 70.0 * t) * exp(-t * 18.0) * 0.6
			return clampf(crack + tail + thump, -1.0, 1.0)))


## A fist landing: a short low thud.
static func punch() -> AudioStreamWAV:
	return _cached("punch", func() -> AudioStreamWAV:
		return _make(0.16, func(t: float, rng: RandomNumberGenerator) -> float:
			var thud := sin(TAU * (95.0 - t * 200.0) * t) * exp(-t * 30.0)
			var slap := rng.randf_range(-1.0, 1.0) * exp(-t * 90.0) * 0.5
			return clampf(thud + slap, -1.0, 1.0)))


## A car going into a wall: a crunch of metal and breaking glass.
static func crash() -> AudioStreamWAV:
	return _cached("crash", func() -> AudioStreamWAV:
		return _make(1.4, func(t: float, rng: RandomNumberGenerator) -> float:
			var bang := sin(TAU * (60.0 - t * 30.0) * t) * exp(-t * 6.0)
			var crunch := rng.randf_range(-1.0, 1.0) * exp(-t * 4.0) * 0.8
			# Glass: bright ringing bits that come and go.
			var glass := sin(TAU * (2600.0 + 900.0 * sin(t * 40.0)) * t) * exp(-t * 3.0) * 0.25 * float(rng.randf() < 0.35)
			return clampf(bang + crunch + glass, -1.0, 1.0)))


## A car alarm: a siren going up and down, then beeps. Plays once (about 6 s).
static func alarm() -> AudioStreamWAV:
	return _cached("alarm", func() -> AudioStreamWAV:
		return _make(6.0, func(t: float, _rng: RandomNumberGenerator) -> float:
			var f := 900.0 + 500.0 * sin(TAU * 1.6 * t) if t < 3.0 else 1300.0
			var on := 1.0 if t < 3.0 or fmod(t, 0.4) < 0.2 else 0.0
			return sin(TAU * f * t) * 0.45 * on))


## A phone ringing: two tones together, on and off (about 4 s, two rings).
static func ring() -> AudioStreamWAV:
	return _cached("ring", func() -> AudioStreamWAV:
		return _make(4.0, func(t: float, _rng: RandomNumberGenerator) -> float:
			var on := 1.0 if fmod(t, 2.0) < 1.2 and fmod(t, 0.1) < 0.07 else 0.0
			return (sin(TAU * 440.0 * t) + sin(TAU * 480.0 * t)) * 0.25 * on))


## The hammer falling on an empty chamber.
static func click() -> AudioStreamWAV:
	return _cached("click", func() -> AudioStreamWAV:
		return _make(0.05, func(t: float, rng: RandomNumberGenerator) -> float:
			return rng.randf_range(-1.0, 1.0) * exp(-t * 160.0) * 0.6))


## Plays `stream` at `at` (world) under `parent`; the player goes when it is done.
static func play(parent: Node, stream: AudioStream, at: Vector3, volume_db := 0.0, unit_size := 10.0) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.volume_db = volume_db
	p.unit_size = unit_size
	p.max_distance = 300.0
	parent.add_child(p)
	p.global_position = at
	p.finished.connect(p.queue_free)
	p.play()


## Plays `stream` everywhere at once (not from a spot in the world): a phone in your pocket.
static func play_flat(parent: Node, stream: AudioStream, volume_db := 0.0) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = volume_db
	parent.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


static func _cached(key: String, make: Callable) -> AudioStreamWAV:
	if not _cache.has(key):
		_cache[key] = make.call()
	return _cache[key]


static func _make(seconds: float, sample: Callable) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	var n := int(seconds * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var v: float = sample.call(float(i) / RATE, rng)
		data.encode_s16(i * 2, int(v * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav
