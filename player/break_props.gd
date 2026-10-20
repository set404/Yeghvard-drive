extends SkeletonModifier3D
## On a smoke break (player.gd), puts the cup in the character's left hand and
## the cigarette in his right each frame, after the animation has moved them.
##
## Mixamo's drinking brings the hand to the side of the face, as for a small
## glass; a cup held in the palm would end up at his cheek. So as the hand comes
## up to the face the cup leaves the palm for his lips, tipped towards him, and
## goes back as the hand comes down.

## The cup (its origin at the middle of its bottom, up its +Y) and how big it is
## against the model (the item's "scale" in game/inventory.gd).
var cup: Node3D
var cup_scale := 1.0
var cigarette: Node3D

## The cup model's height and radius at scale 1 (props/duet.glb).
const CUP_HEIGHT := 0.204
const CUP_RADIUS := 0.075
## The cup starts for his lips with his palm this far from them, and is there at
## SIP_NEAR (metres, at the character's own size).
const SIP_FAR := 0.32
const SIP_NEAR := 0.17
## How far the cup tips towards him at his lips, in degrees.
const SIP_TILT := 35.0

var _palm := Transform3D.IDENTITY
var _cigarette_xf := Transform3D.IDENTITY
var _left := -1
var _right := -1
var _head := -1


func _ready() -> void:
	var skeleton := get_skeleton()
	var model := skeleton.get_parent()
	_palm = model.get_meta("left_palm_in_hand", Transform3D.IDENTITY)
	_cigarette_xf = model.get_meta("cigarette_in_right_hand", Transform3D.IDENTITY)
	for b in skeleton.get_bone_count():
		var n := skeleton.get_bone_name(b)
		if n.ends_with("_LeftHand"):
			_left = b
		elif n.ends_with("_RightHand"):
			_right = b
		elif n.ends_with("_Head"):
			_head = b


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	var size := skeleton.global_basis.get_scale().x
	if cigarette and _right >= 0:
		var xf := skeleton.global_transform * skeleton.get_bone_global_pose(_right) * _cigarette_xf
		cigarette.global_transform = Transform3D(xf.basis.orthonormalized(), xf.origin)
	if cup == null or _left < 0:
		return
	var palm := skeleton.global_transform * skeleton.get_bone_global_pose(_left) * _palm
	palm.basis = palm.basis.orthonormalized()
	var h := CUP_HEIGHT * cup_scale
	var r := CUP_RADIUS * cup_scale
	# In the palm: the cup's side against it, its middle at the palm's height.
	var in_hand := Transform3D(palm.basis.scaled_local(Vector3.ONE * cup_scale), palm * Vector3(0.0, -h * 0.5, r * 0.9))
	if _head < 0:
		cup.global_transform = in_hand
		return
	var head := skeleton.global_transform * skeleton.get_bone_global_pose(_head)
	var up := head.basis.y.normalized()
	var face := head.basis.z.normalized()
	var lips := head * Vector3(0.0, 0.06, 0.1)
	# At his lips: tipped towards him, the near side of the rim on his lower lip.
	var tilt := deg_to_rad(SIP_TILT)
	var axis := (up * cos(tilt) - face * sin(tilt)).normalized()
	var side := axis.cross(face).normalized()
	var at_lips := Basis(side, axis, side.cross(axis)).scaled_local(Vector3.ONE * cup_scale)
	var rim_middle := lips + face * r * 0.8
	var drinking := Transform3D(at_lips, rim_middle - axis * h)
	var w := 1.0 - smoothstep(SIP_NEAR * size, SIP_FAR * size, palm.origin.distance_to(lips))
	cup.global_transform = in_hand.interpolate_with(drinking, w)
