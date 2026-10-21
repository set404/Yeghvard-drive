extends SkeletonModifier3D
## On a smoke break (player.gd), puts the cup in the character's left hand and
## the cigarette in his right each frame, after the animation has moved them.
##
## Mixamo's drinking brings the hand to the side of the face, as for a small
## glass, which would leave a cup in the palm at his cheek. So as the hand comes
## up, his arm reaches on until the cup is at his lips, tipped towards him
## (player/arm_reach.gd), the cup staying in his hand all the while.
##
## With no cup (smoking only) his left arm hangs as it does standing idle,
## instead of drinking from an empty hand.

const ArmReach := preload("res://player/arm_reach.gd")

## The cup (its origin at the middle of its bottom, up its +Y) and how big it is
## against the model (the item's "scale" in game/inventory.gd).
var cup: Node3D
var cup_scale := 1.0
var cigarette: Node3D
## Smoking with nothing to drink: his left arm rests (the idle animation's pose).
var rest_left := false
## The animation his resting left arm takes its pose from.
var rest_animation: Animation

## The arm starts for his lips with his palm this far from them, and is there at
## SIP_NEAR (metres, at the character's own size).
const SIP_FAR := 0.32
const SIP_NEAR := 0.17
## How fast his left arm goes to rest and back (per second).
const REST_RATE := 2.5

var _palm := Transform3D.IDENTITY
var _cigarette_xf := Transform3D.IDENTITY
var _left_arm := PackedInt32Array()
var _right_arm := PackedInt32Array()
var _right := -1
var _head := -1
## Left arm and hand bones -> their rotation track in rest_animation.
var _rest_tracks := {}
var _rest := 0.0
## Handing the cup from his right hand to his left as the break starts: where
## it was, and how far over it is (0..1).
var _handoff_from := Transform3D.IDENTITY
var _handoff := 1.0
## Seconds the hand-over takes.
const HANDOFF_TIME := 0.2
## "Left"/"Right" -> {"" (the hand), "Middle1", ...: bone index}.
var _fingers := {}
## As his hand comes up to smoke, within this of his lips (metres) his arm
## takes the cigarette's filter the rest of the way onto them.
const PUFF_REACH := 0.16


func _ready() -> void:
	var skeleton := get_skeleton()
	var model := skeleton.get_parent()
	_palm = model.get_meta("left_palm_in_hand", Transform3D.IDENTITY)
	_cigarette_xf = model.get_meta("cigarette_in_right_hand", Transform3D.IDENTITY)
	for side: String in ["Left", "Right"]:
		var bones := {}
		for part: String in ["", "Middle1", "Middle3", "Index1", "Index2", "Middle2", "Pinky1"]:
			bones[part] = ArmReach.find_bone(skeleton, "_%sHand%s" % [side, part])
		_fingers[side] = bones
	_left_arm = ArmReach.arm_bones(skeleton, "Left")
	_right_arm = ArmReach.arm_bones(skeleton, "Right")
	_right = ArmReach.find_bone(skeleton, "_RightHand")
	_head = ArmReach.find_bone(skeleton, "_Head")


## The cup comes over from where it is now (in his other hand) rather than jumping.
func hand_over(from: Transform3D) -> void:
	_handoff_from = from
	_handoff = 0.0


func _process_modification_with_delta(delta: float) -> void:
	var skeleton := get_skeleton()
	_handoff = move_toward(_handoff, 1.0, delta / HANDOFF_TIME)
	_rest = move_toward(_rest, 1.0 if rest_left and cup == null else 0.0, REST_RATE * delta)
	if _rest > 0.0:
		_rest_left_arm(skeleton)
	var head := skeleton.global_transform * skeleton.get_bone_global_pose(_head) if _head >= 0 else Transform3D.IDENTITY
	var lips := head * Vector3(0.0, 0.06, 0.1)
	if cigarette and _right >= 0:
		var cig := _cigarette_in_fingers(skeleton)
		if _head >= 0 and not _right_arm.is_empty():
			# A puff: his hand the rest of the way, the filter on his lips.
			var near := 1.0 - smoothstep(0.03, PUFF_REACH, cig.origin.distance_to(lips))
			if near > 0.0:
				# Only his arm moves: his hand keeps its turn against his forearm.
				var hand_now := skeleton.get_bone_global_pose(_right_arm[2])
				var shift := skeleton.global_basis.inverse() * (lips - cig.origin) * near
				ArmReach.reach(skeleton, _right_arm, hand_now.origin + shift)
				cig = _cigarette_in_fingers(skeleton)
		cigarette.global_transform = cig
	if cup == null or _left_arm.is_empty():
		return
	var size := skeleton.global_basis.get_scale().x
	var hand := _hand(skeleton, "Left")
	var h := ArmReach.CUP_HEIGHT * cup_scale
	var r := ArmReach.CUP_RADIUS * cup_scale
	# In his grip: upright along his knuckles (pinky at the bottom, index at the
	# top), its side against his palm, his hand round its middle; its front
	# (+Z, the lid's tab) away from his palm.
	var up: Vector3 = hand["across"]
	var front: Vector3 = -hand["out"]
	front = (front - up * front.dot(up)).normalized()
	var x := up.cross(front).normalized()
	var middle: Vector3 = hand["palm"] + hand["out"] * r
	var in_hand := Transform3D(Basis(x, up, x.cross(up)).scaled_local(Vector3.ONE * cup_scale), middle - up * h * 0.5)
	var palm := Transform3D(Basis.IDENTITY, hand["palm"])
	if _head < 0:
		_place_cup(in_hand)
		return
	var w := 1.0 - smoothstep(SIP_NEAR * size, SIP_FAR * size, palm.origin.distance_to(lips))
	if w <= 0.0:
		_place_cup(in_hand)
		return
	# His arm takes it to his lips, his hand turning with it on the outside of
	# the cup (to his left), thumb up, as one holds a cup to drink.
	var body := skeleton.get_parent().get_parent() as Node3D
	var outward := (body.global_basis.x.normalized() if body else Vector3.LEFT) + Vector3.DOWN * 0.3
	var at_lips := ArmReach.cup_at_lips_held(head, cup_scale, in_hand, hand["palm"], outward)
	_place_cup(ArmReach.carry(skeleton, _left_arm, in_hand, in_hand.interpolate_with(at_lips, w)))


## Turns his left arm, hand and fingers towards their pose in rest_animation, by _rest.
func _rest_left_arm(skeleton: Skeleton3D) -> void:
	if rest_animation == null:
		return
	if _rest_tracks.is_empty():
		for t in rest_animation.get_track_count():
			if rest_animation.track_get_type(t) != Animation.TYPE_ROTATION_3D:
				continue
			var bone_name := str(rest_animation.track_get_path(t).get_concatenated_subnames())
			if bone_name.contains("_Left") and not bone_name.contains("Leg") and not bone_name.contains("Foot") \
					and not bone_name.contains("Toe"):
				var b := skeleton.find_bone(bone_name)
				if b >= 0:
					_rest_tracks[b] = t
	for b: int in _rest_tracks:
		var q := rest_animation.rotation_track_interpolate(_rest_tracks[b], 0.0)
		skeleton.set_bone_pose_rotation(b, skeleton.get_bone_pose_rotation(b).slerp(q, _rest))


## His `side` hand in the world: "palm" (its middle), "out" (out of the palm, the
## way his fingers close), "across" (from his little finger to his index), and
## "along" (from his wrist to his knuckles).
func _hand(skeleton: Skeleton3D, side: String) -> Dictionary:
	var bones: Dictionary = _fingers[side]
	var at := func(part: String) -> Vector3:
		return skeleton.global_transform * skeleton.get_bone_global_pose(bones[part]).origin
	var wrist: Vector3 = at.call("")
	var knuckle: Vector3 = at.call("Middle1")
	var across: Vector3 = (at.call("Index1") - at.call("Pinky1")).normalized()
	var along := (knuckle - wrist).normalized()
	var palm := wrist.lerp(knuckle, 0.55)
	var out := along.cross(across).normalized()
	if out.dot(at.call("Middle3") - palm) < 0.0:
		out = -out
	return {"palm": palm, "out": out, "across": across, "along": along, "wrist": wrist}


## The cigarette between his right index and middle fingers, at their middle
## joints, across them: its filter end (its origin; it runs along its +Y) out on
## the side of his palm, towards his lips as he smokes.
func _cigarette_in_fingers(skeleton: Skeleton3D) -> Transform3D:
	var bones: Dictionary = _fingers["Right"]
	if bones.values().has(-1):
		var xf := skeleton.global_transform * skeleton.get_bone_global_pose(_right) * _cigarette_xf
		return Transform3D(xf.basis.orthonormalized(), xf.origin)
	var hand := _hand(skeleton, "Right")
	var grip := (skeleton.global_transform * skeleton.get_bone_global_pose(bones["Index2"]).origin
		+ skeleton.global_transform * skeleton.get_bone_global_pose(bones["Middle2"]).origin) * 0.5
	var out: Vector3 = hand["out"]
	# Filter 2.5 cm out on the palm side, the lit end out past the back of his fingers.
	var filter := grip + out * 0.025
	var tip_dir := -out
	var side: Vector3 = hand["along"].cross(tip_dir)
	if side.length() < 0.01:
		side = tip_dir.cross(Vector3.UP)
	side = side.normalized()
	return Transform3D(Basis(side, tip_dir, side.cross(tip_dir)), filter)


func _place_cup(xf: Transform3D) -> void:
	if _handoff < 1.0:
		xf = _handoff_from.interpolate_with(xf, smoothstep(0.0, 1.0, _handoff))
	cup.global_transform = xf
