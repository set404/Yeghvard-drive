extends Mission
## Act 1, mission 2: "Սցեպլենիեն սեղմի, ա՛րա"
##
## Back from Dad's errand, Davitik calls: he is loqsh at the bank's hayat, come
## for a coffee and bring the Duets. You buy two at the supermarket, drink them
## with him, and he wants to drive your car. You take him to a quiet street and
## swap seats; he starts it, you tell him to press the clutch, he cannot find it
## (it's automatic). Then he drives a little, turns left and puts the car into
## a wall. You slap him, the uncle whose wall it was comes out, you drive off
## with Davitik running after the car (cars knock him over; he gets up), and
## you drop him back at the hayat. At the end: how many times you screamed
## about the clutch, slapped him and hit him with the car.
##
## Davitik is npc/davitik.gd; the lines are played by game/dialogue.gd.
##
## THE PLACES: the bank's hayat is between the two banks. For the lesson
## street, stand there in the game, press F3 (game/locator.gd copies
## "you (x, y, z)" to the clipboard) and put the numbers in LESSON_SPOT below;
## until then (Vector3.INF) the gas station's taxi stop stands in. At LESSON_SPOT the car
## should face along the street with the wall on its LEFT: Davitik drives
## straight for STRAIGHT_SECONDS, then turns hard left.

const Davitik := preload("res://npc/davitik.gd")
const Dialogue := preload("res://game/dialogue.gd")
const Sfx := preload("res://game/sfx.gd")
const ExtraAnims := preload("res://game/extra_anims.gd")

## The bank's hayat, where Davitik waits and where you drop him at the end.
## Between the two banks (buildings 207635644 and 207635648 on the map), where their ends face each other.
const BANK_HAYAT := Vector3(-695.3, -13.2, 1722.0)
## The quiet street where you swap seats and he drives into the wall.
const LESSON_SPOT := Vector3.INF
## Davitik's drive: seconds straight on (wobbling), pedal, then the turn left.
const STRAIGHT_SECONDS := 2.5
const STRAIGHT_GAS := 0.4
const TURN_GAS := 0.75
## Turning, he gets this long to find a wall; after that it counts as a crash anyway.
const TURN_SECONDS := 4.0
## How close (metres) to the spot counts as there.
const ARRIVE := 12.0
## Metres you drive off before Davitik is let back in (till then, run Davitik, run).
const CHASE_DISTANCE := 60.0
## How much shorter (metres) Davitik is than you.
const DAVITIK_SHORTER := 0.08
## Figures for the uncle whose wall it is (tools/build_npcs.gd), the first there is.
const UNCLE_FIGURES := ["res://npc/Ch02.scn", "res://npc/Ch07.scn", "res://npc/Ch17.scn", "res://npc/Ch22.scn", "res://npc/Untitled.scn"]
const CAR_HIT_LINES := ["Ա՛ՐԱ!!", "Լավ եմ, լավ եմ! Զգույշ քշի, ա՛րա!", "Ինչի՞, ա՛րա!", "ԷԼԻ՞!", "Մեջքս, ա՛րա...", "Պապայիդ եմ զանգում!", "Սպասի, ա՛րա!"]
const SLAP_LINES := ["Վա՜յ!", "Լավ, լավ!", "Ա՛ՐԱ!", "Հերի՛ք, ա՛րա!", "Երեսիս չէ՛!"]

var dav: Davitik
var uncle: Davitik
var talk: Dialogue
## Takes keys before main.gd does (the clutch, slapping, and no getting out
## while you sit in the passenger's seat).
var _keys: Node
## The car he drives into the wall, and the copy of you in its passenger's seat.
var _lesson_car: VehicleBody3D
var _passenger_copy: Node3D
## Whether you sit in the passenger's seat while he drives.
var _riding := false

var _call_done := false
var _coffee_done := false
var _duets_left := 0
var _swapped := false
var _driving := false
var _drive_t := 0.0
var _prev_speed := 0.0
var _said_turn := false
var _crashed := false
var _out := false
var _slap_ok := false
var _uncle_started := false
var _uncle_done := false
var _chase_driven := 0.0
var _chase_from := Vector3.ZERO
var _said_stop := false
var _end_done := false

## What you do while you speak (game/extra_anims.gd's "talk", "phone"...): the
## animation, and seconds left of it.
var _vzgo_anim := ""
var _vzgo_left := 0.0
## AnimationPlayers already given the extra animations.
var _animated := {}

## The score: "press the clutch" screamed (SPACE), and slaps.
var _clutch := 0
var _clutch_on := false
var _slaps := 0


class Keys extends Node:
	var handler: Callable

	func _input(event: InputEvent) -> void:
		var key := event as InputEventKey
		if key and key.pressed and not key.echo and handler.call(key):
			get_viewport().set_input_as_handled()


func build() -> void:
	id = "davitik_lesson"
	title = "Սցեպլենիեն սեղմի, ա՛րա"
	reward = 0.0
	var inv: Inventory = main.inventory
	steps = [
		{ # 0
			"text": "Հեռախոսդ զնգում է",
			"start": _phone_call,
			"done": func() -> bool: return _call_done,
		},
		{ # 1
			"text": "Սուպերմարկետից երկու Դուետ առ՝ մեկը քեզ, մեկը Դավիթիկին",
			"target": func() -> Variant: return _shelf(),
			"done": func() -> bool: return inv.count_of("duet") >= 2,
		},
		{ # 2
			"text": "Գնա բանկի հայաթ, Դավիթիկը սպասում է",
			"start": _davitik_waits,
			"target": func() -> Variant: return dav.global_position if _alive(dav) else hayat(),
			"back_to": func() -> int: return 1 if inv.count_of("duet") < 2 else -1,
			"back_message": func() -> String: return "Դավիթիկի Դուետը խմեցիր! Մի հատ էլ առ։",
			"done": func() -> bool: return _alive(dav) and main.on_foot and _flat(main.player.global_position, dav.global_position) < 4.0,
		},
		{ # 3
			"text": "Դավիթիկի հետ սուրճ խմի (E՝ քոնը խմելու համար)",
			"start": _coffee,
			"back_to": _lost,
			"done": func() -> bool: return _coffee_done and (inv.count_of("duet") < _duets_left or _duets_left == 0) and not main.player.is_busy(),
		},
		{ # 4
			"text": "Դավիթիկը ուզում է քշել։ Նստիր մեքենադ ու կանգնի մոտը, որ նստի",
			"start": _wait_for_lift,
			"target": func() -> Variant: return main.car.global_position if main.on_foot else (dav.global_position if _alive(dav) else null),
			"back_to": _lost,
			"done": _dav_in_car,
		},
		{ # 5
			"text": "Դավիթիկին տար մի հանգիստ փողոց, որ փորձի",
			"start": _off_to_the_lesson,
			"target": func() -> Variant: return lesson_spot(),
			"back_to": func() -> int: return _lost() if _lost() >= 0 else (4 if not _alive(dav) or not dav.seated_in(main.car) else -1),
			"back_message": func() -> String: return "Դավիթիկը մեքենայիդ մեջ չի։",
			"done": func() -> bool: return _dav_in_car() and _flat(main.car.global_position, lesson_spot()) < ARRIVE and absf(main.car.forward_speed()) < 1.5,
		},
		{ # 6
			"text": "Տեղերով փոխվեք՝ իջիր ու թող Դավիթիկը նստի ղեկին (F)",
			"start": _at_the_lesson,
			"back_to": _lost,
			"done": func() -> bool: return _swapped,
		},
		{ # 7
			"text": "Դավիթիկին քշել սովորեցրու։  SPACE՝ ասա, որ սցեպլենիեն սեղմի!",
			"back_to": _lost,
			"done": func() -> bool: return _out,
		},
		{ # 8
			"text": "Տես ինչ արեց՝ գնա մեքենայի առջևի կողմը",
			"target": func() -> Variant: return _front(),
			"back_to": _lost,
			"done": func() -> bool: return _front() != null and _flat(main.player.global_position, _front()) < 3.5,
		},
		{ # 9
			"text": "Մի հատ ապտակ տուր Դավիթիկին (E)",
			"start": _look_at_damage,
			"target": func() -> Variant: return dav.global_position if _alive(dav) else null,
			"back_to": _lost,
			"done": func() -> bool: return _uncle_done,
		},
		{ # 10
			"text": "Նստիր մեքենան ու փախի էստեղից! (Դավիթիկը հետևիցդ վազում է...)",
			"start": _run_away,
			"back_to": _lost,
			"done": _dav_in_car,
		},
		{ # 11
			"text": "Դավիթիկին հետ տար բանկի հայաթ",
			"start": _back_in,
			"target": func() -> Variant: return hayat(),
			"back_to": func() -> int: return _lost() if _lost() >= 0 else (10 if not dav.seated_in() else -1),
			"back_message": func() -> String: return "Դավիթիկը մեքենայի մեջ չի։",
			"done": func() -> bool: return _dav_in_car() and _flat(main.car.global_position, hayat()) < ARRIVE + 4.0 and absf(main.car.forward_speed()) < 1.5,
		},
		{ # 12
			"text": "Դավիթիկին իջեցրու",
			"start": _the_end,
			"back_to": _lost,
			"done": func() -> bool: return _end_done,
		},
	]


# --- the places ----------------------------------------------------------------

## The bank's hayat (BANK_HAYAT, or the supermarket's taxi stop till it is set).
func hayat() -> Vector3:
	if BANK_HAYAT.is_finite():
		return BANK_HAYAT
	return _marker("TaxiStops/Supermarket", Vector3(-766.0, -19.0, 1744.0))


## The quiet street (LESSON_SPOT, or the gas station's taxi stop till it is set).
func lesson_spot() -> Vector3:
	if LESSON_SPOT.is_finite():
		return LESSON_SPOT
	return _marker("TaxiStops/GasStation", Vector3(-835.4, -19.4, 1624.8))


func _marker(path: String, fallback: Vector3) -> Vector3:
	var m := main.get_node_or_null(path) as Node3D
	return m.global_position if m else fallback


## In front of the Duet shelves (as in Dad's errand).
func _shelf() -> Variant:
	var stand := stand_selling("duet")
	if stand == null:
		return null
	return stand.to_global(Vector3(float(stand.get("length")) * 0.5, 0.0, 1.0))


## The front of the car he crashed.
func _front() -> Variant:
	if not _alive(_lesson_car):
		return null
	var half: Vector3 = main.call("_half_size", _lesson_car)
	return _lesson_car.to_global(Vector3(0.0, 0.0, half.z + 0.6))


# --- every frame ---------------------------------------------------------------

func tick(delta: float) -> void:
	var step: int = main.missions.step
	_give_animations()
	_tick_vzgo(delta)
	if _driving:
		_drive(delta)
	if not _alive(dav):
		return
	match step:
		2, 3:
			dav.look(you())
		4:
			_let_him_in()
		8, 9:
			if not dav.seated_in() and dav.arrived():
				dav.look(main.player.global_position)
		10:
			_chase(delta)
	if _alive(uncle):
		if uncle.arrived():
			uncle.look(you())
		if step >= 10 and _flat(uncle.global_position, you()) > 90.0:
			uncle.queue_free()
			uncle = null


## Step 4: in your car, Davitik comes to the passenger's door and gets in
## once you stop; on foot, he waits.
func _let_him_in() -> void:
	if dav.seated_in():
		return
	if main.on_foot:
		if dav.mode == Davitik.Mode.FOLLOW_CAR:
			dav.stand()
		return
	if dav.mode != Davitik.Mode.FOLLOW_CAR or dav.car != main.car:
		dav.get_in_when_caught = true
		dav.follow_car(main.car, _flat(dav.global_position, main.car.global_position) > 20.0)


## Step 10: he runs after the car; once you have driven CHASE_DISTANCE he gets in when he catches you.
func _chase(_delta: float) -> void:
	if dav.seated_in():
		return
	if not main.on_foot:
		var car: VehicleBody3D = main.car
		if dav.mode != Davitik.Mode.FOLLOW_CAR or dav.car != car:
			dav.follow_car(car, true)
		_chase_driven = maxf(_chase_driven, _flat(car.global_position, _chase_from))
	var may := _chase_driven >= CHASE_DISTANCE
	if may and not _said_stop:
		_said_stop = true
		talk.bark("Davitik", "ԿԱՆԳՆԻ, Ա՛ՐԱ, ԳԱԼԻՍ ԵՄ!", 3.0)
	dav.get_in_when_caught = may


# --- the scenes ----------------------------------------------------------------

## Step 0: Davitik calls.
func _phone_call() -> void:
	_ensure()
	# His figure is made from his FBX the first time, and the extra animations
	# read: in the background, while you talk.
	Davitik.prepare()
	ExtraAnims.prepare()
	_call_done = false
	talk.play([
		Dialogue.wait(1.0),
		Dialogue.ring("Davitik"),
		Dialogue.say("Vzgo", "Ալո, գյադա", 0.0, "phone"),
		Dialogue.say("Davitik", "Ալո, ո՞նց ես, ա՛րա", 0.0, "", true),
		Dialogue.say("Vzgo", "Լավ, դու ասա", 0.0, "phone"),
		Dialogue.say("Davitik", "Ոչինչ, արի մի սուրճ խմենք, լոքշ եմ", 0.0, "", true),
		Dialogue.say("Vzgo", "Որտե՞ղ ես", 0.0, "phone"),
		Dialogue.say("Davitik", "Բանկի հայաթում", 0.0, "", true),
		Dialogue.say("Vzgo", "Լավ, գալիս եմ", 0.0, "phone"),
		Dialogue.say("Davitik", "Լավ, Դուետն էլ հետդ բեր", 0.0, "", true),
		Dialogue.run(func() -> void:
			_call_done = true
			_vzgo_stop()),
	])


## Step 2: Davitik stands at the hayat (as soon as his figure is ready: it is
## made in the background the first time, see npc/davitik_figure.gd).
func _davitik_waits() -> void:
	_ensure()
	Davitik.prepare()
	while main.missions.current != null and main.missions.step == 2 and not Davitik.figure_ready():
		await main.get_tree().process_frame
	if not Davitik.figure_ready():
		return
	_spawn_davitik()
	if not dav.seated_in():
		dav.place(hayat())
		# Waiting, on his phone (if there is a phone animation).
		dav.act("phone")


## Step 3: coffee. You give him his Duet; drink yours (E) while you talk.
func _coffee() -> void:
	_ensure()
	if not _alive(dav):
		return
	_coffee_done = false
	var inv: Inventory = main.inventory
	inv.take("duet", 1)
	_duets_left = inv.count_of("duet")
	_hold("duet")
	dav.hold_cup(true)
	dav.act("drink")
	talk.play([
		Dialogue.say("Davitik", "Գյադա ջան, եկար! Դուետս ո՞ւր ա"),
		Dialogue.say("Vzgo", "Ա՛ռ, վերցրու։ Չասես, թե բան չեմ տվել"),
		Dialogue.say("Davitik", "Ա՜խ, սառն ա։ Կյանքիս պես"),
		Dialogue.say("Vzgo", "Ի՞նչ կա-չկա"),
		Dialogue.say("Davitik", "Ոչինչ, ա՛րա, լոքշ, միշտվա պես"),
		Dialogue.say("Davitik", "Գյադա... մի հատ քշել տուր։ Թող մի քիչ մեքենադ քշեմ"),
		Dialogue.say("Vzgo", "Դո՞ւ։ Էդ երբվանի՞ց ես քշում"),
		Dialogue.say("Davitik", "Ա՛րա, երեք տարի ա իրավունք ունեմ, ի՞նչ ես խոսում", 0.0, "shrug"),
		Dialogue.say("Vzgo", "Լավ։ Նստի, մի հանգիստ փողոց գիտեմ դրա համար", 0.0, "point"),
		Dialogue.run(func() -> void:
			_coffee_done = true
			dav.hold_cup(false)
			dav.act("idle")),
	])


## Step 4: he waits for you to come with the car.
func _wait_for_lift() -> void:
	_ensure()
	if _alive(dav) and not dav.seated_in():
		dav.stand()


## Step 5: on the way.
func _off_to_the_lesson() -> void:
	_ensure()
	talk.play([
		Dialogue.wait(1.0),
		Dialogue.say("Davitik", "Ո՞ւր ենք գնում"),
		Dialogue.say("Vzgo", "Կտեսնես"),
	])


## Step 6: there. He takes the wheel once you get out.
func _at_the_lesson() -> void:
	_ensure()
	if not _alive(dav):
		return
	_lesson_car = dav.car if dav.seated_in() else main.car
	_swapped = false
	talk.play([
		Dialogue.say("Vzgo", "Էստեղ։ Դե արի, նստի ղեկին", 0.0, "point"),
		Dialogue.say("Davitik", "Վերջապե՜ս!"),
	])
	_watch_for_swap()


## Waits (a frame at a time) till you are out of the car, then swaps you over.
func _watch_for_swap() -> void:
	while main.missions.current != null and main.missions.step == 6 and not _swapped:
		if main.on_foot and _alive(_lesson_car) and _alive(dav):
			_swap()
			return
		await main.get_tree().process_frame


func _swap() -> void:
	_swapped = true
	var car := _lesson_car
	talk.fade(func() -> void:
		dav.sit_in(car, false)
		_ride_as_passenger(car)
		_clutch_lesson())


## You in the passenger's seat: the camera and HUD on the car, which nobody's keys drive.
func _ride_as_passenger(car: VehicleBody3D) -> void:
	var player: CharacterBody3D = main.player
	_riding = true
	player.set_active(false)
	player.stand_up()
	main.on_foot = false
	main.car = car
	for other: VehicleBody3D in main.get_tree().get_nodes_in_group("cars"):
		other.player_controlled = false
	car.parked = false
	main.lamps = car.get_node_or_null("Lamps")
	main.lights_label.visible = main.lamps != null
	main.speed_label.visible = true
	main.power_bar.visible = true
	main.fuel_bar.visible = true
	main.minimap.target = car
	main.camera.follow(car)
	# A copy of you, sitting beside him.
	const FIGURE := "res://player/character.scn"
	if ResourceLoader.exists(FIGURE):
		var copy: Node3D = (load(FIGURE) as PackedScene).instantiate()
		var s: float = float(player.get("height")) / float(copy.get_meta("height", 1.8))
		copy.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * s), Davitik.seat_origin(copy, car, true, s))
		car.add_child(copy)
		var anim := copy.get_node_or_null("AnimationPlayer") as AnimationPlayer
		if anim and anim.has_animation("drive"):
			anim.play("drive")
		_passenger_copy = copy
		if anim:
			ExtraAnims.add_to(anim)
			_animated[anim.get_instance_id()] = true


## Step 7: "press the clutch".
func _clutch_lesson() -> void:
	var car := _lesson_car
	talk.play([
		Dialogue.wait(0.6),
		Dialogue.say("Vzgo", "Հիմա մեքենան միացրու"),
		Dialogue.run(func() -> void:
			car.engine_running = false
			car.call("_crank")),
		Dialogue.wait(1.3),
		Dialogue.run(func() -> void:
			# He starts it first time, even the Volga: it's his big day.
			car.cranking = false
			car.start_failed = false
			car.engine_running = true),
		Dialogue.say("Davitik", "Օքե՜յ, արեցի!!"),
		Dialogue.say("Vzgo", "Ամրագոտին մի կապի, աղջիկ չես, ա՛րա"),
		Dialogue.say("", "*Դավիթիկը համաձայնեց*", 1.6),
		Dialogue.run(func() -> void:
			_clutch_on = true
			_show_score()),
		Dialogue.say("Vzgo", "Հիմա սցեպլենիեն սեղմի"),
		Dialogue.say("Davitik", "Սցեպլենիեն ո՞րն ա"),
		Dialogue.say("Vzgo", "Էնտեղ ա, սեղմի սցեպլենիեն!"),
		Dialogue.say("Davitik", "Ո՞ւր ա, չեմ գտնում"),
		Dialogue.say("Vzgo", "Արգելակից ձախ, ա՛րաաա"),
		Dialogue.say("Davitik", "Սցեպլենիե չկա, ո՞ւր ա։ Չեմ տեսնում"),
		Dialogue.run(func() -> void: main.missions.show_banner("Մեքենան ԱՎՏՈՄԱՏ էր։")),
		Dialogue.say("Vzgo", "Ավտոմատ ա, ա՛րա, ՀԱ ՀԱ ՀԱ ՀԱ"),
		Dialogue.run(func() -> void: _clutch_on = false),
		Dialogue.say("Davitik", "Շան տղա, ա՛րա, պանիկա եմ ընկել, ա՛րա, ի՞նչ ես բերանդ բացում, ա՛րա"),
		Dialogue.say("Vzgo", "*դեռ ծիծաղում է* Էշի պես հիմար ես։ Լավ, հիմա քշի։ Զգույշ"),
		Dialogue.say("Davitik", "Անասուն"),
		Dialogue.run(func() -> void:
			_driving = true
			_drive_t = 0.0
			_prev_speed = 0.0
			_said_turn = false),
	])


## Davitik at the wheel: straight on, wobbling, then hard left.
func _drive(delta: float) -> void:
	var car := _lesson_car
	if not _alive(car):
		_driving = false
		return
	_drive_t += delta
	car.ai_driven = true
	car.ai_brake = 0.0
	if _drive_t < STRAIGHT_SECONDS:
		car.ai_gas = STRAIGHT_GAS
		car.ai_steer = sin(_drive_t * 4.0) * 0.12
	else:
		if not _said_turn:
			_said_turn = true
			talk.bark("Vzgo", "Էստեղ ձախ թեքվի, կամաց... ԿԱՄԱ՜Ց, Ա՛ՐԱ!", 2.0)
		car.ai_gas = TURN_GAS
		car.ai_steer = float(car.get("max_steer"))
	# Into something: the car loses most of its speed at once.
	var speed := car.linear_velocity.length()
	var hit := _prev_speed > 3.0 and speed < _prev_speed * 0.6
	_prev_speed = speed
	if hit or _drive_t > STRAIGHT_SECONDS + TURN_SECONDS:
		_crash()


func _crash() -> void:
	_driving = false
	_crashed = true
	var car := _lesson_car
	car.ai_gas = 0.0
	car.ai_steer = 0.0
	car.ai_brake = 1.0
	car.engine_running = false
	Sfx.play(main, Sfx.crash(), car.global_position, 8.0, 14.0)
	Sfx.play(main, Sfx.alarm(), car.global_position, -2.0, 12.0)
	_shake(0.7)
	talk.stop()
	talk.play([
		Dialogue.wait(1.6),
		Dialogue.say("Davitik", "Ա՛րա... պատն ինքը եկավ։"),
		Dialogue.say("Vzgo", "ՊԱՏԸ ԵԿԱ՞Վ։ Ի՞ՆՉԸ ԵԿԱՎ, Ա՛ՐԱ, ԴՈՒ ԵՍ ՊԱՏԻՆ ԵԿԵԼ!"),
		Dialogue.say("Davitik", "Մեքենան շատ արագ թեքվեց, էս ավտոմատն ա, նորմալ չի։"),
		Dialogue.say("Vzgo", "Իջի։ Հենց հիմա իջի մեքենայից։"),
		Dialogue.run(_everyone_out),
	])


## Both of you out: you by the passenger's door, him by his.
func _everyone_out() -> void:
	talk.fade(func() -> void:
		var car := _lesson_car
		car.ai_driven = false
		car.ai_brake = 0.0
		car.parked = true
		if _passenger_copy:
			_passenger_copy.queue_free()
			_passenger_copy = null
		_riding = false
		main.call("_get_out")
		var spot := Davitik.door_spot(car, true, main)
		main.player.place(spot + Vector3.UP * 0.1, spot - car.global_position)
		dav.get_out()
		dav.go_to(spot + (car.global_basis.z * 1.6))
		_out = true
		_show_score())


## Step 9: the damage, and then you may slap him.
func _look_at_damage() -> void:
	_ensure()
	if not _alive(dav):
		return
	_slap_ok = false
	var me: Vector3 = main.player.global_position
	var side := dav.global_position - me
	side.y = 0.0
	dav.go_to(me + (side.normalized() if side.length() > 0.1 else Vector3.FORWARD) * 1.4)
	talk.play([
		Dialogue.say("Vzgo", "Նայի սրան։ ՆԱՅԻ ՍՐԱՆ, Ա՛ՐԱ։", 0.0, "angry"),
		Dialogue.say("Davitik", "Պուճուր ա, ոչ մեկ չի տեսնի... մի հատ նակլեյկա կխփես։", 0.0, "shrug"),
		Dialogue.run(func() -> void: _slap_ok = true),
	])


func _slap() -> void:
	_slaps += 1
	var player: CharacterBody3D = main.player
	player.place(player.global_position, dav.global_position - player.global_position)
	var anims: AnimationPlayer = player.get("_anim")
	var swing := "slap" if anims and anims.has_animation("slap") else "punch"
	var swing_time := 0.45
	if anims and anims.has_animation(swing):
		swing_time = clampf(anims.get_animation(swing).length * 0.7, 0.45, 1.4)
	_vzgo_stop()
	player.override_anim = swing
	main.get_tree().create_timer(swing_time).timeout.connect(func() -> void:
		if player.override_anim == swing:
			player.override_anim = "")
	dav.slap(player.global_position)
	_show_score()
	if not _uncle_started:
		_uncle_started = true
		_uncle_scene()
	else:
		talk.bark("Davitik", SLAP_LINES.pick_random(), 1.4)


## The uncle whose wall it was.
func _uncle_scene() -> void:
	talk.play([
		Dialogue.say("Davitik", "Վա՜յ! Լավ, լավ, կվճարեմ!"),
		Dialogue.say("Vzgo", "Կվճարե՞ս։ Ինչո՞վ, Դուետներո՞վ"),
		Dialogue.run(_uncle_comes),
		Dialogue.until(func() -> bool: return not _alive(uncle) or uncle.arrived(), 10.0),
		Dialogue.say("Uncle", "Իմ պատին էս ո՞վ արեց", 0.0, "angry"),
		Dialogue.run(_point_at_each_other),
		Dialogue.say("", "*Վզգոն ու Դավիթիկը իրար են ցույց տալիս*", 2.2),
		Dialogue.say("Uncle", "Ձեզնից ո՞վ էր ղեկին", 0.0, "angry"),
		Dialogue.say("Davitik", "Սցեպլենիեն չաշխատեց, քեռի ջան։", 0.0, "shrug"),
		Dialogue.say("Uncle", "...Ավտոմատ ա, տղա։", 0.0, "no"),
		Dialogue.say("Vzgo", "ՀԱ ՀԱ ՀԱ ՀԱ ՀԱ", 0.0, "laugh"),
		Dialogue.run(_throw_slipper),
		Dialogue.say("", "*Քեռին հողաթափը շպրտում է Դավիթիկի վրա*", 2.0),
		Dialogue.say("Vzgo", "Դավիթիկ... փախի։", 0.0, "point"),
		Dialogue.run(func() -> void: _uncle_done = true),
	])


func _uncle_comes() -> void:
	var figure := ""
	for path: String in UNCLE_FIGURES:
		if ResourceLoader.exists(path):
			figure = path
			break
	if figure == "":
		return
	var car := _lesson_car
	var from := car.to_global(Vector3(0.0, 0.0, -14.0))
	uncle = Davitik.new()
	uncle.name = "Uncle"
	uncle.height = 1.7
	uncle.walk_speed = 1.2
	main.add_child(uncle)
	uncle.setup(main, figure)
	uncle.knockable = false
	uncle.place(from, car.global_position - from)
	var me: Vector3 = main.player.global_position
	uncle.go_to(me + (from - me).normalized() * 2.2)


## Step 10: off you go, Davitik after you.
func _run_away() -> void:
	_ensure()
	if not _alive(dav) or not _alive(_lesson_car):
		return
	_chase_from = _lesson_car.global_position
	_chase_driven = 0.0
	_said_stop = false
	dav.get_in_when_caught = false
	dav.follow_car(_lesson_car, true)
	talk.bark("Davitik", "ՍՊԱՍԻ ԻՆՁ, Ա՛ՐԱ!", 2.5)


## Step 11: he made it in.
func _back_in() -> void:
	_ensure()
	talk.play([
		Dialogue.wait(0.5),
		Dialogue.say("Davitik", "Թողիր գնացիր, ա՛րա... ախպորդ թողիր։"),
		Dialogue.say("Vzgo", "Մեքենաս պատին խփեցիր, հլը ախպերությունից ես խոսո՞ւմ"),
		Dialogue.say("Davitik", "...Հետ գնալիս ես քշե՞մ"),
		Dialogue.say("Vzgo", "Ամրագոտիդ կապի։"),
		Dialogue.say("Davitik", "Բա ասում էիր՝ աղջիկ չեմ։"),
		Dialogue.say("Vzgo", "Հիմա աղջիկ ես։ Կապի։"),
	])


## Step 12: back at the hayat.
func _the_end() -> void:
	_ensure()
	if not _alive(dav):
		return
	_end_done = false
	dav.get_out()
	dav.look(you())
	var away := hayat() + (dav.global_position - you()).normalized() * 30.0
	talk.play([
		Dialogue.say("Davitik", "Հաջորդ անգամ նորմալ մեքենա տուր։ Սցեպլենիեով։", 0.0, "angry"),
		Dialogue.say("Vzgo", "Հաջորդ անգամ ոտքով ես գալու։", 0.0, "point"),
		Dialogue.wait(0.8),
		Dialogue.ring("Papa"),
		Dialogue.say("Vzgo", "...Դավիթիկ, արի էստեղ։", 3.0, "phone"),
		Dialogue.run(func() -> void:
			dav.go_to(away, true)
			_end_done = true),
	])


func finish() -> void:
	success = "\n".join(PackedStringArray([
		"«ՍՑԵՊԼԵՆԻԵՆ ՍԵՂՄԻ, Ա՛ՐԱ!» գոռացիր՝ %d անգամ" % _clutch,
		"Ապտակներ՝ %d     Դավիթիկին մեքենան խփեց՝ %d     Պատեր՝ 1" % [_slaps, dav.car_hits if _alive(dav) else 0],
		"Կոչում՝ Դավիթիկ, ավտոմատի սցեպլենիե փնտրող դիպլոմավոր մասնագետ",
	]))
	_vzgo_stop()
	if talk:
		talk.show_counter("")
		if talk.line_started.is_connected(_on_line):
			talk.line_started.disconnect(_on_line)
	if _keys:
		_keys.queue_free()
		_keys = null
	if _alive(uncle):
		uncle.queue_free()
	if _alive(dav):
		# He runs off; gone a while later.
		var gone := dav
		main.get_tree().create_timer(15.0).timeout.connect(func() -> void:
			if is_instance_valid(gone):
				gone.queue_free())


# --- keys ----------------------------------------------------------------------

func _on_key(key: InputEventKey) -> bool:
	var code := key.physical_keycode
	if _riding:
		# In the passenger's seat: SPACE screams about the clutch; no getting out,
		# changing cars or anything else.
		if code == KEY_SPACE:
			if _clutch_on:
				_clutch += 1
				talk.bark("Vzgo", "ՍՑԵՊԼԵՆԻԵՆ ՍԵՂՄԻ, Ա՛ՐԱ!!", 0.9)
				_show_score()
			return true
		return code in [KEY_F, KEY_E, KEY_P, KEY_G, KEY_T, KEY_Y, KEY_R] or (code >= KEY_0 and code <= KEY_9)
	if code == KEY_E and _slap_ok and main.on_foot and _alive(dav) and not dav.seated_in() \
			and dav.mode != Davitik.Mode.DOWN and _flat(main.player.global_position, dav.global_position) < 2.4:
		_slap()
		return true
	return false


# --- what they do while they talk ----------------------------------------------

## A line starts: the speaker does what it says (anim), or talks (laughs, for "ՀԱ ՀԱ").
func _on_line(who: String, text: String, seconds: float, anim: String) -> void:
	var laughing := text.contains("ՀԱ ՀԱ") or text.begins_with("*դեռ ծիծաղում")
	var what := anim if anim != "" else ("laugh" if laughing else "talk")
	match who:
		"Vzgo":
			_vzgo_do(what, seconds)
		"Davitik":
			if _alive(dav) and not dav.seated_in() and not dav.perform(what, seconds):
				dav.perform("talk", seconds)
		"Uncle":
			if _alive(uncle) and not uncle.perform(what, seconds):
				uncle.perform("talk", seconds)


## You do `anim` for `seconds`: standing still (not while you walk, drink or
## fight), or in the passenger's seat (laughing or talking, sitting).
func _vzgo_do(anim: String, seconds: float) -> void:
	if _riding:
		var copy := _passenger_copy
		var seat_anims := copy.get_node_or_null("AnimationPlayer") as AnimationPlayer if copy else null
		var sitting := "sit_laugh" if anim in ["laugh", "sit_laugh"] else "sit_talk"
		if seat_anims and seat_anims.has_animation(sitting):
			seat_anims.play(sitting, 0.3)
			main.get_tree().create_timer(seconds).timeout.connect(func() -> void:
				if is_instance_valid(copy) and seat_anims.current_animation == sitting:
					seat_anims.play("drive", 0.4))
		return
	if not main.on_foot:
		return
	var player: CharacterBody3D = main.player
	var anims: AnimationPlayer = player.get("_anim")
	if anims == null or not anims.has_animation(anim):
		return
	var current: String = player.override_anim
	if player.velocity.length() > 0.5 or player.is_busy() or (current != "" and current != _vzgo_anim):
		return
	var length := anims.get_animation(anim).length
	if anims.get_animation(anim).loop_mode == Animation.LOOP_NONE:
		seconds = minf(seconds, length * 0.95)
	player.override_anim = anim
	_vzgo_anim = anim
	_vzgo_left = seconds


func _vzgo_stop() -> void:
	if _vzgo_anim != "" and main.player.override_anim == _vzgo_anim:
		main.player.override_anim = ""
	_vzgo_anim = ""
	_vzgo_left = 0.0


## Ends what you were doing once its time is up, or as soon as you move.
func _tick_vzgo(delta: float) -> void:
	if _vzgo_anim == "":
		return
	_vzgo_left -= delta
	if _vzgo_left <= 0.0 or (main.player as CharacterBody3D).velocity.length() > 0.5 or not main.on_foot:
		_vzgo_stop()


## Puts the extra animations (once read) on you, Davitik and the uncle.
func _give_animations() -> void:
	if not ExtraAnims.ready():
		return
	var players: Array = [main.player.get("_anim")]
	if _alive(dav):
		players.append(dav.animation_player())
	if _alive(uncle):
		players.append(uncle.animation_player())
	for anims: AnimationPlayer in players:
		if anims and not _animated.has(anims.get_instance_id()):
			ExtraAnims.add_to(anims)
			_animated[anims.get_instance_id()] = true


## "*Վզգոն ու Դավիթիկը իրար են ցույց տալիս*"
func _point_at_each_other() -> void:
	if not _alive(dav):
		return
	var player: CharacterBody3D = main.player
	player.place(player.global_position, dav.global_position - player.global_position)
	_vzgo_do("point", 2.2)
	dav.look(player.global_position)
	dav.perform("point", 2.2)


## The uncle's slipper: it flies at Davitik's head, and he reels from it.
func _throw_slipper() -> void:
	if not _alive(uncle) or not _alive(dav):
		if _alive(dav):
			dav.slap(dav.global_position + dav.global_basis.z)
		return
	uncle.look(dav.global_position)
	uncle.perform("throw", 1.4)
	var slipper := MeshInstance3D.new()
	slipper.name = "Slipper"
	var shape := BoxMesh.new()
	shape.size = Vector3(0.1, 0.035, 0.27)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.2, 0.45)
	shape.material = mat
	slipper.mesh = shape
	main.add_child(slipper)
	var from := uncle.global_position + Vector3.UP * 1.55
	slipper.global_position = from
	var target := dav
	var flight := func(k: float) -> void:
		if not is_instance_valid(target):
			return
		var to := target.global_position + Vector3.UP * 1.65
		slipper.global_position = from.lerp(to, k) + Vector3.UP * sin(PI * k) * 1.1
		slipper.rotation = Vector3(k * TAU * 2.5, k * TAU, 0.0)
	var t := slipper.create_tween()
	t.tween_interval(0.45)
	t.tween_method(flight, 0.0, 1.0, 0.5)
	t.tween_callback(func() -> void:
		if is_instance_valid(target):
			target.slap(from))
	t.tween_property(slipper, "global_position:y", from.y - 1.5, 0.4).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	t.tween_interval(8.0)
	t.tween_callback(slipper.queue_free)


# --- helpers -------------------------------------------------------------------

## The subtitles and the key catcher, made once.
func _ensure() -> void:
	if talk == null or not is_instance_valid(talk):
		talk = main.get_node("HUD").get_node_or_null("Dialogue") as Dialogue
		if talk == null:
			talk = Dialogue.new()
			talk.name = "Dialogue"
			main.get_node("HUD").add_child(talk)
	if not talk.line_started.is_connected(_on_line):
		talk.line_started.connect(_on_line)
	if _keys == null or not is_instance_valid(_keys):
		var keys := Keys.new()
		keys.name = "DavitikKeys"
		keys.handler = _on_key
		main.add_child(keys)
		_keys = keys


func _spawn_davitik() -> void:
	if _alive(dav):
		return
	dav = Davitik.new()
	dav.name = "Davitik"
	# He is 8 cm shorter than you.
	dav.height = float(main.player.get("height")) - DAVITIK_SHORTER
	main.add_child(dav)
	dav.setup(main)
	dav.hit_by_car.connect(func(_times: int) -> void:
		talk.bark("Davitik", CAR_HIT_LINES.pick_random(), 1.8)
		_show_score())


## Puts `item_id` in your hand, if you have one.
func _hold(item_id: String) -> void:
	var inv: Inventory = main.inventory
	var all := inv.entries()
	for k in all.size():
		if all[k]["id"] == item_id:
			inv.selected = k
			inv.changed.emit()
			return


func _show_score() -> void:
	talk.show_counter("«Սցեպլենիեն սեղմի!» x%d\nԱպտակներ՝ %d\nԴավիթիկին մեքենան խփեց՝ %d" % [_clutch, _slaps, dav.car_hits if _alive(dav) else 0])


## Shakes the camera for `seconds`, hardest at first.
func _shake(seconds: float) -> void:
	var cam: Camera3D = main.camera
	var jolt := func(k: float) -> void:
		cam.h_offset = randf_range(-1.0, 1.0) * k * 0.35
		cam.v_offset = randf_range(-1.0, 1.0) * k * 0.35
	cam.create_tween().tween_method(jolt, 1.0, 0.0, seconds)


## Davitik is in the car you drive (with you at the wheel).
func _dav_in_car() -> bool:
	return _alive(dav) and not main.on_foot and dav.seated_in(main.car) and not _riding


## Back to the hayat (step 2) when Davitik or his car is gone (a saved game
## loaded part way through: they are not saved); -1 otherwise.
func _lost() -> int:
	if not _alive(dav):
		return 2
	if main.missions.step >= 7 and not _alive(_lesson_car):
		return 2
	return -1


static func _alive(node: Node) -> bool:
	return node != null and is_instance_valid(node) and node.is_inside_tree()


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
