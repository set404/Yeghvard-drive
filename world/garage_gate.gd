extends Node3D
## A garage gate built by tools/build_world.gd: two leaves that swing outwards.
## G opens or closes it when the car being driven is close enough.

@export var reach := 14.0 ## metres
@export var open_angle := 105.0 ## degrees
@export var seconds := 1.8 ## time to swing fully open or shut

var is_open := false
## 0 shut .. 1 fully open
var _swing := 0.0
var _sound: AudioStreamPlayer3D

@onready var _left: Node3D = $LeafL
@onready var _right: Node3D = $LeafR
@onready var _blocker_shape: CollisionShape3D = $Blocker/CollisionShape3D


func _ready() -> void:
	add_to_group("gates")
	# The swing takes as long as the recording of the hinges (see tools/build_sounds.gd).
	if ResourceLoader.exists("res://audio/gate.res"):
		_sound = AudioStreamPlayer3D.new()
		_sound.stream = load("res://audio/gate.res")
		_sound.position = Vector3(0.0, 1.2, 0.0)
		_sound.unit_size = 12.0
		_sound.max_distance = 90.0
		add_child(_sound)


## Whether the car the player is driving is near enough to work the gate.
func driver_in_reach() -> bool:
	for car: Node3D in get_tree().get_nodes_in_group("cars"):
		if car.get("player_controlled") and car.global_position.distance_to(global_position) < reach:
			return true
	return false


func toggle() -> void:
	is_open = not is_open
	if _sound:
		_sound.play()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.physical_keycode == KEY_G and driver_in_reach():
		toggle()


func _process(delta: float) -> void:
	var target := 1.0 if is_open else 0.0
	if _swing == target:
		return
	_swing = move_toward(_swing, target, delta / seconds)
	var angle := deg_to_rad(open_angle) * smoothstep(0.0, 1.0, _swing)
	# The free edges come out towards +Z, the outside.
	_left.rotation.y = -angle
	_right.rotation.y = angle
	# The leaves are not solid while they move or stand open, so a car parked in
	# front of them is not thrown aside; shut, the gate blocks the doorway.
	_blocker_shape.disabled = _swing > 0.05
