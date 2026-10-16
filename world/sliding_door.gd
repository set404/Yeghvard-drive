extends Node3D
## An automatic glass door of the supermarket built by tools/build_supermarket.gd:
## its two leaves slide apart when you walk up to it and close again once you
## have gone.
##
## The node sits in the middle of the threshold with +X running across the
## doorway; the leaves are the children "Left" and "Right".

@export var width := 2.0 ## metres between the jambs
@export var reach := 2.6 ## metres from the middle of the threshold
@export var seconds := 0.8 ## time to open or close fully

## 0 shut .. 1 fully open
var _open := 0.0
@onready var _left: Node3D = $Left
@onready var _right: Node3D = $Right


func _process(delta: float) -> void:
	var wanted := 0.0
	for who: Node3D in get_tree().get_nodes_in_group("walkers"):
		if who.get("player_controlled") and who.global_position.distance_to(global_position) < reach:
			wanted = 1.0
	if _open == wanted:
		return
	_open = move_toward(_open, wanted, delta / seconds)
	var shift := width * 0.5 * smoothstep(0.0, 1.0, _open)
	_left.position.x = -shift
	_right.position.x = shift
