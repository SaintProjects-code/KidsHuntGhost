extends MenuWindow
## The PC storage box — only reachable from a town (CityWindow → "PC").
## Team holds at most 6 spirits; extras live here. Deposit moves a spirit
## from team → PC (the team always keeps at least one); Withdraw moves
## PC → team while there's room.
## present(player_index); emits closed().

signal closed()

const TEAM_MAX := 6

var _player: PlayerData
var _team_list: VBoxContainer
var _pc_list: VBoxContainer
var _team_head: Label
var _pc_head: Label

func _ready() -> void:
	var col := _init_window(680, 520)
	col.add_child(_title_label("💻 PC Storage", 26))

	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 12)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(split)
	var left := _column(split)
	_team_head = left.head
	_team_list = left.list
	var right := _column(split)
	_pc_head = right.head
	_pc_list = right.list

	col.add_child(_button("Close", func(): closed.emit()))
	hide()

func _column(parent: Control) -> Dictionary:
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 6)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(side)
	var head := Label.new()
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	side.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	return {"head": head, "list": list}

func present(player_index: int) -> void:
	_player = GameState.players[player_index]
	_refresh()

func _refresh() -> void:
	_team_head.text = "Team  (%d / %d)" % [_player.team.size(), TEAM_MAX]
	_pc_head.text = "PC Box  (%d)" % _player.pc.size()
	for list in [_team_list, _pc_list]:
		for c in list.get_children():
			c.queue_free()
	for mon in _player.team:
		_team_list.add_child(_row(mon, true))
	for mon in _player.pc:
		_pc_list.add_child(_row(mon, false))
	if _player.pc.is_empty():
		var empty := Label.new()
		empty.text = "— empty —"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.modulate = Color(1, 1, 1, 0.5)
		_pc_list.add_child(empty)

func _row(mon: Dictionary, in_team: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(28, 28)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.texture = SpiritsData.sprite_tex(mon.get("name", ""), "icon")
	row.add_child(icon)
	var lbl := Label.new()
	lbl.text = "%s  %s" % [mon.get("name", "?"), SpiritsData.star_text(mon.get("stars", 0))]
	lbl.clip_text = true
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	if in_team:
		var dep := _button("→ PC", _deposit.bind(mon), 32)
		dep.disabled = _player.team.size() <= 1   # never leave the team empty
		row.add_child(dep)
	else:
		var wd := _button("→ Team", _withdraw.bind(mon), 32)
		wd.disabled = _player.team.size() >= TEAM_MAX
		row.add_child(wd)
	return row

func _deposit(mon: Dictionary) -> void:
	if _player.team.size() <= 1:
		return
	_player.team.erase(mon)
	_player.pc.append(mon)
	_refresh()

func _withdraw(mon: Dictionary) -> void:
	if _player.team.size() >= TEAM_MAX:
		return
	_player.pc.erase(mon)
	_player.team.append(mon)
	_refresh()
