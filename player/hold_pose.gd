extends SkeletonModifier3D
## While you carry something (player.gd's `held`), bends the character's right
## elbow so the forearm points forward, as you hold a drink, over whatever
## animation plays, then stands `item` upright in his palm. Runs after the
## AnimationPlayer each frame, so the item keeps to the hand.

## The carried item; null turns the pose off.
var item: Node3D
## Where the forearm points, in the character's space (+Z his front, -X his right).
var forearm_dir := Vector3(0.12, -0.3, 1.0).normalized()

var _upper := -1
var _fore := -1
var _hand := -1
var _knuckle := -1


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


func _process_modification_with_delta(_delta: float) -> void:
	if item == null or _fore < 0 or _hand < 0:
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

	# The palm: between the wrist and the knuckles, its face along the hand's +Z.
	var hand := skeleton.global_transform * skeleton.get_bone_global_pose(_hand)
	var knuckle := skeleton.global_transform * skeleton.get_bone_global_pose(_knuckle) if _knuckle >= 0 else hand
	# The item's size against its model (game/inventory.gd), for a cup 0.2 m tall, 0.15 m across.
	var s: float = item.get_meta("item_scale", 1.0)
	var palm := hand.origin.lerp(knuckle.origin, 0.6)
	var centre := palm + hand.basis.z.normalized() * 0.065 * s
	var owner_body := skeleton.get_parent().get_parent() as Node3D
	var facing := Basis(Vector3.UP, owner_body.rotation.y) if owner_body else Basis.IDENTITY
	item.global_transform = Transform3D(facing.scaled(Vector3.ONE * s), centre - Vector3.UP * 0.11 * s)
