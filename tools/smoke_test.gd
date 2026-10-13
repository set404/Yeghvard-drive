extends SceneTree
## Headless check: terrain collision matches the mesh and the car drives.
## Run:  godot --headless --path . --script res://tools/smoke_test.gd


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Node3D = load("res://main.tscn").instantiate()
	root.add_child(main)
	var car: VehicleBody3D = main.get_node("Car")
	# The parked car stands in the straight line this test drives; move it out of the way.
	main.get_node("Car2").place(Transform3D(Basis.IDENTITY, Vector3(300, 80, 300)))
	for i in 5:
		await physics_frame

	var space := main.get_world_3d().direct_space_state
	var world := main.get_node("World")
	for p: Vector2 in [Vector2(-1800, -1500), Vector2(1700, -900), Vector2(-600, 2000), Vector2(900, 1300)]:
		var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 500, p.y), Vector3(p.x, -500, p.y))
		var hit := space.intersect_ray(q)
		var where: Vector3 = hit.get("position", Vector3.ZERO)
		print("ray at %s: collision y=%.2f on %s, mesh y=%.2f" % [p, where.y, hit.get("collider"), _mesh_height(world, p)])

	var start := car.global_position
	print("spawn %s" % start)
	for i in 120:
		await physics_frame
	print("settled y=%.2f (dropped %.2f), up=%.2f" % [car.global_position.y, start.y - car.global_position.y, car.global_basis.y.y])
	var before := car.global_transform
	Input.action_press("accelerate")
	for i in 300:
		if i % 30 == 0:
			print("  t=%.1f s  %.1f km/h  %.0f hp" % [i / 60.0, car.forward_speed() * 3.6, car.output_hp])
		await physics_frame
	var moved := before.basis.inverse() * (car.global_position - before.origin)
	print("after 5 s throttle: local move %s, speed %.1f km/h, output %.0f of %.0f hp, up=%.2f" % [moved, car.forward_speed() * 3.6, car.output_hp, car.horsepower, car.global_basis.y.y])
	Input.action_press("steer_left")
	var yaw0 := car.global_rotation.y
	for i in 60:
		await physics_frame
	print("steer_left for 1 s: yaw change %.2f rad, up=%.2f" % [angle_difference(yaw0, car.global_rotation.y), car.global_basis.y.y])
	Input.action_release("accelerate")
	Input.action_release("steer_left")
	quit()


func _mesh_height(world: Node, p: Vector2) -> float:
	for mi: MeshInstance3D in world.get_node("Terrain").find_children("Chunk_*", "MeshInstance3D", false, false):
		var box := mi.get_aabb()
		if p.x < box.position.x or p.x > box.end.x or p.y < box.position.z or p.y > box.end.z:
			continue
		var f := mi.mesh.get_faces()
		for k in range(0, f.size(), 3):
			var hit: Variant = Geometry3D.ray_intersects_triangle(Vector3(p.x, 1000, p.y), Vector3.DOWN, f[k], f[k + 1], f[k + 2])
			if hit != null:
				return hit.y
	return NAN
