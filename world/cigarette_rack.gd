extends Node3D
## The packs of cigarettes on the rack behind the cashier (world/cashier.gd).
## tools/build_supermarket.gd builds the cabinet and puts this at the front of
## its bottom left end as you face it: +X along the shelves, +Z out of their
## front, +Y up. When the game starts it fills the shelves with packs
## (props/cigarette.gd), their fronts out, as one MultiMesh for their boxes and
## one for their pictures.

const Cigarette := preload("res://props/cigarette.gd")

## How long the shelves are, and the height of each (metres).
@export var length := 2.2
@export var shelves := PackedFloat32Array([0.95, 1.2, 1.45, 1.7, 1.95])
## Set back from the front of the shelves.
@export var inset := 0.02


func _ready() -> void:
	var size: Vector3 = Cigarette.PACK
	var per_row := floori((length - 0.02) / (size.x + 0.012))
	var gap := (length - per_row * size.x) / (per_row + 1)
	var count := per_row * shelves.size()
	var box := BoxMesh.new()
	box.size = size
	var white := StandardMaterial3D.new()
	white.albedo_color = Cigarette.PACK_COLOR
	white.roughness = 0.5
	box.material = white
	var boxes := _multi(box, count)
	var fronts := _multi(Cigarette.front_mesh(), count)
	var k := 0
	for y: float in shelves:
		for i in per_row:
			var at := Vector3(gap + size.x * 0.5 + i * (size.x + gap), y + size.y * 0.5, -inset - size.z * 0.5)
			boxes.set_instance_transform(k, Transform3D(Basis.IDENTITY, at))
			fronts.set_instance_transform(k, Transform3D(Basis.IDENTITY, at + Vector3(0.0, 0.0, size.z * 0.5 + 0.0005)))
			k += 1
	for part: Array in [["Packs", boxes], ["PackFronts", fronts]]:
		var mmi := MultiMeshInstance3D.new()
		mmi.name = part[0]
		mmi.multimesh = part[1]
		add_child(mmi)


static func _multi(mesh: Mesh, count: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	return mm
