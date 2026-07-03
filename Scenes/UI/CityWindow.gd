extends MenuWindow
## City hub: challenge the gym, shop, take on the Elite Four, or leave.
## present(player_index, city_id); emits chose("gym"|"shop"|"elite"|"leave").

signal chose(action: String)

var _title: Label
var _buttons: VBoxContainer

func _ready() -> void:
	var col := _init_window(420, 360)
	_title = _title_label("City", 28)
	col.add_child(_title)
	_buttons = VBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 10)
	_buttons.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_buttons)
	hide()

func present(player_index: int, city_id: String) -> void:
	var p: PlayerData = GameState.players[player_index]
	var gym: Dictionary = GameData.gym_for_city(city_id)
	_title.text = gym.get("name", "City")
	for c in _buttons.get_children():
		c.queue_free()
	var badge: String = gym.get("badge", "")
	var has_badge: bool = p.progress.badges.get(badge, false)
	if not has_badge:
		_buttons.add_child(_button("⚔ Challenge Gym (%s)" % gym.get("type", ""), func(): chose.emit("gym")))
	else:
		var got := Label.new()
		got.text = "✓ %s Badge earned" % badge.capitalize()
		got.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		got.add_theme_color_override("font_color", Color("9fff9f"))
		_buttons.add_child(got)
	_buttons.add_child(_button("🛒 Shop", func(): chose.emit("shop")))
	_buttons.add_child(_button("💻 PC (spirit storage)", func(): chose.emit("pc")))
	if p.progress.has_all_badges():
		_buttons.add_child(_button("👑 Elite Four", func(): chose.emit("elite")))
	_buttons.add_child(_button("Leave", func(): chose.emit("leave")))
