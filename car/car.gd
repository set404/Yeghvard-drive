extends VehicleBody3D
## Simple arcade car. VehicleBody3D drives towards its local +Z.

const WATTS_PER_HP := 745.7

@export var horsepower := 150.0 ## peak engine power
@export var max_drive_force := 8000.0 ## N; what the tyres can put down at low speed
@export var reverse_force := 4000.0 ## N
@export var max_reverse_speed := 12.0 ## m/s
@export var drag := 0.42 ## air resistance, N per (m/s)^2
@export var rolling_resistance := 180.0 ## N
@export var brake_power := 60.0
@export var max_steer := 0.6
@export var steer_speed := 3.0
## Whether the keyboard drives this car. Parked cars have it off.
@export var player_controlled := true
## In park (P): the transmission is locked, so the car holds still and the
## engine will not drive it, with or without a driver. Out of park, a car with
## nobody in it rolls freely. P only goes into park at walking pace or slower.
@export var parked := false
@export var park_speed := 1.5 ## m/s; fastest the car may be going for P to engage
## Body colour. Only cars built with a "Paint" material (see tools/build_car.gd) use it.
@export var paint_color := Color(0.66, 0.68, 0.68)
## Where the driver's eyes are, for the cabin camera (+X left, +Y up, +Z forward).
@export var driver_view := Vector3(0.37, 1.13, 0.1)

@export_group("Starter")
## How long the starter turns the engine over before it catches, in seconds.
@export var starter_seconds := 1.0
## Chance (0 to 1) that a try to start fails: the starter cranks for a while and
## the engine does not catch, so you have to try again. The try after a failed
## one always works.
@export var start_fail_chance := 0.0

@export_group("Fuel")
## Size of the tank, in litres.
@export var fuel_capacity := 70.0
## What is in the tank now, in litres. The engine dies when it runs dry and
## will not start again until the car is refuelled (refuel() or fill_up()).
@export var fuel := 70.0
## Litres an hour the engine burns ticking over.
@export var idle_consumption := 1.0
## How much faster than a real engine this one drinks, so that a tank lasts
## an evening's driving rather than a week's. 1 is true to life.
@export var fuel_use_scale := 5.0

@export_group("Grip and drifting")
## Tyre grip. The rear has less than the front so that power or the handbrake can break it loose.
@export var front_grip := 2.0
@export var rear_grip := 1.7
@export var handbrake_grip := 0.9 ## rear grip while the handbrake is on
@export var power_slide := 0.8 ## rear grip lost at full throttle in a corner; 0 never power-slides
@export var cornering_g := 1.1 ## at speed the steering lock is capped to this much cornering
@export var countersteer_assist := 0.5 ## how much the car steers into a slide by itself
@export var max_drift_angle := 28.0 ## degrees; past this the car pulls itself straighter
@export var drift_recovery := 20.0 ## how hard it pulls
@export var power_slide_fade_speed := 45.0 ## m/s; above this, throttle no longer loosens the rear
@export var roll_influence := 0.04 ## how much cornering force leans the body; low keeps it from rolling over

@export_group("Engine note and gears")
@export var idle_rpm := 800.0
@export var redline_rpm := 6200.0
## Speed in km/h at which each gear reaches the redline.
@export var gear_top_speeds: Array[float] = [55.0, 95.0, 145.0, 200.0, 270.0]
## Revs at which the automatic changes up when you are easy on the pedal. The
## further down the pedal, the later it changes, up to near the redline flat out.
@export var shift_up_rpm := 2300.0
@export var engine_volume_db := -6.0
@export var skid_volume_db := -10.0
## This car's engine note, a loop (see tools/build_sounds.gd), when it has no engine_layers.
@export_file("*.res") var engine_sound := "res://audio/engine.res"
## The revs engine_sound was recorded at; it is played faster or slower from there.
@export var engine_sound_rpm := 1500.0
## Recordings of this engine held at steady revs, lowest first (see
## tools/build_sounds.gd). The engine note blends between the two nearest the
## revs, each played a little faster or slower to match them.
@export var engine_layers: Array[AudioStream] = []
## The revs each of engine_layers was recorded at, in the same order.
@export var engine_layer_rpms: PackedFloat32Array = []
## How fast its starter motor spins; below 1 for a slow, old one.
@export var starter_pitch := 1.0

const ACTIONS := {
	"accelerate": [KEY_W, KEY_UP],
	"brake": [KEY_S, KEY_DOWN],
	"steer_left": [KEY_A, KEY_LEFT],
	"steer_right": [KEY_D, KEY_RIGHT],
	"handbrake": [KEY_SPACE],
	"reset_car": [KEY_R],
	"park": [KEY_P],
	"starter": [KEY_E],
}

## Pulses per second of the engine being turned over by the starter, as in the
## recording of it (audio/starter.res).
const CRANK_PULSES := 7.7
## Litres of fuel an engine burns per hour for each horsepower it delivers.
const FUEL_PER_HP_HOUR := 0.25
## Below this share of the tank the engine is running on the dregs and coughs.
const FUEL_RESERVE := 0.04

## Sent when the engine dies because the tank has run dry.
signal fuel_empty

## True while the driver is on the brake pedal (not the handbrake); the brake lights follow it.
var braking := false
## Power the engine is delivering right now, in hp.
var output_hp := 0.0
## Whether the engine is running. Off, the car will not drive itself (the
## brakes, lights and parking lock still work). E starts it, or stops it.
var engine_running := false
## True while the starter is turning the engine over.
var cranking := false
## True when the last try to start did not catch.
var start_failed := false
var _crank_time := 0.0
var _crank_for := 0.0
var _will_catch := true
## On the reserve the engine cuts out for moments at a time.
var _cough := false
var _cough_time := 0.0
## Engine speed, for the rev counter and the engine note. There is no real
## gearbox; it is worked out from road speed as an automatic would shift.
var rpm := 800.0
var gear := 1
## The pedal as the gearbox sees it: following the real one, but slowly, so a
## quick dab does not make it change down.
var _shift_gas := 0.0
## Seconds until the gearbox may change again.
var _shift_wait := 0.0
var _gas := 0.0
var _handbrake_on := false
## Where the car is held while it is in park; INF when it is not.
var _park_spot := Vector3.INF
var _engine_sound: AudioStreamPlayer3D
## One player for each of engine_layers.
var _layers: Array[AudioStreamPlayer3D] = []
var _skid_sound: AudioStreamPlayer3D
var _starter_sound: AudioStreamPlayer3D
var _starter_click: AudioStreamPlayer3D
var spawn_transform := Transform3D.IDENTITY
var _front_wheels: Array[VehicleWheel3D] = []
var _rear_wheels: Array[VehicleWheel3D] = []
var _traction_wheels := 0
var _wheelbase := 2.7


func _ready() -> void:
	add_to_group("cars")
	# A sleeping body ignores the engine, so a parked car would never pull away.
	can_sleep = false
	_apply_paint()
	# Each layer needs its revs. An instance override in a scene that empties one
	# list (the editor has saved main.tscn like that) falls back to the single loop.
	var layered := engine_layer_rpms.size() == engine_layers.size()
	if not layered:
		push_warning("%s: %d engine_layers but %d engine_layer_rpms, using the plain engine loop" % [name, engine_layers.size(), engine_layer_rpms.size()])
	for stream in engine_layers if layered else []:
		var layer := AudioStreamPlayer3D.new()
		layer.stream = stream
		layer.unit_size = 9.0
		layer.max_distance = 120.0
		add_child(layer)
		_layers.append(layer)
	if _layers.is_empty():
		_engine_sound = _add_sound(engine_sound)
		if _engine_sound == null:
			_engine_sound = _add_sound("res://audio/engine.res")
	_skid_sound = _add_sound("res://audio/skid.res")
	_starter_sound = _add_sound("res://audio/starter.res")
	_starter_click = _add_sound("res://audio/starter_click.res")
	var front := -INF
	var rear := INF
	var wheels: Array[VehicleWheel3D] = []
	for child in get_children():
		var wheel := child as VehicleWheel3D
		if wheel == null:
			continue
		wheels.append(wheel)
		front = maxf(front, wheel.position.z)
		rear = minf(rear, wheel.position.z)
		if wheel.use_as_traction:
			_traction_wheels += 1
	if front > rear:
		_wheelbase = front - rear
	for wheel in wheels:
		wheel.wheel_roll_influence = roll_influence
		if wheel.position.z > (front + rear) * 0.5:
			_front_wheels.append(wheel)
		else:
			_rear_wheels.append(wheel)
	for action: String in ACTIONS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key: Key in ACTIONS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)


## Signed speed along the nose of the car, in m/s.
func forward_speed() -> float:
	return linear_velocity.dot(global_basis.z)


## How far the rear of the car is sliding sideways, as an angle in radians;
## zero while the rear tyres track cleanly, however tight the turn.
## Positive when it is sliding to its left (nose pointing right of its path).
func slip_angle() -> float:
	var local := global_basis.inverse() * linear_velocity
	if local.z < 3.0:
		return 0.0
	# Sideways speed of the rear axle, which sits half a wheelbase behind the centre.
	var turn_rate := (global_basis.inverse() * angular_velocity).y
	return atan2(local.x - turn_rate * _wheelbase * 0.5, local.z)


func place(xf: Transform3D) -> void:
	_park_spot = Vector3.INF
	spawn_transform = xf
	global_transform = xf
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


func _physics_process(delta: float) -> void:
	var speed := forward_speed()
	if player_controlled and Input.is_action_just_pressed("park"):
		if parked or absf(speed) <= park_speed:
			parked = not parked
	if player_controlled and Input.is_action_just_pressed("starter"):
		if engine_running:
			engine_running = false
		elif cranking:
			cranking = false
		else:
			_crank()
	if cranking:
		_crank_time += delta
		if _crank_time >= _crank_for:
			cranking = false
			engine_running = _will_catch
			start_failed = not _will_catch
			if engine_running:
				# It catches with a little flare of revs before settling to idle.
				rpm = idle_rpm * 1.8
	# A car nobody is driving ignores the keys; one in park ignores the pedals.
	# Without the engine there is no drive, but the brake pedal still works.
	var pedals := player_controlled and not parked
	var gas := Input.get_action_strength("accelerate") if pedals and engine_running else 0.0
	var back := Input.get_action_strength("brake") if pedals else 0.0
	var handbrake := Input.is_action_pressed("handbrake") if player_controlled else false
	var steer_input := Input.get_axis("steer_right", "steer_left") if player_controlled else 0.0
	if engine_running and on_reserve():
		_cough_time -= delta
		if _cough_time <= 0.0:
			_cough = randf() < 0.3
			_cough_time = randf_range(0.1, 0.4)
		if _cough:
			gas *= 0.2
	_gas = gas
	_handbrake_on = handbrake

	var drive := 0.0
	brake = 0.0
	if gas > 0.0:
		if speed < -1.0:
			brake = brake_power * gas
		else:
			# Constant power: force = power / speed, limited by grip when slow.
			drive = minf(max_drive_force, horsepower * WATTS_PER_HP / maxf(speed, 1.0)) * gas
	if back > 0.0:
		if speed > 1.0 or not engine_running:
			brake = brake_power * back
		else:
			drive = -reverse_force * back * clampf(1.0 + speed / max_reverse_speed, 0.0, 1.0)
	braking = brake > 0.0
	if parked:
		# The parking lock holds the wheels. Locked tyres still slide slowly down
		# a slope in the physics engine, so the car is also held to the spot where
		# it stopped. A hard enough knock moves it, and it is held there instead.
		brake = brake_power * 3.0
		if _park_spot == Vector3.INF or global_position.distance_to(_park_spot) > 0.5:
			_park_spot = global_position
		var off := (global_position - _park_spot).slide(Vector3.UP)
		var drift := linear_velocity.slide(Vector3.UP)
		apply_central_force(-(off * 80.0 + drift * 18.0) * mass)
	else:
		_park_spot = Vector3.INF
	var slip := slip_angle()
	# Throttle in a corner loosens the rear to start a slide and keeps one going.
	# The grip comes back as the angle grows, so the slide settles instead of
	# spinning, and the effect fades out as speed builds.
	var asking := maxf(absf(steer_input), minf(absf(slip) / deg_to_rad(10.0), 1.0))
	var room := 1.0 - clampf(absf(slip) / deg_to_rad(max_drift_angle), 0.0, 1.0)
	var slow := clampf(2.0 - 2.0 * absf(speed) / power_slide_fade_speed, 0.0, 1.0)
	var loosen := power_slide * gas * asking * room * slow
	for wheel in _front_wheels:
		wheel.wheel_friction_slip = front_grip
	for wheel in _rear_wheels:
		wheel.wheel_friction_slip = handbrake_grip if handbrake else rear_grip - loosen
		if handbrake:
			# The handbrake locks the rear wheels only, which is what starts a slide.
			wheel.brake = brake_power * 1.5
	# engine_force is applied at every driven wheel.
	engine_force = drive / maxi(_traction_wheels, 1)
	output_hp = absf(drive * speed) / WATTS_PER_HP
	if engine_running:
		var litres_per_hour := idle_consumption + output_hp * FUEL_PER_HP_HOUR
		fuel = maxf(fuel - litres_per_hour / 3600.0 * fuel_use_scale * delta, 0.0)
		if fuel <= 0.0:
			engine_running = false
			fuel_empty.emit()

	# Air and rolling resistance are what set the top speed for a given power.
	var v := linear_velocity
	if v.length() > 0.5:
		apply_central_force(-v * v.length() * drag - v.normalized() * rolling_resistance)

	# Keeps a drift from turning into a spin: past the limit, turn the nose back
	# towards the direction of travel and damp the rotation.
	var over := absf(slip) - deg_to_rad(max_drift_angle)
	if over > 0.0:
		var inertia := mass * 2.2
		apply_torque(Vector3.UP * inertia * (signf(slip) * over * drift_recovery - angular_velocity.y * 2.0))

	# At speed the lock is capped so a tap on the key does not throw the car
	# sideways; once it is sliding the full lock is available for catching it.
	var limit := minf(max_steer, atan(_wheelbase * cornering_g * 9.8 / maxf(speed * speed, 1.0)))
	var sliding := clampf((absf(slip) - deg_to_rad(4.0)) / deg_to_rad(12.0), 0.0, 1.0)
	limit = lerpf(limit, max_steer, sliding)
	var target := steer_input * limit + slip * countersteer_assist
	steering = move_toward(steering, clampf(target, -max_steer, max_steer), steer_speed * delta)

	if player_controlled and Input.is_action_just_pressed("reset_car"):
		var yaw := global_basis.z.slide(Vector3.UP).normalized()
		if yaw.is_zero_approx():
			yaw = Vector3.BACK
		place(Transform3D(Basis.looking_at(-yaw), global_position + Vector3.UP * 1.5))
	elif global_position.y < -500.0:
		place(spawn_transform)


## Puts up to `litres` of fuel in the tank and returns how much went in.
func refuel(litres: float) -> float:
	var added := clampf(litres, 0.0, fuel_capacity - fuel)
	fuel += added
	return added


## Fills the tank to the brim and returns how many litres that took.
func fill_up() -> float:
	return refuel(fuel_capacity)


## How full the tank is, 0 to 1.
func fuel_level() -> float:
	return fuel / fuel_capacity if fuel_capacity > 0.0 else 0.0


## Whether the car is down to the last few litres (or none).
func on_reserve() -> bool:
	return fuel_level() < FUEL_RESERVE


## Turns the starter: the engine catches after about starter_seconds, unless
## this is one of the tries that fail, or the tank is dry.
func _crank() -> void:
	_will_catch = fuel > 0.0 and (start_failed or randf() >= start_fail_chance)
	start_failed = false
	cranking = true
	_crank_time = 0.0
	if _starter_click:
		# The starter engaging; the cranking loop follows once it is over.
		_starter_click.volume_db = engine_volume_db
		_starter_click.pitch_scale = starter_pitch
		_starter_click.play()
	if _will_catch:
		_crank_for = starter_seconds * randf_range(0.85, 1.2)
	else:
		_crank_for = starter_seconds * 1.5 + 0.8


func _apply_paint() -> void:
	# The body, and the driver's door cut out of it (tools/build_car_doors.gd).
	for part: String in ["Body", "DriverDoor/Mesh"]:
		var body := get_node_or_null(part) as MeshInstance3D
		if body == null:
			continue
		for s in body.mesh.get_surface_count():
			var mat := body.mesh.surface_get_material(s) as BaseMaterial3D
			if mat and mat.resource_name == "Paint":
				# A copy, so that two cars sharing the model can be different colours.
				var own := mat.duplicate() as BaseMaterial3D
				own.albedo_color = paint_color
				body.set_surface_override_material(s, own)


## A sound that travels with the car; silent until played. Null if the
## sound has not been made yet (see tools/build_sounds.gd).
func _add_sound(path: String) -> AudioStreamPlayer3D:
	if not ResourceLoader.exists(path):
		return null
	var player := AudioStreamPlayer3D.new()
	player.stream = load(path)
	player.unit_size = 9.0
	player.max_distance = 120.0
	add_child(player)
	return player


## Revs in the given gear at this road speed (the gears reach the redline at gear_top_speeds).
func _gear_rpm(kmh: float, in_gear: int) -> float:
	return kmh / gear_top_speeds[in_gear - 1] * redline_rpm


## Picks the gear as an automatic would. Easy on the pedal it changes up at
## shift_up_rpm and keeps the revs low; the further down the pedal, the later it
## changes, up to near the redline flat out, and pressing hard makes it change
## down. It changes down once the gear below would be well under the change-up
## revs, so it does not hunt between two gears, and waits a moment between changes.
func _shift_gear(kmh: float, delta: float) -> void:
	_shift_gas = move_toward(_shift_gas, _gas, delta * 1.5)
	_shift_wait = maxf(_shift_wait - delta, 0.0)
	var top := gear_top_speeds.size()
	gear = clampi(gear, 1, top)
	if kmh < 3.0:
		gear = 1
		return
	if _shift_wait > 0.0:
		return
	# Squared, so light and middling pedal still change up early.
	var up_at := lerpf(shift_up_rpm, redline_rpm * 0.93, _shift_gas * _shift_gas)
	if gear < top and _gear_rpm(kmh, gear) > up_at:
		gear += 1
		_shift_wait = 0.6
	elif gear > 1 and _gear_rpm(kmh, gear - 1) < up_at * 0.8:
		gear -= 1
		_shift_wait = 0.6


## Plays the two engine_layers nearest the revs, each a little faster or slower
## to match them, crossfading from one to the next as the revs pass between.
## Below the first and above the last, that one alone is slowed or sped up.
func _mix_layers(level_db: float) -> void:
	var n := _layers.size()
	var k := 0
	while k < n - 1 and engine_layer_rpms[k + 1] <= rpm:
		k += 1
	var blend := 0.0
	if k < n - 1 and rpm > engine_layer_rpms[k]:
		blend = (rpm - engine_layer_rpms[k]) / (engine_layer_rpms[k + 1] - engine_layer_rpms[k])
	for i in n:
		# Equal-power crossfade, so the blend is no quieter halfway.
		var share := 0.0
		if i == k:
			share = cos(blend * PI * 0.5)
		elif i == k + 1:
			share = sin(blend * PI * 0.5)
		var layer := _layers[i]
		var on := engine_running and share > 0.001
		if on != layer.playing:
			layer.playing = on
		if on:
			layer.pitch_scale = clampf(rpm / engine_layer_rpms[i], 0.3, 4.0)
			layer.volume_db = level_db + linear_to_db(share)


func _process(delta: float) -> void:
	var kmh := absf(forward_speed()) * 3.6
	_shift_gear(kmh, delta)
	var wanted := maxf(idle_rpm, _gear_rpm(kmh, gear))
	if engine_force != 0.0 and kmh < 25.0:
		# Pulling away, the engine revs before the car has picked up speed, the
		# more so the harder you press.
		wanted = maxf(wanted, lerpf(idle_rpm * 1.5, 3000.0, _gas))
	# The starter turns the engine over slowly, in pulses; stopped, it winds down.
	var pulse := sin(_crank_time * TAU * CRANK_PULSES)
	if cranking:
		wanted = 220.0 + 70.0 * pulse
	elif not engine_running:
		wanted = 0.0
	rpm = lerpf(rpm, wanted, 1.0 - exp(-6.0 * delta))

	# The engine is heard while it runs, whoever is driving (or nobody); while it
	# is cranked, the starter's recording has the engine in it. It is louder
	# under load.
	var effort := clampf(_gas * 0.6 + output_hp / horsepower * 0.4, 0.0, 1.0)
	var level := engine_volume_db + lerpf(-12.0, 0.0, effort)
	if not _layers.is_empty():
		_mix_layers(level)
	elif _engine_sound:
		# One recording at engine_sound_rpm, its speed following the revs.
		if engine_running != _engine_sound.playing:
			_engine_sound.playing = engine_running
		_engine_sound.pitch_scale = clampf(rpm / engine_sound_rpm, 0.4, 4.5)
		_engine_sound.volume_db = level

	if _starter_sound:
		# The recording has the engine's compression strokes in it already.
		var turning := cranking and not (_starter_click and _starter_click.playing)
		if turning != _starter_sound.playing:
			_starter_sound.playing = turning
		_starter_sound.pitch_scale = starter_pitch
		_starter_sound.volume_db = engine_volume_db

	if _skid_sound:
		# Tyres complain under hard braking, with the handbrake on and in a slide.
		var moving := clampf(kmh / 60.0, 0.0, 1.0)
		var scrub := 0.0
		if braking:
			scrub = 0.55 * moving
		if _handbrake_on:
			scrub = maxf(scrub, moving)
		scrub = maxf(scrub, clampf((absf(slip_angle()) - deg_to_rad(6.0)) / deg_to_rad(16.0), 0.0, 1.0))
		if kmh < 4.0:
			scrub = 0.0
		if (scrub > 0.03) != _skid_sound.playing:
			_skid_sound.playing = scrub > 0.03
		_skid_sound.volume_db = skid_volume_db + linear_to_db(maxf(scrub, 0.03))
		_skid_sound.pitch_scale = 0.85 + 0.3 * moving
