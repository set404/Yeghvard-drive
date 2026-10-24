extends Node3D
## The people of the town: they walk along the sidewalks (world/sidewalks.scn),
## stop to look about or at their phones, and stop in pairs to talk. Only those
## near you are kept: as you go, people farther than despawn_distance leave and
## new ones come in out at spawn_min..spawn_max metres.
## The sidewalks are in pieces (they break where a road joins), so the end of
## each is linked to the nearest piece on the same side of the road
## (_build_links): at the end of a piece people walk on to it, over the side
## street, or turn back if there is none. The main road they cross only at a
## crosswalk (world/crosswalk.gd), and only some of those who pass one. They
## wait at the kerb until no car is close or coming (traffic_on).
## The figures are the scenes in res://npc (tools/build_npcs.gd); each person
## is run by npc/npc.gd. A car that runs into someone knocks them down dead.

const Npc := preload("res://npc/npc.gd")
## The physics layer the people's bodies are on: you bump into them, cars do not.
const BODY_LAYER := 1 << 9

## The sidewalks they walk on.
@export var sidewalks: Node3D
## You (on foot): made to bump into them.
@export var player: CharacterBody3D
## How many people about you at a time.
@export var count := 16
## Metres from you where new people come in, and where they leave.
@export var spawn_min := 30.0
@export var spawn_max := 110.0
@export var despawn_distance := 150.0
## Share of newcomers that come in as a pair already talking, and that come in standing.
@export var pair_share := 0.3
@export var standing_share := 0.2
## How often (chance) two walkers who meet stop to talk.
@export var meet_chance := 0.3
## A car going at least this fast (km/h) knocks down whoever it runs into.
@export var deadly_speed := 8.0
@export_group("Crossing the road")
## How far from the end of a sidewalk the next one on the same side may be to
## walk on to it (metres), and how far towards the road (its kerb side) the way
## there may go: more than that and it is across the road.
@export var end_link_reach := 26.0
@export var same_side_offset := 3.0
## Chance a walker passing a crosswalk takes it, and that one at the end of
## their sidewalk walks on to the next rather than turning back.
@export var crosswalk_chance := 0.5
## Chance a walker passing where another sidewalk joins theirs (round a corner) turns on to it.
@export var turn_chance := 0.25
@export var end_cross_chance := 0.85
## A car this close to the crossing (metres), or getting there within
## car_warning seconds, keeps people waiting at the kerb.
@export var car_clearance := 6.0
@export var car_warning := 4.5
@export_group("")

## Each sidewalk as points along its middle (metres, world space), with the
## walkway's width and the distance along it at each point.
var _points: Array[PackedVector3Array] = []
var _widths: Array[PackedFloat32Array] = []
var _distances: Array[PackedFloat32Array] = []
## At each point, the level direction from the middle of the walkway to its kerb (the road).
var _kerbs: Array[PackedVector3Array] = []
## The links from each sidewalk to others, by sidewalk: [{"at": metres along
## this one, "to_path", "to_at": where it comes out, "via": the points walked
## through on the way (a crosswalk's two ends; empty for a side street),
## "crosswalk": bool, "ok": null until checked, then whether the way across is
## clear (link_ok)}].
var _links: Array[Array] = []
var _figures: Array[PackedScene] = []
var _people: Array[Node3D] = []
var _tick := 0.0
## Each car's half size (see _half_size), by car.
var _car_sizes := {}


func _ready() -> void:
	for file in DirAccess.get_files_at("res://npc"):
		file = file.trim_suffix(".remap")
		if file.get_extension() == "scn":
			_figures.append(load("res://npc/" + file))
	if sidewalks:
		_read_sidewalks(sidewalks.get_node("Mesh") as MeshInstance3D)
	var t0 := Time.get_ticks_usec()
	_build_links()
	if player:
		player.collision_mask |= BODY_LAYER
	var links := 0
	for l in _links:
		links += l.size()
	print("Townsfolk: %d figures, %d sidewalks, %d links, %d crosswalks (%.0f ms)" % [
		_figures.size(), _points.size(), links / 2, get_tree().get_nodes_in_group("crosswalks").size(),
		(Time.get_ticks_usec() - t0) / 1000.0])


## The sidewalks' walkways from their mesh: tools/build_sidewalks.gd lays each
## piece of walkway as quads along the road, the first surface, with UV x running
## along it and UV y across it (0 at the kerb).
func _read_sidewalks(mesh_instance: MeshInstance3D) -> void:
	if mesh_instance == null or mesh_instance.mesh == null:
		return
	var arr := mesh_instance.mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if idx.is_empty():
		idx.resize(v.size())
		for i in v.size():
			idx[i] = i
	var xf := mesh_instance.global_transform
	var points := PackedVector3Array()
	var widths := PackedFloat32Array()
	var kerbs := PackedVector3Array()
	# Each quad is two triangles, six corners in a row.
	for q in range(0, idx.size() - 5, 6):
		var corners := {}
		for k in 6:
			var i := idx[q + k]
			corners[uv[i]] = xf * v[i]
		if corners.size() != 4:
			continue
		var keys: Array = corners.keys()
		keys.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
		# Sorted along, then across: [kerb, outer] at the start, then at the end.
		var start: Vector3 = (corners[keys[0]] + corners[keys[1]]) * 0.5
		var end: Vector3 = (corners[keys[2]] + corners[keys[3]]) * 0.5
		var width: float = (corners[keys[0]] as Vector3).distance_to(corners[keys[1]])
		# UV y is 0 at the kerb: the first of each pair across.
		var kerb_start := _level(corners[keys[0]] - start)
		var kerb_end := _level(corners[keys[2]] - end)
		if points.is_empty() or points[points.size() - 1].distance_to(start) > 0.05:
			_add_path(points, widths, kerbs)
			points = PackedVector3Array([start])
			widths = PackedFloat32Array([width])
			kerbs = PackedVector3Array([kerb_start])
		points.append(end)
		widths.append(width)
		kerbs.append(kerb_end)
	_add_path(points, widths, kerbs)


static func _level(v: Vector3) -> Vector3:
	v.y = 0.0
	return v.normalized() if v.length() > 0.0001 else Vector3.ZERO


func _add_path(points: PackedVector3Array, widths: PackedFloat32Array, kerbs: PackedVector3Array) -> void:
	if points.size() < 4:
		return
	var distances := PackedFloat32Array([0.0])
	for i in range(1, points.size()):
		distances.append(distances[i - 1] + points[i].distance_to(points[i - 1]))
	if distances[distances.size() - 1] < 8.0:
		return
	_points.append(points)
	_widths.append(widths)
	_distances.append(distances)
	_kerbs.append(kerbs)


## How many sidewalks there are (for the taxi's fares, game/taxi.gd).
func path_count() -> int:
	return _points.size()


## One of the townspeople's figures (res://npc), or null if there are none.
func random_figure() -> PackedScene:
	return _figures.pick_random() if not _figures.is_empty() else null


func path_length(i: int) -> float:
	return _distances[i][_distances[i].size() - 1]


## Where on sidewalk `i` the point `at` metres along is: its "position",
## "forward" (the way the sidewalk runs, level), walkway "width" and "kerb"
## (the level way to the road).
func point_on(i: int, at: float) -> Dictionary:
	var d := _distances[i]
	var pts := _points[i]
	var k := d.bsearch(at)
	k = clampi(k, 1, pts.size() - 1)
	var span := maxf(d[k] - d[k - 1], 0.001)
	var t := clampf((at - d[k - 1]) / span, 0.0, 1.0)
	var forward := pts[k] - pts[k - 1]
	forward.y = 0.0
	return {
		"position": pts[k - 1].lerp(pts[k], t),
		"forward": forward.normalized() if forward.length() > 0.001 else Vector3.FORWARD,
		"width": lerpf(_widths[i][k - 1], _widths[i][k], t),
		"kerb": _kerbs[i][k - 1].lerp(_kerbs[i][k], t).normalized(),
	}


# --- crossing from one sidewalk to another ---------------------------------

## The links from sidewalk `i` at its end `at` (0 or its length).
func links_at_end(i: int, at: float) -> Array:
	return _links[i].filter(func(l: Dictionary) -> bool: return absf(l["at"] - at) < 1.5)


## The links along sidewalk `i` a walker went past going from `from` to `to`
## metres along (not those at its ends): crosswalks, mostly.
func links_passed(i: int, from: float, to: float) -> Array:
	var lo := minf(from, to)
	var hi := maxf(from, to)
	var length := path_length(i)
	return _links[i].filter(func(l: Dictionary) -> bool:
		return l["at"] > lo and l["at"] <= hi and l["at"] > 1.5 and l["at"] < length - 1.5)


## Whether the way across a link is clear: nothing solid in the way (a wall, a
## building) at waist height, no big drop or climb, ground all the way. Checked
## the first time someone wants to cross there, then remembered.
func link_ok(link: Dictionary, from: int) -> bool:
	if link["ok"] != null:
		return link["ok"]
	if link["crosswalk"]:
		link["ok"] = true
		return true
	var a: Vector3 = point_on(from, link["at"])["position"]
	var b: Vector3 = point_on(link["to_path"], link["to_at"])["position"]
	var ok := absf(a.y - b.y) < 2.5
	var space := get_world_3d().direct_space_state
	var skip: Array[RID] = []
	for car: CollisionObject3D in get_tree().get_nodes_in_group("cars"):
		skip.append(car.get_rid())
	if ok:
		var ray := PhysicsRayQueryParameters3D.create(a + Vector3.UP, b + Vector3.UP)
		ray.collision_mask = 1
		ray.exclude = skip
		ok = space.intersect_ray(ray).is_empty()
	# The ground along the way: no ditch or drop.
	for t: float in [0.25, 0.5, 0.75]:
		if not ok:
			break
		var at := a.lerp(b, t)
		var down := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 2.0, at + Vector3.DOWN * 3.0)
		down.collision_mask = 1
		down.exclude = skip
		ok = not space.intersect_ray(down).is_empty()
	link["ok"] = ok
	return ok


## Whether a car is on or about to be on the way from `a` to `b`: within
## car_clearance of it, or coming at it fast enough to get there in car_warning seconds.
func traffic_on(a: Vector3, b: Vector3) -> bool:
	for car: VehicleBody3D in get_tree().get_nodes_in_group("cars"):
		var p := car.global_position
		var c := Geometry3D.get_closest_point_to_segment(p, a, b)
		var gap := Vector2(c.x - p.x, c.z - p.z)
		var d := gap.length()
		var v := Vector2(car.linear_velocity.x, car.linear_velocity.z)
		if d < car_clearance and (v.length() > 0.5 or d < 2.5):
			return true
		if d < 0.01:
			continue
		var closing := v.dot(gap / d)
		if closing > 1.0 and (d - car_clearance) / closing < car_warning:
			return true
	return false


## Links the sidewalks: the end of each to the nearest one on the same side of
## the road (over a side street, round a corner), and the two sides of the road
## at each crosswalk. Both ways.
func _build_links() -> void:
	_links.clear()
	for i in _points.size():
		_links.append([])
	var grid := _segment_grid()
	var seen := {}
	for i in _points.size():
		var length := path_length(i)
		for at: float in [0.0, length]:
			var where := point_on(i, at)
			var here: Vector3 = where["position"]
			var best := {}
			for n in _nearest_on_others(grid, here, end_link_reach, i):
				var to: Vector3 = n["position"] - here
				to.y = 0.0
				# Neither side may have to head out over its own road to get to the other.
				var theirs: Vector3 = point_on(n["path"], n["at"])["kerb"]
				if to.dot(where["kerb"]) > same_side_offset or (-to).dot(theirs) > same_side_offset:
					continue # across the road
				if best.is_empty() or n["d"] < best["d"]:
					best = n
			if not best.is_empty():
				_link(seen, i, at, best["path"], best["at"])
	for walk: Node3D in get_tree().get_nodes_in_group("crosswalks"):
		_link_crosswalk(grid, walk)


## The sidewalks at the two ends of a crosswalk, linked through it.
func _link_crosswalk(grid: Dictionary, walk: Node3D) -> void:
	var ends: PackedVector3Array = walk.ends()
	var sides: Array[Dictionary] = []
	for e in ends:
		var near := _nearest_on_others(grid, e, walk.reach, -1)
		near.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x["d"] < y["d"])
		if near.is_empty():
			push_warning("%s: no sidewalk within %.1f m of its end at %s" % [walk.get_path(), walk.reach, e])
			return
		sides.append(near[0])
	if sides[0]["path"] == sides[1]["path"]:
		push_warning("%s: both ends come out on the same sidewalk" % walk.get_path())
		return
	var a := sides[0]
	var b := sides[1]
	_links[a["path"]].append({"at": a["at"], "to_path": b["path"], "to_at": b["at"],
		"via": PackedVector3Array([ends[0], ends[1]]), "crosswalk": true, "ok": true})
	_links[b["path"]].append({"at": b["at"], "to_path": a["path"], "to_at": a["at"],
		"via": PackedVector3Array([ends[1], ends[0]]), "crosswalk": true, "ok": true})


func _link(seen: Dictionary, i: int, at: float, j: int, to_at: float) -> void:
	var key := "%d:%d:%d:%d" % [mini(i, j), maxi(i, j), roundi((at if i < j else to_at) / 6.0), roundi((to_at if i < j else at) / 6.0)]
	if seen.has(key):
		return
	seen[key] = true
	_links[i].append({"at": at, "to_path": j, "to_at": to_at, "via": PackedVector3Array(), "crosswalk": false, "ok": null})
	_links[j].append({"at": to_at, "to_path": i, "to_at": at, "via": PackedVector3Array(), "crosswalk": false, "ok": null})


const GRID_CELL := 20.0


## Every sidewalk segment, by the grid cells (GRID_CELL metres) it touches: Vector2i -> [[path, k]].
func _segment_grid() -> Dictionary:
	var grid := {}
	for i in _points.size():
		var pts := _points[i]
		for k in range(1, pts.size()):
			var lo := Vector2(minf(pts[k - 1].x, pts[k].x), minf(pts[k - 1].z, pts[k].z))
			var hi := Vector2(maxf(pts[k - 1].x, pts[k].x), maxf(pts[k - 1].z, pts[k].z))
			for cx in range(floori(lo.x / GRID_CELL), floori(hi.x / GRID_CELL) + 1):
				for cz in range(floori(lo.y / GRID_CELL), floori(hi.y / GRID_CELL) + 1):
					var cell := Vector2i(cx, cz)
					if not grid.has(cell):
						grid[cell] = []
					grid[cell].append(Vector2i(i, k))
	return grid


## The nearest point of each other sidewalk within `reach` of `at` (across the
## ground): [{"path", "at" (metres along it), "position", "d"}].
func _nearest_on_others(grid: Dictionary, at: Vector3, reach: float, skip: int) -> Array:
	var best := {}
	for cx in range(floori((at.x - reach) / GRID_CELL), floori((at.x + reach) / GRID_CELL) + 1):
		for cz in range(floori((at.z - reach) / GRID_CELL), floori((at.z + reach) / GRID_CELL) + 1):
			for seg: Vector2i in grid.get(Vector2i(cx, cz), []):
				var j := seg.x
				if j == skip:
					continue
				var a := _points[j][seg.y - 1]
				var b := _points[j][seg.y]
				var c := Geometry3D.get_closest_point_to_segment(at, a, b)
				if absf(c.y - at.y) > 3.0:
					continue
				var d := Vector2(c.x - at.x, c.z - at.z).length()
				if d > reach or (best.has(j) and best[j]["d"] <= d):
					continue
				best[j] = {"path": j, "at": _distances[j][seg.y - 1] + a.distance_to(c), "position": c, "d": d}
	return best.values()


## Whether a walker has someone just ahead in their way: you, or someone
## slower or standing on the same side of the walkway.
func blocked(who: Node3D) -> bool:
	var ahead := who.global_basis.z
	var me := who.global_position
	var others: Array[Node3D] = []
	if player and player.is_physics_processing():
		others.append(player)
	for p: Node3D in _people:
		if p != who:
			others.append(p)
	for other in others:
		var to := other.global_position - me
		if absf(to.y) > 1.5:
			continue
		to.y = 0.0
		var front := to.dot(ahead)
		if front > 0.1 and front < 1.1 and absf(to.cross(ahead).y) < 0.45:
			# Two walkers face to face step round each other (they keep right).
			if other is Npc and other.state in [Npc.State.WALK, Npc.State.CROSS] and other.global_basis.z.dot(ahead) < 0.0:
				continue
			return true
	return false


func _process(delta: float) -> void:
	_run_over()
	_tick -= delta
	if _tick > 0.0 or _figures.is_empty() or _points.is_empty():
		return
	_tick = 0.5
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var focus := camera.global_position
	# Those who are far away go home.
	for p in _people.duplicate():
		if Vector2(p.global_position.x - focus.x, p.global_position.z - focus.z).length() > despawn_distance:
			_remove(p)
	# Walkers who meet may stop to talk.
	for a in _people:
		if a.state != Npc.State.WALK or a.talk_cooldown > 0.0:
			continue
		for b in _people:
			if b == a or b.state != Npc.State.WALK or b.talk_cooldown > 0.0:
				continue
			if a.global_position.distance_to(b.global_position) < 1.6:
				a.talk_cooldown = 30.0
				b.talk_cooldown = 30.0
				if randf() < meet_chance:
					var seconds := randf_range(10.0, 25.0)
					a.talk_to(b, seconds, true)
					b.talk_to(a, seconds, false)
				break
	# Newcomers, a few at a time.
	for n in 2:
		if _people.size() >= count:
			break
		_spawn(focus)


## Anyone a moving car is driving into is knocked down.
func _run_over() -> void:
	for car: VehicleBody3D in get_tree().get_nodes_in_group("cars"):
		var v := car.linear_velocity
		if v.length() * 3.6 < deadly_speed:
			continue
		if not _car_sizes.has(car):
			_car_sizes[car] = _half_size(car)
		var half: Vector3 = _car_sizes[car]
		var reach := half.length() + 1.0
		for p in _people.duplicate():
			if p.global_position.distance_to(car.global_position) > reach:
				continue
			# Their middle, in the car's own space, inside its box (with a little to spare).
			var local := car.to_local(p.global_position + Vector3.UP * 0.9)
			if absf(local.x) < half.x + 0.25 and absf(local.z) < half.z + 0.25 and local.y < half.y + 0.5 and local.y > -1.2:
				_people.erase(p)
				p.die(v)


## How far a car's collision boxes reach from its origin along each axis.
func _half_size(body: VehicleBody3D) -> Vector3:
	var half := Vector3(0.95, 0.75, 2.3)
	var found := false
	for child in body.get_children():
		var cs := child as CollisionShape3D
		if cs == null or not cs.shape is BoxShape3D:
			continue
		var box: Vector3 = (cs.shape as BoxShape3D).size * 0.5
		var reach := cs.position.abs() + box
		half = reach if not found else half.max(reach)
		found = true
	return half


func _remove(p: Node3D) -> void:
	_people.erase(p)
	for other in _people:
		if other.partner == p:
			other.partner = null
	p.queue_free()


func _spawn(focus: Vector3) -> void:
	# A random spot on a sidewalk in the ring about you.
	for attempt in 24:
		var i := randi() % _points.size()
		var at := randf() * path_length(i)
		var where := point_on(i, at)
		var flat := Vector2(where["position"].x - focus.x, where["position"].z - focus.z).length()
		if flat < spawn_min or flat > spawn_max or absf(where["position"].y - focus.y) > 40.0:
			continue
		var roll := randf()
		if roll < pair_share and _people.size() + 2 <= count:
			var a := _person(i, at, 1.0)
			var b := _person(i, minf(at + 1.1, path_length(i)), -1.0)
			var seconds := randf_range(15.0, 40.0)
			a.talk_to(b, seconds, true)
			b.talk_to(a, seconds, false)
		elif roll < pair_share + standing_share:
			_person(i, at, 1.0 if randf() < 0.5 else -1.0).stand(randf_range(6.0, 20.0))
		else:
			_person(i, at, 1.0 if randf() < 0.5 else -1.0)
		return


func _person(i: int, at: float, way: float) -> Node3D:
	var p := Npc.new()
	p.name = "Person"
	add_child(p)
	p.setup(self, _figures.pick_random(), BODY_LAYER)
	p.walk(i, at, way)
	p.talk_cooldown = randf_range(5.0, 20.0)
	_people.append(p)
	return p
