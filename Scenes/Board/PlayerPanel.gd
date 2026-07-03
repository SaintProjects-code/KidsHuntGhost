extends PanelContainer
## One player-info card (the top-right HUD panels). The LAYOUT lives in
## PlayerPanel.tscn so sizes/spacing can be edited in the Godot editor —
## this script only fills in the per-player data on each refresh.
##
## The scene provides: %NameLabel, %Badges (5 circle dots), %PtsLabel,
## %ItemRow (chips added here), %SpLabel and %PartyRow (6 Slot panels,
## each holding a hidden "Icon" TextureRect).

const MAX_ITEM_SLOTS := 5
const BADGE_EARNED := Color("ffd24d")
const BADGE_UNEARNED := Color(1, 1, 1, 0.15)
const LEAD_TINT := Color("8fff8f")

@onready var _name_lbl: Label = %NameLabel
@onready var _badges: HBoxContainer = %Badges
@onready var _pts_lbl: Label = %PtsLabel
@onready var _items: HFlowContainer = %ItemRow
@onready var _sp_lbl: Label = %SpLabel
@onready var _party: HBoxContainer = %PartyRow

func present(p: PlayerData, active: bool) -> void:
	modulate = Color(1, 1, 1, 1) if active else Color(0.7, 0.7, 0.74, 0.9)
	_name_lbl.text = ("▶ " if active else "") + p.player_name
	_name_lbl.modulate = p.color
	_pts_lbl.text = "pts: %d / %d" % [p.progress.points, GameState.win_threshold]
	_sp_lbl.text = "Sp: %d" % p.team.size()
	_fill_badges(p)
	_fill_items(p)
	_fill_party(p, active)

# The scene's dots have a white circle StyleBox, so a modulate is enough to
# colour them (gold = earned, faint white = not yet).
func _fill_badges(p: PlayerData) -> void:
	var earned: Array = p.progress.badges.values()
	var dots: Array = _badges.get_children()
	for i in dots.size():
		dots[i].modulate = BADGE_EARNED if (i < earned.size() and earned[i]) else BADGE_UNEARNED

func _fill_party(p: PlayerData, active: bool) -> void:
	var slot_i := 0
	for node in _party.get_children():
		if not (node is Panel):
			continue   # skip the Sp: label
		var icon: TextureRect = node.get_node("Icon")
		if slot_i < p.team.size():
			icon.texture = SpiritsData.sprite_tex(p.team[slot_i].get("name", ""), "icon")
			icon.visible = icon.texture != null
			icon.modulate = LEAD_TINT if (slot_i == 0 and active) else Color(1, 1, 1, 1)
		else:
			icon.visible = false
			icon.texture = null
		slot_i += 1

# ---------------- item chips ----------------

func _fill_items(p: PlayerData) -> void:
	for c in _items.get_children():
		c.queue_free()
	# gold leads the row, then the stacked items
	_items.add_child(_item_chip("🪙 %d" % p.inventory.gold))
	for entry in _inventory_slots(p):
		_items.add_child(_item_chip("%s ×%d" % [entry.name, entry.count]))

# Ball counts first, then bag items — the inventory stacks items itself now
# (one entry per type with a "count"). Capped at MAX_ITEM_SLOTS shown.
func _inventory_slots(p: PlayerData) -> Array:
	var slots: Array = []
	for ball in p.inventory.balls.keys():
		var count: int = p.inventory.balls[ball]
		if count > 0:
			slots.append({"name": _ball_name(ball), "count": count})
	for entry in p.inventory.items:
		slots.append({"name": entry.get("name", "Item"), "count": int(entry.get("count", 1))})
	return slots.slice(0, MAX_ITEM_SLOTS)

func _ball_name(ball) -> String:
	return "Spirit Ball" if ball == &"spirit_ball" else "Master Ball"

func _item_chip(text: String) -> Control:
	var chip := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.219608, 0.180392, 0.380392, 0.85)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(0.541176, 0.435294, 0.964706, 0.6)
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	chip.add_theme_stylebox_override("panel", sb)
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 16)
	chip.add_child(lbl)
	return chip
