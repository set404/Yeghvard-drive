extends Node3D

const BEAM_NAMES := ["", "PARK", "LOW", "HIGH"]
## The fuel gauge turns amber below this share of the tank, and blinks red on the reserve.
const LOW_FUEL := 0.15
const FUEL_OK := Color(0.3, 0.75, 0.35)
const FUEL_LOW := Color(0.95, 0.65, 0.1)
const FUEL_EMPTY := Color(0.9, 0.15, 0.1)

## How close (metres, to the middle of the car) you have to stand for F to get you in.
@export var enter_distance := 4.5
## F only gets you out once the car is down to this speed (km/h).
@export var max_exit_speed := 20.0
## Litres a second the pump puts in while you hold T.
@export var refuel_rate := 8.0
## The car you are driving when the game starts. Empty means the node named "Car".
@export var start_car: VehicleBody3D

## The car being driven, or the last one you drove while you are on foot.
## Every car is in the "cars" group; the others are parked.
@onready var car: VehicleBody3D = $Car
## You, when you are out of the car.
@onready var player: CharacterBody3D = $Player
@onready var camera: Camera3D = $ChaseCamera
@onready var minimap: Control = $HUD/Minimap
@onready var speed_label: Label = $HUD/Speed
@onready var power_bar: ProgressBar = $HUD/Power
@onready var power_label: Label = $HUD/Power/Label
@onready var fuel_bar: ProgressBar = $HUD/Fuel
@onready var fuel_label: Label = $HUD/Fuel/Label
@onready var lights_label: Label = $HUD/Lights
@onready var prompt_label: Label = $HUD/Prompt
## Only cars built with lamps have this node. Null while on foot.
var lamps: Node
var on_foot := false
## Seconds left of getting into or out of a car, and which car and which way.
var _door_time := 0.0
var _door_car: VehicleBody3D
var _door_in := false


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
		# The cars standing about are parked; the one you start in is ready to go.
		other.parked = other != car
	_drive(car, true)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or _door_time > 0.0:
		return
	# For testing: 1, 2, 3... put you straight into that car, wherever it is,
	# in the order the cars come in this scene.
	var number := key.physical_keycode - KEY_1
	if number >= 0 and number < 9:
		var cars := get_tree().get_nodes_in_group("cars")
		if number < cars.size():
			_drive(cars[number], true)
		return
	# F gets you in or out; E (the starter) belongs to the car, see car.gd.
	if key.physical_keycode != KEY_F:
		return
	if on_foot:
		var other := _car_in_reach()
		if other:
			_get_in(other)
	elif _slow_enough_to_leave():
		_leave()


## Walks you into the driver's seat of the car, then hands it to you.
func _get_in(other: VehicleBody3D) -> void:
	player.set_active(false)
	minimap.target = other
	camera.follow(other)
	var seconds: float = player.sit_in(other, true)
	if seconds <= 0.0:
		_drive(other)
		return
	_door_car = other
	_door_in = true
	_door_time = seconds


## Stops driving and climbs you out of the car.
func _leave() -> void:
	car.player_controlled = false
	var seconds: float = player.get_out()
	if seconds <= 0.0:
		_get_out()
		return
	_door_car = car
	_door_in = false
	_door_time = seconds


## Puts you in the given car and hands it the controls, camera and HUD.
func _drive(next: VehicleBody3D, jump_camera := false) -> void:
	for other: VehicleBody3D in get_tree().get_nodes_in_group("cars"):
		other.player_controlled = other == next
	car = next
	on_foot = false
	player.set_active(false)
	# You, at the wheel of the car you drive (hidden in the driver's-seat view).
	if player.seated_in() != car:
		player.sit_in(car)
	lamps = car.get_node_or_null("Lamps")
	lights_label.visible = lamps != null
	speed_label.visible = true
	power_bar.visible = true
	fuel_bar.visible = true
	minimap.target = car
	camera.follow(car, jump_camera)


## Leaves the car where it is and stands you beside it.
func _get_out() -> void:
	car.player_controlled = false
	# Where climbing out left you, if there is room to stand there.
	var spot: Dictionary = player.exit_spot()
	var feet: Vector3 = spot["feet"] + Vector3.UP * 0.3 if spot else Vector3.ZERO
	if spot and _room_to_stand(feet):
		player.place(feet, spot["facing"])
	else:
		player.place(_exit_spot(car), car.global_basis.z)
	player.stand_up()
	player.set_active(true)
	on_foot = true
	lamps = null
	lights_label.visible = false
	speed_label.visible = false
	power_bar.visible = false
	fuel_bar.visible = false
	minimap.target = player
	camera.follow(player)


## P in park, R going backwards, otherwise D and the gear the box is in.
func _gear_letter() -> String:
	if car.parked:
		return "P"
	if car.forward_speed() < -0.5 or car.engine_force < 0.0:
		return "R"
	return "D%d" % car.gear


func _slow_enough_to_leave() -> bool:
	return absf(car.forward_speed()) * 3.6 <= max_exit_speed


## Where your feet go when you get out: by the driver's door, or failing that the
## other door, behind or in front of the car, or as a last resort on the roof.
func _exit_spot(from: VehicleBody3D) -> Vector3:
	# The driver sits on the side driver_view says (+X is the car's left).
	var eyes: Vector3 = from.get("driver_view") if from.get("driver_view") is Vector3 else Vector3(0.37, 1.1, 0.0)
	var side := 1.0 if eyes.x >= 0.0 else -1.0
	var half := _half_size(from)
	var out := half.x + 0.55
	var candidates := [
		Vector3(side * out, 0.0, eyes.z),
		Vector3(-side * out, 0.0, eyes.z),
		Vector3(0.0, 0.0, -half.z - 0.7),
		Vector3(0.0, 0.0, half.z + 0.7),
	]
	for local: Vector3 in candidates:
		var at := from.global_transform * local
		at.y = from.global_position.y
		if _room_to_stand(at):
			return at
	return from.global_transform * Vector3(0.0, half.y + 0.3, 0.0)


## How far a car's collision boxes reach from its origin along each axis (its
## half width, roof height and half length), in its own space.
func _half_size(body: VehicleBody3D) -> Vector3:
	var half := Vector3(0.95, 0.75, 2.3)
	var found := false
	for child in body.get_children():
		var cs := child as CollisionShape3D
		if cs == null or not cs.shape is BoxShape3D:
			continue
		var box: Vector3 = (cs.shape as BoxShape3D).size * 0.5
		var reach := cs.position.abs() + box
		half = reach if not found else half.max(reach)
		found = true
	return half


## Whether a person fits standing at this spot (feet roughly at its height).
func _room_to_stand(feet: Vector3) -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.4
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	# Lifted off the ground a little, so a slope or kerb does not count as in the way.
	query.transform = Transform3D(Basis.IDENTITY, feet + Vector3.UP * 1.05)
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


## The nearest car you are standing close enough to get into, or null.
func _car_in_reach() -> VehicleBody3D:
	if not on_foot:
		return null
	var best: VehicleBody3D = null
	var best_distance := enter_distance
	var me := player.global_position
	for other: VehicleBody3D in get_tree().get_nodes_in_group("cars"):
		var d := Vector2(other.global_position.x - me.x, other.global_position.z - me.z).length()
		if d < best_distance and absf(other.global_position.y - me.y) < 3.0:
			best = other
			best_distance = d
	return best


func _process(delta: float) -> void:
	player.show_seated(camera.get("view") != 3 or _door_time > 0.0) # 3: chase_camera.gd's View.DRIVER
	if _door_time > 0.0:
		player.update_seated()
		_door_time -= delta
		prompt_label.visible = false
		if _door_time <= 0.0:
			if _door_in:
				_drive(_door_car)
			else:
				_get_out()
		return
	var hints := PackedStringArray()
	if on_foot:
		if _car_in_reach():
			hints.append("Press F to get in")
	else:
		_refuel(delta, hints)
		speed_label.text = "%s   %d km/h" % [_gear_letter(), absf(car.forward_speed() * 3.6)]
		power_bar.value = car.output_hp / car.horsepower * 100.0
		power_label.text = "%d / %d hp" % [car.output_hp, car.horsepower]
		_show_fuel()
		if car.cranking:
			power_label.text = "starting..."
			hints.append("Starting...")
		elif not car.engine_running:
			power_label.text = "engine off"
			if car.fuel <= 0.0:
				hints.append("Out of fuel")
			elif car.start_failed:
				hints.append("It didn't start. Press E to try again")
			else:
				hints.append("Press E to start the engine")
		if car.parked and car.engine_running and (Input.is_action_pressed("accelerate") or Input.is_action_pressed("brake")):
			hints.append("In park: press P to drive")
		if absf(car.forward_speed()) < 1.0:
			hints.append("Press F to get out")
	for gate in get_tree().get_nodes_in_group("gates"):
		if gate.is_nearest():
			hints.append("Press G to %s the %s" % ["close" if gate.is_open else "open", gate.label])
			break
	prompt_label.text = "\n".join(hints)
	prompt_label.visible = not hints.is_empty()
	if lamps:
		var blink: bool = lamps.blink_on()
		lights_label.text = "%s   %s   %s" % [
			"<<" if lamps.signal_left and blink else "    ",
			BEAM_NAMES[lamps.beam],
			">>" if lamps.signal_right and blink else "    "]


## Whether the car you are in stands at a fuel pump (see tools/build_gas_station.gd).
func _at_pump() -> bool:
	for pumps: Area3D in get_tree().get_nodes_in_group("fuel_pumps"):
		if pumps.overlaps_body(car):
			return true
	return false


## At a pump with the car stopped and the engine off, holding T fills the tank.
func _refuel(delta: float, hints: PackedStringArray) -> void:
	if not _at_pump() or absf(car.forward_speed()) > 1.0:
		return
	if car.fuel >= car.fuel_capacity - 0.05:
		hints.append("Tank full")
	elif car.engine_running:
		hints.append("Stop the engine (E) to refuel")
	elif Input.is_physical_key_pressed(KEY_T):
		car.refuel(refuel_rate * delta)
		hints.append("Refuelling...  %d / %d L" % [ceili(car.fuel), roundi(car.fuel_capacity)])
	else:
		hints.append("Hold T to refuel")


## The fuel gauge: litres left, green, amber when low, blinking red on the reserve.
func _show_fuel() -> void:
	var level: float = car.fuel_level()
	fuel_bar.value = level * 100.0
	fuel_label.text = "FUEL  %d / %d L" % [ceili(car.fuel), roundi(car.fuel_capacity)]
	var fill := fuel_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if car.on_reserve():
		var blink := fmod(Time.get_ticks_msec() / 1000.0, 0.8) < 0.4
		fill.bg_color = FUEL_EMPTY if blink or level <= 0.0 else FUEL_LOW
	elif level < LOW_FUEL:
		fill.bg_color = FUEL_LOW
	else:
		fill.bg_color = FUEL_OK


## Stands a car on whatever ground is at its position, keeping the way it faces.
func _set_on_ground(body: VehicleBody3D) -> void:
	var at := body.global_position
	var exclude: Array[RID] = []
	for other: VehicleBody3D in get_tree().get_nodes_in_group("cars"):
		exclude.append(other.get_rid())
	# First from a little above where it was put, so the roof over a car in a
	# garage does not count; from high up if it was put under the ground.
	var hit := {}
	for above: float in [1.5, 400.0]:
		var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * above, at + Vector3.DOWN * 400.0)
		query.exclude = exclude
		hit = get_world_3d().direct_space_state.intersect_ray(query)
		if hit:
			break
	if hit:
		at.y = hit["position"].y + 0.4
	var nose := body.global_basis.z.slide(Vector3.UP).normalized()
	if nose.is_zero_approx():
		nose = Vector3.BACK
	body.place(Transform3D(Basis.looking_at(-nose), at))
