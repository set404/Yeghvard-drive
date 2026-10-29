@tool
class_name Junction
extends Node3D
## A crossroads laid out by hand over the baked roads: its traffic lights
## (TrafficLight children, world/traffic_light.gd) switched in turn, plain
## asphalt over the middle where the roads' own lane lines cross each other,
## and a sidewalk round a corner that has been moved back.
##
## Points are in this node's space, on the flat (x, z); put the node in the
## middle of the junction at the road's height. Once the game runs, the asphalt
## and the sidewalk follow the ground under them; in the editor they are drawn
## flat at the node's height.

## Seconds each way has green, then yellow, then red both ways before the other's green.
@export var green_time := 16.0
@export var yellow_time := 3.0
@export var clear_time := 3.0
## Asphalt without lane lines over the middle of the junction, a polygon. It
## also covers ground where the road now reaches round a moved corner.
@export var plain_area := PackedVector2Array():
	set(value):
		plain_area = value
		_queue_build()
## A sidewalk built along this line, its kerb on the line and the walkway on
## the right of it going from the first point to the last.
@export var corner_kerb := PackedVector2Array():
	set(value):
		corner_kerb = value
		_queue_build()
@export var corner_width := 2.2
## The sidewalks' mesh, for its paving and kerb materials.
@export var sidewalk_mesh := NodePath("../../Sidewalks/Mesh")

## As tools/build_sidewalks.gd: the walkway's height over the road, the paving's size.
const KERB := 0.15
const PAVER_SIZE := Vector2(2.4, 1.67)
## Points on the asphalt are this far apart at most, so it can follow the road's slopes.
const GRID := 1.5
## The lights it switches (not by class_name: that needs the editor to have seen the script).
const Light := preload("res://world/traffic_light.gd")

var _time := 0.0
var _queued := false
var _ground := {} ## Vector2 (local) -> height (local), once the game runs


func _ready() -> void:
	_build()
	_switch()
	if not Engine.is_editor_hint():
		_follow_ground.call_deferred()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_time += delta
	_switch()


## Sets every light from where the cycle is: group 0 green, yellow, all red,
## then group 1 green, yellow, all red.
func _switch() -> void:
	var half := green_time + yellow_time + clear_time
	var t := fmod(_time, half * 2.0)
	var turn := 0 if t < half else 1
	var into := t - turn * half
	for light in get_children():
		if light.get_script() != Light:
			continue
		var state: int = Light.RED
		if light.group == turn:
			if into < green_time:
				state = Light.GREEN
			elif into < green_time + yellow_time:
				state = Light.YELLOW
		if light.state != state or Engine.is_editor_hint():
			light.show_state(state)


func _queue_build() -> void:
	if _queued or not is_inside_tree():
		return
	_queued = true
	_build.call_deferred()


func _build() -> void:
	_queued = false
	if not is_inside_tree():
		return
	for child in get_children(true):
		if child.get_meta("junction", false):
			child.free()
	if plain_area.size() >= 3:
		_add(_asphalt())
	if corner_kerb.size() >= 2:
		_add(_sidewalk())


func _add(node: Node3D) -> void:
	node.set_meta("junction", true)
	add_child(node, false, Node.INTERNAL_MODE_FRONT)


func _height(p: Vector2) -> float:
	return _ground.get(p.snapped(Vector2(0.01, 0.01)), 0.0)


# --- the asphalt -----------------------------------------------------------------

## Points over the polygon (its corners, its edges and a grid inside it), so the
## asphalt bends with the road.
func _asphalt_points() -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := plain_area.size()
	for i in n:
		var a := plain_area[i]
		var b := plain_area[(i + 1) % n]
		var steps := maxi(ceili(a.distance_to(b) / GRID), 1)
		for k in steps:
			pts.append(a.lerp(b, float(k) / steps))
	var lo := plain_area[0]
	var hi := plain_area[0]
	for p in plain_area:
		lo = lo.min(p)
		hi = hi.max(p)
	var x := lo.x + GRID * 0.5
	while x < hi.x:
		var z := lo.y + GRID * 0.5
		while z < hi.y:
			var p := Vector2(x, z)
			if Geometry2D.is_point_in_polygon(p, plain_area) and _edge_distance(p) > GRID * 0.4:
				pts.append(p)
			z += GRID
		x += GRID
	return pts


func _edge_distance(p: Vector2) -> float:
	var best := INF
	for i in plain_area.size():
		var c := Geometry2D.get_closest_point_to_segment(p, plain_area[i], plain_area[(i + 1) % plain_area.size()])
		best = minf(best, c.distance_to(p))
	return best


func _asphalt() -> MeshInstance3D:
	var pts := _asphalt_points()
	var tris := Geometry2D.triangulate_delaunay(pts)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://world/shaders/road_paint.gdshader")
	mat.set_shader_parameter("asphalt", true)
	mat.set_shader_parameter("layer", 1.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat)
	st.set_normal(Vector3.UP)
	for t in range(0, tris.size(), 3):
		var a := pts[tris[t]]
		var b := pts[tris[t + 1]]
		var c := pts[tris[t + 2]]
		# Delaunay fills the hull; keep only what is inside the polygon.
		if not Geometry2D.is_point_in_polygon((a + b + c) / 3.0, plain_area):
			continue
		for p in [a, b, c]:
			st.add_vertex(Vector3(p.x, _height(p) + 0.03, p.y))
	var mi := MeshInstance3D.new()
	mi.name = "Asphalt"
	mi.mesh = st.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# --- the corner's sidewalk -------------------------------------------------------

## The kerb line smoothed into a curve, a point about every metre.
func _kerb_points() -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in corner_kerb.size() - 1:
		var a := corner_kerb[i]
		var b := corner_kerb[i + 1]
		var steps := maxi(ceili(a.distance_to(b)), 1)
		for k in steps:
			pts.append(a.lerp(b, float(k) / steps))
	pts.append(corner_kerb[corner_kerb.size() - 1])
	return pts


func _sidewalk() -> StaticBody3D:
	var kerb := _kerb_points()
	var n := kerb.size()
	var rows := []
	for i in n:
		var dir := (kerb[mini(i + 1, n - 1)] - kerb[maxi(i - 1, 0)]).normalized()
		var right := Vector2(-dir.y, dir.x)
		var a := kerb[i]
		var b := a + right * corner_width
		var road_y := _height(a) + 0.04
		var top_y := maxf(road_y + KERB, _height(b) + 0.03)
		rows.append([Vector3(a.x, road_y - 0.05, a.y), Vector3(a.x, top_y, a.y), Vector3(b.x, top_y, b.y),
			Vector3(b.x, _height(b) - 0.05, b.y)])
	var paving: Material = null
	var concrete: Material = null
	var walks := get_node_or_null(sidewalk_mesh) as MeshInstance3D
	if walks and walks.mesh and walks.mesh.get_surface_count() >= 2:
		paving = walks.mesh.surface_get_material(0)
		concrete = walks.mesh.surface_get_material(1)
	var tops := SurfaceTool.new()
	tops.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := SurfaceTool.new()
	sides.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var kerb_col := Color(0.78, 0.77, 0.74).srgb_to_linear()
	var side_col := Color(0.58, 0.56, 0.52).srgb_to_linear()
	var along := 0.0
	for k in n - 1:
		var r0: Array = rows[k]
		var r1: Array = rows[k + 1]
		var step := Vector2(r1[1].x - r0[1].x, r1[1].z - r0[1].z).length()
		var u0 := along / PAVER_SIZE.x
		var u1 := (along + step) / PAVER_SIZE.x
		var w := corner_width / PAVER_SIZE.y
		along += step
		_quad(sides, faces, r0[0], r0[1], r1[1], r1[0], kerb_col) # kerb face
		_quad(tops, faces, r0[1], r0[2], r1[2], r1[1], Color.WHITE,
			[Vector2(u0, 0.0), Vector2(u0, w), Vector2(u1, w), Vector2(u1, 0.0)]) # walkway
		_quad(sides, faces, r0[2], r0[3], r1[3], r1[2], side_col) # back, down to the ground
	for end in [[rows[0], rows[1]], [rows[n - 1], rows[n - 2]]]:
		var r: Array = end[0]
		_quad(sides, faces, r[0], r[1], r[2], r[3], side_col)
	var mesh := tops.commit()
	sides.commit(mesh)
	if paving:
		mesh.surface_set_material(0, paving)
	if concrete:
		mesh.surface_set_material(1, concrete)
	var body := StaticBody3D.new()
	body.name = "Sidewalk"
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	body.add_child(mi)
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	return body


## A quad a b c d into `st` and the collision faces. With uvs it is the walkway,
## facing up; without, an upright face, drawn on both sides.
func _quad(st: SurfaceTool, faces: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		col: Color, uvs := []) -> void:
	var vs := [a, b, c, d]
	var windings := []
	if uvs.is_empty():
		windings = [[0, 1, 2, 0, 2, 3], [0, 2, 1, 0, 3, 2]]
	else:
		# Godot's front faces wind clockwise; seen from above that is this sign.
		var turn := (b.x - a.x) * (c.z - a.z) - (b.z - a.z) * (c.x - a.x)
		windings = [[0, 1, 2, 0, 2, 3] if turn > 0.0 else [0, 2, 1, 0, 3, 2]]
	st.set_color(col)
	for w: Array in windings:
		var p0: Vector3 = vs[w[0]]
		var normal: Vector3 = -(vs[w[1]] - p0).cross(vs[w[2]] - p0).normalized()
		for k: int in w:
			st.set_normal(normal)
			if not uvs.is_empty():
				st.set_uv(uvs[k])
			st.add_vertex(vs[k])
	for k: int in windings[0]:
		faces.append(vs[k])


# --- following the ground --------------------------------------------------------

## In the game: the heights of every point under the asphalt and the sidewalk,
## then everything built again on them.
func _follow_ground() -> void:
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	var skip: Array[RID] = []
	for car: CollisionObject3D in get_tree().get_nodes_in_group("cars"):
		skip.append(car.get_rid())
	for child in get_children(true):
		if child is CollisionObject3D:
			skip.append(child.get_rid())
		for body: CollisionObject3D in child.find_children("*", "CollisionObject3D", true, false):
			skip.append(body.get_rid())
	var points := Array(_asphalt_points()) if plain_area.size() >= 3 else []
	if corner_kerb.size() >= 2:
		var kerb := _kerb_points()
		for i in kerb.size():
			var dir := (kerb[mini(i + 1, kerb.size() - 1)] - kerb[maxi(i - 1, 0)]).normalized()
			points.append(kerb[i])
			points.append(kerb[i] + Vector2(-dir.y, dir.x) * corner_width)
	for p: Vector2 in points:
		var at := to_global(Vector3(p.x, 0.0, p.y))
		var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 3.0, at + Vector3.DOWN * 3.0)
		ray.collision_mask = 1
		ray.exclude = skip
		var hit := space.intersect_ray(ray)
		if hit:
			_ground[p.snapped(Vector2(0.01, 0.01))] = to_local(hit["position"]).y
	_build()
