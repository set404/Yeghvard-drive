extends CharacterBody3D
## The driver on foot. W/S/A/D or the arrows walk (relative to the camera),
## Shift runs, Space jumps. main.gd hides this while a car is being driven and
## stands it beside the driver's door when you get out (E).
##
## The figure is built from simple shapes in code, so there is no model to
## import. Like the cars, it faces its local +Z.

@export var walk_speed := 3.0 ## m/s
@export var run_speed := 7.0 ## m/s
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
