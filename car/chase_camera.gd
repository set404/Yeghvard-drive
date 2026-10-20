extends Camera3D
## Follows a car, or you on foot. K cycles through the views; the mouse looks around.
##
## Click in the window to grab the mouse, Esc to let it go. While it is grabbed,
## moving it orbits the camera round the car (or turns your head in the onboard
## views) and the wheel zooms the outside views. Left alone while driving, the
## camera swings back behind the car.
##
## On foot only the outside views are used, and the mouse turns the camera on its
## own: the walker turns to face the way you walk instead of dragging the camera round.

enum View { CHASE, FAR, BUMPER, DRIVER, TOP }

## A car, or anything else to follow (the walker sets chase_distance and chase_height).
@export var target: Node3D
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

## Where the mouse has turned the camera, relative to straight behind / straight
## ahead of a car. On foot it is measured from the world's +Z instead.
var _yaw := 0.0
var _pitch := 0.0
var _zoom := 1.0
var _still := 0.0


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo:
		if key.physical_keycode == KEY_K:
			view = _next_view(view)
			if not _on_foot():
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
		elif _on_foot() and not button.ctrl_pressed:
			# On foot the wheel picks the item in your hand (main.gd); Ctrl + wheel zooms.
			pass
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


## Starts following something else. The camera glides over unless `jump` is set.
func follow(next: Node3D, jump := false) -> void:
	target = next
	_pitch = 0.0
	_yaw = 0.0
	if _on_foot():
		# Start straight behind the walker, whichever way it faces.
		var nose := next.global_basis.z.slide(Vector3.UP).normalized()
		if not nose.is_zero_approx():
			_yaw = Vector3.BACK.signed_angle_to(nose, Vector3.UP)
		if view == View.BUMPER or view == View.DRIVER:
			view = View.CHASE
	if jump:
		snap()


## Jumps straight to where the current view wants the camera.
func snap() -> void:
	if target:
		_update(1.0)


func _on_foot() -> bool:
	return target != null and not target is VehicleBody3D


func _next_view(from: View) -> View:
	var next := (from + 1) % View.size() as View
	# Bumper and driver's seat only make sense in a car.
	while _on_foot() and (next == View.BUMPER or next == View.DRIVER):
		next = (next + 1) % View.size() as View
	return next


func _physics_process(delta: float) -> void:
	if target == null:
		return
	# Hands off the mouse and under way: ease back to the straight-ahead view.
	_still += delta
	var car := target as VehicleBody3D
	if car and _still > recentre_after and car.linear_velocity.length() > 3.0:
		var ease := 1.0 - exp(-recentre_speed * delta)
		_yaw = lerp_angle(_yaw, 0.0, ease)
		_pitch = lerpf(_pitch, 0.0, ease)
	_update(1.0 - exp(-follow_speed * delta))


func _update(blend: float) -> void:
	var near: Variant = target.get("chase_distance")
	var up: Variant = target.get("chase_height")
	var back_by: float = near if near is float else distance
	var up_by: float = up if up is float else height
	match view:
		View.CHASE:
			_follow(back_by, up_by, blend)
		View.FAR:
			_follow(back_by * 2.2, up_by * 2.4, blend)
		View.BUMPER:
			_ride(bumper_offset)
		View.DRIVER:
			# Each car knows where its own driver sits.
			var eyes: Variant = target.get("driver_view")
			_ride(eyes if eyes is Vector3 else driver_offset)
		View.TOP:
			fov = chase_fov
			var nose := _heading()
			global_position = target.global_position + Vector3.UP * top_height * _zoom
			# Straight down, with the way the car is heading at the top of the screen.
			look_at(target.global_position, nose if not nose.is_zero_approx() else Vector3.FORWARD)


## The way the camera counts as "ahead": the car's nose, or on foot the mouse's own heading.
func _heading() -> Vector3:
	if _on_foot():
		return Vector3.BACK.rotated(Vector3.UP, _yaw)
	return target.global_basis.z.slide(Vector3.UP).normalized()


## Trails the target at the given distance behind and above it, easing towards
## its position. The mouse swings the camera round it and up or down.
func _follow(back_by: float, up_by: float, blend: float) -> void:
	fov = chase_fov
	var reach := Vector2(back_by, up_by).length() * _zoom
	# Mouse up looks up, which for a camera circling the car means sinking lower.
	var tilt := clampf(atan2(up_by, back_by) - _pitch, deg_to_rad(3.0), deg_to_rad(80.0))
	# Keep the stored pitch inside what the camera can actually reach.
	_pitch = atan2(up_by, back_by) - tilt
	var back := -_heading() if _on_foot() else -_heading().rotated(Vector3.UP, _yaw)
	var wanted := target.global_position + back * reach * cos(tilt) + Vector3.UP * reach * sin(tilt)
	var pivot := target.global_position + Vector3.UP * 1.2
	# Never behind a wall (indoors that is most of the time). The spot the camera
	# heads for is pulled in front of whatever is in the way, so it stays put and
	# the camera settles there instead of being pushed back and forth.
	wanted = _clear_of_walls(pivot, wanted)
	global_position = _clear_of_walls(pivot, global_position.lerp(wanted, blend))
	if global_position.distance_to(pivot) > 0.05:
		look_at(pivot)


## The point on the way from `pivot` to `to` just short of the first thing in
## the way (other than the target itself), or `to` if nothing is.
func _clear_of_walls(pivot: Vector3, to: Vector3) -> Vector3:
	# A little past `to`, so the camera never sits right against a wall.
	var margin := 0.3
	var reach := (to - pivot).normalized() * margin
	var query := PhysicsRayQueryParameters3D.create(pivot, to + reach)
	var body := target as CollisionObject3D
	if body:
		var skip: Array[RID] = [body.get_rid()]
		query.exclude = skip
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return to
	var at: Vector3 = hit["position"]
	return at + (pivot - at).limit_length(margin)


## Fixed to the car and looking out over its nose; the mouse turns your head.
func _ride(offset: Vector3) -> void:
	fov = onboard_fov
	_pitch = clampf(_pitch, deg_to_rad(-50.0), deg_to_rad(60.0))
	# Cameras look along -Z and the car drives towards +Z, hence the half turn.
	var head := Basis(Vector3.UP, PI + _yaw) * Basis(Vector3.RIGHT, _pitch)
	global_transform = Transform3D(target.global_basis.orthonormalized() * head, target.global_transform * offset)
