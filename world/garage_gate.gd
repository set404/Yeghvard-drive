extends Node3D
## A steel gate built by tools/build_house.gd (the garage and the yard gate):
## two leaves that swing out towards its +Z. G opens or closes the nearest gate
## within reach of the car being driven, or of you on foot.

@export var reach := 14.0 ## metres
## What the on-screen hint calls it: "Press G to open the <label>".
@export var label := "garage"
@export var open_angle := 105.0 ## degrees
@export var seconds := 1.8 ## time to swing fully open or shut

var is_open := false
## 0 shut .. 1 fully open
var _swing := 0.0
var _sound: AudioStreamPlayer3D

@onready var _left: Node3D = $LeafL
@onready var _right: Node3D = $LeafR
## Every piece of what stops a car (a gate with a door for people has several).
@onready var _blocker_shapes: Array[Node] = $Blocker.find_children("*", "CollisionShape3D", false, false)


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


## How far the car being driven, or you on foot, is from the gate.
func driver_distance() -> float:
	var tree := get_tree()
	var best := INF
	for who: Node3D in tree.get_nodes_in_group("cars") + tree.get_nodes_in_group("walkers"):
		if who.get("player_controlled"):
			best = minf(best, who.global_position.distance_to(global_position))
	return best


## Whether the car the player is driving, or the player on foot, is near enough to work the gate.
func driver_in_reach() -> bool:
	return driver_distance() < reach


## Whether G works this gate now: it is in reach and no other gate in reach is nearer.
func is_nearest() -> bool:
	var mine := driver_distance()
	if mine >= reach:
		return false
	for gate in get_tree().get_nodes_in_group("gates"):
		if gate != self and gate.driver_in_reach() and gate.driver_distance() < mine:
			return false
	return true


func toggle() -> void:
	is_open = not is_open
	if _sound:
		_sound.play()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.physical_keycode == KEY_G and is_nearest():
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
	for shape: CollisionShape3D in _blocker_shapes:
		shape.disabled = _swing > 0.05
