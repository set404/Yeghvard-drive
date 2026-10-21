extends Node3D
## The cashier at the till by the main doors (tools/build_supermarket.gd puts
## this behind it, its +Z towards the customers' side, the cigarette rack
## behind her). She is one of the townspeople (npc/Ch22.scn) standing idle.
## Like the Duet shelves (world/duet_stand.gd), she is in the "shop_stands"
## group: in front of her counter, E buys a pack of cigarettes (main.gd pays
## `price` and puts `amount` cigarettes in your inventory) and she hands it
## over: she turns round to the rack, takes a pack, turns back and holds it
## out to you across the counter.

const FIGURE := "res://npc/Ch22.scn"
const Hands := preload("res://world/cashier_hands.gd")
const Cigarette := preload("res://props/cigarette.gd")

## What she sells, as game/inventory.gd knows it, how many cigarettes a pack
## holds, what it costs in drams, and how the on-screen hints put it.
@export var item_id := "cigarette"
@export var amount := 20
@export var price := 1200.0
@export var item_name := "pack of Ararat cigarettes"
@export var verb := "buy"
## Where you stand to buy (her space, metres: across the counter from her)
## and how far from there she serves you.
@export var customer_spot := Vector3(0.0, 0.0, 1.45)
@export var reach := 0.9
## Where she takes a pack from the rack behind her, and where she holds it out
## across the counter (her space).
@export var rack_point := Vector3(0.05, 1.3, -0.48)
@export var hand_over_point := Vector3(-0.08, 1.12, 0.52)

## The serving, in seconds from its start: turned round to the rack by TURN,
## hand at the rack at TAKE (the pack in it), turned back by TURN_BACK, the pack
## held out at GIVE, let go of at GONE, done at DONE.
const TURN := 0.6
const TAKE := 1.2
const LEAVE_RACK := 1.6
const TURN_BACK := 2.2
const GIVE := 2.8
const GONE := 3.1
const DONE := 3.6

var _figure: Node3D
var _anim: AnimationPlayer
var _hands: SkeletonModifier3D
var _pack: Node3D
## Seconds into serving, or -1.
var _serving := -1.0


func _ready() -> void:
	add_to_group("shop_stands")
	if not ResourceLoader.exists(FIGURE):
		push_warning("%s is missing: no cashier" % FIGURE)
		return
	_figure = (load(FIGURE) as PackedScene).instantiate()
	_figure.name = "Figure"
	add_child(_figure)
	_anim = _figure.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	if _anim.has_animation("idle"):
		_anim.get_animation("idle").loop_mode = Animation.LOOP_LINEAR
		_anim.play("idle")
	var skeleton := _figure.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	_hands = Hands.new()
	_hands.name = "Hands"
	skeleton.add_child(_hands)
	_pack = Cigarette.make_pack()
	_pack.top_level = true
	_pack.visible = false
	add_child(_pack)
	_hands.pack = _pack


## How far the walker is from where you stand to buy, or INF when not at her counter.
func shopper_distance(who: Node3D) -> float:
	var p := to_local(who.global_position)
	if absf(p.y) > 1.0 or p.z < customer_spot.z - 0.5 or p.z > customer_spot.z + 0.9 or absf(p.x - customer_spot.x) > 1.2:
		return INF
	return Vector2(p.x - customer_spot.x, p.z - customer_spot.z).length()


func in_reach(who: Node3D) -> bool:
	return shopper_distance(who) < reach


func sold_out() -> bool:
	return false


## Starts handing you a pack; false while she is still serving.
func take(_near: Vector3) -> bool:
	if _figure == null or _serving >= 0.0:
		return false
	_serving = 0.0
	return true


func _process(delta: float) -> void:
	if _serving < 0.0 or _figure == null:
		return
	_serving += delta
	var t := _serving
	# Turning round to the rack and back (the figure faces its +Z).
	var turn := smoothstep(0.0, TURN, t) - smoothstep(LEAVE_RACK, TURN_BACK, t)
	_figure.rotation.y = PI * turn
	# Her right hand: to the rack, then out across the counter.
	var goal := Vector3.ZERO
	var w := 0.0
	if t < LEAVE_RACK:
		goal = rack_point
		w = smoothstep(TURN * 0.6, TAKE, t) - smoothstep(TAKE + 0.1, LEAVE_RACK, t)
	else:
		goal = hand_over_point
		w = smoothstep(TURN_BACK - 0.2, GIVE, t) - smoothstep(GONE, DONE, t)
	_hands.goal = global_transform * goal
	_hands.weight = clampf(w, 0.0, 1.0)
	_pack.visible = t >= TAKE - 0.05 and t < GONE
	if _anim and _anim.has_animation("talk"):
		var talking := t >= TURN_BACK and t < DONE
		var want := "talk" if talking else "idle"
		if _anim.current_animation != want:
			_anim.play(want, 0.3)
	if t >= DONE:
		_serving = -1.0
		_figure.rotation.y = 0.0
		_hands.weight = 0.0
		_pack.visible = false
		if _anim and _anim.has_animation("idle"):
			_anim.play("idle", 0.4)
