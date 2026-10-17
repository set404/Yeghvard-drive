extends SceneTree
## Cuts the driver's door out of the body of each car built by
## tools/build_car.gd (car/*.scn), so it can swing open while you get in and
## out (player/player.gd opens it). Run it again after rebuilding a car.
##
## The models (but for the E50's) have their doors fused into the body, so the
## door is taken as every part of the body that lies, seen from the side, inside
## the door's outline, and on the outer part of the car's left side (+X: the
## driver sits on the left). The result is a node "DriverDoor" on the car,
## standing on the door's front edge (its hinges), with the door as its child
## "Mesh"; turning it about its Y axis swings the door.
##
## Run:  godot --path . --script res://tools/build_car_doors.gd

## Per car: the door's outline seen from the left, as (z, y) points in the car's
## space (front edge first, at the bottom), and how far out (x) the door starts.
const DOORS := {
	"res://car/e50_amg.scn": {"outline": [Vector2(0.90, 0.30), Vector2(0.90, 1.02), Vector2(0.55, 1.42), Vector2(-0.13, 1.42), Vector2(-0.13, 0.30)], "inner": 0.62},
	"res://car/e55_amg.scn": {"outline": [Vector2(0.93, 0.33), Vector2(0.93, 1.0), Vector2(0.60, 1.42), Vector2(-0.25, 1.42), Vector2(-0.25, 0.33)], "inner": 0.62},
	"res://car/volga_3102.scn": {"outline": [Vector2(0.88, 0.18), Vector2(0.88, 0.95), Vector2(0.50, 1.27), Vector2(-0.04, 1.27), Vector2(-0.04, 0.18)], "inner": 0.60},
	"res://car/land_cruiser_80.scn": {"outline": [Vector2(0.75, 0.48), Vector2(0.75, 1.2), Vector2(0.45, 1.78), Vector2(-0.285, 1.78), Vector2(-0.285, 0.48)], "inner": 0.70},
	"res://car/jeep_compass.scn": {"outline": [Vector2(0.78, 0.38), Vector2(0.78, 1.05), Vector2(0.45, 1.47), Vector2(-0.25, 1.47), Vector2(-0.25, 0.38)], "inner": 0.55},
}


func _initialize() -> void:
	var failed := false
	for path: String in DOORS:
		if _cut(path, DOORS[path]) != OK:
			failed = true
	quit(1 if failed else 0)


func _cut(path: String, door: Dictionary) -> Error:
	var car: Node3D = (load(path) as PackedScene).instantiate()
	if car.has_node("DriverDoor"):
		print("%s: already has its door" % path)
		car.free()
		return OK
	var body := car.get_node("Body") as MeshInstance3D
	var outline := PackedVector2Array(door["outline"])
	var inner: float = door["inner"]
	# The hinge: the door's front edge, on the outside of the car.
	var front := outline[0].x
	var hinge := Vector3(_outer_x(body, front), (outline[0].y + outline[1].y) * 0.5, front)

	var kept := ArrayMesh.new()
	var cut := ArrayMesh.new()
	var moved := 0
	for s in body.mesh.get_surface_count():
		var arr := body.mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else _all(v.size())
		var keep := PackedInt32Array()
		var take := PackedInt32Array()
		for k in range(0, idx.size(), 3):
			var c := (body.transform * v[idx[k]] + body.transform * v[idx[k + 1]] + body.transform * v[idx[k + 2]]) / 3.0
			if c.x > inner and Geometry2D.is_point_in_polygon(Vector2(c.z, c.y), outline):
				take.append_array([idx[k], idx[k + 1], idx[k + 2]])
			else:
				keep.append_array([idx[k], idx[k + 1], idx[k + 2]])
		var mat := body.mesh.surface_get_material(s)
		# Custom channels and compression come from the surface's own format.
		var flags: int = body.mesh.surface_get_format(s) & ~((1 << Mesh.ARRAY_FORMAT_CUSTOM_BASE) - 1)
		if not keep.is_empty():
			var a := arr.duplicate()
			a[Mesh.ARRAY_INDEX] = keep
			kept.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a, [], {}, flags)
			kept.surface_set_material(kept.get_surface_count() - 1, mat)
			kept.surface_set_name(kept.get_surface_count() - 1, body.mesh.surface_get_name(s))
		if not take.is_empty():
			# The door's own copy, moved so the hinge is its origin.
			var a := arr.duplicate()
			var dv := PackedVector3Array()
			dv.resize(v.size())
			for i in v.size():
				dv[i] = body.transform * v[i] - hinge
			a[Mesh.ARRAY_VERTEX] = dv
			a[Mesh.ARRAY_INDEX] = take
			cut.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a, [], {}, flags)
			cut.surface_set_material(cut.get_surface_count() - 1, mat)
			moved += take.size() / 3
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


func _all(n: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(n)
	for i in n:
		out[i] = i
	return out
