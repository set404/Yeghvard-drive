extends Node3D
## The Duet iced coffee section in the supermarket. tools/build_supermarket.gd
## builds the shelving and puts this at its left end as you face it: +X along
## the shelves, +Z out of their front, the floor at y = 0.
##
## Fills the shelves with cups of props/duet.glb (one MultiMesh). On foot in
## front of them, E takes one (main.gd pays `price` from the wallet and puts it
## in your inventory). A cup taken comes back on the shelf after `restock_time`.

const CUP_SCENE := "res://props/duet.glb"

## Length of the shelving along +X, and how deep the shelves are (metres).
@export var length := 6.0
@export var depth := 0.5
## Height of each shelf the cups stand on.
@export var levels := PackedFloat32Array([0.12, 0.51, 0.9, 1.28])
## What one cup costs, in drams.
@export var price := 150.0
## What you get, as game/inventory.gd knows it, and what the on-screen hints call it.
@export var item_id := "duet"
@export var item_name := "Duet coffee"
## How far in front of the shelves you can reach them from (metres).
@export var reach := 1.4
@export var restock_time := 120.0
## Centre to centre of the cups standing side by side.
@export var spacing := 0.15

var _multi: MultiMesh
var _slots: Array[Transform3D] = []
## Slot index -> seconds until a cup is back there.
var _gone := {}


func _ready() -> void:
	add_to_group("shop_stands")
	if not ResourceLoader.exists(CUP_SCENE):
		push_warning("%s is missing; the Duet shelves stay empty" % CUP_SCENE)
		return
	_lay_out_slots()
	_multi = MultiMesh.new()
	_multi.transform_format = MultiMesh.TRANSFORM_3D
	_multi.mesh = _cup_mesh()
	_multi.instance_count = _slots.size()
	for k in _slots.size():
		_multi.set_instance_transform(k, _slots[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Cups"
	mmi.multimesh = _multi
	add_child(mmi)


## A row of cups at the front of each shelf and one behind it, in the bays
## between the uprights (as many bays as tools/build_supermarket.gd makes).
func _lay_out_slots() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	# As big as the cup you carry (game/inventory.gd).
	var size: float = Inventory.ITEMS.get(item_id, {}).get("scale", 1.0)
	var bays := maxi(1, roundi(length / 1.0))
	var bay := length / bays
	var per_bay := floori((bay - 0.06) / spacing)
	for y in levels:
		for b in bays:
			var x0 := b * bay + (bay - per_bay * spacing) * 0.5 + spacing * 0.5
			for z: float in [depth - 0.1, depth - 0.26]:
				for i in per_bay:
					var turn := Basis(Vector3.UP, rng.randf_range(-0.6, 0.6)).scaled(Vector3.ONE * size)
					_slots.append(Transform3D(turn, Vector3(x0 + i * spacing, y, z)))


## The cup's meshes (cup, coffee, lid, tab) merged into one mesh with a
## surface for each, as the MultiMesh wants.
static func _cup_mesh() -> ArrayMesh:
	var cup: Node3D = (load(CUP_SCENE) as PackedScene).instantiate()
	var merged := ArrayMesh.new()
	for mi: MeshInstance3D in cup.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D.IDENTITY
		var node: Node = mi
		while node != cup:
			xf = (node as Node3D).transform * xf
			node = node.get_parent()
		for s in mi.mesh.get_surface_count():
			var st := SurfaceTool.new()
			st.append_from(mi.mesh, s, xf)
			st.set_material(mi.get_active_material(s))
			st.commit(merged)
	cup.free()
	return merged


## How far the walker is in front of the shelves, or INF when not in front of them.
func shopper_distance(who: Node3D) -> float:
	var p := to_local(who.global_position)
	if p.x < -0.3 or p.x > length + 0.3 or p.z < depth - 0.2 or absf(p.y) > 1.0:
		return INF
	return maxf(p.z - depth, 0.0)


func in_reach(who: Node3D) -> bool:
	return shopper_distance(who) < reach


func sold_out() -> bool:
	return _multi == null or _gone.size() >= _slots.size()


## Takes the cup on the shelves nearest to `near` (front row first, about chest
## height) off them. Returns false when there are none left.
func take(near: Vector3) -> bool:
	if sold_out():
		return false
	var p := to_local(near)
	var best := -1
	var best_score := INF
	for k in _slots.size():
		if _gone.has(k):
			continue
		var at := _slots[k].origin
		var score := absf(at.x - p.x) + absf(at.y - 1.0) * 0.5 + (depth - at.z) * 2.0
		if score < best_score:
			best = k
			best_score = score
	_gone[best] = restock_time
	_multi.set_instance_transform(best, Transform3D(Basis().scaled(Vector3.ZERO), _slots[best].origin))
	return true


func _process(delta: float) -> void:
	for k: int in _gone.keys():
		_gone[k] -= delta
		if _gone[k] <= 0.0:
			_gone.erase(k)
			_multi.set_instance_transform(k, _slots[k])
