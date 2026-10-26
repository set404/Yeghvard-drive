extends Node3D
## A small cardboard box of 9 mm rounds (no model yet), as the inventory shows it.


func _ready() -> void:
	var box := BoxMesh.new()
	box.size = Vector3(0.09, 0.05, 0.06)
	var card := StandardMaterial3D.new()
	card.albedo_color = Color(0.55, 0.42, 0.22)
	card.roughness = 0.9
	box.material = card
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.position.y = 0.025
	add_child(mi)
	var label := Label3D.new()
	label.text = "9mm"
	label.font_size = 40
	label.pixel_size = 0.0008
	label.outline_size = 0
	label.modulate = Color(0.1, 0.08, 0.05)
	label.position = Vector3(0.0, 0.026, 0.031)
	add_child(label)
