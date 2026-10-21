extends Control
## The inventory (game/inventory.gd) in the top right corner of the HUD: a row
## of slots, each with a picture of its item and how many you have, the one in
## your hand framed in gold and named underneath. Hidden while it is empty.
## The first slot is your empty hand (game/inventory.gd), shown as a hand.
## main.gd adds it to the HUD and sets `inventory`.

const SLOT := 68.0
const GAP := 6.0
const GOLD := Color(1, 0.85, 0.45)
const ICON_SIZE := 128
const EMPTY_HAND_ICON := "res://hud/empty_hand.png"

var inventory: Inventory:
	set(value):
		inventory = value
		inventory.changed.connect(_refresh)
		_refresh()

var _row: HBoxContainer
var _name: Label
## Item id -> a picture of its model, rendered once.
var _icons := {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -(SLOT + GAP) * (Inventory.MAX_SLOTS + Inventory.COMBOS.size() + 1) - 24.0
	offset_right = -24.0
	offset_top = 20.0
	offset_bottom = 20.0 + SLOT + 40.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_row = HBoxContainer.new()
	_row.alignment = BoxContainer.ALIGNMENT_END
	_row.add_theme_constant_override("separation", GAP)
	_row.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_row.offset_bottom = SLOT
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_row)
	_name = Label.new()
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_name.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_name.offset_top = SLOT + 4.0
	_name.offset_bottom = SLOT + 36.0
	_name.add_theme_font_size_override("font_size", 20)
	_name.add_theme_color_override("font_color", GOLD)
	_name.add_theme_color_override("font_outline_color", Color.BLACK)
	_name.add_theme_constant_override("outline_size", 6)
	add_child(_name)


func _refresh() -> void:
	if _row == null or inventory == null:
		return
	for child in _row.get_children():
		child.queue_free()
	# The stacks, then a slot for each pair you can use together (cigarette + coffee).
	var all := inventory.entries()
	visible = not all.is_empty()
	for k in all.size():
		var slot: Dictionary = all[k]
		_row.add_child(_slot(slot["id"], slot["count"], k == inventory.selected))
	var id := inventory.selected_id()
	_name.text = "%s  (wheel to switch)" % Inventory.item_name(id) if all.size() > 1 else Inventory.item_name(id)


func _slot(id: String, count: int, chosen: bool) -> Control:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(SLOT, SLOT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0.6 if chosen else 0.4)
	box.border_color = GOLD if chosen else Color(1, 1, 1, 0.25)
	box.set_border_width_all(3 if chosen else 1)
	box.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", box)
	var icon := TextureRect.new()
	icon.texture = _icon(id)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 6)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(icon)
	if count > 1:
		var n := Label.new()
		n.text = str(count)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		n.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		n.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 4)
		n.add_theme_font_size_override("font_size", 18)
		n.add_theme_color_override("font_outline_color", Color.BLACK)
		n.add_theme_constant_override("outline_size", 6)
		panel.add_child(n)
	return panel


## A picture of the item's model: rendered in a little world of its own,
## framed to fit, once.
func _icon(id: String) -> Texture2D:
	if _icons.has(id):
		return _icons[id]
	if id == Inventory.EMPTY_HAND:
		_icons[id] = _empty_hand_icon()
		return _icons[id]
	var view := SubViewport.new()
	view.size = Vector2i(ICON_SIZE, ICON_SIZE)
	view.own_world_3d = true
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(view)
	var scene_path: String = (Inventory.COMBOS[id] if Inventory.COMBOS.has(id) else Inventory.ITEMS[id])["scene"]
	var model: Node3D = (load(scene_path) as PackedScene).instantiate()
	view.add_child(model)
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = mi.global_transform * mi.mesh.get_aabb() if mi.is_inside_tree() else mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	var centre := box.get_center()
	var radius := box.size.length() * 0.5
	var cam := Camera3D.new()
	cam.fov = 30.0
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.6
	cam.environment = env
	view.add_child(cam)
	var dir := Vector3(0.0, 0.35, 1.0).normalized()
	cam.look_at_from_position(centre + dir * radius / sin(deg_to_rad(cam.fov * 0.5)), centre)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.4
	view.add_child(sun)
	sun.look_at_from_position(centre + Vector3(1.0, 2.0, 2.0), centre)
	_icons[id] = view.get_texture()
	return _icons[id]


static func _empty_hand_icon() -> Texture2D:
	if ResourceLoader.exists(EMPTY_HAND_ICON):
		return load(EMPTY_HAND_ICON)
	# Not imported yet (before the editor has seen it).
	var img := Image.load_from_file(EMPTY_HAND_ICON)
	return ImageTexture.create_from_image(img) if img and not img.is_empty() else null
