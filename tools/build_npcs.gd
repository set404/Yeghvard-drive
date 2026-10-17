extends SceneTree
## Builds the townspeople (world/townsfolk.gd walks them about): one scene
## res://npc/<name>.scn for each Mixamo character in data/models/npc (FBX, with
## skin), each with the same set of animations:
##
##   idle   standing          from data/models/adam/Standing Idle.fbx
##   walk   walking, in place from data/models/adam/Walking.fbx
##   talk   talking, waving a hand and nodding
##   listen listening, nodding now and then
##   look   looking about
##   phone  looking at a phone held in the right hand
##   die    (only from an FBX) falling down dead, when a car hits them; without
##          it npc/npc.gd topples the figure over instead
##
## Mixamo rigs all share their bone names, so Adam's animations fit them all.
## For talk, listen, look and phone an FBX of that name in data/models/npc/animations
## (downloaded from Mixamo without skin, e.g. "Talking.fbx", "Texting.fbx") is used
## when there is one; otherwise they are made here by moving the head and arms on
## top of the standing idle.
##
## Run:  godot --path . --script res://tools/build_npcs.gd

const DIR := "res://data/models/npc/"
const ANIM_DIR := "res://data/models/npc/animations/"
const ADAM := "res://data/models/adam/"
const OUT_DIR := "res://npc/"
## Optional Mixamo animations, by the names tried for each.
const OPTIONAL := {
	"talk": ["Talking.fbx", "Talking 1.fbx", "Talking 2.fbx"],
	"listen": ["Listening.fbx", "Nodding.fbx", "Agreeing.fbx"],
	"look": ["Looking Around.fbx", "Look Around.fbx"],
	"phone": ["Texting.fbx", "Texting While Standing.fbx", "Talking On Phone.fbx"],
	"die": ["Flying Back Death.fbx", "Falling Back Death.fbx", "Dying.fbx", "Death From The Front.fbx"],
}
const LOOPED := ["idle", "walk", "talk", "listen", "look", "phone"]
## Their textures are stored at most this big: they are seen from a distance.
const MAX_TEXTURE := 512
## Keys a second in the animations made here.
const RATE := 15.0


func _initialize() -> void:
	var failed := false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var walk := _take(ADAM + "Walking.fbx")
	var idle := _take(ADAM + "Standing Idle.fbx")
	if walk == null or idle == null:
		push_error("Needs Walking.fbx and Standing Idle.fbx in " + ADAM)
		quit(1)
		return
	for file in DirAccess.get_files_at(ProjectSettings.globalize_path(DIR)):
		if file.get_extension().to_lower() == "fbx":
			if _build(file, idle, walk) != OK:
				failed = true
	quit(1 if failed else 0)


func _load(path: String) -> Node3D:
	var doc := FBXDocument.new()
	var state := FBXState.new()
	var err := doc.append_from_file(ProjectSettings.globalize_path(path), state)
	if err != OK:
		push_error("Loading %s failed: %s" % [path, error_string(err)])
		return null
	return doc.generate_scene(state)


## The longest animation in an FBX file downloaded without skin, or null.
func _take(path: String) -> Animation:
	if not FileAccess.file_exists(ProjectSettings.globalize_path(path)):
		return null
	var scene := _load(path)
	if scene == null:
		return null
	var anim: Animation = null
	for ap: AnimationPlayer in scene.find_children("*", "AnimationPlayer", true, false):
		for n in ap.get_animation_list():
			var a := ap.get_animation(n)
			if anim == null or a.length > anim.length:
				anim = a.duplicate(true)
	scene.free()
	return anim


func _build(file: String, idle_src: Animation, walk_src: Animation) -> Error:
	var source := _load(DIR + file)
	if source == null:
		return FAILED
	var skeleton := source.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var character := Node3D.new()
	character.name = file.get_basename().get_slice("_", 0)
	skeleton.get_parent().remove_child(skeleton)
	skeleton.name = "Skeleton3D"
	character.add_child(skeleton)
	source.free()
	var top := 0.0
	for mi: MeshInstance3D in skeleton.find_children("*", "MeshInstance3D", true, false):
		var box := mi.transform * mi.get_aabb()
		top = maxf(top, box.end.y)
		for k in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(k) as BaseMaterial3D
			if mat:
				mi.set_surface_override_material(k, _compact(mat))
				mi.mesh.surface_set_material(k, null)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		# Not drawn beyond this distance (metres): there are many of them.
		mi.visibility_range_end = 140.0
		mi.visibility_range_end_margin = 10.0
	character.set_meta("height", top)
	var hips := _bone(skeleton, "Hips")
	var hips_path := "Skeleton3D:" + skeleton.get_bone_name(hips)

	var library := AnimationLibrary.new()
	var idle := _retarget(idle_src, skeleton, hips)
	var walk := _retarget(walk_src, skeleton, hips)
	var speed := _pin_hips(walk, hips_path)
	_pin_hips(idle, hips_path)
	library.add_animation("idle", idle)
	library.add_animation("walk", walk)
	for anim_name: String in OPTIONAL:
		var anim: Animation = null
		for f: String in OPTIONAL[anim_name]:
			anim = _take(ANIM_DIR + f)
			if anim:
				anim = _retarget(anim, skeleton, hips)
				# A death keeps how far it throws them; the others stay on the spot.
				if anim_name != "die":
					_pin_hips(anim, hips_path)
				print("  %s from %s" % [anim_name, f])
				break
		if anim == null and anim_name == "die":
			continue
		if anim == null:
			anim = _made(anim_name, idle, skeleton)
		library.add_animation(anim_name, anim)
	for anim_name in library.get_animation_list():
		library.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR if anim_name in LOOPED else Animation.LOOP_NONE

	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	character.add_child(player)
	player.add_animation_library("", library)
	character.set_meta("walk_speed", speed)

	# A phone in the right hand, shown while it plays "phone".
	var hand := _bone(skeleton, "RightHand")
	if hand >= 0:
		var grip := BoneAttachment3D.new()
		grip.name = "RightHand"
		grip.bone_name = skeleton.get_bone_name(hand)
		skeleton.add_child(grip)
		var phone := MeshInstance3D.new()
		phone.name = "Phone"
		var box := BoxMesh.new()
		box.size = Vector3(0.072, 0.15, 0.009)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.05, 0.05, 0.06)
		mat.roughness = 0.3
		box.material = mat
		phone.mesh = box
		# Held in the palm, the screen towards the face (worked out from the rest
		# pose: the hand's axis runs along the fingers).
		var scale := 1.0 / skeleton.get_bone_global_rest(hand).basis.get_scale().x
		phone.scale = Vector3.ONE * scale
		phone.position = Vector3(0.0, 0.09, 0.03) * scale
		phone.visible = false
		grip.add_child(phone)

	_own(character, character)
	var scene := PackedScene.new()
	var err := scene.pack(character)
	var out := OUT_DIR + character.name + ".scn"
	if err == OK:
		err = ResourceSaver.save(scene, out, ResourceSaver.FLAG_COMPRESS)
	print("%s: %.2f m tall, walks %.2f m/s -> %s (%s)" % [file, top, speed, out, error_string(err)])
	character.free()
	return err


## The animation made for another Mixamo rig, on this one: its tracks pointed
## at the bones of the same names here (rigs differ in their prefix, e.g.
## "mixamorig_" or "mixamorig2_"), and the hips' height scaled to this one's.
func _retarget(src: Animation, skeleton: Skeleton3D, hips: int) -> Animation:
	var anim := src.duplicate(true) as Animation
	var lift := 1.0
	for t in range(anim.get_track_count() - 1, -1, -1):
		var bone_name := str(anim.track_get_path(t)).get_slice(":", 1)
		var b := _bone(skeleton, _plain(bone_name))
		if b < 0:
			anim.remove_track(t)
			continue
		anim.track_set_path(t, "Skeleton3D:" + skeleton.get_bone_name(b))
		if b == hips and anim.track_get_type(t) == Animation.TYPE_POSITION_3D and anim.track_get_key_count(t) > 0:
			var first: Vector3 = anim.track_get_key_value(t, 0)
			if absf(first.y) > 1e-4:
				lift = skeleton.get_bone_rest(hips).origin.y / first.y
			for k in anim.track_get_key_count(t):
				anim.track_set_key_value(t, k, (anim.track_get_key_value(t, k) as Vector3) * lift)
	return anim


## A Mixamo bone name without its rig prefix: "mixamorig2_LeftArm" -> "LeftArm".
func _plain(bone_name: String) -> String:
	for sep in [":", "_"]:
		if bone_name.begins_with("mixamorig") and bone_name.contains(sep):
			return bone_name.substr(bone_name.find(sep) + 1)
	return bone_name


func _bone(skeleton: Skeleton3D, suffix: String) -> int:
	for b in skeleton.get_bone_count():
		var n := skeleton.get_bone_name(b)
		if n.ends_with(":" + suffix) or n.ends_with("_" + suffix) or n == suffix:
			return b
	return -1


## Keeps the hips over the spot (townsfolk.gd moves them); returns the speed
## the animation went forward at, metres a second.
func _pin_hips(anim: Animation, hips_path: String) -> float:
	var speed := 0.0
	for t in anim.get_track_count():
		if str(anim.track_get_path(t)) != hips_path or anim.track_get_type(t) != Animation.TYPE_POSITION_3D:
			continue
		var keys := anim.track_get_key_count(t)
		if keys == 0:
			continue
		var first: Vector3 = anim.track_get_key_value(t, 0)
		var last: Vector3 = anim.track_get_key_value(t, keys - 1)
		speed = Vector2(last.x - first.x, last.z - first.z).length() / maxf(anim.length, 0.001)
		for k in keys:
			var p: Vector3 = anim.track_get_key_value(t, k)
			p.x = first.x
			p.z = first.z
			anim.track_set_key_value(t, k, p)
	return speed


## One of the animations made from the idle, by turning bones about axes of
## the body (x: across, to the character's left; y: up; z: forward).
func _made(anim_name: String, idle: Animation, skeleton: Skeleton3D) -> Animation:
	var length := {"talk": 6.0, "listen": 6.0, "look": 8.0, "phone": 6.0}[anim_name] as float
	var moves := []
	match anim_name:
		"talk":
			# The right hand comes up in front and makes a point, twice; the head
			# nods along and turns a little.
			moves = [
				["RightArm", Vector3.RIGHT, func(t: float) -> float: return -deg_to_rad(38.0) * _bump(t, 0.4, 2.6) - deg_to_rad(20.0) * _bump(t, 3.4, 5.4)],
				["RightArm", Vector3.FORWARD, func(t: float) -> float: return deg_to_rad(12.0) * _bump(t, 0.4, 2.6)],
				["RightForeArm", Vector3.ZERO, func(t: float) -> float: return deg_to_rad(55.0) * _bump(t, 0.3, 2.8) + deg_to_rad(35.0) * _bump(t, 3.3, 5.6) + deg_to_rad(10.0) * sin(t * 5.0) * _bump(t, 0.6, 5.2)],
				["LeftArm", Vector3.RIGHT, func(t: float) -> float: return -deg_to_rad(15.0) * _bump(t, 2.2, 4.4)],
				["LeftForeArm", Vector3.ZERO, func(t: float) -> float: return deg_to_rad(30.0) * _bump(t, 2.0, 4.6)],
				["Head", Vector3.RIGHT, func(t: float) -> float: return deg_to_rad(6.0) * sin(t * 3.1) * _bump(t, 0.2, 5.8)],
				["Head", Vector3.UP, func(t: float) -> float: return deg_to_rad(10.0) * sin(t * 0.9)],
			]
		"listen":
			moves = [
				["Head", Vector3.RIGHT, func(t: float) -> float: return deg_to_rad(9.0) * (_bump(t, 1.0, 1.6) + _bump(t, 1.7, 2.3) + _bump(t, 4.2, 4.9))],
				["Head", Vector3.FORWARD, func(t: float) -> float: return deg_to_rad(5.0) * sin(t * TAU / 6.0)],
				["Spine1", Vector3.UP, func(t: float) -> float: return deg_to_rad(4.0) * sin(t * TAU / 6.0)],
			]
		"look":
			moves = [
				["Head", Vector3.UP, func(t: float) -> float: return deg_to_rad(50.0) * (_bump(t, 0.5, 3.0) - _bump(t, 4.0, 7.0))],
				["Neck", Vector3.UP, func(t: float) -> float: return deg_to_rad(15.0) * (_bump(t, 0.5, 3.0) - _bump(t, 4.0, 7.0))],
				["Head", Vector3.RIGHT, func(t: float) -> float: return -deg_to_rad(8.0) * _bump(t, 1.0, 2.6)],
			]
		"phone":
			# Upper arm forward and in, forearm bent up: the hand in front of the
			# chest; head down to look at it, thumbing now and then.
			moves = [
				["RightArm", Vector3.RIGHT, func(_t: float) -> float: return -deg_to_rad(28.0)],
				["RightArm", Vector3.FORWARD, func(_t: float) -> float: return -deg_to_rad(8.0)],
				["RightForeArm", Vector3.ZERO, func(t: float) -> float: return deg_to_rad(100.0) + deg_to_rad(4.0) * sin(t * 7.0)],
				["RightHand", Vector3.UP, func(_t: float) -> float: return deg_to_rad(20.0)],
				["Head", Vector3.RIGHT, func(t: float) -> float: return deg_to_rad(24.0) + deg_to_rad(3.0) * sin(t * 1.3)],
				["Neck", Vector3.RIGHT, func(_t: float) -> float: return deg_to_rad(10.0)],
			]
	var anim := Animation.new()
	anim.length = length
	# The idle's own tracks, sampled over this length (it loops).
	var tracks := {}
	for t in idle.get_track_count():
		tracks[str(idle.track_get_path(t))] = t
	var bones := {}
	for m: Array in moves:
		bones[_bone(skeleton, m[0])] = true
	# Every bone the idle moves keeps moving as in the idle.
	var out_tracks := {}
	for path: String in tracks:
		var it: int = tracks[path]
		var nt := anim.add_track(idle.track_get_type(it))
		anim.track_set_path(nt, path)
		out_tracks[path] = nt
	var frames := int(length * RATE)
	for f in frames + 1:
		var time := f / RATE
		var at := fmod(time, idle.length)
		var pose := _pose(skeleton, idle, tracks, at)
		# Turns, applied from the body outwards so each bone's parent is posed already.
		for b in skeleton.get_bone_count():
			var sum := Quaternion.IDENTITY
			var touched := false
			for m: Array in moves:
				if _bone(skeleton, m[0]) != b:
					continue
				var angle: float = (m[2] as Callable).call(time)
				var axis_body: Vector3 = m[1]
				if axis_body == Vector3.ZERO:
					axis_body = _elbow_axis(skeleton, pose, b)
				var parent_global := _global(skeleton, pose, skeleton.get_bone_parent(b))
				var axis := (parent_global.basis.inverse() * axis_body).normalized()
				sum = Quaternion(axis, angle) * sum
				touched = true
			if touched:
				pose[b] = Transform3D(Basis(sum * pose[b].basis.get_rotation_quaternion()).scaled(pose[b].basis.get_scale()), pose[b].origin)
		for path: String in out_tracks:
			var it: int = tracks[path]
			var nt: int = out_tracks[path]
			var b := skeleton.find_bone(path.get_slice(":", 1))
			match idle.track_get_type(it):
				Animation.TYPE_ROTATION_3D:
					anim.rotation_track_insert_key(nt, time, pose[b].basis.get_rotation_quaternion() if b >= 0 else idle.rotation_track_interpolate(it, at))
				Animation.TYPE_POSITION_3D:
					anim.position_track_insert_key(nt, time, idle.position_track_interpolate(it, at))
				Animation.TYPE_SCALE_3D:
					anim.scale_track_insert_key(nt, time, idle.scale_track_interpolate(it, at))
	# Bones moved here that the idle does not move get tracks of their own.
	for b: int in bones:
		var path := "Skeleton3D:" + skeleton.get_bone_name(b)
		if path in out_tracks:
			continue
		push_warning("%s: %s is not in the idle" % [anim_name, path])
	return anim


## 0 outside [a, b], rising smoothly to 1 in the middle and back.
func _bump(t: float, a: float, b: float) -> float:
	if t <= a or t >= b:
		return 0.0
	var ramp := minf(0.6, (b - a) * 0.3)
	return smoothstep(a, a + ramp, t) * (1.0 - smoothstep(b - ramp, b, t))


## Every bone's local pose at `at` seconds into `anim` (the rest pose where it has no track).
func _pose(skeleton: Skeleton3D, anim: Animation, tracks: Dictionary, at: float) -> Array:
	var pose := []
	for b in skeleton.get_bone_count():
		var rest := skeleton.get_bone_rest(b)
		var path := "Skeleton3D:" + skeleton.get_bone_name(b)
		var rot := rest.basis.get_rotation_quaternion()
		var pos := rest.origin
		var scl := rest.basis.get_scale()
		for t in anim.get_track_count():
			if str(anim.track_get_path(t)) != path:
				continue
			match anim.track_get_type(t):
				Animation.TYPE_ROTATION_3D:
					rot = anim.rotation_track_interpolate(t, at)
				Animation.TYPE_POSITION_3D:
					pos = anim.position_track_interpolate(t, at)
				Animation.TYPE_SCALE_3D:
					scl = anim.scale_track_interpolate(t, at)
		pose.append(Transform3D(Basis(rot).scaled(scl), pos))
	return pose


func _global(skeleton: Skeleton3D, pose: Array, b: int) -> Transform3D:
	var xf := Transform3D.IDENTITY
	while b >= 0:
		xf = pose[b] * xf
		b = skeleton.get_bone_parent(b)
	return xf


## The axis an elbow (or knee) bends about, in body space: across the upper
## and lower bones, oriented so a positive turn bends it the way it bends.
func _elbow_axis(skeleton: Skeleton3D, pose: Array, fore: int) -> Vector3:
	var arm := skeleton.get_bone_parent(fore)
	var hand := -1
	for c in skeleton.get_bone_children(fore):
		hand = c
		break
	var a := _global(skeleton, pose, arm).origin
	var e := _global(skeleton, pose, fore).origin
	var h := _global(skeleton, pose, hand).origin if hand >= 0 else e + (e - a)
	var axis := (e - a).cross(h - e)
	if axis.length() < 1e-4:
		# Straight arm: bend so the hand comes forward.
		axis = (e - a).cross(Vector3.BACK)
	axis = axis.normalized()
	# A positive turn should bring the hand forward and up, not back.
	var test := Quaternion(axis, 0.3) * (h - e)
	if test.z < (h - e).z:
		axis = -axis
	return axis


## The material with its textures shrunk to MAX_TEXTURE.
func _compact(mat: BaseMaterial3D) -> BaseMaterial3D:
	var out := mat.duplicate() as BaseMaterial3D
	for param in [BaseMaterial3D.TEXTURE_ALBEDO, BaseMaterial3D.TEXTURE_NORMAL, BaseMaterial3D.TEXTURE_ROUGHNESS,
			BaseMaterial3D.TEXTURE_METALLIC, BaseMaterial3D.TEXTURE_EMISSION, BaseMaterial3D.TEXTURE_AMBIENT_OCCLUSION]:
		var tex := out.get_texture(param)
		if tex == null:
			continue
		var img := tex.get_image()
		if img == null:
			continue
		if img.is_compressed():
			img.decompress()
		var big := maxi(img.get_width(), img.get_height())
		if big > MAX_TEXTURE:
			var f := float(MAX_TEXTURE) / big
			img.resize(maxi(1, roundi(img.get_width() * f)), maxi(1, roundi(img.get_height() * f)), Image.INTERPOLATE_LANCZOS)
		img.generate_mipmaps()
		out.set_texture(param, ImageTexture.create_from_image(img))
	return out


func _own(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		_own(child, owner_node)
