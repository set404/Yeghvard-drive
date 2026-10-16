extends Node
## The title screen. Loads the world behind it with the game paused and a camera
## slowly panning towards Ararat; Play hands control over to main.tscn.
## In game, Esc brings the same menu back as a pause menu.

const Settings := preload("res://menu/settings.gd")

## Where the background camera stands (on the main road west of town) and the
## bearings, in degrees from north, it pans between.
const VIEW_POS := Vector3(-646.6, -9.5, 847.1)
const PAN_FROM := 175.0
const PAN_TO := 215.0
## Seconds for one sweep across.
const PAN_TIME := 40.0

const CREAM := Color(1, 0.97, 0.9)
const GOLD := Color(1, 0.85, 0.45)
const NAVY := Color(0.05, 0.08, 0.18)

var settings := Settings.new()
var main: Node3D
var view_camera: Camera3D
var layer: CanvasLayer
var buttons: VBoxContainer
## Resume, Options... shown in place of buttons while paused in game.
var pause_buttons: VBoxContainer
## Darkens the whole game behind the pause menu.
var dim: ColorRect
var subtitle: Label
var controls: PanelContainer
var options: PanelContainer
## The title block, hidden while a panel is open to make room.
var heading: Array[Control] = []
## Option name -> the control showing it, so a preset can refresh them all.
var option_widgets := {}
var title_font := SystemFont.new()
var text_font := SystemFont.new()
var pan_t := 0.0
var started := false
## True while Play is fading into the game, so Esc waits for it.
var fading := false
var in_pause := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	main = load("res://main.tscn").instantiate()
	# The menu runs while paused; the world under it must not inherit that, or
	# the chase camera grabs the mouse on the first click outside a button.
	main.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(main)
	main.get_node("HUD").visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	settings.load_file()
	settings.apply_window()
	settings.apply_graphics(get_viewport(), main)

	view_camera = Camera3D.new()
	view_camera.far = 20000.0
	view_camera.fov = 55.0
	add_child(view_camera)
	title_font.font_names = PackedStringArray(["Arial Black", "Impact", "Arial"])
	title_font.font_weight = 900
	text_font.font_names = PackedStringArray(["Segoe UI", "Arial"])
	text_font.font_weight = 600
	_build_ui()
	# Let main.gd set the cars down on the ground before the world stops.
	for i in 3:
		await get_tree().physics_frame
	if not started:
		get_tree().paused = true


func _process(delta: float) -> void:
	if started:
		return
	# main.gd hands the camera to the car once it is set up; keep ours in front.
	view_camera.make_current()
	pan_t += delta
	var k := 0.5 - 0.5 * cos(pan_t / PAN_TIME * PI)
	var az := deg_to_rad(lerpf(PAN_FROM, PAN_TO, k))
	view_camera.global_position = VIEW_POS
	view_camera.look_at(VIEW_POS + Vector3(sin(az), -0.06, -cos(az)))


## Esc closes an open panel; in game it pauses and resumes. Handled here, before
## the chase camera, which would otherwise let go of the mouse on Esc.
func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.physical_keycode != KEY_ESCAPE or fading:
		return
	if controls.visible or options.visible:
		_show_panel(null)
	elif in_pause:
		_resume()
	elif started:
		_pause()
	else:
		return
	get_viewport().set_input_as_handled()


func _play() -> void:
	if started:
		return
	started = true
	fading = true
	var tween := create_tween()
	tween.tween_property(layer.get_node("Fade"), "modulate:a", 1.0, 0.35)
	await tween.finished
	get_tree().paused = false
	main.get_node("HUD").visible = true
	var cam: Camera3D = main.get("camera")
	if cam:
		cam.make_current()
	view_camera.queue_free()
	# From here on the menu is the pause menu.
	buttons.visible = false
	pause_buttons.visible = true
	# The pause menu has an extra button, so a heading replaces the big title.
	heading[0].visible = false
	heading.remove_at(0)
	subtitle.text = "PAUSED"
	subtitle.add_theme_font_override("font", title_font)
	subtitle.add_theme_font_size_override("font_size", 52)
	subtitle.add_theme_color_override("font_color", CREAM)
	subtitle.add_theme_color_override("font_outline_color", NAVY)
	subtitle.add_theme_constant_override("outline_size", 12)
	tween = create_tween()
	tween.tween_property(layer.get_node("Fade"), "modulate:a", 0.0, 0.5)
	await tween.finished
	layer.visible = false
	fading = false


func _pause() -> void:
	in_pause = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	main.get_node("HUD").visible = false
	dim.visible = true
	layer.visible = true
	_show_panel(null)


func _resume() -> void:
	_show_panel(null)
	in_pause = false
	layer.visible = false
	dim.visible = false
	main.get_node("HUD").visible = true
	get_tree().paused = false


## Back to the title screen: reloads the menu and the world from scratch.
func _to_title() -> void:
	settings.save_file()
	get_tree().paused = false
	get_tree().reload_current_scene()


## Opens one of the panels in place of the main buttons, or goes back with null.
func _show_panel(panel: PanelContainer) -> void:
	if options.visible and panel != options:
		settings.save_file()
	controls.visible = panel == controls
	options.visible = panel == options
	for c in heading:
		c.visible = panel == null
	var list := pause_buttons if started else buttons
	list.visible = panel == null
	if panel:
		panel.get_node("Box/Back").grab_focus()
	else:
		list.get_child(0).grab_focus()


func _build_ui() -> void:
	layer = CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	dim = ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.05, 0.55)
	dim.visible = false
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)

	# Darken the left side so the menu reads over the world.
	var grad := Gradient.new()
	grad.set_color(0, Color(0.02, 0.04, 0.1, 0.8))
	grad.set_color(1, Color(0.02, 0.04, 0.1, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_to = Vector2(1, 0)
	var shade := TextureRect.new()
	shade.texture = tex
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	shade.offset_right = 760
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(shade)

	var root := MarginContainer.new()
	root.theme = _menu_theme()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "bottom"]:
		root.add_theme_constant_override("margin_" + side, 72)
	layer.add_child(root)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 10)
	column.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	root.add_child(column)

	var title := Label.new()
	title.text = "YEGHVARD\nDRIVE"
	title.add_theme_font_override("font", title_font)
	title.add_theme_font_size_override("font_size", 76)
	title.add_theme_constant_override("line_spacing", -18)
	title.add_theme_color_override("font_color", CREAM)
	title.add_theme_color_override("font_outline_color", NAVY)
	title.add_theme_constant_override("outline_size", 14)
	column.add_child(title)
	var sub := Label.new()
	sub.text = "Drive the streets of Yeghvard, Armenia"
	sub.add_theme_font_override("font", text_font)
	sub.add_theme_font_size_override("font_size", 24)
	sub.add_theme_color_override("font_color", GOLD)
	column.add_child(sub)
	var gap := Control.new()
	gap.custom_minimum_size.y = 28
	column.add_child(gap)
	heading = [title, sub, gap]
	subtitle = sub

	controls = _build_controls()
	options = _build_options()
	buttons = _button_list(column, [["Play", _play], ["Options", _show_panel.bind(options)],
			["Controls", _show_panel.bind(controls)], ["Quit", get_tree().quit]])
	pause_buttons = _button_list(column, [["Resume", _resume], ["Options", _show_panel.bind(options)],
			["Controls", _show_panel.bind(controls)], ["Main menu", _to_title], ["Quit", get_tree().quit]])
	pause_buttons.visible = false
	column.add_child(controls)
	column.add_child(options)

	var fade := ColorRect.new()
	fade.name = "Fade"
	fade.color = Color.BLACK
	fade.modulate.a = 0.0
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(fade)

	buttons.get_child(0).grab_focus()


func _button_list(parent: Control, entries: Array) -> VBoxContainer:
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	parent.add_child(list)
	for entry in entries:
		list.add_child(_button(entry[0], entry[1]))
	return list


## A hidden panel with a VBox named Box inside, ending in a Back button.
func _panel(heading_text: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.05, 0.12, 0.85)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	var label := Label.new()
	label.text = heading_text
	label.add_theme_font_override("font", title_font)
	label.add_theme_font_size_override("font_size", 30)
	label.add_theme_color_override("font_color", GOLD)
	box.add_child(label)
	return panel


func _add_back(panel: PanelContainer) -> void:
	var back := _button("Back", _show_panel.bind(null))
	back.name = "Back"
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	panel.get_node("Box").add_child(back)


func _build_controls() -> PanelContainer:
	var panel := _panel("CONTROLS")
	# One control per cell, from the help text the HUD shows in game.
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 6)
	panel.get_node("Box").add_child(grid)
	var help_text: String = main.get_node("HUD/Help").text
	for line in help_text.split("\n", false):
		# The 1-5 car keys are for testing; leave them out of the menu.
		if line.begins_with("1-5"):
			continue
		for entry in line.split("   ", false):
			grid.add_child(_label(entry.strip_edges(), 17))
	_add_back(panel)
	return panel


func _build_options() -> PanelContainer:
	var panel := _panel("OPTIONS")
	var sides := HBoxContainer.new()
	sides.add_theme_constant_override("separation", 56)
	panel.get_node("Box").add_child(sides)
	var left := _option_grid(sides)
	var right := _option_grid(sides)

	_section(left, "Display")
	_option_choice(left, "Window", "fullscreen", ["Windowed", "Fullscreen"], false)
	_option_check(left, "V-Sync", "vsync", false)
	_option_choice(left, "Frame rate limit", "max_fps", Settings.FPS_NAMES, false)
	_section(left, "Sound")
	_option_slider(left, "Volume", "volume", 0.0, 1.0, 0.05, false)
	_section(right, "Graphics")
	_option_choice(right, "Quality", "quality", Settings.QUALITY_NAMES, false)
	_option_slider(right, "Render scale", "render_scale", 0.5, 1.0, 0.05, true)
	_option_choice(right, "Anti-aliasing", "aa", Settings.AA_NAMES, true)
	_option_choice(right, "Shadows", "shadows", Settings.SHADOW_NAMES, true)
	_option_check(right, "Ambient occlusion", "ssao", true)
	_option_check(right, "Indirect lighting", "ssil", true)
	_option_check(right, "Glow", "glow", true)
	_refresh_options()
	_add_back(panel)
	return panel


func _option_grid(parent: Control) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 8)
	parent.add_child(grid)
	return grid


func _section(grid: GridContainer, text: String) -> void:
	var label := _label(text, 20)
	label.add_theme_color_override("font_color", GOLD)
	grid.add_child(label)
	grid.add_child(Control.new())


func _option_choice(grid: GridContainer, text: String, key: String, names: Array, graphics: bool) -> void:
	grid.add_child(_label(text, 18))
	var pick := OptionButton.new()
	for n in names:
		pick.add_item(n)
	if key == "quality":
		# Custom only comes from changing a single graphics option.
		pick.set_item_disabled(Settings.CUSTOM, true)
	pick.custom_minimum_size = Vector2(220, 40)
	pick.item_selected.connect(func(i: int) -> void:
		if key == "quality":
			settings.use_preset(i)
		else:
			settings.set(key, i == 1 if key == "fullscreen" else i)
		_changed(graphics))
	option_widgets[key] = pick
	grid.add_child(pick)


func _option_check(grid: GridContainer, text: String, key: String, graphics: bool) -> void:
	grid.add_child(_label(text, 18))
	var check := CheckButton.new()
	check.toggled.connect(func(on: bool) -> void:
		settings.set(key, on)
		_changed(graphics))
	option_widgets[key] = check
	grid.add_child(check)


func _option_slider(grid: GridContainer, text: String, key: String, lo: float, hi: float, step: float, graphics: bool) -> void:
	grid.add_child(_label(text, 18))
	var row := HBoxContainer.new()
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.custom_minimum_size.x = 160
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var value := _label("", 18)
	value.custom_minimum_size.x = 56
	slider.value_changed.connect(func(v: float) -> void:
		value.text = "%d%%" % roundi(v * 100.0)
		settings.set(key, v)
		_changed(graphics))
	row.add_child(slider)
	row.add_child(value)
	option_widgets[key] = slider
	grid.add_child(row)


## Any single graphics change leaves the preset behind.
func _changed(graphics: bool) -> void:
	if graphics:
		settings.quality = Settings.CUSTOM
	settings.apply_window()
	settings.apply_graphics(get_viewport(), main)
	_refresh_options()


## Shows the current settings in every option control without re-triggering them.
func _refresh_options() -> void:
	for key in option_widgets:
		var w: Control = option_widgets[key]
		var v = settings.get(key)
		w.set_block_signals(true)
		if w is OptionButton:
			w.select(int(v) if not v is bool else int(v))
		elif w is CheckButton:
			w.button_pressed = v
		elif w is HSlider:
			w.value = v
			(w.get_parent().get_child(1) as Label).text = "%d%%" % roundi(v * 100.0)
		w.set_block_signals(false)


func _label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", text_font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", CREAM)
	return label


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(300, 54)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 26)
	b.pressed.connect(action)
	return b


func _box(bg: Color, border: Color, border_width := 2) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_width)
	s.set_corner_radius_all(8)
	s.content_margin_left = 22
	s.content_margin_right = 16
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s


## One look for every control in the menu: solid navy boxes, gold when hovered
## or pressed, and a gold outline for keyboard focus.
func _menu_theme() -> Theme:
	var t := Theme.new()
	t.default_font = text_font
	t.default_font_size = 18
	var panel_navy := Color(0.07, 0.1, 0.2, 0.96)
	var edge := Color(1, 1, 1, 0.14)
	var lift := Color(0.13, 0.18, 0.33, 0.98)
	var focus := _box(Color.TRANSPARENT, GOLD, 3)
	focus.draw_center = false
	focus.set_expand_margin_all(2)

	for type in ["Button", "OptionButton"]:
		t.set_stylebox("normal", type, _box(panel_navy, edge))
		t.set_stylebox("disabled", type, _box(Color(panel_navy, 0.5), edge))
		t.set_stylebox("focus", type, focus)
		t.set_color("font_color", type, CREAM)
		t.set_color("font_focus_color", type, CREAM)
	# Menu buttons go gold; dropdowns only lighten, so their arrow stays visible.
	t.set_stylebox("hover", "Button", _box(GOLD, GOLD))
	t.set_stylebox("pressed", "Button", _box(GOLD.darkened(0.15), GOLD.darkened(0.15)))
	t.set_stylebox("hover_pressed", "Button", _box(GOLD, GOLD))
	for state in ["hover", "pressed", "hover_pressed"]:
		t.set_color("font_%s_color" % state, "Button", NAVY)
	t.set_stylebox("hover", "OptionButton", _box(lift, GOLD))
	t.set_stylebox("pressed", "OptionButton", _box(lift, GOLD))
	for state in ["hover", "pressed", "hover_pressed"]:
		t.set_color("font_%s_color" % state, "OptionButton", CREAM)

	var popup := _box(panel_navy, edge)
	popup.set_content_margin_all(6)
	t.set_stylebox("panel", "PopupMenu", popup)
	var popup_hover := _box(GOLD, GOLD, 0)
	popup_hover.set_corner_radius_all(4)
	t.set_stylebox("hover", "PopupMenu", popup_hover)
	t.set_color("font_color", "PopupMenu", CREAM)
	t.set_color("font_hover_color", "PopupMenu", NAVY)
	t.set_color("font_disabled_color", "PopupMenu", Color(CREAM, 0.35))
	t.set_constant("v_separation", "PopupMenu", 10)

	# Toggles: no box behind them, just the switch.
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		t.set_stylebox(state, "CheckButton", StyleBoxEmpty.new())
	t.set_stylebox("focus", "CheckButton", focus)

	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.18)
	track.set_corner_radius_all(3)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	var filled := track.duplicate()
	filled.bg_color = GOLD
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", filled)
	t.set_stylebox("grabber_area_highlight", "HSlider", filled)
	t.set_stylebox("focus", "HSlider", StyleBoxEmpty.new())
	return t
