extends MenuWindow
## Debug helpers for testing. present(player_index); emits closed().

signal closed()

const CompWindow := preload("res://Scenes/UI/CompetitionWindow.gd")

var _player_index: int = -1
var _comp_event_keys: Array = []   # parallel to the dropdown items

func _ready() -> void:
	# Two side-by-side columns keep the window short enough that the Close
	# button below always stays on screen.
	var root := _init_window(760)
	root.add_child(_title_label("⚡ Dev", 26))

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 20)
	root.add_child(cols)
	var left := _column()
	var right := _column()
	cols.add_child(left)
	cols.add_child(right)

	# LEFT: resources + lead-spirit progression
	left.add_child(_title_label("Resources", 18))
	left.add_child(_row([
		_button("+5 pts", func(): GameState.award_points(_player_index, 5)),
		_button("+50 gold", func(): GameState.players[_player_index].inventory.gold += 50),
		_button("+3 Balls", func(): GameState.players[_player_index].inventory.balls[&"spirit_ball"] += 3),
	]))
	left.add_child(_row([
		_button("Give all badges", _all_badges),
		_button("Heal team", _heal),
	]))
	left.add_child(_title_label("Lead spirit", 18))
	left.add_child(_row([
		_button("+1 ★ to lead", _star_lead),
		_button("Evolve lead (→ 3★)", _evolve_lead),
	]))
	left.add_child(_row([
		_button("Random trait to lead", _trait_lead),
	]))

	# RIGHT: step-on-a-tile effects + battles
	right.add_child(_title_label("Step on tile", 18))
	right.add_child(_row([
		_button("SP Pink", func(): _tile(&"PKMN_PINK")),
		_button("SP Green", func(): _tile(&"PKMN_GREEN")),
		_button("SP Red", func(): _tile(&"PKMN_RED")),
	]))
	right.add_child(_row([
		_button("Event", func(): _tile(&"EVENT")),
		_button("Item", func(): _tile(&"ITEM")),
		_button("Comp", func(): _tile(&"COMPETITION")),
	]))
	right.add_child(_row([
		_button("City", func(): _tile(&"CITY")),
		_button("Elite 4", func(): _battle(&"ELITE", _player_index, -1)),
		_button("Gary", func(): _battle(&"GARY", _player_index, -1)),
	]))
	# Comp event picker: forces which event the next Comp tile runs.
	var comp_row := HBoxContainer.new()
	comp_row.add_theme_constant_override("separation", 8)
	var comp_event := OptionButton.new()
	comp_event.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	comp_event.add_item("Comp event: Random")
	_comp_event_keys.append("")
	comp_event.add_item(CompWindow.TREE_JUMP["name"])
	_comp_event_keys.append(CompWindow.TREE_JUMP["key"])
	comp_event.add_item(CompWindow.MAZE["name"])
	_comp_event_keys.append(CompWindow.MAZE["key"])
	for e in CompWindow.EVENTS:
		comp_event.add_item(e["name"])
		_comp_event_keys.append(e["key"])
	comp_event.select(maxi(0, _comp_event_keys.find(CompWindow.dev_forced_event)))
	comp_event.item_selected.connect(func(i): CompWindow.dev_forced_event = _comp_event_keys[i])
	comp_row.add_child(comp_event)
	var run_comp := _button("Run Comp", func(): _tile(&"COMPETITION"))
	comp_row.add_child(run_comp)
	right.add_child(comp_row)
	right.add_child(_title_label("Battle (no rewards)", 18))
	var pvp := HBoxContainer.new()
	pvp.add_theme_constant_override("separation", 8)
	var np: int = GameState.players.size()
	for i in np:
		for j in range(i + 1, np):
			var a: int = i
			var b: int = j
			var lbl: String = "%s v %s" % [GameState.players[a].player_name, GameState.players[b].player_name]
			var btn := _button(lbl, func(): _battle(&"PVP", a, b), 38)
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			pvp.add_child(btn)
	right.add_child(pvp)

	root.add_child(_button("Close", func(): closed.emit()))
	hide()

func _column() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return v

func present(player_index: int) -> void:
	_player_index = player_index

# Close this window first, then fire the request so the flow's own window opens
# on top (and we don't accidentally close the window it just opened).
func _tile(kind: StringName) -> void:
	closed.emit()
	EventBus.dev_tile_requested.emit(kind)

func _battle(kind: StringName, a: int, b: int) -> void:
	closed.emit()
	EventBus.dev_battle_requested.emit(kind, a, b)

func _row(btns: Array) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	for b in btns:
		var btn: Button = b
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(btn)
	return h

# Close the dev window first, then award — the bonus-reward window (on its own
# layer) opens on top of the board once the lead crosses 3 stars.
func _star_lead() -> void:
	var lead: Dictionary = _lead()
	if lead.is_empty():
		return
	closed.emit()
	SpiritsProgressionSystem.award_stars(_player_index, lead, 1.0)

# Jump the lead straight to 3 stars so the evolution + bonus reward fires now.
func _evolve_lead() -> void:
	var lead: Dictionary = _lead()
	if lead.is_empty():
		return
	closed.emit()
	SpiritsProgressionSystem.award_stars(_player_index, lead, 3.0)

func _lead() -> Dictionary:
	var t: Array = GameState.players[_player_index].team
	return t[0] if not t.is_empty() else {}

# DEV: give the lead a random event trait it doesn't have yet (2-trait cap
# enforced by EventsData.grant_trait).
func _trait_lead() -> void:
	var lead: Dictionary = _lead()
	if lead.is_empty():
		return
	var held: Array = lead.get("traits", [])
	var pool: Array = EventsData.TRAIT_DATA.keys().filter(func(k): return not held.has(k))
	if pool.is_empty():
		EventBus.log_entry.emit(_player_index, "dev: %s already has every trait!" % lead.get("name", "?"), "#7fe0d0")
		return
	var key: String = pool[randi() % pool.size()]
	EventBus.log_entry.emit(_player_index, "dev: " + EventsData.grant_trait(lead, key), "#7fe0d0")

func _all_badges() -> void:
	var b = GameState.players[_player_index].progress.badges
	for k in b.keys():
		b[k] = true
	EventBus.badge_earned.emit(_player_index, "DEV")

func _heal() -> void:
	for m in GameState.players[_player_index].team:
		m["current_hp"] = m.get("hp", 0)
