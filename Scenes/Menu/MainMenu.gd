extends Control
## Title screen: one menu — Continue (only when a saved game exists), New Game,
## Settings (sound) and How to Play. The scene's older button groups
## (Start → Adventure / Multiplayer → Local / Online) all led to the same setup
## screen, so they're hidden and this menu is built in code instead.

const DEV_TRAINERS := [
	{"name": "Ember", "starter": "Cinderwisp", "color": Color("ff7a3a"), "portrait": "alain"},
	{"name": "Brooke", "starter": "Puddleboo", "color": Color("4aa3df"), "portrait": "adaman"},
	{"name": "Ivy", "starter": "Mossprig", "color": Color("5ad26a"), "portrait": "akari"},
]

const HOW_TO_PLAY := [
	["🎲 Your turn", "Roll and walk the road. At a fork, pick a way. Land on a tile and something happens."],
	["👻 Ghost tiles", "Pink, green and red tiles hide weak, medium and strong spirits. Roll Lantern dice to catch one — or fight it 1v1 first."],
	["❓ Other tiles", "Event: a surprise choice.  Item: a free card.  Comp: a minigame for everyone.  Clash: battle another player."],
	["🏘 Towns", "Rest to heal, shop for cards, swap spirits in the Spirit Box, and beat the Warden for a badge."],
	["🌫 Spectral Trail", "With enough badges, take on the Haunted Four — and maybe the Spirit Lord."],
	["🏆 Winning", "First to the points target wins (catch +1, Warden +4, Clash +3, Haunted Four +5, Spirit Lord +10). Two Haunted Four wins in a row also wins."],
]

var _settings_win: MenuWindow
var _rules_win: MenuWindow
var _volume_value: Label

func _ready() -> void:
	MusicManager.play_menu()
	for old in ["StartingScreenButton", "MainMenuButton", "MultiplayerMenuButton"]:
		get_node(old).hide()
	var dev: Button = $DevButton
	dev.text = "⚡ Dev"
	UIKit.style_button(dev, "secondary", "s")
	_build_menu()
	_build_settings()
	_build_rules()

func _build_menu() -> void:
	var col := UIKit.vbox(14)
	col.custom_minimum_size.x = 320
	col.anchor_left = 0.5
	col.anchor_right = 0.5
	col.anchor_top = 0.5
	col.anchor_bottom = 0.5
	col.offset_left = -160
	col.offset_right = 160
	col.offset_top = 0
	col.grow_vertical = Control.GROW_DIRECTION_END
	add_child(col)
	if SaveManager.has_save():
		col.add_child(_menu_button("▶ Continue", "gold", "l", _on_continue_pressed))
	col.add_child(_menu_button("✦ New Game", "gold" if not SaveManager.has_save() else "primary", "l", _start_setup))
	col.add_child(_menu_button("⚙ Settings", "secondary", "m", func(): _settings_win.show()))
	col.add_child(_menu_button("📖 How to Play", "secondary", "m", func(): _rules_win.show()))

func _menu_button(text: String, kind: String, size: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	UIKit.style_button(b, kind, size)
	b.pressed.connect(func():
		Sfx.play("click")
		cb.call())
	return b

# A centred pop-up with a title; returns [window, column].
func _window(width: float, title: String) -> Array:
	var win := MenuWindow.new()
	add_child(win)
	var col: VBoxContainer = win._init_window(width)
	var head := UIKit.label(title, 26, UIKit.GOLD)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(head)
	win.hide()
	return [win, col]

func _done(win: Control) -> Button:
	var b := _menu_button("Done", "primary", "m", func(): win.hide())
	b.custom_minimum_size.x = 180
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return b

func _build_settings() -> void:
	var made := _window(460, "⚙ Settings")
	_settings_win = made[0]
	var col: VBoxContainer = made[1]
	var row := UIKit.hbox(12)
	col.add_child(row)
	var l := UIKit.label("Sound", 18)
	l.custom_minimum_size.x = 90
	row.add_child(l)
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 1
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value = round(db_to_linear(AudioServer.get_bus_volume_db(0)) * 100.0)
	row.add_child(slider)
	_volume_value = UIKit.label("", 18)
	_volume_value.custom_minimum_size.x = 56
	_volume_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_volume_value)
	slider.value_changed.connect(_on_volume_changed)
	_on_volume_changed(slider.value)
	var note := UIKit.label("Map, battles, points and the Haunted Four are set when you start a New Game.", 13, Color(1, 1, 1, 0.65))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 420
	col.add_child(note)
	col.add_child(_done(_settings_win))

func _on_volume_changed(value: float) -> void:
	var pct := value / 100.0
	AudioServer.set_bus_mute(0, pct <= 0.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(pct, 0.0001)))
	_volume_value.text = "%d%%" % int(value)

func _build_rules() -> void:
	var made := _window(640, "📖 How to Play")
	_rules_win = made[0]
	var col: VBoxContainer = made[1]
	for entry in HOW_TO_PLAY:
		var head := UIKit.label(entry[0], 18, UIKit.GOLD)
		col.add_child(head)
		var body := UIKit.label(entry[1], 15)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size.x = 600
		col.add_child(body)
	col.add_child(_done(_rules_win))

func _start_setup() -> void:
	get_tree().change_scene_to_file("res://Scenes/Menu/SetupScreen.tscn")

func _on_continue_pressed() -> void:
	if SaveManager.load_game():
		get_tree().change_scene_to_file("res://Scenes/Board/Board.tscn")
	else:
		Sfx.play("error")

# The scene still wires these older buttons; they're hidden now.
func _on_start_game_pressed() -> void:
	_start_setup()

func _on_adventure_mode_pressed() -> void:
	_start_setup()

func _on_multiplayer_pressed() -> void:
	_start_setup()

func _on_setting_pressed() -> void:
	_settings_win.show()

func _on_online_pressed() -> void:
	_start_setup()

func _on_local_pressed() -> void:
	_start_setup()

# DEV shortcut: skips setup — 3 players with full teams, Lanterns, gold
# and cards, and dev_mode on (the only thing that shows the in-game DEV button).
func _on_dev_pressed() -> void:
	GameState.reset()
	GameState.dev_mode = true
	for t in DEV_TRAINERS:
		var p := PlayerData.new()
		p.player_name = t["name"]
		p.trainer_key = t["portrait"]
		p.color = t["color"]
		p.team.append(SpiritsData.get_spirit(t["starter"]))
		for i in 3:
			p.team.append(SpiritsData.random_spirit(1))
		for i in 2:
			p.team.append(SpiritsData.random_spirit(2))
		p.inventory.gold = 200
		p.inventory.hand = ["spirit_lantern", "spirit_lantern", "grand_lantern", "ecto_patch", "spirit_shield",
			"glow_tonic", "boo"]
		GameState.players.append(p)
	get_tree().change_scene_to_file("res://Scenes/Board/Board.tscn")
