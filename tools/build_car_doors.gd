extends SceneTree
## Cuts the driver's door out of the body of each car built by
## tools/build_car.gd (car/*.scn), so it can swing open while you get in and
## out (player/player.gd opens it). Run it again after rebuilding a car.
##
## The models (but for the E50's) have their doors fused into the body, so the
## door is taken as every part of the body that lies, seen from the side, inside
## the door's outline, and on the outer part of the car's left side (+X: the
## driver sits on the left). Triangles across the outline are cut along it, so
## the door and the opening in the body have clean, straight edges. The result
## is a node "DriverDoor" on the car, standing on the door's front edge (its
## hinges), with the door as its child "Mesh"; turning it about its Y axis swings
## the door. A car that already has its door has it put back first and cut again,
## so the outlines can be changed and this run again.
##
## Run:  godot --path . --script res://tools/build_car_doors.gd

## Per car: the door's outline seen from the left, traced along its seams, as
## (z, y) points in the car's space (up the front edge first, from the bottom),
## and how far out (x) the door starts.
const DOORS := {
	"res://car/e50_amg.scn": {"outline": [Vector2(0.904, 0.304), Vector2(0.935, 0.70), Vector2(0.915, 0.867), Vector2(0.80, 0.99), Vector2(0.633, 1.1375), Vector2(0.467, 1.2625), Vector2(0.30, 1.325), Vector2(-0.158, 1.34), Vector2(-0.1375, 0.95), Vector2(-0.127, 0.70), Vector2(-0.158, 0.304)], "inner": 0.62},
	"res://car/e55_amg.scn": {"outline": [Vector2(0.883, 0.273), Vector2(0.925, 0.783), Vector2(0.8625, 0.867), Vector2(0.7375, 1.0125), Vector2(0.55, 1.179), Vector2(0.3417, 1.283), Vector2(0.1333, 1.325), Vector2(-0.2208, 1.335), Vector2(-0.2104, 0.95), Vector2(-0.175, 0.617), Vector2(-0.194, 0.273)], "inner": 0.62},
	"res://car/volga_3102.scn": {"outline": [Vector2(0.873, 0.20), Vector2(0.894, 0.70), Vector2(0.879, 0.835), Vector2(0.81, 0.856), Vector2(0.654, 1.054), Vector2(0.498, 1.252), Vector2(0.467, 1.273), Vector2(-0.044, 1.273), Vector2(-0.044, 0.70), Vector2(-0.033, 0.20)], "inner": 0.60},
	"res://car/land_cruiser_80.scn": {"outline": [Vector2(0.748, 0.492), Vector2(0.758, 0.908), Vector2(0.7375, 1.117), Vector2(0.685, 1.242), Vector2(0.592, 1.346), Vector2(0.467, 1.502), Vector2(0.321, 1.731), Vector2(0.258, 1.773), Vector2(-0.315, 1.773), Vector2(-0.315, 1.2625), Vector2(-0.304, 0.908), Vector2(-0.329, 0.5125), Vector2(-0.335, 0.49)], "inner": 0.70},
	"res://car/jeep_compass.scn": {"outline": [Vector2(0.78, 0.43), Vector2(0.80, 0.90), Vector2(0.806, 1.117), Vector2(0.7375, 1.169), Vector2(0.592, 1.294), Vector2(0.446, 1.398), Vector2(0.279, 1.481), Vector2(0.133, 1.5125), Vector2(-0.26, 1.523), Vector2(-0.252, 1.117), Vector2(-0.227, 0.867), Vector2(-0.235, 0.49), Vector2(-0.24, 0.43)], "inner": 0.55},
}


func _initialize() -> void:
	var failed := false
	for path: String in DOORS:
		if _cut(path, DOORS[path]) != OK:
			failed = true
	quit(1 if failed else 0)


func _cut(path: String, door: Dictionary) -> Error:
	var car: Node3D = (load(path) as PackedScene).instantiate()
	var body := car.get_node("Body") as MeshInstance3D
	if body.transform != Transform3D.IDENTITY:
		push_error("%s: the body has to sit at the car's origin" % path)
		car.free()
		return FAILED
	if car.has_node("DriverDoor"):
		_put_back(car, body)
	var outline := PackedVector2Array(door["outline"])
	var inner: float = door["inner"]
	# The outline in convex pieces, each as the planes of its sides: what is
	# inside a piece is on the plus side of all of them.
	var pieces: Array = []
	for poly in Geometry2D.decompose_polygon_in_convex(outline):
		var turn := 0.0
		for i in poly.size():
			turn += poly[i].cross(poly[(i + 1) % poly.size()])
		var planes: Array[Plane] = []
		for i in poly.size():
			var a := poly[i]
			var b := poly[(i + 1) % poly.size()]
			# (b - a) x (q - a) for q = (z, y), the sign of `turn` inside.
			var n := Vector3(0.0, (b.x - a.x), -(b.y - a.y)) * signf(turn)
			planes.append(Plane(n, n.dot(Vector3(0.0, a.y, a.x))))
		pieces.append(planes)
	var side := Plane(Vector3.RIGHT, inner)
	# The hinge: the door's front edge, on the outside of the car.
	var front := maxf(outline[0].x, outline[1].x)
	var hinge := Vector3(_outer_x(body, front), (outline[0].y + outline[1].y) * 0.5, front)

	var kept := ArrayMesh.new()
	var cut := ArrayMesh.new()
	var moved := 0
	for s in body.mesh.get_surface_count():
		var parts := _split(body.mesh.surface_get_arrays(s), side, pieces)
		var mat := body.mesh.surface_get_material(s)
		var flags: int = body.mesh.surface_get_format(s) & ~((1 << Mesh.ARRAY_FORMAT_CUSTOM_BASE) - 1)
		var keep: Array = parts[0]
		var take: Array = parts[1]
		if not keep.is_empty():
			kept.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, keep, [], {}, flags)
			kept.surface_set_material(kept.get_surface_count() - 1, mat)
			kept.surface_set_name(kept.get_surface_count() - 1, body.mesh.surface_get_name(s))
		if not take.is_empty():
			# The door's copy, moved so the hinge is its origin.
			var dv: PackedVector3Array = take[Mesh.ARRAY_VERTEX]
			for i in dv.size():
				dv[i] -= hinge
			take[Mesh.ARRAY_VERTEX] = dv
			cut.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, take, [], {}, flags)
			cut.surface_set_material(cut.get_surface_count() - 1, mat)
			cut.surface_set_name(cut.get_surface_count() - 1, body.mesh.surface_get_name(s))
			moved += (take[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	if moved == 0:
		push_error("%s: nothing inside the door's outline" % path)
		car.free()
		return FAILED
	body.mesh = kept
	var pivot := Node3D.new()
	pivot.name = "DriverDoor"
	pivot.position = hinge
	car.add_child(pivot)
	pivot.owner = car
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = cut
	pivot.add_child(mi)
	mi.owner = car
	var scene := PackedScene.new()
	var err := scene.pack(car)
	if err == OK:
		err = ResourceSaver.save(scene, path, ResourceSaver.FLAG_COMPRESS)
	car.free()
	print("%s: %d triangles in the door, hinge at %s (%s)" % [path, moved, hinge, error_string(err)])
	return err


## Puts a door cut out before back into the body: each of its surfaces joins the
## body's surface with the same material (and layout), or comes in as one of its own.
func _put_back(car: Node3D, body: MeshInstance3D) -> void:
	var pivot := car.get_node("DriverDoor") as Node3D
	var door := (pivot.get_node("Mesh") as MeshInstance3D).mesh
	var surfaces := []
	for s in body.mesh.get_surface_count():
		surfaces.append([body.mesh.surface_get_arrays(s), body.mesh.surface_get_material(s), body.mesh.surface_get_format(s), body.mesh.surface_get_name(s)])
	for s in door.get_surface_count():
		var arr := door.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for i in v.size():
			v[i] = pivot.transform * v[i]
		arr[Mesh.ARRAY_VERTEX] = v
		var into: Array = []
		for t: Array in surfaces:
			if t[1] == door.surface_get_material(s) and t[2] == door.surface_get_format(s):
				into = t
				break
		if into.is_empty():
			surfaces.append([arr, door.surface_get_material(s), door.surface_get_format(s), door.surface_get_name(s)])
		else:
			into[0] = _join(into[0], arr)
	var mesh := ArrayMesh.new()
	for t: Array in surfaces:
		var flags: int = (t[2] as int) & ~((1 << Mesh.ARRAY_FORMAT_CUSTOM_BASE) - 1)
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, t[0], [], {}, flags)
		mesh.surface_set_material(mesh.get_surface_count() - 1, t[1])
		mesh.surface_set_name(mesh.get_surface_count() - 1, t[3])
	body.mesh = mesh
	car.remove_child(pivot)
	pivot.free()


## Two surfaces' arrays (with the same channels) as one.
func _join(a: Array, b: Array) -> Array:
	var count: int = (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var out := a.duplicate()
	for k in Mesh.ARRAY_MAX:
		if k == Mesh.ARRAY_INDEX or a[k] == null:
			continue
		var c: Variant = a[k].duplicate()
		c.append_array(b[k])
		out[k] = c
	var ia: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else _all(count)
	var bn: int = (b[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var ib: PackedInt32Array = b[Mesh.ARRAY_INDEX] if b[Mesh.ARRAY_INDEX] != null else _all(bn)
	var idx := ia.duplicate()
	for i in ib:
		idx.append(i + count)
	out[Mesh.ARRAY_INDEX] = idx
	return out


## A surface split in two: [what lies outside the door, what lies inside it]
## (each empty if nothing). Inside is on the plus side of `side` and inside one
## of the convex `pieces` (each a list of planes). Triangles across their edges
## are cut along them, the new corners' normals, UVs and so on taken between the old.
func _split(arr: Array, side: Plane, pieces: Array) -> Array:
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var count := v.size()
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else _all(count)
	# New corners: [from, to, t], indices past `count` meaning earlier new corners.
	var made: Array[Vector3] = []
	var spans := []
	var outside := PackedInt32Array()
	var inside := PackedInt32Array()
	for k in range(0, idx.size(), 3):
		var tri := PackedInt32Array([idx[k], idx[k + 1], idx[k + 2]])
		if _where(tri, side, v, made) < 0:
			outside.append_array(tri)
			continue
		# What is left to sort: polygons not yet found inside a piece.
		var rest: Array[PackedInt32Array] = []
		_fan_to(_clip(tri, side, true, v, made, spans), outside, v, made)
		rest.append(_clip(tri, side, false, v, made, spans))
		for planes: Array in pieces:
			var next: Array[PackedInt32Array] = []
			for poly in rest:
				if poly.size() < 3:
					continue
				var where := 1
				for p: Plane in planes:
					var w := _where(poly, p, v, made)
					if w < 0:
						where = -1
						break
					if w == 0:
						where = 0
				if where < 0:
					next.append(poly)
					continue
				if where > 0:
					_fan_to(poly, inside, v, made)
					continue
				var part := poly
				for p: Plane in planes:
					next.append(_clip(part, p, true, v, made, spans))
					part = _clip(part, p, false, v, made, spans)
					if part.size() < 3:
						break
				_fan_to(part, inside, v, made)
			rest = next
		for poly in rest:
			_fan_to(poly, outside, v, made)
	if spans.is_empty():
		return [_subset(arr, outside, count), _subset(arr, inside, count)]
	# The arrays with the new corners on the end.
	var ext := arr.duplicate()
	for ch in Mesh.ARRAY_MAX:
		var src: Variant = arr[ch]
		if ch == Mesh.ARRAY_INDEX or src == null:
			continue
		var stride: int = src.size() / count
		var dst: Variant = src.duplicate()
		dst.resize((count + spans.size()) * stride)
		for j in spans.size():
			var a: int = spans[j][0]
			var b: int = spans[j][1]
			var t: float = spans[j][2]
			var o := (count + j) * stride
			if dst is PackedVector3Array:
				var w: Vector3 = (dst[a] as Vector3).lerp(dst[b], t)
				dst[o] = w.normalized() if ch == Mesh.ARRAY_NORMAL else w
			elif dst is PackedVector2Array:
				dst[o] = (dst[a] as Vector2).lerp(dst[b], t)
			elif dst is PackedColorArray:
				dst[o] = (dst[a] as Color).lerp(dst[b], t)
			elif dst is PackedFloat32Array:
				for e in stride:
					dst[o + e] = lerpf(dst[a * stride + e], dst[b * stride + e], t)
				if ch == Mesh.ARRAY_TANGENT:
					var tg := Vector3(dst[o], dst[o + 1], dst[o + 2]).normalized()
					dst[o] = tg.x
					dst[o + 1] = tg.y
					dst[o + 2] = tg.z
					dst[o + 3] = dst[a * stride + 3]
			else:
				# Bones and packed custom data are not blended: the nearer corner's.
				var near := a if t < 0.5 else b
				for e in stride:
					dst[o + e] = dst[near * stride + e]
		ext[ch] = dst
	return [_subset(ext, outside, count + spans.size()), _subset(ext, inside, count + spans.size())]


## The polygon `poly` (corner indices) clipped to the plus side of `p`, or to its
## minus side when `outer`. New corners go on `made` (their places) and `spans`.
func _clip(poly: PackedInt32Array, p: Plane, outer: bool, v: PackedVector3Array, made: Array[Vector3], spans: Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	var n := poly.size()
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var pa := _at(a, v, made)
		var pb := _at(b, v, made)
		var da := p.distance_to(pa) * (-1.0 if outer else 1.0)
		var db := p.distance_to(pb) * (-1.0 if outer else 1.0)
		if da >= 0.0:
			out.append(a)
		if (da >= 0.0) != (db >= 0.0):
			var t := da / (da - db)
			made.append(pa.lerp(pb, t))
			spans.append([a, b, t])
			out.append(v.size() + made.size() - 1)
	return out


## 1 if the polygon is all on the plus side of `p`, -1 if all on the minus
## side (or on it), 0 if across it.
func _where(poly: PackedInt32Array, p: Plane, v: PackedVector3Array, made: Array[Vector3]) -> int:
	var plus := 0
	var minus := 0
	for i in poly:
		var d := p.distance_to(_at(i, v, made))
		if d > 0.0:
			plus += 1
		elif d < 0.0:
			minus += 1
	if minus == 0 and plus > 0:
		return 1
	if plus == 0:
		return -1
	return 0


func _at(i: int, v: PackedVector3Array, made: Array[Vector3]) -> Vector3:
	return v[i] if i < v.size() else made[i - v.size()]


## A convex polygon as triangles (a fan), leaving out slivers with no area.
func _fan_to(poly: PackedInt32Array, into: PackedInt32Array, v: PackedVector3Array, made: Array[Vector3]) -> void:
	if poly.size() < 3:
		return
	for i in range(1, poly.size() - 1):
		var a := _at(poly[0], v, made)
		if (_at(poly[i], v, made) - a).cross(_at(poly[i + 1], v, made) - a).length_squared() > 1e-14:
			into.append_array([poly[0], poly[i], poly[i + 1]])


## The surface with only the triangles `tris`, and only the vertices they use;
## empty if there are none.
func _subset(arr: Array, tris: PackedInt32Array, count: int) -> Array:
	if tris.is_empty():
		return []
	return _compact(arr, tris, count)


## How far out (x) the body reaches at the given z, near the door's middle height.
func _outer_x(body: MeshInstance3D, z: float) -> float:
	var best := 0.0
	for s in body.mesh.get_surface_count():
		var v: PackedVector3Array = body.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		for p in v:
			var w := body.transform * p
			if absf(w.z - z) < 0.15 and w.y > 0.4 and w.y < 1.0:
				best = maxf(best, w.x)
	return best


## The surface arrays with only the vertices the triangles `tris` use.
func _compact(arr: Array, tris: PackedInt32Array, count: int) -> Array:
	var remap := {}
	var used := PackedInt32Array()
	var idx := PackedInt32Array()
	for i in tris:
		if not remap.has(i):
			remap[i] = used.size()
			used.append(i)
		idx.append(remap[i])
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	for k in Mesh.ARRAY_MAX:
		var src: Variant = arr[k]
		if k == Mesh.ARRAY_INDEX or src == null:
			continue
		var stride: int = src.size() / count
		var dst: Variant = src.duplicate()
		dst.resize(used.size() * stride)
		for n in used.size():
			for e in stride:
				dst[n * stride + e] = src[used[n] * stride + e]
		out[k] = dst
	out[Mesh.ARRAY_INDEX] = idx
	return out


func _all(n: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(n)
	for i in n:
		out[i] = i
	return out
