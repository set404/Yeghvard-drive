@tool
class_name Crosswalk
extends Node3D
## A zebra crossing over a road: the only place the townspeople cross the main
## road (world/townsfolk.gd links the sidewalks at its two ends). People
## walking past it cross some of the time and wait at the kerb for the cars.
##
## To add one: put a Crosswalk node (a Node3D with this script) under
## Crosswalks in main.tscn, its origin in the middle of the road, its +Z
## pointing across from one kerb to the other (the blue arrow), and set
## `length` to the road's width from kerb to kerb. The ends have to be within
## `reach` of a sidewalk on each side. The stripes follow the road's surface
## once the game runs (in the editor they are drawn flat at the node's height).

## Across the road, kerb to kerb, and along it (metres).
@export var length := 12.0:
	set(value):
		length = maxf(value, 1.0)
		_rebuild()
@export var width := 3.0:
	set(value):
		width = maxf(value, 0.5)
		_rebuild()
## The white bars and the gaps between them, across the road (metres).
@export var stripe := 0.5:
	set(value):
		stripe = maxf(value, 0.1)
		_rebuild()
@export var gap := 0.5:
	set(value):
		gap = maxf(value, 0.1)
		_rebuild()
## How far from each end a sidewalk may be for people to use it (metres).
@export var reach := 4.0

## Just above the road, so the paint does not flicker with it.
const LIFT := 0.02

var _mesh: MeshInstance3D


func _enter_tree() -> void:
	# In the group before anyone's _ready, so the townsfolk find it wherever it is in the scene.
	add_to_group("crosswalks")


func _ready() -> void:
	_rebuild()
	if not Engine.is_editor_hint():
		_follow_road.call_deferred()


## The two ends, at the kerbs (world space): -Z first.
func ends() -> PackedVector3Array:
	return PackedVector3Array([to_global(Vector3(0.0, 0.0, -length * 0.5)), to_global(Vector3(0.0, 0.0, length * 0.5))])


func _rebuild(heights := {}) -> void:
	if not is_inside_tree():
		return
	if _mesh == null:
		_mesh = MeshInstance3D.new()
		_mesh.name = "Stripes"
		_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_mesh, false, Node.INTERNAL_MODE_FRONT)
	# Drawn over the road and a junction's plain asphalt (world/shaders/road_paint.gdshader).
	var paint := ShaderMaterial.new()
	paint.shader = preload("res://world/shaders/road_paint.gdshader")
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(paint)
	st.set_normal(Vector3.UP)
	var half_w := width * 0.5
	# Bars from kerb to kerb, the margin left over shared between the two ends.
	var pitch := stripe + gap
	var bars := maxi(int((length + gap) / pitch), 1)
	var z := -length * 0.5 + (length - (bars * pitch - gap)) * 0.5
	for b in bars:
		var corners := [Vector3(-half_w, 0.0, z), Vector3(half_w, 0.0, z),
			Vector3(half_w, 0.0, z + stripe), Vector3(-half_w, 0.0, z + stripe)]
		for k in 4:
			var c: Vector3 = corners[k]
			c.y = heights.get(Vector2(c.x, c.z), 0.0) + LIFT
			corners[k] = c
		for k: int in [0, 2, 1, 0, 3, 2]:
			st.add_vertex(corners[k])
		z += pitch
	_mesh.mesh = st.commit()


## In the game: each bar's corners down onto the road under them.
func _follow_road() -> void:
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	var skip: Array[RID] = []
	for car: CollisionObject3D in get_tree().get_nodes_in_group("cars"):
		skip.append(car.get_rid())
	var heights := {}
	var half_w := width * 0.5
	var pitch := stripe + gap
	var bars := maxi(int((length + gap) / pitch), 1)
	var z := -length * 0.5 + (length - (bars * pitch - gap)) * 0.5
	for b in bars:
		for at: Vector2 in [Vector2(-half_w, z), Vector2(half_w, z), Vector2(half_w, z + stripe), Vector2(-half_w, z + stripe)]:
			var p := to_global(Vector3(at.x, 0.0, at.y))
			var ray := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.0, p + Vector3.DOWN * 2.0)
			ray.collision_mask = 1
			ray.exclude = skip
			var hit := space.intersect_ray(ray)
			if hit:
				heights[at] = to_local(hit["position"]).y
		z += pitch
	_rebuild(heights)
