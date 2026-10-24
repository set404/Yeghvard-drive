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

enum State { WALK, STAND, TALK, DEAD, CROSS }

## Crossing is this much quicker than their walk.
const CROSS_HURRY := 1.2
## Seconds they wait at the kerb for the cars before giving up and turning back.
const CROSS_PATIENCE := 20.0

## Seconds a body lies where it fell before it is taken away.
const CORPSE_SECONDS := 25.0

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
		State.DEAD:
			time_left -= delta
			if time_left <= 0.0:
				queue_free()
			return
	rotation.y = lerp_angle(rotation.y, _yaw, 1.0 - exp(-6.0 * delta))


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
	if _cross_next == _kerb and not _crossing:
		if _townsfolk.traffic_on(_road_from, _road_to):
			_waited += delta
			_anim.speed_scale = 1.0
			_play("look" if _anim.has_animation("look") else "idle", 0.3)
			if _waited > CROSS_PATIENCE:
				# Too busy: back the way they came.
				walk(path, along, -direction)
			return
		_crossing = true
	if _townsfolk.blocked(self):
		_anim.speed_scale = 1.0
		_play("idle", 0.25)
		return
	# Up to the kerb at their own pace, over the road a little quicker.
	var pace := speed * (CROSS_HURRY if _crossing else 1.0)
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
		return
	var p := global_position + to / left * step
	# Down off the kerb and up the other: on the road, at the height of the
	# line across where nothing is found.
	var whole := Vector2(goal.x - _leg_from.x, goal.z - _leg_from.z).length()
	var t := 1.0 - (left - step) / maxf(whole, 0.01)
	p.y = _ground_below(p, lerpf(_leg_from.y, goal.y, clampf(t, 0.0, 1.0)))
	global_position = p


func _talk(delta: float) -> void:
	_anim.speed_scale = 1.0
	if partner == null or not is_instance_valid(partner) or partner.state == State.DEAD:
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
