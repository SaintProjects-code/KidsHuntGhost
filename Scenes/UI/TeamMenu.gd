extends MenuWindow
## The party screen (TEAM button). present(player_index) fills it; emits
## stats_requested(spirit) for a card's Stats button. ▲▼ reorder the team
## (slot 1 leads); "Take charm" returns a charm to the hand.

signal stats_requested(spirit: Dictionary)

var _idx := -1
var _title: Label
var _cards_box: GridContainer

func _ready() -> void:
	var col := _init_window(680, 0)
	_title = _title_label("", 28)
	col.add_child(_title)
	var hint := UIKit.label("▲▼ reorder team · Stats to inspect · charms come from your hand", 15)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(1, 1, 1, 0.7)
	col.add_child(hint)
	_cards_box = GridContainer.new()   # 2 × 3: the team caps at 6
	_cards_box.columns = 2
	_cards_box.add_theme_constant_override("h_separation", 8)
	_cards_box.add_theme_constant_override("v_separation", 8)
	col.add_child(_cards_box)
	col.add_child(_button("Close", func(): UIManager.close_overlay()))
	hide()

func present(player_index: int) -> void:
	_idx = player_index
	_refresh()

func _player() -> PlayerData:
	return GameState.players[_idx]

func _refresh() -> void:
	_title.text = "%s's Spirits" % _player().player_name
	UIKit.clear(_cards_box)
	for i in _player().team.size():
		_cards_box.add_child(_make_card(i))

func _make_card(i: int) -> Control:
	var mon: Dictionary = _player().team[i]
	var card := UIKit.card_panel(Vector2(306, 104), Color(0.14, 0.12, 0.26, 0.9))
	var row := UIKit.hbox(8)
	card.add_child(row)
	row.add_child(UIKit.spirit_sprite(mon, Vector2(84, 84)))
	var info := UIKit.vbox(2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(info)
	info.add_child(UIKit.label("[%d] %s  %s" % [i + 1, mon["name"], SpiritsData.star_text(mon.get("stars", 0))], 16))
	var charm := String(mon.get("charm", ""))
	var sub := UIKit.label("✦%s · [%s]%s" % [SpiritsData.move_of(SpiritsData.move_key(mon))["name"], SpiritsData.type_text(mon),
		(" · " + CardsData.card_name(charm)) if charm != "" else ""], 13)
	sub.clip_text = true
	sub.modulate = Color(1, 1, 1, 0.75)
	info.add_child(sub)
	var hp := UIKit.hp_bar(10)
	UIKit.set_hp(hp, int(mon.get("current_hp", 0)), int(mon.get("hp", 1)))
	info.add_child(hp)
	info.add_child(UIKit.label("HP %d/%d  ATK:%d DEF:%d SPD:%d" % [mon.get("current_hp", 0), mon.get("hp", 0),
		mon.get("atk", 0), mon.get("def", 0), mon.get("spd", 0)], 13))
	var buttons := UIKit.hbox(4)
	info.add_child(buttons)
	buttons.add_child(UIKit.small_button("Stats", func(): stats_requested.emit(mon), 13))
	if charm != "":
		buttons.add_child(UIKit.small_button("Take charm", func():
			await CardSystem.take_charm(_idx, mon)
			_refresh(), 13))
	buttons.add_child(UIKit.small_button("▲", _move.bind(i, -1), 13))
	buttons.add_child(UIKit.small_button("▼", _move.bind(i, 1), 13))
	return card

func _move(i: int, dir: int) -> void:
	var team: Array = _player().team
	var j: int = i + dir
	if j < 0 or j >= team.size():
		return
	var tmp = team[i]
	team[i] = team[j]
	team[j] = tmp
	_refresh()
