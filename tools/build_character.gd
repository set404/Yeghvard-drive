extends SceneTree
## Builds res://player/character.scn, the figure of the walker (player/player.gd),
## from the Mixamo character "Adam" and his animations in data/models/adam
## (FBX files downloaded from mixamo.com, see data/models/CREDITS.txt):
##
##   Ch08_nonPBR.fbx  the character, with skin
##   Walking.fbx, Running.fbx, Jumping.fbx  animations, without skin
##   Driving.fbx  seated with his hands on a steering wheel, for the driver
##            (main.gd seats him in the car you drive)
##   Entering Car.fbx, Exiting Car.fbx  getting in and out of the driver's seat;
##            these keep the way they move him (see _seat_paths)
##   Standing Idle.fbx (optional) a standing idle; without it he stands in a relaxed
##            pose made from his rest pose
##
## The walk and run were downloaded moving forward, not "in place": their hips
## are pinned here so player.gd moves him instead, and the distance they
## covered sets how fast each plays (saved as metadata on the scene, metres a
## second at normal speed). The jump keeps its crouch but not its rise, which
## the player's own jump gives him.
##
## Run:  godot --path . --script res://tools/build_character.gd

const DIR := "res://data/models/adam/"
const CHARACTER := "Ch08_nonPBR.fbx"
const ANIMATIONS := {"idle": "Standing Idle.fbx", "walk": "Walking.fbx", "run": "Running.fbx", "jump": "Jumping.fbx",
	"drive": "Driving.fbx", "enter": "Entering Car.fbx", "exit": "Exiting Car.fbx"}
## Animations that keep how far they move him.
const MOVING := ["enter", "exit"]
## Mixamo's driving pose sits upright as on a high chair; in our cars that put
## his feet through the floor. His thighs are raised this much (degrees), as in
## a car seat, which brings his feet up and his knees up under the wheel.
const DRIVE_LEG_LIFT := 30.0
## How far into getting in (share of its length) his hand is on the door handle.
const REACH := 0.18
const LOOPED := ["idle", "walk", "run", "drive"]
const OUT_PATH := "res://player/character.scn"
## Textures are stored at most this big.
const MAX_TEXTURE := 1024


func _initialize() -> void:
	var err := _build()
	quit(0 if err == OK else 1)


func _load(file: String) -> Node3D:
	var doc := FBXDocument.new()
	var state := FBXState.new()
	var err := doc.append_from_file(ProjectSettings.globalize_path(DIR + file), state)
	if err != OK:
		push_error("Loading %s failed: %s" % [file, error_string(err)])
		return null
	return doc.generate_scene(state)


func _build() -> Error:
	var source := _load(CHARACTER)
	if source == null:
		return FAILED
	var skeleton := source.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var hips_name := ""
	for b in skeleton.get_bone_count():
		if skeleton.get_bone_name(b).ends_with("Hips"):
			hips_name = skeleton.get_bone_name(b)
	var character := Node3D.new()
	character.name = "Character"
	skeleton.get_parent().remove_child(skeleton)
	skeleton.name = "Skeleton3D"
	character.add_child(skeleton)
	source.free()

	# His height, from the meshes in the rest pose.
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
	character.set_meta("height", top)

	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	character.add_child(player)
	var library := AnimationLibrary.new()
	var speeds := {}
	for anim_name: String in ANIMATIONS:
		var file: String = ANIMATIONS[anim_name]
		var anim: Animation = null
		if FileAccess.file_exists(ProjectSettings.globalize_path(DIR + file)) or ResourceLoader.exists(DIR + file):
			anim = _take(file)
		if anim == null and anim_name == "idle":
			anim = _standing_pose(skeleton)
		if anim == null:
			push_warning("No %s animation (%s)" % [anim_name, file])
			continue
		speeds[anim_name] = 0.0 if anim_name in MOVING else _pin_hips(anim, "Skeleton3D:" + hips_name, anim_name)
		anim.loop_mode = Animation.LOOP_LINEAR if anim_name in LOOPED else Animation.LOOP_NONE
		library.add_animation(anim_name, anim)
		print("%s: %.2f s, %.2f m/s" % [anim_name, anim.length, speeds[anim_name]])
	player.add_animation_library("", library)
	character.set_meta("speeds", speeds)
	if library.has_animation("drive"):
		_lift_legs(library.get_animation("drive"), "Skeleton3D:" + hips_name, skeleton)
		_measure_seat(character, player, skeleton)
		_seat_paths(character, library, "Skeleton3D:" + hips_name)

	_own(character, character)
	var scene := PackedScene.new()
	var err := scene.pack(character)
	if err == OK:
		err = ResourceSaver.save(scene, OUT_PATH, ResourceSaver.FLAG_COMPRESS)
	character.free()
	if err != OK:
		push_error("Saving %s failed: %s" % [OUT_PATH, error_string(err)])
	else:
		print("Saved %s (%.2f m tall)" % [OUT_PATH, top])
	return err


## Where his eyes and hands are when seated (the start of the drive
## animation), in the character's own space, for placing him in a car:
## metadata "drive_eyes" and "drive_hands".
func _measure_seat(character: Node3D, player: AnimationPlayer, skeleton: Skeleton3D) -> void:
	root.add_child(character)
	player.play("drive")
	player.seek(0.0, true)
	var at := func(suffix: String) -> Vector3:
		for b in skeleton.get_bone_count():
			if skeleton.get_bone_name(b).ends_with(suffix):
				return skeleton.transform * skeleton.get_bone_global_pose(b).origin
		return Vector3.ZERO
	var head: Vector3 = at.call("_Head")
	var top: Vector3 = at.call("_HeadTop_End")
	var eyes := head.lerp(top, 0.4) + Vector3(0.0, 0.0, 0.09)
	var hands: Vector3 = (at.call("_LeftHand") + at.call("_RightHand")) * 0.5
	character.set_meta("drive_eyes", eyes)
	character.set_meta("drive_hands", hands)
	character.set_meta("drive_feet", (at.call("_LeftToeBase") + at.call("_RightToeBase")) * 0.5)
	print("seated: eyes %s, hands %s, hips %s, feet %s" % [eyes, hands, at.call("_Hips"), character.get_meta("drive_feet")])
	player.stop()
	root.remove_child(character)


## Raises both thighs of the animation by DRIVE_LEG_LIFT, about his body's
## side-to-side axis.
func _lift_legs(anim: Animation, hips_path: String, skeleton: Skeleton3D) -> void:
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


## Where the hips start and end in sitting, getting in and getting out, and
## which way he faces (metadata "<anim>_hips_start", "_hips_end",
## "_facing_start", "_facing_end"; facings are directions on the ground, x and
## z). player.gd lines getting in and out up with his hips in the driver's seat.
func _seat_paths(character: Node3D, library: AnimationLibrary, hips_path: String) -> void:
	for anim_name: String in ["drive", "enter", "exit"]:
		if not library.has_animation(anim_name):
			continue
		var anim := library.get_animation(anim_name)
		for t in anim.get_track_count():
			if str(anim.track_get_path(t)) != hips_path:
				continue
			var n := anim.track_get_key_count(t)
			if anim.track_get_type(t) == Animation.TYPE_POSITION_3D:
				character.set_meta(anim_name + "_hips_start", anim.track_get_key_value(t, 0))
				character.set_meta(anim_name + "_hips_end", anim.track_get_key_value(t, n - 1))
			elif anim.track_get_type(t) == Animation.TYPE_ROTATION_3D:
				for end: String in ["start", "end"]:
					var q: Quaternion = anim.track_get_key_value(t, 0 if end == "start" else n - 1)
					var f := q * Vector3.BACK
					character.set_meta("%s_facing_%s" % [anim_name, end], Vector2(f.x, f.z).normalized())


## The animation in an FBX file downloaded without skin.
func _take(file: String) -> Animation:
	var scene := _load(file)
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


## Pins the hips over the spot he stands on: their forward and sideways travel
## goes (player.gd moves him), and for the jump also their rise. Returns how
## fast the animation went forward, in metres a second.
func _pin_hips(anim: Animation, hips_path: String, anim_name: String) -> float:
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
			if anim_name == "jump":
				p.y = minf(p.y, first.y)
			anim.track_set_key_value(t, k, p)
	return speed


## A relaxed standing pose (arms down at his sides), breathing a little, for
## when there is no idle animation: made from the rest pose, which is a T-pose.
func _standing_pose(skeleton: Skeleton3D) -> Animation:
	var anim := Animation.new()
	anim.length = 4.0
	for side: String in ["Left", "Right"]:
		var arm := -1
		var fore := -1
		for b in skeleton.get_bone_count():
			var n := skeleton.get_bone_name(b)
			if n.ends_with(side + "Arm"):
				arm = b
			elif n.ends_with(side + "ForeArm"):
				fore = b
		if arm < 0:
			continue
		# Turn the upper arm down about the body's forward axis, worked out in the
		# arm's parent space so it does not matter how the rig's bones are rolled.
		var parent_global := skeleton.get_bone_global_rest(skeleton.get_bone_parent(arm))
		var rest := skeleton.get_bone_rest(arm)
		var down := (1.0 if side == "Left" else -1.0) * deg_to_rad(72.0)
		var axis := (parent_global.basis.inverse() * Vector3.FORWARD).normalized()
		var t := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(t, "Skeleton3D:" + skeleton.get_bone_name(arm))
		for k in 3:
			var sway := down + (1.0 if side == "Left" else -1.0) * 0.03 * sin(k * PI)
			var q := Quaternion(axis, sway) * rest.basis.get_rotation_quaternion()
			anim.rotation_track_insert_key(t, k * 2.0, q)
		if fore >= 0:
			var fparent := skeleton.get_bone_global_rest(arm)
			var faxis := (fparent.basis.inverse() * Vector3.UP).normalized()
			var ft := anim.add_track(Animation.TYPE_ROTATION_3D)
			anim.track_set_path(ft, "Skeleton3D:" + skeleton.get_bone_name(fore))
			var fq := Quaternion(faxis, (1.0 if side == "Left" else -1.0) * deg_to_rad(12.0)) * skeleton.get_bone_rest(fore).basis.get_rotation_quaternion()
			anim.rotation_track_insert_key(ft, 0.0, fq)
	return anim


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
