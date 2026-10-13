extends SceneTree
## Renders preview images of the main scene into the given folder.
## Run:  godot --path . --script res://tools/screenshot.gd -- <output folder>


func _initialize() -> void:
	_run.call_deferred()


func _shot(path: String) -> void:
	for i in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("wrote ", path)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else OS.get_user_data_dir()
	var main: Node3D = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _shot(out.path_join("drive.png"))

	var car: Node3D = main.get_node("Car")
	var cam := Camera3D.new()
	cam.far = 8000.0
	main.add_child(cam)
	cam.make_current()
	cam.global_position = car.global_position + Vector3(-120, 90, 160)
	cam.look_at(car.global_position)
	await _shot(out.path_join("low_aerial.png"))
	cam.global_position = Vector3(-900, 1500, 2600)
	cam.look_at(Vector3(0, 0, 200))
	await _shot(out.path_join("aerial.png"))
	quit()
