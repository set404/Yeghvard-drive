extends RefCounted
## Bends an arm of the character so his hand takes something held in it where
## it should be: player/hold_pose.gd raises the cup in his right hand to his
## lips for a sip, player/break_props.gd the one in his left on a smoke break.
## The arm is the upper arm, forearm and hand bones (a two-bone reach that keeps
## the elbow on the side the animation has it), and the held thing stays fixed
## in the hand, so the hand always comes with it.

## The cup model's height and radius at scale 1 (props/duet.glb).
const CUP_HEIGHT := 0.204
const CUP_RADIUS := 0.075
## How far the cup tips towards him at his lips, in degrees.
const SIP_TILT := 35.0


## The upper arm, forearm and hand bones of his "Left" or "Right" arm; empty
## when the skeleton has no such arm.
static func arm_bones(skeleton: Skeleton3D, side: String) -> PackedInt32Array:
	var found := PackedInt32Array([-1, -1, -1])
	for b in skeleton.get_bone_count():
		var n := skeleton.get_bone_name(b)
		if n.ends_with("_%sArm" % side):
			found[0] = b
		elif n.ends_with("_%sForeArm" % side):
			found[1] = b
		elif n.ends_with("_%sHand" % side):
			found[2] = b
	return found if not found.has(-1) else PackedInt32Array()


static func find_bone(skeleton: Skeleton3D, suffix: String) -> int:
	for b in skeleton.get_bone_count():
		if skeleton.get_bone_name(b).ends_with(suffix):
			return b
	return -1


## Where a cup (origin at the middle of its bottom, up its +Y; `s` its scale)
## is as he drinks from it: tipped towards him, the near side of its rim on his
## lower lip, its front (+Z, where the lid's tab is) towards him and so its open
## lid away from him. World space; `head` is his head bone in world space.
static func cup_at_lips(head: Transform3D, s: float) -> Transform3D:
	var up := head.basis.y.normalized()
	var face := head.basis.z.normalized()
	var lips := head * Vector3(0.0, 0.06, 0.1)
	var tilt := deg_to_rad(SIP_TILT)
	var axis := (up * cos(tilt) - face * sin(tilt)).normalized()
	var side := face.cross(axis).normalized()
	var at_lips := Basis(side, axis, side.cross(axis)).scaled_local(Vector3.ONE * s)
	var rim_middle := lips + face * CUP_RADIUS * s * 0.8
	return Transform3D(at_lips, rim_middle - axis * CUP_HEIGHT * s)


## cup_at_lips(), turned about its own axis so that the side his palm holds it
## by (`palm`, world, with the cup at `held`, world) is towards `outward`
## (world): his hand stays on the outside of the cup, thumb up, as one holds a
## cup to drink, rather than round in front of it.
static func cup_at_lips_held(head: Transform3D, s: float, held: Transform3D, palm: Vector3, outward: Vector3) -> Transform3D:
	var at := cup_at_lips(head, s)
	var axis := at.basis.y.normalized()
	var local := held.affine_inverse() * palm
	var side := at.basis * Vector3(local.x, 0.0, local.z)
	side = (side - axis * side.dot(axis)).normalized()
	var want := (outward - axis * outward.dot(axis)).normalized()
	if side.length() < 0.5 or want.length() < 0.5:
		return at
	var angle := side.signed_angle_to(want, axis)
	return Transform3D(Basis(axis, angle) * at.basis, at.origin)


## Moves the arm `bones` so that `held`, which sits at `held_now` (world) with
## the hand where the animation has it, goes to `held_goal` (world) with the
## hand fixed to it. Returns where `held` is then: `held_goal`, or as near as
## his arm reaches.
static func carry(skeleton: Skeleton3D, bones: PackedInt32Array, held_now: Transform3D, held_goal: Transform3D) -> Transform3D:
	var to_skel := skeleton.global_transform.affine_inverse()
	var hand := skeleton.get_bone_global_pose(bones[2]) # skeleton space
	# The held thing in the hand's space, and where that puts the hand.
	var in_hand := hand.affine_inverse() * (to_skel * held_now)
	var hand_goal := (to_skel * held_goal) * in_hand.affine_inverse()
	reach(skeleton, bones, hand_goal.origin)
	# Turn the hand as the held thing turns (only its rotation, not its scale).
	var now := skeleton.get_bone_global_pose(bones[2])
	var turn := hand_goal.basis.orthonormalized() * hand.basis.orthonormalized().inverse()
	skeleton.set_bone_global_pose(bones[2], Transform3D(Basis(turn.get_rotation_quaternion()) * hand.basis, now.origin))
	return skeleton.global_transform * skeleton.get_bone_global_pose(bones[2]) * in_hand


## Two-bone reach: bends the upper arm and forearm so the hand bone's origin
## comes to `target` (skeleton space), as near as the arm's length allows,
## keeping the elbow on the side it was.
static func reach(skeleton: Skeleton3D, bones: PackedInt32Array, target: Vector3) -> void:
	var shoulder := skeleton.get_bone_global_pose(bones[0]).origin
	var elbow := skeleton.get_bone_global_pose(bones[1]).origin
	var wrist := skeleton.get_bone_global_pose(bones[2]).origin
	var a := shoulder.distance_to(elbow)
	var b := elbow.distance_to(wrist)
	var to := target - shoulder
	if to.length() < 0.0001 or a < 0.0001 or b < 0.0001:
		return
	var n := to.normalized()
	var d := clampf(to.length(), absf(a - b) + 0.001, a + b - 0.001)
	# The side the elbow bends to: where it is now, across the line to the target.
	var bend := (elbow - shoulder) - n * (elbow - shoulder).dot(n)
	if bend.length() < 0.0001:
		bend = Vector3.DOWN - n * n.y
	bend = bend.normalized()
	var cos_a := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
	var new_elbow := shoulder + n * a * cos_a + bend * a * sqrt(1.0 - cos_a * cos_a)
	_turn(skeleton, bones[0], elbow - shoulder, new_elbow - shoulder)
	var fore := skeleton.get_bone_global_pose(bones[1]).origin
	var hand := skeleton.get_bone_global_pose(bones[2]).origin
	_turn(skeleton, bones[1], hand - fore, shoulder + n * d - fore)


## Turns `bone` (in skeleton space, about its own origin) so `from` points along `to`.
static func _turn(skeleton: Skeleton3D, bone: int, from: Vector3, to: Vector3) -> void:
	if from.length() < 0.0001 or to.length() < 0.0001:
		return
	var pose := skeleton.get_bone_global_pose(bone)
	var q := Quaternion(from.normalized(), to.normalized())
	skeleton.set_bone_global_pose(bone, Transform3D(Basis(q) * pose.basis, pose.origin))
