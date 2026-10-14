@tool
extends Node3D
## One building of the editable map (world/map/map.tscn). Move, turn, duplicate
## or delete it in the editor; tools/build_world.gd bakes it into the game.
## It always stands on the terrain, however high the node is.

const MapKit := preload("res://world/map/map_kit.gd")

## The outline of the building in metres, around the node's origin (x, z).
@export var footprint := PackedVector2Array([Vector2(-5, -4), Vector2(5, -4), Vector2(5, 4), Vector2(-5, 4)]):
	set(value):
		footprint = value
		_queue_draw()
## From the highest ground under it to the roof, in metres (3 m a storey, plus 0.6).
@export_range(2.0, 40.0, 0.1, "or_greater") var height := 6.6:
	set(value):
		height = value
		_queue_draw()
@export var wall_color := Color(0.82, 0.62, 0.44):
	set(value):
		wall_color = value
		_queue_draw()
@export var roof_color := Color(0.5, 0.26, 0.2):
	set(value):
		roof_color = value
		_queue_draw()
## Plain walls with no windows (sheds, garages).
@export var plain := false:
	set(value):
		plain = value
		_queue_draw()
## Walls of pink tuff blocks instead of plain colour.
@export var tuff := false:
	set(value):
		tuff = value
		_queue_draw()
## Where it came from in OpenStreetMap; 0 for one added by hand.
@export var osm_id := 0

var _preview: MeshInstance3D
var _queued := false


func _ready() -> void:
	set_notify_transform(true)
	_queue_draw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_queue_draw()


## The footprint in world metres (x, z).
func world_footprint() -> PackedVector2Array:
	var out := PackedVector2Array()
	var xf := _world_transform()
	for p in footprint:
		var w := xf * Vector3(p.x, 0.0, p.y)
		out.append(Vector2(w.x, w.z))
	return out


## The node's place in the world, also when it is not in the scene tree (as when
## tools/build_world.gd reads the map).
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
	# Only the editor draws the map piece by piece; the game uses the baked chunks.
	if not Engine.is_editor_hint() or not is_inside_tree() or _queued:
		return
	_queued = true
	_draw_preview.call_deferred()


func _draw_preview() -> void:
	_queued = false
	if _preview == null:
		_preview = MeshInstance3D.new()
		_preview.visibility_range_end = 700.0
		add_child(_preview, false, INTERNAL_MODE_FRONT)
	_preview.mesh = MapKit.building_mesh(world_footprint(), height, wall_color, roof_color, plain, tuff,
		global_transform.affine_inverse())
