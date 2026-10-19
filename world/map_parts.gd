extends Node3D
## The buildings, walls, gates, doors and models of the editable map (world/map/map.tscn),
## baked by tools/bake_map.gd into world/map_parts.scn without rebuilding the
## whole world. main.tscn stands it beside the world (node "World"); when the
## game starts it takes the place of the world's own baked buildings, walls,
## gates, doors and models, so the map's latest edits are what you see.

## The parts of the world this replaces.
const PARTS := ["Buildings", "Fences", "Gates", "Doors", "Props"]


func _ready() -> void:
	var world := get_parent().get_node_or_null("World") if get_parent() else null
	if world == null:
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
