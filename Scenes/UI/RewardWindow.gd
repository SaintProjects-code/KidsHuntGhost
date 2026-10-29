extends MenuWindow
## "You found…!" — shows a line of text and any cards won, flipping them in
## one by one. present(title, text, cards); emits closed(). Space/Enter = OK.

signal closed()

var _title: Label
var _text: Label
var _row: HBoxContainer

func _ready() -> void:
	var col := _init_window(440, 0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	_title = _title_label("", 26)
	col.add_child(_title)
	_text = UIKit.wrap_label("", 18, 400)
	col.add_child(_text)
	_row = UIKit.hbox(10)
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(_row)
	col.add_child(_button("OK", func(): closed.emit()))
	hide()

func present(title: String, text: String, cards: Array) -> void:
	_title.text = title
	_text.text = text
	UIKit.clear(_row)
	Sfx.play("pop")
	for i in cards.size():
		var cv := CardView.new(cards[i], Vector2(96, 128))
		cv.mouse_filter = Control.MOUSE_FILTER_PASS
		_row.add_child(cv)
		_flip_in(cv, 0.15 + i * 0.25)

# A card "flips" in: squashed flat, face-down colour, then springs open.
func _flip_in(cv: Control, delay: float) -> void:
	cv.modulate.a = 0.0
	await get_tree().create_timer(delay).timeout
	if not is_instance_valid(cv):
		return
	cv.pivot_offset = cv.size * 0.5
	cv.scale = Vector2(0.05, 1.0)
	cv.modulate.a = 1.0
	Sfx.play("draw")
	var tw := cv.create_tween()
	tw.tween_property(cv, "scale", Vector2(1.12, 1.12), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(cv, "scale", Vector2.ONE, 0.1)

func _unhandled_key_input(ev: InputEvent) -> void:
	if visible and Controls.confirm_pressed(ev):
		get_viewport().set_input_as_handled()
		closed.emit()
