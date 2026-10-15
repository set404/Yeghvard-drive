extends SceneTree
## Turns glTF car models into drivable car scenes (VehicleBody3D + car.gd).
##
## Every model needs its nose towards +Z and a tyre material the wheels can be
## found by. The rest differs from model to model and is described in MODELS.
##
## Run:  godot --path . --script res://tools/build_car.gd            (all cars)
##       godot --path . --script res://tools/build_car.gd -- e55_amg (one car)

const MODELS := {
	"e50_amg": {
		"source": "res://data/models/1996_mercedes-benz_e50_amg_w210.glb",
		# Materials whose name contains one of these are left out (hidden under the bonnet).
		"skip": ["Engine"],
		# The bodywork paint and tyre materials, as named in the model.
		"paint": "1241010001",
		"tyre": "Tyre",
		# Each wheel is a node of its own; everything under it turns with the wheel.
		"wheels_are_nodes": true,
		"lamps": "w210",
		"idle_glow": 0.3,
		"interior": true,
		"mass": 1680.0, "horsepower": 347.0, "max_drive_force": 9500.0, "drag": 0.62, "fuel_capacity": 80.0,
		# Engine note: recordings held at steady revs, [name in audio/layers, rpm] (see
		# tools/build_sounds.gd). A Mercedes AMG V8 idling, and made from it the way an
		# engine revs (tools/engine_layers/pulses.js); higher up, the E55's.
		"engine_layers": [["e50_0890", 890.0], ["e50_1300", 1300.0], ["e50_1800", 1800.0],
			["e55_2600", 2600.0], ["e55_3300", 3300.0], ["e55_4200", 4200.0], ["e55_5300", 5300.0]],
	},
	"e55_amg": {
		"source": "res://data/models/2003_mercedes-benz_e55_amg_w211.glb",
		"skip": ["engine_Mat"],
		"paint": "CarPaint",
		"tyre": "Tire",
		# The model is not to scale and is centred on its middle rather than standing on the ground.
		"length": 4.82,
		"stand_on_ground": true,
		"wheels_are_nodes": false,
		"lamps": "w211",
		"idle_glow": 0.0,
		"glow_scale": 0.9,
		"interior": false,
		"mass": 1835.0, "horsepower": 476.0, "max_drive_force": 11000.0, "drag": 0.62, "fuel_capacity": 80.0,
		# A big-block V8 idling, and made from it the way an engine revs
		# (tools/engine_layers/pulses.js).
		"engine_layers": [["e55_1120", 1120.0], ["e55_1500", 1500.0], ["e55_2000", 2000.0],
			["e55_2600", 2600.0], ["e55_3300", 3300.0], ["e55_4200", 4200.0], ["e55_5300", 5300.0]],
	},
	"volga_3102": {
		"source": "res://data/models/volga_gaz_3102/scene.gltf",
		"skip": [],
		"paint": "Car_Paint",
		"tyre": "Rubber",
		"length": 4.96,
		"stand_on_ground": true,
		# Each wheel part is one mesh for both sides of the car, and the wheels alone
		# are 600,000 triangles, so they are cut in two and thinned to a fraction.
		"wheels_are_nodes": false,
		"wheels_on_axles": true,
		"wheel_detail": 0.08,
		"lamps": "gaz3102",
		"idle_glow": 0.0,
		"glow_scale": 0.9,
		"interior": false,
		"mass": 1470.0, "horsepower": 105.0, "max_drive_force": 5200.0, "drag": 0.75, "fuel_capacity": 55.0,
		"driver_view": Vector3(0.36, 1.0, -0.12),
		# A four pulling hard (an old Mazda's), over a modern four's idle.
		"engine_layers": [["compass_0810", 810.0], ["volga_1700", 1700.0], ["volga_2100", 2100.0],
			["volga_2500", 2500.0], ["volga_2900", 2900.0], ["volga_3300", 3300.0],
			# Above the recording, made from its top the way an engine revs.
			["volga_4000", 4000.0], ["volga_4800", 4800.0], ["volga_5600", 5600.0]],
		# An old, slow-turning starter.
		"starter_pitch": 0.85,
		# The model was made for another kind of renderer; on import its window glass
		# came out solid black and its chrome and gold lost their metal.
		"material_fixes": {
			"Glass_Window": {"transparency": BaseMaterial3D.TRANSPARENCY_ALPHA, "albedo_color": Color(0.04, 0.06, 0.07, 0.28), "roughness": 0.05},
			"Glass_Window2": {"albedo_color": Color(0.04, 0.06, 0.07, 0.2), "roughness": 0.05},
			# The red tail-lamp lens is nearly clear in the model, which shows the bright
			# reflectors behind it; a real one is a deep, mostly solid red.
			"Glass_Window3.1": {"albedo_color": Color(0.5, 0.02, 0.03, 0.88), "roughness": 0.2},
			"Chrome": {"albedo_color": Color(0.82, 0.83, 0.86), "metallic": 1.0, "roughness": 0.14},
			"Mirror": {"albedo_color": Color(0.85, 0.87, 0.9), "metallic": 1.0, "roughness": 0.03},
			"Gold": {"albedo_color": Color(0.83, 0.62, 0.24), "metallic": 1.0, "roughness": 0.25},
			"Car_Paint_-_Black_Solid": {"metallic": 0.35, "roughness": 0.22},
		},
	},
	"land_cruiser_80": {
		"source": "res://data/models/land_cruiser_80/land-cruiser.glb",
		# This model is a kit put together in Blender: no colours, and the driver's controls loose. See _assemble_lc80.
		"kit": "lc80",
		"skip": [],
		"paint": "paint",
		"tyre": "tire",
		"wheels_are_nodes": false,
		"lamps": "lc80",
		"idle_glow": 0.0,
		"glow_scale": 0.9,
		"interior": true,
		"gauges_shader": "res://car/gauges_lc80.gdshader",
		"mass": 2260.0, "horsepower": 212.0, "max_drive_force": 9000.0, "drag": 0.95, "fuel_capacity": 95.0,
		"driver_view": Vector3(0.38, 1.42, -0.1),
		# A straight six (an E-type Jaguar's).
		"engine_layers": [["landcruiser_1400", 1400.0], ["landcruiser_1520", 1520.0],
			["landcruiser_1900", 1900.0], ["landcruiser_2300", 2300.0],
			["landcruiser_2900", 2900.0], ["landcruiser_3600", 3600.0], ["landcruiser_4500", 4500.0]],
	},
	"jeep_compass": {
		"source": "res://data/models/jeep_compass_2022/jeep_compass_2022_lowpoly.glb",
		"skip": [],
		# The teal bodywork; the roof is black with a panoramic glass roof in it.
		# Other materials share the start of its name, so only the exact name is the paint.
		"paint": "Jeep_Compass_mat_13_1",
		"paint_exact": true,
		"tyre": "Teana",
		# Each tyre and rim mesh holds both wheels of one side of the car.
		"wheels_are_nodes": false,
		"wheels_in_tyres": true,
		"lamps": "none",
		"idle_glow": 0.0,
		"interior": false,
		"mass": 1600.0, "horsepower": 177.0, "max_drive_force": 6500.0, "drag": 0.8, "fuel_capacity": 60.0,
		# It sits higher than the saloons; their eye point looks into the steering wheel.
		"driver_view": Vector3(0.37, 1.33, -0.3),
		# A modern turbocharged four (an Audi 2.0 TFSI's).
		"engine_layers": [["compass_0810", 810.0], ["compass_1900", 1900.0], ["compass_2200", 2200.0],
			["compass_2500", 2500.0], ["compass_2750", 2750.0],
			["compass_3400", 3400.0], ["compass_4200", 4200.0], ["compass_5200", 5200.0]],
	},
}

const REST_LENGTH := 0.2
const STIFFNESS := 45.0
## How far the springs settle under the car's own weight (four wheels sharing it).
const SAG := 9.8 / (4.0 * STIFFNESS)


func _initialize() -> void:
	_build_all.call_deferred()


func _build_all() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Run without --headless so the textures are kept.")
		quit(1)
		return
	var wanted := OS.get_cmdline_user_args()
	var failed := false
	if wanted.is_empty() or "land_cruiser_80" in wanted:
		_lc80_dial = await _lc80_paint_dial()
	for car_name: String in MODELS:
		if wanted.is_empty() or car_name in wanted:
			if not _build(car_name, MODELS[car_name]):
				failed = true
	quit(1 if failed else 0)


func _build(car_name: String, cfg: Dictionary) -> bool:
	var out_path := "res://car/%s.scn" % car_name
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(ProjectSettings.globalize_path(cfg["source"]), state)
	if err != OK:
		push_error("Cannot read %s: %s" % [cfg["source"], error_string(err)])
		return false
	var model: Node3D = doc.generate_scene(state)
	root.add_child(model)
	if cfg.get("kit", "") == "lc80":
		_assemble_lc80(model)

	var meshes: Array[MeshInstance3D] = []
	for node in model.find_children("*", "MeshInstance3D", true, false):
		meshes.append(node)
	# Repairs to materials, by exact name.
	var fixes: Dictionary = cfg.get("material_fixes", {})
	var fixed := {}
	for mi in meshes:
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s)
			if mat and fixes.has(mat.resource_name) and not fixed.has(mat):
				fixed[mat] = true
				for property: String in fixes[mat.resource_name]:
					mat.set(property, fixes[mat.resource_name][property])
	var whole := _bounds(meshes)
	if cfg.has("length"):
		model.scale = Vector3.ONE * (cfg["length"] / whole.size.z)
	elif whole.size.z < 0.5:
		# Exports are often off by the centimetre/metre factor; a car is 3 to 6 m long.
		model.scale = Vector3.ONE * 100.0
	elif whole.size.z > 50.0:
		model.scale = Vector3.ONE * 0.01
	if cfg.get("stand_on_ground", false):
		model.position.y = -_bounds(meshes).position.y

	# Wheels: found by their tyres. The tyre's middle is the axle.
	var wheels: Array[Dictionary] = []
	var in_wheel := {} # MeshInstance3D -> true
	var body_parts := {}
	if cfg.get("wheels_on_axles", false):
		wheels = _axle_wheels(meshes, cfg, in_wheel)
	elif cfg.get("wheels_in_tyres", false):
		wheels = _tyre_wheels(meshes, cfg, in_wheel, body_parts)
	for mi in meshes:
		var tyre := _box(mi)
		if cfg.get("wheels_on_axles", false) or cfg.get("wheels_in_tyres", false) or not _material_name(mi, 0).contains(cfg["tyre"]) or tyre.size.y < 0.4:
			continue
		var members: Array[MeshInstance3D] = []
		for other in meshes:
			var turns: bool
			if cfg["wheels_are_nodes"]:
				turns = other.get_parent() == mi.get_parent()
			else:
				# Loose parts turn with the wheel if they sit on its axle; a brake
				# caliper sits off to one side and stays with the body.
				var c := _box(other).get_center()
				var off_axle := Vector2(c.y - tyre.get_center().y, c.z - tyre.get_center().z).length()
				turns = tyre.grow(0.03).has_point(c) and off_axle < tyre.size.y * 0.06
			if turns:
				members.append(other)
				in_wheel[other] = true
		wheels.append({"at": tyre.get_center(), "tyre": tyre, "members": members})
	if wheels.size() != 4:
		push_error("%s: expected 4 wheels, found %d" % [car_name, wheels.size()])
		model.free()
		return false

	var car := VehicleBody3D.new()
	car.name = "Car"
	car.mass = cfg["mass"]
	car.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	car.set_script(load("res://car/car.gd"))
	car.set("horsepower", cfg["horsepower"])
	car.set("max_drive_force", cfg["max_drive_force"])
	car.set("drag", cfg["drag"])
	# Built with a full tank; main.tscn says how much each car starts with.
	car.set("fuel_capacity", cfg["fuel_capacity"])
	car.set("fuel", cfg["fuel_capacity"])
	if cfg.has("driver_view"):
		car.set("driver_view", cfg["driver_view"])
	# The engine note and starter (tools/build_sounds.gd); the rest share the default ones.
	if cfg.has("engine_sound"):
		car.set("engine_sound", cfg["engine_sound"])
	if cfg.has("engine_sound_rpm"):
		car.set("engine_sound_rpm", cfg["engine_sound_rpm"])
	if cfg.has("engine_layers"):
		var streams: Array[AudioStream] = []
		var rpms := PackedFloat32Array()
		for layer: Array in cfg["engine_layers"]:
			streams.append(load("res://audio/layers/%s.res" % layer[0]))
			rpms.append(layer[1])
		car.set("engine_layers", streams)
		car.set("engine_layer_rpms", rpms)
	if cfg.has("starter_pitch"):
		car.set("starter_pitch", cfg["starter_pitch"])

	# Body: everything that is not a wheel, merged into one mesh per material.
	var lamp_zones := {} # zone name -> [SurfaceTool, source material]
	var lamp_rest := {} # lamp housing that never lights up
	var gauge_parts := {} # instrument cluster faces
	var wheel_surfaces := [] # steering wheel: [MeshInstance3D, surface]
	var box := AABB()
	var tris := 0
	for mi in meshes:
		if in_wheel.has(mi):
			continue
		for s in mi.mesh.get_surface_count():
			var mat_name := _material_name(mi, s)
			if _skipped(mat_name, cfg["skip"]):
				continue
			if cfg["interior"] and mat_name.contains("Dashboard"):
				_append(gauge_parts, mi, s, mi.global_transform)
			elif cfg["interior"] and _is_steering_wheel(mi):
				wheel_surfaces.append([mi, s])
			elif _is_lamp_surface(mi, mat_name, cfg["lamps"]):
				_split_lamps(mi, s, cfg["lamps"], lamp_zones, lamp_rest)
			else:
				_append(body_parts, mi, s, mi.global_transform)
			var part := _box(mi)
			box = part if box.size == Vector3.ZERO else box.merge(part)
	if box.size == Vector3.ZERO:
		# The body was cut out of the same meshes as the wheels.
		box = _bounds(meshes)
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = _commit(body_parts)
	_commit(lamp_rest, body.mesh)
	# Name the bodywork paint so car.gd can recolour it.
	for s in body.mesh.get_surface_count():
		var paint := body.mesh.surface_get_material(s)
		if paint.resource_name == cfg["paint"] or (not cfg.get("paint_exact", false) and paint.resource_name.contains(cfg["paint"])):
			paint.resource_name = "Paint"
	car.add_child(body)
	tris += _count_tris(body.mesh)
	_add_lamps(car, lamp_zones, cfg)
	if cfg["interior"]:
		_add_interior(car, gauge_parts, wheel_surfaces, cfg.get("gauges_shader", "res://car/gauges.gdshader"))

	var front_z := -INF
	var rear_z := INF
	var half_track := 0.0
	for w in wheels:
		var at: Vector3 = w["at"]
		var tyre: AABB = w["tyre"]
		var parts: Dictionary = w.get("parts", {})
		for mi: MeshInstance3D in w.get("members", []):
			for s in mi.mesh.get_surface_count():
				_append(parts, mi, s, Transform3D(Basis.IDENTITY, -at) * mi.global_transform)
		var wheel := VehicleWheel3D.new()
		wheel.name = "Wheel%s%s" % ["F" if at.z > 0.0 else "R", "L" if at.x > 0.0 else "R"]
		# The node is the top of the suspension; the wheel hangs below it.
		wheel.position = Vector3(at.x, at.y + REST_LENGTH - SAG, at.z)
		wheel.use_as_steering = at.z > 0.0
		wheel.use_as_traction = at.z < 0.0
		# Never larger than the axle height, or the car would sit too high.
		wheel.wheel_radius = minf(tyre.size.y * 0.5, at.y)
		wheel.wheel_rest_length = REST_LENGTH
		wheel.wheel_friction_slip = 2.2
		wheel.wheel_roll_influence = 0.15
		wheel.suspension_travel = 0.25
		wheel.suspension_stiffness = STIFFNESS
		var visual := MeshInstance3D.new()
		visual.name = "Mesh"
		visual.mesh = _commit(parts)
		wheel.add_child(visual)
		car.add_child(wheel)
		tris += _count_tris(visual.mesh)
		half_track = maxf(half_track, tyre.end.x)
		front_z = maxf(front_z, at.z)
		rear_z = minf(rear_z, at.z)

	# Low centre of mass keeps an arcade car on its wheels.
	car.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	car.center_of_mass = Vector3(0.0, 0.2, (front_z + rear_z) * 0.5)

	# Collision: one box for the body shell and one for the cabin.
	var floor_y := 0.22
	var waist_y := box.position.y + box.size.y * 0.62
	_add_box(car, "BodyShape",
		Vector3(half_track * 2.0, waist_y - floor_y, box.size.z - 0.1),
		Vector3(0.0, (waist_y + floor_y) * 0.5, box.get_center().z))
	_add_box(car, "CabinShape",
		Vector3(half_track * 1.7, box.end.y - waist_y, box.size.z * 0.45),
		Vector3(0.0, (box.end.y + waist_y) * 0.5, box.get_center().z - box.size.z * 0.06))

	for node in car.find_children("*", "", true, false):
		node.owner = car
	var scene := PackedScene.new()
	err = scene.pack(car)
	if err == OK:
		err = ResourceSaver.save(scene, out_path, ResourceSaver.FLAG_COMPRESS)
	if err != OK:
		push_error("Saving %s failed: %s" % [out_path, error_string(err)])
	else:
		print("Saved %s: %.2f x %.2f x %.2f m, wheelbase %.2f m, wheel radius %.2f m, %d triangles, %d body materials" % [
			out_path, box.size.x, box.size.y, box.size.z, front_z - rear_z,
			minf(wheels[0]["tyre"].size.y * 0.5, wheels[0]["at"].y), tris, body_parts.size()])
	car.free()
	model.free()
	return err == OK


## Wheels of a model where each part of a wheel is one mesh for the whole axle,
## left and right together. Finds the axles by their tyres, thins the meshes out
## (such models tend to be far too detailed) and cuts every part down the middle.
func _axle_wheels(meshes: Array[MeshInstance3D], cfg: Dictionary, in_wheel: Dictionary) -> Array[Dictionary]:
	var axles: Array[AABB] = []
	for mi in meshes:
		var tyre := _box(mi)
		if not _material_name(mi, 0).contains(cfg["tyre"]) or tyre.size.y < 0.4:
			continue
		var known := false
		for k in axles.size():
			if absf(axles[k].get_center().z - tyre.get_center().z) < 0.5:
				axles[k] = axles[k].merge(tyre)
				known = true
		if not known:
			axles.append(tyre)

	var wheels: Array[Dictionary] = []
	for axle in axles:
		var centre := axle.get_center()
		# One record per side: where the tyre is, and the wheel's pieces by material.
		var sides := {1.0: {"tyre": AABB(), "seen": false, "parts": {}}, -1.0: {"tyre": AABB(), "seen": false, "parts": {}}}
		var pieces := []
		for mi in meshes:
			var c := _box(mi).get_center()
			var off_axle := Vector2(c.y - centre.y, c.z - centre.z).length()
			if not axle.grow(0.03).has_point(Vector3(centre.x, c.y, c.z)) or off_axle > axle.size.y * 0.06:
				continue
			in_wheel[mi] = true
			var thinned := _thinned(mi, cfg.get("wheel_detail", 1.0))
			pieces.append([mi, thinned])
			if _material_name(mi, 0).contains(cfg["tyre"]):
				for p: Vector3 in thinned[Mesh.ARRAY_VERTEX]:
					var g := mi.global_transform * p
					var side: Dictionary = sides[1.0 if g.x > 0.0 else -1.0]
					side["tyre"] = side["tyre"].expand(g) if side["seen"] else AABB(g, Vector3.ZERO)
					side["seen"] = true
		for piece: Array in pieces:
			var mi: MeshInstance3D = piece[0]
			var a: Array = piece[1]
			var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
			var uvs := PackedVector2Array()
			if a[Mesh.ARRAY_TEX_UV] != null:
				uvs = a[Mesh.ARRAY_TEX_UV]
			var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
			var xf := mi.global_transform
			var turn := xf.basis.orthonormalized()
			var mat := mi.get_active_material(0)
			for t in range(0, idx.size(), 3):
				var mid := xf * ((verts[idx[t]] + verts[idx[t + 1]] + verts[idx[t + 2]]) / 3.0)
				var side: Dictionary = sides[1.0 if mid.x > 0.0 else -1.0]
				var parts: Dictionary = side["parts"]
				if not parts.has(mat):
					parts[mat] = SurfaceTool.new()
					parts[mat].begin(Mesh.PRIMITIVE_TRIANGLES)
				var st: SurfaceTool = parts[mat]
				var at: Vector3 = side["tyre"].get_center()
				for k in 3:
					var i := idx[t + k]
					st.set_normal(turn * normals[i])
					if not uvs.is_empty():
						st.set_uv(uvs[i])
					st.add_vertex(xf * verts[i] - at)
		for sign: float in sides:
			var side: Dictionary = sides[sign]
			for mat: Material in side["parts"]:
				side["parts"][mat].index()
			wheels.append({"at": side["tyre"].get_center(), "tyre": side["tyre"], "parts": side["parts"]})
	return wheels


## Wheels of a model whose tyres and rims are one mesh for several wheels (a side
## of the car, or all of it). The tyres say where the four wheels are; every
## triangle of the model inside a tyre's outline turns with that wheel, and the
## rest goes to the body (`body_parts`, by material).
func _tyre_wheels(meshes: Array[MeshInstance3D], cfg: Dictionary, in_wheel: Dictionary,
		body_parts: Dictionary) -> Array[Dictionary]:
	var tyre_points := PackedVector3Array()
	for mi in meshes:
		if _material_name(mi, 0).contains(cfg["tyre"]):
			for p: Vector3 in mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
				tyre_points.append(mi.global_transform * p)
	var mid_z := 0.0
	for p in tyre_points:
		mid_z += p.z / tyre_points.size()
	# One tyre per side and end of the car.
	var tyres := {}
	for p in tyre_points:
		var key := Vector2i(1 if p.x > 0.0 else -1, 1 if p.z > mid_z else -1)
		tyres[key] = (tyres[key] as AABB).expand(p) if tyres.has(key) else AABB(p, Vector3.ZERO)
	var wheels: Array[Dictionary] = []
	for key: Vector2i in tyres:
		wheels.append({"at": (tyres[key] as AABB).get_center(), "tyre": tyres[key], "parts": {}})

	for mi in meshes:
		in_wheel[mi] = true
		var xf := mi.global_transform
		var turn := xf.basis.orthonormalized()
		for s in mi.mesh.get_surface_count():
			if _skipped(_material_name(mi, s), cfg["skip"]):
				continue
			var mat := mi.get_active_material(s)
			var a: Array = mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
			var uvs := PackedVector2Array()
			if a[Mesh.ARRAY_TEX_UV] != null:
				uvs = a[Mesh.ARRAY_TEX_UV]
			var idx := PackedInt32Array()
			if a[Mesh.ARRAY_INDEX] != null:
				idx = a[Mesh.ARRAY_INDEX]
			else:
				for k in verts.size():
					idx.append(k)
			for t in range(0, idx.size(), 3):
				var mid := xf * ((verts[idx[t]] + verts[idx[t + 1]] + verts[idx[t + 2]]) / 3.0)
				var parts := body_parts
				var at := Vector3.ZERO
				for w in wheels:
					var tyre: AABB = w["tyre"]
					var c := tyre.get_center()
					if mid.x >= tyre.position.x - 0.02 and mid.x <= tyre.end.x + 0.02 \
							and Vector2(mid.y - c.y, mid.z - c.z).length() <= tyre.size.y * 0.5 + 0.01:
						parts = w["parts"]
						at = c
						break
				if not parts.has(mat):
					parts[mat] = SurfaceTool.new()
					parts[mat].begin(Mesh.PRIMITIVE_TRIANGLES)
				var st: SurfaceTool = parts[mat]
				for k in 3:
					var i := idx[t + k]
					st.set_normal(turn * normals[i])
					if not uvs.is_empty():
						st.set_uv(uvs[i])
					st.add_vertex(xf * verts[i] - at)
	for w in wheels:
		for mat: Material in w["parts"]:
			w["parts"][mat].index()
	for mat: Material in body_parts:
		body_parts[mat].index()
	return wheels


## The surface arrays of a mesh with only about `keep` of its triangles left.
func _thinned(mi: MeshInstance3D, keep: float) -> Array:
	var arrays: Array = mi.mesh.surface_get_arrays(0)
	if arrays[Mesh.ARRAY_INDEX] == null:
		var count: int = arrays[Mesh.ARRAY_VERTEX].size()
		var all := PackedInt32Array()
		all.resize(count)
		for k in count:
			all[k] = k
		arrays[Mesh.ARRAY_INDEX] = all
	var full: int = arrays[Mesh.ARRAY_INDEX].size()
	if keep >= 1.0 or full < 1500:
		return arrays
	# Models like this often give every face its own corners, which leaves nothing
	# to merge. Weld corners that share a position first, then smooth the shading.
	var bare := []
	bare.resize(Mesh.ARRAY_MAX)
	bare[Mesh.ARRAY_VERTEX] = arrays[Mesh.ARRAY_VERTEX]
	bare[Mesh.ARRAY_INDEX] = arrays[Mesh.ARRAY_INDEX]
	var welder := SurfaceTool.new()
	welder.create_from_arrays(bare)
	welder.deindex()
	welder.index()
	welder.generate_normals()
	arrays = welder.commit_to_arrays()
	# Godot's level-of-detail builder does the thinning; take the first level that is small enough.
	var simplifier := ImporterMesh.new()
	simplifier.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays)
	simplifier.generate_lods(25.0, 60.0, [])
	for level in simplifier.get_surface_lod_count(0):
		var idx := simplifier.get_surface_lod_indices(0, level)
		arrays[Mesh.ARRAY_INDEX] = idx
		if idx.size() <= full * keep:
			break
	return arrays


func _box(mi: MeshInstance3D) -> AABB:
	return mi.global_transform * mi.get_aabb()


func _bounds(meshes: Array[MeshInstance3D]) -> AABB:
	var all := _box(meshes[0])
	for mi in meshes:
		all = all.merge(_box(mi))
	return all


func _material_name(mi: MeshInstance3D, surface: int) -> String:
	var mat := mi.get_active_material(surface)
	return mat.resource_name if mat else ""


func _skipped(material_name: String, words: Array) -> bool:
	for word: String in words:
		if material_name.contains(word):
			return true
	return false


func _append(parts: Dictionary, mi: MeshInstance3D, surface: int, xform: Transform3D) -> void:
	var mat := mi.get_active_material(surface)
	if not parts.has(mat):
		parts[mat] = SurfaceTool.new()
	var st: SurfaceTool = parts[mat]
	st.append_from(mi.mesh, surface, xform)


func _commit(parts: Dictionary, mesh: ArrayMesh = null) -> ArrayMesh:
	if mesh == null:
		mesh = ArrayMesh.new()
	for mat: Material in parts:
		var st: SurfaceTool = parts[mat]
		st.set_material(mat)
		st.commit(mesh)
	return mesh


func _count_tris(mesh: ArrayMesh) -> int:
	var n := 0
	for s in mesh.get_surface_count():
		n += mesh.surface_get_array_index_len(s) / 3
	return n


func _add_box(car: Node3D, node_name: String, size: Vector3, at: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.name = node_name
	cs.shape = shape
	cs.position = at
	car.add_child(cs)


# --- lamps ------------------------------------------------------------------
# Lamps are cut out of the model by where their triangles sit on the car (metres;
# +X is the car's left, +Z its nose). Each model has its own layout.

## Whether a surface holds lamp parts that need cutting out.
func _is_lamp_surface(mi: MeshInstance3D, mat_name: String, layout: String) -> bool:
	if layout == "none":
		return false
	if layout == "w210":
		# The lit parts are the textured lenses behind the clear covers.
		return mat_name.contains("Light") and not mat_name.contains("Glass")
	if layout == "lc80":
		return mat_name.contains("lightmesh") or mat_name.contains("fensiggls")
	if layout == "gaz3102":
		# All the lamp lenses are among the glass materials.
		return mat_name.begins_with("Glass_Window")
	# W211: the lamp covers themselves light up...
	if mat_name == "Red_glass" or mat_name == "Glass":
		return true
	# ...and so does the row of LEDs in each door mirror, which is chrome.
	var box := _box(mi)
	return (mat_name == "Chorme" or mat_name == "Light_Chrome") and maxf(absf(box.position.x), absf(box.end.x)) > 0.95


## Which lamp a triangle belongs to; "" for housing or ordinary glass.
## A "__suffix" marks a second piece of the same lamp made of another material.
func _lamp_zone(c: Vector3, facing: Vector3, layout: String, mat_name: String, on_trunk_lid: bool) -> String:
	var side := "l" if c.x > 0.0 else "r"
	var out := absf(c.x)
	if layout == "w210":
		if c.z < -1.5:
			if c.y > 0.9:
				return "stop" # high-mounted brake light
			if on_trunk_lid:
				return "reverse" if c.y < 0.752 else "tail"
			return "indicator_" + side if out > 0.555 and c.y > 0.79 else "stop"
		if c.z > 1.9 and c.y > 0.5:
			if out < 0.57:
				return "high"
			return "indicator_" + side if c.y > 0.70 else "low"
		if out > 0.8 and c.z > 0.9 and c.z < 1.3:
			return "indicator_" + side # repeater on the front wing
		return ""
	if layout == "lc80":
		if mat_name.contains("fensiggls"):
			return "indicator_" + side # repeater on the front wing
		if c.z > 0.0:
			# Headlamp unit: the outer corner is the turn signal.
			return "indicator_" + side if out > 0.74 else "low"
		# Tail lamp, top to bottom: brake, turn signal, reversing.
		if c.y > 1.02:
			return "stop"
		return "indicator_" + side if c.y > 0.93 else "reverse"
	if layout == "gaz3102":
		if mat_name == "Glass_Window2.1":
			return "indicator_" + side # corner lamps front and rear, and the wing repeaters
		if mat_name == "Glass_Window3.1":
			return "stop"
		# Clear lenses low down at either end: headlamps in front, reversing lamps behind.
		if c.y > 0.4 and c.y < 0.72 and out > 0.2:
			if c.z > 2.25:
				return "low"
			# Only the middle segment of each tail cluster is the reversing lamp.
			if c.z < -2.25 and out > 0.405 and out < 0.495:
				return "reverse"
		return ""
	# W211
	if mat_name == "Chorme" or mat_name == "Light_Chrome":
		# The strip wraps round the outer end of the mirror; back there only faces
		# looking sideways belong to it, the rest is the mirror glass.
		var sideways := facing.x * signf(c.x) > 0.45
		if out > 0.885 and c.y > 0.9 and c.y < 0.97 and c.z < 0.74 and (c.z > 0.655 or (c.z > 0.59 and sideways)):
			return "indicator_%s__mirror" % side
		return ""
	if mat_name == "Red_glass":
		return "stop" if c.z < -1.5 else ""
	if c.z < -1.9 and c.y > 0.6:
		# Two clear strips in the tail lamp: reversing light above, turn signal below.
		return "reverse" if c.y > 0.817 else "indicator_" + side
	if c.z > 1.9 and c.y > 0.42:
		if out < 0.56:
			return "high" # inner, smaller lamp
		# Outer lamp: turn signal in its top part, low beam below.
		return "indicator_" + side if c.y > W211_FRONT_SIGNAL_Y else "low"
	return ""


## Height of the line between low beam and turn signal in the W211 outer headlamp.
const W211_FRONT_SIGNAL_Y := 0.672


## Heights at which a lamp triangle at this place must be cut in two, because the
## model's lens is one piece where the real lamp has two.
func _lamp_cuts(c: Vector3, layout: String) -> Array[float]:
	if layout == "w211" and c.z > 1.9 and absf(c.x) > 0.56 and c.y > 0.42:
		return [W211_FRONT_SIGNAL_Y]
	return []


## Cuts a triangle along the horizontal plane y = height. A corner is
## [position, normal, uv]; the pieces keep the winding of the original.
func _cut_at_height(tri: Array, height: float) -> Array:
	var above := 0
	for corner: Array in tri:
		if corner[0].y > height:
			above += 1
	if above == 0 or above == 3:
		return [tri]
	# One corner is alone on its side; the plane crosses the two edges leaving it.
	var lone := 0
	for k in 3:
		if (tri[k][0].y > height) == (above == 1):
			lone = k
	var a: Array = tri[lone]
	var b: Array = tri[(lone + 1) % 3]
	var c: Array = tri[(lone + 2) % 3]
	var ab := _lerp_corner(a, b, (height - a[0].y) / (b[0].y - a[0].y))
	var ac := _lerp_corner(a, c, (height - a[0].y) / (c[0].y - a[0].y))
	return [[a, ab, ac], [ab, b, c], [ab, c, ac]]


func _lerp_corner(a: Array, b: Array, t: float) -> Array:
	return [a[0].lerp(b[0], t), a[1].lerp(b[1], t).normalized(), a[2].lerp(b[2], t)]


func _split_lamps(mi: MeshInstance3D, surface: int, layout: String, zones: Dictionary, rest: Dictionary) -> void:
	var mat := mi.get_active_material(surface)
	var a: Array = mi.mesh.surface_get_arrays(surface)
	var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var uvs := PackedVector2Array()
	if a[Mesh.ARRAY_TEX_UV] != null:
		uvs = a[Mesh.ARRAY_TEX_UV]
	var idx := PackedInt32Array()
	if a[Mesh.ARRAY_INDEX] != null:
		idx = a[Mesh.ARRAY_INDEX]
	else:
		idx.resize(verts.size())
		for k in idx.size():
			idx[k] = k
	var xf := mi.global_transform
	var turn := xf.basis.orthonormalized()
	var on_trunk_lid := String(mi.get_parent().name).contains("Trunk")
	for t in range(0, idx.size(), 3):
		var tri := []
		for k in 3:
			var i := idx[t + k]
			tri.append([xf * verts[i], turn * normals[i], uvs[i] if not uvs.is_empty() else Vector2.ZERO])
		var pieces := [tri]
		for height in _lamp_cuts((tri[0][0] + tri[1][0] + tri[2][0]) / 3.0, layout):
			var cut := []
			for piece: Array in pieces:
				cut.append_array(_cut_at_height(piece, height))
			pieces = cut
		for piece: Array in pieces:
			var centre: Vector3 = (piece[0][0] + piece[1][0] + piece[2][0]) / 3.0
			var facing: Vector3 = (piece[0][1] + piece[1][1] + piece[2][1]).normalized()
			var zone := _lamp_zone(centre, facing, layout, mat.resource_name, on_trunk_lid)
			var st: SurfaceTool
			if zone == "":
				if not rest.has(mat):
					rest[mat] = SurfaceTool.new()
					rest[mat].begin(Mesh.PRIMITIVE_TRIANGLES)
				st = rest[mat]
			else:
				if not zones.has(zone):
					zones[zone] = [SurfaceTool.new(), mat]
					zones[zone][0].begin(Mesh.PRIMITIVE_TRIANGLES)
				st = zones[zone][0]
			for corner: Array in piece:
				st.set_normal(corner[1])
				if not uvs.is_empty():
					st.set_uv(corner[2])
				st.add_vertex(corner[0])


## One mesh per lamp, each with its own material so car_lights.gd can light it.
func _add_lamps(car: Node3D, zones: Dictionary, cfg: Dictionary) -> void:
	if zones.is_empty():
		return
	var lamps := Node3D.new()
	lamps.name = "Lamps"
	lamps.set_script(load("res://car/car_lights.gd"))
	lamps.set("idle_glow", cfg["idle_glow"])
	lamps.set("glow_scale", cfg.get("glow_scale", 1.0))
	car.add_child(lamps)
	var low := AABB()
	for zone: String in zones:
		var st: SurfaceTool = zones[zone][0]
		var mat: StandardMaterial3D = (zones[zone][1] as StandardMaterial3D).duplicate()
		mat.resource_name = "Lamp_" + zone
		if cfg["lamps"] == "lc80":
			# The kit has no lens colours; give each lamp the colour of its lens.
			if zone == "stop":
				mat.albedo_color = Color(0.45, 0.03, 0.03)
			elif zone.begins_with("indicator"):
				mat.albedo_color = Color(0.8, 0.4, 0.05)
		if cfg["lamps"] == "w211" and zone == "stop":
			# The model's red lens is nearly clear, which shows the chrome behind it
			# and reads as pink; a real tail lamp is a deep, mostly solid red.
			mat.albedo_color = Color(0.5, 0.02, 0.03, 0.85)
		# Glow in the lamp's own colours: where the lens has a texture, that is the
		# light. The tint keeps coloured lamps from washing out when bright.
		mat.emission_enabled = true
		if zone.begins_with("indicator"):
			mat.emission = Color(1.0, 0.5, 0.08)
		elif zone == "stop" or zone == "tail":
			mat.emission = Color(1.0, 0.12, 0.08)
		else:
			mat.emission = Color.WHITE
		if cfg["lamps"] == "w210":
			# Painted lenses: the texture itself is the light.
			mat.emission_texture = mat.albedo_texture
		else:
			# Plain lenses get a bulb: bright in the middle of each lamp, fading to its edges.
			mat.emission_texture = _bulb_texture()
			mat.emission_on_uv2 = true
		mat.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
		mat.emission_energy_multiplier = 0.0
		st.index()
		st.set_material(mat)
		var lamp := MeshInstance3D.new()
		lamp.name = "Lamp_" + zone
		lamp.mesh = st.commit() if cfg["lamps"] == "w210" else _with_bulbs(st, mat)
		lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lamps.add_child(lamp)
		if zone == "low":
			low = lamp.get_aabb()
		print("  lamp %-12s %5d triangles, %s .. %s" % [zone, _count_tris(lamp.mesh),
			lamp.get_aabb().position.snapped(Vector3.ONE * 0.01), lamp.get_aabb().end.snapped(Vector3.ONE * 0.01)])
	if not zones.has("low"):
		return
	# The low-beam mesh spans both sides of the car, so it places both beams.
	for side: float in [1.0, -1.0]:
		var spot := SpotLight3D.new()
		spot.name = "BeamL" if side > 0.0 else "BeamR"
		spot.position = Vector3((low.end.x - 0.1) * side, low.get_center().y, low.end.z + 0.15)
		spot.rotation_degrees = Vector3(-6.0, 180.0, 0.0)
		spot.light_color = Color(1.0, 0.95, 0.85)
		spot.spot_angle = 38.0
		spot.spot_attenuation = 0.7
		spot.visible = false
		lamps.add_child(spot)


# --- cabin ------------------------------------------------------------------

## The steering wheel is the skinned "Body_Bones" part in front of the driver.
## The box is measured on the W210 model (left-hand drive). A kit marks its own.
func _is_steering_wheel(mi: MeshInstance3D) -> bool:
	if mi.has_meta("steering_axis"):
		return true
	if not String(mi.get_parent().name).contains("Body_Bones"):
		return false
	var c := _box(mi).get_center()
	return c.x > 0.15 and c.x < 0.6 and c.y > 0.65 and c.y < 1.1 and c.z > 0.3 and c.z < 0.65


## The direction a flat ring of points faces: the one they vary least along.
func _ring_axis(points: PackedVector3Array) -> Vector3:
	var mean := Vector3.ZERO
	for p in points:
		mean += p / points.size()
	var cov := Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
	for p in points:
		var d := p - mean
		cov.x += d * d.x
		cov.y += d * d.y
		cov.z += d * d.z
	# Power iteration on (trace - covariance) converges on the least-varying direction.
	var trace := cov.x.x + cov.y.y + cov.z.z
	var axis := Vector3(0.3, 0.5, -0.8).normalized()
	for _i in 60:
		axis = (axis * trace - cov * axis).normalized()
	return axis


func _add_interior(car: Node3D, gauge_parts: Dictionary, wheel_surfaces: Array, gauges_shader: String) -> void:
	var interior := Node3D.new()
	interior.name = "Interior"
	interior.set_script(load("res://car/car_interior.gd"))
	car.add_child(interior)

	if not gauge_parts.is_empty():
		var gauges := MeshInstance3D.new()
		gauges.name = "Gauges"
		gauges.mesh = _commit(gauge_parts)
		for s in gauges.mesh.get_surface_count():
			var painted := gauges.mesh.surface_get_material(s) as BaseMaterial3D
			var dial := ShaderMaterial.new()
			dial.shader = load(gauges_shader)
			dial.set_shader_parameter("dial", painted.albedo_texture)
			gauges.mesh.surface_set_material(s, dial)
		gauges.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		interior.add_child(gauges)

	if wheel_surfaces.is_empty():
		return
	# The rim is the widest piece; it gives the centre and the axis to turn about.
	var rim: MeshInstance3D = wheel_surfaces[0][0]
	for entry: Array in wheel_surfaces:
		var mi: MeshInstance3D = entry[0]
		if _box(mi).size.x > _box(rim).size.x:
			rim = mi
	var pivot := _box(rim).get_center()
	var points := PackedVector3Array()
	for p: Vector3 in rim.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		points.append(rim.global_transform * p)
	var axis := _ring_axis(points)
	if axis.z > 0.0:
		axis = -axis # towards the driver
	if rim.has_meta("steering_axis"):
		# A kit knows where it put the wheel.
		pivot = rim.get_meta("steering_pivot")
		axis = rim.get_meta("steering_axis")
	var parts := {}
	for entry: Array in wheel_surfaces:
		var mi: MeshInstance3D = entry[0]
		_append(parts, mi, entry[1], Transform3D(Basis.IDENTITY, -pivot) * mi.global_transform)
	var wheel := Node3D.new()
	wheel.name = "SteeringWheel"
	wheel.position = pivot
	wheel.set_meta("axis", axis)
	var visual := MeshInstance3D.new()
	visual.name = "Mesh"
	visual.mesh = _commit(parts)
	wheel.add_child(visual)
	interior.add_child(wheel)
	print("  steering wheel: %d pieces, centre %s, axis %s (tilted %.0f deg)" % [
		wheel_surfaces.size(), pivot.snapped(Vector3.ONE * 0.01), axis.snapped(Vector3.ONE * 0.01), rad_to_deg(acos(-axis.z))])


# --- bulbs ------------------------------------------------------------------

var _bulb: GradientTexture2D


## A soft round glow: white-hot in the middle, dim at the rim.
func _bulb_texture() -> GradientTexture2D:
	if _bulb == null:
		var falloff := Gradient.new()
		falloff.offsets = PackedFloat32Array([0.0, 0.12, 0.4, 1.0])
		falloff.colors = PackedColorArray([Color(1, 1, 1), Color(0.9, 0.9, 0.9), Color(0.38, 0.38, 0.38), Color(0.14, 0.14, 0.14)])
		_bulb = GradientTexture2D.new()
		_bulb.gradient = falloff
		_bulb.fill = GradientTexture2D.FILL_RADIAL
		_bulb.fill_from = Vector2(0.5, 0.5)
		_bulb.fill_to = Vector2(1.1, 0.5)
		_bulb.width = 64
		_bulb.height = 64
	return _bulb


## Commits a lamp with a second set of texture coordinates that puts the centre
## of the bulb texture in the middle of each separate lamp. The pieces of one
## zone (left and right, front and rear, each segment of a cluster) are told
## apart by which end of the car they are at and by gaps of more than `gap` metres across it.
func _with_bulbs(st: SurfaceTool, mat: Material, gap := 0.03) -> ArrayMesh:
	var arrays := st.commit_to_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	# Triangles by end of the car, sorted across it.
	var groups := {}
	for t in range(0, idx.size(), 3):
		var c := (verts[idx[t]] + verts[idx[t + 1]] + verts[idx[t + 2]]) / 3.0
		var end := 1 if c.z > 1.5 else (-1 if c.z < -1.5 else 0)
		if not groups.has(end):
			groups[end] = []
		var x0 := minf(verts[idx[t]].x, minf(verts[idx[t + 1]].x, verts[idx[t + 2]].x))
		var x1 := maxf(verts[idx[t]].x, maxf(verts[idx[t + 1]].x, verts[idx[t + 2]].x))
		groups[end].append([x0, t, x1])
	var uv2 := PackedVector2Array()
	uv2.resize(verts.size())
	for end: int in groups:
		var tris: Array = groups[end]
		tris.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		var first := 0
		var reach: float = tris[0][2] # how far across the lamp being gathered extends
		for k in range(1, tris.size() + 1):
			if k < tris.size() and tris[k][0] - reach < gap:
				reach = maxf(reach, tris[k][2])
				continue
			# Triangles first..k-1 are one lamp.
			var box := AABB(verts[idx[tris[first][1]]], Vector3.ZERO)
			for n in range(first, k):
				for corner in 3:
					box = box.expand(verts[idx[tris[n][1] + corner]])
			# Seen from the front or back a lamp spreads across the car; on its side, along it.
			var across := box.size.x >= box.size.z
			var centre := box.get_center()
			var half := Vector2(maxf(box.size.x if across else box.size.z, 0.02), maxf(box.size.y, 0.02)) * 0.5
			for n in range(first, k):
				for corner in 3:
					var i := idx[tris[n][1] + corner]
					var p := verts[i] - centre
					uv2[i] = Vector2((p.x if across else p.z) / half.x, p.y / half.y) * 0.5 + Vector2(0.5, 0.5)
			first = k
			if k < tris.size():
				reach = tris[k][2]
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, mat)
	return mesh


# --- Land Cruiser 80 kit ----------------------------------------------------

## What each kind of part in the kit is made of: [colour, metallic, roughness].
## The kind is in the name of the part; the first entry whose key it contains wins.
const LC80_MATERIALS := [
	["glass", Color(0.04, 0.06, 0.07, 0.3), 0.0, 0.05],
	["lightgls", Color(0.85, 0.9, 0.95, 0.12), 0.0, 0.05], # clear covers over the lamps
	["paint", Color(0.05, 0.17, 0.52), 0.3, 0.25],
	["intchrome", Color(0.8, 0.8, 0.82), 1.0, 0.25],
	["chrome", Color(0.82, 0.83, 0.86), 1.0, 0.15],
	["decals", Color(0.82, 0.83, 0.86), 1.0, 0.2],
	["tire", Color(0.03, 0.03, 0.03), 0.0, 0.9],
	["sparewheel", Color(0.03, 0.03, 0.03), 0.0, 0.9],
	["wheel", Color(0.75, 0.76, 0.78), 0.9, 0.35],
	["lightmesh", Color(0.8, 0.8, 0.8), 0.7, 0.2],
	["fensiggls", Color(0.8, 0.4, 0.05), 0.0, 0.2],
	["greyplas", Color(0.3, 0.3, 0.3), 0.0, 0.7],
	["intplas", Color(0.33, 0.31, 0.28), 0.0, 0.8],
	["plas", Color(0.05, 0.05, 0.055), 0.0, 0.6],
	["metalbl", Color(0.04, 0.04, 0.045), 0.6, 0.4],
	["offroad", Color(0.04, 0.04, 0.045), 0.6, 0.45],
	["under", Color(0.1, 0.09, 0.08), 0.3, 0.8],
	["grill", Color(0.03, 0.03, 0.03), 0.0, 0.6],
	["leatherblack", Color(0.04, 0.04, 0.04), 0.0, 0.6],
	["leather", Color(0.5, 0.45, 0.38), 0.0, 0.65],
	["seats", Color(0.47, 0.43, 0.37), 0.0, 0.8],
	["fabric", Color(0.68, 0.66, 0.62), 0.0, 0.95],
	["carpet", Color(0.2, 0.19, 0.17), 0.0, 1.0],
	["tuma", Color(0.2, 0.19, 0.17), 0.0, 1.0],
	["wood", Color(0.3, 0.16, 0.07), 0.0, 0.25],
	["intkop", Color(0.1, 0.1, 0.1), 0.0, 0.7],
	["speaker", Color(0.06, 0.06, 0.06), 0.0, 0.8],
	["gear", Color(0.85, 0.85, 0.8), 0.0, 0.5],
	["none", Color(0.85, 0.85, 0.85), 0.0, 0.5],
]
## Share of triangles kept for the kinds that are far more detailed than the game can show.
const LC80_DETAIL := {"under": 0.3, "intplas": 0.4, "leather": 0.4, "seats1": 0.4, "intkop": 0.5, "metalbl": 0.5}
## The gear sticks of the manual car, which stand where the automatic's selector goes.
const LC80_MANUAL_LEVERS := [55, 56, 57, 58, 200, 201]
## The middle of the end of the steering column, and how far the column leans back, in degrees.
const LC80_COLUMN_END := Vector3(0.405, 1.178, 0.384)
const LC80_COLUMN_LEAN := 24.0


## Where the driver's controls go, by part number: [transform into place, kind to
## dress the part as ("" for its own), whether it turns with the steering wheel]. They lie loose around the origin of the
## file, each kind twice or more (left- and right-hand drive, manual and
## automatic); these are the ones for a left-hand-drive automatic.
func _lc80_fittings() -> Dictionary:
	# The steering wheel lies flat, face up; the underside of its boss goes on the end of the column.
	var steering := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(LC80_COLUMN_LEAN - 90.0)), LC80_COLUMN_END) \
			* Transform3D(Basis.IDENTITY, Vector3(0.07, 0.068, -0.27))
	# The selector stands upright already; its collar goes on the gate in the console.
	var selector := Transform3D(Basis.IDENTITY, Vector3(0.001, 0.886, 0.37))
	# The transfer lever lies on its side with its foot at the origin; stand it
	# beside the selector, leaning back and towards the driver.
	var transfer := Transform3D(Basis(Vector3.UP, -PI / 2.0) * Basis(Vector3.BACK, PI / 2.0), Vector3(0.095, 0.884, 0.4))
	# The pedals hang from the origin, the brake already 15 cm to the left of the
	# accelerator; the pivots go up under the dashboard, ahead of the driver's feet.
	var pedals := Transform3D(Basis.IDENTITY, Vector3(0.27, 0.93, 0.84))
	return {
		37: [steering, "", true],
		32: [steering, "intchrome", true], # the badge on the boss
		60: [selector, "leatherblack", false],
		44: [transfer, "", false],
		129: [pedals, "", false], # accelerator
		213: [pedals, "", false], # the automatic's wide brake pedal
	}


## Finishes the Land Cruiser. The file is the kit put together in Blender: body,
## wheels and trim are in place, but everything shares one grey material and the
## driver's controls still lie loose at the origin. This colours each part by its
## kind, fits the controls and leaves out what cannot be seen or is there twice.
func _assemble_lc80(model: Node3D) -> void:
	var materials := {}
	var fittings := _lc80_fittings()
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node
		var b := _box(mi)
		var c := b.get_center()
		var kind := _lc80_kind(mi)
		var number := _lc80_number(mi)
		var keep := true
		if fittings.has(number):
			mi.global_transform = fittings[number][0] * mi.global_transform
			if fittings[number][2]:
				# Kept apart from the body so that it can turn (see _add_interior).
				var lean := deg_to_rad(LC80_COLUMN_LEAN)
				mi.set_meta("steering_pivot", LC80_COLUMN_END)
				mi.set_meta("steering_axis", Vector3(0.0, sin(lean), -cos(lean)))
			if fittings[number][1] != "":
				kind = fittings[number][1]
		elif c.y < 0.2 and b.end.y < 0.5 and absf(c.z) < 1.0 and absf(c.x) < 0.5:
			# The rest of the loose parts: the other variants of the controls and the gauge needles.
			keep = false
		else:
			# Number plates come in two shapes on top of each other, and a pair hidden behind the spare wheel.
			var spare_plate := kind == "none" and absf(c.z) > 2.2 and (mi.mesh.get_faces().size() / 3 == 36 or (c.z < 0.0 and absf(c.x) < 0.1))
			# A piece of the right-hand-drive dashboard is still parked above the roof rack.
			var parked := b.position.y > 2.24
			keep = not (kind == "engine" or spare_plate or parked or number in LC80_MANUAL_LEVERS or number in LC80_CLUSTER_SHAPES)
		if not keep:
			mi.free()
			continue
		if number == 194 and kind == "decals_int":
			_lc80_cluster(mi, model)
		# The front wings with their flares are one plastic part; paint them like the body.
		if kind == "plas" and absf(c.x) > 0.7 and c.z > 1.0 and b.size.y > 0.7 and b.size.z > 1.2:
			kind = "paint"
		# The rear doors are filed under chrome in the kit.
		if kind == "chrome" and absf(c.x) > 0.6 and c.z > -1.3 and c.z < -0.2 and b.size.y > 1.0:
			kind = "paint"
		_dress_lc80(mi, kind, materials)

	# The slot the selector stands in is open to the gearbox below; close it with a plate.
	var gate := MeshInstance3D.new()
	gate.name = "gate"
	var plate := PlaneMesh.new()
	plate.size = Vector2(0.08, 0.2)
	gate.mesh = plate
	model.add_child(gate)
	gate.global_position = Vector3(0.001, 0.884, 0.373)
	_dress_lc80(gate, "plas", materials)


## The instrument cluster's face: its middle, the direction up it (it leans
## back) and its size in metres. The dial texture is stretched over this.
const LC80_DIAL_CENTRE := Vector3(0.4075, 1.278, 0.604)
const LC80_DIAL_UP := Vector3(0.0, 0.855, 0.519)
const LC80_DIAL_SIZE := Vector2(0.36, 0.144)
## Size of the dial texture; car/gauges_lc80.gdshader places its needles in these pixels.
const LC80_DIAL_PIXELS := Vector2i(1280, 512)
## Lettering and lamps of the cluster that the kit has as loose shapes; the dial texture has them painted on.
const LC80_CLUSTER_SHAPES := [125, 126, 127, 128, 191, 192]

var _lc80_dial: ImageTexture


## Takes the instrument cluster out of the dashboard's markings. The kit has no
## pictures, so the face of the cluster is blank and the sheet in front of it
## came out as a mirror; the sheet goes, and the face becomes a part of its own
## with the painted dials on it.
func _lc80_cluster(markings: MeshInstance3D, model: Node3D) -> void:
	var a: Array = markings.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var xf := markings.global_transform
	var facing := LC80_DIAL_UP.cross(Vector3.LEFT) # towards the driver
	var rest := SurfaceTool.new()
	rest.begin(Mesh.PRIMITIVE_TRIANGLES)
	var face := SurfaceTool.new()
	face.begin(Mesh.PRIMITIVE_TRIANGLES)
	for t in range(0, idx.size(), 3):
		var p0 := xf * verts[idx[t]]
		var p1 := xf * verts[idx[t + 1]]
		var p2 := xf * verts[idx[t + 2]]
		var c := (p0 + p1 + p2) / 3.0
		var in_cluster := c.x > 0.2 and c.x < 0.62 and c.y > 1.2 and c.y < 1.36 and c.z > 0.5
		if in_cluster and (p1 - p0).cross(p2 - p0).length() > 0.02:
			continue # the sheet in front
		# The face is the part that had a picture laid over it once; the cluster's sides repeat a pattern.
		var painted := in_cluster
		for k in 3:
			var uv := uvs[idx[t + k]]
			if uv.x < -0.01 or uv.x > 1.01 or uv.y < -0.01 or uv.y > 1.01:
				painted = false
		if in_cluster and not painted and c.x > 0.23 and c.x < 0.585:
			continue # the odometer's number drums, which are painted on the dial instead
		for k in 3:
			var i := idx[t + k]
			if painted:
				var d := xf * verts[i] - LC80_DIAL_CENTRE
				face.set_normal(facing)
				face.set_uv(Vector2(0.5 + d.dot(Vector3.LEFT) / LC80_DIAL_SIZE.x, 0.5 - d.dot(LC80_DIAL_UP) / LC80_DIAL_SIZE.y))
				face.add_vertex(xf * verts[i])
			else:
				rest.set_normal(normals[i])
				rest.set_uv(uvs[i])
				rest.add_vertex(verts[i])
	# The odometer's windows are holes in the face; a sheet just behind it carries the picture on across them.
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var across := corner * 0.49
		face.set_normal(facing)
		face.set_uv(Vector2(0.5 + across.x, 0.5 - across.y))
		face.add_vertex(LC80_DIAL_CENTRE - facing * 0.006 + Vector3.LEFT * across.x * LC80_DIAL_SIZE.x + LC80_DIAL_UP * across.y * LC80_DIAL_SIZE.y)
	rest.index()
	markings.mesh = rest.commit()
	face.index()
	var dials := MeshInstance3D.new()
	dials.name = "cluster"
	dials.mesh = face.commit()
	# By this name _build hands it to the cabin (see _add_interior).
	var paint := StandardMaterial3D.new()
	paint.resource_name = "Dashboard"
	paint.albedo_texture = _lc80_dial
	dials.set_surface_override_material(0, paint)
	model.add_child(dials)


## Paints the Land Cruiser's dial texture: rev counter, speedometer, fuel and
## temperature gauges, the gear letters and the turn arrows.
func _lc80_paint_dial() -> ImageTexture:
	var viewport := SubViewport.new()
	viewport.size = LC80_DIAL_PIXELS
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var canvas := Control.new()
	canvas.size = LC80_DIAL_PIXELS
	canvas.draw.connect(_lc80_draw_dial.bind(canvas))
	viewport.add_child(canvas)
	root.add_child(viewport)
	for _i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	viewport.queue_free()
	image.convert(Image.FORMAT_RGB8)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


func _lc80_draw_dial(canvas: Control) -> void:
	var white := Color(0.92, 0.92, 0.88)
	var grey := Color(0.5, 0.5, 0.48)
	var red := Color(0.85, 0.12, 0.05)
	var needle := Color(0.85, 0.2, 0.03)
	canvas.draw_rect(Rect2(Vector2.ZERO, LC80_DIAL_PIXELS), Color(0.012, 0.012, 0.016))
	# The hubs and arrows are where car/gauges_lc80.gdshader expects them.
	var rev_hub := Vector2(397, 280)
	var speed_hub := Vector2(883, 280)
	# Rev counter: 0 to 7 (thousand), red from 6.
	_lc80_draw_scale(canvas, rev_hub, 205.0, 210.0, -30.0, 7, 4, white, 6)
	for n in 8:
		_lc80_draw_text(canvas, rev_hub + _lc80_spoke(210.0 - 240.0 * n / 7.0) * 152.0, str(n), 40, red if n >= 6 else white)
	_lc80_draw_text(canvas, rev_hub + Vector2(0, 84), "x1000 r/min", 20, grey)
	# Speedometer: 0 to 200 km/h.
	_lc80_draw_scale(canvas, speed_hub, 205.0, 210.0, -30.0, 10, 4, white, 99)
	for n in 11:
		_lc80_draw_text(canvas, speed_hub + _lc80_spoke(210.0 - 24.0 * n) * 150.0, str(n * 20), 28, white)
	_lc80_draw_text(canvas, speed_hub + Vector2(0, 62), "km/h", 20, grey)
	canvas.draw_rect(Rect2(speed_hub + Vector2(-58, 84), Vector2(116, 34)), Color(0.07, 0.07, 0.07))
	_lc80_draw_text(canvas, speed_hub + Vector2(0, 101), "186420", 24, white)
	# Fuel on the far left, temperature on the far right; their needles do not move.
	var gauges := [[Vector2(100, 310), "E", "F", 0.7], [Vector2(1180, 310), "C", "H", 0.45]]
	for gauge: Array in gauges:
		var hub: Vector2 = gauge[0]
		_lc80_draw_scale(canvas, hub, 80.0, 140.0, 40.0, 4, 2, white, 99)
		_lc80_draw_text(canvas, hub + _lc80_spoke(140.0) * 50.0, gauge[1], 20, white)
		_lc80_draw_text(canvas, hub + _lc80_spoke(40.0) * 50.0, gauge[2], 20, white)
		canvas.draw_line(hub, hub + _lc80_spoke(140.0 - 100.0 * gauge[3]) * 70.0, needle, 4.0, true)
		canvas.draw_circle(hub, 9.0, Color(0.03, 0.03, 0.03))
	# Gear letters down the middle.
	var letters := "PRND2L"
	for n in letters.length():
		_lc80_draw_text(canvas, Vector2(640, 185 + 38 * n), letters[n], 26, white if letters[n] == "D" else grey)
	# Turn arrows, dark until the shader lights them.
	for side: float in [-1.0, 1.0]:
		var at := Vector2(640 + 71 * side, 66)
		var arrow := PackedVector2Array()
		for corner: Vector2 in [Vector2(28, 0), Vector2(4, -22), Vector2(4, -10), Vector2(-26, -10), Vector2(-26, 10), Vector2(4, 10), Vector2(4, 22)]:
			arrow.append(at + Vector2(corner.x * side, corner.y))
		canvas.draw_colored_polygon(arrow, Color(0.0, 0.1, 0.015))


## Unit vector at an angle in degrees, anticlockwise from the right, in texture pixels (y down).
func _lc80_spoke(degrees: float) -> Vector2:
	return Vector2(cos(deg_to_rad(degrees)), -sin(deg_to_rad(degrees)))


## The ticks of a dial from one angle round to another: `steps` numbered
## divisions of `parts` small ones each, red from division `red_from` on.
func _lc80_draw_scale(canvas: Control, hub: Vector2, radius: float, from: float, to: float, steps: int, parts: int, colour: Color, red_from: int) -> void:
	for n in steps * parts + 1:
		var spoke := _lc80_spoke(lerpf(from, to, float(n) / (steps * parts)))
		var numbered := n % parts == 0
		var ink := Color(0.85, 0.12, 0.05) if n >= red_from * parts else colour
		canvas.draw_line(hub + spoke * (radius - (20.0 if numbered else 10.0)), hub + spoke * radius, ink, 5.0 if numbered else 2.5, true)


## Text with its middle at the given point.
func _lc80_draw_text(canvas: Control, at: Vector2, text: String, size: int, colour: Color) -> void:
	var font := ThemeDB.fallback_font
	var box := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	canvas.draw_string(font, at + Vector2(-box.x * 0.5, font.get_ascent(size) - box.y * 0.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, colour)


## The kind of a kit part, from its name ("mesh_018_J80KEN_tire_0" is a "tire").
func _lc80_kind(mi: MeshInstance3D) -> String:
	var part := String(mi.name)
	var at := part.find("J80KEN_")
	if at < 0:
		return "none"
	var kind := part.substr(at + 7)
	# Copies made in Blender carry a counter after the name ("tire_0_001").
	var counter := kind.rfind("_")
	if kind.length() - counter == 4 and kind.substr(counter + 1).is_valid_int():
		kind = kind.left(counter)
	return kind.trim_suffix("_0")


## The number of a kit part ("mesh_018_J80KEN_tire_0" is part 18; the first part has none).
func _lc80_number(mi: MeshInstance3D) -> int:
	var number := String(mi.name).get_slice("_", 1)
	return number.to_int() if number.is_valid_int() else 0


## Gives a kit part the material of its kind, and thins it if it is over-detailed.
func _dress_lc80(mi: MeshInstance3D, kind: String, materials: Dictionary) -> void:
	if not materials.has(kind):
		var mat := StandardMaterial3D.new()
		mat.resource_name = kind
		for entry: Array in LC80_MATERIALS:
			if kind.contains(entry[0]):
				mat.albedo_color = entry[1]
				mat.metallic = entry[2]
				mat.roughness = entry[3]
				break
		if mat.albedo_color.a < 1.0:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		# Many panels in the kit are single skins seen from both sides.
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		materials[kind] = mat
	for key: String in LC80_DETAIL:
		if kind.contains(key):
			var thinned := ArrayMesh.new()
			thinned.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _thinned(mi, LC80_DETAIL[key]))
			mi.mesh = thinned
			break
	mi.set_surface_override_material(0, materials[kind])
