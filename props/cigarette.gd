extends Node3D
## A pack of Ararat cigarettes, two sticking out of its open top: the picture
## of the "cigarette" item in the inventory (props/cigarettes.tscn), built in
## code. make_pack() builds a pack (the cashier's shelf and her hand,
## world/cashier.gd), make() one cigarette, as player.gd lights one.

const PACK := Vector3(0.055, 0.085, 0.022) ## width, height, depth (m)
const PACK_COLOR := Color(0.92, 0.93, 0.94)
## The front (and back) of the pack.
const PACK_FRONT := "res://props/ararat_pack.png"


func _init() -> void:
	add_child(make_pack())
	for k in 2:
		var cig := make(false)
		cig.position = Vector3(-0.012 + k * 0.016, PACK.y - 0.06 + k * 0.012, 0.0)
		add_child(cig)


## One cigarette, 8.5 cm long: its filter end at the origin, the rest along +Y.
## Lit, it has a glowing tip and a thin trail of smoke.
static func make(lit := true) -> Node3D:
	var cig := Node3D.new()
	cig.name = "Cigarette"
	var tip_color := Color(1.0, 0.35, 0.05) if lit else Color(0.93, 0.93, 0.9)
	var parts := [[0.0, 0.022, Color(0.85, 0.55, 0.25), 0.0], [0.022, 0.08, Color(0.95, 0.95, 0.93), 0.0],
		[0.08, 0.085, tip_color, 3.0 if lit else 0.0]]
	for p: Array in parts:
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.0042
		mesh.bottom_radius = 0.0042
		mesh.height = p[1] - p[0]
		mesh.radial_segments = 8
		mesh.rings = 1
		var mat := StandardMaterial3D.new()
		mat.albedo_color = p[2]
		mat.roughness = 0.8
		if p[3] > 0.0:
			mat.emission_enabled = true
			mat.emission = p[2]
			mat.emission_energy_multiplier = p[3]
		mesh.material = mat
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.position.y = (p[0] + p[1]) * 0.5
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cig.add_child(mi)
	if lit:
		cig.add_child(_smoke())
	return cig


static func _smoke() -> CPUParticles3D:
	var smoke := CPUParticles3D.new()
	smoke.name = "Smoke"
	smoke.position.y = 0.085
	smoke.amount = 24
	smoke.lifetime = 2.2
	smoke.local_coords = false
	smoke.direction = Vector3.UP
	smoke.spread = 12.0
	smoke.gravity = Vector3(0.0, 0.18, 0.0)
	smoke.initial_velocity_min = 0.04
	smoke.initial_velocity_max = 0.08
	smoke.scale_amount_min = 0.6
	smoke.scale_amount_max = 1.0
	var grow := Curve.new()
	grow.max_value = 3.0
	grow.add_point(Vector2(0.0, 0.2))
	grow.add_point(Vector2(1.0, 3.0))
	smoke.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.set_color(0, Color(0.85, 0.85, 0.85, 0.16))
	fade.set_color(1, Color(0.85, 0.85, 0.85, 0.0))
	smoke.color_ramp = fade
	var puff := SphereMesh.new()
	puff.radius = 0.012
	puff.height = 0.024
	puff.radial_segments = 8
	puff.rings = 4
	var puff_mat := StandardMaterial3D.new()
	puff_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff_mat.vertex_color_use_as_albedo = true
	puff_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	puff.material = puff_mat
	smoke.mesh = puff
	return smoke


## A pack: its bottom at the origin, its front (the picture) facing +Z.
static func make_pack() -> Node3D:
	var pack := Node3D.new()
	pack.name = "Pack"
	var box := _box(PACK, PACK_COLOR)
	box.position.y = PACK.y * 0.5
	pack.add_child(box)
	for side in [1.0, -1.0]:
		var face := MeshInstance3D.new()
		face.mesh = front_mesh()
		face.position = Vector3(0.0, PACK.y * 0.5, PACK.z * 0.5 * side + 0.0005 * side)
		if side < 0.0:
			face.rotation.y = PI
		pack.add_child(face)
	return pack


## The pack's front: a quad the size of the pack with the picture on it.
static func front_mesh() -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(PACK.x, PACK.y)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = front_texture()
	mat.roughness = 0.45
	quad.material = mat
	return quad


static func front_texture() -> Texture2D:
	if ResourceLoader.exists(PACK_FRONT):
		return load(PACK_FRONT)
	# Not imported yet (a build script run before the editor has seen it).
	var img := Image.load_from_file(PACK_FRONT)
	if img == null or img.is_empty():
		return null
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _box(size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.6
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	return mi
