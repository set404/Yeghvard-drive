@tool
extends Path3D
## One wall of the editable map (world/map/map.tscn): it runs straight from each
## point of the curve to the next. Drag, add or delete points with the editor's
## curve tools; the height of the points does not matter, the wall always
## stands on the terrain. tools/build_world.gd bakes it into the game.

const MapKit := preload("res://world/map/map_kit.gd")

@export var kind: MapKit.Kind = MapKit.Kind.STONE:
	set(value):
		kind = value
		_queue_draw()
## The stone, or the paint of a sheet fence.
@export var color := Color(0.82, 0.62, 0.44):
	set(value):
		color = value
		_queue_draw()
@export_range(0.5, 5.0, 0.05) var height := 2.0:
	set(value):
		height = value
		_queue_draw()
## Where the gate is, in metres along the wall from its first point; -1 for none.
@export var gate_at := -1.0:
	set(value):
		gate_at = value
		_queue_draw()
@export var gate_color := Color(0.24, 0.40, 0.30):
	set(value):
		gate_color = value
		_queue_draw()
## Fixed: the gate is a shut sheet. Otherwise its two leaves swing open (G) to that
## side, looking along the wall from its first point.
@export_enum("Fixed", "Left", "Right") var gate_swing := 0

var _preview: MeshInstance3D
var _queued := false


func _ready() -> void:
	set_notify_transform(true)
	if curve == null:
		curve = Curve3D.new()
	if not curve.changed.is_connected(_queue_draw):
		curve.changed.connect(_queue_draw)
	_queue_draw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_queue_draw()


## The corners of the wall in world metres (x, z).
func world_points() -> PackedVector2Array:
	var out := PackedVector2Array()
	if curve == null:
		return out
	var xf := _world_transform()
	for i in curve.point_count:
		var w := xf * curve.get_point_position(i)
		out.append(Vector2(w.x, w.z))
	return out


func _world_transform() -> Transform3D:
	if is_inside_tree():
		return global_transform
	var xf := transform
	var p := get_parent() as Node3D
	while p:
		xf = p.transform * xf
		p = p.get_parent() as Node3D
	return xf


func _queue_draw() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree() or _queued:
		return
	_queued = true
	_draw_preview.call_deferred()


func _draw_preview() -> void:
	_queued = false
	_keep_on_ground()
	if _preview == null:
		_preview = MeshInstance3D.new()
		_preview.visibility_range_end = 500.0
		add_child(_preview, false, INTERNAL_MODE_FRONT)
	_preview.mesh = MapKit.wall_mesh(world_points(), kind, color, height, gate_at, gate_color,
		global_transform.affine_inverse())
	# Clicking it in the viewport hits its gizmo (addons/map_editing), which takes its shape from this mesh.
	update_gizmos()


## Puts the node (its first point) on the ground there, so its move handles and
## curve are where the wall stands rather than deep underground. Only x and z
## count for the wall itself.
func _keep_on_ground() -> void:
	var ground := MapKit.height_at(global_position.x, global_position.z)
	if absf(global_position.y - ground) > 0.05:
		global_position.y = ground


## The editor's preview of it, in its own space; null outside the editor.
func preview_mesh() -> Mesh:
	return _preview.mesh if _preview else null
