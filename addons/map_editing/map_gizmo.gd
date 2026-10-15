@tool
extends EditorNode3DGizmoPlugin
## An invisible gizmo for each building and wall of the editable map, with the
## shape of its preview, so clicking the building or wall selects it.

const MAP_BUILDING := preload("res://world/map/map_building.gd")
const MAP_WALL := preload("res://world/map/map_wall.gd")


func _get_gizmo_name() -> String:
	return "MapPiece"


func _has_gizmo(node: Node3D) -> bool:
	var script: Script = node.get_script()
	return script == MAP_BUILDING or script == MAP_WALL


func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var mesh: Mesh = gizmo.get_node_3d().preview_mesh()
	if mesh:
		gizmo.add_collision_triangles(mesh.generate_triangle_mesh())
