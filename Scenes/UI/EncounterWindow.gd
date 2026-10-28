extends MenuWindow
## "A wild <spirit> appeared!" — Fight or Catch. present(spirit) / present_cpu
## (spirit, action); emits chose("fight" | "catch"). Keys: 1 = fight, 2 = catch.

signal chose(action: String)

var _title: Label
var _sprite: TextureRect
var _info: Label
var _fight_btn: Button
var _catch_btn: Button

func _ready() -> void:
	var col := _init_window(480, 400)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	_title = _title_label("", 24)
	col.add_child(_title)
	_sprite = UIKit.sprite(null, Vector2(120, 120))
	_sprite.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(_sprite)
	_info = UIKit.label("", 16)
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_info)
	var buttons := UIKit.hbox(16)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(buttons)
	_fight_btn = _button("", func(): chose.emit("fight"), 54)
	_fight_btn.custom_minimum_size.x = 170
	buttons.add_child(_fight_btn)
	_catch_btn = _button("", func(): chose.emit("catch"), 54)
	_catch_btn.custom_minimum_size.x = 170
	buttons.add_child(_catch_btn)
	hide()

func present(spirit: Dictionary) -> void:
	on_closed()   # stop any previous bob
	_title.text = "A wild %s appeared!" % spirit.get("name", "?")
	_sprite.texture = SpiritsData.sprite_tex(spirit.get("name", ""), "front")
	_info.text = "%s  ·  Stage %d  ·  HP %d  ·  ATK %d%s" % [SpiritsData.type_text(spirit), spirit.get("stage", 1),
		spirit.get("hp", 0), spirit.get("atk", 0), "  ·  🍬 lured" if spirit.get("_lured", false) else ""]
	for b in [_fight_btn, _catch_btn]:
		b.disabled = false
		b.modulate = Color.WHITE
	_fight_btn.text = "1 · ⚔ Fight"
	_catch_btn.text = "2 · 🫙 Catch"
	# the spirit drifts up and down while you decide
	var tw := _sprite.create_tween().set_loops()
	tw.tween_property(_sprite, "position:y", -6.0, 0.8).as_relative().set_trans(Tween.TRANS_SINE)
	tw.tween_property(_sprite, "position:y", 6.0, 0.8).as_relative().set_trans(Tween.TRANS_SINE)
	_sprite.set_meta("bob", tw)

# Spectator view of a CPU's decision: both buttons locked, the pick lit up.
func present_cpu(spirit: Dictionary, action: String) -> void:
	present(spirit)
	_fight_btn.disabled = true
	_catch_btn.disabled = true
	var pick: Button = _catch_btn if action == "catch" else _fight_btn
	pick.text = "▶ " + pick.text + " ◀"
	pick.modulate = Color(1.25, 1.15, 0.6)

func on_closed() -> void:
	if _sprite.has_meta("bob"):
		(_sprite.get_meta("bob") as Tween).kill()
		_sprite.remove_meta("bob")

func _unhandled_key_input(ev: InputEvent) -> void:
	if not visible or _fight_btn.disabled:
		return
	match Controls.number_pressed(ev):
		0:
			get_viewport().set_input_as_handled()
			chose.emit("fight")
		1:
			get_viewport().set_input_as_handled()
			chose.emit("catch")
