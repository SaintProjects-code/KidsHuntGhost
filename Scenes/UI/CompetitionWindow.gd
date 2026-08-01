extends MenuWindow
## Competition tile, in three steps:
##   1) Selection — every player picks ONE of their spirits to enter (all six
##      shown as small circular icons; CPUs auto-pick their strongest).
##   2) The comp event — 🌳 Tree Jump! Every entrant runs in its own lane and
##      must hop over the map's trees. DEF + HP act as WEIGHT (heavy spirits
##      fall faster), the game speeds up over time, last one standing wins.
##   3) Rewards — podium window with the top-3 spirits and their points.
## present(triggering_player_index); emits closed().
## resolve_cpu(idx) resolves the whole comp silently on CPU turns (stat contest).

signal closed()

const EVENTS := [
	{"key": "spd",     "name": "🎽 Sprint Race",      "stat": "spd",     "label": "Speed"},
	{"key": "atk",     "name": "💪 Strength Contest", "stat": "atk",     "label": "Attack"},
	{"key": "def",     "name": "🛡 Toughness Test",   "stat": "def",     "label": "Defense"},
	{"key": "hp_stat", "name": "🌟 Endurance Show",   "stat": "hp_stat", "label": "HP Tier"},
]
const TREE_JUMP := {"key": "tree_jump", "name": "🌳 Tree Jump"}
const MAZE := {"key": "maze", "name": "🌀 Dark Maze"}
# Dev override: an event "key" forces that comp event; "" = random (default).
static var dev_forced_event := ""

# Tree Jump all-time record (winner's survival seconds). Beating it = +2 pts.
const RECORD_PATH := "user://tree_jump_record.save"
const RECORD_BONUS := 2
var _record_broken := false
var _new_record := 0.0
const PODIUM_POINTS := [3, 2, 1]
const MEDALS := ["🥇", "🥈", "🥉"]

var _title: Label
var _body: VBoxContainer
var _next: Button

var _phase := 0       # 1 = selection, 2 = event, 3 = podium
var _event_pick := {}
var _picks := {}      # player_idx -> entered spirit Dictionary
var _chips := {}      # player_idx -> Array of SpiritChip
var _results: Array = []   # [{idx, spirit, stat, roll, score}] best-first

func _ready() -> void:
	var col := _init_window(640, 0)
	_title = _title_label("🏅 Competition!", 26)
	col.add_child(_title)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 8)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_body)
	_next = _button("Start the Comp!", _on_next)
	col.add_child(_next)
	hide()

func present(_player_index: int) -> void:
	_phase = 1
	_picks.clear()
	_results.clear()
	_record_broken = false
	_event_pick = _choose_event()
	_build_selection()

# Dev-forced event if set, otherwise random (a minigame or a stat contest).
func _choose_event() -> Dictionary:
	if dev_forced_event == TREE_JUMP["key"]:
		return TREE_JUMP
	if dev_forced_event == MAZE["key"]:
		return MAZE
	for e in EVENTS:
		if e["key"] == dev_forced_event:
			return e
	var all: Array = EVENTS.duplicate()
	all.append(TREE_JUMP)
	all.append(MAZE)
	return all.pick_random()

# All-CPU game: nobody can press Start / Awards / OK, so the window drives
# itself — every player is a CPU, so picks are pre-locked, and the minigames'
# CPU entrants already play on their own.
func run_cpu_auto() -> void:
	while visible and _phase < 3:
		await get_tree().create_timer(1.2).timeout
		if not visible:
			return
		if not _next.disabled:
			await get_tree().create_timer(0.8).timeout
			if visible and not _next.disabled:
				_on_next()
	# podium: let it sink in, then close
	await get_tree().create_timer(2.5).timeout
	if visible and _phase == 3:
		_on_next()

# CPU turn: everyone auto-enters their strongest spirit, no windows.
# Minigames can't run unattended, so CPU turns always use a stat contest.
func resolve_cpu(_player_index: int) -> void:
	_picks.clear()
	_event_pick = _choose_event()
	if not _event_pick.has("stat"):
		_event_pick = EVENTS.pick_random()
	for i in GameState.players.size():
		var p: PlayerData = GameState.players[i]
		if not p.team.is_empty():
			_picks[i] = p.team[_best_index(p.team)]
	_score_entrants()
	for rank in mini(PODIUM_POINTS.size(), _results.size()):
		GameState.award_points(_results[rank]["idx"], PODIUM_POINTS[rank])

func _on_next() -> void:
	match _phase:
		1:
			match String(_event_pick["key"]):
				"tree_jump": _show_game()
				"maze": _show_maze()
				_: _show_stat_event()
		2: _show_podium()
		3: closed.emit()

func _clear_body() -> void:
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()

# ─── Step 1: every player picks a spirit ──────────────────────────────────────
func _build_selection() -> void:
	# announce WHICH comp it is, so picks can be strategic
	_title.text = "🏅 %s — pick your Spirit!" % _event_pick["name"]
	_next.text = "Start the Comp!"
	_clear_body()
	var hint := Label.new()
	match String(_event_pick["key"]):
		"tree_jump":
			hint.text = "Light spirits jump best — DEF + HP is your WEIGHT!"
		"maze":
			hint.text = "Fast spirits escape quickest — SPD is your walking speed!"
		_:
			hint.text = "Judged on %s ×2, plus stars and a die roll!" % _event_pick["label"]
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 14)
	hint.modulate = Color(1, 1, 1, 0.8)
	_body.add_child(hint)
	# players sit in a 2-column grid — the window grows WIDE instead of tall,
	# so the Start button always stays on screen
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 26)
	grid.add_theme_constant_override("v_separation", 10)
	_body.add_child(grid)
	_chips.clear()
	for i in GameState.players.size():
		var p: PlayerData = GameState.players[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		# Big player-coloured circle with the trainer portrait inside.
		var tchip := TrainerChip.new(
			GameData.trainer_texture(GameData.player_trainer(p.player_name)), p.color)
		row.add_child(tchip)
		var right := VBoxContainer.new()
		right.add_theme_constant_override("separation", 2)
		right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(right)
		var name := Label.new()
		name.text = p.player_name
		name.add_theme_color_override("font_color", p.color)
		right.add_child(name)
		var chips_row := HBoxContainer.new()
		chips_row.add_theme_constant_override("separation", 8)
		right.add_child(chips_row)
		_chips[i] = []
		if p.team.is_empty():
			var none := Label.new()
			none.text = "— no spirits —"
			none.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			chips_row.add_child(none)
		for s in p.team:
			var chip := SpiritChip.new(s)
			chip.picked.connect(_on_chip_picked.bind(i))
			chips_row.add_child(chip)
			_chips[i].append(chip)
		grid.add_child(row)
		if p.is_cpu and not p.team.is_empty():
			_select_chip(i, _chips[i][_best_index(p.team)])
	_update_next()

func _on_chip_picked(chip: SpiritChip, player_idx: int) -> void:
	if GameState.players[player_idx].is_cpu:
		return   # CPU entries are locked in
	_select_chip(player_idx, chip)
	_update_next()

func _select_chip(player_idx: int, chip: SpiritChip) -> void:
	for c in _chips[player_idx]:
		c.set_selected(c == chip)
	_picks[player_idx] = chip.spirit

# Start stays disabled until every player who HAS spirits picked one.
func _update_next() -> void:
	if _phase != 1:
		_next.disabled = false
		return
	for i in GameState.players.size():
		if not GameState.players[i].team.is_empty() and not _picks.has(i):
			_next.disabled = true
			return
	_next.disabled = _picks.is_empty()

# CPU pick: the best spirit FOR THIS EVENT (it's announced, so pick smart) —
# lightest for Tree Jump, fastest for the Maze, highest stat for contests.
func _best_index(team: Array) -> int:
	var best := 0
	var best_v := -999.0
	for i in team.size():
		var s: Dictionary = team[i]
		var v: float
		match String(_event_pick["key"]):
			"tree_jump":
				v = -float(int(s.get("def", 0)) + int(s.get("hp_stat", 0)))
			"maze":
				v = float(s.get("spd", 0))
			_:
				v = float(s.get(_event_pick.get("stat", "atk"), 0)) * 2.0 + float(s.get("stars", 0))
		if v > best_v:
			best_v = v
			best = i
	return best

# ─── Step 2: the comp event (🌳 Tree Jump or a stat contest) ──────────────────
func _score_entrants() -> void:
	_results.clear()
	for i in _picks:
		var s: Dictionary = _picks[i]
		var stat: int = int(s.get(_event_pick["stat"], 0))
		var roll := randi_range(1, 6)
		var score: int = stat * 2 + int(s.get("stars", 0)) + roll
		_results.append({"idx": i, "spirit": s, "stat": stat, "roll": roll, "score": score})
	_results.sort_custom(func(a, b): return a["score"] > b["score"])

# A stat contest: reveal the event, score every entrant, show the standings.
func _show_stat_event() -> void:
	_phase = 2
	_score_entrants()
	_title.text = "%s!" % _event_pick["name"]
	_next.text = "Awards ▶"
	_clear_body()
	var sub := Label.new()
	sub.text = "Judged on %s ×2, plus stars and a die roll!" % _event_pick["label"]
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.add_child(sub)
	for r in _results:
		var p: PlayerData = GameState.players[r["idx"]]
		var l := Label.new()
		l.text = "%s — %s:  %d   (%s %d ×2 + ⭐%d + 🎲%d)" % [
			p.player_name, r["spirit"].get("name", "?"), r["score"],
			_event_pick["label"], r["stat"], int(r["spirit"].get("stars", 0)), r["roll"]]
		_body.add_child(l)
	if _results.is_empty():
		var l := Label.new()
		l.text = "Nobody could enter…"
		_body.add_child(l)

func _show_game() -> void:
	_phase = 2
	_title.text = "🌳 Tree Jump!"
	_next.text = "Awards ▶"
	_next.disabled = true
	_clear_body()
	var sub := Label.new()
	sub.text = "Hop over the trees — tap your lane or press your key! Heavy spirits (DEF + HP) fall faster. Last one standing wins!"
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.add_child(sub)
	var entries: Array = []
	var idxs: Array = _picks.keys()
	idxs.sort()
	for i in idxs:
		var p: PlayerData = GameState.players[i]
		entries.append({
			"idx": i, "spirit": _picks[i], "human": not p.is_cpu,
			"color": p.color, "name": p.player_name,
		})
	var view := TreeJumpView.new(entries, _load_record())
	view.finished.connect(_on_game_finished)
	_body.add_child(view)

# 🌀 Dark Maze: everyone races their own maze at once — SPD sets walking
# speed, Left/Right buttons appear at each crossroad. First out wins.
func _show_maze() -> void:
	_phase = 2
	_title.text = "🌀 Dark Maze!"
	_next.text = "Awards ▶"
	_next.disabled = true
	_clear_body()
	var sub := Label.new()
	sub.text = "Race out of the dark! SPD = walking speed. Each crossroad has 3 paths: ★ way out · spikes = trap (−30 HP) · wall = dead end · arrow = back one fork. First one out wins!"
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 13)
	_body.add_child(sub)
	var entries: Array = []
	var idxs: Array = _picks.keys()
	idxs.sort()
	for i in idxs:
		var p: PlayerData = GameState.players[i]
		entries.append({
			"idx": i, "spirit": _picks[i], "human": not p.is_cpu,
			"color": p.color, "name": p.player_name,
		})
	var view := MazeView.new(entries)
	view.finished.connect(_on_maze_finished)
	_body.add_child(view)

func _on_maze_finished(ranks: Array) -> void:
	_results.clear()
	for i in ranks:
		_results.append({"idx": i, "spirit": _picks[i]})
	_next.disabled = false

func _on_game_finished(ranks: Array, best_time: float) -> void:
	_results.clear()
	for i in ranks:
		_results.append({"idx": i, "spirit": _picks[i]})
	if best_time > _load_record():
		_record_broken = true
		_new_record = best_time
		_save_record(best_time)
	_next.disabled = false

func _load_record() -> float:
	if not FileAccess.file_exists(RECORD_PATH):
		return 0.0
	var f := FileAccess.open(RECORD_PATH, FileAccess.READ)
	return float(f.get_var()) if f else 0.0

func _save_record(value: float) -> void:
	var f := FileAccess.open(RECORD_PATH, FileAccess.WRITE)
	if f:
		f.store_var(value)

# ─── Step 3: rewards (top 3) ──────────────────────────────────────────────────
func _show_podium() -> void:
	_phase = 3
	_title.text = "🏆 Winners!"
	_next.text = "OK"
	_clear_body()
	for rank in mini(PODIUM_POINTS.size(), _results.size()):
		var r: Dictionary = _results[rank]
		var p: PlayerData = GameState.players[r["idx"]]
		var pts: int = PODIUM_POINTS[rank]
		GameState.award_points(r["idx"], pts)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		var medal := Label.new()
		medal.text = MEDALS[rank]
		medal.add_theme_font_size_override("font_size", 30)
		row.add_child(medal)
		var chip := SpiritChip.new(r["spirit"])
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(chip)
		var l := Label.new()
		l.text = "%s's %s   +%d points!" % [p.player_name, r["spirit"].get("name", "?"), pts]
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.add_theme_color_override("font_color", p.color)
		row.add_child(l)
		_body.add_child(row)
	# Tree Jump record bonus: the winner beat the all-time survival record.
	if _record_broken and not _results.is_empty():
		GameState.award_points(_results[0]["idx"], RECORD_BONUS)
		var rec := Label.new()
		rec.text = "🎉 NEW RECORD — %.1fs!  %s gets +%d bonus points!" % [
			_new_record, GameState.players[_results[0]["idx"]].player_name, RECORD_BONUS]
		rec.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rec.add_theme_color_override("font_color", Color("ffd24d"))
		_body.add_child(rec)
	if _results.is_empty():
		var l := Label.new()
		l.text = "No winners this time!"
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_body.add_child(l)

# ─── A spirit as a small clickable circle ─────────────────────────────────────
class SpiritChip:
	extends Control
	signal picked(chip)
	var spirit: Dictionary
	var selected := false
	var _tex: Texture2D

	func _init(s: Dictionary) -> void:
		spirit = s
		custom_minimum_size = Vector2(64, 78)   # circle + a stat line below
		tooltip_text = String(s.get("name", "?"))
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_tex = SpiritsData.sprite_tex(s.get("name", ""), "front")

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			picked.emit(self)

	func set_selected(v: bool) -> void:
		selected = v
		queue_redraw()

	func _draw() -> void:
		# circle sits in the square area above the stat line
		var d := minf(size.x, size.y - 16.0)
		var c := Vector2(size.x * 0.5, d * 0.5)
		var r := d * 0.5 - 2.0
		if selected:
			draw_circle(c, r, Color.WHITE)
		draw_circle(c, r - 3.0, SpiritsData.type_color(spirit.get("type", "")))
		if _tex:
			var side := r * 1.5
			draw_texture_rect(_tex, Rect2(c - Vector2(side, side) * 0.5, Vector2(side, side)), false)
		# A/D/S stats under the circle, so comp picks can be informed
		var font := ThemeDB.fallback_font
		var txt := "A%d D%d S%d" % [int(spirit.get("atk", 0)), int(spirit.get("def", 0)), int(spirit.get("spd", 0))]
		var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		draw_string(font, Vector2((size.x - w) * 0.5, size.y - 4.0), txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.9))

# The player's trainer portrait in a big circle tinted with the player's colour.
class TrainerChip:
	extends Control
	var _tex: Texture2D
	var _color: Color

	func _init(tex: Texture2D, color: Color) -> void:
		_tex = tex
		_color = color
		custom_minimum_size = Vector2(84, 84)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 2.0
		draw_circle(c, r, _color)
		draw_circle(c, r - 4.0, _color.darkened(0.45))
		if _tex:
			var ts := _tex.get_size()
			var s := (r * 1.5) / maxf(ts.x, ts.y)
			var sz := ts * s
			draw_texture_rect(_tex, Rect2(c - sz * 0.5, sz), false)

# ─── 🌳 Tree Jump — the comp minigame ─────────────────────────────────────────
# One lane per entrant (like the sketch): spirit circle on the left, the map's
# trees scroll in from the right, everything speeds up over time. A spirit's
# DEF + HP is its WEIGHT: heavier spirits fall faster (shorter hops).
# Humans jump by tapping/clicking their lane or pressing their key; CPUs have
# an auto-jumper that fumbles more as the speed climbs. The round runs until
# EVERY spirit is out (the last one keeps running for the record). Emits
# finished(ranks, best_time) — player indices winner-first, and the winner's
# survival time (for the all-time record bonus).
class TreeJumpView:
	extends Control

	signal finished(ranks: Array, best_time: float)

	const TREE_TEX := preload("res://Assets/Trees/tree1.png")
	const KEYS := [KEY_A, KEY_F, KEY_J, KEY_L, KEY_Z, KEY_M]
	const KEY_NAMES := ["A", "F", "J", "L", "Z", "M"]
	const ORDINAL := ["1st", "2nd", "3rd", "4th", "5th", "6th"]
	const LANE_H := 92.0
	const VIEW_W := 720.0
	const RUN_X := 84.0        # spirit's fixed x position
	const R := 24.0            # spirit circle radius
	const TREE_H := 34.0
	const START_SPEED := 170.0
	const ACCEL := 9.0         # px/s gained per second
	const MAX_SPEED := 560.0
	const JUMP_V := 330.0
	const BASE_G := 950.0

	var lanes: Array = []
	var speed := START_SPEED
	var t := 0.0
	var countdown := 3.0
	var running := false
	var ended := false
	var record := 0.0            # all-time best survival time (seconds)
	var _end_t := 0.0
	var _emitted := false
	var eliminated: Array = []   # player indices, first out first

	func _init(entries: Array, best: float = 0.0) -> void:
		record = best
		custom_minimum_size = Vector2(VIEW_W, LANE_H * entries.size())
		mouse_filter = Control.MOUSE_FILTER_STOP
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		for e in entries:
			var s: Dictionary = e["spirit"]
			var weight: int = int(s.get("def", 0)) + int(s.get("hp_stat", 0))
			lanes.append({
				"idx": e["idx"], "name": e["name"], "human": e["human"],
				"color": e["color"], "tex": SpiritsData.sprite_tex(s.get("name", ""), "front"),
				"gmult": 1.0 + maxf(0.0, weight - 2.0) * 0.055,   # weight 2→1.0 … 12→1.55
				"y": 0.0, "vy": 0.0, "air": false, "alive": true, "out_pos": 0,
				"time": 0.0, "trees": [], "gap": randf_range(320.0, 520.0),
				# per-CPU pilot skill: reaction window + steadiness, rolled per
				# race so every CPU jumps (and crashes) differently
				"react": randf_range(0.26, 0.38),
				"skill": randf_range(0.65, 1.1),
			})

	func _process(delta: float) -> void:
		if _emitted:
			return
		if ended:
			_end_t += delta
			if _end_t > 0.9:
				_emitted = true
				set_process(false)
				finished.emit(_ranks(), _best_time())
			return
		if countdown > 0.0:
			countdown -= delta
			if countdown <= 0.0:
				running = true
			queue_redraw()
			return
		t += delta
		speed = minf(MAX_SPEED, START_SPEED + ACCEL * t)
		for lane in lanes:
			if not lane["alive"]:
				continue
			_step_lane(lane, delta)
		var alive := 0
		for lane in lanes:
			if lane["alive"]:
				alive += 1
		# The round only ends when EVERYBODY is out — the last spirit keeps
		# running to push the record as far as it can.
		if alive == 0:
			ended = true
			running = false
		queue_redraw()

	func _step_lane(lane: Dictionary, delta: float) -> void:
		# Trees scroll left; spawn a new one past the right edge when there's room.
		var trees: Array = lane["trees"]
		for tr in trees:
			tr["x"] -= speed * delta
		while not trees.is_empty() and trees[0]["x"] < -60.0:
			trees.pop_front()
		if trees.is_empty() or trees[-1]["x"] < VIEW_W - lane["gap"]:
			# Sometimes a cluster of 2 or 3 trees side by side — doubles show up
			# after 10s and triples after 25s, once the speed can carry a jump
			# far enough to clear them.
			var w := TREE_H * TREE_TEX.get_size().x / TREE_TEX.get_size().y
			var count := 1
			var roll := randf()
			if t > 25.0 and roll < 0.15:
				count = 3
			elif t > 10.0 and roll < 0.45:
				count = 2
			for n in count:
				# only the first tree of a cluster gets the CPU's fumble roll
				trees.append({"x": VIEW_W + 40.0 + n * w, "seen": n > 0})
			lane["gap"] = randf_range(320.0, 520.0) + count * w
		# Jump physics — heavier spirits pull down harder.
		if lane["air"]:
			lane["vy"] += BASE_G * lane["gmult"] * delta
			lane["y"] += lane["vy"] * delta
			if lane["y"] >= 0.0:
				lane["y"] = 0.0
				lane["vy"] = 0.0
				lane["air"] = false
		# CPU pilot: jump when a tree enters ITS reaction window; fumble odds
		# grow with speed and shrink with the pilot's personal skill.
		if not lane["human"] and not lane["air"]:
			for tr in trees:
				var dist: float = tr["x"] - RUN_X
				if dist > 0.0 and dist < speed * float(lane["react"]):
					if not tr["seen"]:
						tr["seen"] = true
						var fumble := minf(0.55, (0.02 + t * 0.012) * (2.0 - float(lane["skill"])))
						if randf() < fumble:
							tr["skip"] = true   # this one gets fumbled
					if not tr.get("skip", false):
						_jump(lane)
					break
		# Collision: forgiving hitbox, kids' game.
		var tree_w := TREE_H * TREE_TEX.get_size().x / TREE_TEX.get_size().y
		for tr in trees:
			var cx: float = tr["x"] + tree_w * 0.5
			if absf(cx - RUN_X) < tree_w * 0.5 + R * 0.55 and lane["y"] > -(TREE_H - 12.0):
				lane["alive"] = false
				lane["time"] = t
				eliminated.append(lane["idx"])
				lane["out_pos"] = lanes.size() - eliminated.size() + 1
				break

	func _jump(lane: Dictionary) -> void:
		if running and lane["alive"] and not lane["air"]:
			lane["vy"] = -JUMP_V
			lane["air"] = true

	# Winner first: any survivor (safety), then the fallen in reverse order —
	# the last one out is the winner.
	func _ranks() -> Array:
		var out: Array = []
		for lane in lanes:
			if lane["alive"]:
				out.append(lane["idx"])
		for i in range(eliminated.size() - 1, -1, -1):
			out.append(eliminated[i])
		return out

	# The winner's survival time — the longest anyone lasted.
	func _best_time() -> float:
		var best := 0.0
		for lane in lanes:
			best = maxf(best, t if lane["alive"] else float(lane["time"]))
		return best

	# Tap/click (or touch) a lane to jump — every player gets a "button".
	func _gui_input(ev: InputEvent) -> void:
		var pos := Vector2.ZERO
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			pos = ev.position
		elif ev is InputEventScreenTouch and ev.pressed:
			pos = ev.position
		else:
			return
		var i := int(pos.y / LANE_H)
		if i >= 0 and i < lanes.size() and lanes[i]["human"]:
			_jump(lanes[i])

	func _unhandled_key_input(ev: InputEvent) -> void:
		if ev is InputEventKey and ev.pressed and not ev.echo:
			for i in lanes.size():
				if lanes[i]["human"] and i < KEYS.size() and ev.keycode == KEYS[i]:
					_jump(lanes[i])

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var tree_sz := TREE_TEX.get_size()
		var tree_w := TREE_H * tree_sz.x / tree_sz.y
		for i in lanes.size():
			var lane: Dictionary = lanes[i]
			var top := i * LANE_H
			var ground := top + LANE_H - 10.0
			# Lane strip + ground line (grass-green when alive, grey when out).
			var bg := Color(0.10, 0.20, 0.12, 0.55) if lane["alive"] else Color(0.16, 0.10, 0.10, 0.6)
			draw_rect(Rect2(0, top + 2, size.x, LANE_H - 4), bg)
			draw_line(Vector2(0, ground), Vector2(size.x, ground),
				Color(0.35, 0.65, 0.35) if lane["alive"] else Color(0.4, 0.3, 0.3), 2.0)
			# Trees (the map's tree sprite).
			for tr in lane["trees"]:
				draw_texture_rect(TREE_TEX,
					Rect2(tr["x"], ground - TREE_H, tree_w, TREE_H), false,
					Color.WHITE if lane["alive"] else Color(1, 1, 1, 0.4))
			# The spirit: player-coloured ring, type-coloured fill, sprite on top.
			var c := Vector2(RUN_X, ground - R + lane["y"])
			var tint := Color.WHITE if lane["alive"] else Color(1, 1, 1, 0.35)
			draw_circle(c, R + 3.0, lane["color"] * tint)
			draw_circle(c, R, Color(0.12, 0.12, 0.2) * tint)
			if lane["tex"]:
				var side := R * 1.6
				draw_texture_rect(lane["tex"], Rect2(c - Vector2(side, side) * 0.5, Vector2(side, side)), false, tint)
			# Lane label: name + jump key (or CPU), or final placing when out.
			var label: String = lane["name"]
			if not lane["alive"]:
				label += "  ✗ OUT — %s (%.1fs)" % [
					ORDINAL[clampi(lane["out_pos"] - 1, 0, ORDINAL.size() - 1)], float(lane["time"])]
			elif lane["human"]:
				label += "  [%s]" % KEY_NAMES[i]
			else:
				label += "  (CPU)"
			draw_string(font, Vector2(10, top + 20), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, lane["color"])
		# Countdown / finish banner.
		if countdown > 0.0:
			var n := int(ceil(countdown))
			_banner(font, "%d…" % n if n > 1 else "GO!")
		elif ended:
			var ranks := _ranks()
			if not ranks.is_empty():
				_banner(font, "🏁 %s wins — %.1fs!" % [_lane_name(ranks[0]), _best_time()])
				if _best_time() > record:
					_banner(font, "🎉 NEW RECORD! (+2 pts)", 40.0)
		elif running:
			var hud := "⏱ %.1fs   🏆 best %.1fs   speed ×%.1f" % [t, record, speed / START_SPEED]
			draw_string(font, Vector2(size.x - 280, 20), hud, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
				Color(1, 1, 1, 0.7) if t <= record or record <= 0.0 else Color("ffd24d"))

	func _banner(font: Font, text: String, dy: float = 0.0) -> void:
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
		var p := Vector2((size.x - w) * 0.5, size.y * 0.5 + dy)
		draw_string(font, p + Vector2(2, 2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color(0, 0, 0, 0.7))
		draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color("ffd24d"))

	func _lane_name(player_idx: int) -> String:
		for lane in lanes:
			if lane["idx"] == player_idx:
				return lane["name"]
		return "?"

# ─── 🌀 Dark Maze — the torch-light maze minigame ─────────────────────────────
# EVERY player races at once, each in their own panel (a 2-column grid like the
# sketch). A panel is pitch black except an oval of torchlight showing the
# corridor's two parallel walls and the spirit in a red ring. Spirits walk the
# corridors automatically — SPD sets how fast — and when one reaches a
# crossroad the fork wall appears and (for humans) its Left/Right buttons pop
# in. Readable forks show the gap on the open side; tricky forks show gaps on
# BOTH sides. A wrong pick backs you up and re-shuffles the fork. First out
# wins. Emits finished(ranks) — escape order, winner first.
class MazeView:
	extends GridContainer

	signal finished(ranks: Array)

	var panels: Array = []
	var order: Array = []   # player indices in escape order

	func _init(entries: Array) -> void:
		columns = 2
		add_theme_constant_override("h_separation", 10)
		add_theme_constant_override("v_separation", 10)
		for e in entries:
			var p := MazePanel.new(e)
			p.escaped.connect(_on_escaped)
			add_child(p)
			panels.append(p)

	func _ready() -> void:
		if panels.is_empty():
			finished.emit([])

	func _on_escaped(player_idx: int) -> void:
		order.append(player_idx)
		for p in panels:
			if p.entrant["idx"] == player_idx:
				p.place = order.size()
				p.queue_redraw()
		if order.size() >= panels.size():
			finished.emit(order)

# One player's maze: walk (parallel walls scrolling by), fork (a 3-way
# crossroad with Left / Middle / Right buttons), back (walk of shame), out.
# Each fork's three arms are: one PATH forward, and two hazards from
# {trap: −30 HP, dead end: retry the fork, wrong turn: go BACK one fork}.
# Hints appear in the torchlight so it's readable: hazards usually show their
# marker (cap wall / red spikes / grey arrow), and the path sometimes shows
# a gold star.
class MazePanel:
	extends Control

	signal escaped(player_idx: int)

	const FORKS := 5
	const CPU_SMART := 0.8      # CPUs trust the hints this often
	const BACK_TIME := 0.9
	const HINT_HAZARD := 0.6    # chance a hazard arm shows its marker
	const HINT_PATH := 0.35     # chance the path arm shows its star
	const BG := Color(0.02, 0.02, 0.04)
	const BTN_BLUE := Color(0.11, 0.6, 0.86)
	const ORDINAL := ["1st", "2nd", "3rd", "4th", "5th", "6th"]
	const DIRS := ["left", "center", "right"]

	var entrant: Dictionary
	var place := 0             # escape position, set by MazeView
	var phase := "walk"        # walk / fork / back / out
	var t := 0.0
	var walk_time := 1.6       # per corridor — faster spirits walk quicker
	var forks_passed := 0
	var arms := {}             # dir -> "path" | "trap" | "dead" | "back"
	var revealed := {}         # dir -> bool: its hint is visible
	var msg := ""
	var smart := 0.8           # per-CPU: how reliably it reads the hints

	var _left_btn: Button
	var _center_btn: Button
	var _right_btn: Button

	func _init(e: Dictionary) -> void:
		entrant = e
		custom_minimum_size = Vector2(320, 208)
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		entrant["tex"] = SpiritsData.sprite_tex(e["spirit"].get("name", ""), "front")
		# SPD 1 → ~2.3s per corridor, SPD 6 → ~0.8s
		walk_time = clampf(2.6 - 0.3 * float(e["spirit"].get("spd", 2)), 0.8, 2.6)
		smart = randf_range(0.6, 0.95)   # each CPU reads the maze differently

	func _ready() -> void:
		_left_btn = _maze_button("⬅ Left")
		_left_btn.offset_left = 8
		_left_btn.offset_right = 100
		_left_btn.pressed.connect(func(): _choose("left"))
		add_child(_left_btn)
		_center_btn = _maze_button("⬆ Middle")
		_center_btn.anchor_left = 0.5
		_center_btn.anchor_right = 0.5
		_center_btn.offset_left = -52
		_center_btn.offset_right = 52
		_center_btn.pressed.connect(func(): _choose("center"))
		add_child(_center_btn)
		_right_btn = _maze_button("Right ➡")
		_right_btn.anchor_left = 1.0
		_right_btn.anchor_right = 1.0
		_right_btn.offset_left = -100
		_right_btn.offset_right = -8
		_right_btn.pressed.connect(func(): _choose("right"))
		add_child(_right_btn)
		_set_buttons(false)

	func _set_buttons(on: bool) -> void:
		_left_btn.visible = on
		_center_btn.visible = on
		_right_btn.visible = on

	func _maze_button(text: String) -> Button:
		var b := Button.new()
		b.text = text
		b.focus_mode = Control.FOCUS_NONE
		b.offset_top = 30
		b.offset_bottom = 64
		var sb := StyleBoxFlat.new()
		sb.bg_color = BTN_BLUE
		sb.corner_radius_top_left = 8
		sb.corner_radius_top_right = 8
		sb.corner_radius_bottom_left = 8
		sb.corner_radius_bottom_right = 8
		b.add_theme_stylebox_override("normal", sb)
		var sbh := sb.duplicate()
		sbh.bg_color = BTN_BLUE.lightened(0.2)
		b.add_theme_stylebox_override("hover", sbh)
		return b

	func _process(delta: float) -> void:
		match phase:
			"walk":
				t += delta
				if t >= walk_time:
					if forks_passed >= FORKS:
						_escape()
					else:
						_enter_fork()
				queue_redraw()
			"back":
				t += delta
				if t >= BACK_TIME:
					_enter_fork()
				queue_redraw()

	func _enter_fork() -> void:
		phase = "fork"
		t = 0.0
		# one arm is the path; the other two get distinct hazards
		var dirs := DIRS.duplicate()
		dirs.shuffle()
		var hazards := ["trap", "dead", "back"]
		hazards.shuffle()
		arms = {dirs[0]: "path", dirs[1]: hazards[0], dirs[2]: hazards[1]}
		revealed = {}
		for d in DIRS:
			revealed[d] = randf() < (HINT_PATH if arms[d] == "path" else HINT_HAZARD)
		msg = "Which way?"
		if entrant["human"]:
			_set_buttons(true)
		else:
			_cpu_pick()
		queue_redraw()

	# CPU: follows a visible star, avoids visible hazards, guesses the rest —
	# with per-CPU smarts, so some read the walls better than others.
	func _cpu_pick() -> void:
		await get_tree().create_timer(randf_range(0.5, 1.1)).timeout
		if phase != "fork":
			return
		var pick := ""
		if randf() < smart:
			for d in DIRS:
				if revealed[d] and arms[d] == "path":
					pick = d
			if pick == "":
				var safe: Array = DIRS.filter(func(d): return not (revealed[d] and arms[d] != "path"))
				if not safe.is_empty():
					pick = safe[randi() % safe.size()]
		if pick == "":
			pick = DIRS[randi() % DIRS.size()]
		_choose(pick)

	func _choose(dir: String) -> void:
		if phase != "fork":
			return
		_set_buttons(false)
		t = 0.0
		match arms.get(dir, "dead"):
			"path":
				forks_passed += 1
				phase = "walk"
				msg = ""
			"trap":
				# ouch — real damage to the spirit (never below 1 HP)
				var s: Dictionary = entrant["spirit"]
				s["current_hp"] = maxi(1, int(s.get("current_hp", s.get("hp", 60))) - 30)
				phase = "back"
				msg = "💥 A trap! −30 HP"
			"dead":
				phase = "back"
				msg = "🧱 Dead end!"
			"back":
				forks_passed = maxi(0, forks_passed - 1)
				phase = "back"
				msg = "↩ Wrong turn — back one fork!"
		queue_redraw()

	func _escape() -> void:
		phase = "out"
		set_process(false)
		_set_buttons(false)
		msg = "🎉 Out!"
		escaped.emit(entrant["idx"])
		queue_redraw()

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		draw_rect(Rect2(Vector2.ZERO, size), BG)
		# header: player name + fork progress
		draw_string(font, Vector2(10, 20), "%s — fork %d/%d   ♥%d" % [
			entrant["name"], mini(forks_passed + 1, FORKS), FORKS,
			int(entrant["spirit"].get("current_hp", 0))],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, entrant["color"])
		if msg != "":
			var mw := font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
			draw_string(font, Vector2((size.x - mw) * 0.5, size.y - 10), msg,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.85))
		# the torchlight oval; walls are drawn cave-black on top so they only
		# exist inside the light
		var c := Vector2(size.x * 0.5, size.y * 0.55)
		var rx := 104.0
		var ry := 68.0
		var pts := PackedVector2Array()
		for i in 40:
			var a := TAU * float(i) / 40.0
			pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
		draw_colored_polygon(pts, Color.WHITE if phase != "out" else Color(0.75, 1.0, 0.78))
		var xl := c.x - 52.0
		var xr := c.x + 52.0
		if phase == "walk" or phase == "back":
			# ONLY the two parallel walls, scrolling to show movement
			# (downward while walking forward, upward while backing out)
			var speed_px := 150.0 / walk_time
			var dir := 1.0 if phase == "walk" else -1.5
			var offset := fposmod(t * speed_px * dir, 30.0)
			var y := c.y - ry - 30.0 + offset
			while y < c.y + ry:
				draw_rect(Rect2(xl - 7, y, 7, 20), BG)
				draw_rect(Rect2(xr, y, 7, 20), BG)
				y += 30.0
		elif phase == "fork":
			# A 3-way crossroad: the corridor meets a cross passage. The far
			# wall has a CENTER GAP (the middle path continues forward), and
			# the arms open left and right. Hints appear per arm: a cap wall
			# = dead end, red spikes = trap, a grey arrow = sends you back,
			# a gold star = the way out.
			var y_top := c.y - 36.0
			var y_near := c.y + 16.0
			# far wall, split around the center gap
			draw_rect(Rect2(c.x - rx, y_top, (xl - 7.0) - (c.x - rx), 7), BG)
			draw_rect(Rect2(xr, y_top, (c.x + rx) - xr, 7), BG)
			# the middle path's walls continuing up through the gap
			draw_rect(Rect2(xl - 7, y_top - 22, 7, 22), BG)
			draw_rect(Rect2(xr, y_top - 22, 7, 22), BG)
			# near walls: from the light's edge in to the corridor corners
			draw_rect(Rect2(c.x - rx, y_near, (xl - 7.0) - (c.x - rx), 7), BG)
			draw_rect(Rect2(xr, y_near, (c.x + rx) - xr, 7), BG)
			# the corridor you came from
			draw_rect(Rect2(xl - 7, y_near, 7, c.y + ry - y_near), BG)
			draw_rect(Rect2(xr, y_near, 7, c.y + ry - y_near), BG)
			# hint markers on each arm
			for d in DIRS:
				if not revealed.get(d, false):
					continue
				var hp2 := Vector2(c.x, y_top - 12.0)          # center arm
				if d == "left":
					hp2 = Vector2(c.x - 80.0, (y_top + y_near) * 0.5 + 3.0)
				elif d == "right":
					hp2 = Vector2(c.x + 80.0, (y_top + y_near) * 0.5 + 3.0)
				_draw_hint(font, d, String(arms[d]), hp2, y_top, y_near, xl, xr, c)
		# the spirit, big, in its red ring
		if entrant["tex"]:
			var side := 52.0
			draw_texture_rect(entrant["tex"],
				Rect2(c + Vector2(-side * 0.5, -side * 0.5 + 8), Vector2(side, side)), false)
		draw_arc(c + Vector2(0, 8), 31.0, 0, TAU, 48, Color(0.9, 0.12, 0.12), 3.5)
		# escaped: show the placing over the light
		if phase == "out" and place > 0:
			var txt: String = "🎉 %s!" % ORDINAL[clampi(place - 1, 0, ORDINAL.size() - 1)]
			var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
			draw_string(font, Vector2((size.x - w) * 0.5, c.y - ry - 8), txt,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color("ffd24d"))

	func _draw_hint(font: Font, dir: String, kind: String, p: Vector2,
			y_top: float, y_near: float, xl: float, xr: float, c: Vector2) -> void:
		match kind:
			"dead":
				# a cap wall blocking that arm
				if dir == "center":
					draw_rect(Rect2(xl - 7, y_top - 22, (xr - xl) + 14, 7), BG)
				elif dir == "left":
					draw_rect(Rect2(c.x - 91.0, y_top, 7, y_near - y_top + 7), BG)
				else:
					draw_rect(Rect2(c.x + 84.0, y_top, 7, y_near - y_top + 7), BG)
			"trap":
				# little red spikes
				for i in 3:
					var sx := p.x - 12.0 + i * 12.0
					draw_colored_polygon(PackedVector2Array([
						Vector2(sx - 4, p.y + 4), Vector2(sx + 4, p.y + 4), Vector2(sx, p.y - 6)]),
						Color(0.85, 0.15, 0.15))
			"back":
				# a grey arrow pointing back down the corridor
				draw_rect(Rect2(p.x - 2, p.y - 8, 4, 10), Color(0.35, 0.35, 0.4))
				draw_colored_polygon(PackedVector2Array([
					Vector2(p.x - 6, p.y + 2), Vector2(p.x + 6, p.y + 2), Vector2(p.x, p.y + 10)]),
					Color(0.35, 0.35, 0.4))
			"path":
				# the golden star marks the way out
				var star := "★"
				var w := font.get_string_size(star, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
				draw_string(font, Vector2(p.x - w * 0.5, p.y + 6), star,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1.0, 0.78, 0.15))
