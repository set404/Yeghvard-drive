class_name MissionManager
extends Node
## Runs the missions (game/mission.gd, one file each in res://missions/) one
## after another in the order of MISSIONS. main.gd adds this as "Missions".
##
## It shows what to do next in a panel on the HUD, says the briefing and the
## "mission complete" in a banner across the top of the screen, and marks where
## to go: a beam of light in the world and a marker on the minimap
## (hud/minimap.gd `objective`). Done missions and the step you are on are kept
## in user://missions.cfg; delete it (or call reset(), the 0 key for testing)
## to play them again.

signal mission_started(mission: Mission)
signal mission_completed(mission: Mission)

const SAVE_PATH := "user://missions.cfg"
## The story, in order.
const MISSIONS: Array[String] = [
	"res://missions/dads_errand.gd",
]

const GOLD := Color(1.0, 0.82, 0.3)
const BEAM_HEIGHT := 60.0

## Seconds after the game starts (and after one mission ends) until the next begins.
@export var start_delay := 3.0
## How long a banner stays up, in seconds.
@export var banner_time := 6.0

## The game (main.gd); set before this enters the tree.
var main: Node3D
var current: Mission
var step := -1
## The next mission while it waits for you to start it (its start_text, can_start).
var pending: Mission
var _completed: PackedStringArray = []
var _wait := 0.0
## Saved step to resume at when the first mission is loaded.
var _resume := {}

var _panel: PanelContainer
## The key help (main.gd's HUD/Help), which I hides; the panel moves up into its place.
var _help: Control
var _title_label: Label
var _step_label: Label
var _banner: Label
var _banner_left := 0.0
var _beam: MeshInstance3D
var _beam_material: StandardMaterial3D


func _ready() -> void:
	_load()
	_build_hud()
	_build_beam()
	_wait = start_delay


func _process(delta: float) -> void:
	_tick_banner(delta)
	_place_panel()
	if current == null and pending:
		# Waiting for you to do what starts it (go into the house, say).
		if pending.can_start():
			var m := pending
			pending = null
			_begin(m, 0)
			return
		var at: Variant = pending.start_target()
		_show_target(at)
		_step_label.text = pending.start_text + ("   %s" % _distance_text(pending.distance_to(at)) if at is Vector3 else "")
		return
	if current == null:
		_wait -= delta
		if _wait <= 0.0:
			_start_next()
		_show_target(null)
		return
	var s := current.steps[step]
	if s.has("back_to"):
		var back: int = s["back_to"].call()
		if back >= 0 and back < step:
			if s.has("back_message"):
				show_banner(s["back_message"].call())
			_enter_step(back)
			return
	if s["done"].call():
		if step + 1 < current.steps.size():
			_enter_step(step + 1)
		else:
			_complete()
		return
	var target: Variant = s["target"].call() if s.has("target") else null
	_show_target(target)
	var text: String = s["text"]
	if target is Vector3:
		text += "   %s" % _distance_text(current.distance_to(target))
	_step_label.text = text


## The panel sits under the key help while that shows, in the corner when it is hidden.
func _place_panel() -> void:
	var top := 20.0
	if _help and _help.visible:
		top = _help.position.y + _help.size.y + 16.0
	_panel.position = Vector2(20.0, top)


## Puts up a message across the top of the screen for a few seconds.
func show_banner(text: String) -> void:
	_banner.text = text
	_banner_left = banner_time


## Forgets every mission done and starts again from the first, `delay` seconds on.
func reset(delay := 0.5) -> void:
	_completed.clear()
	current = null
	pending = null
	step = -1
	_resume = {}
	_wait = delay
	_panel.visible = false
	_save()


func _start_next() -> void:
	for path in MISSIONS:
		var m: Mission = (load(path) as GDScript).new()
		m.main = main
		m.build()
		if m.id in _completed or m.steps.is_empty():
			continue
		_title_label.text = m.title.to_upper()
		_panel.visible = true
		# A mission saved part way through carries on from there.
		if _resume.get("id", "") == m.id:
			var resume_at := clampi(int(_resume.get("step", 0)), 0, m.steps.size() - 1)
			_resume = {}
			_begin(m, resume_at)
			return
		_resume = {}
		if m.start_text != "":
			pending = m
			_step_label.text = m.start_text
			return
		_begin(m, 0)
		return
	# Every mission done: wait for more (none yet).
	_wait = INF


## Starts `m` at step `at` (0 with its briefing).
func _begin(m: Mission, at: int) -> void:
	current = m
	_title_label.text = m.title.to_upper()
	_panel.visible = true
	if at == 0 and m.briefing != "":
		show_banner(m.briefing)
	_enter_step(at)
	mission_started.emit(m)


func _enter_step(index: int) -> void:
	step = index
	var s := current.steps[step]
	if s.has("start"):
		s["start"].call()
	_step_label.text = s["text"]
	_save()


func _complete() -> void:
	var m := current
	m.finish()
	current = null
	step = -1
	_completed.append(m.id)
	if m.reward > 0.0:
		main.wallet.earn(m.reward)
		main.wallet.save()
	var lines := PackedStringArray()
	if m.success != "":
		lines.append(m.success)
	lines.append("MISSION COMPLETE: %s" % m.title.to_upper())
	if m.reward > 0.0:
		lines.append("+%s" % Wallet.format(m.reward))
	show_banner("\n".join(lines))
	_panel.visible = false
	_show_target(null)
	_save()
	_wait = start_delay + banner_time
	mission_completed.emit(m)


## Points the beam and the minimap at `target` (a Vector3), or hides them (null).
func _show_target(target: Variant) -> void:
	var minimap: Control = main.minimap
	if not target is Vector3:
		_beam.visible = false
		minimap.set("objective", null)
		return
	var at: Vector3 = target
	minimap.set("objective", at)
	_beam.visible = true
	# The cylinder is centred on its origin: lifted, it stands on the spot.
	_beam.global_position = at + Vector3.UP * BEAM_HEIGHT * 0.5
	# It fades out as you get near, so it is not in your face at the shop counter.
	var m := current if current else pending
	var d := m.distance_to(at) if m else 0.0
	_beam_material.albedo_color.a = clampf((d - 6.0) / 40.0, 0.0, 1.0) * 0.35


static func _distance_text(metres: float) -> String:
	if metres >= 1000.0:
		return "%.1f km" % (metres / 1000.0)
	return "%d m" % roundi(metres)


func _tick_banner(delta: float) -> void:
	if _banner_left <= 0.0:
		_banner.visible = false
		return
	_banner_left -= delta
	_banner.visible = true
	# Fades in over the first half second and out over the last.
	_banner.modulate.a = clampf(minf(banner_time - _banner_left, _banner_left) * 2.0, 0.0, 1.0)


func _load() -> void:
	var file := ConfigFile.new()
	if file.load(SAVE_PATH) != OK:
		return
	_completed = PackedStringArray(file.get_value("missions", "completed", []))
	var id: String = file.get_value("missions", "current", "")
	if id != "":
		_resume = {"id": id, "step": file.get_value("missions", "step", 0)}


func _save() -> void:
	var file := ConfigFile.new()
	file.set_value("missions", "completed", Array(_completed))
	file.set_value("missions", "current", current.id if current else "")
	file.set_value("missions", "step", maxi(step, 0))
	file.save(SAVE_PATH)


func _build_hud() -> void:
	var hud: CanvasLayer = main.get_node("HUD")
	# The objective panel, top left: under the key help while it shows (see _place_panel).
	_help = main.get_node_or_null("HUD/Help") as Control
	_panel = PanelContainer.new()
	_panel.name = "Mission"
	_panel.position = Vector2(20.0, 150.0)
	_panel.custom_minimum_size = Vector2(420.0, 0.0)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.0, 0.0, 0.0, 0.55)
	box.border_color = GOLD
	box.border_width_left = 4
	box.set_corner_radius_all(5)
	box.set_content_margin_all(10.0)
	box.content_margin_left = 14.0
	_panel.add_theme_stylebox_override("panel", box)
	_panel.visible = false
	var rows := VBoxContainer.new()
	_panel.add_child(rows)
	_title_label = Label.new()
	_title_label.add_theme_color_override("font_color", GOLD)
	_title_label.add_theme_font_size_override("font_size", 18)
	rows.add_child(_title_label)
	_step_label = Label.new()
	_step_label.add_theme_font_size_override("font_size", 22)
	_step_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_step_label.custom_minimum_size = Vector2(392.0, 0.0)
	rows.add_child(_step_label)
	hud.add_child(_panel)
	# The banner, across the top middle.
	_banner = Label.new()
	_banner.name = "MissionBanner"
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.offset_left = -520.0
	_banner.offset_right = 520.0
	_banner.offset_top = 130.0
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner.add_theme_font_size_override("font_size", 30)
	_banner.add_theme_color_override("font_color", Color(1.0, 0.95, 0.8))
	_banner.add_theme_color_override("font_outline_color", Color.BLACK)
	_banner.add_theme_constant_override("outline_size", 10)
	_banner.visible = false
	hud.add_child(_banner)


## A tall glowing column standing on the objective, seen from far off.
func _build_beam() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.7
	mesh.bottom_radius = 0.7
	mesh.height = BEAM_HEIGHT
	mesh.cap_top = false
	mesh.cap_bottom = false
	_beam_material = StandardMaterial3D.new()
	_beam_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beam_material.albedo_color = Color(GOLD, 0.35)
	mesh.material = _beam_material
	_beam = MeshInstance3D.new()
	_beam.name = "MissionBeam"
	_beam.mesh = mesh
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.visible = false
	add_child(_beam)
