extends Control
## Pick 2–4 players: name, trainer (each comes with its own starter), CPU or
## human, plus the game settings (map, points to win, volume).
## 📱 Phones: start hosting a room (see Remote); every phone that joins takes a
## human player card and can flip through trainers from the phone.

const MIN_PLAYERS := 2
const MAX_PLAYERS := 4

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
	for spec in [[add_button, "+ Add Player", "secondary", "m"], [$GameSettings, "⚙ Game Settings", "secondary", "m"],
			[$ConfirmButton, "▶ Start Game", "gold", "l"], [$SettingsPanel/Margin/Settings/DoneButton, "Done", "primary", "m"]]:
		spec[0].text = spec[1]
		UIKit.style_button(spec[0], spec[2], spec[3])
	_setup_settings()
	settings_panel.hide()
	_build_phones_panel()
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
	{ "name": "Ember",  "starter": "Cinderwisp", "color": Color("ff7a3a"), "portrait": "alain" },
	{ "name": "Brooke", "starter": "Puddleboo",  "color": Color("4aa3df"), "portrait": "adaman" },
	{ "name": "Ivy",    "starter": "Mossprig",   "color": Color("5ad26a"), "portrait": "akari" },
	{ "name": "Zap",    "starter": "Zapkin",     "color": Color("ffd24d"), "portrait": "acerola" },
	{ "name": "Rex",    "starter": "Brawlboo",   "color": Color("e0563a"), "portrait": "alder" },
	{ "name": "Shade",  "starter": "Wispy",      "color": Color("8e6fd6"), "portrait": "allister" },
	{ "name": "Luna",   "starter": "Dreamwisp",  "color": Color("e86fb0"), "portrait": "amarys" },
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
		UIKit.style_button(btn, "secondary", "m")
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
	SaveManager.delete_save()   # a new game replaces the old save
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
		p.remote_id = String(card.get_meta("remote_id", ""))
		p.team.append(SpiritsData.get_spirit(trainer["starter"]))
		GameState.players.append(p)
	get_tree().change_scene_to_file("res://Scenes/Board/Board.tscn")

# ---------------- Game settings ----------------

func _setup_settings() -> void:
	# Map dropdown.
	map_option.clear()
	for n in GameData.MAPS:
		map_option.add_item("%d · %s" % [n, GameData.MAPS[n]["name"]], n - 1)
	map_option.select(clampi(GameState.active_map - 1, 0, GameData.MAPS.size() - 1))
	map_option.tooltip_text = GameData.map_info(GameState.active_map)["blurb"]
	map_option.item_selected.connect(_on_map_selected)
	# Points to win.
	win_slider.min_value = 10
	win_slider.max_value = 50
	win_slider.step = 5
	win_slider.value = GameState.win_threshold
	win_slider.value_changed.connect(_on_win_changed)
	_on_win_changed(win_slider.value)
	# "No pts": points never win — beat 2 of the Haunted Four in a row, then
	# the Spirit Lord. A compact toggle placed
	# INSIDE the win row, so it doesn't add a row that overflows the panel.
	var inf := CheckButton.new()
	inf.text = "No pts"
	inf.focus_mode = Control.FOCUS_NONE
	inf.custom_minimum_size = Vector2(96, 0)
	inf.tooltip_text = "Points can't win: beat 2 of the Haunted Four in a row, then defeat Spirit Lord Vesper"
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
	var info: Dictionary = GameData.map_info(GameState.active_map)
	map_option.tooltip_text = info["blurb"]
	win_slider.value = int(info["target"])   # each board has its own sensible target

func _on_win_changed(value: float) -> void:
	GameState.win_threshold = int(value)
	win_value.text = "%d" % int(value)

func _on_volume_changed(value: float) -> void:
	var pct := value / 100.0
	AudioServer.set_bus_mute(0, pct <= 0.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(pct, 0.0001)))
	volume_value.text = "%d%%" % int(value)

# ---------------- 📱 Phones ----------------
# The 📱 Phones panel hosts a room (on this computer, or an online server for
# internet play). Each phone that joins takes a human player card — the name
# typed on the phone fills the card, a 📱 tag under it shows the phone is
# linked, and the phone can flip through trainers itself.

var _phones_panel: PanelContainer
var _url_field: LineEdit
var _phone_status: Label
var _phone_steps: Label
var _phone_list: Label
var _phone_chip: Label           # "📱 Room KXRT · 2 phones" beside the Phones button

func _build_phones_panel() -> void:
	var back := Button.new()
	back.text = "◀ Back"
	back.position = Vector2(16, 16)
	back.size = Vector2(110, 36)
	UIKit.style_button(back, "secondary", "m")
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://Scenes/Menu/MainMenu.tscn"))
	add_child(back)
	var open_btn := Button.new()
	open_btn.text = "📱 Phones"
	open_btn.position = Vector2(340, 583)
	open_btn.size = Vector2(200, 36)
	UIKit.style_button(open_btn, "secondary", "m")
	add_child(open_btn)
	_phone_chip = UIKit.label("", 14, UIKit.GOLD)
	_phone_chip.position = Vector2(548, 591)
	add_child(_phone_chip)

	_phones_panel = PanelContainer.new()
	_phones_panel.add_theme_stylebox_override("panel", UIKit.box(Color(UIKit.NIGHT, 0.97), 14, 2, UIKit.GOLD, Vector2(18, 14)))
	_phones_panel.position = Vector2(226, 40)
	_phones_panel.custom_minimum_size = Vector2(700, 0)
	add_child(_phones_panel)
	var col := UIKit.vbox(10)
	_phones_panel.add_child(col)
	col.add_child(UIKit.label("📱 Play with phones", 24, UIKit.GOLD))
	var local := Button.new()
	local.text = "📶 Start on this computer  (phones on the same Wi-Fi)"
	UIKit.style_button(local, "gold", "l")
	local.pressed.connect(func(): Remote.start_local())
	col.add_child(local)
	_phone_status = UIKit.label("", 30, UIKit.GOLD)
	_phone_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_phone_status)
	_phone_steps = UIKit.wrap_label("", 16, 660)
	col.add_child(_phone_steps)
	_phone_list = UIKit.wrap_label("", 16, 660)
	col.add_child(_phone_list)
	var row := UIKit.hbox(8)
	col.add_child(row)
	row.add_child(UIKit.label("Online server:", 13))
	_url_field = LineEdit.new()
	_url_field.text = Remote.url
	_url_field.custom_minimum_size = Vector2(300, 32)
	_url_field.tooltip_text = "For playing over the internet: your server's address, e.g. wss://yourdomain.com/ws"
	row.add_child(_url_field)
	row.add_child(UIKit.small_button("Connect", func(): Remote.start(_url_field.text)))
	row.add_child(UIKit.small_button("Stop", func(): Remote.stop()))
	var done := Button.new()
	done.text = "Done"
	UIKit.style_button(done, "primary", "m")
	done.pressed.connect(func(): _phones_panel.hide())
	col.add_child(done)
	_phones_panel.hide()
	open_btn.pressed.connect(func(): _phones_panel.visible = not _phones_panel.visible)
	Remote.room_changed.connect(func(_c): _refresh_phones())
	Remote.phones_changed.connect(_on_phones_changed)
	Remote.lobby_view = _phone_lobby_view
	_on_phones_changed()

func _process(_delta: float) -> void:
	_refresh_phones()   # cheap: a few labels

func _refresh_phones() -> void:
	if _phone_status == null:
		return
	var online := Remote.phones.keys().filter(func(id): return Remote.phones[id]["online"]).size()
	_phone_chip.text = ("Room %s · %d phone%s" % [Remote.code, online, "" if online == 1 else "s"]) if Remote.code != "" else ""
	if Remote.code != "":
		_phone_status.text = "Room code:  %s" % Remote.code
		_phone_steps.text = "1.  On each phone open:   %s\n2.  Type the code  %s  and your name, then tap Join!" % [
			Remote.phone_url(), Remote.code]
		if Remote.is_local():
			_phone_steps.text += "\n(If Windows asks, ALLOW Godot on private networks. Phones must be on this Wi-Fi.)"
	else:
		_phone_status.text = "" if Remote.status_text() == "off" else "Phones: %s" % Remote.status_text()
		_phone_steps.text = "Press the gold button, then follow the steps that appear here."
	var lines: Array = []
	for id in Remote.phones:
		var card := _card_of(id)
		var where := "no free seat (4 players max)"
		if card:
			var trainer: Dictionary = TRAINERS[int(card.get_meta("trainer_idx", 0))]
			where = "Player %d · %s" % [card.get_index() + 1, trainer["name"]]
		lines.append("%s  %s  →  %s" % ["🟢" if Remote.phones[id]["online"] else "⚪ (left)", Remote.phones[id]["name"], where])
	_phone_list.text = "Connected:\n" + "\n".join(lines) if not lines.is_empty() else ""
	_update_phone_tags()

# A "📱 Ivy's phone" line on every card a phone controls.
func _update_phone_tags() -> void:
	for card in player_cards.get_children():
		var body := card.find_child("Body", true, false)
		if body == null:
			continue
		var tag := body.get_node_or_null("PhoneTag") as Label
		var id := String(card.get_meta("remote_id", ""))
		if id == "" or not Remote.phones.has(id):
			if tag:
				tag.queue_free()
			continue
		if tag == null:
			tag = UIKit.label("", 14)
			tag.name = "PhoneTag"
			tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			body.add_child(tag)
			body.move_child(tag, 3)   # under the name field
		var on: bool = Remote.phones[id]["online"]
		tag.text = "📱 %s's phone%s" % [Remote.phones[id]["name"], "" if on else " (disconnected)"]
		tag.add_theme_color_override("font_color", UIKit.GOOD if on else Color(1, 1, 1, 0.5))

# Give every phone a human player card: its own, a free human card, or a new one.
func _on_phones_changed() -> void:
	for id in Remote.phones:
		var card := _card_of(id)
		if card == null:
			for c in player_cards.get_children():
				var cpu := c.find_child("CPUButton", true, false) as Button
				if not c.has_meta("remote_id") and not (cpu and cpu.button_pressed):
					card = c
					break
			if card == null and player_cards.get_child_count() < MAX_PLAYERS:
				_add_card()
				_relabel()
				card = player_cards.get_child(player_cards.get_child_count() - 1)
			if card == null:
				continue
			card.set_meta("remote_id", id)
		# the name typed on the phone, and a phone player is never a CPU
		var field := card.find_child("NameField", true, false) as LineEdit
		if field:
			field.text = Remote.phones[id]["name"]
		var cpu_btn := card.find_child("CPUButton", true, false) as Button
		if cpu_btn:
			cpu_btn.button_pressed = false
	# cards whose phone is gone from the room (room stopped) are freed up
	for c in player_cards.get_children():
		if c.has_meta("remote_id") and not Remote.phones.has(String(c.get_meta("remote_id"))):
			c.remove_meta("remote_id")
	_refresh_phones()

func _card_of(id: String) -> Node:
	for card in player_cards.get_children():
		if String(card.get_meta("remote_id", "")) == id:
			return card
	return null

# What a phone shows before the game starts (Remote calls this).
func _phone_lobby_view(id: String) -> Dictionary:
	var card := _card_of(id)
	if card == null:
		return {"screen": "wait", "text": "The game is full (4 players) — you can watch!", "me": {"name": Remote.phones[id]["name"]}}
	var trainer: Dictionary = TRAINERS[int(card.get_meta("trainer_idx", 0))]
	return {"screen": "buttons", "title": "You're Player %d!" % (card.get_index() + 1),
		"lines": ["Trainer: %s  ·  starter: %s" % [trainer["name"], trainer["starter"]], "Wait for the host to press ▶ Start Game."],
		"buttons": [{"label": "◀ Change trainer ▶"}],
		"_actions": [func(): _on_character_pressed(card)],
		"me": {"name": Remote.phones[id]["name"], "color": "#" + Color(trainer["color"]).to_html(false)}}
