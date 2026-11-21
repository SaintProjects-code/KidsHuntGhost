extends MenuWindow
## Debug helpers (only in games started from the menu's DEV button).
## present(player_index); emits closed().

signal closed()

const CompWindow := preload("res://Scenes/UI/Competition/CompetitionWindow.gd")

var _idx := -1

# Reopen after the board restarts (Add player / Switch map), so the window
# doesn't vanish on you.
static var reopen := false

func _ready() -> void:
	var root := _init_window(860)
	root.add_theme_constant_override("separation", 12)
	root.add_child(_title_label("⚡ Dev tools", 26))

	# ── the game: players, phones, map ───────────────────────────────────────
	var game := _card("🎮 Game")
	root.add_child(game[0])
	_players_row = UIKit.hbox(8)
	_players_row.alignment = BoxContainer.ALIGNMENT_CENTER
	game[1].add_child(_players_row)
	var ctl := UIKit.hbox(10)
	game[1].add_child(ctl)
	var add := _button("＋ Add player", _add_player, 40)
	add.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ctl.add_child(add)
	var phones := _button("📱 Connect phones", _connect_phones, 40)
	phones.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ctl.add_child(phones)
	var map_pick := OptionButton.new()
	map_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_pick.add_theme_font_size_override("font_size", 18)
	var map_keys: Array = GameData.MAPS.keys()
	for k in map_keys:
		var info: Dictionary = GameData.MAPS[k]
		map_pick.add_item("🗺 " + info["name"])
	map_pick.select(maxi(0, map_keys.find(GameState.active_map)))
	map_pick.tooltip_text = "Pick a map — the board restarts on it with the same players"
	map_pick.item_selected.connect(func(i): _switch_map(map_keys[i]))   # switches right away
	ctl.add_child(map_pick)
	_phone_info = UIKit.label("", 13, Color(1, 1, 1, 0.75))
	_phone_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_phone_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game[1].add_child(_phone_info)

	var cols := UIKit.hbox(12)
	root.add_child(cols)
	# ── the current player ───────────────────────────────────────────────────
	var me := _card("🧑 Current player")
	me[0].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(me[0])
	var left: VBoxContainer = me[1]
	left.add_child(_row([
		_button("+5 pts", func(): GameState.award_points(_idx, 5)),
		_button("+50 gold", func(): _p().inventory.gold += 50),
		_button("Heal team", _heal),
	]))
	left.add_child(_row([
		_button("+Lantern", func():
			closed.emit()
			CardSystem.give(_idx, "spirit_lantern")),
		_button("+Soul Lantern", func():
			closed.emit()
			CardSystem.give(_idx, "soul_lantern")),
		_button("Draw card", func():
			closed.emit()
			CardSystem.give_random(_idx)),
	]))
	left.add_child(_row([_button("All badges", _all_badges), _button("+1 ★ lead", func(): _stars(1.0)), _button("Lead → 3★", func(): _stars(3.0))]))
	left.add_child(_row([_button("Random trait to lead", _trait_lead)]))
	# ── test a tile / minigame / battle ──────────────────────────────────────
	var test := _card("🧪 Try something")
	test[0].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(test[0])
	var right: VBoxContainer = test[1]
	right.add_child(_row([_button("Wisp", func(): _tile(&"WISP")), _button("Ghost", func(): _tile(&"GHOST")), _button("Phantom", func(): _tile(&"PHANTOM"))]))
	right.add_child(_row([_button("Event", func(): _tile(&"EVENT")), _button("Item", func(): _tile(&"ITEM")), _button("Town", func(): _tile(&"CITY"))]))
	right.add_child(_row([_button("Trail tile", func(): _tile(&"WARDEN")), _button("Clash tile", func(): _tile(&"CLASH"))]))
	var comp_row := UIKit.hbox(8)
	var comp_event := OptionButton.new()
	comp_event.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	comp_event.add_theme_font_size_override("font_size", 18)
	var keys: Array = [""] + CompWindow.all_events()
	for k in keys:
		comp_event.add_item("Minigame: Random" if k == "" else CompWindow.event_name(k))
	comp_event.select(maxi(0, keys.find(CompWindow.dev_forced_event)))
	comp_event.item_selected.connect(func(i): CompWindow.dev_forced_event = keys[i])
	comp_row.add_child(comp_event)
	comp_row.add_child(_button("▶ Play", func(): _tile(&"COMPETITION")))
	right.add_child(comp_row)
	right.add_child(_row([
		_button("Haunted Four", func(): _battle(&"WARDEN", _idx, -1)),
		_button("Spirit Lord", func(): _battle(&"CHAMPION", _idx, -1)),
		_button("PvP vs next", func(): _battle(&"PVP", _idx, (_idx + 1) % GameState.players.size())),
	]))
	root.add_child(_button("Close", func(): closed.emit()))
	hide()

var _players_row: HBoxContainer

# A titled card (dark rounded panel); returns [card, its column].
func _card(title: String) -> Array:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UIKit.box(Color(0.08, 0.06, 0.16, 0.9), 12, 1, Color(UIKit.PURPLE, 0.5), Vector2(12, 10)))
	var col := UIKit.vbox(8)
	card.add_child(col)
	var head := UIKit.label(title, 17, UIKit.GOLD)
	col.add_child(head)
	return [card, col]

func present(player_index: int) -> void:
	_idx = player_index

var _phone_info: Label

func _process(_delta: float) -> void:
	if not visible or _phone_info == null:
		return
	if _players_sig != _sig():
		_players_sig = _sig()
		UIKit.clear(_players_row)
		for p in GameState.players:
			var chip := UIKit.label("%s%s" % [p.player_name, "  📱" if p.remote_id != "" else ("  CPU" if p.is_cpu else "")], 14, Color.WHITE)
			chip.add_theme_stylebox_override("normal", UIKit.box(Color(0.1, 0.08, 0.18), 10, 2, p.color, Vector2(10, 3)))
			_players_row.add_child(chip)
	_phone_info.text = ("📱 Room %s — open %s on a phone and join. A phone takes the next CPU player." % [Remote.code, Remote.phone_url()]) \
		if Remote.is_on() else "%d / %d players · phones off" % [GameState.players.size(), MAX_PLAYERS]

const MAX_PLAYERS := 6
var _players_sig := ""

func _sig() -> String:
	return ",".join(GameState.players.map(func(p): return "%s%s%s" % [p.player_name, p.remote_id, p.is_cpu]))
const SetupScript := preload("res://Scenes/Menu/SetupScreen.gd")

# DEV: one more player (a CPU — a phone can take it over). The board restarts
# with everyone at the start so the new player gets a token and a turn.
func _add_player() -> void:
	if GameState.players.size() >= MAX_PLAYERS:
		Sfx.play("error")
		return
	var used: Array = GameState.players.map(func(p): return p.trainer_key)
	var t: Dictionary = SetupScript.TRAINERS[0]
	for cand in SetupScript.TRAINERS:
		if not used.has(cand["portrait"]):
			t = cand
			break
	var p := PlayerData.new()
	p.player_name = t["name"]
	p.trainer_key = t["portrait"]
	p.color = t["color"]
	p.is_cpu = true
	p.team.append(SpiritsData.get_spirit(t["starter"]))
	for k in 3:
		p.team.append(SpiritsData.random_spirit(1))
	p.inventory.gold = 100
	p.inventory.hand = ["spirit_lantern", "spirit_lantern", "spirit_shield", "battle_cry"]
	GameState.players.append(p)
	reopen = true
	closed.emit()
	UIManager.reset_pause()
	get_tree().reload_current_scene()

# DEV: play the same players on another map (the board restarts there).
func _switch_map(map: int) -> void:
	GameState.active_map = map
	GameState.gang_hideout = ""   # each map picks its own hideout town
	reopen = true
	closed.emit()
	UIManager.reset_pause()
	get_tree().reload_current_scene()

# DEV: host a phone room on this computer.
func _connect_phones() -> void:
	if not Remote.is_on():
		Remote.start_local()
	Sfx.play("click")

func _p() -> PlayerData:
	return GameState.players[_idx]

# Close first, then fire the request, so the flow's own window opens on top.
func _tile(kind: StringName) -> void:
	closed.emit()
	EventBus.dev_tile_requested.emit(kind)

func _battle(kind: StringName, a: int, b: int) -> void:
	closed.emit()
	EventBus.dev_battle_requested.emit(kind, a, b)

func _row(btns: Array) -> HBoxContainer:
	var h := UIKit.hbox(8)
	for b in btns:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(b)
	return h

func _stars(amount: float) -> void:
	if _p().team.is_empty():
		return
	closed.emit()
	SpiritsProgressionSystem.award_stars(_idx, _p().lead(), amount)

func _trait_lead() -> void:
	if _p().team.is_empty():
		return
	var lead := _p().lead()
	var held: Array = lead.get("traits", [])
	var pool: Array = EventsData.TRAIT_DATA.keys().filter(func(k): return not held.has(k))
	if not pool.is_empty():
		EventBus.log_entry.emit(_idx, "dev: " + EventsData.grant_trait(lead, pool.pick_random()), "#7fe0d0")

func _all_badges() -> void:
	for k in _p().progress.badges:
		_p().progress.badges[k] = true
	EventBus.badge_earned.emit(_idx, "DEV")

func _heal() -> void:
	for m in _p().team:
		m["current_hp"] = m.get("hp", 0)
