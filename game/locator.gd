extends CanvasLayer
## F3: where you are and what you are looking at, copied to the clipboard and
## shown for a few seconds at the bottom of the screen, so you can paste it
## when asking for a change to the map. Works on foot, in a car and in the map
## editor (F2, where the game is paused): there "looking at" is the spot under
## the mouse, elsewhere the middle of the screen.

const KEY := KEY_F3
## How far (metres) the look ray reaches.
const REACH := 1000.0
const SHOW_SECONDS := 6.0

@onready var _main: Node3D = get_parent()
var _label: Label
var _left := 0.0


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
	_label.offset_top = -90.0
	_label.offset_bottom = -50.0
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
	if key == null or not key.pressed or key.echo or key.physical_keycode != KEY:
		return
	get_viewport().set_input_as_handled()
	var text := describe()
	DisplayServer.clipboard_set(text)
	_label.text = text + "   (copied)"
	_left = SHOW_SECONDS
	_label.visible = true
	print(text)


## "you (812.3, 9.1, 545.0), looking at (820.4, 8.2, 551.7) on Fences, 10 m away"
func describe() -> String:
	var camera := get_viewport().get_camera_3d()
	var editing := get_tree().paused
	var you: Vector3
	if editing and camera:
		you = camera.global_position
	elif _main.get("on_foot"):
		you = (_main.get("player") as Node3D).global_position
	else:
		you = (_main.get("car") as Node3D).global_position
	var text := "you %s" % _v(you)
	if camera == null:
		return text
	var screen := get_viewport().get_visible_rect().size * 0.5
	if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		screen = get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(screen)
	var ray := PhysicsRayQueryParameters3D.create(from, from + camera.project_ray_normal(screen) * REACH)
	# Not you, nor the car you sit in.
	var exclude: Array[RID] = []
	for body: Node in [_main.get("player"), _main.get("car")]:
		if body is CollisionObject3D and not editing:
			exclude.append((body as CollisionObject3D).get_rid())
	ray.exclude = exclude
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():
		return text + ", looking at the sky"
	var at: Vector3 = hit["position"]
	var what: Node = hit["collider"]
	return text + ", looking at %s on %s, %.0f m away" % [_v(at), _name_of(what), from.distance_to(at)]


static func _v(p: Vector3) -> String:
	return "(%.1f, %.1f, %.1f)" % [p.x, p.y, p.z]


## The hit thing's name, with the scene's own nodes named from the root down
## (World/Fences, House/Body) rather than the full /root/Main/... path.
func _name_of(node: Node) -> String:
	if node.is_in_group("cars"):
		return "a car (%s)" % node.name
	if _main.is_ancestor_of(node):
		return String(_main.get_path_to(node))
	return String(node.name)
