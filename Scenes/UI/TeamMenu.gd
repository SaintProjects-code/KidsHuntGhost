extends MenuWindow
## The party screen ("<Player>'s Pokémon"). Built in code, shown via UIManager.
## present(player) populates it. Emits stats_requested(spirit) when a card's
## Stats button is pressed (the HUD opens the Stats screen).

signal stats_requested(spirit: Dictionary)

const TEAM_MAX := 6   # 3 rows × 2 columns; extras live in the PC (in towns)

var _player: PlayerData
var _title: Label
var _cards_box: GridContainer

func _ready() -> void:
	_build()
	hide()

func _build() -> void:
	# Sizes to content: 6 cards in a 2×3 grid always fit without scrolling.
	var col := _init_window(680, 0)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 28)
	_title.add_theme_color_override("font_color", Color("ffd24d"))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_title)

	var hint := Label.new()
	hint.text = "▲▼ reorder team · Stats to inspect"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(1, 1, 1, 0.7)
	col.add_child(hint)

	# 2 columns × 3 rows — the team caps at TEAM_MAX (6) spirits, so the
	# grid never needs a scroll bar.
	_cards_box = GridContainer.new()
	_cards_box.columns = 2
	_cards_box.add_theme_constant_override("h_separation", 8)
	_cards_box.add_theme_constant_override("v_separation", 8)
	_cards_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_cards_box)

	var close := Button.new()
	close.text = "Close"
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(0, 44)
	close.pressed.connect(func(): UIManager.close_overlay())
	col.add_child(close)

func present(player: PlayerData) -> void:
	_player = player
	_refresh()

func _refresh() -> void:
	_title.text = "%s's Spirits" % _player.player_name
	for c in _cards_box.get_children():
		c.queue_free()
	for i in mini(_player.team.size(), TEAM_MAX):
		_cards_box.add_child(_make_card(i))

func _make_card(i: int) -> Control:
	var mon: Dictionary = _player.team[i]
	var card := PanelContainer.new()
	# fixed cell size so 2 columns fit the window; slimmer padding than the
	# theme default so 3 rows stay well inside the screen
	card.custom_minimum_size = Vector2(306, 104)
	var card_sb := StyleBoxFlat.new()
	card_sb.bg_color = Color(0.14, 0.12, 0.26, 0.9)
	card_sb.border_width_left = 2
	card_sb.border_width_top = 2
	card_sb.border_width_right = 2
	card_sb.border_width_bottom = 2
	card_sb.border_color = Color(0.541, 0.435, 0.965, 0.5)
	card_sb.corner_radius_top_left = 12
	card_sb.corner_radius_top_right = 12
	card_sb.corner_radius_bottom_left = 12
	card_sb.corner_radius_bottom_right = 12
	card_sb.content_margin_left = 10
	card_sb.content_margin_right = 10
	card_sb.content_margin_top = 8
	card_sb.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", card_sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	card.add_child(row)

	var sprite := TextureRect.new()
	sprite.custom_minimum_size = Vector2(84, 84)
	sprite.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.texture = SpiritsData.sprite_tex(mon.get("name", ""), "front")
	row.add_child(sprite)

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(info)

	# two short lines instead of one long one, so every word stays visible
	var head := Label.new()
	head.text = "[%d] %s  %s" % [i + 1, mon.get("name", "?"), SpiritsData.star_text(mon.get("stars", 0))]
	head.add_theme_font_size_override("font_size", 16)
	info.add_child(head)
	var sub := Label.new()
	var held: StringName = mon.get("held_item", &"")
	var held_txt := ""
	if held != &"" and GameData.HELD_ITEMS.has(held):
		held_txt = " · 🎒 %s" % GameData.HELD_ITEMS[held]["name"]
	sub.text = "%s · [%s]%s" % [mon.get("rarity", ""), mon.get("type", ""), held_txt]
	sub.clip_text = true
	sub.add_theme_font_size_override("font_size", 13)
	sub.modulate = Color(1, 1, 1, 0.75)
	info.add_child(sub)

	var hp := ProgressBar.new()
	hp.max_value = mon.get("hp", 1)
	hp.value = mon.get("current_hp", mon.get("hp", 1))
	hp.custom_minimum_size = Vector2(0, 10)
	hp.show_percentage = false
	info.add_child(hp)

	var stat := Label.new()
	stat.text = "HP %d/%d  ATK:%d DEF:%d SPD:%d" % [
		mon.get("current_hp", 0), mon.get("hp", 0),
		mon.get("atk", 0), mon.get("def", 0), mon.get("spd", 0)]
	stat.add_theme_font_size_override("font_size", 13)
	info.add_child(stat)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 4)
	info.add_child(buttons)
	buttons.add_child(_mini_btn("Stats", func(): stats_requested.emit(mon)))
	# equipping happens from the ITEM bag; this side only takes items back
	if mon.get("held_item", &"") != &"":
		buttons.add_child(_mini_btn("Take 🎒", _on_take.bind(mon)))
	buttons.add_child(_mini_btn("▲", func(): _move(i, -1)))
	buttons.add_child(_mini_btn("▼", func(): _move(i, 1)))
	return card

# Unequip the spirit's held item back into the bag (blocked if the bag can't
# take it — 7 kinds / stacks of 5).
func _on_take(mon: Dictionary) -> void:
	var held: StringName = mon.get("held_item", &"")
	if held == &"" or not GameData.HELD_ITEMS.has(held):
		return
	if _player.inventory.add_item(GameData.held_item_entry(held)):
		mon["held_item"] = &""
	_refresh()

# Compact purple button (the theme's default padding is too chunky in-card).
func _mini_btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_stylebox_override("normal", _mini_style(Color(0.541, 0.435, 0.965)))
	b.add_theme_stylebox_override("hover", _mini_style(Color(0.651, 0.565, 1.0)))
	b.add_theme_stylebox_override("pressed", _mini_style(Color(0.435, 0.337, 0.847)))
	b.pressed.connect(cb)
	return b

func _mini_style(bg: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_width_bottom = 2
	sb.border_color = Color(0.345, 0.247, 0.737)
	sb.corner_radius_top_left = 7
	sb.corner_radius_top_right = 7
	sb.corner_radius_bottom_left = 7
	sb.corner_radius_bottom_right = 7
	sb.content_margin_left = 8.0
	sb.content_margin_right = 8.0
	sb.content_margin_top = 3.0
	sb.content_margin_bottom = 3.0
	return sb

func _move(i: int, dir: int) -> void:
	var j: int = i + dir
	if j < 0 or j >= _player.team.size():
		return
	var tmp = _player.team[i]
	_player.team[i] = _player.team[j]
	_player.team[j] = tmp
	_refresh()

func _stars(n: int) -> String:
	var out := ""
	for i in 3:
		out += "★" if i < n else "☆"
	return out
