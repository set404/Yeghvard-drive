@tool
extends Node3D
## The buildings, walls, gates, doors and models of the editable map (world/map/map.tscn),
## baked by tools/bake_map.gd into world/map_parts.scn without rebuilding the
## whole world. main.tscn stands it beside the world (node "World"); when the
## game starts it takes the place of the world's own baked buildings, walls,
## gates, doors and models, so the map's latest edits are what you see.
##
## In the Godot editor the world's own are only hidden from view, so main.tscn
## does not show the town twice (the old places as well as the new). They are
## hidden in the renderer, not by their visible property, so nothing about it
## is saved into main.tscn.

## The parts of the world this replaces.
const PARTS := ["Buildings", "Fences", "Gates", "Doors", "Props"]


func _ready() -> void:
	var world := get_parent().get_node_or_null("World") if get_parent() else null
	if world == null:
		return
	if Engine.is_editor_hint():
		_hide_old.call_deferred(world)
		return
	for part: String in PARTS:
		var old := world.get_node_or_null(part)
		if old:
			world.remove_child(old)
			old.queue_free()
		var mine := get_node_or_null(part)
		if mine:
			remove_child(mine)
			world.add_child(mine)


func _hide_old(world: Node) -> void:
	for part: String in PARTS:
		var old := world.get_node_or_null(part)
		if old == null:
			continue
		for mesh: GeometryInstance3D in old.find_children("*", "GeometryInstance3D", true, false):
			RenderingServer.instance_set_visible(mesh.get_instance(), false)
