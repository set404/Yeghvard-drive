extends SceneTree
## Bakes the buildings, walls and models (props) of the editable map
## (world/map/map.tscn) into res://world/map_parts.scn, which main.tscn puts in
## place of the world's own (see world/map_parts.gd). Quick, and needs none of the
## downloaded map data: the ground heights come from world/map/terrain_height.res.
## The trees and the minimap stay as tools/build_world.gd last made them; run that
## for a full rebuild.
##
## Run:  godot --headless --path . --script res://tools/bake_map.gd

const BuildWorld := preload("res://tools/build_world.gd")
const MapEditor := preload("res://world/map_editor.gd")
const OUT_PATH := "res://world/map_parts.scn"


func _initialize() -> void:
	quit(0 if bake() else 1)


static func bake() -> bool:
	var bw = BuildWorld.new()
	var p := deg_to_rad(BuildWorld.LAT0)
	bw.mz = 111132.92 - 559.82 * cos(2.0 * p) + 1.175 * cos(4.0 * p)
	bw.mx = 111412.84 * cos(p) - 93.5 * cos(3.0 * p)
	var heights: Image = load(BuildWorld.HEIGHTS_PATH)
	if heights == null or heights.get_width() != BuildWorld.GRID_N:
		push_error("No terrain heights in %s: run tools/build_world.gd once" % BuildWorld.HEIGHTS_PATH)
		bw.free()
		return false
	bw.hgt = heights.get_data().to_float32_array()
	var walls: Array[Dictionary] = bw._load_map()
	var root := Node3D.new()
	root.name = "MapParts"
	root.set_script(load("res://world/map_parts.gd"))
	bw._build_buildings(root)
	bw._build_walls(root, walls)
	bw.free()
	_add_props(root)
	_own(root, root)
	var scene := PackedScene.new()
	var err := scene.pack(root)
	if err == OK:
		err = ResourceSaver.save(scene, OUT_PATH, ResourceSaver.FLAG_COMPRESS)
	print("Saved %s: %s (%s)" % [OUT_PATH, error_string(err), ", ".join(root.get_children().map(func(n: Node) -> String: return "%s %d" % [n.name, n.get_child_count()]))])
	root.free()
	return err == OK


## The map's models (its "Props"), each as world/map_editor.gd places them.
static func _add_props(root: Node3D) -> void:
	var map: Node = (load("res://world/map/map.tscn") as PackedScene).instantiate()
	var src := map.get_node_or_null("Props") as Node3D
	if src:
		var props := Node3D.new()
		props.name = "Props"
		root.add_child(props)
		for node in src.get_children():
			var prop := MapEditor.make_prop(str(node.get_meta("scene", node.scene_file_path)))
			if prop == null:
				push_warning("No model for " + node.name)
				continue
			prop.name = node.name
			prop.set_meta("map_key", "Props/" + node.name)
			props.add_child(prop)
			prop.transform = (node as Node3D).transform
	map.free()


static func _own(node: Node, top: Node) -> void:
	for child in node.get_children():
		child.owner = top
		# The models are saved as instances of their own scenes, not copied in.
		if child.scene_file_path == "":
			_own(child, top)
