extends Control

const MIN_PLAYERS := 2
const MAX_PLAYERS := 4

# Token tint per player (applied to the shared player sprite).
const PLAYER_COLORS := [
	Color("ff5a5a"),  # Player 1 - red
	Color("5aa6ff"),  # Player 2 - blue
	Color("5ad26a"),  # Player 3 - green
	Color("ffd24d"),  # Player 4 - yellow
]

const PLAYER_SHEET := "res://Assets/Player/Male_Spritesheet.png"
const TOKEN_FRAME := Rect2(16, 0, 16, 16)  # front-facing frame

@onready var player_cards: HBoxContainer = $PlayerCards
@onready var add_button: Button = $AddPlayerCard
@onready var settings_panel: Panel = $SettingsPanel
@onready var map_option: OptionButton = $SettingsPanel/Margin/Settings/MapRow/MapOption
@onready var win_slider: HSlider = $SettingsPanel/Margin/Settings/WinRow/WinSlider
@onready var win_value: Label = $SettingsPanel/Margin/Settings/WinRow/WinValue
@onready var volume_slider: HSlider = $SettingsPanel/Margin/Settings/VolumeRow/VolumeSlider
@onready var volume_value: Label = $SettingsPanel/Margin/Settings/VolumeRow/VolumeValue

func _ready() -> void:
	MusicManager.play_menu()
	_setup_settings()
	settings_panel.hide()
	# The scene ships with one card; fill up to the minimum player count.
	while player_cards.get_child_count() < MIN_PLAYERS:
		_add_card()
	_relabel()

# ---------------- Player cards ----------------

func _on_add_player_pressed() -> void:
	if player_cards.get_child_count() < MAX_PLAYERS:
		_add_card()
		_relabel()

# Trainer (character) roster — each ties to a starter, a colour and a UNIQUE
# portrait (a sprite no NPC in the game uses). The card shows the trainer big
# with their starter tucked in the bottom corner.
const TRAINERS := [
	{ "name": "Ember",  "starter": "Charmander", "color": Color("ff7a3a"), "portrait": "alain" },
	{ "name": "Brooke", "starter": "Squirtle",   "color": Color("4aa3df"), "portrait": "adaman" },
	{ "name": "Ivy",    "starter": "Bulbasaur",  "color": Color("5ad26a"), "portrait": "akari" },
	{ "name": "Zap",    "starter": "Pikachu",    "color": Color("ffd24d"), "portrait": "acerola" },
	{ "name": "Rex",    "starter": "Machop",     "color": Color("e0563a"), "portrait": "alder" },
	{ "name": "Shade",  "starter": "Gastly",     "color": Color("8e6fd6"), "portrait": "allister" },
	{ "name": "Luna",   "starter": "Abra",       "color": Color("e86fb0"), "portrait": "amarys" },
]

func _add_card() -> void:
	var card := player_cards.get_child(0).duplicate()
	# Fresh card: drop any copied selection so it gets its own default.
	if card.has_meta("trainer_idx"):
		card.remove_meta("trainer_idx")
	player_cards.add_child(card)

func _relabel() -> void:
	# Keep card headers/placeholders/character in sync and lock add at the cap.
	for i in player_cards.get_child_count():
		var card := player_cards.get_child(i)
		var label := card.find_child("PlayerName", true, false) as Label
		if label:
			label.text = "Player %d" % (i + 1)
		var field := card.find_child("NameField", true, false) as LineEdit
		if field:
			field.placeholder_text = "Player %d" % (i + 1)
		_setup_card(card, i)
	add_button.disabled = player_cards.get_child_count() >= MAX_PLAYERS

# Wire the character button and show the chosen trainer's starter.
func _setup_card(card: Node, index: int) -> void:
	if not card.has_meta("trainer_idx"):
		card.set_meta("trainer_idx", index % TRAINERS.size())
	var btn := card.find_child("character selection", true, false) as Button
	if btn:
		# Re-bind cleanly each refresh so the press always targets THIS card.
		for con in btn.pressed.get_connections():
			btn.pressed.disconnect(con["callable"])
		btn.pressed.connect(_on_character_pressed.bind(card))
	_apply_trainer(card)

func _on_character_pressed(card: Node) -> void:
	var idx: int = (int(card.get_meta("trainer_idx", 0)) + 1) % TRAINERS.size()
	card.set_meta("trainer_idx", idx)
	_apply_trainer(card)

func _apply_trainer(card: Node) -> void:
	var trainer: Dictionary = TRAINERS[int(card.get_meta("trainer_idx", 0))]
	var icon := card.find_child("PlayerIcon", true, false) as TextureRect
	if icon:
		# the TRAINER front and centre…
		icon.texture = GameData.trainer_texture([trainer["portrait"]])
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.modulate = Color.WHITE
		# …with their starter tucked in the bottom-right corner
		var starter := icon.get_node_or_null("StarterIcon") as TextureRect
		if starter == null:
			starter = TextureRect.new()
			starter.name = "StarterIcon"
			starter.anchor_left = 1.0
			starter.anchor_top = 1.0
			starter.anchor_right = 1.0
			starter.anchor_bottom = 1.0
			starter.offset_left = -46
			starter.offset_top = -46
			starter.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			starter.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			starter.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			icon.add_child(starter)
		starter.texture = SpiritsData.sprite_tex(trainer["starter"], "front")
	var btn := card.find_child("character selection", true, false) as Button
	if btn:
		btn.text = "◀ %s ▶\n(%s)" % [trainer["name"], trainer["starter"]]

func _on_confirm_pressed() -> void:
	GameState.reset()
	for i in player_cards.get_child_count():
		var card := player_cards.get_child(i)
		var trainer: Dictionary = TRAINERS[int(card.get_meta("trainer_idx", 0))]
		var p := PlayerData.new()
		var field := card.find_child("NameField", true, false) as LineEdit
		var entered := field.text.strip_edges() if field else ""
		p.player_name = entered if entered != "" else String(trainer["name"])
		p.trainer_key = String(trainer["portrait"])
		var cpu := card.find_child("CPUButton", true, false) as Button
		p.is_cpu = cpu.button_pressed if cpu else false
		p.color = trainer["color"]
		p.team.append(SpiritsData.get_spirit(trainer["starter"]))
		GameState.players.append(p)
	get_tree().change_scene_to_file("res://Scenes/Board/Board.tscn")

# ---------------- Game settings ----------------

func _setup_settings() -> void:
	# Map dropdown.
	map_option.clear()
	for n in 3:
		map_option.add_item("Map %d" % (n + 1), n)
	map_option.select(clampi(GameState.active_map - 1, 0, 2))
	map_option.item_selected.connect(_on_map_selected)
	# Points to win.
	win_slider.min_value = 10
	win_slider.max_value = 50
	win_slider.step = 5
	win_slider.value = GameState.win_threshold
	win_slider.value_changed.connect(_on_win_changed)
	_on_win_changed(win_slider.value)
	# "No pts": points never win — only the E4 does. A compact toggle placed
	# INSIDE the win row, so it doesn't add a row that overflows the panel.
	var inf := CheckButton.new()
	inf.text = "No pts"
	inf.focus_mode = Control.FOCUS_NONE
	inf.custom_minimum_size = Vector2(96, 0)
	inf.button_pressed = GameState.infinite_points
	inf.toggled.connect(func(on: bool):
		GameState.infinite_points = on
		win_slider.editable = not on
		win_value.text = "∞" if on else "%d" % int(win_slider.value))
	win_slider.get_parent().add_child(inf)   # into the WinRow
	# apply the initial state (greys the slider out if already on)
	win_slider.editable = not GameState.infinite_points
	win_value.text = "∞" if GameState.infinite_points else "%d" % int(win_slider.value)
	# Sound volume (from the Master bus).
	volume_slider.min_value = 0
	volume_slider.max_value = 100
	volume_slider.step = 1
	volume_slider.value = round(db_to_linear(AudioServer.get_bus_volume_db(0)) * 100.0)
	volume_slider.value_changed.connect(_on_volume_changed)
	_on_volume_changed(volume_slider.value)

func _on_game_settings_pressed() -> void:
	settings_panel.visible = not settings_panel.visible

func _on_settings_done_pressed() -> void:
	settings_panel.hide()

func _on_map_selected(index: int) -> void:
	GameState.active_map = index + 1

func _on_win_changed(value: float) -> void:
	GameState.win_threshold = int(value)
	win_value.text = "%d" % int(value)

func _on_volume_changed(value: float) -> void:
	var pct := value / 100.0
	AudioServer.set_bus_mute(0, pct <= 0.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(pct, 0.0001)))
	volume_value.text = "%d%%" % int(value)
