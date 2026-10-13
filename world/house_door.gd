extends Node3D
## A door of the house built by tools/build_house.gd. It swings open by itself
## when you walk up to it and shuts again once you have gone.
##
## The node sits on the hinge with +X running across the doorway; the leaf is
## the child "Leaf".

@export var width := 0.9 ## metres across the doorway
@export var open_angle := 95.0 ## degrees; the sign picks the side it swings to
@export var reach := 1.6 ## metres from the middle of the doorway
@export var seconds := 0.7 ## time to swing fully open or shut

## 0 shut .. 1 fully open
var _swing := 0.0
@onready var _leaf: Node3D = $Leaf


func _process(delta: float) -> void:
	# The middle of the threshold; the walkers' positions are their feet.
	var centre := to_global(Vector3(width * 0.5, 0.0, 0.0))
	var wanted := 0.0
	for who: Node3D in get_tree().get_nodes_in_group("walkers"):
		if who.get("player_controlled") and who.global_position.distance_to(centre) < reach:
			wanted = 1.0
	if _swing == wanted:
		return
	_swing = move_toward(_swing, wanted, delta / seconds)
	_leaf.rotation.y = deg_to_rad(open_angle) * smoothstep(0.0, 1.0, _swing)
