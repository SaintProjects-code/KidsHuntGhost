extends MenuWindow
## Debug helpers (only in games started from the menu's DEV button).
## present(player_index); emits closed().

signal closed()

const CompWindow := preload("res://Scenes/UI/Competition/CompetitionWindow.gd")

var _idx := -1

func _ready() -> void:
	var root := _init_window(780)
	root.add_child(_title_label("⚡ Dev", 26))
	var cols := UIKit.hbox(20)
	root.add_child(cols)
	var left := UIKit.vbox(8)
	var right := UIKit.vbox(8)
	for c in [left, right]:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cols.add_child(c)

	left.add_child(_title_label("Resources", 18))
	left.add_child(_row([
		_button("+5 pts", func(): GameState.award_points(_idx, 5)),
		_button("+50 gold", func(): _p().inventory.gold += 50),
		_button("+Lantern", func():
			closed.emit()
			CardSystem.give(_idx, "spirit_lantern")),
	]))
	left.add_child(_row([
		_button("+Soul Lantern", func():
			closed.emit()
			CardSystem.give(_idx, "soul_lantern")),
		_button("Draw card", func():
			closed.emit()
			CardSystem.give_random(_idx)),
	]))
	left.add_child(_row([_button("Give all badges", _all_badges), _button("Heal team", _heal)]))
	left.add_child(_title_label("Lead spirit", 18))
	left.add_child(_row([
		_button("+1 ★ to lead", func(): _stars(1.0)),
		_button("Lead → 3★", func(): _stars(3.0)),
	]))
	left.add_child(_row([_button("Random trait to lead", _trait_lead)]))
	# test more players and phones without going back to Player Setup
	left.add_child(_title_label("Players & phones", 18))
	left.add_child(_row([
		_button("＋ Add player", _add_player),
		_button("📱 Connect phones", _connect_phones),
	]))
	_phone_info = UIKit.label("", 13, Color(1, 1, 1, 0.8))
	_phone_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_phone_info.custom_minimum_size.x = 300
	left.add_child(_phone_info)

	right.add_child(_title_label("Step on tile", 18))
	right.add_child(_row([
		_button("Wisp", func(): _tile(&"WISP")),
		_button("Ghost", func(): _tile(&"GHOST")),
		_button("Phantom", func(): _tile(&"PHANTOM")),
	]))
	right.add_child(_row([
		_button("Event", func(): _tile(&"EVENT")),
		_button("Item", func(): _tile(&"ITEM")),
		_button("Comp", func(): _tile(&"COMPETITION")),
	]))
	right.add_child(_row([
		_button("Town", func(): _tile(&"CITY")),
		_button("Trail tile", func(): _tile(&"WARDEN")),
		_button("Clash tile", func(): _tile(&"CLASH")),
	]))
	# forces which event the next Comp tile runs
	var comp_row := UIKit.hbox(8)
	var comp_event := OptionButton.new()
	comp_event.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var keys: Array = [""] + CompWindow.all_events()
	for k in keys:
		comp_event.add_item("Comp event: Random" if k == "" else CompWindow.event_name(k))
	comp_event.select(maxi(0, keys.find(CompWindow.dev_forced_event)))
	comp_event.item_selected.connect(func(i): CompWindow.dev_forced_event = keys[i])
	comp_row.add_child(comp_event)
	comp_row.add_child(_button("Run Comp", func(): _tile(&"COMPETITION")))
	right.add_child(comp_row)
	right.add_child(_title_label("Battle (no rewards)", 18))
	right.add_child(_row([
		_button("Haunted Four", func(): _battle(&"WARDEN", _idx, -1)),
		_button("Spirit Lord", func(): _battle(&"CHAMPION", _idx, -1)),
	]))
	var pvp := UIKit.hbox(8)
	for i in GameState.players.size():
		for j in range(i + 1, GameState.players.size()):
			var a := i
			var b := j
			var btn := _button("%s v %s" % [GameState.players[a].player_name, GameState.players[b].player_name],
				func(): _battle(&"PVP", a, b), 38)
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			pvp.add_child(btn)
	right.add_child(pvp)
	root.add_child(_button("Close", func(): closed.emit()))
	hide()

func present(player_index: int) -> void:
	_idx = player_index

var _phone_info: Label

func _process(_delta: float) -> void:
	if not visible or _phone_info == null:
		return
	var seats: Array = []
	for p in GameState.players:
		seats.append("%s%s" % [p.player_name, " 📱" if p.remote_id != "" else (" (CPU)" if p.is_cpu else "")])
	var room := "📱 Room %s — on a phone open %s and join with the code." % [Remote.code, Remote.phone_url()] if Remote.is_on() \
		else "Phones are off — press 📱 Connect phones."
	_phone_info.text = "%d/%d players: %s\n%s\nA phone that joins takes the next CPU seat (it becomes that player)." % [
		GameState.players.size(), MAX_PLAYERS, ", ".join(seats), room]

const MAX_PLAYERS := 6
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
