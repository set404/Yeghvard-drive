extends SceneTree
## Builds res://world/sidewalks.scn: raised sidewalks of paving slabs with a kerb
## along both sides of the main road (route H-4), from the gas station on
## Yeghvard highway north through town to the end of Komitas street, and along
## Charents street, the other way of the route through town. main.tscn stands
## it in the world (node Sidewalks).
##
## The road lines come from tools/build_world.gd itself (OpenStreetMap, with the
## two halves of the dual carriageway slid apart the way it lays them), so the
## sidewalks sit right on the road edges. They break where another road joins,
## where something solid is still in the way (the gas station), and
## on the inner side of the dual carriageway.
##
## Run:  godot --path . --script res://tools/build_sidewalks.gd

const BuildWorld := preload("res://tools/build_world.gd")
const OUT_PATH := "res://world/sidewalks.scn"
const SCENE_PATH := "res://main.tscn"

## The OpenStreetMap ways that get sidewalks: the route from the gas station into
## town, then Charents street (its two one-way halves and the residential end).
const ROUTE := [1328842574, 568252353, 568252354, 899170835, 902993586, 88174826,
	208624874, 1049340727, 79129299, 189291674,
	208565490, 899170834, 1048567977, 88174895]
## The paving on the walkway, and how many metres one copy of the image covers.
const PAVERS := "res://data/textures/sidewalk_pavers.webp"
const PAVER_SIZE := Vector2(2.4, 1.67)
## Metres: the walkway (the same all along: tools/clear_sidewalks.gd keeps the walls back),
## its height above the road edge, and the gap to the road.
const WIDTH := 2.2
const KERB := 0.15
const GAP := 0.05
## How far out the bank on the outer side may reach.
const SKIRT := 3.0
## How far out the kerb's collision ramps up onto the walkway (four times its
## height, at least this and at most 2 m), so you walk and drive up onto the
## sidewalk without a step. The kerb and the ends still look square.
const RAMP := 0.6
## Spacing of the points along each side.
const STEP := 1.5
## Room left round a road that joins, beyond its half width.
const JUNCTION := 1.5
## How far across a median between the two halves of a dual carriageway can be.
const MEDIAN := 12.0
## Shorter pieces than this are left out.
const MIN_RUN := 6.0

var _space: PhysicsDirectSpaceState3D
var _ground_skip: Array[RID] = []
var _solid: Array[RID] = []
## Where something solid still stands on the sidewalk (10 m spots) -> what it is.
var _blocked := {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var lines := _route_lines()
	var bw = BuildWorld.new()
	var p := deg_to_rad(BuildWorld.LAT0)
	bw.mz = 111132.92 - 559.82 * cos(2.0 * p) + 1.175 * cos(4.0 * p)
	bw.mx = 111412.84 * cos(p) - 93.5 * cos(3.0 * p)
	bw._parse_osm()
	# Which of the world's road runs are the route: matched before the dual
	# carriageway is slid apart, while they still lie on the OSM lines.
	var on_route := {}
	for i in bw.roads.size():
		var mid: Vector2 = bw.roads[i]["pts"][bw.roads[i]["pts"].size() / 2]
		for line in lines:
			if _distance_to_line(mid, line) < 0.5:
				on_route[i] = true
	bw._pair_carriageways()
	var roads: Array = bw.roads
	bw.free()
	print("Route: %d of %d road runs" % [on_route.size(), roads.size()])

	var main: Node3D = load(SCENE_PATH).instantiate()
	root.add_child(main)
	for i in 4:
		await physics_frame
	_space = main.get_world_3d().direct_space_state
	var world := main.get_node("World")
	for body: CollisionObject3D in main.find_children("*", "CollisionObject3D", true, false):
		if body.get_parent() == world and body.name == "Terrain":
			continue
		_ground_skip.append(body.get_rid())
		if body is VehicleBody3D or body is CharacterBody3D or body is Area3D or body.name in ["Roads", "Terrain", "Trees"]:
			continue
		if main.get_node("Sidewalks").is_ancestor_of(body):
			continue # the sidewalks from an earlier run
		if world.has_node("Props") and world.get_node("Props").is_ancestor_of(body):
			continue # the bus stops stand at the kerb, the sidewalk runs on under them
		_solid.append(body.get_rid())

	var faces := PackedVector3Array()
	var tops := SurfaceTool.new()
	tops.begin(Mesh.PRIMITIVE_TRIANGLES)
	var edges := SurfaceTool.new()
	edges.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pieces := 0
	var length := 0.0
	for i: int in on_route:
		var road: Dictionary = roads[i]
		for side: float in [1.0, -1.0]:
			for run in _side_runs(road, side, roads, on_route):
				pieces += 1
				length += (run.size() - 1) * STEP
				_add_walk(tops, edges, faces, run)
	var mesh := tops.commit()
	edges.commit(mesh)
	var paving := StandardMaterial3D.new()
	var img := Image.load_from_file(ProjectSettings.globalize_path(PAVERS))
	img.generate_mipmaps()
	paving.albedo_texture = ImageTexture.create_from_image(img)
	paving.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	paving.roughness = 0.9
	mesh.surface_set_material(0, paving)
	var concrete := StandardMaterial3D.new()
	concrete.vertex_color_use_as_albedo = true
	concrete.roughness = 0.92
	mesh.surface_set_material(1, concrete)
	print("Sidewalks: %d pieces, %.1f km" % [pieces, length / 1000.0])
	for spot: Vector2i in _blocked:
		print("  in the way at (%d, %d): %s" % [spot.x, spot.y, _blocked[spot]])
	main.free()

	var walks := Node3D.new()
	walks.name = "Sidewalks"
	var look := MeshInstance3D.new()
	look.name = "Mesh"
	look.mesh = mesh
	walks.add_child(look)
	var body := StaticBody3D.new()
	body.name = "Body"
	walks.add_child(body)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	cs.shape = shape
	body.add_child(cs)
	for n in [look, body, cs]:
		n.owner = walks
	var scene := PackedScene.new()
	var err := scene.pack(walks)
	if err == OK:
		err = ResourceSaver.save(scene, OUT_PATH, ResourceSaver.FLAG_COMPRESS)
	print("Saved %s: %s" % [OUT_PATH, error_string(err)])
	walks.free()
	quit(0 if err == OK else 1)


## The route's ways as lines in world metres, straight from OpenStreetMap.
static func _route_lines() -> Array[PackedVector2Array]:
	var p := deg_to_rad(BuildWorld.LAT0)
	var mz := 111132.92 - 559.82 * cos(2.0 * p) + 1.175 * cos(4.0 * p)
	var mx := 111412.84 * cos(p) - 93.5 * cos(3.0 * p)
	var osm: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/osm.json"))
	var out: Array[PackedVector2Array] = []
	for el: Dictionary in osm["elements"]:
		if el["type"] == "way" and int(el["id"]) in ROUTE:
			var line := PackedVector2Array()
			for g: Dictionary in el["geometry"]:
				line.append(Vector2((g["lon"] - BuildWorld.LON0) * mx, -(g["lat"] - BuildWorld.LAT0) * mz))
			out.append(line)
	return out


static func _distance_to_line(p: Vector2, line: PackedVector2Array) -> float:
	var best := INF
	for k in line.size() - 1:
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, line[k], line[k + 1])))
	return best


## The stretches of sidewalk along one side of a road run (side 1 is the left of
## its direction), as lists of [inner edge, outer edge] points at STEP spacing.
func _side_runs(road: Dictionary, side: float, roads: Array, on_route: Dictionary) -> Array:
	var pts: PackedVector2Array = road["pts"]
	var hw: float = road["hw"]
	var runs := []
	var cur := []
	var total := 0.0
	for k in pts.size() - 1:
		total += pts[k].distance_to(pts[k + 1])
	var at := 0.0
	while at <= total:
		var sample := _along(pts, at)
		var c: Vector2 = sample[0]
		var n := Vector2(-sample[1].y, sample[1].x) * side
		# The same width all along: tools/clear_sidewalks.gd keeps walls and
		# buildings back from it.
		var inner := c + n * (hw + GAP)
		var outer := c + n * (hw + GAP + WIDTH)
		if not _median(c + n * (hw + MEDIAN), road, roads, on_route) and _clear(inner, outer, road, roads, on_route):
			cur.append([inner, outer])
		else:
			if cur.size() * STEP >= MIN_RUN:
				runs.append(cur)
			cur = []
		at += STEP
	if cur.size() * STEP >= MIN_RUN:
		runs.append(cur)
	return runs


## The point at a distance along a line, and the line's direction there.
func _along(pts: PackedVector2Array, at: float) -> Array:
	for k in pts.size() - 1:
		var seg := pts[k].distance_to(pts[k + 1])
		if at <= seg or k == pts.size() - 2:
			var dir := (pts[k + 1] - pts[k]).normalized()
			# Average with the neighbouring segments near the corners, so the sides bend smoothly.
			if at < 1.0 and k > 0:
				dir = (dir + (pts[k] - pts[k - 1]).normalized()).normalized()
			elif seg - at < 1.0 and k < pts.size() - 2:
				dir = (dir + (pts[k + 2] - pts[k + 1]).normalized()).normalized()
			return [pts[k] + (pts[k + 1] - pts[k]).normalized() * minf(at, seg), dir]
		at -= seg
	return [pts[pts.size() - 1], (pts[pts.size() - 1] - pts[pts.size() - 2]).normalized()]


## Whether a spot beside a one-way half of the dual carriageway lies towards the
## other half (in the median), where no sidewalk goes.
static func _median(probe: Vector2, road: Dictionary, roads: Array, on_route: Dictionary) -> bool:
	if not road.get("oneway", false):
		return false
	for i: int in on_route:
		var other: Dictionary = roads[i]
		if other != road and other.get("oneway", false) and _distance_to_line(probe, other["pts"]) < other["hw"] + MEDIAN:
			return true
	return false


## Whether a slice of sidewalk can go here: not on any road (other runs of the
## route included, which leaves out the inner side of the dual carriageway), not
## at a junction, and not into anything solid.
func _clear(inner: Vector2, outer: Vector2, road: Dictionary, roads: Array, on_route: Dictionary) -> bool:
	var mid := (inner + outer) * 0.5
	for i in roads.size():
		var other: Dictionary = roads[i]
		if other == road:
			continue
		var room: float = other["hw"] + (0.3 if on_route.has(i) else JUNCTION)
		if other["kind"] == 2:
			continue # footpaths may run alongside
		var opts: PackedVector2Array = other["pts"]
		var lo := opts[0]
		var hi := opts[0]
		for q in opts:
			lo = lo.min(q)
			hi = hi.max(q)
		if mid.x < lo.x - room - WIDTH or mid.x > hi.x + room + WIDTH or mid.y < lo.y - room - WIDTH or mid.y > hi.y + room + WIDTH:
			continue
		for p in [inner, mid, outer]:
			if _distance_to_line(p, opts) < room:
				return false
	# Walls, fences and buildings are trimesh shapes, which have no inside for a
	# point to be in: look for them with rays instead. Straight down onto each
	# spot finds a roof or the top of a wall standing on it...
	for p in [inner, mid, outer]:
		var down := PhysicsRayQueryParameters3D.create(Vector3(p.x, 600.0, p.y), Vector3(p.x, _ground(p) + 0.05, p.y))
		while true:
			var hit := _space.intersect_ray(down)
			if hit.is_empty():
				break
			if (hit["collider"] as CollisionObject3D).get_rid() in _solid:
				var spot := Vector2i(roundi(p.x / 10.0) * 10, roundi(p.y / 10.0) * 10)
				_blocked[spot] = "%s, hit at %s" % [(hit["collider"] as Node).get_path(), hit["position"]]
				return false
			down.exclude = down.exclude + [hit["rid"]]
	return true


func _ground(p: Vector2) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 600.0, p.y), Vector3(p.x, -300.0, p.y))
	q.exclude = _ground_skip
	var hit := _space.intersect_ray(q)
	return hit["position"].y if hit else 0.0


## One stretch of sidewalk: a paved top KERB above the road edge (into tops), and
## in concrete (into edges) the kerb face down to the road, a bank down to the
## ground on the outside and the two ends.
func _add_walk(tops: SurfaceTool, edges: SurfaceTool, faces: PackedVector3Array, run: Array) -> void:
	var kerb := Color(0.78, 0.77, 0.74).srgb_to_linear()
	var side := Color(0.58, 0.56, 0.52).srgb_to_linear()
	var rows := []
	for slice in run:
		var a: Vector2 = slice[0]
		var b: Vector2 = slice[1]
		var road_y := _ground(a) + 0.04
		var top_y := maxf(road_y + KERB, _ground(b) + 0.03)
		# Where the ground falls away from the road, the walkway ends in a bank that
		# runs down to it at 45 degrees (at most SKIRT metres out) rather than a sheer
		# drop, so its side can be seen from the walkway and the road.
		var out2 := (b - a).normalized()
		var drop := top_y - _ground(b)
		var foot := b + out2 * clampf(drop, 0.1, SKIRT)
		rows.append([Vector3(a.x, road_y - 0.05, a.y), Vector3(a.x, top_y, a.y),
			Vector3(b.x, top_y, b.y), Vector3(foot.x, _ground(foot) - 0.05, foot.y)])
	# Metres along the kerb, for the paving to run with the street.
	var along := [0.0]
	for k in range(1, rows.size()):
		var step: Vector3 = rows[k][1] - rows[k - 1][1]
		along.append(along[k - 1] + Vector2(step.x, step.z).length())
	for k in rows.size() - 1:
		var r0: Array = rows[k]
		var r1: Array = rows[k + 1]
		var u0: float = along[k] / PAVER_SIZE.x
		var u1: float = along[k + 1] / PAVER_SIZE.x
		var w0: float = Vector2(r0[2].x - r0[1].x, r0[2].z - r0[1].z).length() / PAVER_SIZE.y
		var w1: float = Vector2(r1[2].x - r1[1].x, r1[2].z - r1[1].z).length() / PAVER_SIZE.y
		var out: Vector3 = r0[2] - r0[1]
		out.y = 0.0
		out = out.normalized()
		var bank: Vector3 = (r0[3] - r0[2]).cross(r1[2] - r0[2]).normalized()
		if bank.dot(out + Vector3.UP) < 0.0:
			bank = -bank
		_quad(edges, PackedVector3Array(), r0[0], r0[1], r1[1], r1[0], -out, kerb) # kerb face, towards the road
		var f0 := _ramp_foot(r0[1], -out)
		var f1 := _ramp_foot(r1[1], -out)
		_quad_faces(faces, f0, r0[1], r1[1], f1, -out + Vector3.UP) # the ramp up it, felt but not seen
		_quad(tops, faces, r0[1], r0[2], r1[2], r1[1], Vector3.UP, Color.WHITE,
			[Vector2(u0, 0.0), Vector2(u0, w0), Vector2(u1, w1), Vector2(u1, 0.0)]) # walkway
		_quad(edges, faces, r0[2], r0[3], r1[3], r1[2], bank, side) # bank down to the ground
	# Close both ends, where the sidewalk stops at a gap.
	for end in [[rows[0], rows[1]], [rows[rows.size() - 1], rows[rows.size() - 2]]]:
		var r: Array = end[0]
		var away: Vector3 = r[1] - end[1][1]
		away.y = 0.0
		away = away.normalized()
		_quad(edges, PackedVector3Array(), r[0], r[1], r[2], r[3], away, side)
		_quad_faces(faces, r[1], r[2], _ramp_foot(r[2], away), _ramp_foot(r[1], away), away + Vector3.UP)


## Where the collision ramp from a top edge of the walkway meets the ground, out
## along `out` (level), a little under the road surface so there is no lip.
func _ramp_foot(top: Vector3, out: Vector3) -> Vector3:
	var p := top + out * RAMP
	var ground := _ground(Vector2(p.x, p.z))
	p = top + out * clampf((top.y - ground) * 4.0, RAMP, 2.0)
	return Vector3(p.x, _ground(Vector2(p.x, p.z)) - 0.01, p.z)


## Two triangles of collision only, facing n.
func _quad_faces(faces: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	for tri: Array in [[a, b, c], [a, c, d]]:
		if (tri[1] - tri[0]).cross(tri[2] - tri[0]).dot(n) > 0.0:
			tri = [tri[0], tri[2], tri[1]]
		faces.append_array(PackedVector3Array(tri))


## Two triangles facing the given normal. Godot's front faces wind clockwise, so
## each triangle is turned until (b - a) x (c - a) points away from n; the back
## face would otherwise be drawn and lit as if facing the other way. uvs, when
## given, are those of a, b, c and d.
func _quad(st: SurfaceTool, faces: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col: Color, uvs := []) -> void:
	for tri: Array in [[0, 1, 2], [0, 2, 3]]:
		var corners := [a, b, c, d]
		if (corners[tri[1]] - corners[tri[0]]).cross(corners[tri[2]] - corners[tri[0]]).dot(n) > 0.0:
			tri = [tri[0], tri[2], tri[1]]
		for i: int in tri:
			st.set_color(col)
			st.set_normal(n)
			if not uvs.is_empty():
				st.set_uv(uvs[i])
			st.add_vertex(corners[i])
			faces.append(corners[i])
