class_name Taxi
extends Node
## Taxi work. In a taxi (a car with the metadata "taxi" = true; it gets a
## TAXI sign on its roof), Y starts and stops taking fares:
##  1. Someone waits for you at the kerb somewhere near (a green mark on the
##     minimap and a green beam of light). Stop next to them and they get in.
##  2. They say where to: one of the taxi stops (Marker3D nodes in the
##     "taxi_stops" group, named after the place) or somewhere along the
##     sidewalks. Drive there and stop, and they pay what the meter says:
##     base_fare plus per_km for every kilometre you drove, with a tip if you
##     were quick and did not crash.
##  3. Hit something hard (hard_hit) and they complain and the tip is gone;
##     max_hits times and they get out at the next stop without paying. They
##     also leave without paying if you get out of the car on the way.
## The sign on the roof is lit while you are on duty and free.
## main.gd has this as the node "Taxi" and asks it for its key hints (add_hints).

enum Stage { OFF, WAITING, PICKUP, BOARDING, RIDE, ALIGHTING }

## Drams: what the meter starts at, and adds for each kilometre driven.
@export var base_fare := 600.0
@export var per_km := 250.0
## The tip, as a share of the fare, for a quick ride with no crashes.
@export var tip_share := 0.15
## The meter stops at this many times the fare of the straight way there
## (driving in circles does not pay).
@export var fare_cap := 2.0
## How far from you (metres) a passenger may be waiting, and how far they may want to go.
@export var pickup_range := Vector2(150.0, 700.0)
@export var trip_range := Vector2(400.0, 2000.0)
## Chance a passenger wants one of the taxi stops rather than an address.
@export var stop_share := 0.35
## How close you stop to them to pick them up, and to where they are going (metres).
@export var pickup_reach := 9.0
@export var dropoff_reach := 14.0
## A bump harder than this (m/s², the change of the car's speed) counts as a crash.
@export var hard_hit := 30.0
@export var max_hits := 3
## Seconds between one passenger getting out and the next one calling.
@export var next_fare_wait := Vector2(4.0, 10.0)

const GREEN := Color(0.35, 0.9, 0.45)
const SIGN_LIT := Color(1.0, 0.78, 0.1)
const SIGN_DARK := Color(0.35, 0.28, 0.05)
const BEAM_HEIGHT := 40.0
## Walking pace of a passenger (metres a second), and the stop under which the car counts as standing.
const WALK_SPEED := 1.4
const STOPPED := 0.8
const GREETINGS := [
	"Barev dzez! %s, please.",
	"Barev. Take me to %s.",
	"Hi! To %s, quick, I'm in a hurry.",
]
const THANKS := ["Merci, have a good day!", "Shnorhakalutyun!", "Thanks, aper jan."]

## The game (main.gd), this node's parent.
var main: Node3D
var stage := Stage.OFF
## The car you are on duty in.
var cab: VehicleBody3D

var _passenger: Node3D
var _anim: AnimationPlayer
var _walk_anim_speed := 1.5
## Where they wait (on the sidewalk, by the kerb) and which way the road is.
var _pickup := Vector3.ZERO
var _pickup_face := Vector3.FORWARD
## Where they are going: where you stop, what they call it, where they walk to after.
var _dest := Vector3.ZERO
var _dest_name := ""
var _dest_walk: Variant = null
## The ride: metres driven, the straight way, when it started, what a quick ride
## takes (seconds), crashes so far, and whether they will pay.
var _driven := 0.0
var _direct := 0.0
var _started := 0.0
var _par := 0.0
var _hits := 0
var _last_pos := Vector3.ZERO
var _last_vel := Vector3.ZERO
var _since_hit := 0.0
var _wait := 0.0
## Walking the passenger: to where, and what to do on getting there.
var _walk_to := Vector3.ZERO
var _walk_done: Callable

var _panel: PanelContainer
var _title: Label
var _line: Label
var _beam: MeshInstance3D
var _beam_material: StandardMaterial3D
## Each taxi's roof sign material, by car.
var _signs := {}


func _ready() -> void:
	main = get_parent()
	_build_hud()
	_build_beam()
	# The cars are put on the ground by main.gd after a physics frame; the
	# signs go on after that.
	await get_tree().physics_frame
	await get_tree().process_frame
	for car: VehicleBody3D in _taxis():
		_add_sign(car)
	# The stops go down on to the ground under them (from a little above, so
	# a roof such as the gas station's canopy does not count).
	for stop: Node3D in get_tree().get_nodes_in_group("taxi_stops"):
		var p := stop.global_position
		var ray := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 3.0, p + Vector3.DOWN * 50.0)
		ray.collision_mask = 1
		var hit := main.get_world_3d().direct_space_state.intersect_ray(ray)
		if hit:
			stop.global_position.y = (hit["position"] as Vector3).y


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.physical_keycode != KEY_Y:
		return
	if stage != Stage.OFF:
		_end_duty("Taxi work over for now.")
		return
	if main.on_foot:
		return
	if not is_taxi(main.car):
		_say("Only a taxi takes fares.")
		return
	cab = main.car
	stage = Stage.WAITING
	_wait = 2.0
	_say("Taxi work: drive about, someone will call soon. Y to stop.")


## Whether `car` is a taxi (its metadata "taxi").
static func is_taxi(car: Node) -> bool:
	return car != null and car.get_meta("taxi", false)


## The key hints for main.gd's prompt.
func add_hints(hints: PackedStringArray) -> void:
	if main.on_foot:
		return
	if stage == Stage.OFF and is_taxi(main.car) and absf(main.car.forward_speed()) < 1.0:
		hints.append("Press Y to take taxi fares")
	elif stage == Stage.PICKUP and _flat(cab.global_position, _pickup) < pickup_reach * 2.5:
		hints.append("Stop next to the passenger")
	elif stage == Stage.RIDE and _flat(cab.global_position, _dest) < dropoff_reach * 2.5:
		hints.append("Stop here to let them out")


func _process(delta: float) -> void:
	_light_signs()
	_place_panel()
	if stage == Stage.OFF:
		_panel.visible = false
		_show_target(null)
		return
	# Driving some other car ends it.
	if not main.on_foot and main.car != cab:
		_end_duty("You left the taxi: taxi work over.")
		return
	_panel.visible = true
	_title.text = "TAXI"
	match stage:
		Stage.WAITING:
			_line.text = "Waiting for a call..."
			_show_target(null)
			_wait -= delta
			if _wait <= 0.0:
				_new_fare()
		Stage.PICKUP:
			_line.text = "Pick up the passenger   %s" % _distance_text(_flat(_you(), _pickup))
			_show_target(_pickup)
			if not main.on_foot and _stopped() and _flat(cab.global_position, _pickup) < pickup_reach:
				_board()
		Stage.BOARDING:
			_line.text = "The passenger is getting in..."
			_show_target(null)
			if main.on_foot or not _stopped():
				# You drove off (or got out): they wait where they are.
				_pickup = _passenger.global_position
				_idle()
				stage = Stage.PICKUP
				return
			_walk_to = _door()
			_walk_passenger(delta)
		Stage.RIDE:
			_ride(delta)
		Stage.ALIGHTING:
			_line.text = "Waiting for a call..."
			_show_target(null)
			_walk_passenger(delta)


func _physics_process(delta: float) -> void:
	if stage != Stage.RIDE or cab == null:
		return
	var v := cab.linear_velocity
	_since_hit += delta
	if delta > 0.0 and (v - _last_vel).length() / delta > hard_hit and _since_hit > 1.0 and _flat(cab.global_position, _last_pos) < 5.0:
		_since_hit = 0.0
		_hits += 1
		if _hits >= max_hits:
			_say("Passenger: \"Stop the car, I'm getting out!\"")
		elif _hits == 1:
			_say("Passenger: \"Ay! Careful!\"  (no tip now)")
		else:
			_say("Passenger: \"Are you trying to kill me?\"")
	_last_vel = v
	var p := cab.global_position
	var moved := _flat(p, _last_pos)
	# A jump (the car put back on the road with R) is not driving.
	if moved < 5.0:
		_driven += moved
	_last_pos = p


func _ride(_delta: float) -> void:
	if main.on_foot:
		_passenger_leaves("Passenger: \"Fine, I'll walk.\"  (they did not pay)")
		return
	var fare := _fare()
	if _hits >= max_hits:
		_line.text = "Stop: the passenger wants out"
		_show_target(null)
		if _stopped():
			_passenger_leaves("The passenger got out without paying.")
		return
	_line.text = "Drive to %s   %s\nMeter: %s" % [_dest_name, _distance_text(_flat(cab.global_position, _dest)), Wallet.format(fare)]
	_show_target(_dest)
	if _stopped() and _flat(cab.global_position, _dest) < dropoff_reach:
		_pay(fare)


# --- fares --------------------------------------------------------------------

## Finds someone waiting at a kerb near you and puts them there.
func _new_fare() -> void:
	var town: Node = main.get_node_or_null("Townsfolk")
	if town == null or town.path_count() == 0 or town.random_figure() == null:
		_wait = 5.0
		return
	var me := _you()
	for attempt in 60:
		var i: int = randi() % town.path_count()
		var where: Dictionary = town.point_on(i, randf() * town.path_length(i))
		var d := _flat(where["position"], me)
		if d < pickup_range.x or d > pickup_range.y:
			continue
		var kerb: Vector3 = where["kerb"]
		_pickup = where["position"] + kerb * (where["width"] * 0.5 - 0.35)
		_pickup_face = kerb
		_spawn_passenger(town.random_figure())
		stage = Stage.PICKUP
		_say("A fare is waiting %s away." % _distance_text(d))
		return
	# Nobody near: try again in a moment.
	_wait = 3.0


func _spawn_passenger(figure: PackedScene) -> void:
	_passenger = figure.instantiate()
	_passenger.name = "TaxiPassenger"
	add_child(_passenger)
	_passenger.global_position = _pickup
	_face(_pickup_face)
	_anim = _passenger.get_node_or_null("AnimationPlayer")
	_walk_anim_speed = maxf(float(_passenger.get_meta("walk_speed", 1.5)), 0.1)
	var phone := _passenger.get_node_or_null("Skeleton3D/RightHand/Phone") as Node3D
	if phone:
		phone.visible = false
	_idle()


## They walk to the car's back door and get in.
func _board() -> void:
	stage = Stage.BOARDING
	_walk_to = _door()
	_walk_done = _start_ride


func _start_ride() -> void:
	_passenger.visible = false
	_choose_destination()
	_driven = 0.0
	_hits = 0
	_since_hit = 0.0
	_last_pos = cab.global_position
	_last_vel = cab.linear_velocity
	_direct = _flat(cab.global_position, _dest)
	_started = Time.get_ticks_msec() / 1000.0
	# A quick ride: the straight way at 30 km/h, roads being what they are, and a minute to spare.
	_par = _direct * 1.4 / 8.3 + 60.0
	stage = Stage.RIDE
	_say("Passenger: \"%s\"" % _greeting())


func _greeting() -> String:
	var line: String = GREETINGS.pick_random()
	var place := _dest_name
	# At the start of the sentence it takes a capital.
	if line.begins_with("%s"):
		place = place.substr(0, 1).to_upper() + place.substr(1)
	return line % place


## A taxi stop, or a spot along the sidewalks far enough off.
func _choose_destination() -> void:
	var stops: Array[Node3D] = []
	for stop: Node3D in get_tree().get_nodes_in_group("taxi_stops"):
		var d := _flat(stop.global_position, _pickup)
		if d > trip_range.x * 0.5:
			stops.append(stop)
	if not stops.is_empty() and randf() < stop_share:
		var stop: Node3D = stops.pick_random()
		_dest = stop.global_position
		# What they call it: its "place" metadata, or "the" and its name.
		_dest_name = String(stop.get_meta("place", "the " + stop.name.capitalize().to_lower()))
		_dest_walk = null
		return
	var town: Node = main.get_node("Townsfolk")
	var best := {}
	for attempt in 80:
		var i: int = randi() % town.path_count()
		var where: Dictionary = town.point_on(i, randf() * town.path_length(i))
		var d := _flat(where["position"], _pickup)
		if d >= trip_range.x and d <= trip_range.y:
			best = where
			break
		# Failing that, the farthest one tried.
		if best.is_empty() or d > _flat(best["position"], _pickup):
			best = where
	var kerb: Vector3 = best["kerb"]
	# Where the car stops: on the road just off the kerb.
	_dest = best["position"] + kerb * (best["width"] * 0.5 + 1.8)
	_dest_walk = best["position"]
	_dest_name = "this address"


## What the meter says now.
func _fare() -> float:
	var fare := base_fare + per_km * _driven / 1000.0
	var cap := (base_fare + per_km * _direct * 1.3 / 1000.0) * fare_cap
	return minf(fare, cap)


func _pay(fare: float) -> void:
	var seconds := Time.get_ticks_msec() / 1000.0 - _started
	var tip := 0.0
	if _hits == 0 and seconds <= _par:
		tip = roundf(fare * tip_share / 10.0) * 10.0
	fare = roundf(fare / 10.0) * 10.0
	main.wallet.earn(fare + tip)
	main.wallet.save()
	var text := "Passenger: \"%s\"\nFare %s" % [THANKS.pick_random(), Wallet.format(fare)]
	if tip > 0.0:
		text += "  +  tip %s" % Wallet.format(tip)
	_say(text)
	_get_out()


## They get out at the side of the car and walk off.
func _get_out() -> void:
	_passenger.visible = true
	var door := _door()
	_passenger.global_position = door
	var away: Vector3 = (door - cab.global_position)
	away.y = 0.0
	_walk_to = _dest_walk if _dest_walk is Vector3 and _flat(_dest_walk, door) < 12.0 else door + away.normalized() * 4.0
	_walk_done = _passenger_gone
	stage = Stage.ALIGHTING


func _passenger_leaves(text: String) -> void:
	_say(text)
	_dest_walk = null
	_get_out()


func _passenger_gone() -> void:
	if _passenger:
		_passenger.queue_free()
	_passenger = null
	stage = Stage.WAITING
	_wait = randf_range(next_fare_wait.x, next_fare_wait.y)


func _end_duty(text: String) -> void:
	_say(text)
	if _passenger:
		_passenger.queue_free()
	_passenger = null
	stage = Stage.OFF
	_show_target(null)
	cab = null


# --- the passenger walking ---------------------------------------------------------

func _walk_passenger(delta: float) -> void:
	if _passenger == null:
		return
	var to := _walk_to - _passenger.global_position
	to.y = 0.0
	var step := WALK_SPEED * delta
	if to.length() <= step:
		_passenger.global_position = _walk_to
		_idle()
		var done := _walk_done
		_walk_done = Callable()
		if done.is_valid():
			done.call()
		return
	var p := _passenger.global_position + to.normalized() * step
	p.y = _ground_below(p, _passenger.global_position.y)
	_passenger.global_position = p
	_face(to)
	if _anim and _anim.has_animation("walk"):
		if _anim.current_animation != "walk":
			_anim.play("walk", 0.25)
		_anim.speed_scale = WALK_SPEED / _walk_anim_speed


func _idle() -> void:
	if _anim == null:
		return
	_anim.speed_scale = 1.0
	var want := "look" if _anim.has_animation("look") else "idle"
	if _anim.has_animation(want) and _anim.current_animation != want:
		_anim.play(want, 0.3)


func _face(dir: Vector3) -> void:
	if Vector2(dir.x, dir.z).length() > 0.01:
		_passenger.rotation.y = atan2(dir.x, dir.z)


## The back door on the kerb side of the car (the side away from the driver).
func _door() -> Vector3:
	var eyes: Vector3 = cab.get("driver_view") if cab.get("driver_view") is Vector3 else Vector3(0.37, 1.1, 0.0)
	var side := -1.0 if eyes.x >= 0.0 else 1.0
	var half: Vector3 = main._half_size(cab)
	var at := cab.to_global(Vector3(side * (half.x + 0.45), 0.0, -0.5))
	at.y = _ground_below(at, cab.global_position.y - 0.4)
	return at


func _ground_below(at: Vector3, fallback: float) -> float:
	var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 2.0, at + Vector3.DOWN * 4.0)
	ray.collision_mask = 1
	var skip: Array[RID] = []
	for car: CollisionObject3D in get_tree().get_nodes_in_group("cars"):
		skip.append(car.get_rid())
	ray.exclude = skip
	var hit := main.get_world_3d().direct_space_state.intersect_ray(ray)
	return (hit["position"] as Vector3).y if hit else fallback


# --- bits ---------------------------------------------------------------------

func _taxis() -> Array:
	return get_tree().get_nodes_in_group("cars").filter(func(c: Node) -> bool: return is_taxi(c))


func _you() -> Vector3:
	return main.player.global_position if main.on_foot else main.car.global_position


func _stopped() -> bool:
	return cab != null and cab.linear_velocity.length() < STOPPED


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


static func _distance_text(metres: float) -> String:
	if metres >= 1000.0:
		return "%.1f km" % (metres / 1000.0)
	return "%d m" % roundi(metres)


## A line across the top of the screen (the mission banner, game/mission_manager.gd).
func _say(text: String) -> void:
	var missions = main.get("missions")
	if missions:
		missions.show_banner(text)
	else:
		print(text)


func _show_target(at: Variant) -> void:
	var minimap: Control = main.get("minimap")
	if minimap:
		minimap.set_marker("taxi", at, GREEN)
	if not at is Vector3:
		_beam.visible = false
		return
	_beam.visible = true
	_beam.global_position = at + Vector3.UP * BEAM_HEIGHT * 0.5
	var d := _flat(_you(), at)
	_beam_material.albedo_color.a = clampf((d - 8.0) / 40.0, 0.0, 1.0) * 0.35


## Under the mission panel (or the key help) on the left.
func _place_panel() -> void:
	var top := 20.0
	var above: Array[Control] = []
	var help := main.get_node_or_null("HUD/Help") as Control
	if help:
		above.append(help)
	var missions = main.get("missions")
	if missions and missions.get("_panel"):
		above.append(missions._panel)
	for c in above:
		if c.visible:
			top = maxf(top, c.position.y + c.size.y + 12.0)
	_panel.position = Vector2(20.0, top)


func _light_signs() -> void:
	for car: VehicleBody3D in _signs:
		var lit: bool = car == cab and stage in [Stage.WAITING, Stage.PICKUP]
		var mat: StandardMaterial3D = _signs[car]
		mat.albedo_color = SIGN_LIT if lit else SIGN_DARK
		mat.emission_enabled = lit


## A TAXI box on the car's roof (over the middle of its body, from its meshes).
func _add_sign(car: VehicleBody3D) -> void:
	var box := AABB()
	var first := true
	var to_car := car.global_transform.affine_inverse()
	for mi: MeshInstance3D in car.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var b := (to_car * mi.global_transform) * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first:
		return
	var roof := Node3D.new()
	roof.name = "TaxiSign"
	var centre := box.get_center()
	roof.position = Vector3(centre.x, box.end.y + 0.08, centre.z - box.size.z * 0.06)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.62, 0.16, 0.24)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = SIGN_DARK
	mat.emission = SIGN_LIT
	mat.emission_energy_multiplier = 1.6
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	roof.add_child(mi)
	for z: float in [0.121, -0.121]:
		var label := Label3D.new()
		label.text = "TAXI"
		label.font_size = 48
		label.outline_size = 0
		label.pixel_size = 0.0035
		label.modulate = Color(0.08, 0.08, 0.08)
		label.position = Vector3(0.0, 0.0, z)
		label.rotation.y = 0.0 if z > 0.0 else PI
		label.double_sided = false
		roof.add_child(label)
	car.add_child(roof)
	_signs[car] = mat


func _build_hud() -> void:
	var hud: CanvasLayer = main.get_node("HUD")
	_panel = PanelContainer.new()
	_panel.name = "Taxi"
	_panel.custom_minimum_size = Vector2(420.0, 0.0)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.0, 0.0, 0.0, 0.55)
	box.border_color = GREEN
	box.border_width_left = 4
	box.set_corner_radius_all(5)
	box.set_content_margin_all(10.0)
	box.content_margin_left = 14.0
	_panel.add_theme_stylebox_override("panel", box)
	_panel.visible = false
	var rows := VBoxContainer.new()
	_panel.add_child(rows)
	_title = Label.new()
	_title.add_theme_color_override("font_color", GREEN)
	_title.add_theme_font_size_override("font_size", 18)
	rows.add_child(_title)
	_line = Label.new()
	_line.add_theme_font_size_override("font_size", 22)
	rows.add_child(_line)
	hud.add_child(_panel)


func _build_beam() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.7
	mesh.bottom_radius = 0.7
	mesh.height = BEAM_HEIGHT
	mesh.cap_top = false
	mesh.cap_bottom = false
	_beam_material = StandardMaterial3D.new()
	_beam_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beam_material.albedo_color = Color(GREEN, 0.35)
	mesh.material = _beam_material
	_beam = MeshInstance3D.new()
	_beam.name = "TaxiBeam"
	_beam.mesh = mesh
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.visible = false
	add_child(_beam)
