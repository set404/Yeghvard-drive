@tool
extends EditorPlugin
## The editor picks what you click in the 3D viewport by its gizmo. The map's
## buildings and walls draw themselves with an internal mesh that gets none, so
## this gives them one shaped like that mesh.

const MapGizmo := preload("res://addons/map_editing/map_gizmo.gd")

var _gizmo := MapGizmo.new()


func _enter_tree() -> void:
	add_node_3d_gizmo_plugin(_gizmo)


func _exit_tree() -> void:
	remove_node_3d_gizmo_plugin(_gizmo)
