extends RefCounted
## Makes Davitik's figure from his model, data/models/special characters/Davitik/Davitik.fbx,
## and the shared Mixamo animations in data/models/animations. The data folder
## is left out of Godot's import (data/.gdignore), so the FBX files are read
## straight from disk, as the tools/build_*.gd scripts do.
##
## npc/davitik.gd calls make() the first time he is needed and keeps the result
## in user://davitik_figure.scn, so it is only slow (a few seconds: the FBX is
## big) once. tools/build_davitik.gd saves it as res://npc/davitik.scn instead,
## which then comes first. Replace Davitik.fbx and the cached one is made again.
##
## The figure gets the animations idle, walk, run, drive (seated; legs lifted
## for a car seat), drink, hit, die (thrown backwards, keeps how far), cower and
## punch, and the metadata "height", "speeds", "drive_eyes", "drive_hands".

const FBX := "res://data/models/special characters/Davitik/Davitik.fbx"
const ANIM_DIR := "res://data/models/animations/"
const CACHE := "user://davitik_figure.scn"
## Bumped when what make() builds changes, so an old cached figure is made again.
const VERSION := 1
const ANIMATIONS := {"idle": "Standing Idle.fbx", "walk": "Walking.fbx", "run": "Running.fbx",
	"drive": "Driving.fbx", "drink": "Drinking.fbx", "hit": "Hit Reaction.fbx",
	"die": "Flying Back Death.fbx", "cower": "Terrified.fbx", "punch": "Punching.fbx"}
const LOOPED := ["idle", "walk", "run", "drive", "cower", "drink"]
## Animations that keep how far they move him.
const MOVING := ["die"]
## Thighs raised this much (degrees) in the seated pose, as in a car seat (see tools/build_character.gd).
const DRIVE_LEG_LIFT := 30.0
## Textures are kept at most this big.
const MAX_TEXTURE := 1024
const AnimMerge := preload("res://tools/anim_merge.gd")


## Getting it ready in the background (prepare()): the task, and what it made.
static var _task := -1
static var _prepared: Node3D


## Starts getting his figure ready on another thread, so that taking it later
## (take()) does not hold the game up. Does nothing if it is already under way.
static func prepare() -> void:
	if _task >= 0 or _prepared:
		return
	_task = WorkerThreadPool.add_task(func() -> void: _prepared = load_or_make(), false, "Davitik's figure")


## Whether prepare() is done (or was never started): take() will not hold the game up.
static func ready() -> bool:
	return _task < 0 or WorkerThreadPool.is_task_completed(_task)


## His figure: the one prepare() got ready, or one got now. Null without the
## FBX. Call it once ready() says so: waiting on the background task from the
## game's own thread can hang it.
static func take() -> Node3D:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	if _prepared and is_instance_valid(_prepared):
		var figure := _prepared
		_prepared = null
		return figure
	return load_or_make()


## His figure: the cached one, or made now (and cached). Null without the FBX.
static func load_or_make() -> Node3D:
	if ResourceLoader.exists(CACHE):
		var cached := load(CACHE) as PackedScene
		if cached:
			var figure := cached.instantiate() as Node3D
			if figure and int(figure.get_meta("version", 0)) == VERSION and int(figure.get_meta("fbx_time", 0)) == _fbx_time():
				return figure
			if figure:
				figure.free()
	var made := make()
	if made == null:
		return null
	var scene := PackedScene.new()
	_own(made, made)
	if scene.pack(made) == OK:
		ResourceSaver.save(scene, CACHE, ResourceSaver.FLAG_COMPRESS)
	return made


## Makes the figure from the FBX files (null if his model is not there).
static func make() -> Node3D:
	if not FileAccess.file_exists(ProjectSettings.globalize_path(FBX)):
		push_warning("No %s" % FBX)
		return null
	var t0 := Time.get_ticks_msec()
	var source := _load(FBX)
	if source == null:
		return null
	var found := source.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		push_error("%s has no skeleton: rig him on mixamo.com and download as FBX with skin" % FBX)
		source.free()
		return null
	var skeleton := found[0] as Skeleton3D
	var skinned := false
	for mi: MeshInstance3D in skeleton.find_children("*", "MeshInstance3D", true, false):
		skinned = skinned or mi.skin != null
	if not skinned:
		# Exported from Blender without the armature binding (no skin): the body
		# would not move with the bones, and is not kept with the skeleton.
		push_error("%s has no skinning: its mesh is not bound to the skeleton. In Blender, parent the body to the armature (Armature modifier) and export both." % FBX)
		source.free()
		return null
	var hips_name := ""
	for b in skeleton.get_bone_count():
		if skeleton.get_bone_name(b).ends_with("Hips"):
			hips_name = skeleton.get_bone_name(b)
	var character := Node3D.new()
	character.name = "Davitik"
	var skeleton_xf := _to_root(skeleton, source)
	skeleton.get_parent().remove_child(skeleton)
	skeleton.owner = null
	skeleton.name = "Skeleton3D"
	skeleton.transform = skeleton_xf
	character.add_child(skeleton)
	source.free()

	# His height from the meshes; a model made by an AI tool (Tripo) keeps its
	# mesh in tiny units sized by the skin, and then from the top of his head.
	var top := 0.0
	var meshes := skeleton.find_children("*", "MeshInstance3D", true, false)
	for mi: MeshInstance3D in meshes:
		top = maxf(top, (skeleton.transform * mi.transform * mi.get_aabb()).end.y)
		for k in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(k) as BaseMaterial3D
			if mat:
				mi.set_surface_override_material(k, _compact(mat))
				mi.mesh.surface_set_material(k, null)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var head_top := 0.0
	for b in skeleton.get_bone_count():
		if skeleton.get_bone_name(b).ends_with("HeadTop_End"):
			head_top = (skeleton.transform * skeleton.get_bone_global_rest(b)).origin.y
	if top < head_top * 0.5:
		top = head_top + 0.02
		# Bounds the size of him, not of the tiny mesh (or he vanishes whenever that is off screen).
		for mi: MeshInstance3D in meshes:
			mi.custom_aabb = AABB(Vector3(-top * 0.7, -top * 0.1, -top * 0.7), Vector3(top * 1.4, top * 1.3, top * 1.4))
	character.set_meta("height", top)
	character.set_meta("version", VERSION)
	character.set_meta("fbx_time", _fbx_time())

	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	character.add_child(player)
	var library := AnimationLibrary.new()
	var speeds := {}
	var hips_path := "Skeleton3D:" + hips_name
	# How much the hips' movement is scaled to his size: from a standing animation.
	var lift := 1.0
	for anim_name: String in ANIMATIONS:
		var anim := _take(ANIM_DIR + ANIMATIONS[anim_name])
		if anim == null:
			push_warning("Davitik: no %s animation (%s)" % [anim_name, ANIMATIONS[anim_name]])
			continue
		AnimMerge.point_at(anim, skeleton)
		if anim_name in ["idle", "walk"] and is_equal_approx(lift, 1.0):
			lift = _hips_lift(anim, skeleton, hips_name)
		_fit_hips(anim, hips_path, lift)
		speeds[anim_name] = 0.0 if anim_name in MOVING else _pin_hips(anim, hips_path)
		anim.loop_mode = Animation.LOOP_LINEAR if anim_name in LOOPED else Animation.LOOP_NONE
		library.add_animation(anim_name, anim)
	player.add_animation_library("", library)
	character.set_meta("speeds", speeds)
	if library.has_animation("drive"):
		_lift_legs(library.get_animation("drive"), hips_path)
		_measure_seat(character, library.get_animation("drive"), skeleton)
	print("Davitik's figure made in %d ms (%.2f m tall)" % [Time.get_ticks_msec() - t0, top])
	return character


## When his FBX was last changed: a cached figure made from an older one is made again.
static func _fbx_time() -> int:
	return FileAccess.get_modified_time(ProjectSettings.globalize_path(FBX))


static func _load(path: String) -> Node3D:
	var doc := FBXDocument.new()
	var state := FBXState.new()
	var err := doc.append_from_file(ProjectSettings.globalize_path(path), state)
	if err != OK:
		push_error("Loading %s failed: %s" % [path, error_string(err)])
		return null
	return doc.generate_scene(state)


## The longest animation in an FBX file downloaded without skin, or null.
static func _take(path: String) -> Animation:
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


## How much an animation's hips move compared with his (its first key, standing, against his rest pose).
static func _hips_lift(anim: Animation, skeleton: Skeleton3D, hips_name: String) -> float:
	var hips := skeleton.find_bone(hips_name)
	if hips < 0:
		return 1.0
	var rest_y := skeleton.get_bone_rest(hips).origin.y
	for t in anim.get_track_count():
		if str(anim.track_get_path(t)) != "Skeleton3D:" + hips_name or anim.track_get_type(t) != Animation.TYPE_POSITION_3D:
			continue
		if anim.track_get_key_count(t) == 0:
			continue
		var first: Vector3 = anim.track_get_key_value(t, 0)
		if absf(first.y) > 1e-4 and absf(rest_y) > 1e-4:
			var lift := rest_y / first.y
			return 1.0 if absf(lift - 1.0) < 0.05 else lift
	return 1.0


static func _fit_hips(anim: Animation, hips_path: String, lift: float) -> void:
	if is_equal_approx(lift, 1.0):
		return
	for t in anim.get_track_count():
		if str(anim.track_get_path(t)) != hips_path or anim.track_get_type(t) != Animation.TYPE_POSITION_3D:
			continue
		for k in anim.track_get_key_count(t):
			anim.track_set_key_value(t, k, (anim.track_get_key_value(t, k) as Vector3) * lift)


## Keeps the hips over the spot (npc/davitik.gd moves him); returns the speed
## the animation went forward at, in his units a second.
static func _pin_hips(anim: Animation, hips_path: String) -> float:
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


## Raises both thighs of the seated animation by DRIVE_LEG_LIFT.
static func _lift_legs(anim: Animation, hips_path: String) -> void:
	var hips_track := -1
	for t in anim.get_track_count():
		if str(anim.track_get_path(t)) == hips_path and anim.track_get_type(t) == Animation.TYPE_ROTATION_3D:
			hips_track = t
	var lift := Quaternion(Vector3.RIGHT, -deg_to_rad(DRIVE_LEG_LIFT))
	for t in anim.get_track_count():
		var path := str(anim.track_get_path(t))
		if anim.track_get_type(t) != Animation.TYPE_ROTATION_3D or not path.ends_with("UpLeg"):
			continue
		for k in anim.track_get_key_count(t):
			var at := anim.track_get_key_time(t, k)
			var hips := anim.rotation_track_interpolate(hips_track, at) if hips_track >= 0 else Quaternion.IDENTITY
			var q: Quaternion = anim.track_get_key_value(t, k)
			anim.track_set_key_value(t, k, hips.inverse() * lift * hips * q)


## Where his eyes, hands and feet are seated (the first moment of "drive"),
## worked out down the bones from the animation's keys.
static func _measure_seat(character: Node3D, anim: Animation, skeleton: Skeleton3D) -> void:
	var count := skeleton.get_bone_count()
	var rot: Array[Quaternion] = []
	var pos: Array[Vector3] = []
	for b in count:
		rot.append(skeleton.get_bone_rest(b).basis.get_rotation_quaternion())
		pos.append(skeleton.get_bone_rest(b).origin)
	for t in anim.get_track_count():
		var bone := skeleton.find_bone(str(anim.track_get_path(t)).get_slice(":", 1))
		if bone < 0:
			continue
		match anim.track_get_type(t):
			Animation.TYPE_ROTATION_3D:
				rot[bone] = anim.rotation_track_interpolate(t, 0.0)
			Animation.TYPE_POSITION_3D:
				pos[bone] = anim.position_track_interpolate(t, 0.0)
	var posed: Array[Transform3D] = []
	posed.resize(count)
	for b in count:
		var local := Transform3D(Basis(rot[b]), pos[b])
		var parent := skeleton.get_bone_parent(b)
		posed[b] = posed[parent] * local if parent >= 0 and parent < b else local
	var at := func(suffix: String) -> Vector3:
		for b in count:
			if skeleton.get_bone_name(b).ends_with(suffix):
				return skeleton.transform * posed[b].origin
		return Vector3.ZERO
	var head: Vector3 = at.call("_Head")
	var top: Vector3 = at.call("_HeadTop_End")
	var eyes := head.lerp(top, 0.4) + Vector3(0.0, 0.0, 0.09) * (top.y / 1.75 if top.y > 0.1 else 1.0)
	character.set_meta("drive_eyes", eyes)
	character.set_meta("drive_hands", (at.call("_LeftHand") + at.call("_RightHand")) * 0.5)
	character.set_meta("drive_feet", (at.call("_LeftToeBase") + at.call("_RightToeBase")) * 0.5)


## The material with its textures shrunk to MAX_TEXTURE.
static func _compact(mat: BaseMaterial3D) -> BaseMaterial3D:
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


## Where `node` sits relative to `root` (its parents' transforms one after another).
static func _to_root(node: Node3D, root: Node) -> Transform3D:
	var xf := node.transform
	var p := node.get_parent()
	while p and p != root:
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		p = p.get_parent()
	if root is Node3D:
		xf = (root as Node3D).transform * xf
	return xf


static func _own(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		_own(child, owner_node)
