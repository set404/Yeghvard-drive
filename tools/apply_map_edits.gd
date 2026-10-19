extends SceneTree
## Makes the changes made in the in-game map editor (world/map_editor.gd, saved
## in world/map/map_edits.json) a fixed part of the map: buildings and walls
## moved, turned, changed or removed in world/map/map.tscn, and the models placed
## there as nodes under its "Props". Then bakes the map for the game (as tools/bake_map.gd does) and
## empties the edits file (keeping a copy, map_edits.applied.json).
##
## Run:  godot --headless --path . --script res://tools/apply_map_edits.gd

const MAP_PATH := "res://world/map/map.tscn"
const EDITS_PATH := "res://world/map/map_edits.json"


func _initialize() -> void:
	if not FileAccess.file_exists(EDITS_PATH):
		print("No edits in %s" % EDITS_PATH)
		quit(0)
		return
	var edits: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(EDITS_PATH))
	var map: Node3D = (load(MAP_PATH) as PackedScene).instantiate()
	var moved := 0
	var removed := 0
	for kind in ["buildings", "walls"]:
		var changed: Dictionary = edits.get(kind, {})
		for path: String in changed:
			var node := map.get_node_or_null(path) as Node3D
			if node == null:
				push_warning("Not in the map any more: " + path)
				continue
			var e: Dictionary = changed[path]
			if e.get("removed", false):
				node.get_parent().remove_child(node)
				node.free()
				removed += 1
				continue
			# How it looks.
			if kind == "buildings":
				node.set("height", float(e["height"]))
				node.set("wall_color", Color.html(e["wall"]))
				node.set("roof_color", Color.html(e["roof"]))
				node.set("plain", bool(e["plain"]))
				node.set("tuff", bool(e["tuff"]))
			else:
				node.set("kind", int(e["kind"]))
				node.set("color", Color.html(e["color"]))
				node.set("height", float(e["height"]))
				node.set("gate_at", float(e["gate_at"]))
				node.set("gate_color", Color.html(e["gate_color"]))
				node.set("gate_swing", int(e.get("swing", 0)))
			# Where it is: the same turn about the middle of its points, then the
			# shift, as the editor shows.
			var off: Array = e.get("offset", [0.0, 0.0])
			var yaw := float(e.get("yaw", 0.0))
			if is_zero_approx(float(off[0])) and is_zero_approx(float(off[1])) and is_zero_approx(yaw):
				continue
			var flat: Array = e["poly"] if e.has("poly") else e["pts"]
			var c := Vector3.ZERO
			for k in range(0, flat.size() - 1, 2):
				c += Vector3(flat[k], 0.0, flat[k + 1])
			c /= maxf(flat.size() / 2, 1)
			var delta := Transform3D(Basis(Vector3.UP, yaw), c + Vector3(off[0], 0.0, off[1])) * Transform3D(Basis.IDENTITY, -c)
			node.transform = _world(node.get_parent()).affine_inverse() * delta * _world(node)
			moved += 1
	var props_root := map.get_node_or_null("Props") as Node3D
	if props_root == null:
		props_root = Node3D.new()
		props_root.name = "Props"
		map.add_child(props_root)
		props_root.owner = map
	var added := 0
	for e: Dictionary in edits.get("props", []):
		var key: String = e.get("key", "")
		var node := map.get_node_or_null(key) as Node3D if key != "" else null
		if e.get("removed", false):
			if node:
				node.get_parent().remove_child(node)
				node.free()
				removed += 1
			continue
		var pos: Array = e["pos"]
		var xf := Transform3D(Basis(Vector3.UP, float(e["yaw"])).scaled(Vector3.ONE * float(e["scale"])), Vector3(pos[0], pos[1], pos[2]))
		if node == null:
			var scene_path: String = e["scene"]
			if not ResourceLoader.exists(scene_path):
				push_warning("No model " + scene_path)
				continue
			# An instance of the model, so it shows in the map in the editor too.
			var res: Resource = load(scene_path)
			if res is PackedScene:
				node = (res as PackedScene).instantiate() as Node3D
			elif res is Mesh:
				node = MeshInstance3D.new()
				(node as MeshInstance3D).mesh = res
			if node == null:
				push_warning("Not a model: " + scene_path)
				continue
			node.name = "Prop_%d" % (props_root.get_child_count() + 1)
			while props_root.has_node(NodePath(node.name)):
				node.name = node.name + "_"
			node.set_meta("scene", scene_path)
			props_root.add_child(node)
			node.owner = map
			added += 1
		else:
			moved += 1
		node.transform = _world(node.get_parent()).affine_inverse() * xf
	var scene := PackedScene.new()
	var err := scene.pack(map)
	if err == OK:
		err = ResourceSaver.save(scene, MAP_PATH)
	map.free()
	print("Map: %d moved or changed, %d removed, %d models added -> %s (%s)" % [moved, removed, added, MAP_PATH, error_string(err)])
	if err != OK:
		quit(1)
		return
	DirAccess.rename_absolute(ProjectSettings.globalize_path(EDITS_PATH), ProjectSettings.globalize_path("res://world/map/map_edits.applied.json"))
	# Bake it, as tools/bake_map.gd does.
	var bake: Script = load("res://tools/bake_map.gd")
	var ok: bool = bake.bake()
	quit(0 if ok else 1)


func _world(node: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	while node:
		if node is Node3D:
			xf = (node as Node3D).transform * xf
		node = node.get_parent()
	return xf
