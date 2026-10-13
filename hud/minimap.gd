extends Control
## North-up minimap centred on the target, with an arrow showing its heading.
## Other cars (nodes in the "cars" group) show as dots.
## M switches between the close view and a wide overview.

const ARROW := [Vector2(0, -10), Vector2(7, 8), Vector2(0, 4), Vector2(-7, 8)]

@export var target: Node3D
@export var map: Texture2D
@export var view_radius := 250.0 ## metres from the centre to the edge
@export var wide_radius := 1200.0

var _wide := false


func _ready() -> void:
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if map == null:
		map = load("res://world/minimap.res")


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.physical_keycode == KEY_M:
		_wide = not _wide


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.25, 0.24, 0.22))
	if map == null or target == null:
		return
	var world_size: float = map.get_meta("world_size", 4608.0)
	var px_per_m := size.x * 0.5 / (wide_radius if _wide else view_radius)
	var centre := size * 0.5
	var pos := Vector2(target.global_position.x, target.global_position.z)
	# The map covers the world square centred on the origin, north (-Z) up.
	var corner := centre - (pos + Vector2.ONE * world_size * 0.5) * px_per_m
	draw_texture_rect(map, Rect2(corner, Vector2.ONE * world_size * px_per_m), false)

	for other: Node3D in get_tree().get_nodes_in_group("cars"):
		if other == target:
			continue
		var at := centre + (Vector2(other.global_position.x, other.global_position.z) - pos) * px_per_m
		draw_circle(at, 5.0, Color.WHITE)
		draw_circle(at, 3.5, Color(0.15, 0.4, 0.9))

	var nose := target.global_basis.z
	draw_set_transform(centre, atan2(nose.x, -nose.z))
	draw_colored_polygon(PackedVector2Array(ARROW), Color(0.86, 0.12, 0.10))
	draw_polyline(PackedVector2Array(ARROW + [ARROW[0]]), Color.WHITE, 1.5, true)
	draw_set_transform(Vector2.ZERO)

	var font := ThemeDB.fallback_font
	draw_string_outline(font, Vector2(size.x * 0.5 - 5, 18), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, Color.WHITE)
	draw_string(font, Vector2(size.x * 0.5 - 5, 18), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.15, 0.15, 0.15))
	draw_rect(Rect2(Vector2.ONE, size - Vector2.ONE * 2.0), Color(0.1, 0.1, 0.1, 0.9), false, 2.0)
