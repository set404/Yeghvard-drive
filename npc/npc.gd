extends Node3D
## One of the townspeople. world/townsfolk.gd makes them, gives them a sidewalk
## to walk along and pairs them up to talk; this moves and animates one of them.
## The figure is one of the scenes tools/build_npcs.gd makes in res://npc.
## Hit by a car (townsfolk.gd finds that), they are thrown down and lie there
## for corpse_seconds, then are gone.
## At the end of their sidewalk they walk on to the next one on the same side
## (over a side street); passing a crosswalk they sometimes cross the road on it
## (townsfolk.gd links them). Before stepping on to the road they wait at the
## kerb, looking about, till no car is near, then walk over a little quicker.
## In a fight (player/combat.gd): hit, they lose health (take_hit) and either
## fight back, running at whoever hit them and punching, or run off along their
## sidewalk; a gunshot near them (townsfolk.gd alarm) sends them running too.
## Out of health they go down like someone hit by a car.

enum State { WALK, STAND, TALK, DEAD, CROSS, FLEE, FIGHT }

const Sfx := preload("res://game/sfx.gd")

## Crossing is this much quicker than their walk.
const CROSS_HURRY := 1.2
## Seconds they wait at the kerb for the cars before giving up and turning back.
const CROSS_PATIENCE := 20.0

## Seconds a body lies where it fell before it is taken away.
const CORPSE_SECONDS := 25.0

## Running away, and running at someone to fight (metres a second).
const RUN_SPEED := 4.2
const CHARGE_SPEED := 3.2
## How fast the Mixamo run covers ground at normal speed (they have no measure of it).
const RUN_ANIM_SPEED := 3.6
## Seconds they run before calming down; how long a fight lasts at most.
const FLEE_TIME := Vector2(10.0, 16.0)
const FIGHT_TIME := 25.0
## A punch of theirs: how close they get, every how many seconds, what it does,
## how long it takes and when in it it lands.
const PUNCH_REACH := 1.05
const PUNCH_EVERY := 1.3
const PUNCH_DAMAGE := 9.0
const PUNCH_TIME := 0.45
const PUNCH_LANDS := 0.18
## They give up the fight past this far from whoever they fight (metres).
const FIGHT_LOST := 30.0
## Chance someone punched fights back rather than running.
const BRAVE := 0.45
## Seconds someone hit reels (the "hit" animation's recoil, or the lean back)
## before they run or fight, and how hard a hit knocks them back (m/s).
const REEL_TIME := 0.75
const LEAN_TIME := 0.4
const KNOCK_PUNCH := 2.2
const KNOCK_SHOT := 3.0

var state := State.WALK
## The walk: which sidewalk (an index into the townsfolk's paths), how far
## along it (metres), which way (+1 or -1) and how fast (metres a second).
var path := -1
var along := 0.0
var direction := 1.0
var speed := 1.3
## Seconds left in the present state (standing, talking, or walking before a stop).
var time_left := 0.0
## Who they are talking to, and seconds before they would stop to talk again.
var partner: Node3D
var talk_cooldown := 0.0
## What they do standing: "idle", "look" or "phone".
var pastime := "idle"

var _townsfolk: Node
var _model: Node3D
var _anim: AnimationPlayer
var _phone: Node3D
var _body: AnimatableBody3D
var _walk_anim_speed := 1.5
var _yaw := 0.0
## Talking: seconds until the other one takes a turn, and whether it is our turn.
var _turn_left := 0.0
var _speaking := false
## Crossing: the points they walk through (a crosswalk's ends, then the
## right-hand lane of the sidewalk they come out on) and the next one, where
## they step on to the road (at the kerb they look out for cars first) and the
## stretch of road to look along, whether they have stepped off yet and how
## long they have waited, and the sidewalk, place and way they walk on from there.
var _cross_points := PackedVector3Array()
var _cross_next := 0
var _kerb := 0
var _road_from := Vector3.ZERO
var _road_to := Vector3.ZERO
var _leg_from := Vector3.ZERO
var _crossing := false
var _waited := 0.0
var _next_path := -1
var _next_at := 0.0
var _next_way := 1.0
## In a fight: health left (100 full), who they fight, what they run from,
## seconds till the next punch and how far into the one they throw (-1 none),
## whether it has landed, and their right arm for throwing it without a "punch"
## animation (world/cashier_hands.gd, made on first use).
var health := 100.0
var foe: Node3D
var _threat := Vector3.ZERO
var _punch_wait := 0.0
var _punch_t := -1.0
var _punch_landed := false
var _hands: SkeletonModifier3D
var _hit_lean := 0.0
## Running from something: crossing to the next sidewalk at a run, without
## waiting for cars, and seconds of running left after it.
var _panic := false
var _panic_left := 0.0
## Reeling from a hit: seconds left, and the knock back still carrying them (m/s, level).
var _reel_left := 0.0
var _knock := Vector3.ZERO


func setup(townsfolk: Node, figure: PackedScene, body_layer: int) -> void:
	_townsfolk = townsfolk
	_model = figure.instantiate()
	add_child(_model)
	_anim = _model.get_node("AnimationPlayer")
	_phone = _model.get_node_or_null("Skeleton3D/RightHand/Phone")
	_walk_anim_speed = maxf(float(_model.get_meta("walk_speed", 1.5)), 0.1)
	var height := float(_model.get_meta("height", 1.75))
	# Something for you to bump into (only you: see townsfolk.gd), not cars.
	var body := AnimatableBody3D.new()
	_body = body
	body.sync_to_physics = false
	body.collision_layer = body_layer
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.25
	capsule.height = height
	shape.shape = capsule
	shape.position.y = height * 0.5
	body.add_child(shape)
	add_child(body)
	speed = randf_range(1.05, 1.45)
	_anim.speed_scale = 1.0


## Walk along the given sidewalk, from `at` metres, the given way.
func walk(on_path: int, at: float, way: float) -> void:
	path = on_path
	along = at
	direction = way
	state = State.WALK
	time_left = randf_range(15.0, 50.0)
	_set_phone(false)
	_place(true)


## Stand where they are doing something for a while.
func stand(seconds: float, what := "") -> void:
	state = State.STAND
	time_left = seconds
	pastime = what if what != "" else ["idle", "look", "phone", "phone"].pick_random()
	_set_phone(pastime == "phone")
	_play(pastime)


## Stop and talk to `other` (who is told the same) for a while.
func talk_to(other: Node3D, seconds: float, first: bool) -> void:
	partner = other
	state = State.TALK
	# Stand about a metre apart, face to face.
	var gap := other.global_position - global_position
	gap.y = 0.0
	if gap.length() > 1.2:
		global_position += gap - gap.normalized() * 1.1 if first else Vector3.ZERO
	elif gap.length() < 0.8 and gap.length() > 0.01:
		global_position -= gap.normalized() * (0.9 - gap.length())
	time_left = seconds
	_speaking = first
	_turn_left = randf_range(2.0, 3.5)
	_set_phone(false)
	_play("talk" if _speaking else "listen")


## Knocked down by a car moving at `velocity`: they are thrown the way it went
## and lie down; they stop being in the way and are removed after a while.
func die(velocity: Vector3) -> void:
	if state == State.DEAD:
		return
	state = State.DEAD
	partner = null
	time_left = CORPSE_SECONDS
	_set_phone(false)
	if _body:
		_body.queue_free()
		_body = null
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var away := flat.normalized() if flat.length() > 0.1 else -global_basis.z
	var hit_speed := flat.length()
	_anim.speed_scale = 1.0
	# Where they come down: thrown some way ahead of the car, on the ground there.
	var land := global_position + away * clampf(hit_speed * 0.35, 1.0, 7.0)
	land.y = _ground_below(land, global_position.y)
	if _anim.has_animation("die"):
		# The death animation throws them backwards (it carries them some way
		# itself): face the car, so they fly away from it, and a faster car
		# throws them farther still.
		rotation.y = atan2(-away.x, -away.z)
		_anim.play("die", 0.08)
		var extra := global_position + away * clampf(hit_speed * 0.2 - 1.5, 0.0, 5.0)
		extra.y = _ground_below(extra, global_position.y)
		var slide := create_tween()
		slide.tween_property(self, "global_position", extra, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		return
	# No death animation: the pose they were in, toppled over the way they were
	# thrown (turned about their feet until they lie flat on their back or front).
	_anim.pause()
	var axis := Vector3.UP.cross(away).normalized()
	var lying := Basis(axis, PI * 0.5) * global_basis.orthonormalized()
	land.y += 0.13
	var fall := create_tween().set_parallel(true)
	fall.tween_property(self, "global_position", land, 0.55).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	fall.tween_property(self, "quaternion", lying.get_rotation_quaternion(), 0.45).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)


## The height of the ground (or road, sidewalk...) under `at`, or `fallback`.
func _ground_below(at: Vector3, fallback: float) -> float:
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 2.0, at + Vector3.DOWN * 6.0)
	var skip: Array[RID] = []
	for car: CollisionObject3D in get_tree().get_nodes_in_group("cars"):
		skip.append(car.get_rid())
	query.exclude = skip
	query.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return (hit["position"] as Vector3).y if hit else fallback


func _set_phone(on: bool) -> void:
	if _phone:
		_phone.visible = on


func _play(anim_name: String, blend := 0.35) -> void:
	if _anim.current_animation != anim_name:
		_anim.play(anim_name, blend)
		# Start somewhere else in the loop, so people doing the same are not in step.
		if anim_name != "walk":
			_anim.seek(randf() * _anim.current_animation_length, true)


func _process(delta: float) -> void:
	talk_cooldown = maxf(talk_cooldown - delta, 0.0)
	# Reeling from a hit: knocked back a step, the reaction plays out, nothing else.
	if _reel_left > 0.0 and state != State.DEAD:
		_reel(delta)
		return
	match state:
		State.WALK:
			_walk(delta)
		State.STAND:
			time_left -= delta
			if time_left <= 0.0:
				# Off again, sometimes back the way they came.
				walk(path, along, direction if randf() < 0.6 else -direction)
		State.TALK:
			_talk(delta)
		State.CROSS:
			_cross(delta)
		State.FLEE:
			_flee(delta)
		State.FIGHT:
			_fight(delta)
		State.DEAD:
			time_left -= delta
			if time_left <= 0.0:
				queue_free()
			return
	rotation.y = lerp_angle(rotation.y, _yaw, 1.0 - exp(-(10.0 if state == State.FIGHT else 6.0) * delta))
	# Rocked back by a hit (without a "hit" animation), then upright again.
	if _hit_lean > 0.0:
		_hit_lean = maxf(_hit_lean - delta * 2.5, 0.0)
		_model.rotation.x = -sin(_hit_lean * PI) * 0.35


func _walk(delta: float) -> void:
	var length: float = _townsfolk.path_length(path)
	if _townsfolk.blocked(self):
		# Someone (you, or a slower walker) in the way: wait.
		_anim.speed_scale = 1.0
		_play("idle", 0.25)
		return
	_play("walk", 0.25)
	_anim.speed_scale = speed / _walk_anim_speed
	var before := along
	along += direction * speed * delta
	if along <= 0.0 or along >= length:
		along = clampf(along, 0.0, length)
		# The end of the sidewalk: usually on to the next one, across the road.
		if randf() < _townsfolk.end_cross_chance and _try_cross(_townsfolk.links_at_end(path, along)):
			return
		direction = -direction
		stand(randf_range(3.0, 8.0))
		_anim.speed_scale = 1.0
		return
	_place(false)
	# Passing a crosswalk: now and then over to the other side; where another
	# sidewalk joins, now and then on to it.
	for link: Dictionary in _townsfolk.links_passed(path, before, along):
		var chance: float = _townsfolk.crosswalk_chance if link["crosswalk"] else _townsfolk.turn_chance
		if randf() < chance and _try_cross([link]):
			return
	time_left -= delta
	if time_left <= 0.0:
		_anim.speed_scale = 1.0
		stand(randf_range(5.0, 14.0))


## Sets off across one of these links (townsfolk.gd) whose way is clear;
## false if there is none.
func _try_cross(links: Array) -> bool:
	var open := links.filter(func(l: Dictionary) -> bool: return _townsfolk.link_ok(l, path))
	if open.is_empty():
		return false
	var link: Dictionary = open.pick_random()
	_next_path = link["to_path"]
	_next_at = link["to_at"]
	# Out at an end of the next sidewalk, along it; in its middle, either way.
	var length: float = _townsfolk.path_length(_next_path)
	if _next_at < 1.5:
		_next_way = 1.0
	elif _next_at > length - 1.5:
		_next_way = -1.0
	else:
		_next_way = 1.0 if randf() < 0.5 else -1.0
	var where: Dictionary = _townsfolk.point_on(_next_path, _next_at)
	var right: Vector3 = (where["forward"] * _next_way).cross(Vector3.UP).normalized()
	var via: PackedVector3Array = link["via"]
	_cross_points = via.duplicate()
	_cross_points.append(where["position"] + right * where["width"] * 0.22)
	_cross_next = 0
	# Over a crosswalk the road is between its ends: first to the kerb, then
	# look. Over a side street it starts where they stand.
	if via.size() >= 2:
		_kerb = 1
		_road_from = via[0]
		_road_to = via[via.size() - 1]
	else:
		_kerb = 0
		_road_from = global_position
		_road_to = _cross_points[0]
	_leg_from = global_position
	_crossing = false
	_waited = 0.0
	state = State.CROSS
	_set_phone(false)
	return true


## To the kerb, there looking out for cars, then over the road.
func _cross(delta: float) -> void:
	var goal := _cross_points[_cross_next]
	var to := goal - global_position
	to.y = 0.0
	if to.length() > 0.05:
		_yaw = atan2(to.x, to.z)
	if _cross_next == _kerb and not _crossing and not _panic:
		if _townsfolk.traffic_on(_road_from, _road_to):
			_waited += delta
			_anim.speed_scale = 1.0
			_play("look" if _anim.has_animation("look") else "idle", 0.3)
			if _waited > CROSS_PATIENCE:
				# Too busy: back the way they came.
				walk(path, along, -direction)
			return
		_crossing = true
	if not _panic and _townsfolk.blocked(self):
		_anim.speed_scale = 1.0
		_play("idle", 0.25)
		return
	# Up to the kerb at their own pace, over the road a little quicker;
	# running from something, at a run all the way.
	var pace := speed * (CROSS_HURRY if _crossing else 1.0)
	if _panic:
		pace = RUN_SPEED
		if _anim.has_animation("run"):
			_play("run", 0.2)
			_anim.speed_scale = pace / RUN_ANIM_SPEED
		else:
			_play("walk", 0.2)
			_anim.speed_scale = minf(pace / _walk_anim_speed, 2.6)
	else:
		_play("walk", 0.25)
		_anim.speed_scale = pace / _walk_anim_speed
	var left := to.length()
	var step := pace * delta
	if left <= step:
		global_position = goal
		_cross_next += 1
		_leg_from = goal
		if _cross_next >= _cross_points.size():
			walk(_next_path, _next_at, _next_way)
			if _panic:
				# Still running.
				_panic = false
				state = State.FLEE
				time_left = maxf(_panic_left, 3.0)
		return
	var p := global_position + to / left * step
	# Down off the kerb and up the other: on the road, at the height of the
	# line across where nothing is found.
	var whole := Vector2(goal.x - _leg_from.x, goal.z - _leg_from.z).length()
	var t := 1.0 - (left - step) / maxf(whole, 0.01)
	p.y = _ground_below(p, lerpf(_leg_from.y, goal.y, clampf(t, 0.0, 1.0)))
	global_position = p


# --- fighting -------------------------------------------------------------------

## Hit by `by` (from `from`, world) for `damage`; `kind` is "punch" or "shot".
## Out of health they go down, thrown away from the hit; otherwise they reel,
## then fight back (some, when punched) or run.
func take_hit(damage: float, from: Vector3, by: Node3D, kind: String) -> void:
	if state == State.DEAD:
		return
	health -= damage
	var away := global_position - from
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else -global_basis.z
	if health <= 0.0:
		if _hands:
			_hands.weight = 0.0
		_townsfolk.forget(self)
		die(away * (7.0 if kind == "shot" else 4.0))
		return
	# The reaction from its start (again, if hit again while reeling).
	if _anim.has_animation("hit"):
		_anim.speed_scale = 1.0
		_anim.play("hit", 0.05)
		_anim.seek(0.0, true)
		_reel_left = minf(REEL_TIME, _anim.get_animation("hit").length)
	else:
		_hit_lean = 1.0
		_reel_left = LEAN_TIME
	_knock = away * (KNOCK_SHOT if kind == "shot" else KNOCK_PUNCH)
	if _punch_t >= 0.0:
		# A punch of theirs is cut short.
		_punch_t = -1.0
		_punch_wait = 0.3
		if _hands:
			_hands.weight = 0.0
	if state == State.FIGHT:
		return
	if kind == "punch" and by != null and randf() < BRAVE:
		fight(by)
	else:
		flee(from)


func _reel(delta: float) -> void:
	_reel_left -= delta
	if _knock.length() > 0.01:
		var p := global_position + _knock * delta
		p.y = _ground_below(p, global_position.y)
		global_position = p
		_knock = _knock.move_toward(Vector3.ZERO, 5.0 * delta)
	if _hit_lean > 0.0:
		_hit_lean = maxf(_hit_lean - delta * 2.5, 0.0)
		_model.rotation.x = -sin(_hit_lean * PI) * 0.35
	if _reel_left <= 0.0:
		_knock = Vector3.ZERO
		# Back on their sidewalk where the hit pushed them (unless fighting, off it anyway).
		if state in [State.FLEE, State.WALK, State.STAND, State.TALK]:
			_back_on_path()


## Off along their sidewalk, away from `from` (world), as fast as they can.
func flee(from: Vector3) -> void:
	if state in [State.DEAD, State.FIGHT]:
		return
	# The one they were talking to runs too; each lets go of the other first,
	# or they would keep telling each other to run.
	var other := partner
	partner = null
	if other and is_instance_valid(other) and other.state == State.TALK:
		other.partner = null
		other.flee(from)
	_threat = from
	if state == State.CROSS and _panic:
		return # already running over to the next sidewalk
	_panic = false
	if state == State.CROSS or path < 0:
		_back_on_path()
	var ahead: Vector3 = _townsfolk.point_on(path, along)["forward"]
	direction = 1.0 if ahead.dot(global_position - from) >= 0.0 else -1.0
	state = State.FLEE
	time_left = randf_range(FLEE_TIME.x, FLEE_TIME.y)
	_set_phone(false)


## A gunshot (or a fight) near them: they run.
func alarm(from: Vector3) -> void:
	if state in [State.WALK, State.STAND, State.TALK, State.CROSS]:
		flee(from)


## Whether they are running from something (on their sidewalk or over to the next).
func fleeing() -> bool:
	return state == State.FLEE or (state == State.CROSS and _panic)


## Runs at `who` and punches them till one of them is down or too far.
func fight(who: Node3D) -> void:
	if state == State.DEAD:
		return
	partner = null
	foe = who
	state = State.FIGHT
	time_left = FIGHT_TIME
	_punch_wait = 0.4
	_set_phone(false)


func _flee(delta: float) -> void:
	time_left -= delta
	var length: float = _townsfolk.path_length(path)
	var pace := RUN_SPEED
	if _anim.has_animation("run"):
		_play("run", 0.2)
		_anim.speed_scale = pace / RUN_ANIM_SPEED
	else:
		_play("walk", 0.2)
		_anim.speed_scale = minf(pace / _walk_anim_speed, 2.6)
	along += direction * pace * delta
	if along <= 0.0 or along >= length:
		along = clampf(along, 0.0, length)
		# Run on to the next sidewalk if there is one; otherwise cower here.
		_panic_left = time_left
		if _try_cross(_townsfolk.links_at_end(path, along)):
			_panic = true
		else:
			_anim.speed_scale = 1.0
			stand(randf_range(6.0, 12.0), "cower" if _anim.has_animation("cower") else "look")
		return
	_place(false)
	if time_left <= 0.0:
		_anim.speed_scale = 1.0
		walk(path, along, direction)


func _fight(delta: float) -> void:
	time_left -= delta
	var gone := foe == null or not is_instance_valid(foe) or not foe.is_visible_in_tree()
	var foe_health: Node = null if gone else foe.get_node_or_null("Health")
	if gone or (foe_health and foe_health.is_dead()) or time_left <= 0.0 \
			or _flat(foe.global_position) > FIGHT_LOST:
		_calm()
		return
	var to := foe.global_position - global_position
	to.y = 0.0
	if to.length() > 0.05:
		_yaw = atan2(to.x, to.z)
	if _punch_t >= 0.0:
		_throw_punch(delta)
		return
	_punch_wait -= delta
	if to.length() > PUNCH_REACH:
		# Run at them.
		var step := minf(CHARGE_SPEED * delta, to.length() - PUNCH_REACH * 0.8)
		var p := global_position + to.normalized() * step
		p.y = _ground_below(p, global_position.y)
		global_position = p
		if _anim.has_animation("run"):
			_play("run", 0.2)
			_anim.speed_scale = CHARGE_SPEED / RUN_ANIM_SPEED
		else:
			_play("walk", 0.2)
			_anim.speed_scale = minf(CHARGE_SPEED / _walk_anim_speed, 2.4)
		return
	_anim.speed_scale = 1.0
	if _punch_wait <= 0.0:
		_punch_t = 0.0
		_punch_landed = false
		if _anim.has_animation("punch"):
			_anim.play("punch", 0.08)
	else:
		_play("idle", 0.2)


## Their punch: the "punch" animation, or their right arm thrown out at the
## foe's chest and back; it lands PUNCH_LANDS in, if they are still in reach.
func _throw_punch(delta: float) -> void:
	_punch_t += delta
	var t := _punch_t
	if not _anim.has_animation("punch"):
		var hands := _arm()
		if hands:
			hands.goal = foe.global_position + Vector3.UP * 1.35
			var w := smoothstep(0.0, PUNCH_LANDS, t) - smoothstep(PUNCH_LANDS + 0.05, PUNCH_TIME, t)
			hands.weight = clampf(w, 0.0, 1.0)
	if not _punch_landed and t >= PUNCH_LANDS:
		_punch_landed = true
		if _flat(foe.global_position) <= PUNCH_REACH + 0.35:
			var hp: Node = foe.get_node_or_null("Health")
			if hp:
				hp.hurt(PUNCH_DAMAGE, global_position)
			Sfx.play(self, Sfx.punch(), global_position + Vector3.UP * 1.3, -4.0)
	if t >= PUNCH_TIME:
		_punch_t = -1.0
		_punch_wait = PUNCH_EVERY * randf_range(0.8, 1.3)
		if _hands:
			_hands.weight = 0.0


## The fight is over: back to the nearest sidewalk, walking.
func _calm() -> void:
	foe = null
	_punch_t = -1.0
	if _hands:
		_hands.weight = 0.0
	_anim.speed_scale = 1.0
	_back_on_path()
	walk(path, along, direction)


## On to the sidewalk nearest where they are now (after a fight or mid-crossing).
func _back_on_path() -> void:
	var near: Dictionary = _townsfolk.nearest_point(global_position)
	if near.is_empty():
		return
	path = near["path"]
	along = near["at"]


func _arm() -> SkeletonModifier3D:
	if _hands:
		return _hands
	var skeleton := _model.get_node_or_null("Skeleton3D") as Skeleton3D
	if skeleton == null:
		return null
	_hands = preload("res://world/cashier_hands.gd").new()
	_hands.name = "PunchArm"
	skeleton.add_child(_hands)
	return _hands


func _flat(at: Vector3) -> float:
	return Vector2(at.x - global_position.x, at.z - global_position.z).length()


func _talk(delta: float) -> void:
	_anim.speed_scale = 1.0
	# The other one gone, down, or off running or fighting: the talk is over.
	if partner == null or not is_instance_valid(partner) or partner.state != State.TALK:
		partner = null
		walk(path, along, direction)
		return
	var to: Vector3 = partner.global_position - global_position
	if Vector2(to.x, to.z).length() > 0.05:
		_yaw = atan2(to.x, to.z)
	time_left -= delta
	_turn_left -= delta
	if _turn_left <= 0.0:
		_speaking = not _speaking
		_turn_left = randf_range(2.0, 3.8) if _speaking else randf_range(1.8, 3.2)
		_play("talk" if _speaking else "listen")
	if time_left <= 0.0:
		talk_cooldown = 60.0
		partner = null
		walk(path, along, direction if randf() < 0.5 else -direction)


## Puts them on their sidewalk at `along`, keeping to the right of the way they walk.
func _place(snap: bool) -> void:
	var where: Dictionary = _townsfolk.point_on(path, along)
	var forward: Vector3 = where["forward"] * direction
	var right := forward.cross(Vector3.UP).normalized()
	var lane: float = where["width"] * 0.22
	global_position = where["position"] + right * lane
	_yaw = atan2(forward.x, forward.z)
	if snap:
		rotation.y = _yaw
