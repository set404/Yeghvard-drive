extends Node3D
## Vazgen, who sells what is not sold in shops, behind the supermarket. He is
## one of the townspeople's figures standing about, and a shop stand like the
## cashier (the "shop_stands" group, main.gd's E to buy): his first sale is a
## pistol (with a box of rounds thrown in), after that rounds. Put him anywhere
## in main.tscn; he stands on the ground under where he is put, facing his +Z.

## What the pistol and a box of rounds cost (drams) and how many rounds a box holds.
@export var pistol_price := 45000.0
@export var ammo_price := 2500.0
@export var ammo_box := 16
## How close you stand to him to buy (metres).
@export var reach := 1.8
@export var verb := "buy"

## main.gd reads these when you buy: what he has for you now.
var item_id: String:
	get:
		return "ammo" if _has_pistol() else "pistol"
var price: float:
	get:
		return ammo_price if _has_pistol() else pistol_price
var amount: int:
	get:
		return ammo_box if _has_pistol() else 1
var item_name: String:
	get:
		return "box of %d rounds" % ammo_box if _has_pistol() else "Makarov pistol"

var _figure: Node3D
var _anim: AnimationPlayer
var _greeted := false


func _enter_tree() -> void:
	add_to_group("shop_stands")


func _ready() -> void:
	var town := get_parent().get_node_or_null("Townsfolk")
	var figures: Array[String] = []
	for file in DirAccess.get_files_at("res://npc"):
		file = file.trim_suffix(".remap")
		if file.get_extension() == "scn":
			figures.append("res://npc/" + file)
	figures.sort()
	if not figures.is_empty():
		# Always the same one, so he is recognisable: the last of them.
		_figure = (load(figures[figures.size() - 1]) as PackedScene).instantiate()
		add_child(_figure)
		_anim = _figure.get_node_or_null("AnimationPlayer")
		_idle()
	elif town == null:
		push_warning("No figures in res://npc: the dealer is invisible")
	_stand_on_ground.call_deferred()


func shopper_distance(who: Node3D) -> float:
	return Vector2(who.global_position.x - global_position.x, who.global_position.z - global_position.z).length()


func in_reach(who: Node3D) -> bool:
	return shopper_distance(who) < reach


func sold_out() -> bool:
	return false


## He hands it over (talking); the pistol comes with a box of rounds.
func take(_near: Vector3) -> bool:
	var main := get_parent()
	if not _has_pistol():
		var inv: Node = main.get("inventory")
		if inv:
			inv.add.call_deferred("ammo", ammo_box)
		var missions = main.get("missions")
		if missions:
			missions.show_banner("Vazgen: \"You didn't get it from me, understood?\"\nLeft click to shoot, hold right click to aim, R to reload.")
	if _anim and _anim.has_animation("talk"):
		_anim.play("talk", 0.3)
		get_tree().create_timer(3.0).timeout.connect(_idle)
	return true


func _process(_delta: float) -> void:
	# A word when you come close the first time.
	var main := get_parent()
	var player: Node3D = main.get("player")
	if _greeted or player == null or not main.get("on_foot"):
		return
	if shopper_distance(player) < 4.0:
		_greeted = true
		var missions = main.get("missions")
		if missions:
			missions.show_banner("Vazgen: \"Psst, akhper. Looking for something special?\"")


func _has_pistol() -> bool:
	var inv: Node = get_parent().get("inventory")
	return inv != null and inv.count_of("pistol") > 0


func _idle() -> void:
	if _anim == null:
		return
	var want := "phone" if _anim.has_animation("phone") else "idle"
	if _anim.has_animation(want):
		_anim.play(want, 0.4)
	var phone := _figure.get_node_or_null("Skeleton3D/RightHand/Phone") as Node3D
	if phone:
		phone.visible = want == "phone"


func _stand_on_ground() -> void:
	await get_tree().physics_frame
	var p := global_position
	var ray := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 3.0, p + Vector3.DOWN * 50.0)
	ray.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if hit:
		global_position.y = (hit["position"] as Vector3).y
