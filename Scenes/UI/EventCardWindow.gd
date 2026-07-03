extends MenuWindow
## Shows an event card and an OK button. present(card); emits closed().

signal closed()

var _title: Label
var _desc: Label

func _ready() -> void:
	var col := _init_window(460, 240)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	_title = _title_label("Event", 26)
	# long titles wrap instead of stretching the window off screen
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.custom_minimum_size = Vector2(420, 0)
	col.add_child(_title)
	_desc = Label.new()
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# fixed width + wrap: the label grows DOWN as text gets longer, and the
	# window grows with it, so any card text always fits
	_desc.custom_minimum_size = Vector2(420, 0)
	col.add_child(_desc)
	col.add_child(_button("OK", func(): closed.emit()))
	hide()

func present(card: Dictionary) -> void:
	_title.text = card.get("title", "Event")
	_desc.text = card.get("desc", "")
