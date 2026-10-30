extends CanvasLayer
## For testing: moves you about the map, on foot or in the car you drive.
## F4 puts you at the spot you are looking at (the middle of the screen, or the
## spot under the mouse while it shows, as in the map editor, F2).
## F5 jumps to the next named place (the house, the taxi stops, the gun dealer,
## the spawn on the road); Shift+F5 to the one before.

const KEY_HERE := KEY_F4
const KEY_PLACES := KEY_F5
## How far (metres) the look ray reaches.
const REACH := 2000.0
const SHOW_SECONDS := 3.0

@onready var _main: Node3D = get_parent()
var _label: Label
var _left := 0.0
## The place F5 jumped to last, in _places().
var _place := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	_label = Label.new()
	_label.anchor_left = 0.5
	_label.anchor_right = 0.5
	_label.anchor_top = 1.0
	_label.anchor_bottom = 1.0
	_label.offset_left = -500.0
	_label.offset_right = 500.0
	_label.offset_top = -130.0
	_label.offset_bottom = -95.0
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_constant_override("outline_size", 6)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.visible = false
	add_child(_label)


func _process(delta: float) -> void:
	if _left > 0.0:
		_left -= delta
		_label.visible = _left > 0.0


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_HERE:
		get_viewport().set_input_as_handled()
		var at: Variant = _looked_at()
		if at is Vector3:
			_go(at, "there")
		else:
			_show("Nothing to stand on there")
	elif key.physical_keycode == KEY_PLACES:
		get_viewport().set_input_as_handled()
		var places := _places()
		if places.is_empty():
			return
		_place = posmod(_place + (-1 if key.shift_pressed else 1), places.size())
		var place: Array = places[_place]
		_go(place[1], "%s  (%d/%d)" % [place[0], _place + 1, places.size()])


## [name, feet position] for every place F5 goes to.
func _places() -> Array:
	var places := []
	var door: Variant = _main.call("front_door_outside", 1.8)
	if door is Vector3:
		places.append(["the house", door])
	for stop: Node3D in get_tree().get_nodes_in_group("taxi_stops"):
		places.append([str(stop.get_meta("place", stop.name)), stop.global_position])
	var dealer := _main.get_node_or_null("GunDealer") as Node3D
	if dealer:
		# A couple of metres in front of the counter, not inside it.
		places.append(["the gun dealer", dealer.global_position + dealer.global_basis.z * 2.5])
	var spawn := _main.get_node_or_null("World/Spawn") as Node3D
	if spawn:
		places.append(["the spawn on the road", spawn.global_position])
	return places


## The ground under the middle of the screen (or the mouse), or null.
func _looked_at() -> Variant:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null
	var screen := get_viewport().get_visible_rect().size * 0.5
	if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		screen = get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(screen)
	var ray := PhysicsRayQueryParameters3D.create(from, from + camera.project_ray_normal(screen) * REACH)
	ray.exclude = _bodies()
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():
		return null
	# Off a wall a little, so you land at its foot rather than in it.
	return hit["position"] + (hit["normal"] as Vector3) * 0.6


## Moves you (or the car you drive) to `at`, set down on the ground there.
func _go(at: Vector3, where: String) -> void:
	var camera: Camera3D = _main.get("camera")
	var facing := -camera.global_basis.z if camera else Vector3.FORWARD
	if _main.get("on_foot"):
		var player: Node3D = _main.get("player")
		player.call("place", _ground(at) + Vector3.UP * 0.1, facing)
		if camera:
			camera.call("follow", player, true)
	else:
		var car: VehicleBody3D = _main.get("car")
		var nose := facing.slide(Vector3.UP).normalized()
		if nose.is_zero_approx():
			nose = car.global_basis.z
		# Cars drive towards their +Z.
		car.place(Transform3D(Basis.looking_at(-nose), at))
		_main.call("_set_on_ground", car)
		if camera:
			camera.call("follow", car, true)
	_show("Teleported to %s" % where)


## The ground below a point (from a little above it), or the point itself.
func _ground(at: Vector3) -> Vector3:
	var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 1.5, at + Vector3.DOWN * 400.0)
	ray.exclude = _bodies()
	var hit := _main.get_world_3d().direct_space_state.intersect_ray(ray)
	return hit["position"] if hit else at


## You and the car you sit in, which the rays look past.
func _bodies() -> Array[RID]:
	var bodies: Array[RID] = []
	for body: Variant in [_main.get("player"), _main.get("car")]:
		if body is CollisionObject3D:
			bodies.append((body as CollisionObject3D).get_rid())
	return bodies


func _show(text: String) -> void:
	_label.text = text
	_left = SHOW_SECONDS
	_label.visible = true
	print(text)
