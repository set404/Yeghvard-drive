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
## Body colour. Only cars built with a "Paint" material (see tools/build_car.gd) use it.
@export var paint_color := Color(0.66, 0.68, 0.68)
## Where the driver's eyes are, for the cabin camera (+X left, +Y up, +Z forward).
@export var driver_view := Vector3(0.37, 1.13, 0.1)

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
@export var engine_volume_db := -6.0
@export var skid_volume_db := -10.0

const ACTIONS := {
	"accelerate": [KEY_W, KEY_UP],
	"brake": [KEY_S, KEY_DOWN],
	"steer_left": [KEY_A, KEY_LEFT],
	"steer_right": [KEY_D, KEY_RIGHT],
	"handbrake": [KEY_SPACE],
	"reset_car": [KEY_R],
}

## True while the driver is on the brake pedal (not the handbrake); the brake lights follow it.
var braking := false
## Power the engine is delivering right now, in hp.
var output_hp := 0.0
## Engine speed, for the rev counter and the engine note. There is no real
## gearbox; it is worked out from road speed as an automatic would shift.
var rpm := 800.0
var gear := 1
var _gas := 0.0
var _handbrake_on := false
var _engine_sound: AudioStreamPlayer3D
var _skid_sound: AudioStreamPlayer3D
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
	_engine_sound = _add_sound("res://audio/engine.res")
	_skid_sound = _add_sound("res://audio/skid.res")
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
	spawn_transform = xf
	global_transform = xf
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


func _physics_process(delta: float) -> void:
	var speed := forward_speed()
	# A car nobody is driving ignores the keys and holds itself on the brakes.
	var gas := Input.get_action_strength("accelerate") if player_controlled else 0.0
	var back := Input.get_action_strength("brake") if player_controlled else 0.0
	var handbrake := Input.is_action_pressed("handbrake") if player_controlled else false
	var steer_input := Input.get_axis("steer_right", "steer_left") if player_controlled else 0.0
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
		if speed > 1.0:
			brake = brake_power * back
		else:
			drive = -reverse_force * back * clampf(1.0 + speed / max_reverse_speed, 0.0, 1.0)
	braking = brake > 0.0
	if not player_controlled:
		brake = brake_power * 0.5
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


func _apply_paint() -> void:
	var body := get_node_or_null("Body") as MeshInstance3D
	if body == null:
		return
	for s in body.mesh.get_surface_count():
		var mat := body.mesh.surface_get_material(s) as BaseMaterial3D
		if mat and mat.resource_name == "Paint":
			# A copy, so that two cars sharing the model can be different colours.
			var own := mat.duplicate() as BaseMaterial3D
			own.albedo_color = paint_color
			body.set_surface_override_material(s, own)


## A looping sound that travels with the car; silent until played. Null if the
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


func _process(delta: float) -> void:
	var kmh := absf(forward_speed()) * 3.6
	gear = gear_top_speeds.size()
	for i in gear_top_speeds.size():
		if kmh < gear_top_speeds[i] * 0.93:
			gear = i + 1
			break
	var wanted := maxf(idle_rpm, kmh / gear_top_speeds[gear - 1] * redline_rpm)
	if engine_force != 0.0:
		# Pulling away, the engine revs before the car has picked up speed.
		wanted = maxf(wanted, 2400.0)
	rpm = lerpf(rpm, wanted, 1.0 - exp(-6.0 * delta))

	if _engine_sound:
		# The engine only runs in the car being driven. The recording is at
		# 1500 rpm, so its speed follows the revs; it is louder under load.
		if player_controlled != _engine_sound.playing:
			_engine_sound.playing = player_controlled
		_engine_sound.pitch_scale = clampf(rpm / 1500.0, 0.4, 4.5)
		var effort := clampf(_gas * 0.6 + output_hp / horsepower * 0.4, 0.0, 1.0)
		_engine_sound.volume_db = engine_volume_db + lerpf(-12.0, 0.0, effort)

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
