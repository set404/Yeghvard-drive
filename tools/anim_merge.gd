extends RefCounted
## Merges Mixamo animations bone by bone, for tools/build_character.gd (and the
## townspeople in tools/build_npcs.gd, whose rigs have the same bones): one
## animation gives most of the body, another gives some bones, and a few more
## bones can follow the other one for a while, blended in and out.
##
## Bones are matched by name without the rig's "mixamorigN_" prefix, so
## animations downloaded on different Mixamo characters still fit.

## Keys a second in the merged tracks.
const RATE := 30.0


## A track's bone name without its prefix ("LeftForeArm"), or "".
static func bone_of(anim: Animation, track: int) -> String:
	var bone := str(anim.track_get_path(track)).get_slice(":", 1)
	var cut := bone.find("_")
	return bone.substr(cut + 1) if cut >= 0 else bone


## Points the animation's tracks at the bones of the same names in `skeleton`
## (Mixamo downloads differ in their prefix, e.g. "mixamorig1_" against the
## character's "mixamorig7_"); tracks for bones it lacks are dropped.
static func point_at(anim: Animation, skeleton: Skeleton3D) -> void:
	var bones := {}
	for b in skeleton.get_bone_count():
		var n := skeleton.get_bone_name(b)
		var cut := n.find("_")
		bones[n.substr(cut + 1) if cut >= 0 else n] = n
	for t in range(anim.get_track_count() - 1, -1, -1):
		var bone := bone_of(anim, t)
		if not bones.has(bone):
			anim.remove_track(t)
			continue
		anim.track_set_path(t, "Skeleton3D:" + bones[bone])


## One moment of `anim` (`at` seconds in) held still for `length` seconds.
static func still(anim: Animation, at: float, length: float) -> Animation:
	var out := anim.duplicate(true) as Animation
	out.length = length
	for t in out.get_track_count():
		var type := out.track_get_type(t)
		if type != Animation.TYPE_ROTATION_3D and type != Animation.TYPE_POSITION_3D and type != Animation.TYPE_SCALE_3D:
			continue
		var value: Variant
		if type == Animation.TYPE_ROTATION_3D:
			value = anim.rotation_track_interpolate(t, at)
		elif type == Animation.TYPE_POSITION_3D:
			value = anim.position_track_interpolate(t, at)
		else:
			value = anim.scale_track_interpolate(t, at)
		for k in range(out.track_get_key_count(t) - 1, -1, -1):
			out.track_remove_key(t, k)
		out.track_insert_key(t, 0.0, value)
		out.track_insert_key(t, length, value)
	return out


## Bones of the hips and both legs, down to the toes.
static func is_hips_or_leg(bone: String) -> bool:
	if bone == "Hips":
		return true
	for side in ["Left", "Right"]:
		for part in ["UpLeg", "Leg", "Foot", "Toe"]:
			if bone.begins_with(side + part):
				return true
	return false


## Bones of one arm, from the shoulder to the fingertips ("Left" or "Right").
static func is_arm(bone: String, side: String) -> bool:
	for part in ["Shoulder", "Arm", "ForeArm", "Hand"]:
		if bone.begins_with(side + part):
			return true
	return false


## `base`, with:
## - the bones `take` says yes to from `other`, which starts `start` seconds
##   into base and holds its first and last frames before and after;
## - the bones `follow` says yes to turning from base's pose to other's while
##   other's own time is inside `window`, fading in and out over `fade` s.
## The result is as long as base and loops as base does.
static func merge(base: Animation, other: Animation, take: Callable, follow: Callable,
		start: float, window := Vector2.ZERO, fade := 0.4) -> Animation:
	var out := base.duplicate(true) as Animation
	var others := {}
	for t in other.get_track_count():
		others["%s|%d" % [bone_of(other, t), other.track_get_type(t)]] = t
	var steps := ceili(base.length * RATE)
	for t in out.get_track_count():
		var type := out.track_get_type(t)
		if type != Animation.TYPE_ROTATION_3D and type != Animation.TYPE_POSITION_3D:
			continue
		var bone := bone_of(out, t)
		var taking: bool = take.call(bone)
		var following: bool = not taking and window != Vector2.ZERO and follow.call(bone)
		var key := "%s|%d" % [bone, type]
		if not (taking or following) or not others.has(key):
			continue
		var ot: int = others[key]
		for k in range(out.track_get_key_count(t) - 1, -1, -1):
			out.track_remove_key(t, k)
		for i in steps + 1:
			var time := minf(i / RATE, base.length)
			var at := clampf(time - start, 0.0, other.length)
			var w := 1.0
			if following:
				w = smoothstep(window.x - fade, window.x, at) * (1.0 - smoothstep(window.y, window.y + fade, at))
			if type == Animation.TYPE_ROTATION_3D:
				var a := base.rotation_track_interpolate(t, time)
				var b := other.rotation_track_interpolate(ot, at)
				out.rotation_track_insert_key(t, time, a.slerp(b, w))
			else:
				var a := base.position_track_interpolate(t, time)
				var b := other.position_track_interpolate(ot, at)
				out.position_track_insert_key(t, time, a.lerp(b, w))
	return out
