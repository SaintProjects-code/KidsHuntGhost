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
var _visited: Array = []           # Dictionary set of cities each player reached
var _cpu_bias: Array = []          # per player: personal weights for sp/item/badge/pts
var _moving: bool = false
var _moves_left: int = 0           # steps left this roll, for the choice prompt
var _follow: Node2D = null         # token the camera is currently following (null = free)

func _ready() -> void:
	MusicManager.play_map()
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
	EventBus.dev_tile_requested.connect(_on_dev_tile_requested)
	EventBus.victory_road_entered.connect(_on_victory_road)
	EventBus.victory_road_failed.connect(_on_victory_road_failed)
	_build_fly_button()
	TurnSystem.cpu_turn_override = _cpu_pre_roll   # CPUs may fly instead of rolling
	_add_yellow_border_label(info_label)
	_add_yellow_border_button(roll_button)
	TurnSystem.start_game()

# Frame the top turn/roll message in the game's gold so it stands out.
func _add_yellow_border_label(lbl: Label) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.106, 0.086, 0.196, 0.92)
	sb.border_width_left = 3
	sb.border_width_top = 3
	sb.border_width_right = 3
	sb.border_width_bottom = 3
	sb.border_color = Color("ffd24d")
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	lbl.add_theme_stylebox_override("normal", sb)

# Add a gold border to the Roll button while keeping the theme's look.
func _add_yellow_border_button(btn: Button) -> void:
	for st in ["normal", "hover", "pressed", "disabled"]:
		var base: StyleBox = btn.get_theme_stylebox(st)
		var nb: StyleBox = base.duplicate() if base != null else StyleBoxFlat.new()
		if nb is StyleBoxFlat:
			var f: StyleBoxFlat = nb
			f.border_width_left = 3
			f.border_width_top = 3
			f.border_width_right = 3
			f.border_width_bottom = 3
			f.border_color = Color("ffd24d")
		btn.add_theme_stylebox_override(st, nb)

# DEV: run a tile/city effect on the current player as if they'd landed on it.
func _on_dev_tile_requested(kind: StringName) -> void:
	if _moving:
		return
	var cur: int = GameState.current_player_index
	var type: StringName = kind
	if String(kind) == "CITY":
		type = _random_city()
	_moving = true
	await _apply_tile(cur, type)
	await _check_whiteout(cur)
	_moving = false

func _random_city() -> StringName:
	if _cities.is_empty():
		return &"A"
	return StringName(_cities[randi() % _cities.size()])

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

# Camera: follow whoever's turn it is. Manual panning (arrows / WASD) only
# works in View Map mode (the MAP button) — see PauseMenu — so stray key
# presses during events (e.g. jump keys in a comp minigame) can't drag the map.
func _process(delta: float) -> void:
	if _follow != null and is_instance_valid(_follow):
		# smoothly chase the active player's token
		var t: float = clampf(FOLLOW_LERP * delta, 0.0, 1.0)
		camera.global_position = camera.global_position.lerp(_follow.global_position, t)

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
	var trainers: Array = ["red", "blue"]
	for i in 2:
		var p := PlayerData.new()
		p.player_name = "Player %d" % (i + 1)
		p.trainer_key = trainers[i]
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
		_visited.append({START_NODE: true})   # cities this player has reached
		# every CPU gets its own personality: how much it cares about catching
		# spirits, grabbing items, chasing badges and scoring points
		_cpu_bias.append({
			"sp": randf_range(0.6, 1.5), "item": randf_range(0.6, 1.5),
			"badge": randf_range(0.6, 1.5), "pts": randf_range(0.6, 1.5),
		})
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
	# ✈ Fly shows at the START of a human turn with 3+ badges, until they roll
	fly_button.visible = not GameState.players[idx].is_cpu \
		and GameState.players[idx].progress.badge_count() >= 3
	# point the camera at whoever's turn it is
	if idx < _tokens.size():
		_follow = _tokens[idx]
	# active token jumps on top of its tile; the others slide to their corners
	_reposition_tokens()
	# traits are temporary — count one turn off every trait this player carries
	_tick_traits(idx)
	# starting a turn while resting in a city fully heals the team; otherwise a
	# CPU uses its healing items on hurt/fainted spirits before it rolls
	if _at_city(idx):
		_heal_team_at_city(idx, _current_node(idx))
	elif GameState.players[idx].is_cpu:
		_cpu_use_items(idx)

# Age this player's traits by one turn; anything that runs out wears off.
func _tick_traits(player_i: int) -> void:
	var p: PlayerData = GameState.players[player_i]
	var worn: Array = []
	for m in p.team + p.pc:
		for nm in EventsData.tick_traits(m):
			worn.append("%s's ✦%s" % [m.get("name", "?"), nm])
	if not worn.is_empty():
		EventBus.log_entry.emit(player_i, "Traits wore off: %s" % ", ".join(worn), "#9fdcff")

# CPU turn-start: spend Revives on fainted spirits and Potions on the most-hurt
# living ones (below half HP). At most one of each stack per turn.
func _cpu_use_items(player_i: int) -> void:
	var p: PlayerData = GameState.players[player_i]
	var used: Array = []
	for entry in p.inventory.items.duplicate():
		match String(entry.get("kind", "")):
			"revive":
				for m in p.team:
					if int(m.get("current_hp", 0)) <= 0:
						m["current_hp"] = int(m.get("hp", 0) / 2)
						p.inventory.consume_item(entry)
						used.append("revived %s" % m.get("name", "?"))
						break
			"potion":
				var target: Dictionary = {}
				var worst := 0.5
				for m in p.team:
					var hp: int = int(m.get("current_hp", 0))
					var mx: int = maxi(1, int(m.get("hp", 1)))
					if hp > 0 and float(hp) / float(mx) < worst:
						worst = float(hp) / float(mx)
						target = m
				if not target.is_empty():
					target["current_hp"] = mini(int(target.get("hp", 0)),
						int(target.get("current_hp", 0)) + int(entry.get("amount", 40)))
					p.inventory.consume_item(entry)
					used.append("healed %s" % target.get("name", "?"))
	if not used.is_empty():
		EventBus.log_entry.emit(player_i, "%s uses items: %s" % [
			p.player_name, ", ".join(used)], "#9fdcff")

# Fully restore a player's team; logged as a city rest.
func _heal_team_at_city(player_i: int, city: String) -> void:
	var p: PlayerData = GameState.players[player_i]
	var hurt := false
	for m in p.team:
		if int(m.get("current_hp", 0)) < int(m.get("hp", 0)):
			hurt = true
		m["current_hp"] = m.get("hp", 0)
	if hurt:
		EventBus.log_entry.emit(player_i, "%s's team rests at %s — fully healed!" % [
			p.player_name, _dest_label(city)], "#9fff9f")

func _on_roll_pressed() -> void:
	if _moving:
		return
	fly_button.hide()   # rolling forfeits the fly for this turn
	roll_button.disabled = true
	TurnSystem.roll_dice()

# ─── ✈ Fly (3+ badges): jump to any city instead of rolling ──────────────────

var fly_button: Button

func _build_fly_button() -> void:
	fly_button = Button.new()
	fly_button.text = "✈ Fly"
	fly_button.focus_mode = Control.FOCUS_NONE
	fly_button.custom_minimum_size = Vector2(110, 84)
	fly_button.pressed.connect(_on_fly_pressed)
	fly_button.hide()
	var bar := roll_button.get_parent()
	bar.add_child(fly_button)
	bar.move_child(fly_button, roll_button.get_index())

func _on_fly_pressed() -> void:
	if _moving:
		return
	var idx: int = GameState.current_player_index
	var labels: Array = []
	var cities: Array = map.CITIES.duplicate()
	for c in cities:
		labels.append(_dest_label(c))
	labels.append("✖ Cancel")
	var pick: int = await _show_choice("Fly where?", labels)
	if pick >= cities.size():
		return   # cancelled — the fly is still available
	fly_button.hide()
	roll_button.disabled = true
	_moving = true
	var city: String = cities[pick]
	info_label.text = "%s flies to %s!" % [GameState.players[idx].player_name, _dest_label(city)]
	_teleport_to_city(idx, city)
	await _resolve_city(idx, city)   # heals + opens the city like a landing
	await _check_whiteout(idx)
	_moving = false
	end_turn_button.disabled = false

# CPU pre-roll hook (called by TurnSystem): with 3+ badges it may fly to an
# unbeaten gym it's ready for. Returns true if it flew (the move is used).
func _cpu_pre_roll(idx: int) -> bool:
	var p: PlayerData = GameState.players[idx]
	if GameState.winner_index != -1:
		return false
	if p.progress.badge_count() < 3 or p.team.size() < 4 or _moving:
		return false
	var route: Dictionary = _routes[_route_of[idx]]
	if route["from"] == "VEnter" or route["to"] == "VEnter":
		return false   # already climbing Victory Road
	if not GameData.cpu_will_gym(p):
		return false   # losing streak → don't fly to a gym; walk and train instead
	var target := ""
	for c in map.CITIES:
		if c == START_NODE:
			continue   # home has no gym to challenge
		var gym: Dictionary = GameData.gym_for_city(c)
		if not p.progress.badges.get(gym.get("badge", ""), false):
			target = c
			break
	if target == "" and p.team_ready_for_victory():
		target = map.CITIES[randi() % map.CITIES.size()]   # any city → Victory Road
	if target == "" or (_at_node(idx) and _current_node(idx) == target):
		return false
	_moving = true
	info_label.text = "%s flies to %s!" % [p.player_name, _dest_label(target)]
	_teleport_to_city(idx, target)
	await _resolve_city(idx, target)
	await _check_whiteout(idx)
	_moving = false
	await get_tree().create_timer(CPU_END_TURN_DELAY).timeout
	TurnSystem.advance_turn()
	return true

# City chose "Victory Road" (3+ badges): teleport there; the turn then ends.
func _on_victory_road(player_i: int) -> void:
	_teleport_victory(player_i)
	info_label.text = "%s travels to Victory Road!" % GameState.players[player_i].player_name

# Lost an Elite fight on Victory Road: retreat to Cobweb City and heal up.
func _on_victory_road_failed(player_i: int) -> void:
	_teleport_to_city(player_i, "C")
	_heal_team_at_city(player_i, "C")

# Drop the player's token on Victory Road's FIRST space (the Item tile next
# to the entrance), facing the peak. They roll from there next turn.
func _teleport_victory(player_i: int) -> void:
	for r in _routes.size():
		if _routes[r]["from"] == "VEnter":
			_route_of[player_i] = r
			_index_of[player_i] = 1          # stop 0 is the VEnter node itself
			_heading_of[player_i] = 1
			_came_route[player_i] = -1
			_passed[player_i].clear()
			_token_base[player_i] = _stops[r][1]
			_reposition_tokens()
			camera.position = _token_base[player_i]
			return

# Teleport a token to a city node (whiteout rescue).
func _teleport_to_city(player_i: int, city: String) -> void:
	var routes: Array = _node_routes.get(city, [])
	if routes.is_empty():
		return
	_mount_route(player_i, routes[0], city)
	_came_route[player_i] = -1
	_passed[player_i].clear()
	_mark_visited(player_i, city)
	_token_base[player_i] = _node_pos[city]
	_reposition_tokens()
	camera.position = _node_pos[city]

# All spirits fainted → the team is rushed to Cobweb City (C) and healed —
# or back to the start if that player has never reached C.
func _check_whiteout(player_i: int) -> void:
	var p: PlayerData = GameState.players[player_i]
	if p.team.is_empty():
		return
	for m in p.team:
		if int(m.get("current_hp", 0)) > 0:
			return
	for m in p.team:
		m["current_hp"] = m.get("hp", 0)
	var target: String = "C" if _visited[player_i].has("C") else START_NODE
	_teleport_to_city(player_i, target)
	EventBus.log_entry.emit(player_i, "%s's team was wiped out — rushed to %s and healed!" % [
		p.player_name, _dest_label(target)], "#ff9f9f")
	if not p.is_cpu:
		await _show_flash("%s's team fainted! Back to %s…" % [p.player_name, _dest_label(target)], 1.4)

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
			if remaining > 0:
				await _check_pvp_pass(player_i)   # ⚔ walking past a rival?
		else:
			var landed: String = await _advance_one(player_i)
			remaining -= 1
			if remaining > 0:
				await _check_pvp_pass(player_i)   # ⚔ walking past a rival?
			if landed != "":   # reached a city (junctions are handled above)
				_came_route[player_i] = _route_of[player_i]
				_mark_visited(player_i, landed)
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
			_mark_visited(player_i, node)
			await _resolve_city(player_i, node)
	else:
		await _resolve_space(player_i)
	# landing on another ⚔-tagged player forces a PvP battle
	await _check_pvp_land(player_i)
	# a lost battle / nasty event may have downed the whole team
	await _check_whiteout(player_i)
	_moving = false

# Record a visited city; reaching Cobweb City (C) awards the ⚔ PvP tag.
func _mark_visited(player_i: int, node: String) -> void:
	_visited[player_i][node] = true
	if node == "C" and not GameState.players[player_i].pvp_tag:
		GameState.players[player_i].pvp_tag = true
		EventBus.log_entry.emit(player_i, "%s earned the ⚔ PvP tag at Cobweb City!" % [
			GameState.players[player_i].player_name], "#ffd24d")

# All OTHER players standing on this player's tile.
func _others_here(player_i: int) -> Array:
	var here: Vector2 = _token_base[player_i]
	var out: Array = []
	for j in GameState.players.size():
		if j != player_i and j < _token_base.size() and _token_base[j].distance_to(here) < 4.0:
			out.append(j)
	return out

# Cities are safe zones — no PvP while a token stands on one.
func _at_city(player_i: int) -> bool:
	return _at_node(player_i) and _is_city(_current_node(player_i))

# Victory Road is its own PvP-free zone (the Elite gauntlet, no player clashes).
func _on_victory_road_route(player_i: int) -> bool:
	var route: Dictionary = _routes[_route_of[player_i]]
	return route["from"] == "VEnter" or route["to"] == "VEnter"

# PvP is blocked in cities AND on Victory Road.
func _pvp_safe(player_i: int) -> bool:
	return _at_city(player_i) or _on_victory_road_route(player_i)

# Mid-move: a ⚔-tagged HUMAN walking onto another tagged player's tile may
# Battle / Trade / Skip. (CPUs always skip for now; trade needs two humans.)
func _check_pvp_pass(player_i: int) -> void:
	var p: PlayerData = GameState.players[player_i]
	if p.is_cpu or not p.pvp_tag or GameState.winner_index != -1 or _pvp_safe(player_i):
		return
	for j in _others_here(player_i):
		var q: PlayerData = GameState.players[j]
		if not q.pvp_tag:
			continue
		var opts: Array = ["⚔ Battle %s" % q.player_name]
		var modes: Array = ["battle"]
		if not q.is_cpu:
			opts.append("🔁 Trade with %s" % q.player_name)
			modes.append("trade")
		opts.append("👋 Skip")
		modes.append("skip")
		_set_idle(player_i)
		var pick: int = await _show_choice("You pass %s!" % q.player_name, opts)
		var mode: String = modes[pick]
		if mode == "skip":
			continue
		EventBus.pvp_started.emit(player_i, j, mode)
		await EventBus.pvp_finished
		return   # one clash per step is plenty

# Landing ON another ⚔-tagged player (both tagged) forces a battle — both
# sides must pick spirits and fight (CPUs auto-pick).
func _check_pvp_land(player_i: int) -> void:
	var p: PlayerData = GameState.players[player_i]
	if not p.pvp_tag or GameState.winner_index != -1 or _pvp_safe(player_i):
		return   # cities and Victory Road are safe zones
	for j in _others_here(player_i):
		if GameState.players[j].pvp_tag:
			await _show_flash("%s and %s clash — PvP battle!" % [
				p.player_name, GameState.players[j].player_name], 1.2)
			EventBus.pvp_started.emit(player_i, j, "battle")
			await EventBus.pvp_finished
			return

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
	await _apply_tile(player_i, map.space_types[gi])

# Run a tile type's effect for a player (used by real landings AND the dev tools).
func _apply_tile(player_i: int, type: StringName) -> void:
	# SpaceResolver (autoloaded) listens for this and dispatches by type.
	EventBus.emit_signal("space_landed", player_i, type)
	if String(type).begins_with("PKMN"):
		await _start_encounter(player_i, type)
	else:
		# EVENT / ITEM / COMPETITION / a city key → TileController runs the window.
		EventBus.emit_signal("tile_action", player_i, type)
		await EventBus.tile_resolved

# PKMN tile: flash a 1-second message, then hand off to the encounter flow and
# wait for it to finish (catch resolved / battle done) before the turn can end.
func _start_encounter(player_i: int, type: StringName) -> void:
	# RED tiles hold STANDALONE basics (no evolution); PINK / GREEN hold basics
	# that can still grow into a stage 2/3.
	var spirit: Dictionary = SpiritsData.random_basic(type != &"PKMN_RED")
	if spirit.is_empty():
		return
	# announce for EVERYONE — CPU encounters play out on screen too
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
	# Landing in town rests the whole team back to full HP.
	_heal_team_at_city(player_i, city)
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
		# A true dead end (e.g. Victory Peak): turning around is the only way —
		# without this the token would be stranded facing the wall forever.
		if came != -1 and _node_routes.get(node_name, []).has(came):
			opts.append(came)
		else:
			return -1
	if opts.size() == 1:
		return opts[0]
	if GameState.players[player_i].is_cpu:
		return _cpu_pick_route(player_i, node_name, opts)
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

# ─── CPU route choice ─────────────────────────────────────────────────────────
# Each CPU scores every road out of a fork by what's ON it (SP / Item / Event /
# Comp tiles) and where it LEADS (a town with an unbeaten gym), weighted by its
# current needs (team size, balls, items, points gap) and its personal bias —
# then picks by roulette on the scores, so different CPUs (and different runs)
# take different routes.
func _cpu_pick_route(player_i: int, node_name: String, opts: Array) -> int:
	var p: PlayerData = GameState.players[player_i]
	var bias: Dictionary = _cpu_bias[player_i]
	# needs from the CPU's current state
	var need_sp: float = maxf(0.2, (6.0 - float(p.team.size())) / 3.0) \
		* (1.5 if p.inventory.total_balls() > 0 else 0.4)   # no balls → SP tiles are risky
	var need_item: float = 1.5 if p.inventory.items.is_empty() else 0.6
	if p.inventory.ball_count(&"spirit_ball") == 0:
		need_item += 0.8
	var need_badge: float = 2.0 if p.team.size() >= 4 else 0.3
	var need_pts: float = 0.5 + 0.05 * maxf(0.0, float(_best_points() - p.progress.points))
	# Momentum weight: losing (negative) pulls toward wild SP fights to train and
	# away from gyms; winning (positive) does the opposite — chase gyms harder
	# (and, through the badges they earn, the Elite Four).
	var m: int = clampi(p.cpu_momentum, -6, 6)
	var down: float = float(maxi(0, -m))   # losing streak
	var up: float = float(maxi(0, m))      # winning streak
	need_sp *= (1.0 + 0.35 * down) / (1.0 + 0.25 * up)
	need_badge *= (1.0 + 0.4 * up) / (1.0 + 0.6 * down)
	var scores: Array = []
	var total := 0.0
	for raw in opts:
		var ri: int = raw
		var s := 1.0   # base chance so no road is ever impossible (and stays random)
		for t in _routes[ri].get("types", []):
			var ts := String(t)
			if ts.begins_with("PKMN"):
				s += need_sp * float(bias["sp"])
			elif ts == "ITEM":
				s += need_item * float(bias["item"])
			elif ts == "EVENT":
				s += 0.5 * need_pts * float(bias["pts"])   # events: mixed rewards
			elif ts == "COMPETITION":
				s += need_pts * float(bias["pts"])
		var dest: String = _routes[ri]["to"] if _routes[ri]["from"] == node_name else _routes[ri]["from"]
		if _is_city(dest):
			s += 0.5   # towns heal and restock
			var gym: Dictionary = GameData.gym_for_city(dest)
			if dest != START_NODE and not gym.is_empty() \
					and not p.progress.badges.get(gym.get("badge", ""), false):
				s += 3.0 * need_badge * float(bias["badge"])
		# ±55% random swing per road, so CPUs wander and take varied routes
		# instead of always chasing the single best-scoring option.
		s *= randf_range(0.45, 1.55)
		scores.append(s)
		total += s
	var roll := randf() * total
	for i in scores.size():
		roll -= scores[i]
		if roll <= 0.0:
			return opts[i]
	return opts[opts.size() - 1]

# The current points leader (CPUs chase comps harder when they're behind).
func _best_points() -> int:
	var best := 0
	for pl in GameState.players:
		best = maxi(best, pl.progress.points)
	return best

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
	var p: PlayerData = GameState.players[player_i]
	if p.is_cpu:
		# The CPU stops when town is useful: an unbeaten gym it's ready for
		# (4+ spirits), Victory Road prep (3 badges + full team), or restock.
		var gym: Dictionary = GameData.gym_for_city(city)
		var wants_gym: bool = city != START_NODE \
			and not p.progress.badges.get(gym.get("badge", ""), false) \
			and p.team.size() >= 4 and GameData.cpu_will_gym(p)
		var wants_vr: bool = p.progress.badge_count() >= 3 and p.team_ready_for_victory() \
			and GameData.cpu_will_gym(p)
		var needs_shop: bool = p.inventory.ball_count(&"spirit_ball") == 0 \
			and p.inventory.gold >= 10
		return wants_gym or wants_vr or needs_shop
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
