extends Node2D
## Map layout only — builds the board graph and draws it.
## Exposes `spaces` (the small road-space positions) so the Board scene can
## place and move the player tokens. No tokens / turns / UI live here.
##
##   NODES  = cities / junctions   (name -> tile coordinate)
##   ROUTES = roads between nodes   (the corner tiles each road bends through)
## A FORK is just several ROUTES that share the same node name.
##
## To find a tile coordinate: in the editor, select the TileMap and hover a cell
## (its coord shows at the bottom of the viewport). Or run the game and
## LEFT-CLICK the map — the tile under the mouse is printed to Output.

# ======================= EDIT YOUR MAP HERE =======================

# Every connection point (cities AND junctions): name -> tile coordinate.
var NODES := {
	"A": Vector2i(-4, 88),
	"B": Vector2i(-4, -14),
	"C": Vector2i(87, -14),
	"G": Vector2i(145, 87),
	"H": Vector2i(144, -14),
	"D": Vector2i(65, 36),
	"E": Vector2i(30, 68),
	"F": Vector2i(104, 11), # a JUNCTION (not listed in CITIES below) — just a fork point
	
	"J1": Vector2i(-4, 44), #A->B
	"J2": Vector2i(-4, 21),
	"J3": Vector2i(29, -14), #B->C
	"J4": Vector2i(62, -14),
	"J5": Vector2i(84, -2), #C->D/E
	"J6": Vector2i(66, 70), #D->G
	"J7": Vector2i(115, 87),
	"J8": Vector2i(144, 7), #H->G
	"J9": Vector2i(145, 54),

	"VEnter": Vector2i(169, 53),
	"VEnd": Vector2i(169, 5),
	
	
	 # Victory Peak — top of the E4/Gary corridor (dead end)
}

# Which nodes are drawn as big cities. Any node NOT in here is a small junction.
var CITIES := ["A", "B", "C", "D", "E", "F", "G", "H"]

# Display names shown to players (fork choices, stop prompts, "you reached..." text).
# Cities get a place name starting with their letter; junctions are "Route N",
# numbered by the roads leaving them (parallel roads each count as a route).
var NAMES := {
	"A": "Ashen Hollow",
	"B": "Boo Bayou",
	"C": "Cobweb City",
	"D": "Dusk Den",
	"E": "Echo End",
	"F": "Foggy Fen",
	"G": "Ghoul Grove",
	"H": "Haunted Harbor",

	"J1": "Route 1",
	"J2": "Route 3",
	"J3": "Route 4",
	"J4": "Route 6",
	"J5": "Route 7",
	"J6": "Route 9",
	"J7": "Route 11",
	"J8": "Route 12",
	"J9": "Route 14",
	"VEnter": "Victory Entrance",
	"VEnd":  "Victory Peak",
}

# Roads. Each connects two node names; "corners" are the bend tiles in between
# (leave [] for a straight road). A fork = several roads sharing one node.
# Add "spaces": N to put EXACTLY N spaces on that road. Omit it and the road
# auto-fills evenly using SPACING (below), based on the road's length.
#
# "types": one entry per space, naming what kind of tile it is (see
# SPACE_TYPE_NAMES below). The list runs from the "from" node toward the "to"
# node. Any space with no type listed falls back to DEFAULT_SPACE_TYPE.
# Every route carries 1 EVENT and 1 COMPETITION tile (plus its SP/ITEM tiles;
# the long J5→E scenic road keeps a 2nd EVENT).
var ROUTES := [
	{ "from": "A", "to": "J1", "corners": [], "spaces": 4,
		"types": [&"PKMN_PINK", &"EVENT", &"PKMN_PINK", &"ITEM"] },
	{ "from": "B", "to": "J3", "corners": [], "spaces": 4,
		"types": [&"PKMN_PINK", &"EVENT", &"COMPETITION", &"PKMN_PINK"] },
	{ "from": "C", "to": "H", "corners": [], "spaces": 6,
		"types": [&"PKMN_GREEN", &"EVENT", &"ITEM", &"PKMN_GREEN", &"PKMN_GREEN", &"PKMN_GREEN"] },
	{ "from": "C", "to": "J5", "corners": [], "spaces": 2,
		"types": [&"EVENT", &"COMPETITION"] },
	{ "from": "E", "to": "D", "corners": [Vector2i(46, 66),Vector2i(46, 35)], "spaces": 5,
		"types": [&"PKMN_GREEN", &"EVENT", &"COMPETITION", &"ITEM", &"PKMN_GREEN"] },
	{ "from": "H", "to": "J8", "corners": [], "spaces": 4,
		"types": [&"PKMN_GREEN", &"EVENT", &"PKMN_GREEN", &"ITEM"] },
	{ "from": "D", "to": "J6", "corners": [], "spaces": 6,
		"types": [&"PKMN_GREEN", &"EVENT", &"COMPETITION", &"PKMN_GREEN", &"ITEM", &"PKMN_GREEN"] },
	{ "from": "D", "to": "F", "corners": [Vector2i(91, 36),Vector2i(91, 25),Vector2i(104, 25)], "spaces": 6,
		"types": [&"PKMN_RED", &"EVENT", &"ITEM", &"PKMN_GREEN", &"PKMN_RED", &"PKMN_RED"] },

	#junctions
	# Parallel roads share both endpoints, so each is named after one of its two
	# junctions ("name_of") to keep the fork choices distinct and meaningful.
	{ "from": "J1", "to": "J2", "corners": [Vector2i(7, 43),Vector2i(7, 21)], "spaces": 5, "name_of": "J1",
		"types": [&"EVENT", &"PKMN_PINK", &"PKMN_PINK", &"ITEM", &"PKMN_PINK"] },
	{ "from": "J1", "to": "J2", "corners": [], "spaces": 4, "name_of": "J2",
		"types": [&"EVENT", &"PKMN_PINK", &"EVENT", &"EVENT"] },
	{ "from": "J2", "to": "B", "corners": [], "spaces": 5,
		"types": [&"PKMN_PINK", &"EVENT", &"COMPETITION", &"ITEM", &"PKMN_PINK"] },

	{ "from": "J3", "to": "J4", "corners": [Vector2i(28, -21),Vector2i(61, -22)], "spaces": 5, "name_of": "J3",
		"types": [&"PKMN_PINK", &"EVENT", &"PKMN_PINK", &"ITEM", &"PKMN_PINK"] },
	{ "from": "J3", "to": "J4", "corners": [], "spaces": 5, "name_of": "J4",
		"types": [&"ITEM", &"EVENT", &"COMPETITION", &"PKMN_PINK", &"PKMN_PINK"] },
	{ "from": "J4", "to": "C", "corners": [], "spaces": 5,
		"types": [&"PKMN_PINK", &"EVENT", &"COMPETITION", &"PKMN_PINK", &"PKMN_PINK"] },

	{ "from": "J5", "to": "E", "corners": [Vector2i(42, -1),Vector2i(42, 10),Vector2i(30, 10)], "spaces": 10,
		"types": [&"EVENT", &"PKMN_GREEN", &"COMPETITION", &"ITEM", &"PKMN_GREEN", &"PKMN_GREEN", &"EVENT", &"PKMN_GREEN", &"PKMN_GREEN", &"PKMN_GREEN"] },
	{ "from": "J5", "to": "D", "corners": [Vector2i(85, 12),Vector2i(65, 13)], "spaces": 6,
		"types": [&"PKMN_GREEN", &"COMPETITION", &"ITEM", &"EVENT", &"PKMN_GREEN", &"PKMN_GREEN"] },

	{ "from": "J6", "to": "J7", "corners": [Vector2i(116, 70)], "spaces": 5, "name_of": "J6",
		"types": [&"PKMN_GREEN", &"EVENT", &"PKMN_GREEN", &"ITEM", &"PKMN_RED"] },
	{ "from": "J6", "to": "J7", "corners": [Vector2i(66, 86)], "spaces": 5, "name_of": "J7",
		"types": [&"ITEM", &"EVENT", &"COMPETITION", &"PKMN_GREEN", &"PKMN_RED"] },
	{ "from": "J7", "to": "G", "corners": [], "spaces": 5,
		"types": [&"PKMN_RED", &"EVENT", &"PKMN_RED", &"ITEM", &"PKMN_RED"] },

	{ "from": "J8", "to": "J9", "corners": [], "spaces": 6, "name_of": "J8",
		"types": [&"PKMN_GREEN", &"PKMN_GREEN", &"ITEM", &"EVENT", &"PKMN_GREEN", &"PKMN_RED"] },
	{ "from": "J8", "to": "J9", "corners": [Vector2i(132, 7),Vector2i(132, 54)], "spaces": 6, "name_of": "J9",
		"types": [&"PKMN_GREEN", &"EVENT", &"COMPETITION", &"ITEM", &"PKMN_RED", &"PKMN_RED"] },
	{ "from": "J9", "to": "G", "corners": [], "spaces": 5,
		"types": [&"PKMN_RED", &"EVENT", &"EVENT", &"ITEM", &"PKMN_RED"] },

	# Victory road: the dirt corridor north of Echo End. A dead end — two
	# Elite Four tiles guard the climb and Gary waits on the platform at the top.
	{ "from": "VEnter", "to": "VEnd", "corners": [], "spaces": 7,
		"types": [&"ITEM", &"E4", &"ITEM",&"E4",&"ITEM",&"E4",&"E4"] },

]

# ==================================================================

const SPACING := 42.0              # default px between spaces (used when a route has no "spaces")
const SPACE_RADIUS := 15.0
const CITY_RADIUS := 20.0
const LINE_COLOR := Color(0, 0, 0, 0.7)
const LINE_WIDTH := 4.0
const CITY_COLOR := Color("2f6bd0")
const GYM_DONE_COLOR := Color("d4af37")   # a city whose gym THIS player has cleared
const GYM_DONE_RING := Color("ffe066")    # bright gold ring drawn around a cleared gym
const MARKER_ALPHA := 0.95          # tile fill opacity (1 = fully solid)

# White name printed on each tile (and shown in the landing window). pkmnfl is
# the same pixel font the menus use.
const LABEL_FONT := preload("res://Assets/UI/pkmnfl.ttf")
const LABEL_FONT_SIZE := 11
const LABEL_COLOR := Color.WHITE
const LABEL_OUTLINE_SIZE := 2
const LABEL_OUTLINE_COLOR := Color(0, 0, 0, 0.9)

# The kinds of tile a space can be. The KEY is the type the game logic reacts to
# (SpaceResolver dispatches on it); the VALUE is the short white name drawn on
# the tile and shown in the landing window.
#
# PKMN comes in three colours = three spirit types; all three read "SP".
const SPACE_TYPE_NAMES := {
	&"PKMN_PINK":   "SP",
	&"PKMN_GREEN":  "SP",
	&"PKMN_RED":    "SP",
	&"EVENT":       "Event",
	&"ITEM":        "Item",
	&"COMPETITION": "Comp",
	&"E4":          "E4",
	&"GARY":        "Gary",
}

# A colour per kind, so the board reads at a glance which tile is which.
const SPACE_TYPE_COLORS := {
	&"PKMN_PINK":   Color("f7a8c0"),
	&"PKMN_GREEN":  Color("2fa84f"),
	&"PKMN_RED":    Color("e03131"),
	&"EVENT":       Color("f4d03f"),
	&"ITEM":        Color("f08a2e"),
	&"COMPETITION": Color("8e8e93"),
	&"E4":          Color("7b5cd6"),
	&"GARY":        Color("d4af37"),
}

# Used when a space has no type listed in its route's "types".
const DEFAULT_SPACE_TYPE := &"PKMN_GREEN"

@onready var tilemap: TileMap = $TileMap

var spaces: Array = []             # Vector2 positions of the small road spaces (drawn)
var space_types: Array = []        # a StringName kind per space (parallel to `spaces`)
var _space_col: Array = []         # a Color per space

# Friendly display name for a space type (falls back to the raw type string).
func space_type_name(type: StringName) -> String:
	return SPACE_TYPE_NAMES.get(type, String(type))

func _ready() -> void:
	tilemap.show_behind_parent = true
	_build_spaces()
	# Re-highlight cleared gyms when a badge is won or the turn passes on (the
	# highlight reflects the current player's earned badges).
	EventBus.badge_earned.connect(func(_i, _n): queue_redraw())
	EventBus.turn_started.connect(func(_i): queue_redraw())
	queue_redraw()
	_setup_preview_camera()

# True if the current player has earned this city's gym badge (reads the static
# gym table so it never triggers remainder-gym generation just to draw).
func _gym_beaten(city: String) -> bool:
	if GameState.players.is_empty():
		return false
	var badge: String = String(GameData.GYMS.get(city, {}).get("badge", ""))
	if badge == "":
		return false
	var idx: int = GameState.current_player_index
	return idx >= 0 and idx < GameState.players.size() \
		and GameState.players[idx].progress.badges.get(badge, false)

# ── Standalone map preview ────────────────────────────────────────────────────
# Run THIS scene by itself (F6 on Map1.tscn) and fly around with the ARROW
# keys (or WASD); Q / E zooms. Left-click still prints the tile coord under
# the mouse to Output — handy for filling in NODES / corners.
# Inside the real game Map1 is instanced under Board, which has its own
# camera, so the preview camera is only created when Map1 IS the scene.
const PREVIEW_PAN_SPEED := 900.0
const PREVIEW_ZOOM_MIN := 0.15
const PREVIEW_ZOOM_MAX := 3.0

var _preview_cam: Camera2D

func _setup_preview_camera() -> void:
	if get_tree().current_scene != self:
		set_process(false)
		return
	_preview_cam = Camera2D.new()
	# start centred between the map's nodes
	var center := Vector2.ZERO
	for n in NODES:
		center += _cell_to_world(NODES[n])
	if NODES.size() > 0:
		center /= float(NODES.size())
	_preview_cam.position = center
	_preview_cam.zoom = Vector2(0.6, 0.6)
	add_child(_preview_cam)
	_preview_cam.make_current()
	set_process(true)

func _process(delta: float) -> void:
	if _preview_cam == null:
		return
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		dir.x += 1.0
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		dir.y -= 1.0
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		dir.y += 1.0
	if dir != Vector2.ZERO:
		# divide by zoom so panning feels the same speed at any zoom level
		_preview_cam.position += dir.normalized() * PREVIEW_PAN_SPEED * delta / _preview_cam.zoom.x
	var zdir := 0.0
	if Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_MINUS):
		zdir -= 1.0
	if Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_EQUAL):
		zdir += 1.0
	if zdir != 0.0:
		var z := clampf(_preview_cam.zoom.x * (1.0 + zdir * 1.2 * delta), PREVIEW_ZOOM_MIN, PREVIEW_ZOOM_MAX)
		_preview_cam.zoom = Vector2(z, z)

# ---------------- Board (graph) ----------------

func _cell_to_world(cell: Vector2i) -> Vector2:
	return tilemap.position + tilemap.map_to_local(cell)

func _route_cells(route: Dictionary) -> Array:
	# Full list of tile cells a road passes through: start node, corners, end node.
	var cells: Array = []
	var a: Vector2i = NODES[route["from"]]
	cells.append(a)
	for c in route["corners"]:
		var cc: Vector2i = c
		cells.append(cc)
	var b: Vector2i = NODES[route["to"]]
	cells.append(b)
	return cells

func _build_spaces() -> void:
	spaces.clear()
	space_types.clear()
	_space_col.clear()
	for route in ROUTES:
		var rd: Dictionary = route
		var count: int = rd.get("spaces", -1)   # per-route count; -1 = auto from SPACING
		var from_city: bool = CITIES.has(rd["from"])
		var to_city: bool = CITIES.has(rd["to"])
		_fill_along(_route_cells(rd), count, rd.get("types", []), from_city, to_city)

func _fill_along(cells: Array, count: int, types: Array, from_city: bool, to_city: bool) -> void:
	# Build the world-space polyline and measure its total length.
	var pts: Array = []
	for c in cells:
		var cc: Vector2i = c
		pts.append(_cell_to_world(cc))
	var total: float = 0.0
	for i in range(pts.size() - 1):
		var a0: Vector2 = pts[i]
		var b0: Vector2 = pts[i + 1]
		total += a0.distance_to(b0)
	if total <= 0.0:
		return
	# How many spaces: the route's own count, or auto from SPACING.
	var n: int = count
	if n < 0:
		n = int(round(total / SPACING))
	if n <= 0:
		return
	# Spacing: leave a FULL gap before a city (so tiles don't crowd the big
	# circle) but only a HALF gap before a junction. Junctions are invisible, so
	# the two half-gaps of the roads meeting there add up to one normal gap —
	# the chain of tiles reads as continuous with no blank spot.
	var cf: float = 1.0 if from_city else 0.5
	var ct: float = 1.0 if to_city else 0.5
	var gap: float = total / (cf + ct + float(n) - 1.0)
	for k in range(n):
		var t: float = gap * (cf + float(k))
		var sp_type: StringName = types[k] if k < types.size() else DEFAULT_SPACE_TYPE
		spaces.append(_point_on_polyline(pts, t))
		space_types.append(sp_type)
		_space_col.append(SPACE_TYPE_COLORS.get(sp_type, Color("888888")))

func _point_on_polyline(pts: Array, dist: float) -> Vector2:
	# Position at arc-length `dist` along the polyline of points.
	var remaining: float = dist
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var seg: float = a.distance_to(b)
		if seg <= 0.0:
			continue
		if remaining <= seg or i == pts.size() - 2:
			return a + (b - a) * (remaining / seg)
		remaining -= seg
	return pts[pts.size() - 1]

func _draw() -> void:
	# 1) roads
	for route in ROUTES:
		var rd: Dictionary = route
		var cells: Array = _route_cells(rd)
		for i in range(cells.size() - 1):
			var ca: Vector2i = cells[i]
			var cb: Vector2i = cells[i + 1]
			draw_line(_cell_to_world(ca), _cell_to_world(cb), LINE_COLOR, LINE_WIDTH)
	var outline := Color(0, 0, 0, 0.85)
	# 2) small spaces along the roads, each with its white name
	for i in spaces.size():
		var p: Vector2 = spaces[i]
		var sc: Color = _space_col[i]
		draw_circle(p, SPACE_RADIUS + 1.5, outline)
		draw_circle(p, SPACE_RADIUS, Color(sc, MARKER_ALPHA))
		_draw_label(p, space_type_name(space_types[i]))
	# 3) cities on top (big blue circle + "City" name). Junctions are invisible.
	for node_name in NODES:
		var nn: String = node_name
		if not CITIES.has(nn):
			continue
		var cc: Vector2 = _cell_to_world(NODES[nn])
		var beaten: bool = _gym_beaten(nn)
		if beaten:
			# a bright gold ring marks a gym this player has already cleared
			draw_arc(cc, CITY_RADIUS + 6.0, 0.0, TAU, 40, GYM_DONE_RING, 4.0, true)
		draw_circle(cc, CITY_RADIUS + 2.0, outline)
		draw_circle(cc, CITY_RADIUS, Color(GYM_DONE_COLOR if beaten else CITY_COLOR, MARKER_ALPHA))
		_draw_label(cc, "City")

# Draw a short white name centred on a tile, with a dark outline for contrast.
func _draw_label(center: Vector2, text: String) -> void:
	var w := 100.0
	var pos := Vector2(center.x - w * 0.5, center.y + LABEL_FONT_SIZE * 0.35)
	draw_string_outline(LABEL_FONT, pos, text, HORIZONTAL_ALIGNMENT_CENTER, w,
		LABEL_FONT_SIZE, LABEL_OUTLINE_SIZE, LABEL_OUTLINE_COLOR)
	draw_string(LABEL_FONT, pos, text, HORIZONTAL_ALIGNMENT_CENTER, w,
		LABEL_FONT_SIZE, LABEL_COLOR)

# Click the map to print the tile under the mouse (handy for filling NODES).
func _unhandled_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		var cell: Vector2i = tilemap.local_to_map(tilemap.to_local(get_global_mouse_position()))
		print("tile under mouse: ", cell)
