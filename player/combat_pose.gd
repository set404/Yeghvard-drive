extends SkeletonModifier3D
## The arms in a fight, over whatever animation plays (player/combat.gd sets
## the goals and weights): a punch throws a hand out to `right_goal` or
## `left_goal`, aiming holds the right hand out towards the target with the left
## supporting it. Each hand reaches its goal (world) as far as its weight
## (0..1) takes it from where the animation has it (player/arm_reach.gd).
## Emits `posed` once the arms are set, for the pistol to be put in the hand.

const ArmReach := preload("res://player/arm_reach.gd")

signal posed

var right_goal := Vector3.ZERO
var right_weight := 0.0
var left_goal := Vector3.ZERO
var left_weight := 0.0

var _right := PackedInt32Array()
var _left := PackedInt32Array()
var _right_knuckle := -1


func _ready() -> void:
	var skeleton := get_skeleton()
	_right = ArmReach.arm_bones(skeleton, "Right")
	_left = ArmReach.arm_bones(skeleton, "Left")
	_right_knuckle = ArmReach.find_bone(skeleton, "_RightHandMiddle1")


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	var to_skel := skeleton.global_transform.affine_inverse()
	for arm: Array in [[_right, right_goal, right_weight], [_left, left_goal, left_weight]]:
		var bones: PackedInt32Array = arm[0]
		var weight: float = arm[2]
		if bones.is_empty() or weight <= 0.001:
			continue
		var hand := skeleton.get_bone_global_pose(bones[2]).origin
		ArmReach.reach(skeleton, bones, hand.lerp(to_skel * (arm[1] as Vector3), clampf(weight, 0.0, 1.0)))
	posed.emit()


## Where his `side` ("Right" or "Left") shoulder is (world), or null.
func shoulder(side: String) -> Variant:
	var bones := _right if side == "Right" else _left
	if bones.is_empty():
		return null
	var skeleton := get_skeleton()
	return skeleton.global_transform * skeleton.get_bone_global_pose(bones[0]).origin


## His right palm (world): between the wrist and the middle knuckle; and the way
## his forearm points. Empty without the bones.
func right_palm() -> Dictionary:
	if _right.is_empty() or _right_knuckle < 0:
		return {}
	var skeleton := get_skeleton()
	var at := func(b: int) -> Vector3: return skeleton.global_transform * skeleton.get_bone_global_pose(b).origin
	var wrist: Vector3 = at.call(_right[2])
	var elbow: Vector3 = at.call(_right[1])
	return {"palm": wrist.lerp(at.call(_right_knuckle), 0.6), "forearm": (wrist - elbow).normalized()}
