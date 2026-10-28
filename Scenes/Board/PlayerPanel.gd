extends PanelContainer
## One player-info card (the top-right HUD panels). The LAYOUT lives in
## PlayerPanel.tscn so sizes/spacing can be edited in the Godot editor —
## this script only fills in the per-player data on each refresh.
##
## The scene provides: %NameLabel, %Badges (circle dots), %PtsLabel,
## %ItemRow (gold / jar / card chips added here), %SpLabel and %PartyRow (6
## Slot panels, each holding a hidden "Icon" TextureRect).
const BADGE_EARNED := Color("ffd24d")
const BADGE_UNEARNED := Color(1, 1, 1, 0.15)
const LEAD_TINT := Color("8fff8f")

var _trainer_icon: TextureRect      # built in code (see _set_trainer_icon)
@onready var _name_lbl: Label = %NameLabel
@onready var _badges: HBoxContainer = %Badges
@onready var _pts_lbl: Label = %PtsLabel
@onready var _items: HFlowContainer = %ItemRow
@onready var _sp_lbl: Label = %SpLabel
@onready var _party: HBoxContainer = %PartyRow

func present(p: PlayerData, active: bool) -> void:
	modulate = Color(1, 1, 1, 1) if active else Color(0.7, 0.7, 0.74, 0.9)
	_set_trainer_icon(p)
	_name_lbl.text = ("▶ " if active else "") + p.player_name + (" ⚔" if p.pvp_tag else "")
	_name_lbl.modulate = p.color
	_pts_lbl.text = "pts: %d / %d" % [p.progress.points, GameState.win_threshold]
	_sp_lbl.text = "Team: %d" % p.team.size()
	_fill_badges(p)
	_fill_items(p)
	_fill_party(p, active)

# Trainer portrait beside the name. Built in code (not in the .tscn) so the
# scene can be re-saved in the editor without dropping it.
func _set_trainer_icon(p: PlayerData) -> void:
	if _trainer_icon == null:
		_trainer_icon = TextureRect.new()
		_trainer_icon.custom_minimum_size = Vector2(46, 56)
		_trainer_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_trainer_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_trainer_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_trainer_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var header: Node = _name_lbl.get_parent()
		header.add_child(_trainer_icon)
		header.move_child(_trainer_icon, 0)   # sit before the name
	_trainer_icon.texture = GameData.trainer_texture(GameData.player_trainer(p))
	_trainer_icon.visible = _trainer_icon.texture != null

# The scene's dots have a white circle StyleBox, so a modulate colours them
# (gold = earned). The scene ships with 5 dots; grow the row to one per badge.
func _fill_badges(p: PlayerData) -> void:
	var total: int = p.progress.badges.size()
	while _badges.get_child_count() < total:
		_badges.add_child(_badges.get_child(0).duplicate())
	var count: int = p.progress.badge_count()
	var dots: Array = _badges.get_children()
	for i in dots.size():
		dots[i].visible = i < total
		dots[i].modulate = BADGE_EARNED if i < count else BADGE_UNEARNED

func _fill_party(p: PlayerData, active: bool) -> void:
	var slot_i := 0
	for node in _party.get_children():
		if not (node is Panel):
			continue   # skip the Team: label
		var icon: TextureRect = node.get_node("Icon")
		if slot_i < p.team.size():
			icon.texture = SpiritsData.sprite_tex(p.team[slot_i].get("name", ""), "icon")
			icon.visible = icon.texture != null
			icon.modulate = LEAD_TINT if (slot_i == 0 and active) else Color(1, 1, 1, 1)
		else:
			icon.visible = false
			icon.texture = null
		slot_i += 1

# ---------------- resource chips ----------------

func _fill_items(p: PlayerData) -> void:
	UIKit.clear(_items)
	_items.add_child(_chip("🪙 %d" % p.inventory.gold))
	for jar in CatchSystem.JAR_ORDER:
		var n: int = p.inventory.jar_count(jar)
		if n > 0:
			_items.add_child(_chip("%s ×%d" % [CatchSystem.jar_name(jar), n]))
	_items.add_child(_chip("🃏 %d/%d" % [p.inventory.hand.size(), Balance.HAND_SIZE]))

func _chip(text: String) -> Control:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", UIKit.box(Color(0.22, 0.18, 0.38, 0.85), 8, 1,
		Color(UIKit.PURPLE, 0.6), Vector2(8, 3)))
	chip.add_child(UIKit.label(text, 16))
	return chip
