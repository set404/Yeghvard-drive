extends Node3D
## Someone the story brings on who is not one of the townsfolk: Davitik (the
## second mission, missions/davitik_lesson.gd), or the uncle whose wall he drives
## into. A mission moves him about: stand somewhere, walk or run to a spot, run
## after a car and climb into its passenger's seat, sit in a car (at the wheel
## or beside it), get out again. Slapped (slap()), he reels with stars round his
## head; a car that runs into him (any car going faster than KNOCK_SPEED) throws
## him through the air, and after a moment he gets up again. It is that kind of game.
##
## His figure: made from data/models/special characters/Davitik/Davitik.fbx by
## npc/davitik_figure.gd (the first time, then kept in user://), with the
## animations idle, walk, run, drive, drink, hit, die, cower; or
## res://npc/davitik.scn when tools/build_davitik.gd has built it. setup() can
## take another figure (an npc/*.scn of the townsfolk: idle, walk, talk, run...).

signal hit_by_car(times: int)
signal slapped(times: int)

const DAVITIK_SCENE := "res://npc/davitik.scn"
const DavitikFigure := preload("res://npc/davitik_figure.gd")
const DUET_SCENE := "res://props/duet.glb"
const Sfx := preload("res://game/sfx.gd")

enum Mode { STAND, GO, FOLLOW_CAR, SEATED, DOWN, REEL }

## Metres a second walking and running.
@export var walk_speed := 1.5
@export var run_speed := 5.2
## How tall he is (metres): the figure is scaled to it.
@export var height := 1.78
## Seconds he lies on the ground after a car knocks him over.
@export var down_seconds := 2.4
## A car going at least this fast (m/s) knocks him over.
const KNOCK_SPEED := 2.5
## Far behind a car he runs after, he sprints (it's Davitik, he does not give up).
const SPRINT_SPEED := 9.0
const SPRINT_BEYOND := 60.0

var mode := Mode.STAND
## The game (main.gd).
var main: Node3D
## Times a car knocked him over, and slaps taken.
var car_hits := 0
var slaps := 0
## Running after a car: whether he climbs into its passenger's seat once he
## reaches the door with the car stopped.
var get_in_when_caught := true
## Whether cars knock him over.
var knockable := true
## The car he sits in (or runs after), and whether in the passenger's seat.
var car: VehicleBody3D
var passenger := false

var _model: Node3D
var _anim: AnimationPlayer
var _speeds := {}
var _scale := 1.0
var _goal := Vector3.ZERO
var _running := false
## What he went back to doing after lying down or reeling.
var _resume := Mode.STAND
## Seconds left lying down or reeling; seconds before a car can knock him over again.
var _left := 0.0
var _cooldown := 0.0
## Knocked back by a slap (m/s, level).
var _knock := Vector3.ZERO
## Where he looks while he stands, or null.
var _look_at: Variant = null
var _stars: Node3D
var _stars_left := 0.0
var _cup: Node3D
## perform(): seconds left of what he does, and what he goes back to after it.
var _act_left := 0.0
var _act_after := "idle"


## Starts getting Davitik's figure ready in the background (before he is needed).
static func prepare() -> void:
	if not ResourceLoader.exists(DAVITIK_SCENE):
		DavitikFigure.prepare()


## Whether Davitik's figure is ready to be taken without holding the game up.
static func figure_ready() -> bool:
	return ResourceLoader.exists(DAVITIK_SCENE) or DavitikFigure.ready()


## Makes the figure. `game` is main.gd; `scene_path` another figure than Davitik's.
func setup(game: Node3D, scene_path := DAVITIK_SCENE) -> void:
	main = game
	if scene_path == DAVITIK_SCENE and not ResourceLoader.exists(DAVITIK_SCENE):
		# Not built with tools/build_davitik.gd: made from his FBX (slow only the first time).
		_model = DavitikFigure.take()
	elif ResourceLoader.exists(scene_path):
		var packed := load(scene_path) as PackedScene
		_model = packed.instantiate() as Node3D if packed else null
	if _model == null:
		push_warning("No figure for %s (%s): a stand-in instead." % [name, scene_path])
		_model = _stand_in()
	_model.name = "Figure"
	add_child(_model)
	_anim = _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var tall := float(_model.get_meta("height", 0.0))
	if tall < 0.5 or tall > 3.0:
		tall = _measure()
	_scale = height / tall if tall > 0.01 else 1.0
	_model.scale = Vector3.ONE * _scale
	var speeds: Variant = _model.get_meta("speeds", {})
	_speeds = speeds if speeds is Dictionary else {}
	if not _speeds.has("walk") and _model.has_meta("walk_speed"):
		_speeds["walk"] = float(_model.get_meta("walk_speed"))
	_play("idle", 0.0)


## Stands him at `at` (on the ground there), facing along `facing`.
func place(at: Vector3, facing := Vector3.ZERO) -> void:
	_leave_car()
	global_position = _on_ground(at)
	if not facing.is_zero_approx():
		_face(facing)
	stand()


## Stands still (looking towards `look_at`, a point, if given).
func stand(look_at: Variant = null) -> void:
	mode = Mode.STAND
	_look_at = look_at
	_act_left = 0.0
	_act_after = "idle"
	_play("idle")


## Turns him to look towards `at` while he stands (null: as he is), without
## changing what he is doing.
func look(at: Variant) -> void:
	_look_at = at


## Walks (or runs) to `at` and stands there.
func go_to(at: Vector3, run := false) -> void:
	_leave_car()
	_goal = at
	_running = run
	mode = Mode.GO


## Whether he has got where go_to() sent him.
func arrived() -> bool:
	return mode == Mode.STAND


## Runs after `target` and, once he reaches its passenger door with it stopped,
## gets in (with get_in_when_caught).
func follow_car(target: VehicleBody3D, run := true) -> void:
	_leave_car()
	car = target
	_running = run
	mode = Mode.FOLLOW_CAR


## Sits him in `in_car`: at the wheel, or (`as_passenger`) beside it.
func sit_in(in_car: VehicleBody3D, as_passenger := false) -> void:
	hold_cup(false)
	car = in_car
	passenger = as_passenger
	mode = Mode.SEATED
	_knock = Vector3.ZERO
	if get_parent() != in_car:
		reparent(in_car, false)
	transform = Transform3D(Basis.IDENTITY, seat_origin(_model, in_car, as_passenger, _scale))
	_play("drive", 0.0)


## Whether he is sitting in `in_car` (any car with null).
func seated_in(in_car: VehicleBody3D = null) -> bool:
	return mode == Mode.SEATED and car != null and (in_car == null or car == in_car)


## Out of the car he sits in, standing beside his door.
func get_out() -> void:
	if mode != Mode.SEATED or car == null:
		return
	var spot := door_spot(car, passenger, main)
	var away := spot - car.global_position
	_leave_car()
	place(spot, away)


## Shows (or puts away) a Duet in his right hand.
func hold_cup(on: bool) -> void:
	if not on:
		if _cup:
			_cup.queue_free()
			_cup = null
		return
	if _cup or not ResourceLoader.exists(DUET_SCENE):
		return
	var skeleton := _model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return
	var hand := -1
	for b in skeleton.get_bone_count():
		if skeleton.get_bone_name(b).ends_with("RightHand"):
			hand = b
	if hand < 0:
		return
	var grip := BoneAttachment3D.new()
	grip.bone_name = skeleton.get_bone_name(hand)
	skeleton.add_child(grip)
	var cup: Node3D = (load(DUET_SCENE) as PackedScene).instantiate()
	# The hand bone's scale in the world (Mixamo's centimetres, his size) undone:
	# the cup at the size it is in your hand.
	var bone_scale := (skeleton.global_basis * skeleton.get_bone_global_pose(hand).basis).get_scale().x
	var undo := 1.0 / maxf(bone_scale, 0.0001)
	cup.scale = Vector3.ONE * undo * 0.75
	cup.position = Vector3(0.0, 0.08, 0.04) * undo
	grip.add_child(cup)
	_cup = grip


## Plays one of his animations ("drink", "cower"...) while he stands; "idle" back to normal.
func act(anim_name: String) -> void:
	if mode == Mode.STAND:
		_act_after = anim_name
		_act_left = 0.0
		_play(anim_name)


## Does `anim_name` ("talk", "point", "laugh"...) for `seconds` while he stands,
## then goes back to `after` (what he was doing). False if he has no such
## animation or is not standing.
func perform(anim_name: String, seconds: float, after := "") -> bool:
	if mode != Mode.STAND or _anim == null or not _anim.has_animation(anim_name):
		return false
	if after == "":
		after = _act_after
	_act_after = after
	_act_left = seconds
	_play(anim_name, 0.2)
	return true


## His AnimationPlayer (for game/extra_anims.gd), or null.
func animation_player() -> AnimationPlayer:
	return _anim


## A slap from someone standing at `from`: he reels back a step, stars round his head.
func slap(from: Vector3) -> void:
	if mode == Mode.SEATED or mode == Mode.DOWN:
		return
	slaps += 1
	if mode != Mode.REEL:
		_resume = mode
	mode = Mode.REEL
	_left = 0.8
	var away := global_position - from
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else -global_basis.z
	_knock = away * 1.6
	_face(-away)
	if _anim and _anim.has_animation("hit"):
		_anim.play("hit", 0.05)
		_anim.seek(0.0, true)
	Sfx.play(main, Sfx.punch(), global_position + Vector3.UP * 1.5, 9.0)
	_show_stars(2.0)
	slapped.emit(slaps)


## Knocked over by a car going at `velocity`: thrown the way it went, he lies a
## moment and gets up again.
func knock(velocity: Vector3) -> void:
	if mode == Mode.SEATED or mode == Mode.DOWN:
		return
	car_hits += 1
	if mode != Mode.REEL:
		_resume = mode
	mode = Mode.DOWN
	_left = down_seconds
	_cooldown = down_seconds + 1.0
	hold_cup(false)
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var away := flat.normalized() if flat.length() > 0.1 else -global_basis.z
	var speed := flat.length()
	var land := _on_ground(global_position + away * clampf(speed * 0.45, 2.0, 9.0))
	var top := (global_position + land) * 0.5 + Vector3.UP * clampf(speed * 0.15, 0.6, 2.5)
	# Facing the car, so the fall throws him backwards, away from it.
	_face(-away)
	if _anim and _anim.has_animation("die"):
		_anim.play("die", 0.05)
		_anim.seek(0.0, true)
	else:
		var axis := Vector3.UP.cross(away).normalized()
		var lying := Basis(axis, PI * 0.5) * global_basis.orthonormalized()
		create_tween().tween_property(self, "quaternion", lying.get_rotation_quaternion(), 0.4)
	var fly := create_tween()
	fly.tween_property(self, "global_position", top, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	fly.tween_property(self, "global_position", land, 0.35).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	Sfx.play(main, Sfx.punch(), global_position + Vector3.UP, 12.0)
	hit_by_car.emit(car_hits)


## Where he (or anyone) gets out on that side of `of_car`: beside the driver's
## door, or the passenger's.
static func door_spot(of_car: VehicleBody3D, on_passenger_side: bool, game: Node3D = null) -> Vector3:
	var view: Variant = of_car.get("driver_view")
	var eyes: Vector3 = view if view is Vector3 else Vector3(0.37, 1.13, 0.1)
	var side := 1.0 if eyes.x >= 0.0 else -1.0
	if on_passenger_side:
		side = -side
	var half := Vector3(0.95, 0.75, 2.3)
	if game and game.has_method("_half_size"):
		half = game.call("_half_size", of_car)
	return of_car.to_global(Vector3(side * (half.x + 0.7), 0.0, eyes.z))


## Where a seated figure goes in `in_car` (its origin, in the car's space) so
## that its eyes are where the driver's are (driver_view), or mirrored across
## for the passenger: from the "drive_eyes" metadata tools/build_character.gd
## and tools/build_davitik.gd measure. `s` is the figure's scale.
static func seat_origin(figure: Node3D, in_car: Node3D, as_passenger: bool, s: float) -> Vector3:
	var view: Variant = in_car.get("driver_view")
	var eye_point: Vector3 = view if view is Vector3 else Vector3(0.37, 1.13, 0.1)
	if as_passenger:
		eye_point.x = -eye_point.x
	if not figure.has_meta("drive_eyes"):
		# Not measured: about where a seated person's feet go under eyes there.
		return Vector3(eye_point.x, eye_point.y - 1.15, eye_point.z - 0.35)
	var eyes: Vector3 = figure.get_meta("drive_eyes")
	var at := eye_point + Vector3(0.0, 0.0, 0.05) - eyes * s
	if not as_passenger:
		var hands: Vector3 = figure.get_meta("drive_hands", eyes)
		var wheel := in_car.find_child("SteeringWheel", true, false) as Node3D
		if wheel and wheel.is_inside_tree():
			var short := in_car.to_local(wheel.global_position).z - (at + hands * s).z
			at.z += clampf(short, 0.0, 0.15)
	return at


func _physics_process(delta: float) -> void:
	_tick_stars(delta)
	_keep_cup_upright()
	if mode == Mode.SEATED:
		return
	_cooldown -= delta
	match mode:
		Mode.DOWN:
			_left -= delta
			if _left <= 0.0:
				_get_up()
			return
		Mode.REEL:
			_left -= delta
			global_position = _on_ground(global_position + _knock * delta)
			_knock = _knock.move_toward(Vector3.ZERO, 5.0 * delta)
			if _left <= 0.0:
				mode = _resume
				_play("idle")
			return
	if knockable and _cooldown <= 0.0:
		var hitting := _car_hitting()
		if hitting:
			knock(hitting.linear_velocity)
			return
	match mode:
		Mode.STAND:
			if _act_left > 0.0:
				_act_left -= delta
				if _act_left <= 0.0:
					_play(_act_after, 0.3)
			if _look_at is Vector3:
				var to: Vector3 = _look_at - global_position
				to.y = 0.0
				if to.length() > 0.3:
					rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), 1.0 - exp(-6.0 * delta))
			if _anim and _anim.current_animation in ["walk", "run", ""]:
				_play(_act_after if _act_left <= 0.0 else "idle")
		Mode.GO:
			if _move_to(_goal, delta, _running, run_speed):
				stand()
		Mode.FOLLOW_CAR:
			if car == null or not is_instance_valid(car):
				stand()
				return
			var door := door_spot(car, true, main)
			var far := Vector2(door.x - global_position.x, door.z - global_position.z).length()
			var speed := SPRINT_SPEED if far > SPRINT_BEYOND else run_speed
			if _move_to(door, delta, _running, speed) or far < 1.2:
				_look_at = car.global_position
				if get_in_when_caught and car.linear_velocity.length() < 1.0:
					sit_in(car, true)


## Steps towards `at`; true once he is there.
func _move_to(at: Vector3, delta: float, run: bool, speed: float) -> bool:
	var to := at - global_position
	to.y = 0.0
	var dist := to.length()
	if dist < 0.5:
		_play("idle")
		return true
	var pace := speed if run else walk_speed
	var step := minf(pace * delta, dist)
	var dir := to / dist
	global_position = _on_ground(global_position + dir * step)
	rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), 1.0 - exp(-10.0 * delta))
	var anim_name := "run" if run and _anim and _anim.has_animation("run") else "walk"
	_play(anim_name)
	if _anim:
		var natural := float(_speeds.get(anim_name, 0.0)) * _scale
		_anim.speed_scale = clampf(pace / natural, 0.5, 2.2) if natural > 0.1 else 1.0
	return false


func _get_up() -> void:
	# Toppled over (no "die" animation): stood upright again.
	rotation.x = 0.0
	rotation.z = 0.0
	_cooldown = 1.0
	mode = _resume if _resume != Mode.SEATED else Mode.STAND
	_play("idle", 0.4)
	_show_stars(2.5)


## A car (other than the one he sits in) running into him, or null.
func _car_hitting() -> VehicleBody3D:
	var middle := global_position + Vector3.UP * 0.9
	for other: VehicleBody3D in get_tree().get_nodes_in_group("cars"):
		if other.linear_velocity.length() < KNOCK_SPEED:
			continue
		var half := Vector3(0.95, 0.75, 2.3)
		if main and main.has_method("_half_size"):
			half = main.call("_half_size", other)
		var local := other.to_local(middle)
		if absf(local.x) < half.x + 0.3 and absf(local.z) < half.z + 0.3 and local.y > -1.5 and local.y < half.y + 1.2:
			return other
	return null


## Out of a car he sat in: back under the game, standing.
func _leave_car() -> void:
	if get_parent() != main and main:
		var xf := global_transform
		reparent(main, false)
		global_transform = Transform3D(Basis.IDENTITY, xf.origin)
		rotation.y = xf.basis.get_euler().y
	if mode == Mode.SEATED:
		mode = Mode.STAND
		if _anim:
			_anim.speed_scale = 1.0


## `at` set down on the ground (road, pavement...) under it.
func _on_ground(at: Vector3) -> Vector3:
	if not is_inside_tree():
		return at
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 2.0, at + Vector3.DOWN * 8.0)
	query.collision_mask = 1
	var skip: Array[RID] = []
	for c: CollisionObject3D in get_tree().get_nodes_in_group("cars"):
		skip.append(c.get_rid())
	if main and main.get("player") is CollisionObject3D:
		skip.append((main.get("player") as CollisionObject3D).get_rid())
	query.exclude = skip
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit:
		at.y = (hit["position"] as Vector3).y
	return at


func _face(dir: Vector3) -> void:
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length() > 0.001:
		rotation = Vector3(0.0, atan2(flat.x, flat.z), 0.0)


func _play(anim_name: String, blend := 0.25) -> void:
	if _anim == null:
		return
	if not _anim.has_animation(anim_name):
		anim_name = "idle" if _anim.has_animation("idle") else ""
	if anim_name == "" or _anim.current_animation == anim_name:
		return
	_anim.speed_scale = 1.0
	_anim.play(anim_name, blend)


## Stars spinning round his head for `seconds`.
func _show_stars(seconds: float) -> void:
	_stars_left = maxf(_stars_left, seconds)
	if _stars:
		_stars.visible = true
		return
	_stars = Node3D.new()
	_stars.name = "Stars"
	add_child(_stars)
	_stars.position.y = height + 0.15
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.1)
	mat.emission_energy_multiplier = 2.0
	var ball := SphereMesh.new()
	ball.radius = 0.045
	ball.height = 0.09
	ball.material = mat
	for k in 4:
		var star := MeshInstance3D.new()
		star.mesh = ball
		star.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var a := TAU * k / 4.0
		star.position = Vector3(cos(a) * 0.25, 0.04 * sin(a * 2.0), sin(a) * 0.25)
		_stars.add_child(star)


## The Duet in his hand stays the right way up (his hand bone's axes turn it every which way).
func _keep_cup_upright() -> void:
	if _cup == null or _cup.get_child_count() == 0:
		return
	var cup := _cup.get_child(0) as Node3D
	var size := cup.global_basis.get_scale()
	cup.global_basis = Basis.from_euler(Vector3(0.0, global_rotation.y, 0.0)).scaled(size)


func _tick_stars(delta: float) -> void:
	if _stars == null:
		return
	_stars_left -= delta
	_stars.visible = _stars_left > 0.0
	_stars.rotation.y += 5.0 * delta


## His height (metres) from the figure's meshes, for a figure without "height".
func _measure() -> float:
	var low := INF
	var high := -INF
	for mi: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		var box := _model.global_transform.affine_inverse() * mi.global_transform * mi.get_aabb() if is_inside_tree() else mi.get_aabb()
		low = minf(low, box.position.y)
		high = maxf(high, box.end.y)
	var tall := high - low if high > low else 0.0
	# Meshes in tiny units sized by the skin (an AI-made model): the bones say how tall.
	var skeleton := _model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton and tall < 0.3:
		var top := 0.0
		for b in skeleton.get_bone_count():
			top = maxf(top, (skeleton.transform * skeleton.get_bone_global_rest(b)).origin.y)
		tall = top + 0.02
	return tall if tall > 0.3 else 1.8


## A plain capsule in his place when there is no figure at all.
func _stand_in() -> Node3D:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.25
	capsule.height = 1.78
	body.mesh = capsule
	body.position.y = 0.89
	root.add_child(body)
	root.set_meta("height", 1.78)
	return root
