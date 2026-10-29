extends Node2D
## Gameplay scene: holds the map + UI and runs turns. Tokens move along the
## BoardGraph built from Map1. Players pick a direction at forks, can't
## reverse into a junction they've already passed, and are asked whether to
## stop each time they reach a town.
##
## Keyboard: Space/Enter rolls or ends the turn; 1–9 pick a choice button.

const PLAYER_SHEET := "res://Assets/Player/Male_Spritesheet.png"
const FRAME_SIZE := Vector2i(16, 32)  # sheet: 3 walk frames × 3 facings
const ROWS := {"down": 0, "up": 1, "side": 2}   # side is drawn facing left
const WALK_COLS := [1, 0, 1, 2]       # column 1 is the standing pose
const WALK_FPS := 8.0
const TOKEN_SCALE := 2.4
# Corners for the players whose turn it ISN'T, so shared tiles fan out.
const TOKEN_OFFSETS := [Vector2(-29, -8), Vector2(29, -8), Vector2(-29, 18), Vector2(29, 18)]
const ACTIVE_TOKEN_DROP := Vector2(0, 10)
const STEP_TIME := 0.28
const CPU_END_TURN_DELAY := 0.7
const START_NODE := "A"
const RESCUE_NODE := "C"              # whiteouts and lost trail fights end up here
const FOLLOW_LERP := 6.0

@onready var map = _load_map()
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

var graph: BoardGraph
var hud: Control
var fly_button: Button

# per-player token state
var _tokens: Array = []        # AnimatedSprite2D
var _token_base: Array = []    # tile position, before the side offset
var _route_of: Array = []      # current route index
var _index_of: Array = []      # current stop index in that route
var _heading_of: Array = []    # +1 / -1 along the route's stop list
var _came_route: Array = []    # route arrived on (-1 = none)
var _passed: Array = []        # Dictionary set of passed junctions
var _visited: Array = []       # Dictionary set of towns reached
var _cpu_bias: Array = []
var _moving := false
var _jumping := false          # a fly / warp town visit is in progress
var _moves_left := 0
var _follow: Node2D = null

func _ready() -> void:
	MusicManager.play_map()
	choice_panel.hide()
	event_panel.hide()
	event_ok.pressed.connect(func(): event_panel.hide())
	graph = BoardGraph.new(map)
	camera.position = graph.node_pos.get(START_NODE, Vector2.ZERO)
	if GameState.players.is_empty():
		_make_dummies()
	_spawn_tokens()
	_spawn_hud()
	choice_panel.move_to_front()   # popups above the HUD
	event_panel.move_to_front()
	EventBus.turn_started.connect(_on_turn_started)
	EventBus.dice_rolled.connect(_on_dice_rolled)
	EventBus.dev_tile_requested.connect(_on_dev_tile_requested)
	EventBus.trail_entered.connect(_teleport_trail)
	EventBus.trail_failed.connect(_on_trail_failed)
	EventBus.warp_requested.connect(_on_warp_requested)
	_build_fly_button()
	TurnSystem.cpu_turn_override = _cpu_pre_roll
	info_label.add_theme_stylebox_override("normal", UIKit.box(Color(UIKit.NIGHT, 0.92), 8, 3, UIKit.GOLD, Vector2(12, 6)))
	_style_board_buttons()
	SaveManager.board_state_provider = _save_state
	var saved := SaveManager.take_pending_board_state()
	if saved.is_empty():
		_deal_starting_cards()
		TurnSystem.start_game()
	else:
		_load_state(saved)
		TurnSystem.resume_game()

func _exit_tree() -> void:
	SaveManager.board_state_provider = Callable()
	TurnSystem.stop()

# The board chrome uses the same themed buttons as every window: one height
# for the whole action bar, gold for the main action.
func _style_board_buttons() -> void:
	var bar := roll_button.get_parent()
	var specs := [
		[roll_button, "🎲 Roll", "gold", 128], [end_turn_button, "End Turn", "primary", 128],
		[bar.get_node("TeamButton"), "👥 Team", "secondary", 100], [bar.get_node("MapButton"), "🗺 Map", "secondary", 90],
	]
	for sp in specs:
		var b: Button = sp[0]
		b.text = sp[1]
		b.clip_text = false
		b.custom_minimum_size = Vector2(sp[3], 54)
		UIKit.style_button(b, sp[2], "l")
	var util := $BoardUI/Root/UtilRow
	for pair in [["LogButton", "📜 Log"], ["DevButton", "⚡ Dev"]]:
		var b: Button = util.get_node(pair[0])
		b.text = pair[1]
		b.clip_text = false
		b.custom_minimum_size = Vector2(84, 34)
		UIKit.style_button(b, "secondary", "s")
	var settings: Button = $TopUI/SettingsButton
	settings.text = "⚙ Settings"
	UIKit.style_button(settings, "secondary", "s")
	UIKit.style_button(event_ok, "primary", "m")

# The board picked in setup (Map1 is in the scene; the others swap in).
func _load_map() -> Node2D:
	var base: Node2D = $Map1
	var info: Dictionary = GameData.map_info(GameState.active_map)
	if info["scene"] == base.scene_file_path:
		return base
	var m: Node2D = load(info["scene"]).instantiate()
	add_child(m)
	move_child(m, base.get_index())
	remove_child(base)
	base.queue_free()
	return m

func _deal_starting_cards() -> void:
	# some boards start everyone with a few spirits (3v3 from turn one)
	var start_team: int = int(GameData.map_info(GameState.active_map).get("start_team", 1))
	for p in GameState.players:
		while p.team.size() < start_team:
			p.team.append(SpiritsData.random_spirit(1))
	for i in GameState.players.size():
		var hand: Array = GameState.players[i].inventory.hand
		if hand.is_empty():
			for n in Balance.START_LANTERNS:
				hand.append("spirit_lantern")
			hand.append(CardsData.random_card("tactic"))
			for n in Balance.START_CARDS - 1:
				hand.append(CardsData.random_card("field"))
			EventBus.hand_changed.emit(i)

# The HUD, the encounter flow and the tile flow live in their own scripts.
func _spawn_hud() -> void:
	hud = preload("res://Scenes/Board/BoardHUD.gd").new()
	hud.name = "HUD"
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.process_mode = Node.PROCESS_MODE_PAUSABLE   # its timer stops while paused
	$BoardUI/Root.add_child(hud)
	hud.board = self
	var enc: CanvasLayer = preload("res://Scenes/UI/EncounterController.gd").new()
	add_child(enc)
	var tiles: CanvasLayer = preload("res://Scenes/UI/TileController.gd").new()
	add_child(tiles)
	add_child(preload("res://Scenes/Board/CpuPace.gd").new())   # CPU turns play at 2x

# Camera follows whoever's turn it is (manual panning lives in View Map mode).
func _process(delta: float) -> void:
	if _follow != null and is_instance_valid(_follow):
		camera.global_position = camera.global_position.lerp(_follow.global_position, clampf(FOLLOW_LERP * delta, 0.0, 1.0))

# ---------------- players & tokens ----------------

func _make_dummies() -> void:
	for t in [["Ember", "Cinderwisp", Color("ff7a3a")], ["Brooke", "Puddleboo", Color("4aa3df")]]:
		var p := PlayerData.new()
		p.player_name = t[0]
		p.color = t[2]
		p.team.append(SpiritsData.get_spirit(t[1]))
		GameState.players.append(p)

func _build_token_frames() -> SpriteFrames:
	var sheet: Texture2D = load(PLAYER_SHEET)
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	for anim in ROWS:
		sf.add_animation(anim)
		sf.set_animation_loop(anim, true)
		sf.set_animation_speed(anim, WALK_FPS)
		for col in WALK_COLS:
			var tex := AtlasTexture.new()
			tex.atlas = sheet
			tex.region = Rect2(col * FRAME_SIZE.x, ROWS[anim] * FRAME_SIZE.y, FRAME_SIZE.x, FRAME_SIZE.y)
			sf.add_frame(anim, tex)
	return sf

func _spawn_tokens() -> void:
	var frames := _build_token_frames()
	var start_routes: Array = graph.node_routes.get(START_NODE, [0])
	for i in GameState.players.size():
		var spr := AnimatedSprite2D.new()
		spr.sprite_frames = frames
		spr.animation = "down"
		spr.frame = 0
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.modulate = GameState.players[i].color
		spr.scale = Vector2(TOKEN_SCALE, TOKEN_SCALE)
		spr.offset = Vector2(0, -FRAME_SIZE.y * 0.5 + 4)   # feet on the path point
		map.add_child(spr)
		_tokens.append(spr)
		_route_of.append(0)
		_index_of.append(0)
		_heading_of.append(1)
		_came_route.append(-1)
		_passed.append({})
		_visited.append({START_NODE: true})
		_cpu_bias.append(CpuBrain.new_bias())
		_token_base.append(graph.node_pos[START_NODE])
		_mount_route(i, start_routes[0], START_NODE)
	_reposition_tokens()

func _offset_for(i: int) -> Vector2:
	return ACTIVE_TOKEN_DROP if i == GameState.current_player_index else TOKEN_OFFSETS[i % TOKEN_OFFSETS.size()]

func _reposition_tokens() -> void:
	for i in _tokens.size():
		_tokens[i].position = _token_base[i] + _offset_for(i)

# ---------------- save / load ----------------

func _save_state() -> Dictionary:
	return {
		"route": _route_of.duplicate(), "index": _index_of.duplicate(), "heading": _heading_of.duplicate(),
		"came": _came_route.duplicate(), "passed": _passed.duplicate(true), "visited": _visited.duplicate(true),
		"base": _token_base.duplicate(), "bias": _cpu_bias.duplicate(true), "time": hud.elapsed,
	}

func _load_state(s: Dictionary) -> void:
	for key in ["route", "index", "heading", "came", "passed", "visited", "base", "bias"]:
		if s.get(key, []).size() != _tokens.size():
			push_warning("Board: save doesn't match the player count — starting positions kept")
			return
	_route_of = s["route"]
	_index_of = s["index"]
	_heading_of = s["heading"]
	_came_route = s["came"]
	_passed = s["passed"]
	_visited = s["visited"]
	_token_base = s["base"]
	_cpu_bias = s["bias"]
	hud.elapsed = float(s.get("time", 0.0))
	_reposition_tokens()
	camera.position = _token_base[GameState.current_player_index]

# ---------------- turns ----------------

func _on_turn_started(idx: int) -> void:
	var p: PlayerData = GameState.players[idx]
	info_label.text = "%s's turn — roll!" % p.player_name
	roll_button.disabled = p.is_cpu
	end_turn_button.disabled = true   # can't end a turn before moving
	fly_button.visible = not p.is_cpu and p.progress.badge_count() >= Balance.FLY_BADGES
	if idx < _tokens.size():
		_follow = _tokens[idx]
	_reposition_tokens()
	_tick_traits(idx)
	if _at_city(idx):
		_heal_team_at_city(idx, _current_node(idx))

func _tick_traits(i: int) -> void:
	var p: PlayerData = GameState.players[i]
	var worn: Array = []
	for m in p.team + p.pc:
		for nm in EventsData.tick_traits(m):
			worn.append("%s's ✦%s" % [m.get("name", "?"), nm])
	if not worn.is_empty():
		EventBus.log_entry.emit(i, "Traits wore off: %s" % ", ".join(worn), "#9fdcff")

func _heal_team_at_city(i: int, city: String) -> void:
	var p: PlayerData = GameState.players[i]
	var hurt := false
	for m in p.team:
		if int(m.get("current_hp", 0)) < int(m.get("hp", 0)):
			hurt = true
		m["current_hp"] = m.get("hp", 0)
	if hurt:
		EventBus.log_entry.emit(i, "%s's team rests at %s — fully healed!" % [p.player_name, graph.label(city)], "#9fff9f")

func can_act_on_board(i: int) -> bool:
	return i == GameState.current_player_index and not _moving and not GameState.players[i].is_cpu

func before_roll(i: int) -> bool:
	return can_act_on_board(i) and not roll_button.disabled

func _on_roll_pressed() -> void:
	if _moving or roll_button.disabled:
		return
	fly_button.hide()   # rolling forfeits the fly for this turn
	roll_button.disabled = true
	TurnSystem.roll_dice()

func _on_end_turn_pressed() -> void:
	if _moving or end_turn_button.disabled:
		return
	end_turn_button.disabled = true
	Sfx.play("click")
	TurnSystem.advance_turn()

func _unhandled_key_input(ev: InputEvent) -> void:
	if UIManager.is_open() or UIManager.overlay_open() or get_tree().paused:
		return
	if choice_panel.visible:
		var n := Controls.number_pressed(ev)
		if n >= 0 and n < choice_buttons.get_child_count():
			get_viewport().set_input_as_handled()
			_choice_selected.emit(n)
		return
	if Controls.confirm_pressed(ev):
		get_viewport().set_input_as_handled()
		if not roll_button.disabled:
			_on_roll_pressed()
		elif not end_turn_button.disabled:
			_on_end_turn_pressed()

func _on_dice_rolled(total: int, faces: Array) -> void:
	var idx: int = GameState.current_player_index
	var p: PlayerData = GameState.players[idx]
	_moving = true
	var bonus := total
	for f in faces:
		bonus -= int(f)
	await hud.show_roll(faces, bonus, p.color)
	info_label.text = "%s rolled %d" % [p.player_name, total]
	await _move_player(idx, total)
	if p.is_cpu:
		await get_tree().create_timer(CPU_END_TURN_DELAY).timeout
		TurnSystem.advance_turn()
	else:
		info_label.text = "%s — play cards or press End Turn" % p.player_name
		end_turn_button.disabled = false

# ─── ✈ Fly (3+ badges) and the Warp Door: jump to a town instead of rolling ──

func _build_fly_button() -> void:
	fly_button = Button.new()
	fly_button.text = "✈ Fly"
	fly_button.custom_minimum_size = Vector2(96, 54)
	UIKit.style_button(fly_button, "gold", "l")
	fly_button.pressed.connect(_on_fly_pressed)
	fly_button.hide()
	var bar := roll_button.get_parent()
	bar.add_child(fly_button)
	bar.move_child(fly_button, roll_button.get_index())

func _on_fly_pressed() -> void:
	if _moving:
		return
	var city := await pick_town("Fly where?", graph.cities)
	if city != "":
		await _jump_to_town(GameState.current_player_index, city, "flies")

# Town picker shared by Fly and the Warp Door. Returns "" on cancel.
func pick_town(title: String, towns: Array) -> String:
	var labels: Array = towns.map(func(c): return graph.label(c))
	labels.append("✖ Cancel")
	var pick: int = await _show_choice(title, labels)
	return towns[pick] if pick < towns.size() else ""

func visited_towns(i: int) -> Array:
	return graph.cities.filter(func(c): return _visited[i].has(c))

func _on_warp_requested(i: int, city: String) -> void:
	await _jump_to_town(i, city, "warps")

# Teleport to a town and visit it like a landing; uses up the move.
func _jump_to_town(i: int, city: String, verb: String) -> void:
	fly_button.hide()
	roll_button.disabled = true
	_moving = true
	_jumping = true
	info_label.text = "%s %s to %s!" % [GameState.players[i].player_name, verb, graph.label(city)]
	Sfx.play("whoosh")
	_teleport_to_city(i, city)
	await _resolve_city(i, city)
	await _check_whiteout(i)
	_moving = false
	_jumping = false
	if not GameState.players[i].is_cpu:
		end_turn_button.disabled = false

# CPU pre-roll hook (TurnSystem): play field cards, maybe warp or fly to a
# useful town. Returns true if it moved (the turn is then over).
func _cpu_pre_roll(idx: int) -> bool:
	var p: PlayerData = GameState.players[idx]
	if GameState.winner_index != -1 or _moving:
		return false
	var here := _current_node(idx) if _at_node(idx) else ""
	var warp_to := CpuBrain.wanted_town(p, graph.cities, _visited[idx], here, true)
	# a played Warp Door starts the town visit itself (warp_requested)
	var warped := await CardSystem.cpu_field_turn(idx, warp_to if not _on_trail(idx) else "")
	if warped != "":
		await get_tree().process_frame
		while _jumping:
			await get_tree().process_frame
	elif p.progress.badge_count() >= Balance.FLY_BADGES and not _on_trail(idx):
		var fly_to := CpuBrain.wanted_town(p, graph.cities, _visited[idx], here, false)
		if fly_to == "":
			return false
		await _jump_to_town(idx, fly_to, "flies")
	else:
		return false
	await get_tree().create_timer(CPU_END_TURN_DELAY).timeout
	TurnSystem.advance_turn()
	return true

func _on_trail_failed(i: int) -> void:
	_teleport_to_city(i, RESCUE_NODE)
	_heal_team_at_city(i, RESCUE_NODE)

func _teleport_trail(i: int) -> void:
	for r in graph.routes.size():
		if graph.routes[r]["from"] == "VEnter":
			_route_of[i] = r
			_index_of[i] = 1          # stop 0 is the entrance node itself
			_heading_of[i] = 1
			_came_route[i] = -1
			_passed[i].clear()
			_token_base[i] = graph.stops[r][1]
			_reposition_tokens()
			camera.position = _token_base[i]
			info_label.text = "%s sets out on the Spectral Trail!" % GameState.players[i].player_name
			return

func _teleport_to_city(i: int, city: String) -> void:
	var routes: Array = graph.node_routes.get(city, [])
	if routes.is_empty():
		return
	_mount_route(i, routes[0], city)
	_came_route[i] = -1
	_passed[i].clear()
	_mark_visited(i, city)
	_token_base[i] = graph.node_pos[city]
	_reposition_tokens()
	camera.position = _token_base[i]

# All spirits fainted → rushed to Cobweb City (or home if never reached) and healed.
func _check_whiteout(i: int) -> void:
	var p: PlayerData = GameState.players[i]
	if p.team.is_empty() or not p.living_team().is_empty():
		return
	for m in p.team:
		m["current_hp"] = m.get("hp", 0)
	var target: String = RESCUE_NODE if _visited[i].has(RESCUE_NODE) else START_NODE
	_teleport_to_city(i, target)
	EventBus.log_entry.emit(i, "%s's team was wiped out — rushed to %s and healed!" % [p.player_name, graph.label(target)], "#ff9f9f")
	if not p.is_cpu:
		await _show_flash("%s's team fainted! Back to %s…" % [p.player_name, graph.label(target)], 1.4)

# ---------------- movement ----------------

func _at_node(i: int) -> bool:
	return _index_of[i] == 0 or _index_of[i] == graph.stops[_route_of[i]].size() - 1

func _current_node(i: int) -> String:
	var route: Dictionary = graph.routes[_route_of[i]]
	return route["from"] if _index_of[i] == 0 else route["to"]

func _at_city(i: int) -> bool:
	return _at_node(i) and graph.is_city(_current_node(i))

func _on_trail(i: int) -> bool:
	var route: Dictionary = graph.routes[_route_of[i]]
	return route["from"] == "VEnter" or route["to"] == "VEnter"

func _move_player(i: int, steps: int) -> void:
	_moving = true
	var remaining := steps
	while remaining > 0:
		_moves_left = remaining
		# leaving a town (the only node we rest on): pick a road first
		if _at_node(i) and not await _choose_direction(i, _current_node(i)):
			break
		# junctions are chosen while still on a real tile, then crossed in one go
		var nxt := _peek_next_node(i)
		if nxt != "" and not graph.is_city(nxt):
			var arrival: int = _route_of[i]
			var chosen: int = await _pick_route(i, nxt, arrival)
			if chosen == -1:
				break
			await _cross_junction(i, nxt, arrival, chosen)
			remaining -= 1
			if remaining > 0:
				await _check_pvp_pass(i)
		else:
			var landed := await _advance_one(i)
			remaining -= 1
			if remaining > 0:
				await _check_pvp_pass(i)
			if landed != "":
				_came_route[i] = _route_of[i]
				_mark_visited(i, landed)
				_passed[i].clear()
				info_label.text = "%s reached %s" % [GameState.players[i].player_name, graph.label(landed)]
				if remaining > 0 and await _ask_stop(i, landed):
					break
	_set_idle(i)
	# resolve whatever the token ended on (Roll/End Turn stay locked meanwhile)
	if _at_node(i):
		if graph.is_city(_current_node(i)):
			await _resolve_city(i, _current_node(i))
	else:
		await _resolve_space(i)
	await _check_pvp_land(i)
	await _check_whiteout(i)
	_moving = false

# Reaching Cobweb City (C) awards the ⚔ PvP tag.
func _mark_visited(i: int, node: String) -> void:
	_visited[i][node] = true
	var p: PlayerData = GameState.players[i]
	if node == RESCUE_NODE and not p.pvp_tag:
		p.pvp_tag = true
		EventBus.log_entry.emit(i, "%s earned the ⚔ PvP tag at Cobweb City!" % p.player_name, "#ffd24d")

func _advance_one(i: int) -> String:
	var r: int = _route_of[i]
	var segs: int = graph.stops[r].size() - 1
	var from_i: int = _index_of[i]
	var to_i: int = clampi(from_i + _heading_of[i], 0, segs)
	_index_of[i] = to_i
	if to_i != from_i:
		var tw := create_tween()
		tw.tween_method(_place_token.bind(i, graph.poly[r], _offset_for(i)),
			graph.stop_dist[r][from_i], graph.stop_dist[r][to_i], STEP_TIME)
		await tw.finished
		Sfx.play("step", randf_range(0.9, 1.1))
	if to_i == 0:
		return graph.routes[r]["from"]
	if to_i == segs:
		return graph.routes[r]["to"]
	return ""

# Tween callback: put the token at arc-length `d` and face the way it moves.
func _place_token(d: float, i: int, pts: Array, off: Vector2) -> void:
	var spr: AnimatedSprite2D = _tokens[i]
	var prev: Vector2 = spr.position - off
	var p := BoardGraph.point_on_polyline(pts, d)
	_token_base[i] = p
	spr.position = p + off
	var move := p - prev
	if move.length() <= 0.01:
		return
	var anim := "side" if absf(move.x) >= absf(move.y) else ("down" if move.y > 0.0 else "up")
	spr.flip_h = anim == "side" and move.x > 0.0   # sheet faces left
	if spr.animation != anim or not spr.is_playing():
		spr.play(anim)

func _set_idle(i: int) -> void:
	_tokens[i].stop()
	_tokens[i].frame = 0

# The node one stop ahead, or "" if the next stop is a space.
func _peek_next_node(i: int) -> String:
	var r: int = _route_of[i]
	var segs: int = graph.stops[r].size() - 1
	var to_i: int = clampi(_index_of[i] + _heading_of[i], 0, segs)
	if to_i == 0:
		return graph.routes[r]["from"]
	if to_i == segs:
		return graph.routes[r]["to"]
	return ""

# Arrival road → junction → first tile of the chosen road, without a pause.
func _cross_junction(i: int, junction: String, arrival: int, chosen: int) -> void:
	await _advance_one(i)
	_came_route[i] = arrival
	_passed[i][junction] = true
	_mount_route(i, chosen, junction)
	await _advance_one(i)

func _choose_direction(i: int, node_name: String) -> bool:
	var chosen: int = await _pick_route(i, node_name, _came_route[i])
	if chosen == -1:
		return false
	_mount_route(i, chosen, node_name)
	return true

# Roads out of `node_name` (not the one we came in on, nor back to a passed
# junction). Prompts a human at a real fork. Returns a route index or -1.
func _pick_route(i: int, node_name: String, came: int) -> int:
	var opts: Array = graph.node_routes.get(node_name, []).filter(func(ri):
		return ri != came and not _passed[i].has(graph.other_end(ri, node_name)))
	if opts.is_empty():
		# a true dead end (the Spectral Peak): turning around is the only way
		if came != -1 and graph.node_routes.get(node_name, []).has(came):
			opts.append(came)
		else:
			return -1
	if opts.size() == 1:
		return opts[0]
	if GameState.players[i].is_cpu:
		return CpuBrain.pick_route(graph, GameState.players[i], _cpu_bias[i], node_name, opts, _best_points())
	var labels: Array = opts.map(func(ri): return graph.route_label(ri, node_name))
	for k in labels.size():   # two roads to the same place get numbered
		if labels.count(labels[k]) > 1:
			labels[k] += " #%d" % (k + 1)
	_set_idle(i)
	var pick: int = await _show_choice("Which way?   (%d move%s left)" % [_moves_left, "" if _moves_left == 1 else "s"], labels)
	return opts[pick]

func _best_points() -> int:
	var best := 0
	for pl in GameState.players:
		best = maxi(best, pl.progress.points)
	return best

func _mount_route(i: int, route: int, node_name: String) -> void:
	_route_of[i] = route
	if graph.routes[route]["from"] == node_name:
		_index_of[i] = 0
		_heading_of[i] = 1
	else:
		_index_of[i] = graph.stops[route].size() - 1
		_heading_of[i] = -1

func _ask_stop(i: int, city: String) -> bool:
	var p: PlayerData = GameState.players[i]
	if p.is_cpu:
		return CpuBrain.wants_stop(p, city)
	_set_idle(i)
	return await _show_choice("Stop at %s?" % graph.label(city), ["Stop here", "Keep going"]) == 0

# ---------------- ⚔ PvP ----------------

func _others_here(i: int) -> Array:
	var out: Array = []
	for j in GameState.players.size():
		if j != i and _token_base[j].distance_to(_token_base[i]) < 4.0:
			out.append(j)
	return out

# Towns and the Spectral Trail are safe zones.
func _pvp_safe(i: int) -> bool:
	return _at_city(i) or _on_trail(i)

# Mid-move: a ⚔-tagged human walking past another tagged player may battle,
# trade, or skip.
func _check_pvp_pass(i: int) -> void:
	var p: PlayerData = GameState.players[i]
	if p.is_cpu or not p.pvp_tag or GameState.winner_index != -1 or _pvp_safe(i):
		return
	for j in _others_here(i):
		var q: PlayerData = GameState.players[j]
		if not q.pvp_tag:
			continue
		_set_idle(i)
		var modes := ["battle", "trade", "skip"]
		var pick: int = await _show_choice("You pass %s!" % q.player_name,
			["⚔ Battle %s" % q.player_name, "🔁 Trade with %s" % q.player_name, "👋 Skip"])
		if modes[pick] == "skip":
			continue
		EventBus.pvp_started.emit(i, j, modes[pick])
		await EventBus.pvp_finished
		return   # one clash per step is plenty

# Landing ON another ⚔-tagged player forces a battle.
func _check_pvp_land(i: int) -> void:
	if not GameState.players[i].pvp_tag or GameState.winner_index != -1 or _pvp_safe(i):
		return
	for j in _others_here(i):
		if GameState.players[j].pvp_tag:
			await _show_flash("%s and %s clash — PvP battle!" % [GameState.players[i].player_name, GameState.players[j].player_name], 1.2)
			EventBus.pvp_started.emit(i, j, "battle")
			await EventBus.pvp_finished
			return

# ⚔ CLASH tile: challenge any player who isn't on the Spectral Trail (no tag
# needed). Humans pick a rival (or pass); CPUs go for the points leader. With
# no rival around, you draw a card instead.
func _run_clash(i: int) -> void:
	var p: PlayerData = GameState.players[i]
	if p.living_team().is_empty():
		return
	var rivals: Array = []
	for j in GameState.players.size():
		if j != i and not _on_trail(j) and not GameState.players[j].living_team().is_empty():
			rivals.append(j)
	if rivals.is_empty():
		await _show_flash("⚔ No rivals to challenge — you find a card instead!", 1.2)
		await CardSystem.give_random(i)
		return
	var j: int
	if p.is_cpu:
		rivals.sort_custom(func(a, b): return GameState.players[a].progress.points > GameState.players[b].progress.points)
		j = rivals[0]
	else:
		_set_idle(i)
		var labels: Array = rivals.map(func(k): return "⚔ %s  (%d pts)" % [GameState.players[k].player_name,
			GameState.players[k].progress.points])
		labels.append("👋 Pass")
		var pick: int = await _show_choice("⚔ Clash! Win: +%d pts, +%d gold, 1 of their cards" % [
			Balance.PTS_PVP_WIN, Balance.GOLD_PVP_TAKE], labels)
		if pick >= rivals.size():
			return
		j = rivals[pick]
	await _show_flash("%s challenges %s — PvP battle!" % [p.player_name, GameState.players[j].player_name], 1.2)
	EventBus.pvp_started.emit(i, j, "battle")
	await EventBus.pvp_finished

# ---------------- tiles ----------------

func _resolve_space(i: int) -> void:
	var type := graph.space_type(_route_of[i], _index_of[i])
	if type != &"":
		await _apply_tile(i, type)

# Run a tile's effect for a player (real landings AND the dev tools).
func _apply_tile(i: int, type: StringName) -> void:
	var p: PlayerData = GameState.players[i]
	EventBus.space_landed.emit(i, type)
	if p.salt and (map.GHOST_TILES.has(type) or type == &"EVENT"):
		p.salt = false
		await _show_flash("🧂 The salt circle keeps it away!", 1.0)
		return
	if map.GHOST_TILES.has(type):
		await _start_encounter(i, type)
	elif type == &"CLASH":
		await _run_clash(i)
	else:
		EventBus.tile_action.emit(i, type)
		await EventBus.tile_resolved

# Ghost tile: announce the spirit, then wait for the encounter flow.
func _start_encounter(i: int, type: StringName) -> void:
	var p: PlayerData = GameState.players[i]
	var stage: int = map.roll_stage(type)
	if p.lure:
		stage = mini(3, stage + 1)
	var spirit: Dictionary = SpiritsData.random_spirit(stage)
	if spirit.is_empty():
		return
	if p.lure:
		p.lure = false
		spirit["_lured"] = true
	Sfx.play("boo", 1.3)
	await _show_flash("%s — a wild %s appeared!" % [p.player_name, spirit.get("name", "?")], 1.0)
	EventBus.wild_encounter_started.emit(i, spirit)
	await EventBus.encounter_finished

# Stopping in a town: rest, then the town menu (gym / shop / box / trail).
func _resolve_city(i: int, city: String) -> void:
	_mark_visited(i, city)
	_heal_team_at_city(i, city)
	if city == START_NODE:
		return   # home is just a rest stop
	EventBus.space_landed.emit(i, &"CITY")
	EventBus.tile_action.emit(i, StringName(city))
	await EventBus.tile_resolved

# DEV: run a tile/town effect on the current player as if they'd landed there.
func _on_dev_tile_requested(kind: StringName) -> void:
	if _moving:
		return
	var cur: int = GameState.current_player_index
	_moving = true
	if String(kind) == "CITY":
		await _resolve_city(cur, graph.cities.slice(1).pick_random())
	else:
		await _apply_tile(cur, kind)
	await _check_whiteout(cur)
	_moving = false

# ---------------- popups ----------------

# A message that shows for `secs` seconds then dismisses itself.
func _show_flash(text: String, secs: float) -> void:
	event_title.text = ""
	event_body.text = text
	_fit_event_font()
	event_ok.hide()
	event_panel.show()
	Juice.pop(event_panel, 1.06)
	await get_tree().create_timer(secs).timeout
	event_panel.hide()
	event_ok.show()

# Shrink the body font (36 → 16) until the message fits the panel width.
func _fit_event_font() -> void:
	var f: Font = event_body.get_theme_font("font")
	var max_w: float = event_panel.size.x - 56.0
	var size := 36
	while size > 16 and f.get_string_size(event_body.text, HORIZONTAL_ALIGNMENT_CENTER, -1, size).x > max_w:
		size -= 2
	event_body.add_theme_font_size_override("font_size", size)

func _show_choice(title: String, labels: Array) -> int:
	choice_title.text = title
	UIKit.clear(choice_buttons)
	for i in labels.size():
		var b := Button.new()
		b.text = "%d · %s" % [i + 1, labels[i]] if labels.size() > 1 else String(labels[i])
		UIKit.style_button(b, UIKit.kind_for(String(labels[i])), "m")
		b.pressed.connect(func(): _choice_selected.emit(i))
		choice_buttons.add_child(b)
	choice_panel.show()
	Juice.pop(choice_panel, 1.04)
	var idx: int = await _choice_selected
	Sfx.play("click")
	choice_panel.hide()
	return idx
