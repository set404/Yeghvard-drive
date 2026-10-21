extends SkeletonModifier3D
## The cashier's right arm as she serves (world/cashier.gd sets `goal` and
## `weight`): it reaches for `goal` (world) over whatever animation plays
## (player/arm_reach.gd), and `pack`, while shown, sits in her hand.

const ArmReach := preload("res://player/arm_reach.gd")

## Where her hand goes (world), and how far it goes there from the animation (0..1).
var goal := Vector3.ZERO
var weight := 0.0
## The pack she holds (shown while she has one).
var pack: Node3D

var _arm := PackedInt32Array()
var _knuckle := -1
var _index := -1
var _pinky := -1


func _ready() -> void:
	var skeleton := get_skeleton()
	_arm = ArmReach.arm_bones(skeleton, "Right")
	_knuckle = ArmReach.find_bone(skeleton, "_RightHandMiddle1")
	_index = ArmReach.find_bone(skeleton, "_RightHandIndex1")
	_pinky = ArmReach.find_bone(skeleton, "_RightHandPinky1")


func _process_modification_with_delta(_delta: float) -> void:
	if _arm.is_empty():
		return
	var skeleton := get_skeleton()
	if weight > 0.0:
		var hand := skeleton.get_bone_global_pose(_arm[2]).origin
		var target := skeleton.global_transform.affine_inverse() * goal
		ArmReach.reach(skeleton, _arm, hand.lerp(target, weight))
	if pack and pack.visible and not [_knuckle, _index, _pinky].has(-1):
		# Held in her fingers against her palm: across her palm, its front out
		# of it, sticking out past her fingers' side.
		var at := func(b: int) -> Vector3:
			return skeleton.global_transform * skeleton.get_bone_global_pose(b).origin
		var wrist: Vector3 = at.call(_arm[2])
		var knuckle: Vector3 = at.call(_knuckle)
		var along := (knuckle - wrist).normalized()
		var across: Vector3 = (at.call(_index) - at.call(_pinky)).normalized()
		# Out of the palm of a right hand: from the little finger to the index,
		# then round towards the fingers (her fingers are straight in the idle).
		var out := across.cross(along).normalized()
		var palm := wrist.lerp(knuckle, 0.75)
		var up := across # the pack's height along her knuckles, from little finger to index
		var front := (out - up * out.dot(up)).normalized()
		var x := up.cross(front).normalized()
		pack.global_transform = Transform3D(Basis(x, up, front), palm + out * 0.03 - up * 0.04)
