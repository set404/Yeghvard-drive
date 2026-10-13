extends Camera3D
## Follows a car. K cycles through the views; the mouse looks around.
##
## Click in the window to grab the mouse, Esc to let it go. While it is grabbed,
## moving it orbits the camera round the car (or turns your head in the onboard
## views) and the wheel zooms the outside views. Left alone while driving, the
## camera swings back behind the car.

enum View { CHASE, FAR, BUMPER, DRIVER, TOP }

@export var target: VehicleBody3D
@export var distance := 7.5
@export var height := 3.0
@export var follow_speed := 5.0

@export_group("Other views")
## Positions in the car's own space: +X is its left, +Y up, +Z its nose.
@export var bumper_offset := Vector3(0.0, 0.65, 2.5)
@export var driver_offset := Vector3(0.37, 1.13, 0.1)
@export var top_height := 45.0
@export var chase_fov := 65.0
@export var onboard_fov := 75.0

@export_group("Mouse")
@export var mouse_sensitivity := 0.003 ## radians per pixel
@export var recentre_after := 2.5 ## seconds without mouse movement, while driving
@export var recentre_speed := 2.0

var view := View.CHASE

## Where the mouse has turned the camera, relative to straight behind / straight ahead.
var _yaw := 0.0
var _pitch := 0.0
var _zoom := 1.0
var _still := 0.0


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo:
		if key.physical_keycode == KEY_K:
			view = (view + 1) % View.size() as View
			_yaw = 0.0
			_pitch = 0.0
			snap()
		elif key.physical_keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return

	var button := event as InputEventMouseButton
	if button and button.pressed:
		if button.button_index == MOUSE_BUTTON_LEFT or button.button_index == MOUSE_BUTTON_RIGHT:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = maxf(_zoom / 1.12, 0.45)
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = minf(_zoom * 1.12, 3.0)
		return

	var motion := event as InputEventMouseMotion
	if motion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw = wrapf(_yaw - motion.relative.x * mouse_sensitivity, -PI, PI)
		_pitch -= motion.relative.y * mouse_sensitivity
		_still = 0.0


## Jumps straight to where the current view wants the camera.
func snap() -> void:
	if target:
		_update(1.0)


func _physics_process(delta: float) -> void:
	if target == null:
		return
	# Hands off the mouse and under way: ease back to the straight-ahead view.
	_still += delta
	if _still > recentre_after and target.linear_velocity.length() > 3.0:
		var ease := 1.0 - exp(-recentre_speed * delta)
		_yaw = lerp_angle(_yaw, 0.0, ease)
		_pitch = lerpf(_pitch, 0.0, ease)
	_update(1.0 - exp(-follow_speed * delta))


func _update(blend: float) -> void:
	match view:
		View.CHASE:
			_follow(distance, height, blend)
		View.FAR:
			_follow(distance * 2.2, height * 2.4, blend)
		View.BUMPER:
			_ride(bumper_offset)
		View.DRIVER:
			# Each car knows where its own driver sits.
			var eyes: Variant = target.get("driver_view")
			_ride(eyes if eyes is Vector3 else driver_offset)
		View.TOP:
			fov = chase_fov
			var nose := target.global_basis.z.slide(Vector3.UP).normalized()
			global_position = target.global_position + Vector3.UP * top_height * _zoom
			# Straight down, with the way the car is heading at the top of the screen.
			look_at(target.global_position, nose if not nose.is_zero_approx() else Vector3.FORWARD)


## Trails the car at the given distance behind and above it, easing towards its
## position. The mouse swings the camera round the car and up or down.
func _follow(back_by: float, up_by: float, blend: float) -> void:
	fov = chase_fov
	var reach := Vector2(back_by, up_by).length() * _zoom
	# Mouse up looks up, which for a camera circling the car means sinking lower.
	var tilt := clampf(atan2(up_by, back_by) - _pitch, deg_to_rad(3.0), deg_to_rad(80.0))
	# Keep the stored pitch inside what the camera can actually reach.
	_pitch = atan2(up_by, back_by) - tilt
	var back := -target.global_basis.z.slide(Vector3.UP).normalized().rotated(Vector3.UP, _yaw)
	var wanted := target.global_position + back * reach * cos(tilt) + Vector3.UP * reach * sin(tilt)
	global_position = global_position.lerp(wanted, blend)
	look_at(target.global_position + Vector3.UP * 1.2)


## Fixed to the car and looking out over its nose; the mouse turns your head.
func _ride(offset: Vector3) -> void:
	fov = onboard_fov
	_pitch = clampf(_pitch, deg_to_rad(-50.0), deg_to_rad(60.0))
	# Cameras look along -Z and the car drives towards +Z, hence the half turn.
	var head := Basis(Vector3.UP, PI + _yaw) * Basis(Vector3.RIGHT, _pitch)
	global_transform = Transform3D(target.global_basis.orthonormalized() * head, target.global_transform * offset)
