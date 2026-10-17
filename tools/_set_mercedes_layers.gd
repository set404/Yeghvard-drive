extends SceneTree
## One-off: points the two Mercedes at their engine loops cut from the Barracuda V8
## recording (tools/engine_layers). Run after tools/build_sounds.gd.
const SETS := {
	"res://car/e55_amg.scn": ["e55_0800", "e55_1100", "e55_1350", "e55_1800", "e55_2400", "e55_3100", "e55_4000", "e55_5200"],
	"res://car/e50_amg.scn": ["e50_0800", "e55_1100", "e55_1350", "e55_1800", "e55_2400", "e55_3100", "e55_4000", "e55_5200"],
}
func _initialize() -> void:
	for path: String in SETS:
		var car: Node = (load(path) as PackedScene).instantiate()
		var streams: Array[AudioStream] = []
		var rpms := PackedFloat32Array()
		for n: String in SETS[path]:
			streams.append(load("res://audio/layers/%s.res" % n) as AudioStream)
			rpms.append(float(n.get_slice("_", 1)))
		car.engine_layers = streams
		car.engine_layer_rpms = rpms
		var scene := PackedScene.new()
		var err := scene.pack(car)
		if err == OK:
			err = ResourceSaver.save(scene, path, ResourceSaver.FLAG_COMPRESS)
		print(path, " ", rpms, " ", error_string(err))
		car.free()
	quit()
