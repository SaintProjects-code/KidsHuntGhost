extends MenuWindow
## "Choose Your Battle Team" — your spirits on the left, the enemy on the right.
##
## Single mode: present(player, vs_label, opp_team); emits chosen(team).
##   Click rows (or press 1–6) to pick up to 4 — pick order = battle order.
##   Space/Enter starts.
## PvP mode: present_pvp(player_a, player_b); emits chosen_pvp([team_a, team_b]).
##   BOTH columns are clickable so two players pick on one screen.
## An empty array = backed out.

signal chosen(team: Array)
signal chosen_pvp(teams: Array)

const SLOT_NAMES := ["Lead", "2nd", "3rd", "End"]
const ROW_BG := Color(0.08, 0.07, 0.16, 0.9)
const ROW_BG_SEL := Color(0.32, 0.25, 0.62, 0.95)

var _player: PlayerData
var _player_b: PlayerData      # PvP: the right-hand player
var _selected: Array = []      # indices into _player.team, in pick order
var _selected_b: Array = []
var _opp_team: Array = []
var _pvp := false

var _title_lbl: Label
var _hint_lbl: Label
var _your_head: Label
var _vs_lbl: Label
var _your_list: VBoxContainer
var _opp_list: VBoxContainer
var _slots_row: HBoxContainer
var _start: Button

func _ready() -> void:
	var col := _init_window(880, 0)
	col.add_theme_constant_override("separation", 6)
	_title_lbl = _title_label("⚔ Choose Your Battle Team", 20)
	col.add_child(_title_lbl)
	_hint_lbl = UIKit.label("", 12)
	_hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_lbl.modulate = Color(1, 1, 1, 0.7)
	col.add_child(_hint_lbl)
	var heads := HBoxContainer.new()
	col.add_child(heads)
	_your_head = _head(heads, Color("8fff8f"))
	_vs_lbl = _head(heads, Color("ffb45a"))
	var split := UIKit.hbox(14)
	col.add_child(split)
	_your_list = UIKit.vbox(4)
	_opp_list = UIKit.vbox(4)
	for l in [_your_list, _opp_list]:
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		split.add_child(l)
	_slots_row = UIKit.hbox(10)
	_slots_row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(_slots_row)
	_start = _button("", _on_start, 36)
	col.add_child(_start)
	var cancel := _button("Back out", _cancel, 24)
	cancel.add_theme_font_size_override("font_size", 13)
	col.add_child(cancel)
	hide()

func _head(parent: Control, color: Color) -> Label:
	var l := UIKit.label("", 13, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(l)
	return l

func present(player: PlayerData, vs_label: String, opp_team: Array = []) -> void:
	_pvp = false
	_player = player
	_opp_team = opp_team
	_selected.clear()
	_title_lbl.text = "⚔ Choose Your Battle Team"
	_hint_lbl.text = "Press 1–6 or click a spirit (up to %d) · Space to start" % Balance.BATTLE_PICK_MAX
	_your_head.text = "YOUR TEAM"
	_vs_lbl.text = vs_label
	_refresh()

func present_pvp(a: PlayerData, b: PlayerData) -> void:
	_pvp = true
	_player = a
	_player_b = b
	_selected.clear()
	_selected_b.clear()
	_title_lbl.text = "⚔ Pick Your Teams"
	_hint_lbl.text = "Both players — click your own spirits (up to %d each). %s can also use 1–6." % [
		Balance.BATTLE_PICK_MAX, a.player_name]
	_refresh()

func _unhandled_key_input(ev: InputEvent) -> void:
	if not visible or _player == null:
		return
	if Controls.confirm_pressed(ev) and not _start.disabled:
		get_viewport().set_input_as_handled()
		_on_start()
		return
	var n := Controls.number_pressed(ev)
	if n >= 0 and n < _player.team.size():
		get_viewport().set_input_as_handled()
		_on_toggle(n, 0)

func _refresh() -> void:
	UIKit.clear(_your_list)
	UIKit.clear(_opp_list)
	for i in _player.team.size():
		_your_list.add_child(_pick_row(i, 0))
	if _pvp:
		for j in _player_b.team.size():
			_opp_list.add_child(_pick_row(j, 1))
		_your_head.text = "%s  (%d/%d)" % [_player.player_name, _selected.size(), Balance.BATTLE_PICK_MAX]
		_vs_lbl.text = "%s  (%d/%d)" % [_player_b.player_name, _selected_b.size(), Balance.BATTLE_PICK_MAX]
		_start.disabled = _selected.is_empty() or _selected_b.is_empty()
		_start.text = "Start Battle (%d vs %d)" % [_selected.size(), _selected_b.size()] if not _start.disabled else "Both players pick a spirit…"
	else:
		for mon in _opp_team:
			var card := PanelContainer.new()
			card.add_theme_stylebox_override("panel", _row_style(ROW_BG, false))
			card.custom_minimum_size = Vector2(0, 46)
			card.add_child(_row_content("#%d" % (_opp_team.find(mon) + 1), mon, -1, false, true))
			_opp_list.add_child(card)
		_start.disabled = _selected.is_empty()
		_start.text = "Start Battle (%d) ⏎" % _selected.size() if not _start.disabled else "Select at least 1 spirit…"
	_slots_row.visible = not _pvp
	if not _pvp:
		_refresh_slots()

func _team_for(side: int) -> Array:
	return _player.team if side == 0 else _player_b.team

func _sel_for(side: int) -> Array:
	return _selected if side == 0 else _selected_b

func _pick_row(i: int, side: int) -> Control:
	var mon: Dictionary = _team_for(side)[i]
	var order: int = _sel_for(side).find(i)
	var fainted: bool = int(mon.get("current_hp", 0)) <= 0
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 46)
	b.add_theme_stylebox_override("normal", _row_style(ROW_BG_SEL if order != -1 else ROW_BG, order != -1))
	b.add_theme_stylebox_override("hover", _row_style(ROW_BG_SEL if order != -1 else Color(0.14, 0.12, 0.26, 0.95), order != -1))
	b.add_theme_stylebox_override("pressed", _row_style(ROW_BG_SEL, true))
	b.disabled = fainted   # fainted spirits can't fight until healed
	if fainted:
		b.modulate = Color(0.5, 0.5, 0.55, 0.8)
	else:
		b.pressed.connect(_on_toggle.bind(i, side))
	var content := _row_content("[%d]" % (i + 1), mon, order, fainted, false)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 8
	content.offset_right = -8
	b.add_child(content)
	UIKit.pass_through(content)
	return b

# number · sprite · name/stars · stat line · (slot marker)
func _row_content(num: String, mon: Dictionary, order: int, fainted: bool, enemy: bool) -> Control:
	var row := UIKit.hbox(8)
	var n := UIKit.label(num, 14)
	n.modulate = Color(1, 1, 1, 0.7)
	n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(n)
	row.add_child(UIKit.spirit_sprite(mon, Vector2(36, 36)))
	var info := UIKit.vbox(1)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(info)
	info.add_child(UIKit.label("%s  %s%s" % [mon["name"], SpiritsData.star_text(mon.get("stars", 0)),
		"   💀 FAINTED" if fainted else ""], 14, UIKit.BAD if fainted else null))
	var stat := UIKit.label("HP %d/%d   A%d D%d S%d   [%s] ✦%s%s" % [mon.get("current_hp", 0), mon.get("hp", 0),
		mon.get("atk", 0), mon.get("def", 0), mon.get("spd", 0), SpiritsData.type_text(mon),
		SpiritsData.move_of(SpiritsData.move_key(mon))["name"],
		("  " + CardsData.card_name(mon["charm"])) if mon.has("charm") else ""], 11, Color("ffb45a") if enemy else null)
	stat.modulate = Color(1, 1, 1, 0.8)
	info.add_child(stat)
	if order != -1:
		var slot := UIKit.label("◄ %s" % SLOT_NAMES[mini(order, SLOT_NAMES.size() - 1)], 14, UIKit.GOLD)
		slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(slot)
	return row

func _row_style(bg: Color, selected: bool) -> StyleBoxFlat:
	return UIKit.box(bg, 8, 2 if selected else 0, UIKit.GOLD, Vector2(6, 2))

func _refresh_slots() -> void:
	UIKit.clear(_slots_row)
	for s in Balance.BATTLE_PICK_MAX:
		var filled: bool = s < _selected.size()
		var chip := PanelContainer.new()
		chip.custom_minimum_size = Vector2(104, 36)
		chip.add_theme_stylebox_override("panel", _row_style(ROW_BG_SEL if filled else ROW_BG, filled))
		var vb := VBoxContainer.new()
		vb.alignment = BoxContainer.ALIGNMENT_CENTER
		chip.add_child(vb)
		for t in [[_player.team[_selected[s]]["name"] if filled else "○", 12], [SLOT_NAMES[s], 11]]:
			var l := UIKit.label(t[0], t[1])
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			vb.add_child(l)
		_slots_row.add_child(chip)

func _on_toggle(i: int, side: int) -> void:
	if int(_team_for(side)[i].get("current_hp", 0)) <= 0:
		return
	var sel: Array = _sel_for(side)
	if sel.has(i):
		sel.erase(i)
	elif sel.size() < Balance.BATTLE_PICK_MAX:
		sel.append(i)
	Sfx.play("pop")
	_refresh()

func _team_from(team: Array, sel: Array) -> Array:
	return sel.map(func(i): return team[i])

func _on_start() -> void:
	Sfx.play("click")
	if _pvp:
		if not (_selected.is_empty() or _selected_b.is_empty()):
			chosen_pvp.emit([_team_from(_player.team, _selected), _team_from(_player_b.team, _selected_b)])
	elif not _selected.is_empty():
		chosen.emit(_team_from(_player.team, _selected))

func _cancel() -> void:
	if _pvp:
		chosen_pvp.emit([])
	else:
		chosen.emit([])
