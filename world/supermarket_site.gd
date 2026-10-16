extends Node3D
## The supermarket site built by tools/build_supermarket.gd (world/supermarket.scn):
## the shop, the guard's booth and the parking lot.
##
## The world (world/yeghvard.scn, the node "World" beside this one) still has
## the plain boxes tools/build_world.gd made for the two buildings, the ground
## rising through the shop floor, and a service road across the parking lot.
## When the game starts this takes those out of it: the boxes, the terrain
## under the shop (its collision gets a hole there, made good round the edges),
## and the roads inside the lot. Doing it here rather than in the saved world
## means rebuilding the world never brings them back.

## Outlines in world metres (x, z), filled in by tools/build_supermarket.gd.
@export var shop_outline := PackedVector2Array()
@export var booth_outline := PackedVector2Array()
@export var parking_outline := PackedVector2Array()
## Name of the collision piece added to the terrain round the hole.
@export var terrain_patch := "SupermarketCut"


func _ready() -> void:
	var world := get_parent().get_node_or_null("World") as Node3D if get_parent() else null
	if world == null or shop_outline.size() < 3:
		return
	apply(world)


## Makes the changes to the given world.
func apply(world: Node3D) -> void:
	var t0 := Time.get_ticks_usec()
	var removed := _strip_old_buildings(world, [shop_outline, booth_outline])
	_cut_terrain(world, shop_outline, terrain_patch)
	_cut_roads(world, parking_outline)
	print_verbose("Supermarket: %d old triangles out, ground and roads cut in %.1f ms" % [removed, (Time.get_ticks_usec() - t0) / 1000.0])


static func _area(poly: PackedVector2Array) -> float:
	var s := 0.0
	for k in poly.size():
		var a := poly[k]
		var b := poly[(k + 1) % poly.size()]
		s += a.x * b.y - b.x * a.y
	return s * 0.5


## Removes the walls and roofs of the boxes build_world.gd made for the buildings.
## Returns how many triangles went.
static func _strip_old_buildings(world: Node3D, outlines: Array) -> int:
	var zones: Array[PackedVector2Array] = []
	for outline: PackedVector2Array in outlines:
		zones.append(Geometry2D.offset_polygon(outline, 0.05)[0])
	var inside := func(p: Vector3) -> bool:
		for zone in zones:
			if Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), zone):
				return true
		return false
	var removed := 0
	var buildings := world.get_node("Buildings")
	var zlo := Vector2(INF, INF)
	var zhi := Vector2(-INF, -INF)
	for zone in zones:
		for p in zone:
			zlo = zlo.min(p)
			zhi = zhi.max(p)
	for mi: MeshInstance3D in buildings.find_children("*", "MeshInstance3D", false, false):
		var box := mi.transform * mi.mesh.get_aabb()
		if box.position.x > zhi.x or box.end.x < zlo.x or box.position.z > zhi.y or box.end.z < zlo.y:
			continue
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


## Cuts the shop's outline out of the terrain, which rises above the shop floor
## towards the back: the triangles under it are trimmed to its edges, and the
## height map's collision gets a hole there (Jolt leaves out cells with a NaN
## corner), its cells round the hole replaced by the trimmed triangles.
static func _cut_terrain(world: Node3D, poly: PackedVector2Array, patch_name: String) -> bool:
	var terrain := world.get_node("Terrain") as StaticBody3D
	var changed := false
	for mi: MeshInstance3D in terrain.find_children("Chunk_*", "MeshInstance3D", false, false):
		if _cut_mesh(mi, poly):
			changed = true
	var cs := terrain.get_node("CollisionShape3D") as CollisionShape3D
	var hs := cs.shape as HeightMapShape3D
	var n := hs.map_width
	var cell := cs.scale.x
	var half := (n - 1) * cell * 0.5
	var data := hs.map_data
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in poly:
		lo = lo.min(p)
		hi = hi.max(p)
	var i0 := floori((lo.x + half) / cell)
	var i1 := floori((hi.x + half) / cell)
	var j0 := floori((lo.y + half) / cell)
	var j1 := floori((hi.y + half) / cell)
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var x := -half + i * cell
			var z := -half + j * cell
			var sq := PackedVector2Array([Vector2(x, z), Vector2(x + cell, z), Vector2(x + cell, z + cell), Vector2(x, z + cell)])
			var area := 0.0
			for piece: PackedVector2Array in Geometry2D.intersect_polygons(sq, poly):
				area += absf(_area(piece))
			if area < 0.01:
				continue
			for corner: Vector2i in [Vector2i(i, j), Vector2i(i + 1, j), Vector2i(i, j + 1), Vector2i(i + 1, j + 1)]:
				var at := corner.y * n + corner.x
				if not is_nan(data[at]):
					data[at] = NAN
					changed = true
	if not changed and terrain.has_node(patch_name):
		return false
	hs.map_data = data
	# Every cell with a NaN corner is a hole: give the collision back the parts of
	# those cells outside the shop, from the trimmed triangles.
	var holes := {}
	for j in range(j0 - 1, j1 + 3):
		for i in range(i0 - 1, i1 + 3):
			if j < 0 or i < 0 or j >= n or i >= n or not is_nan(data[j * n + i]):
				continue
			for c: Vector2i in [Vector2i(i - 1, j - 1), Vector2i(i, j - 1), Vector2i(i - 1, j), Vector2i(i, j)]:
				holes[c] = true
	var faces := PackedVector3Array()
	var reach := AABB(Vector3(lo.x - 2.0 * cell, 0.0, lo.y - 2.0 * cell), Vector3(hi.x - lo.x + 4.0 * cell, 1.0, hi.y - lo.y + 4.0 * cell))
	for mi: MeshInstance3D in terrain.find_children("Chunk_*", "MeshInstance3D", false, false):
		var box := mi.transform * mi.mesh.get_aabb()
		if box.position.x > reach.end.x or box.end.x < reach.position.x or box.position.z > reach.end.z or box.end.z < reach.position.z:
			continue
		var arr := mi.mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		for k in range(0, idx.size(), 3):
			var a := mi.transform * v[idx[k]]
			var b := mi.transform * v[idx[k + 1]]
			var c := mi.transform * v[idx[k + 2]]
			var m := (a + b + c) / 3.0
			var key := Vector2i(floori((m.x + half) / cell), floori((m.z + half) / cell))
			if holes.has(key):
				faces.append_array([a, b, c])
	var old := terrain.get_node_or_null(patch_name)
	if old:
		terrain.remove_child(old)
		old.free()
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var patch := CollisionShape3D.new()
	patch.name = patch_name
	patch.shape = shape
	terrain.add_child(patch)
	print_verbose("Supermarket: %d terrain cells left out of the height map, %d triangles in their place" % [holes.size(), faces.size() / 3])
	return true


## Takes the roads out of the parking lot (the service road the lot replaces).
static func _cut_roads(world: Node3D, poly: PackedVector2Array) -> bool:
	var roads := world.get_node("Roads")
	var changed := false
	for mi: MeshInstance3D in roads.find_children("*", "MeshInstance3D", false, false):
		if _cut_mesh(mi, poly):
			changed = true
	for cs: CollisionShape3D in roads.find_children("*", "CollisionShape3D", false, false):
		var shape := cs.shape as ConcavePolygonShape3D
		if shape == null:
			continue
		var f := shape.get_faces()
		var cut := _cut_faces(f, poly)
		if cut.size() != f.size() or cut != f:
			var fresh := ConcavePolygonShape3D.new()
			fresh.set_faces(cut)
			cs.shape = fresh
			changed = true
	return changed


## Area of the part of triangle tri (x, z) inside poly.
static func _overlap(tri: PackedVector2Array, poly: PackedVector2Array, lo: Vector2, hi: Vector2) -> float:
	var tlo := tri[0].min(tri[1]).min(tri[2])
	var thi := tri[0].max(tri[1]).max(tri[2])
	if thi.x < lo.x or tlo.x > hi.x or thi.y < lo.y or tlo.y > hi.y:
		return 0.0
	var area := 0.0
	for piece: PackedVector2Array in Geometry2D.intersect_polygons(tri, poly):
		area += absf(_area(piece))
	return area


## Barycentric weights of p in the triangle a, b, c.
static func _bary(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> Vector3:
	var v0 := b - a
	var v1 := c - a
	var v2 := p - a
	var den := v0.x * v1.y - v1.x * v0.y
	if absf(den) < 1e-12:
		return Vector3(1, 0, 0)
	var wb := (v2.x * v1.y - v1.x * v2.y) / den
	var wc := (v0.x * v2.y - v2.x * v0.y) / den
	return Vector3(1.0 - wb - wc, wb, wc)


## Replaces the mesh's triangles that overlap `poly` (world x, z) by their parts
## outside it, carrying every vertex attribute over. Returns whether it changed.
static func _cut_mesh(mi: MeshInstance3D, poly: PackedVector2Array) -> bool:
	var mesh := mi.mesh as ArrayMesh
	if mesh == null:
		return false
	var to_local := mi.transform.affine_inverse()
	var lpoly := PackedVector2Array()
	for p in poly:
		var q := to_local * Vector3(p.x, 0.0, p.y)
		lpoly.append(Vector2(q.x, q.z))
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in lpoly:
		lo = lo.min(p)
		hi = hi.max(p)
	var box := mesh.get_aabb()
	if box.position.x > hi.x or box.end.x < lo.x or box.position.z > hi.y or box.end.z < lo.y:
		return false
	var arr := mesh.surface_get_arrays(0)
	for k in range(Mesh.ARRAY_TEX_UV2 + 1, Mesh.ARRAY_MAX):
		if k != Mesh.ARRAY_INDEX and arr[k] != null:
			push_warning("%s has vertex data the cut does not carry over; left alone" % mi.name)
			return false
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var has_n: bool = arr[Mesh.ARRAY_NORMAL] != null
	var has_t: bool = arr[Mesh.ARRAY_TANGENT] != null
	var has_c: bool = arr[Mesh.ARRAY_COLOR] != null
	var has_uv: bool = arr[Mesh.ARRAY_TEX_UV] != null
	var has_uv2: bool = arr[Mesh.ARRAY_TEX_UV2] != null
	var nn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if has_n else PackedVector3Array()
	var tt: PackedFloat32Array = arr[Mesh.ARRAY_TANGENT] if has_t else PackedFloat32Array()
	var cc: PackedColorArray = arr[Mesh.ARRAY_COLOR] if has_c else PackedColorArray()
	var u1: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV] if has_uv else PackedVector2Array()
	var u2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2] if has_uv2 else PackedVector2Array()
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var hits := _near(v, idx, lo, hi)
	if hits.is_empty():
		return false
	var keep := PackedInt32Array()
	var changed := false
	var last := 0
	for k: int in hits:
		keep.append_array(idx.slice(last, k))
		last = k + 3
		var ia := idx[k]
		var ib := idx[k + 1]
		var ic := idx[k + 2]
		var tri := PackedVector2Array([Vector2(v[ia].x, v[ia].z), Vector2(v[ib].x, v[ib].z), Vector2(v[ic].x, v[ic].z)])
		# Pieces left from an earlier cut touch the outline; the clipping's rounding
		# can make them seem to reach a hair over it.
		if _overlap(tri, lpoly, lo, hi) < 0.01:
			keep.append_array([ia, ib, ic])
			continue
		changed = true
		var sense := signf(_area(tri))
		for piece: PackedVector2Array in Geometry2D.clip_polygons(tri, lpoly):
			if signf(_area(piece)) != sense:
				push_warning("%s: a triangle wholly round the cut is left out" % mi.name)
				continue
			var tris := Geometry2D.triangulate_polygon(piece)
			for t in range(0, tris.size(), 3):
				var ids := PackedInt32Array()
				for m in 3:
					var q := piece[tris[t + m]]
					var w := _bary(q, tri[0], tri[1], tri[2])
					v.append(v[ia] * w.x + v[ib] * w.y + v[ic] * w.z)
					if has_n:
						nn.append((nn[ia] * w.x + nn[ib] * w.y + nn[ic] * w.z).normalized())
					if has_t:
						for e in 4:
							tt.append(tt[ia * 4 + e] * w.x + tt[ib * 4 + e] * w.y + tt[ic * 4 + e] * w.z)
					if has_c:
						cc.append(cc[ia] * w.x + cc[ib] * w.y + cc[ic] * w.z)
					if has_uv:
						u1.append(u1[ia] * w.x + u1[ib] * w.y + u1[ic] * w.z)
					if has_uv2:
						u2.append(u2[ia] * w.x + u2[ib] * w.y + u2[ic] * w.z)
					ids.append(v.size() - 1)
				var p0 := piece[tris[t]]
				var p1 := piece[tris[t + 1]]
				var p2 := piece[tris[t + 2]]
				if signf((p1 - p0).cross(p2 - p0)) != sense:
					ids = PackedInt32Array([ids[0], ids[2], ids[1]])
				keep.append_array(ids)
	keep.append_array(idx.slice(last))
	if not changed:
		return false
	arr[Mesh.ARRAY_VERTEX] = v
	if has_n:
		arr[Mesh.ARRAY_NORMAL] = nn
	if has_t:
		arr[Mesh.ARRAY_TANGENT] = tt
	if has_c:
		arr[Mesh.ARRAY_COLOR] = cc
	if has_uv:
		arr[Mesh.ARRAY_TEX_UV] = u1
	if has_uv2:
		arr[Mesh.ARRAY_TEX_UV2] = u2
	arr[Mesh.ARRAY_INDEX] = keep
	var mat := mesh.surface_get_material(0)
	var fresh := ArrayMesh.new()
	fresh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	fresh.surface_set_material(0, mat)
	mi.mesh = fresh
	return true


## The same cut for collision triangles (world space).
static func _cut_faces(f: PackedVector3Array, poly: PackedVector2Array) -> PackedVector3Array:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in poly:
		lo = lo.min(p)
		hi = hi.max(p)
	var hits := _near(f, PackedInt32Array(), lo, hi)
	if hits.is_empty():
		return f
	var out := PackedVector3Array()
	var last := 0
	for k: int in hits:
		out.append_array(f.slice(last, k))
		last = k + 3
		var a := f[k]
		var b := f[k + 1]
		var c := f[k + 2]
		var tri := PackedVector2Array([Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z)])
		if absf(_area(tri)) < 1e-6 or _overlap(tri, poly, lo, hi) < 0.01:
			out.append_array([a, b, c])
			continue
		var sense := signf(_area(tri))
		for piece: PackedVector2Array in Geometry2D.clip_polygons(tri, poly):
			if signf(_area(piece)) != sense:
				continue
			var tris := Geometry2D.triangulate_polygon(piece)
			for t in range(0, tris.size(), 3):
				var pts := PackedVector3Array()
				for m in 3:
					var q := piece[tris[t + m]]
					var w := _bary(q, tri[0], tri[1], tri[2])
					pts.append(a * w.x + b * w.y + c * w.z)
				var p0 := piece[tris[t]]
				var p1 := piece[tris[t + 1]]
				var p2 := piece[tris[t + 2]]
				if signf((p1 - p0).cross(p2 - p0)) != sense:
					pts = PackedVector3Array([pts[0], pts[2], pts[1]])
				out.append_array(pts)
	out.append_array(f.slice(last))
	return out


## Starts (in the vertex list, or in `idx` when given) of the triangles whose
## bounding box in x, z overlaps lo..hi.
static func _near(v: PackedVector3Array, idx: PackedInt32Array, lo: Vector2, hi: Vector2) -> PackedInt32Array:
	var out := PackedInt32Array()
	var indexed := not idx.is_empty()
	var count := idx.size() if indexed else v.size()
	for k in range(0, count, 3):
		var a := v[idx[k]] if indexed else v[k]
		var b := v[idx[k + 1]] if indexed else v[k + 1]
		var c := v[idx[k + 2]] if indexed else v[k + 2]
		if maxf(a.x, maxf(b.x, c.x)) < lo.x or minf(a.x, minf(b.x, c.x)) > hi.x:
			continue
		if maxf(a.z, maxf(b.z, c.z)) < lo.y or minf(a.z, minf(b.z, c.z)) > hi.y:
			continue
		out.append(k)
	return out
