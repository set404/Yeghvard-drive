extends Mission
## Act 1, mission 1: go into the house and Dad sends you to the supermarket
## for a pack of Ararat and a Duet. Teaches getting about, the shop and the inventory. Smoke or drink
## what you bought on the way back and you are sent to buy it again.

const PACK := 20 ## cigarettes in a pack (world/cashier.gd sells `amount`)


func build() -> void:
	id = "dads_errand"
	title = "Dad's errand"
	reward = 5000.0
	briefing = "Dad: \"Gyada, run to the supermarket for me: a pack of seri barak Ararat and a Duet.\""
	success = "Dad: \"Thanks, Gyada!\""
	start_text = "Dad is waiting at home: go inside the house"
	var inv: Inventory = main.inventory
	steps = [
		{
			"text": "Go to the supermarket",
			"target": func() -> Variant: return _till(),
			"done": func() -> bool: return _till() != null and distance_to(_till()) < 30.0,
		},
		{
			"text": "Buy a pack of Ararat at the till",
			"target": func() -> Variant: return _till(),
			# Done once you have a pack's worth for Dad (with some on you already, at once).
			"done": func() -> bool: return inv.count_of("cigarette") >= PACK,
		},
		{
			"text": "Grab a Duet ice coffee from the shelf",
			"target": func() -> Variant: return _shelf(),
			"done": func() -> bool: return inv.count_of("duet") >= 1,
		},
		{
			"text": "Bring them home to Dad, inside the house",
			"target": func() -> Variant: return _front_door(),
			"back_to": func() -> int: return 1 if inv.count_of("cigarette") < PACK else (2 if inv.count_of("duet") < 1 else -1),
			"back_message": func() -> String: return "Those were Dad's cigarettes! Buy another pack." if inv.count_of("cigarette") < PACK else "You drank Dad's coffee! Grab another one.",
			"done": func() -> bool: return _at_home(),
		},
	]


## Dad takes what you brought.
func finish() -> void:
	main.inventory.take("cigarette", PACK)
	main.inventory.take("duet", 1)


## Where you stand at the cashier's counter.
func _till() -> Variant:
	var cashier := stand_selling("cigarette")
	if cashier == null:
		return null
	return cashier.to_global(cashier.get("customer_spot"))


## In front of the middle of the Duet shelves.
func _shelf() -> Variant:
	var stand := stand_selling("duet")
	if stand == null:
		return null
	return stand.to_global(Vector3(float(stand.get("length")) * 0.5, 0.0, 1.0))


func start_target() -> Variant:
	return _front_door()


## Starts once you walk into the house.
func can_start() -> bool:
	return _at_home()


## On foot inside the house (main.gd's inside_house).
func _at_home() -> bool:
	return main.on_foot and main.inside_house(main.player.global_position)


## Just outside the house's front door (main.gd), or the house itself.
func _front_door() -> Vector3:
	var at: Variant = main.front_door_outside(1.0)
	if at is Vector3:
		return at
	return (main.get_node("House") as Node3D).global_position
