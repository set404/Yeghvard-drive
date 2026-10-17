extends CharacterBody3D
## The driver on foot. W/S/A/D or the arrows walk (relative to the camera),
## Shift runs, Space jumps. main.gd hides this while a car is being driven and
## stands it beside the driver's door when you get out (E).
##
## The figure is the Mixamo character in player/character.scn (built by
## tools/build_character.gd), with his idle, walk, run and jump; without that
## scene it is built from simple shapes in code. Like the cars, it faces its
## local +Z.

## Walking and running speeds, close to the pace of the character's own walk
## and run, so his feet keep to the ground.
@export var walk_speed := 1.8 ## m/s
@export var run_speed := 6.0 ## m/s
@export var jump_speed := 4.0 ## m/s upwards; about 0.8 m high
@export var acceleration := 30.0 ## m/s² on the ground; much less in the air
@export var turn_speed := 12.0
## How tall you are, in metres; the figure and its collision capsule follow it.
@export var height := 1.68

@export_group("Looks")
@export var shirt_color := Color(0.62, 0.12, 0.1)
@export var trousers_color := Color(0.12, 0.15, 0.24)
@export var skin_color := Color(0.86, 0.67, 0.53)
@export var hair_color := Color(0.1, 0.07, 0.05)
@export var shoe_color := Color(0.08, 0.08, 0.08)

## How the chase camera frames someone on foot (it reads these by name).
var chase_distance := 4.0
var chase_height := 1.5

## True while you are walking around, false while you sit in a car. Same name
## as the cars' flag, so the garage gates treat a driver and a walker alike.
var player_controlled := false

const ACTIONS := {
	"walk_forward": [KEY_W, KEY_UP],
	"walk_back": [KEY_S, KEY_DOWN],
	"walk_left": [KEY_A, KEY_LEFT],
	"walk_right": [KEY_D, KEY_RIGHT],
	"run": [KEY_SHIFT],
	"jump": [KEY_SPACE],
}

const CHARACTER_PATH := "res://player/character.scn"
## When in getting in (share of its length) his left hand takes the door handle.
const ENTER_GRAB := 0.18

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _shape: CollisionShape3D
var _leg_l: Node3D
var _leg_r: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _stride := 0.0
var _swing := 0.0
## Last place you stood on solid ground, for falling out of the world.
var _safe_spot := Vector3.ZERO
## The character's animations (null with the figure made of shapes), how fast
## his walk and run go at normal speed, and how long you have been in the air.
var _anim: AnimationPlayer
var _anim_speeds := {}
var _air_time := 0.0
## The same character seated at the wheel of the car you are driving, or null,
## the car, and where he sits in it (car space).
var _seated: Node3D
var _seated_car: Node3D
var _seat_xf := Transform3D.IDENTITY
## While getting in or out: where the copy stands lined up with the seat, how
## far below that the ground beside the car is (car space), and his hips bone.
var _door_xf := Transform3D.IDENTITY
var _door_drop := 0.0
var _hips_bone := -1
## While he stands at the door: how far to move him (car space) so his hand
## meets this car's door handle, out of the way of the door as it swings.
var _door_shift := Vector3.ZERO
## How far open the door has been pulled so far (0..1).
var _door_open := 0.0

## Getting in and out play this much faster than they came from Mixamo (five
## or six seconds each).
@export var door_speed := 1.5
## How far the driver's door swings open (degrees) as you get in and out; it
## opens on cars that have one cut out (tools/build_car_doors.gd).
@export var door_open_angle := 65.0


func _ready() -> void:
	add_to_group("walkers")
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(50.0)
	_build_figure()
	for action: String in ACTIONS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key: Key in ACTIONS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
	set_active(false)


## Shows the walker and gives it the keys, or hides it while you are in a car.
func set_active(on: bool) -> void:
	player_controlled = on
	visible = on
	_shape.disabled = not on
	velocity = Vector3.ZERO
	_swing = 0.0
	# Disabled, the body also leaves the physics world, so cars pass through where it was.
	process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED


## Stands the walker with its feet at the given point, facing along `facing`.
func place(feet: Vector3, facing: Vector3) -> void:
	var nose := facing.slide(Vector3.UP).normalized()
	if nose.is_zero_approx():
		nose = Vector3.BACK
	global_transform = Transform3D(Basis.looking_at(-nose), feet)
	velocity = Vector3.ZERO
	_safe_spot = feet


func _physics_process(delta: float) -> void:
	var input := Input.get_vector("walk_left", "walk_right", "walk_back", "walk_forward")
	# Forward is wherever the camera looks, flattened onto the ground.
	var forward := Vector3.FORWARD
	var cam := get_viewport().get_camera_3d()
	if cam:
		forward = (-cam.global_basis.z).slide(Vector3.UP)
		if forward.length() < 0.1:
			# Looking straight down (the top view): the top of the screen is forward.
			forward = cam.global_basis.y.slide(Vector3.UP)
	forward = forward.normalized()
	var right := forward.cross(Vector3.UP)
	var wish := (right * input.x + forward * input.y).limit_length(1.0)

	var speed := run_speed if Input.is_action_pressed("run") else walk_speed
	var ground := Vector3(velocity.x, 0.0, velocity.z)
	var accel := acceleration if is_on_floor() else acceleration * 0.2
	ground = ground.move_toward(wish * speed, accel * delta)
	velocity.x = ground.x
	velocity.z = ground.z
	if is_on_floor():
		_safe_spot = global_position
		if Input.is_action_just_pressed("jump"):
			velocity.y = jump_speed
			if _anim and _anim.has_animation("jump"):
				# Past the crouch: the jump starts as he leaves the ground.
				_anim.play("jump", 0.08)
				_anim.seek(0.3, true)
	else:
		velocity.y -= _gravity * delta
	move_and_slide()

	if wish.length() > 0.05:
		rotation.y = lerp_angle(rotation.y, atan2(wish.x, wish.z), 1.0 - exp(-turn_speed * delta))

	if global_position.y < -500.0:
		place(_safe_spot + Vector3.UP * 2.0, global_basis.z)

	_animate(delta)


## Swings the arms and legs in step with how fast you are going.
func _animate(delta: float) -> void:
	if _anim:
		_animate_character(delta)
		return
	var ground_speed := Vector2(velocity.x, velocity.z).length()
	# About one full stride (two steps) every 1.5 m.
	_stride = fmod(_stride + ground_speed * delta * TAU / 1.5, TAU)
	var wanted := clampf(ground_speed / run_speed, 0.0, 1.0) * 0.9
	if ground_speed > 0.2:
		wanted = maxf(wanted, 0.35)
	_swing = lerpf(_swing, wanted, 1.0 - exp(-10.0 * delta))
	var s := sin(_stride) * _swing
	if is_on_floor():
		_leg_l.rotation.x = s
		_leg_r.rotation.x = -s
	else:
		# In the air: one knee up, arms out a little.
		_leg_l.rotation.x = lerpf(_leg_l.rotation.x, -0.5, 1.0 - exp(-8.0 * delta))
		_leg_r.rotation.x = lerpf(_leg_r.rotation.x, 0.2, 1.0 - exp(-8.0 * delta))
	_arm_l.rotation.x = -s * 0.9
	_arm_r.rotation.x = s * 0.9
	_arm_l.rotation.z = 0.06 + _swing * 0.08
	_arm_r.rotation.z = -_arm_l.rotation.z


## Seats a copy of the character at the wheel of `car`, playing his driving
## animation: his hands on the steering wheel where the car has one (a node
## named SteeringWheel), otherwise his eyes where the car's driver_view says.
## With `entering`, he first gets in from beside the driver's door; returns how
## many seconds that takes (0 when he is straight away at the wheel).
func sit_in(car: Node3D, entering := false) -> float:
	stand_up()
	if not ResourceLoader.exists(CHARACTER_PATH):
		return 0.0
	var driver: Node3D = (load(CHARACTER_PATH) as PackedScene).instantiate()
	var anim := driver.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if anim == null or not anim.has_animation("drive") or not driver.has_meta("drive_eyes"):
		driver.free()
		return 0.0
	driver.name = "Driver"
	var s: float = height / float(driver.get_meta("height", 1.8))
	var eyes: Vector3 = driver.get_meta("drive_eyes")
	var hands: Vector3 = driver.get_meta("drive_hands", eyes)
	# His eyes where the car's in-car camera is (driver_view), a little forward
	# of it; where the car has a steering wheel, forward again until his hands
	# are on it (by up to 15 cm).
	var view: Variant = car.get("driver_view")
	var eye_point: Vector3 = view if view is Vector3 else Vector3(0.37, 1.13, 0.1)
	var at := eye_point + Vector3(0.0, 0.0, 0.05) - eyes * s
	var wheel := car.find_child("SteeringWheel", true, false) as Node3D
	if wheel and wheel.is_inside_tree():
		var short := car.to_local(wheel.global_position).z - (at + hands * s).z
		at.z += clampf(short, 0.0, 0.15)
	_seat_xf = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * s), at)
	driver.transform = _seat_xf
	car.add_child(driver)
	_seated = driver
	_seated_car = car
	anim.animation_finished.connect(_on_seated_animation_finished)
	if entering and anim.has_animation("enter") and driver.has_meta("enter_hips_end"):
		_begin_door("enter", "end")
		anim.speed_scale = door_speed
		anim.play("enter")
		return anim.get_animation("enter").length / door_speed
	anim.play("drive")
	return 0.0


## The car he is sitting in (or getting into or out of), or null.
func seated_in() -> Node3D:
	return _seated_car if _seated and is_instance_valid(_seated) else null


## Starts him getting out of the car; returns how many seconds that takes (0
## when there is no animation for it).
func get_out() -> float:
	if seated_in() == null:
		return 0.0
	var anim := _seated.get_node("AnimationPlayer") as AnimationPlayer
	if not anim.has_animation("exit") or not _seated.has_meta("exit_hips_start"):
		return 0.0
	_begin_door("exit", "start")
	anim.speed_scale = door_speed
	anim.play("exit")
	return anim.get_animation("exit").length / door_speed


## Where getting out leaves him: {"feet": world position, "facing": direction}.
## Empty when he is not getting out.
func exit_spot() -> Dictionary:
	if seated_in() == null or not _seated.has_meta("exit_hips_end"):
		return {}
	var hips: Vector3 = _seated.get_meta("exit_hips_end")
	var facing: Vector2 = _seated.get_meta("exit_facing_end")
	var xf := _seated.global_transform
	return {"feet": xf * Vector3(hips.x, 0.0, hips.z), "facing": (xf.basis * Vector3(facing.x, 0.0, facing.y)).normalized()}


## Where to put the seated copy for getting in or out, so that his hips meet
## the driver's at the seated `end` of that animation, turned to face the same way.
func _path_xf(anim_name: String, end: String) -> Transform3D:
	var drive_hips: Vector3 = _seated.get_meta("drive_hips_start")
	var drive_facing: Vector2 = _seated.get_meta("drive_facing_start")
	var hips: Vector3 = _seated.get_meta("%s_hips_%s" % [anim_name, end])
	var facing: Vector2 = _seated.get_meta("%s_facing_%s" % [anim_name, end])
	var turn := atan2(drive_facing.x, drive_facing.y) - atan2(facing.x, facing.y)
	var s := _seat_xf.basis.get_scale().x
	var basis := Basis(Vector3.UP, turn).scaled(Vector3.ONE * s)
	return Transform3D(basis, _seat_xf * drive_hips - basis * hips)


## Getting in or out was made for a car whose seat is higher off the ground
## than ours: lined up at the seat, his feet would be under the road while he
## stands. So he stands on the ground beside the door and is lifted to the
## seat only as he sits (see update_seated).
func _begin_door(anim_name: String, end: String) -> void:
	_door_xf = _path_xf(anim_name, end)
	_door_drop = _ground_beside(_seated_car) - _door_xf.origin.y
	_door_shift = _shift_to_handle()
	_door_open = 0.0
	var skeleton := _seated.get_node("Skeleton3D") as Skeleton3D
	_hips_bone = -1
	for b in skeleton.get_bone_count():
		if skeleton.get_bone_name(b).ends_with("Hips"):
			_hips_bone = b
	_seated.transform = _door_xf
	update_seated()


## Getting in was made for another car: lined up at the seat, his hand would
## reach for the door some way off this car's handle, and he would stand where
## the door swings. This is how far to move him while he stands at the door so
## his hand meets the handle (near the door's back edge, just outside it).
func _shift_to_handle() -> Vector3:
	var door := _seated_car.get_node_or_null("DriverDoor") as Node3D
	var mesh := door.get_node_or_null("Mesh") as MeshInstance3D if door else null
	var anim := _seated.get_node("AnimationPlayer") as AnimationPlayer
	if mesh == null or not anim.has_animation("enter"):
		return Vector3.ZERO
	var box := mesh.get_aabb()
	var handle := door.position + Vector3(0.05, 0.0, box.position.z + 0.15)
	# Where his left hand is when it takes the handle, with him lined up at the seat.
	var skeleton := _seated.get_node("Skeleton3D") as Skeleton3D
	var hand_bone := -1
	for b in skeleton.get_bone_count():
		if skeleton.get_bone_name(b).ends_with("_LeftHand"):
			hand_bone = b
	anim.play("enter")
	anim.seek(anim.get_animation("enter").length * ENTER_GRAB, true)
	var reach := _path_xf("enter", "end") * (skeleton.transform * skeleton.get_bone_global_pose(hand_bone).origin)
	anim.seek(0.0, true)
	return Vector3(handle.x - reach.x, 0.0, handle.z - reach.z)


## Height of the ground beside the driver's door, in the car's space.
func _ground_beside(car: Node3D) -> float:
	var view: Variant = car.get("driver_view")
	var side := 1.0 if not (view is Vector3) or (view as Vector3).x >= 0.0 else -1.0
	if car.is_inside_tree():
		var from := car.to_global(Vector3(side * 1.6, 2.0, 0.0))
		var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 6.0)
		var skip: Array[RID] = []
		for other: CollisionObject3D in get_tree().get_nodes_in_group("cars"):
			skip.append(other.get_rid())
		query.exclude = skip
		var hit := car.get_world_3d().direct_space_state.intersect_ray(query)
		if hit:
			return car.to_local(hit["position"]).y
	# No ground found: where the tyres touch it with the springs at rest.
	var lowest := INF
	for wheel: VehicleWheel3D in car.find_children("*", "VehicleWheel3D", false, false):
		lowest = minf(lowest, wheel.position.y - wheel.wheel_rest_length - wheel.wheel_radius)
	return lowest if lowest < INF else 0.0


## Keeps his feet on the ground while he stands beside the car, easing him up
## to the seat as his hips drop into it. main.gd calls this every frame.
func update_seated() -> void:
	if seated_in() == null or _hips_bone < 0:
		return
	var anim := _seated.get_node("AnimationPlayer") as AnimationPlayer
	var playing := anim.assigned_animation
	if playing != "enter" and playing != "exit":
		_swing_door(0.0)
		return
	var t := anim.current_animation_position / maxf(anim.get_animation(playing).length, 0.001)
	var skeleton := _seated.get_node("Skeleton3D") as Skeleton3D
	var standing: float = (_seated.get_meta("enter_hips_start") as Vector3).y
	var sitting: float = (_seated.get_meta("exit_hips_start") as Vector3).y
	var y := skeleton.get_bone_pose_position(_hips_bone).y
	var seated := smoothstep(0.25, 0.9, inverse_lerp(standing, sitting, y))
	var xf := _door_xf
	xf.origin.y += _door_drop * (1.0 - seated)
	# At the door he stands where this car's handle is; he moves over to the
	# seat as he climbs in (and back out as he climbs out).
	var at_door := 1.0 - smoothstep(0.35, 0.6, t) if playing == "enter" else smoothstep(0.32, 0.55, t)
	xf.origin += _door_shift * at_door
	_seated.transform = xf
	_move_door(playing, t, skeleton)


## The door follows his left hand while he pulls it open getting in (and
## swings open as he pushes it getting out), stays open, and swings shut as he
## closes it.
func _move_door(playing: String, t: float, skeleton: Skeleton3D) -> void:
	var door := _seated_car.get_node_or_null("DriverDoor") as Node3D
	if door == null:
		return
	var opening := Vector2(0.16, 0.40) if playing == "enter" else Vector2(0.06, 0.34)
	var closing := Vector2(0.80, 0.92) if playing == "enter" else Vector2(0.62, 0.80)
	if t < opening.x:
		_door_open = 0.0
	elif playing == "exit":
		# Pushed open from inside, where his hand cannot be followed.
		_door_open = maxf(_door_open, smoothstep(opening.x, opening.y * 0.8, t))
	elif t <= opening.y:
		var hand := Vector3.ZERO
		for b in skeleton.get_bone_count():
			if skeleton.get_bone_name(b).ends_with("_LeftHand"):
				hand = skeleton.global_transform * skeleton.get_bone_global_pose(b).origin
		var rel: Vector3 = _seated_car.to_local(hand) - door.position
		# The closed door runs back (-Z) from its hinge; opened by a, its back
		# edge points along (-sin a, -cos a).
		var angle := atan2(-rel.x, -rel.z)
		var open := clampf(-rad_to_deg(angle) / door_open_angle, 0.0, 1.0)
		_door_open = maxf(_door_open, open)
	var shut := 1.0 - smoothstep(closing.x, closing.y, t)
	_swing_door(_door_open * shut)

## Opens the car's driver's door this far (0 shut, 1 fully open).
func _swing_door(open: float) -> void:
	var door := _seated_car.get_node_or_null("DriverDoor") as Node3D if _seated_car else null
	if door:
		door.rotation.y = -deg_to_rad(door_open_angle) * open


func _on_seated_animation_finished(anim_name: StringName) -> void:
	if anim_name == &"enter" and _seated:
		_seated.transform = _seat_xf
		var anim := _seated.get_node("AnimationPlayer") as AnimationPlayer
		anim.speed_scale = 1.0
		anim.play("drive")
		_swing_door(0.0)


## Takes the seated copy out of the car.
func stand_up() -> void:
	if _seated and is_instance_valid(_seated):
		_seated.queue_free()
	if _seated_car and is_instance_valid(_seated_car):
		_swing_door(0.0)
	_seated = null
	_seated_car = null


func show_seated(on: bool) -> void:
	if _seated and is_instance_valid(_seated):
		_seated.visible = on


## Plays the character's idle, walk or run, at the pace you are going; the
## jump while you are in the air.
func _animate_character(delta: float) -> void:
	_air_time = 0.0 if is_on_floor() else _air_time + delta
	var ground_speed := Vector2(velocity.x, velocity.z).length()
	if not is_on_floor():
		if _air_time > 0.2 and _anim.current_animation != "jump" and _anim.has_animation("jump"):
			# Stepped off something: the airborne part of the jump.
			_anim.play("jump", 0.15)
			_anim.seek(0.5, true)
		return
	var wanted := "idle"
	var rate := 1.0
	if ground_speed > 0.2:
		var run := ground_speed > (walk_speed + run_speed) * 0.5 and _anim.has_animation("run")
		wanted = "run" if run else "walk"
		rate = clampf(ground_speed / float(_anim_speeds.get(wanted, ground_speed)), 0.4, 1.8)
	var landing := _anim.current_animation == "jump" and _anim.current_animation_position < 0.85
	if landing and wanted == "idle":
		return
	if _anim.current_animation != wanted:
		_anim.play(wanted, 0.2)
	_anim.speed_scale = rate


# --- the figure -------------------------------------------------------------
# Modelled 1.8 m tall with its feet at the origin, then scaled to `height`.
# +X is its left, +Z its front.

func _build_figure() -> void:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = height
	_shape = CollisionShape3D.new()
	_shape.name = "CollisionShape3D"
	_shape.shape = capsule
	_shape.position = Vector3(0.0, height * 0.5, 0.0)
	add_child(_shape)

	if ResourceLoader.exists(CHARACTER_PATH):
		var character: Node3D = (load(CHARACTER_PATH) as PackedScene).instantiate()
		character.name = "Model"
		var model_height: float = character.get_meta("height", 1.8)
		character.scale = Vector3.ONE * height / model_height
		_anim_speeds = character.get_meta("speeds", {})
		add_child(character)
		_anim = character.get_node_or_null("AnimationPlayer") as AnimationPlayer
		if _anim and _anim.has_animation("idle"):
			_anim.play("idle")
		return

	var model := Node3D.new()
	model.name = "Model"
	model.scale = Vector3.ONE * height / 1.8
	add_child(model)
	var shirt := _material(shirt_color)
	var trousers := _material(trousers_color)
	var skin := _material(skin_color)
	var shoes := _material(shoe_color)

	# Body and head.
	_piece(model, _capsule(0.2, 0.62), shirt, Vector3(0.0, 1.27, 0.0), Vector3(1.0, 1.0, 0.62))
	_piece(model, _capsule(0.17, 0.3), trousers, Vector3(0.0, 0.98, 0.0), Vector3(1.0, 1.0, 0.7))
	_piece(model, _cylinder(0.05, 0.1), skin, Vector3(0.0, 1.58, 0.0))
	_piece(model, _sphere(0.115), skin, Vector3(0.0, 1.71, 0.0), Vector3(0.92, 1.0, 1.0))
	_piece(model, _sphere(0.122), _material(hair_color), Vector3(0.0, 1.745, -0.02), Vector3(0.95, 0.8, 1.0))
	var eye := _material(Color(0.05, 0.05, 0.06))
	for x in [0.04, -0.04]:
		_piece(model, _sphere(0.014), eye, Vector3(x, 1.725, 0.1))

	# Legs and arms hang from pivots at the hips and shoulders, so they can swing.
	_leg_l = _limb(model, Vector3(0.1, 0.94, 0.0))
	_leg_r = _limb(model, Vector3(-0.1, 0.94, 0.0))
	for leg in [_leg_l, _leg_r]:
		_piece(leg, _capsule(0.075, 0.88), trousers, Vector3(0.0, -0.44, 0.0))
		_piece(leg, _box(Vector3(0.11, 0.08, 0.26)), shoes, Vector3(0.0, -0.9, 0.05))
	_arm_l = _limb(model, Vector3(0.25, 1.5, 0.0))
	_arm_r = _limb(model, Vector3(-0.25, 1.5, 0.0))
	for arm in [_arm_l, _arm_r]:
		_piece(arm, _capsule(0.06, 0.58), shirt, Vector3(0.0, -0.27, 0.0))
		_piece(arm, _sphere(0.055), skin, Vector3(0.0, -0.6, 0.0))


func _limb(parent: Node3D, at: Vector3) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = at
	parent.add_child(pivot)
	return pivot


func _piece(parent: Node3D, mesh: Mesh, mat: Material, at: Vector3, scale_by := Vector3.ONE) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = at
	mi.scale = scale_by
	parent.add_child(mi)


func _material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.8
	return mat


func _capsule(radius: float, height: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = height
	m.radial_segments = 16
	m.rings = 4
	return m


func _cylinder(radius: float, height: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = height
	m.radial_segments = 12
	return m


func _sphere(radius: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = 16
	m.rings = 8
	return m


func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m
