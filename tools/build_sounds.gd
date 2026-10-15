extends SceneTree
## Synthesises the game's sound effects into res://audio/*.res (AudioStreamWAV),
## so no recordings are needed.
##
## Run:  godot --headless --path . --script res://tools/build_sounds.gd

const RATE := 22050
const OUT_DIR := "res://audio"

var rng := RandomNumberGenerator.new()


func _initialize() -> void:
	rng.seed = 1996
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	# Engines, each at 1500 rpm (car.gd plays them faster or slower with the revs):
	# per cylinder in firing order, how strongly it fires and how early or late.
	# The one most cars use: a big V8.
	_save("engine", _engine_pulses([1.0, 0.85, 0.95, 0.8, 1.0, 0.88, 0.92, 0.78],
		[0.0, 0.06, -0.04, 0.05, 0.0, -0.05, 0.04, -0.03], 120.0, 55.0, 48.0, 1.6), true)
	# Volga GAZ-3102: carburetted 2.4 l straight four, rough and tappety.
	_save("engine_i4_volga", _engine_pulses([1.0, 0.82, 0.95, 0.78], [0.0, 0.04, -0.03, 0.02],
		150.0, 70.0, 38.0, 2.0, 0.0, 0.05), true)
	# E50 AMG: 5.0 l V8, smooth and deep.
	_save("engine_v8_e50", _engine_pulses([1.0, 0.9, 0.96, 0.86, 1.0, 0.92, 0.94, 0.88],
		[0.0, 0.04, -0.03, 0.03, 0.0, -0.03, 0.03, -0.02], 105.0, 45.0, 42.0, 1.3), true)
	# E55 AMG: a recording of a real big-block V8 idling at about 1120 rpm (the
	# E55's engine_sound_rpm). It was cut from data/sounds/big_block_v8_rev.mp3,
	# 0.785 s from 1.89 s in, with its end blended into its start.
	_save_recording("engine_v8k_e55", "res://data/sounds/big_block_v8_idle_loop.wav")
	# The starter, from a recording of a car being cranked (data/sounds/starting.mp3):
	# it engaging (0.18 to 0.45 s in), then 2.065 s of cranking from 1.87 s in, four
	# turns of its compression rhythm, with its end blended into its start.
	_save_recording("starter", "res://data/sounds/starter_loop.wav")
	_save_recording("starter_click", "res://data/sounds/starter_engage.wav", false)
	# Engines held at steady revs (car.gd's engine_layers), cut from recordings by
	# tools/engine_layers/layers.js; each file is named after its car and revs.
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR + "/layers"))
	for wav in DirAccess.get_files_at("res://data/sounds/layers"):
		if wav.ends_with(".wav"):
			_save_recording("layers/" + wav.get_basename(), "res://data/sounds/layers/" + wav)
	_save("skid", _skid(), true)
	_save("tick", _click(2400.0), false)
	_save("tock", _click(1650.0), false)
	_save("gate", _gate(), false)
	quit()


func _save(sound: String, samples: PackedFloat32Array, loop: bool) -> void:
	var peak := 0.0001
	var power := 0.0
	for s in samples:
		peak = maxf(peak, absf(s))
		power += s * s
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i] / peak * 0.9, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = bytes
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = samples.size()
	var path := "%s/%s.res" % [OUT_DIR, sound]
	var err := ResourceSaver.save(stream, path, ResourceSaver.FLAG_COMPRESS)
	print("%s: %.2f s, loudness %.0f%% of peak%s%s" % [path, samples.size() / float(RATE),
		sqrt(power / samples.size()) / peak * 100.0, ", loops" if loop else "", "" if err == OK else "  SAVE FAILED"])


## A sound from a recording; if `loop`, the .wav must already loop cleanly.
func _save_recording(sound: String, wav: String, loop := true) -> void:
	var stream := AudioStreamWAV.load_from_file(ProjectSettings.globalize_path(wav))
	if stream == null:
		push_error("Cannot read %s" % wav)
		return
	var frames := stream.data.size() / (2 * (2 if stream.stereo else 1))
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = frames
	var path := "%s/%s.res" % [OUT_DIR, sound]
	var err := ResourceSaver.save(stream, path, ResourceSaver.FLAG_COMPRESS)
	print("%s: %.2f s from %s%s%s" % [path, frames / float(stream.mix_rate), wav.get_file(),
		", loops" if loop else "", "" if err == OK else "  SAVE FAILED"])


func _blank(seconds: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(seconds * RATE))
	return out


## White noise through a one-pole low-pass and high-pass, i.e. a rough band.
func _noise(count: int, low_cut: float, high_cut: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(count)
	var a_low := 1.0 - exp(-TAU * high_cut / RATE)
	var a_high := 1.0 - exp(-TAU * low_cut / RATE)
	var low := 0.0
	var slow := 0.0
	for i in count:
		low += a_low * (rng.randf_range(-1.0, 1.0) - low)
		slow += a_high * (low - slow)
		out[i] = low - slow
	return out


## Blends the end of a sound into its start so that it loops without a click.
func _make_seamless(samples: PackedFloat32Array, overlap: int) -> PackedFloat32Array:
	var count := samples.size() - overlap
	var out := samples.slice(0, count)
	for i in overlap:
		var t := float(i) / overlap
		out[i] = samples[i] * t + samples[count + i] * (1.0 - t)
	return out


## Two seconds of an engine at 1500 rpm: 25 turns of its four-stroke cycle, made
## of its firing. Each cylinder's exhaust pulse is a thump that rings at `ring`
## Hz over a lower `body` tone and dies away at `decay` per second. `levels`
## and `timing` (a share of the gap between firings) give each cylinder in firing
## order its strength and how early or late it fires; the unevenness is what makes
## an engine burble. `drive` is how hard it is clipped, `whine` a supercharger's
## tone (Hz; 0 for none) and `tappets` the level of the valvetrain's ticking.
## Every part repeats exactly, so it loops without a seam and has no hiss.
func _engine_pulses(levels: Array, timing: Array, ring: float, decay: float, body: float, drive: float,
		whine := 0.0, tappets := 0.0) -> PackedFloat32Array:
	var out := _blank(2.0)
	var n := out.size()
	var cycle := 0.08
	var gap := cycle / levels.size()
	var pulse := PackedFloat32Array()
	pulse.resize(int(0.07 * RATE))
	for i in pulse.size():
		var dt := float(i) / RATE
		pulse[i] = sin(TAU * ring * dt) * exp(-dt * decay) + 0.7 * sin(TAU * body * dt) * exp(-dt * decay * 0.6)
	for c in 25:
		for k in levels.size():
			var start := int(round((c * cycle + (k + float(timing[k])) * gap) * RATE))
			for i in pulse.size():
				# The tail of the last firings carries on into the start of the loop.
				out[posmod(start + i, n)] += pulse[i] * float(levels[k])
	var peak := 0.0001
	for s in out:
		peak = maxf(peak, absf(s))
	var smooth := 0.0
	var a := 1.0 - exp(-TAU * 2500.0 / RATE)
	for i in n:
		var t := float(i) / RATE
		var v := tanh(out[i] / peak * drive) / tanh(drive)
		if whine > 0.0:
			v += (sin(TAU * whine * t) + 0.35 * sin(TAU * whine * 2.0 * t)) * 0.06
		if tappets > 0.0:
			# A tick each time a valve shuts: 50 a second, each a short ring of metal.
			v += sin(TAU * 3100.0 * t) * tappets * exp(-fposmod(t, 0.02) * 1500.0)
		# Takes the harsh edge off, as the exhaust and body do.
		smooth += a * (v - smooth)
		out[i] = smooth
	return out


## Tyres scrubbing: hissing rubber with a thin squeal on top.
func _skid() -> PackedFloat32Array:
	var count := int(1.5 * RATE)
	var hiss := _make_seamless(_noise(count + 2000, 700.0, 3200.0), 2000)
	var out := PackedFloat32Array()
	out.resize(count)
	for i in count:
		var t := float(i) / RATE
		var wobble := 0.6 + 0.4 * sin(TAU * 4.0 * t)
		var squeal := sin(TAU * 1180.0 * t + 0.6 * sin(TAU * 6.0 * t)) * 0.16 * wobble
		squeal += sin(TAU * 1730.0 * t) * 0.07 * (1.0 - wobble)
		out[i] = hiss[i] * 1.5 + squeal
	return out


## The click of the indicator relay.
func _click(pitch: float) -> PackedFloat32Array:
	var out := _blank(0.05)
	var snap := _noise(out.size(), 900.0, 6000.0)
	for i in out.size():
		var t := float(i) / RATE
		out[i] = snap[i] * exp(-t * 260.0) * 1.2 + sin(TAU * pitch * t) * exp(-t * 110.0) * 0.5
	return out


## Heavy steel doors swinging: rumbling hinges, a dry creak that sticks and
## slips, and the clunk as they come to rest.
func _gate() -> PackedFloat32Array:
	var swing := 1.8
	var out := _blank(swing + 0.5)
	var rumble := _noise(out.size(), 30.0, 220.0)
	var grit := _noise(out.size(), 2.0, 9.0) # slow, for the stick-slip of the creak
	var phase := 0.0
	for i in out.size():
		var t := float(i) / RATE
		var moving := smoothstep(0.0, 0.15, t) * (1.0 - smoothstep(swing - 0.15, swing, t))
		var s := rumble[i] * 2.2 * moving
		# The creak wanders in pitch and only sounds while the hinge is binding.
		var pitch := 340.0 + 230.0 * sin(TAU * 0.8 * t) + 70.0 * sin(TAU * 6.5 * t)
		phase += TAU * pitch / RATE
		var binding := clampf(grit[i] * 14.0, 0.0, 1.0)
		s += (sin(phase) + 0.4 * sin(phase * 2.01) + 0.2 * sin(phase * 3.02)) * 0.28 * binding * moving
		# The leaves hit their stops.
		var after := t - swing
		if after > 0.0:
			s += sin(TAU * 68.0 * after) * exp(-after * 16.0) * 1.3
			s += rumble[i] * 3.0 * exp(-after * 30.0)
		out[i] = s
	return out
