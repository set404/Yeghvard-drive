extends Node3D
## The in-game map editor. F2 opens it (the game pauses) and closes it again.
##
## In it you fly about freely and change the town: move, turn or remove
## buildings and walls, change how they look (colours, height, a wall's kind and
## its gate), and place models (props) from res://props: any .glb, .gltf, .fbx,
## .obj, .tscn or .scn put in that folder. Your changes are kept in
## world/map/map_edits.json (Ctrl+S); each time the game starts they are put on
## top of the baked town, so you see them straight away. To make them a fixed
## part of the map, tools/apply_map_edits.gd writes them into world/map/map.tscn
## and bakes it (tools/bake_map.gd), after which the edits file is emptied.
##
## Keys while editing:
##   W A S D, Space / C   fly, up / down (Shift: faster)
##   Arrow keys           look about (Alt: slowly), as holding the right mouse button does
##   Left click           pick a building, wall or model; the panel on the right changes how it looks
##   G                    move what is picked (it follows the mouse; click to drop, right click to cancel)
##   E                    a wall: drag the corner (or end) nearest the mouse; its length is in the panel too
##   Z / X                turn it (15 degrees, with Shift 1)
##   Delete               remove it
##   + / -                make a model bigger / smaller
##   Tab / Shift+Tab      choose the model to place;  N  place it (it follows the mouse; click to drop)
##   Ctrl+Z               undo        Ctrl+S  save
##   Esc                  drop the pick, or close the editor

const MapKit := preload("res://world/map/map_kit.gd")
const MAP_BUILDING := preload("res://world/map/map_building.gd")
const MAP_WALL := preload("res://world/map/map_wall.gd")
## The town's baker: the chunks a changed building or wall was baked into are
## baked again here without it (all on the processor: reading the baked meshes
## back from the graphics card is what made the graphics driver give out).
const BuildWorld := preload("res://tools/build_world.gd")
const MAP_PATH := "res://world/map/map.tscn"
const EDITS_PATH := "res://world/map/map_edits.json"
const PROPS_DIR := "res://props"
const MODEL_EXTENSIONS := ["glb", "gltf", "fbx", "obj", "tscn", "scn", "blend"]
## Not F9: when the game runs from the Godot editor, F9 suspends it.
const TOGGLE_KEY := KEY_F2
## How near (metres) a click has to be to a building's outline or a wall to pick it.
const PICK_MARGIN := 0.7
## Baked walls within this (metres) of a changed wall's line are its own.
const WALL_REACH := 0.45
const KIND_NAMES := ["Stone", "Sheet metal", "Wire mesh"]
const SWING_NAMES := ["Fixed (shut)", "Opens left", "Opens right"]

## The edits, by path in map.tscn:
## buildings[path] = {poly: [x, z, ...] (world metres, as in the map), height,
##   wall, roof (colours as html), plain, tuff, removed, offset: [dx, dz], yaw (radians)}
## walls[path] = {pts: [x, z, ...], kind, color, height, gate_at (-1: none),
##   gate_color, swing, removed, offset, yaw}; a wall reshaped in the editor keeps
##   its new corners in pts and the map's in orig
## props[i] = {key: its path in map.tscn ("" for a new one), scene, pos: [x, y, z],
##   yaw, scale, removed}
var edits := {"buildings": {}, "walls": {}, "props": []}
var editing := false

var _world: Node3D
var _layer: Node3D ## the edited buildings and walls and the props, in the world
var _camera: Camera3D
var _previous_camera: Camera3D
var _was_paused := false
var _previous_mouse := Input.MOUSE_MODE_VISIBLE
var _ui: CanvasLayer
var _status: Label
var _panel: PanelContainer
var _outline: MeshInstance3D

## The map's buildings and walls, read from map.tscn the first time the editor
## opens (path -> what it is like), and grids of their paths by 50 m cell.
var _map_buildings := {}
var _map_walls := {}
var _grid := {}
var _wall_grid := {}
## The baked props of the map (World/Props), by path.
var _baked_props := {}
var _models: PackedStringArray = []
var _model := 0
## "building:path", "wall:path" or "prop:i" -> the node showing it in _layer.
var _shown := {}

## What is picked: kind "building", "wall", "prop" or "", and its path (or prop index).
var _pick_kind := ""
var _pick_key := ""
var _moving := false
var _move_from := Vector3.ZERO
var _move_start := {}
## While moving: the edit as it was when what is moved was last drawn. It is
## then only shifted and turned each frame (making new meshes every frame wears
## out the graphics driver), and drawn properly again when dropped.
var _drag_ref := {}
var _drag_redraw := 0
var _drag_node_xf := Transform3D.IDENTITY
var _undo: Array[String] = []
var _bw: Object ## a BuildWorld, made when first needed
## Buildings and walls (paths) the baked chunks are now made without.
var _left_out := {"buildings": {}, "walls": {}}
var _undo_tag := ""
var _undo_time := 0
var _unsaved := false
var _look := false
var _yaw := 0.0
var _pitch := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_world = get_parent().get_node_or_null("World") as Node3D
	if _world == null:
		return
	_layer = Node3D.new()
	_layer.name = "MapEdits"
	_world.add_child(_layer)
	_load_edits()
	if not (edits["buildings"].is_empty() and edits["walls"].is_empty()):
		_read_map()
	_apply_all()


func _exit_tree() -> void:
	if _bw:
		_bw.free()
		_bw = null


# --- the edits on the town -------------------------------------------------

func _load_edits() -> void:
	for path in [EDITS_PATH, "user://map_edits.json"]:
		if not FileAccess.file_exists(path):
			continue
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if data is Dictionary:
			edits["buildings"] = data.get("buildings", {})
			edits["walls"] = data.get("walls", {})
			edits["props"] = data.get("props", [])
			return


func _save_edits() -> void:
	var text := JSON.stringify(edits, "\t")
	var file := FileAccess.open(EDITS_PATH, FileAccess.WRITE)
	var where := EDITS_PATH
	if file == null:
		# res:// cannot be written in an exported game.
		file = FileAccess.open("user://map_edits.json", FileAccess.WRITE)
		where = ProjectSettings.globalize_path("user://map_edits.json")
	if file == null:
		_say("Could not save the edits!")
		return
	file.store_string(text)
	file.close()
	_unsaved = false
	_say("Saved to " + where)


## Puts every edit on the town: changed buildings and walls are left out of the
## baked chunks and drawn again as they now are; props are placed.
func _apply_all() -> void:
	for child in _layer.get_children():
		child.queue_free()
	_shown.clear()
	_refresh_baked()
	for path: String in edits["buildings"]:
		_show("building", path)
	for path: String in edits["walls"]:
		_show("wall", path)
	var props: Array = edits["props"]
	for i in props.size():
		_show("prop", str(i))


## A building's outline or a wall's corners, as the map has them (world metres).
func _points(entry: Dictionary) -> PackedVector2Array:
	var flat: Array = entry["poly"] if entry.has("poly") else entry["pts"]
	var out := PackedVector2Array()
	for k in range(0, flat.size() - 1, 2):
		out.append(Vector2(flat[k], flat[k + 1]))
	return out


static func _flat(points: PackedVector2Array) -> Array:
	var flat := []
	for p in points:
		flat.append_array([snappedf(p.x, 0.001), snappedf(p.y, 0.001)])
	return flat


## Where the edit puts those points: turned about their middle, then shifted.
func _moved(entry: Dictionary) -> PackedVector2Array:
	var pts := _points(entry)
	var c := _centre(pts)
	var off: Array = entry.get("offset", [0.0, 0.0])
	var basis := Basis(Vector3.UP, float(entry.get("yaw", 0.0)))
	var out := PackedVector2Array()
	for p in pts:
		var r := basis * Vector3(p.x - c.x, 0.0, p.y - c.y)
		out.append(Vector2(c.x + float(off[0]) + r.x, c.y + float(off[1]) + r.z))
	return out


static func _centre(pts: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in pts:
		c += p
	return c / maxf(pts.size(), 1)


func _entry(kind: String, key: String) -> Dictionary:
	if kind == "prop":
		return edits["props"][int(key)]
	return edits[kind + "s"].get(key, {})


## Draws one edited building, wall or prop as it now is (nothing if removed), with
## something to collide with unless `solid` is false (while it is being moved).
func _show(kind: String, key: String, solid := true) -> void:
	var id := kind + ":" + key
	var old: Node = _shown.get(id)
	if old:
		old.queue_free()
		_shown.erase(id)
	var e := _entry(kind, key)
	if kind == "prop":
		var baked := _baked_prop(e.get("key", ""))
		if baked:
			baked.visible = false
			for cs: CollisionShape3D in baked.find_children("*", "CollisionShape3D", true, false):
				cs.disabled = true
	if e.is_empty() or e.get("removed", false):
		return
	var node: StaticBody3D
	if kind == "prop":
		node = make_prop(e["scene"], solid)
		if node == null:
			return
		var pos: Array = e["pos"]
		node.transform = Transform3D(Basis(Vector3.UP, float(e["yaw"])).scaled(Vector3.ONE * float(e["scale"])),
			Vector3(pos[0], pos[1], pos[2]))
	else:
		var mesh: ArrayMesh
		if kind == "building":
			mesh = MapKit.building_mesh(_moved(e), float(e["height"]), Color.html(e["wall"]), Color.html(e["roof"]),
				bool(e["plain"]), bool(e["tuff"]), Transform3D.IDENTITY)
		else:
			mesh = MapKit.wall_mesh(_moved(e), int(e["kind"]), Color.html(e["color"]), float(e["height"]),
				float(e["gate_at"]), Color.html(e["gate_color"]), Transform3D.IDENTITY)
		if mesh == null:
			return
		node = StaticBody3D.new()
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		node.add_child(mi)
		if solid:
			# Made from the outline, not from the mesh (reading a mesh back from
			# the graphics card upsets the graphics driver).
			var cs := CollisionShape3D.new()
			cs.shape = _solid(kind, _moved(e), float(e["height"]))
			node.add_child(cs)
	node.set_meta("map_kind", kind)
	node.set_meta("map_key", key)
	_layer.add_child(node)
	_shown[id] = node


## Something to bump into for a building (its walls and roof) or a wall (a thin
## slab along each run), in world space.
func _solid(kind: String, pts: PackedVector2Array, height: float) -> ConcavePolygonShape3D:
	var faces := PackedVector3Array()
	var low := INF
	var high := -INF
	for p in pts:
		var y := MapKit.height_at(p.x, p.y)
		low = minf(low, y)
		high = maxf(high, y)
	low -= 0.6
	var top := high + height
	var quad := func(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
		faces.append_array([a, b, c, a, c, d])
	if kind == "building":
		for k in pts.size():
			var a := pts[k]
			var b := pts[(k + 1) % pts.size()]
			quad.call(Vector3(a.x, low, a.y), Vector3(b.x, low, b.y), Vector3(b.x, top, b.y), Vector3(a.x, top, a.y))
		var tris := Geometry2D.triangulate_polygon(pts)
		for i in tris:
			faces.append(Vector3(pts[i].x, top, pts[i].y))
	else:
		for k in pts.size() - 1:
			var a := pts[k]
			var b := pts[k + 1]
			if a.distance_to(b) < 0.01:
				continue
			var d := (b - a).normalized()
			var n := Vector2(d.y, -d.x) * 0.15
			for side in [n, -n]:
				quad.call(Vector3(a.x + side.x, low, a.y + side.y), Vector3(b.x + side.x, low, b.y + side.y),
					Vector3(b.x + side.x, top, b.y + side.y), Vector3(a.x + side.x, top, a.y + side.y))
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	return shape


## A prop: the model, standing on a static body with a box round it to bump into.
## tools/bake_map.gd makes the baked ones the same way.
static func make_prop(scene_path: String, solid := true) -> StaticBody3D:
	if not ResourceLoader.exists(scene_path):
		return null
	var res: Resource = load(scene_path)
	var model: Node3D
	if res is PackedScene:
		model = (res as PackedScene).instantiate() as Node3D
	elif res is Mesh:
		model = MeshInstance3D.new()
		(model as MeshInstance3D).mesh = res
	if model == null:
		return null
	var body := StaticBody3D.new()
	body.name = "Prop"
	body.set_meta("scene", scene_path)
	body.add_child(model)
	if solid:
		# The model's own surfaces, not a box round it, so you can walk into a
		# besedka or under a bus stop's roof.
		var meshes: Array = model.find_children("*", "MeshInstance3D", true, false)
		if model is MeshInstance3D:
			meshes.append(model)
		for mi: MeshInstance3D in meshes:
			if mi.mesh == null:
				continue
			var shape := mi.mesh.create_trimesh_shape()
			if shape == null:
				continue
			shape.backface_collision = true
			var cs := CollisionShape3D.new()
			cs.shape = shape
			cs.transform = _relative_xf(mi, body)
			body.add_child(cs)
	return body


static func _relative_xf(node: Node3D, top: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n and n != top:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


func _baked_prop(key: String) -> Node3D:
	if key == "":
		return null
	var props := _world.get_node_or_null("Props")
	return props.get_node_or_null(key.get_file()) as Node3D if props else null


## Bakes again every chunk of the town whose buildings or walls left out have
## changed, so the baked town has none of the edited ones (they are drawn by
## _show) and all the others, as the map has them.
func _refresh_baked() -> void:
	if _map_buildings.is_empty() and _map_walls.is_empty():
		return
	for kind in ["buildings", "walls"]:
		var want: Dictionary = edits[kind]
		var have: Dictionary = _left_out[kind]
		var chunks := {}
		for path: String in want:
			if not have.has(path):
				_chunks_of(kind, path, chunks)
		for path: String in have:
			if not want.has(path):
				_chunks_of(kind, path, chunks)
		var now := {}
		for path: String in want:
			now[path] = true
		if kind == "walls":
			for path: String in want:
				if not have.has(path):
					_wall_gates(path, false)
			for path: String in have:
				if not want.has(path):
					_wall_gates(path, true)
		_left_out[kind] = now
		for key: Vector2i in chunks:
			_rebake(kind, key)


## Hides (or shows again) the baked swinging gate of a map wall, a node of its own.
func _wall_gates(path: String, on: bool) -> void:
	var gates := _world.get_node_or_null("Gates")
	if gates == null or not _map_walls.has(path):
		return
	var pts := _points(_map_walls[path])
	for gate in gates.get_children():
		if not (gate is Node3D) or not str(gate.name).begins_with("YardGate"):
			continue
		var g := (gate as Node3D).global_position
		if _distance(Vector2(g.x, g.z), pts, false) < 1.5:
			(gate as Node3D).visible = on
			gate.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
			for cs: CollisionShape3D in gate.find_children("*", "CollisionShape3D", true, false):
				cs.disabled = not on


## The baked chunks a building (by its middle) or a wall (all along) is in.
func _chunks_of(kind: String, path: String, into: Dictionary) -> void:
	if kind == "buildings":
		if _map_buildings.has(path):
			var c := _centre(_points(_map_buildings[path]))
			into[Vector2i(floori(c.x / BuildWorld.OBJ_CHUNK), floori(c.y / BuildWorld.OBJ_CHUNK))] = true
		return
	if not _map_walls.has(path):
		return
	var pts := _points(_map_walls[path])
	var size: float = BuildWorld.FENCE_CHUNK
	for k in pts.size():
		into[Vector2i(floori(pts[k].x / size), floori(pts[k].y / size))] = true
		if k + 1 < pts.size():
			var steps := ceili(pts[k].distance_to(pts[k + 1]) / 5.0)
			for i in steps + 1:
				var p := pts[k].lerp(pts[k + 1], float(i) / maxf(steps, 1))
				into[Vector2i(floori(p.x / size), floori(p.y / size))] = true


func _builder() -> Object:
	if _bw == null:
		_bw = BuildWorld.new()
		var p := deg_to_rad(BuildWorld.LAT0)
		_bw.mz = 111132.92 - 559.82 * cos(2.0 * p) + 1.175 * cos(4.0 * p)
		_bw.mx = 111412.84 * cos(p) - 93.5 * cos(3.0 * p)
		var heights: Image = load(BuildWorld.HEIGHTS_PATH)
		_bw.hgt = heights.get_data().to_float32_array()
	return _bw


## The baker's form of a map building.
func _bake_building(path: String) -> Dictionary:
	var b: Dictionary = _map_buildings[path]
	var poly := _points(b)
	var area := 0.0
	for k in poly.size():
		area += poly[k].cross(poly[(k + 1) % poly.size()]) * 0.5
	if area < 0.0:
		poly.reverse()
		area = -area
	return {"poly": poly, "id": int(b.get("id", 0)), "area": area, "tags": {"building": "shed" if b["plain"] else "yes"},
		"height": float(b["height"]), "wall": Color.html(b["wall"]), "roof": Color.html(b["roof"]),
		"plain": bool(b["plain"]), "stone": bool(b["tuff"])}


## Bakes one chunk of the town's buildings or walls again, leaving out the edited
## ones, and puts it in place of the world's.
func _rebake(kind: String, key: Vector2i) -> void:
	var bw := _builder()
	var part := "Buildings" if kind == "buildings" else "Fences"
	var root := Node3D.new()
	if kind == "buildings":
		var list: Array[Dictionary] = []
		for path: String in _map_buildings:
			if edits["buildings"].has(path):
				continue
			var c := _centre(_points(_map_buildings[path]))
			if Vector2i(floori(c.x / BuildWorld.OBJ_CHUNK), floori(c.y / BuildWorld.OBJ_CHUNK)) == key:
				list.append(_bake_building(path))
		bw.buildings = list
		bw._build_buildings(root)
	else:
		# Walls keep out of the buildings, so the baker needs all of them.
		var all_buildings: Array[Dictionary] = []
		for path: String in _map_buildings:
			all_buildings.append(_bake_building(path))
		bw.buildings = all_buildings
		var size: float = BuildWorld.FENCE_CHUNK
		var area := Rect2(Vector2(key) * size, Vector2(size, size)).grow(6.0)
		var walls: Array[Dictionary] = []
		for path: String in _map_walls:
			if edits["walls"].has(path):
				continue
			var w: Dictionary = _map_walls[path]
			var pts := _points(w)
			if not _box(pts, 0.0).intersects(area):
				continue
			walls.append({"pts": pts, "kind": int(w["kind"]), "color": Color.html(w["color"]), "height": float(w["height"]),
				"gate": float(w["gate_at"]), "gate_color": Color.html(w["gate_color"]), "swing": int(w["swing"])})
		bw._build_walls(root, walls)
	var made: Array = _chunk_parts(root.get_node_or_null(part), part).get(key, [])
	var mine: Array = _chunk_parts(_world.get_node_or_null(part), part).get(key, [])
	if not mine.is_empty():
		(mine[0] as MeshInstance3D).mesh = (made[0] as MeshInstance3D).mesh if not made.is_empty() else null
		if mine[1]:
			(mine[1] as CollisionShape3D).shape = (made[1] as CollisionShape3D).shape if not made.is_empty() and made[1] else ConcavePolygonShape3D.new()
	elif not made.is_empty():
		# A chunk the world had nothing in (a wall moved there): take the new one.
		var body := _world.get_node(part)
		for n: Node in made:
			if n:
				n.get_parent().remove_child(n)
				body.add_child(n)
	root.free()


## A baked part's chunks: key -> [its mesh, its collision], from how the baker
## lays them out (each chunk's mesh, "<part>_x_y", then its collision).
func _chunk_parts(body: Node, part: String) -> Dictionary:
	var out := {}
	if body == null:
		return out
	var last := Vector2i.MAX
	for child in body.get_children():
		if child is MeshInstance3D and str(child.name).begins_with(part + "_"):
			var bits := str(child.name).split("_")
			last = Vector2i(int(bits[bits.size() - 2]), int(bits[bits.size() - 1]))
			out[last] = [child, null]
		elif child is CollisionShape3D and out.has(last) and out[last][1] == null:
			out[last][1] = child
	return out


func _box(pts: PackedVector2Array, grow: float) -> Rect2:
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	return r.grow(grow)


# --- the editor --------------------------------------------------------------

func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.physical_keycode == TOGGLE_KEY:
		_set_editing(not editing)
		get_viewport().set_input_as_handled()
		return
	if not editing:
		return
	if key and key.pressed and key.physical_keycode == KEY_ESCAPE:
		if _moving:
			_cancel_move()
		elif _pick_kind != "":
			_select("", "")
		else:
			_set_editing(false)
		get_viewport().set_input_as_handled()
		return
	var motion := event as InputEventMouseMotion
	if motion and _look:
		_yaw -= motion.relative.x * 0.004
		_pitch = clampf(_pitch - motion.relative.y * 0.004, -1.5, 1.5)
		_camera.rotation = Vector3(_pitch, _yaw, 0.0)
		get_viewport().set_input_as_handled()
		return
	# F3 is the locator's (game/locator.gd): it copies the spot under the mouse.
	# F4 and F5 are the teleport's (game/teleport.gd), F6 the mission select's.
	if key and key.pressed and not key.physical_keycode in [KEY_F3, KEY_F4, KEY_F5, KEY_F6]:
		_key(key)
		get_viewport().set_input_as_handled()


## Clicks that the panel did not take.
func _unhandled_input(event: InputEvent) -> void:
	if not editing:
		return
	var button := event as InputEventMouseButton
	if button == null:
		return
	if button.button_index == MOUSE_BUTTON_RIGHT:
		if button.pressed and _moving:
			_cancel_move()
		else:
			_look = button.pressed
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _look else Input.MOUSE_MODE_VISIBLE
	elif button.button_index == MOUSE_BUTTON_LEFT and button.pressed:
		_click(button.position)
	get_viewport().set_input_as_handled()


func _key(key: InputEventKey) -> void:
	var step := deg_to_rad(1.0 if key.shift_pressed else 15.0)
	match key.physical_keycode:
		KEY_S when key.ctrl_pressed:
			_save_edits()
		KEY_Z when key.ctrl_pressed:
			_undo_last()
		KEY_G:
			_start_move()
		KEY_E:
			_start_corner()
		KEY_Z:
			_turn(step)
		KEY_X:
			_turn(-step)
		KEY_DELETE, KEY_BACKSPACE:
			_remove()
		KEY_EQUAL, KEY_KP_ADD:
			_scale(1.1)
		KEY_MINUS, KEY_KP_SUBTRACT:
			_scale(1.0 / 1.1)
		KEY_TAB:
			_find_models() # models added to the folder since
			if _models.is_empty():
				_say("No models: put .glb / .fbx / .obj files in the props folder")
			else:
				_model = posmod(_model + (-1 if key.shift_pressed else 1), _models.size())
				_say("Model %d of %d: %s   (N to place it)" % [_model + 1, _models.size(), _models[_model].get_file()])
		KEY_N:
			_new_prop()
	_update_ui()


func _set_editing(on: bool) -> void:
	if on == editing or _world == null:
		return
	editing = on
	if on:
		if _map_buildings.is_empty():
			_read_map()
		_find_models()
		_was_paused = get_tree().paused
		get_tree().paused = true
		_previous_mouse = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_previous_camera = get_viewport().get_camera_3d()
		if _camera == null:
			_camera = Camera3D.new()
			_camera.far = 20000.0
			add_child(_camera)
		if _previous_camera:
			_camera.global_transform = _previous_camera.global_transform
		var e := _camera.global_transform.basis.get_euler()
		_pitch = e.x
		_yaw = e.y
		_camera.rotation = Vector3(_pitch, _yaw, 0.0)
		_camera.make_current()
		_make_ui()
		_ui.visible = true
		_set_game_hud(false)
	else:
		if _moving:
			_cancel_move()
		_select("", "")
		_look = false
		get_tree().paused = _was_paused
		Input.mouse_mode = _previous_mouse
		if _previous_camera and is_instance_valid(_previous_camera):
			_previous_camera.make_current()
		if _ui:
			_ui.visible = false
		_set_game_hud(true)
	_update_ui()


## The game's own HUD (speed, fuel, help...) is hidden while editing.
func _set_game_hud(on: bool) -> void:
	var hud := get_parent().get_node_or_null("HUD") as CanvasLayer
	if hud:
		hud.visible = on


func _process(delta: float) -> void:
	if not editing:
		return
	var dir := Vector3.ZERO
	if not Input.is_key_pressed(KEY_CTRL):
		if Input.is_physical_key_pressed(KEY_W):
			dir -= _camera.global_basis.z
		if Input.is_physical_key_pressed(KEY_S):
			dir += _camera.global_basis.z
		if Input.is_physical_key_pressed(KEY_A):
			dir -= _camera.global_basis.x
		if Input.is_physical_key_pressed(KEY_D):
			dir += _camera.global_basis.x
		if Input.is_physical_key_pressed(KEY_SPACE):
			dir += Vector3.UP
		if Input.is_physical_key_pressed(KEY_C):
			dir -= Vector3.UP
	# The arrow keys turn the view, as the right mouse button does.
	var turn := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_LEFT):
		turn.x += 1.0
	if Input.is_physical_key_pressed(KEY_RIGHT):
		turn.x -= 1.0
	if Input.is_physical_key_pressed(KEY_UP):
		turn.y += 1.0
	if Input.is_physical_key_pressed(KEY_DOWN):
		turn.y -= 1.0
	if turn != Vector2.ZERO:
		var rate := 1.6 * delta * (0.4 if Input.is_key_pressed(KEY_ALT) else 1.0)
		_yaw += turn.x * rate
		_pitch = clampf(_pitch + turn.y * rate, -1.5, 1.5)
		_camera.rotation = Vector3(_pitch, _yaw, 0.0)
	var speed := 120.0 if Input.is_key_pressed(KEY_SHIFT) else 30.0
	if dir != Vector3.ZERO:
		_camera.global_position += dir.normalized() * speed * delta
	if _moving:
		_follow_mouse()


## Reads the map's buildings and walls (where they are and how they look) from map.tscn.
func _read_map() -> void:
	if not ResourceLoader.exists(MAP_PATH):
		return
	var map: Node = (load(MAP_PATH) as PackedScene).instantiate()
	for node in map.find_children("*", "", true, false):
		var script: Script = node.get_script()
		if script == MAP_BUILDING:
			var poly: PackedVector2Array = node.world_footprint()
			if poly.size() < 3:
				continue
			var path := str(map.get_path_to(node))
			var id: int = node.osm_id if node.osm_id != 0 else -(_map_buildings.size() + 1)
			_map_buildings[path] = {"poly": _flat(poly), "height": node.height, "wall": node.wall_color.to_html(),
				"roof": node.roof_color.to_html(), "plain": node.plain, "tuff": node.tuff, "id": id}
			_index(_grid, path, poly)
		elif script == MAP_WALL:
			var pts: PackedVector2Array = node.world_points()
			if pts.size() < 2:
				continue
			var path := str(map.get_path_to(node))
			_map_walls[path] = {"pts": _flat(pts), "kind": int(node.kind), "color": node.color.to_html(),
				"height": node.height, "gate_at": node.gate_at, "gate_color": node.gate_color.to_html(),
				"swing": int(node.gate_swing)}
			_index(_wall_grid, path, pts)
	map.free()
	var props := _world.get_node_or_null("Props")
	if props:
		for p in props.get_children():
			_baked_props[str(p.get_meta("map_key", "Props/" + p.name))] = p


## Files a path under every 50 m cell its points' box touches.
func _index(grid: Dictionary, path: String, pts: PackedVector2Array) -> void:
	var box := _box(pts, 1.0)
	for cx in range(floori(box.position.x / 50.0), floori(box.end.x / 50.0) + 1):
		for cz in range(floori(box.position.y / 50.0), floori(box.end.y / 50.0) + 1):
			(grid.get_or_add(Vector2i(cx, cz), []) as Array).append(path)


func _find_models() -> void:
	_models.clear()
	_scan(PROPS_DIR)
	_model = clampi(_model, 0, maxi(_models.size() - 1, 0))


func _scan(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		f = f.trim_suffix(".remap").trim_suffix(".import")
		if f.get_extension().to_lower() in MODEL_EXTENSIONS and not _models.has(dir.path_join(f)):
			_models.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_scan(dir.path_join(d))


## What is under the mouse: {position, collider}, or empty.
func _ray(at: Vector2, skip: Array[RID] = []) -> Dictionary:
	var from := _camera.project_ray_origin(at)
	var query := PhysicsRayQueryParameters3D.create(from, from + _camera.project_ray_normal(at) * 3000.0)
	query.exclude = skip
	return get_world_3d().direct_space_state.intersect_ray(query)


func _click(at: Vector2) -> void:
	if _moving:
		_drop()
		return
	var hit := _ray(at)
	if hit.is_empty():
		_select("", "")
		return
	var body: Object = hit["collider"]
	if body is Node and (body as Node).has_meta("map_kind"):
		_select(str((body as Node).get_meta("map_kind")), str((body as Node).get_meta("map_key")))
		return
	# A baked prop: picking it starts an edit of it.
	for key: String in _baked_props:
		var baked: Node = _baked_props[key]
		if body == baked or baked.is_ancestor_of(body as Node):
			_select("prop", str(_edit_baked_prop(key, baked)))
			return
	var p: Vector3 = hit["position"]
	var found := _thing_at(Vector2(p.x, p.z))
	_select(found[0], found[1])


## The building or wall at a spot: [kind, path], or ["", ""]. Inside a building
## is that building; otherwise the nearest outline or wall within PICK_MARGIN.
func _thing_at(p: Vector2) -> Array:
	var cell := Vector2i(floori(p.x / 50.0), floori(p.y / 50.0))
	var best := ["", ""]
	var best_d := PICK_MARGIN
	for path: String in _grid.get(cell, []):
		if edits["buildings"].has(path):
			continue # edited ones are picked by their own body
		var poly := _points(_map_buildings[path])
		if Geometry2D.is_point_in_polygon(p, poly):
			return ["building", path]
		var d := _distance(p, poly, true)
		if d < best_d:
			best_d = d
			best = ["building", path]
	for path: String in _wall_grid.get(cell, []):
		if edits["walls"].has(path):
			continue
		var d := _distance(p, _points(_map_walls[path]), false)
		if d < best_d:
			best_d = d
			best = ["wall", path]
	return best


static func _distance(p: Vector2, pts: PackedVector2Array, closed: bool) -> float:
	var best := INF
	var n := pts.size() if closed else pts.size() - 1
	for k in n:
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, pts[k], pts[(k + 1) % pts.size()])))
	return best


func _select(kind: String, key: String) -> void:
	_pick_kind = kind
	_pick_key = key
	_draw_outline()
	_build_panel()
	_update_ui()


## The edit entry of what is picked, made (cutting the baked one out of the
## world) the first time it is changed.
func _picked_entry() -> Dictionary:
	if _pick_kind == "prop":
		return edits["props"][int(_pick_key)]
	var all: Dictionary = edits[_pick_kind + "s"]
	if not all.has(_pick_key):
		var src: Dictionary = (_map_buildings if _pick_kind == "building" else _map_walls)[_pick_key]
		var e := src.duplicate(true)
		e["removed"] = false
		e["offset"] = [0.0, 0.0]
		e["yaw"] = 0.0
		all[_pick_key] = e
		_refresh_baked()
	return all[_pick_key]


## What the picked thing looks like now (its edit, or as the map has it).
func _picked_look() -> Dictionary:
	if _pick_kind == "prop":
		return edits["props"][int(_pick_key)]
	var e: Dictionary = edits[_pick_kind + "s"].get(_pick_key, {})
	if not e.is_empty():
		return e
	return (_map_buildings if _pick_kind == "building" else _map_walls).get(_pick_key, {})


func _edit_baked_prop(key: String, baked: Node3D) -> int:
	var props: Array = edits["props"]
	for i in props.size():
		if props[i].get("key", "") == key:
			return i
	_remember()
	var xf := baked.global_transform
	props.append({"key": key, "scene": str(baked.get_meta("scene", "")), "pos": [xf.origin.x, xf.origin.y, xf.origin.z],
		"yaw": xf.basis.get_euler().y, "scale": xf.basis.get_scale().x, "removed": false})
	_show("prop", str(props.size() - 1))
	return props.size() - 1


## Keeps the edits as they are, for Ctrl+Z. Changes in a row to the same thing
## (dragging a slider) make one step.
func _remember(tag := "") -> void:
	var now := Time.get_ticks_msec()
	if tag != "" and tag == _undo_tag and now - _undo_time < 1500:
		_undo_time = now
		return
	_undo_tag = tag
	_undo_time = now
	_undo.append(JSON.stringify(edits))
	if _undo.size() > 60:
		_undo.pop_front()
	_unsaved = true


func _undo_last() -> void:
	if _undo.is_empty():
		_say("Nothing to undo")
		return
	var data: Dictionary = JSON.parse_string(_undo.pop_back())
	_undo_tag = ""
	for kind in ["buildings", "walls"]:
		if not data.has(kind):
			data[kind] = {}
	var old := edits
	edits = data
	_moving = false
	var pick_kind := _pick_kind
	var pick_key := _pick_key
	# Only what the undo changes is drawn again (and the chunks it touches baked again).
	_refresh_baked()
	for kind in ["building", "wall"]:
		var before: Dictionary = old[kind + "s"]
		var after: Dictionary = edits[kind + "s"]
		for path: String in before.keys() + after.keys():
			if JSON.stringify(before.get(path, {})) != JSON.stringify(after.get(path, {})):
				_show(kind, path)
	var old_props: Array = old["props"]
	var props: Array = edits["props"]
	for i in maxi(old_props.size(), props.size()):
		if i >= props.size():
			var gone: Node = _shown.get("prop:%d" % i)
			if gone:
				gone.queue_free()
				_shown.erase("prop:%d" % i)
			# A baked prop no longer edited shows again.
			var baked := _baked_prop(old_props[i].get("key", ""))
			if baked:
				baked.visible = true
				for cs: CollisionShape3D in baked.find_children("*", "CollisionShape3D", true, false):
					cs.disabled = false
		elif i >= old_props.size() or JSON.stringify(old_props[i]) != JSON.stringify(props[i]):
			_show("prop", str(i))
	if pick_kind == "prop" and int(pick_key) >= edits["props"].size():
		pick_kind = ""
	_select(pick_kind, pick_key)
	_say("Undone")


func _turn(angle: float) -> void:
	if _pick_kind == "":
		return
	_remember("turn")
	var e := _picked_entry()
	e["yaw"] = float(e["yaw"]) + angle
	if _moving:
		_drag_visual()
	else:
		_show(_pick_kind, _pick_key)
		_draw_outline()


func _scale(factor: float) -> void:
	if _pick_kind != "prop":
		return
	_remember("scale")
	var e := _picked_entry()
	e["scale"] = clampf(float(e["scale"]) * factor, 0.05, 50.0)
	if _moving:
		_drag_visual()
	else:
		_show("prop", _pick_key)
		_draw_outline()


func _remove() -> void:
	if _pick_kind == "":
		return
	_remember()
	_picked_entry()["removed"] = true
	_show(_pick_kind, _pick_key)
	_say({"building": "Building", "wall": "Wall", "prop": "Model"}[_pick_kind] + " removed")
	_moving = false
	_select("", "")


func _new_prop() -> void:
	if _models.is_empty():
		_say("No models: put some in %s" % PROPS_DIR)
		return
	_remember()
	var props: Array = edits["props"]
	props.append({"key": "", "scene": _models[_model], "pos": [0.0, 0.0, 0.0], "yaw": _camera.rotation.y + PI,
		"scale": 1.0, "removed": false})
	_select("prop", str(props.size() - 1))
	_moving = true
	_move_start = {}
	_drag_visual()
	_follow_mouse()


## The wall's corners made its own (any move and turn so far put into them), so
## they can be changed one by one; the map's are kept to cut the baked wall out.
func _own_corners(e: Dictionary) -> PackedVector2Array:
	if not e.has("orig"):
		e["orig"] = (e["pts"] as Array).duplicate()
	var pts := _moved(e)
	e["pts"] = _flat(pts)
	e["offset"] = [0.0, 0.0]
	e["yaw"] = 0.0
	return pts


## Starts dragging the picked wall's corner nearest the mouse.
func _start_corner() -> void:
	if _pick_kind != "wall":
		_say("Pick a wall first (E drags its corners)")
		return
	_remember()
	var e := _picked_entry()
	var pts := _own_corners(e)
	var hit := _ray(get_viewport().get_mouse_position(), _skip())
	var at := Vector2(hit["position"].x, hit["position"].z) if hit else _centre(pts)
	var nearest := 0
	for k in pts.size():
		if at.distance_to(pts[k]) < at.distance_to(pts[nearest]):
			nearest = k
	_move_start = {"corner": nearest}
	_drag_visual()
	_moving = true
	_say("Dragging corner %d of %d: click to drop" % [nearest + 1, pts.size()])


## Makes the picked wall `length` metres long, cutting it short or carrying its
## last run on further.
func _set_length(length: float) -> void:
	if _pick_kind != "wall":
		return
	_remember("length")
	var e := _picked_entry()
	var pts := _own_corners(e)
	var out := PackedVector2Array([pts[0]])
	var along := 0.0
	for k in range(1, pts.size()):
		var run := pts[k - 1].distance_to(pts[k])
		var last := k == pts.size() - 1
		if along + run >= length or last:
			var dir := (pts[k] - pts[k - 1]).normalized()
			out.append(pts[k - 1] + dir * maxf(length - along, 0.2))
			break
		out.append(pts[k])
		along += run
	e["pts"] = _flat(out)
	if float(e["gate_at"]) > length:
		e["gate_at"] = maxf(length * 0.5, 0.0)
	_show("wall", _pick_key)
	_draw_outline()


func _wall_length(pts: PackedVector2Array) -> float:
	var length := 0.0
	for k in pts.size() - 1:
		length += pts[k].distance_to(pts[k + 1])
	return length


func _start_move() -> void:
	if _pick_kind == "":
		return
	_remember()
	var hit := _ray(get_viewport().get_mouse_position(), _skip())
	_move_from = hit["position"] if hit else Vector3.ZERO
	var e := _picked_entry()
	if _pick_kind == "prop":
		_move_start = {"pos": (e["pos"] as Array).duplicate()}
	else:
		_move_start = {"offset": (e["offset"] as Array).duplicate()}
	_drag_visual()
	_moving = true


## The body of what is being moved, for the mouse ray to look past.
func _skip() -> Array[RID]:
	var skip: Array[RID] = []
	var node: Node = _shown.get(_pick_kind + ":" + _pick_key)
	if node is CollisionObject3D:
		skip.append((node as CollisionObject3D).get_rid())
	return skip


func _follow_mouse() -> void:
	var hit := _ray(get_viewport().get_mouse_position(), _skip())
	if hit.is_empty() or _pick_kind == "":
		return
	var p: Vector3 = hit["position"]
	var e := _picked_entry()
	if _move_start.has("corner"):
		var flat: Array = e["pts"]
		var k: int = _move_start["corner"]
		flat[k * 2] = snappedf(p.x, 0.01)
		flat[k * 2 + 1] = snappedf(p.z, 0.01)
	elif _pick_kind == "prop":
		if _move_start.has("pos"):
			var start: Array = _move_start["pos"]
			e["pos"] = [float(start[0]) + p.x - _move_from.x, p.y, float(start[2]) + p.z - _move_from.z]
		else:
			e["pos"] = [p.x, p.y, p.z] # a new one, on the spot under the mouse
	else:
		var start: Array = _move_start["offset"]
		e["offset"] = [snappedf(float(start[0]) + p.x - _move_from.x, 0.01), snappedf(float(start[1]) + p.z - _move_from.z, 0.01)]
	if _move_start.has("corner"):
		# The wall's shape changes: drawn again, but not more than ten times a second.
		if Time.get_ticks_msec() - _drag_redraw > 100:
			_drag_visual()
		return
	var node: Node3D = _shown.get(_pick_kind + ":" + _pick_key)
	var rel := _xf(e) * _xf(_drag_ref).affine_inverse()
	if node:
		node.transform = rel * _drag_node_xf
	if _outline:
		_outline.transform = rel


## Draws what is being moved (without collision) and its outline as the edit now
## is; _follow_mouse then shifts them from here.
func _drag_visual() -> void:
	_show(_pick_kind, _pick_key, false)
	_draw_outline()
	_drag_ref = _picked_entry().duplicate(true)
	_drag_redraw = Time.get_ticks_msec()
	var node: Node3D = _shown.get(_pick_kind + ":" + _pick_key)
	_drag_node_xf = node.transform if node else Transform3D.IDENTITY


## The edit's place as a transform: for a prop where it stands; for a building or
## wall, from where the map has it to where the edit puts it (kept on the ground).
func _xf(e: Dictionary) -> Transform3D:
	if e.is_empty():
		return Transform3D.IDENTITY
	if _pick_kind == "prop":
		var pos: Array = e["pos"]
		return Transform3D(Basis(Vector3.UP, float(e["yaw"])).scaled(Vector3.ONE * float(e["scale"])), Vector3(pos[0], pos[1], pos[2]))
	var c := _centre(_points(e))
	var off: Array = e.get("offset", [0.0, 0.0])
	var to := c + Vector2(float(off[0]), float(off[1]))
	var dy := MapKit.height_at(to.x, to.y) - MapKit.height_at(c.x, c.y)
	return Transform3D(Basis(Vector3.UP, float(e.get("yaw", 0.0))), Vector3(to.x, dy, to.y)) * Transform3D(Basis.IDENTITY, Vector3(-c.x, 0.0, -c.y))


func _drop() -> void:
	_moving = false
	_show(_pick_kind, _pick_key)
	_draw_outline()
	if _move_start.has("corner"):
		_build_panel() # the length shown there
	_move_start = {}
	_update_ui()


func _cancel_move() -> void:
	_moving = false
	_undo_last()


## A see-through yellow box, with yellow edges, round what is picked.
func _draw_outline() -> void:
	if _outline == null:
		_outline = MeshInstance3D.new()
		_outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_outline)
	_outline.transform = Transform3D.IDENTITY
	var lines := ImmediateMesh.new()
	_outline.mesh = lines
	var loops: Array[PackedVector2Array] = []
	var closed := true
	var low := 0.0
	var high := 0.0
	if _pick_kind == "building" or _pick_kind == "wall":
		var look := _picked_look()
		if look.is_empty():
			return
		var pts := _moved(look) if look.has("offset") else _points(look)
		low = INF
		for p in pts:
			low = minf(low, MapKit.height_at(p.x, p.y))
		if _pick_kind == "building":
			loops.append(pts)
			high = low + float(look["height"]) + 0.8
		else:
			# A thin box along each run of the wall.
			closed = false
			for k in pts.size() - 1:
				var d := (pts[k + 1] - pts[k]).normalized()
				var n := Vector2(d.y, -d.x) * 0.35
				loops.append(PackedVector2Array([pts[k] + n - d * 0.3, pts[k + 1] + n + d * 0.3, pts[k + 1] - n + d * 0.3, pts[k] - n - d * 0.3]))
			high = low + float(look["height"]) + 0.6
		low -= 0.5
	elif _pick_kind == "prop":
		var node: Node3D = _shown.get("prop:" + _pick_key)
		if node == null:
			return
		var box := AABB()
		var first := true
		for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
			var b := mi.global_transform * mi.get_aabb()
			box = b if first else box.merge(b)
			first = false
		box = box.grow(0.15)
		loops.append(PackedVector2Array([Vector2(box.position.x, box.position.z), Vector2(box.end.x, box.position.z),
			Vector2(box.end.x, box.end.z), Vector2(box.position.x, box.end.z)]))
		low = box.position.y
		high = box.end.y
	if loops.is_empty():
		return
	var yellow := Color(1.0, 0.82, 0.1)
	lines.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _outline_material(Color(yellow, 0.22), true))
	for poly in loops:
		for k in poly.size():
			var a := poly[k]
			var b := poly[(k + 1) % poly.size()]
			for v in [Vector3(a.x, low, a.y), Vector3(b.x, low, b.y), Vector3(b.x, high, b.y),
					Vector3(a.x, low, a.y), Vector3(b.x, high, b.y), Vector3(a.x, high, a.y)]:
				lines.surface_add_vertex(v)
	lines.surface_end()
	lines.surface_begin(Mesh.PRIMITIVE_LINES, _outline_material(yellow, false))
	for poly in loops:
		for y in [low, high]:
			for k in poly.size():
				var a := poly[k]
				var b := poly[(k + 1) % poly.size()]
				lines.surface_add_vertex(Vector3(a.x, y, a.y))
				lines.surface_add_vertex(Vector3(b.x, y, b.y))
		for p in poly:
			lines.surface_add_vertex(Vector3(p.x, low, p.y))
			lines.surface_add_vertex(Vector3(p.x, high, p.y))
	lines.surface_end()


var _outline_mats := {}


func _outline_material(color: Color, faces: bool) -> StandardMaterial3D:
	if not _outline_mats.has(faces):
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if faces else BaseMaterial3D.TRANSPARENCY_DISABLED
		mat.no_depth_test = not faces
		mat.albedo_color = color
		_outline_mats[faces] = mat
	return _outline_mats[faces]


# --- the panel: how the picked thing looks -------------------------------------

## Sets a property of the picked building or wall from the panel and redraws it.
func _set_look(field: String, value: Variant) -> void:
	if _pick_kind != "building" and _pick_kind != "wall":
		return
	_remember(field)
	var e := _picked_entry()
	e[field] = value
	_show(_pick_kind, _pick_key)
	_draw_outline()
	_update_ui()


func _build_panel() -> void:
	if _panel == null:
		return
	var box: VBoxContainer = _panel.get_child(0)
	for child in box.get_children():
		child.queue_free()
	_panel.visible = _pick_kind == "building" or _pick_kind == "wall"
	if not _panel.visible:
		return
	var look := _picked_look()
	if _pick_kind == "building":
		_heading(box, "BUILDING")
		_slider(box, "Height (m)", float(look["height"]), 2.0, 40.0, 0.1, func(v: float) -> void: _set_look("height", v))
		_color(box, "Walls", Color.html(look["wall"]), func(c: Color) -> void: _set_look("wall", c.to_html(false)))
		_color(box, "Roof", Color.html(look["roof"]), func(c: Color) -> void: _set_look("roof", c.to_html(false)))
		_check(box, "Tuff stone walls", bool(look["tuff"]), func(on: bool) -> void: _set_look("tuff", on))
		_check(box, "No windows (shed, garage)", bool(look["plain"]), func(on: bool) -> void: _set_look("plain", on))
	else:
		var pts := _points(look)
		var length := 0.0
		for k in pts.size() - 1:
			length += pts[k].distance_to(pts[k + 1])
		_heading(box, "WALL  (%.0f m)" % length)
		_choice(box, "Kind", KIND_NAMES, int(look["kind"]), func(i: int) -> void: _set_look("kind", i))
		_color(box, "Colour", Color.html(look["color"]), func(c: Color) -> void: _set_look("color", c.to_html(false)))
		_slider(box, "Height (m)", float(look["height"]), 0.5, 5.0, 0.05, func(v: float) -> void: _set_look("height", v))
		_slider(box, "Length (m)", length, 1.0, maxf(length * 2.0, length + 30.0), 0.1, func(v: float) -> void: _set_length(v))
		var tip := Label.new()
		tip.text = "E: drag a corner or end with the mouse"
		tip.add_theme_font_size_override("font_size", 12)
		box.add_child(tip)
		_heading(box, "GATE")
		var has_gate := float(look["gate_at"]) >= 0.0
		_check(box, "Has a gate", has_gate, func(on: bool) -> void:
			_set_look("gate_at", length * 0.5 if on else -1.0)
			_build_panel())
		if has_gate:
			_slider(box, "Where (m along)", float(look["gate_at"]), 0.0, maxf(length, 0.1), 0.1,
				func(v: float) -> void: _set_look("gate_at", v))
			_color(box, "Gate colour", Color.html(look["gate_color"]), func(c: Color) -> void: _set_look("gate_color", c.to_html(false)))
			_choice(box, "Gate", SWING_NAMES, int(look.get("swing", 0)), func(i: int) -> void: _set_look("swing", i))
			var note := Label.new()
			note.text = "(swinging leaves are made when the map is baked)"
			note.add_theme_font_size_override("font_size", 12)
			box.add_child(note)


func _heading(box: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	box.add_child(label)


func _row(box: VBoxContainer, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = 130
	row.add_child(label)
	box.add_child(row)
	return row


func _slider(box: VBoxContainer, text: String, value: float, lo: float, hi: float, step: float, on_change: Callable) -> void:
	var row := _row(box, text)
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.value = value
	slider.custom_minimum_size.x = 150
	slider.focus_mode = Control.FOCUS_NONE
	var shown := Label.new()
	shown.text = "%.1f" % value
	shown.custom_minimum_size.x = 44
	slider.value_changed.connect(func(v: float) -> void:
		shown.text = "%.1f" % v
		on_change.call(v))
	row.add_child(slider)
	row.add_child(shown)


func _color(box: VBoxContainer, text: String, value: Color, on_change: Callable) -> void:
	var row := _row(box, text)
	var button := ColorPickerButton.new()
	button.color = value
	button.edit_alpha = false
	button.custom_minimum_size = Vector2(150, 26)
	button.focus_mode = Control.FOCUS_NONE
	button.color_changed.connect(on_change)
	row.add_child(button)


func _check(box: VBoxContainer, text: String, value: bool, on_change: Callable) -> void:
	var check := CheckBox.new()
	check.text = text
	check.button_pressed = value
	check.focus_mode = Control.FOCUS_NONE
	check.toggled.connect(on_change)
	box.add_child(check)


func _choice(box: VBoxContainer, text: String, names: Array, value: int, on_change: Callable) -> void:
	var row := _row(box, text)
	var option := OptionButton.new()
	for n: String in names:
		option.add_item(n)
	option.selected = clampi(value, 0, names.size() - 1)
	option.focus_mode = Control.FOCUS_NONE
	option.custom_minimum_size.x = 150
	option.item_selected.connect(on_change)
	row.add_child(option)


# --- what is shown on screen ------------------------------------------------

func _make_ui() -> void:
	if _ui:
		return
	_ui = CanvasLayer.new()
	_ui.layer = 50
	add_child(_ui)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.07, 0.12, 0.82)
	style.set_content_margin_all(12)
	style.set_corner_radius_all(6)
	var info := PanelContainer.new()
	info.position = Vector2(16, 16)
	info.add_theme_stylebox_override("panel", style)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(info)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(box)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 20)
	_status.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	box.add_child(_status)
	var help := Label.new()
	help.add_theme_font_size_override("font_size", 15)
	help.text = "\n".join([
		"MAP EDITOR   (F2 / Esc: back to the game)",
		"WASD, Space/C: fly (Shift: fast)   Arrows or right mouse: look",
		"Click: pick a building, wall or model   G: move it (click to drop, right click: cancel)",
		"E: drag a wall's corner or end (click to drop)",
		"Z / X: turn (Shift: 1 degree)   Delete: remove   + / -: model size",
		"Tab: choose model   N: place it   Ctrl+Z: undo   Ctrl+S: save   F3: copy the spot under the mouse",
	])
	box.add_child(help)
	# How the picked building or wall looks, on the right.
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", style)
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.offset_left = -360
	_panel.offset_right = -16
	_panel.offset_top = 16
	_panel.visible = false
	_ui.add_child(_panel)
	var props := VBoxContainer.new()
	props.add_theme_constant_override("separation", 8)
	_panel.add_child(props)


var _message := ""
var _message_time := 0


func _say(text: String) -> void:
	_message = text
	_message_time = Time.get_ticks_msec()
	_update_ui()


func _update_ui() -> void:
	if _status == null:
		return
	var parts := PackedStringArray()
	var moving := " (moving)" if _moving else ""
	match _pick_kind:
		"building":
			parts.append("Building " + _pick_key.get_file() + moving)
		"wall":
			parts.append("Wall " + _pick_key.get_file() + moving)
		"prop":
			parts.append("Model " + str(edits["props"][int(_pick_key)]["scene"]).get_file() + moving)
		_:
			parts.append("Nothing picked")
	parts.append("Model to place: " + (_models[_model].get_file() if not _models.is_empty() else "none in " + PROPS_DIR))
	parts.append("%d buildings, %d walls changed, %d models" % [edits["buildings"].size(), edits["walls"].size(),
		edits["props"].size()] + ("   * not saved" if _unsaved else ""))
	if _message != "" and Time.get_ticks_msec() - _message_time < 4000:
		parts.append(_message)
	_status.text = "\n".join(parts)
