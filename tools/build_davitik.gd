extends SceneTree
## Builds res://npc/davitik.scn, Davitik's figure (npc/davitik.gd), from his
## model data/models/special characters/Davitik/Davitik.fbx and the shared
## animations in data/models/animations: see npc/davitik_figure.gd, which does
## the work. Optional: without this file the game makes the figure itself the
## first time he appears (a few seconds) and keeps it in user://.
##
## Run:  godot --headless --path . --script res://tools/build_davitik.gd

const DavitikFigure := preload("res://npc/davitik_figure.gd")
const OUT := "res://npc/davitik.scn"


func _initialize() -> void:
	var figure := DavitikFigure.make()
	if figure == null:
		quit(1)
		return
	DavitikFigure._own(figure, figure)
	var scene := PackedScene.new()
	var err := scene.pack(figure)
	if err == OK:
		err = ResourceSaver.save(scene, OUT, ResourceSaver.FLAG_COMPRESS)
	figure.free()
	print("Saved %s (%s)" % [OUT, error_string(err)])
	quit(0 if err == OK else 1)
