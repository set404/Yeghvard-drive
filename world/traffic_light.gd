@tool
class_name TrafficLight
extends Node3D
## A traffic light on its pole, with the white stop line across the lanes it
## holds back. A Junction (world/junction.gd) above it switches it; the
## traffic (world/traffic.gd) stops at its line on red, and on yellow when
## there is room to.
##
## To add one: put a TrafficLight node under a Junction, on the kerb to the
## right of the lanes coming in, its -Z (the way the lamps face) towards the
## cars. The stop line runs from `kerb_gap` to the right of the pole, as the
## cars see it, `stop_width` across their lanes, `stop_back` metres before it.

## Which of the junction's two ways it belongs to: 0 and 1 have green in turn.
@export_range(0, 1) var group := 0:
	set(value):
		group = value
		if is_inside_tree():
			_build()
@export var stop_width := 7.0:
	set(value):
		stop_width = maxf(value, 0.5)
		_build()
@export var stop_back := 1.0:
	set(value):
		stop_back = value
		_build()
@export var kerb_gap := 0.6:
	set(value):
		kerb_gap = value
		_build()

enum { RED, YELLOW, GREEN }

const POLE_HEIGHT := 2.5
## The stop line, across the road and along it (metres).
const LINE_WIDTH := 0.4
## How hard a driver will brake (m/s²) to stop for a yellow; otherwise on through.
const YELLOW_BRAKE := 4.0

var state := RED
var _lamps: Array[MeshInstance3D] = []
var _line: MeshInstance3D
var _line_heights := {}


func _enter_tree() -> void:
	add_to_group("traffic_lights")


func _ready() -> void:
	_build()
	if not Engine.is_editor_hint():
		_follow_road.call_deferred()


## Shows red, yellow or green.
func show_state(value: int) -> void:
	state = value
	for i in _lamps.size():
		var on := (i == 0 and state == RED) or (i == 1 and state == YELLOW) or (i == 2 and state == GREEN)
		var mat := _lamps[i].material_override as StandardMaterial3D
		mat.emission_enabled = on
		mat.albedo_color = _lamp_color(i) if on else _lamp_color(i).darkened(0.8)


## Whether a car `gap` metres before the stop line going `speed` m/s has to stop.
func must_stop(gap: float, speed: float) -> bool:
	if state == GREEN:
		return false
	if state == YELLOW:
		return gap > speed * speed / (2.0 * YELLOW_BRAKE)
	return true


## The stop line's two ends, kerb first (world space).
func stop_line() -> PackedVector3Array:
	return PackedVector3Array([to_global(Vector3(kerb_gap, 0.0, -stop_back)),
		to_global(Vector3(kerb_gap + stop_width, 0.0, -stop_back))])


static func _lamp_color(i: int) -> Color:
	return [Color(1.0, 0.12, 0.08), Color(1.0, 0.7, 0.05), Color(0.15, 1.0, 0.35)][i]


func _build() -> void:
	if not is_inside_tree():
		return
	for child in get_children(true):
		if child.get_meta("traffic_light", false):
			child.free()
	_lamps.clear()
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.16, 0.17, 0.18)
	metal.roughness = 0.6
	metal.metallic = 0.4
	var pole := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.06
	cyl.bottom_radius = 0.07
	cyl.height = POLE_HEIGHT
	cyl.material = metal
	pole.mesh = cyl
	pole.position.y = POLE_HEIGHT * 0.5
	_add(pole)
	# The head: a box with a visor over each lamp, facing -Z.
	var head := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.34, 0.95, 0.24)
	box.material = metal
	head.mesh = box
	head.position = Vector3(0.0, POLE_HEIGHT + 0.42, 0.0)
	_add(head)
	for i in 3:
		var y := POLE_HEIGHT + 0.72 - i * 0.3
		var lamp := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.1
		sphere.height = 0.2
		lamp.mesh = sphere
		var mat := StandardMaterial3D.new()
		mat.emission = _lamp_color(i)
		mat.emission_energy_multiplier = 3.0
		mat.roughness = 0.3
		lamp.material_override = mat
		lamp.position = Vector3(0.0, y, -0.1)
		lamp.scale = Vector3(1.0, 1.0, 0.5)
		lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_add(lamp)
		_lamps.append(lamp)
		var visor := MeshInstance3D.new()
		var cap := BoxMesh.new()
		cap.size = Vector3(0.26, 0.02, 0.16)
		cap.material = metal
		visor.mesh = cap
		visor.position = Vector3(0.0, y + 0.12, -0.18)
		_add(visor)
	# Something to bump into.
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var col := CylinderShape3D.new()
	col.radius = 0.08
	col.height = POLE_HEIGHT + 0.9
	shape.shape = col
	shape.position.y = col.height * 0.5
	body.add_child(shape)
	_add(body)
	_line = MeshInstance3D.new()
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add(_line)
	_draw_line()
	show_state(state)


func _add(node: Node3D) -> void:
	node.set_meta("traffic_light", true)
	add_child(node, false, Node.INTERNAL_MODE_FRONT)


## The stop line, its corners on the road under them once the game runs.
func _draw_line() -> void:
	var paint := ShaderMaterial.new()
	paint.shader = preload("res://world/shaders/road_paint.gdshader")
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(paint)
	st.set_normal(Vector3.UP)
	var x0 := kerb_gap
	var x1 := kerb_gap + stop_width
	var z0 := -stop_back - LINE_WIDTH * 0.5
	var z1 := -stop_back + LINE_WIDTH * 0.5
	var corners: Array[Vector3] = []
	for c: Vector2 in [Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)]:
		corners.append(Vector3(c.x, _line_heights.get(c, 0.0) + 0.02, c.y))
	for k: int in [0, 2, 1, 0, 3, 2]:
		st.add_vertex(corners[k])
	_line.mesh = st.commit()


func _follow_road() -> void:
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	var skip: Array[RID] = []
	for car: CollisionObject3D in get_tree().get_nodes_in_group("cars"):
		skip.append(car.get_rid())
	for body: CollisionObject3D in find_children("*", "CollisionObject3D", true, false):
		skip.append(body.get_rid())
	# The pole on the ground (or sidewalk) where it stands.
	var down := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 3.0, global_position + Vector3.DOWN * 3.0)
	down.collision_mask = 1
	down.exclude = skip
	var under := space.intersect_ray(down)
	if under:
		global_position.y = (under["position"] as Vector3).y
	var x0 := kerb_gap
	var x1 := kerb_gap + stop_width
	var z0 := -stop_back - LINE_WIDTH * 0.5
	var z1 := -stop_back + LINE_WIDTH * 0.5
	for c: Vector2 in [Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)]:
		var p := to_global(Vector3(c.x, 0.0, c.y))
		var ray := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.5, p + Vector3.DOWN * 2.0)
		ray.collision_mask = 1
		ray.exclude = skip
		var hit := space.intersect_ray(ray)
		if hit:
			_line_heights[c] = to_local(hit["position"]).y
	_draw_line()
