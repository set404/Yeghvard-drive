class_name Combat
extends Node
## Fighting and shooting on foot. main.gd adds this as "Combat".
##
## With the mouse grabbed:
##   Left click, empty-handed: a punch (left and right in turn) at whoever is
##   just in front of you; he turns to the nearest one in reach.
##   With the pistol in your hand (picked in the inventory with the wheel):
##   hold Right click to aim over the shoulder (a crosshair; you only walk),
##   Left click to shoot where the crosshair is (from the hip without aiming).
##   R reloads from the rounds you carry ("ammo" in the inventory).
## Hit people lose health (npc/npc.gd take_hit); a shot sends everyone near
## running (world/townsfolk.gd alarm). Your health ("Health" on the player,
## game/health.gd) is on the HUD and comes back slowly; knocked out, you wake
## up at home and pay the hospital.
##
## With the character's Mixamo punches (tools/build_character.gd: "punch" with
## his lead, left hand, "punch_rear" with his right) a punch plays those in
## turn; otherwise his arm is thrown out in code (player/combat_pose.gd), which
## also always points the pistol at what you aim at.

const Pose := preload("res://player/combat_pose.gd")
const Pistol := preload("res://props/pistol.gd")
const Sfx := preload("res://game/sfx.gd")
## The townspeople's bodies (world/townsfolk.gd BODY_LAYER).
const BODY_LAYER := 1 << 9

@export_group("Fists")
@export var punch_damage := 25.0
## How far in front of you a punch reaches (metres), and how long one takes,
## and when in it it lands (seconds).
@export var punch_reach := 1.0
@export var punch_time := 0.42
@export var punch_lands := 0.14
@export_group("Pistol")
@export var shot_damage := 55.0
## A shot this high up someone (metres from their feet) is to the head.
@export var head_height := 1.45
@export var head_damage := 200.0
@export var fire_interval := 0.3
@export var magazine_size := 8
@export var reload_time := 1.5
@export var shot_range := 150.0
## Everyone within this far of a shot runs.
@export var alarm_radius := 45.0
@export_group("Knocked out")
## Share of your money the hospital takes when you are knocked out, and at least this.
@export var hospital_share := 0.1
@export var hospital_min := 2000.0

## The game (main.gd), this node's parent.
var main: Node3D
var health: Health
var aiming := false
## Rounds in the pistol.
var magazine := 0

var _pose: SkeletonModifier3D
var _pistol: Node3D
var _cooldown := 0.0
var _reload_left := 0.0
## Punching: seconds into it (-1 when not), with which hand, whether it landed, at whom.
var _punch_t := -1.0
var _punch_side := "Right"
var _punch_landed := false
var _punch_target: Node3D
## Seconds the gun stays up after a shot from the hip.
var _raised := 0.0
## Seconds left of his own reaction to being hit (the character's "hit").
var _hurt_left := 0.0
## Where the crosshair points (world), worked out each frame.
var _aim_point := Vector3.ZERO
var _grabbed := false
var _flash: OmniLight3D
var _flash_left := 0.0

var _crosshair: Control
var _health_bar: ProgressBar
var _ammo_label: Label


func _ready() -> void:
	main = get_parent()
	health = Health.new()
	health.name = "Health"
	main.player.add_child(health)
	health.died.connect(_knocked_out)
	health.damaged.connect(_on_hurt)
	_pistol = Pistol.new()
	_pistol.name = "HeldPistol"
	_pistol.top_level = true
	_pistol.visible = false
	add_child(_pistol)
	_flash = OmniLight3D.new()
	_flash.light_color = Color(1.0, 0.8, 0.45)
	_flash.light_energy = 0.0
	_flash.omni_range = 5.0
	_flash.top_level = true
	add_child(_flash)
	_build_hud()


## Whether the pistol is the thing in your hand.
func armed() -> bool:
	return main.inventory.selected_id() == "pistol"


## Whether you can fight now: on foot, not getting in or out, drinking or smoking.
func can_fight() -> bool:
	var p: Node = main.player
	return main.on_foot and p.player_controlled and not p.is_busy() and not p.on_break \
		and float(main.get("_door_time")) <= 0.0 and not health.is_dead()


func _unhandled_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		# The click that grabs the mouse (chase_camera.gd) is not a punch.
		if _grabbed and can_fight():
			if armed():
				shoot()
			else:
				punch()
		return
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.physical_keycode == KEY_R and main.on_foot and armed():
		reload()


func _process(delta: float) -> void:
	_grabbed = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	_cooldown -= delta
	_raised -= delta
	if _hurt_left > 0.0:
		_hurt_left -= delta
		if _hurt_left <= 0.0 and main.player.override_anim == "hit":
			main.player.override_anim = ""
	var fighting := can_fight()
	var gun := fighting and armed()
	aiming = gun and _grabbed and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	_aim_point = _crosshair_point()
	if _reload_left > 0.0:
		_reload_left -= delta
		if _reload_left <= 0.0:
			_finish_reload()
	if _punch_t >= 0.0:
		_punching(delta)
	var p: Node = main.player
	# The camera over his shoulder while aiming.
	var close := aiming
	p.chase_distance = lerpf(p.chase_distance, 1.9 if close else 4.0, 1.0 - exp(-10.0 * delta))
	p.chase_height = lerpf(p.chase_height, 0.45 if close else 1.5, 1.0 - exp(-10.0 * delta))
	p.chase_side = lerpf(p.chase_side, 0.6 if close else 0.0, 1.0 - exp(-10.0 * delta))
	p.aim_slow = aiming
	var gun_up := gun and (aiming or _raised > 0.0)
	if gun_up:
		p.aim_yaw = _yaw_to(_aim_point)
	elif _punch_t >= 0.0 and _punch_target:
		p.aim_yaw = _yaw_to(_punch_target.global_position)
	else:
		p.aim_yaw = null
	_arms(gun_up, delta)
	_pistol.visible = main.on_foot and armed() and p.visible
	if _pistol.visible and _pose == null:
		_place_pistol_plain(gun_up)
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			_flash.light_energy = 0.0
	_hud(gun, delta)


# --- punching ------------------------------------------------------------------

func punch() -> void:
	if _punch_t >= 0.0 or _cooldown > 0.0:
		return
	_punch_t = 0.0
	_punch_landed = false
	_punch_side = "Left" if _punch_side == "Right" else "Right"
	_punch_target = _nearest_in_reach(punch_reach + 0.8)
	var p: Node = main.player
	var anim: AnimationPlayer = p.get("_anim")
	if anim:
		var want := "punch_rear" if _punch_side == "Right" else "punch"
		if not anim.has_animation(want):
			want = "punch"
		if anim.has_animation(want):
			p.override_anim = want


func _punching(delta: float) -> void:
	_punch_t += delta
	if not _punch_landed and _punch_t >= punch_lands:
		_punch_landed = true
		var who := _nearest_in_reach(punch_reach)
		if who:
			who.take_hit(punch_damage, main.player.global_position, main.player, "punch")
			Sfx.play(self, Sfx.punch(), who.global_position + Vector3.UP * 1.4)
			# Those watching a fight steer clear of it.
			_town().alarm(main.player.global_position, 6.0)
	var length := punch_time
	var p: Node = main.player
	var playing: String = p.override_anim
	if playing.begins_with("punch") and p._anim.has_animation(playing):
		length = maxf(punch_time, p._anim.get_animation(playing).length * 0.6)
	if _punch_t >= length:
		_punch_t = -1.0
		_punch_target = null
		_cooldown = 0.08
		if playing.begins_with("punch"):
			p.override_anim = ""


## The nearest person in front of you within `reach` metres, or null.
func _nearest_in_reach(reach: float) -> Node3D:
	var town := _town()
	if town == null:
		return null
	var me: Vector3 = main.player.global_position
	var front: Vector3 = main.player.global_basis.z
	var best: Node3D = null
	var best_d := reach
	for who: Node3D in town.people():
		var to := who.global_position - me
		if absf(to.y) > 1.2:
			continue
		to.y = 0.0
		var d := to.length()
		# Within reach, and not behind him (he turns to face them).
		if d < best_d and (d < 0.6 or to.normalized().dot(front) > -0.2):
			best = who
			best_d = d
	return best


# --- shooting ------------------------------------------------------------------

func shoot() -> void:
	if _cooldown > 0.0 or _reload_left > 0.0:
		return
	if magazine <= 0:
		Sfx.play(self, Sfx.click(), main.player.global_position + Vector3.UP * 1.3, -6.0)
		_cooldown = 0.25
		if main.inventory.count_of("ammo") > 0:
			reload()
		else:
			_say("Out of ammo: the dealer behind the supermarket sells rounds.")
		return
	magazine -= 1
	_cooldown = fire_interval
	_raised = 1.2
	var muzzle := _muzzle()
	# From the muzzle to where the crosshair is (stopped by whatever is in the way).
	var to := _aim_point
	var dir := (to - muzzle).normalized()
	var ray := PhysicsRayQueryParameters3D.create(muzzle, muzzle + dir * shot_range)
	ray.collision_mask = 1 | BODY_LAYER
	ray.exclude = [main.player.get_rid()]
	var hit := main.get_world_3d().direct_space_state.intersect_ray(ray)
	var end: Vector3 = hit["position"] if hit else muzzle + dir * shot_range
	if hit:
		_hit(hit["collider"], end, dir)
	Sfx.play(self, Sfx.shot(), muzzle, 4.0, 25.0)
	_flash.global_position = muzzle
	_flash.light_energy = 6.0
	_flash_left = 0.06
	_tracer(muzzle, end)
	_town().alarm(main.player.global_position, alarm_radius)


func _hit(collider: Object, at: Vector3, dir: Vector3) -> void:
	var node := collider as Node
	var who := node.get_parent() if node else null
	if who and who.has_method("take_hit"):
		var head: bool = at.y - who.global_position.y > head_height
		who.take_hit(head_damage if head else shot_damage, main.player.global_position, main.player, "shot")
		return
	var car := collider as RigidBody3D
	if car:
		car.apply_impulse(dir * 40.0, at - car.global_position)


func reload() -> void:
	if _reload_left > 0.0 or magazine >= magazine_size or main.inventory.count_of("ammo") <= 0:
		return
	_reload_left = reload_time


func _finish_reload() -> void:
	var take := mini(magazine_size - magazine, main.inventory.count_of("ammo"))
	if take > 0 and main.inventory.take("ammo", take):
		magazine += take


## Where the middle of the screen points: the first thing the camera's line
## of sight meets past you, or far off along it.
func _crosshair_point() -> Vector3:
	var cam := main.get_viewport().get_camera_3d()
	if cam == null:
		return main.player.global_position + main.player.global_basis.z * 20.0
	var from := cam.global_position
	var dir := -cam.global_basis.z
	var ray := PhysicsRayQueryParameters3D.create(from, from + dir * shot_range)
	ray.collision_mask = 1 | BODY_LAYER
	ray.exclude = [main.player.get_rid()]
	var hit := main.get_world_3d().direct_space_state.intersect_ray(ray)
	return hit["position"] if hit else from + dir * shot_range


func _muzzle() -> Vector3:
	return _pistol.global_transform * Pistol.MUZZLE


func _yaw_to(at: Vector3) -> float:
	var to: Vector3 = at - main.player.global_position
	return atan2(to.x, to.z)


func _tracer(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 0.5:
		return
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.012, 0.012, length)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.85, 0.5, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.top_level = true
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var mid := (from + to) * 0.5
	mi.global_transform = Transform3D(Basis.looking_at(to - from), mid)
	get_tree().create_timer(0.05).timeout.connect(mi.queue_free)


# --- arms and the pistol ----------------------------------------------------------

## The arm pose over his animation: the pistol held out at the aim point with
## both hands, or a punch thrown, or nothing.
func _arms(gun_up: bool, delta: float) -> void:
	var skeleton := main.player.get_node_or_null("Model/Skeleton3D") as Skeleton3D
	if skeleton == null:
		return
	if _pose == null:
		_pose = Pose.new()
		_pose.name = "CombatPose"
		skeleton.add_child(_pose)
		_pose.posed.connect(_place_pistol)
	var blend := 1.0 - exp(-18.0 * delta)
	var right_w := 0.0
	var left_w := 0.0
	if gun_up:
		var shoulder: Variant = _pose.shoulder("Right")
		if shoulder is Vector3:
			var dir: Vector3 = (_aim_point - shoulder).normalized()
			_pose.right_goal = shoulder + dir * 0.6
			# The left hand comes across to steady it.
			_pose.left_goal = _pose.right_goal - dir * 0.05 + main.player.global_basis.x * 0.04 + Vector3.DOWN * 0.03
			right_w = 1.0
			left_w = 0.9
	elif _punch_t >= 0.0 and not String(main.player.override_anim).begins_with("punch"):
		var shoulder: Variant = _pose.shoulder(_punch_side)
		if shoulder is Vector3:
			var front: Vector3 = main.player.global_basis.z
			var goal: Vector3 = shoulder + front * 0.62 + Vector3.DOWN * 0.03
			if _punch_target:
				goal = shoulder + ((_punch_target.global_position + Vector3.UP * 1.4) - shoulder).normalized() * 0.62
			var t := _punch_t
			var w := smoothstep(0.0, punch_lands, t) - smoothstep(punch_lands + 0.05, punch_time, t)
			if _punch_side == "Right":
				_pose.right_goal = goal
				_pose.right_weight = w
			else:
				_pose.left_goal = goal
				_pose.left_weight = w
			return
	_pose.right_weight = lerpf(_pose.right_weight, right_w, blend)
	_pose.left_weight = lerpf(_pose.left_weight, left_w, blend)


## The pistol in his right palm, pointing at the aim point when the gun is up,
## otherwise along his forearm, tipped down (called once the arms are posed).
func _place_pistol() -> void:
	if not _pistol.visible:
		return
	var palm: Dictionary = _pose.right_palm()
	if palm.is_empty():
		_place_pistol_plain(aiming or _raised > 0.0)
		return
	var at: Vector3 = palm["palm"]
	var barrel: Vector3
	if aiming or _raised > 0.0:
		barrel = (_aim_point - at).normalized()
	else:
		barrel = (palm["forearm"] as Vector3 + Vector3.DOWN * 0.6).normalized()
	_pistol.global_transform = Transform3D(_gun_basis(barrel), at)


## Without a character's skeleton (the figure made of shapes): out in front of him.
func _place_pistol_plain(up: bool) -> void:
	var p: Node3D = main.player
	var at := p.global_transform * (Vector3(-0.2, 1.35, 0.5) if up else Vector3(-0.25, 0.95, 0.15))
	var barrel: Vector3 = (_aim_point - at).normalized() if up else (p.global_basis.z + Vector3.DOWN).normalized()
	_pistol.global_transform = Transform3D(_gun_basis(barrel), at)


## Barrel (+Z) along `barrel`, sights (+Y) as near up as that allows.
static func _gun_basis(barrel: Vector3) -> Basis:
	var up := Vector3.UP if absf(barrel.dot(Vector3.UP)) < 0.98 else Vector3.BACK
	var x := up.cross(barrel).normalized()
	return Basis(x, barrel.cross(x).normalized(), barrel)


# --- getting hurt ---------------------------------------------------------------------

func _on_hurt(_amount: float, _from: Vector3) -> void:
	var p: Node = main.player
	if p.has_method("end_break"):
		p.end_break()
	# He reels (the character's "hit", while not throwing a punch himself).
	var anim: AnimationPlayer = p.get("_anim")
	if anim and anim.has_animation("hit") and main.on_foot and not String(p.override_anim).begins_with("punch"):
		p.override_anim = "hit"
		anim.play("hit", 0.05)
		anim.seek(0.0, true)
		_hurt_left = minf(0.6, anim.get_animation("hit").length)


## Out of health: you wake up at home a bit poorer, and the fights are over.
func _knocked_out() -> void:
	var bill := minf(maxf(main.wallet.balance * hospital_share, hospital_min), main.wallet.balance)
	main.wallet.spend(bill)
	main.wallet.save()
	_punch_t = -1.0
	main.player.override_anim = ""
	var town := _town()
	if town:
		town.calm_all()
	var spot: Variant = main.front_door_outside(1.8) if main.has_method("front_door_outside") else null
	if spot is Vector3:
		main.player.place(spot + Vector3.UP * 0.1, main.player.global_basis.z)
	health.reset()
	_say("You were knocked out and woke up at home.\nHospital bill: %s" % Wallet.format(bill))


func _town() -> Node:
	return main.get_node_or_null("Townsfolk")


func _say(text: String) -> void:
	var missions = main.get("missions")
	if missions:
		missions.show_banner(text)


# --- HUD ------------------------------------------------------------------------------

func _hud(gun: bool, _delta: float) -> void:
	_crosshair.visible = gun and _grabbed and (aiming or _raised > 0.0)
	_crosshair.queue_redraw()
	_ammo_label.visible = main.on_foot and armed()
	if _ammo_label.visible:
		var spare: int = main.inventory.count_of("ammo")
		_ammo_label.text = "Reloading..." if _reload_left > 0.0 else "%d / %d" % [magazine, spare]
	_health_bar.value = health.share() * 100.0
	_health_bar.visible = main.on_foot or health.share() < 1.0


func _build_hud() -> void:
	var hud: CanvasLayer = main.get_node("HUD")
	_crosshair = Control.new()
	_crosshair.name = "Crosshair"
	_crosshair.set_anchors_preset(Control.PRESET_CENTER)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crosshair.visible = false
	_crosshair.draw.connect(func() -> void:
		for d: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			_crosshair.draw_line(d * 4.0, d * 11.0, Color(0, 0, 0, 0.7), 4.0)
			_crosshair.draw_line(d * 4.0, d * 11.0, Color.WHITE, 2.0)
		_crosshair.draw_circle(Vector2.ZERO, 1.5, Color.WHITE))
	hud.add_child(_crosshair)

	_health_bar = ProgressBar.new()
	_health_bar.name = "Health"
	_health_bar.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_health_bar.offset_left = -260.0
	_health_bar.offset_right = -30.0
	_health_bar.offset_top = -292.0
	_health_bar.offset_bottom = -270.0
	_health_bar.show_percentage = false
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0, 0, 0, 0.55)
	back.set_corner_radius_all(5)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.85, 0.18, 0.15)
	fill.set_corner_radius_all(5)
	_health_bar.add_theme_stylebox_override("background", back)
	_health_bar.add_theme_stylebox_override("fill", fill)
	_health_bar.value = 100.0
	hud.add_child(_health_bar)

	_ammo_label = Label.new()
	_ammo_label.name = "Ammo"
	_ammo_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_ammo_label.offset_left = -366.0
	_ammo_label.offset_right = -30.0
	_ammo_label.offset_top = -330.0
	_ammo_label.offset_bottom = -296.0
	_ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ammo_label.add_theme_font_size_override("font_size", 26)
	_ammo_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_ammo_label.add_theme_constant_override("outline_size", 8)
	_ammo_label.visible = false
	hud.add_child(_ammo_label)
