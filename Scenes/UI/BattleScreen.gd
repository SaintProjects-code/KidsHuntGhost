extends MenuWindow
## Team-vs-team auto-battler screen, laid out as two horizontal rows of cards:
##   • ENEMY row on top, YOUR team below — each row headed by the trainer in a
##     coloured circle (your player colour / enemy red), "VS" between them
##   • one card per spirit: name banner, sprite, green HP bar, compact stat
##     line (A+3/D-2 style buffs); fainted cards dim, the active pair glows
##   • cards ANIMATE: lunge toward the opponent when attacking, shake when an
##     ability fires or when they take damage
##   • battle log bottom-left; Next Round / Skip→Continue / 2x buttons beside it
##
## Reused for wild encounters, gyms, Elite Four and Gary.
## present(team, opp_team, title, player_color); emits finished(player_won).
## Fights run on copies (so buffs/statuses don't stick), but the DAMAGE is
## real: when the battle ends each spirit's HP is written back to the actual
## team. Cities fully heal; a full wipe teleports the player home.

signal finished(player_won: bool)

const CARD_SIZE := Vector2(150, 142)   # fixed slot so cards can animate freely
const TRAINER_W := 96.0                # trainer column width (VS aligns to it)
const LUNGE := 26.0                    # attack lunge distance (px)

const FIELD_BG := Color(0.106, 0.086, 0.196)       # game's dark purple
const CARD_BG := Color(0.55, 0.76, 0.47)           # green field per card
const BANNER_BG := Color(0.07, 0.1, 0.06, 0.85)    # dark name banner
const HP_GREEN := Color(0.4, 0.85, 0.35)
const HP_YELLOW := Color(0.95, 0.85, 0.3)
const HP_RED := Color(0.9, 0.3, 0.25)
const ACTIVE_GOLD := Color(1.0, 0.85, 0.3)
const ENEMY_RED := Color(0.85, 0.3, 0.3)

# status badge shown on a card while its spirit is statused
const STATUS_ABBR := {"stun": "STN", "sleep": "SLP", "poison": "PSN", "burn": "BRN", "confuse": "CNF"}
const STATUS_COLORS := {
	"stun": Color(0.8, 0.68, 0.1), "sleep": Color(0.42, 0.47, 0.62),
	"poison": Color(0.55, 0.28, 0.7), "burn": Color(0.85, 0.4, 0.12),
	"confuse": Color(0.8, 0.35, 0.55),
}

# Battle-log palette: your side blue, enemy red, abilities yellow, damage dark
# red, healing green, everything else the default white.
const LOG_YOU := "5aa6ff"
const LOG_ENEMY := "ff6a6a"
const LOG_ABILITY := "ffd24d"
const LOG_DMG := "b02a2a"
const LOG_HEAL := "4fd24f"

var _team: Array = []
var _opp: Array = []
var _src_team: Array = []            # the caller's real team — HP syncs back
var _active: int = 0
var _opp_active: int = 0
var _over: bool = false
var _won: bool = false
var _speed: float = 1.0               # 1x / 2x / 3x pacing (auto-play + animations)
var _auto: bool = false               # human auto-play running (Next Round stops it)
var _auto_running: bool = false       # an auto loop (human or CPU) is active
var _skipping: bool = false           # no animations while resolving instantly
var _busy: bool = false               # a sequence (opening / round) is playing
var _opening_pending: bool = false    # play the intro once the window shows
var _pvp_names: Array = []            # [your name, enemy name] in PvP battles
var _detached: bool = false           # panel pulled out of the CenterContainer
var _round_num: int = 0
var _star_credits: Dictionary = {}   # team index -> stars earned this battle
var _ko_stars: Dictionary = {}       # team index -> KO stars this battle (capped)

const MAX_KO_STARS := 2.0   # per spirit per battle — stops over-levelling
const FATIGUE_START := 15   # from this round on, both leads take escalating chip damage
const MAX_ROUNDS := 60      # absolute cap — decide by remaining HP if ever reached

var _title: Label
var _team_row: HBoxContainer          # your card row (bottom)
var _opp_row: HBoxContainer           # enemy card row (top)
var _team_cards: Array = []   # per spirit: {slot, card, bg, hp, hp_text, stats}
var _opp_cards: Array = []
var _team_disc: TrainerDisc
var _opp_disc: TrainerDisc
var _team_name_lbl: Label
var _opp_name_lbl: Label
var _log: RichTextLabel
var _next_btn: Button
var _skip_btn: Button
var _continue_btn: Button
var _speed_btn: Button

func _ready() -> void:
	# Sized to stay inside the 1152×648 design viewport with room to spare.
	var col := _init_window(1080, 0)
	col.add_theme_constant_override("separation", 6)
	# window frame keeps the game's dark-purple theme
	var field := StyleBoxFlat.new()
	field.bg_color = FIELD_BG
	field.corner_radius_top_left = 18
	field.corner_radius_top_right = 18
	field.corner_radius_bottom_left = 18
	field.corner_radius_bottom_right = 18
	field.border_width_left = 3
	field.border_width_top = 3
	field.border_width_right = 3
	field.border_width_bottom = 3
	field.border_color = Color(0.541, 0.435, 0.965, 0.7)
	panel.add_theme_stylebox_override("panel", field)

	_title = _title_label("Battle", 18)
	col.add_child(_title)

	# Enemy row on top, your team below (Pokémon-style), so attack lunges move
	# toward the opposing row. "VS" sits between them, under the trainers.
	var opp_side := _make_team_row(col, false)
	_opp_row = opp_side["cards"]
	_opp_disc = opp_side["disc"]
	_opp_name_lbl = opp_side["name"]

	var vs_row := HBoxContainer.new()
	col.add_child(vs_row)
	var vs := Label.new()
	vs.text = "VS"
	vs.add_theme_font_size_override("font_size", 20)
	vs.add_theme_color_override("font_color", ACTIVE_GOLD)
	vs.custom_minimum_size = Vector2(TRAINER_W, 0)
	vs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vs_row.add_child(vs)

	var team_side := _make_team_row(col, true)
	_team_row = team_side["cards"]
	_team_disc = team_side["disc"]
	_team_name_lbl = team_side["name"]

	# Bottom strip: battle log on the left, the three buttons beside it.
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	col.add_child(bottom)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.custom_minimum_size = Vector2(0, 140)
	_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log.add_theme_font_size_override("normal_font_size", 14)
	_log.add_theme_color_override("default_color", Color.WHITE)
	_log.scroll_following = true
	var log_bg := StyleBoxFlat.new()
	log_bg.bg_color = Color(0.05, 0.05, 0.08, 0.85)
	log_bg.corner_radius_top_left = 8
	log_bg.corner_radius_top_right = 8
	log_bg.corner_radius_bottom_left = 8
	log_bg.corner_radius_bottom_right = 8
	log_bg.content_margin_left = 8
	log_bg.content_margin_right = 8
	log_bg.content_margin_top = 4
	log_bg.content_margin_bottom = 4
	_log.add_theme_stylebox_override("normal", log_bg)
	bottom.add_child(_log)

	var btns := VBoxContainer.new()
	btns.add_theme_constant_override("separation", 8)
	btns.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bottom.add_child(btns)
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 8)
	btns.add_child(brow)
	_next_btn = _button("Next Round", _on_next, 36)
	_next_btn.add_theme_font_size_override("font_size", 14)
	_next_btn.custom_minimum_size = Vector2(110, 36)
	brow.add_child(_next_btn)
	_skip_btn = _button("Skip", _on_skip, 36)
	_skip_btn.add_theme_font_size_override("font_size", 14)
	_skip_btn.custom_minimum_size = Vector2(90, 36)
	brow.add_child(_skip_btn)
	_continue_btn = _button("Continue", func(): finished.emit(_won), 36)
	_continue_btn.add_theme_font_size_override("font_size", 14)
	_continue_btn.custom_minimum_size = Vector2(90, 36)
	_continue_btn.hide()
	brow.add_child(_continue_btn)
	_speed_btn = _button("Auto ▶", _on_speed_toggle, 36)
	_speed_btn.add_theme_font_size_override("font_size", 14)
	btns.add_child(_speed_btn)

	# layout is only final once shown — refit every time the window opens, and
	# start the battle intro (it plays step by step, so it needs to be seen)
	visibility_changed.connect(func():
		if visible:
			_fit_to_screen()
			if _opening_pending:
				_opening_pending = false
				_opening())
	hide()

# One team row: the trainer in a coloured circle (+ side label) then the cards.
func _make_team_row(parent: Control, is_player: bool) -> Dictionary:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	parent.add_child(h)
	var tcol := VBoxContainer.new()
	tcol.custom_minimum_size = Vector2(TRAINER_W, 0)
	tcol.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(tcol)
	var disc := TrainerDisc.new()
	disc.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tcol.add_child(disc)
	var nm := Label.new()
	nm.text = "YOU" if is_player else "ENEMY"
	nm.add_theme_font_size_override("font_size", 12)
	nm.modulate = Color(1, 1, 1, 0.75)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tcol.add_child(nm)
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 10)
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(cards)
	return {"cards": cards, "disc": disc, "name": nm}

func present(team: Array, opp_team: Array, title: String, player_color: Color = Color.WHITE, atk_mod: int = 0,
		player_trainer: Array = [], enemy_trainer: Array = [], pvp_names: Array = []) -> void:
	# trainer circles (named sprites from Assets/Trainer, with fallbacks) —
	# labelled with the REAL trainer's name (a CPU's battle isn't "YOU")
	_team_disc.set_data(GameData.trainer_texture(player_trainer), player_color)
	_opp_disc.set_data(GameData.trainer_texture(enemy_trainer), ENEMY_RED)
	_team_name_lbl.text = pvp_names[0] if pvp_names.size() == 2 else GameState.current_player().player_name
	_opp_name_lbl.text = pvp_names[1] if pvp_names.size() == 2 else "ENEMY"
	_src_team = team
	_team = _copy_team(team)
	_opp = _copy_team(opp_team)
	# Event-tile status effect: blessed (+1 ATK) or spooked (-1 ATK), this
	# battle only — applied to the copies, never the real team.
	if atk_mod != 0:
		for m in _team:
			m["atk"] = clampi(int(m.get("atk", 1)) + atk_mod, 1, 6)
	_active = 0
	_opp_active = 0
	_over = false
	_won = false
	_skipping = false
	_speed = 1.0
	_auto = false
	_speed_btn.text = "Auto ▶"
	_round_num = 0
	_star_credits = {}
	_ko_stars = {}
	_log.clear()   # fresh battle log every fight
	_continue_btn.hide()
	_skip_btn.show()
	_next_btn.disabled = false
	_skip_btn.disabled = false
	_title.text = title
	_pvp_names = pvp_names
	_busy = false
	if atk_mod > 0:
		_logln("[color=#9f9]Blessed! ATK +%d this battle.[/color]" % atk_mod)
	elif atk_mod < 0:
		_logln("[color=#f99]Spooked! ATK %d this battle.[/color]" % atk_mod)
	_build_cards()
	_refresh()
	# The intro (send-outs, match-start abilities, entry effects) plays step by
	# step, so it starts once the window is actually on screen.
	if visible:
		call_deferred("_opening")   # gauntlets re-present while already shown
	else:
		_opening_pending = true
	_fit_to_screen()

# Guarantee the window fits the game view AND stays centred. A CenterContainer
# can't lift an oversized child above the top edge (it pins it to y=0), so we
# pull the panel out and place the scaled panel ourselves, dead-centre.
func _fit_to_screen() -> void:
	if not _detached:
		var cc: Node = panel.get_parent()
		if cc != self:
			cc.remove_child(panel)
			add_child(panel)          # now a plain child we position by hand
		_detached = true
	panel.scale = Vector2.ONE
	panel.size = panel.get_combined_minimum_size()
	await get_tree().process_frame
	await get_tree().process_frame   # let the child layout settle
	var need: Vector2 = panel.get_combined_minimum_size()
	panel.size = need
	if need.y <= 0.0:
		return
	var vp: Vector2 = get_viewport_rect().size
	var avail: Vector2 = vp - Vector2(24, 24)
	var s: float = minf(1.0, minf(avail.x / maxf(1.0, need.x), avail.y / maxf(1.0, need.y)))
	panel.pivot_offset = Vector2.ZERO           # scale from the top-left
	panel.scale = Vector2(s, s)
	panel.position = (vp - need * s) * 0.5       # centre the scaled panel

# Stars earned during the battle (KOs + surviving a win), keyed by the index
# into the ORIGINAL team array passed to present(). Cleared on read.
func take_star_credits() -> Dictionary:
	var out := _star_credits
	_star_credits = {}
	return out

func _copy_team(src: Array) -> Array:
	var out: Array = []
	for i in src.size():
		var c: Dictionary = src[i].duplicate(true)
		# battles start from the spirit's REAL current HP (damage persists)
		c["current_hp"] = clampi(int(src[i].get("current_hp", c.get("hp", 1))), 0, int(c.get("hp", 1)))
		c["_oi"] = i   # index into the caller's array, for star credits
		# remember battle-start stats so the cards can show buffs/debuffs
		for key in ["atk", "def", "spd"]:
			c["_base_" + key] = int(c.get(key, 1))
		out.append(c)
	return out

# Credit stars to a spirit. KO stars are CAPPED at MAX_KO_STARS per battle
# (survival bonuses aren't). Returns how much was actually granted.
func _credit_stars(mon: Dictionary, amount: float, from_ko: bool = true) -> float:
	var oi: int = int(mon.get("_oi", -1))
	if oi < 0:
		return 0.0
	if from_ko:
		var so_far: float = float(_ko_stars.get(oi, 0.0))
		amount = minf(amount, MAX_KO_STARS - so_far)
		if amount <= 0.0:
			return 0.0
		_ko_stars[oi] = so_far + amount
	_star_credits[oi] = float(_star_credits.get(oi, 0.0)) + amount
	return amount

# ---------------- spirit cards ----------------

func _build_cards() -> void:
	for box in [_team_row, _opp_row]:
		for c in box.get_children():
			c.queue_free()
	_team_cards = []
	_opp_cards = []
	for m in _team:
		_team_cards.append(_make_card(m, true))
	for m in _opp:
		_opp_cards.append(_make_card(m, false))

# A card like the sketch: name banner, sprite, green HP bar, stat line. The
# card lives inside a fixed-size slot so its lunge/shake animations can move
# it freely without the row container fighting back.
func _make_card(mon: Dictionary, is_player: bool) -> Dictionary:
	var slot := Control.new()
	slot.custom_minimum_size = CARD_SIZE
	# never stretch to a sibling's height — every card stays the same size
	slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	(_team_row if is_player else _opp_row).add_child(slot)

	var card := PanelContainer.new()
	card.clip_contents = true   # content can never spill past the slot
	var bg := StyleBoxFlat.new()
	bg.bg_color = CARD_BG
	bg.corner_radius_top_left = 8
	bg.corner_radius_top_right = 8
	bg.corner_radius_bottom_left = 8
	bg.corner_radius_bottom_right = 8
	bg.content_margin_left = 6
	bg.content_margin_right = 6
	bg.content_margin_top = 4
	bg.content_margin_bottom = 4
	card.add_theme_stylebox_override("panel", bg)
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	slot.add_child(card)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	card.add_child(vb)

	# dark name banner
	var banner := PanelContainer.new()
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = BANNER_BG
	bsb.corner_radius_top_left = 5
	bsb.corner_radius_top_right = 5
	bsb.corner_radius_bottom_left = 5
	bsb.corner_radius_bottom_right = 5
	bsb.content_margin_left = 6
	bsb.content_margin_right = 6
	bsb.content_margin_top = 1
	bsb.content_margin_bottom = 1
	banner.add_theme_stylebox_override("panel", bsb)
	vb.add_child(banner)
	var name_lbl := Label.new()
	name_lbl.text = "%s %s" % [mon.get("name", "?"), SpiritsData.star_text(mon.get("stars", 0))]
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.clip_text = true
	banner.add_child(name_lbl)

	# the sprite fills the middle of the card — both sides show the FRONT of
	# the spirit, facing its own trainer
	var sprite := TextureRect.new()
	sprite.texture = SpiritsData.sprite_tex(mon.get("name", ""), "front")
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.custom_minimum_size = Vector2(0, 56)
	sprite.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(sprite)

	# green HP bar in a dark frame
	var hp := ProgressBar.new()
	hp.show_percentage = false
	hp.custom_minimum_size = Vector2(0, 10)
	hp.max_value = mon.get("hp", 1)
	var hp_bg := StyleBoxFlat.new()
	hp_bg.bg_color = Color(0.07, 0.1, 0.06, 0.9)
	hp_bg.corner_radius_top_left = 4
	hp_bg.corner_radius_top_right = 4
	hp_bg.corner_radius_bottom_left = 4
	hp_bg.corner_radius_bottom_right = 4
	hp.add_theme_stylebox_override("background", hp_bg)
	vb.add_child(hp)

	# numbers + live stat line under the bar (buffs ▲ green, debuffs ▼ red)
	var info := HBoxContainer.new()
	info.add_theme_constant_override("separation", 4)
	vb.add_child(info)
	var hp_text := Label.new()
	hp_text.add_theme_font_size_override("font_size", 10)
	hp_text.add_theme_color_override("font_color", Color(0.12, 0.25, 0.1))
	info.add_child(hp_text)
	var stats := RichTextLabel.new()
	stats.bbcode_enabled = true
	# HARD single line: no fit_content growth, no wrapping — a long buffed
	# stat line (e.g. "A4▲1 D1 S7▲3") must never inflate the card
	stats.fit_content = false
	stats.autowrap_mode = TextServer.AUTOWRAP_OFF
	stats.clip_contents = true
	stats.scroll_active = false
	stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats.custom_minimum_size = Vector2(0, 14)
	stats.add_theme_font_size_override("normal_font_size", 10)
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(stats)

	# status badge ("SLP 2", "PSN 3"…) pinned to the card's top-right corner,
	# shown while the spirit has a status effect
	var status_bg := StyleBoxFlat.new()
	status_bg.bg_color = Color(0.5, 0.5, 0.5)
	status_bg.corner_radius_top_left = 6
	status_bg.corner_radius_top_right = 6
	status_bg.corner_radius_bottom_left = 6
	status_bg.corner_radius_bottom_right = 6
	status_bg.border_width_left = 1
	status_bg.border_width_top = 1
	status_bg.border_width_right = 1
	status_bg.border_width_bottom = 1
	status_bg.border_color = Color(0, 0, 0, 0.6)
	var status := Label.new()
	status.add_theme_font_size_override("font_size", 10)
	status.add_theme_color_override("font_color", Color.WHITE)
	status.add_theme_stylebox_override("normal", status_bg)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.anchor_left = 1.0
	status.anchor_right = 1.0
	status.offset_left = -52
	status.offset_right = -4
	status.offset_top = 20
	status.offset_bottom = 37
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status.hide()
	slot.add_child(status)   # on the slot, above the card, so it never dims

	return {"slot": slot, "card": card, "bg": bg, "hp": hp, "hp_text": hp_text,
		"stats": stats, "status": status, "status_bg": status_bg}

func _refresh() -> void:
	_refresh_side(_team, _team_cards, _active)
	_refresh_side(_opp, _opp_cards, _opp_active)

# Compact "A+3 D2 S-1" style line for the narrow cards: green when buffed
# above the battle-start value, red when debuffed, plain grey otherwise.
func _stat_line(mon: Dictionary) -> String:
	var parts: Array = []
	for pair in [["atk", "A"], ["def", "D"], ["spd", "S"]]:
		var cur: int = int(mon.get(pair[0], 1))
		var base: int = int(mon.get("_base_" + pair[0], cur))
		if cur > base:
			parts.append("[color=#0d5c17]%s%d▲%d[/color]" % [pair[1], cur, cur - base])
		elif cur < base:
			parts.append("[color=#8e1f1f]%s%d▼%d[/color]" % [pair[1], cur, base - cur])
		else:
			parts.append("[color=#2d4426]%s%d[/color]" % [pair[1], cur])
	return " ".join(parts)

func _refresh_side(team: Array, cards: Array, active: int) -> void:
	for i in cards.size():
		var mon: Dictionary = team[i]
		var c: Dictionary = cards[i]
		var hp_now: int = mon.get("current_hp", 0)
		var hp_max: int = mon.get("hp", 1)
		(c.hp as ProgressBar).max_value = hp_max
		(c.hp as ProgressBar).value = hp_now
		(c.hp_text as Label).text = "%d/%d" % [hp_now, hp_max]
		(c.stats as RichTextLabel).text = _stat_line(mon)
		# HP bar colour: green -> yellow -> red
		var ratio := float(hp_now) / float(hp_max)
		var fill := StyleBoxFlat.new()
		fill.bg_color = HP_GREEN if ratio > 0.5 else (HP_YELLOW if ratio > 0.2 else HP_RED)
		fill.corner_radius_top_left = 4
		fill.corner_radius_top_right = 4
		fill.corner_radius_bottom_left = 4
		fill.corner_radius_bottom_right = 4
		(c.hp as ProgressBar).add_theme_stylebox_override("fill", fill)
		# once a faint has played out, the card leaves the row and the rest
		# slide forward; a revived spirit's card comes back
		(c.slot as Control).visible = not mon.get("_gone", false)
		# status badge: "SLP 2" etc. while statused, hidden when healthy
		var st: Dictionary = mon.get("_status", {})
		var badge: Label = c.status
		if st.is_empty() or hp_now <= 0:
			badge.hide()
		else:
			var kind := String(st.get("kind", ""))
			badge.text = "%s %d" % [STATUS_ABBR.get(kind, kind.to_upper()), maxi(1, int(st.get("rounds", 1)))]
			(c.status_bg as StyleBoxFlat).bg_color = STATUS_COLORS.get(kind, Color(0.5, 0.5, 0.5))
			badge.show()
		# fainted spirits grey out; the active pair gets a golden glow
		var bg_sb: StyleBoxFlat = c.bg
		if hp_now <= 0:
			(c.card as Control).modulate = Color(0.45, 0.45, 0.45, 0.7)
			_set_card_glow(bg_sb, false)
		elif i == active and not _over:
			(c.card as Control).modulate = Color(1, 1, 1, 1)
			_set_card_glow(bg_sb, true)
		else:
			(c.card as Control).modulate = Color(0.82, 0.82, 0.85, 1)
			_set_card_glow(bg_sb, false)

func _set_card_glow(sb: StyleBoxFlat, on: bool) -> void:
	if on:
		sb.border_width_left = 3
		sb.border_width_top = 3
		sb.border_width_right = 3
		sb.border_width_bottom = 3
		sb.border_color = ACTIVE_GOLD
		sb.shadow_color = Color(ACTIVE_GOLD, 0.5)
		sb.shadow_size = 6
	else:
		sb.border_width_left = 0
		sb.border_width_top = 0
		sb.border_width_right = 0
		sb.border_width_bottom = 0
		sb.shadow_size = 0

# ---------------- battle flow ----------------

func _on_next() -> void:
	# Next Round drops out of auto-play and returns to manual, round-speed play.
	_auto = false
	_speed = 1.0
	_update_speed_btn()
	if not _over and not _busy:
		_round()

# ── CPU auto-play ─────────────────────────────────────────────────────────────
# Plays a whole battle by itself ON SCREEN (CPU turns): the intro runs, rounds
# fire at a watchable pace, and the window lingers on the result. The caller
# opens the window first (which starts the intro) and closes it afterwards.
func autoplay() -> void:
	_next_btn.disabled = true    # spectators don't get to drive
	_skip_btn.disabled = true
	_auto_running = true         # the speed button can still change the pace
	_update_speed_btn()
	while not _over:
		await get_tree().create_timer(0.5 / _speed).timeout
		if not _busy and not _over:
			await _round()
	_auto_running = false
	_continue_btn.hide()         # no button — the caller closes the window
	await get_tree().create_timer(1.8).timeout

# Resolve the whole battle instantly (no animations, no beats).
func _on_skip() -> void:
	_auto = false          # skipping overrides auto-play
	_skip_btn.disabled = true
	_skipping = true
	while _busy:            # let the sequence in flight flush through
		await get_tree().process_frame
	while not _over:
		await _round()
	_skipping = false

# The speed button drives AUTO-PLAY: the first press starts the battle playing
# itself; each further press cycles the pace 1x → 2x → 3x → 1x. Next Round stops
# it and returns to manual, one-round-at-a-time play.
func _on_speed_toggle() -> void:
	if _auto_running:
		# already auto-playing (this battle, or a spectated CPU one) — change pace
		_speed = 1.0 if _speed >= 3.0 else _speed + 1.0
	else:
		_auto = true
		_run_auto()          # fire-and-forget; runs until _over or Next Round
	_update_speed_btn()

# Play rounds back-to-back while auto-play is on. Reads _speed each loop so the
# button changes pace live; stops the moment _auto clears or the battle ends.
func _run_auto() -> void:
	_auto_running = true
	_update_speed_btn()
	while _auto and not _over:
		while _busy and _auto and not _over:
			await get_tree().process_frame
		if not _auto or _over:
			break
		await _round()
		if not _auto or _over:
			break
		await get_tree().create_timer(0.4 / _speed).timeout
	_auto = false
	_auto_running = false
	_update_speed_btn()

func _update_speed_btn() -> void:
	_speed_btn.text = ("▶ %dx" % int(_speed)) if _auto_running else "Auto ▶"

# ---------------- card animations ----------------

func _card_of(mon: Dictionary) -> Control:
	var i: int = _team.find(mon)
	if i >= 0 and i < _team_cards.size():
		return _team_cards[i]["card"]
	i = _opp.find(mon)
	if i >= 0 and i < _opp_cards.size():
		return _opp_cards[i]["card"]
	return null

# Kill any running animation on a card and snap it back to its slot.
func _fresh_tween(c: Control) -> Tween:
	var old = c.get_meta("anim", null)
	if old is Tween and old.is_valid():
		old.kill()
	c.position = Vector2.ZERO
	var tw := c.create_tween()
	c.set_meta("anim", tw)
	return tw

# Attack: the card lunges toward the opposing row (yours up, enemy down).
func _anim_attack(mon: Dictionary, delay: float = 0.0) -> void:
	if _skipping or not visible:
		return
	var c := _card_of(mon)
	if c == null:
		return
	var dy: float = -LUNGE if _team.has(mon) else LUNGE
	var tw := _fresh_tween(c)
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_property(c, "position:y", dy, 0.12 / _speed) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "position:y", 0.0, 0.16 / _speed) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

# Ability: a smooth left-right sway, clearly different from the damage shake.
func _anim_ability(mon: Dictionary, delay: float = 0.0) -> void:
	if _skipping or not visible:
		return
	var c := _card_of(mon)
	if c == null:
		return
	var tw := _fresh_tween(c)
	if delay > 0.0:
		tw.tween_interval(delay)
	for off in [12.0, -12.0, 8.0, 0.0]:
		tw.tween_property(c, "position:x", off, 0.11 / _speed) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

# Taking damage: a fast rattle.
func _anim_shake(mon: Dictionary, delay: float = 0.0) -> void:
	if _skipping or not visible:
		return
	var c := _card_of(mon)
	if c == null:
		return
	var tw := _fresh_tween(c)
	if delay > 0.0:
		tw.tween_interval(delay)
	for off in [6.0, -6.0, 5.0, -5.0, 3.0, 0.0]:
		tw.tween_property(c, "position:x", off, 0.035 / _speed)

# ---------------- sequenced playback ----------------
# Every battle action plays one at a time: log line + animation, then a beat.
# Skipping (or a hidden window) makes beats instant so logic still resolves.

func _beat(time: float = 0.5) -> void:
	_refresh()
	if _skipping or not visible:
		return
	await get_tree().create_timer(time / _speed).timeout

# An ability that logs outside _ability_line: sway the card, log, wait a beat.
func _ability_note(mon: Dictionary, text: String) -> void:
	_anim_ability(mon)
	_logln(text)
	await _beat(0.55)

# "Go, X!" — or in PvP, both trainers announce their picks by name.
func _sendout_line(is_me: bool) -> String:
	var mon: Dictionary = _team[_active] if is_me else _opp[_opp_active]
	if _pvp_names.size() == 2:
		var trainer: String = _pvp_names[0] if is_me else _pvp_names[1]
		return "%s chooses %s!" % [trainer, _who(mon)]
	if is_me:
		return "Go, %s!" % _who(mon)
	return "Opponent sends out %s!" % _who(mon)

# The battle intro, played step by step once the window is visible.
func _opening() -> void:
	_busy = true
	if _pvp_names.size() == 2:
		_logln("Battle start!")
		await _beat(0.4)
		_logln(_sendout_line(true))
		await _beat(0.5)
		_logln(_sendout_line(false))
		await _beat(0.5)
	else:
		_logln("Battle start! Go, %s!" % _who(_team[_active]))
		await _beat(0.5)
	await _apply_traits()
	await _apply_match_start()
	await _on_entry(true)
	await _on_entry(false)
	await _check_monument(_team)
	await _check_monument(_opp)
	_refresh()
	_busy = false

# ── traits (permanent quirks earned from events — see EventsData) ────────────
# Battle-start stat traits apply here; Sleepyhead / Cursed Wound / Regrowth
# tick during rounds (_trait_tick).
func _apply_traits() -> void:
	for side in [_team, _opp]:
		for m in side:
			for key in m.get("traits", []):
				match String(key):
					"swift_soul":
						_buff(m, "spd", 3)
						await _trait_note(m, "Swift Soul", "SPD +3")
					"heavy_boots":
						_buff(m, "spd", -3)
						await _trait_note(m, "Heavy Boots", "SPD −3")
					"brave_heart":
						_buff(m, "atk", 2)
						await _trait_note(m, "Brave Heart", "ATK +2")
					"timid":
						_buff(m, "atk", -2)
						await _trait_note(m, "Timid", "ATK −2")
					"stone_skin":
						_buff(m, "def", 2)
						await _trait_note(m, "Stone Skin", "DEF +2")
					"brittle_bones":
						_buff(m, "def", -2)
						await _trait_note(m, "Brittle Bones", "DEF −2")

func _trait_note(m: Dictionary, trait_name: String, effect: String) -> void:
	await _ability_note(m, "[Trait] ✦%s %s %s" % [trait_name, _who(m), effect])

func _has_trait(m: Dictionary, key: String) -> bool:
	return m.get("traits", []).has(key)

# Round-start trait ticks for an active fighter; can cancel its action.
func _trait_tick(m: Dictionary, acts: bool) -> bool:
	if _has_trait(m, "sleepyhead") and _round_num == 1:
		acts = false
		_logln("[Trait] ✦Sleepyhead %s snoozes through round 1!" % _who(m))
		await _beat(0.45)
	if _has_trait(m, "cursed_wound"):
		m["current_hp"] = maxi(1, int(m.get("current_hp", 1)) - 3)
		_logln("[Trait] ✦Cursed Wound %s loses 3 HP." % _who(m))
		await _beat(0.3)
	if _has_trait(m, "regrowth") and int(m.get("current_hp", 0)) < int(m.get("hp", 1)):
		_heal_mon(m, 3)
		_logln("[Trait] ✦Regrowth %s heals 3 HP." % _who(m))
		await _beat(0.3)
	return acts

# A fainted spirit leaves only AFTER its damage shake has played: log the
# faint, pull its card from the row (the rest slide forward), send the next.
func _faint(mon: Dictionary, is_me: bool) -> void:
	_logln("%s fainted!" % _who(mon))
	await _beat(0.45)
	# Fallen: surviving allies grow stronger with every loss (uncapped)
	for a in (_team if is_me else _opp):
		if a != mon and int(a.get("current_hp", 0)) > 0 and _has(a, "fallen"):
			_buff(a, "atk", 1)
			_buff(a, "def", 1)
			await _ability_line("Passive", a, "Fallen", "avenges the fallen — ATK/DEF +1")
	# Soul Heart: an ally's death saps the ENEMY team's power (stacks)
	var sh_side: Array = _team if is_me else _opp
	var sh_foes: Array = _opp if is_me else _team
	var sh_holder: Dictionary = {}
	for sh in sh_side:
		if sh != mon and int(sh.get("current_hp", 0)) > 0 and _has(sh, "soul_heart"):
			sh_holder = sh
			break
	if not sh_holder.is_empty():
		for o in sh_foes:
			if int(o.get("current_hp", 0)) > 0:
				_buff(o, "atk", -2)
				_buff(o, "def", -2)
		await _ability_line("Passive", sh_holder, "Soul Heart", "the enemy team is sapped - ATK/DEF -2")
	await _check_monument(sh_side)
	mon["_gone"] = true
	_refresh()
	await _beat(0.35)
	if is_me:
		_active += 1
		while _active < _team.size() and int(_team[_active].get("current_hp", 0)) <= 0:
			_team[_active]["_gone"] = true   # skip allies already downed (e.g. by Electric Field)
			_active += 1
		if _active >= _team.size():
			_end(false)
		else:
			_logln(_sendout_line(true))
			await _beat(0.4)
			await _on_entry(true)
	else:
		_opp_active += 1
		while _opp_active < _opp.size() and int(_opp[_opp_active].get("current_hp", 0)) <= 0:
			_opp[_opp_active]["_gone"] = true
			_opp_active += 1
		if _opp_active >= _opp.size():
			_end(true)
		else:
			_logln(_sendout_line(false))
			await _beat(0.4)
			await _on_entry(false)

func _round() -> void:
	if _over or _busy:
		return
	_busy = true
	_round_num += 1
	_logln("[color=#a89ae0]— Round %d —[/color]" % _round_num)
	var me: Dictionary = _team[_active]
	var op: Dictionary = _opp[_opp_active]
	# status ticks decide who can act this round
	var me_acts: bool = await _process_status(me)
	var op_acts: bool = await _process_status(op)
	# trait ticks (Sleepyhead / Cursed Wound / Regrowth)
	me_acts = await _trait_tick(me, me_acts)
	op_acts = await _trait_tick(op, op_acts)
	# round-start abilities fire "at the same time" → faster spirit goes first
	var order: Array = [me, op] if int(me.get("spd", 0)) >= int(op.get("spd", 0)) else [op, me]
	for actor in order:
		var foe: Dictionary = op if actor == me else me
		for slot in 2:
			await _round_start_abilities(actor, foe, slot, true)
	# Bench spirits also fire their non-lead round-start abilities each round.
	await _bench_round_start(_team, _active, op)
	await _bench_round_start(_opp, _opp_active, me)
	# A spirit dropped to 0 by a status tick or round-start ability can't strike,
	# and nobody swings at one that's already down.
	if me.get("spd", 0) >= op.get("spd", 0):
		if me_acts and me["current_hp"] > 0 and op["current_hp"] > 0:
			await _strike(me, op, true)
		if op_acts and op["current_hp"] > 0 and me["current_hp"] > 0:
			await _strike(op, me, false)
	else:
		if op_acts and op["current_hp"] > 0 and me["current_hp"] > 0:
			await _strike(op, me, false)
		if me_acts and me["current_hp"] > 0 and op["current_hp"] > 0:
			await _strike(me, op, true)
	# Helping Hand: a bench ally leaps in front of a hurt lead
	await _helping_hand(_team, _active)
	await _helping_hand(_opp, _opp_active)
	# Helping Hand may have swapped the lead — re-point to the current fighters
	me = _team[_active]
	op = _opp[_opp_active]
	# EXHAUSTION: after FATIGUE_START rounds both active fighters take escalating
	# UNHEALABLE chip damage each round. This breaks heal-loop stalemates (an
	# enemy that heals exactly as much as you deal) so battles always end.
	if _round_num >= FATIGUE_START:
		var burn: int = (_round_num - FATIGUE_START + 1) * 5
		if int(me.get("current_hp", 0)) > 0:
			me["current_hp"] = maxi(0, int(me["current_hp"]) - burn)
		if int(op.get("current_hp", 0)) > 0:
			op["current_hp"] = maxi(0, int(op["current_hp"]) - burn)
		_logln("[color=#e0b060]Exhaustion sets in — both fighters lose %d HP![/color]" % burn)
		await _beat(0.35)
	# Vengeance fires before faint checks so its KOs resolve this round
	if me["current_hp"] <= 0:
		await _vengeance(_team, op)
	if op["current_hp"] <= 0:
		await _vengeance(_opp, me)
	# Independent checks (not elif): abilities like Destiny Bond / Explosion
	# can take both fighters down in the same round.
	if op["current_hp"] <= 0:
		await _faint(op, false)
	if not _over and me["current_hp"] <= 0:
		await _faint(me, true)
	# Absolute backstop: if a battle somehow reaches the cap, end it by whoever
	# has more total HP left (the player wins a tie).
	if not _over and _round_num >= MAX_ROUNDS:
		_logln("[color=#e0b060]The battle drags on too long — judged by remaining HP![/color]")
		_end(_team_hp() >= _opp_hp())
	_refresh()
	_busy = false

func _team_hp() -> int:
	var n := 0
	for m in _team:
		n += maxi(0, int(m.get("current_hp", 0)))
	return n

func _opp_hp() -> int:
	var n := 0
	for m in _opp:
		n += maxi(0, int(m.get("current_hp", 0)))
	return n

# Living bench members with Vengeance avenge a fallen ally on the enemy lead.
func _vengeance(side: Array, enemy_active: Dictionary) -> void:
	for j in side.size():
		var b: Dictionary = side[j]
		if int(b.get("current_hp", 0)) > 0 and _has(b, "vengeance") and int(enemy_active.get("current_hp", 0)) > 0 and not _ab_immune(enemy_active):
			var hit: int = 30
			enemy_active["current_hp"] = maxi(0, int(enemy_active.get("current_hp", 0)) - hit)
			await _ability_line("Passive", b, "Vengeance", "%d damage to %s" % [hit, _who(enemy_active)])
			if int(enemy_active["current_hp"]) <= 0 and side == _team:
				var _granted := _credit_stars(b, _ko_credit(b, enemy_active))

# Helping Hand: once per battle each, a bench ally swaps in when the lead
# drops below 45% HP.
func _helping_hand(side: Array, active: int) -> void:
	if active >= side.size():
		return
	var lead: Dictionary = side[active]
	if int(lead.get("current_hp", 0)) <= 0:
		return
	var ratio := float(lead.get("current_hp", 0)) / float(maxi(1, lead.get("hp", 1)))
	if ratio >= 0.45:
		return
	for j in side.size():
		if j == active:
			continue
		var b: Dictionary = side[j]
		if int(b.get("current_hp", 0)) > 0 and _has(b, "helping_hand") and not b.get("_hh_used", false):
			b["_hh_used"] = true
			_heal_mon(b, 20)
			side[active] = b
			side[j] = lead
			await _ability_line("Passive", b, "Helping Hand", "heals 20 and steps in for %s" % _who(lead))
			_build_cards()
			await _on_entry(side == _team)
			return

# Monument (passive): the last spirit standing on a side surges +3 to all stats.
func _check_monument(side: Array) -> void:
	var living: Array = []
	for mm in side:
		if int(mm.get("current_hp", 0)) > 0:
			living.append(mm)
	if living.size() == 1 and _has(living[0], "monument") and not living[0].get("_monument_used", false):
		var mo: Dictionary = living[0]
		mo["_monument_used"] = true
		_buff(mo, "atk", 3)
		_buff(mo, "def", 3)
		_buff(mo, "spd", 3)
		await _ability_line("Passive", mo, "Monument", "stands alone — +3 to all stats")

# Bench spirits fire their NON-lead round-start abilities each round too — Wish,
# Healer, Regenerator, Medic, Electric Field… anything without a "· Lead" tag
# works from any slot. Lead-only abilities are gated out inside
# _round_start_abilities. `foe_lead` is the opposing active fighter.
func _bench_round_start(side: Array, active: int, foe_lead: Dictionary) -> void:
	for j in side.size():
		if j == active:
			continue
		var b: Dictionary = side[j]
		if int(b.get("current_hp", 0)) <= 0:
			continue
		for slot in 2:
			await _round_start_abilities(b, foe_lead, slot, false)

# True if anyone alive on this side is below full HP (so Wish doesn't spam
# the log while the team is already topped up).
func _needs_healing(side: Array) -> bool:
	for m in side:
		if int(m.get("current_hp", 0)) > 0 and int(m.get("current_hp", 0)) < int(m.get("hp", 1)):
			return true
	return false

# ---------------- abilities & held items ----------------

func _ab(mon: Dictionary) -> String:
	return String(mon.get("ability", ""))

# Spirits can hold up to TWO abilities (a bonus reward stacks a second one).
# Both live in "ability" / "ability2"; every ability check runs for each slot.
func _ability_slot(mon: Dictionary, slot: int) -> String:
	if slot == 0:
		return String(mon.get("ability", ""))
	if slot == 1:
		return String(mon.get("ability2", ""))
	return ""

func _has(mon: Dictionary, name: String) -> bool:
	return String(mon.get("ability", "")) == name or String(mon.get("ability2", "")) == name

# A 2★+ Veteran shrugs off enemy abilities entirely: no ability damage, debuffs
# or sealing can touch it (status immunity is handled separately in
# _apply_status). Effects that target it check this first.
func _ab_immune(mon: Dictionary) -> bool:
	return _has(mon, "veteran") and int(mon.get("stars", 0)) >= 2

# A spirit's name coloured by its team side: your team blue, enemy team red.
func _who(mon: Dictionary) -> String:
	var c: String = LOG_YOU if _team.has(mon) else LOG_ENEMY
	return "[color=#%s]%s[/color]" % [c, mon.get("name", "?")]

# An ability name in yellow.
func _abn(ability_name: String) -> String:
	return "[color=#%s]%s[/color]" % [LOG_ABILITY, ability_name]

# Ability log line:  [phase]  AbilityName(yellow)  Spirit(team colour)  effect(white)
# Using an ability sways the spirit's card, then holds a beat so actions play
# out one at a time.
func _ability_line(phase: String, mon: Dictionary, ability_name: String, effect: String) -> void:
	_anim_ability(mon)
	_logln("[%s] %s %s %s" % [phase, _abn(ability_name), _who(mon), effect])
	await _beat(0.55)

# Log a passive only the FIRST time it fires this battle (so per-hit passives
# like Thick Fat don't spam the log). `key` is the ability key.
func _passive_once(mon: Dictionary, key: String, effect: String) -> void:
	if mon.get("_plog_" + key, false):
		return
	mon["_plog_" + key] = true
	await _ability_line("Passive", mon, String(SpiritsData.ability_of(key).get("name", key)), effect)

func _held(mon: Dictionary) -> StringName:
	return mon.get("held_item", &"")

func _buff(mon: Dictionary, stat: String, delta: int) -> void:
	mon[stat] = clampi(int(mon.get(stat, 1)) + delta, 1, 9)

func _heal_mon(mon: Dictionary, amount: int) -> void:
	mon["current_hp"] = mini(int(mon.get("hp", 1)), int(mon.get("current_hp", 0)) + amount)

# Match-start abilities: fire once per battle from anywhere in the lineup.
# They all "happen at the same time", so both teams' spirits act in SPD order.
func _apply_match_start() -> void:
	var actors: Array = _team + _opp
	actors.sort_custom(func(a, b): return int(a.get("spd", 0)) > int(b.get("spd", 0)))
	for m in actors:
		var mine: Array = _team if _team.has(m) else _opp
		var theirs: Array = _opp if mine == _team else _team
		for slot in 2:
			await _side_match_start(mine, theirs, slot, m)
	# U-Turn last: the lead hits and rotates to the back
	await _u_turn(_team, _opp)
	await _u_turn(_opp, _team)

func _count_type(side: Array, type: String) -> int:
	var n := 0
	for a in side:
		if String(a.get("type", "")) == type:
			n += 1
	return n

# One spirit's match-start ability (called per spirit, in speed order).
func _side_match_start(mine: Array, theirs: Array, slot: int, only: Dictionary) -> void:
	for m in mine:
		if m != only:
			continue
		match _ability_slot(m, slot):
			"intimidate":
				for o in theirs:
					if not _ab_immune(o):
						_buff(o, "atk", -3)
				await _ability_line("Match Start", m, "Intimidate", "enemy team ATK −3")
			"screech":
				if not _ab_immune(theirs[0]):
					_buff(theirs[0], "def", -2)
				await _ability_line("Match Start", m, "Screech", "%s DEF −2" % _who(theirs[0]))
			"tailwind":
				for a in mine:
					_buff(a, "spd", 3)
				await _ability_line("Match Start", m, "Tailwind", "team SPD +3")
			"speed_boost":
				for a in mine:
					_buff(a, "atk", 1)
					_buff(a, "spd", 1)
				_buff(m, "atk", 2)   # the booster itself gets an extra +2 ATK
				await _ability_line("Match Start", m, "Speed Boost", "self ATK +2, team ATK/SPD +1")
			"reflect":
				for a in mine:
					_buff(a, "def", 2)
				await _ability_line("Match Start", m, "Reflect", "team DEF +2")
			"veteran":
				if int(m.get("stars", 0)) >= 2:
					_buff(m, "atk", 3)
					await _ability_line("Match Start", m, "Veteran", "self ATK +3, immune to status & abilities")
			"thunder_wave":
				await _apply_status(theirs[0], "stun", 2, m, "Thunder Wave")
			"confuse_ray":
				await _apply_status(theirs[0], "confuse", randi_range(2, 3), m, "Confuse Ray")
			"taunt":
				for o in theirs:
					o["_taunted"] = true
				await _ability_line("Match Start", m, "Taunt", "enemy can't heal or inflict status")
			"sniper":
				var living: Array = []
				for o in theirs:
					if int(o.get("current_hp", 0)) > 0 and not _ab_immune(o):
						living.append(o)
				if not living.is_empty():
					var target: Dictionary = living[randi() % living.size()]
					var hit: int = 40
					target["current_hp"] = maxi(1, int(target.get("current_hp", 1)) - hit)
					await _ability_line("Match Start", m, "Sniper", "snipes %s for %d" % [_who(target), hit])
			"spikes":
				for o in theirs:
					o["_spikes_pending"] = true
				await _ability_line("Match Start", m, "Spikes", "set on the enemy team")
			"fire_bond":
				_buff(m, "atk", 2 * _count_type(mine, "Fire"))
				for a in mine:
					if a != m:
						_buff(a, "def", 1)
				await _ability_line("Match Start", m, "Fire Bond", "self ATK up, allies DEF +1")
			"water_bond":
				_buff(m, "atk", _count_type(mine, "Water"))
				for a in mine:
					if a != m:
						_buff(a, "def", 2)
				await _ability_line("Match Start", m, "Water Bond", "self ATK up, allies DEF +2")
			"grass_bond":
				_buff(m, "atk", _count_type(mine, "Grass"))
				for a in mine:
					if a != m:
						a["hp"] = int(a.get("hp", 60)) + 60
						_heal_mon(a, 60)
				await _ability_line("Match Start", m, "Grass Bond", "self ATK up, allies +2 HP")
			"electric_bond":
				_buff(m, "atk", _count_type(mine, "Electric"))
				for a in mine:
					if a != m:
						_buff(a, "spd", 2)
				await _ability_line("Match Start", m, "Electric Bond", "self ATK up, allies SPD +2")
			"fighting_bond":
				_buff(m, "atk", 2 * _count_type(mine, "Fighting"))
				for a in mine:
					if a != m:
						_buff(a, "atk", 2)
				await _ability_line("Match Start", m, "Fighting Bond", "self ATK up, allies ATK +2")
			"psychic_bond":
				_buff(m, "atk", _count_type(mine, "Psychic"))
				for a in mine:
					if a != m:
						a["_status_immune"] = true
				await _ability_line("Match Start", m, "Psychic Bond", "self ATK up, allies status immune")
			"dark_bond":
				_buff(m, "atk", _count_type(mine, "Dark"))
				for o in theirs:
					if not _ab_immune(o):
						_buff(o, "def", -2)
				await _ability_line("Match Start", m, "Dark Bond", "self ATK up, enemy DEF −2")
			"tailwind":
				for a in mine:
					_buff(a, "spd", 3)
				await _ability_line("Match Start", m, "Tailwind", "team SPD +3")
			"mayhem":
				# scramble the whole enemy line-up — their lead can change
				theirs.shuffle()
				_build_cards()
				await _ability_line("Match Start", m, "Mayhem", "scrambles the enemy line-up!")
			"mind_hold":
				# wipe two random opponents' abilities for the whole battle
				var targets: Array = []
				for o in theirs:
					if int(o.get("current_hp", 0)) > 0 and not _ab_immune(o):
						targets.append(o)
				targets.shuffle()
				var held: Array = []
				for t in targets.slice(0, 2):
					t["ability"] = ""
					t["ability2"] = ""
					t["_suppressed"] = 999
					held.append(_who(t))
				if not held.is_empty():
					await _ability_line("Match Start", m, "Mind Hold",
						"seals the minds of %s!" % ", ".join(held))

# U-Turn: the lead lands a free hit, rotates to the back, and hypes the ally
# who takes its place.
func _u_turn(mine: Array, theirs: Array) -> void:
	if mine.size() < 2 or not _has(mine[0], "u_turn"):
		return
	var m: Dictionary = mine[0]
	var foe: Dictionary = theirs[0]
	var hit: int = 0 if _ab_immune(foe) else 20
	if hit > 0:
		foe["current_hp"] = maxi(1, int(foe.get("current_hp", 1)) - hit)
	mine.remove_at(0)
	mine.append(m)
	_buff(mine[0], "atk", 2)
	_build_cards()   # the rotation reorders the row
	await _ability_line("Match Start", m, "U-Turn", "hits %d, %s steps up ATK +2" % [hit, _who(mine[0])])

# Entry effects (held items + abilities) whenever a spirit becomes the fighter.
func _on_entry(is_me: bool) -> void:
	var mine: Array = _team if is_me else _opp
	var theirs: Array = _opp if is_me else _team
	var idx: int = _active if is_me else _opp_active
	var their_idx: int = _opp_active if is_me else _active
	if idx >= mine.size():
		return
	var m: Dictionary = mine[idx]
	match _held(m):
		&"choice_band":
			_buff(m, "atk", 1)
			_logln("%s's Choice Band! ATK +1." % _who(m))
		&"vanguard_shield":
			_buff(m, "def", 1)
			_logln("%s's Vanguard Shield! DEF +1." % _who(m))
		&"battle_drum":
			if their_idx < theirs.size():
				var foe: Dictionary = theirs[their_idx]
				var hit: int = maxi(1, int(DamageCalculator.calculate(m, foe) * 0.4))
				foe["current_hp"] = maxi(1, int(foe.get("current_hp", 1)) - hit)
				_logln("%s's Battle Drum! Free hit for %d." % [_who(m), hit])
		&"trophy":
			var living := 0
			for a in mine:
				if int(a.get("current_hp", 0)) > 0:
					living += 1
			if living <= 1:
				_buff(m, "atk", 1)
				m["_trophy_on"] = true
				_logln("%s raises the Trophy! ATK +1, but it takes more damage." % _who(m))
	# stepping onto Spikes
	if m.get("_spikes_pending", false):
		m.erase("_spikes_pending")
		if not _ab_immune(m):
			m["current_hp"] = maxi(1, int(m.get("current_hp", 1)) - 30)
			_anim_shake(m)
			_logln("%s is hurt by Spikes! -30 HP." % _who(m))
			await _beat(0.45)
	for slot in 2:
		await _entry_ability(m, mine, theirs, their_idx, _ability_slot(m, slot))

# Entry abilities fire per ability slot so a stacked second ability triggers too.
func _entry_ability(m: Dictionary, mine: Array, theirs: Array, their_idx: int, ab: String) -> void:
	match ab:
		"shell_smash":
			_buff(m, "def", -3)
			_buff(m, "atk", 3)
			_buff(m, "spd", 3)
			await _ability_note(m, "%s's %s! ATK +3, SPD +3, DEF -3." % [_who(m), _abn("Shell Smash")])
		"all_for_one":
			if not m.get("_afo_used", false):
				m["_afo_used"] = true
				_buff(m, "atk", 4)
				_buff(m, "def", 4)
				_buff(m, "spd", 4)
				for a in mine:
					if a != m:
						_buff(a, "atk", -4)
						_buff(a, "def", -4)
						_buff(a, "spd", -4)
				await _ability_note(m, "%s takes the lead - %s! Self +4 all, allies -4 all." % [_who(m), _abn("All For One")])
		"hypnosis":
			if not m.get("_hyp_used", false) and their_idx < theirs.size():
				m["_hyp_used"] = true
				await _apply_status(theirs[their_idx], "sleep", 2, m, "Hypnosis")
		"encore":
			if their_idx < theirs.size():
				theirs[their_idx]["_suppressed"] = 999
				await _ability_note(m, "%s's %s! %s's ability is suppressed." % [
					_who(m), _abn("Encore"), _who(theirs[their_idx])])

# ---------------- status effects ----------------

const STATUS_NAMES := {
	"stun": "stunned", "sleep": "asleep", "poison": "poisoned",
	"burn": "burned", "confuse": "confused",
}

func _apply_status(target: Dictionary, kind: String, rounds: int, inflictor: Dictionary = {}, source: String = "") -> void:
	if not inflictor.is_empty() and inflictor.get("_taunted", false):
		return   # taunted spirits can't inflict status
	if target.get("_status_immune", false):
		return
	if _has(target, "veteran") and int(target.get("stars", 0)) >= 2:
		return
	if target.has("_status"):
		return   # one status at a time
	target["_status"] = {"kind": kind, "rounds": rounds}
	if kind == "burn":
		_buff(target, "atk", -1)
	_anim_shake(target)
	# Always name the source, so a status never seems to appear from nowhere:
	# "<caster>'s <Ability> — <target> is asleep!".
	if not inflictor.is_empty() and source != "":
		_anim_ability(inflictor)
		_logln("%s's %s — %s is %s!" % [
			_who(inflictor), _abn(source), _who(target), STATUS_NAMES.get(kind, kind)])
	else:
		_logln("%s is %s!" % [_who(target), STATUS_NAMES.get(kind, kind)])
	await _beat(0.45)

# Tick the active fighter's status at round start. Returns false if the
# status stops it from attacking this round. Status damage CAN now KO (the
# strike phase and end-of-round faint checks handle a spirit dropped to 0).
func _process_status(m: Dictionary) -> bool:
	if not m.has("_status"):
		return true
	var st: Dictionary = m["_status"]
	var kind: String = st.get("kind", "")
	var can_act := true
	match kind:
		"poison", "burn":
			m["current_hp"] = maxi(0, int(m.get("current_hp", 1)) - 10)
			_anim_shake(m)
			_logln("%s is hurt by %s! -10 HP." % [_who(m), kind])
			await _beat(0.45)
		"stun", "sleep":
			can_act = false
			_logln("%s is %s and can't move!" % [_who(m), STATUS_NAMES[kind]])
			await _beat(0.45)
		"confuse":
			if randf() < 0.5:
				can_act = false
				m["current_hp"] = maxi(0, int(m.get("current_hp", 1)) - 15)
				_anim_shake(m)
				_logln("%s hurt itself in confusion! -15 HP." % _who(m))
				await _beat(0.45)
	st["rounds"] = int(st.get("rounds", 1)) - 1
	if int(st["rounds"]) <= 0:
		m.erase("_status")
		_logln("%s recovered from being %s." % [_who(m), STATUS_NAMES.get(kind, kind)])
		await _beat(0.4)
	return can_act

# Round-start abilities for one spirit. `is_lead` is true only for the active
# fighter; abilities tagged "· Lead" do nothing off the lead, while untagged
# ones (Wish, Regenerator, Medic, Electric Field…) fire from any slot. Damage
# here CAN KO; the strike phase and faint checks skip any spirit dropped to 0.
func _round_start_abilities(m: Dictionary, foe: Dictionary, slot: int, is_lead: bool) -> void:
	if int(m.get("current_hp", 0)) <= 0:
		return   # a spirit downed earlier this round takes no round-start action
	# Encore suppression: no round-start ability while suppressed (tick once,
	# on the first slot, so the counter doesn't drain twice per round)
	if int(m.get("_suppressed", 0)) > 0:
		if slot == 0:
			m["_suppressed"] = int(m["_suppressed"]) - 1
		return
	var ab := _ability_slot(m, slot)
	# A "· Lead" ability only works from the lead spot; untagged round-start
	# abilities fire from anywhere in the lineup.
	if not is_lead and "Lead" in String(SpiritsData.ability_of(ab).get("cat", "")):
		return
	# Taunt blocks the healing abilities
	var taunted: bool = m.get("_taunted", false)
	if taunted and ab in ["dynasty", "regenerator", "wish", "medic", "healer"]:
		return
	match ab:
		"fortress":
			_buff(m, "def", 1)
			await _ability_line("Round Start", m, "Fortress", "self DEF +1")
		"iron_will":
			_buff(m, "atk", 1)
			await _ability_line("Round Start", m, "Iron Will", "self ATK +1")
		"drought":
			var d_team: Array = _team if _team.has(m) else _opp
			for a in d_team:
				_buff(a, "atk", 1)
			await _ability_line("Round Start", m, "Drought", "team ATK +1")
		"leech_seed":
			if not _ab_immune(foe):
				var drain: int = 20 if foe.has("_status") else 10
				foe["current_hp"] = maxi(0, int(foe.get("current_hp", 1)) - drain)
				_heal_mon(m, drain)
				await _ability_line("Round Start", m, "Leech Seed", "drains %d HP from %s" % [drain, _who(foe)])
		"berserker":
			_buff(m, "atk", 2)
			m["current_hp"] = maxi(1, int(m.get("current_hp", 1)) - 10)
			await _ability_line("Round Start", m, "Berserker", "self ATK +2, -10 HP")
		"dynasty":
			if int(m.get("current_hp", 0)) < int(m.get("hp", 1)):
				_heal_mon(m, 20)
				await _ability_line("Round Start", m, "Dynasty", "heals 20 HP")
		"regenerator":
			if int(m.get("current_hp", 0)) < int(m.get("hp", 1)):
				var amount: int = int(m.get("hp", 1) * 0.3)
				_heal_mon(m, amount)
				await _ability_line("Round Start", m, "Regenerator", "heals %d HP" % amount)
		"wish":
			var mine: Array = _team if _team.has(m) else _opp
			if _needs_healing(mine):
				for a in mine:
					if int(a.get("current_hp", 0)) > 0:
						_heal_mon(a, 20)
				await _ability_line("Round Start", m, "Wish", "team heals 20 HP")
		"drain_punch":
			if not _ab_immune(foe):
				foe["current_hp"] = maxi(0, int(foe.get("current_hp", 1)) - 30)
				_heal_mon(m, 20)
				await _ability_line("Round Start", m, "Drain Punch", "deals 30 and heals 20")
		"electric_field":
			# 10 damage to TWO random living opponents (bench included)
			var pool: Array = _opp if _team.has(m) else _team
			var foes: Array = []
			for o in pool:
				if int(o.get("current_hp", 0)) > 0 and not _ab_immune(o):
					foes.append(o)
			foes.shuffle()
			var zap: int = 10
			var hit_names: Array = []
			for t in foes.slice(0, 2):
				t["current_hp"] = maxi(0, int(t.get("current_hp", 1)) - zap)
				_anim_shake(t)
				hit_names.append(_who(t))
			if not hit_names.is_empty():
				await _ability_line("Round Start", m, "Electric Field",
					"zaps %s for %d each" % [", ".join(hit_names), zap])
		"medic":
			if not m.get("_medic_used", false) and randf() < 0.3:
				var mine2: Array = _team if _team.has(m) else _opp
				for a in mine2:
					if int(a.get("current_hp", 0)) <= 0:
						a["current_hp"] = int(a.get("hp", 1))   # revived to full HP
						a.erase("_gone")   # its card returns to the row
						m["_medic_used"] = true
						await _ability_line("Round Start", m, "Medic", "revives %s" % _who(a))
						_requeue_revived(a)   # it rejoins the send-out line
						break
		"healer":
			# supports the lead from behind — never fires while leading itself
			if is_lead:
				return
			var hside: Array = _team if _team.has(m) else _opp
			var hactive: int = _active if _team.has(m) else _opp_active
			if hactive < hside.size():
				var lead: Dictionary = hside[hactive]
				if int(lead.get("current_hp", 0)) > 0 and int(lead.get("current_hp", 0)) < int(lead.get("hp", 1)):
					_heal_mon(lead, 30)
					await _ability_line("Round Start", m, "Healer", "restores 30 HP to %s" % _who(lead))

# A revived ally is stranded at its fainted slot (behind the active index),
# so the round loop never reaches it. Move it to just BEHIND the current
# fighter — it steps up next when the active spirit falls.
func _requeue_revived(a: Dictionary) -> void:
	var is_me: bool = _team.has(a)
	var side: Array = _team if is_me else _opp
	var active: int = _active if is_me else _opp_active
	var idx: int = side.find(a)
	if idx == -1 or idx >= active:
		return   # already waiting in line — nothing to fix
	side.remove_at(idx)
	active -= 1                    # everything after idx shifted down one
	side.insert(active + 1, a)     # slot it right behind the active fighter
	if is_me:
		_active = active
	else:
		_opp_active = active
	_build_cards()   # array order changed — rebuild the card row to match
	_refresh()

func _strike(att: Dictionary, def_: Dictionary, attacker_is_me: bool) -> void:
	# the attacker lunges toward the enemy row; the defender's shake comes
	# with the hit further down
	_anim_attack(att)
	await _beat(0.3)
	# Bodyguard: a bench ally throws itself in front of a HURT lead (below 50%
	# HP), once per round — the whole hit lands on the guard instead.
	if float(def_.get("current_hp", 0)) / float(maxi(1, def_.get("hp", 1))) < 0.5:
		for b in (_team if _team.has(def_) else _opp):
			if b != def_ and int(b.get("current_hp", 0)) > 0 and _has(b, "bodyguard") \
					and int(b.get("_bg_round", -1)) != _round_num:
				b["_bg_round"] = _round_num
				await _ability_note(b, "%s's %s! It shields %s and takes the hit!" % [
					_who(b), _abn("Bodyguard"), _who(def_)])
				def_ = b
				break
	# attacker items / abilities
	var item_mult := 1.2 if _held(att) == &"expert_belt" else 1.0
	if _has(att, "reckless"):
		item_mult *= 1.25
	var dmg: int = DamageCalculator.calculate(att, def_, 1.0, 1.0, item_mult)
	# absorb abilities can negate the hit outright
	if _has(def_, "flash_fire") and randf() < 0.25:
		_buff(def_, "atk", 2)
		await _ability_line("Passive", def_, "Flash Fire", "absorbs the hit, ATK +2")
		return
	if _has(def_, "volt_absorb") and randf() < 0.35:
		_heal_mon(def_, dmg)
		await _ability_line("Passive", def_, "Volt Absorb", "turns the hit into %d HP" % dmg)
		return
	# defender reductions
	var taken := float(dmg)
	if _held(def_) == &"assault_vest":
		taken *= 0.85
	if _has(def_, "thick_fat"):
		taken *= 0.8
		await _passive_once(def_, "thick_fat", "incoming damage ×0.8")
	if _has(def_, "reckless"):
		taken *= 1.15
	var ratio := float(def_.get("current_hp", 0)) / float(maxi(1, def_.get("hp", 1)))
	if _has(def_, "grit") and ratio < 0.5:
		taken *= 0.6
		await _passive_once(def_, "grit", "x0.6 damage while low")
	if _has(def_, "battle_armor") and _round_num <= 2:
		taken *= 0.5
		await _passive_once(def_, "battle_armor", "×0.5 in early rounds")
	if _has(def_, "multiscale") and def_.get("current_hp", 0) == def_.get("hp", 1) and not def_.get("_ms_used", false):
		taken *= 0.5
		def_["_ms_used"] = true
		await _ability_line("Passive", def_, "Multiscale", "halves the first big hit")
	if def_.get("_trophy_on", false):
		taken *= 1.2
	var final := maxi(1, int(round(taken)))
	var hp_after: int = int(def_.get("current_hp", 0)) - final
	# the hit lands and logs FIRST (the bar visibly drops)…
	def_["current_hp"] = maxi(0, hp_after)
	var t_mult: float = SpiritsData.effectiveness(String(att.get("type", "")), def_)
	var eff := ""
	if t_mult > 1.0:
		eff = "  Super effective!"
	elif t_mult < 1.0:
		eff = "  Not very effective…"
	_anim_shake(def_)
	_logln("%s hits %s for %d!%s" % [_who(att), _who(def_), final, eff])
	await _beat(0.5)
	# …THEN survive-lethal effects explain why the defender is still standing
	if hp_after <= 0:
		if _held(def_) == &"focus_sash" and not def_.get("_sash_used", false):
			def_["_sash_used"] = true
			def_["current_hp"] = 1
			_logln("%s hangs on with its Focus Sash!" % _who(def_))
			await _beat(0.45)
		elif _has(def_, "sturdy") and not def_.get("_sturdy_used", false):
			def_["_sturdy_used"] = true
			def_["current_hp"] = 1
			await _ability_note(def_, "%s endures the hit — %s!" % [_who(def_), _abn("Sturdy")])
		elif _has(def_, "anger_point") and not def_.get("_anger_used", false):
			def_["_anger_used"] = true
			def_["current_hp"] = 1
			_buff(def_, "atk", 3)
			await _ability_note(def_, "%s hits its %s! Survives at 1 HP, ATK +3!" % [_who(def_), _abn("Anger Point")])
	# on-hit items / abilities
	if _held(att) == &"shell_bell":
		var sip: int = maxi(1, final / 10)
		_heal_mon(att, sip)
		_logln("%s's Shell Bell restores %d HP." % [_who(att), sip])
	if _held(def_) == &"rocky_helmet":
		att["current_hp"] = maxi(1, int(att.get("current_hp", 1)) - 15)
		_logln("%s is hurt by the Rocky Helmet! -15 HP." % _who(att))
	if _has(att, "thief"):
		_buff(att, "atk", 1)
		_buff(def_, "atk", -1)
		await _ability_note(att, "%s steals power — %s! ATK +1." % [_who(att), _abn("Thief")])
	if _has(def_, "counter") and randf() < 0.75 and def_["current_hp"] > 0:
		var payback: int = int(final * 0.4)
		att["current_hp"] = maxi(0, int(att.get("current_hp", 0)) - payback)
		_anim_shake(att)
		await _ability_note(def_, "%s Counters for %d!" % [_who(def_), payback])
	if _has(def_, "bulwark") and def_["current_hp"] > 0:
		_buff(att, "def", -2)
		await _ability_note(def_, "%s's %s saps %s's DEF −2!" % [_who(def_), _abn("Bulwark"), _who(att)])
	# contact statuses punish the attacker
	if def_["current_hp"] > 0:
		if _has(def_, "static") and randf() < 0.3:
			await _apply_status(att, "stun", 1, def_, "Static")
		if _has(def_, "poison_point"):
			await _apply_status(att, "poison", 3, def_, "Poison Point")
		if _has(def_, "flame_body"):
			await _apply_status(att, "burn", 3, def_, "Flame Body")
		if _has(def_, "spore"):
			await _apply_status(att, ["stun", "poison", "burn", "confuse", "sleep"][randi() % 5], 2, def_, "Spore")
	# defender recovery / threshold abilities
	if def_["current_hp"] > 0:
		var new_ratio := float(def_["current_hp"]) / float(maxi(1, def_.get("hp", 1)))
		if _held(def_) == &"sitrus_berry" and new_ratio < 0.5 and not def_.get("_berry_used", false):
			def_["_berry_used"] = true
			_heal_mon(def_, int(def_.get("hp", 1) * 0.3))
			_logln("%s munches its Sitrus Berry — HP restored!" % _who(def_))
		if _has(def_, "blaze") and new_ratio < 0.33 and not def_.get("_blaze_used", false):
			def_["_blaze_used"] = true
			_buff(def_, "atk", 4)
			_buff(def_, "spd", 2)
			await _ability_note(def_, "%s's %s ignites! ATK +4, SPD +2!" % [_who(def_), _abn("Blaze")])
		if _has(def_, "overgrow") and new_ratio < 0.5 and not def_.get("_overgrow_used", false):
			def_["_overgrow_used"] = true
			_buff(def_, "def", 4)
			await _ability_note(def_, "%s's %s surges! DEF +4!" % [_who(def_), _abn("Overgrow")])
	else:
		# on-KO effects
		if _held(def_) == &"phoenix_ash" and not def_.get("_phoenix_used", false):
			def_["_phoenix_used"] = true
			def_["current_hp"] = maxi(1, int(def_.get("hp", 1) * 0.25))
			_logln("%s rises from the Phoenix Ash!" % _who(def_))
			return
		# Phoenix (ability): reborn once per battle at 30% HP
		if _has(def_, "phoenix") and not def_.get("_phoenix_ab_used", false):
			def_["_phoenix_ab_used"] = true
			def_["current_hp"] = maxi(1, int(def_.get("hp", 1) * 0.3))
			await _ability_note(def_, "%s is reborn from the ashes — %s!" % [
				_who(def_), _abn("Phoenix")])
			return
		# star credit: a full star for beating an equal/higher-stage spirit,
		# half a star for a lower one — capped at 2 KO stars per battle
		if attacker_is_me:
			var granted := _credit_stars(att, _ko_credit(att, def_))
			if granted > 0.0:
				_logln("[color=#d3a8ff]%s earns %s star for the KO![/color]" % [
					att.get("name", "?"), "a" if granted >= 1.0 else "half a"])
			else:
				_logln("[color=#d3a8ff]%s is maxed on KO stars this battle (2).[/color]" % att.get("name", "?"))
		if _has(def_, "destiny_bond"):
			att["current_hp"] = 0
			_anim_shake(att)
			await _ability_note(def_, "%s's %s drags %s down with it!" % [_who(def_), _abn("Destiny Bond"), _who(att)])
		elif _has(def_, "explosion"):
			var boom: int = int(def_.get("hp", 1) * 0.6)
			att["current_hp"] = maxi(0, int(att.get("current_hp", 0)) - boom)
			_anim_shake(att)
			for o in (_team if _team.has(att) else _opp):
				_buff(o, "atk", -2)
				_buff(o, "def", -2)
			await _ability_note(def_, "%s explodes for %d — enemy team ATK/DEF −2!" % [_who(def_), boom])
		if _has(att, "moxie"):
			_buff(att, "atk", 2)
			await _ability_note(att, "%s's %s! ATK +2." % [_who(att), _abn("Moxie")])

func _ko_credit(att: Dictionary, def_: Dictionary) -> float:
	return 1.0 if int(def_.get("stage", 1)) >= int(att.get("stage", 1)) else 0.5

func _end(player_won: bool) -> void:
	_over = true
	_won = player_won
	_next_btn.disabled = true
	_skip_btn.hide()   # the Skip slot becomes Continue
	# battle damage is real: write each spirit's HP back to the actual team
	# (clamped to its true max — battle-only HP boosts don't carry over)
	for m in _team:
		var oi: int = int(m.get("_oi", -1))
		if oi >= 0 and oi < _src_team.size():
			var orig: Dictionary = _src_team[oi]
			orig["current_hp"] = clampi(int(m.get("current_hp", 0)), 0, int(orig.get("hp", 1)))
	if player_won:
		_logln("[color=#9f9]You won the battle![/color]")
		# survivors share the glory: half a star each
		var survivors: Array = []
		for m in _team:
			if int(m.get("current_hp", 0)) > 0:
				var _granted := _credit_stars(m, 0.5, false)   # survival isn't KO-capped
				survivors.append(m.get("name", "?"))
		if not survivors.is_empty():
			_logln("[color=#d3a8ff]%s earn%s half a star for surviving![/color]" % [
				", ".join(survivors), "s" if survivors.size() == 1 else ""])
	else:
		_logln("[color=#f99]Your team was defeated…[/color]")
	_continue_btn.show()

func _logln(t: String) -> void:
	_log.append_text(t + "\n")

# The trainer portrait in a circle tinted with the team's colour.
class TrainerDisc:
	extends Control
	var tex: Texture2D
	var color := Color(0.6, 0.6, 0.7)

	func _init() -> void:
		custom_minimum_size = Vector2(76, 76)
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_data(t: Texture2D, c: Color) -> void:
		tex = t
		color = c
		queue_redraw()

	func _draw() -> void:
		var ctr := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 2.0
		draw_circle(ctr, r, color)
		draw_circle(ctr, r - 3.0, color.darkened(0.45))
		if tex:
			var ts := tex.get_size()
			var s := (r * 1.5) / maxf(ts.x, ts.y)
			draw_texture_rect(tex, Rect2(ctr - ts * s * 0.5, ts * s), false)
