extends MenuWindow
## Two uses:
##   present_reward(player_index, item)  → "You found X!" popup, applies it, emits closed()
##   present_bag(player_index)           → inventory viewer (balls + potions/revives to use)
## Emits closed() when dismissed.

signal closed()

var _title: Label
var _body: VBoxContainer
var _player_index: int = -1

func _ready() -> void:
	# Sizes to content: even a full bag (gold + balls + 7 stacked items, or
	# the 6-spirit target picker) fits on screen without a scroll bar.
	var col := _init_window(440, 0)
	_title = _title_label("Items", 26)
	col.add_child(_title)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 6)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_body)
	col.add_child(_button("Close", func(): closed.emit()))
	hide()

# ── ITEM tile: grant a random item, show what it was ──────────────────────────
func present_reward(player_index: int, item: Dictionary) -> void:
	_player_index = player_index
	_apply_item(player_index, item)
	_title.text = "You found an Item!"
	_clear()
	var lbl := Label.new()
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.text = "%s\n(%s)" % [item.get("name", "Item"), _describe(item)]
	_body.add_child(lbl)

# ── ITEM button: show the bag and let the player use heals ────────────────────
func present_bag(player_index: int) -> void:
	_player_index = player_index
	_title.text = "%s's Bag" % GameState.players[player_index].player_name
	_clear()
	var inv = GameState.players[player_index].inventory
	_body.add_child(_line("Gold: %d" % inv.gold))
	for ball in inv.balls.keys():
		_body.add_child(_line("%s ×%d" % [_ball_name(ball), inv.balls[ball]]))
	if inv.items.is_empty():
		_body.add_child(_line("No usable items."))
	else:
		for entry in inv.items:
			_body.add_child(_item_use_row(entry))

func _item_use_row(entry: Dictionary) -> Control:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = "%s ×%d" % [entry.get("name", "Item"), int(entry.get("count", 1))]
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	row.add_child(_button("Use", func(): _show_targets(entry), 36))
	return row

# ── Target picker: choose which spirit the item affects ──────────────────────
# Clicking Use swaps the bag list for the team, one card per spirit with a
# live HP bar (PokeLike-style); pick a spirit to apply the item to it.

func _show_targets(entry: Dictionary) -> void:
	_title.text = "Use %s on…" % entry.get("name", "Item")
	_clear()
	# 2 columns × 3 rows so a full 6-spirit team never runs off screen
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_body.add_child(grid)
	for mon in GameState.players[_player_index].team:
		grid.add_child(_target_card(entry, mon))
	_body.add_child(_button("Back", func(): present_bag(_player_index), 36))

func _target_card(entry: Dictionary, mon: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(300, 0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(44, 44)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.texture = SpiritsData.sprite_tex(mon.get("name", ""), "front")
	row.add_child(icon)

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(info)
	var hp_now: int = mon.get("current_hp", 0)
	var hp_max: int = mon.get("hp", 1)
	var name_lbl := Label.new()
	name_lbl.text = "%s   %d/%d" % [mon.get("name", "?"), hp_now, hp_max]
	name_lbl.add_theme_font_size_override("font_size", 16)
	info.add_child(name_lbl)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 10)
	bar.max_value = hp_max
	bar.value = hp_now
	var ratio := float(hp_now) / float(hp_max)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.4, 0.85, 0.35) if ratio > 0.5 else (Color(0.95, 0.85, 0.3) if ratio > 0.2 else Color(0.9, 0.3, 0.25))
	fill.corner_radius_top_left = 4
	fill.corner_radius_top_right = 4
	fill.corner_radius_bottom_left = 4
	fill.corner_radius_bottom_right = 4
	bar.add_theme_stylebox_override("fill", fill)
	info.add_child(bar)

	var pick := _button("Equip" if entry.get("kind", "") == "held" else "Use", func(): _apply_to(entry, mon), 34)
	pick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# potions need a hurt-but-standing spirit; revives need a fainted one;
	# held items can be equipped on anyone
	match entry.get("kind", ""):
		"potion":
			pick.disabled = hp_now <= 0 or hp_now >= hp_max
		"revive":
			pick.disabled = hp_now > 0
	row.add_child(pick)
	return card

func _apply_to(entry: Dictionary, mon: Dictionary) -> void:
	match entry.get("kind", ""):
		"potion":
			mon["current_hp"] = mini(mon.get("hp", 0), mon.get("current_hp", 0) + int(entry.get("amount", 40)))
		"revive":
			if mon.get("current_hp", 0) <= 0:
				mon["current_hp"] = int(mon.get("hp", 0) / 2)
		"held":
			# equip; anything already held goes back to the bag (the slot we
			# just consumed leaves room)
			var old: StringName = mon.get("held_item", &"")
			mon["held_item"] = entry.get("key", &"")
			GameState.players[_player_index].inventory.consume_item(entry)
			if old != &"" and GameData.HELD_ITEMS.has(old):
				GameState.players[_player_index].inventory.add_item(GameData.held_item_entry(old))
			present_bag(_player_index)
			return
	GameState.players[_player_index].inventory.consume_item(entry)
	present_bag(_player_index)

# Grant an item without showing the window (used for CPU).
func grant(player_index: int, item: Dictionary) -> void:
	_apply_item(player_index, item)

# ── Apply a granted item to the player ────────────────────────────────────────
func _apply_item(player_index: int, item: Dictionary) -> void:
	var p: PlayerData = GameState.players[player_index]
	match item.get("kind", ""):
		"ball":
			p.inventory.balls[&"spirit_ball"] = p.inventory.ball_count(&"spirit_ball") + int(item.get("amount", 1))
		"gold":
			p.inventory.gold += int(item.get("amount", 0))
		"potion", "revive":
			# Bag rules: 7 distinct items max, stacks of 5 — a full bag
			# silently drops the reward (same as the old 7-slot cap).
			p.inventory.add_item(item)
		"held":
			# ITEM-tile "?" placeholder → roll a random held battle item.
			if not item.has("key"):
				var key := GameData.random_held_key()
				item["key"] = key
				item["name"] = GameData.HELD_ITEMS[key]["name"]
			p.inventory.add_item(item)

func _describe(item: Dictionary) -> String:
	match item.get("kind", ""):
		"ball":   return "+%d Spirit Ball" % int(item.get("amount", 1))
		"gold":   return "+%d gold" % int(item.get("amount", 0))
		"potion": return "heals %d HP" % int(item.get("amount", 0))
		"revive": return "revives a fainted spirit"
		"held":   return String(GameData.HELD_ITEMS.get(item.get("key", &""), {}).get("desc", "a battle item"))
	return ""

func _ball_name(ball) -> String:
	return "Spirit Ball" if ball == &"spirit_ball" else "Master Ball"

func _line(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l

func _clear() -> void:
	for c in _body.get_children():
		c.queue_free()
