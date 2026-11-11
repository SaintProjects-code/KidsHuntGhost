extends PanelContainer
## One player-info card (the top-right HUD panel). Layout:
##
##   ┌────────┐  ▶ Name ⚔
##   │trainer │  ★ ★ ☆ +2          (badges needed for the Haunted Four)
##   │portrait│  12 / 40 pts  ▓▓▓░░
##   │        │  🪙 10  [cards]  🃏 4/7
##   └────────┘
##   [lead][sp][sp][sp][sp][sp]     (spirit art, HP bar under each)
##
## Built in code; present() fills it in for a player.

const PORTRAIT_SIZE := Vector2(84, 116)
const SLOT_SIZE := Vector2(50, 50)
const BADGE_EARNED := Color("ffd24d")
const BADGE_UNEARNED := Color(1, 1, 1, 0.18)
const LEAD_BORDER := Color("5dcaa5")
const MINI_CARD := Vector2(22, 30)

var _portrait: TextureRect
var _name_lbl: Label
var _badges: HBoxContainer
var _pts_lbl: Label
var _pts_bar: ProgressBar
var _items: HFlowContainer
var _party: HBoxContainer

func _ready() -> void:
	# Older copies of PlayerPanel.tscn carry the previous layout's nodes; this
	# card builds its own, so clear out whatever the scene file brought along.
	for old in get_children():
		remove_child(old)
		old.queue_free()
	scale = Vector2.ONE
	custom_minimum_size = Vector2.ZERO
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	add_child(margin)
	var col := UIKit.vbox(8)
	margin.add_child(col)
	var top := UIKit.hbox(10)
	col.add_child(top)

	var frame := PanelContainer.new()
	frame.custom_minimum_size = PORTRAIT_SIZE
	frame.add_theme_stylebox_override("panel", UIKit.box(Color(0.15, 0.12, 0.3, 0.9), 10, 2, Color(UIKit.PURPLE, 0.45)))
	top.add_child(frame)
	_portrait = TextureRect.new()
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	frame.add_child(_portrait)

	var info := UIKit.vbox(5)
	info.custom_minimum_size.x = 236
	top.add_child(info)
	_name_lbl = UIKit.label("", 22)
	_name_lbl.clip_text = true
	info.add_child(_name_lbl)
	_badges = UIKit.hbox(2)
	_badges.tooltip_text = "Badges — enough of them opens the Spectral Trail (the Haunted Four) and ✈ Fly"
	_badges.mouse_filter = Control.MOUSE_FILTER_PASS
	info.add_child(_badges)
	_pts_lbl = UIKit.label("", 15, Color(1, 1, 1, 0.85))
	info.add_child(_pts_lbl)
	_pts_bar = ProgressBar.new()
	_pts_bar.show_percentage = false
	_pts_bar.custom_minimum_size = Vector2(0, 8)
	_pts_bar.add_theme_stylebox_override("background", UIKit.box(Color(1, 1, 1, 0.12), 4))
	_pts_bar.add_theme_stylebox_override("fill", UIKit.box(BADGE_EARNED, 4))
	info.add_child(_pts_bar)
	_items = HFlowContainer.new()
	_items.add_theme_constant_override("h_separation", 6)
	_items.add_theme_constant_override("v_separation", 4)
	info.add_child(_items)

	_party = UIKit.hbox(6)
	col.add_child(_party)

func present(p: PlayerData, active: bool) -> void:
	modulate = Color(1, 1, 1, 1) if active else Color(0.7, 0.7, 0.74, 0.9)
	_portrait.texture = _trimmed(GameData.trainer_texture(GameData.player_trainer(p)))
	_name_lbl.text = ("▶ " if active else "") + p.player_name + (" ⚔" if p.pvp_tag else "")
	_name_lbl.add_theme_color_override("font_color", p.color)
	if GameState.infinite_points:
		_pts_lbl.text = "%d pts" % p.progress.points
		_pts_bar.hide()
	else:
		_pts_lbl.text = "%d / %d pts" % [p.progress.points, GameState.win_threshold]
		_pts_bar.max_value = GameState.win_threshold
		_pts_bar.value = mini(p.progress.points, GameState.win_threshold)
		_pts_bar.show()
	_fill_badges(p)
	_fill_items(p)
	_fill_party(p, active)

# The trainer art has empty space around the character; crop to the drawn
# pixels so the portrait fills its frame. Cached per texture.
static var _trim_cache: Dictionary = {}

static func _trimmed(tex: Texture2D) -> Texture2D:
	if tex == null:
		return null
	if _trim_cache.has(tex):
		return _trim_cache[tex]
	var out: Texture2D = tex
	var img := tex.get_image()
	if img != null:
		var used := img.get_used_rect()
		if used.size.x > 0 and used.size.y > 0:
			var crop := AtlasTexture.new()
			if tex is AtlasTexture:   # already a slice of a sheet: crop within it
				crop.atlas = (tex as AtlasTexture).atlas
				crop.region = Rect2((tex as AtlasTexture).region.position + Vector2(used.position), Vector2(used.size))
			else:
				crop.atlas = tex
				crop.region = Rect2(used)
			out = crop
	_trim_cache[tex] = out
	return out

# One star per badge the Haunted Four need (Game Settings), gold once earned,
# then "+N" for any beyond that.
func _fill_badges(p: PlayerData) -> void:
	UIKit.clear(_badges)
	var need: int = GameState.trail_badges
	var have: int = p.progress.badge_count()
	for i in need:
		_badges.add_child(UIKit.label("★", 22, BADGE_EARNED if i < have else BADGE_UNEARNED))
	if have > need:
		var extra := UIKit.label("+%d" % (have - need), 16, BADGE_EARNED)
		extra.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_badges.add_child(extra)

# Six spirit slots: the spirit's own picture, a small HP bar, the lead outlined.
func _fill_party(p: PlayerData, active: bool) -> void:
	UIKit.clear(_party)
	for i in Balance.TEAM_MAX:
		var slot := PanelContainer.new()
		slot.custom_minimum_size = SLOT_SIZE
		var lead := i == 0 and i < p.team.size()
		slot.add_theme_stylebox_override("panel", UIKit.box(Color(0.15, 0.12, 0.3, 0.9), 9,
			2, LEAD_BORDER if lead else Color(UIKit.PURPLE, 0.35)))
		_party.add_child(slot)
		if i >= p.team.size():
			continue
		var mon: Dictionary = p.team[i]
		slot.tooltip_text = "%s%s" % [mon.get("name", "?"), "  (lead)" if lead else ""]
		var stack := UIKit.vbox(0)
		slot.add_child(stack)
		var pic := UIKit.sprite(SpiritsData.sprite_tex(String(mon.get("name", "")), "front"), Vector2(SLOT_SIZE.x - 6, SLOT_SIZE.y - 12))
		pic.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var hp_now := int(mon.get("current_hp", 0))
		if hp_now <= 0:
			pic.modulate = Color(1, 1, 1, 0.35)   # fainted
		stack.add_child(pic)
		var bar := UIKit.hp_bar(4)
		UIKit.set_hp(bar, hp_now, int(mon.get("hp", 1)))
		stack.add_child(bar)

# ---------------- gold + hand ----------------
# The row shows gold, then the hand as mini cards (kind colour + icon; CPUs'
# cards face-down), then a "cards n/7" count with a per-kind tooltip.

func _fill_items(p: PlayerData) -> void:
	UIKit.clear(_items)
	_items.add_child(_chip("🪙 %d" % p.inventory.gold))
	var count := _chip("🃏 %d/%d" % [p.inventory.hand.size(), Balance.HAND_SIZE])
	var kinds: Array = []
	for kind in ["capture", "tactic", "field"]:
		var n := p.inventory.cards_of_kind(kind).size()
		if n > 0:
			kinds.append("%d %s" % [n, kind])
	count.tooltip_text = ", ".join(kinds) if not kinds.is_empty() else "no cards"
	_items.add_child(count)
	var strip := UIKit.hbox(3)
	strip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for key in p.inventory.hand:
		strip.add_child(_mini_card("" if p.is_cpu else String(key)))
	for n in Balance.HAND_SIZE - p.inventory.hand.size():
		strip.add_child(_mini_card("-"))   # empty slot
	_items.add_child(strip)

# A tiny card: "" = face-down, "-" = empty slot, else a card key.
func _mini_card(key: String) -> Control:
	var c := Panel.new()
	c.custom_minimum_size = MINI_CARD
	c.mouse_filter = Control.MOUSE_FILTER_PASS
	if key == "-":
		c.add_theme_stylebox_override("panel", UIKit.box(Color(1, 1, 1, 0.04), 4, 1, Color(1, 1, 1, 0.15)))
		return c
	if key == "":
		c.add_theme_stylebox_override("panel", UIKit.box(Color(0.24, 0.17, 0.48), 4, 1, Color(0.66, 0.56, 1.0, 0.8)))
		return c
	var info := CardsData.card(key)
	var col: Color = CardsData.KIND_COLORS.get(info["kind"], Color.GRAY)
	c.add_theme_stylebox_override("panel", UIKit.box(col.darkened(0.25), 4, 1, col.lightened(0.4)))
	c.tooltip_text = "%s — %s" % [info["name"], info["desc"]]
	var icon := UIKit.label(String(info.get("icon", "?")), 13)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(icon)
	return c

func _chip(text: String) -> Control:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", UIKit.box(Color(0.22, 0.18, 0.38, 0.85), 8, 1,
		Color(UIKit.PURPLE, 0.6), Vector2(8, 3)))
	chip.mouse_filter = Control.MOUSE_FILTER_PASS
	chip.add_child(UIKit.label(text, 16))
	return chip
