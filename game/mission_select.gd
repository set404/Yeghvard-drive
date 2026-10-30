extends CanvasLayer
## For testing: F6 opens a list of the missions (game/mission_manager.gd) with
## the game paused. Click a mission to play it from its start (the ones before
## it count as done), or one of its steps to jump straight to that step. F6 or
## Esc closes it.

const KEY := KEY_F6
const GOLD := Color(1.0, 0.82, 0.3)

@onready var _main: Node3D = get_parent()
var _panel: PanelContainer
var _rows: VBoxContainer
var _was_paused := false
var _previous_mouse := Input.MOUSE_MODE_VISIBLE


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 30
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.custom_minimum_size = Vector2(560.0, 0.0)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.0, 0.0, 0.0, 0.8)
	box.border_color = GOLD
	box.border_width_left = 4
	box.set_corner_radius_all(5)
	box.set_content_margin_all(14.0)
	_panel.add_theme_stylebox_override("panel", box)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0.0, 420.0)
	_panel.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows)
	_panel.visible = false
	add_child(_panel)


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY:
		get_viewport().set_input_as_handled()
		if _panel.visible:
			close()
		else:
			open()
	elif key.physical_keycode == KEY_ESCAPE and _panel.visible:
		get_viewport().set_input_as_handled()
		close()


func open() -> void:
	var missions: MissionManager = _main.get("missions")
	if missions == null or _panel.visible:
		return
	_fill(missions)
	_panel.visible = true
	_was_paused = get_tree().paused
	get_tree().paused = true
	_previous_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	if not _panel.visible:
		return
	_panel.visible = false
	get_tree().paused = _was_paused
	Input.mouse_mode = _previous_mouse


## A row per mission, with a button under it for each of its steps.
func _fill(missions: MissionManager) -> void:
	for child in _rows.get_children():
		child.queue_free()
	var heading := Label.new()
	heading.text = "MISSION SELECT (testing)   F6 / Esc: close"
	heading.add_theme_color_override("font_color", GOLD)
	heading.add_theme_font_size_override("font_size", 18)
	_rows.add_child(heading)
	var list := missions.catalogue()
	for i in list.size():
		var m := list[i]
		var state := ""
		if missions.current and missions.current.id == m.id:
			state = "   (playing, step %d)" % (missions.step + 1)
		elif missions.pending and missions.pending.id == m.id:
			state = "   (waiting to start)"
		elif missions.is_done(m.id):
			state = "   (done)"
		var start := _button("%d. %s%s" % [i + 1, m.title, state], 20)
		start.tooltip_text = m.start_text if m.start_text != "" else "Starts at once"
		start.pressed.connect(_pick.bind(i, -1))
		_rows.add_child(start)
		for s in m.steps.size():
			var b := _button("      step %d: %s" % [s + 1, m.steps[s]["text"]], 16)
			b.pressed.connect(_pick.bind(i, s))
			_rows.add_child(b)
	var reset := _button("Forget every mission done (as the 0 key)", 16)
	reset.pressed.connect(func() -> void:
		missions.reset()
		close())
	_rows.add_child(reset)


func _button(text: String, font_size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.add_theme_font_size_override("font_size", font_size)
	return b


func _pick(index: int, at_step: int) -> void:
	close()
	(_main.get("missions") as MissionManager).select(index, at_step)
