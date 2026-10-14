extends RefCounted
## Draws the editable map's buildings and walls (world/map/map.tscn) for the
## editor's preview. tools/build_world.gd bakes the same data into the game's
## chunks with its own copy of these rules (see _build_buildings and
## _build_walls); keep the two in step.

const HEIGHTS_PATH := "res://world/map/terrain_height.res"

## Wall kinds; the numbers are what world/shaders/fence.gdshader expects.
enum Kind { STONE = 0, SHEET = 1, MESH = 2 }
const POST := 3
const PIECE := 2.5 ## longest stretch of wall laid over the ground as one piece
const SINK := 0.3 ## how far walls go into the ground, so slopes do not show a gap
const STONE_HALF := 0.15 ## half the thickness of a stone wall
const GATE_WIDTH := 3.4
const GATE_HEIGHT := 2.2
const POST_COLOR := Color(0.2, 0.2, 0.2)

static var _heights := PackedFloat32Array()
static var _grid_n := 0
static var _cell := 0.0
static var _half := 0.0
static var _fence_mat: ShaderMaterial
static var _building_mat: ShaderMaterial


## Height of the terrain at a world position (x, z), as tools/build_world.gd made it.
static func height_at(x: float, z: float) -> float:
	if _grid_n == 0:
		if not ResourceLoader.exists(HEIGHTS_PATH):
			return 0.0
		var img: Image = load(HEIGHTS_PATH)
		_grid_n = img.get_width()
		_heights = img.get_data().to_float32_array()
		_cell = img.get_meta("cell", 9.0)
		_half = (_grid_n - 1) * _cell * 0.5
	var gx := clampf((x + _half) / _cell, 0.0, _grid_n - 1.0001)
	var gz := clampf((z + _half) / _cell, 0.0, _grid_n - 1.0001)
	var i := int(gx)
	var j := int(gz)
	var fx := gx - i
	var fz := gz - j
	var h00 := _heights[j * _grid_n + i]
	var h10 := _heights[j * _grid_n + i + 1]
	var h01 := _heights[(j + 1) * _grid_n + i]
	var h11 := _heights[(j + 1) * _grid_n + i + 1]
	if fx + fz <= 1.0:
		return h00 + fx * (h10 - h00) + fz * (h01 - h00)
	return h11 + (1.0 - fx) * (h01 - h11) + (1.0 - fz) * (h10 - h11)


## Mesh of a building standing on the terrain. `poly` is its footprint in world
## metres (x, z); `to_local` takes world positions into the mesh's own space.
static func building_mesh(poly: PackedVector2Array, height: float, wall: Color, roof: Color, plain: bool,
		tuff: bool, to_local: Transform3D) -> ArrayMesh:
	var b := Buf.new()
	var n := poly.size()
	if n < 3:
		return null
	var ymin := INF
	var ymax := -INF
	for p in poly:
		var y := height_at(p.x, p.y)
		ymin = minf(ymin, y)
		ymax = maxf(ymax, y)
	var base := ymin - 0.6
	var top := ymax + height
	var wc := wall.srgb_to_linear()
	wc.a = 0.5 if plain else 1.0
	var rc := roof.srgb_to_linear()
	rc.a = 0.0
	# Walls run round the footprint whichever way it was drawn.
	var ccw := _signed_area(poly) > 0.0
	for k in n:
		var a := poly[k] if ccw else poly[n - 1 - k]
		var c := poly[(k + 1) % n] if ccw else poly[(n - 2 - k + n) % n]
		var d := c - a
		var length := d.length()
		if length < 0.05:
			continue
		var nrm := Vector3(d.y, 0.0, -d.x) / length
		var dims := Vector2(length, -height if tuff else height)
		var v0 := b.add(to_local * Vector3(a.x, base, a.y), nrm, wc, Vector2(0.0, top - base), dims)
		var v1 := b.add(to_local * Vector3(c.x, base, c.y), nrm, wc, Vector2(length, top - base), dims)
		var v2 := b.add(to_local * Vector3(c.x, top, c.y), nrm, wc, Vector2(length, 0.0), dims)
		var v3 := b.add(to_local * Vector3(a.x, top, a.y), nrm, wc, Vector2(0.0, 0.0), dims)
		b.tri(v0, v1, v2)
		b.tri(v0, v2, v3)
	var tris := Geometry2D.triangulate_polygon(poly)
	var first := b.v.size()
	for p in poly:
		b.add(to_local * Vector3(p.x, top, p.y), Vector3.UP, rc, Vector2.ZERO)
	for k in range(0, tris.size(), 3):
		b.tri_up(first + tris[k], first + tris[k + 1], first + tris[k + 2])
	if _building_mat == null:
		_building_mat = ShaderMaterial.new()
		_building_mat.shader = load("res://world/shaders/building.gdshader")
	return b.commit(_building_mat)


## Mesh of a wall along `pts` (world metres, x and z), with a gate `gate_at`
## metres along it (none if negative).
static func wall_mesh(pts: PackedVector2Array, kind: int, color: Color, height: float, gate_at: float,
		gate_color: Color, to_local: Transform3D) -> ArrayMesh:
	if pts.size() < 2:
		return null
	var b := Buf.new()
	var col := color.srgb_to_linear()
	var gate_col := gate_color.srgb_to_linear()
	var pillar := col * 0.92
	var along := 0.0
	for s in pts.size() - 1:
		var a := pts[s]
		var c := pts[s + 1]
		var run := a.distance_to(c)
		if run < 0.01:
			continue
		var dir := (c - a) / run
		var gaps: Array[Vector2] = []
		if gate_at >= 0.0 and gate_at >= along and gate_at < along + run:
			var at := clampf(gate_at - along, GATE_WIDTH * 0.5, maxf(run - GATE_WIDTH * 0.5, GATE_WIDTH * 0.5))
			gaps.append(Vector2(at - GATE_WIDTH * 0.5, at + GATE_WIDTH * 0.5))
		run_into(b, a, c, kind, height, col, gaps, to_local)
		for g in gaps:
			var g0 := a + dir * g.x
			var g1 := a + dir * minf(g.y, run)
			run_into(b, g0, g1, Kind.SHEET, GATE_HEIGHT, gate_col, [], to_local)
			for p in [g0, g1]:
				box_into(b, p, 0.25, height + 0.15, pillar, Kind.STONE, to_local)
		if kind == Kind.STONE:
			var turn := s > 0 and (pts[s] - pts[s - 1]).normalized().dot(dir) < 0.96
			if s == 0 or turn:
				box_into(b, a, 0.22, height + 0.1, pillar, Kind.STONE, to_local)
		along += run
	if kind == Kind.STONE:
		box_into(b, pts[pts.size() - 1], 0.22, height + 0.1, pillar, Kind.STONE, to_local)
	if _fence_mat == null:
		_fence_mat = ShaderMaterial.new()
		_fence_mat.shader = load("res://world/shaders/fence.gdshader")
	return b.commit(_fence_mat)


## One straight run of wall from a to b, with `gaps` (metres from a) left open.
static func run_into(b: Buf, a: Vector2, c: Vector2, kind: int, height: float, col: Color, gaps: Array,
		to_local: Transform3D) -> void:
	var run := a.distance_to(c)
	var dir := (c - a) / run
	var nrm := Vector2(dir.y, -dir.x)
	var steps := maxi(1, int(ceil(run / PIECE)))
	var half := STONE_HALF if kind == Kind.STONE else 0.0
	var extra := Vector2(kind, 0.0)
	for s in steps:
		var t0 := run * s / steps
		var t1 := run * (s + 1) / steps
		for g: Vector2 in gaps:
			if t0 < g.y and t1 > g.x:
				if t0 >= g.x and t1 <= g.y:
					t0 = t1
				elif t0 < g.x:
					t1 = g.x
				else:
					t0 = g.y
		if t1 - t0 < 0.05:
			continue
		var p0 := a + dir * t0
		var p1 := a + dir * t1
		var y0 := height_at(p0.x, p0.y)
		var y1 := height_at(p1.x, p1.y)
		for side: float in ([-1.0, 1.0] if half > 0.0 else [0.0]):
			var o := nrm * half * side
			var n3 := Vector3(nrm.x, 0.0, nrm.y) * (side if side != 0.0 else 1.0)
			b.quad(to_local * Vector3(p0.x + o.x, y0 - SINK, p0.y + o.y), to_local * Vector3(p1.x + o.x, y1 - SINK, p1.y + o.y),
				to_local * Vector3(p1.x + o.x, y1 + height, p1.y + o.y), to_local * Vector3(p0.x + o.x, y0 + height, p0.y + o.y),
				n3, col, Vector2(t0, -SINK), Vector2(t1, -SINK), Vector2(t1, height), Vector2(t0, height), extra)
		if half > 0.0:
			var l := nrm * half
			b.quad(to_local * Vector3(p0.x - l.x, y0 + height, p0.y - l.y), to_local * Vector3(p1.x - l.x, y1 + height, p1.y - l.y),
				to_local * Vector3(p1.x + l.x, y1 + height, p1.y + l.y), to_local * Vector3(p0.x + l.x, y0 + height, p0.y + l.y),
				Vector3.UP, col * 0.9, Vector2(t0, 0.0), Vector2(t1, 0.0), Vector2(t1, 0.3), Vector2(t0, 0.3), extra)
		else:
			box_into(b, p0, 0.04, height + 0.05, POST_COLOR, POST, to_local)
			if s == steps - 1:
				box_into(b, p1, 0.04, height + 0.05, POST_COLOR, POST, to_local)


## A square post or pillar of half width `half` standing on the ground at p.
static func box_into(b: Buf, p: Vector2, half: float, height: float, col: Color, kind: int, to_local: Transform3D) -> void:
	var g := height_at(p.x, p.y)
	var y0 := g - SINK
	var y1 := g + height
	var extra := Vector2(kind, 0.0)
	var corners := [Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)]
	for k in 4:
		var q0: Vector2 = p + corners[k]
		var q1: Vector2 = p + corners[(k + 1) % 4]
		var mid: Vector2 = (corners[k] + corners[(k + 1) % 4]).normalized()
		b.quad(to_local * Vector3(q0.x, y0, q0.y), to_local * Vector3(q1.x, y0, q1.y), to_local * Vector3(q1.x, y1, q1.y),
			to_local * Vector3(q0.x, y1, q0.y), Vector3(mid.x, 0.0, mid.y), col, Vector2(0.0, -SINK),
			Vector2(half * 2.0, -SINK), Vector2(half * 2.0, height), Vector2(0.0, height), extra)
	b.quad(to_local * Vector3(p.x - half, y1, p.y - half), to_local * Vector3(p.x + half, y1, p.y - half),
		to_local * Vector3(p.x + half, y1, p.y + half), to_local * Vector3(p.x - half, y1, p.y + half), Vector3.UP, col,
		Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, extra)


static func _signed_area(poly: PackedVector2Array) -> float:
	var s := 0.0
	for k in poly.size():
		var a := poly[k]
		var b := poly[(k + 1) % poly.size()]
		s += a.x * b.y - b.x * a.y
	return s * 0.5


## Vertex lists for one mesh (as MeshBuf in tools/build_world.gd).
class Buf:
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

	## A flat four-cornered face looking along `nrm`, whatever order the corners come in.
	func quad(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, nrm: Vector3, col: Color,
			uv0: Vector2, uv1: Vector2, uv2_: Vector2, uv3: Vector2, extra: Vector2) -> void:
		var v0 := add(p0, nrm, col, uv0, extra)
		var v1 := add(p1, nrm, col, uv1, extra)
		var v2 := add(p2, nrm, col, uv2_, extra)
		var v3 := add(p3, nrm, col, uv3, extra)
		if (p2 - p0).cross(p1 - p0).dot(nrm) > 0.0:
			tri(v0, v1, v2)
			tri(v0, v2, v3)
		else:
			tri(v0, v2, v1)
			tri(v0, v3, v2)

	func commit(mat: Material) -> ArrayMesh:
		if idx.is_empty():
			return null
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
