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
	_save("engine", _engine(), true)
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


## Two seconds of a big V8 at 1500 rpm. Played faster or slower for other revs.
func _engine() -> PackedFloat32Array:
	var out := _blank(2.0)
	# Firing is 100 Hz at 1500 rpm; the uneven burble sits at the half orders below it.
	var partials := {25.0: 0.45, 50.0: 1.0, 75.0: 0.55, 100.0: 0.85, 150.0: 0.4, 200.0: 0.3, 300.0: 0.14, 400.0: 0.07}
	var phases := {}
	for f: float in partials:
		phases[f] = rng.randf() * TAU
	var rumble := _make_seamless(_noise(out.size() + 2000, 40.0, 420.0), 2000)
	for i in out.size():
		var t := float(i) / RATE
		var s := 0.0
		for f: float in partials:
			s += partials[f] * sin(TAU * f * t + phases[f])
		# Each cylinder bank pulses a little differently.
		s *= 1.0 + 0.22 * sin(TAU * 12.5 * t) + 0.1 * sin(TAU * 37.5 * t + 1.0)
		out[i] = tanh((s * 0.45 + rumble[i] * 1.6) * 1.4)
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
