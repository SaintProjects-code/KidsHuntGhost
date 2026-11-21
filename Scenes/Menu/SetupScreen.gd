extends Control
## Player setup: 2–6 player cards (name, trainer with its starter, human or
## CPU), a Game card summing up the settings with a Settings window (map,
## battle size, points to win, sound), and 📱 Phones: host a room (see Remote);
## every phone that joins takes a human player card and can flip through
## trainers from the phone.
##
## The layout is built here from containers (top bar · card row · bottom bar),
## and both pop-ups are MenuWindows, so everything fits any screen size.

const MIN_PLAYERS := 2
const MAX_PLAYERS := 6
const CARD_WIDTH := 184.0
# 5–6 players: narrower cards (and Game card / Add slot) so the row still fits
const CARD_WIDTH_BY_COUNT := {5: 140.0, 6: 132.0}
const SIDE_BUTTON_WIDTH := 120.0   # Back, mirrored on the right so the title stays centred

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

var player_cards: HBoxContainer   # only the player cards: child index = player number - 1
var _add_slot: Button
var _game_card: PanelContainer
var _row: HBoxContainer
var _row_holder: Control
var _game_summary: Label
var _phones_button: Button

# Settings window
var _settings_win: MenuWindow
var map_option: OptionButton
var _map_blurb: Label
var _size_buttons: Dictionary = {}   # battle size -> Button
var win_slider: HSlider
var win_value: Label
var _no_points: CheckButton
var trail_slider: HSlider
var trail_value: Label
var volume_slider: HSlider
var volume_value: Label

func _ready() -> void:
	MusicManager.play_menu()
	_build_layout()
	_build_settings_window()
	_build_phones_window()
	while player_cards.get_child_count() < MIN_PLAYERS:
		_add_card()
	_relabel()
	_refresh_game_card()
	_on_phones_changed()

# ---------------- Layout ----------------

func _build_layout() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	margin.add_theme_constant_override("margin_top", 14)
	add_child(margin)
	var col := UIKit.vbox(12)
	margin.add_child(col)

	var top := UIKit.hbox(12)
	col.add_child(top)
	var back := Button.new()
	back.text = "◀ Back"
	back.custom_minimum_size.x = SIDE_BUTTON_WIDTH
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UIKit.style_button(back, "secondary", "m")
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://Scenes/Menu/MainMenu.tscn"))
	top.add_child(back)
	var title := UIKit.label("Player Setup", 44, UIKit.GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_constant_override("outline_size", 8)
	title.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.18))
	top.add_child(title)
	var balance := Control.new()
	balance.custom_minimum_size.x = SIDE_BUTTON_WIDTH
	top.add_child(balance)

	var middle := CenterContainer.new()
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(middle)
	# the row sits in a plain holder (containers reset a child's scale), so it
	# can be scaled down to fit when 5–6 player cards make it too wide
	_row_holder = Control.new()
	middle.add_child(_row_holder)
	var row := UIKit.hbox(16)
	_row = row
	_row_holder.add_child(row)
	resized.connect(_fit_row)
	player_cards = UIKit.hbox(16)
	row.add_child(player_cards)
	_add_slot = _make_add_slot()
	row.add_child(_add_slot)
	_game_card = _make_game_card()
	row.add_child(_game_card)

	var bottom := UIKit.hbox(12)
	col.add_child(bottom)
	_phones_button = Button.new()
	_phones_button.text = "📱 Phones"
	_phones_button.custom_minimum_size.x = 260
	_phones_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UIKit.style_button(_phones_button, "secondary", "m")
	bottom.add_child(_phones_button)
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(fill)
	var start := Button.new()
	start.text = "▶ Start Game"
	start.custom_minimum_size.x = 240
	UIKit.style_button(start, "gold", "l")
	start.pressed.connect(_on_confirm_pressed)
	bottom.add_child(start)

# An empty dashed-looking slot: click to add a player.
func _make_add_slot() -> Button:
	var b := Button.new()
	b.text = "+\nAdd player"
	b.custom_minimum_size = Vector2(130, 0)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 18)
	b.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	var idle := UIKit.box(Color(1, 1, 1, 0.03), 14, 2, Color(UIKit.PURPLE, 0.4))
	var hover := UIKit.box(Color(1, 1, 1, 0.08), 14, 2, Color(UIKit.PURPLE, 0.8))
	for st in ["normal", "disabled"]:
		b.add_theme_stylebox_override(st, idle)
	for st in ["hover", "pressed"]:
		b.add_theme_stylebox_override(st, hover)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(_on_add_player_pressed)
	return b

# The settings at a glance, with a button to change them.
func _make_game_card() -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(190, 0)
	card.add_theme_stylebox_override("panel", UIKit.box(UIKit.CARD_BG, 14, 2, Color(UIKit.GOLD, 0.45), Vector2(14, 12)))
	var col := UIKit.vbox(10)
	card.add_child(col)
	var head := UIKit.label("Game", 20, UIKit.GOLD)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(head)
	_game_summary = UIKit.label("", 15)
	_game_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_game_summary.custom_minimum_size.x = 160
	_game_summary.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_game_summary)
	var change := Button.new()
	change.text = "⚙ Change"
	UIKit.style_button(change, "primary", "m")
	change.pressed.connect(func(): _settings_win.show())
	col.add_child(change)
	return card

func _refresh_game_card() -> void:
	var info: Dictionary = GameData.map_info(GameState.active_map)
	var goal := "No points: beat the Haunted Four" if GameState.infinite_points else "First to %d points" % GameState.win_threshold
	_game_summary.text = "🗺 %s\n\n⚔ %dv%d battles\n\n🏆 %s\n\n👻 Haunted Four at %d badge%s" % [info["name"],
		GameState.battle_size, GameState.battle_size, goal, GameState.trail_badges, "" if GameState.trail_badges == 1 else "s"]
	if not GameState.minigames_off.is_empty():
		_game_summary.text += "

🎮 %d / %d minigames" % [CompWin.all_events().size() - GameState.minigames_off.size(), CompWin.all_events().size()]

# ---------------- Player cards ----------------

func _on_add_player_pressed() -> void:
	if player_cards.get_child_count() < MAX_PLAYERS:
		Sfx.play("click")
		_add_card()
		_relabel()

func _add_card() -> void:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	card.add_theme_stylebox_override("panel", UIKit.box(UIKit.CARD_BG, 14, 2, Color(UIKit.PURPLE, 0.55), Vector2(12, 12)))
	var body := UIKit.vbox(8)
	body.name = "Body"
	card.add_child(body)

	var head := UIKit.hbox(4)
	body.add_child(head)
	var title := UIKit.label("", 20)
	title.name = "PlayerName"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(title)
	var remove := UIKit.small_button("✕", func(): _remove_card(card))
	remove.name = "RemoveButton"
	remove.tooltip_text = "Remove this player"
	UIKit.style_button(remove, "danger", "s")
	head.add_child(remove)

	var icon := TextureRect.new()
	icon.name = "PlayerIcon"
	icon.custom_minimum_size = Vector2(0, 120)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	body.add_child(icon)

	var field := LineEdit.new()
	field.name = "NameField"
	field.placeholder_text = "Name"
	field.alignment = HORIZONTAL_ALIGNMENT_CENTER
	field.max_length = 12
	body.add_child(field)

	var pick := UIKit.hbox(4)
	body.add_child(pick)
	pick.add_child(UIKit.small_button("◀", func(): _step_trainer(card, -1)))
	var who := UIKit.vbox(0)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick.add_child(who)
	var trainer_name := UIKit.label("", 16)
	trainer_name.name = "TrainerName"
	trainer_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	who.add_child(trainer_name)
	var starter_name := UIKit.label("", 12, Color(1, 1, 1, 0.65))
	starter_name.name = "StarterName"
	starter_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	who.add_child(starter_name)
	pick.add_child(UIKit.small_button("▶", func(): _step_trainer(card, 1)))

	var switch := UIKit.hbox(4)
	body.add_child(switch)
	for spec in [["HumanButton", "Human", false], ["CPUButton", "CPU", true]]:
		var b := Button.new()
		b.name = spec[0]
		b.text = spec[1]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cpu: bool = spec[2]
		b.pressed.connect(func():
			Sfx.play("click")
			_set_cpu(card, cpu))
		switch.add_child(b)

	card.set_meta("trainer_idx", _free_trainer())
	player_cards.add_child(card)
	_set_cpu(card, false)

# The first trainer nobody has picked yet.
func _free_trainer() -> int:
	var used: Array = player_cards.get_children().map(func(c): return int(c.get_meta("trainer_idx", -1)))
	for i in TRAINERS.size():
		if not used.has(i):
			return i
	return 0

func _remove_card(card: Node) -> void:
	if player_cards.get_child_count() <= MIN_PLAYERS:
		return
	player_cards.remove_child(card)
	card.queue_free()
	_relabel()

# Card titles, which cards can be removed, and whether there's room to add.
func _relabel() -> void:
	for i in player_cards.get_child_count():
		var card := player_cards.get_child(i)
		(card.find_child("PlayerName", true, false) as Label).text = "Player %d" % (i + 1)
		var remove := card.find_child("RemoveButton", true, false) as Button
		remove.visible = i >= MIN_PLAYERS and not card.has_meta("remote_id")
		_apply_trainer(card)
	_add_slot.visible = player_cards.get_child_count() < MAX_PLAYERS
	_fit_cards()

# Narrower cards once there are 5 or 6 players, so the whole row stays on screen.
func _fit_cards() -> void:
	var n := player_cards.get_child_count()
	var w: float = CARD_WIDTH_BY_COUNT.get(n, CARD_WIDTH)
	for card in player_cards.get_children():
		(card as Control).custom_minimum_size.x = w
		var icon := card.find_child("PlayerIcon", true, false) as Control
		if icon:
			icon.custom_minimum_size.y = 120 if n <= 4 else 96
	_add_slot.custom_minimum_size.x = 130 if n <= 4 else 90
	if _game_card:
		_game_card.custom_minimum_size.x = 190 if n <= 4 else 170
	_fit_row.call_deferred()

func _fit_row() -> void:
	if _row == null:
		return
	var need := _row.get_combined_minimum_size()
	var avail := size.x - 48.0
	var k := minf(1.0, avail / maxf(1.0, need.x))
	_row.size = need
	_row.position = Vector2.ZERO
	_row.scale = Vector2(k, k)
	_row_holder.custom_minimum_size = need * k

func _is_cpu(card: Node) -> bool:
	return bool(card.get_meta("cpu", false))

# The Human / CPU switch: the chosen side is lit, the other is dark.
func _set_cpu(card: Node, on: bool) -> void:
	card.set_meta("cpu", on)
	for spec in [["HumanButton", not on], ["CPUButton", on]]:
		var b := card.find_child(spec[0], true, false) as Button
		UIKit.style_button(b, "primary" if spec[1] else "secondary", "s")

# ◀ / ▶ on the card (and "Change trainer" on a phone, via _on_character_pressed).
func _step_trainer(card: Node, step: int) -> void:
	card.set_meta("trainer_idx", posmod(int(card.get_meta("trainer_idx", 0)) + step, TRAINERS.size()))
	_apply_trainer(card)

func _on_character_pressed(card: Node) -> void:
	_step_trainer(card, 1)

func _apply_trainer(card: Node) -> void:
	var trainer: Dictionary = TRAINERS[int(card.get_meta("trainer_idx", 0))]
	var icon := card.find_child("PlayerIcon", true, false) as TextureRect
	# the TRAINER front and centre…
	icon.texture = GameData.trainer_texture([trainer["portrait"]])
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
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
	(card.find_child("TrainerName", true, false) as Label).text = String(trainer["name"])
	(card.find_child("StarterName", true, false) as Label).text = "with %s" % trainer["starter"]

func _on_confirm_pressed() -> void:
	SaveManager.delete_save()   # a new game replaces the old save
	GameState.reset()
	for i in player_cards.get_child_count():
		var card := player_cards.get_child(i)
		var trainer: Dictionary = TRAINERS[int(card.get_meta("trainer_idx", 0))]
		var p := PlayerData.new()
		var field := card.find_child("NameField", true, false) as LineEdit
		var entered := field.text.strip_edges()
		p.player_name = entered if entered != "" else String(trainer["name"])
		p.trainer_key = String(trainer["portrait"])
		p.is_cpu = _is_cpu(card)
		p.color = trainer["color"]
		p.remote_id = String(card.get_meta("remote_id", ""))
		p.team.append(SpiritsData.get_spirit(trainer["starter"]))
		GameState.players.append(p)
	get_tree().change_scene_to_file("res://Scenes/Board/Board.tscn")

# ---------------- Windows ----------------

# A centred pop-up (dimmed backdrop, shrinks to fit the screen). Returns [window, column].
func _make_window(width: float, title: String) -> Array:
	var win := MenuWindow.new()
	add_child(win)
	var col: VBoxContainer = win._init_window(width)
	var head := UIKit.label(title, 26, UIKit.GOLD)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(head)
	win.hide()
	return [win, col]

func _done_button(win: Control) -> Button:
	var done := Button.new()
	done.text = "Done"
	done.custom_minimum_size.x = 180
	done.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UIKit.style_button(done, "primary", "m")
	done.pressed.connect(func():
		Sfx.play("click")
		win.hide())
	return done

# ---------------- Minigames on / off ----------------

const CompWin := preload("res://Scenes/UI/Competition/CompetitionWindow.gd")
var _games_btn: Button
var _games_win: MenuWindow

func _games_label() -> String:
	var all := CompWin.all_events()
	var on := all.filter(func(k): return not GameState.minigames_off.has(k)).size()
	return "🎮 %d / %d on — choose…" % [on, all.size()]

# A window with a checkbox per minigame (2 columns); at least one stays on.
func _build_games_window() -> void:
	if _games_win:
		_games_win.queue_free()
	var made := _make_window(620, "Minigames")
	_games_win = made[0]
	var col: VBoxContainer = made[1]
	var hint := UIKit.label("Untick the ones you don't want to play. At least one stays on.", 14, Color(1, 1, 1, 0.7))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(hint)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 6)
	col.add_child(grid)
	var boxes: Array = []
	for k in CompWin.all_events():
		var cb := CheckBox.new()
		cb.text = CompWin.event_name(k)
		cb.focus_mode = Control.FOCUS_NONE
		cb.add_theme_font_size_override("font_size", 17)
		cb.custom_minimum_size.x = 270
		cb.button_pressed = not GameState.minigames_off.has(k)
		var key: String = k
		cb.toggled.connect(func(on: bool):
			if on:
				GameState.minigames_off.erase(key)
			elif CompWin.all_events().size() - GameState.minigames_off.size() > 1:
				GameState.minigames_off.append(key)
			else:
				cb.set_pressed_no_signal(true)   # keep the last one on
				Sfx.play("error")
			_games_btn.text = _games_label())
		grid.add_child(cb)
		boxes.append(cb)
	var row := UIKit.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(UIKit.small_button("All on", func():
		GameState.minigames_off.clear()
		for b in boxes:
			b.set_pressed_no_signal(true)
		_games_btn.text = _games_label()))
	row.add_child(_done_button(_games_win))
	col.add_child(row)

# ---------------- Game settings ----------------

func _build_settings_window() -> void:
	var made := _make_window(580, "Game Settings")
	_settings_win = made[0]
	var col: VBoxContainer = made[1]
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 16)
	col.add_child(grid)

	# Map
	map_option = OptionButton.new()
	map_option.custom_minimum_size = Vector2(360, 40)
	map_option.focus_mode = Control.FOCUS_NONE
	for n in GameData.MAPS:
		map_option.add_item("%d · %s" % [n, GameData.MAPS[n]["name"]], n)
	map_option.select(maxi(0, map_option.get_item_index(GameState.active_map)))
	map_option.item_selected.connect(_on_map_selected)
	_map_blurb = UIKit.label("", 13, Color(1, 1, 1, 0.65))
	_map_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_map_blurb.custom_minimum_size.x = 360
	_settings_row(grid, "Map", [map_option, _map_blurb])

	# Battle size: a 3-way switch
	var sizes := UIKit.hbox(6)
	for n in [3, 4, 6]:
		var b := Button.new()
		b.text = "%dv%d" % [n, n]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.tooltip_text = "Spirits per side in every battle"
		b.pressed.connect(func():
			Sfx.play("click")
			GameState.battle_size = n
			_refresh_settings())
		sizes.add_child(b)
		_size_buttons[n] = b
	_settings_row(grid, "Battles", [sizes])

	# Points to win, or no points at all
	win_slider = HSlider.new()
	win_slider.min_value = 10
	win_slider.max_value = 50
	win_slider.step = 5
	win_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	win_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	win_slider.value = GameState.win_threshold
	win_slider.value_changed.connect(_on_win_changed)
	win_value = UIKit.label("", 18)
	win_value.custom_minimum_size.x = 56
	win_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var win_row := UIKit.hbox(10)
	win_row.add_child(win_slider)
	win_row.add_child(win_value)
	# "No points": points never win — beat 2 of the Haunted Four in a row,
	# then the Spirit Lord.
	_no_points = CheckButton.new()
	_no_points.text = "No points: beat the Haunted Four instead"
	_no_points.focus_mode = Control.FOCUS_NONE
	_no_points.add_theme_font_size_override("font_size", 14)
	_no_points.tooltip_text = "Points can't win: beat 2 of the Haunted Four in a row, then defeat Spirit Lord Vesper"
	_no_points.button_pressed = GameState.infinite_points
	_no_points.toggled.connect(func(on: bool):
		GameState.infinite_points = on
		_refresh_settings())
	_settings_row(grid, "Points to win", [win_row, _no_points])

	# Badges needed to take on the Haunted Four (the Spectral Trail), and to Fly
	trail_slider = HSlider.new()
	trail_slider.min_value = 1
	trail_slider.max_value = 8
	trail_slider.step = 1
	trail_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trail_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	trail_slider.value = GameState.trail_badges
	trail_slider.value_changed.connect(func(v: float):
		GameState.trail_badges = int(v)
		_refresh_settings())
	trail_value = UIKit.label("", 18)
	trail_value.custom_minimum_size.x = 56
	trail_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var trail_row := UIKit.hbox(10)
	trail_row.add_child(trail_slider)
	trail_row.add_child(trail_value)
	var trail_hint := UIKit.label("Badges needed to face them on the Spectral Trail (also unlocks ✈ Fly)", 13, Color(1, 1, 1, 0.65))
	trail_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	trail_hint.custom_minimum_size.x = 360
	_settings_row(grid, "Haunted Four", [trail_row, trail_hint])

	# Sound (the Master bus)
	volume_slider = HSlider.new()
	volume_slider.min_value = 0
	volume_slider.max_value = 100
	volume_slider.step = 1
	volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	volume_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	volume_slider.value = round(db_to_linear(AudioServer.get_bus_volume_db(0)) * 100.0)
	volume_slider.value_changed.connect(_on_volume_changed)
	volume_value = UIKit.label("", 18)
	volume_value.custom_minimum_size.x = 56
	volume_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var vol_row := UIKit.hbox(10)
	vol_row.add_child(volume_slider)
	vol_row.add_child(volume_value)
	_settings_row(grid, "Sound", [vol_row])

	# Minigames: a button that opens a checklist of every minigame
	_games_btn = Button.new()
	_games_btn.focus_mode = Control.FOCUS_NONE
	_games_btn.text = _games_label()
	UIKit.style_button(_games_btn, "secondary", "m")
	_games_btn.pressed.connect(func():
		Sfx.play("click")
		_build_games_window()
		_games_win.show())
	_settings_row(grid, "Minigames", [_games_btn])

	col.add_child(_done_button(_settings_win))
	_settings_win.visibility_changed.connect(_refresh_game_card)
	_on_volume_changed(volume_slider.value)
	_refresh_settings()

# One row of the settings grid: a label on the left, controls stacked on the right.
func _settings_row(grid: GridContainer, text: String, controls: Array) -> void:
	var l := UIKit.label(text, 17, Color(1, 1, 1, 0.85))
	l.custom_minimum_size.x = 130
	l.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	l.custom_minimum_size.y = 40
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	grid.add_child(l)
	var stack := UIKit.vbox(6)
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for c in controls:
		stack.add_child(c)
	grid.add_child(stack)

func _refresh_settings() -> void:
	_map_blurb.text = String(GameData.map_info(GameState.active_map)["blurb"])
	for n in _size_buttons:
		UIKit.style_button(_size_buttons[n], "primary" if n == GameState.battle_size else "secondary", "s")
	win_slider.editable = not GameState.infinite_points
	win_value.text = "∞" if GameState.infinite_points else "%d" % int(win_slider.value)
	trail_value.text = "%d 🏅" % GameState.trail_badges
	_refresh_game_card()

func _on_map_selected(index: int) -> void:
	GameState.active_map = map_option.get_item_id(index)
	win_slider.value = int(GameData.map_info(GameState.active_map)["target"])   # each board has its own sensible target
	_refresh_settings()

func _on_win_changed(value: float) -> void:
	GameState.win_threshold = int(value)
	_refresh_settings()

func _on_volume_changed(value: float) -> void:
	var pct := value / 100.0
	AudioServer.set_bus_mute(0, pct <= 0.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(pct, 0.0001)))
	volume_value.text = "%d%%" % int(value)

# ---------------- 📱 Phones ----------------
# The 📱 Phones window hosts a room (on this computer, or an online server for
# internet play). Each phone that joins takes a human player card — the name
# typed on the phone fills the card, a 📱 tag under it shows the phone is
# linked, and the phone can flip through trainers itself.

var _phones_win: MenuWindow
var _url_field: LineEdit
var _phone_status: Label
var _phone_steps: Label
var _phone_list: Label

func _build_phones_window() -> void:
	var made := _make_window(640, "📱 Play with phones")
	_phones_win = made[0]
	var col: VBoxContainer = made[1]
	# 1. the address: this computer's IP (home play) or a website (internet play)
	var row := UIKit.hbox(8)
	col.add_child(row)
	var ip_label := UIKit.label("Server IP:", 16)
	ip_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ip_label)
	_url_field = LineEdit.new()
	var ips := LocalServer.lan_ips()
	_url_field.text = ips[0] if not ips.is_empty() else ""
	_url_field.placeholder_text = "this computer's IP, e.g. 192.168.1.20"
	_url_field.custom_minimum_size = Vector2(0, 40)
	_url_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_url_field.tooltip_text = "Home play: this computer's IP.\nInternet play: your server's address, e.g. ghost.yourdomain.com"
	_url_field.text_submitted.connect(func(t): Remote.connect_to(t))
	row.add_child(_url_field)
	var connect_btn := Button.new()
	connect_btn.text = "Connect"
	UIKit.style_button(connect_btn, "gold", "m")
	connect_btn.pressed.connect(func(): Remote.connect_to(_url_field.text))
	row.add_child(connect_btn)
	var stop := Button.new()
	stop.text = "Stop"
	UIKit.style_button(stop, "secondary", "m")
	stop.pressed.connect(func(): Remote.stop())
	row.add_child(stop)
	var ip_hint := UIKit.wrap_label("This computer: %s" % ("  ·  ".join(ips) if not ips.is_empty() else "no network found — connect to Wi-Fi or a hotspot"), 13, 600)
	ip_hint.modulate = Color(1, 1, 1, 0.7)
	col.add_child(ip_hint)
	# 2. the room: code, the address phones open, who joined
	_phone_status = UIKit.label("", 36, UIKit.GOLD)
	_phone_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_phone_status)
	_phone_steps = UIKit.wrap_label("", 16, 600)
	col.add_child(_phone_steps)
	_phone_list = UIKit.wrap_label("", 16, 600)
	col.add_child(_phone_list)
	var bottom := UIKit.hbox(10)
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(bottom)
	if OS.get_name() == "Windows":
		var fw := Button.new()
		fw.text = "🛡 Allow phones through Windows Firewall"
		fw.tooltip_text = "Adds a firewall rule for the game's phone ports (Windows asks for permission)."
		UIKit.style_button(fw, "secondary", "m")
		fw.pressed.connect(_open_firewall)
		bottom.add_child(fw)
	bottom.add_child(_done_button(_phones_win))
	_phones_button.pressed.connect(func():
		Sfx.play("click")
		_phones_win.show())
	Remote.room_changed.connect(func(_c): _refresh_phones())
	Remote.phones_changed.connect(_on_phones_changed)
	Remote.lobby_view = _phone_lobby_view

# One firewall rule (all profiles) for every port pair the game may use. It
# runs netsh through an elevated prompt, so Windows asks the player first.
func _open_firewall() -> void:
	var ports: Array = LocalServer.PORTS.map(func(p): return "%d-%d" % [p, p + 1])
	var rule := "name=KidsHuntGhostPhones dir=in action=allow protocol=TCP localport=%s profile=any" % ",".join(ports)
	var cmd := "/c netsh advfirewall firewall delete rule name=KidsHuntGhostPhones & netsh advfirewall firewall add rule " + rule
	OS.create_process("powershell.exe", ["-NoProfile", "-WindowStyle", "Hidden", "-Command",
		"Start-Process cmd -Verb RunAs -WindowStyle Hidden -ArgumentList '%s'" % cmd])

func _process(_delta: float) -> void:
	_refresh_phones()   # cheap: a few labels

func _refresh_phones() -> void:
	if _phone_status == null:
		return
	var online := Remote.phones.keys().filter(func(id): return Remote.phones[id]["online"]).size()
	_phones_button.text = ("📱 Room %s · %d phone%s" % [Remote.code, online, "" if online == 1 else "s"]) if Remote.code != "" else "📱 Phones"
	if Remote.code != "":
		_phone_status.text = "Room code:  %s" % Remote.code
		_phone_steps.text = "Phones open  %s  and type the code." % Remote.phone_url()
		if Remote.is_local():
			var st: Dictionary = Remote.local_stats()
			if int(st["https"]) > 0:
				_phone_steps.text += "\n⚠ Use http:// (not https)"
			if int(st["loads"]) == 0:
				_phone_steps.text += "\nNo phone connected yet — same Wi-Fi? Firewall (🛡)?"
				var others: Array = Remote.other_urls()
				if not others.is_empty():
					_phone_steps.text += "\nOr try:  " + "   ".join(others)
	else:
		var status := Remote.status_text()
		_phone_status.text = ""
		_phone_steps.text = "Press Connect to open a room for phones." if status == "off" else status
	var lines: Array = []
	for id in Remote.phones:
		var card := _card_of(id)
		var where := "no free seat (4 players max)"
		if card:
			var trainer: Dictionary = TRAINERS[int(card.get_meta("trainer_idx", 0))]
			where = "Player %d · %s" % [card.get_index() + 1, trainer["name"]]
		lines.append("%s  %s  →  %s" % ["🟢" if Remote.phones[id]["online"] else "⚪ (left)", Remote.phones[id]["name"], where])
	_phone_list.text = ("In this room (%d):\n" % lines.size() + "\n".join(lines)) if not lines.is_empty() else \
		("In this room: nobody yet" if Remote.code != "" else "")
	_update_phone_tags()

# A "📱 Ivy's phone" line on every card a phone controls.
func _update_phone_tags() -> void:
	for card in player_cards.get_children():
		var body := card.find_child("Body", true, false)
		var tag := body.get_node_or_null("PhoneTag") as Label
		var id := String(card.get_meta("remote_id", ""))
		if id == "" or not Remote.phones.has(id):
			if tag:
				tag.queue_free()
			continue
		if tag == null:
			tag = UIKit.label("", 13)
			tag.name = "PhoneTag"
			tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			tag.clip_text = true
			body.add_child(tag)
		var on: bool = Remote.phones[id]["online"]
		tag.text = "📱 %s's phone%s" % [Remote.phones[id]["name"], "" if on else " (left)"]
		tag.add_theme_color_override("font_color", UIKit.GOOD if on else Color(1, 1, 1, 0.5))

# Give every phone a human player card: its own, a free human card, or a new one.
func _on_phones_changed() -> void:
	for id in Remote.phones:
		var card := _card_of(id)
		if card == null:
			# Player 1 is the keyboard player at the TV: a phone takes another free
			# human seat, else a new seat, and Player 1 only as a last resort
			var free: Array = player_cards.get_children().filter(func(c):
				return not c.has_meta("remote_id") and not _is_cpu(c))
			var others: Array = free.filter(func(c): return c.get_index() > 0)
			if not others.is_empty():
				card = others[0]
			elif player_cards.get_child_count() < MAX_PLAYERS:
				_add_card()
				card = player_cards.get_child(player_cards.get_child_count() - 1)
			elif not free.is_empty():
				card = free[0]
			if card == null:
				continue
			card.set_meta("remote_id", id)
		# the name typed on the phone, and a phone player is never a CPU
		(card.find_child("NameField", true, false) as LineEdit).text = Remote.phones[id]["name"]
		_set_cpu(card, false)
	# cards whose phone is gone from the room (room stopped) are freed up
	for c in player_cards.get_children():
		if c.has_meta("remote_id") and not Remote.phones.has(String(c.get_meta("remote_id"))):
			c.remove_meta("remote_id")
	_relabel()
	_refresh_phones()

func _card_of(id: String) -> Node:
	for card in player_cards.get_children():
		if String(card.get_meta("remote_id", "")) == id:
			return card
	return null

# "Room KLNN: 🟢 Ivy · 🟢 Max · ⚪ Sam" for the phones' lobby screen.
func _room_roster() -> String:
	var names: Array = Remote.phones.keys().map(func(id): return ("🟢 " if Remote.phones[id]["online"] else "⚪ ") + String(Remote.phones[id]["name"]))
	return "Room %s (%d): %s" % [Remote.code, names.size(), "  ·  ".join(names)]

# What a phone shows before the game starts (Remote calls this).
func _phone_lobby_view(id: String) -> Dictionary:
	var card := _card_of(id)
	if card == null:
		return {"screen": "wait", "text": "The game is full (4 players) — you can watch!\n" + _room_roster(), "me": {"name": Remote.phones[id]["name"]}}
	var trainer: Dictionary = TRAINERS[int(card.get_meta("trainer_idx", 0))]
	return {"screen": "buttons", "title": "You're Player %d!" % (card.get_index() + 1),
		"lines": ["Trainer: %s  ·  starter: %s" % [trainer["name"], trainer["starter"]], "Wait for the host to press ▶ Start Game.",
			_room_roster()],
		"buttons": [{"label": "◀ Change trainer ▶"}],
		"_actions": [func(): _on_character_pressed(card)],
		"me": {"name": Remote.phones[id]["name"], "color": "#" + Color(trainer["color"]).to_html(false)}}
