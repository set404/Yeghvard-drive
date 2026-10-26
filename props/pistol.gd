extends Node3D
## A Makarov-like pistol made of boxes (no model yet): its origin is where the
## hand holds it, at the top of the grip; the barrel points along +Z and the
## sights are up (+Y). MUZZLE is the end of the barrel. player/combat.gd holds
## it; props/pistol.tscn is the scene the inventory shows.

const MUZZLE := Vector3(0.0, 0.045, 0.16)

const STEEL := Color(0.12, 0.12, 0.13)
const GRIP := Color(0.2, 0.13, 0.08)


func _ready() -> void:
	var steel := _material(STEEL, 0.45, 0.8)
	var grip := _material(GRIP, 0.8, 0.0)
	# The slide and barrel, from behind the hand to the muzzle.
	_box(Vector3(0.032, 0.036, 0.19), Vector3(0.0, 0.045, 0.065), steel)
	# The frame under it, and the trigger guard.
	_box(Vector3(0.028, 0.018, 0.12), Vector3(0.0, 0.02, 0.05), steel)
	_box(Vector3(0.024, 0.03, 0.006), Vector3(0.0, -0.002, 0.075), steel)
	# The grip, raked back, the hand round its top.
	var g := _box(Vector3(0.03, 0.105, 0.042), Vector3(0.0, -0.035, -0.012), grip)
	g.rotation.x = deg_to_rad(-14.0)
	# Front sight.
	_box(Vector3(0.004, 0.008, 0.006), Vector3(0.0, 0.066, 0.15), steel)


func _box(size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = at
	add_child(mi)
	return mi


func _material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	return m
