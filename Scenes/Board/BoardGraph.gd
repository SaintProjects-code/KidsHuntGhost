class_name BoardGraph
extends RefCounted
## The movement graph Board builds from the map: towns/junctions (nodes),
## roads (routes) and the stops along each road, plus the polyline maths that
## keeps tokens on the drawn lines. Pure data — no nodes, no tokens.

var map                          # the Map1 instance (read-only source)
var routes: Array = []           # the map's route dictionaries
var cities: Array = []           # town names
var node_pos: Dictionary = {}    # name -> Vector2 world position
var node_routes: Dictionary = {} # name -> Array[int] incident route indices
var stops: Array = []            # per route: Array[Vector2] = [from, spaces..., to]
var poly: Array = []             # per route: world polyline (from, corners.., to)
var stop_dist: Array = []        # per route: arc-length of each stop along the polyline
var route_space_start: Array = []# per route: index into map.spaces of its first space

func _init(source_map) -> void:
	map = source_map
	routes = map.ROUTES
	cities = map.CITIES
	for k in map.NODES:
		node_pos[k] = _world(map.NODES[k])
	# Slice each road's stops out of the spaces the map already drew, so tokens
	# land exactly on the visible circles.
	var idx := 0
	for r in routes.size():
		var route: Dictionary = routes[r]
		var cells: Array = [map.NODES[route["from"]]]
		cells.append_array(route["corners"])
		cells.append(map.NODES[route["to"]])
		var world_poly: Array = cells.map(_world)
		var total := 0.0
		for i in world_poly.size() - 1:
			total += world_poly[i].distance_to(world_poly[i + 1])
		poly.append(world_poly)
		var n: int = route.get("spaces", -1)
		if n < 0:
			n = int(round(total / map.SPACING))
		if total <= 0.0:
			n = 0
		route_space_start.append(idx)
		var seg: Array = map.spaces.slice(idx, idx + n)
		idx += n
		stops.append([node_pos[route["from"]]] + seg + [node_pos[route["to"]]])
		# spaces aren't evenly spaced, so measure each one's true distance
		var dists: Array = [0.0]
		for sp in seg:
			dists.append(arc_length_of(world_poly, sp))
		dists.append(total)
		stop_dist.append(dists)
		for end in [route["from"], route["to"]]:
			if not node_routes.has(end):
				node_routes[end] = []
			node_routes[end].append(r)

func _world(cell: Vector2i) -> Vector2:
	return map.tilemap.position + map.tilemap.map_to_local(cell)

func is_city(node_name: String) -> bool:
	return cities.has(node_name)

func label(node_name: String) -> String:
	return map.NAMES.get(node_name, node_name)

# The node at the far end of route `r` when leaving from `node_name`.
func other_end(r: int, node_name: String) -> String:
	return routes[r]["to"] if routes[r]["from"] == node_name else routes[r]["from"]

func space_type(r: int, stop_i: int) -> StringName:
	if stop_i <= 0 or stop_i >= stops[r].size() - 1:
		return &""
	var gi: int = route_space_start[r] + stop_i - 1
	return map.space_types[gi] if gi < map.space_types.size() else &""

static func point_on_polyline(pts: Array, dist: float) -> Vector2:
	var remaining := dist
	for i in pts.size() - 1:
		var seg: float = pts[i].distance_to(pts[i + 1])
		if seg <= 0.0:
			continue
		if remaining <= seg or i == pts.size() - 2:
			return pts[i] + (pts[i + 1] - pts[i]) * (remaining / seg)
		remaining -= seg
	return pts[pts.size() - 1]

# Arc-length of point `p` (which sits on the polyline) from its start.
static func arc_length_of(pts: Array, p: Vector2) -> float:
	var best_d := INF
	var best_len := 0.0
	var acc := 0.0
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var ab: Vector2 = pts[i + 1] - a
		var seg_len := ab.length()
		if seg_len > 0.0:
			var t := clampf((p - a).dot(ab) / (seg_len * seg_len), 0.0, 1.0)
			var d := p.distance_to(a + ab * t)
			if d < best_d:
				best_d = d
				best_len = acc + t * seg_len
		acc += seg_len
	return best_len

# Compass arrow for the way a road physically leaves `node_name`.
func route_arrow(r: int, node_name: String) -> String:
	var pts: Array = poly[r]
	var next: Vector2 = pts[1] if routes[r]["from"] == node_name else pts[pts.size() - 2]
	var v: Vector2 = next - node_pos[node_name]
	if v == Vector2.ZERO:
		return "→"
	var a := fposmod(rad_to_deg(atan2(v.y, v.x)), 360.0)   # 0=E, 90=S (y down)
	return ["→", "↘", "↓", "↙", "←", "↖", "↑", "↗"][int(round(a / 45.0)) % 8]

# Fork button text for road `r` out of `node_name`.
func route_label(r: int, node_name: String) -> String:
	var route: Dictionary = routes[r]
	# parallel roads carry their own name so the fork choices stay distinct
	var name := label(route["name_of"]) if route.has("name_of") else label(other_end(r, node_name))
	return name + " " + route_arrow(r, node_name)
