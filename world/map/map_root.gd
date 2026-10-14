@tool
extends Node3D
## Root of the editable map (world/map/map.tscn). In the editor it shows the
## baked world underneath for reference (terrain, roads, trees), without the
## baked buildings and walls, which the map's own nodes stand in for. Nothing of
## this is saved with the map.
##
## After editing, bake the map into the game:
##   godot --path . --script res://tools/build_world.gd

@export var show_ground := true:
	set(value):
		show_ground = value
		if _ground:
			_ground.visible = value

var _ground: Node3D


func _ready() -> void:
	if not Engine.is_editor_hint() or not ResourceLoader.exists("res://world/yeghvard.scn"):
		return
	_ground = (load("res://world/yeghvard.scn") as PackedScene).instantiate()
	for part in ["Buildings", "Fences"]:
		var baked := _ground.get_node_or_null(part)
		if baked:
			baked.queue_free()
	_ground.visible = show_ground
	add_child(_ground, false, INTERNAL_MODE_FRONT)
