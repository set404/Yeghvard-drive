extends SceneTree
## Builds res://world/yeghvard.scn from OpenStreetMap data and elevation tiles.
##
## Inputs (see tools/fetch_data.ps1):
##   data/osm.json            Overpass API export ("out body geom")
##   data/elev/13_X_Y.png     Terrarium elevation tiles
##
## Run:  godot --path . --script res://tools/build_world.gd
## (not --headless: the headless renderer drops the tree instance data)

const LAT0 := 40.322
const LON0 := 44.4815

const GRID_N := 513
const CELL := 9.0
const HALF := (GRID_N - 1) * CELL * 0.5

const ELEV_ZOOM := 13
const TILE_X0 := 5106
const TILE_Y0 := 3090
const TILES := 4
const EW := TILES * 256

const TEX_N := 1152
const TEX_PX := 2.0 * HALF / TEX_N

const TERRAIN_CHUNKS := 8
const OBJ_CHUNK := 768.0
const TREE_CHUNK := 1152.0
const ROAD_STEP := 3.0
const MAX_TREES := 45000

const OUT_DIR := "res://world"
const OUT_PATH := "res://world/yeghvard.scn"
const MAP_PATH := "res://world/minimap.res"
const MAP_N := 2304

const MASK_BUILDING := 1
const MASK_ROAD := 2
const MASK_WATER := 3

# highway type -> [width m, priority, kind, lane markings]
# kind: 0 asphalt, 1 dirt, 2 footpath, 3 rail bed
const ROAD_TYPES := {
	"motorway": [11.0, 6, 0, true], "trunk": [10.0, 6, 0, true],
	"primary": [9.0, 5, 0, true], "secondary": [8.0, 4, 0, true],
	"tertiary": [7.0, 3, 0, true],
	"motorway_link": [6.0, 3, 0, false], "trunk_link": [6.0, 3, 0, false],
	"primary_link": [6.0, 3, 0, false], "secondary_link": [6.0, 3, 0, false],
	"tertiary_link": [6.0, 3, 0, false],
	"unclassified": [5.5, 2, 0, false], "residential": [5.5, 2, 0, false],
	"living_street": [5.0, 2, 0, false], "road": [5.0, 2, 0, false],
	"service": [3.6, 1, 0, false], "track": [3.2, 0, 1, false],
	"pedestrian": [4.0, 0, 2, false], "footway": [1.8, 0, 2, false],
	"path": [1.5, 0, 2, false], "steps": [1.8, 0, 2, false],
	"cycleway": [1.8, 0, 2, false], "bridleway": [1.8, 0, 1, false],
}
const UNPAVED := ["unpaved", "dirt", "ground", "gravel", "earth", "compacted", "sand", "fine_gravel", "mud", "grass"]

const AREA_CLASS := {
	"residential": 1,
	"farmland": 2, "farmyard": 2,
	"orchard": 3, "vineyard": 3, "allotments": 3, "plant_nursery": 3,
	"forest": 4, "wood": 4,
	"grass": 5, "meadow": 5, "park": 5, "garden": 5, "recreation_ground": 5,
	"village_green": 5, "pitch": 5, "grassland": 5, "playground": 5,
	"industrial": 6, "commercial": 6, "retail": 6, "construction": 6,
	"brownfield": 6, "railway": 6, "garages": 6,
	"cemetery": 7,
	"quarry": 8, "bare_rock": 8, "scree": 8, "landfill": 8, "sand": 8,
	"water": 9, "reservoir": 9, "basin": 9,
	"scrub": 10, "heath": 10,
}
# sRGB ground colours per class id
const AREA_COLORS := [
	Color(0.50, 0.46, 0.31), # 0 unmapped: dry steppe
	Color(0.55, 0.51, 0.40), # 1 residential
	Color(0.64, 0.58, 0.34), # 2 farmland
	Color(0.36, 0.47, 0.24), # 3 orchard
	Color(0.24, 0.37, 0.19), # 4 forest
	Color(0.41, 0.53, 0.27), # 5 grass
	Color(0.53, 0.52, 0.50), # 6 industrial
	Color(0.48, 0.51, 0.40), # 7 cemetery
	Color(0.62, 0.60, 0.56), # 8 bare
	Color(0.20, 0.34, 0.44), # 9 water
	Color(0.46, 0.49, 0.30), # 10 scrub
]
# trees per square metre, by class id
const AREA_TREES := {3: 1.0 / 50.0, 4: 1.0 / 45.0, 5: 1.0 / 260.0, 7: 1.0 / 350.0, 10: 1.0 / 400.0}

# Armenian tuff, basalt and plaster tones
const WALL_COLORS := [
	Color(0.80, 0.58, 0.50), Color(0.82, 0.62, 0.44), Color(0.74, 0.50, 0.42),
	Color(0.50, 0.49, 0.49), Color(0.82, 0.74, 0.62), Color(0.87, 0.83, 0.75),
	Color(0.64, 0.50, 0.40), Color(0.72, 0.68, 0.62),
]
const ROOF_COLORS := [
	Color(0.55, 0.56, 0.58), Color(0.50, 0.26, 0.20), Color(0.32, 0.32, 0.34),
	Color(0.42, 0.44, 0.40), Color(0.60, 0.36, 0.26), Color(0.66, 0.66, 0.64),
]
## Storey height and window spacing in metres; building.gdshader uses the same numbers.
const FLOOR_HEIGHT := 3.0
const WINDOW_SPACING := 3.2

## Corrections to single buildings, by OpenStreetMap id (for a building that is a
## relation: relation id + member way id).
##   floors       number of storeys
##   stone        "pink_tuff" for walls of Armenian pink tuff blocks
##   garage_near  a spot (x, z) in world metres; the ground-floor window nearest
##                to it becomes a garage door
const BUILDING_FIXES := {
	293496245: {"floors": 2, "garage_near": Vector2(662.9, 545.2), "stone": "pink_tuff"},
}

## Garages cut into buildings by BUILDING_FIXES (metres).
const GATE_HEIGHT := 2.3
const TRANSOM_HEIGHT := 0.5
const GARAGE_DEPTH := 7.5
const GARAGE_MARGIN := 0.3 ## how much wider the room is than its door, each side
const GARAGE_RAMP := 1.6

const PLAIN_BUILDINGS := ["garage", "garages", "shed", "hut", "roof", "greenhouse", "barn",
	"ruins", "carport", "cowshed", "sty", "stable", "kiosk", "service", "transformer_tower"]


class MeshBuf:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()

	func add(p: Vector3, nrm: Vector3, col: Color, t: Vector2, t2 := Vector2.ZERO) -> int:
		v.append(p)
		n.append(nrm)
		c.append(col)
		uv.append(t)
		uv2.append(t2)
		return v.size() - 1

	func tri(a: int, b: int, d: int) -> void:
		idx.append(a)
		idx.append(b)
		idx.append(d)

	## Adds a triangle wound so that it faces +Y.
	func tri_up(a: int, b: int, d: int) -> void:
		var pa := v[a]
		var pb := v[b]
		var pd := v[d]
		if (pb.x - pa.x) * (pd.z - pa.z) - (pb.z - pa.z) * (pd.x - pa.x) > 0.0:
			tri(a, b, d)
		else:
			tri(a, d, b)

	func commit(mat: Material) -> ArrayMesh:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = n
		arr[Mesh.ARRAY_COLOR] = c
		arr[Mesh.ARRAY_TEX_UV] = uv
		arr[Mesh.ARRAY_TEX_UV2] = uv2
		arr[Mesh.ARRAY_INDEX] = idx
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		m.surface_set_material(0, mat)
		return m


var mx := 0.0 # metres per degree of longitude
var mz := 0.0 # metres per degree of latitude
var elev := PackedFloat32Array()
var hgt := PackedFloat32Array()
var base_elev := 0.0

var roads: Array[Dictionary] = []
var waters: Array[PackedVector2Array] = []
var buildings: Array[Dictionary] = []
var areas: Array[Dictionary] = []
var tree_nodes: Array[Vector2] = []

var cls := PackedByteArray()
var mask := PackedByteArray()
var trees := {} # Vector3i(cx, cz, type) -> Array of [Vector2 pos, scale, tint]
var tree_count := 0


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Run without --headless: MultiMesh tree data is not kept by the headless renderer.")
		quit(1)
		return
	var t0 := Time.get_ticks_msec()
	var p := deg_to_rad(LAT0)
	mz = 111132.92 - 559.82 * cos(2.0 * p) + 1.175 * cos(4.0 * p)
	mx = 111412.84 * cos(p) - 93.5 * cos(3.0 * p)

	_load_elev()
	_make_grid()
	_parse_osm()
	_pair_carriageways()
	_level_roads()
	_rasterize()
	_scatter_trees()

	var root := Node3D.new()
	root.name = "World"
	root.set_meta("origin_lat", LAT0)
	root.set_meta("origin_lon", LON0)
	root.set_meta("base_elevation", base_elev)
	_build_terrain(root)
	_build_roads(root)
	_build_water(root)
	_build_buildings(root)
	_build_trees(root)
	_build_spawn(root)
	_build_minimap()
	_own(root, root)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
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


func _own(node: Node, root: Node) -> void:
	for child in node.get_children():
		child.owner = root
		_own(child, root)


# --- projection & elevation -------------------------------------------------

func _local(lat: float, lon: float) -> Vector2:
	return Vector2((lon - LON0) * mx, -(lat - LAT0) * mz)


func _load_elev() -> void:
	elev.resize(EW * EW)
	for ty in TILES:
		for tx in TILES:
			var path := "res://data/elev/%d_%d_%d.png" % [ELEV_ZOOM, TILE_X0 + tx, TILE_Y0 + ty]
			var img := Image.load_from_file(ProjectSettings.globalize_path(path))
			img.convert(Image.FORMAT_RGB8)
			var d := img.get_data()
			for y in 256:
				var row := (ty * 256 + y) * EW + tx * 256
				for x in 256:
					var o := (y * 256 + x) * 3
					elev[row + x] = d[o] * 256.0 + d[o + 1] + d[o + 2] / 256.0 - 32768.0


func _elev_at(lat: float, lon: float) -> float:
	var n := float(1 << ELEV_ZOOM) * 256.0
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


func _make_grid() -> void:
	hgt.resize(GRID_N * GRID_N)
	for j in GRID_N:
		var lat := LAT0 - (-HALF + j * CELL) / mz
		for i in GRID_N:
			var lon := LON0 + (-HALF + i * CELL) / mx
			hgt[j * GRID_N + i] = _elev_at(lat, lon)
	# The source is ~30 m data with 1 m steps; blur it so slopes are drivable.
	var tmp := PackedFloat32Array()
	tmp.resize(hgt.size())
	for _pass in 3:
		for j in GRID_N:
			for i in GRID_N:
				var a := hgt[j * GRID_N + maxi(i - 1, 0)]
				var b := hgt[j * GRID_N + mini(i + 1, GRID_N - 1)]
				tmp[j * GRID_N + i] = (a + 2.0 * hgt[j * GRID_N + i] + b) * 0.25
		for j in GRID_N:
			for i in GRID_N:
				var a := tmp[maxi(j - 1, 0) * GRID_N + i]
				var b := tmp[mini(j + 1, GRID_N - 1) * GRID_N + i]
				hgt[j * GRID_N + i] = (a + 2.0 * tmp[j * GRID_N + i] + b) * 0.25
	base_elev = hgt[(GRID_N / 2) * GRID_N + GRID_N / 2]
	var lo := INF
	var hi := -INF
	for k in hgt.size():
		hgt[k] -= base_elev
		lo = minf(lo, hgt[k])
		hi = maxf(hi, hgt[k])
	print("Terrain: centre %.0f m a.s.l., relief %.0f..%.0f m" % [base_elev, lo, hi])


## Height of the terrain mesh at a local position (exact on its triangles).
func _h(x: float, z: float) -> float:
	var gx := clampf((x + HALF) / CELL, 0.0, GRID_N - 1.0001)
	var gz := clampf((z + HALF) / CELL, 0.0, GRID_N - 1.0001)
	var i := int(gx)
	var j := int(gz)
	var fx := gx - i
	var fz := gz - j
	var h00 := hgt[j * GRID_N + i]
	var h10 := hgt[j * GRID_N + i + 1]
	var h01 := hgt[(j + 1) * GRID_N + i]
	var h11 := hgt[(j + 1) * GRID_N + i + 1]
	if fx + fz <= 1.0:
		return h00 + fx * (h10 - h00) + fz * (h01 - h00)
	return h11 + (1.0 - fx) * (h01 - h11) + (1.0 - fz) * (h10 - h11)


func _inside(p: Vector2, margin := 2.0) -> bool:
	return absf(p.x) < HALF - margin and absf(p.y) < HALF - margin


# --- OSM --------------------------------------------------------------------

func _geom(g: Variant) -> PackedVector2Array:
	var out := PackedVector2Array()
	if g is Array:
		for pt in g:
			if pt is Dictionary:
				out.append(_local(pt["lat"], pt["lon"]))
	return out


## Splits a polyline into runs inside the terrain, subdivided to ROAD_STEP.
func _runs(pts: PackedVector2Array) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var cur := PackedVector2Array()
	for k in pts.size():
		if not _inside(pts[k]):
			if cur.size() >= 2:
				out.append(cur)
			cur = PackedVector2Array()
			continue
		if not cur.is_empty():
			var a := cur[cur.size() - 1]
			var d := pts[k] - a
			var steps := int(ceil(d.length() / ROAD_STEP))
			if steps == 0:
				continue
			for s in range(1, steps):
				cur.append(a + d * (float(s) / steps))
		cur.append(pts[k])
	if cur.size() >= 2:
		out.append(cur)
	return out


func _parse_osm() -> void:
	var text := FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://data/osm.json"))
	var data: Dictionary = JSON.parse_string(text)
	for e: Dictionary in data["elements"]:
		var tags: Dictionary = e.get("tags", {})
		var type: String = e["type"]
		if type == "node":
			if tags.get("natural", "") == "tree":
				tree_nodes.append(_local(e["lat"], e["lon"]))
			continue
		if type == "relation":
			if tags.has("building"):
				for m: Dictionary in e.get("members", []):
					if m.get("type", "") == "way" and m.get("role", "") != "inner":
						_add_building(_geom(m.get("geometry")), tags, int(e["id"]) + int(m["ref"]))
			continue
		var pts := _geom(e.get("geometry"))
		if pts.size() < 2:
			continue
		var closed := pts.size() >= 4 and pts[0].distance_to(pts[pts.size() - 1]) < 0.01
		if tags.has("building"):
			_add_building(pts, tags, int(e["id"]))
		elif tags.has("highway"):
			if tags.get("area", "no") != "yes":
				_add_road(pts, tags)
		elif tags.get("railway", "") in ["rail", "light_rail", "narrow_gauge"]:
			for run in _runs(pts):
				roads.append({"pts": run, "hw": 1.6, "prio": 0, "kind": 3, "marked": false})
		elif tags.get("waterway", "") in ["stream", "river", "canal", "drain", "ditch"]:
			waters.append_array(_runs(pts))
		elif closed:
			var c := 0
			for key in ["natural", "landuse", "leisure"]:
				c = AREA_CLASS.get(tags.get(key, ""), 0)
				if c != 0:
					break
			if c != 0:
				pts.remove_at(pts.size() - 1)
				areas.append({"poly": pts, "cls": c, "area": absf(_signed_area(pts))})
	print("OSM: %d road runs, %d buildings, %d areas, %d waterways" % [roads.size(), buildings.size(), areas.size(), waters.size()])


func _add_road(pts: PackedVector2Array, tags: Dictionary) -> void:
	var spec: Array = ROAD_TYPES.get(tags["highway"], [])
	if spec.is_empty():
		return
	var width: float = spec[0]
	var kind: int = spec[2]
	if tags.has("width") and str(tags["width"]).to_float() > 1.0:
		width = clampf(str(tags["width"]).to_float(), 1.5, 30.0)
	var oneway: bool = tags.get("oneway", "no") in ["yes", "true", "1", "-1"]
	var lanes := int(str(tags.get("lanes", "0")).to_float())
	if tags.has("width") and str(tags["width"]).to_float() > 1.0:
		width = clampf(str(tags["width"]).to_float(), 1.5, 30.0)
	elif lanes > 0 and kind == 0:
		# A one-way way is a single carriageway, so it is only as wide as its lanes.
		width = lanes * 3.5 if oneway else maxf(width, lanes * 3.3)
	if lanes <= 0:
		lanes = 1 if oneway else 2
	if kind == 0 and tags.get("surface", "") in UNPAVED:
		kind = 1
	for run in _runs(pts):
		roads.append({"pts": run, "hw": width * 0.5, "prio": spec[1], "kind": kind,
			"marked": spec[3] and kind == 0, "lanes": lanes, "oneway": oneway})


## Dual carriageways are mapped as two one-way ways, usually closer together than
## their real width, so the two ribbons would overlap. Slide each one sideways
## until the pair sits edge to edge.
func _pair_carriageways() -> void:
	var moved := {}
	for ai in roads.size():
		var a := roads[ai]
		if not a.get("oneway", false) or a["kind"] != 0:
			continue
		var pts: PackedVector2Array = a["pts"]
		var out := pts.duplicate()
		for k in pts.size():
			var p := pts[k]
			var dir := (pts[mini(k + 1, pts.size() - 1)] - pts[maxi(k - 1, 0)]).normalized()
			var best := INF
			var best_q := Vector2.ZERO
			var best_hw := 0.0
			for bi in roads.size():
				var b := roads[bi]
				if bi == ai or not b.get("oneway", false) or b["kind"] != 0:
					continue
				var reach: float = a["hw"] + b["hw"] + 3.0
				var bp: PackedVector2Array = b["pts"]
				for j in bp.size() - 1:
					if absf(bp[j].x - p.x) > reach + ROAD_STEP or absf(bp[j].y - p.y) > reach + ROAD_STEP:
						continue
					# Only the carriageway running the other way counts.
					if (bp[j + 1] - bp[j]).normalized().dot(dir) > -0.5:
						continue
					var q := Geometry2D.get_closest_point_to_segment(p, bp[j], bp[j + 1])
					var d := p.distance_to(q)
					if d < best and d < reach:
						best = d
						best_q = q
						best_hw = b["hw"]
			if best > 0.5 and best < INF:
				out[k] = p + (p - best_q) / best * (a["hw"] + best_hw - best) * 0.5
		moved[ai] = out
	for ai: int in moved:
		roads[ai]["pts"] = moved[ai]


func _signed_area(poly: PackedVector2Array) -> float:
	var s := 0.0
	var n := poly.size()
	for k in n:
		var a := poly[k]
		var b := poly[(k + 1) % n]
		s += a.x * b.y - b.x * a.y
	return s * 0.5


func _add_building(pts: PackedVector2Array, tags: Dictionary, id: int) -> void:
	if pts.size() < 4 or pts[0].distance_to(pts[pts.size() - 1]) > 0.01:
		return
	pts.remove_at(pts.size() - 1)
	for p in pts:
		if not _inside(p, CELL):
			return
	var area := _signed_area(pts)
	if area < 0.0:
		pts.reverse()
		area = -area
	if area < 6.0:
		return
	buildings.append({"poly": pts, "tags": tags, "id": id, "area": area})


# --- terrain conditioning ---------------------------------------------------

## Flattens the terrain across each road so that roads are level side to side.
func _level_roads() -> void:
	var sumw := PackedFloat32Array()
	var sumh := PackedFloat32Array()
	var maxw := PackedFloat32Array()
	sumw.resize(hgt.size())
	sumh.resize(hgt.size())
	maxw.resize(hgt.size())
	for road in roads:
		if road["kind"] == 2:
			continue
		var pts: PackedVector2Array = road["pts"]
		var n := pts.size()
		var hc := PackedFloat32Array()
		hc.resize(n)
		for k in n:
			hc[k] = _h(pts[k].x, pts[k].y)
		for _pass in 2:
			var sm := hc.duplicate()
			for k in range(1, n - 1):
				var acc := 0.0
				var cnt := 0
				for q in range(maxi(0, k - 3), mini(n, k + 4)):
					acc += hc[q]
					cnt += 1
				sm[k] = acc / cnt
			hc = sm
		var r_in: float = road["hw"] + 6.0
		var r_out := r_in + 2.0 * CELL
		for k in range(0, n, 2):
			var p := pts[k]
			var i0 := maxi(0, int(floor((p.x - r_out + HALF) / CELL)))
			var i1 := mini(GRID_N - 1, int(ceil((p.x + r_out + HALF) / CELL)))
			var j0 := maxi(0, int(floor((p.y - r_out + HALF) / CELL)))
			var j1 := mini(GRID_N - 1, int(ceil((p.y + r_out + HALF) / CELL)))
			for j in range(j0, j1 + 1):
				for i in range(i0, i1 + 1):
					var d := Vector2(-HALF + i * CELL, -HALF + j * CELL).distance_to(p)
					if d >= r_out:
						continue
					var w := 1.0 - smoothstep(r_in, r_out, d)
					var g := j * GRID_N + i
					sumw[g] += w
					sumh[g] += w * hc[k]
					maxw[g] = maxf(maxw[g], w)
	for g in hgt.size():
		if sumw[g] > 0.0:
			hgt[g] = lerpf(hgt[g], sumh[g] / sumw[g], maxw[g])


func _px(p: Vector2, size := TEX_N) -> Vector2:
	return (p + Vector2(HALF, HALF)) * (size / (2.0 * HALF))


func _fill_poly(poly: PackedVector2Array, buf: PackedByteArray, val: int, size := TEX_N) -> void:
	var n := poly.size()
	var ymin := INF
	var ymax := -INF
	var pp := PackedVector2Array()
	for p in poly:
		var q := _px(p, size)
		pp.append(q)
		ymin = minf(ymin, q.y)
		ymax = maxf(ymax, q.y)
	var y0 := maxi(0, int(floor(ymin)))
	var y1 := mini(size - 1, int(ceil(ymax)))
	for y in range(y0, y1 + 1):
		var yc := y + 0.5
		var xs := PackedFloat32Array()
		for k in n:
			var a := pp[k]
			var b := pp[(k + 1) % n]
			if (a.y <= yc) != (b.y <= yc):
				xs.append(a.x + (yc - a.y) / (b.y - a.y) * (b.x - a.x))
		xs.sort()
		for s in range(0, xs.size() - 1, 2):
			var xa := maxi(0, int(ceil(xs[s] - 0.5)))
			var xb := mini(size - 1, int(floor(xs[s + 1] - 0.5)))
			for x in range(xa, xb + 1):
				buf[y * size + x] = val


func _stamp(p: Vector2, radius: float, val: int, buf: PackedByteArray, size := TEX_N) -> void:
	var q := _px(p, size)
	var r := radius * size / (2.0 * HALF)
	for y in range(maxi(0, int(q.y - r)), mini(size - 1, int(q.y + r)) + 1):
		for x in range(maxi(0, int(q.x - r)), mini(size - 1, int(q.x + r)) + 1):
			if Vector2(x + 0.5, y + 0.5).distance_to(q) <= r + 0.5:
				buf[y * size + x] = val


func _rasterize() -> void:
	cls.resize(TEX_N * TEX_N)
	mask.resize(TEX_N * TEX_N)
	areas.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["area"] > b["area"])
	for a in areas:
		_fill_poly(a["poly"], cls, a["cls"])
	for road in roads:
		for p: Vector2 in road["pts"]:
			_stamp(p, road["hw"] + 1.5, MASK_ROAD, mask)
	for w in waters:
		for p in w:
			_stamp(p, 1.5, MASK_WATER, mask)
	for b in buildings:
		_fill_poly(b["poly"], mask, MASK_BUILDING)


func _ground_texture() -> ImageTexture:
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.02
	noise.fractal_octaves = 4
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var yard := Color(0.50, 0.47, 0.42)
	var shoulder := Color(0.47, 0.44, 0.38)
	var data := PackedByteArray()
	data.resize(TEX_N * TEX_N * 3)
	for y in TEX_N:
		for x in TEX_N:
			var k := y * TEX_N + x
			var col: Color = AREA_COLORS[cls[k]]
			match mask[k]:
				MASK_BUILDING: col = col.lerp(yard, 0.6)
				MASK_ROAD: col = col.lerp(shoulder, 0.5)
				MASK_WATER: col = col.lerp(AREA_COLORS[5], 0.6)
			var f := 1.0 + 0.16 * noise.get_noise_2d(x, y) + rng.randf_range(-0.03, 0.03)
			data[k * 3] = int(clampf(col.r * f, 0.0, 1.0) * 255.0)
			data[k * 3 + 1] = int(clampf(col.g * f, 0.0, 1.0) * 255.0)
			data[k * 3 + 2] = int(clampf(col.b * f, 0.0, 1.0) * 255.0)
	var img := Image.create_from_data(TEX_N, TEX_N, false, Image.FORMAT_RGB8, data)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# --- terrain ----------------------------------------------------------------

func _build_terrain(root: Node3D) -> void:
	var body := StaticBody3D.new()
	body.name = "Terrain"
	root.add_child(body)

	var mat := ShaderMaterial.new()
	mat.shader = load("res://world/shaders/terrain.gdshader")
	mat.set_shader_parameter("ground", _ground_texture())

	var per := (GRID_N - 1) / TERRAIN_CHUNKS
	for cj in TERRAIN_CHUNKS:
		for ci in TERRAIN_CHUNKS:
			var buf := MeshBuf.new()
			for j in range(cj * per, (cj + 1) * per + 1):
				for i in range(ci * per, (ci + 1) * per + 1):
					var hl := hgt[j * GRID_N + maxi(i - 1, 0)]
					var hr := hgt[j * GRID_N + mini(i + 1, GRID_N - 1)]
					var hu := hgt[maxi(j - 1, 0) * GRID_N + i]
					var hd := hgt[mini(j + 1, GRID_N - 1) * GRID_N + i]
					var nrm := Vector3(hl - hr, 2.0 * CELL, hu - hd).normalized()
					buf.add(Vector3(-HALF + i * CELL, hgt[j * GRID_N + i], -HALF + j * CELL), nrm,
						Color.WHITE, Vector2(float(i) / (GRID_N - 1), float(j) / (GRID_N - 1)))
			var w := per + 1
			for j in per:
				for i in per:
					var a := j * w + i
					buf.tri(a, a + 1, a + w)
					buf.tri(a + 1, a + w + 1, a + w)
			var mi := MeshInstance3D.new()
			mi.name = "Chunk_%d_%d" % [ci, cj]
			mi.mesh = buf.commit(mat)
			body.add_child(mi)

	var shape := HeightMapShape3D.new()
	shape.map_width = GRID_N
	shape.map_depth = GRID_N
	shape.map_data = hgt
	var cs := CollisionShape3D.new()
	cs.name = "CollisionShape3D"
	cs.shape = shape
	cs.scale = Vector3(CELL, 1.0, CELL)
	body.add_child(cs)


# --- roads & water ----------------------------------------------------------

func _chunk_buf(chunks: Dictionary, p: Vector2) -> MeshBuf:
	var key := Vector2i(int(floor(p.x / OBJ_CHUNK)), int(floor(p.y / OBJ_CHUNK)))
	if not chunks.has(key):
		chunks[key] = MeshBuf.new()
	return chunks[key]


func _p3(p: Vector2, yoff: float) -> Vector3:
	return Vector3(p.x, _h(p.x, p.y) + yoff, p.y)


## Drapes a ribbon of the given half width over the terrain.
func _strip(pts: PackedVector2Array, hw: float, yoff: float, col: Color, chunks: Dictionary, caps: bool, marks := 0.0) -> void:
	var n := pts.size()
	var left := PackedVector3Array()
	var mid := PackedVector3Array()
	var right := PackedVector3Array()
	var dist := PackedFloat32Array()
	var run := 0.0
	var t := Vector2.RIGHT
	for k in n:
		var seg := (pts[mini(k + 1, n - 1)] - pts[maxi(k - 1, 0)])
		var fwd := (pts[mini(k + 1, n - 1)] - pts[k]) if k < n - 1 else (pts[k] - pts[k - 1])
		if seg.length() > 0.001:
			t = seg.normalized()
		var mitre := 1.0
		if fwd.length() > 0.001:
			mitre = 1.0 / maxf(0.6, t.dot(fwd.normalized()))
		var side := Vector2(-t.y, t.x) * hw * mitre
		if k > 0:
			run += pts[k].distance_to(pts[k - 1])
		left.append(_p3(pts[k] + side, yoff))
		mid.append(_p3(pts[k], yoff))
		right.append(_p3(pts[k] - side, yoff))
		dist.append(run)
	var width := Vector2(hw * 2.0, marks)
	for k in n - 1:
		var buf := _chunk_buf(chunks, (pts[k] + pts[k + 1]) * 0.5)
		var l0 := buf.add(left[k], Vector3.UP, col, Vector2(0.0, dist[k]), width)
		var m0 := buf.add(mid[k], Vector3.UP, col, Vector2(0.5, dist[k]), width)
		var r0 := buf.add(right[k], Vector3.UP, col, Vector2(1.0, dist[k]), width)
		var l1 := buf.add(left[k + 1], Vector3.UP, col, Vector2(0.0, dist[k + 1]), width)
		var m1 := buf.add(mid[k + 1], Vector3.UP, col, Vector2(0.5, dist[k + 1]), width)
		var r1 := buf.add(right[k + 1], Vector3.UP, col, Vector2(1.0, dist[k + 1]), width)
		buf.tri_up(l0, m0, l1)
		buf.tri_up(m0, m1, l1)
		buf.tri_up(m0, r0, m1)
		buf.tri_up(r0, r1, m1)
	if caps:
		# Caps carry the road class but never markings (see the alpha code in _build_roads).
		var plain := Color(col.r, col.g, col.b, col.a - 0.5 if col.a >= 0.5 else col.a)
		for end: Vector2 in [pts[0], pts[n - 1]]:
			var buf := _chunk_buf(chunks, end)
			var c := buf.add(_p3(end, yoff), Vector3.UP, plain, Vector2.ZERO, width)
			var rim := PackedInt32Array()
			for s in 10:
				var a := TAU * s / 10.0
				rim.append(buf.add(_p3(end + Vector2(cos(a), sin(a)) * hw, yoff), Vector3.UP, plain, Vector2.ZERO, width))
			for s in 10:
				buf.tri_up(c, rim[s], rim[(s + 1) % 10])


func _commit_chunks(chunks: Dictionary, parent: Node3D, mat: Material, prefix: String) -> PackedVector3Array:
	var faces := PackedVector3Array()
	for key: Vector2i in chunks:
		var buf: MeshBuf = chunks[key]
		if buf.idx.is_empty():
			continue
		var mi := MeshInstance3D.new()
		mi.name = "%s_%d_%d" % [prefix, key.x, key.y]
		mi.mesh = buf.commit(mat)
		parent.add_child(mi)
		for i in buf.idx:
			faces.append(buf.v[i])
	return faces


func _add_trimesh(body: StaticBody3D, faces: PackedVector3Array, node_name: String) -> void:
	if faces.is_empty():
		return
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.name = node_name
	cs.shape = shape
	body.add_child(cs)


func _build_roads(root: Node3D) -> void:
	var body := StaticBody3D.new()
	body.name = "Roads"
	root.add_child(body)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://world/shaders/road.gdshader")
	var chunks := {}
	for road in roads:
		var col: Color
		match road["kind"]:
			1: col = Color(0.50, 0.42, 0.30)
			2: col = Color(0.62, 0.58, 0.52)
			3: col = Color(0.33, 0.29, 0.26)
			_:
				if road["prio"] >= 3:
					col = Color(0.21, 0.21, 0.22)
				elif road["prio"] == 2:
					col = Color(0.28, 0.28, 0.28)
				else:
					col = Color(0.34, 0.33, 0.32)
		col = col.srgb_to_linear()
		# Alpha carries the road class (0..7) in sixteenths, plus a half when the road has markings.
		col.a = (road["prio"] + (8 if road["marked"] else 0)) / 16.0
		# Roads lie almost flush with the ground; the road shader draws them slightly
		# nearer the camera so the terrain cannot show through. Higher classes sit a
		# few millimetres higher and are drawn on top at junctions.
		# Lane count for the markings; negative means all lanes run the same way.
		var marks: float = road.get("lanes", 2) * (-1.0 if road.get("oneway", false) else 1.0)
		_strip(road["pts"], road["hw"], 0.02 + 0.005 * road["prio"], col, chunks, true, marks)
	var faces := _commit_chunks(chunks, body, mat, "Roads")
	for child in body.get_children():
		if child is MeshInstance3D:
			child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add_trimesh(body, faces, "CollisionShape3D")


func _build_water(root: Node3D) -> void:
	if waters.is_empty():
		return
	var node := Node3D.new()
	node.name = "Water"
	root.add_child(node)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.30, 0.38)
	mat.roughness = 0.12
	mat.vertex_color_use_as_albedo = false
	var chunks := {}
	for w in waters:
		_strip(w, 1.2, 0.05, Color.WHITE, chunks, false)
	_commit_chunks(chunks, node, mat, "Water")


# --- buildings --------------------------------------------------------------

func _building_height(tags: Dictionary, area: float, rng: RandomNumberGenerator) -> float:
	if tags.has("height") and str(tags["height"]).to_float() > 1.0:
		return str(tags["height"]).to_float()
	if tags.has("building:levels") and str(tags["building:levels"]).to_float() > 0.0:
		return str(tags["building:levels"]).to_float() * 3.0 + 0.6
	match tags["building"]:
		"apartments", "dormitory", "hotel":
			return 3.0 * rng.randi_range(4, 6) + 0.6
		"church", "chapel", "cathedral", "monastery":
			return rng.randf_range(10.0, 14.0)
		"school", "university", "hospital", "public", "civic", "government", "office":
			return rng.randf_range(7.0, 10.0)
		"industrial", "warehouse", "factory", "hangar":
			return rng.randf_range(6.0, 9.0)
		"commercial", "retail", "supermarket":
			return rng.randf_range(4.5, 6.5)
	if tags["building"] in PLAIN_BUILDINGS:
		return rng.randf_range(2.6, 3.4)
	if area < 45.0:
		return rng.randf_range(2.6, 3.4)
	if area > 700.0:
		return rng.randf_range(6.5, 10.0)
	return 3.6 if rng.randf() < 0.55 else 6.6


func _build_buildings(root: Node3D) -> void:
	var body := StaticBody3D.new()
	body.name = "Buildings"
	root.add_child(body)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://world/shaders/building.gdshader")
	var chunks := {}
	var rng := RandomNumberGenerator.new()
	for b in buildings:
		var poly: PackedVector2Array = b["poly"]
		var tags: Dictionary = b["tags"]
		rng.seed = b["id"]
		var height := _building_height(tags, b["area"], rng)
		var n := poly.size()
		var ymin := INF
		var ymax := -INF
		var centre := Vector2.ZERO
		for p in poly:
			var y := _h(p.x, p.y)
			ymin = minf(ymin, y)
			ymax = maxf(ymax, y)
			centre += p / n
		var base := ymin - 0.6
		var top := ymax + height
		var plain: bool = tags["building"] in PLAIN_BUILDINGS or height < 3.2
		var wall: Color = WALL_COLORS[rng.randi() % WALL_COLORS.size()].srgb_to_linear()
		wall = wall * rng.randf_range(0.88, 1.06)
		wall.a = 0.5 if plain else 1.0
		# Hand-made corrections for single buildings.
		var fix: Dictionary = BUILDING_FIXES.get(b["id"], {})
		if fix.has("floors"):
			height = fix["floors"] * FLOOR_HEIGHT + 0.6
			top = ymax + height
			wall.a = 1.0
		var garage_wall := -1
		var garage_column := 0
		if fix.has("garage_near"):
			# The door goes in the window column nearest to the given spot.
			var spot: Vector2 = fix["garage_near"]
			var nearest := INF
			for k in n:
				var q := Geometry2D.get_closest_point_to_segment(spot, poly[k], poly[(k + 1) % n])
				if spot.distance_to(q) < nearest:
					nearest = spot.distance_to(q)
					garage_wall = k
					var length := poly[k].distance_to(poly[(k + 1) % n])
					var columns := maxi(1, int(length / WINDOW_SPACING))
					garage_column = clampi(int(poly[k].distance_to(q) / length * columns), 0, columns - 1)
		var roof: Color = ROOF_COLORS[rng.randi() % ROOF_COLORS.size()].srgb_to_linear()
		roof.a = 0.0
		var buf := _chunk_buf(chunks, centre)
		for k in n:
			var a := poly[k]
			var c := poly[(k + 1) % n]
			var d := c - a
			var length := d.length()
			if length < 0.05:
				continue
			var nrm := Vector3(d.y, 0.0, -d.x) / length
			# A negative height tells building.gdshader the wall is tuff masonry.
			var dims := Vector2(length, -height if fix.get("stone", "") == "pink_tuff" else height)
			if k != garage_wall:
				_wall_piece(buf, a, d / length, 0.0, length, base, top, top, wall, dims)
				continue
			# A wall with a garage carries the column of its door in the alpha (see building.gdshader).
			var face := wall
			face.a = 0.78 + 0.02 * garage_column
			_add_garage(root, buf, b["id"], a, d / length, length, garage_column, base, top, face, dims)
		var tris := Geometry2D.triangulate_polygon(poly)
		var first := buf.v.size()
		for p in poly:
			buf.add(Vector3(p.x, top, p.y), Vector3.UP, roof, Vector2.ZERO)
		for k in range(0, tris.size(), 3):
			buf.tri_up(first + tris[k], first + tris[k + 1], first + tris[k + 2])
	var k := 0
	for key: Vector2i in chunks:
		var one := {key: chunks[key]}
		_add_trimesh(body, _commit_chunks(one, body, mat, "Buildings"), "CollisionShape3D_%d" % k)
		k += 1



# --- garages ----------------------------------------------------------------

## A rectangle of outside wall: from u0 to u1 metres along the wall that starts
## at `a` and runs along `along`, between heights y0 and y1.
func _wall_piece(buf: MeshBuf, a: Vector2, along: Vector2, u0: float, u1: float, y0: float, y1: float,
		top: float, col: Color, dims: Vector2) -> void:
	if u1 - u0 < 0.001 or y1 - y0 < 0.001:
		return
	var nrm := Vector3(along.y, 0.0, -along.x)
	var p0 := a + along * u0
	var p1 := a + along * u1
	var v0 := buf.add(Vector3(p0.x, y0, p0.y), nrm, col, Vector2(u0, top - y0), dims)
	var v1 := buf.add(Vector3(p1.x, y0, p1.y), nrm, col, Vector2(u1, top - y0), dims)
	var v2 := buf.add(Vector3(p1.x, y1, p1.y), nrm, col, Vector2(u1, top - y1), dims)
	var v3 := buf.add(Vector3(p0.x, y1, p0.y), nrm, col, Vector2(u0, top - y1), dims)
	buf.tri(v0, v1, v2)
	buf.tri(v0, v2, v3)


## A flat four-cornered face looking along `nrm`, whatever order the corners come in.
func _quad(buf: MeshBuf, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, nrm: Vector3, col: Color,
		uv0 := Vector2.ZERO, uv1 := Vector2.ZERO, uv2 := Vector2.ZERO, uv3 := Vector2.ZERO, extra := Vector2.ZERO) -> void:
	var v0 := buf.add(p0, nrm, col, uv0, extra)
	var v1 := buf.add(p1, nrm, col, uv1, extra)
	var v2 := buf.add(p2, nrm, col, uv2, extra)
	var v3 := buf.add(p3, nrm, col, uv3, extra)
	# Front faces wind clockwise, which puts (p2 - p0) x (p1 - p0) along the normal.
	if (p2 - p0).cross(p1 - p0).dot(nrm) > 0.0:
		buf.tri(v0, v1, v2)
		buf.tri(v0, v2, v3)
	else:
		buf.tri(v0, v2, v1)
		buf.tri(v0, v3, v2)


## Builds the wall around a garage doorway, the room behind it, a ramp up to its
## floor and the gate itself. The doorway takes the place of one window column.
func _add_garage(root: Node3D, buf: MeshBuf, id: int, a: Vector2, along: Vector2, length: float, column: int,
		base: float, top: float, face: Color, dims: Vector2) -> void:
	var out := Vector2(along.y, -along.x)
	var out3 := Vector3(out.x, 0.0, out.y)
	var along3 := Vector3(along.x, 0.0, along.y)
	var column_width := length / maxi(1, int(length / WINDOW_SPACING))
	var u0 := (column + 0.1) * column_width
	var u1 := (column + 0.9) * column_width
	var in0 := maxf(u0 - GARAGE_MARGIN, 0.05)
	var in1 := minf(u1 + GARAGE_MARGIN, length - 0.05)

	# The floor is level, just above the highest ground under the room.
	var floor_y := -INF
	for u: float in [in0, (in0 + in1) * 0.5, in1]:
		for depth: float in [0.0, GARAGE_DEPTH * 0.5, GARAGE_DEPTH]:
			var p := a + along * u - out * depth
			floor_y = maxf(floor_y, _h(p.x, p.y))
	floor_y += 0.04
	var lintel := floor_y + GATE_HEIGHT + TRANSOM_HEIGHT

	# The wall, with the doorway left open.
	_wall_piece(buf, a, along, 0.0, u0, base, top, top, face, dims)
	_wall_piece(buf, a, along, u1, length, base, top, top, face, dims)
	_wall_piece(buf, a, along, u0, u1, lintel, top, top, face, dims)
	_wall_piece(buf, a, along, u0, u1, base, floor_y, top, face, dims)

	# The room. Corner at u metres along the wall, `depth` metres in, height y.
	var corner := func(u: float, depth: float, y: float) -> Vector3:
		var p := a + along * u - out * depth
		return Vector3(p.x, y, p.y)
	var walls := Color(0.62, 0.61, 0.58).srgb_to_linear()
	walls.a = 0.5
	var concrete := Color(0.36, 0.36, 0.35).srgb_to_linear()
	concrete.a = 0.5
	var d := GARAGE_DEPTH
	_quad(buf, corner.call(in0, 0.0, floor_y), corner.call(in1, 0.0, floor_y), corner.call(in1, d, floor_y), corner.call(in0, d, floor_y), Vector3.UP, concrete)
	_quad(buf, corner.call(in0, 0.0, lintel), corner.call(in1, 0.0, lintel), corner.call(in1, d, lintel), corner.call(in0, d, lintel), Vector3.DOWN, walls)
	_quad(buf, corner.call(in0, d, floor_y), corner.call(in1, d, floor_y), corner.call(in1, d, lintel), corner.call(in0, d, lintel), out3, walls)
	_quad(buf, corner.call(in0, 0.0, floor_y), corner.call(in0, d, floor_y), corner.call(in0, d, lintel), corner.call(in0, 0.0, lintel), along3, walls)
	_quad(buf, corner.call(in1, 0.0, floor_y), corner.call(in1, d, floor_y), corner.call(in1, d, lintel), corner.call(in1, 0.0, lintel), -along3, walls)
	_quad(buf, corner.call(in0, 0.0, floor_y), corner.call(u0, 0.0, floor_y), corner.call(u0, 0.0, lintel), corner.call(in0, 0.0, lintel), -out3, walls)
	_quad(buf, corner.call(u1, 0.0, floor_y), corner.call(in1, 0.0, floor_y), corner.call(in1, 0.0, lintel), corner.call(u1, 0.0, lintel), -out3, walls)

	# A short ramp from the ground outside up to the floor.
	var r0: Vector3 = corner.call(u0 - 0.3, -GARAGE_RAMP, 0.0)
	var r1: Vector3 = corner.call(u1 + 0.3, -GARAGE_RAMP, 0.0)
	r0.y = _h(r0.x, r0.z) + 0.03
	r1.y = _h(r1.x, r1.z) + 0.03
	_quad(buf, corner.call(u0 - 0.3, 0.0, floor_y), corner.call(u1 + 0.3, 0.0, floor_y), r1, r0, Vector3.UP, concrete)

	_add_gate(root, id, a + along * ((u0 + u1) * 0.5), floor_y, along3, out3, u1 - u0)


## The gate in a garage doorway: two leaves that swing outwards under a fixed
## glazed transom. `at` is the middle of the threshold.
func _add_gate(root: Node3D, id: int, at: Vector2, floor_y: float, along3: Vector3, out3: Vector3, width: float) -> void:
	var gates := root.get_node_or_null("Gates")
	if gates == null:
		gates = Node3D.new()
		gates.name = "Gates"
		root.add_child(gates)
	var gate := Node3D.new()
	gate.name = "Gate_%d" % id
	gate.set_script(load("res://world/garage_gate.gd"))
	# Seen from outside: +X to the right, +Z towards the viewer.
	gate.transform = Transform3D(Basis(-along3, Vector3.UP, out3), Vector3(at.x, floor_y, at.y) + out3 * 0.02)
	gates.add_child(gate)

	var shader: Shader = load("res://world/shaders/gate.gdshader")
	var painted := ShaderMaterial.new()
	painted.shader = shader
	painted.set_shader_parameter("part", 0)
	var glazed := ShaderMaterial.new()
	glazed.shader = shader
	glazed.set_shader_parameter("part", 1)

	var half := width * 0.5
	var size := Vector2(width, GATE_HEIGHT)
	# Each leaf hangs from a pivot at its outer edge; UV.x runs 0..1 across the whole gate.
	for side: float in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.name = "LeafL" if side < 0.0 else "LeafR"
		pivot.position = Vector3(half * side, 0.0, 0.0)
		gate.add_child(pivot)
		var x0 := 0.0 if side < 0.0 else -half
		var u0 := 0.0 if side < 0.0 else 0.5
		var leaf := MeshBuf.new()
		_quad(leaf, Vector3(x0, 0.0, 0.0), Vector3(x0 + half, 0.0, 0.0), Vector3(x0 + half, GATE_HEIGHT, 0.0), Vector3(x0, GATE_HEIGHT, 0.0),
			Vector3.BACK, Color.WHITE, Vector2(u0, 0.0), Vector2(u0 + 0.5, 0.0), Vector2(u0 + 0.5, 1.0), Vector2(u0, 1.0), size)
		var visual := MeshInstance3D.new()
		visual.name = "Mesh"
		visual.mesh = leaf.commit(painted)
		pivot.add_child(visual)

	var glass := MeshBuf.new()
	var y0 := GATE_HEIGHT
	var y1 := GATE_HEIGHT + TRANSOM_HEIGHT
	_quad(glass, Vector3(-half, y0, 0.0), Vector3(half, y0, 0.0), Vector3(half, y1, 0.0), Vector3(-half, y1, 0.0),
		Vector3.BACK, Color.WHITE, Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0), Vector2(width, TRANSOM_HEIGHT))
	var transom := MeshInstance3D.new()
	transom.name = "Transom"
	transom.mesh = glass.commit(glazed)
	gate.add_child(transom)

	# What stops a car while the gate is shut.
	var blocker := StaticBody3D.new()
	blocker.name = "Blocker"
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, GATE_HEIGHT, 0.12)
	var cs := CollisionShape3D.new()
	cs.name = "CollisionShape3D"
	cs.shape = shape
	cs.position = Vector3(0.0, GATE_HEIGHT * 0.5, 0.0)
	blocker.add_child(cs)
	gate.add_child(blocker)

# --- trees ------------------------------------------------------------------

func _try_tree(p: Vector2, type: int, rng: RandomNumberGenerator) -> void:
	if tree_count >= MAX_TREES or not _inside(p, 4.0):
		return
	var q := _px(p)
	var k := int(q.y) * TEX_N + int(q.x)
	if mask[k] != 0 or cls[k] == 9:
		return
	var key := Vector3i(int(floor(p.x / TREE_CHUNK)), int(floor(p.y / TREE_CHUNK)), type)
	if not trees.has(key):
		trees[key] = []
	trees[key].append([p, rng.randf_range(0.7, 1.3), rng.randf_range(0.75, 1.1)])
	tree_count += 1


func _scatter_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	for p in tree_nodes:
		_try_tree(p, 0, rng)
	# Poplars lining the irrigation channels.
	for w in waters:
		var side := 1.0
		for k in range(2, w.size() - 1, 4):
			var t := (w[k + 1] - w[k - 1]).normalized()
			_try_tree(w[k] + Vector2(-t.y, t.x) * side * rng.randf_range(3.5, 5.0), 1, rng)
			side = -side
	# Orchards, woods and parks.
	for a in areas:
		var density: float = AREA_TREES.get(a["cls"], 0.0)
		if density <= 0.0:
			continue
		var poly: PackedVector2Array = a["poly"]
		var box := Rect2(poly[0], Vector2.ZERO)
		for p in poly:
			box = box.expand(p)
		for _i in mini(int(box.get_area() * density), 20000):
			var p := box.position + Vector2(rng.randf(), rng.randf()) * box.size
			if Geometry2D.is_point_in_polygon(p, poly):
				_try_tree(p, 0 if a["cls"] != 4 or rng.randf() < 0.7 else 1, rng)
	# Garden trees around houses.
	for b in buildings:
		if b["area"] > 400.0:
			continue
		var poly: PackedVector2Array = b["poly"]
		for _i in rng.randi_range(1, 4):
			var ang := rng.randf() * TAU
			var p := poly[0] + Vector2(cos(ang), sin(ang)) * rng.randf_range(5.0, 16.0)
			_try_tree(p, 0 if rng.randf() < 0.8 else 1, rng)
	print("Trees: %d" % tree_count)


func _prim(buf: MeshBuf, prim: PrimitiveMesh, xf: Transform3D, col: Color) -> void:
	var a := prim.get_mesh_arrays()
	var pv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var pn: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var pi: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var first := buf.v.size()
	for k in pv.size():
		buf.add(xf * pv[k], pn[k], col, Vector2.ZERO)
	for k in pi:
		buf.idx.append(first + k)


func _tree_mesh(type: int, mat: Material) -> ArrayMesh:
	var buf := MeshBuf.new()
	var trunk := CylinderMesh.new()
	trunk.radial_segments = 6
	trunk.rings = 1
	trunk.top_radius = 0.12
	trunk.bottom_radius = 0.2
	trunk.height = 2.4
	_prim(buf, trunk, Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0)), Color(0.30, 0.22, 0.15).srgb_to_linear())
	var crown := SphereMesh.new()
	crown.radial_segments = 8
	crown.rings = 5
	if type == 0:
		crown.radius = 2.1
		crown.height = 3.8
		_prim(buf, crown, Transform3D(Basis.IDENTITY, Vector3(0.0, 3.7, 0.0)), Color(0.27, 0.45, 0.18).srgb_to_linear())
	else:
		crown.radius = 1.1
		crown.height = 10.0
		_prim(buf, crown, Transform3D(Basis.IDENTITY, Vector3(0.0, 6.6, 0.0)), Color(0.22, 0.40, 0.17).srgb_to_linear())
	return buf.commit(mat)


func _build_trees(root: Node3D) -> void:
	var node := Node3D.new()
	node.name = "Trees"
	root.add_child(node)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	var meshes := [_tree_mesh(0, mat), _tree_mesh(1, mat)]
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for key: Vector3i in trees:
		var list: Array = trees[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = meshes[key.z]
		mm.instance_count = list.size()
		for k in list.size():
			var p: Vector2 = list[k][0]
			var s: float = list[k][1]
			var tint: float = list[k][2]
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.85, 1.15), s))
			mm.set_instance_transform(k, Transform3D(basis, Vector3(p.x, _h(p.x, p.y) - 0.1, p.y)))
			mm.set_instance_color(k, Color(tint, tint, tint * 0.9))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Trees_%d_%d_%s" % [key.x, key.y, "round" if key.z == 0 else "poplar"]
		mmi.multimesh = mm
		node.add_child(mmi)


# --- spawn ------------------------------------------------------------------

func _build_spawn(root: Node3D) -> void:
	var best := INF
	var pos := Vector2.ZERO
	var dir := Vector2.UP
	var park_pos := Vector2.ZERO
	var park_dir := Vector2.UP
	for road in roads:
		if road["kind"] != 0 or road["prio"] < 2:
			continue
		var pts: PackedVector2Array = road["pts"]
		for k in range(4, pts.size() - 4):
			var d := pts[k].length()
			if d < best:
				best = d
				pos = pts[k]
				dir = (pts[k + 1] - pts[k - 1]).normalized()
				# A parking place about 18 m further along the same road, by its right-hand edge.
				var j := mini(k + 6, pts.size() - 2)
				if pts[j].distance_to(pts[k]) < 10.0:
					j = maxi(k - 6, 1)
				park_dir = (pts[j + 1] - pts[j - 1]).normalized()
				park_pos = pts[j] + Vector2(-park_dir.y, park_dir.x) * maxf(road["hw"] - 1.1, 0.0)
	_add_marker(root, "Spawn", pos, dir)
	_add_marker(root, "Parking", park_pos, park_dir)


## A marker standing on the ground with its -Z along the given direction.
func _add_marker(root: Node3D, marker_name: String, pos: Vector2, dir: Vector2) -> void:
	var marker := Marker3D.new()
	marker.name = marker_name
	marker.transform = Transform3D(Basis.looking_at(Vector3(dir.x, 0.0, dir.y)), Vector3(pos.x, _h(pos.x, pos.y) + 1.0, pos.y))
	root.add_child(marker)


# --- minimap ----------------------------------------------------------------

## Bakes a north-up street map of the whole world for the HUD minimap.
func _build_minimap() -> void:
	var palette: Array[Color] = []
	palette.resize(32)
	palette.fill(Color(0.87, 0.85, 0.79))
	palette[1] = Color(0.89, 0.87, 0.83)
	palette[2] = Color(0.91, 0.89, 0.74)
	palette[3] = Color(0.76, 0.87, 0.68)
	palette[4] = Color(0.66, 0.80, 0.60)
	palette[5] = Color(0.78, 0.89, 0.70)
	palette[6] = Color(0.84, 0.82, 0.85)
	palette[7] = Color(0.78, 0.84, 0.76)
	palette[8] = Color(0.83, 0.82, 0.78)
	palette[9] = Color(0.60, 0.77, 0.90)
	palette[10] = Color(0.80, 0.86, 0.72)
	const BUILDING := 20
	const STREET := 21
	const MAIN_ROAD := 22
	const STREAM := 23
	const TRACK := 24
	palette[BUILDING] = Color(0.66, 0.59, 0.53)
	palette[STREET] = Color(1.0, 1.0, 1.0)
	palette[MAIN_ROAD] = Color(0.98, 0.80, 0.38)
	palette[STREAM] = Color(0.55, 0.74, 0.90)
	palette[TRACK] = Color(0.76, 0.69, 0.58)

	var buf := PackedByteArray()
	buf.resize(MAP_N * MAP_N)
	var ratio := MAP_N / TEX_N
	for y in MAP_N:
		var src := (y / ratio) * TEX_N
		for x in MAP_N:
			buf[y * MAP_N + x] = cls[src + x / ratio]
	for w in waters:
		for p in w:
			_stamp(p, 2.0, STREAM, buf, MAP_N)
	# Minor roads first so the main ones stay on top.
	for level in [TRACK, STREET, MAIN_ROAD]:
		for road in roads:
			var val := TRACK
			if road["kind"] == 0:
				val = MAIN_ROAD if road["prio"] >= 3 else STREET
			if val != level:
				continue
			var radius: float = maxf(road["hw"], 4.5 if val == MAIN_ROAD else 2.2)
			for p: Vector2 in road["pts"]:
				_stamp(p, radius, val, buf, MAP_N)
	for b in buildings:
		_fill_poly(b["poly"], buf, BUILDING, MAP_N)

	var data := PackedByteArray()
	data.resize(MAP_N * MAP_N * 3)
	for k in buf.size():
		var col := palette[buf[k]]
		data[k * 3] = col.r8
		data[k * 3 + 1] = col.g8
		data[k * 3 + 2] = col.b8
	var img := Image.create_from_data(MAP_N, MAP_N, false, Image.FORMAT_RGB8, data)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	tex.set_meta("world_size", 2.0 * HALF)
	var err := ResourceSaver.save(tex, MAP_PATH, ResourceSaver.FLAG_COMPRESS)
	if err != OK:
		push_error("Saving %s failed: %s" % [MAP_PATH, error_string(err)])
