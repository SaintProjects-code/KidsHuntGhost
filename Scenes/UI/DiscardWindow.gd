extends MenuWindow
## "Hand full!" — pick one card to throw away (the new card is one of the
## options). present(player, options); emits chose(key).

signal chose(key: String)

var _title: Label
var _row: HBoxContainer
var remote_owner := -1           # 📱 the player whose hand this is (Remote mirrors it to their phone)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var col := _init_window(640, 0)
	_title = _title_label("Hand full!", 24)
	col.add_child(_title)
	col.add_child(UIKit.wrap_label("You can hold %d cards. Click one to discard:" % Balance.HAND_SIZE, 15, 600))
	_row = UIKit.hbox(10)
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(_row)
	hide()

func present(p: PlayerData, options: Array) -> void:
	_title.text = "%s — hand full!" % p.player_name
	remote_owner = GameState.players.find(p)
	UIKit.clear(_row)
	for i in options.size():
		var key: String = options[i]
		var cv := CardView.new(key)
		if i == options.size() - 1:
			cv.armed = true   # the new arrival
		cv.pressed.connect(func():
			Sfx.play("whoosh")
			hide()
			chose.emit(key))
		_row.add_child(cv)
	show()
	Sfx.play("error")

func _unhandled_key_input(ev: InputEvent) -> void:
	if not visible:
		return
	var n := Controls.number_pressed(ev)
	if n >= 0 and n < _row.get_child_count():
		get_viewport().set_input_as_handled()
		(_row.get_child(n) as CardView).pressed.emit()
