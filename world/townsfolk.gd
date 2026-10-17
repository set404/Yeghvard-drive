extends Node3D
## The people of the town: they walk along the sidewalks (world/sidewalks.scn),
## stop to look about or at their phones, and stop in pairs to talk. Only those
## near you are kept: as you go, people farther than despawn_distance leave and
## new ones come in out at spawn_min..spawn_max metres.
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

## Each sidewalk as points along its middle (metres, world space), with the
## walkway's width and the distance along it at each point.
var _points: Array[PackedVector3Array] = []
var _widths: Array[PackedFloat32Array] = []
var _distances: Array[PackedFloat32Array] = []
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
	if player:
		player.collision_mask |= BODY_LAYER
	print("Townsfolk: %d figures, %d sidewalks" % [_figures.size(), _points.size()])


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
		if points.is_empty() or points[points.size() - 1].distance_to(start) > 0.05:
			_add_path(points, widths)
			points = PackedVector3Array([start])
			widths = PackedFloat32Array([width])
		points.append(end)
		widths.append(width)
	_add_path(points, widths)


func _add_path(points: PackedVector3Array, widths: PackedFloat32Array) -> void:
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


func path_length(i: int) -> float:
	return _distances[i][_distances[i].size() - 1]


## Where on sidewalk `i` the point `at` metres along is: its "position",
## "forward" (the way the sidewalk runs, level) and walkway "width".
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
	}


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
			if other is Npc and other.state == Npc.State.WALK and other.global_basis.z.dot(ahead) < 0.0:
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
