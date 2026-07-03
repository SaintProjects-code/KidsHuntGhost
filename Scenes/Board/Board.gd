extends Node2D
## Gameplay scene: holds the map + UI and runs turns. Tokens move along a board
## GRAPH that Board builds from the map's nodes/routes (Map1 is read-only).
## Players pick a direction at forks, can't reverse into a junction they've
## already passed, and are asked whether to stop each time they reach a city.

const PLAYER_SHEET := "res://Assets/Player/Male_Spritesheet.png"
# The sheet is 3 columns (walk frames) x 3 rows (facings) of 16x32 cells.
const FRAME_SIZE := Vector2i(16, 32)
const ROW_DOWN := 0                # facing the camera
const ROW_UP := 1                  # facing away
const ROW_SIDE := 2                # profile (drawn facing left; flip for right)
const WALK_COLS := [1, 0, 1, 2]    # step order; column 1 is the standing/idle pose
const WALK_FPS := 8.0
const TOKEN_SCALE := 2.4
# Corners for the players whose turn it ISN'T (top-left, top-right, bottom-left,
# bottom-right). Big enough that the scaled tokens fan out instead of stacking.
const TOKEN_OFFSETS := [Vector2(-29, -8), Vector2(29, -8), Vector2(-29, 18), Vector2(29, 18)]
const ACTIVE_TOKEN_DROP := Vector2(0, 10)   # active player sits a bit low, off the tile name
const STEP_TIME := 0.28
const CPU_END_TURN_DELAY := 0.7   # pause after a CPU lands, before its turn ends
const START_NODE := "A"
const PAN_SPEED := 600.0           # camera move speed (px/sec) for arrow keys
const FOLLOW_LERP := 6.0           # how snappily the camera chases the active token

@onready var map = $Map1   # the Map1 instance (read-only source of the layout)
@onready var camera: Camera2D = $Camera2D
@onready var roll_button: Button = $BoardUI/Root/ActionBar/RollButton
@onready var end_turn_button: Button = $BoardUI/Root/ActionBar/EndTurnButton
@onready var info_label: Label = $BoardUI/Root/InfoLabel
@onready var choice_panel: Panel = $BoardUI/Root/ChoicePanel
@onready var choice_title: Label = $BoardUI/Root/ChoicePanel/VBox/Title
@onready var choice_buttons: HBoxContainer = $BoardUI/Root/ChoicePanel/VBox/Buttons
@onready var event_panel: Panel = $BoardUI/Root/EventPanel
@onready var event_title: Label = $BoardUI/Root/EventPanel/VBox/Title
@onready var event_body: Label = $BoardUI/Root/EventPanel/VBox/Body
@onready var event_ok: Button = $BoardUI/Root/EventPanel/VBox/OkButton

signal _choice_selected(index: int)
signal _event_closed

# --- movement graph (built from the map) ---
var _routes: Array = []            # the map's route dictionaries
var _cities: Array = []            # city names
var _node_pos: Dictionary = {}     # name -> Vector2 world position
var _node_routes: Dictionary = {}  # name -> Array[int] incident route indices
var _stops: Array = []             # per route: Array[Vector2] = [from, spaces..., to]
var _poly: Array = []              # per route: Array[Vector2] world polyline (from, corners.., to)
var _poly_len: Array = []          # per route: total arc-length of that polyline
var _route_space_start: Array = [] # per route: index into map.spaces of its first space
var _stop_dist: Array = []         # per route: arc-length along the polyline of each stop

# --- per-player movement state ---
var _token_frames: SpriteFrames    # shared walk animations (down/up/side)
var _tokens: Array = []            # AnimatedSprite2D
var _token_base: Array = []        # per token: its tile position, before the side offset
var _route_of: Array = []          # current route index
var _index_of: Array = []          # current stop index in that route
var _heading_of: Array = []        # +1 / -1 along the route's stop list
var _came_route: Array = []        # route arrived on (-1 = none)
var _passed: Array = []            # Dictionary set of passed junction names
var _moving: bool = false
var _moves_left: int = 0           # steps left this roll, for the choice prompt
var _follow: Node2D = null         # token the camera is currently following (null = free)

func _ready() -> void:
	choice_panel.hide()
	event_panel.hide()
	event_ok.pressed.connect(func(): _event_closed.emit())
	_build_graph()
	if _node_pos.has(START_NODE):
		camera.position = _node_pos[START_NODE]   # start framed on city A
	if GameState.players.is_empty():
		_make_dummies()
	_spawn_tokens()
	_spawn_hud()
	# The HUD was just added after these panels, so it would draw over them.
	# Controls render in tree order — move the event/choice popups to the
	# front so they always sit on top of the HUD (player panels, buttons).
	choice_panel.move_to_front()
	event_panel.move_to_front()
	EventBus.turn_started.connect(_on_turn_started)
	EventBus.dice_rolled.connect(_on_dice_rolled)
	TurnSystem.start_game()

# The on-screen HUD (buttons, timer, player panels) lives in its own script so
# Board.gd stays focused on the board itself. It's parented under
# BoardUI/Root (not Board directly) so its buttons/panels/popups inherit
# MenuTheme.tres like the rest of the board chrome.
func _spawn_hud() -> void:
	var hud: Control = preload("res://Scenes/Board/BoardHUD.gd").new()
	hud.name = "HUD"
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Root runs with process_mode = Always (so Settings/View-Map keep working
	# while paused); pull the HUD back to Pausable so its timer still stops.
	hud.process_mode = Node.PROCESS_MODE_PAUSABLE
	$BoardUI/Root.add_child(hud)
	# Owns the wild-encounter window flow (Fight / Catch / Battle).
	var enc: CanvasLayer = preload("res://Scenes/UI/EncounterController.gd").new()
	enc.name = "EncounterController"
	add_child(enc)
	# Owns event / item / competition / city (gym / shop / Elite Four) + win.
	var tiles: CanvasLayer = preload("res://Scenes/UI/TileController.gd").new()
	tiles.name = "TileController"
	add_child(tiles)

# Camera: follow whoever's turn it is, with arrow keys / WASD as a manual override.
func _process(delta: float) -> void:
	var dir: Vector2 = Vector2.ZERO
	if Input.is_action_pressed("ui_left") or _held(KEY_LEFT) or _held(KEY_A):
		dir.x -= 1.0
	if Input.is_action_pressed("ui_right") or _held(KEY_RIGHT) or _held(KEY_D):
		dir.x += 1.0
	if Input.is_action_pressed("ui_up") or _held(KEY_UP) or _held(KEY_W):
		dir.y -= 1.0
	if Input.is_action_pressed("ui_down") or _held(KEY_DOWN) or _held(KEY_S):
		dir.y += 1.0
	if dir != Vector2.ZERO:
		# manual panning overrides the follow for this frame
		# divide by zoom so it feels the same speed at any zoom level
		camera.position += dir.normalized() * PAN_SPEED * delta / camera.zoom.x
	elif _follow != null and is_instance_valid(_follow):
		# smoothly chase the active player's token
		var t: float = clampf(FOLLOW_LERP * delta, 0.0, 1.0)
		camera.global_position = camera.global_position.lerp(_follow.global_position, t)

func _held(keycode: int) -> bool:
	return Input.is_key_pressed(keycode) or Input.is_physical_key_pressed(keycode)

# ---------------- Build the movement graph from the map ----------------

func _node_world(cell: Vector2i) -> Vector2:
	var tm: TileMap = map.tilemap
	return tm.position + tm.map_to_local(cell)

func _build_graph() -> void:
	_routes = map.ROUTES
	_cities = map.CITIES
	var nodes: Dictionary = map.NODES
	var all_spaces: Array = map.spaces
	var spacing: float = map.SPACING

	_node_pos = {}
	for k in nodes:
		var nm: String = k
		var cell: Vector2i = nodes[nm]
		_node_pos[nm] = _node_world(cell)

	# Rebuild each route's stop list by slicing the spaces the map already drew,
	# so tokens land exactly on the visible circles.
	_stops = []
	_poly = []
	_poly_len = []
	_route_space_start = []
	_stop_dist = []
	var idx: int = 0
	for r in range(_routes.size()):
		var route: Dictionary = _routes[r]
		var from_n: String = route["from"]
		var to_n: String = route["to"]
		# world-space polyline through the corners (same maths the map uses);
		# tokens travel along this so they hug the drawn line round bends.
		var cells: Array = [nodes[from_n]]
		for c in route["corners"]:
			var cc: Vector2i = c
			cells.append(cc)
		cells.append(nodes[to_n])
		var world_poly: Array = []
		for wc in cells:
			world_poly.append(_node_world(wc))
		var total: float = 0.0
		for i in range(world_poly.size() - 1):
			total += world_poly[i].distance_to(world_poly[i + 1])
		_poly.append(world_poly)
		_poly_len.append(total)
		var n: int = route.get("spaces", -1)
		if n < 0:
			n = int(round(total / spacing))
		if total <= 0.0 or n <= 0:
			n = 0
		# Remember where this route's spaces begin in the shared map.spaces list,
		# so we can look a landed space's type back up later.
		_route_space_start.append(idx)
		var seg: Array = all_spaces.slice(idx, idx + n)
		idx += n
		var stop_list: Array = [_node_pos[from_n]]
		for sp in seg:
			stop_list.append(sp)
		stop_list.append(_node_pos[to_n])
		_stops.append(stop_list)
		# Arc-length of each stop along the route's polyline. The spaces are no
		# longer evenly spaced, so we measure each one's true distance instead of
		# assuming a fixed fraction — tokens then land exactly on the drawn tiles.
		var dist_list: Array = [0.0]
		for sp in seg:
			dist_list.append(_arc_length_of(world_poly, sp))
		dist_list.append(total)
		_stop_dist.append(dist_list)

	_node_routes = {}
	for r in range(_routes.size()):
		var route2: Dictionary = _routes[r]
		_add_incident(route2["from"], r)
		_add_incident(route2["to"], r)

func _add_incident(node_name, r: int) -> void:
	var nm: String = node_name
	if not _node_routes.has(nm):
		_node_routes[nm] = []
	_node_routes[nm].append(r)

func _is_city(node_name: String) -> bool:
	return _cities.has(node_name)

func _dest_label(node_name: String) -> String:
	return map.NAMES.get(node_name, node_name)

# ---------------- Players ----------------

func _make_dummies() -> void:
	var cols: Array = [Color("ff5a5a"), Color("5aa6ff")]
	var starters: Array = ["Charmander", "Squirtle"]
	for i in 2:
		var p := PlayerData.new()
		p.player_name = "Player %d" % (i + 1)
		p.color = cols[i]
		p.team.append(SpiritsData.get_spirit(starters[i]))
		GameState.players.append(p)

func _build_token_frames() -> SpriteFrames:
	# One shared set of walk cycles (down / up / side) sliced from the sheet.
	var sheet: Texture2D = load(PLAYER_SHEET)
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	var rows := {"down": ROW_DOWN, "up": ROW_UP, "side": ROW_SIDE}
	for anim in rows:
		var row: int = rows[anim]
		sf.add_animation(anim)
		sf.set_animation_loop(anim, true)
		sf.set_animation_speed(anim, WALK_FPS)
		for col in WALK_COLS:
			var tex := AtlasTexture.new()
			tex.atlas = sheet
			tex.region = Rect2(col * FRAME_SIZE.x, row * FRAME_SIZE.y, FRAME_SIZE.x, FRAME_SIZE.y)
			sf.add_frame(anim, tex)
	return sf

func _spawn_tokens() -> void:
	if _stops.is_empty() or not _node_pos.has(START_NODE):
		return
	_token_frames = _build_token_frames()
	var start_routes: Array = _node_routes.get(START_NODE, [])
	for i in GameState.players.size():
		var spr := AnimatedSprite2D.new()
		spr.sprite_frames = _token_frames
		spr.animation = "down"
		spr.frame = 0   # WALK_COLS[0] == column 1 == the standing pose
		spr.stop()
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.modulate = GameState.players[i].color
		spr.scale = Vector2(TOKEN_SCALE, TOKEN_SCALE)
		spr.offset = Vector2(0, -FRAME_SIZE.y * 0.5 + 4)   # seat the feet on the path point
		map.add_child(spr)
		_tokens.append(spr)
		# start sitting on city A, facing one of its roads
		var r0: int = start_routes[0] if not start_routes.is_empty() else 0
		_route_of.append(r0)
		if not start_routes.is_empty() and _routes[r0]["from"] == START_NODE:
			_index_of.append(0)
			_heading_of.append(1)
		else:
			_index_of.append(_stops[r0].size() - 1)
			_heading_of.append(-1)
		_came_route.append(-1)
		_passed.append({})
		_token_base.append(_node_pos[START_NODE])
		spr.position = _token_base[i] + _offset_for(i)

# The active player sits centred on the tile (on top); everyone else is nudged
# to a corner so tokens sharing a tile don't overlap.
func _offset_for(player_i: int) -> Vector2:
	if player_i == GameState.current_player_index:
		return ACTIVE_TOKEN_DROP
	return TOKEN_OFFSETS[player_i % TOKEN_OFFSETS.size()]

# Re-seat every token for the current turn (active one centred, rest to the side).
func _reposition_tokens() -> void:
	for i in _tokens.size():
		if is_instance_valid(_tokens[i]) and i < _token_base.size():
			_tokens[i].position = _token_base[i] + _offset_for(i)

# ---------------- Turns ----------------

func _on_turn_started(idx: int) -> void:
	info_label.text = "%s's turn — roll!" % GameState.players[idx].player_name
	roll_button.disabled = GameState.players[idx].is_cpu
	end_turn_button.disabled = true   # can't end a turn before rolling/moving
	# point the camera at whoever's turn it is
	if idx < _tokens.size():
		_follow = _tokens[idx]
	# active token jumps on top of its tile; the others slide to their corners
	_reposition_tokens()

func _on_roll_pressed() -> void:
	if _moving:
		return
	roll_button.disabled = true
	TurnSystem.roll_dice()

func _on_dice_rolled(result: int) -> void:
	var idx: int = GameState.current_player_index
	info_label.text = "%s rolled %d" % [GameState.players[idx].player_name, result]
	await _move_player(idx, result)
	# CPUs end their own turn; a human stays put (camera holds on them) until
	# they press End Turn.
	if GameState.players[idx].is_cpu:
		# Hold a beat after landing so the turn reads at a human's pace, not instantly.
		await get_tree().create_timer(CPU_END_TURN_DELAY).timeout
		TurnSystem.advance_turn()
	else:
		info_label.text = "%s — press End Turn" % GameState.players[idx].player_name
		end_turn_button.disabled = false

func _on_end_turn_pressed() -> void:
	if _moving:
		return
	end_turn_button.disabled = true
	TurnSystem.advance_turn()

# ---------------- Movement ----------------

func _at_node(player_i: int) -> bool:
	var i: int = _index_of[player_i]
	return i == 0 or i == _stops[_route_of[player_i]].size() - 1

func _current_node(player_i: int) -> String:
	var route: Dictionary = _routes[_route_of[player_i]]
	return route["from"] if _index_of[player_i] == 0 else route["to"]

func _move_player(player_i: int, steps: int) -> void:
	if _stops.is_empty():
		return
	_moving = true
	var remaining: int = steps
	while remaining > 0:
		_moves_left = remaining   # shown on "Which way?" prompts
		# Leaving a city (the only node we ever rest on): pick a road first.
		if _at_node(player_i):
			if not await _choose_direction(player_i, _current_node(player_i)):
				break   # dead end
		# If the next stop is a junction, choose its onward road NOW — while the
		# token is still on a real tile — then glide straight through. Junctions
		# don't cost a step and the token never stops on one.
		var nxt: String = _peek_next_node(player_i)
		if nxt != "" and not _is_city(nxt):
			var arrival: int = _route_of[player_i]
			var chosen: int = await _pick_route(player_i, nxt, arrival)
			if chosen == -1:
				break   # dead end at the junction; stay on this tile
			await _cross_junction(player_i, nxt, arrival, chosen)
			remaining -= 1   # the whole crossing counts as a single step
		else:
			var landed: String = await _advance_one(player_i)
			remaining -= 1
			if landed != "":   # reached a city (junctions are handled above)
				_came_route[player_i] = _route_of[player_i]
				info_label.text = "%s reached %s" % [GameState.players[player_i].player_name, _dest_label(landed)]
				_passed[player_i].clear()
				if remaining > 0 and await _ask_stop(player_i, landed):
					break
	_set_idle(player_i)
	# Movement is over. Resolve whatever the token ended on: a road space, or a
	# city node. Keep _moving true so Roll/End Turn stay locked until the event
	# window is dismissed.
	if _at_node(player_i):
		var node: String = _current_node(player_i)
		if _is_city(node):
			await _resolve_city(player_i, node)
	else:
		await _resolve_space(player_i)
	_moving = false

# ---------------- Space events ----------------

# Index into map.spaces for the space `player_i` is sitting on, or -1 if the
# token is on a city/junction node instead of a space.
func _space_global_index(player_i: int) -> int:
	var r: int = _route_of[player_i]
	var i: int = _index_of[player_i]
	var segs: int = _stops[r].size() - 1
	if i <= 0 or i >= segs:
		return -1
	if r >= _route_space_start.size():
		return -1
	return _route_space_start[r] + (i - 1)

# Announce the landed space to the rest of the game and (for humans) pop the
# "you landed on..." window naming the tile.
func _resolve_space(player_i: int) -> void:
	var gi: int = _space_global_index(player_i)
	if gi < 0 or gi >= map.space_types.size():
		return
	var type: StringName = map.space_types[gi]
	# SpaceResolver (autoloaded) listens for this and dispatches by type.
	EventBus.emit_signal("space_landed", player_i, type)
	if String(type).begins_with("PKMN"):
		await _start_encounter(player_i, type)
	else:
		# EVENT / ITEM / COMPETITION → TileController runs the window.
		EventBus.emit_signal("tile_action", player_i, type)
		await EventBus.tile_resolved

# PKMN tile: flash a 1-second message, then hand off to the encounter flow and
# wait for it to finish (catch resolved / battle done) before the turn can end.
func _start_encounter(player_i: int, type: StringName) -> void:
	var stage: int = 2 if type == &"PKMN_RED" else 1
	var spirit: Dictionary = SpiritsData.random_spirit(stage)
	if spirit.is_empty():
		return
	if not GameState.players[player_i].is_cpu:
		var who: String = GameState.players[player_i].player_name
		await _show_flash("%s — a wild %s appeared!" % [who, spirit.get("name", "?")], 1.0)
	EventBus.emit_signal("wild_encounter_started", player_i, spirit)
	await EventBus.encounter_finished

# A message that shows for `secs` seconds then dismisses itself (no button).
func _show_flash(text: String, secs: float) -> void:
	event_title.text = ""
	event_body.text = text
	_fit_event_font()
	event_ok.hide()
	event_panel.show()
	await get_tree().create_timer(secs).timeout
	event_panel.hide()
	event_ok.show()

# Shrink the body font (36 down to 16) until the message fits the panel
# width, so long names never overflow the window.
func _fit_event_font() -> void:
	var f: Font = event_body.get_theme_font("font")
	var max_w: float = event_panel.size.x - 56.0
	var size: int = 36
	while size > 16 and f.get_string_size(event_body.text, HORIZONTAL_ALIGNMENT_CENTER, -1, size).x > max_w:
		size -= 2
	event_body.add_theme_font_size_override("font_size", size)

# Stopping on a city: hand off to TileController (gym / shop / Elite Four).
func _resolve_city(player_i: int, city: String) -> void:
	EventBus.emit_signal("space_landed", player_i, &"CITY")
	EventBus.emit_signal("tile_action", player_i, StringName(city))
	await EventBus.tile_resolved

func _show_event(title: String, body: String) -> void:
	event_title.text = title
	event_body.text = body
	_fit_event_font()
	event_panel.show()
	await _event_closed
	event_panel.hide()

func _advance_one(player_i: int) -> String:
	var r: int = _route_of[player_i]
	var stop_list: Array = _stops[r]
	var segs: int = stop_list.size() - 1
	var from_i: int = _index_of[player_i]
	var to_i: int = clampi(from_i + _heading_of[player_i], 0, segs)
	_index_of[player_i] = to_i
	var off: Vector2 = _offset_for(player_i)   # the mover is the active player -> centred
	if segs > 0 and to_i != from_i:
		# Tween between the two stops' real arc-lengths and read the position off
		# the polyline — that hugs the corners and lands on the drawn tiles even
		# though tiles aren't evenly spaced.
		var poly: Array = _poly[r]
		var d_from: float = _stop_dist[r][from_i]
		var d_to: float = _stop_dist[r][to_i]
		var tw := create_tween()
		tw.tween_method(_place_token.bind(player_i, poly, off), d_from, d_to, STEP_TIME)
		await tw.finished
	if to_i == 0:
		return _routes[r]["from"]
	elif to_i == stop_list.size() - 1:
		return _routes[r]["to"]
	return ""

# Tween callback: drop the token at arc-length `d` along the polyline and turn it
# to face the way it's actually moving (so it follows the bends, too).
func _place_token(d: float, player_i: int, poly: Array, off: Vector2) -> void:
	var spr: AnimatedSprite2D = _tokens[player_i]
	var prev: Vector2 = spr.position - off
	var p: Vector2 = _point_on_polyline(poly, d)
	_token_base[player_i] = p   # remember the tile spot so turn changes can re-seat it
	spr.position = p + off
	var move: Vector2 = p - prev
	if move.length() > 0.01:
		_face_token(player_i, move)

func _point_on_polyline(pts: Array, dist: float) -> Vector2:
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

# Arc-length of point `p` (which sits on the polyline) measured from its start.
func _arc_length_of(poly: Array, p: Vector2) -> float:
	var best_d: float = INF
	var best_len: float = 0.0
	var acc: float = 0.0
	for i in range(poly.size() - 1):
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[i + 1]
		var ab: Vector2 = b - a
		var seg_len: float = ab.length()
		if seg_len > 0.0:
			var t: float = clampf((p - a).dot(ab) / (seg_len * seg_len), 0.0, 1.0)
			var d: float = p.distance_to(a + ab * t)
			if d < best_d:
				best_d = d
				best_len = acc + t * seg_len
		acc += seg_len
	return best_len

# Pick the walk animation + flip from the movement direction, and keep it playing.
func _face_token(player_i: int, move: Vector2) -> void:
	var spr: AnimatedSprite2D = _tokens[player_i]
	var anim: String
	var flip := false
	if absf(move.x) >= absf(move.y):
		anim = "side"
		flip = move.x > 0.0   # sheet faces left, so flip when heading right
	elif move.y > 0.0:
		anim = "down"
	else:
		anim = "up"
	spr.flip_h = flip
	if spr.animation != anim or not spr.is_playing():
		spr.play(anim)

func _set_idle(player_i: int) -> void:
	var spr: AnimatedSprite2D = _tokens[player_i]
	spr.stop()
	spr.frame = 0   # standing pose, keeps the last facing/flip

# The node one stop ahead (junction or city), or "" if the next stop is a space.
func _peek_next_node(player_i: int) -> String:
	var r: int = _route_of[player_i]
	var segs: int = _stops[r].size() - 1
	var to_i: int = clampi(_index_of[player_i] + _heading_of[player_i], 0, segs)
	if to_i == 0:
		return _routes[r]["from"]
	elif to_i == segs:
		return _routes[r]["to"]
	return ""

# Glide arrival-road -> junction -> first tile of the chosen road, in one go.
# The direction was already picked, so there's no pause sitting on the junction.
func _cross_junction(player_i: int, junction: String, arrival: int, chosen: int) -> void:
	await _advance_one(player_i)               # step onto the (invisible) junction
	_came_route[player_i] = arrival
	_passed[player_i][junction] = true
	_mount_route(player_i, chosen, junction)
	await _advance_one(player_i)               # step onto the chosen road's first tile

# Leaving a city: pick a road and face down it. Returns false on a dead end.
func _choose_direction(player_i: int, node_name: String) -> bool:
	var chosen: int = await _pick_route(player_i, node_name, _came_route[player_i])
	if chosen == -1:
		return false
	_mount_route(player_i, chosen, node_name)
	return true

# Choose which road to take out of `node_name` (excluding the one we came in on
# and any that loops back to a node we already passed). Prompts a human at a real
# fork; auto-picks for a CPU or a single option. Returns the route index or -1.
func _pick_route(player_i: int, node_name: String, came: int) -> int:
	var opts: Array = []
	for raw in _node_routes.get(node_name, []):
		var ri: int = raw
		if ri == came:
			continue
		var route: Dictionary = _routes[ri]
		var other: String = route["to"] if route["from"] == node_name else route["from"]
		if _passed[player_i].has(other):
			continue
		opts.append(ri)
	if opts.is_empty():
		return -1
	if opts.size() == 1 or GameState.players[player_i].is_cpu:
		return opts[0]
	var labels: Array = []
	for raw2 in opts:
		var ri2: int = raw2
		var route2: Dictionary = _routes[ri2]
		# a road can carry its own name (parallel roads do, so they stay
		# distinct); otherwise label it by where it leads.
		var name: String
		if route2.has("name_of"):
			name = _dest_label(route2["name_of"])
		else:
			var dest: String = route2["to"] if route2["from"] == node_name else route2["from"]
			name = _dest_label(dest)
		# Arrow points the way this road physically leaves the node, so the sign
		# matches what the player sees on the map.
		labels.append(name + " " + _route_arrow(ri2, node_name))
	_disambiguate(labels)
	_set_idle(player_i)   # stop the walk cycle while the player decides
	var title := "Which way?   (%d move%s left)" % [_moves_left, "" if _moves_left == 1 else "s"]
	var pick: int = await _show_choice(title, labels)
	return opts[pick]

# Face the token down `route` from `node_name` (sets its current route/heading).
func _mount_route(player_i: int, route: int, node_name: String) -> void:
	_route_of[player_i] = route
	if _routes[route]["from"] == node_name:
		_index_of[player_i] = 0
		_heading_of[player_i] = 1
	else:
		_index_of[player_i] = _stops[route].size() - 1
		_heading_of[player_i] = -1

func _ask_stop(player_i: int, city: String) -> bool:
	if GameState.players[player_i].is_cpu:
		return false
	_set_idle(player_i)   # stop the walk cycle while the player decides
	var pick: int = await _show_choice("Stop at %s?" % _dest_label(city), ["Stop here", "Keep going"])
	return pick == 0

func _route_arrow(ri: int, node_name: String) -> String:
	# Direction this road heads as it leaves `node_name`: node -> first point
	# along the route's drawn polyline (the next corner, or the far node).
	var poly: Array = _poly[ri]
	var here: Vector2 = _node_pos[node_name]
	var next: Vector2
	if _routes[ri]["from"] == node_name:
		next = poly[1]
	else:
		next = poly[poly.size() - 2]
	return _dir_arrow(next - here)

func _dir_arrow(v: Vector2) -> String:
	# Nearest of 8 compass arrows for a screen-space vector (x right, y down).
	if v == Vector2.ZERO:
		return "→"
	var a: float = rad_to_deg(atan2(v.y, v.x))   # 0=E, 90=S(down), -90=N(up), 180=W
	if a < 0.0:
		a += 360.0
	var arrows: Array = ["→", "↘", "↓", "↙", "←", "↖", "↑", "↗"]
	return arrows[int(round(a / 45.0)) % 8]

func _disambiguate(labels: Array) -> void:
	# Append a number to any duplicate labels (e.g. two roads to the same place).
	for i in labels.size():
		var lab: String = labels[i]
		var dup: bool = false
		for j in labels.size():
			if j != i and String(labels[j]) == lab:
				dup = true
		if dup:
			labels[i] = lab + " #" + str(i + 1)

# ---------------- Choice UI ----------------

func _show_choice(title: String, labels: Array) -> int:
	choice_title.text = title
	for c in choice_buttons.get_children():
		choice_buttons.remove_child(c)
		c.queue_free()
	for i in labels.size():
		var b := Button.new()
		b.text = String(labels[i])
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 44)
		b.pressed.connect(_on_choice_button.bind(i))
		choice_buttons.add_child(b)
	choice_panel.show()
	var idx: int = await _choice_selected
	choice_panel.hide()
	return idx

func _on_choice_button(i: int) -> void:
	_choice_selected.emit(i)
