extends SceneTree
## Headless check of how the car slides on a large flat pad.
## Run:  godot --headless --path . --script res://tools/drift_test.gd

var car: VehicleBody3D


func _initialize() -> void:
	_run.call_deferred()


func _hold(actions: Array, seconds: float, label: String) -> void:
	for a: String in ["accelerate", "brake", "steer_left", "steer_right", "handbrake"]:
		if a in actions:
			Input.action_press(a)
		else:
			Input.action_release(a)
	var peak := 0.0
	var line := ""
	for i in int(seconds * 60.0):
		await physics_frame
		var slip := rad_to_deg(car.slip_angle())
		peak = maxf(peak, absf(slip))
		if i % 30 == 29:
			line += "%.0f " % slip
	if label != "":
		print("  %-26s end %3.0f km/h, peak slide %2.0f deg, yaw %5.2f rad/s, up %.2f | slide each 0.5 s: %s" % [
			label, car.linear_velocity.length() * 3.6, peak, car.angular_velocity.y, car.global_basis.y.y, line])


func _reset() -> void:
	car.place(Transform3D(Basis.IDENTITY, Vector3(0, 0.3, -300)))
	await _hold([], 1.0, "")


func _run() -> void:
	var ground := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var pad := BoxShape3D.new()
	pad.size = Vector3(1600, 1, 1600)
	cs.shape = pad
	cs.position = Vector3(0, -0.5, 0)
	ground.add_child(cs)
	root.add_child(ground)
	car = load("res://car/e50_amg.scn").instantiate()
	root.add_child(car)

	print("Gentle corner, no throttle:")
	await _reset()
	await _hold(["accelerate"], 3.0, "accelerate")
	await _hold(["steer_left"], 3.0, "coast and steer")

	print("Corner on full throttle (power slide):")
	await _reset()
	await _hold(["accelerate"], 3.0, "accelerate")
	await _hold(["accelerate", "steer_left"], 5.0, "throttle + steer")
	await _hold(["accelerate"], 2.0, "straighten, keep throttle")

	print("Handbrake turn:")
	await _reset()
	await _hold(["accelerate"], 4.5, "accelerate")
	await _hold(["steer_left", "handbrake"], 0.8, "steer + handbrake")
	await _hold(["accelerate", "steer_left"], 3.0, "throttle + steer")
	await _hold([], 2.0, "let go of everything")

	print("Flick at speed:")
	await _reset()
	await _hold(["accelerate"], 8.0, "accelerate")
	await _hold(["accelerate", "steer_left"], 1.0, "steer left")
	await _hold(["accelerate", "steer_right"], 1.5, "steer right")
	await _hold(["accelerate"], 2.0, "straighten")
	quit()
