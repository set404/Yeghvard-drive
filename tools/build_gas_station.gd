extends SceneTree
## Builds res://world/gas_station.scn from the Lowpoly Gas Station model
## (data/models/gas_station, see data/models/CREDITS.txt): one mesh and the
## collision of its larger pieces. The shop front and the pumps face +X.
##
## The station stands in main.tscn (node GasStation), where OpenStreetMap has the
## fuel station on the Yeghvard highway (building 464545727): move and turn it
## there in the editor. The plain box tools/build_world.gd made for that building
## is taken out of res://world/yeghvard.scn (newer builds leave the gap; see
## "replaced" in its BUILDING_FIXES), so run this again after rebuilding the world.
##
## Run:  godot --path . --script res://tools/build_gas_station.gd
## (not --headless: saving the world scene headless would drop its trees)

const WORLD_PATH := "res://world/yeghvard.scn"
const MAP_PATH := "res://world/map/map.tscn"
const MODEL_PATH := "res://data/models/gas_station/lowpoly_gas_station.glb"
const OUT_PATH := "res://world/gas_station.scn"
const OSM_ID := 464545727
## The price sign stands by the road in the model, in the highway once placed
## here: its pole and panel go to the side of the forecourt instead (model
## space, metres; panel centre x 17.7, z 0.35), and the curb strip it stood on
## is left out.
const SIGN_PIECES := ["Sign_Palette_0", "Sign_Sign_0"]
const SIGN_MOVE := Vector3(-9.7, 0.0, 12.65)
const CURB_TOP := 0.4
## The forecourt under the pump canopy, in model space (metres).
const PUMP_ZONE := AABB(Vector3(1.4, 0.0, -7.7), Vector3(12.7, 4.0, 16.1))
## Pieces this small get no collision (snacks, coins, signs on the glass...).
const MIN_SOLID := 1.5

func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Run without --headless: saving the world headless would drop its trees.")
		quit(1)
		return
	_run.call_deferred()


func _run() -> void:
	var map: Node3D = (load(MAP_PATH) as PackedScene).instantiate()
	root.add_child(map)
	await process_frame
	var outline := PackedVector2Array()
	for b in map.find_children("Building_*", "Node3D", true, false):
		if b.get("osm_id") == OSM_ID:
			outline = b.call("world_footprint")
	map.free()
	if outline.is_empty():
		push_error("Building %d is not in %s" % [OSM_ID, MAP_PATH])
		quit(1)
		return

	var station := _build_station()
	_own(station, station)
	var scene := PackedScene.new()
	var err := scene.pack(station)
	if err == OK:
		err = ResourceSaver.save(scene, OUT_PATH, ResourceSaver.FLAG_COMPRESS)
	station.free()
	if err != OK:
		push_error("Saving %s failed: %s" % [OUT_PATH, error_string(err)])
		quit(1)
		return
	print("Saved %s" % OUT_PATH)

	var world: Node3D = load(WORLD_PATH).instantiate()
	root.add_child(world)
	var removed := _strip_old_building(world, outline)
	# Earlier versions of this tool stood the station in the world itself.
	var old := world.get_node_or_null("GasStation")
	var had_old := old != null
	if had_old:
		world.remove_child(old)
		old.free()
	if removed > 0 or had_old:
		print("Took %d triangles of the old building out of the world" % removed)
		_save_world(world)
	else:
		world.free()
	quit(0)


## The model as one mesh (a surface per material) and a static body with the
## shapes of its larger pieces, in the model's own space.
func _build_station() -> Node3D:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(ProjectSettings.globalize_path(MODEL_PATH), state)
	if err != OK:
		push_error("Loading %s failed: %s" % [MODEL_PATH, error_string(err)])
		return Node3D.new()
	var model: Node3D = doc.generate_scene(state)
	root.add_child(model)

	var tools := {}
	var faces := PackedVector3Array()
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	for mi: MeshInstance3D in meshes:
		var source: Mesh = mi.mesh
		var xf := mi.global_transform
		if mi.name in SIGN_PIECES:
			source = _without_curb(mi.mesh, xf)
			xf = Transform3D(Basis.IDENTITY, SIGN_MOVE)
		for s in source.get_surface_count():
			var mat := mi.get_active_material(s)
			if not tools.has(mat):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[mat] = st
			tools[mat].append_from(source, s, xf)
		var size := (xf * source.get_aabb()).size
		if maxf(size.x, maxf(size.y, size.z)) >= MIN_SOLID:
			var piece := source.get_faces()
			for k in piece.size():
				piece[k] = xf * piece[k]
			faces.append_array(piece)

	var station := Node3D.new()
	station.name = "GasStation"
	var mesh := ArrayMesh.new()
	for mat in tools:
		var st: SurfaceTool = tools[mat]
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
	var look := MeshInstance3D.new()
	look.name = "Model"
	look.mesh = mesh
	station.add_child(look)
	var body := StaticBody3D.new()
	body.name = "Body"
	station.add_child(body)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	cs.shape = shape
	body.add_child(cs)

	# Where a car can stand to fill up: the forecourt under the canopy. main.gd
	# looks for areas in the "fuel_pumps" group.
	var pumps := Area3D.new()
	pumps.name = "Pumps"
	pumps.add_to_group("fuel_pumps", true)
	pumps.monitorable = false
	station.add_child(pumps)
	var zone := CollisionShape3D.new()
	zone.name = "Zone"
	var box := BoxShape3D.new()
	box.size = PUMP_ZONE.size
	zone.shape = box
	zone.position = PUMP_ZONE.get_center()
	pumps.add_child(zone)
	print("Model: %d pieces in %d surfaces, %d collision triangles" % [meshes.size(), mesh.get_surface_count(), faces.size() / 3])
	model.free()
	return station


## The mesh moved into model space by xf, without the triangles lying wholly
## below CURB_TOP (the curb strip under the price sign).
func _without_curb(mesh: Mesh, xf: Transform3D) -> ArrayMesh:
	var out := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.append_from(mesh, s, xf)
		var arr := st.commit_to_arrays()
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx := PackedInt32Array()
		if arr[Mesh.ARRAY_INDEX] == null:
			idx.resize(v.size())
			for k in v.size():
				idx[k] = k
		else:
			idx = arr[Mesh.ARRAY_INDEX]
		var keep := PackedInt32Array()
		for k in range(0, idx.size(), 3):
			if maxf(v[idx[k]].y, maxf(v[idx[k + 1]].y, v[idx[k + 2]].y)) >= CURB_TOP:
				keep.append_array([idx[k], idx[k + 1], idx[k + 2]])
		arr[Mesh.ARRAY_INDEX] = keep
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return out


## Removes the walls and roof of the box build_world.gd made for the building.
## Returns how many triangles went.
func _strip_old_building(world: Node3D, outline: PackedVector2Array) -> int:
	var zone: PackedVector2Array = Geometry2D.offset_polygon(outline, 0.05)[0]
	var inside := func(p: Vector3) -> bool:
		return Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), zone)
	var removed := 0
	var buildings := world.get_node("Buildings")
	for mi: MeshInstance3D in buildings.find_children("*", "MeshInstance3D", false, false):
		var arr := mi.mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var keep := PackedInt32Array()
		for k in range(0, idx.size(), 3):
			if inside.call(v[idx[k]]) and inside.call(v[idx[k + 1]]) and inside.call(v[idx[k + 2]]):
				removed += 1
				continue
			keep.append_array([idx[k], idx[k + 1], idx[k + 2]])
		if keep.size() == idx.size():
			continue
		var mat := mi.mesh.surface_get_material(0)
		arr[Mesh.ARRAY_INDEX] = keep
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.surface_set_material(0, mat)
		mi.mesh = mesh
	for cs: CollisionShape3D in buildings.find_children("*", "CollisionShape3D", false, false):
		var shape := cs.shape as ConcavePolygonShape3D
		if shape == null:
			continue
		var f := shape.get_faces()
		var kept := PackedVector3Array()
		for k in range(0, f.size(), 3):
			if not (inside.call(f[k]) and inside.call(f[k + 1]) and inside.call(f[k + 2])):
				kept.append_array([f[k], f[k + 1], f[k + 2]])
		if kept.size() != f.size():
			var fresh := ConcavePolygonShape3D.new()
			fresh.set_faces(kept)
			cs.shape = fresh
	return removed


func _save_world(world: Node3D) -> void:
	world.get_parent().remove_child(world)
	var scene := PackedScene.new()
	var err := scene.pack(world)
	if err == OK:
		err = ResourceSaver.save(scene, WORLD_PATH, ResourceSaver.FLAG_COMPRESS)
	if err != OK:
		push_error("Saving %s failed: %s" % [WORLD_PATH, error_string(err)])
	else:
		print("Saved %s" % WORLD_PATH)
	world.free()


func _own(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		_own(child, owner_node)
