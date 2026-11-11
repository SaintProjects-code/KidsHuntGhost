extends RefCounted
## Turns a board's 2D tile data into 3D meshes: stepped terrain, ponds, trees,
## buildings, tall grass and the road tiles. All art is generated here (flat
## faceted colours + tiny pixel textures), so a map needs no extra asset files.
##
## World scale: one 16 px tile = one 3D unit. Roads sit at y = 0, so tokens
## never need a height lookup; everything else steps up or down around them.

const TILE_PX := 16.0
const LAYER_GROUND := 0
const LAYER_OBJECTS := 1
const SRC_GROUND := 0
const SRC_HOUSE := 1
const SRC_LAB := 2
const SRC_TALL_GRASS := 3
const SRC_WATER := 4
const SRC_TREE := 5
const GROUND_GRASS_COLUMN := 3      # tileset columns 0-2 are road, 3 is grass

const PATH_H := 0.0
const GRASS_H := 0.55
const WATER_FLOOR_H := -0.45
const WATER_SURFACE_H := -0.14
const VOID_H := -1.5
const DISC_RIM_H := 0.08
const DISC_TOP := 0.18
# City pavement sits level with the grass, so a road through town has the
# same banks as a road through the countryside.
const PLAZA_H := GRASS_H

# City districts: towns not listed as villages get paved over and built up.
const CITY_RADIUS := Vector2(16.0, 13.0)   # district size in tiles (x, z)
const STREET_HALF_WIDTH := 2.0             # inside a city, the road is this wide each side of its line
const AVENUE_DEFAULT := 5.0                # paved street running out past a city's edge, in tiles
const AVENUE_LAMP_STEP := 4.0              # lamp spacing along an avenue
const ROAD_CLEARANCE := 2.6                # nothing is built closer than this to a road's line
const MAX_BUILDINGS := 22                  # per city
const BUILDING_SIZE := {"landmark": Vector2i(6, 4), "tower": Vector2i(4, 3), "shop": Vector2i(4, 3), "row": Vector2i(3, 3)}
# Lowest total height (roof, flag and rooftop bits included) each kind can be built at.
const BUILDING_MIN_H := {"landmark": 4.4, "tower": 3.6, "shop": 2.0, "row": 2.4}
const LANDMARK_TOP := 1.45                 # the landmark's upper storey + parapet
const TOWER_TOP := 0.9                     # rooftop unit on a tower
const ROW_ROOF := 0.9

# House roofs, and the squat version used where a full house would hide a road.
const ROOF_H := 1.35
const LOW_WALL := 1.1
const LOW_ROOF := 0.7
const TREE_HEIGHT := 2.9                   # a full-size tree's top above the grass
const TREE_MIN_ROOM := 1.4                 # below this, a tree is left out
const PLANTER_HEIGHT := 1.7
const BUILDING_ORDER := ["tower", "shop", "tower", "row", "shop", "tower", "row"]   # after the landmark

const ATLAS_CELLS := 4
const TERRAIN_GRASS := [0, 1, 2, 3]
const TERRAIN_SAND := [4, 5]
const TERRAIN_BANK := 6
const TERRAIN_PLAZA := 7
const TERRAIN_STREET := 8

const LIGHT_DIR := Vector2(-0.45, 0.89)   # low sun from the viewer's left (x, z)

const C_GRASS := Color("70c8a4")
const C_GRASS_DARK := Color("3c9c7c")
const C_GRASS_PALE := Color("b4e4b0")
const C_SAND := Color("e8b490")
const C_SAND_DARK := Color("d8966c")
const C_BANK := Color("a9794f")
const C_BANK_DARK := Color("8a6040")
const C_BANK_TOP := Color("c8e0a8")
const C_TRUNK := Color("7a5236")
const C_LEAF := Color("5ccb4a")
const C_LEAF_ALT := Color("3fb860")
const C_LEAF_SHADE := Color("1f8a58")
const C_LEAF_LIGHT := Color("b6ee5e")
# Canopy outline, bottom to top, as [radius, height]: lathed into a rounded tree.
const TREE_PROFILE := [[0.82, 0.0], [1.2, 0.45], [1.24, 1.0], [1.0, 1.55], [0.56, 2.0], [0.0, 2.2]]
const C_TALL_GRASS := Color("3a8f8a")
const C_TALL_GRASS_TIP := Color("6fd0b0")
const C_WALL := Color("efe6d2")
const C_WALL_LAB := Color("d5dfe8")
const C_DOOR := Color("7b4a2c")
const C_WINDOW := Color("ffe08a")
const C_FRAME := Color("4c4a5e")
const C_STONE := Color("8d8a98")
const C_TILE_RIM := Color("20242e")
const C_PAVE := Color("d2ccc2")
const C_PAVE_LINE := Color("b2ab9f")
const C_STREET := Color("b9ab98")
const C_STREET_LINE := Color("9c8e7c")
const CITY_WALLS := [Color("e9dcc6"), Color("d5dfe8"), Color("f0c9b8"), Color("cfe3d0"), Color("e6d8f0")]
const AWNINGS := [Color("d85a30"), Color("1d9e75"), Color("534ab7"), Color("e0a040")]
const C_GLASS := Color("9fd6e8")
const C_DARK_WINDOW := Color("4c4a5e")
const C_LANDMARK := Color("f1ead8")
const C_BANNER := Color("7b5cd6")
const C_TRAIL := Color("6e4630")
const TRAIL_WIDTH := 0.34
const ROOF_COLORS := [Color("e8705a"), Color("9a6bd0"), Color("4aa0c8"), Color("e0a040")]
const C_ROOF_LAB := Color("4f7fd8")

# ─── Mesh batching ───────────────────────────────────────────────────────────

## Collects triangles and bakes them into one mesh. Faces carry their shading
## in the vertex colour, so the look doesn't depend on the renderer's lights.
class Batch:
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()

	static func planar_uv(p: Vector3) -> Vector2:
		return Vector2(p.x + p.z * 0.7, p.y + p.z * 0.7) * 0.5

	func tri(a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
		for p in [a, b, c]:
			verts.append(p)
			cols.append(col)
			uvs.append(planar_uv(p))

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
		tri(a, b, c, col)
		tri(a, c, d, col)

	# a-b-c-d run around the quad; the rect is mapped a=top-left, c=bottom-right.
	func quad_uv(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, r: Rect2) -> void:
		var corners := [[a, r.position], [b, Vector2(r.end.x, r.position.y)], [c, r.end], [d, Vector2(r.position.x, r.end.y)]]
		for k in [0, 1, 2, 0, 2, 3]:
			verts.append(corners[k][0])
			cols.append(col)
			uvs.append(corners[k][1])

	func box(lo: Vector3, hi: Vector3, col: Color) -> void:
		var tl := Vector3(lo.x, hi.y, lo.z)
		var tr := Vector3(hi.x, hi.y, lo.z)
		var br := Vector3(hi.x, hi.y, hi.z)
		var bl := Vector3(lo.x, hi.y, hi.z)
		var fl := Vector3(lo.x, lo.y, hi.z)
		var fr := Vector3(hi.x, lo.y, hi.z)
		var nl := Vector3(lo.x, lo.y, lo.z)
		var nr := Vector3(hi.x, lo.y, lo.z)
		quad(tl, tr, br, bl, col)                # top
		quad(bl, br, fr, fl, _shade(col, 0.88))  # front
		quad(tl, bl, fl, nl, _shade(col, 0.95))  # left
		quad(br, tr, nr, fr, _shade(col, 0.72))  # right
		quad(tr, tl, nl, nr, _shade(col, 0.66))  # back

	## A tapered n-sided column, with sides lit in three flat bands.
	func prism(c: Vector3, r0: float, r1: float, h: float, sides: int, side: Color, top: Color, cap := true) -> void:
		var top_c := c + Vector3(0, h, 0)
		for i in sides:
			var a0 := TAU * float(i) / float(sides)
			var a1 := TAU * float(i + 1) / float(sides)
			var d0 := Vector3(cos(a0), 0, sin(a0))
			var d1 := Vector3(cos(a1), 0, sin(a1))
			var mid := (a0 + a1) * 0.5
			var lit := Vector2(cos(mid), sin(mid)).dot(LIGHT_DIR)
			var band := 1.0 if lit > 0.35 else (0.82 if lit > -0.35 else 0.64)
			quad(c + d0 * r0, c + d1 * r0, top_c + d1 * r1, top_c + d0 * r1, _shade(side, band))
			if cap and r1 > 0.001:
				tri(top_c, top_c + d0 * r1, top_c + d1 * r1, top)

	static func _shade(col: Color, f: float) -> Color:
		return Color(col.r * f, col.g * f, col.b * f, col.a)

	func commit() -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_COLOR] = cols
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh

# ─── Building the board ──────────────────────────────────────────────────────

var _kind: Dictionary = {}     # Vector2i -> &"grass" | &"path" | &"water"
var _variant: Dictionary = {}  # Vector2i -> grass tile variant
var _discs: Array = []         # [centre in tile units, radius] of every road tile
var _rng := RandomNumberGenerator.new()
# Tile (0, 0) sits at the TileMap node's position, which isn't always the world
# origin. Terrain is built in tile coordinates and shifted by this.
var _origin := Vector2.ZERO
var _zone: Dictionary = {}       # Vector2i -> true: tiles inside a city district
var _protected: Dictionary = {}  # Vector2i -> true: tiles beside a road, never built on
var _street: Dictionary = {}     # Vector2i -> true: tiles that are road surface inside a city
var _taken: Dictionary = {}      # Vector2i -> true: tiles a city building already uses
var _city_plan: Array = []       # {kind, cell, size, height, wall, accent}
var _lamps: Array = []           # Vector2i street-lamp tiles
var _planters: Array = []        # Vector2i planter-tree tiles
var _gates: Array = []           # Vector2 gate-pillar spots where an avenue begins
var _tall: Dictionary = {}       # Vector2i -> top height of anything standing there (for checks)

## How high the walkable surface is at a 2D world position: on a tile's top
## face, or on the ground around it.
func surface_height(world: Vector2) -> float:
	var at := world / TILE_PX
	for d in _discs:
		if at.distance_to(d[0]) <= d[1]:
			return DISC_TOP
	return maxf(_height(Vector2i((at - _origin).floor())), PATH_H)

## Returns a Node3D holding the whole static board. Options (from the map's
## GameData entry): "villages" = towns that keep their houses (default: all);
## every other town is rebuilt as a city. "avenues" = {town: tiles} of paved
## street leading out of that city (default AVENUE_DEFAULT).
func build(map, options: Dictionary = {}) -> Node3D:
	_rng.seed = 20261109   # the same forest every time the board loads
	var tilemap: TileMap = map.tilemap
	_origin = tilemap.position / TILE_PX
	_read_terrain(tilemap)
	_discs.clear()
	_tall.clear()
	_protect_roads(map)
	var villages: Array = options.get("villages", map.CITIES)
	_plan_cities(map, map.CITIES.filter(func(c): return not villages.has(c)), options.get("avenues", {}))
	bushes.clear()
	if options.get("landing_shows", false):
		_plan_bushes(map)
	var root := Node3D.new()
	root.name = "Board3D"
	var ground := Node3D.new()
	ground.name = "Ground"
	ground.position = Vector3(_origin.x, 0.0, _origin.y)
	root.add_child(ground)
	ground.add_child(_mesh_node("Terrain", _build_terrain(), _terrain_material()))
	ground.add_child(_mesh_node("Water", _build_water(), _water_material()))
	ground.add_child(_mesh_node("Props", _build_props(tilemap), _props_material()))
	if not (_city_plan.is_empty() and _lamps.is_empty()):
		ground.add_child(_mesh_node("Cities", _build_cities(), _props_material()))
	var tiles := Batch.new()
	_build_tiles(tiles, map)
	root.add_child(_mesh_node("Tiles", tiles.commit(), _props_material()))
	return root

func _read_terrain(tilemap: TileMap) -> void:
	_kind.clear()
	_variant.clear()
	for cell in tilemap.get_used_cells(LAYER_GROUND):
		var atlas: Vector2i = tilemap.get_cell_atlas_coords(LAYER_GROUND, cell)
		_kind[cell] = &"grass" if atlas.x == GROUND_GRASS_COLUMN else &"path"
		_variant[cell] = atlas.y % TERRAIN_GRASS.size()
	for cell in tilemap.get_used_cells(LAYER_OBJECTS):
		if tilemap.get_cell_source_id(LAYER_OBJECTS, cell) == SRC_WATER:
			_kind[cell] = &"water"

func _height(cell: Vector2i) -> float:
	match _kind.get(cell, &""):
		&"grass": return GRASS_H
		&"path", &"street": return PATH_H
		&"plaza": return PLAZA_H
		&"water": return WATER_FLOOR_H
	return VOID_H

func _atlas_rect(index: int) -> Rect2:
	var s := 1.0 / float(ATLAS_CELLS)
	var inset := s * 0.002   # keeps a neighbouring tile from bleeding in at the seams
	return Rect2(Vector2(index % ATLAS_CELLS, index / ATLAS_CELLS) * s + Vector2(inset, inset),
		Vector2(s - inset * 2.0, s - inset * 2.0))

func _build_terrain() -> ArrayMesh:
	var b := Batch.new()
	var bank := _atlas_rect(TERRAIN_BANK)
	# neighbour step, the wall's two ends on this cell, and how much light it gets
	var sides := [
		[Vector2i(0, 1), Vector2(0, 1), Vector2(1, 1), 1.0],
		[Vector2i(1, 0), Vector2(1, 1), Vector2(1, 0), 0.72],
		[Vector2i(-1, 0), Vector2(0, 0), Vector2(0, 1), 0.92],
		[Vector2i(0, -1), Vector2(1, 0), Vector2(0, 0), 0.66],
	]
	for cell in _kind:
		var kind: StringName = _kind[cell]
		var h := _height(cell)
		var x := float(cell.x)
		var z := float(cell.y)
		if kind != &"water":
			var tile: int = TERRAIN_SAND[(cell.x * 7 + cell.y * 13) % 11 / 10]
			match kind:
				&"grass": tile = TERRAIN_GRASS[_variant[cell]]
				&"plaza": tile = TERRAIN_PLAZA
				&"street": tile = TERRAIN_STREET
			b.quad_uv(Vector3(x, h, z), Vector3(x + 1, h, z), Vector3(x + 1, h, z + 1), Vector3(x, h, z + 1), Color.WHITE, _atlas_rect(tile))
		var wall := _atlas_rect(TERRAIN_PLAZA) if kind == &"plaza" else bank   # city kerbs are stone
		for s in sides:
			var nh := _height(cell + s[0])
			if nh >= h:
				continue
			var p0: Vector2 = Vector2(x, z) + s[1]
			var p1: Vector2 = Vector2(x, z) + s[2]
			b.quad_uv(Vector3(p0.x, h, p0.y), Vector3(p1.x, h, p1.y), Vector3(p1.x, nh, p1.y), Vector3(p0.x, nh, p0.y),
				Color(s[3], s[3], s[3]), wall)
	return b.commit()

func _build_water() -> ArrayMesh:
	var b := Batch.new()
	var y := WATER_SURFACE_H
	for cell in _kind:
		if _kind[cell] == &"water":
			var x := float(cell.x)
			var z := float(cell.y)
			b.quad(Vector3(x, y, z), Vector3(x + 1, y, z), Vector3(x + 1, y, z + 1), Vector3(x, y, z + 1), Color.WHITE)
	return b.commit()

func _build_props(tilemap: TileMap) -> ArrayMesh:
	var b := Batch.new()
	for cell in tilemap.get_used_cells(LAYER_OBJECTS):
		var src: int = tilemap.get_cell_source_id(LAYER_OBJECTS, cell)
		var atlas: Vector2i = tilemap.get_cell_atlas_coords(LAYER_OBJECTS, cell)
		# A city (or its avenues) clears whatever stood on its ground, judged at
		# the object's base. Anything else is shrunk, or left out, so it can't
		# hide a road.
		match src:
			SRC_TREE:
				if atlas == Vector2i.ZERO and not _cleared(cell + Vector2i(1, 2)):
					var room := _room_behind(cell + Vector2i(0, 1), Vector2i(2, 1))
					if room >= TREE_MIN_ROOM:
						_tree(b, Vector3(cell.x + 1.0, GRASS_H, cell.y + 2.5), minf(1.0, room / TREE_HEIGHT))
						_mark_tall(cell + Vector2i(0, 1), Vector2i(2, 2), GRASS_H + minf(TREE_HEIGHT, room))
			SRC_HOUSE:
				if atlas == Vector2i.ZERO and not _cleared(cell + Vector2i(2, 3)):
					_house(b, cell, _room_behind(cell + Vector2i(0, 2), Vector2i(5, 1)))
			SRC_LAB:
				if atlas == Vector2i.ZERO and not _cleared(cell + Vector2i(3, 3)):
					_lab(b, cell, _room_behind(cell + Vector2i(0, 2), Vector2i(7, 1)))
			SRC_TALL_GRASS:
				if not _cleared(cell):
					_tall_grass(b, cell)
	return b.commit()

func _cleared(cell: Vector2i) -> bool:
	return _zone.has(cell) or _kind.get(cell, &"") == &"street" or _taken.has(cell)

# ─── Landing bushes ──────────────────────────────────────────────────────────
# Boards with "landing_shows": a bush beside every tile where something can
# jump out at you. Board3DView makes each one its own node so it can shake.

const BUSH_TILES := [&"WISP", &"GHOST", &"PHANTOM", &"EVENT", &"ITEM", &"CLASH"]
const BUSH_OFFSETS := [2.6, 3.2, 2.2, 4.0]   # distance from the tile, in order of preference
const BUSH_HEIGHT := 1.35
const BUSH_PROFILE := [[0.6, 0.0], [1.0, 0.35], [0.88, 0.8], [0.42, 1.05], [0.0, 1.15]]

## {space: index into map.spaces, pos: Vector3 in board units, planter: bool}
var bushes: Array = []

func _plan_bushes(map) -> void:
	var pts: Array = map.spaces.map(func(w): return w / TILE_PX - _origin)
	var segments: Array = []   # every road segment, to read the road's direction at a tile
	for route in map.ROUTES:
		var cells: Array = map._route_cells(route)
		for k in cells.size() - 1:
			segments.append([map._cell_to_world(cells[k]) / TILE_PX - _origin, map._cell_to_world(cells[k + 1]) / TILE_PX - _origin])
	for i in pts.size():
		if not BUSH_TILES.has(map.space_types[i]):
			continue
		var p: Vector2 = pts[i]
		var side := _road_direction(segments, p).orthogonal()
		var sides := [side, -side]
		if sides[0].y > sides[1].y:
			sides.reverse()   # north of the road first: a bush there hides nothing
		for ang in range(0, 360, 45):   # then anywhere around the tile
			sides.append(Vector2.UP.rotated(deg_to_rad(ang)))
		var placed := false
		for s in sides:
			for off in BUSH_OFFSETS:
				var spot: Vector2 = p + s * off
				if _bush_spot_ok(spot, pts):
					var cell := Vector2i(spot.floor())
					bushes.append({"space": i, "pos": Vector3(spot.x + _origin.x, _height(cell), spot.y + _origin.y),
						"planter": _kind[cell] == &"plaza"})
					_taken[cell] = true
					_mark_tall(cell, Vector2i.ONE, _height(cell) + BUSH_HEIGHT)
					placed = true
					break
			if placed:
				break

# Unit direction of the road segment passing closest to `p`.
func _road_direction(segments: Array, p: Vector2) -> Vector2:
	var best := INF
	var dir := Vector2.RIGHT
	for seg in segments:
		var a: Vector2 = seg[0]
		var ab: Vector2 = seg[1] - a
		if ab.length_squared() <= 0.0:
			continue
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var d := p.distance_squared_to(a + ab * t)
		if d < best:
			best = d
			dir = ab.normalized()
	return dir

func _bush_spot_ok(spot: Vector2, tiles: Array) -> bool:
	var cell := Vector2i(spot.floor())
	var kind: StringName = _kind.get(cell, &"")
	if not (kind == &"grass" or kind == &"plaza" or kind == &"path") or _taken.has(cell):
		return false
	for t in tiles:   # never on top of a road tile
		if (t as Vector2).distance_to(spot) < 1.9:
			return false
	return _room_behind(cell, Vector2i.ONE) >= BUSH_HEIGHT

## The bush (in a stone planter in cities), standing on its own origin.
func bush_mesh(planter: bool) -> ArrayMesh:
	var b := Batch.new()
	var y := 0.0
	if planter:
		b.box(Vector3(-0.65, 0, -0.5), Vector3(0.65, 0.35, 0.5), C_STONE)
		y = 0.35
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for blob in [[Vector3(-0.32, y, 0.08), 0.55], [Vector3(0.34, y, 0.02), 0.6], [Vector3(0.0, y + 0.08, -0.16), 0.66]]:
		var leaf: Color = C_LEAF.lerp(C_LEAF_ALT, rng.randf())
		var rows: int = BUSH_PROFILE.size() - 1
		for i in rows:
			var low: Array = BUSH_PROFILE[i]
			var high: Array = BUSH_PROFILE[i + 1]
			var col: Color = C_LEAF_SHADE.lerp(leaf, minf(float(i) / float(rows - 1) * 2.2, 1.0))
			var r: float = blob[1]
			b.prism(blob[0] + Vector3(0, low[1] * r, 0), low[0] * r, high[0] * r, (high[1] - low[1]) * r, 8, col, col, false)
	return b.commit()

## A small wrapped gift box, centred on its origin (the Item tile pop-out).
func gift_mesh() -> ArrayMesh:
	var b := Batch.new()
	b.box(Vector3(-0.45, -0.4, -0.45), Vector3(0.45, 0.3, 0.45), Color("e0a040"))
	b.box(Vector3(-0.52, 0.3, -0.52), Vector3(0.52, 0.5, 0.52), Color("f0c36a"))
	b.box(Vector3(-0.1, -0.41, -0.47), Vector3(0.1, 0.51, 0.47), Color("d85a30"))
	b.box(Vector3(-0.47, -0.41, -0.1), Vector3(0.47, 0.51, 0.1), Color("d85a30"))
	b.prism(Vector3(0, 0.5, 0), 0.22, 0.05, 0.3, 4, Color("d85a30"), Color("d85a30"))
	return b.commit()

## Shared look for the separate bush / gift nodes.
func props_material() -> Material:
	return _props_material()

func _tree(b: Batch, p: Vector3, max_scale := 1.12) -> void:
	var s := minf(_rng.randf_range(0.9, 1.12), max_scale)
	var leaf: Color = C_LEAF.lerp(C_LEAF_ALT, _rng.randf())
	b.prism(p + Vector3(0.18, 0.02, 0.1), 1.25 * s, 1.25 * s, 0.0, 10, C_GRASS_DARK, C_GRASS_DARK)  # ground shadow
	b.prism(p, 0.3 * s, 0.24 * s, 0.8 * s, 6, C_TRUNK, C_TRUNK)
	var base := p + Vector3(0, 0.62 * s, 0)
	var rows: int = TREE_PROFILE.size() - 1
	for i in rows:
		var low: Array = TREE_PROFILE[i]
		var high: Array = TREE_PROFILE[i + 1]
		var t := float(i) / float(rows - 1)
		var col: Color = C_LEAF_SHADE.lerp(leaf, minf(t * 2.5, 1.0)).lerp(C_LEAF_LIGHT, maxf(t - 0.5, 0.0) * 1.3)
		b.prism(base + Vector3(0, low[1] * s, 0), low[0] * s, high[0] * s, (high[1] - low[1]) * s, 10, col, col, false)

func _tall_grass(b: Batch, cell: Vector2i) -> void:
	for n in 4:
		var p := Vector3(cell.x + 0.22 + 0.56 * (n % 2), GRASS_H, cell.y + 0.22 + 0.56 * (n / 2))
		p += Vector3(_rng.randf_range(-0.08, 0.08), 0, _rng.randf_range(-0.08, 0.08))
		b.prism(p, 0.3, 0.06, _rng.randf_range(0.55, 0.8), 4, C_TALL_GRASS, C_TALL_GRASS_TIP)

# Wall and roof heights for a house that must stay under `room`, or [] when
# even a low cottage would hide the road behind it.
func _fit_house(room: float, wall: float) -> Array:
	if room >= wall + ROOF_H + 0.4:
		return [wall, ROOF_H]
	var squeeze := room - 0.2
	if squeeze < LOW_WALL + LOW_ROOF:
		return []
	return [maxf(LOW_WALL, squeeze - LOW_ROOF), LOW_ROOF]

func _house(b: Batch, cell: Vector2i, room: float) -> void:
	var fit := _fit_house(room, 2.4)
	if fit.is_empty():
		return
	var roof: Color = ROOF_COLORS[(cell.x + cell.y * 3) % ROOF_COLORS.size()]
	var x0 := cell.x + 0.4
	var x1 := cell.x + 4.6
	var z1 := cell.y + 4.6
	var z0 := z1 - 2.8
	_building_shell(b, x0, x1, z0, z1, fit[0], C_WALL, roof, GRASS_H, fit[1])
	_mark_tall(cell + Vector2i(0, 2), Vector2i(5, 3), GRASS_H + fit[0] + fit[1])
	var y := GRASS_H
	var mid := (x0 + x1) * 0.5
	var f := z1 + 0.03
	_door(b, mid, f, y)
	var win_y := minf(y + 1.35, y + fit[0] - 0.5)
	_window(b, x0 + 0.9, f, win_y)
	_window(b, x1 - 0.9, f, win_y)
	if fit[1] == ROOF_H:   # chimneys only on full-height houses
		b.box(Vector3(x1 - 1.1, y + 3.1, z0 + 0.6), Vector3(x1 - 0.5, y + 4.3, z0 + 1.2), C_STONE)

func _lab(b: Batch, cell: Vector2i, room: float) -> void:
	var fit := _fit_house(room, 2.8)
	if fit.is_empty():
		return
	var x0 := cell.x + 0.4
	var x1 := cell.x + 6.6
	var z1 := cell.y + 4.6
	var z0 := z1 - 3.2
	_building_shell(b, x0, x1, z0, z1, fit[0], C_WALL_LAB, C_ROOF_LAB, GRASS_H, fit[1])
	_mark_tall(cell + Vector2i(0, 2), Vector2i(7, 3), GRASS_H + fit[0] + fit[1])
	var y := GRASS_H
	var mid := (x0 + x1) * 0.5
	var f := z1 + 0.03
	_door(b, mid, f, y)
	for wx in [x0 + 1.0, x0 + 2.0, x1 - 2.0, x1 - 1.0]:
		_window(b, wx, f, minf(y + 1.4, y + fit[0] - 0.5))

# Four walls and a gabled roof whose ridge runs left-right.
func _building_shell(b: Batch, x0: float, x1: float, z0: float, z1: float, wall_h: float, wall: Color, roof: Color,
		y := GRASS_H, roof_h := ROOF_H) -> void:
	var eave := y + wall_h
	var ridge := eave + roof_h
	var over := 0.32
	var zm := (z0 + z1) * 0.5
	b.box(Vector3(x0, y, z0), Vector3(x1, eave, z1), wall)
	for side in [[x0, 0.95], [x1, 0.72]]:   # gable ends
		b.tri(Vector3(side[0], eave, z0), Vector3(side[0], eave, z1), Vector3(side[0], ridge, zm), Batch._shade(wall, side[1]))
	var xl := x0 - over
	var xr := x1 + over
	var strips := 4
	var front_eave := Vector3(0, eave - 0.14, z1 + over)
	var top := Vector3(0, ridge, zm)
	for i in strips:   # front slope drawn as shingle rows
		var a := front_eave.lerp(top, float(i) / float(strips))
		var c := front_eave.lerp(top, float(i + 1) / float(strips))
		var col: Color = roof if i % 2 == 0 else Batch._shade(roof, 0.88)
		b.quad(Vector3(xl, c.y, c.z), Vector3(xr, c.y, c.z), Vector3(xr, a.y, a.z), Vector3(xl, a.y, a.z), col)
	var back := Batch._shade(roof, 0.62)
	b.quad(Vector3(xl, ridge, zm), Vector3(xr, ridge, zm), Vector3(xr, eave - 0.14, z0 - over), Vector3(xl, eave - 0.14, z0 - over), back)

func _door(b: Batch, x: float, f: float, y: float) -> void:
	b.quad(Vector3(x - 0.42, y + 1.3, f), Vector3(x + 0.42, y + 1.3, f), Vector3(x + 0.42, y, f), Vector3(x - 0.42, y, f), C_DOOR)
	b.box(Vector3(x - 0.6, y, f), Vector3(x + 0.6, y + 0.12, f + 0.35), C_STONE)

func _window(b: Batch, x: float, f: float, y: float) -> void:
	b.quad(Vector3(x - 0.4, y + 0.4, f), Vector3(x + 0.4, y + 0.4, f), Vector3(x + 0.4, y - 0.4, f), Vector3(x - 0.4, y - 0.4, f), C_FRAME)
	var g := f + 0.02
	b.quad(Vector3(x - 0.3, y + 0.3, g), Vector3(x + 0.3, y + 0.3, g), Vector3(x + 0.3, y - 0.3, g), Vector3(x - 0.3, y - 0.3, g), C_WINDOW)

# ─── Cities ──────────────────────────────────────────────────────────────────
# Each city town gets an oval district: grass becomes raised pavement, road
# tiles become street, and buildings fill the pavement nearest the town first.
# Roads, road tiles and the town spot itself never move or get covered.

func _plan_cities(map, cities: Array, avenues: Dictionary) -> void:
	_zone.clear()
	_taken.clear()
	_city_plan.clear()
	_lamps.clear()
	_planters.clear()
	_gates.clear()
	if cities.is_empty():
		return
	for city in cities:
		var center: Vector2 = map._cell_to_world(map.NODES[city]) / TILE_PX - _origin
		var cells: Array = []
		var reach := Vector2i(ceili(CITY_RADIUS.x), ceili(CITY_RADIUS.y))
		for dz in range(-reach.y, reach.y + 1):
			for dx in range(-reach.x, reach.x + 1):
				var off := Vector2(dx, dz) / CITY_RADIUS
				if off.length_squared() > 1.0:
					continue
				var cell := Vector2i(floori(center.x) + dx, floori(center.y) + dz)
				# Only the road itself stays road; the old sand town square and
				# the grass around it become pavement.
				var kind: StringName = _kind.get(cell, &"")
				if kind != &"grass" and kind != &"path":
					continue
				_kind[cell] = &"street" if _street.has(cell) else &"plaza"
				_zone[cell] = true
				cells.append(cell)
		cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return (Vector2(a) + Vector2(0.5, 0.5)).distance_squared_to(center) < (Vector2(b) + Vector2(0.5, 0.5)).distance_squared_to(center))
		_place_buildings(cells)
		_place_lamps(cells)
		_pave_avenues(map, city, center, float(avenues.get(city, AVENUE_DEFAULT)))

# Every road out of a city stays paved for `length` tiles past the district's
# edge, lit by lamps on both sides, and starts at a pair of gate pillars: so
# you walk into town along a street rather than step off a dirt road.
func _pave_avenues(map, city: String, center: Vector2, length: float) -> void:
	for route in map.ROUTES:
		if route["from"] != city and route["to"] != city:
			continue
		var pts: Array = map._route_cells(route).map(func(c): return map._cell_to_world(c) / TILE_PX - _origin)
		if route["to"] == city:
			pts.reverse()
		var total := 0.0
		for i in pts.size() - 1:
			total += (pts[i] as Vector2).distance_to(pts[i + 1])
		var edge := 0.0   # where the road leaves the district
		while edge < total and ((_along(pts, edge)[0] - center) / CITY_RADIUS).length_squared() <= 1.0:
			edge += 0.5
		var end := minf(edge + length, total)
		var s := edge
		while s <= end:
			var p: Vector2 = _along(pts, s)[0]
			var r := ceili(ROAD_CLEARANCE)
			for dz in range(-r, r + 1):
				for dx in range(-r, r + 1):
					var cell := Vector2i(floori(p.x) + dx, floori(p.y) + dz)
					var d := (Vector2(cell) + Vector2(0.5, 0.5)).distance_to(p)
					var kind: StringName = _kind.get(cell, &"")
					# the street's width, plus any leftover sand of the old road
					if (d <= STREET_HALF_WIDTH and kind == &"grass") or (d <= ROAD_CLEARANCE and kind == &"path"):
						_kind[cell] = &"street"
			s += 0.5
		var lamp_at := edge + 2.0
		while lamp_at < end:
			_avenue_pair(_along(pts, lamp_at), STREET_HALF_WIDTH + 0.6, _lamps)
			lamp_at += AVENUE_LAMP_STEP
		if end < total and length > 0.0:
			_avenue_pair(_along(pts, end), STREET_HALF_WIDTH + 0.8, _gates)

# A spot on each side of the road at `at` = [point, direction], if free.
func _avenue_pair(at: Array, offset: float, into: Array) -> void:
	var side: Vector2 = (at[1] as Vector2).orthogonal()
	for sign in [-1.0, 1.0]:
		var cell := Vector2i((at[0] + side * offset * sign).floor())
		var kind: StringName = _kind.get(cell, &"")
		if (kind == &"grass" or kind == &"plaza") and not _taken.has(cell):
			into.append(cell)
			_taken[cell] = true

# [point, unit direction] at arc length `s` along a polyline.
func _along(pts: Array, s: float) -> Array:
	var left := s
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var seg := a.distance_to(b)
		if seg <= 0.0:
			continue
		if left <= seg or i == pts.size() - 2:
			return [a.lerp(b, clampf(left / seg, 0.0, 1.0)), (b - a) / seg]
		left -= seg
	return [pts.back(), Vector2.DOWN]

# Tiles within ROAD_CLEARANCE of any road's centre line stay open; the inner
# STREET_HALF_WIDTH of that is road surface wherever a city repaves.
func _protect_roads(map) -> void:
	_protected.clear()
	_street.clear()
	var r := ceili(ROAD_CLEARANCE)
	for route in map.ROUTES:
		var cells: Array = map._route_cells(route)
		for i in cells.size() - 1:
			var a: Vector2 = map._cell_to_world(cells[i]) / TILE_PX - _origin
			var c: Vector2 = map._cell_to_world(cells[i + 1]) / TILE_PX - _origin
			var steps := maxi(1, ceili(a.distance_to(c) * 2.0))
			for s in steps + 1:
				var p := a.lerp(c, float(s) / float(steps))
				for dz in range(-r, r + 1):
					for dx in range(-r, r + 1):
						var cell := Vector2i(floori(p.x) + dx, floori(p.y) + dz)
						var d := (Vector2(cell) + Vector2(0.5, 0.5)).distance_to(p)
						if d <= ROAD_CLEARANCE:
							_protected[cell] = true
						if d <= STREET_HALF_WIDTH:
							_street[cell] = true

func _place_buildings(cells: Array) -> void:
	var placed := 0
	for cell in cells:
		if placed >= MAX_BUILDINGS:
			return
		var wanted: String = "landmark" if placed == 0 else BUILDING_ORDER[(placed - 1) % BUILDING_ORDER.size()]
		var options: Array = [wanted] if wanted == "landmark" else [wanted, "shop", "row"]
		for kind in options:
			var size: Vector2i = BUILDING_SIZE[kind]
			if not _fits(cell, size):
				continue
			# A building hides the ground behind it, so its height is capped by
			# the open space between its back wall and the next road.
			var room := _room_behind(cell, size)
			if room < BUILDING_MIN_H[kind]:
				continue
			# total height, rooftop details included
			var height := room
			match kind:
				"tower": height = minf(room, _rng.randf_range(5.0, 8.8))
				"shop": height = minf(room, 2.65)
				"row": height = minf(room, 3.9)
				"landmark": height = minf(room, 5.9)
			_city_plan.append({"kind": kind, "cell": cell, "size": size, "height": height,
				"wall": CITY_WALLS[_rng.randi() % CITY_WALLS.size()], "accent": AWNINGS[_rng.randi() % AWNINGS.size()]})
			for dz in size.y:
				for dx in size.x:
					_taken[cell + Vector2i(dx, dz)] = true
			_mark_tall(cell, size, PLAZA_H + height)
			placed += 1
			break

# The whole footprint must be open pavement. Buildings may stand wall to wall
# side by side (a city block) but keep a one-tile gap front and back.
func _fits(cell: Vector2i, size: Vector2i) -> bool:
	for dz in range(-1, size.y + 1):
		for dx in size.x:
			var c := cell + Vector2i(dx, dz)
			if _taken.has(c):
				return false
			var inside := dx >= 0 and dz >= 0 and dx < size.x and dz < size.y
			if inside and (_kind.get(c, &"") != &"plaza" or _protected.has(c) or not _zone.has(c)):
				return false
	return true

# How many open tiles lie north of the footprint before a road (max 10).
# The camera looks north at 45°, so something that tall hides exactly that much
# ground behind it: keeping height under this keeps every road in view.
func _room_behind(cell: Vector2i, size: Vector2i) -> float:
	var room := 10
	for dx in size.x:
		for n in range(1, 11):
			var c := cell + Vector2i(dx, -n)
			if _protected.has(c) or _kind.get(c, &"") == &"street":
				room = mini(room, n - 1)
				break
	return float(room) - 0.3

# Lamps along the kerb every few tiles, and small planter trees dotted over
# the open pavement away from the roads.
func _place_lamps(cells: Array) -> void:
	for cell in cells:
		if _kind[cell] != &"plaza" or _taken.has(cell):
			continue
		var kerb := false
		for n in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			kerb = kerb or _kind.get(cell + n, &"") == &"street"
		if kerb and posmod(cell.x + cell.y * 2, 5) == 0:
			_lamps.append(cell)
			_taken[cell] = true
		elif not kerb and not _protected.has(cell) and posmod(cell.x * 3 + cell.y * 5, 13) == 0 \
				and _room_behind(cell, Vector2i.ONE) >= PLANTER_HEIGHT:
			_planters.append(cell)
			_taken[cell] = true
			_mark_tall(cell, Vector2i.ONE, PLAZA_H + PLANTER_HEIGHT)

func _mark_tall(cell: Vector2i, size: Vector2i, top: float) -> void:
	for dz in size.y:
		for dx in size.x:
			var c := cell + Vector2i(dx, dz)
			_tall[c] = maxf(float(_tall.get(c, 0.0)), top)

func _build_cities() -> ArrayMesh:
	var b := Batch.new()
	for plan in _city_plan:
		var cell: Vector2i = plan["cell"]
		var size: Vector2i = plan["size"]
		var lo := Vector3(cell.x + 0.15, PLAZA_H, cell.y + 0.15)
		var body: float = plan["height"]   # walls only: what sits on top is taken off
		match plan["kind"]:
			"landmark": body -= LANDMARK_TOP + 1.6   # upper storey, then the flag
			"tower": body -= TOWER_TOP
			"shop": body -= 0.25
			"row": body -= ROW_ROOF
		var hi := Vector3(cell.x + size.x - 0.15, PLAZA_H + body, cell.y + size.y - 0.15)
		match plan["kind"]:
			"landmark": _landmark(b, lo, hi)
			"tower": _tower(b, lo, hi, plan["wall"], plan["accent"])
			"shop": _shop(b, lo, hi, plan["wall"], plan["accent"])
			"row": _row_house(b, lo, hi, plan["wall"], plan["accent"])
	for cell in _lamps:
		var p := Vector3(cell.x + 0.5, _height(cell), cell.y + 0.5)
		b.prism(p, 0.09, 0.07, 1.9, 4, C_FRAME, C_FRAME)
		b.box(p + Vector3(-0.2, 1.9, -0.2), p + Vector3(0.2, 2.25, 0.2), C_WINDOW)
	for cell in _gates:
		var p := Vector3(cell.x + 0.5, _height(cell), cell.y + 0.5)
		b.box(p + Vector3(-0.32, 0, -0.32), p + Vector3(0.32, 2.3, 0.32), C_STONE)
		b.box(p + Vector3(-0.42, 2.3, -0.42), p + Vector3(0.42, 2.5, 0.42), C_PAVE)
		b.box(p + Vector3(-0.18, 2.5, -0.18), p + Vector3(0.18, 2.85, 0.18), C_WINDOW)
	for cell in _planters:
		var p := Vector3(cell.x + 0.5, PLAZA_H, cell.y + 0.5)
		b.box(p + Vector3(-0.45, 0, -0.45), p + Vector3(0.45, 0.35, 0.45), C_STONE)
		b.prism(p + Vector3(0, 0.35, 0), 0.5, 0.5, 0.02, 8, C_GRASS_DARK, C_GRASS_DARK)
		var leaf: Color = C_LEAF.lerp(C_LEAF_ALT, _rng.randf())
		var rows: int = TREE_PROFILE.size() - 1
		for i in rows:
			var low: Array = TREE_PROFILE[i]
			var high: Array = TREE_PROFILE[i + 1]
			var col: Color = C_LEAF_SHADE.lerp(leaf, minf(float(i) / float(rows - 1) * 2.5, 1.0))
			b.prism(p + Vector3(0, 0.55 + low[1] * 0.45, 0), low[0] * 0.45, high[0] * 0.45, (high[1] - low[1]) * 0.45, 8, col, col, false)
	return b.commit()

# A flat roof with a low parapet, shared by the city blocks.
func _flat_roof(b: Batch, lo: Vector3, hi: Vector3, trim: Color) -> void:
	b.box(Vector3(lo.x - 0.06, hi.y, lo.z - 0.06), Vector3(hi.x + 0.06, hi.y + 0.22, hi.z + 0.06), trim)

func _tower(b: Batch, lo: Vector3, hi: Vector3, wall: Color, accent: Color) -> void:
	b.box(lo, hi, wall)
	_flat_roof(b, lo, hi, Batch._shade(wall, 0.8))
	b.box(Vector3(lo.x + 0.5, hi.y + 0.22, lo.z + 0.4), Vector3(lo.x + 1.3, hi.y + 0.9, lo.z + 1.1), C_STONE)
	var f := hi.z + 0.02
	var floors := int((hi.y - lo.y - 0.3) / 1.05)
	var cols := int(hi.x - lo.x)
	for fl in range(1, floors):
		var y := lo.y + 0.55 + fl * 1.05
		for c in cols:
			var x := lo.x + 0.5 + c + ((hi.x - lo.x) - cols) * 0.5
			var col: Color = C_WINDOW if _rng.randf() < 0.65 else C_DARK_WINDOW
			b.quad(Vector3(x - 0.24, y + 0.28, f), Vector3(x + 0.24, y + 0.28, f), Vector3(x + 0.24, y - 0.28, f), Vector3(x - 0.24, y - 0.28, f), col)
	var mid := (lo.x + hi.x) * 0.5
	b.quad(Vector3(mid - 0.45, lo.y + 1.2, f), Vector3(mid + 0.45, lo.y + 1.2, f), Vector3(mid + 0.45, lo.y, f), Vector3(mid - 0.45, lo.y, f), accent.darkened(0.3))

func _shop(b: Batch, lo: Vector3, hi: Vector3, wall: Color, accent: Color) -> void:
	b.box(lo, hi, wall)
	_flat_roof(b, lo, hi, accent)
	var f := hi.z + 0.02
	# big shop window, door, sign band and a striped awning
	b.quad(Vector3(lo.x + 0.3, lo.y + 1.35, f), Vector3(hi.x - 1.2, lo.y + 1.35, f), Vector3(hi.x - 1.2, lo.y + 0.25, f), Vector3(lo.x + 0.3, lo.y + 0.25, f), C_GLASS)
	b.quad(Vector3(hi.x - 0.95, lo.y + 1.3, f), Vector3(hi.x - 0.35, lo.y + 1.3, f), Vector3(hi.x - 0.35, lo.y, f), Vector3(hi.x - 0.95, lo.y, f), C_DOOR)
	b.quad(Vector3(lo.x + 0.2, hi.y - 0.15, f), Vector3(hi.x - 0.2, hi.y - 0.15, f), Vector3(hi.x - 0.2, hi.y - 0.55, f), Vector3(lo.x + 0.2, hi.y - 0.55, f), accent)
	var stripes := int((hi.x - lo.x) / 0.5)
	var step := (hi.x - lo.x) / float(stripes)
	for i in stripes:
		var x0 := lo.x + i * step
		var col: Color = accent if i % 2 == 0 else Color.WHITE
		b.quad(Vector3(x0, lo.y + 1.65, f), Vector3(x0 + step, lo.y + 1.65, f), Vector3(x0 + step, lo.y + 1.35, f + 0.7), Vector3(x0, lo.y + 1.35, f + 0.7), col)

func _row_house(b: Batch, lo: Vector3, hi: Vector3, wall: Color, accent: Color) -> void:
	_building_shell(b, lo.x, hi.x, lo.z, hi.z, hi.y - lo.y, wall, accent, lo.y, ROW_ROOF)
	var f := hi.z + 0.03
	var mid := (lo.x + hi.x) * 0.5
	_door(b, mid, f, lo.y)
	if hi.y - lo.y >= 2.5:
		_window(b, mid, f, lo.y + 2.0)

# The town's big building: a pale hall with columns, a banner and a flag.
func _landmark(b: Batch, lo: Vector3, hi: Vector3) -> void:
	b.box(lo, hi, C_LANDMARK)
	var inner_lo := Vector3(lo.x + 1.0, hi.y, lo.z + 0.5)
	var inner_hi := Vector3(hi.x - 1.0, hi.y + 1.2, hi.z - 0.8)
	b.box(inner_lo, inner_hi, Batch._shade(C_LANDMARK, 0.95))
	_flat_roof(b, inner_lo, inner_hi, C_ROOF_LAB)
	_flat_roof(b, lo, hi, C_ROOF_LAB)
	var f := hi.z + 0.02
	var mid := (lo.x + hi.x) * 0.5
	for i in 4:   # columns across the front
		var x := lo.x + 0.6 + i * (hi.x - lo.x - 1.2) / 3.0
		b.box(Vector3(x - 0.15, lo.y, hi.z), Vector3(x + 0.15, hi.y - 0.4, hi.z + 0.35), Color.WHITE)
	b.box(Vector3(lo.x + 0.2, hi.y - 0.45, hi.z), Vector3(hi.x - 0.2, hi.y - 0.1, hi.z + 0.5), C_STONE)
	b.quad(Vector3(mid - 0.6, lo.y + 1.6, f), Vector3(mid + 0.6, lo.y + 1.6, f), Vector3(mid + 0.6, lo.y, f), Vector3(mid - 0.6, lo.y, f), C_DOOR)
	b.quad(Vector3(mid - 0.7, hi.y - 0.6, f), Vector3(mid + 0.7, hi.y - 0.6, f), Vector3(mid + 0.7, lo.y + 1.9, f), Vector3(mid - 0.7, lo.y + 1.9, f), C_BANNER)
	var pole := Vector3(mid, inner_hi.y + 0.22, (inner_lo.z + inner_hi.z) * 0.5)
	b.prism(pole, 0.06, 0.05, 1.6, 4, C_FRAME, C_FRAME)
	b.quad(pole + Vector3(0.05, 1.6, 0), pole + Vector3(0.95, 1.45, 0), pole + Vector3(0.95, 1.0, 0), pole + Vector3(0.05, 1.15, 0), C_BANNER)

func _build_tiles(b: Batch, map) -> void:
	for route in map.ROUTES:
		var cells: Array = map._route_cells(route)
		for i in cells.size() - 1:
			_trail(b, map._cell_to_world(cells[i]), map._cell_to_world(cells[i + 1]))
	for i in map.spaces.size():
		var col: Color = map.SPACE_TYPE_COLORS.get(map.space_types[i], Color("888888"))
		_disc(b, map.spaces[i], 0.96, col)
	for node_name in map.NODES:
		if map.CITIES.has(node_name):
			_disc(b, map._cell_to_world(map.NODES[node_name]), 1.4, map.CITY_COLOR)

# A worn line along the road, so players can see which tiles connect at a fork.
func _trail(b: Batch, from: Vector2, to: Vector2) -> void:
	var a := from / TILE_PX
	var c := to / TILE_PX
	var side := (c - a).orthogonal().normalized() * TRAIL_WIDTH * 0.5
	var y := PATH_H + 0.03
	b.quad(Vector3(a.x - side.x, y, a.y - side.y), Vector3(a.x + side.x, y, a.y + side.y),
		Vector3(c.x + side.x, y, c.y + side.y), Vector3(c.x - side.x, y, c.y - side.y), C_TRAIL)

func _disc(b: Batch, world: Vector2, radius: float, col: Color) -> void:
	var p := Vector3(world.x / TILE_PX, PATH_H, world.y / TILE_PX)
	b.prism(p, radius + 0.1, radius + 0.1, DISC_RIM_H, 20, C_TILE_RIM, C_TILE_RIM)
	b.prism(p + Vector3(0, DISC_RIM_H, 0), radius, radius, DISC_TOP - DISC_RIM_H, 20, Batch._shade(col, 0.7), col)
	_discs.append([world / TILE_PX, radius + 0.1])

# ─── Materials and generated textures ────────────────────────────────────────

func _mesh_node(node_name: String, mesh: Mesh, material: Material) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.name = node_name
	n.mesh = mesh
	n.material_override = material
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return n

func _base_material(tex: Texture2D, repeat: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.albedo_texture = tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.texture_repeat = repeat
	return m

func _terrain_material() -> Material:
	return _base_material(ImageTexture.create_from_image(_terrain_atlas()), false)

var _props_mat: Material = null

func _props_material() -> Material:
	if _props_mat == null:
		_props_mat = _base_material(ImageTexture.create_from_image(_speckle_tile()), true)
	return _props_mat

func _water_material() -> Material:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;
varying vec3 world;
void vertex() { world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = floor(world.xz * 8.0) / 8.0;
	float t = floor(TIME * 6.0) / 6.0;
	float w = sin(p.x * 2.1 + sin(p.y * 1.3 + t * 0.7) * 1.8 + t * 1.2) + sin(p.y * 3.4 - t);
	vec3 deep = pow(vec3(0.27, 0.53, 0.80), vec3(2.2));
	vec3 mid = pow(vec3(0.40, 0.68, 0.90), vec3(2.2));
	vec3 foam = pow(vec3(0.84, 0.95, 1.0), vec3(2.2));
	ALBEDO = mix(mix(deep, mid, step(0.35, w)), foam, step(1.55, w));
}
"""
	var m := ShaderMaterial.new()
	m.shader = shader
	return m

func _terrain_atlas() -> Image:
	var px := int(TILE_PX)
	var img := Image.create(px * ATLAS_CELLS, px * ATLAS_CELLS, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in TERRAIN_GRASS:
		_fill_tile(img, i, C_GRASS)
	_dashes(img, TERRAIN_GRASS[1], C_GRASS_PALE, rng, 3)
	_dashes(img, TERRAIN_GRASS[2], C_GRASS_DARK, rng, 2)
	_specks(img, TERRAIN_GRASS[3], C_GRASS_PALE, rng, 3)
	for i in TERRAIN_SAND:
		_fill_tile(img, i, C_SAND)
	_specks(img, TERRAIN_SAND[0], C_SAND_DARK, rng, 4)
	_specks(img, TERRAIN_SAND[1], C_SAND_DARK, rng, 9)
	_fill_tile(img, TERRAIN_PLAZA, C_PAVE)
	var po := _tile_origin(TERRAIN_PLAZA)
	for k in int(TILE_PX):   # paving slabs: a grid line every 8 px
		img.set_pixel(po.x + k, po.y + 7, C_PAVE_LINE)
		img.set_pixel(po.x + 7, po.y + k, C_PAVE_LINE)
	_specks(img, TERRAIN_PLAZA, C_PAVE_LINE, rng, 5)
	_fill_tile(img, TERRAIN_STREET, C_STREET)
	var so := _tile_origin(TERRAIN_STREET)
	for row in [3, 7, 11, 15]:   # setts: staggered courses of stone blocks
		for k in int(TILE_PX):
			img.set_pixel(so.x + k, so.y + row, C_STREET_LINE)
		for k in 3:
			var x: int = (k * 6 + (3 if row % 8 == 3 else 0)) % 16
			for y in range(row - 3, row):
				img.set_pixel(so.x + x, so.y + y, C_STREET_LINE)
	_fill_tile(img, TERRAIN_BANK, C_BANK)
	_specks(img, TERRAIN_BANK, C_BANK_DARK, rng, 26)
	var o := _tile_origin(TERRAIN_BANK)
	for x in px:   # grassy lip along the top of every bank
		for y in 4 + (x % 3):
			img.set_pixel(o.x + x, o.y + y, C_BANK_TOP)
	return img

func _speckle_tile() -> Image:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for n in 34:
		img.set_pixel(rng.randi() % 16, rng.randi() % 16, Color(0.9, 0.9, 0.9))
	return img

func _tile_origin(index: int) -> Vector2i:
	return Vector2i(index % ATLAS_CELLS, index / ATLAS_CELLS) * int(TILE_PX)

func _fill_tile(img: Image, index: int, col: Color) -> void:
	img.fill_rect(Rect2i(_tile_origin(index), Vector2i(int(TILE_PX), int(TILE_PX))), col)

func _specks(img: Image, index: int, col: Color, rng: RandomNumberGenerator, count: int) -> void:
	var o := _tile_origin(index)
	for n in count:
		img.set_pixel(o.x + rng.randi() % 16, o.y + rng.randi() % 16, col)

func _dashes(img: Image, index: int, col: Color, rng: RandomNumberGenerator, count: int) -> void:
	var o := _tile_origin(index)
	for n in count:
		var x := rng.randi() % 13
		var y := rng.randi() % 16
		for k in 3:
			img.set_pixel(o.x + x + k, o.y + y, col)

# ─── Dice ────────────────────────────────────────────────────────────────────

const DIE_HALF := 0.45
const C_DIE := Color("f4f1ea")
const C_PIP := Color("2a2438")
# Which face shows which number (opposite faces add up to 7).
const DIE_FACES := {1: Vector3.UP, 6: Vector3.DOWN, 2: Vector3.RIGHT, 5: Vector3.LEFT, 3: Vector3.BACK, 4: Vector3.FORWARD}
const DIE_PIPS := {
	1: [[0, 0]], 2: [[-1, -1], [1, 1]], 3: [[-1, -1], [0, 0], [1, 1]],
	4: [[-1, -1], [1, -1], [-1, 1], [1, 1]], 5: [[-1, -1], [1, -1], [0, 0], [-1, 1], [1, 1]],
	6: [[-1, -1], [1, -1], [-1, 0], [1, 0], [-1, 1], [1, 1]],
}

## A white die centred on its origin. Unlike the board it carries normals,
## because it tumbles and is lit by a real light rather than baked shading.
func die_mesh() -> ArrayMesh:
	_die_verts = PackedVector3Array()
	_die_norms = PackedVector3Array()
	_die_cols = PackedColorArray()
	for value in DIE_FACES:
		var n: Vector3 = DIE_FACES[value]
		var t := die_face_tangent(n)
		var bt := n.cross(t)
		var c := n * DIE_HALF
		var h := DIE_HALF
		_die_tri(c - t * h - bt * h, c + t * h - bt * h, c + t * h + bt * h, n, C_DIE)
		_die_tri(c - t * h - bt * h, c + t * h + bt * h, c - t * h + bt * h, n, C_DIE)
		for pip in DIE_PIPS[value]:   # a little 8-sided dot, just proud of the face
			var at: Vector3 = n * (DIE_HALF + 0.004) + t * pip[0] * 0.23 + bt * pip[1] * 0.23
			for k in 8:
				var a0 := TAU * k / 8.0
				var a1 := TAU * (k + 1) / 8.0
				_die_tri(at, at + (t * cos(a0) + bt * sin(a0)) * 0.085, at + (t * cos(a1) + bt * sin(a1)) * 0.085, n, C_PIP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _die_verts
	arrays[Mesh.ARRAY_NORMAL] = _die_norms
	arrays[Mesh.ARRAY_COLOR] = _die_cols
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

# (members, not locals in a lambda: packed arrays are copied into lambdas)
var _die_verts := PackedVector3Array()
var _die_norms := PackedVector3Array()
var _die_cols := PackedColorArray()

func _die_tri(a: Vector3, b: Vector3, c: Vector3, n: Vector3, col: Color) -> void:
	for p in [a, b, c]:
		_die_verts.append(p)
		_die_norms.append(n)
		_die_cols.append(col)

# The "across" direction of a face: pips are laid out along it and n × it.
static func die_face_tangent(n: Vector3) -> Vector3:
	return (n.cross(Vector3.UP) if absf(n.y) < 0.5 else Vector3.RIGHT).normalized()

# The die shades its own faces from their direction (like the rest of the
# board, no real lights), so the shading stays right while it spins.
func die_material() -> Material:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;
void fragment() {
	// the faces are wound the other way round, so Godot hands us the normal
	// flipped; turn it back outward
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(FRONT_FACING ? NORMAL : -NORMAL, 0.0)).xyz);
	float lit = 0.62 + 0.38 * max(dot(n, normalize(vec3(-0.35, 0.8, 0.5))), 0.0);
	ALBEDO = COLOR.rgb * lit;   // the Compatibility renderer shows unshaded colour as-is
}
"""
	var m := ShaderMaterial.new()
	m.shader = shader
	return m

## The die's rotation that turns face `value` square-on toward `toward` (a
## unit vector, e.g. at the camera), with the face's rows of pips level.
static func die_face_toward(value: int, toward: Vector3) -> Basis:
	var n: Vector3 = DIE_FACES[value]
	var t := die_face_tangent(n)
	var local := Basis(t, n.cross(t), n)   # the face's own frame
	var across := Vector3.RIGHT
	var world := Basis(across, toward.cross(across), toward)   # where that frame should end up
	return world * local.inverse()
