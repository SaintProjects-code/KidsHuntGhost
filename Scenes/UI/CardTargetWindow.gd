extends MenuWindow
## Pick which spirit a field card goes on. Spirits the card can't
## affect (full HP for a tonic, awake for a Wake Bell…) are greyed out.
## present(player, card_key); emits chose(spirit Dictionary, or null on cancel).

signal chose(target)

var _title: Label
var _grid: GridContainer
var remote_owner := -1           # 📱 whose card this is: their phone picks the spirit

func _ready() -> void:
	var col := _init_window(640, 0)
	_title = _title_label("Use on…", 24)
	col.add_child(_title)
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	col.add_child(_grid)
	col.add_child(_button("Cancel", func(): chose.emit(null), 38))
	hide()

func present(p: PlayerData, key: String) -> void:
	_title.text = "%s — on which spirit?" % CardsData.card_name(key)
	remote_owner = GameState.players.find(p)
	UIKit.clear(_grid)
	for i in p.team.size():
		_grid.add_child(_spirit_row(p.team[i], key, i))

func _spirit_row(mon: Dictionary, key: String, i: int) -> Control:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(300, 64)
	b.disabled = not CardSystem.can_target(key, mon)
	b.pressed.connect(func(): chose.emit(mon))
	b.set_meta("phone_spirit", mon)
	var row := UIKit.hbox(8)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 8
	b.add_child(row)
	row.add_child(UIKit.spirit_sprite(mon, Vector2(44, 44)))
	var info := UIKit.vbox(2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(info)
	info.add_child(UIKit.label("[%d] %s  %d/%d" % [i + 1, mon["name"], mon["current_hp"], mon["hp"]], 14))
	var bar := UIKit.hp_bar(8)
	UIKit.set_hp(bar, int(mon["current_hp"]), int(mon["hp"]))
	info.add_child(bar)
	UIKit.pass_through(row)
	return b

func _unhandled_key_input(ev: InputEvent) -> void:
	if not visible:
		return
	var n := Controls.number_pressed(ev)
	if n >= 0 and n < _grid.get_child_count() and not (_grid.get_child(n) as Button).disabled:
		get_viewport().set_input_as_handled()
		(_grid.get_child(n) as Button).pressed.emit()
	elif ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
		chose.emit(null)
