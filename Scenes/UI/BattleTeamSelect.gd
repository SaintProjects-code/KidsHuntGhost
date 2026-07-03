extends MenuWindow
## "Choose Your Battle Team" — two columns like the classic select screen:
## YOUR TEAM (click rows to pick, up to 4; pick order = battle order) on the
## left, the enemy lineup on the right, and Lead/2nd/3rd/End slot chips at the
## bottom. Keys 1–6 also toggle picks.
## present(player, vs_label, opp_team); emits chosen(ordered_team)
## (empty array = backed out).

signal chosen(team: Array)

const MAX_PICK := 4
const SLOT_NAMES := ["Lead", "2nd", "3rd", "End"]
const ROW_BG := Color(0.08, 0.07, 0.16, 0.9)
const ROW_BG_SEL := Color(0.32, 0.25, 0.62, 0.95)

var _player: PlayerData
var _selected: Array = []          # indices into _player.team, in pick order
var _opp_team: Array = []
var _vs_lbl: Label
var _your_list: VBoxContainer
var _opp_list: VBoxContainer
var _slots_row: HBoxContainer
var _start: Button

func _ready() -> void:
	_build()
	hide()

func _build() -> void:
	# Sizes to content — rows are compact enough that a full 6-spirit team
	# and a 6-enemy lineup fit on screen with no scroll bars.
	var col := _init_window(880, 0)
	col.add_theme_constant_override("separation", 6)

	var title := _title_label("⚔ Choose Your Battle Team", 20)
	col.add_child(title)
	var hint := Label.new()
	hint.text = "Press 1–6 or click a Spirit to select  (up to %d)" % MAX_PICK
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	hint.modulate = Color(1, 1, 1, 0.7)
	col.add_child(hint)

	# column headers
	var heads := HBoxContainer.new()
	col.add_child(heads)
	var yours := Label.new()
	yours.text = "YOUR TEAM"
	yours.add_theme_font_size_override("font_size", 13)
	yours.add_theme_color_override("font_color", Color("8fff8f"))
	yours.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	yours.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heads.add_child(yours)
	_vs_lbl = Label.new()
	_vs_lbl.add_theme_font_size_override("font_size", 13)
	_vs_lbl.add_theme_color_override("font_color", Color("ffb45a"))
	_vs_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vs_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heads.add_child(_vs_lbl)

	# the two scrolling columns
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 14)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(split)
	_your_list = _scroll_column(split)
	_opp_list = _scroll_column(split)

	# slot chips: pick order = battle order
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
	cancel.pressed.connect(func(): chosen.emit([]))
	col.add_child(cancel)

func _scroll_column(parent: Control) -> VBoxContainer:
	# Plain column (no ScrollContainer): rows are sized so 6 always fit.
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(list)
	return list

func present(player: PlayerData, vs_label: String, opp_team: Array = []) -> void:
	_player = player
	_opp_team = opp_team
	_selected.clear()
	_vs_lbl.text = vs_label
	_refresh()

# 1–6 toggle picks while the window is visible.
func _input(event: InputEvent) -> void:
	if not visible or _player == null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var idx: int = event.keycode - KEY_1
		if idx >= 0 and idx < _player.team.size():
			_on_toggle(idx)
			get_viewport().set_input_as_handled()

func _refresh() -> void:
	for list in [_your_list, _opp_list]:
		for c in list.get_children():
			c.queue_free()
	for i in _player.team.size():
		_your_list.add_child(_your_row(i))
	for j in _opp_team.size():
		_opp_list.add_child(_opp_row(j))
	_refresh_slots()
	var n := _selected.size()
	_start.disabled = n == 0
	_start.text = "Start Battle (%d)" % n if n > 0 else "Select at least 1 Spirit…"

# ── your side: clickable rows ─────────────────────────────────────────────────

func _your_row(i: int) -> Control:
	var mon: Dictionary = _player.team[i]
	var order := _selected.find(i)
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 46)
	b.add_theme_stylebox_override("normal", _row_style(ROW_BG_SEL if order != -1 else ROW_BG, order != -1))
	b.add_theme_stylebox_override("hover", _row_style(ROW_BG_SEL if order != -1 else Color(0.14, 0.12, 0.26, 0.95), order != -1))
	b.add_theme_stylebox_override("pressed", _row_style(ROW_BG_SEL, true))
	b.pressed.connect(_on_toggle.bind(i))
	b.add_child(_row_content(i, mon, order))
	return b

func _row_content(i: int, mon: Dictionary, order: int) -> Control:
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
	name_lbl.text = "%s  %s" % [mon.get("name", "?"), SpiritsData.star_text(mon.get("stars", 0))]
	name_lbl.add_theme_font_size_override("font_size", 14)
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

# ── enemy side: read-only preview ─────────────────────────────────────────────

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

# ── slot chips (Lead / 2nd / 3rd / End) ───────────────────────────────────────

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

func _on_toggle(i: int) -> void:
	if _selected.has(i):
		_selected.erase(i)
	elif _selected.size() < MAX_PICK:
		_selected.append(i)
	_refresh()

func _on_start() -> void:
	if _selected.is_empty():
		return
	var team: Array = []
	for i in _selected:
		team.append(_player.team[i])
	chosen.emit(team)
