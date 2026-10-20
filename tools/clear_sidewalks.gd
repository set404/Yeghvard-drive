extends SceneTree
## Moves the buildings and walls of the editable map (world/map/map.tscn) back
## off the sidewalks, so tools/build_sidewalks.gd can lay them the full width all
## along the route. Anything closer to a route road than its edge plus the
## sidewalk (plus CLEARANCE) is pushed straight out from the road: a building as
## a whole, a wall corner by corner (with a corner added where a wall cuts across
## without one of its corners being in the way).
##
## Leaves alone what is beside the junctions (no sidewalk goes there) and on the
## inner side of the dual carriageway. Then bake the map (tools/bake_map.gd) and
## build the sidewalks again.
##
## Run:  godot --headless --path . --script res://tools/clear_sidewalks.gd

const BuildWorld := preload("res://tools/build_world.gd")
const Sidewalks := preload("res://tools/build_sidewalks.gd")
const MAP_BUILDING := preload("res://world/map/map_building.gd")
const MAP_WALL := preload("res://world/map/map_wall.gd")
const MAP_PATH := "res://world/map/map.tscn"
## Room left between the back of the sidewalk and the line of a wall or a building
## (a stone wall's square pillars reach 0.35 m out from it).
const CLEARANCE := 0.45
## Pushes longer than this are reported, to look at.
const FAR := 4.0

## Metres: the side of a cell of the grids below.
const CELL := 16.0

var _roads: Array
var _on_route: Dictionary
var _reach: float
## Vector2i cell -> [[road, segment], ...]: the route's segments, and the other
## roads' (those that join it), each in every cell it reaches into.
var _route_grid := {}
var _side_grid := {}


func _initialize() -> void:
	var lines := Sidewalks._route_lines()
	var bw = BuildWorld.new()
	var p := deg_to_rad(BuildWorld.LAT0)
	bw.mz = 111132.92 - 559.82 * cos(2.0 * p) + 1.175 * cos(4.0 * p)
	bw.mx = 111412.84 * cos(p) - 93.5 * cos(3.0 * p)
	bw._parse_osm()
	for i in bw.roads.size():
		var mid: Vector2 = bw.roads[i]["pts"][bw.roads[i]["pts"].size() / 2]
		for line in lines:
			if Sidewalks._distance_to_line(mid, line) < 0.5:
				_on_route[i] = true
	bw._pair_carriageways()
	_roads = bw.roads
	bw.free()
	_reach = Sidewalks.GAP + Sidewalks.WIDTH + CLEARANCE
	for i in _roads.size():
		var road: Dictionary = _roads[i]
		if _on_route.has(i):
			_grid_road(_route_grid, i, road["hw"] + _reach)
		elif road["kind"] != 2:
			_grid_road(_side_grid, i, road["hw"] + Sidewalks.JUNCTION)

	var map: Node3D = (load(MAP_PATH) as PackedScene).instantiate()
	var buildings := 0
	var walls := 0
	var corners := 0
	for node in map.find_children("*", "", true, false):
		var script: Script = node.get_script()
		if script == MAP_BUILDING:
			if _clear_building(node):
				buildings += 1
		elif script == MAP_WALL:
			var n := _clear_wall(node)
			if n > 0:
				walls += 1
				corners += n
	var behind := _part_buildings(map)
	var scene := PackedScene.new()
	var err := scene.pack(map)
	if err == OK:
		err = ResourceSaver.save(scene, MAP_PATH)
	map.free()
	print("Moved back %d buildings and %d walls (%d corners), and %d buildings behind them -> %s (%s)" % [buildings, walls, corners, behind, MAP_PATH, error_string(err)])
	quit(0 if err == OK else 1)


func _grid_road(grid: Dictionary, i: int, reach: float) -> void:
	var pts: PackedVector2Array = _roads[i]["pts"]
	for k in pts.size() - 1:
		var lo := pts[k].min(pts[k + 1]) - Vector2.ONE * reach
		var hi := pts[k].max(pts[k + 1]) + Vector2.ONE * reach
		for cx in range(floori(lo.x / CELL), floori(hi.x / CELL) + 1):
			for cz in range(floori(lo.y / CELL), floori(hi.y / CELL) + 1):
				var key := Vector2i(cx, cz)
				if not grid.has(key):
					grid[key] = []
				grid[key].append([i, k])


func _cell(q: Vector2) -> Vector2i:
	return Vector2i(floori(q.x / CELL), floori(q.y / CELL))


## How far, and which way, a point has to go to be clear of the sidewalks.
func _push(q: Vector2) -> Vector2:
	var out := Vector2.ZERO
	var near := {} # road -> [distance, closest point, segment]
	for entry: Array in _route_grid.get(_cell(q), []):
		var pts: PackedVector2Array = _roads[entry[0]]["pts"]
		var k: int = entry[1]
		var c := Geometry2D.get_closest_point_to_segment(q, pts[k], pts[k + 1])
		var d := q.distance_to(c)
		if not near.has(entry[0]) or d < near[entry[0]][0]:
			near[entry[0]] = [d, c, k]
	for i: int in near:
		var road: Dictionary = _roads[i]
		var pts: PackedVector2Array = road["pts"]
		var need: float = road["hw"] + _reach
		var best: float = near[i][0]
		var best_c: Vector2 = near[i][1]
		var best_k: int = near[i][2]
		if best >= need or best < 0.01:
			continue
		# Past the end of the road, only where the route carries on from there.
		var at_end := (best_k == 0 and best_c.distance_to(pts[0]) < 0.01) or \
			(best_k == pts.size() - 2 and best_c.distance_to(pts[pts.size() - 1]) < 0.01)
		if at_end and not _joins_route(best_c, i):
			continue
		var n := (q - best_c) / best
		if Sidewalks._median(best_c + n * (road["hw"] + Sidewalks.MEDIAN), road, _roads, _on_route):
			continue
		if _at_junction(q):
			continue
		var p := n * (need - best)
		if p.length() > out.length():
			out = p
	return out


func _joins_route(end: Vector2, me: int) -> bool:
	for i: int in _on_route:
		if i == me:
			continue
		var pts: PackedVector2Array = _roads[i]["pts"]
		if pts[0].distance_to(end) < 1.0 or pts[pts.size() - 1].distance_to(end) < 1.0:
			return true
	return false


## Whether a point is where a road joins the route, where the sidewalk breaks.
func _at_junction(q: Vector2) -> bool:
	for entry: Array in _side_grid.get(_cell(q), []):
		var road: Dictionary = _roads[entry[0]]
		var pts: PackedVector2Array = road["pts"]
		var k: int = entry[1]
		if q.distance_to(Geometry2D.get_closest_point_to_segment(q, pts[k], pts[k + 1])) < road["hw"] + Sidewalks.JUNCTION:
			return true
	return false


## Points round an outline (closed) or along a line, at most 0.5 m apart.
func _samples(pts: PackedVector2Array, closed: bool) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size() if closed else pts.size() - 1
	for k in n:
		var a := pts[k]
		var b := pts[(k + 1) % pts.size()]
		var steps := maxi(1, ceili(a.distance_to(b) / 0.5))
		for s in steps:
			out.append(a.lerp(b, float(s) / steps))
	if not closed:
		out.append(pts[pts.size() - 1])
	return out


func _clear_building(node: Node3D) -> bool:
	var total := Vector2.ZERO
	for _pass in 6:
		var worst := Vector2.ZERO
		for q in _samples(node.world_footprint(), true):
			var p := _push(q)
			if p.length() > worst.length():
				worst = p
		if worst.length() < 0.02:
			break
		_shift(node, worst * 1.02)
		total += worst
	if total.length() < 0.02:
		return false
	if total.length() > FAR:
		var at: Vector2 = node.world_footprint()[0]
		print("  far: %s moved %.1f m (at %.0f, %.0f)" % [node.name, total.length(), at.x, at.y])
	return true


## Buildings near the route that now run into each other (one moved back into
## the next): the one further from the road goes back too, until they are apart.
## Returns how many moved.
func _part_buildings(map: Node3D) -> int:
	var nodes: Array[Node3D] = []
	for node in map.find_children("*", "", true, false):
		if node.get_script() == MAP_BUILDING:
			nodes.append(node)
	var moved := {}
	for _pass in 10:
		var polys: Array[PackedVector2Array] = []
		var mids: Array[Vector2] = []
		for node in nodes:
			var poly: PackedVector2Array = node.world_footprint()
			polys.append(poly)
			var c := Vector2.ZERO
			for q in poly:
				c += q
			mids.append(c / poly.size())
		var parted := false
		for a in nodes.size():
			var away_a := _away(mids[a])
			if away_a[0] > 40.0:
				continue
			for b in nodes.size():
				if b == a or mids[a].distance_to(mids[b]) > 60.0 or _overlap(polys[a], polys[b]) < 0.5:
					continue
				var away_b := _away(mids[b])
				if away_b[0] < away_a[0]:
					continue # b is the nearer one: dealt with the other way round
				# b goes back from the road, the way a was pushed.
				var n: Vector2 = away_a[1]
				var far := nodes[b]
				var step := 0
				while step < 60 and _overlap(polys[a], far.world_footprint()) >= 0.5:
					_shift(far, n * 0.25)
					step += 1
				moved[far] = true
				parted = true
				polys[b] = far.world_footprint()
				var c := Vector2.ZERO
				for q in polys[b]:
					c += q
				mids[b] = c / polys[b].size()
		if not parted:
			break
	return moved.size()


## The distance from a point to the nearest road of the route, and the way away from it.
func _away(q: Vector2) -> Array:
	var best := INF
	var dir := Vector2.ZERO
	for i: int in _on_route:
		var pts: PackedVector2Array = _roads[i]["pts"]
		for k in pts.size() - 1:
			var c := Geometry2D.get_closest_point_to_segment(q, pts[k], pts[k + 1])
			var d := q.distance_to(c)
			if d < best and d > 0.01:
				best = d
				dir = (q - c) / d
	return [best, dir]


func _overlap(a: PackedVector2Array, b: PackedVector2Array) -> float:
	var total := 0.0
	for part in Geometry2D.intersect_polygons(a, b):
		var area := 0.0
		for k in part.size():
			area += part[k].cross(part[(k + 1) % part.size()])
		total += absf(area) * 0.5
	return total


func _shift(node: Node3D, by: Vector2) -> void:
	var parent := _world(node.get_parent())
	node.transform.origin += parent.basis.inverse() * Vector3(by.x, 0.0, by.y)


func _clear_wall(node: Path3D) -> int:
	var curve := node.curve
	if curve == null or curve.point_count < 2:
		return 0
	var to_local := _world(node).affine_inverse()
	var from_local := _world(node)
	var changed := {}
	for _pass in 6:
		var moved := false
		# The corners themselves.
		for i in curve.point_count:
			var w := from_local * curve.get_point_position(i)
			var p := _push(Vector2(w.x, w.z))
			if p.length() < 0.02:
				continue
			curve.set_point_position(i, to_local * (w + Vector3(p.x, 0.0, p.y) * 1.02))
			changed[i] = true
			moved = true
		# A stretch cutting across with its corners clear: a corner where it is worst.
		var i := 0
		while i < curve.point_count - 1:
			var a := from_local * curve.get_point_position(i)
			var b := from_local * curve.get_point_position(i + 1)
			var worst := Vector2.ZERO
			var worst_t := 0.0
			var steps := maxi(2, ceili(a.distance_to(b) / 0.5))
			for s in range(1, steps):
				var t := float(s) / steps
				var w := a.lerp(b, t)
				var p := _push(Vector2(w.x, w.z))
				if p.length() > worst.length():
					worst = p
					worst_t = t
			if worst.length() >= 0.05:
				var w := a.lerp(b, worst_t) + Vector3(worst.x, 0.0, worst.y) * 1.02
				curve.add_point(to_local * w, Vector3.ZERO, Vector3.ZERO, i + 1)
				changed["added %d" % changed.size()] = true
				moved = true
				i += 1
			i += 1
		if not moved:
			break
	return changed.size()


func _world(node: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	while node:
		if node is Node3D:
			xf = (node as Node3D).transform * xf
		node = node.get_parent()
	return xf
