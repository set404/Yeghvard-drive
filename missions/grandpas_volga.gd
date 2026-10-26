extends Mission
## Act 1, mission 2: Grandpa's old Volga (the taxi, main.tscn's Car3) has stood
## at Uncle Gagik's for a year. Get it going, fill it up at the gas station
## and bring it home. It barely starts (start_fail_chance) and has little fuel:
## run dry on the way and a friend of Dad's brings a canister. Done, it is
## your taxi: game/taxi.gd only takes fares once this mission is done.

## Litres in the tank that count as filled up.
const FULL_ENOUGH := 35.0
## What the canister puts in when you run dry.
const CANISTER := 6.0
## How close to the garage gate the Volga has to be parked (metres).
const HOME_REACH := 16.0

## Seconds until the next canister can come (so it does not come every frame).
var _rescue_wait := 0.0


func build() -> void:
	id = "grandpas_volga"
	title = "Grandpa's Volga"
	reward = 3000.0
	start_text = "Dad wants a word: go inside the house"
	briefing = "Dad: \"Gyada, your grandpa's Volga has been standing at Uncle Gagik's for a year. Go and get it, fill it up and bring it home.\""
	success = "Dad: \"Your grandpa drove a taxi in that Volga for twenty years. The sign is still on the roof: go and earn some money!\"\nTaxi work unlocked: Y in the Volga"
	var not_in_it := func() -> int: return 1 if main.on_foot or main.car != _volga() else -1
	steps = [
		{
			"text": "Go to Uncle Gagik's and find Grandpa's Volga",
			"target": func() -> Variant: return _volga().global_position,
			"done": func() -> bool: return distance_to(_volga().global_position) < 12.0,
		},
		{
			"text": "Get in the Volga (F)",
			"target": func() -> Variant: return _volga().global_position,
			"done": func() -> bool: return not main.on_foot and main.car == _volga(),
		},
		{
			"text": "Start it (E). It's old: keep trying",
			"back_to": not_in_it,
			"back_message": func() -> String: return "Get back in the Volga.",
			"done": func() -> bool: return _volga().engine_running,
		},
		{
			"text": "Fill it up at the gas station (engine off, hold T)",
			"target": func() -> Variant: return _pumps(),
			"back_to": not_in_it,
			"back_message": func() -> String: return "Get back in the Volga.",
			"done": func() -> bool: return _volga().fuel >= minf(FULL_ENOUGH, _volga().fuel_capacity * 0.9),
		},
		{
			"text": "Bring it home: park by the garage and get out",
			"target": func() -> Variant: return _garage(),
			"done": func() -> bool: return main.on_foot and _volga().linear_velocity.length() < 0.5 \
					and _flat(_volga().global_position, _garage()) < HOME_REACH,
		},
	]


func start_target() -> Variant:
	return main.front_door_outside(1.0)


## Starts when you go in to Dad (you finish the errand inside, so straight away).
func can_start() -> bool:
	return main.on_foot and main.inside_house(main.player.global_position)


## Run dry on the way to the pump or home: a canister.
func tick(delta: float) -> void:
	_rescue_wait -= delta
	var volga := _volga()
	if volga == null or volga.fuel > 0.05 or _rescue_wait > 0.0:
		return
	_rescue_wait = 20.0
	volga.refuel(CANISTER)
	main.missions.show_banner("Out of fuel! Dad's friend Ashot comes by with a canister: %d litres." % CANISTER)


## The Volga: the first taxi (game/taxi.gd), else the car named Car3.
func _volga() -> VehicleBody3D:
	for car: VehicleBody3D in main.get_tree().get_nodes_in_group("cars"):
		if car.get_meta("taxi", false):
			return car
	return main.get_node_or_null("Car3") as VehicleBody3D


## The nearest fuel pumps (tools/build_gas_station.gd).
func _pumps() -> Variant:
	var best: Variant = null
	var best_d := INF
	for pumps: Node3D in main.get_tree().get_nodes_in_group("fuel_pumps"):
		var d := distance_to(pumps.global_position)
		if d < best_d:
			best = pumps.global_position
			best_d = d
	return best


## In front of the house's garage gate.
func _garage() -> Vector3:
	var gate := main.get_node_or_null("House/GarageGate") as Node3D
	if gate:
		return gate.to_global(Vector3(0.0, 0.0, 4.0))
	return (main.get_node("House") as Node3D).global_position


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
