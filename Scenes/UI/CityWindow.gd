extends MenuWindow
## Town hub: challenge the gym, shop, the Spirit Box, set out on the Spectral
## Trail (3+ badges), or leave. present(player_index, city);
## emits chose("gym" | "shop" | "pc" | "trail" | "leave"). Keys 1–5 pick.

signal chose(action: String)

var _title: Label
var _buttons: VBoxContainer

func _ready() -> void:
	var col := _init_window(420, 360)
	_title = _title_label("Town", 28)
	col.add_child(_title)
	_buttons = UIKit.vbox(10)
	_buttons.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_buttons)
	hide()

func present(player_index: int, city: String) -> void:
	var p: PlayerData = GameState.players[player_index]
	var gym: Dictionary = GameData.gym_for_city(city)
	_title.text = gym.get("name", "Town")
	UIKit.clear(_buttons)
	var options: Array = []
	if not p.progress.badges.get(gym.get("badge", ""), false):
		options.append(["⚔ Challenge the Warden (%s)" % gym.get("type", ""), "gym"])
	else:
		var got := UIKit.label("✓ %s earned" % GameData.badge_name(gym["badge"]), 18, UIKit.GOOD)
		got.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_buttons.add_child(got)
	options.append(["🛒 Shop", "shop"])
	options.append(["📦 Spirit Box", "pc"])
	if p.progress.badge_count() >= Balance.FLY_BADGES:
		options.append(["🌫 Spectral Trail", "trail"])
	options.append(["Leave", "leave"])
	for i in options.size():
		var action: String = options[i][1]
		_buttons.add_child(_button("%d · %s" % [i + 1, options[i][0]], func(): chose.emit(action)))
	Juice.pop(panel, 1.04)

# Spectator view for a CPU's visit: same menu, every button locked.
func present_cpu(player_index: int, city: String) -> void:
	present(player_index, city)
	_title.text += "  (%s visits)" % GameState.players[player_index].player_name
	for c in _buttons.get_children():
		if c is Button:
			c.disabled = true

func _unhandled_key_input(ev: InputEvent) -> void:
	if not visible:
		return
	var buttons: Array = _buttons.get_children().filter(func(c): return c is Button and not c.disabled)
	var n := Controls.number_pressed(ev)
	if n >= 0 and n < buttons.size():
		get_viewport().set_input_as_handled()
		buttons[n].pressed.emit()
