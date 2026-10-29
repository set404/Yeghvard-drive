extends RefCounted
## Extra Mixamo animations for the story's scenes (talking, on the phone,
## laughing, pointing, slapping, throwing...), put on any Mixamo figure while
## the game runs: Davitik (npc/davitik.gd), you (player/player.gd's figure) and
## the uncle (one of the townsfolk's figures). Mixamo rigs share their bone
## names, so one download fits them all.
##
## Each is an FBX downloaded from mixamo.com WITHOUT skin, put in
## data/models/animations under one of the names in FILES. One that is not
## there is simply not played (the scene carries on without it).
##
## prepare() reads the files on another thread (started with the mission);
## add_to() puts those read on a figure's AnimationPlayer, fitted to its size.

const ANIM_DIR := "res://data/models/animations/"
const AnimMerge := preload("res://tools/anim_merge.gd")
const Figure := preload("res://npc/davitik_figure.gd")
## Animation name -> the file names tried for it, in order.
const FILES := {
	"talk": ["Talking.fbx", "Talking 1.fbx", "Talking 2.fbx"],
	"phone": ["Talking On Phone.fbx", "Talking On A Cell Phone.fbx", "Phone Call.fbx"],
	"laugh": ["Laughing.fbx"],
	"point": ["Pointing.fbx", "Pointing Forward.fbx"],
	"slap": ["Slap.fbx", "Slapping.fbx"],
	"throw": ["Throw.fbx", "Throwing.fbx", "Throw Object.fbx"],
	"angry": ["Angry.fbx", "Angry Gesture.fbx"],
	"no": ["Shaking Head No.fbx", "Head Shake No.fbx"],
	"wave": ["Waving.fbx"],
	"shrug": ["Shrugging.fbx", "Shrug.fbx"],
	"sit_laugh": ["Sitting Laughing.fbx"],
	"sit_talk": ["Sitting Talking.fbx"],
	"panic": ["Terrified.fbx"],
	"hit": ["Hit Reaction.fbx"],
	"drink": ["Drinking.fbx"],
}
const LOOPED := ["talk", "phone", "laugh", "angry", "sit_laugh", "sit_talk", "panic"]
## A standing animation whose hips set how high the others' hips are (fitted to each figure's size).
const REFERENCE := "Standing Idle.fbx"

static var _task := -1
static var _sources := {}
static var _reference_hips := 0.0


## Starts reading the animations that are there, on another thread.
static func prepare() -> void:
	if _task >= 0 or not _sources.is_empty():
		return
	_task = WorkerThreadPool.add_task(_read_all, false, "Story animations")


## Whether the animations have been read (add_to() has them all).
static func ready() -> bool:
	return _task < 0 or WorkerThreadPool.is_task_completed(_task)


static func _read_all() -> void:
	var found := {}
	for anim_name: String in FILES:
		for file: String in FILES[anim_name]:
			var anim := Figure._take(ANIM_DIR + file)
			if anim:
				anim.loop_mode = Animation.LOOP_LINEAR if anim_name in LOOPED else Animation.LOOP_NONE
				found[anim_name] = anim
				break
	var reference := Figure._take(ANIM_DIR + REFERENCE)
	if reference:
		_reference_hips = _hips_y(reference)
	_sources = found


## The names of the animations there are (read so far).
static func available() -> PackedStringArray:
	return PackedStringArray(_sources.keys()) if ready() else PackedStringArray()


## Puts the read animations `player` does not have yet on it (all of them, or
## those in `names`). Does nothing until they have been read.
static func add_to(player: AnimationPlayer, names: Array = []) -> void:
	if player == null or not ready():
		return
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	var root := player.get_node_or_null(player.root_node)
	var skeleton := root.find_child("Skeleton3D", true, false) as Skeleton3D if root else null
	if skeleton == null or not player.has_animation_library(""):
		return
	var hips_name := ""
	for b in skeleton.get_bone_count():
		if skeleton.get_bone_name(b).ends_with("Hips"):
			hips_name = skeleton.get_bone_name(b)
	var hips := skeleton.find_bone(hips_name)
	var lift := 1.0
	if hips >= 0 and _reference_hips > 0.0001:
		lift = skeleton.get_bone_rest(hips).origin.y / _reference_hips
	var library := player.get_animation_library("")
	for anim_name: String in _sources:
		if (not names.is_empty() and anim_name not in names) or library.has_animation(anim_name):
			continue
		var anim := (_sources[anim_name] as Animation).duplicate(true) as Animation
		AnimMerge.point_at(anim, skeleton)
		Figure._fit_hips(anim, "Skeleton3D:" + hips_name, lift)
		Figure._pin_hips(anim, "Skeleton3D:" + hips_name)
		library.add_animation(anim_name, anim)


static func _hips_y(anim: Animation) -> float:
	for t in anim.get_track_count():
		if str(anim.track_get_path(t)).ends_with("Hips") and anim.track_get_type(t) == Animation.TYPE_POSITION_3D and anim.track_get_key_count(t) > 0:
			return (anim.track_get_key_value(t, 0) as Vector3).y
	return 0.0
