extends SceneTree
## Builds res://world/supermarket.scn: the supermarket on Yeghvard highway
## (OpenStreetMap building 436388507), the guard's booth by the road (building
## 1256383569) and the parking lot between the shop and the highway, laid out
## from the owner's sketch.
##
## The shop: a glass shopfront facing the highway, with the pharmacy's glass
## doors at its left end and the supermarket's in the cut-off corner at its
## right end; no other windows. The pharmacy is a room of its own in the front
## left corner; the four tills stand beside it along the glass, and the store
## room is in the back right corner.
## The walls keep the colour the map gives the building.
##
## The guard's booth: one room with a bed, its door on the side away from the
## shop's left doors (as seen from the road, its right-hand side).
##
## The world still has the plain boxes tools/build_world.gd made for both
## buildings, ground that rises through the shop floor and a service road
## across the parking lot: world/supermarket_site.gd, the scene's root, takes
## those out of it when the game starts.
##
## Run:  godot --path . --script res://tools/build_supermarket.gd
##
## Plan coordinates (shop and booth alike): u metres along the front wall from
## its left end, as seen from outside, and v metres from the front wall
## inwards. In the scene the floor is y = 0, +X runs along u and +Z points out
## of the front, so the plan point (u, v) is at (u, y, -v). Outside the front
## wall v is negative: the parking lot is laid out in the shop's plan too.

const MapKit := preload("res://world/map/map_kit.gd")

const MAP_PATH := "res://world/map/map.tscn"
const OUT_PATH := "res://world/supermarket.scn"
const STORE_ID := 436388507
const BOOTH_ID := 1256383569

# --- the shop ---------------------------------------------------------------------
# Heights above the shop floor, in metres.
const CEILING := 4.0 ## the suspended ceiling
const GLASS_TOP := 3.4 ## top of the glass shopfront; solid wall above
const DOOR_TOP := 2.6 ## top of the sliding doors; fixed glass above
const PASSAGE := 2.6 ## open doorways inside
const DOOR_HEIGHT := 2.1 ## swing doors (store room, booth)
## The floor sits this far above the highest ground along the shopfront.
const FLOOR_RISE := 0.1

const OUTER := 0.3 ## outside wall thickness
const INNER := 0.12 ## partition thickness

## The pharmacy's doors at the left end of the front wall (u; the solid pier is left of them).
const PHARMACY_DOOR := Vector2(1.0, 3.4)
## Width of the supermarket's doors, in the middle of the cut-off corner.
const MAIN_DOOR := 2.0

## The pharmacy in the front left corner, a room of its own: u of its
## right-hand wall, v of its back wall.
const PHARMACY := Vector2(6.0, 6.0)
## Inside the main doors, the shelves along the right-hand wall start this far back (v).
const ENTRY_DEPTH := 5.5
## The store room in the back right corner: u of its left wall, v of its front
## wall, and its door in the left wall (v range).
const STORE_ROOM := Vector2(18.5, 14.0)
const STORE_DOOR := Vector2(15.0, 16.0)

## The tills: u of the middle of each, and the v range they take up.
const TILLS := [7.5, 9.5, 11.5, 13.5]
const TILL_V := Vector2(2.0, 5.0)
## The cashier (world/cashier.gd) at the last till, by the main doors: where
## she stands (plan), and the cigarette rack behind her: u of its front, its
## v range, how deep and tall, and the heights of its shelves.
const CASHIER := Vector2(14.3, 3.0)
const RACK_U := 14.78
const RACK_V := Vector2(1.75, 3.95)
const RACK_DEPTH := 0.26
const RACK_HEIGHT := 2.15
const RACK_SHELVES := [0.95, 1.2, 1.45, 1.7, 1.95]
## Double-sided shelving down the shop: u of the middle of each run, where they
## start (v), the cross aisle, and the clear space left before a wall.
const GONDOLAS := [7.2, 9.9, 12.6, 15.3]
const GONDOLA_START := 7.6
const CROSS_AISLE := Vector2(14.0, 16.0)
const AISLE := 1.6
const SHELF_DEPTH := 0.5 ## one side of a gondola, and the shelves along the walls
const SHELF_HEIGHT := 1.9
const FRIDGE_DEPTH := 0.75
## Fruit and vegetable tables: centres (u, v); each 1.2 x 2.0 m along v.
## Kept clear of the Duet section on the store room's front wall behind them.
const PRODUCE := [Vector2(18.0, 8.6), Vector2(20.4, 8.6), Vector2(18.0, 11.6), Vector2(20.4, 11.6)]
## The Duet iced coffee (props/duet.glb) on the store room's front wall, straight
## ahead as you come in through the main doors: what a cup costs in drams, and
## the brand's colours.
const DUET_PRICE := 150.0
## Shelves the cups stand on (the other shop shelving has 4), as far apart as elsewhere.
const DUET_LEVELS := 2
const DUET_BROWN := Color(0.25, 0.13, 0.08)
const DUET_RED := Color(0.9, 0.12, 0.14)

# --- the booth --------------------------------------------------------------------
const BOOTH_WALL := 0.15
const BOOTH_DOOR := Vector2(1.75, 2.6) ## u range in its front wall
const BOOTH_CEILING := 2.45
## The booth as world/map/map.tscn had it before the map edits of 2026-10-20
## took it out of the map: its outline in world metres (x, z), height and colours.
const BOOTH_FALLBACK := {
	"outline": [Vector2(-777.034585, 1738.4102666), Vector2(-774.2298365, 1737.688587),
		Vector2(-773.1759425, 1741.7082402), Vector2(-775.9891749, 1742.4410283)],
	"height": 2.9685752,
	"wall": Color(0.49569857, 0.4857761, 0.4857761, 1),
	"roof": Color(0.66, 0.66, 0.64, 1),
}

# --- the parking lot --------------------------------------------------------------
## Its outline in world metres (x, z), measured off the roads: 0.7 m off the
## highway's edge and 0.3 m short of the street to the south. The shop's front
## walls close it on the east; these points run from its north-west corner
## round to the north-east one and on from the shop's south corner.
const PARK_NORTH := [Vector2(-779.3, 1726.0), Vector2(-757.0, 1726.0)]
const PARK_SOUTH := [Vector2(-749.52, 1765.05), Vector2(-756.0, 1764.4), Vector2(-768.0, 1763.3),
	Vector2(-772.25, 1762.9), Vector2(-772.9, 1760.0), Vector2(-773.3, 1754.0), Vector2(-775.5, 1746.0)]
## Parking bays in the shop's plan: the row along the shop and the row along
## the highway (v ranges), 2.5 m wide, with the aisle between them.
const ROW_SHOP := Vector2(-7.5, -2.5)
const ROW_ROAD := Vector2(-18.5, -13.5)
const BAY := 2.5
## The pedestrian crossing to the main doors (u range).
const CROSSING := Vector2(0.45, 3.95)
## Over this far from the shopfront the lot rises to the shop floor.
const RAMP := 2.5

# --- state ------------------------------------------------------------------------
var _bufs := {} # material name -> Buf, for the part being built
var _mats := {} # material name -> Material
var _faces := PackedVector3Array() # collision triangles of the part being built
var _hulls: Array[PackedVector3Array] = []
var _rng := RandomNumberGenerator.new()

## Plan frame of the part being built: origin and the world directions of +u and +v (x, z).
var _o := Vector2.ZERO
var _ua := Vector2.RIGHT
var _va := Vector2(0, 1)

var _floor_y := 0.0 ## world height of the shop floor
var _wall_col := Color.WHITE ## for building.gdshader: the walls' colour, alpha 0.5 (plain)
var _roof_col := Color.WHITE
var _shop_top := 5.0 ## height of the shop's roof above its floor


class Buf:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()

	func add(p: Vector3, nrm: Vector3, col: Color, t: Vector2, t2: Vector2) -> int:
		v.append(p)
		n.append(nrm)
		c.append(col)
		uv.append(t)
		uv2.append(t2)
		return v.size() - 1

	func commit_into(mesh: ArrayMesh, mat: Material) -> void:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = n
		arr[Mesh.ARRAY_COLOR] = c
		arr[Mesh.ARRAY_TEX_UV] = uv
		arr[Mesh.ARRAY_TEX_UV2] = uv2
		arr[Mesh.ARRAY_INDEX] = idx
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_rng.seed = 436388507
	# The two buildings as the editable map has them.
	var map: Node3D = (load(MAP_PATH) as PackedScene).instantiate()
	root.add_child(map)
	await process_frame
	var found := {}
	for b in map.find_children("Building_*", "Node3D", true, false):
		var id: int = b.get("osm_id")
		if id == STORE_ID or id == BOOTH_ID:
			var outline: PackedVector2Array = b.call("world_footprint")
			found[id] = {"outline": outline, "height": b.get("height"), "wall": b.get("wall_color"), "roof": b.get("roof_color")}
	map.free()
	if not found.has(BOOTH_ID):
		print("Building %d is not in %s; building the booth as the map last had it" % [BOOTH_ID, MAP_PATH])
		found[BOOTH_ID] = BOOTH_FALLBACK.duplicate()
		found[BOOTH_ID]["outline"] = PackedVector2Array(BOOTH_FALLBACK["outline"])
	for id: int in [STORE_ID, BOOTH_ID]:
		if not found.has(id):
			push_error("Building %d is not in %s" % [id, MAP_PATH])
			quit(1)
			return
	var store: Dictionary = found[STORE_ID]
	var booth: Dictionary = found[BOOTH_ID]
	var store_outline: PackedVector2Array = store["outline"]
	var booth_outline: PackedVector2Array = booth["outline"]
	if store_outline.size() != 5:
		push_error("Expected the five corners of building %d, found %d" % [STORE_ID, store_outline.size()])
		quit(1)
		return

	_make_materials()
	var site := Node3D.new()
	site.name = "Supermarket"
	site.set_script(load("res://world/supermarket_site.gd"))
	var shop := _build_shop(store_outline, store)
	site.add_child(shop)
	var park := _parking_outline(store_outline)
	site.add_child(_build_booth(booth_outline, booth))
	site.add_child(_build_parking(park, store_outline, booth_outline))
	site.set("shop_outline", store_outline)
	site.set("booth_outline", booth_outline)
	site.set("parking_outline", park)

	_own(site, site)
	var scene := PackedScene.new()
	var err := scene.pack(site)
	if err == OK:
		err = ResourceSaver.save(scene, OUT_PATH, ResourceSaver.FLAG_COMPRESS)
	site.free()
	if err != OK:
		push_error("Saving %s failed: %s" % [OUT_PATH, error_string(err)])
		quit(1)
		return
	print("Saved %s" % OUT_PATH)

	quit(0)


func _own(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		_own(child, owner_node)


# --- materials and buffers -------------------------------------------------------

func _make_materials() -> void:
	var building := ShaderMaterial.new()
	building.shader = load("res://world/shaders/building.gdshader")
	_mats["ext"] = building
	var floors := ShaderMaterial.new()
	floors.shader = load("res://world/shaders/house_floor.gdshader")
	_mats["floor"] = floors
	var asphalt := ShaderMaterial.new()
	asphalt.shader = load("res://world/shaders/asphalt.gdshader")
	_mats["asphalt"] = asphalt
	_mats["plaster"] = _plain(Color(0.9, 0.89, 0.86), 0.92)
	# A little light of its own, or it takes the brown of the ground from the sky.
	_mats["ceiling"] = _plain(Color(0.94, 0.94, 0.93), 0.95)
	_mats["ceiling"].emission_enabled = true
	_mats["ceiling"].emission = Color(0.94, 0.94, 0.93)
	_mats["ceiling"].emission_energy_multiplier = 0.22
	_mats["frame"] = _plain(Color(0.6, 0.62, 0.64), 0.35, 0.6)
	_mats["metal"] = _plain(Color(0.85, 0.86, 0.87), 0.45, 0.2)
	_mats["dark"] = _plain(Color(0.2, 0.21, 0.23), 0.6)
	_mats["belt"] = _plain(Color(0.04, 0.04, 0.045), 0.8)
	_mats["wood"] = _plain(Color(0.45, 0.3, 0.18), 0.7)
	_mats["linen"] = _plain(Color(0.78, 0.8, 0.84), 0.9)
	_mats["blanket"] = _plain(Color(0.32, 0.36, 0.3), 0.95)
	_mats["concrete"] = _plain(Color(0.5, 0.5, 0.48), 0.95)
	_mats["steel"] = _plain(Color(0.55, 0.56, 0.55), 0.5, 0.3)
	_mats["red"] = _plain(Color(0.72, 0.07, 0.06), 0.5)
	_mats["green"] = _plain(Color(0.1, 0.5, 0.25), 0.5)
	_mats["white"] = _plain(Color(0.95, 0.95, 0.95), 0.4)
	_mats["rack"] = _plain(Color(0.9, 0.45, 0.08), 0.5, 0.3)
	_mats["upright"] = _plain(Color(0.12, 0.27, 0.55), 0.5, 0.3)
	_mats["cardboard"] = _plain(Color(0.62, 0.47, 0.3), 0.95)
	_mats["pallet"] = _plain(Color(0.66, 0.53, 0.36), 0.9)
	_mats["duet"] = _plain(DUET_BROWN, 0.6)
	_mats["duet_red"] = _plain(DUET_RED, 0.45)
	_mats["chill"] = _glow(Color(0.85, 0.93, 1.0), 1.4)
	var goods := StandardMaterial3D.new()
	goods.vertex_color_use_as_albedo = true
	goods.roughness = 0.55
	_mats["goods"] = goods
	_mats["panel"] = _glow(Color(1.0, 0.98, 0.94), 1.6)
	_mats["fridge_light"] = _glow(Color(0.85, 0.93, 1.0), 2.0)
	_mats["cross"] = _glow(Color(0.1, 0.85, 0.3), 2.5)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.55, 0.68, 0.72, 0.26)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.04
	glass.metallic = 0.4
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats["glass"] = glass


func _plain(color: Color, roughness: float, metallic := 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	return mat


func _glow(color: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	return mat


## Starts a new part (the shop, the booth, the parking lot) with empty buffers.
func _begin() -> void:
	_bufs.clear()
	for mat_name: String in _mats:
		_bufs[mat_name] = Buf.new()
	_faces = PackedVector3Array()
	_hulls.clear()


## Puts what was built since _begin() into `part` as meshes and one static body.
func _finish(part: Node3D) -> void:
	var body := StaticBody3D.new()
	body.name = "Body"
	part.add_child(body)
	for mat_name: String in _bufs:
		var buf: Buf = _bufs[mat_name]
		if buf.idx.is_empty():
			continue
		var mesh := ArrayMesh.new()
		buf.commit_into(mesh, _mats[mat_name])
		var mi := MeshInstance3D.new()
		mi.name = mat_name.capitalize().replace(" ", "")
		mi.mesh = mesh
		if mat_name == "glass":
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(mi)
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(_faces)
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	cs.shape = shape
	body.add_child(cs)
	for k in _hulls.size():
		var hull := ConvexPolygonShape3D.new()
		hull.points = _hulls[k]
		var hs := CollisionShape3D.new()
		hs.name = "Ramp%d" % k
		hs.shape = hull
		body.add_child(hs)


# --- plan geometry --------------------------------------------------------------------

## Sets the plan frame from the front wall's left and right ends (world x, z).
func _set_frame(left: Vector2, right: Vector2) -> void:
	_o = left
	_ua = (right - left).normalized()
	_va = Vector2(_ua.y, -_ua.x)


## The frame as a transform from the part's space (plan (u, v) at (u, y, -v)) to the world.
func _frame_xf(floor_y: float) -> Transform3D:
	var x3 := Vector3(_ua.x, 0.0, _ua.y)
	return Transform3D(Basis(x3, Vector3.UP, x3.cross(Vector3.UP)), Vector3(_o.x, floor_y, _o.y))


func _to_plan(w: Vector2) -> Vector2:
	var d := w - _o
	return Vector2(d.dot(_ua), d.dot(_va))


func _to_world(p: Vector2) -> Vector2:
	return _o + _ua * p.x + _va * p.y


func _plan_poly(world_poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for w in world_poly:
		out.append(_to_plan(w))
	return out


func _p(q: Vector2, y: float) -> Vector3:
	return Vector3(q.x, y, -q.y)


static func _area(poly: PackedVector2Array) -> float:
	var s := 0.0
	for k in poly.size():
		var a := poly[k]
		var b := poly[(k + 1) % poly.size()]
		s += a.x * b.y - b.x * a.y
	return s * 0.5


## The polygon moved in by `t` on every side (mitred corners). Counter-clockwise
## polygons (u right, v up) have their inside to the left of each edge.
static func _inset(poly: PackedVector2Array, t: float) -> PackedVector2Array:
	var n := poly.size()
	var sgn := 1.0 if _area(poly) > 0.0 else -1.0
	var out := PackedVector2Array()
	for k in n:
		var p0 := poly[(k - 1 + n) % n]
		var p1 := poly[k]
		var p2 := poly[(k + 1) % n]
		var d0 := (p1 - p0).normalized()
		var d1 := (p2 - p1).normalized()
		var n0 := Vector2(-d0.y, d0.x) * sgn * t
		var n1 := Vector2(-d1.y, d1.x) * sgn * t
		var hit: Variant = Geometry2D.line_intersects_line(p0 + n0, d0, p1 + n1, d1)
		out.append(hit if hit != null else p1 + n1)
	return out


## How far from `o` along `d` the ray first meets the polygon's outline.
static func _hit(poly: PackedVector2Array, o: Vector2, d: Vector2) -> float:
	var best := INF
	for k in poly.size():
		var hit: Variant = Geometry2D.segment_intersects_segment(o, o + d * 500.0, poly[k], poly[(k + 1) % poly.size()])
		if hit != null:
			var at: Vector2 = hit
			best = minf(best, o.distance_to(at))
	return best


static func _dist_to_poly(p: Vector2, poly: PackedVector2Array) -> float:
	if Geometry2D.is_point_in_polygon(p, poly):
		return 0.0
	var best := INF
	for k in poly.size():
		var q := Geometry2D.get_closest_point_to_segment(p, poly[k], poly[(k + 1) % poly.size()])
		best = minf(best, p.distance_to(q))
	return best


## Rectangle u0..u1 x v0..v1 as a counter-clockwise polygon.
static func _rect(u0: float, v0: float, u1: float, v1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)])


# --- mesh helpers (part space) ------------------------------------------------------

## A flat four-cornered face looking along `nrm`, whatever order the corners come in.
func _quad(mat: String, p: Array, nrm: Vector3, col := Color.WHITE, collide := true, uv2 := Vector2.ZERO) -> void:
	var buf: Buf = _bufs[mat]
	var first := buf.v.size()
	var t := Vector3(nrm.z, 0.0, -nrm.x).normalized() if absf(nrm.y) < 0.7 else Vector3.RIGHT
	for k in 4:
		var q: Vector3 = p[k]
		var uv := Vector2(q.x, q.z) if absf(nrm.y) >= 0.7 else Vector2(q.dot(t), q.y)
		buf.add(q, nrm, col, uv, uv2)
	# Front faces wind clockwise, which puts (p2 - p0) x (p1 - p0) along the normal.
	var a: Vector3 = p[0]
	var b: Vector3 = p[1]
	var c: Vector3 = p[2]
	var order := [0, 1, 2, 0, 2, 3]
	if (c - a).cross(b - a).dot(nrm) <= 0.0:
		order = [0, 2, 1, 0, 3, 2]
	for k: int in order:
		buf.idx.append(first + k)
	if collide:
		for k: int in order:
			_faces.append(p[k])


func _tri(mat: String, a: Vector3, b: Vector3, c: Vector3, nrm: Vector3, col := Color.WHITE, collide := true) -> void:
	var buf: Buf = _bufs[mat]
	var pts := [a, b, c]
	if (c - a).cross(b - a).dot(nrm) <= 0.0:
		pts = [a, c, b]
	for q: Vector3 in pts:
		buf.idx.append(buf.add(q, nrm, col, Vector2(q.x, q.z), Vector2.ZERO))
		if collide:
			_faces.append(q)


## A flat horizontal polygon (plan points) at height y, facing up or down.
func _hpoly(mat: String, poly: PackedVector2Array, y: float, up: bool, col := Color.WHITE, collide := true) -> void:
	var tris := Geometry2D.triangulate_polygon(poly)
	var nrm := Vector3.UP if up else Vector3.DOWN
	for k in range(0, tris.size(), 3):
		_tri(mat, _p(poly[tris[k]], y), _p(poly[tris[k + 1]], y), _p(poly[tris[k + 2]], y), nrm, col, collide)


## A six-sided block between the bottom ring `bot` and the top ring `top` (four
## corners each, in the same order). `mats` names the material of "top",
## "bottom", "sides", or of side k (from corner k to k + 1) as "side<k>"; ""
## leaves a face out.
func _hexa(mats: Dictionary, bot: Array, top: Array, col := Color.WHITE, collide := true, uv2 := Vector2.ZERO) -> void:
	var centre := Vector3.ZERO
	for q: Vector3 in bot + top:
		centre += q / 8.0
	var faces := [["top", top], ["bottom", bot]]
	for k in 4:
		faces.append(["side%d" % k, [bot[k], bot[(k + 1) % 4], top[(k + 1) % 4], top[k]]])
	for face: Array in faces:
		var key: String = face[0]
		var mat: String = mats.get(key, mats.get("sides", "plaster"))
		if mat == "":
			continue
		var q: Array = face[1]
		var q0: Vector3 = q[0]
		var q1: Vector3 = q[1]
		var q2: Vector3 = q[2]
		var q3: Vector3 = q[3]
		var nrm := (q1 - q0).cross(q3 - q0)
		if nrm.length_squared() < 1e-10:
			nrm = (q2 - q1).cross(q0 - q1)
		if nrm.length_squared() < 1e-10:
			continue
		nrm = nrm.normalized()
		if nrm.dot((q0 + q1 + q2 + q3) * 0.25 - centre) < 0.0:
			nrm = -nrm
		_quad(mat, q, nrm, col, collide, uv2)


## A box in the plan: s0..s1 along the plan direction `a` from `o`, c0..c1 to
## its left (towards (-a.y, a.x)), y0..y1 up.
func _obox(mats: Dictionary, o: Vector2, a: Vector2, s0: float, s1: float, c0: float, c1: float, y0: float, y1: float,
		col := Color.WHITE, collide := false) -> void:
	var n := Vector2(-a.y, a.x)
	var q := [o + a * s0 + n * c0, o + a * s1 + n * c0, o + a * s1 + n * c1, o + a * s0 + n * c1]
	var bot := []
	var top := []
	for p: Vector2 in q:
		bot.append(_p(p, y0))
		top.append(_p(p, y1))
	_hexa(mats, bot, top, col, collide)


## An axis-aligned box in the plan.
func _abox(mats: Dictionary, u0: float, u1: float, v0: float, v1: float, y0: float, y1: float,
		col := Color.WHITE, collide := false) -> void:
	_obox(mats, Vector2.ZERO, Vector2.RIGHT, u0, u1, v0, v1, y0, y1, col, collide)


## Collision only: a solid box in the plan, nothing drawn.
func _solid(o: Vector2, a: Vector2, s0: float, s1: float, c0: float, c1: float, y0: float, y1: float) -> void:
	var n := Vector2(-a.y, a.x)
	var q := [o + a * s0 + n * c0, o + a * s1 + n * c0, o + a * s1 + n * c1, o + a * s0 + n * c1]
	var pts := PackedVector3Array()
	for p: Vector2 in q:
		pts.append(_p(p, y0))
		pts.append(_p(p, y1))
	_hulls.append(pts)


## A wall between the outline points a_out..b_out and the matching inner points
## a_in..b_in, from y0 to y1, with openings [from, to, bottom, top] measured
## along it from a_out. `mats`: "outer", "inner", "ends", "top".
func _wall(a_out: Vector2, b_out: Vector2, a_in: Vector2, b_in: Vector2, y0: float, y1: float, openings: Array,
		mats: Dictionary, col := Color.WHITE) -> void:
	var length := a_out.distance_to(b_out)
	var dir := (b_out - a_out) / length
	var sa := (a_in - a_out).dot(dir)
	var across := (a_in - a_out) - dir * sa
	var hm := {"side0": mats.get("outer", "plaster"), "side2": mats.get("inner", "plaster"),
		"side1": mats.get("ends", "plaster"), "side3": mats.get("ends", "plaster"),
		"top": mats.get("top", "plaster"), "bottom": ""}
	var cuts := [0.0, length]
	for o: Array in openings:
		cuts.append_array([clampf(o[0], 0.0, length), clampf(o[1], 0.0, length)])
	cuts.sort()
	for i in cuts.size() - 1:
		var s0: float = cuts[i]
		var s1: float = cuts[i + 1]
		if s1 - s0 < 0.001:
			continue
		var i0 := a_in if s0 < 0.001 else a_out + dir * s0 + across
		var i1 := b_in if s1 > length - 0.001 else a_out + dir * s1 + across
		var o0 := a_out + dir * s0
		var o1 := a_out + dir * s1
		var mid := (s0 + s1) * 0.5
		var gaps := openings.filter(func(o: Array) -> bool: return o[0] <= mid and mid <= o[1])
		gaps.sort_custom(func(a: Array, b: Array) -> bool: return a[2] < b[2])
		var y := y0
		for o: Array in gaps:
			_wall_piece(hm, o0, o1, i1, i0, y, o[2], col)
			y = maxf(y, o[3])
		_wall_piece(hm, o0, o1, i1, i0, y, y1, col)


func _wall_piece(mats: Dictionary, o0: Vector2, o1: Vector2, i1: Vector2, i0: Vector2, b: float, t: float, col: Color) -> void:
	if t - b < 0.001:
		return
	_hexa(mats, [_p(o0, b), _p(o1, b), _p(i1, b), _p(i0, b)], [_p(o0, t), _p(o1, t), _p(i1, t), _p(i0, t)], col)


## A partition along the centre line p0..p1, both faces plaster.
func _partition(p0: Vector2, p1: Vector2, openings: Array, height := CEILING) -> void:
	var d := (p1 - p0).normalized()
	var n := Vector2(-d.y, d.x) * INNER * 0.5
	_wall(p0 + n, p1 + n, p0 - n, p1 - n, 0.0, height, openings, {})


## A glazed wall along its centre line m0..m1: aluminium mullions, rails and
## glass from the floor to `top`, with doorways (s ranges) left open below
## DOOR_TOP and glazed above.
func _glazing(m0: Vector2, m1: Vector2, panels: int, doors: Array, top: float) -> void:
	var length := m0.distance_to(m1)
	var d := (m1 - m0) / length
	var fm := {"sides": "frame", "top": "frame", "bottom": ""}
	var stops := []
	for k in panels + 1:
		var s := length * k / panels
		var inside := false
		for door: Vector2 in doors:
			if s > door.x - 0.3 and s < door.y + 0.3:
				inside = true
		if not inside:
			stops.append(s)
	for door: Vector2 in doors:
		stops.append_array([door.x, door.y])
	stops.sort()
	for s: float in stops:
		_obox(fm, m0, d, s - 0.035, s + 0.035, -0.08, 0.08, 0.0, top, Color.WHITE, true)
	_obox(fm, m0, d, 0.0, length, -0.08, 0.08, top - 0.08, top, Color.WHITE, true)
	for i in stops.size() - 1:
		var s0: float = stops[i]
		var s1: float = stops[i + 1]
		var door := false
		for dr: Vector2 in doors:
			if absf(dr.x - s0) < 0.01 and absf(dr.y - s1) < 0.01:
				door = true
		var bottom := 0.12
		if door:
			_obox(fm, m0, d, s0, s1, -0.08, 0.08, DOOR_TOP, DOOR_TOP + 0.08, Color.WHITE, true)
			bottom = DOOR_TOP + 0.08
		else:
			_obox(fm, m0, d, s0, s1, -0.08, 0.08, 0.0, 0.12, Color.WHITE, true)
		var a := m0 + d * (s0 + 0.035)
		var b := m0 + d * (s1 - 0.035)
		var nrm := Vector3(-d.y, 0.0, -d.x)
		_quad("glass", [_p(a, bottom), _p(b, bottom), _p(b, top - 0.08), _p(a, top - 0.08)], nrm)


## Automatic sliding doors (world/sliding_door.gd) between s0 and s1 along the
## glazing m0..m1, sliding just inside it.
func _sliding_door(parent: Node3D, door_name: String, m0: Vector2, m1: Vector2, s0: float, s1: float) -> void:
	var d := (m1 - m0).normalized()
	var inward := Vector2(-d.y, d.x)
	var width := s1 - s0 - 0.07
	var centre := m0 + d * (s0 + s1) * 0.5 + inward * 0.1
	var x3 := Vector3(d.x, 0.0, -d.y)
	var door := Node3D.new()
	door.name = door_name
	door.set_script(load("res://world/sliding_door.gd"))
	door.transform = Transform3D(Basis(x3, Vector3.UP, x3.cross(Vector3.UP)), _p(centre, 0.0))
	door.set("width", width)
	parent.add_child(door)
	for side: String in ["Left", "Right"]:
		var x0 := -width * 0.5 - 0.02 if side == "Left" else -0.02
		var x1 := 0.02 if side == "Left" else width * 0.5 + 0.02
		var h := DOOR_TOP - 0.02
		var frame := Buf.new()
		var pane := Buf.new()
		var f := 0.05
		for box: Array in [[x0, x0 + f, 0.0, h], [x1 - f, x1, 0.0, h], [x0, x1, 0.0, 0.1], [x0, x1, h - f, h]]:
			_leaf_box(frame, Vector3(box[0], box[2], -0.02), Vector3(box[1], box[3], 0.02))
		var first := pane.v.size()
		for corner: Vector3 in [Vector3(x0 + f, 0.1, 0.0), Vector3(x1 - f, 0.1, 0.0), Vector3(x1 - f, h - f, 0.0), Vector3(x0 + f, h - f, 0.0)]:
			pane.add(corner, Vector3.BACK, Color.WHITE, Vector2.ZERO, Vector2.ZERO)
		pane.idx.append_array([first, first + 2, first + 1, first, first + 3, first + 2])
		var mesh := ArrayMesh.new()
		frame.commit_into(mesh, _mats["frame"])
		pane.commit_into(mesh, _mats["glass"])
		var mi := MeshInstance3D.new()
		mi.name = side
		mi.mesh = mesh
		door.add_child(mi)


## A door that swings open by itself (world/house_door.gd) in the doorway s0..s1
## along a wall from `o` in direction `a`, `c` across it: hung at s0 and swinging
## towards the plan direction `swing`.
func _swing_door(parent: Node3D, door_name: String, o: Vector2, a: Vector2, s0: float, s1: float, c: float,
		half: float, swing: Vector2, leaf_mat: String) -> void:
	var fm := {"sides": "frame", "top": "frame", "bottom": ""}
	var f := 0.05
	_obox(fm, o, a, s0, s0 + f, c - half - 0.01, c + half + 0.01, 0.0, DOOR_HEIGHT)
	_obox(fm, o, a, s1 - f, s1, c - half - 0.01, c + half + 0.01, 0.0, DOOR_HEIGHT)
	_obox(fm, o, a, s0, s1, c - half - 0.01, c + half + 0.01, DOOR_HEIGHT - f, DOOR_HEIGHT)
	var n := Vector2(-a.y, a.x)
	var width := s1 - s0 - 2.0 * f
	var x3 := Vector3(a.x, 0.0, -a.y)
	var frame := Basis(x3, Vector3.UP, x3.cross(Vector3.UP))
	var towards := Vector3(swing.x, 0.0, -swing.y)
	var turn := 1.0 if towards.dot(-frame.z) > 0.0 else -1.0
	var door := Node3D.new()
	door.name = door_name
	door.set_script(load("res://world/house_door.gd"))
	door.transform = Transform3D(frame, _p(o + a * (s0 + f) + n * c, 0.0))
	door.set("width", width)
	door.set("open_angle", 95.0 * turn)
	parent.add_child(door)
	var leaf := Buf.new()
	var lw := width - 0.01
	var lh := DOOR_HEIGHT - f - 0.01
	_leaf_box(leaf, Vector3(0.005, 0.01, -0.02), Vector3(lw, lh, 0.02))
	for side: float in [-1.0, 1.0]:
		var z := side * 0.05
		_leaf_box(leaf, Vector3(lw - 0.17, 1.0, z - 0.012), Vector3(lw - 0.05, 1.03, z + 0.012))
	var mesh := ArrayMesh.new()
	leaf.commit_into(mesh, _mats[leaf_mat])
	var mi := MeshInstance3D.new()
	mi.name = "Leaf"
	mi.mesh = mesh
	door.add_child(mi)


## A plain box in a door's own space.
func _leaf_box(buf: Buf, lo: Vector3, hi: Vector3) -> void:
	var corners := [
		[Vector3.UP, [Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)]],
		[Vector3.DOWN, [Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z)]],
		[Vector3.LEFT, [Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, lo.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3(lo.x, hi.y, lo.z)]],
		[Vector3.RIGHT, [Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, hi.y, lo.z)]],
		[Vector3.FORWARD, [Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, lo.z)]],
		[Vector3.BACK, [Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)]],
	]
	for face: Array in corners:
		var nrm: Vector3 = face[0]
		var p: Array = face[1]
		var first := buf.v.size()
		for k in 4:
			buf.add(p[k], nrm, Color.WHITE, Vector2.ZERO, Vector2.ZERO)
		var a: Vector3 = p[0]
		var b: Vector3 = p[1]
		var c: Vector3 = p[2]
		var order := [0, 1, 2, 0, 2, 3]
		if (c - a).cross(b - a).dot(nrm) <= 0.0:
			order = [0, 2, 1, 0, 3, 2]
		for k: int in order:
			buf.idx.append(first + k)


## A window with an aluminium frame and glass in a wall from `o` along `a`
## (s0..s1, b..t high), lying across c0..c1.
func _window(o: Vector2, a: Vector2, s0: float, s1: float, b: float, t: float, c0: float, c1: float) -> void:
	var fm := {"sides": "frame", "top": "frame", "bottom": ""}
	var m := (c0 + c1) * 0.5
	var f := 0.05
	_obox(fm, o, a, s0, s0 + f, m - 0.03, m + 0.03, b, t)
	_obox(fm, o, a, s1 - f, s1, m - 0.03, m + 0.03, b, t)
	_obox(fm, o, a, s0, s1, m - 0.03, m + 0.03, t - f, t)
	_obox(fm, o, a, s0, s1, m - 0.03, m + 0.03, b, b + f)
	_obox(fm, o, a, (s0 + s1) * 0.5 - 0.025, (s0 + s1) * 0.5 + 0.025, m - 0.03, m + 0.03, b, t)
	var n := Vector2(-a.y, a.x)
	var pts := []
	for corner: Vector2 in [Vector2(s0, b), Vector2(s1, b), Vector2(s1, t), Vector2(s0, t)]:
		pts.append(_p(o + a * corner.x + n * m, corner.y))
	_quad("glass", pts, Vector3(n.x, 0.0, -n.y))
	_obox({"sides": "white", "top": "white", "bottom": ""}, o, a, s0 - 0.04, s1 + 0.04, minf(c0, c1) - 0.06, maxf(c0, c1) + 0.06, b - 0.04, b)


# --- the shop ----------------------------------------------------------------------

func _build_shop(world_outline: PackedVector2Array, info: Dictionary) -> Node3D:
	# The map lists the corners from the back-left one round the back; the front
	# wall runs from corner 4 (left, as seen from the parking lot) to corner 3,
	# then the cut-off corner to corner 2, the right-hand side to corner 1, the
	# back to corner 0 and the left-hand side back to corner 4.
	var w_e := world_outline[4]
	var w_d := world_outline[3]
	_set_frame(w_e, w_d)
	var fp := _plan_poly(PackedVector2Array([world_outline[4], world_outline[3], world_outline[2], world_outline[1], world_outline[0]]))
	if _area(fp) < 0.0:
		push_error("The shop's outline runs the wrong way round")
	var inner := _inset(fp, OUTER)

	# Heights: the floor level with the ground along the shopfront; the walls
	# from below the lowest ground to where the map's box had its roof.
	var front_high := -INF
	for k in 9:
		for edge: Array in [[fp[0], fp[1]], [fp[1], fp[2]]]:
			var a: Vector2 = edge[0]
			var b: Vector2 = edge[1]
			var w := _to_world(a.lerp(b, k / 8.0))
			front_high = maxf(front_high, MapKit.height_at(w.x, w.y))
	var low := INF
	var high := -INF
	for w in world_outline:
		var g := MapKit.height_at(w.x, w.y)
		low = minf(low, g)
		high = maxf(high, g)
	_floor_y = front_high + FLOOR_RISE
	var height: float = info["height"]
	var top := high + height - _floor_y
	_shop_top = top
	var base := low - 0.6 - _floor_y
	var wall_color: Color = info["wall"]
	var roof_color: Color = info["roof"]
	_wall_col = wall_color.srgb_to_linear()
	_wall_col.a = 0.5
	_roof_col = roof_color.srgb_to_linear()
	_roof_col.a = 0.0
	print("Shop: floor at %.2f m (ground %.2f .. %.2f), roof %.2f m above the floor" % [_floor_y, low, high, top])

	_begin()
	var shop := Node3D.new()
	shop.name = "Shop"
	shop.transform = _frame_xf(_floor_y)
	var doors := Node3D.new()
	doors.name = "Doors"
	shop.add_child(doors)
	var lights := Node3D.new()
	lights.name = "Lights"
	shop.add_child(lights)

	# Outside walls. The front and the cut-off corner are glass from the floor
	# to GLASS_TOP (but for the pier left of the main doors), solid above.
	var ext := {"outer": "ext", "inner": "plaster", "ends": "plaster", "top": ""}
	var n := fp.size()
	for k in n:
		var a := fp[k]
		var b := fp[(k + 1) % n]
		var length := a.distance_to(b)
		var openings := []
		if k == 0:
			openings = [[PHARMACY_DOOR.x, length + 1.0, -0.01, GLASS_TOP]]
		elif k == 1:
			openings = [[-1.0, length + 1.0, -0.01, GLASS_TOP]]
		_wall(a, b, inner[k], inner[(k + 1) % n], base, top, openings, ext, _wall_col)
	# The glass: centre lines of the two walls, meeting at the corner.
	var mid_d := (fp[1] + inner[1]) * 0.5
	var mid_c := (fp[2] + inner[2]) * 0.5
	var m0 := Vector2(PHARMACY_DOOR.x, OUTER * 0.5) # the front wall runs along u
	var front_len := m0.distance_to(mid_d)
	var ph_door := Vector2(0.0, PHARMACY_DOOR.y - PHARMACY_DOOR.x)
	_glazing(m0, mid_d, roundi(front_len / 1.6), [ph_door], GLASS_TOP)
	_sliding_door(doors, "PharmacyDoor", m0, mid_d, ph_door.x, ph_door.y)
	var corner_len := mid_d.distance_to(mid_c)
	var main_door := Vector2((corner_len - MAIN_DOOR) * 0.5, (corner_len + MAIN_DOOR) * 0.5)
	_glazing(mid_d, mid_c, 4, [main_door], GLASS_TOP)
	_sliding_door(doors, "MainDoor", mid_d, mid_c, main_door.x, main_door.y)

	# Roof over the whole outline, at the height of the map's box.
	_hpoly("ext", fp, top, true, _roof_col, false)

	# Rooms.
	var h := INNER * 0.5
	var front_in := inner[0].y # the front wall's inner face (v); the front runs along u
	var pharmacy := _rect(-50.0, -50.0, PHARMACY.x, PHARMACY.y)
	var store := _rect(STORE_ROOM.x, STORE_ROOM.y, 100.0, 100.0)
	var ph_left := _hit(inner, Vector2(PHARMACY.x, PHARMACY.y), Vector2.LEFT)
	var st_right := _hit(inner, Vector2(STORE_ROOM.x, STORE_ROOM.y), Vector2.RIGHT)
	var st_back := _hit(inner, Vector2(STORE_ROOM.x, STORE_ROOM.y), Vector2(0, 1))
	# The pharmacy, closed off from the shop: its back wall and right-hand wall.
	_partition(Vector2(PHARMACY.x - ph_left - 0.15, PHARMACY.y), Vector2(PHARMACY.x + h, PHARMACY.y), [])
	_partition(Vector2(PHARMACY.x, front_in - 0.15), Vector2(PHARMACY.x, PHARMACY.y - h), [])
	# The store room, with its door into the shop.
	_partition(Vector2(STORE_ROOM.x - h, STORE_ROOM.y), Vector2(STORE_ROOM.x + st_right + 0.15, STORE_ROOM.y), [])
	var sd0 := Vector2(STORE_ROOM.x, STORE_ROOM.y - h)
	_partition(sd0, Vector2(STORE_ROOM.x, STORE_ROOM.y + st_back + 0.15),
		[[STORE_DOOR.x - sd0.y, STORE_DOOR.y - sd0.y, -0.01, DOOR_HEIGHT]])
	_swing_door(doors, "StoreRoomDoor", sd0, Vector2(0, 1), STORE_DOOR.x - sd0.y, STORE_DOOR.y - sd0.y, 0.0, h,
		Vector2.RIGHT, "steel")

	# Floors: tiles, bare concrete in the store room; the ceiling with its lights.
	var store_poly: PackedVector2Array = Geometry2D.intersect_polygons(fp, store)[0]
	for piece: PackedVector2Array in Geometry2D.clip_polygons(fp, store):
		_hpoly("floor", piece, 0.0, true, Color(1, 1, 1, 0.5))
	_hpoly("floor", store_poly, 0.0, true, Color(1, 1, 1, 0.0))
	_hpoly("ceiling", inner, CEILING, false, Color.WHITE, false)
	var rooms := {
		"Pharmacy": Geometry2D.intersect_polygons(inner, pharmacy)[0],
		"StoreRoom": Geometry2D.intersect_polygons(inner, store)[0],
	}
	_ceiling_lights(lights, inner, rooms)

	_shop_fittings(fp, inner, doors)
	_duet_section(shop, inner)
	_cashier(shop)
	_signs(shop, fp)
	_finish(shop)
	return shop


## Distance from p to the nearest edge of the polygon.
static func _edge_dist(p: Vector2, poly: PackedVector2Array) -> float:
	var best := INF
	for k in poly.size():
		var q := Geometry2D.get_closest_point_to_segment(p, poly[k], poly[(k + 1) % poly.size()])
		best = minf(best, p.distance_to(q))
	return best


## Light panels in the ceiling, on a grid centred in each room, and lamps:
## one in each small room, one for every 6 m square of the shop floor.
func _ceiling_lights(lights: Node3D, inner: PackedVector2Array, rooms: Dictionary) -> void:
	var all := rooms.duplicate()
	all["Shop"] = inner
	for room: String in all:
		var poly: PackedVector2Array = all[room]
		var spacing := 3.0 if room == "Shop" else 2.4
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for p in poly:
			lo = lo.min(p)
			hi = hi.max(p)
		var size := hi - lo
		var start := lo + Vector2(fmod(size.x, spacing), fmod(size.y, spacing)) * 0.5 + Vector2(spacing, spacing) * 0.5
		var groups := {}
		var u := start.x
		while u < hi.x:
			var v := start.y
			while v < hi.y:
				var at := Vector2(u, v)
				var ok := Geometry2D.is_point_in_polygon(at, poly) and _edge_dist(at, poly) > 0.8
				if room == "Shop":
					for other: String in rooms:
						var op: PackedVector2Array = rooms[other]
						if Geometry2D.is_point_in_polygon(at, op) or _edge_dist(at, op) < 0.8:
							ok = false
				if ok:
					_abox({"sides": "frame", "bottom": "panel", "top": ""}, u - 0.3, u + 0.3, v - 0.6, v + 0.6, CEILING - 0.03, CEILING)
					var key := room
					if room == "Shop":
						key = "Shop_%d_%d" % [floori(u / 6.0), floori(v / 6.0)]
					if not groups.has(key):
						groups[key] = []
					groups[key].append(at)
				v += spacing
			u += spacing
		for key: String in groups:
			var spots: Array = groups[key]
			var centre := Vector2.ZERO
			for p: Vector2 in spots:
				centre += p / spots.size()
			var lamp := OmniLight3D.new()
			lamp.name = key.replace("_", "")
			lamp.position = _p(centre, CEILING - 0.4)
			lamp.light_energy = 0.9 if room == "Shop" else 0.8
			lamp.omni_range = 8.5 if room == "Shop" else 7.0
			lamp.light_color = Color(1.0, 0.97, 0.92)
			lamp.light_specular = 0.3
			lights.add_child(lamp)


## The shopfront's white board with "ՄԻՇՏ ՑԱԾՐ ԳՆԵՐ" in blue, the CITY logo
## over the main doors, and the pharmacy's green cross over its doors.
const SIGN_BLUE := Color(0.0, 0.141, 0.29, 1.0)
const SIGN_FONT := "res://props/NotoSansArmenian-Bold.ttf"
const LOGO_PATH := "res://props/city_logo.png"

func _signs(shop: Node3D, fp: PackedVector2Array) -> void:
	var front_len := fp[0].distance_to(fp[1])
	var shop_sign := _board(shop, "ShopSign", fp[0], fp[1], PHARMACY.x - 0.6, front_len - 0.5, 1.1, "white")
	var font := FontFile.new()
	if font.load_dynamic_font(SIGN_FONT) == OK:
		shop_sign.font = font
	else:
		push_warning("Could not load %s: the Armenian letters may not show." % SIGN_FONT)
	shop_sign.text = "ՄԻՇՏ ՑԱԾՐ ԳՆԵՐ"
	shop_sign.font_size = 110
	shop_sign.modulate = SIGN_BLUE
	shop_sign.outline_size = 0
	_logo_board(shop, fp[1], fp[2])
	# Over the pharmacy's doors in the front wall.
	var d := Vector2.RIGHT
	var out := Vector2(0, -1)
	var mid := Vector2((PHARMACY_DOOR.x + PHARMACY_DOOR.y) * 0.5, 0.0)
	var y := GLASS_TOP + 1.25
	_obox({"sides": "white", "top": "white", "bottom": "white"}, mid, d, -0.65, 0.65, -0.12, 0.0, y - 0.65, y + 0.65)
	# The cross stands 1 cm proud of the plate's face (v = -0.12), not in it.
	var cross := mid + out * 0.13
	var cm := {"sides": "cross", "top": "cross", "bottom": "cross"}
	_obox(cm, cross, d, -0.48, 0.48, -0.08, 0.0, y - 0.16, y + 0.16)
	_obox(cm, cross, d, -0.16, 0.16, -0.08, 0.0, y - 0.48, y + 0.48)
	var ph := Label3D.new()
	ph.name = "PharmacySign"
	ph.text = "PHARMACY"
	ph.font_size = 64
	ph.pixel_size = 0.006
	ph.modulate = Color(0.15, 0.7, 0.3)
	ph.outline_modulate = Color(1, 1, 1)
	ph.outline_size = 10
	ph.position = _p(mid + out * 0.02, GLASS_TOP + 0.3)
	shop.add_child(ph)


## A board in material `mat` on the outside of the wall a..b (plan), from s0 to
## s1 along it, `tall` metres high above the glass, and an empty label centred
## on its face for the caller to fill in.
func _board(shop: Node3D, sign_name: String, a: Vector2, b: Vector2, s0: float, s1: float,
		tall: float, mat: String) -> Label3D:
	var d := (b - a).normalized()
	var out := Vector2(d.y, -d.x)
	var y0 := GLASS_TOP + 0.35
	_obox({"sides": mat, "top": mat, "bottom": mat}, a, d, s0, s1, -0.14, 0.0, y0, y0 + tall)
	var label := Label3D.new()
	label.name = sign_name
	label.pixel_size = 0.0075
	var x3 := Vector3(d.x, 0.0, -d.y)
	label.transform = Transform3D(Basis(x3, Vector3.UP, x3.cross(Vector3.UP)),
		_p(a + d * (s0 + s1) * 0.5 + out * 0.15, y0 + tall * 0.5))
	shop.add_child(label)
	return label


## The CITY logo (props/city_logo.png) on a white board over the main doors in
## the cut-off corner a..b, lying horizontally, as tall as the roof allows.
func _logo_board(shop: Node3D, a: Vector2, b: Vector2) -> void:
	var img := Image.load_from_file(LOGO_PATH)
	if img == null or img.is_empty():
		push_warning("Could not load %s: no logo over the main doors." % LOGO_PATH)
		return
	img.generate_mipmaps()
	var aspect := float(img.get_width()) / img.get_height()
	var d := (b - a).normalized()
	var out := Vector2(d.y, -d.x)
	var corner_len := a.distance_to(b)
	var y0 := GLASS_TOP + 0.35
	# Up to 1.5 m tall, staying 0.15 m under the roof and inside the corner wall.
	var tall := minf(1.5, _shop_top - y0 - 0.15)
	tall = minf(tall, (corner_len - 0.4) / aspect)
	var wide := tall * aspect
	var s0 := (corner_len - wide) * 0.5
	var s1 := s0 + wide
	_obox({"sides": "white", "top": "white", "bottom": "white"}, a, d, s0, s1, -0.14, 0.0, y0, y0 + tall)
	var logo := Sprite3D.new()
	logo.name = "EntranceLogo"
	logo.texture = ImageTexture.create_from_image(img)
	logo.pixel_size = tall / img.get_height()
	var x3 := Vector3(d.x, 0.0, -d.y)
	logo.transform = Transform3D(Basis(x3, Vector3.UP, x3.cross(Vector3.UP)),
		_p(a + d * (s0 + s1) * 0.5 + out * 0.15, y0 + tall * 0.5))
	shop.add_child(logo)


func _shop_fittings(fp: PackedVector2Array, inner: PackedVector2Array, doors: Node3D) -> void:
	var h := INNER * 0.5
	# Shelves along the left-hand wall, from behind the lobby to the fridges at the back.
	var left_a := inner[0]
	var left_b := inner[4]
	var left_dir := (left_b - left_a).normalized()
	var left_len := left_a.distance_to(left_b)
	var lobby_s := (PHARMACY.y + h + 0.3 - left_a.y) / left_dir.y
	_shelf_run(left_b, -left_dir, FRIDGE_DEPTH + 0.15, left_len - lobby_s)
	# Fridges along the back wall from the store room to the left-hand corner
	# (the wall runs from the right-hand corner, with the shop to its left).
	var back_a := inner[3]
	var back_b := inner[4]
	var back_dir := (back_b - back_a).normalized()
	var back_start := (STORE_ROOM.x - h - 0.05 - back_a.x) / back_dir.x
	_fridges(back_a, back_dir, back_start, back_a.distance_to(back_b) - 0.1)
	# Shelves along the right-hand wall, between the pharmacy and the store room.
	var right_a := inner[2]
	var right_b := inner[3]
	var right_dir := (right_b - right_a).normalized()
	var r0 := (ENTRY_DEPTH - right_a.y) / right_dir.y
	var r1 := (STORE_ROOM.y - h - 0.25 - right_a.y) / right_dir.y
	_shelf_run(right_a, right_dir, r0, r1)

	# Gondolas: to the cross aisle, then on towards the back as far as there is room.
	for uc: float in GONDOLAS:
		var u_lo := uc - SHELF_DEPTH - 0.05
		var u_hi := uc + SHELF_DEPTH + 0.05
		var end := INF
		for u: float in [u_lo, u_hi]:
			end = minf(end, GONDOLA_START + _hit(inner, Vector2(u, GONDOLA_START), Vector2(0, 1)) - FRIDGE_DEPTH - 0.1 - AISLE - 0.3)
		var left_room := GONDOLA_START + _hit(inner, Vector2(u_lo - SHELF_DEPTH - AISLE - 0.1, GONDOLA_START), Vector2(0, 1))
		end = minf(end, left_room)
		if end - GONDOLA_START < 2.0:
			continue
		if end <= CROSS_AISLE.y + 2.0:
			_gondola(uc, GONDOLA_START, minf(end, CROSS_AISLE.x))
		else:
			_gondola(uc, GONDOLA_START, CROSS_AISLE.x)
			_gondola(uc, CROSS_AISLE.y, end)
	for c: Vector2 in PRODUCE:
		_produce_table(c)
	for k in TILLS.size():
		_till(TILLS[k])
	_entry_fittings(inner)
	_pharmacy_fittings(inner)
	_store_room_fittings(inner)


## Products on a shelf: blocks of a few identical packs side by side, between
## s0 and s1 along `a` from `o`, c0..c1 deep (c1 the shelf's front edge), on y.
func _goods(o: Vector2, a: Vector2, s0: float, s1: float, c0: float, c1: float, y: float, max_h: float, tall := false) -> void:
	var gm := {"sides": "goods", "top": "goods", "bottom": ""}
	var s := s0 + 0.02
	while s < s1 - 0.1:
		var hue := _rng.randf()
		var col := Color.from_hsv(hue, _rng.randf_range(0.35, 0.9), _rng.randf_range(0.45, 0.95)).srgb_to_linear()
		if _rng.randf() < 0.2:
			col = Color.from_hsv(hue, 0.08, _rng.randf_range(0.75, 0.95)).srgb_to_linear()
		var w := _rng.randf_range(0.07, 0.11) if tall else _rng.randf_range(0.1, 0.3)
		var ht := minf(max_h, _rng.randf_range(0.22, 0.34) if tall else _rng.randf_range(0.12, 0.34))
		var depth := (c1 - c0) * _rng.randf_range(0.65, 0.95)
		var facings := _rng.randi_range(2, 5)
		for k in facings:
			if s + w > s1 - 0.02:
				break
			_obox(gm, o, a, s, s + w - 0.012, c1 - depth, c1 - 0.02, y, y + ht, col)
			s += w
		s += 0.03


## Shelving against a wall: along `a` from `o` (s0..s1), the shelves to the
## left of the line, back panel on it.
## Without `stocked` the shelves are left empty (for world/duet_stand.gd to fill).
func _shelf_run(o: Vector2, a: Vector2, s0: float, s1: float, depth := SHELF_DEPTH, levels := 4, stocked := true,
		height := SHELF_HEIGHT) -> void:
	if s1 - s0 < 0.6:
		return
	var mm := {"sides": "metal", "top": "metal", "bottom": ""}
	_obox({"sides": "dark", "top": "dark", "bottom": ""}, o, a, s0, s1, 0.04, depth - 0.02, 0.0, 0.12)
	_obox(mm, o, a, s0, s1, 0.0, 0.04, 0.0, height)
	var step := (height - 0.35) / levels
	var bays := maxi(1, roundi((s1 - s0) / 1.0))
	for k in bays + 1:
		var s := lerpf(s0, s1, float(k) / bays)
		_obox(mm, o, a, s - 0.015, s + 0.015, 0.0, depth, 0.0, height)
	if stocked:
		_goods(o, a, s0, s1, 0.06, depth, 0.12, step - 0.06)
	for k in range(1, levels + 1):
		var y := 0.12 + step * k
		_obox(mm, o, a, s0, s1, 0.04, depth, y - 0.025, y)
		if k < levels and stocked:
			_goods(o, a, s0, s1, 0.06, depth, y, step - 0.06)
	_solid(o, a, s0, s1, 0.0, depth, 0.0, height)


## The Duet iced coffee section on the store room's front wall, facing you as
## you come in through the main doors: empty shelving with a brown back, a light
## under each shelf and a DUET board over it. The node DuetStand
## (world/duet_stand.gd) puts the cups on the shelves when the game runs and
## sells them.
func _duet_section(shop: Node3D, inner: PackedVector2Array) -> void:
	var h := INNER * 0.5
	var v := STORE_ROOM.y - h
	var u0 := STORE_ROOM.x + 0.15
	# Up to the shelves along the right-hand wall.
	var u1 := STORE_ROOM.x + _hit(inner, Vector2(STORE_ROOM.x, v - SHELF_DEPTH - 0.05), Vector2.RIGHT) - SHELF_DEPTH - 0.1
	var length := u1 - u0
	var o := Vector2(u1, v)
	var a := Vector2.LEFT
	var levels := DUET_LEVELS
	# The same gap between shelves as the 4-shelf units, so a lower unit.
	var step := (SHELF_HEIGHT - 0.35) / 4
	var height := 0.35 + step * levels
	_shelf_run(o, a, 0.0, length, SHELF_DEPTH, levels, false, height)
	_obox({"sides": "duet", "top": "", "bottom": ""}, o, a, 0.0, length, 0.04, 0.045, 0.12, height)
	for k in range(1, levels + 1):
		var y := 0.12 + step * k - 0.025
		_obox({"sides": "metal", "top": "", "bottom": "chill"}, o, a, 0.0, length, SHELF_DEPTH - 0.08, SHELF_DEPTH - 0.04, y - 0.015, y)

	# The board over the shelves, brown with a red edge.
	var y0 := height + 0.15
	var y1 := y0 + 0.75
	_obox({"sides": "duet", "top": "duet", "bottom": "duet"}, o, a, 0.0, length, 0.0, 0.08, y0, y1)
	_obox({"sides": "duet_red", "top": "duet_red", "bottom": "duet_red"}, o, a, 0.0, length, 0.08, 0.09, y0, y0 + 0.07)
	var mid := Vector2((u0 + u1) * 0.5, v - 0.1)
	var brand := Label3D.new()
	brand.name = "DuetSign"
	brand.text = "DUET"
	brand.font_size = 72
	brand.pixel_size = 0.006
	brand.modulate = DUET_RED
	brand.outline_modulate = Color(1, 1, 1)
	brand.outline_size = 14
	brand.position = _p(mid, y1 - 0.26)
	shop.add_child(brand)
	var line := Label3D.new()
	line.name = "DuetPrice"
	line.text = "ICE COFFEE   %d AMD" % roundi(DUET_PRICE)
	line.font_size = 28
	line.pixel_size = 0.006
	line.modulate = Color(1, 0.97, 0.9)
	line.outline_size = 0
	line.position = _p(mid, y0 + 0.17)
	shop.add_child(line)

	var stand := Node3D.new()
	stand.name = "DuetStand"
	stand.set_script(load("res://world/duet_stand.gd"))
	# +X along the shelves from their left end as you face them, +Z out of their front.
	stand.position = _p(Vector2(u0, v), 0.0)
	stand.set("length", length)
	stand.set("depth", SHELF_DEPTH)
	var heights := PackedFloat32Array()
	for k in levels:
		heights.append(0.12 + step * k)
	stand.set("levels", heights)
	stand.set("price", DUET_PRICE)
	shop.add_child(stand)


## The cashier behind the last till and the cigarette rack behind her: a
## cabinet of shelves full of packs of Ararat (props/cigarette.gd), their
## fronts to the till.
func _cashier(shop: Node3D) -> void:
	var u0 := RACK_U
	var u1 := RACK_U + RACK_DEPTH
	var v0 := RACK_V.x
	var v1 := RACK_V.y
	var wood := {"sides": "wood", "top": "wood", "bottom": "wood"}
	var dm := {"sides": "dark", "top": "dark", "bottom": ""}
	_abox(dm, u1 - 0.03, u1, v0, v1, 0.0, RACK_HEIGHT)
	_abox(wood, u0, u1, v0 - 0.03, v0, 0.0, RACK_HEIGHT)
	_abox(wood, u0, u1, v1, v1 + 0.03, 0.0, RACK_HEIGHT)
	_abox(wood, u0, u1, v0 - 0.03, v1 + 0.03, RACK_HEIGHT - 0.04, RACK_HEIGHT)
	_abox(wood, u0, u1, v0, v1, 0.0, RACK_SHELVES[0] - 0.02)
	for y: float in RACK_SHELVES:
		_abox(wood, u0, u1 - 0.03, v0, v1, y - 0.02, y)
	_solid(Vector2.ZERO, Vector2.RIGHT, u0, u1, v0 - 0.03, v1 + 0.03, 0.0, RACK_HEIGHT)

	# The packs (world/cigarette_rack.gd fills the shelves when the game
	# starts): its +X along the shelves (-v), +Z out of their front (-u).
	var rack := Node3D.new()
	rack.name = "CigaretteRack"
	rack.set_script(load("res://world/cigarette_rack.gd"))
	rack.transform = Transform3D(Basis(Vector3.UP, -PI * 0.5), _p(Vector2(u0, v1), 0.0))
	rack.set("length", v1 - v0)
	rack.set("shelves", PackedFloat32Array(RACK_SHELVES))
	shop.add_child(rack)

	var cashier := Node3D.new()
	cashier.name = "Cashier"
	cashier.set_script(load("res://world/cashier.gd"))
	# Facing the customers' side of the till (-u).
	cashier.transform = Transform3D(Basis(Vector3.UP, -PI * 0.5), _p(CASHIER, 0.0))
	shop.add_child(cashier)
	print("Cashier at u %.1f, v %.1f" % [CASHIER.x, CASHIER.y])


## A double-sided run of shelves down the shop, centred on u = uc from v0 to v1.
func _gondola(uc: float, v0: float, v1: float) -> void:
	_shelf_run(Vector2(uc, v0), Vector2(0, 1), 0.0, v1 - v0)
	_shelf_run(Vector2(uc, v1), Vector2(0, -1), 0.0, v1 - v0)
	var mm := {"sides": "metal", "top": "metal", "bottom": ""}
	for end: float in [v0, v1]:
		_abox(mm, uc - SHELF_DEPTH, uc + SHELF_DEPTH, end - 0.02, end + 0.02, 0.0, SHELF_HEIGHT)


## Glass-door fridges against a wall, along `a` from `o` (s0..s1), facing left of the line.
func _fridges(o: Vector2, a: Vector2, s0: float, s1: float) -> void:
	var units := maxi(1, floori((s1 - s0) / 1.25))
	var unit := (s1 - s0) / units
	var d := FRIDGE_DEPTH
	var wm := {"sides": "white", "top": "white", "bottom": ""}
	var top := 2.05
	_obox(wm, o, a, s0, s1, 0.0, 0.05, 0.0, top)
	_obox(wm, o, a, s0, s1, 0.0, d, 0.0, 0.25)
	_obox(wm, o, a, s0, s1, 0.0, d, top - 0.25, top)
	_obox({"sides": "fridge_light", "top": "", "bottom": ""}, o, a, s0, s1, d - 0.01, d + 0.005, top - 0.22, top - 0.05)
	for k in units + 1:
		var s := s0 + unit * k
		_obox(wm, o, a, s - 0.03, s + 0.03, 0.0, d, 0.0, top)
	for k in units:
		var a0 := s0 + unit * k + 0.03
		var a1 := s0 + unit * (k + 1) - 0.03
		for level in 4:
			var y := 0.25 + level * 0.42
			if level > 0:
				_obox({"sides": "metal", "top": "metal", "bottom": ""}, o, a, a0, a1, 0.05, d - 0.08, y - 0.02, y)
			_goods(o, a, a0, a1, 0.08, d - 0.1, y, 0.34, true)
		# Glass doors with an aluminium edge between them.
		var mid := (a0 + a1) * 0.5
		_obox({"sides": "frame", "top": "frame", "bottom": ""}, o, a, mid - 0.02, mid + 0.02, d - 0.04, d, 0.25, top - 0.25)
		var n := Vector2(-a.y, a.x)
		var pts := []
		for corner: Vector2 in [Vector2(a0, 0.25), Vector2(a1, 0.25), Vector2(a1, top - 0.25), Vector2(a0, top - 0.25)]:
			pts.append(_p(o + a * corner.x + n * (d - 0.02), corner.y))
		_quad("glass", pts, Vector3(n.x, 0.0, -n.y), Color.WHITE, false)
	_solid(o, a, s0, s1, 0.0, d, 0.0, top)


## A table of fruit and vegetables in crates, centred at c (1.2 x 2.0 m along v).
func _produce_table(c: Vector2) -> void:
	var u0 := c.x - 0.6
	var u1 := c.x + 0.6
	var v0 := c.y - 1.0
	var v1 := c.y + 1.0
	var wood := {"sides": "wood", "top": "wood", "bottom": ""}
	_abox(wood, u0 + 0.05, u1 - 0.05, v0 + 0.05, v1 - 0.05, 0.0, 0.7)
	_solid(Vector2.ZERO, Vector2.RIGHT, u0, u1, v0, v1, 0.0, 0.85)
	var fruit := [Color(0.85, 0.12, 0.08), Color(0.95, 0.55, 0.08), Color(0.95, 0.85, 0.2), Color(0.35, 0.65, 0.15),
		Color(0.45, 0.12, 0.35), Color(0.6, 0.4, 0.2), Color(0.85, 0.75, 0.55), Color(0.2, 0.45, 0.12)]
	var gm := {"sides": "goods", "top": "goods", "bottom": ""}
	for i in 2:
		for j in 3:
			var cu0 := u0 + i * 0.6 + 0.03
			var cv0 := v0 + j * (2.0 / 3.0) + 0.03
			var cu1 := cu0 + 0.54
			var cv1 := cv0 + 2.0 / 3.0 - 0.06
			_abox(wood, cu0, cu1, cv0, cv1, 0.7, 0.74)
			for side: Array in [[cu0, cu0 + 0.02, cv0, cv1], [cu1 - 0.02, cu1, cv0, cv1], [cu0, cu1, cv0, cv0 + 0.02], [cu0, cu1, cv1 - 0.02, cv1]]:
				_abox(wood, side[0], side[1], side[2], side[3], 0.74, 0.86)
			var base: Color = fruit[_rng.randi_range(0, fruit.size() - 1)]
			var size := _rng.randf_range(0.07, 0.1)
			var u := cu0 + 0.03
			while u < cu1 - 0.03 - size:
				var v := cv0 + 0.03
				while v < cv1 - 0.03 - size:
					var col := base * _rng.randf_range(0.8, 1.1)
					col.a = 1.0
					var y := 0.74 + _rng.randf_range(0.0, 0.06)
					_abox(gm, u, u + size, v, v + size, y, y + size, col.srgb_to_linear())
					v += size + 0.01
				u += size + 0.01


## A till: the counter with its belt along v at u = uc, the register at the
## front end on the cashier's side (+u), a stool and a lamp post with the
## number.
func _till(uc: float) -> void:
	var v0 := TILL_V.x
	var v1 := TILL_V.y
	var dm := {"sides": "dark", "top": "dark", "bottom": ""}
	_abox(dm, uc - 0.4, uc + 0.4, v0, v1, 0.0, 0.88)
	_abox({"sides": "belt", "top": "belt", "bottom": ""}, uc - 0.32, uc - 0.02, v0 + 1.1, v1 - 0.1, 0.88, 0.9)
	_abox({"sides": "metal", "top": "metal", "bottom": ""}, uc - 0.4, uc + 0.4, v0, v0 + 1.0, 0.88, 0.9)
	_solid(Vector2.ZERO, Vector2.RIGHT, uc - 0.4, uc + 0.4, v0, v1, 0.0, 0.9)
	# Register and screen on the cashier's side.
	_abox(dm, uc + 0.1, uc + 0.38, v0 + 0.25, v0 + 0.6, 0.9, 1.05)
	_obox(dm, Vector2(uc + 0.24, v0 + 0.75), Vector2.RIGHT, -0.15, 0.15, -0.02, 0.02, 0.95, 1.25)
	# The cashier's stool.
	var su := uc + 0.75
	var sv := v0 + 0.55
	_abox({"sides": "steel", "top": "steel", "bottom": ""}, su - 0.03, su + 0.03, sv - 0.03, sv + 0.03, 0.0, 0.62)
	_abox({"sides": "dark", "top": "dark", "bottom": ""}, su - 0.2, su + 0.2, sv - 0.2, sv + 0.2, 0.62, 0.68)
	# Lamp post at the front corner with the till's light.
	_abox({"sides": "steel", "top": "steel", "bottom": ""}, uc - 0.38, uc - 0.34, v0 + 0.02, v0 + 0.06, 0.9, 2.0)
	_abox({"sides": "white", "bottom": "white", "top": "panel"}, uc - 0.46, uc - 0.26, v0 - 0.06, v0 + 0.14, 2.0, 2.2)


## Inside the main doors: lockers against the right-hand wall and a stack of baskets.
func _entry_fittings(inner: PackedVector2Array) -> void:
	var right_a := inner[2]
	var right_b := inner[3]
	var dir := (right_b - right_a).normalized()
	var s0 := (1.9 - right_a.y) / dir.y
	var s1 := (ENTRY_DEPTH - 0.4 - right_a.y) / dir.y
	_obox({"sides": "steel", "top": "steel", "bottom": ""}, right_a, dir, s0, s1, 0.0, 0.5, 0.0, 1.8, Color.WHITE, false)
	_solid(right_a, dir, s0, s1, 0.0, 0.5, 0.0, 1.8)
	var dm := {"sides": "dark", "top": "", "bottom": ""}
	var cols := maxi(1, floori((s1 - s0) / 0.4))
	for i in cols + 1:
		var s := lerpf(s0, s1, float(i) / cols)
		_obox(dm, right_a, dir, s - 0.008, s + 0.008, 0.5, 0.505, 0.0, 1.8)
	for row in range(1, 4):
		_obox(dm, right_a, dir, s0, s1, 0.5, 0.505, row * 0.45 - 0.008, row * 0.45 + 0.008)
	var red := {"sides": "red", "top": "red", "bottom": "red"}
	var bu := PHARMACY.x + 9.0
	for k in 8:
		var y := k * 0.07
		_abox(red, bu, bu + 0.5, 4.2, 4.55, y, y + 0.05)
	_solid(Vector2.ZERO, Vector2.RIGHT, bu, bu + 0.5, 4.2, 4.55, 0.0, 0.6)


## The pharmacy: a counter across the room, shelves of medicine behind it on
## the back wall, and a display on the wall to the shop.
func _pharmacy_fittings(inner: PackedVector2Array) -> void:
	var h := INNER * 0.5
	var right := PHARMACY.x - h
	var back := PHARMACY.y - h
	var left_at_counter := right - _hit(inner, Vector2(right, 3.6), Vector2.LEFT)
	var cu0 := left_at_counter + 0.05
	var cu1 := right - 1.1
	var wm := {"sides": "white", "top": "white", "bottom": ""}
	_abox(wm, cu0, cu1, 3.3, 3.9, 0.0, 1.0, Color.WHITE, true)
	_abox({"sides": "green", "top": "", "bottom": ""}, cu0, cu1, 3.29, 3.3, 0.75, 0.95)
	_abox({"sides": "dark", "top": "dark", "bottom": ""}, cu1 - 1.2, cu1 - 0.85, 3.45, 3.75, 1.0, 1.12)
	# Medicine along the back wall, between the counter's end and the right-hand wall.
	var left_at_back := right - _hit(inner, Vector2(right, back - 0.45), Vector2.LEFT)
	_shelf_run(Vector2(right - 0.05, back), Vector2.LEFT, 0.0, right - left_at_back - 0.15, 0.4, 5)
	# A display on the wall to the shop, by the door.
	_shelf_run(Vector2(right, 0.8), Vector2(0, 1), 0.0, 1.9, 0.4, 4)


## The store room: racks of boxes along its right-hand wall and pallets.
func _store_room_fittings(inner: PackedVector2Array) -> void:
	var h := INNER * 0.5
	var right_a := inner[2]
	var right_b := inner[3]
	var dir := (right_b - right_a).normalized()
	var s0 := (STORE_ROOM.y + h + 0.3 - right_a.y) / dir.y
	var s1 := s0 + 6.0
	var back_hit := _hit(inner, right_a + dir * s0 + Vector2.LEFT * 0.5, dir)
	s1 = minf(s1, s0 + back_hit - 0.4)
	_rack(right_a, dir, s0, s1)
	for c: Vector2 in [Vector2(STORE_ROOM.x + 1.6, STORE_ROOM.y + 3.0), Vector2(STORE_ROOM.x + 1.6, STORE_ROOM.y + 5.0),
			Vector2(STORE_ROOM.x + 3.3, STORE_ROOM.y + 4.0)]:
		_pallet(c)


func _rack(o: Vector2, a: Vector2, s0: float, s1: float) -> void:
	var depth := 0.9
	var um := {"sides": "upright", "top": "upright", "bottom": ""}
	var rm := {"sides": "rack", "top": "rack", "bottom": ""}
	var bays := maxi(1, roundi((s1 - s0) / 2.0))
	for k in bays + 1:
		var s := lerpf(s0, s1, float(k) / bays)
		for c: float in [0.05, depth - 0.05]:
			_obox(um, o, a, s - 0.04, s + 0.04, c - 0.04, c + 0.04, 0.0, 3.2)
	for y: float in [0.15, 1.2, 2.25]:
		for c: float in [0.05, depth - 0.05]:
			_obox(rm, o, a, s0, s1, c - 0.03, c + 0.03, y, y + 0.1)
		var s := s0 + 0.1
		while s < s1 - 0.5:
			var w := _rng.randf_range(0.4, 0.7)
			var ht := _rng.randf_range(0.3, 0.8)
			var col := Color(1, 1, 1) * _rng.randf_range(0.85, 1.1)
			_obox({"sides": "cardboard", "top": "cardboard", "bottom": ""}, o, a, s, minf(s + w, s1 - 0.1), 0.1,
				depth - 0.1, y + 0.1, y + 0.1 + ht, col)
			s += w + 0.05
	_solid(o, a, s0, s1, 0.0, depth, 0.0, 3.2)


func _pallet(c: Vector2) -> void:
	var pm := {"sides": "pallet", "top": "pallet", "bottom": ""}
	_abox(pm, c.x - 0.6, c.x + 0.6, c.y - 0.4, c.y + 0.4, 0.0, 0.14)
	var layers := _rng.randi_range(2, 4)
	var cm := {"sides": "cardboard", "top": "cardboard", "bottom": ""}
	for l in layers:
		for i in 2:
			for j in 2:
				var u := c.x - 0.58 + i * 0.58
				var v := c.y - 0.38 + j * 0.38
				_abox(cm, u + 0.01, u + 0.57, v + 0.01, v + 0.37, 0.14 + l * 0.35, 0.14 + l * 0.35 + 0.34)
	_solid(Vector2.ZERO, Vector2.RIGHT, c.x - 0.6, c.x + 0.6, c.y - 0.4, c.y + 0.4, 0.0, 0.14 + layers * 0.35)


# --- the guard's booth ------------------------------------------------------------------

func _build_booth(world_outline: PackedVector2Array, info: Dictionary) -> Node3D:
	# Its door is in the side facing south (towards the street): find that side
	# and its left and right ends as seen from outside.
	var n := world_outline.size()
	var centre := Vector2.ZERO
	for w in world_outline:
		centre += w / n
	var best := -INF
	var left := Vector2.ZERO
	var right := Vector2.ZERO
	for k in n:
		var a := world_outline[k]
		var b := world_outline[(k + 1) % n]
		var d := (b - a).normalized()
		var out := Vector2(d.y, -d.x)
		if out.dot((a + b) * 0.5 - centre) < 0.0:
			out = -out
		if out.y > best:
			best = out.y
			var r := Vector2(out.y, -out.x)
			left = a if a.dot(r) < b.dot(r) else b
			right = b if a.dot(r) < b.dot(r) else a
	_set_frame(left, right)
	var fp := _plan_poly(world_outline)
	if _area(fp) < 0.0:
		fp.reverse()
	var start := 0
	for k in n:
		if fp[k].length() < 0.01:
			start = k
	var ordered := PackedVector2Array()
	for k in n:
		ordered.append(fp[(start + k) % n])
	fp = ordered
	var inner := _inset(fp, BOOTH_WALL)

	var low := INF
	var high := -INF
	for w in world_outline:
		var g := MapKit.height_at(w.x, w.y)
		low = minf(low, g)
		high = maxf(high, g)
	var floor_y := high + 0.15
	var height: float = info["height"]
	var top := high + height - floor_y
	var base := low - 0.5 - floor_y
	var wall_color: Color = info["wall"]
	var roof_color: Color = info["roof"]
	var wall_col := wall_color.srgb_to_linear()
	wall_col.a = 0.5
	var roof_col := roof_color.srgb_to_linear()
	roof_col.a = 0.0

	_begin()
	var booth := Node3D.new()
	booth.name = "GuardBooth"
	booth.transform = _frame_xf(floor_y)
	var doors := Node3D.new()
	doors.name = "Doors"
	booth.add_child(doors)
	var width := fp[0].distance_to(fp[1])
	var depth := fp[1].distance_to(fp[2])
	var t := BOOTH_WALL
	# Openings per side: front (door and a window), right (towards the shop), back, left (towards the road).
	var win := Vector2(0.95, 2.0)
	var sides := [
		[[BOOTH_DOOR.x, BOOTH_DOOR.y, -0.01, DOOR_HEIGHT], [0.35, 1.3, win.x, win.y]],
		[[depth * 0.5 - 0.7, depth * 0.5 + 0.7, win.x, win.y]],
		[],
		[[depth * 0.5 - 0.6, depth * 0.5 + 0.6, win.x, win.y]],
	]
	var ext := {"outer": "ext", "inner": "plaster", "ends": "plaster", "top": "plaster"}
	for k in 4:
		var a := fp[k]
		var b := fp[(k + 1) % 4]
		var openings: Array = sides[k]
		_wall(a, b, inner[k], inner[(k + 1) % 4], base, BOOTH_CEILING + 0.15, openings, ext, wall_col)
		var dir := (b - a).normalized()
		for o: Array in openings:
			if o[2] > 0.0:
				_window(a, dir, o[0], o[1], o[2], o[3], 0.0, t)
	# A flat roof slab overhanging the walls a little.
	var roof: PackedVector2Array = Geometry2D.offset_polygon(fp, 0.2, Geometry2D.JOIN_MITER)[0]
	var rb := BOOTH_CEILING + 0.15
	_hpoly("ext", roof, top, true, roof_col, true)
	_hpoly("concrete", roof, rb, false, Color.WHITE, false)
	for k in roof.size():
		var a := roof[k]
		var b := roof[(k + 1) % roof.size()]
		var d := (b - a).normalized()
		_quad("concrete", [_p(a, rb), _p(b, rb), _p(b, top), _p(a, top)], Vector3(d.y, 0.0, d.x), Color.WHITE, false)
	_hpoly("ceiling", inner, BOOTH_CEILING, false, Color.WHITE, false)
	_hpoly("floor", fp, 0.0, true, Color(1, 1, 1, 1.0))
	_swing_door(doors, "Door", Vector2.ZERO, Vector2.RIGHT, BOOTH_DOOR.x, BOOTH_DOOR.y, t * 0.5, t * 0.5, Vector2(0, 1), "steel")
	# A concrete step out of the door down to the ground.
	var g := MapKit.height_at(_to_world(Vector2((BOOTH_DOOR.x + BOOTH_DOOR.y) * 0.5, -0.8)).x,
		_to_world(Vector2((BOOTH_DOOR.x + BOOTH_DOOR.y) * 0.5, -0.8)).y) + 0.03 - floor_y
	var su0 := BOOTH_DOOR.x - 0.15
	var su1 := BOOTH_DOOR.y + 0.15
	_abox({"sides": "concrete", "top": "concrete", "bottom": ""}, su0, su1, -0.45, 0.0, base, 0.0)
	_hulls.append(PackedVector3Array([_p(Vector2(su0, 0.0), 0.0), _p(Vector2(su1, 0.0), 0.0), _p(Vector2(su0, -0.45), 0.0),
		_p(Vector2(su1, -0.45), 0.0), _p(Vector2(su0, -0.9), g), _p(Vector2(su1, -0.9), g),
		_p(Vector2(su0, 0.0), base), _p(Vector2(su1, 0.0), base), _p(Vector2(su0, -0.9), base), _p(Vector2(su1, -0.9), base)]))

	# Inside: the bed along the left-hand wall at the back, a table under the
	# right-hand window with a chair, and a lamp.
	var wood := {"sides": "wood", "top": "wood", "bottom": ""}
	var bu0 := t + 0.03
	var bv1 := depth - t - 0.03
	var bv0 := bv1 - 1.95
	_abox(wood, bu0, bu0 + 0.85, bv0, bv1, 0.0, 0.32, Color.WHITE, true)
	_abox(wood, bu0, bu0 + 0.85, bv1 - 0.04, bv1, 0.32, 0.75)
	_abox({"sides": "linen", "top": "linen", "bottom": ""}, bu0 + 0.03, bu0 + 0.82, bv0 + 0.02, bv1 - 0.05, 0.32, 0.48)
	_abox({"sides": "blanket", "top": "blanket", "bottom": ""}, bu0 + 0.01, bu0 + 0.84, bv0, bv1 - 0.55, 0.42, 0.52)
	_abox({"sides": "linen", "top": "linen", "bottom": ""}, bu0 + 0.12, bu0 + 0.73, bv1 - 0.5, bv1 - 0.12, 0.48, 0.6)
	var tu1 := width - t - 0.03
	var tv := depth * 0.5
	_abox(wood, tu1 - 0.6, tu1, tv - 0.4, tv + 0.4, 0.72, 0.76, Color.WHITE, true)
	for leg: Vector2 in [Vector2(tu1 - 0.57, tv - 0.37), Vector2(tu1 - 0.03, tv - 0.37), Vector2(tu1 - 0.57, tv + 0.37), Vector2(tu1 - 0.03, tv + 0.37)]:
		_abox(wood, leg.x - 0.025, leg.x + 0.025, leg.y - 0.025, leg.y + 0.025, 0.0, 0.72)
	var cu := tu1 - 0.95
	_abox(wood, cu - 0.2, cu + 0.2, tv - 0.2, tv + 0.2, 0.42, 0.46)
	_abox(wood, cu - 0.22, cu - 0.18, tv - 0.2, tv + 0.2, 0.46, 0.9)
	for leg: Vector2 in [Vector2(-0.17, -0.17), Vector2(0.17, -0.17), Vector2(-0.17, 0.17), Vector2(0.17, 0.17)]:
		_abox(wood, cu + leg.x - 0.02, cu + leg.x + 0.02, tv + leg.y - 0.02, tv + leg.y + 0.02, 0.0, 0.42)
	_abox({"sides": "dark", "top": "dark", "bottom": ""}, tu1 - 0.45, tu1 - 0.1, tv + 0.05, tv + 0.3, 0.76, 0.79)
	_abox({"sides": "white", "bottom": "panel", "top": "white"}, width * 0.5 - 0.15, width * 0.5 + 0.15, depth * 0.5 - 0.15,
		depth * 0.5 + 0.15, BOOTH_CEILING - 0.05, BOOTH_CEILING)
	var lamp := OmniLight3D.new()
	lamp.name = "Lamp"
	lamp.position = _p(Vector2(width * 0.5, depth * 0.5), BOOTH_CEILING - 0.3)
	lamp.light_energy = 0.6
	lamp.omni_range = 4.0
	lamp.light_color = Color(1.0, 0.9, 0.78)
	booth.add_child(lamp)
	_finish(booth)
	return booth


# --- the parking lot ---------------------------------------------------------------------

## The lot's outline (world x, z): round from the north-west corner, along the
## shop's front walls, and back along the street and the highway.
func _parking_outline(store_outline: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Vector2 in PARK_NORTH:
		out.append(p)
	out.append_array([store_outline[4], store_outline[3], store_outline[2]])
	for p: Vector2 in PARK_SOUTH:
		out.append(p)
	return out


## Height of the lot's surface (world): just above the ground, rising to the
## shop floor along the shopfront.
func _park_height(w: Vector2, shop_poly: PackedVector2Array) -> float:
	var y := MapKit.height_at(w.x, w.y) + 0.03
	var d := _dist_to_poly(w, shop_poly)
	if d < RAMP:
		y = maxf(y, lerpf(_floor_y, y, smoothstep(0.0, RAMP, d)))
	return y


func _build_parking(park: PackedVector2Array, store_outline: PackedVector2Array, booth_outline: PackedVector2Array) -> Node3D:
	_begin()
	var lot := Node3D.new()
	lot.name = "ParkingLot"
	var asphalt := Color(0.13, 0.13, 0.135)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in park:
		lo = lo.min(p)
		hi = hi.max(p)
	var cell := 1.0
	var x := floorf(lo.x)
	var buf: Buf = _bufs["asphalt"]
	var h := func(p: Vector2) -> float: return _park_height(p, store_outline)
	while x < hi.x:
		var z := floorf(lo.y)
		while z < hi.y:
			var sq := PackedVector2Array([Vector2(x, z), Vector2(x + cell, z), Vector2(x + cell, z + cell), Vector2(x, z + cell)])
			for piece: PackedVector2Array in Geometry2D.intersect_polygons(sq, park):
				var tris := Geometry2D.triangulate_polygon(piece)
				for k in range(0, tris.size(), 3):
					var pts := []
					for m in 3:
						var q := piece[tris[k + m]]
						var y: float = h.call(q)
						pts.append(Vector3(q.x, y, q.y))
					var a: Vector3 = pts[0]
					var b: Vector3 = pts[1]
					var c: Vector3 = pts[2]
					if (b.x - a.x) * (c.z - a.z) - (b.z - a.z) * (c.x - a.x) < 0.0:
						pts = [a, c, b]
					for q: Vector3 in pts:
						var p2 := Vector2(q.x, q.z)
						var dx: float = h.call(p2 + Vector2(0.3, 0.0)) - h.call(p2 - Vector2(0.3, 0.0))
						var dz: float = h.call(p2 + Vector2(0.0, 0.3)) - h.call(p2 - Vector2(0.0, 0.3))
						var nrm := Vector3(-dx, 0.6, -dz).normalized()
						buf.idx.append(buf.add(q, nrm, asphalt, p2, Vector2.ZERO))
						_faces.append(q)
			z += cell
		x += cell
	# A skirt down into the ground round the open edges.
	for k in park.size():
		var a := park[k]
		var b := park[(k + 1) % park.size()]
		if _dist_to_poly((a + b) * 0.5, store_outline) < 0.05:
			continue
		var steps := maxi(1, ceili(a.distance_to(b)))
		var d := (b - a).normalized()
		var out := Vector3(d.y, 0.0, -d.x) * (1.0 if _area(park) > 0.0 else -1.0)
		for s in steps:
			var p0 := a.lerp(b, float(s) / steps)
			var p1 := a.lerp(b, float(s + 1) / steps)
			var y0: float = h.call(p0)
			var y1: float = h.call(p1)
			var g0 := MapKit.height_at(p0.x, p0.y) - 0.3
			var g1 := MapKit.height_at(p1.x, p1.y) - 0.3
			_quad("asphalt", [Vector3(p0.x, y0, p0.y), Vector3(p1.x, y1, p1.y), Vector3(p1.x, g1, p1.y), Vector3(p0.x, g0, p0.y)],
				out, asphalt, false)

	# Markings, laid out in the shop's plan.
	_set_frame(store_outline[4], store_outline[3])
	var inside := Geometry2D.offset_polygon(park, -0.3)
	var keep: PackedVector2Array = inside[0] if not inside.is_empty() else park
	var paint := Color(0.8, 0.8, 0.76)
	paint.a = 0.0
	var lines := {}
	for row: Vector2 in [ROW_SHOP, ROW_ROAD]:
		var u := -10.5
		while u < 40.0:
			var bay := PackedVector2Array([_to_world(Vector2(u, row.x)), _to_world(Vector2(u + BAY, row.x)),
				_to_world(Vector2(u + BAY, row.y)), _to_world(Vector2(u, row.y))])
			var ok := true
			for p in bay:
				if not Geometry2D.is_point_in_polygon(p, keep) or _dist_to_poly(p, booth_outline) < 0.8:
					ok = false
			if u + BAY > CROSSING.x - 0.8 and u < CROSSING.y + 0.8 and row == ROW_SHOP:
				ok = false
			if ok:
				for e: float in [u, u + BAY]:
					lines["%.2f_%.2f" % [e, row.x]] = [Vector2(e, row.x), Vector2(e, row.y)]
			u += BAY
	for key: String in lines:
		var seg: Array = lines[key]
		_paint_strip(seg[0], seg[1], 0.1, paint, store_outline)
	var zebra := Color(0.85, 0.85, 0.8)
	zebra.a = 0.0
	var su := CROSSING.x
	while su < CROSSING.y - 0.2:
		_paint_strip(Vector2(su + 0.25, ROW_ROAD.y), Vector2(su + 0.25, ROW_SHOP.x), 0.5, zebra, store_outline)
		su += 1.0
	_finish(lot)
	return lot


## A painted strip `width` wide along the plan line a..b, on the lot's surface.
func _paint_strip(a: Vector2, b: Vector2, width: float, col: Color, store_outline: PackedVector2Array) -> void:
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x) * width * 0.5
	var steps := maxi(1, ceili(a.distance_to(b) / 1.0))
	for s in steps:
		var p0 := a.lerp(b, float(s) / steps)
		var p1 := a.lerp(b, float(s + 1) / steps)
		var pts := []
		for q: Vector2 in [p0 - n, p1 - n, p1 + n, p0 + n]:
			var w := _to_world(q)
			pts.append(Vector3(w.x, _park_height(w, store_outline) + 0.005, w.y))
		_quad("asphalt", pts, Vector3.UP, col, false)
