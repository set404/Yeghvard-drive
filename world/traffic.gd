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
## colour none of those has. At the wheel of each sits one of the townspeople
## (res://npc), playing your character's "drive" animation (player/character.scn),
## its bones renamed to theirs (each Mixamo rig has its own prefix) and its hips
## moved to their height. Get into one (F) and it is yours: the driver gets
## out and traffic lets go of it.

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
@export var bend_grip := 1.8
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
## m/s² the cars' full foot brake gives (car.gd brake_decel).
const BRAKE_DECEL := 10.0
## Metres past a traffic light's stop line that must be clear (no car standing)
## before a car goes in on green.
const BOX := 25.0

## One car of the traffic and where it is going.
class Driver:
	var car: VehicleBody3D
	## The way ahead: graph nodes, the edges between them, the points along the
	## lane (offset to the right of the middle) and the distance to each.
	var nodes := PackedInt32Array()
	var edges := PackedInt32Array()
	## The lane's corner points, and pts: the same with the corners rounded
	## into curves a car can follow (_lane_points).
	var raw := PackedVector3Array()
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
	## Metres to the blocker's back and how fast it is going our way, m/s.
	var gap := INF
	var gap_speed := 0.0
	var blocked_for := 0.0
	var ignore_cars_for := 0.0
	var stuck_for := 0.0
	var turn_signal := 0 ## -1 right, 1 left, 0 none


@onready var _main: Node3D = get_parent()

# The road network.
var _pos := PackedVector3Array()
var _out: Array[PackedInt32Array] = [] ## directed edges leaving each node
var _e_from := PackedInt32Array()
var _e_to := PackedInt32Array()
## Whether a car fits along the lane, found the first time it is asked (_edge_clear):
## 0 not yet known, 1 clear, 2 a fence or wall stands in it.
var _e_clear := PackedByteArray()
var _ground: Array[RID] = [] ## the terrain and the roads, which the lane test ignores
var _e_offset := PackedFloat32Array() ## metres from the middle to the lane, to the right
var _e_hw := PackedFloat32Array() ## the road's half width
var _e_two_way := PackedByteArray()
var _e_speed := PackedFloat32Array() ## m/s
var _grid := {} ## Vector2i cell -> PackedInt32Array of nodes that have a way out
const CELL := 40.0

var _scenes: Array[PackedScene] = []
## The townspeople's figures, to sit at the wheel.
var _figures: Array[PackedScene] = []
## Your character's "drive" animation and where his eyes and hands are in it.
var _drive_anim: Animation
var _drive_eyes := Vector3(0.0, 1.26, 0.05)
var _drive_hands := Vector3(0.0, 0.94, 0.26)
var _drive_height := 1.78
var _drive_prefix := ""
var _drive_hips := 0.98
var _colours: Array[Color] = []
var _drivers: Array[Driver] = []
var _manage_in := 1.5


func _ready() -> void:
	var t0 := Time.get_ticks_usec()
	var world := _main.get_node_or_null("World")
	var roads: Node = world.find_child("Roads", true, false) if world else null
	if world:
		for body: CollisionObject3D in world.find_children("*", "CollisionObject3D", true, false):
			if body.name in [&"Terrain", &"Roads", &"Water"]:
				_ground.append(body.get_rid())
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
	_load_drivers()
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
			_e_from.append(dir[0])
			_e_to.append(dir[1])
			_e_offset.append(offset)
			_e_hw.append(hw)
			_e_two_way.append(0 if oneway else 1)
			_e_speed.append(piece[5])
			tmp[dir[0]].append(e)
	_e_clear.resize(_e_to.size())
	for id in _pos.size():
		_out[id] = PackedInt32Array(tmp[id])
		if not _out[id].is_empty():
			var cell := _cell_of(_pos[id], CELL)
			if not _grid.has(cell):
				_grid[cell] = PackedInt32Array()
			var list: PackedInt32Array = _grid[cell]
			list.append(id)
			_grid[cell] = list


## False where a fence or wall stands in the lane (a yard built over the end of
## a street, a join across a verge): a car following it would only hit it.
func _edge_clear(e: int) -> bool:
	if _e_clear[e] == 0:
		var a := _pos[_e_from[e]]
		var b := _pos[_e_to[e]]
		var dir := _flat(b - a)
		var length := dir.length()
		dir = dir.normalized() if length > 0.01 else Vector3.BACK
		var right := dir.cross(UP)
		var box := BoxShape3D.new()
		# A car's width and a little: a street a car only scrapes along is no good either.
		box.size = Vector3(2.1, 0.8, maxf(length, 0.5))
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = box
		query.collision_mask = 1
		var mid := (a + b) * 0.5 + right * _e_offset[e] + UP * 1.0
		query.transform = Transform3D(Basis.looking_at(dir), mid)
		var exclude := _ground.duplicate()
		for car: CollisionObject3D in get_tree().get_nodes_in_group("cars"):
			exclude.append(car.get_rid())
		query.exclude = exclude
		var hits := get_world_3d().direct_space_state.intersect_shape(query, 1)
		_e_clear[e] = 2 if not hits.is_empty() else 1
	return _e_clear[e] == 1


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
		_seat_driver(car)
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
	var driver := car.get_node_or_null("NpcDriver")
	if driver:
		_get_out(car, driver)


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
		if not _edge_clear(e):
			continue
		_start_route(d, id, e)
		if d.ends or d.cum[d.cum.size() - 1] < 40.0:
			continue
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
	d.k = 0
	d.s = 0.0
	d.gap = INF
	# Rolling no faster than the first bend allows, or it is in the fence.
	_plan(d, 0.0)
	d.car.linear_velocity = dir * minf(minf(d.cruise, d.allowed), 9.0)


# --- drivers ------------------------------------------------------------------

func _load_drivers() -> void:
	for file in DirAccess.get_files_at("res://npc"):
		file = file.trim_suffix(".remap")
		if file.get_extension() == "scn":
			_figures.append(load("res://npc/" + file))
	const CHARACTER := "res://player/character.scn"
	if not ResourceLoader.exists(CHARACTER):
		return
	var adam: Node3D = (load(CHARACTER) as PackedScene).instantiate()
	var anim := adam.get_node_or_null("AnimationPlayer") as AnimationPlayer
	var skeleton := adam.get_node_or_null("Skeleton3D") as Skeleton3D
	if anim and skeleton and anim.has_animation("drive") and skeleton.get_bone_count() > 0:
		_drive_anim = anim.get_animation("drive")
		_drive_eyes = adam.get_meta("drive_eyes", _drive_eyes)
		_drive_hands = adam.get_meta("drive_hands", _drive_eyes)
		_drive_height = adam.get_meta("height", _drive_height)
		_drive_prefix = _bone_prefix(skeleton)
		_drive_hips = skeleton.get_bone_rest(0).origin.y
	adam.free()


## "mixamorig7_" of "mixamorig7_Hips": the part of the bone names each rig has its own.
static func _bone_prefix(skeleton: Skeleton3D) -> String:
	var root := skeleton.get_bone_name(0)
	var cut := root.find("_")
	return root.substr(0, cut + 1) if cut >= 0 else ""


## The drive animation fitted to a figure: its bone names, and the hips (the
## only bone that moves, not just turns) scaled to its height.
func _drive_for(skeleton: Skeleton3D) -> Animation:
	var prefix := _bone_prefix(skeleton)
	var scale := skeleton.get_bone_rest(0).origin.y / _drive_hips if _drive_hips > 0.01 else 1.0
	var anim := _drive_anim.duplicate(true) as Animation
	for t in anim.get_track_count():
		var path := String(anim.track_get_path(t))
		if _drive_prefix != "" and prefix != _drive_prefix:
			path = path.replace(":" + _drive_prefix, ":" + prefix)
			anim.track_set_path(t, NodePath(path))
		if anim.track_get_type(t) == Animation.TYPE_POSITION_3D:
			for k in anim.track_get_key_count(t):
				anim.track_set_key_value(t, k, (anim.track_get_key_value(t, k) as Vector3) * scale)
	anim.loop_mode = Animation.LOOP_LINEAR
	return anim


## Sits one of the townspeople at the wheel, eyes where the car's in-car camera
## is and hands on the steering wheel, as player.gd seats you.
func _seat_driver(car: VehicleBody3D) -> void:
	if _drive_anim == null or _figures.is_empty():
		return
	var figure: Node3D = _figures.pick_random().instantiate()
	var anim := figure.get_node_or_null("AnimationPlayer") as AnimationPlayer
	var skeleton := figure.get_node_or_null("Skeleton3D") as Skeleton3D
	if anim == null or skeleton == null or skeleton.get_bone_count() == 0:
		figure.free()
		return
	figure.name = "NpcDriver"
	# Their own library, so the people walking about who share the figure are not touched.
	var library := AnimationLibrary.new()
	library.add_animation(&"drive", _drive_for(skeleton))
	anim.add_animation_library(&"traffic", library)
	var phone := figure.get_node_or_null("Skeleton3D/RightHand/Phone") as Node3D
	if phone:
		phone.visible = false
	var s := float(figure.get_meta("height", _drive_height)) / _drive_height
	var view: Variant = car.get("driver_view")
	var eye_point: Vector3 = view if view is Vector3 else Vector3(0.37, 1.13, 0.1)
	var at := eye_point + Vector3(0.0, 0.0, 0.05) - _drive_eyes * s
	var wheel := car.find_child("SteeringWheel", true, false) as Node3D
	if wheel and wheel.is_inside_tree():
		var short := car.to_local(wheel.global_position).z - (at + _drive_hands * s).z
		at.z += clampf(short, 0.0, 0.15)
	figure.position = at
	car.add_child(figure)
	anim.play(&"traffic/drive")


## The driver of a car you took is out of it and runs off along the nearest
## walk, as one of the townspeople.
func _get_out(car: VehicleBody3D, driver: Node3D) -> void:
	driver.queue_free()
	var townsfolk := _main.get_node_or_null("Townsfolk")
	if townsfolk == null or not townsfolk.has_method("nearest_point") or not townsfolk.has_method("_person"):
		return
	var near: Dictionary = townsfolk.call("nearest_point", car.global_position)
	if near.is_empty():
		return
	# On the nearest walk, running from you.
	var person: Node3D = townsfolk.call("_person", near["path"], near["at"], 1.0 if randf() < 0.5 else -1.0)
	if person.has_method("alarm"):
		person.call("alarm", car.global_position)


# --- the way ahead --------------------------------------------------------------

func _start_route(d: Driver, from: int, edge: int) -> void:
	d.nodes = PackedInt32Array([from, _e_to[edge]])
	d.edges = PackedInt32Array([edge])
	d.raw = PackedVector3Array()
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
		var hairpin := -1
		for e in _out[here]:
			var to := _e_to[e]
			if to == came or not _edge_clear(e):
				continue
			# Not into a dead end: a join onto a one-way road the wrong way leads
			# nowhere but back, and the car would stop there for good.
			var onward := false
			for next in _out[to]:
				if _e_to[next] != here:
					onward = true
					break
			if not onward:
				continue
			var cos_turn := dir_in.dot(_flat(_pos[to] - _pos[here]).normalized())
			# Doubling back into a fork's other arm: too tight to take, and the
			# corner of the yard between the two is in the way.
			if cos_turn < -0.2:
				hairpin = e
				continue
			var w := 4.0 if cos_turn > 0.7 else 1.5
			options.append(e)
			weights.append(w)
			total += w
		if options.is_empty() and hairpin >= 0:
			options.append(hairpin)
			weights.append(1.0)
			total += 1.0
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


## The lane points: each node moved to the right of the way by its lane offset,
## then the corners rounded. A junction's lane is a sharp corner that no car can
## turn on the spot: following it, a car swings wide past a right turn into the
## other side of the new street. Each point is averaged with two either side
## (weights 1 2 3 2 1), which makes a right angle of 3 m pieces a curve of about
## 4.6 m radius: one a car can take, starting before the corner and ending in
## its own lane; a left turn crosses near the middle of the junction.
func _lane_points(d: Driver) -> void:
	var n := d.nodes.size()
	# Only the last two corner points can have changed, and the rounded points
	# within two of them.
	var first := maxi(d.raw.size() - 1, 0)
	d.raw.resize(n)
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
		d.raw[i] = p + dir.cross(UP).normalized() * offset * mitre
	for i in range(maxi(first - 2, 0), n):
		var sum := Vector3.ZERO
		var weight := 0.0
		for j in range(maxi(i - 2, 0), mini(i + 3, n)):
			var w := 3.0 - absi(j - i)
			sum += d.raw[j] * w
			weight += w
		d.pts[i] = sum / weight
		_keep_in_lane(d, i)
		# Round the corner only where a car fits: not into a wall at the kerb.
		if d.pts[i] != d.raw[i] and not _fits(d.pts[i], d.raw[mini(i + 1, n - 1)] - d.raw[maxi(i - 1, 0)]):
			d.pts[i] = d.raw[i]
	for i in range(maxi(first - 2, 0), n):
		d.cum[i] = 0.0 if i == 0 else d.cum[i - 1] + _flat(d.pts[i] - d.pts[i - 1]).length()


## True if nothing but the ground and cars is where a car would stand at `at`,
## facing `dir`.
func _fits(at: Vector3, dir: Vector3) -> bool:
	dir = _flat(dir)
	if dir.length() < 0.01:
		return true
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 0.8, 3.0)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	query.collision_mask = 1
	query.transform = Transform3D(Basis.looking_at(dir.normalized()), at + UP * 1.0)
	var exclude := _ground.duplicate()
	for car: CollisionObject3D in get_tree().get_nodes_in_group("cars"):
		exclude.append(car.get_rid())
	query.exclude = exclude
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


## Rounding cuts a left turn towards the middle of the junction, across the
## oncoming lanes, and a right turn towards the kerb. Keeps a rounded point from
## going more than KEEP_CENTRE over the middle of a two-way road (a left turn
## then swings wider, as a driver's does) or nearer the edge than KEEP_EDGE.
const KEEP_CENTRE := 1.1
const KEEP_EDGE := 1.1

func _keep_in_lane(d: Driver, i: int) -> void:
	var n := d.nodes.size()
	for j in range(maxi(i - 2, 0), mini(i + 2, n - 1)):
		var a := _pos[d.nodes[j]]
		var ab := _flat(_pos[d.nodes[j + 1]] - a)
		if ab.length() < 0.01:
			continue
		var rel := _flat(d.pts[i] - a)
		var t := rel.dot(ab) / ab.length_squared()
		# Only beside this piece of road, not off past its ends.
		if t < -0.2 or t > 1.2:
			continue
		var right := ab.normalized().cross(UP)
		var lateral := rel.dot(right)
		var e := d.edges[j]
		var lo := KEEP_CENTRE if _e_two_way[e] == 1 else -INF
		# At a junction the kerb opens out round the corner: up to the road's
		# edge line there, the fences stand back from it (build_world FENCE_ROAD_GAP).
		var junction := _out[d.nodes[j]].size() > 2 or _out[d.nodes[j + 1]].size() > 2
		var hi := maxf(_e_hw[e] - (0.0 if junction else KEEP_EDGE), _e_offset[e])
		if absf(lateral) > _e_hw[e] + 2.0:
			continue # beside some other arm of the junction
		d.pts[i] += right * (clampf(lateral, lo, hi) - lateral)


## Drops the part of the way already driven.
func _trim(d: Driver) -> void:
	var drop := d.k - 2
	if drop <= 8:
		return
	d.nodes = d.nodes.slice(drop)
	d.edges = d.edges.slice(drop)
	d.raw = d.raw.slice(drop)
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

	# Steering: aim at a point on the lane a little ahead (pure pursuit). Short
	# when slow, so it follows a tight corner instead of cutting it. (From the
	# middle of the car, not the rear axle: the tyres slip, so the car turns
	# wider than the geometry says, and that makes up for it.)
	var wheelbase: float = car.get("_wheelbase") if car.get("_wheelbase") != null else 2.7
	var look := clampf(2.0 + speed * 0.45, 3.5, 16.0)
	var target := _point_at(d, d.s + look)
	var local := car.global_basis.inverse() * (target - p)
	if local.x > 0.0:
		# Bending left: aiming far ahead turns in early, across the oncoming
		# lane. Aim nearer, and turn in late as a driver does.
		target = _point_at(d, d.s + maxf(look * 0.55, 2.5))
		local = car.global_basis.inverse() * (target - p)
	var alpha := atan2(local.x, local.z)
	var dist := maxf(Vector2(local.x, local.z).length(), 1.0)
	var max_steer: float = car.get("max_steer")
	# Aiming ahead alone lets the car drift inside a long bend (a left turn
	# across the junction); steer back towards the lane by how far off it is.
	var off_lane := 0.0
	if seg.length() > 0.001:
		var c := d.pts[d.k] + seg.normalized() * along
		off_lane = _flat(p - c).dot(seg.normalized().cross(UP))
	var correct := clampf(off_lane * 0.25, -0.25, 0.25)
	car.set("ai_steer", clampf(atan(2.0 * wheelbase * sin(alpha) / dist) + correct, -max_steer, max_steer))

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
	elif err < -0.6:
		brake = clampf(-err * 0.4, 0.0, 1.0)
	# Closing on whoever is ahead: brake as hard as it takes to stop short of
	# them (the gap shrinks between plans), not just towards the wanted speed.
	if d.gap < INF:
		var closing := speed - d.gap_speed
		d.gap -= closing * delta
		if closing > 0.3:
			var need := closing * closing / (2.0 * maxf(d.gap, 0.3))
			if need > comfort_brake * 0.8 or d.gap < 1.5:
				gas = 0.0
				brake = maxf(brake, clampf(need / BRAKE_DECEL * 1.2, 0.0, 1.0))
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
		obstacles.append([other, other.global_position, 2.2, 7.0])
		if other.linear_velocity.length() > 2.0:
			# Where it will be in a moment: catches a car about to cross.
			obstacles.append([other, other.global_position + other.linear_velocity * 0.8, 2.0, 7.0, true])
	var me := d.car.global_position
	var to_local := d.car.global_basis.inverse()
	var reach := horizon - d.s + 8.0
	# Right in front of the bumper, wherever the way goes: a car cutting across
	# or over the line, someone stepping out. Never waved through.
	var close := 5.0 + maxf(speed, 0.0) * 1.2
	for o: Array in obstacles:
		var at: Vector3 = o[1]
		if _flat(at - me).length() > reach or absf(at.y - me.y) > 4.0:
			continue
		var g := INF
		var local := to_local * (at - me)
		var in_front: bool = o.size() < 5 and local.z > 0.0 and local.z < close + o[3] and absf(local.x) < o[2] * 0.85
		if in_front:
			g = local.z - o[3]
		else:
			for i in range(d.k + 1, last + 1):
				var ahead := d.cum[i] - d.s
				if ahead > reach:
					break
				if _flat(at - d.pts[i]).length() < o[2]:
					g = ahead - o[3]
					break
		if g >= gap:
			continue
		if not in_front and o[0] is VehicleBody3D and o[0].get("ai_driven"):
			# Squeezing past one it has waited on too long.
			if d.ignore_cars_for > 0.0:
				continue
			# Two cars each in the other's way: the one that came first goes.
			var other_driver := _driver_of(o[0])
			if other_driver and other_driver.blocker == d.car and d.car.get_instance_id() > (o[0] as Object).get_instance_id():
				continue
		gap = g
		blocker = o[0]
	# Traffic lights: where the way ahead crosses one's stop line, stop there on
	# red (and on yellow, if there is room).
	for light: Node3D in get_tree().get_nodes_in_group("traffic_lights"):
		if _flat(light.global_position - me).length() > reach + 10.0:
			continue
		var line: PackedVector3Array = light.call("stop_line")
		var l0 := Vector2(line[0].x, line[0].z)
		var l1 := Vector2(line[1].x, line[1].z)
		for i in range(d.k, last):
			if d.cum[i] - d.s > reach:
				break
			var p0 := Vector2(d.pts[i].x, d.pts[i].z)
			var cross: Variant = Geometry2D.segment_intersects_segment(p0, Vector2(d.pts[i + 1].x, d.pts[i + 1].z), l0, l1)
			if cross == null:
				continue
			# From the car's front (half a car ahead of its middle) to the line.
			var g: float = d.cum[i] + p0.distance_to(cross) - d.s - 2.3
			if g > -1.0 and g < gap:
				# Green too, but not into the junction behind a car standing in it:
				# that is how everyone ends up waiting on everyone else.
				var full: bool = g > 0.5 and blocker is VehicleBody3D and gap < g + BOX \
						and (blocker as VehicleBody3D).linear_velocity.length() < 2.0
				if full or light.call("must_stop", g, speed):
					gap = maxf(g, 0.0)
					blocker = light
			break
	d.blocker = blocker
	d.gap = gap
	d.gap_speed = 0.0
	if blocker:
		allowed = minf(allowed, _stop_speed(gap))
		if blocker is VehicleBody3D:
			d.gap_speed = maxf((blocker as VehicleBody3D).linear_velocity.dot(d.car.global_basis.z), 0.0)
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
