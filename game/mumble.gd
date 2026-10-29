extends RefCounted
## Gibberish voices for the story's lines (game/dialogue.gd), the way The Sims
## and Animal Crossing talk: each line is spoken as a run of short made-up
## syllables in the speaker's own voice, while its text types out.
##
## A voice is a pitch, a pace, how far up its vowels sit (a smaller person's
## voice is brighter) and how rough it is. The syllables are made here in
## code: each is a vowel (two formants over the voice's harmonics, one period
## of it looped), gliding a little in pitch, sometimes after a short consonant
## hiss. A voice heard over the phone is cut down to a phone's narrow band.

const RATE := 22050
## Per speaker: pitch (Hz), pace (syllables faster or slower), formants (vowels
## higher or lower), rasp (roughness, 0..1). Anyone else gets DEFAULT.
const VOICES := {
	"Vzgo": {"pitch": 118.0, "pace": 1.0, "formants": 1.0, "rasp": 0.04},
	"Davitik": {"pitch": 152.0, "pace": 1.18, "formants": 1.1, "rasp": 0.02},
	"Uncle": {"pitch": 92.0, "pace": 0.8, "formants": 0.92, "rasp": 0.22},
	"Papa": {"pitch": 100.0, "pace": 0.9, "formants": 0.95, "rasp": 0.1},
}
const DEFAULT := {"pitch": 130.0, "pace": 1.0, "formants": 1.0, "rasp": 0.05}
## Vowels by their first two formants (Hz): a, e, i, o, u, and the "uh" between.
const VOWELS := [[800.0, 1200.0], [500.0, 1800.0], [320.0, 2300.0], [500.0, 900.0], [350.0, 800.0], [620.0, 1150.0]]
## Syllables made for each voice (played in a shuffled order, at slightly different pitches).
const SYLLABLES := 12

static var _cache := {}


## The speaker's voice (a Dictionary like those in VOICES).
static func voice(who: String) -> Dictionary:
	return VOICES.get(who, DEFAULT)


## Seconds between syllables in the speaker's voice.
static func syllable_gap(who: String) -> float:
	return 0.115 / float(voice(who)["pace"])


## The speaker's syllables, made the first time they are asked for; `phone`:
## as heard over the phone.
static func syllables(who: String, phone := false) -> Array:
	var key := who + ("/phone" if phone else "")
	if _cache.has(key):
		return _cache[key]
	var v := voice(who)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var made := []
	for i in SYLLABLES:
		made.append(_syllable(v, VOWELS[i % VOWELS.size()], rng, phone))
	_cache[key] = made
	return made


static func _syllable(v: Dictionary, vowel: Array, rng: RandomNumberGenerator, phone: bool) -> AudioStreamWAV:
	var f0: float = float(v["pitch"]) * rng.randf_range(0.92, 1.1)
	var seconds: float = rng.randf_range(0.075, 0.13) / float(v["pace"])
	var count := int(seconds * RATE)
	# One period of the vowel: the voice's harmonics, loudest near its two formants.
	var period := maxi(int(RATE / f0), 8)
	var table := PackedFloat32Array()
	table.resize(period)
	var f1: float = float(vowel[0]) * float(v["formants"])
	var f2: float = float(vowel[1]) * float(v["formants"])
	var k := 1
	while k * f0 < 4000.0:
		var f := k * f0
		var a := exp(-pow((f - f1) / 170.0, 2.0)) + 0.6 * exp(-pow((f - f2) / 240.0, 2.0)) + 0.12 / k
		if phone and (f < 350.0 or f > 3000.0):
			a *= 0.04
		for s in period:
			table[s] += a * sin(TAU * k * s / period)
		k += 1
	var peak := 0.001
	for s in period:
		peak = maxf(peak, absf(table[s]))
	# Up or down a little through the syllable, as speech goes.
	var glide := rng.randf_range(-0.12, 0.12)
	var consonant := rng.randf() < 0.6
	var rasp: float = float(v["rasp"])
	var data := PackedByteArray()
	data.resize(count * 2)
	var phase := 0.0
	for i in count:
		var t := float(i) / RATE
		var env := minf(1.0, t / 0.012) * clampf((seconds - t) / 0.035, 0.0, 1.0)
		var sample := table[int(phase) % period] / peak * env * 0.55
		phase += 1.0 + glide * t / seconds
		sample += rng.randf_range(-1.0, 1.0) * rasp * env * 0.35
		if consonant and t < 0.018:
			sample = sample * (t / 0.018) + rng.randf_range(-1.0, 1.0) * 0.25 * (1.0 - t / 0.018)
		if phone:
			sample = sample * 0.8 + rng.randf_range(-1.0, 1.0) * 0.015
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 30000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav
