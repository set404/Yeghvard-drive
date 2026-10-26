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
