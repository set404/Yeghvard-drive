extends SceneTree
## Builds res://world/house.scn: the two-storey pink tuff house with the garage
## where the game starts (OpenStreetMap building 293496245). The ground floor is
## laid out room by room with doors that open as you walk up to them; a
## staircase leads to the upper floor, which is still one open room. A stone
## wall closes in the yard at the side and back, with a gate onto the road.
##
## It also takes the plain box that tools/build_world.gd used to put there out
## of res://world/yeghvard.scn (newer builds of the world leave the gap; see
## "replaced" in its BUILDING_FIXES), so run it again after rebuilding the world.
##
## Run:  godot --path . --script res://tools/build_house.gd
## (not --headless: saving the world scene headless would drop its trees)
##
## Plan coordinates: u metres along the front wall from its left end, as seen
## from the street, and v metres from the front wall towards the back. In the
## house scene the ground-floor floor is y = 0, +X runs along u and +Z points out
## of the front wall, so the plan point (u, v) is at (u, y, -v).

const WORLD_PATH := "res://world/yeghvard.scn"
const OUT_PATH := "res://world/house.scn"

## Corners of the building in world metres (x, z), from its OpenStreetMap outline.
const FRONT_LEFT := Vector2(653.125, 552.928)
const FRONT_RIGHT := Vector2(662.713, 542.534)
const BACK_LEFT := Vector2(645.774, 546.143)

# Heights above the ground-floor floor, in metres.
const CEILING := 2.8 ## of the ground floor
const UPPER := 3.0 ## the upper floor
const UPPER_CEILING := 5.8
const ROOF := 6.0
const PARAPET := 6.4

const OUTER := 0.35 ## outside wall thickness
const INNER := 0.12 ## partition thickness

const DOOR_HEIGHT := 2.1
const GATE_HEIGHT := 2.3
const TRANSOM_HEIGHT := 0.5
const GARAGE_RAMP := 1.6 ## how far the ramp reaches out from the garage door

## Ground-floor and upper-floor windows: bottom and top.
const WINDOW_LOW := Vector2(0.9, 2.3)
const WINDOW_HIGH := Vector2(UPPER + 0.9, UPPER + 2.3)

# The staircase in the back-left corner of the hall: two flights side by side
# with a landing against the back wall. 16 risers of 18.75 cm, treads of 25 cm.
const STAIR_FRONT := 7.0 ## v where both flights end at the front
const STAIR_SPLIT := 1.45 ## u of the middle of the wall between the flights
const STAIR_RIGHT := 2.55 ## u of the right-hand side of the staircase
const STEPS := 8 ## risers per flight
const TREAD := 0.25

# --- the plan -----------------------------------------------------------------
# Drawn from the owner's sketch of the ground floor; the sketch is not to scale,
# so the rooms are stretched to the real outline. L and W are the length of the
# front wall and the depth of the house, worked out from the corners above.

## The wall between the front rooms and the back ones (v of its middle).
const SPLIT := 5.6
## u of the middle of the wall between the middle front room and the garage, and
## between the big back room and the back-right room.
const GARAGE_WALL := 10.5
## The bathroom in the back corner of the big room, next to the stair hall.
const BATH := Rect2(3.31, 6.9, 1.6, 0.0) ## u, v of its front-left corner and width; it runs to the back wall

# The yard wall: tuff, 2 m high, on the left side between the house and the
# road and round the back. Left side u, depth of the back yard, the gate (v range).
const YARD_LEFT := -2.6
const YARD_DEPTH := 30.0
const YARD_GATE := Vector2(11.0, 15.0)
const FENCE_HEIGHT := 2.0
const FENCE_THICK := 0.3
## The door for people in the yard gate: width, how far from the leaf's hinge,
## bottom and top.
const WICKET_WIDTH := 0.9
const WICKET_FROM_HINGE := 0.4
const WICKET_BOTTOM := 0.08
const WICKET_TOP := 1.78
## The strip between the house and the yard wall is a terrace at floor level
## from the front as far as this v; from there steps across its whole width go
## down into the garden.
const TERRACE_END := 7.4


var L := 0.0
var W := 0.0
var floor_y := 0.0 ## world height of the ground-floor floor
var base := 0.0 ## bottom of the walls (below the lowest ground), house space

var _bufs := {} # material name -> Buf
var _mats := {} # material name -> Material
var _faces := PackedVector3Array() # collision triangles, house space
var _ramps: Array[PackedVector3Array] = [] # convex collision for stairs and ramps
var _space: PhysicsDirectSpaceState3D
var _skip: Array[RID] = []
var _xf := Transform3D.IDENTITY # house space -> world
var _steps_foot := TERRACE_END # v where the terrace steps reach the garden
var _steps_ground := 0.0 # and the height of the ground there


class Buf:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()

	func add(p: Vector3, nrm: Vector3, col: Color, t: Vector2, t2: Vector2) -> int:
		v.append(p)
		n.append(nrm)
		c.append(col)
		uv.append(t)
		uv2.append(t2)
		return v.size() - 1

	func commit(mat: Material) -> ArrayMesh:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = n
		arr[Mesh.ARRAY_COLOR] = c
		arr[Mesh.ARRAY_TEX_UV] = uv
		arr[Mesh.ARRAY_TEX_UV2] = uv2
		arr[Mesh.ARRAY_INDEX] = idx
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		m.surface_set_material(0, mat)
		return m


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Run without --headless: saving the world headless would drop its trees.")
		quit(1)
		return
	_run.call_deferred()


func _run() -> void:
	var along := (FRONT_RIGHT - FRONT_LEFT).normalized()
	L = FRONT_LEFT.distance_to(FRONT_RIGHT)
	W = FRONT_LEFT.distance_to(BACK_LEFT)

	var world: Node3D = load(WORLD_PATH).instantiate()
	root.add_child(world)
	await physics_frame
	await physics_frame
	_space = world.get_world_3d().direct_space_state
	var buildings := world.get_node("Buildings") as StaticBody3D
	_skip.append(buildings.get_rid())
	for blocker: StaticBody3D in world.find_children("Blocker", "StaticBody3D", true, false):
		_skip.append(blocker.get_rid())

	# The ground floor sits just above the highest ground under the house.
	var outline := PackedVector2Array([FRONT_LEFT, FRONT_RIGHT, FRONT_RIGHT + BACK_LEFT - FRONT_LEFT, BACK_LEFT])
	var low := INF
	var high := -INF
	for i in 8:
		for j in 6:
			var p := FRONT_LEFT + (FRONT_RIGHT - FRONT_LEFT) * (i / 7.0) + (BACK_LEFT - FRONT_LEFT) * (j / 5.0)
			var y := _ground(p)
			low = minf(low, y)
			high = maxf(high, y)
	floor_y = high + 0.15
	base = low - 0.6 - floor_y
	# House +X along the front, +Z out of it.
	var x3 := Vector3(along.x, 0.0, along.y)
	_xf = Transform3D(Basis(x3, Vector3.UP, x3.cross(Vector3.UP)), Vector3(FRONT_LEFT.x, floor_y, FRONT_LEFT.y))
	print("House %.2f x %.2f m, floor at %.2f m (ground %.2f .. %.2f)" % [L, W, floor_y, low, high])

	# Built first: it looks at the ground round the house, which needs the world.
	var house := _build_house()
	var removed := _strip_old_building(world, outline)
	if removed > 0:
		print("Took %d triangles of the old building out of the world" % removed)
		_save_world(world)

	_own(house, house)
	var scene := PackedScene.new()
	var err := scene.pack(house)
	if err == OK:
		err = ResourceSaver.save(scene, OUT_PATH, ResourceSaver.FLAG_COMPRESS)
	if err != OK:
		push_error("Saving %s failed: %s" % [OUT_PATH, error_string(err)])
	else:
		print("Saved %s" % OUT_PATH)
	house.free()
	quit(0 if err == OK else 1)


# --- the old building -----------------------------------------------------------

## Height of the ground at a world spot, ignoring buildings.
func _ground(p: Vector2) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 500.0, p.y), Vector3(p.x, -500.0, p.y))
	q.exclude = _skip
	var hit := _space.intersect_ray(q)
	return hit["position"].y if hit else 0.0


## Ground height at a plan spot, in house space.
func _ground_at(u: float, v: float) -> float:
	var w := _xf * Vector3(u, 0.0, -v)
	return _ground(Vector2(w.x, w.z)) - floor_y


## Removes the walls, roof and garage of the box build_world.gd made for this
## house, and its gate. Returns how many triangles went.
func _strip_old_building(world: Node3D, outline: PackedVector2Array) -> int:
	var zone: PackedVector2Array = Geometry2D.offset_polygon(outline, 0.05)[0]
	# The old garage also had a ramp out in front of its door, by the right-hand corner.
	var out := (FRONT_LEFT - BACK_LEFT).normalized()
	var along := (FRONT_RIGHT - FRONT_LEFT).normalized()
	var ramp := PackedVector2Array([
		FRONT_RIGHT - along * 5.0, FRONT_RIGHT + along * 0.1,
		FRONT_RIGHT + along * 0.1 + out * 2.0, FRONT_RIGHT - along * 5.0 + out * 2.0])
	var inside := func(p: Vector3) -> bool:
		var q := Vector2(p.x, p.z)
		return Geometry2D.is_point_in_polygon(q, zone) or Geometry2D.is_point_in_polygon(q, ramp)
	var removed := 0
	var buildings := world.get_node("Buildings")
	for mi: MeshInstance3D in buildings.find_children("*", "MeshInstance3D", false, false):
		var arr := mi.mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var keep := PackedInt32Array()
		for k in range(0, idx.size(), 3):
			if inside.call(v[idx[k]]) and inside.call(v[idx[k + 1]]) and inside.call(v[idx[k + 2]]):
				removed += 1
				continue
			keep.append_array([idx[k], idx[k + 1], idx[k + 2]])
		if keep.size() == idx.size():
			continue
		var mat := mi.mesh.surface_get_material(0)
		arr[Mesh.ARRAY_INDEX] = keep
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.surface_set_material(0, mat)
		mi.mesh = mesh
	for cs: CollisionShape3D in buildings.find_children("*", "CollisionShape3D", false, false):
		var shape := cs.shape as ConcavePolygonShape3D
		if shape == null:
			continue
		var f := shape.get_faces()
		var kept := PackedVector3Array()
		for k in range(0, f.size(), 3):
			if not (inside.call(f[k]) and inside.call(f[k + 1]) and inside.call(f[k + 2])):
				kept.append_array([f[k], f[k + 1], f[k + 2]])
		if kept.size() != f.size():
			var fresh := ConcavePolygonShape3D.new()
			fresh.set_faces(kept)
			cs.shape = fresh
	var gates := world.get_node_or_null("Gates")
	if gates:
		for gate in gates.get_children():
			if gate.global_position.distance_to(_xf.origin) < 25.0:
				gates.remove_child(gate)
				gate.free()
				removed += 1
	return removed


func _save_world(world: Node3D) -> void:
	world.get_parent().remove_child(world)
	var scene := PackedScene.new()
	var err := scene.pack(world)
	if err == OK:
		err = ResourceSaver.save(scene, WORLD_PATH, ResourceSaver.FLAG_COMPRESS)
	if err != OK:
		push_error("Saving %s failed: %s" % [WORLD_PATH, error_string(err)])
	else:
		print("Saved %s" % WORLD_PATH)
	world.free()


func _own(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		_own(child, owner_node)


# --- the house -------------------------------------------------------------------

func _build_house() -> Node3D:
	_make_materials()
	var house := Node3D.new()
	house.name = "House"
	house.transform = _xf
	var doors := Node3D.new()
	doors.name = "Doors"
	house.add_child(doors)
	var lights := Node3D.new()
	lights.name = "Lights"
	house.add_child(lights)

	_outside_walls(house)
	_partitions(doors)
	_floors_and_ceilings(lights)
	_staircase()
	_entrance_steps()
	_garage_ramp()
	_furniture()
	_yard(house)

	var body := StaticBody3D.new()
	body.name = "Body"
	house.add_child(body)
	for mat_name: String in _bufs:
		var buf: Buf = _bufs[mat_name]
		if buf.idx.is_empty():
			continue
		var mi := MeshInstance3D.new()
		mi.name = mat_name.capitalize().replace(" ", "")
		mi.mesh = buf.commit(_mats[mat_name])
		body.add_child(mi)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(_faces)
	var cs := CollisionShape3D.new()
	cs.name = "Walls"
	cs.shape = shape
	body.add_child(cs)
	for k in _ramps.size():
		var hull := ConvexPolygonShape3D.new()
		hull.points = _ramps[k]
		var rs := CollisionShape3D.new()
		rs.name = "Ramp%d" % k
		rs.shape = hull
		body.add_child(rs)
	return house


func _make_materials() -> void:
	var tuff := ShaderMaterial.new()
	tuff.shader = load("res://world/shaders/building.gdshader")
	_mats["tuff"] = tuff
	var floors := ShaderMaterial.new()
	floors.shader = load("res://world/shaders/house_floor.gdshader")
	_mats["floor"] = floors
	_mats["plaster"] = _plain(Color(0.86, 0.83, 0.77), 0.92)
	_mats["ceiling"] = _plain(Color(0.93, 0.92, 0.89), 0.95)
	_mats["roof"] = _plain(Color(0.33, 0.33, 0.34), 0.95)
	_mats["cap"] = _plain(Color(0.62, 0.6, 0.57), 0.9)
	_mats["frame"] = _plain(Color(0.92, 0.92, 0.9), 0.5)
	_mats["wood"] = _plain(Color(0.42, 0.26, 0.15), 0.6)
	_mats["stone"] = _plain(Color(0.64, 0.6, 0.56), 0.8)
	_mats["concrete"] = _plain(Color(0.42, 0.42, 0.41), 0.95)
	_mats["rail"] = _plain(Color(0.18, 0.18, 0.19), 0.4)
	_mats["porcelain"] = _plain(Color(0.95, 0.95, 0.94), 0.15)
	_mats["linen"] = _plain(Color(0.78, 0.8, 0.84), 0.9)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.55, 0.68, 0.72, 0.28)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.04
	glass.metallic = 0.4
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats["glass"] = glass
	for mat_name: String in _mats:
		_bufs[mat_name] = Buf.new()


func _plain(color: Color, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	return mat


# --- geometry helpers --------------------------------------------------------------

func _p(u: float, y: float, v: float) -> Vector3:
	return Vector3(u, y, -v)


## A flat four-cornered face looking along `nrm` (house space), whatever order
## the corners come in.
func _quad(mat: String, p: Array, nrm: Vector3, uv: Array, col := Color.WHITE, uv2 := Vector2.ZERO, collide := true) -> void:
	var buf: Buf = _bufs[mat]
	var first := buf.v.size()
	for k in 4:
		buf.add(p[k], nrm, col, uv[k], uv2)
	# Front faces wind clockwise, which puts (p2 - p0) x (p1 - p0) along the normal.
	var order := [0, 1, 2, 0, 2, 3]
	if (p[2] - p[0]).cross(p[1] - p[0]).dot(nrm) <= 0.0:
		order = [0, 2, 1, 0, 3, 2]
	for k: int in order:
		buf.idx.append(first + k)
	if collide:
		for k: int in order:
			_faces.append(p[k])


## A box between plan corners lo and hi, given as (u, y, v). `mats` names the
## material of each face by "top", "bottom", "outer" (the face looking along
## `outer`, a plan direction), and "sides" for the rest; "" leaves a face out.
## An outer face is tuff masonry measured along a wall of length `wall_len`.
func _box(lo: Vector3, hi: Vector3, mats: Dictionary, outer := Vector2.ZERO, collide := true) -> void:
	var sides: String = mats.get("sides", "plaster")
	# Each face: plan normal (u, y, v) and its four corners.
	var faces := [
		[Vector3(0, 1, 0), [Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)]],
		[Vector3(0, -1, 0), [Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z)]],
		[Vector3(-1, 0, 0), [Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, lo.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3(lo.x, hi.y, lo.z)]],
		[Vector3(1, 0, 0), [Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, hi.y, lo.z)]],
		[Vector3(0, 0, -1), [Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, lo.z)]],
		[Vector3(0, 0, 1), [Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)]],
	]
	for face: Array in faces:
		var pn: Vector3 = face[0]
		var corners: Array = face[1]
		var mat := sides
		if pn.y > 0.5:
			mat = mats.get("top", sides)
		elif pn.y < -0.5:
			mat = mats.get("bottom", sides)
		elif outer != Vector2.ZERO and (Vector2(pn.x, pn.z).dot(outer) > 0.9 or _on_outline(lo, hi, pn)):
			# The face looking out of the house, or the end of an outside wall at a corner.
			mat = mats.get("outer", "tuff")
		if mat == "":
			continue
		var pts := []
		var uvs := []
		for c: Vector3 in corners:
			pts.append(_p(c.x, c.y, c.z))
			uvs.append(_face_uv(c, pn, mat))
		var col := Color.WHITE
		var uv2 := Vector2.ZERO
		if mat == "tuff":
			# building.gdshader: plain wall (no painted windows); negative height means tuff.
			col = Color(1, 1, 1, 0.5)
			uv2 = Vector2(maxf(L, W), -(PARAPET - base))
		_quad(mat, pts, Vector3(pn.x, pn.y, -pn.z), uvs, col, uv2, collide)


## Whether the face of box lo..hi looking along pn lies on the outline of the house.
func _on_outline(lo: Vector3, hi: Vector3, pn: Vector3) -> bool:
	return (pn.x < -0.5 and lo.x < 0.001) or (pn.x > 0.5 and hi.x > L - 0.001) \
		or (pn.z < -0.5 and lo.z < 0.001) or (pn.z > 0.5 and hi.z > W - 0.001)


## Texture coordinates in metres. Tuff faces run along the wall and down from the parapet.
func _face_uv(c: Vector3, pn: Vector3, mat: String) -> Vector2:
	if mat == "tuff":
		var s := c.x if absf(pn.z) > 0.5 else c.z
		if pn.z > 0.5:
			s = L - c.x
		elif pn.x < -0.5:
			s = W - c.z
		return Vector2(s, PARAPET - c.y)
	if absf(pn.y) > 0.5:
		return Vector2(c.x, c.z)
	return Vector2(c.z if absf(pn.x) > 0.5 else c.x, c.y)


## A straight wall filling the plan rectangle u0..u1 x v0..v1 from y0 to y1,
## with openings [from, to, bottom, top] measured along its length (u for a wall
## that runs along u, v otherwise).
func _wall(u0: float, u1: float, v0: float, v1: float, y0: float, y1: float, openings: Array,
		outer := Vector2.ZERO, mats := {}) -> void:
	var along_u := (u1 - u0) >= (v1 - v0)
	var a0 := u0 if along_u else v0
	var a1 := u1 if along_u else v1
	var piece := func(s0: float, s1: float, b: float, t: float) -> void:
		if s1 - s0 < 0.001 or t - b < 0.001:
			return
		if along_u:
			_box(Vector3(s0, b, v0), Vector3(s1, t, v1), mats, outer)
		else:
			_box(Vector3(u0, b, s0), Vector3(u1, t, s1), mats, outer)
	# Cut the wall into strips at every edge of an opening; each strip is solid
	# except where the openings crossing it are (windows above one another, say).
	var cuts := [a0, a1]
	for o: Array in openings:
		cuts.append_array([o[0], o[1]])
	cuts.sort()
	for i in cuts.size() - 1:
		var s0: float = cuts[i]
		var s1: float = cuts[i + 1]
		if s1 - s0 < 0.001:
			continue
		var mid := (s0 + s1) * 0.5
		var gaps := openings.filter(func(o: Array) -> bool: return o[0] <= mid and mid <= o[1])
		gaps.sort_custom(func(a: Array, b: Array) -> bool: return a[2] < b[2])
		var y := y0
		for o: Array in gaps:
			piece.call(s0, s1, y, o[2])
			y = maxf(y, o[3])
		piece.call(s0, s1, y, y1)


## A box in the frame of a wall: s along it, y up, c across it.
func _wall_box(along_u: bool, s0: float, s1: float, y0: float, y1: float, c0: float, c1: float, mat: String,
		collide := true) -> void:
	var m := {"top": mat, "bottom": mat, "sides": mat}
	if along_u:
		_box(Vector3(s0, y0, c0), Vector3(s1, y1, c1), m, Vector2.ZERO, collide)
	else:
		_box(Vector3(c0, y0, s0), Vector3(c1, y1, s1), m, Vector2.ZERO, collide)


## Frame, glass and sills of a window in a wall lying across c0..c1; `out` is
## +1 when the outside is towards larger c.
func _window_fittings(along_u: bool, s0: float, s1: float, b: float, t: float, c0: float, c1: float, out: float) -> void:
	var m := (c0 + c1) * 0.5
	var f := 0.06
	_wall_box(along_u, s0, s0 + f, b, t, m - 0.04, m + 0.04, "frame")
	_wall_box(along_u, s1 - f, s1, b, t, m - 0.04, m + 0.04, "frame")
	_wall_box(along_u, s0, s1, t - f, t, m - 0.04, m + 0.04, "frame")
	_wall_box(along_u, s0, s1, b, b + f, m - 0.04, m + 0.04, "frame")
	var mid := (s0 + s1) * 0.5
	_wall_box(along_u, mid - 0.03, mid + 0.03, b, t, m - 0.04, m + 0.04, "frame")
	# The pane, seen from both sides; solid, so you cannot walk out through it.
	var pts := []
	for corner: Vector2 in [Vector2(s0, b), Vector2(s1, b), Vector2(s1, t), Vector2(s0, t)]:
		pts.append(_p(corner.x, corner.y, m) if along_u else _p(m, corner.y, corner.x))
	var nrm := Vector3(0, 0, -1) if along_u else Vector3(1, 0, 0)
	_quad("glass", pts, nrm, [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	# Stone sill outside, a wooden one inside.
	var outside := c1 if out > 0.0 else c0
	var inside := c0 if out > 0.0 else c1
	_wall_box(along_u, s0 - 0.06, s1 + 0.06, b - 0.05, b, minf(outside, outside + out * 0.07), maxf(outside, outside + out * 0.07), "cap")
	_wall_box(along_u, s0 - 0.03, s1 + 0.03, b - 0.03, b, minf(inside, inside - out * 0.05), maxf(inside, inside - out * 0.05), "wood")


# --- outside walls -------------------------------------------------------------

func _outside_walls(house: Node3D) -> void:
	var lo := WINDOW_LOW
	var hi := WINDOW_HIGH
	# Front: two windows in the living room, one in the middle room, the garage door.
	var garage := _garage_door()
	var front := [
		[0.9, 2.4, lo.x, lo.y], [4.0, 5.5, lo.x, lo.y], [7.95, 9.4, lo.x, lo.y],
		[0.9, 2.4, hi.x, hi.y], [4.0, 5.5, hi.x, hi.y], [7.95, 9.4, hi.x, hi.y], [11.45, 12.9, hi.x, hi.y],
	]
	# Back: two windows in the big room and one in the back bedroom, all onto the yard.
	var back := [
		[5.1, 6.6, lo.x, lo.y], [7.95, 9.6, lo.x, lo.y], [11.8, 13.1, lo.x, lo.y],
		[1.3, 2.5, hi.x, hi.y], [5.1, 6.6, hi.x, hi.y], [7.95, 9.6, hi.x, hi.y], [11.8, 13.1, hi.x, hi.y],
	]
	# Left: the living-room window and the front door into the stair hall.
	var left := [[2.0, 3.5, lo.x, lo.y], [2.0, 3.5, hi.x, hi.y], [8.0, 9.2, hi.x, hi.y]]
	var right := [[2.0, 3.4, hi.x, hi.y], [6.6, 8.0, hi.x, hi.y]]
	var entrance := _entrance()

	var top := {"top": "cap"}
	_wall(0.0, L, 0.0, OUTER, base, PARAPET, front + [[garage.x, garage.y, -0.01, CEILING]], Vector2(0, -1), top)
	_wall(0.0, L, W - OUTER, W, base, PARAPET, back, Vector2(0, 1), top)
	_wall(0.0, OUTER, OUTER, W - OUTER, base, PARAPET, left + [[entrance.x, entrance.y, -0.01, DOOR_HEIGHT]], Vector2(-1, 0), top)
	_wall(L - OUTER, L, OUTER, W - OUTER, base, PARAPET, right, Vector2(1, 0), top)
	for w: Array in front:
		_window_fittings(true, w[0], w[1], w[2], w[3], 0.0, OUTER, -1.0)
	for w: Array in back:
		_window_fittings(true, w[0], w[1], w[2], w[3], W - OUTER, W, 1.0)
	for w: Array in left:
		_window_fittings(false, w[0], w[1], w[2], w[3], 0.0, OUTER, -1.0)
	for w: Array in right:
		_window_fittings(false, w[0], w[1], w[2], w[3], L - OUTER, L, 1.0)
	_door(house.get_node("Doors"), "FrontDoor", false, entrance.x, entrance.y, 0.0, OUTER, true, Vector2(1, 0), 1.0)
	_add_gate(house, "GarageGate", _p((garage.x + garage.y) * 0.5, 0.0, OUTER * 0.5), Basis.IDENTITY,
		garage.y - garage.x, GATE_HEIGHT, true, "garage", 14.0)


## u range of the garage doorway: centred on the inside of the garage.
func _garage_door() -> Vector2:
	var centre := (GARAGE_WALL + INNER * 0.5 + L - OUTER) * 0.5
	return Vector2(centre - 1.3, centre + 1.3)


## v range of the front door in the left wall, at the front of the stair hall.
func _entrance() -> Vector2:
	return Vector2(SPLIT + 0.2, SPLIT + 1.2)


# --- partitions and doors -------------------------------------------------------

func _partitions(doors: Node3D) -> void:
	var h := INNER * 0.5
	var g := GARAGE_WALL
	var door_b := Vector2(SPLIT + h + 0.06, SPLIT + h + 0.91)
	var door_c := Vector2(6.66 - h - 1.0, 6.66 - h - 0.1)
	var door_d := Vector2(g - h - 1.0, g - h - 0.1)
	var door_e := Vector2(SPLIT + h + 0.06, SPLIT + h + 0.96)
	var bath0 := BATH.position.x + h
	var bath1 := BATH.position.x + BATH.size.x - h
	var door_bath := Vector2(bath1 - 0.9, bath1 - 0.04)
	var y := DOOR_HEIGHT
	# Between the front rooms and the back ones, right across the house.
	_wall(OUTER, L - OUTER, SPLIT - h, SPLIT + h, 0.0, CEILING, [[door_c.x, door_c.y, -0.01, y], [door_d.x, door_d.y, -0.01, y]])
	# Front bedroom | garage, and big back room | back bedroom.
	_wall(g - h, g + h, OUTER, W - OUTER, 0.0, CEILING, [[door_e.x, door_e.y, -0.01, y]])
	# Living room | middle room.
	_wall(6.66 - h, 6.66 + h, OUTER, SPLIT - h, 0.0, CEILING, [])
	# Stair hall | big back room.
	_wall(3.31 - h, 3.31 + h, SPLIT + h, W - OUTER, 0.0, CEILING, [[door_b.x, door_b.y, -0.01, y]])
	# The bathroom in the corner of the big back room.
	var bu := BATH.position.x + BATH.size.x
	var bv := BATH.position.y
	_wall(bu - h, bu + h, bv, W - OUTER, 0.0, CEILING, [])
	_wall(bath0, bu - h, bv - h, bv + h, 0.0, CEILING, [[door_bath.x, door_bath.y, -0.01, y]])

	# Which way each door swings: into the big room, the living room (which opens
	# off the big room through the wall between them), the front
	# bedroom, the back bedroom and the bathroom.
	_door(doors, "HallDoor", false, door_b.x, door_b.y, 3.31 - h, 3.31 + h, true, Vector2(1, 0))
	_door(doors, "LivingRoomDoor", true, door_c.x, door_c.y, SPLIT - h, SPLIT + h, false, Vector2(0, -1))
	_door(doors, "FrontBedroomDoor", true, door_d.x, door_d.y, SPLIT - h, SPLIT + h, false, Vector2(0, -1))
	_door(doors, "BackBedroomDoor", false, door_e.x, door_e.y, g - h, g + h, true, Vector2(1, 0))
	_door(doors, "BathroomDoor", true, door_bath.x, door_bath.y, bv - h, bv + h, false, Vector2(0, 1))


## A doorway from s0 to s1 along a wall lying across c0..c1: its frame and a
## leaf hung at the s0 end (or s1 when `hinge_low` is false) that swings
## towards `swing` (a plan direction).
func _door(doors: Node3D, door_name: String, along_u: bool, s0: float, s1: float, c0: float, c1: float,
		hinge_low: bool, swing: Vector2, thickness_extra := 0.0) -> void:
	var f := 0.05
	var e := 0.01
	_wall_box(along_u, s0, s0 + f, 0.0, DOOR_HEIGHT, c0 - e, c1 + e, "frame")
	_wall_box(along_u, s1 - f, s1, 0.0, DOOR_HEIGHT, c0 - e, c1 + e, "frame")
	_wall_box(along_u, s0, s1, DOOR_HEIGHT - f, DOOR_HEIGHT, c0 - e, c1 + e, "frame")
	var width := s1 - s0 - 2.0 * f
	var hinge_s := s0 + f if hinge_low else s1 - f
	var m := (c0 + c1) * 0.5
	# A front door sits by the face of its thick wall that it opens towards.
	if thickness_extra > 0.0:
		m = c1 - 0.08 if swing.x > 0.0 or swing.y > 0.0 else c0 + 0.08
	var hinge := _p(hinge_s, 0.0, m) if along_u else _p(m, 0.0, hinge_s)
	var across := 1.0 if hinge_low else -1.0
	var x_dir := Vector3(across, 0, 0) if along_u else Vector3(0, 0, -across)
	var frame := Basis(x_dir, Vector3.UP, x_dir.cross(Vector3.UP))
	# Turning +Y swings the leaf's free edge towards the node's -Z.
	var towards := Vector3(swing.x, 0.0, -swing.y)
	var turn := 1.0 if towards.dot(-frame.z) > 0.0 else -1.0

	var door := Node3D.new()
	door.name = door_name
	door.set_script(load("res://world/house_door.gd"))
	door.transform = Transform3D(frame, hinge)
	door.set("width", width)
	door.set("open_angle", 95.0 * turn)
	doors.add_child(door)

	var leaf := Buf.new()
	var lw := width - 0.01
	var lh := DOOR_HEIGHT - f - 0.01
	var thick := 0.05 if thickness_extra > 0.0 else 0.04
	_leaf_box(leaf, Vector3(0.005, 0.01, -thick * 0.5), Vector3(lw, lh, thick * 0.5))
	# Handles on both faces.
	for side: float in [-1.0, 1.0]:
		var z := side * (thick * 0.5 + 0.03)
		_leaf_box(leaf, Vector3(lw - 0.17, 1.0, z - 0.012), Vector3(lw - 0.05, 1.03, z + 0.012))
	var mi := MeshInstance3D.new()
	mi.name = "Leaf"
	mi.mesh = leaf.commit(_mats["wood"])
	door.add_child(mi)


## A plain box for a door leaf, in the door's own space.
func _leaf_box(buf: Buf, lo: Vector3, hi: Vector3) -> void:
	var corners := [
		[Vector3.UP, [Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)]],
		[Vector3.DOWN, [Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z)]],
		[Vector3.LEFT, [Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, lo.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3(lo.x, hi.y, lo.z)]],
		[Vector3.RIGHT, [Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, hi.y, lo.z)]],
		[Vector3.FORWARD, [Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, lo.z)]],
		[Vector3.BACK, [Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)]],
	]
	for face: Array in corners:
		var nrm: Vector3 = face[0]
		var p: Array = face[1]
		var first := buf.v.size()
		for k in 4:
			buf.add(p[k], nrm, Color.WHITE, Vector2.ZERO, Vector2.ZERO)
		var order := [0, 1, 2, 0, 2, 3]
		if (p[2] - p[0]).cross(p[1] - p[0]).dot(nrm) <= 0.0:
			order = [0, 2, 1, 0, 3, 2]
		for k: int in order:
			buf.idx.append(first + k)


# --- floors, ceilings, lights ------------------------------------------------------

## Ground-floor rooms: name, [u0, u1, v0, v1] to the middle of their walls, floor
## (1 parquet, 0.5 tiles, 0 concrete). A room in two pieces lists the second
## piece with an empty name, so it gets no second ceiling light.
func _rooms() -> Array:
	var g := GARAGE_WALL
	var bu := BATH.position.x + BATH.size.x
	var bv := BATH.position.y
	return [
		["Living room", [0.0, 6.66, 0.0, SPLIT], 1.0],
		["Front bedroom", [6.66, g, 0.0, SPLIT], 1.0],
		["Garage", [g, L, 0.0, SPLIT], 0.0],
		["Stair hall", [0.0, 3.31, SPLIT, W], 0.5],
		["Big room", [3.31, g, SPLIT, bv], 1.0],
		["", [bu, g, bv, W], 1.0],
		["Bathroom", [3.31, bu, bv, W], 0.5],
		["Back bedroom", [g, L, SPLIT, W], 1.0],
	]


func _floors_and_ceilings(lights: Node3D) -> void:
	for room: Array in _rooms():
		var r: Array = room[1]
		_floor(r[0], r[1], r[2], r[3], 0.0, room[2])
		if room[0] == "":
			continue
		var lamp := OmniLight3D.new()
		lamp.name = String(room[0]).replace(" ", "")
		lamp.position = _p((r[0] + r[1]) * 0.5, CEILING - 0.25, (r[2] + r[3]) * 0.5)
		lamp.light_energy = 0.6
		lamp.omni_range = 6.0
		lamp.light_color = Color(1.0, 0.9, 0.78)
		lights.add_child(lamp)
	# The upper floor is one open room for now: a slab with the stair well cut out
	# of its back-left corner, and the roof slab above.
	var o := OUTER
	var slab := {"top": "", "bottom": "ceiling", "sides": "plaster"}
	_box(Vector3(o, CEILING, o), Vector3(L - o, UPPER, STAIR_FRONT), slab)
	_box(Vector3(STAIR_RIGHT, CEILING, STAIR_FRONT), Vector3(L - o, UPPER, W - o), slab)
	_floor(o, L - o, o, STAIR_FRONT, UPPER, 1.0)
	_floor(STAIR_RIGHT, L - o, STAIR_FRONT, W - o, UPPER, 1.0)
	_box(Vector3(o, UPPER_CEILING, o), Vector3(L - o, ROOF, W - o), {"top": "roof", "bottom": "ceiling", "sides": ""})
	for k in 3:
		var lamp := OmniLight3D.new()
		lamp.name = "Upstairs%d" % (k + 1)
		lamp.position = _p(L * (k + 0.5) / 3.0, UPPER_CEILING - 0.25, W * 0.5)
		lamp.light_energy = 0.6
		lamp.omni_range = 7.0
		lamp.light_color = Color(1.0, 0.9, 0.78)
		lights.add_child(lamp)
	# A railing round the stair well, open where the upper flight arrives.
	var h := UPPER + 0.95
	_box(Vector3(STAIR_RIGHT - 0.05, UPPER, STAIR_FRONT), Vector3(STAIR_RIGHT, h, W - o), {"sides": "rail", "top": "wood"})
	_box(Vector3(STAIR_SPLIT + 0.05, UPPER, STAIR_FRONT - 0.05), Vector3(STAIR_RIGHT, h, STAIR_FRONT), {"sides": "rail", "top": "wood"})


func _floor(u0: float, u1: float, v0: float, v1: float, y: float, kind: float) -> void:
	var pts := [_p(u0, y, v0), _p(u1, y, v0), _p(u1, y, v1), _p(u0, y, v1)]
	var uvs := [Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)]
	_quad("floor", pts, Vector3.UP, uvs, Color(1, 1, 1, kind))


# --- staircase ------------------------------------------------------------------

func _staircase() -> void:
	var o := OUTER
	var rise := UPPER / (STEPS * 2.0)
	var landing := STAIR_FRONT + (STEPS - 1) * TREAD
	var split0 := STAIR_SPLIT - 0.05
	var split1 := STAIR_SPLIT + 0.05
	var stone := {"top": "stone", "sides": "stone", "bottom": ""}
	# Steps are only to look at; you walk on the smooth slopes added below them.
	# First flight, on the right, climbing towards the back.
	for i in range(1, STEPS):
		var v0 := STAIR_FRONT + (i - 1) * TREAD
		_box(Vector3(split1, 0.0, v0), Vector3(STAIR_RIGHT, i * rise, v0 + TREAD), stone, Vector2.ZERO, false)
	# The landing, across both flights against the back wall.
	_box(Vector3(o, 0.0, landing), Vector3(STAIR_RIGHT, STEPS * rise, W - o), stone, Vector2.ZERO, false)
	# Second flight, on the left, climbing back towards the front.
	for j in range(1, STEPS):
		var v1 := landing - (j - 1) * TREAD
		_box(Vector3(o, 0.0, v1 - TREAD), Vector3(split0, (STEPS + j) * rise, v1), stone, Vector2.ZERO, false)
	# The wall between the flights, carried up to railing height upstairs.
	_box(Vector3(split0, 0.0, STAIR_FRONT), Vector3(split1, UPPER + 0.95, landing), {"top": "wood"})
	# What you actually walk on.
	_ramp(split1, STAIR_RIGHT, STAIR_FRONT, landing, 0.0, STEPS * rise)
	_ramp(o, split0, landing, STAIR_FRONT, STEPS * rise, UPPER)
	_hull([_p(o, 0.0, landing), _p(STAIR_RIGHT, 0.0, landing), _p(o, 0.0, W - o), _p(STAIR_RIGHT, 0.0, W - o),
		_p(o, STEPS * rise, landing), _p(STAIR_RIGHT, STEPS * rise, landing), _p(o, STEPS * rise, W - o), _p(STAIR_RIGHT, STEPS * rise, W - o)])


## A solid wedge from the floor up to a slope running along v from (v0, y0) to (v1, y1).
func _ramp(u0: float, u1: float, v0: float, v1: float, y0: float, y1: float) -> void:
	_hull([_p(u0, 0.0, v0), _p(u1, 0.0, v0), _p(u0, 0.0, v1), _p(u1, 0.0, v1),
		_p(u0, y0, v0), _p(u1, y0, v0), _p(u0, y1, v1), _p(u1, y1, v1)])


func _hull(points: Array) -> void:
	var pts := PackedVector3Array()
	for p: Vector3 in points:
		pts.append(p)
	_ramps.append(pts)


# --- outside: steps and the garage --------------------------------------------------

## The side terrace: the strip between the house and the yard wall raised to
## the level of the front door, from the front wall of the yard back to
## TERRACE_END, then steps across its whole width down into the garden.
func _entrance_steps() -> void:
	var u0 := YARD_LEFT + FENCE_THICK
	var mid := u0 * 0.5
	# How far down the garden is where the steps end (it depends on how many there are).
	var ground := minf(_ground_at(mid, TERRACE_END + 2.0), -0.05)
	var risers := maxi(1, ceili(-ground / 0.17))
	ground = minf(_ground_at(mid, TERRACE_END + risers * 0.3), -0.05)
	risers = maxi(1, ceili(-ground / 0.17))
	var rise := -ground / risers
	var low := ground
	for v: float in [FENCE_THICK, TERRACE_END * 0.5, TERRACE_END]:
		for u: float in [u0, 0.0]:
			low = minf(low, _ground_at(u, v))
	var deep := low - 0.5
	var stone := {"top": "stone", "sides": "stone", "bottom": ""}
	_box(Vector3(u0, deep, FENCE_THICK), Vector3(0.0, 0.0, TERRACE_END), stone)
	var v := TERRACE_END
	for k in range(1, risers):
		_box(Vector3(u0, deep, v), Vector3(0.0, -k * rise, v + 0.3), stone, Vector2.ZERO, false)
		v += 0.3
	_steps_foot = v
	_steps_ground = ground
	# One slope over the steps to walk on, down to the ground past the last one.
	_hull([_p(u0, 0.0, TERRACE_END), _p(0.0, 0.0, TERRACE_END), _p(u0, ground, v + 0.3), _p(0.0, ground, v + 0.3),
		_p(u0, deep, TERRACE_END), _p(0.0, deep, TERRACE_END), _p(u0, deep, v + 0.3), _p(0.0, deep, v + 0.3)])


## Height of what you stand on in the yard: the terrace and its steps beside
## the house, the ground everywhere else (house space).
func _yard_ground(u: float, v: float) -> float:
	var g := _ground_at(u, v)
	if u > YARD_LEFT - 0.5 and u < 0.5:
		if v <= TERRACE_END:
			return maxf(g, 0.0)
		if v < _steps_foot + 0.3:
			return maxf(g, lerpf(0.0, _steps_ground, (v - TERRACE_END) / (_steps_foot + 0.3 - TERRACE_END)))
	return g


## A concrete ramp from the street up to the garage floor.
func _garage_ramp() -> void:
	var door := _garage_door()
	var u0 := door.x - 0.3
	var u1 := door.y + 0.3
	var g0 := minf(_ground_at(u0, -GARAGE_RAMP), -0.02)
	var g1 := minf(_ground_at(u1, -GARAGE_RAMP), -0.02)
	var pts := [_p(u0, 0.0, 0.0), _p(u1, 0.0, 0.0), _p(u1, g1, -GARAGE_RAMP), _p(u0, g0, -GARAGE_RAMP)]
	var up: Vector3 = (pts[3] - pts[0]).cross(pts[1] - pts[0]).normalized()
	_quad("concrete", pts, up, [Vector2(u0, 0), Vector2(u1, 0), Vector2(u1, 1.6), Vector2(u0, 1.6)])
	var deep := minf(g0, g1) - 0.4
	for side: Array in [[u0, g0], [u1, g1]]:
		var s: float = side[0]
		_quad("concrete", [_p(s, 0.0, 0.0), _p(s, side[1], -GARAGE_RAMP), _p(s, deep, -GARAGE_RAMP), _p(s, deep, 0.0)],
			Vector3(-1 if s == u0 else 1, 0, 0), [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	# The garage floor goes on through the doorway.
	_floor(door.x, door.y, 0.0, OUTER, 0.0, 0.0)


## A steel gate like the one the world builder used to make for garages, so
## world/garage_gate.gd swings it (G): two leaves, under a glazed transom if
## `transom`, and with a door for people in its right-hand leaf if `wicket`
## (it opens by itself as you walk up, like the doors of the house).
## `frame` turns the gate's own space (+X across it, +Z the side the
## leaves swing to) into house space; `at` is the middle of its threshold.
func _add_gate(house: Node3D, gate_name: String, at: Vector3, frame: Basis, width: float, height: float,
		transom: bool, label: String, reach: float, wicket := false) -> void:
	var gate := Node3D.new()
	gate.name = gate_name
	gate.set_script(load("res://world/garage_gate.gd"))
	gate.transform = Transform3D(frame, at)
	gate.set("label", label)
	gate.set("reach", reach)
	house.add_child(gate)

	var shader: Shader = load("res://world/shaders/gate.gdshader")
	var painted := ShaderMaterial.new()
	painted.shader = shader
	painted.set_shader_parameter("part", 0)
	var glazed := ShaderMaterial.new()
	glazed.shader = shader
	glazed.set_shader_parameter("part", 1)

	var half := width * 0.5
	var size := Vector2(width, height)
	for side: float in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.name = "LeafL" if side < 0.0 else "LeafR"
		pivot.position = Vector3(half * side, 0.0, 0.0)
		gate.add_child(pivot)
		var x0 := 0.0 if side < 0.0 else -half
		var u0 := 0.0 if side < 0.0 else 0.5
		# UV.x runs 0..1 across the whole gate, so the painted pattern lines up.
		var to_uv := func(x: float, y: float) -> Vector2: return Vector2(u0 + (x - x0) / half * 0.5, y / height)
		var leaf := Buf.new()
		if wicket and side > 0.0:
			# The leaf with the door: four panels round the doorway, and the door
			# itself hung on the side nearer the leaf's hinge, swinging out too.
			var w := _wicket(half, height)
			_gate_panel(leaf, x0, w.x, 0.0, height, to_uv, size)
			_gate_panel(leaf, w.y, x0 + half, 0.0, height, to_uv, size)
			_gate_panel(leaf, w.x, w.y, 0.0, WICKET_BOTTOM, to_uv, size)
			_gate_panel(leaf, w.x, w.y, WICKET_TOP, height, to_uv, size)
			var door := Node3D.new()
			door.name = "Wicket"
			door.set_script(load("res://world/house_door.gd"))
			# Its +X runs from the hinge across the doorway (towards the leaf's free
			# edge); turning it swings the free edge out, towards the gate's +Z.
			door.transform = Transform3D(Basis(Vector3.LEFT, Vector3.UP, Vector3.FORWARD), Vector3(w.y, 0.0, 0.0))
			door.set("width", w.y - w.x)
			door.set("open_angle", 95.0)
			pivot.add_child(door)
			var panel := Buf.new()
			var door_uv := func(x: float, y: float) -> Vector2: return to_uv.call(w.y - x, y)
			_gate_panel(panel, 0.0, w.y - w.x, WICKET_BOTTOM, WICKET_TOP, door_uv, size)
			var door_mesh := MeshInstance3D.new()
			door_mesh.name = "Leaf"
			door_mesh.mesh = panel.commit(painted)
			door.add_child(door_mesh)
		else:
			_gate_panel(leaf, x0, x0 + half, 0.0, height, to_uv, size)
		var visual := MeshInstance3D.new()
		visual.name = "Mesh"
		visual.mesh = leaf.commit(painted)
		pivot.add_child(visual)

	if transom:
		var glass := Buf.new()
		var y0 := height
		var y1 := height + TRANSOM_HEIGHT
		_gate_quad(glass, [Vector3(-half, y0, 0.0), Vector3(half, y0, 0.0), Vector3(half, y1, 0.0), Vector3(-half, y1, 0.0)],
			[Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)], Vector2(width, TRANSOM_HEIGHT))
		var strip := MeshInstance3D.new()
		strip.name = "Transom"
		strip.mesh = glass.commit(glazed)
		gate.add_child(strip)

	# What stops a car while the gate is shut, with a gap where the door for
	# people is (the gate's own space: the right-hand leaf hangs from +half).
	var blocker := StaticBody3D.new()
	blocker.name = "Blocker"
	gate.add_child(blocker)
	var boxes := [[-half, half, 0.0, height]]
	if wicket:
		var w := _wicket(half, height)
		var a := half + w.x
		var b := half + w.y
		boxes = [[-half, a, 0.0, height], [b, half, 0.0, height], [a, b, WICKET_TOP, height]]
	for k in boxes.size():
		var r: Array = boxes[k]
		var shape := BoxShape3D.new()
		shape.size = Vector3(r[1] - r[0], r[3] - r[2], 0.12)
		var cs := CollisionShape3D.new()
		cs.name = "CollisionShape3D" if k == 0 else "CollisionShape3D%d" % (k + 1)
		cs.shape = shape
		cs.position = Vector3((r[0] + r[1]) * 0.5, (r[2] + r[3]) * 0.5, 0.0)
		blocker.add_child(cs)


## Where the door for people sits in a gate leaf, as x from..to in the leaf's
## own space (its hinge at 0, the leaf running towards -x).
func _wicket(half: float, _height: float) -> Vector2:
	var from := -WICKET_FROM_HINGE - WICKET_WIDTH
	return Vector2(maxf(from, -half + 0.15), -WICKET_FROM_HINGE)


## A flat panel of a gate leaf from x0 to x1 and y0 to y1, facing +Z.
func _gate_panel(buf: Buf, x0: float, x1: float, y0: float, y1: float, to_uv: Callable, size: Vector2) -> void:
	_gate_quad(buf, [Vector3(x0, y0, 0.0), Vector3(x1, y0, 0.0), Vector3(x1, y1, 0.0), Vector3(x0, y1, 0.0)],
		[to_uv.call(x0, y0), to_uv.call(x1, y0), to_uv.call(x1, y1), to_uv.call(x0, y1)], size)


func _gate_quad(buf: Buf, p: Array, uv: Array, size: Vector2) -> void:
	var first := buf.v.size()
	for k in 4:
		buf.add(p[k], Vector3.BACK, Color.WHITE, uv[k], size)
	var order := [0, 1, 2, 0, 2, 3]
	if (p[2] - p[0]).cross(p[1] - p[0]).dot(Vector3.BACK) <= 0.0:
		order = [0, 2, 1, 0, 3, 2]
	for k: int in order:
		buf.idx.append(first + k)


# --- furniture ----------------------------------------------------------------------

## Just enough to tell the rooms apart: beds in the bedrooms, a toilet and a
## basin in the bathroom.
func _furniture() -> void:
	var g := GARAGE_WALL - INNER * 0.5
	# Front bedroom: head against the garage wall.
	_bed(g, 2.6, -1.0)
	# Back bedroom: head against the right-hand outside wall.
	_bed(L - OUTER, 7.9, -1.0)
	var porcelain := {"top": "porcelain", "sides": "porcelain", "bottom": ""}
	var mid := BATH.position.x + BATH.size.x * 0.5
	var back := W - OUTER
	# Toilet against the back wall: cistern, bowl and seat.
	_box(Vector3(mid - 0.2, 0.0, back - 0.2), Vector3(mid + 0.2, 0.85, back), porcelain)
	_box(Vector3(mid - 0.16, 0.0, back - 0.68), Vector3(mid + 0.16, 0.4, back - 0.2), porcelain)
	_box(Vector3(mid - 0.18, 0.4, back - 0.7), Vector3(mid + 0.18, 0.43, back - 0.2), {"top": "frame", "sides": "frame", "bottom": ""})
	# Basin on the side wall, clear of the door as it swings in.
	var side := BATH.position.x + BATH.size.x - INNER * 0.5
	var bv := BATH.position.y + INNER * 0.5
	_box(Vector3(side - 0.45, 0.78, bv + 1.0), Vector3(side, 0.88, bv + 1.55), porcelain)
	_box(Vector3(side - 0.12, 0.0, bv + 1.17), Vector3(side, 0.78, bv + 1.38), porcelain)


## A double bed with its head against a wall at u = `wall`, centred on v, the
## foot towards `dir` (-1 towards smaller u).
func _bed(wall: float, v: float, dir: float) -> void:
	var u0 := minf(wall, wall + dir * 2.1)
	var u1 := maxf(wall, wall + dir * 2.1)
	var wood := {"top": "wood", "sides": "wood", "bottom": ""}
	var linen := {"top": "linen", "sides": "linen", "bottom": ""}
	_box(Vector3(u0, 0.0, v - 0.8), Vector3(u1, 0.3, v + 0.8), wood)
	_box(Vector3(u0 + 0.05, 0.3, v - 0.75), Vector3(u1 - 0.05, 0.52, v + 0.75), linen)
	# Headboard and pillows at the wall end.
	var head := wall + dir * 0.08
	_box(Vector3(minf(wall, head), 0.0, v - 0.85), Vector3(maxf(wall, head), 1.0, v + 0.85), wood)
	var p0 := wall + dir * 0.12
	var p1 := wall + dir * 0.55
	var cotton := {"top": "frame", "sides": "frame", "bottom": ""}
	_box(Vector3(minf(p0, p1), 0.52, v - 0.7), Vector3(maxf(p0, p1), 0.64, v - 0.05), cotton)
	_box(Vector3(minf(p0, p1), 0.52, v + 0.05), Vector3(maxf(p0, p1), 0.64, v + 0.7), cotton)


# --- the yard -----------------------------------------------------------------------

## The stone wall round the yard: along the front from the house's left corner
## out to the road, up the side between the house and the road with the gate in
## it, across the back, and down the right-hand side back to the house.
func _yard(house: Node3D) -> void:
	var t := FENCE_THICK
	var back := W + YARD_DEPTH
	var x := YARD_LEFT
	_fence(x, 0.0, 0.0, t, [])
	_fence(x, x + t, 0.0, back + t, [YARD_GATE])
	_fence(x, L, back, back + t, [])
	_fence(L - t, L, W, back, [])
	# Piers either side of the gate, a little taller than the wall.
	var stone := {"sides": "tuff", "top": "cap", "bottom": ""}
	for v: float in [YARD_GATE.x, YARD_GATE.y]:
		var gy := _yard_ground(x + t * 0.5, v)
		var v0 := v - 0.45 if v == YARD_GATE.x else v
		_box(Vector3(x - 0.08, gy - 0.5, v0), Vector3(x + t + 0.08, gy + FENCE_HEIGHT + 0.3, v0 + 0.45), stone)
	# The gate swings out over the road; seen from the road +X runs towards the
	# front, so the leaf with the door for people is the one nearer the steps.
	var mid := (YARD_GATE.x + YARD_GATE.y) * 0.5
	var width := YARD_GATE.y - YARD_GATE.x - 0.04
	var gy := _yard_ground(x + t * 0.5, mid)
	_add_gate(house, "YardGate", _p(x + t * 0.5, gy, mid), Basis(Vector3(0, 0, 1), Vector3.UP, Vector3(-1, 0, 0)),
		width, FENCE_HEIGHT - 0.1, false, "yard gate", 9.0, true)


## A straight run of wall over the plan rectangle u0..u1 x v0..v1, stepping
## with the ground every two metres or so, with gaps [from, to] along it.
func _fence(u0: float, u1: float, v0: float, v1: float, gaps: Array) -> void:
	var along_u := (u1 - u0) >= (v1 - v0)
	var a0 := u0 if along_u else v0
	var a1 := u1 if along_u else v1
	# Stretches between the gaps.
	var runs := []
	var at := a0
	for gap: Vector2 in gaps:
		runs.append(Vector2(at, gap.x))
		at = gap.y
	runs.append(Vector2(at, a1))
	var stone := {"sides": "tuff", "top": "cap", "bottom": ""}
	for run: Vector2 in runs:
		var pieces := maxi(1, ceili((run.y - run.x) / 2.0))
		for k in pieces:
			var s0 := lerpf(run.x, run.y, float(k) / pieces)
			var s1 := lerpf(run.x, run.y, float(k + 1) / pieces)
			# 2 m above what you stand on inside (the terrace, beside the house), and
			# down into the real ground on both sides.
			var low := INF
			var lo_in := INF
			var hi_in := -INF
			for s: float in [s0, (s0 + s1) * 0.5, s1]:
				var u := s if along_u else (u0 + u1) * 0.5
				var v := (v0 + v1) * 0.5 if along_u else s
				var inside := _yard_ground(u, v)
				low = minf(low, minf(_ground_at(u, v), _ground_at(u - 0.4, v)))
				lo_in = minf(lo_in, inside)
				hi_in = maxf(hi_in, inside)
			var top := (lo_in + hi_in) * 0.5 + FENCE_HEIGHT
			if along_u:
				_box(Vector3(s0, low - 0.5, v0), Vector3(s1, top, v1), stone)
			else:
				_box(Vector3(u0, low - 0.5, s0), Vector3(u1, top, s1), stone)
