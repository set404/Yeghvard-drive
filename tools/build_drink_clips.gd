extends SceneTree
## Builds res://player/drink_clips.res: the opening and drinking cut from
## Mixamo's "Sitting Drinking" (data/models/animations/Sitting Drinking.fbx),
## for the cup in the player's right hand (player/hold_pose.gd plays them over
## whatever he is doing, standing or walking).
##
##   "open"  his left hand opens the top of what his right holds in front of him;
##   "sip"   his right hand takes it up to his mouth, he drinks and brings it down.
##
## Sitting, he leans forward with his arms out over his knees, so his arms'
## angles would not do standing. What is kept is where his hands go: in "open",
## his left hand against the top of what his right holds, where his left
## fingers work (metadata "left_in_cup", against a frame there facing his
## way, +Z ahead); in "sip", his right hand against his head ("right_in_head");
## each a Transform3D per 1/RATE s. player/hold_pose.gd bends his arms to put his hands there. The
## animations themselves only turn his fingers (and his neck and head in "sip").
##
## The library's metadata "cup_grip" says how the cup sits in his right hand,
## in the hand bone's space: origin the middle of his palm, +Y up the cup, +Z
## the cup's front (where its lid's tab is) towards his face as he drinks;
## "cup_out" the way out of his palm to the cup's middle (hand space);
## "cup_slide" how far up the cup (share of its height) his hand holds it off
## the middle, so that its rim meets his lips as he drinks.
##
## Run:  godot --headless --path . --script res://tools/build_drink_clips.gd

const AnimMerge := preload("res://tools/anim_merge.gd")

const SOURCE := "res://data/models/animations/Sitting Drinking.fbx"
const CHARACTER := "res://player/character.scn"
const OUT_PATH := "res://player/drink_clips.res"
const RATE := 30.0

## The parts kept, in the source's seconds; the bones whose turning is kept
## (without the rig's prefix; "...Hand" means that hand's fingers); and whose
## hand is placed against what.
const CLIPS := {
	"open": {"from": 5.1, "to": 7.3, "bones": ["LeftHand", "RightHand"], "hand": "Left", "against": "cup"},
	"sip": {"from": 7.3, "to": 11.7, "bones": ["RightHand", "Neck", "Head"], "hand": "Right", "against": "head"},
}
## The moment of the sip (source seconds) the cup's rim is set to meet his lips.
const AT_LIPS := 8.1
## The cup at the size it is carried (props/duet.glb at its scale in game/inventory.gd).
const CUP_HEIGHT := 0.204 * 0.75
const CUP_RADIUS := 0.075 * 0.75


func _initialize() -> void:
	var err: Error = await _build()
	quit(0 if err == OK else 1)


func _build() -> Error:
	var character: Node3D = (load(CHARACTER) as PackedScene).instantiate()
	root.add_child(character)
	var skeleton := character.get_node("Skeleton3D") as Skeleton3D
	var player := character.get_node("AnimationPlayer") as AnimationPlayer

	var doc := FBXDocument.new()
	var state := FBXState.new()
	if doc.append_from_file(ProjectSettings.globalize_path(SOURCE), state) != OK:
		push_error("Could not read " + SOURCE)
		return FAILED
	var scene := doc.generate_scene(state)
	var src_player := scene.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var source := src_player.get_animation(src_player.get_animation_list()[0]).duplicate(true) as Animation
	scene.free()
	AnimMerge.point_at(source, skeleton)
	var whole := AnimationLibrary.new()
	whole.add_animation("all", source)
	player.add_animation_library("drink_source", whole)
	player.play("drink_source/all")
	player.pause()

	var library := AnimationLibrary.new()
	# How the cup sits in his hand: at the moment he drinks, its rim at his lips.
	await _pose_at(player, skeleton, AT_LIPS)
	var hand := _pose(skeleton, "_RightHand")
	var knuckle := _pose(skeleton, "_RightHandMiddle1").origin
	var tip := _pose(skeleton, "_RightHandMiddle3").origin
	var across := _pose(skeleton, "_RightHandIndex1").origin - _pose(skeleton, "_RightHandPinky1").origin
	var head := _pose(skeleton, "_Head")
	var palm := hand.origin.lerp(knuckle, 0.55)
	var out := (knuckle - hand.origin).cross(across).normalized()
	if out.dot(tip - palm) < 0.0:
		out = -out # towards where his fingers close round the cup
	var face := head.basis.z.normalized()
	var lips := head * Vector3(0.0, 0.06, 0.1)
	var middle := palm + out * CUP_RADIUS
	var rim := lips + face * CUP_RADIUS * 0.6
	var up := (rim - middle).normalized()
	# +Z: the side of the rim at his lips, towards his face, square to the cup's axis.
	var z := (-face - up * (-face).dot(up)).normalized()
	var grip_world := Transform3D(Basis(up.cross(z), up, z), palm)
	var grip := hand.affine_inverse() * grip_world
	var slide := clampf((middle.distance_to(rim) - CUP_HEIGHT * 0.5) / CUP_HEIGHT, -0.3, 0.3)
	var cup_out := hand.basis.inverse() * out
	library.set_meta("cup_grip", grip)
	library.set_meta("cup_out", cup_out)
	library.set_meta("cup_slide", slide)

	for clip_name: String in CLIPS:
		var spec: Dictionary = CLIPS[clip_name]
		var anim := _cut(source, spec["from"], spec["to"], spec["bones"])
		var frames: Array[Transform3D] = []
		var n := ceili(anim.length * RATE)
		# For the opening: the top of what he opens, where his left thumb and
		# index fingertips are on the whole in the middle of it, as he faces then.
		var top := Transform3D.IDENTITY
		if spec["against"] == "cup":
			var sum := Vector3.ZERO
			var count := 0
			for k in range(int(n * 0.3), int(n * 0.8)):
				await _pose_at(player, skeleton, spec["from"] + k / RATE)
				sum += (_pose(skeleton, "_LeftHandThumb4").origin + _pose(skeleton, "_LeftHandIndex4").origin) * 0.5
				count += 1
			var ahead := _pose(skeleton, "_Hips").basis.z
			top = Transform3D(Basis(Vector3.UP, atan2(ahead.x, ahead.z)), sum / count)
		for k in n + 1:
			await _pose_at(player, skeleton, spec["from"] + minf(k / RATE, anim.length))
			var placed := _pose(skeleton, "_%sHand" % spec["hand"])
			var frame := _pose(skeleton, "_Head")
			if spec["against"] == "cup":
				frame = top
			frame.basis = frame.basis.orthonormalized()
			frames.append(frame.affine_inverse() * placed)
		anim.set_meta("%s_in_%s" % [spec["hand"].to_lower(), spec["against"]], frames)
		library.add_animation(clip_name, anim)
		print("%s: %.1f s, %d frames" % [clip_name, anim.length, frames.size()])
	player.stop()

	var err := ResourceSaver.save(library, OUT_PATH)
	if err != OK:
		push_error("Saving %s failed: %s" % [OUT_PATH, error_string(err)])
		return err
	print("Saved ", OUT_PATH)
	return OK


## Where the cup is held by `hand` (skeleton space), as player/hold_pose.gd places it.
static func _cup(hand: Transform3D, grip: Transform3D, cup_out: Vector3, slide: float) -> Transform3D:
	var g := hand * grip
	var out := (hand.basis * cup_out).normalized()
	var up := g.basis.y.normalized()
	var front := g.basis.z.normalized()
	var x := up.cross(front).normalized()
	var bottom := g.origin + out * CUP_RADIUS - up * CUP_HEIGHT * (0.5 - slide)
	return Transform3D(Basis(x, up, x.cross(up)), bottom)


static func _pose(skeleton: Skeleton3D, suffix: String) -> Transform3D:
	for b in skeleton.get_bone_count():
		if skeleton.get_bone_name(b).ends_with(suffix):
			return skeleton.get_bone_global_pose(b)
	return Transform3D.IDENTITY


## Poses the character `at` seconds into the source.
func _pose_at(player: AnimationPlayer, skeleton: Skeleton3D, at: float) -> void:
	player.seek(at, true)
	await process_frame
	skeleton.force_update_all_bone_transforms()


## The rotations of `bones` ("...Hand": that hand's fingers, not the hand
## itself) from `from` to `to` seconds of `source`, as an animation starting at 0.
static func _cut(source: Animation, from: float, to: float, bones: Array) -> Animation:
	var anim := Animation.new()
	anim.length = to - from
	for t in source.get_track_count():
		if source.track_get_type(t) != Animation.TYPE_ROTATION_3D:
			continue
		var bone := AnimMerge.bone_of(source, t)
		var keep := false
		for b: String in bones:
			if b.ends_with("Hand"):
				keep = keep or (bone.begins_with(b) and bone != b)
			else:
				keep = keep or bone == b
		if not keep:
			continue
		var track := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(track, source.track_get_path(t))
		var n := ceili(anim.length * RATE)
		for k in n + 1:
			var at := minf(k / RATE, anim.length)
			anim.rotation_track_insert_key(track, at, source.rotation_track_interpolate(t, from + at))
	return anim
