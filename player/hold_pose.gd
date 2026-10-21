extends SkeletonModifier3D
## While you carry something (player.gd's `held`), bends the character's right
## elbow so the forearm points forward, as you hold a drink, over whatever
## animation plays, then stands `item` upright in his palm. Runs after the
## AnimationPlayer each frame, so the item keeps to the hand.
##
## sip() takes the cup in his hand up to his mouth from in front, his arm
## bending to put it there and his hand on the outside of the cup
## (player/arm_reach.gd), a drink, and down. A cup with its lid shut (its "Lid"
## node, props/duet.glb) is opened first, with the opening cut from Mixamo's
## "Sitting Drinking" (player/drink_clips.res, made by
## tools/build_drink_clips.gd): he holds it in front of him and his left hand
## goes to its top as it goes to the top of the drink there, opening the lid,
## which flips back on its hinge and stays open.

const ArmReach := preload("res://player/arm_reach.gd")

## Emitted when a sip is over and the cup back down.
signal sipped
## Emitted when he has opened the cup's lid.
signal lid_opened

const CLIPS_PATH := "res://player/drink_clips.res"

## The carried item; null turns the pose off.
var item: Node3D
## Where the forearm points, in the character's space (+Z his front, -X his right).
var forearm_dir := Vector3(0.12, -0.3, 1.0).normalized()

## How fast the opening plays against the original.
const OPEN_RATE := 1.1
## A sip: up to his lips, a drink, back down (seconds each).
const SIP_UP := 0.8
const SIP_HOLD := 1.2
const SIP_DOWN := 0.8
## Seconds (of a clip) to blend it in at its start and out at its end.
const BLEND := 0.5
## The cup model's height and radius at scale 1 (props/duet.glb).
const CUP_HEIGHT := 0.204
const CUP_RADIUS := 0.075
## The lid's hinge along the back of its rim (cup model space, about +X), how
## far it turns open (degrees; past upright, it hangs down the back of the
## cup), and when in "open" it flips (shares of the clip).
const LID_HINGE := Vector3(0.0, 0.2035, -0.0775)
const LID_OPEN := 250.0
const LID_FLIP := Vector2(0.55, 0.85)

var _upper := -1
var _fore := -1
var _hand := -1
var _knuckle := -1
var _head := -1
var _arm := PackedInt32Array()
var _left_arm := PackedInt32Array()
var _clips: AnimationLibrary
## Per clip: [[bone, track], ...] of the bones it turns.
var _tracks := {}
## The clip playing ("open" or "sip", "" for none) and how far into it (its
## own seconds); whether a sip follows the opening, and whether this sip came
## straight from an opening (no blending between them).
var _clip := ""
var _t := 0.0
var _sip_after := false
var _from_open := false


func _ready() -> void:
	var skeleton := get_skeleton()
	for b in skeleton.get_bone_count():
		var n := skeleton.get_bone_name(b)
		if n.ends_with("_RightArm"):
			_upper = b
		elif n.ends_with("_RightForeArm"):
			_fore = b
		elif n.ends_with("_RightHand"):
			_hand = b
		elif n.ends_with("_RightHandMiddle1"):
			_knuckle = b
		elif n.ends_with("_Head"):
			_head = b
	_arm = ArmReach.arm_bones(skeleton, "Right")
	_left_arm = ArmReach.arm_bones(skeleton, "Left")
	if ResourceLoader.exists(CLIPS_PATH):
		_clips = load(CLIPS_PATH) as AnimationLibrary
	if _clips == null or _arm.is_empty() or _left_arm.is_empty() or _head < 0:
		_clips = null
		push_warning("%s is missing: run tools/build_drink_clips.gd; he cannot drink" % CLIPS_PATH)
		return
	for clip_name: StringName in _clips.get_animation_list():
		var anim := _clips.get_animation(clip_name)
		var pairs := []
		for t in anim.get_track_count():
			var b := skeleton.find_bone(str(anim.track_get_path(t).get_concatenated_subnames()))
			if b >= 0:
				pairs.append([b, t])
		_tracks[str(clip_name)] = pairs


## Starts a sip (opening the cup first if its lid is shut); false if he is busy
## with the cup already or there is nothing to drink.
func sip() -> bool:
	if item == null or is_sipping() or _clips == null:
		return false
	if is_sealed():
		return open_lid(true)
	_play("sip")
	return true


## Opens the lid of the cup in his hand (lid_opened when done), then takes a
## sip with `then_sip`. False if it is open already or he is busy with the cup.
func open_lid(then_sip := false) -> bool:
	if not is_sealed() or is_sipping() or _clips == null:
		return false
	_sip_after = then_sip
	_play("open")
	return true


## Whether the cup in his hand still has its lid shut.
func is_sealed() -> bool:
	var lid := _lid()
	return lid != null and not lid.get_meta("open", false)


func is_sipping() -> bool:
	return _clip != ""


func _lid() -> Node3D:
	return item.find_child("Lid", true, false) as Node3D if item else null


func _play(clip_name: String) -> void:
	_clip = clip_name
	_t = 0.0


func _process_modification_with_delta(delta: float) -> void:
	if item == null or _fore < 0 or _hand < 0:
		_clip = ""
		_sip_after = false
		_from_open = false
		return
	var skeleton := get_skeleton()
	# Turn the forearm (in the skeleton's space) from where the animation has
	# it to forearm_dir, keeping its twist; the hand follows.
	var parent := skeleton.get_bone_global_pose(_upper) if _upper >= 0 else Transform3D.IDENTITY
	var fore := skeleton.get_bone_global_pose(_fore)
	var to := (skeleton.transform.basis.inverse() * forearm_dir).normalized()
	var turn := Quaternion(fore.basis.y.normalized(), to)
	var bent := Basis(turn) * fore.basis
	var local := (parent.basis.inverse() * bent).get_rotation_quaternion()
	skeleton.set_bone_pose_rotation(_fore, local)

	# The item's size against its model (game/inventory.gd), for a cup 0.2 m tall, 0.15 m across.
	var s: float = item.get_meta("item_scale", 1.0)
	var owner_body := skeleton.get_parent().get_parent() as Node3D
	# The cup's front (+Z, the lid's tab) towards him, so its lid opens away from him.
	var facing := Basis(Vector3.UP, owner_body.rotation.y + PI) if owner_body else Basis.IDENTITY
	# The palm: between the wrist and the knuckles, its face along the hand's +Z.
	var hand := skeleton.global_transform * skeleton.get_bone_global_pose(_hand)
	var knuckle := skeleton.global_transform * skeleton.get_bone_global_pose(_knuckle) if _knuckle >= 0 else hand
	var palm := hand.origin.lerp(knuckle.origin, 0.6)
	var centre := palm + hand.basis.z.normalized() * 0.065 * s
	var held := Transform3D(facing.scaled(Vector3.ONE * s), centre - Vector3.UP * 0.11 * s)
	if _clip == "":
		item.global_transform = held
		return

	if _clip == "sip":
		# Up to his lips from in front, his hand on the outside of the cup
		# (player/arm_reach.gd), a drink, and down.
		_t += delta
		var w := smoothstep(0.0, SIP_UP, _t)
		if _t > SIP_UP + SIP_HOLD:
			w = 1.0 - smoothstep(SIP_UP + SIP_HOLD, SIP_UP + SIP_HOLD + SIP_DOWN, _t)
		var head := skeleton.global_transform * skeleton.get_bone_global_pose(_head)
		var outward := -(owner_body.global_basis.x.normalized() if owner_body else Vector3.RIGHT) + Vector3.DOWN * 0.3
		var at_lips := ArmReach.cup_at_lips_held(head, s, held, palm, outward)
		item.global_transform = ArmReach.carry(skeleton, _arm, held, held.interpolate_with(at_lips, w))
		if _t >= SIP_UP + SIP_HOLD + SIP_DOWN:
			_finish()
		return

	# The opening: his fingers turn as in the clip, his left hand goes where it went.
	var anim := _clips.get_animation(_clip)
	_t += delta * OPEN_RATE
	var at := minf(_t, anim.length)
	var w_in := smoothstep(0.0, BLEND, at)
	var w_out := 1.0 if _sip_after else 1.0 - smoothstep(anim.length - BLEND, anim.length, at)
	var w := minf(w_in, w_out)
	for pair: Array in _tracks[_clip]:
		# His right fingers stay as they hold the cup.
		if skeleton.get_bone_name(pair[0]).contains("RightHand"):
			continue
		var q := anim.rotation_track_interpolate(pair[1], at)
		skeleton.set_bone_pose_rotation(pair[0], skeleton.get_bone_pose_rotation(pair[0]).slerp(q, w))
	# The cup stays in his right hand; his left goes to its top, facing his way.
	item.global_transform = held
	var top := Transform3D(Basis.IDENTITY, skeleton.global_transform.affine_inverse() * (held * Vector3(0.0, CUP_HEIGHT, 0.0)))
	_place_hand(skeleton, _left_arm, top * _frame(anim, "left_in_cup", at), w)
	var lid := _lid()
	if lid:
		var f := clampf((at / anim.length - LID_FLIP.x) / (LID_FLIP.y - LID_FLIP.x), 0.0, 1.0)
		lid.transform = _lid_xf(LID_OPEN * f * f)
	if _t >= anim.length:
		_finish()


func _finish() -> void:
	if _clip == "open":
		var lid := _lid()
		if lid:
			lid.transform = _lid_xf(LID_OPEN)
			lid.set_meta("open", true)
		# Done with the cup before saying so: what comes next (a smoke break) may start now.
		if _sip_after:
			_sip_after = false
			_from_open = true
			_play("sip")
		else:
			_clip = ""
		lid_opened.emit()
		return
	_clip = ""
	_from_open = false
	sipped.emit()


## The clip's hand placement (a list in its metadata `key`, RATE a second) `at` seconds in.
static func _frame(anim: Animation, key: String, at: float) -> Transform3D:
	var frames: Array = anim.get_meta(key, [])
	if frames.is_empty():
		return Transform3D.IDENTITY
	var f := clampf(at * 30.0, 0.0, frames.size() - 1.0)
	var k := mini(floori(f), frames.size() - 2)
	if k < 0:
		return frames[0]
	return (frames[k] as Transform3D).interpolate_with(frames[k + 1], f - k)


## Bends the arm `bones` so its hand goes to `goal` (skeleton space), by `w`
## from where it is, and turns the hand as `goal` is turned.
static func _place_hand(skeleton: Skeleton3D, bones: PackedInt32Array, goal: Transform3D, w: float) -> void:
	if w <= 0.0:
		return
	var now := skeleton.get_bone_global_pose(bones[2])
	ArmReach.reach(skeleton, bones, now.origin.lerp(goal.origin, w))
	var reached := skeleton.get_bone_global_pose(bones[2])
	var turn := now.basis.get_rotation_quaternion().slerp(goal.basis.get_rotation_quaternion(), w)
	skeleton.set_bone_global_pose(bones[2], Transform3D(Basis(turn), reached.origin))


## The lid turned `degrees` open on its hinge (in the cup's space).
static func _lid_xf(degrees: float) -> Transform3D:
	var turn := Basis(Vector3.RIGHT, -deg_to_rad(degrees))
	return Transform3D(turn, LID_HINGE - turn * LID_HINGE)
