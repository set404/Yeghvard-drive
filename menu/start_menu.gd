extends Node
## The title screen. Loads the world behind it with the game paused and a camera
## slowly panning towards Ararat; Play hands control over to main.tscn.

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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	main = load("res://main.tscn").instantiate()
	add_child(main)
	get_tree().paused = true
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


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if started or key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_ESCAPE and not buttons.visible:
		_show_panel(null)
		get_viewport().set_input_as_handled()


func _play() -> void:
	if started:
		return
	started = true
	var tween := create_tween()
	tween.tween_property(layer.get_node("Fade"), "modulate:a", 1.0, 0.35)
	await tween.finished
	get_tree().paused = false
	main.get_node("HUD").visible = true
	var cam: Camera3D = main.get("camera")
	if cam:
		cam.make_current()
	view_camera.queue_free()
	tween = create_tween()
	tween.tween_property(layer.get_node("Fade"), "modulate:a", 0.0, 0.5)
	await tween.finished
	layer.queue_free()


## Opens one of the panels in place of the main buttons, or goes back with null.
func _show_panel(panel: PanelContainer) -> void:
	if options.visible and panel != options:
		settings.save_file()
	controls.visible = panel == controls
	options.visible = panel == options
	for c in heading:
		c.visible = panel == null
	buttons.visible = panel == null
	if panel:
		panel.get_node("Box/Back").grab_focus()
	else:
		buttons.get_child(0).grab_focus()


func _build_ui() -> void:
	layer = CanvasLayer.new()
	layer.layer = 10
	add_child(layer)

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

	buttons = VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	column.add_child(buttons)
	controls = _build_controls()
	options = _build_options()
	for entry in [["Play", _play], ["Options", _show_panel.bind(options)],
			["Controls", _show_panel.bind(controls)], ["Quit", get_tree().quit]]:
		buttons.add_child(_button(entry[0], entry[1]))
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
	pick.custom_minimum_size.x = 220
	pick.add_theme_font_override("font", text_font)
	pick.add_theme_font_size_override("font_size", 18)
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
	b.custom_minimum_size = Vector2(260, 52)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_override("font", text_font)
	b.add_theme_font_size_override("font_size", 26)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(1, 1, 1, 0.08)
	normal.set_corner_radius_all(6)
	normal.content_margin_left = 20
	var hover := normal.duplicate()
	hover.bg_color = Color(GOLD, 0.9)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("focus", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_color_override("font_color", CREAM)
	for state in ["hover", "focus", "pressed"]:
		b.add_theme_color_override("font_%s_color" % state, NAVY)
	b.pressed.connect(action)
	return b
