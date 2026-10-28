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
	# the Spectral Trail: a dead-end climb guarded by the Haunted Four
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
	"VEnter": "Spectral Trail",
	"VEnd":  "Spectral Peak",
}

# Roads. Each connects two node names; "corners" are the bend tiles in between
# (leave [] for a straight road). A fork = several roads sharing one node.
# Add "spaces": N to put EXACTLY N spaces on that road. Omit it and the road
# auto-fills evenly using SPACING (below), based on the road's length.
#
# "types": one entry per space, naming what kind of tile it is (see
# SPACE_TYPE_NAMES below). The list runs from the "from" node toward the "to"
# node. Any space with no type listed falls back to DEFAULT_SPACE_TYPE.
# Every route carries 1 EVENT and 1 COMPETITION tile (plus its ghost/ITEM tiles;
# the long J5→E scenic road keeps a 2nd EVENT).
var ROUTES := [
	{ "from": "A", "to": "J1", "corners": [], "spaces": 4,
		"types": [&"WISP", &"EVENT", &"WISP", &"ITEM"] },
	{ "from": "B", "to": "J3", "corners": [], "spaces": 4,
		"types": [&"WISP", &"EVENT", &"COMPETITION", &"WISP"] },
	{ "from": "C", "to": "H", "corners": [], "spaces": 6,
		"types": [&"GHOST", &"EVENT", &"ITEM", &"GHOST", &"GHOST", &"GHOST"] },
	{ "from": "C", "to": "J5", "corners": [], "spaces": 2,
		"types": [&"EVENT", &"COMPETITION"] },
	{ "from": "E", "to": "D", "corners": [Vector2i(46, 66),Vector2i(46, 35)], "spaces": 5,
		"types": [&"GHOST", &"EVENT", &"COMPETITION", &"ITEM", &"GHOST"] },
	{ "from": "H", "to": "J8", "corners": [], "spaces": 4,
		"types": [&"GHOST", &"EVENT", &"GHOST", &"ITEM"] },
	{ "from": "D", "to": "J6", "corners": [], "spaces": 6,
		"types": [&"GHOST", &"EVENT", &"COMPETITION", &"GHOST", &"ITEM", &"GHOST"] },
	{ "from": "D", "to": "F", "corners": [Vector2i(91, 36),Vector2i(91, 25),Vector2i(104, 25)], "spaces": 6,
		"types": [&"PHANTOM", &"EVENT", &"ITEM", &"GHOST", &"PHANTOM", &"PHANTOM"] },

	#junctions
	# Parallel roads share both endpoints, so each is named after one of its two
	# junctions ("name_of") to keep the fork choices distinct and meaningful.
	{ "from": "J1", "to": "J2", "corners": [Vector2i(7, 43),Vector2i(7, 21)], "spaces": 5, "name_of": "J1",
		"types": [&"EVENT", &"WISP", &"WISP", &"ITEM", &"WISP"] },
	{ "from": "J1", "to": "J2", "corners": [], "spaces": 4, "name_of": "J2",
		"types": [&"EVENT", &"WISP", &"EVENT", &"EVENT"] },
	{ "from": "J2", "to": "B", "corners": [], "spaces": 5,
		"types": [&"WISP", &"EVENT", &"COMPETITION", &"ITEM", &"WISP"] },

	{ "from": "J3", "to": "J4", "corners": [Vector2i(28, -21),Vector2i(61, -22)], "spaces": 5, "name_of": "J3",
		"types": [&"WISP", &"EVENT", &"WISP", &"ITEM", &"WISP"] },
	{ "from": "J3", "to": "J4", "corners": [], "spaces": 5, "name_of": "J4",
		"types": [&"ITEM", &"EVENT", &"COMPETITION", &"WISP", &"WISP"] },
	{ "from": "J4", "to": "C", "corners": [], "spaces": 5,
		"types": [&"WISP", &"EVENT", &"COMPETITION", &"WISP", &"WISP"] },

	{ "from": "J5", "to": "E", "corners": [Vector2i(42, -1),Vector2i(42, 10),Vector2i(30, 10)], "spaces": 10,
		"types": [&"EVENT", &"GHOST", &"COMPETITION", &"ITEM", &"GHOST", &"GHOST", &"EVENT", &"GHOST", &"GHOST", &"GHOST"] },
	{ "from": "J5", "to": "D", "corners": [Vector2i(85, 12),Vector2i(65, 13)], "spaces": 6,
		"types": [&"GHOST", &"COMPETITION", &"ITEM", &"EVENT", &"GHOST", &"GHOST"] },

	{ "from": "J6", "to": "J7", "corners": [Vector2i(116, 70)], "spaces": 5, "name_of": "J6",
		"types": [&"GHOST", &"EVENT", &"GHOST", &"ITEM", &"PHANTOM"] },
	{ "from": "J6", "to": "J7", "corners": [Vector2i(66, 86)], "spaces": 5, "name_of": "J7",
		"types": [&"ITEM", &"EVENT", &"COMPETITION", &"GHOST", &"PHANTOM"] },
	{ "from": "J7", "to": "G", "corners": [], "spaces": 5,
		"types": [&"PHANTOM", &"EVENT", &"PHANTOM", &"ITEM", &"PHANTOM"] },

	{ "from": "J8", "to": "J9", "corners": [], "spaces": 6, "name_of": "J8",
		"types": [&"GHOST", &"GHOST", &"ITEM", &"EVENT", &"GHOST", &"PHANTOM"] },
	{ "from": "J8", "to": "J9", "corners": [Vector2i(132, 7),Vector2i(132, 54)], "spaces": 6, "name_of": "J9",
		"types": [&"GHOST", &"EVENT", &"COMPETITION", &"ITEM", &"PHANTOM", &"PHANTOM"] },
	{ "from": "J9", "to": "G", "corners": [], "spaces": 5,
		"types": [&"PHANTOM", &"EVENT", &"EVENT", &"ITEM", &"PHANTOM"] },

	# The Spectral Trail: a dead-end climb. Each WARDEN tile is a fight against
	# one of the Haunted Four (or Champion Vesper).
	{ "from": "VEnter", "to": "VEnd", "corners": [], "spaces": 7,
		"types": [&"ITEM", &"WARDEN", &"ITEM",&"WARDEN",&"ITEM",&"WARDEN",&"WARDEN"] },

]

# ==================================================================

const SPACING := 42.0              # default px between spaces (used when a route has no "spaces")
const SPACE_RADIUS := 15.0
const CITY_RADIUS := 20.0
const LINE_COLOR := Color(0, 0, 0, 0.7)
const LINE_WIDTH := 4.0
const CITY_COLOR := Color("2f6bd0")
const MARKER_ALPHA := 0.95          # tile fill opacity (1 = fully solid)

# White name printed on each tile.
var LABEL_FONT: Font = ThemeDB.fallback_font
const LABEL_FONT_SIZE := 11
const LABEL_COLOR := Color.WHITE
const LABEL_OUTLINE_SIZE := 2
const LABEL_OUTLINE_COLOR := Color(0, 0, 0, 0.9)

# The kinds of tile a space can be. The KEY is the type the game logic reacts
# to; the VALUE is the short white name drawn on the tile.
# Three ghost tiles, weakest to strongest: Wisp, Ghost, Phantom.
const SPACE_TYPE_NAMES := {
	&"WISP":        "Wisp",
	&"GHOST":       "Ghost",
	&"PHANTOM":     "Phantom",
	&"EVENT":       "Event",
	&"ITEM":        "Item",
	&"COMPETITION": "Comp",
	&"WARDEN":      "Warden",
}

const GHOST_TILES := [&"WISP", &"GHOST", &"PHANTOM"]

# Spirit stage odds per ghost tile: [stage, chance %] pairs.
const STAGE_ODDS := {
	&"WISP":    [[1, 100]],
	&"GHOST":   [[1, 80], [2, 20]],
	&"PHANTOM": [[2, 80], [3, 20]],
}

static func roll_stage(type: StringName) -> int:
	var roll := randi_range(1, 100)
	for pair in STAGE_ODDS.get(type, [[1, 100]]):
		roll -= int(pair[1])
		if roll <= 0:
			return int(pair[0])
	return 1

# A colour per kind, so the board reads at a glance which tile is which.
const SPACE_TYPE_COLORS := {
	&"WISP":        Color("f7a8c0"),
	&"GHOST":       Color("2fa84f"),
	&"PHANTOM":     Color("e03131"),
	&"EVENT":       Color("f4d03f"),
	&"ITEM":        Color("f08a2e"),
	&"COMPETITION": Color("8e8e93"),
	&"WARDEN":      Color("7b5cd6"),
}

# Used when a space has no type listed in its route's "types".
const DEFAULT_SPACE_TYPE := &"GHOST"

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
	queue_redraw()
	_setup_preview_camera()

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
	# 3) towns on top (big blue circle + "Town"). Junctions are invisible.
	for node_name in NODES:
		var nn: String = node_name
		if not CITIES.has(nn):
			continue
		var cc: Vector2 = _cell_to_world(NODES[nn])
		draw_circle(cc, CITY_RADIUS + 2.0, outline)
		draw_circle(cc, CITY_RADIUS, Color(CITY_COLOR, MARKER_ALPHA))
		_draw_label(cc, "Town")

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
