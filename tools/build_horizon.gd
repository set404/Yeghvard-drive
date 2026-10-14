extends SceneTree
## Builds res://world/horizon.scn: the land around the town out to ~100 km, so that
## Ararat, Aragats and the other mountains stand on the horizon where they really are.
##
## Input (see tools/fetch_data.ps1):
##   data/elev_far/9_X_Y.png   Terrarium elevation tiles, ~230 m per pixel
## Needs world/yeghvard.scn (tools/build_world.gd) for the town's base elevation.
##
## Run:  godot --path . --script res://tools/build_horizon.gd
## (not --headless: the headless renderer does not keep mesh data)
##
## The mesh is a polar grid around the town, finer close in and coarser far out,
## at the land's true positions (with the Earth's curvature). world/shaders/
## horizon.gdshader draws it closer to the camera than it is, to fit the far plane.

# Must match tools/build_world.gd.
const LAT0 := 40.322
const LON0 := 44.4815
const HALF := 2304.0

const ZOOM := 9
const TILE_X0 := 317
const TILE_Y0 := 191
const TILES := 5
const EW := TILES * 256

const AZIMUTHS := 720
const SECTORS := 24
const R_START := 2150.0
const R_END := 105000.0
const R_GROWTH := 1.03
const EARTH_R := 6371000.0
const REFRACTION := 0.13
## How far below the town's terrain the horizon tucks in next to its edge (metres).
const EDGE_SINK := 3.0

const WORLD_PATH := "res://world/yeghvard.scn"
const OUT_PATH := "res://world/horizon.scn"

var elev := PackedFloat32Array()


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Run without --headless: mesh data is not kept by the headless renderer.")
		quit(1)
		return
	var t0 := Time.get_ticks_msec()
	_load_elev()
	var base := _base_elevation()

	var radii := PackedFloat32Array()
	var r := R_START
	while r < R_END:
		radii.append(r)
		r *= R_GROWTH
	var nr := radii.size()

	# True positions and heights above sea level, ring by ring.
	var pos := PackedVector3Array()
	var asl := PackedFloat32Array()
	pos.resize(nr * AZIMUTHS)
	asl.resize(nr * AZIMUTHS)
	var peak := Vector3(0.0, -INF, 0.0)
	for k in nr:
		var dist := radii[k]
		var drop := dist * dist * (1.0 - REFRACTION) / (2.0 * EARTH_R)
		for a in AZIMUTHS:
			var az := TAU * a / AZIMUTHS
			var ll := _destination(az, dist)
			var e := _elev_at(ll.x, ll.y)
			var x := dist * sin(az)
			var z := -dist * cos(az)
			var outside := maxf(absf(x), absf(z)) - HALF
			var sink := EDGE_SINK * (1.0 - smoothstep(0.0, 400.0, outside))
			pos[k * AZIMUTHS + a] = Vector3(x, e - base - drop - sink, z)
			asl[k * AZIMUTHS + a] = e
			if e > peak.y:
				peak = Vector3(rad_to_deg(az), e, dist)
	print("Horizon: %d rings x %d azimuths; highest %.0f m at azimuth %.1f, %.1f km" % [
		nr, AZIMUTHS, peak.y, peak.x, peak.z / 1000.0])

	var mat := ShaderMaterial.new()
	mat.shader = load("res://world/shaders/horizon.gdshader")
	var root := Node3D.new()
	root.name = "Horizon"
	var per := AZIMUTHS / SECTORS
	for s in SECTORS:
		var mi := MeshInstance3D.new()
		mi.name = "Sector_%d" % s
		mi.mesh = _sector_mesh(pos, asl, nr, s * per, per, mat)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		mi.owner = root

	# Leave every uniform unset, so the defaults in the shader file are the ones used
	# (otherwise the values at build time are saved with the material and stick).
	for u in mat.shader.get_shader_uniform_list():
		mat.set_shader_parameter(u["name"], null)

	var scene := PackedScene.new()
	var err := scene.pack(root)
	if err == OK:
		err = ResourceSaver.save(scene, OUT_PATH, ResourceSaver.FLAG_COMPRESS)
	if err != OK:
		push_error("Saving %s failed: %s" % [OUT_PATH, error_string(err)])
	else:
		print("Saved %s in %.1f s" % [OUT_PATH, (Time.get_ticks_msec() - t0) / 1000.0])
	root.free()
	quit(0 if err == OK else 1)


## The town's elevation above sea level, which build_world.gd made its zero.
func _base_elevation() -> float:
	var state := (load(WORLD_PATH) as PackedScene).get_state()
	for i in state.get_node_property_count(0):
		if state.get_node_property_name(0, i) == &"metadata/base_elevation":
			return state.get_node_property_value(0, i)
	push_error("No base_elevation on %s; build the world first." % WORLD_PATH)
	return 0.0


## Latitude and longitude (degrees) reached going `dist` metres from the town
## centre along the bearing `az` (radians, clockwise from north).
func _destination(az: float, dist: float) -> Vector2:
	var p1 := deg_to_rad(LAT0)
	var d := dist / EARTH_R
	var p2 := asin(sin(p1) * cos(d) + cos(p1) * sin(d) * cos(az))
	var l2 := deg_to_rad(LON0) + atan2(sin(az) * sin(d) * cos(p1), cos(d) - sin(p1) * sin(p2))
	return Vector2(rad_to_deg(p2), rad_to_deg(l2))


func _load_elev() -> void:
	elev.resize(EW * EW)
	for ty in TILES:
		for tx in TILES:
			var path := "res://data/elev_far/%d_%d_%d.png" % [ZOOM, TILE_X0 + tx, TILE_Y0 + ty]
			var img := Image.load_from_file(ProjectSettings.globalize_path(path))
			img.convert(Image.FORMAT_RGB8)
			var d := img.get_data()
			for y in 256:
				var row := (ty * 256 + y) * EW + tx * 256
				for x in 256:
					var o := (y * 256 + x) * 3
					elev[row + x] = d[o] * 256.0 + d[o + 1] + d[o + 2] / 256.0 - 32768.0


func _elev_at(lat: float, lon: float) -> float:
	var n := float(1 << ZOOM) * 256.0
	var lr := deg_to_rad(lat)
	var px := (lon + 180.0) / 360.0 * n - TILE_X0 * 256.0 - 0.5
	var py := (1.0 - log(tan(lr) + 1.0 / cos(lr)) / PI) * 0.5 * n - TILE_Y0 * 256.0 - 0.5
	px = clampf(px, 0.0, EW - 1.001)
	py = clampf(py, 0.0, EW - 1.001)
	var x0 := int(px)
	var y0 := int(py)
	var fx := px - x0
	var fy := py - y0
	var a := elev[y0 * EW + x0]
	var b := elev[y0 * EW + x0 + 1]
	var c := elev[(y0 + 1) * EW + x0]
	var d := elev[(y0 + 1) * EW + x0 + 1]
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy)


## One wedge of the grid, azimuths a0..a0+count. Cells wholly inside the town's
## own terrain are left out.
func _sector_mesh(pos: PackedVector3Array, asl: PackedFloat32Array, nr: int, a0: int, count: int,
		mat: Material) -> ArrayMesh:
	var v := PackedVector3Array()
	var nrm := PackedVector3Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	var w := count + 1
	for k in nr:
		for j in w:
			var a := (a0 + j) % AZIMUTHS
			var p := pos[k * AZIMUTHS + a]
			var along := pos[k * AZIMUTHS + (a + 1) % AZIMUTHS] - pos[k * AZIMUTHS + (a + AZIMUTHS - 1) % AZIMUTHS]
			var out := pos[mini(k + 1, nr - 1) * AZIMUTHS + a] - pos[maxi(k - 1, 0) * AZIMUTHS + a]
			var n := along.cross(out).normalized()
			if n.y < 0.0:
				n = -n
			v.append(p)
			nrm.append(n)
			uv.append(Vector2(asl[k * AZIMUTHS + a], 0.0))
	for k in nr - 1:
		for j in count:
			var i00 := k * w + j
			var i01 := i00 + 1
			var i10 := i00 + w
			var i11 := i10 + 1
			var inside := true
			for i in [i00, i01, i10, i11]:
				if maxf(absf(v[i].x), absf(v[i].z)) > HALF - 30.0:
					inside = false
			if inside:
				continue
			_tri_up(v, idx, i00, i01, i10)
			_tri_up(v, idx, i01, i11, i10)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.surface_set_material(0, mat)
	return m


## Adds a triangle wound so that it faces +Y (as build_world.gd's MeshBuf.tri_up).
func _tri_up(v: PackedVector3Array, idx: PackedInt32Array, a: int, b: int, d: int) -> void:
	var pa := v[a]
	var pb := v[b]
	var pd := v[d]
	if (pb.x - pa.x) * (pd.z - pa.z) - (pb.z - pa.z) * (pd.x - pa.x) > 0.0:
		idx.append_array([a, b, d])
	else:
		idx.append_array([a, d, b])
