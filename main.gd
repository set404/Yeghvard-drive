extends Node3D

const BEAM_NAMES := ["", "PARK", "LOW", "HIGH"]

## How close (metres) another car has to be before E gets you into it.
@export var switch_distance := 7.0
## The car you are driving when the game starts. Empty means the node named "Car".
@export var start_car: VehicleBody3D

## The car being driven. Every car is in the "cars" group; the others are parked.
@onready var car: VehicleBody3D = $Car
@onready var camera: Camera3D = $ChaseCamera
@onready var minimap: Control = $HUD/Minimap
@onready var speed_label: Label = $HUD/Speed
@onready var power_bar: ProgressBar = $HUD/Power
@onready var power_label: Label = $HUD/Power/Label
@onready var lights_label: Label = $HUD/Lights
@onready var prompt_label: Label = $HUD/Prompt
## Only cars built with lamps have this node.
var lamps: Node


func _ready() -> void:
	# Every car starts wherever it stands in this scene (move it in the editor)
	# and is set down on the ground at that spot. A car left at the scene origin
	# has not been placed, so it goes to the spawn point on the road instead.
	if start_car:
		car = start_car
	await get_tree().physics_frame
	for other: VehicleBody3D in get_tree().get_nodes_in_group("cars"):
		if other.position.is_zero_approx():
			# The spawn marker's -Z runs along a road; cars drive towards their +Z.
			var spawn: Marker3D = $World/Spawn
			other.place(spawn.global_transform.rotated_local(Vector3.UP, PI))
		else:
			_set_on_ground(other)
	_drive(car)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.physical_keycode == KEY_E:
		var other := _car_in_reach()
		if other:
			_drive(other)


## Hands the controls, camera and HUD over to the given car.
func _drive(next: VehicleBody3D) -> void:
	for other: VehicleBody3D in get_tree().get_nodes_in_group("cars"):
		other.player_controlled = other == next
	car = next
	lamps = car.get_node_or_null("Lamps")
	lights_label.visible = lamps != null
	minimap.target = car
	camera.target = car
	camera.snap()


## The nearest other car within switch_distance, or null.
func _car_in_reach() -> VehicleBody3D:
	var best: VehicleBody3D = null
	var best_distance := switch_distance
	for other: VehicleBody3D in get_tree().get_nodes_in_group("cars"):
		if other == car:
			continue
		var d := other.global_position.distance_to(car.global_position)
		if d < best_distance:
			best = other
			best_distance = d
	return best


func _process(_delta: float) -> void:
	speed_label.text = "%d km/h" % absf(car.forward_speed() * 3.6)
	power_bar.value = car.output_hp / car.horsepower * 100.0
	power_label.text = "%d / %d hp" % [car.output_hp, car.horsepower]
	var hints := PackedStringArray()
	if _car_in_reach():
		hints.append("Press E to switch car")
	for gate in get_tree().get_nodes_in_group("gates"):
		if gate.driver_in_reach():
			hints.append("Press G to %s the garage" % ("close" if gate.is_open else "open"))
			break
	prompt_label.text = "\n".join(hints)
	prompt_label.visible = not hints.is_empty()
	if lamps:
		var blink: bool = lamps.blink_on()
		lights_label.text = "%s   %s   %s" % [
			"<<" if lamps.signal_left and blink else "    ",
			BEAM_NAMES[lamps.beam],
			">>" if lamps.signal_right and blink else "    "]


## Stands a car on whatever ground is at its position, keeping the way it faces.
func _set_on_ground(body: VehicleBody3D) -> void:
	var at := body.global_position
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 400.0, at + Vector3.DOWN * 400.0)
	var exclude: Array[RID] = []
	for other: VehicleBody3D in get_tree().get_nodes_in_group("cars"):
		exclude.append(other.get_rid())
	query.exclude = exclude
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit:
		at.y = hit["position"].y + 0.4
	var nose := body.global_basis.z.slide(Vector3.UP).normalized()
	if nose.is_zero_approx():
		nose = Vector3.BACK
	body.place(Transform3D(Basis.looking_at(-nose), at))
