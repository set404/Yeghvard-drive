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
## What a litre of fuel costs at the pump, in drams (see game/wallet.gd).
@export var fuel_price := 490.0
## The car you are driving when the game starts. Empty means the node named "Car".
@export var start_car: VehicleBody3D
## Start on foot outside the house's front door (the car above parked nearby)
## rather than at the wheel.
@export var start_at_house := true

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
@onready var money_label: Label = $HUD/Money
## The key help in the top left corner; I shows or hides it.
@onready var help_label: Label = $HUD/Help
## Whether the key help is on screen when the game starts.
@export var show_help_at_start := false
## Seconds of play left to remind you that I shows the key help.
var _help_hint_left := 8.0
## Your money.
@onready var wallet: Wallet = $Wallet
## What you carry; the selected item is in your hand (see game/inventory.gd).
var inventory: Inventory
## The story missions (game/mission_manager.gd); made in _ready.
var missions: MissionManager
## Fighting and shooting on foot (player/combat.gd); made in _ready.
var combat: Combat
## Only cars built with lamps have this node. Null while on foot.
var lamps: Node
var on_foot := false
## Seconds left of getting into or out of a car, and which car and which way.
var _door_time := 0.0
var _door_car: VehicleBody3D
var _door_in := false
## This visit to the pump so far: litres put in and what they cost.
var _pumped := 0.0
var _bill := 0.0
## Paid since the wallet was last saved.
var _unsaved := false


func _ready() -> void:
	# Every car starts wherever it stands in this scene (move it in the editor)
	# and is set down on the ground at that spot. A car left at the scene origin
	# has not been placed, so it goes to the spawn point on the road instead.
	if start_car:
		car = start_car
	inventory = Inventory.new()
	inventory.name = "Inventory"
	add_child(inventory)
	inventory.changed.connect(_hold_selected)
	player.drink_finished.connect(_on_drink_finished)
	player.smoke_finished.connect(_on_smoke_finished)
	_hold_selected()
	var bar := preload("res://hud/inventory_bar.gd").new()
	bar.name = "Inventory"
	$HUD.add_child(bar)
	help_label.visible = show_help_at_start
	bar.inventory = inventory
	# The key help wraps short of the inventory in the top right corner.
	var help := $HUD/Help as Label
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.offset_right = help.offset_left + 740.0
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
	if not (start_at_house and _start_at_house()):
		_drive(car, true)
	wallet.changed.connect(_show_money)
	_show_money(wallet.balance)
	# The story: one mission after another (game/mission_manager.gd, res://missions/).
	missions = MissionManager.new()
	missions.name = "Missions"
	missions.main = self
	add_child(missions)
	combat = Combat.new()
	combat.name = "Combat"
	add_child(combat)
	# Cars driven about the town's roads (world/traffic.gd).
	var traffic: Node3D = preload("res://world/traffic.gd").new()
	traffic.name = "Traffic"
	add_child(traffic)
	# F3: where you are, copied for asking about a spot on the map (game/locator.gd).
	var locator: CanvasLayer = preload("res://game/locator.gd").new()
	locator.name = "Locator"
	add_child(locator)


func _show_money(balance: float) -> void:
	money_label.text = Wallet.format(balance)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	# I shows or hides the key help in the top left corner.
	if key.physical_keycode == KEY_I:
		help_label.visible = not help_label.visible
		_help_hint_left = 0.0
		return
	if _door_time > 0.0:
		return
	# For testing: 0 forgets the missions done and starts again from the first.
	if key.physical_keycode == KEY_0:
		if missions:
			missions.reset()
		return
	# For testing: 1, 2, 3... put you straight into that car, wherever it is,
	# in the order the cars come in this scene.
	var number := key.physical_keycode - KEY_1
	if number >= 0 and number < 9:
		var cars := get_tree().get_nodes_in_group("cars")
		if number < cars.size():
			_drive(cars[number], true)
		return
	# For testing: = puts 10 000 drams in your wallet.
	if key.physical_keycode == KEY_EQUAL:
		wallet.earn(10000.0)
		wallet.save()
		return
	# For testing: - gives you a pack of 20 cigarettes (the cashier sells them, world/cashier.gd).
	if key.physical_keycode == KEY_MINUS:
		inventory.add("cigarette", 20)
		return
	# On foot, E takes a Duet coffee off the shelf in front of you, or uses
	# the item in your hand: a sip of a drink (the last sip finishes it, see
	# _on_drink_finished); a cigarette, a smoke break (player.gd), with the
	# coffee too when the cigarette + coffee slot is chosen; E again ends the
	# break. In a car E is the starter, see car.gd.
	if key.physical_keycode == KEY_E and on_foot:
		var stand := _stand_in_reach()
		if stand and not player.on_break:
			_buy_from(stand)
		elif player.on_break:
			player.end_break()
		elif not player.is_busy():
			_use_selected(false)
		return
	# C: on a smoke break, squat or stand up; with a cigarette in hand, a smoke
	# break squatting.
	if key.physical_keycode == KEY_C and on_foot:
		if player.on_break:
			player.start_break(not player.break_squat)
		elif not player.is_busy() and inventory.selected_use() in ["smoke", "smoke_drink"]:
			_use_selected(true)
		return
	# F gets you in or out.
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


## Stands you just outside the front door, facing the start car, with every car
## parked. False when there is no house.
func _start_at_house() -> bool:
	var spot: Variant = front_door_outside(1.8)
	if not spot is Vector3:
		return false
	car.parked = true
	car.player_controlled = false
	var facing: Vector3 = car.global_position - spot
	player.place(spot + Vector3.UP * 0.1, facing)
	player.stand_up()
	player.set_active(true)
	on_foot = true
	lamps = null
	lights_label.visible = false
	speed_label.visible = false
	power_bar.visible = false
	fuel_bar.visible = false
	minimap.target = player
	camera.follow(player, true)
	return true


## A point `distance` metres out from the middle of the house's front door
## (tools/build_house.gd puts it in the side wall, facing the terrace), or null
## with no house. Out is the side with no roof over it.
func front_door_outside(distance := 1.5) -> Variant:
	var door := get_node_or_null("House/Doors/FrontDoor") as Node3D
	if door == null:
		return null
	var middle := door.to_global(Vector3(float(door.get("width")) * 0.5, 0.0, 0.0))
	var out := -(get_node("House") as Node3D).global_basis.x
	out = out.slide(Vector3.UP).normalized()
	var spot := middle + out * distance
	if _under_house(spot):
		spot = middle - out * distance
	return spot


## Whether `at` (someone's feet) is inside the house: under its roof or upper floor.
func inside_house(at: Vector3) -> bool:
	return _under_house(at)


func _under_house(at: Vector3) -> bool:
	var body := get_node_or_null("House/Body") as CollisionObject3D
	if body == null:
		return false
	var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 2.0, at + Vector3.UP * 15.0)
	ray.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	return not hit.is_empty() and hit["collider"] == body


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
		_end_pump_visit()
		_shop_hints(hints)
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
	# Taxi work (game/taxi.gd): Y to start, and where to stop.
	var taxi := get_node_or_null("Taxi")
	if taxi:
		taxi.add_hints(hints)
	if _help_hint_left > 0.0:
		_help_hint_left -= delta
		if not help_label.visible:
			hints.append("Press I for the controls")
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


## The nearest shop shelf you stand in front of (world/duet_stand.gd), or null.
func _stand_in_reach() -> Node3D:
	var best: Node3D = null
	var best_distance := INF
	for stand: Node3D in get_tree().get_nodes_in_group("shop_stands"):
		var d: float = stand.shopper_distance(player)
		if stand.in_reach(player) and d < best_distance:
			best = stand
			best_distance = d
	return best


## Pays for what the stand sells (a cup of Duet, a pack of cigarettes from the
## cashier) and puts it in your inventory: `amount` of its item, if it says.
func _buy_from(stand: Node3D) -> void:
	if inventory.is_full_for(stand.item_id) or not wallet.can_afford(stand.price):
		return
	if not stand.take(player.global_position):
		return
	wallet.spend(stand.price)
	wallet.save()
	var amount = stand.get("amount")
	inventory.add(stand.item_id, amount if amount != null else 1)


## Uses the item in your hand (E, or C for a smoke break squatting): it leaves
## the inventory as he starts. A coffee he drinks (player.drink()), a cigarette
## he smokes, with cigarette + coffee both, on a smoke break (player.start_break()).
## Either lasts up to player.ACTION_TIME; what he holds meanwhile stays in his
## hand till he is done (_hold_selected waits).
func _use_selected(squat: bool) -> void:
	var id := inventory.selected_id()
	match inventory.selected_use():
		"drink":
			if player.drink():
				inventory.use_one(id)
		"smoke":
			if player.start_break(squat):
				inventory.use_one(id)
		"smoke_drink":
			if player.start_break(squat):
				inventory.use_one(Inventory.COMBOS[id]["smoke"])
				inventory.use_one(Inventory.COMBOS[id]["drink"])


## The drink is over: the cup in his hand is drunk.
func _on_drink_finished() -> void:
	player.drop_held()
	_hold_selected()


## A smoke break over: the cigarette is smoked, and the drink he had with it drunk.
func _on_smoke_finished(with_drink: bool) -> void:
	if with_drink:
		player.drop_held()
	_hold_selected()


## Shows the selected item in your hand (it hides with you while you drive).
func _hold_selected() -> void:
	# Not while he drinks or smokes: what he holds then is already used up and
	# goes when he is done (_on_drink_finished, _on_smoke_finished).
	if player.is_busy():
		return
	# A cigarette stays in its pack till a smoke break; with cigarette +
	# coffee chosen, the coffee is in your hand.
	var id := inventory.held_id()
	if player.held and player.held.get_meta("item_id", "") == id:
		return
	player.drop_held()
	if id != "":
		var item: Node3D = (load(Inventory.ITEMS[id]["scene"]) as PackedScene).instantiate()
		item.set_meta("item_id", id)
		item.set_meta("item_scale", Inventory.ITEMS[id].get("scale", 1.0))
		player.hold(item)


## On foot the mouse wheel picks the item in your hand (Ctrl + wheel zooms).
func _unhandled_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null or not button.pressed or not on_foot or button.ctrl_pressed:
		return
	if button.button_index == MOUSE_BUTTON_WHEEL_UP:
		inventory.select_step(-1)
	elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		inventory.select_step(1)


func _shop_hints(hints: PackedStringArray) -> void:
	var stand := _stand_in_reach()
	var id := inventory.selected_id()
	var use := inventory.selected_use()
	if player.on_break:
		hints.append("Smoke break: C to %s, E or walk to stop" % ["stand up" if player.break_squat else "squat"])
	elif use in ["smoke", "smoke_drink"] and player.can_take_break() and not player.is_busy() and stand == null:
		hints.append("Press E to %s, C to squat" % ["smoke" if use == "smoke" else "smoke with your coffee"])
	if stand == null:
		if use == "drink" and not player.is_busy():
			hints.append("Press E to drink your %s" % Inventory.item_name(id))
		return
	var price := Wallet.format(stand.price)
	if inventory.is_full_for(stand.item_id):
		hints.append("No room in your inventory for another %s" % stand.item_name)
	elif stand.sold_out():
		hints.append("%s is sold out, more soon" % stand.item_name)
	elif not wallet.can_afford(stand.price):
		hints.append("Not enough money for a %s  (%s)" % [stand.item_name, price])
	else:
		var verb = stand.get("verb")
		hints.append("Press E to %s a %s  (%s)" % [verb if verb != null else "grab", stand.item_name, price])


## Whether the car you are in stands at a fuel pump (see tools/build_gas_station.gd).
func _at_pump() -> bool:
	for pumps: Area3D in get_tree().get_nodes_in_group("fuel_pumps"):
		if pumps.overlaps_body(car):
			return true
	return false


## At a pump with the car stopped and the engine off, holding T fills the tank,
## paying fuel_price a litre from your wallet as it goes in; it stops when the
## tank is full or the money runs out.
func _refuel(delta: float, hints: PackedStringArray) -> void:
	if not _at_pump() or absf(car.forward_speed()) > 1.0:
		_end_pump_visit()
		return
	var price := "%s a litre" % Wallet.format(fuel_price)
	var paid := "  -  %d L, %s" % [roundi(_pumped), Wallet.format(_bill)] if _pumped > 0.0 else ""
	if car.fuel >= car.fuel_capacity - 0.05:
		hints.append("Tank full" + paid)
	elif car.engine_running:
		hints.append("Stop the engine (E) to refuel  (%s)" % price)
	elif not wallet.can_afford(fuel_price * 0.1):
		hints.append("Not enough money for fuel  (%s)" % price + paid)
	elif Input.is_physical_key_pressed(KEY_T):
		# As much as flows this frame, the tank takes and you can pay for.
		var litres := minf(refuel_rate * delta, wallet.balance / fuel_price)
		litres = car.refuel(litres)
		wallet.spend(litres * fuel_price)
		_pumped += litres
		_bill += litres * fuel_price
		_unsaved = _unsaved or litres > 0.0
		hints.append("Refuelling...  %d / %d L  -  %s" % [ceili(car.fuel), roundi(car.fuel_capacity), Wallet.format(_bill)])
	else:
		hints.append("Hold T to refuel  (%s)" % price + paid)
	if _unsaved and not Input.is_physical_key_pressed(KEY_T):
		wallet.save()
		_unsaved = false


## Leaving the pump: what you paid is kept, and the next visit starts a new bill.
func _end_pump_visit() -> void:
	if _unsaved:
		wallet.save()
		_unsaved = false
	_pumped = 0.0
	_bill = 0.0


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
