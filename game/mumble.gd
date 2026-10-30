extends RefCounted
## Gibberish voices for the story's lines (game/dialogue.gd), the way The Sims
## and Animal Crossing talk, but following the line's own letters: each vowel
## in it is a syllable, said with the consonant before it (syllables_of()), so
## the mumble keeps the words' rhythm and sounds.
##
## A voice is a pitch, a pace, how far up its vowels sit (a smaller person's
## voice is brighter), how rough and how breathy it is. The syllables are made
## here in code, like a formant synthesizer: a glottal buzz with the small
## wobble of pitch and loudness a real voice has, and some breath, through
## three resonators at the vowel's formants, gliding in from the consonant: a
## plosive's burst, a hiss, an h, a nasal or l/r murmur. A voice heard over the
## phone is cut down to a phone's narrow band.

const RATE := 22050
## Per speaker: pitch (Hz), pace (faster or slower), formants (vowels higher or
## lower), rasp (roughness, 0..1), breath (0..1). Anyone else gets DEFAULT.
const VOICES := {
	"Vzgo": {"pitch": 118.0, "pace": 1.0, "formants": 1.0, "rasp": 0.04, "breath": 0.1},
	"Davitik": {"pitch": 150.0, "pace": 1.15, "formants": 1.1, "rasp": 0.02, "breath": 0.14},
	"Uncle": {"pitch": 92.0, "pace": 0.85, "formants": 0.92, "rasp": 0.2, "breath": 0.12},
	"Papa": {"pitch": 100.0, "pace": 0.92, "formants": 0.95, "rasp": 0.08, "breath": 0.1},
}
const DEFAULT := {"pitch": 130.0, "pace": 1.0, "formants": 1.0, "rasp": 0.05, "breath": 0.1}
## Vowels by their first three formants (Hz): a, e, i, o, u, and the "uh" (ը) between.
const VOWELS := [
	[780.0, 1250.0, 2550.0], [500.0, 1850.0, 2550.0], [320.0, 2250.0, 2950.0],
	[520.0, 920.0, 2450.0], [350.0, 800.0, 2300.0], [560.0, 1300.0, 2450.0],
]
## The consonant before a vowel, by the kind of sound it makes.
enum Cons { NONE, STOP, S, SH, H, NASAL, LIQUID, F }
## Letters of each kind, Armenian and Latin.
const LETTERS := {
	Cons.STOP: "պբտդկգքթփpbtdkgcq",
	Cons.S: "սզծձցszx",
	Cons.SH: "շժճջչj",
	Cons.H: "հխղh",
	Cons.NASAL: "մնmn",
	Cons.LIQUID: "լրռյlryw",
	Cons.F: "ֆվfv",
}
## Letters that are vowels, and which of VOWELS (ո before ւ is "u").
const VOWEL_LETTERS := {
	"ա": 0, "ե": 1, "է": 1, "և": 1, "ի": 2, "ո": 3, "օ": 3, "ը": 5,
	"a": 0, "e": 1, "i": 2, "o": 3, "u": 4,
}
## Marks that sit inside an Armenian word (stress, question, exclamation) and the
## ւ of ու: no break between words.
const IN_WORD := "՛՞՜ւ'"
## Takes of each syllable, one picked at random each time it is said.
const VARIANTS := 2

static var _cache := {}


## The speaker's voice (a Dictionary like those in VOICES).
static func voice(who: String) -> Dictionary:
	return VOICES.get(who, DEFAULT)


## The syllables of `text`, in order: for each vowel, {"at": its index in the
## text, "cons": the Cons before it, "vowel": its index in VOWELS, "stress":
## whether it ends its word (Armenian stresses the last syllable)}.
static func syllables_of(text: String) -> Array:
	var t := _lower(text)
	var found := []
	var cons := Cons.NONE
	var word_start := 0
	for i in t.length():
		var c := t[i]
		if VOWEL_LETTERS.has(c):
			var v: int = VOWEL_LETTERS[c]
			if c == "ո" and i + 1 < t.length() and t[i + 1] == "ւ":
				v = 4
			found.append({"at": i, "cons": cons, "vowel": v, "stress": false})
			cons = Cons.NONE
			continue
		var kind := _kind(c)
		if kind != Cons.NONE:
			cons = kind
		elif not IN_WORD.contains(c):
			if found.size() > word_start:
				found[-1]["stress"] = true
			word_start = found.size()
			cons = Cons.NONE
	if found.size() > word_start:
		found[-1]["stress"] = true
	return found


## One syllable in the speaker's voice, made the first time it is asked for;
## `phone`: as heard over the phone.
static func sound(who: String, cons: int, vowel: int, phone := false) -> AudioStreamWAV:
	var key := "%s/%d/%d/%d/%s" % [who, cons, vowel, randi() % VARIANTS, phone]
	if not _cache.has(key):
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(key)
		_cache[key] = _make(voice(who), cons, VOWELS[vowel], rng, phone)
	return _cache[key]


static func _kind(c: String) -> int:
	for kind: int in LETTERS:
		if (LETTERS[kind] as String).contains(c):
			return kind
	return Cons.NONE


## Lower case, Armenian capitals too, one character for one so the indices stay.
static func _lower(text: String) -> String:
	var out := ""
	for i in text.length():
		var u := text.unicode_at(i)
		out += String.chr(u + 0x30) if u >= 0x531 and u <= 0x556 else text[i].to_lower()
	return out


static func _make(v: Dictionary, cons: int, vowel: Array, rng: RandomNumberGenerator, phone: bool) -> AudioStreamWAV:
	var pace: float = v["pace"]
	var fm: float = v["formants"]
	var rasp: float = v["rasp"]
	var breath: float = v["breath"]
	var f0: float = float(v["pitch"]) * rng.randf_range(0.95, 1.05)
	var target := [vowel[0] * fm, vowel[1] * fm, vowel[2] * fm]
	# The consonant: how long it is, the formants the vowel glides in from (its
	# place in the mouth), its hiss (centre Hz, 0 for none, and how loud) and
	# how loud its voiced murmur is (a nasal, l or r).
	var lead := 0.0
	var start: Array = target.duplicate()
	var hiss_f := 0.0
	var hiss_level := 0.0
	var murmur := 0.0
	match cons:
		Cons.STOP:
			lead = rng.randf_range(0.035, 0.05)
			start = [260.0 * fm, [1100.0, 1750.0, 2100.0][rng.randi() % 3] * fm, 2600.0 * fm]
			hiss_f = [1300.0, 2600.0, 3600.0][rng.randi() % 3]
			hiss_level = 0.45
		Cons.S:
			lead = rng.randf_range(0.055, 0.075)
			start = [300.0 * fm, 1750.0 * fm, 2700.0 * fm]
			hiss_f = 5200.0
			hiss_level = 0.3
		Cons.SH:
			lead = rng.randf_range(0.055, 0.075)
			start = [300.0 * fm, 1950.0 * fm, 2650.0 * fm]
			hiss_f = 2900.0
			hiss_level = 0.35
		Cons.H:
			lead = rng.randf_range(0.04, 0.055)
		Cons.NASAL:
			lead = rng.randf_range(0.045, 0.06)
			start = [260.0 * fm, 1150.0 * fm, 2350.0 * fm]
			murmur = 0.35
		Cons.LIQUID:
			lead = rng.randf_range(0.035, 0.05)
			start = [360.0 * fm, 1100.0 * fm, 2500.0 * fm]
			murmur = 0.6
		Cons.F:
			lead = rng.randf_range(0.045, 0.06)
			start = [300.0 * fm, 1300.0 * fm, 2400.0 * fm]
			hiss_f = 1800.0
			hiss_level = 0.12
	lead /= pace
	var total := lead + rng.randf_range(0.075, 0.105) / pace
	var count := int(total * RATE)
	# A nasal, l, r or h sounds from the start; after a stop or a hiss the voice comes in at the vowel.
	var voice_from := 0.0 if cons in [Cons.NONE, Cons.NASAL, Cons.LIQUID, Cons.H] else lead
	# The pitch through the syllable: a little up or down, as speech goes.
	var glide := rng.randf_range(-0.07, 0.04)
	var glide_in := 0.045 / pace
	const BANDS := [80.0, 100.0, 150.0]

	var said := PackedFloat32Array()
	said.resize(count)
	var hiss := PackedFloat32Array()
	hiss.resize(count)
	var coef := []
	var state := [[0.0, 0.0], [0.0, 0.0], [0.0, 0.0]]
	var hiss_coef := _resonator(maxf(hiss_f, 100.0), maxf(hiss_f * 0.35, 100.0))
	var hiss_state := [0.0, 0.0]
	var phase := 0.0
	var period_scale := 1.0
	var shimmer := 1.0
	var flow_prev := 0.0
	for i in count:
		var t := float(i) / RATE
		# The formants, gliding (eased) from the consonant's into the vowel's.
		if i % 32 == 0:
			var k := clampf((t - lead) / glide_in, 0.0, 1.0)
			k = k * k * (3.0 - 2.0 * k)
			coef.clear()
			for f in 3:
				coef.append(_resonator(lerpf(start[f], target[f], k), BANDS[f]))
		# The glottis: a smooth puff of air each period, pitch and loudness
		# wobbling a little from one to the next, with breath through it.
		phase += f0 * (1.0 + glide * t / total) * period_scale / RATE
		if phase >= 1.0:
			phase -= 1.0
			period_scale = 1.0 + rng.randf_range(-0.015, 0.015)
			shimmer = 1.0 + rng.randf_range(-0.08, 0.08)
		var flow := 0.5 * (1.0 - cos(PI * phase / 0.6)) if phase < 0.6 else 0.5 * (1.0 + cos(PI * (phase - 0.6) / 0.4))
		var pulse := (flow - flow_prev) * 40.0 * shimmer
		flow_prev = flow
		var noise := rng.randf_range(-1.0, 1.0)
		var x := pulse + noise * (breath * flow + rasp * 0.6)
		if t < lead:
			match cons:
				Cons.NASAL, Cons.LIQUID:
					x *= murmur
				Cons.H:
					x = noise * 0.5 * sin(PI * t / lead)
				_:
					x = 0.0
		# In and out without a click.
		var on := clampf((t - voice_from) / 0.012, 0.0, 1.0)
		var off := clampf((total - t) / 0.035, 0.0, 1.0)
		x *= sin(on * PI * 0.5) * sin(off * PI * 0.5)
		for f in 3:
			var c: Array = coef[f]
			var y: float = c[0] * x + c[1] * state[f][0] + c[2] * state[f][1]
			state[f][1] = state[f][0]
			state[f][0] = y
			x = y
		said[i] = x
		# The consonant's own noise: a stop's burst as it opens, or a hiss.
		if hiss_f > 0.0 and t < lead + 0.015:
			var h: float = hiss_coef[0] * noise + hiss_coef[1] * hiss_state[0] + hiss_coef[2] * hiss_state[1]
			hiss_state[1] = hiss_state[0]
			hiss_state[0] = h
			var shape := 0.0
			if cons == Cons.STOP:
				shape = exp(-(t - lead * 0.75) / 0.006) if t > lead * 0.75 else 0.0
			else:
				shape = sin(PI * clampf(t / (lead + 0.015), 0.0, 1.0))
			hiss[i] = h * shape
	# The voice at 0.6 of full; the hiss as loud as hiss_level of that.
	var said_peak := 0.0001
	var hiss_peak := 0.0001
	for i in count:
		said_peak = maxf(said_peak, absf(said[i]))
		hiss_peak = maxf(hiss_peak, absf(hiss[i]))
	var out := PackedFloat32Array()
	out.resize(count)
	for i in count:
		out[i] = said[i] / said_peak * 0.6 + hiss[i] / hiss_peak * 0.6 * hiss_level
	# A phone: only its middle band (about 350 to 2800 Hz), a little crackle.
	if phone:
		var high := 0.0
		var low := 0.0
		var prev := 0.0
		for i in count:
			high = 0.9 * (high + out[i] - prev)
			prev = out[i]
			low += (high - low) * 0.55
			out[i] = low * 1.4 + rng.randf_range(-1.0, 1.0) * 0.01
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		data.encode_s16(i * 2, int(clampf(out[i], -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav


## A two-pole resonator at `freq` Hz, `band` Hz wide, with a gain of 1 at 0 Hz:
## [a, b, c] for y = a*x + b*y1 + c*y2.
static func _resonator(freq: float, band: float) -> Array:
	var r := exp(-PI * band / RATE)
	var b := 2.0 * r * cos(TAU * freq / RATE)
	var c := -r * r
	return [1.0 - b - c, b, c]
