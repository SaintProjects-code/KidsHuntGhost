extends MenuWindow
## "Choose Your Battle Team" — two columns like the classic select screen.
##
## Single mode:  present(player, vs_label, opp_team); emits chosen(team).
##   Left = YOUR TEAM (click rows to pick, up to 4; pick order = battle order),
##   right = the enemy lineup (read-only). Keys 1–6 also toggle picks.
##
## PvP mode:  present_pvp(player_a, player_b); emits chosen_pvp([team_a, team_b]).
##   BOTH columns are clickable — the two players pick their teams at the same
##   time on one screen, then a shared Start begins the fight.
##
## (An empty array = backed out.)

signal chosen(team: Array)
signal chosen_pvp(teams: Array)

const MAX_PICK := 4
const SLOT_NAMES := ["Lead", "2nd", "3rd", "End"]
const ROW_BG := Color(0.08, 0.07, 0.16, 0.9)
const ROW_BG_SEL := Color(0.32, 0.25, 0.62, 0.95)

var _player: PlayerData
var _selected: Array = []          # indices into _player.team, in pick order
var _opp_team: Array = []
var _pvp: bool = false
var _player_b: PlayerData          # PvP: the right-hand player
var _selected_b: Array = []        # PvP: indices into _player_b.team

var _title_lbl: Label
var _hint_lbl: Label
var _your_head: Label
var _vs_lbl: Label
var _your_list: VBoxContainer
var _opp_list: VBoxContainer
var _slots_row: HBoxContainer
var _start: Button

func _ready() -> void:
	_build()
	hide()

func _build() -> void:
	var col := _init_window(880, 0)
	col.add_theme_constant_override("separation", 6)

	_title_lbl = _title_label("⚔ Choose Your Battle Team", 20)
	col.add_child(_title_lbl)
	_hint_lbl = Label.new()
	_hint_lbl.text = "Press 1–6 or click a Spirit to select  (up to %d)" % MAX_PICK
	_hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_lbl.add_theme_font_size_override("font_size", 12)
	_hint_lbl.modulate = Color(1, 1, 1, 0.7)
	col.add_child(_hint_lbl)

	# column headers
	var heads := HBoxContainer.new()
	col.add_child(heads)
	_your_head = Label.new()
	_your_head.text = "YOUR TEAM"
	_your_head.add_theme_font_size_override("font_size", 13)
	_your_head.add_theme_color_override("font_color", Color("8fff8f"))
	_your_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_your_head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heads.add_child(_your_head)
	_vs_lbl = Label.new()
	_vs_lbl.add_theme_font_size_override("font_size", 13)
	_vs_lbl.add_theme_color_override("font_color", Color("ffb45a"))
	_vs_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vs_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heads.add_child(_vs_lbl)

	# the two columns
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 14)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(split)
	_your_list = _scroll_column(split)
	_opp_list = _scroll_column(split)

	# slot chips: pick order = battle order (single mode only)
	_slots_row = HBoxContainer.new()
	_slots_row.add_theme_constant_override("separation", 10)
	_slots_row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(_slots_row)

	_start = Button.new()
	_start.focus_mode = Control.FOCUS_NONE
	_start.custom_minimum_size = Vector2(0, 36)
	_start.pressed.connect(_on_start)
	col.add_child(_start)

	var cancel := Button.new()
	cancel.text = "Back out"
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.custom_minimum_size = Vector2(0, 24)
	cancel.add_theme_font_size_override("font_size", 13)
	cancel.pressed.connect(_cancel)
	col.add_child(cancel)

func _scroll_column(parent: Control) -> VBoxContainer:
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(list)
	return list

func present(player: PlayerData, vs_label: String, opp_team: Array = []) -> void:
	_pvp = false
	_player = player
	_opp_team = opp_team
	_selected.clear()
	_title_lbl.text = "⚔ Choose Your Battle Team"
	_hint_lbl.text = "Press 1–6 or click a Spirit to select  (up to %d)" % MAX_PICK
	_your_head.text = "YOUR TEAM"
	_vs_lbl.text = vs_label
	_refresh()

# PvP: both players pick their own team at the same time (both columns clickable).
func present_pvp(a: PlayerData, b: PlayerData) -> void:
	_pvp = true
	_player = a
	_player_b = b
	_selected.clear()
	_selected_b.clear()
	_title_lbl.text = "⚔ Pick Your Teams"
	_hint_lbl.text = "Both players — click your own Spirits  (up to %d each)" % MAX_PICK
	_refresh()

# 1–6 toggle picks (single mode only — ambiguous with two players).
func _input(event: InputEvent) -> void:
	if _pvp or not visible or _player == null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var idx: int = event.keycode - KEY_1
		if idx >= 0 and idx < _player.team.size():
			_on_toggle(idx, 0)
			get_viewport().set_input_as_handled()

func _refresh() -> void:
	for list in [_your_list, _opp_list]:
		for c in list.get_children():
			c.queue_free()
	for i in _player.team.size():
		_your_list.add_child(_pick_row(i, 0))
	if _pvp:
		for j in _player_b.team.size():
			_opp_list.add_child(_pick_row(j, 1))
		_your_head.text = "%s  (%d/%d)" % [_player.player_name, _selected.size(), MAX_PICK]
		_vs_lbl.text = "%s  (%d/%d)" % [_player_b.player_name, _selected_b.size(), MAX_PICK]
	else:
		for j in _opp_team.size():
			_opp_list.add_child(_opp_row(j))
	_slots_row.visible = not _pvp
	if not _pvp:
		_refresh_slots()
	if _pvp:
		_start.disabled = _selected.is_empty() or _selected_b.is_empty()
		_start.text = "Start Battle (%d vs %d)" % [_selected.size(), _selected_b.size()] if not _start.disabled else "Both players pick a Spirit…"
	else:
		var n := _selected.size()
		_start.disabled = n == 0
		_start.text = "Start Battle (%d)" % n if n > 0 else "Select at least 1 Spirit…"

# ── clickable team rows (works for either side) ───────────────────────────────

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
	# fainted spirits can't fight — greyed out and unclickable until healed
	b.disabled = fainted
	if fainted:
		b.modulate = Color(0.5, 0.5, 0.55, 0.8)
	else:
		b.pressed.connect(_on_toggle.bind(i, side))
	b.add_child(_row_content(i, mon, order, fainted))
	return b

func _row_content(i: int, mon: Dictionary, order: int, fainted: bool = false) -> Control:
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 8
	row.offset_right = -8
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pass_through(row)

	var num := Label.new()
	num.text = "[%d]" % (i + 1)
	num.add_theme_font_size_override("font_size", 14)
	num.modulate = Color(1, 1, 1, 0.7)
	num.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(num)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(36, 36)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.texture = SpiritsData.sprite_tex(mon.get("name", ""), "front")
	row.add_child(icon)

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 1)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(info)
	var name_lbl := Label.new()
	name_lbl.text = "%s  %s%s" % [mon.get("name", "?"), SpiritsData.star_text(mon.get("stars", 0)),
		"   💀 FAINTED" if fainted else ""]
	name_lbl.add_theme_font_size_override("font_size", 14)
	if fainted:
		name_lbl.add_theme_color_override("font_color", Color("ff9f9f"))
	info.add_child(name_lbl)
	var stat := Label.new()
	stat.text = "HP %d/%d   ATK:%d  SPD:%d   [%s]" % [
		mon.get("current_hp", 0), mon.get("hp", 0),
		mon.get("atk", 0), mon.get("spd", 0), mon.get("type", "")]
	stat.add_theme_font_size_override("font_size", 11)
	stat.modulate = Color(1, 1, 1, 0.75)
	info.add_child(stat)

	if order != -1:
		var slot := Label.new()
		slot.text = "◄ %s" % SLOT_NAMES[min(order, SLOT_NAMES.size() - 1)]
		slot.add_theme_font_size_override("font_size", 14)
		slot.add_theme_color_override("font_color", Color("ffd24d"))
		slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(slot)
	_pass_through(row)
	return row

# Buttons need their child controls to ignore the mouse so clicks land.
func _pass_through(node: Control) -> void:
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in node.get_children():
		if c is Control:
			_pass_through(c)

# ── enemy side: read-only preview (single mode) ───────────────────────────────

func _opp_row(j: int) -> Control:
	var mon: Dictionary = _opp_team[j]
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _row_style(ROW_BG, false))
	card.custom_minimum_size = Vector2(0, 46)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	card.add_child(row)
	var num := Label.new()
	num.text = "#%d" % (j + 1)
	num.add_theme_font_size_override("font_size", 14)
	num.modulate = Color(1, 1, 1, 0.7)
	num.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(num)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(36, 36)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.texture = SpiritsData.sprite_tex(mon.get("name", ""), "front")
	row.add_child(icon)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 1)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(info)
	var name_lbl := Label.new()
	name_lbl.text = str(mon.get("name", "?"))
	name_lbl.add_theme_font_size_override("font_size", 14)
	info.add_child(name_lbl)
	var stat := Label.new()
	stat.text = "HP:%d  ATK:%d  [%s]" % [mon.get("hp", 0), mon.get("atk", 0), mon.get("type", "")]
	stat.add_theme_font_size_override("font_size", 11)
	stat.add_theme_color_override("font_color", Color("ffb45a"))
	info.add_child(stat)
	return card

func _row_style(bg: Color, selected: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	if selected:
		sb.border_width_left = 2
		sb.border_width_top = 2
		sb.border_width_right = 2
		sb.border_width_bottom = 2
		sb.border_color = Color("ffd24d")
	return sb

# ── slot chips (Lead / 2nd / 3rd / End) — single mode only ────────────────────

func _refresh_slots() -> void:
	for c in _slots_row.get_children():
		c.queue_free()
	for s in MAX_PICK:
		var chip := PanelContainer.new()
		chip.custom_minimum_size = Vector2(104, 36)
		var filled: bool = s < _selected.size()
		chip.add_theme_stylebox_override("panel", _row_style(ROW_BG_SEL if filled else ROW_BG, filled))
		var vb := VBoxContainer.new()
		vb.alignment = BoxContainer.ALIGNMENT_CENTER
		chip.add_child(vb)
		var who := Label.new()
		who.text = _player.team[_selected[s]].get("name", "?") if filled else "○"
		who.add_theme_font_size_override("font_size", 12)
		who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(who)
		var slot := Label.new()
		slot.text = SLOT_NAMES[s]
		slot.add_theme_font_size_override("font_size", 11)
		slot.modulate = Color(1, 1, 1, 0.65)
		slot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(slot)
		_slots_row.add_child(chip)

# ── selection ─────────────────────────────────────────────────────────────────

func _on_toggle(i: int, side: int) -> void:
	if int(_team_for(side)[i].get("current_hp", 0)) <= 0:
		return   # fainted spirits can't be picked
	var sel: Array = _sel_for(side)
	if sel.has(i):
		sel.erase(i)
	elif sel.size() < MAX_PICK:
		sel.append(i)
	_refresh()

func _team_from(team: Array, sel: Array) -> Array:
	var out: Array = []
	for i in sel:
		out.append(team[i])
	return out

func _on_start() -> void:
	if _pvp:
		if _selected.is_empty() or _selected_b.is_empty():
			return
		chosen_pvp.emit([_team_from(_player.team, _selected), _team_from(_player_b.team, _selected_b)])
	else:
		if _selected.is_empty():
			return
		chosen.emit(_team_from(_player.team, _selected))

func _cancel() -> void:
	if _pvp:
		chosen_pvp.emit([])
	else:
		chosen.emit([])
