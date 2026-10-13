extends SceneTree
## Headless check of acceleration and top speed on a long flat strip.
## Run:  godot --headless --path . --script res://tools/top_speed_test.gd


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var ground := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	# A long strip rather than a WorldBoundaryShape3D, which Jolt ends 1 km out.
	var strip := BoxShape3D.new()
	strip.size = Vector3(40, 1, 8000)
	cs.shape = strip
	cs.position = Vector3(0, -0.5, 3900)
	ground.add_child(cs)
	root.add_child(ground)
	var car: VehicleBody3D = load("res://car/e50_amg.scn").instantiate()
	root.add_child(car)
	car.global_position = Vector3(0, 0.6, 0)
	for i in 60:
		await physics_frame
	Input.action_press("accelerate")
	var to_100 := -1.0
	for i in 60 * 60:
		await physics_frame
		var kmh: float = car.forward_speed() * 3.6
		if to_100 < 0.0 and kmh >= 100.0:
			to_100 = i / 60.0
		if i % 300 == 0:
			var contact := 0
			var slip := ""
			for w in car.get_children():
				if w is VehicleWheel3D:
					contact += int(w.is_in_contact())
					slip += "%.2f " % w.get_skidinfo()
			print("t=%2d s  %5.1f km/h  %3.0f hp  wheels down %d  grip %s y=%.2f" % [i / 60, kmh, car.output_hp, contact, slip, car.global_position.y])
	print("0-100 km/h: %.1f s" % to_100)
	quit()
