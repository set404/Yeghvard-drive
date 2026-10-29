extends SceneTree
## Headless check: how often the traffic's cars hit things.
## Run:  godot --headless --fixed-fps 60 --path . --script res://tools/traffic_test.gd [-- seconds]


var _hits := {} ## "kind" -> count
var _log: Array[String] = []
var _t := 0.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var seconds := 120.0
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		seconds = float(args[0])
	var main: Node3D = load("res://main.tscn").instantiate()
	root.add_child(main)
	while main.get_node_or_null("Traffic") == null:
		await process_frame
	var traffic: Node3D = main.get_node("Traffic")
	# A second argument: the traffic script to try instead of world/traffic.gd ("" for none).
	if args.size() > 1 and args[1] != "":
		traffic.free()
		traffic = load(args[1]).new()
		traffic.name = "Traffic"
		main.add_child(traffic)
	# Third and fourth: x and z to stand at, so the traffic is round there.
	if args.size() > 3:
		var you := main.get("player") as Node3D
		await physics_frame
		you.global_position = Vector3(float(args[2]), you.global_position.y, float(args[3]))
		var space := main.get_world_3d().direct_space_state
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(you.global_position + Vector3.UP * 300.0, you.global_position + Vector3.DOWN * 300.0))
		if hit:
			you.global_position.y = (hit["position"] as Vector3).y + 1.0
	var watched := {}
	var frames := int(seconds * 60.0)
	var stops := 0
	var max_speed := 0.0
	var red_runs := 0
	var red_stops := 0
	var last_pos := {}
	for f in frames:
		await physics_frame
		_t = f / 60.0
		# A traffic car crossing a stop line on red (more than 1.5 m in, so not one
		# that stopped with its nose just over).
		for d in traffic.get("_drivers"):
			var now: Vector3 = d.car.global_position + d.car.global_basis.z * 2.3
			var before: Vector3 = last_pos.get(d.car, now)
			last_pos[d.car] = now
			for light: Node3D in get_nodes_in_group("traffic_lights"):
				var line: PackedVector3Array = light.call("stop_line")
				var cross: Variant = Geometry2D.segment_intersects_segment(Vector2(before.x, before.z), Vector2(now.x, now.z),
					Vector2(line[0].x, line[0].z), Vector2(line[1].x, line[1].z))
				if cross != null and light.get("state") == 0:
					red_runs += 1
					_log.append("%.1f s %s ran the red at %s, %.0f km/h" % [_t, d.car.name, light.name, d.car.linear_velocity.length() * 3.6])
			if d.blocker is Node3D and d.blocker.is_in_group("traffic_lights") and d.car.call("forward_speed") < 0.5 and f % 60 == 0:
				red_stops += 1
		for car: Node in traffic.get_children():
			if car is VehicleBody3D and not watched.has(car):
				watched[car] = true
				car.contact_monitor = true
				car.max_contacts_reported = 4
				car.body_entered.connect(_on_hit.bind(car))
		if f % 6 == 0:
			for d in traffic.get("_drivers"):
				_side_sample(traffic, d)
		if f % 60 == 0:
			for d in traffic.get("_drivers"):
				max_speed = maxf(max_speed, d.car.call("forward_speed"))
				if d.car.call("forward_speed") < 0.5:
					stops += 1
	print("--- %d s, %d cars seen, max speed %.0f km/h, car-seconds standing %d" % [seconds, watched.size(), max_speed * 3.6, stops])
	print("  traffic lights: %d car-seconds waiting at a red, %d ran a red" % [red_stops, red_runs])
	for d in traffic.get("_drivers"):
		if d.car.call("forward_speed") < 0.5:
			print("  standing: %s at %s, waiting for %s %.1f m ahead, stuck %.0f s, blocked %.0f s" % [d.car.name,
				d.car.global_position.snapped(Vector3.ONE), d.blocker.name if is_instance_valid(d.blocker) else "nothing",
				d.gap, d.stuck_for, d.blocked_for])
			if not is_instance_valid(d.blocker):
				var ahead := []
				for j in range(d.k, mini(d.k + 6, d.nodes.size())):
					ahead.append(d.nodes[j])
				print("    allowed %.1f cruise %.1f ends %s k %d/%d nodes %s gas %.2f brake %.2f steer %.2f" % [d.allowed, d.cruise,
					d.ends, d.k, d.pts.size(), ahead, d.car.get("ai_gas"), d.car.get("ai_brake"), d.car.get("ai_steer")])
	var clear: Variant = traffic.get("_e_clear")
	if clear is PackedByteArray:
		print("  lanes tested %d, blocked %d" % [clear.count(1) + clear.count(2), clear.count(2)])
	for kind in _side:
		var s: Array = _side[kind]
		print("  %s: %d samples, %.1f%% body over the centre line, %.1f%% centre over, deepest %.1f m over; line itself over %.1f%%" % [
			kind, s[0], 100.0 * s[1] / maxf(s[0], 1), 100.0 * s[2] / maxf(s[0], 1), s[3], 100.0 * s[4] / maxf(s[0], 1)])
	for line in _detail:
		print("    " + line)
	# The lines themselves: points nearer the centre of a two-way piece beside them than 0.75 m.
	var pos: PackedVector3Array = traffic.get("_pos")
	var two: PackedByteArray = traffic.get("_e_two_way")
	var checked := 0
	var near := 0
	var worst := INF
	for d in traffic.get("_drivers"):
		for i in d.pts.size():
			for j in [i - 1, i]:
				if j < 0 or j + 1 >= d.nodes.size() or two[d.edges[j]] == 0:
					continue
				var a: Vector3 = pos[d.nodes[j]]
				var ab: Vector3 = pos[d.nodes[j + 1]] - a
				ab.y = 0.0
				var rel: Vector3 = d.pts[i] - a
				rel.y = 0.0
				var t := rel.dot(ab) / maxf(ab.length_squared(), 0.0001)
				if t < 0.0 or t > 1.0:
					continue
				var lat := rel.dot(ab.normalized().cross(Vector3.UP))
				checked += 1
				worst = minf(worst, lat)
				if lat < 0.75:
					near += 1
	print("  line points checked %d, nearer the centre than 0.75 m: %d, nearest %.2f m" % [checked, near, worst])
	for k in _hits:
		print("  %s: %d" % [k, _hits[k]])
	for line in _log.slice(0, 40):
		print("    " + line)
	quit()


## kind -> [samples, body over, centre over, deepest metres the body is over] of
## moving cars over their road's centre line (a car is 1.8 m wide), on two-way
## roads; a turn is within 10 m of a bend of 30°+.
var _side := {"left turn": [0, 0, 0, 0.0, 0], "right turn": [0, 0, 0, 0.0, 0], "straight": [0, 0, 0, 0.0, 0]}


var _detail: Array[String] = []


func _side_sample(traffic: Node, d: Object) -> void:
	var car: VehicleBody3D = d.car
	if car.call("forward_speed") < 1.0:
		return
	var pos: PackedVector3Array = traffic.get("_pos")
	var outs: Array = traffic.get("_out")
	var e_to: PackedInt32Array = traffic.get("_e_to")
	var nodes: PackedInt32Array = d.nodes
	var p := car.global_position
	p.y = 0.0
	var best := INF
	var lateral := 0.0
	var best_j := -1
	for j in range(maxi(d.k - 3, 0), mini(d.k + 4, nodes.size() - 1)):
		var a := pos[nodes[j]]
		var b := pos[nodes[j + 1]]
		a.y = 0.0
		b.y = 0.0
		var c := Geometry3D.get_closest_point_to_segment(p, a, b)
		if c.distance_to(p) < best:
			best = c.distance_to(p)
			best_j = j
			lateral = (p - c).dot((b - a).normalized().cross(Vector3.UP))
	if best_j < 0 or best > 8.0:
		return
	# Two-way only: the way back must exist.
	var back := false
	for e in outs[nodes[best_j + 1]]:
		if e_to[e] == nodes[best_j]:
			back = true
	if not back:
		return
	var turning := "straight"
	var sharpest := cos(deg_to_rad(30.0))
	for j in range(maxi(best_j - 3, 1), mini(best_j + 4, nodes.size() - 1)):
		var a := pos[nodes[j]] - pos[nodes[j - 1]]
		var b := pos[nodes[j + 1]] - pos[nodes[j]]
		a.y = 0.0
		b.y = 0.0
		if a.length() > 0.01 and b.length() > 0.01 and a.normalized().dot(b.normalized()) < sharpest:
			sharpest = a.normalized().dot(b.normalized())
			turning = "right turn" if b.dot(a.cross(Vector3.UP)) > 0.0 else "left turn"
	var s: Array = _side[turning]
	# Where the line it follows is, beside the car: over too, or the car off it?
	var pts: PackedVector3Array = d.pts
	var line_lat := INF
	var line_d := INF
	var a0 := pos[nodes[best_j]]
	var b0 := pos[nodes[best_j + 1]]
	a0.y = 0.0
	b0.y = 0.0
	var normal := (b0 - a0).normalized().cross(Vector3.UP)
	for j in range(maxi(d.k - 3, 0), mini(d.k + 4, pts.size() - 1)):
		var pa := pts[j]
		var pb := pts[j + 1]
		pa.y = 0.0
		pb.y = 0.0
		var c := Geometry3D.get_closest_point_to_segment(p, pa, pb)
		if c.distance_to(p) < line_d:
			line_d = c.distance_to(p)
			line_lat = (c - Geometry3D.get_closest_point_to_segment(c, a0, b0)).dot(normal)
	if line_lat < 0.9:
		s[4] += 1
	if lateral < -0.5 and _detail.size() < 25:
		_detail.append("%s at %s: car %.1f m, its line %.1f m right of centre; car %.1f m off line, %.0f km/h, centre piece %d (k %d), junction nodes %s" % [
			turning, car.global_position.snapped(Vector3.ONE), lateral, line_lat, line_d, car.call("forward_speed") * 3.6, best_j, d.k,
			str(range(maxi(best_j - 3, 0), mini(best_j + 4, nodes.size())).filter(func(j: int) -> bool: return outs[nodes[j]].size() > 2))])
	s[0] += 1
	if lateral < 0.9:
		s[1] += 1
	if lateral < 0.0:
		s[2] += 1
	s[3] = maxf(s[3], 0.9 - lateral)


func _on_hit(body: Node, car: VehicleBody3D) -> void:
	if body is VehicleBody3D:
		# Counted once per pair.
		if body.get("ai_driven") and body.get_instance_id() < car.get_instance_id():
			return
		var kind := "car-traffic" if body.get("ai_driven") else "car-other"
		_hits[kind] = _hits.get(kind, 0) + 1
		_log.append("%.1f s %s hit %s (%s) at %.0f km/h" % [_t, car.name, body.name, kind, car.linear_velocity.length() * 3.6])
		return
	if body is CharacterBody3D:
		_hits["person"] = _hits.get("person", 0) + 1
		_log.append("%.1f s %s hit person %s" % [_t, car.name, body.name])
		return
	var name := String(body.name)
	if name.begins_with("Terrain") or name.begins_with("Chunk") or name.contains("Road"):
		return
	_hits["static"] = _hits.get("static", 0) + 1
	var off := "?"
	var d: Variant = car.get_parent().call("_driver_of", car) if car.get_parent().has_method("_driver_of") else null
	if d:
		# How far the car is from its lane, and where on its way.
		var p := car.global_position
		var best := INF
		for i in range(maxi(d.k - 2, 0), mini(d.k + 4, d.pts.size() - 1)):
			best = minf(best, Geometry3D.get_closest_point_to_segment(p, d.pts[i], d.pts[i + 1]).distance_to(p))
		off = "%.1f m off lane, k %d/%d, steer %.2f, at %s" % [best, d.k, d.pts.size(), car.steering, p.snapped(Vector3.ONE)]
	_log.append("%.1f s %s hit %s at %.0f km/h, %s" % [_t, car.name, body.get_path(), car.linear_velocity.length() * 3.6, off])
