extends Node3D
## The town's traffic: cars that drive themselves along the roads, keeping to
## the right, slowing for bends, stopping for whoever is in their way (people,
## you, other cars) and turning at junctions as they please. Only those near
## you are kept: one that falls far behind, or gets stuck, comes back somewhere
## else out of sight, in a new colour.
##
## The roads come from the world's road mesh (tools/build_world.gd, _strip):
## every 3 m piece of road is six vertices in a row, left / middle / right at
## its start then at its end, with UV x 0, 0.5, 1 across, UV y the distance
## along, UV2 (width, lanes; negative lanes for one-way) and the colour's
## alpha the road class in sixteenths. The middles, joined where they meet,
## are the road network the cars drive on.
##
## The cars are the models of the cars placed in main.tscn, each painted a
## colour none of those has. Get into one (F) and it is yours; traffic lets go.

## Cars driving about you at a time.
@export var count := 12
## Metres from you where cars come in, and past which they leave.
@export var spawn_min := 70.0
@export var spawn_max := 210.0
@export var despawn_distance := 270.0
## Road classes cars drive on (tools/build_world.gd ROAD_TYPES priority): 2 is
## residential streets, 1 would add service roads and driveways.
@export var min_road_class := 2
## Speed in km/h by road class (2 streets, 3 tertiary, 4 secondary, 5 primary, 6 trunk).
@export var class_speeds := {2: 35.0, 3: 45.0, 4: 50.0, 5: 60.0, 6: 70.0}
## How hard they take bends (m/s² sideways) and brake for what is ahead (m/s²).
@export var bend_grip := 2.6
@export var comfort_brake := 3.0

## Body colours (sRGB), as car.gd's paint_color. Any close to a colour the
## cars in main.tscn already have is left out, so the traffic never matches them.
const PALETTE: Array[Color] = [
	Color(0.86, 0.86, 0.84), # white
	Color(0.015, 0.015, 0.017), # black
	Color(0.58, 0.04, 0.04), # red
	Color(0.30, 0.02, 0.06), # cherry
	Color(0.74, 0.66, 0.50), # beige
	Color(0.88, 0.66, 0.06), # yellow
	Color(0.82, 0.33, 0.05), # orange
	Color(0.38, 0.62, 0.82), # sky blue
	Color(0.26, 0.13, 0.06), # brown
	Color(0.64, 0.54, 0.34), # champagne
	Color(0.03, 0.38, 0.40), # teal
	Color(0.24, 0.07, 0.32), # purple
	Color(0.46, 0.50, 0.20), # olive
	Color(0.70, 0.20, 0.42), # raspberry
]
## How close (RGB distance) a colour may be to a placed car's and still be used.
const SAME_COLOUR := 0.12
const UP := Vector3.UP

## One car of the traffic and where it is going.
class Driver:
	var car: VehicleBody3D
	## The way ahead: graph nodes, the edges between them, the points along the
	## lane (offset to the right of the middle) and the distance to each.
	var nodes := PackedInt32Array()
	var edges := PackedInt32Array()
	var pts := PackedVector3Array()
	var cum := PackedFloat32Array()
	## The piece of the way the car is on (pts[k] to pts[k + 1]) and how far along it is.
	var k := 0
	var s := 0.0
	## True when the way ahead runs out (a one-way street into nowhere).
	var ends := false
	var cruise := 10.0 ## m/s on this road, with this driver's own temper
	var temper := 1.0
	var allowed := 0.0 ## m/s, from bends and what is in the way
	var plan_in := 0.0
	var blocker: Node3D
	var blocked_for := 0.0
	var ignore_cars_for := 0.0
	var stuck_for := 0.0
	var turn_signal := 0 ## -1 right, 1 left, 0 none


@onready var _main: Node3D = get_parent()

# The road network.
var _pos := PackedVector3Array()
var _out: Array[PackedInt32Array] = [] ## directed edges leaving each node
var _e_to := PackedInt32Array()
var _e_offset := PackedFloat32Array() ## metres from the middle to the lane, to the right
var _e_speed := PackedFloat32Array() ## m/s
var _grid := {} ## Vector2i cell -> PackedInt32Array of nodes that have a way out
const CELL := 40.0

var _scenes: Array[PackedScene] = []
var _colours: Array[Color] = []
var _drivers: Array[Driver] = []
var _manage_in := 1.5


func _ready() -> void:
	var t0 := Time.get_ticks_usec()
	var roads := _main.get_node_or_null("World")
	roads = roads.find_child("Roads", true, false) if roads else null
	if roads:
		_build_network(roads)
	# The models and colours: those of the cars placed in the scene.
	var taken: Array[Color] = []
	var paths := {}
	for car: Node in get_tree().get_nodes_in_group("cars"):
		taken.append(car.get("paint_color"))
		if car.scene_file_path != "":
			paths[car.scene_file_path] = true
	for path: String in paths:
		var scene := load(path) as PackedScene
		if scene:
			_scenes.append(scene)
	for c in PALETTE:
		var free := true
		for t in taken:
			if Vector3(c.r - t.r, c.g - t.g, c.b - t.b).length() < SAME_COLOUR:
				free = false
				break
		if free:
			_colours.append(c)
	if _colours.is_empty():
		_colours = PALETTE.duplicate()
	print("Traffic: %d road nodes, %d lanes, %d models, %d colours (%.0f ms)" % [
		_pos.size(), _e_to.size(), _scenes.size(), _colours.size(), (Time.get_ticks_usec() - t0) / 1000.0])


# --- the road network ----------------------------------------------------------

func _build_network(roads: Node) -> void:
	var index := {} # snapped position -> node
	var nbrs: Array[Dictionary] = [] # undirected neighbours, node -> {node: true}
	var node_hw := [] # widest half width at each node
	# Each piece of road: [a, b, half width, lanes, one way, speed].
	var pieces: Array = []
	var add_node := func(p: Vector3) -> int:
		var key := Vector2i(roundi(p.x * 10.0), roundi(p.z * 10.0))
		if index.has(key):
			return index[key]
		var id := _pos.size()
		index[key] = id
		_pos.append(p)
		nbrs.append({})
		node_hw.append(0.0)
		return id
	for mi: MeshInstance3D in roads.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var xf := mi.global_transform
		var arr := mi.mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		var uv2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2] if arr[Mesh.ARRAY_TEX_UV2] != null else PackedVector2Array()
		var col: PackedColorArray = arr[Mesh.ARRAY_COLOR] if arr[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		if uv2.size() != v.size() or col.size() != v.size():
			continue
		var i := 0
		var n := v.size()
		while i + 5 < n:
			if not (_near(uv[i].x, 0.0) and _near(uv[i + 1].x, 0.5) and _near(uv[i + 2].x, 1.0)
					and _near(uv[i + 3].x, 0.0) and _near(uv[i + 4].x, 0.5) and _near(uv[i + 5].x, 1.0)
					and uv[i + 4].y > uv[i + 1].y):
				i += 1
				continue
			var c := col[i]
			var road_class := roundi(c.a * 16.0) % 8
			# Asphalt is grey; dirt, footpaths and rail beds are tinted.
			if road_class >= min_road_class and absf(c.r - c.b) < 0.06:
				var hw := uv2[i].x * 0.5
				var lanes := uv2[i].y
				var a: int = add_node.call(xf * v[i + 1])
				var b: int = add_node.call(xf * v[i + 4])
				if a != b:
					var kmh: float = class_speeds.get(mini(road_class, 6), 40.0)
					pieces.append([a, b, hw, absi(roundi(lanes)), lanes < 0.0, kmh / 3.6])
					nbrs[a][b] = true
					nbrs[b][a] = true
					node_hw[a] = maxf(node_hw[a], hw)
					node_hw[b] = maxf(node_hw[b], hw)
			i += 6
	# Ends that stop short of the road they join (dual carriageways are slid
	# apart, so the side streets no longer meet them) are joined to it where
	# the two roads' surfaces touch.
	var near_grid := {}
	for id in _pos.size():
		near_grid.get_or_add(_cell_of(_pos[id], 10.0), []).append(id)
	for id in _pos.size():
		if nbrs[id].size() != 1:
			continue
		var own := _within_hops(nbrs, id, 6)
		var best := -1
		var best_d := INF
		var c := _cell_of(_pos[id], 10.0)
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				for other: int in near_grid.get(c + Vector2i(dx, dz), []):
					if own.has(other):
						continue
					var d := _flat(_pos[other] - _pos[id]).length()
					if d < best_d and d < node_hw[id] + node_hw[other] + 0.5 and absf(_pos[other].y - _pos[id].y) < 1.5:
						best = other
						best_d = d
		if best >= 0:
			pieces.append([id, best, minf(node_hw[id], node_hw[best]), 2, false, 25.0 / 3.6])
			nbrs[id][best] = true
			nbrs[best][id] = true
	# Dead ends (cul-de-sacs, roads off the edge of the map) are left out, so
	# that a car never drives into one: it could not turn round.
	var gone := PackedByteArray()
	gone.resize(_pos.size())
	var queue: Array[int] = []
	for id in _pos.size():
		if nbrs[id].size() <= 1:
			queue.append(id)
	while not queue.is_empty():
		var id: int = queue.pop_back()
		if gone[id]:
			continue
		gone[id] = 1
		for other: int in nbrs[id]:
			nbrs[other].erase(id)
			if not gone[other] and nbrs[other].size() <= 1:
				queue.append(other)
		nbrs[id].clear()
	_out.resize(_pos.size())
	for id in _pos.size():
		_out[id] = PackedInt32Array()
	var tmp: Array = []
	tmp.resize(_pos.size())
	for id in _pos.size():
		tmp[id] = []
	for piece: Array in pieces:
		var a: int = piece[0]
		var b: int = piece[1]
		if gone[a] or gone[b]:
			continue
		var hw: float = piece[2]
		var lanes: int = piece[3]
		var oneway: bool = piece[4]
		var offset := 0.0
		if oneway:
			offset = hw * 0.35 if lanes >= 2 else 0.0
		else:
			offset = clampf(hw * 0.5, 1.3, 3.2)
		for dir in ([[a, b]] if oneway else [[a, b], [b, a]]):
			var e := _e_to.size()
			_e_to.append(dir[1])
			_e_offset.append(offset)
			_e_speed.append(piece[5])
			tmp[dir[0]].append(e)
	for id in _pos.size():
		_out[id] = PackedInt32Array(tmp[id])
		if not _out[id].is_empty():
			var cell := _cell_of(_pos[id], CELL)
			if not _grid.has(cell):
				_grid[cell] = PackedInt32Array()
			var list: PackedInt32Array = _grid[cell]
			list.append(id)
			_grid[cell] = list


static func _near(a: float, b: float) -> bool:
	return absf(a - b) < 0.01


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


static func _cell_of(p: Vector3, size: float) -> Vector2i:
	return Vector2i(floori(p.x / size), floori(p.z / size))


## The nodes no more than `hops` steps from `from` along the roads.
static func _within_hops(nbrs: Array[Dictionary], from: int, hops: int) -> Dictionary:
	var seen := {from: true}
	var ring := [from]
	for h in hops:
		var next := []
		for id: int in ring:
			for other: int in nbrs[id]:
				if not seen.has(other):
					seen[other] = true
					next.append(other)
		ring = next
	return seen


# --- keeping cars about you -----------------------------------------------------

## Where you are: on foot or in the car you drive.
func _focus() -> Vector3:
	if _main.get("on_foot"):
		return (_main.get("player") as Node3D).global_position
	return (_main.get("car") as Node3D).global_position


func _physics_process(delta: float) -> void:
	if _pos.is_empty() or _scenes.is_empty():
		return
	_manage_in -= delta
	if _manage_in <= 0.0:
		_manage_in = 0.5
		_manage()
	for d in _drivers:
		_drive(d, delta)


func _manage() -> void:
	var focus := _focus()
	var camera := get_viewport().get_camera_3d()
	for d: Driver in _drivers.duplicate():
		var car := d.car
		if not is_instance_valid(car):
			_drivers.erase(d)
			continue
		# You got in: it is yours now.
		if car.player_controlled or car == _main.get("car"):
			_release(d)
			continue
		var dist := _flat(car.global_position - focus).length()
		var seen := camera != null and camera.is_position_in_frustum(car.global_position) and dist < 160.0
		var flipped := car.global_basis.y.y < 0.4
		var lost := d.pts.size() >= 2 and _flat(car.global_position - d.pts[mini(d.k + 1, d.pts.size() - 1)]).length() > 14.0
		var at_end := d.ends and d.cum[d.cum.size() - 1] - d.s < 10.0
		if dist > despawn_distance and not seen or dist > despawn_distance * 1.6:
			_respawn(d, focus)
		elif (flipped or d.stuck_for > 25.0 or d.blocked_for > 15.0 or at_end or lost) and not seen:
			_respawn(d, focus)
		elif lost:
			# Knocked off its way where you can see it: it finds the road again from where it is.
			_route_from(d, car.global_position, car.global_basis.z)
	if _drivers.size() < count:
		var scene := _scenes[randi() % _scenes.size()]
		var car := scene.instantiate() as VehicleBody3D
		car.set("paint_color", _colours[randi() % _colours.size()])
		car.set("player_controlled", false)
		car.set("parked", false)
		var d := Driver.new()
		d.car = car
		d.temper = randf_range(0.85, 1.12)
		d.plan_in = randf() * 0.1
		if not _place(d, focus):
			car.free()
			return
		add_child(car)
		car.set("fuel_use_scale", 0.0)
		car.set("engine_volume_db", float(car.get("engine_volume_db")) - 4.0)
		car.set("ai_driven", true)
		car.set("engine_running", true)
		_set_down(d)
		_drivers.append(d)


## Lets go of a car you have got into; it is an ordinary car from now on.
func _release(d: Driver) -> void:
	_drivers.erase(d)
	var car := d.car
	car.set("ai_driven", false)
	car.set("ai_gas", 0.0)
	car.set("ai_brake", 0.0)
	_signal(d, 0)


## Brings the car back somewhere else out of sight, in a new colour.
func _respawn(d: Driver, focus: Vector3) -> void:
	if not _place(d, focus):
		return
	d.car.call("set_paint", _colours[randi() % _colours.size()])
	d.stuck_for = 0.0
	d.blocked_for = 0.0
	_set_down(d)


## Picks a spot on a road spawn_min..spawn_max from you, out of sight and clear
## of other cars, and a way on from there. False if none was found this time.
func _place(d: Driver, focus: Vector3) -> bool:
	var camera := get_viewport().get_camera_3d()
	var reach := ceili(spawn_max / CELL)
	var centre := _cell_of(focus, CELL)
	for attempt in 12:
		var cell := centre + Vector2i(randi_range(-reach, reach), randi_range(-reach, reach))
		var list: PackedInt32Array = _grid.get(cell, PackedInt32Array())
		if list.is_empty():
			continue
		var id := list[randi() % list.size()]
		var p := _pos[id]
		var dist := _flat(p - focus).length()
		if dist < spawn_min or dist > spawn_max:
			continue
		if camera and dist < 150.0 and camera.is_position_in_frustum(p + UP):
			continue
		if not _clear_at(p, 16.0, d.car):
			continue
		var e := _out[id][randi() % _out[id].size()]
		_start_route(d, id, e)
		return true
	return false


func _clear_at(p: Vector3, radius: float, except: Node3D) -> bool:
	for car: Node3D in get_tree().get_nodes_in_group("cars"):
		if car != except and car.global_position.distance_to(p) < radius:
			return false
	return true


## Puts the car down on the road at the start of its way, facing along it, rolling.
func _set_down(d: Driver) -> void:
	var at := d.pts[0]
	var dir := _flat(d.pts[1] - d.pts[0]).normalized()
	var exclude: Array[RID] = []
	for car: CollisionObject3D in get_tree().get_nodes_in_group("cars"):
		exclude.append(car.get_rid())
	var ray := PhysicsRayQueryParameters3D.create(at + UP * 3.0, at + UP * -10.0)
	ray.collision_mask = 1
	ray.exclude = exclude
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if hit:
		at.y = (hit["position"] as Vector3).y
	at.y += 0.4
	d.car.call("place", Transform3D(Basis.looking_at(-dir), at))
	d.cruise = _e_speed[d.edges[0]] * d.temper
	d.car.linear_velocity = dir * minf(d.cruise, 9.0)
	d.k = 0
	d.s = 0.0


# --- the way ahead --------------------------------------------------------------

func _start_route(d: Driver, from: int, edge: int) -> void:
	d.nodes = PackedInt32Array([from, _e_to[edge]])
	d.edges = PackedInt32Array([edge])
	d.pts = PackedVector3Array()
	d.cum = PackedFloat32Array()
	d.ends = false
	d.k = 0
	d.s = 0.0
	d.blocker = null
	_extend(d)


## A new way from the road node nearest `at`, the way that runs most like `heading`.
func _route_from(d: Driver, at: Vector3, heading: Vector3) -> void:
	var best := -1
	var best_d := INF
	var c := _cell_of(at, CELL)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for id: int in _grid.get(c + Vector2i(dx, dz), PackedInt32Array()):
				var dd := _flat(_pos[id] - at).length()
				if dd < best_d:
					best = id
					best_d = dd
	if best < 0:
		return
	var best_e := _out[best][0]
	var best_dot := -INF
	for e in _out[best]:
		var dot := _flat(_pos[_e_to[e]] - _pos[best]).normalized().dot(_flat(heading).normalized())
		if dot > best_dot:
			best_dot = dot
			best_e = e
	_start_route(d, best, best_e)


## Carries the way on to at least 90 m ahead, choosing at each junction, and
## works out the lane points along it.
func _extend(d: Driver) -> void:
	while not d.ends and (d.cum.size() < d.nodes.size() or d.cum[d.cum.size() - 1] - d.s < 90.0):
		var n := d.nodes.size()
		var here := d.nodes[n - 1]
		var came := d.nodes[n - 2]
		var dir_in := _flat(_pos[here] - _pos[came]).normalized()
		var options: Array[int] = []
		var weights: Array[float] = []
		var total := 0.0
		for e in _out[here]:
			var to := _e_to[e]
			if to == came:
				continue
			var cos_turn := dir_in.dot(_flat(_pos[to] - _pos[here]).normalized())
			var w := 4.0 if cos_turn > 0.7 else (1.5 if cos_turn > -0.3 else 0.15)
			options.append(e)
			weights.append(w)
			total += w
		if options.is_empty():
			d.ends = true
		else:
			var pick := randf() * total
			var chosen := options[options.size() - 1]
			for i in options.size():
				pick -= weights[i]
				if pick <= 0.0:
					chosen = options[i]
					break
			d.edges.append(chosen)
			d.nodes.append(_e_to[chosen])
		_lane_points(d)


## The lane points: each node moved to the right of the way by its lane offset.
func _lane_points(d: Driver) -> void:
	var n := d.nodes.size()
	# Only the last two can have changed.
	var first := maxi(d.pts.size() - 1, 0)
	d.pts.resize(n)
	d.cum.resize(n)
	for i in range(first, n):
		var p := _pos[d.nodes[i]]
		var dir_in := _flat(p - _pos[d.nodes[i - 1]]).normalized() if i > 0 else Vector3.ZERO
		var dir_out := _flat(_pos[d.nodes[i + 1]] - p).normalized() if i < n - 1 else Vector3.ZERO
		var dir := (dir_in + dir_out)
		if dir.length() < 0.2:
			dir = dir_out if dir_out != Vector3.ZERO else dir_in
		dir = dir.normalized()
		var offset := _e_offset[d.edges[mini(i, d.edges.size() - 1)]]
		# Sharper corners need the lane point pushed out further to keep the gap.
		var mitre := 1.0
		if dir_in != Vector3.ZERO and dir_out != Vector3.ZERO:
			mitre = 1.0 / maxf(0.7, dir.dot(dir_out))
		d.pts[i] = p + dir.cross(UP).normalized() * offset * mitre
		d.cum[i] = 0.0 if i == 0 else d.cum[i - 1] + _flat(d.pts[i] - d.pts[i - 1]).length()


## Drops the part of the way already driven.
func _trim(d: Driver) -> void:
	var drop := d.k - 2
	if drop <= 8:
		return
	d.nodes = d.nodes.slice(drop)
	d.edges = d.edges.slice(drop)
	d.pts = d.pts.slice(drop)
	var base := d.cum[drop]
	d.cum = d.cum.slice(drop)
	for i in d.cum.size():
		d.cum[i] -= base
	d.s -= base
	d.k -= drop


## The point `ahead` metres further along the way than where the car is.
func _point_at(d: Driver, s: float) -> Vector3:
	var last := d.pts.size() - 1
	if s >= d.cum[last]:
		return d.pts[last]
	var i := d.k
	while i < last - 1 and d.cum[i + 1] < s:
		i += 1
	var seg := d.cum[i + 1] - d.cum[i]
	var t := 0.0 if seg < 0.001 else clampf((s - d.cum[i]) / seg, 0.0, 1.0)
	return d.pts[i].lerp(d.pts[i + 1], t)


# --- driving ------------------------------------------------------------------

func _drive(d: Driver, delta: float) -> void:
	var car := d.car
	if d.pts.size() < 2:
		return
	var p := car.global_position
	# Where along the way the car has got to.
	var last := d.pts.size() - 1
	while d.k < last - 1 and _flat(p - d.pts[d.k + 1]).dot(_flat(d.pts[d.k + 1] - d.pts[d.k])) > 0.0:
		d.k += 1
	var seg := _flat(d.pts[d.k + 1] - d.pts[d.k])
	var along := clampf(_flat(p - d.pts[d.k]).dot(seg.normalized()), 0.0, seg.length()) if seg.length() > 0.001 else 0.0
	d.s = d.cum[d.k] + along
	if d.k > 10:
		_trim(d)
	_extend(d)
	d.cruise = lerpf(d.cruise, _e_speed[d.edges[mini(d.k, d.edges.size() - 1)]] * d.temper, minf(delta, 1.0))
	var speed: float = car.call("forward_speed")

	d.plan_in -= delta
	if d.plan_in <= 0.0:
		d.plan_in = 0.1
		_plan(d, speed)

	# Steering: aim at a point on the lane a little ahead (pure pursuit).
	var look := clampf(4.0 + speed * 0.6, 6.0, 18.0)
	var target := _point_at(d, d.s + look)
	var local := car.global_basis.inverse() * (target - p)
	var alpha := atan2(local.x, local.z)
	var dist := maxf(Vector2(local.x, local.z).length(), 1.0)
	var wheelbase: float = car.get("_wheelbase") if car.get("_wheelbase") != null else 2.7
	var max_steer: float = car.get("max_steer")
	car.set("ai_steer", clampf(atan(2.0 * wheelbase * sin(alpha) / dist), -max_steer, max_steer))

	# Pedals: hold the speed the road, the bends and the traffic allow; stop
	# for you getting in.
	var want := minf(d.cruise, d.allowed)
	if _main.get("_door_car") == car and float(_main.get("_door_time")) > 0.0:
		want = 0.0
	if absf(alpha) > 1.2:
		want = minf(want, 3.0)
	var err := want - speed
	var gas := 0.0
	var brake := 0.0
	if want < 0.3 and speed < 1.5:
		brake = 1.0
	elif err > -0.3:
		gas = clampf(0.12 + err * 0.35, 0.0, 1.0)
	elif err < -1.0:
		brake = clampf(-err * 0.18, 0.0, 1.0)
	car.set("ai_gas", gas)
	car.set("ai_brake", brake)

	# Stuck: trying to go and not moving (against a wall, in a heap).
	if want > 2.0 and absf(speed) < 0.5:
		d.stuck_for += delta
	else:
		d.stuck_for = maxf(d.stuck_for - delta * 2.0, 0.0)


## Ten times a second: how fast the bends ahead and anyone in the way let the
## car go, and the turn signal for the next junction.
func _plan(d: Driver, speed: float) -> void:
	var last := d.pts.size() - 1
	var horizon := d.s + maxf(30.0, speed * speed / (2.0 * comfort_brake) + 20.0)
	var allowed := INF
	# Bends: the tighter, the slower, and slowing in time for them.
	for i in range(d.k + 1, last):
		var ahead := d.cum[i] - d.s
		if d.cum[i] > horizon:
			break
		var lo := maxi(i - 2, 0)
		var hi := mini(i + 2, last)
		var a := _flat(d.pts[i] - d.pts[lo]).normalized()
		var b := _flat(d.pts[hi] - d.pts[i]).normalized()
		var turn := acos(clampf(a.dot(b), -1.0, 1.0))
		if turn < 0.05:
			continue
		var radius := (d.cum[hi] - d.cum[lo]) / turn
		var corner := maxf(sqrt(bend_grip * radius), 3.5)
		allowed = minf(allowed, sqrt(corner * corner + 2.0 * comfort_brake * maxf(ahead - 3.0, 0.0)))
	# The end of the way, if it runs out.
	if d.ends:
		allowed = minf(allowed, _stop_speed(d.cum[last] - d.s - 4.0))
	# Whoever is on the lane ahead: people, you, other cars.
	var gap := INF
	var blocker: Node3D = null
	var obstacles: Array = []
	var townsfolk := _main.get_node_or_null("Townsfolk")
	if townsfolk and townsfolk.has_method("people"):
		for person: Node3D in townsfolk.call("people"):
			obstacles.append([person, person.global_position, 1.6, 4.5])
	if _main.get("on_foot"):
		var you := _main.get("player") as Node3D
		obstacles.append([you, you.global_position, 1.7, 5.0])
	for other: VehicleBody3D in get_tree().get_nodes_in_group("cars"):
		if other == d.car:
			continue
		if d.ignore_cars_for > 0.0 and other.get("ai_driven"):
			continue
		obstacles.append([other, other.global_position, 2.2, 7.0])
		if other.linear_velocity.length() > 2.0:
			# Where it will be in a moment: catches a car about to cross.
			obstacles.append([other, other.global_position + other.linear_velocity * 0.8, 2.0, 7.0])
	var me := d.car.global_position
	var reach := horizon - d.s + 8.0
	for o: Array in obstacles:
		var at: Vector3 = o[1]
		if _flat(at - me).length() > reach or absf(at.y - me.y) > 4.0:
			continue
		for i in range(d.k + 1, last + 1):
			var ahead := d.cum[i] - d.s
			if ahead > reach:
				break
			if _flat(at - d.pts[i]).length() < o[2]:
				var g: float = ahead - o[3]
				if g < gap:
					# Two cars each in the other's way: the one that came first goes.
					var other_driver := _driver_of(o[0])
					if other_driver and other_driver.blocker == d.car and d.car.get_instance_id() > (o[0] as Object).get_instance_id():
						break
					gap = g
					blocker = o[0]
				break
	d.blocker = blocker
	if blocker:
		allowed = minf(allowed, _stop_speed(gap))
	# Held up by a car that does not move. Another of the traffic (two waiting
	# on each other at a junction): after a while, squeeze past. A parked one:
	# out of sight, the car comes back elsewhere (_manage).
	d.ignore_cars_for = maxf(d.ignore_cars_for - 0.1, 0.0)
	if blocker and blocker is VehicleBody3D and speed < 0.5:
		d.blocked_for += 0.1
		if blocker.get("ai_driven") and d.blocked_for > 10.0:
			d.ignore_cars_for = 4.0
			d.blocked_for = 0.0
	else:
		d.blocked_for = 0.0
	d.allowed = allowed
	_signal(d, _next_turn(d))


func _stop_speed(gap: float) -> float:
	return sqrt(2.0 * comfort_brake * 1.4 * maxf(gap, 0.0))


func _driver_of(node: Object) -> Driver:
	for d in _drivers:
		if d.car == node:
			return d
	return null


## Which way the way turns at the next junction within 35 m: 1 left, -1 right, 0 straight on.
func _next_turn(d: Driver) -> int:
	var last := d.nodes.size() - 1
	for i in range(d.k + 1, last):
		if d.cum[i] - d.s > 35.0:
			break
		if _out[d.nodes[i]].size() <= 2:
			continue
		var a := _flat(_pos[d.nodes[i]] - _pos[d.nodes[i - 1]]).normalized()
		var b := _flat(_pos[d.nodes[mini(i + 3, last)]] - _pos[d.nodes[i]]).normalized()
		var side := a.cross(b).y
		if a.dot(b) > 0.85:
			return 0
		return 1 if side > 0.0 else -1
	return 0


func _signal(d: Driver, turn: int) -> void:
	if d.turn_signal == turn:
		return
	d.turn_signal = turn
	var lamps := d.car.get_node_or_null("Lamps")
	if lamps and lamps.has_method("_set_signals"):
		lamps.call("_set_signals", turn == 1, turn == -1)
