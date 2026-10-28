extends MenuWindow
## Competition tile, in three steps:
##   1) Selection — every player enters ONE spirit (CPUs pick the best one for
##      the announced event). Keys 1–6 pick for the first human.
##   2) The event, FULL SCREEN — a minigame (everyone plays at once on one
##      keyboard, see Controls) or a stat contest (roll → perform → results).
##   3) Podium — revealed 3rd → 2nd → 1st; top 3 earn points, and beating a
##      minigame record pays a bonus.
## present(triggering_player_index); emits closed().

signal closed()

const GAMES := {
	"climb":      {"name": "🧗 Spirit Climb", "script": preload("res://Scenes/UI/Competition/ClimbGame.gd"),
		"hint": "Bounce up the platforms, steering LEFT / RIGHT. Light spirits (low DEF + HP) bounce higher, SPD steers faster."},
	"maze":       {"name": "🌀 Dark Maze",  "script": preload("res://Scenes/UI/Competition/DarkMazeGame.gd"),
		"hint": "Pick LEFT / MIDDLE / RIGHT at each crossroad. SPD = walking speed, HP = trap tolerance. First out wins!"},
	"ghost_snap": {"name": "📸 Ghost Snap", "script": preload("res://Scenes/UI/Competition/GhostSnapGame.gd"),
		"hint": "Snap the ghost when it's in your frame — ACTION key. SPD = a wider frame, HP = a calmer ghost."},
	"scare_off":  {"name": "😱 Scare-Off",  "script": preload("res://Scenes/UI/Competition/ScareOffGame.gd"),
		"hint": "MASH your ACTION key to scare the scarecrow away! ATK = scare power, DEF = slower drain."},
	"wisp_float": {"name": "🎈 Wisp Float", "script": preload("res://Scenes/UI/Competition/WispFloatGame.gd"),
		"hint": "HOLD your ACTION key to float, grab wisps, dodge bats. SPD = lift, DEF = shrug off bats."},
	"pumpkin_toss": {"name": "🎃 Pumpkin Toss", "script": preload("res://Scenes/UI/Competition/PumpkinTossGame.gd"),
		"hint": "Press ACTION when the power meter is high — 3 throws, farthest total wins. ATK = distance, SPD = easier timing."},
	"boo_reflex": {"name": "👻 Boo Reflex", "script": preload("res://Scenes/UI/Competition/BooReflexGame.gd"),
		"hint": "Wait for the BOO!, then press ACTION first — too early and you sit out. Best of 3. SPD = sharper reflexes."},
	"bat_dodge":  {"name": "🦇 Bat Dodge",  "script": preload("res://Scenes/UI/Competition/BatDodgeGame.gd"),
		"hint": "LEFT / MIDDLE / RIGHT to dodge the swooping bats. Last one flying wins. DEF = an extra heart."},
	"lantern_memory": {"name": "🏮 Lantern Memory", "script": preload("res://Scenes/UI/Competition/LanternMemoryGame.gd"),
		"hint": "Watch the lanterns flash, then repeat the pattern with LEFT / MIDDLE / RIGHT. HP = an extra life."},
}
const CONTESTS := {
	"spd":     {"name": "🏃 Haunted Dash",       "label": "Speed"},
	"atk":     {"name": "💪 Coffin Lift",        "label": "Attack"},
	"def":     {"name": "🛡 Spooky Stare-Down",  "label": "Defense"},
	"hp_stat": {"name": "🌟 Midnight Marathon",  "label": "HP Tier"},
	"beauty":  {"name": "✨ Moonlight Pageant",  "label": "Charm"},
}
const MEDALS := ["🥇", "🥈", "🥉"]
const CONTEST_CHANCE := 0.3   # how often the event is a quick stat contest

# Dev override: a GAMES/CONTESTS key forces that event; "" = random.
static var dev_forced_event := ""

var _title: Label
var _hint: Label
var _body: VBoxContainer
var _next: Button
var _phase := 0       # 1 = selection, 2 = event, 3 = podium
var _event := ""      # a GAMES or CONTESTS key
var _picks := {}      # player idx -> entered spirit
var _chips := {}      # player idx -> Array of SpiritChip
var _ranks: Array = []
var _game: CompGame

func _ready() -> void:
	var col := _init_window(700, 0)
	_title = _title_label("🏅 Competition!", 26)
	col.add_child(_title)
	_hint = UIKit.wrap_label("", 14, 660)
	_hint.modulate = Color(1, 1, 1, 0.85)
	col.add_child(_hint)
	_body = UIKit.vbox(8)
	col.add_child(_body)
	_next = _button("Start!", _on_next)
	col.add_child(_next)
	hide()

static func all_events() -> Array:
	return GAMES.keys() + CONTESTS.keys()

static func event_name(key: String) -> String:
	return String(GAMES.get(key, CONTESTS.get(key, {})).get("name", key))

func present(_player_index: int) -> void:
	_phase = 1
	_picks.clear()
	_ranks.clear()
	_event = dev_forced_event if all_events().has(dev_forced_event) else \
		(CONTESTS.keys().pick_random() if randf() < CONTEST_CHANCE else GAMES.keys().pick_random())
	_build_selection()

func _is_game() -> bool:
	return GAMES.has(_event)

# All-CPU game: nobody can press the buttons, so the window drives itself.
func run_cpu_auto() -> void:
	while visible and _phase < 3:
		await get_tree().create_timer(1.0).timeout
		if visible and not _next.disabled:
			_on_next()
	await get_tree().create_timer(2.5).timeout
	if visible and _phase == 3:
		_on_next()

func _on_next() -> void:
	Sfx.play("click")
	match _phase:
		1: _start_event()
		2: _show_podium()
		3: closed.emit()

# ─── Step 1: every player picks a spirit ──────────────────────────────────────
func _build_selection() -> void:
	_title.text = "🏅 %s — pick your spirit!" % event_name(_event)
	_hint.text = GAMES[_event]["hint"] if _is_game() else \
		"Judged on %s ×2, plus stars and a die roll!" % CONTESTS[_event]["label"]
	if _event == "beauty":
		_hint.text = "Three judges each love one stat — a well-rounded spirit shines! Plus stars and a die roll."
	if _is_game():
		_hint.text += "\nKeys — P1 W · ASD   P2 I · JKL   P3 ↑ · ←↓→   P4 Num8 · 456   (or click your area)"
	_next.text = "Start!  [Space]"
	UIKit.clear(_body)
	var grid := GridContainer.new()
	grid.columns = 2   # wide instead of tall, so Start stays on screen
	grid.add_theme_constant_override("h_separation", 26)
	grid.add_theme_constant_override("v_separation", 10)
	_body.add_child(grid)
	_chips.clear()
	for i in GameState.players.size():
		var p: PlayerData = GameState.players[i]
		var row := UIKit.hbox(12)
		row.add_child(CompChips.TrainerChip.new(GameData.trainer_texture(GameData.player_trainer(p)), p.color))
		var right := UIKit.vbox(2)
		right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(right)
		var slot := Controls.slot_of(i)
		right.add_child(UIKit.label(p.player_name + ("  (P%d keys)" % (slot + 1) if not p.is_cpu and slot >= 0 and _is_game() else ""), 16, p.color))
		var chips_row := GridContainer.new()   # 2 rows × 3: a team of 6 stays compact
		chips_row.columns = 3
		chips_row.add_theme_constant_override("h_separation", 8)
		chips_row.add_theme_constant_override("v_separation", 4)
		right.add_child(chips_row)
		_chips[i] = []
		for s in p.team:
			var chip := CompChips.SpiritChip.new(s, star_text(fit_stars(_event, s)))
			chip.picked.connect(func(c): _on_chip_picked(c, i))
			chips_row.add_child(chip)
			_chips[i].append(chip)
		if p.team.is_empty():
			chips_row.add_child(UIKit.label("— no spirits —", 14))
		grid.add_child(row)
		if p.is_cpu and not p.team.is_empty():
			_select_chip(i, _chips[i][_best_index(p.team)])
	_update_next()

# 📱 Phones (see Remote): in the pick step EVERY player picks their own spirit
# at the same time, and anyone can press Start once all have picked. Other
# steps use the normal button mirroring.
func remote_view(idx: int) -> Dictionary:
	if _phase != 1:
		# everyone takes part, so any human may move the awards along — even
		# when the competition started on a CPU's turn
		if GameState.players[idx].is_cpu or _next.disabled or not _next.is_visible_in_tree():
			return {"screen": "wait", "title": _title.text, "text": "🏅 Competition!"}
		return {"screen": "buttons", "title": _title.text, "lines": [],
			"buttons": [{"label": _next.text.get_slice("  [", 0), "gold": true}], "_actions": [_on_next]}
	if not _chips.has(idx):
		return {}
	var buttons: Array = []
	var actions: Array = []
	for chip in _chips[idx]:
		var s: Dictionary = chip.spirit
		buttons.append({"label": "%s  %s%s" % [s.get("name", "?"), star_text(fit_stars(_event, s)), "  ✓" if _picks.get(idx) == s else ""],
			"desc": "ATK %d · DEF %d · SPD %d · HP %d" % [int(s.get("atk", 0)), int(s.get("def", 0)), int(s.get("spd", 0)), int(s.get("hp_stat", 0))],
			"img": Remote.sprite_url(s)})
		actions.append(func(): _on_chip_picked(chip, idx))
	if not _next.disabled:
		buttons.append({"label": "▶ Start!", "gold": true})
		actions.append(_on_next)
	return {"screen": "buttons", "title": _title.text, "lines": [_hint.text.get_slice("\n", 0), "★★★ = a great pick for this event, ★ = a poor one."],
		"buttons": buttons, "_actions": actions}

func _on_chip_picked(chip, i: int) -> void:
	if not GameState.players[i].is_cpu and _phase == 1:
		Sfx.play("pop")
		_select_chip(i, chip)
		_update_next()

func _select_chip(i: int, chip) -> void:
	for c in _chips[i]:
		c.set_selected(c == chip)
	_picks[i] = chip.spirit

# Start stays disabled until every player with spirits has picked.
func _update_next() -> void:
	_next.disabled = _picks.is_empty() or GameState.players.size() != _picks.size() + \
		GameState.players.filter(func(p): return p.team.is_empty()).size()

# How well a spirit suits THIS event, 0–10ish. Shown on every chip so the
# pick is informed, and used for the CPU's pick.
static func rating(event: String, s: Dictionary) -> float:
	var g := func(k): return float(s.get(k, 0))
	match event:
		"climb":      return 14.0 - g.call("def") - g.call("hp_stat") + g.call("spd") * 0.5   # light + nimble
		"maze":       return g.call("spd") * 1.5 + g.call("hp_stat") * 0.5
		"ghost_snap": return g.call("spd") + g.call("hp_stat") * 0.6
		"scare_off":  return g.call("atk") + g.call("def") * 0.6
		"wisp_float": return g.call("spd") + g.call("def") * 0.5
		"pumpkin_toss": return g.call("atk") * 1.5 + g.call("spd") * 0.5
		"boo_reflex": return g.call("spd") * 1.5
		"bat_dodge":  return g.call("spd") + g.call("def") * 0.8
		"lantern_memory": return g.call("hp_stat") + g.call("spd") * 0.5
		"beauty":     return (g.call("atk") + g.call("def") + g.call("spd") + g.call("hp_stat")) * 0.75 + g.call("stars")
	return g.call(event) * 2.0 + g.call("stars")   # stat contests

# The rating as 1–3 stars: where it falls between the weakest and strongest
# spirit possible for this event (every stat tier 1…6, 0…3 stars).
static func fit_stars(event: String, s: Dictionary) -> int:
	var lo := INF
	var hi := -INF
	for mask in 32:   # every corner of the stat box
		var probe := {}
		var k := 0
		for stat in ["atk", "def", "spd", "hp_stat"]:
			probe[stat] = 6 if mask & (1 << k) else 1
			k += 1
		probe["stars"] = 3 if mask & 16 else 0
		var r := rating(event, probe)
		lo = minf(lo, r)
		hi = maxf(hi, r)
	var f := (rating(event, s) - lo) / maxf(0.001, hi - lo)
	return 3 if f >= 0.6 else (2 if f >= 0.3 else 1)

static func star_text(n: int) -> String:
	return "★".repeat(n) + "☆".repeat(3 - n)

func _best_index(team: Array) -> int:
	var best := 0
	for i in team.size():
		if rating(_event, team[i]) > rating(_event, team[best]):
			best = i
	return best

func _unhandled_key_input(ev: InputEvent) -> void:
	if not visible:
		return
	if Controls.confirm_pressed(ev) and not _next.disabled and _phase != 2:
		get_viewport().set_input_as_handled()
		_on_next()
		return
	# 1–6 pick for the first human who hasn't picked yet
	var n := Controls.number_pressed(ev)
	if _phase == 1 and n >= 0:
		for i in GameState.players.size():
			if not GameState.players[i].is_cpu and n < _chips[i].size():
				get_viewport().set_input_as_handled()
				_on_chip_picked(_chips[i][n], i)
				return

# ─── Step 2: the event ────────────────────────────────────────────────────────
func _start_event() -> void:
	_phase = 2
	_title.text = "%s!" % event_name(_event)
	_hint.text = ""
	_next.text = "Awards ▶"
	_next.disabled = true
	UIKit.clear(_body)
	_set_fullscreen(true)
	var entries: Array = []
	var idxs: Array = _picks.keys()
	idxs.sort()
	for i in idxs:
		var p: PlayerData = GameState.players[i]
		entries.append({"idx": i, "spirit": _picks[i], "human": not p.is_cpu, "color": p.color, "name": p.player_name})
	if _is_game():
		_game = GAMES[_event]["script"].new()
	else:
		_game = preload("res://Scenes/UI/Competition/StatContestGame.gd").new()
		_game.stat = _event
		_game.label = CONTESTS[_event]["label"]
		_game.event_name = CONTESTS[_event]["name"]
	_game.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_game.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_game.setup(entries)
	_game.finished.connect(func(r):
		_ranks = r
		_next.disabled = false)
	_body.add_child(_game)

# The game area fills the whole screen while an event plays.
func _set_fullscreen(on: bool) -> void:
	var vp := get_viewport_rect().size
	panel.custom_minimum_size = vp - Vector2(24, 24) if on else Vector2(700, 0)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL if on else Control.SIZE_FILL

# ─── Step 3: podium (revealed 3rd → 2nd → 1st) ────────────────────────────────
func _show_podium() -> void:
	_phase = 3
	_title.text = "🏆 Winners!"
	_hint.text = ""
	_next.text = "OK  [Space]"
	_next.disabled = true
	var record := _game.beat_record()
	UIKit.clear(_body)
	_set_fullscreen(false)
	var rows: Array = []
	for rank in mini(Balance.PODIUM_POINTS.size(), _ranks.size()):
		var i: int = _ranks[rank]
		var p: PlayerData = GameState.players[i]
		var pts: int = Balance.PODIUM_POINTS[rank]
		var row := UIKit.hbox(10)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(UIKit.label(MEDALS[rank], 30))
		var chip := CompChips.SpiritChip.new(_picks[i])
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(chip)
		var l := UIKit.label("%s's %s   +%d points!" % [p.player_name, _picks[i]["name"], pts], 18, p.color)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(l)
		row.modulate.a = 0.0
		_body.add_child(row)
		rows.append([row, i, pts])
	if _ranks.is_empty():
		_body.add_child(UIKit.label("No winners this time!", 18))
	# reveal from 3rd up to 1st, awarding as each appears
	for k in range(rows.size() - 1, -1, -1):
		await get_tree().create_timer(0.8).timeout
		if not visible:
			return
		var row: Control = rows[k][0]
		row.modulate.a = 1.0
		Juice.pop(row, 1.12, 0.3)
		Sfx.play("win" if k == 0 else "points")
		GameState.award_points(rows[k][1], rows[k][2])
	if record and not _ranks.is_empty():
		await get_tree().create_timer(0.6).timeout
		GameState.award_points(_ranks[0], Balance.RECORD_BONUS)
		var rec := UIKit.label("🎉 NEW RECORD!  %s gets +%d bonus points!" % [GameState.players[_ranks[0]].player_name,
			Balance.RECORD_BONUS], 18, UIKit.GOLD)
		rec.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_body.add_child(rec)
		Juice.pop(rec)
	_next.disabled = false
