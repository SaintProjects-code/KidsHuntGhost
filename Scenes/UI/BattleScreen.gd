extends MenuWindow
## Team-vs-team auto-battler screen, styled after PokeLike:
##   • light-green field background with a gold battle title
##   • SKIP centred at the top
##   • two dark full-height columns — YOUR TEAM / ENEMY — each headed by a
##     trainer sprite and a coloured type badge (e.g. "GRASS T1") for the
##     active spirit
##   • one card per spirit: name bar, HP bar, sprite on a grass platform;
##     your side shows back sprites, the enemy faces you; fainted cards dim
##
## Reused for wild encounters, gyms, Elite Four and Gary.
## present(team, opp_team, title, player_color); emits finished(player_won).
## Works on copies so the player's real team HP isn't permanently spent.

signal finished(player_won: bool)

const BASE_DELAY := 0.55
const SPRITE_H := 28.0
const PLATFORM_TEX := "res://Assets/Forest.webp"   # forest grass floor

const FIELD_BG := Color(0.106, 0.086, 0.196)       # game's dark purple
const COLUMN_BG := Color(0.05, 0.05, 0.08, 0.95)
const CARD_BG := Color(0.55, 0.76, 0.47)           # green field per card
const BANNER_BG := Color(0.07, 0.1, 0.06, 0.85)    # dark name banner
const PLATFORM_GREEN := Color(0.35, 0.6, 0.28)
const HP_GREEN := Color(0.4, 0.85, 0.35)
const HP_YELLOW := Color(0.95, 0.85, 0.3)
const HP_RED := Color(0.9, 0.3, 0.25)
const ACTIVE_GOLD := Color(1.0, 0.85, 0.3)

# type badge colours ("GRASS T1" chips); anything unknown falls back to purple
const TYPE_COLORS := {
	"Fire": Color(0.9, 0.35, 0.15), "Water": Color(0.25, 0.5, 0.9),
	"Grass": Color(0.35, 0.7, 0.3), "Electric": Color(0.9, 0.8, 0.2),
	"Poison": Color(0.6, 0.3, 0.7), "Ghost": Color(0.45, 0.35, 0.65),
	"Rock": Color(0.7, 0.6, 0.4), "Normal": Color(0.6, 0.6, 0.55),
	"Psychic": Color(0.9, 0.4, 0.6), "Flying": Color(0.55, 0.65, 0.9),
}

var _team: Array = []
var _opp: Array = []
var _active: int = 0
var _opp_active: int = 0
var _over: bool = false
var _won: bool = false
var _speed: float = 1.0
var _auto_running: bool = false
var _round_num: int = 0
var _star_credits: Dictionary = {}   # team index -> stars earned this battle

var _title: Label
var _team_box: VBoxContainer
var _opp_box: VBoxContainer
var _team_cards: Array = []   # per spirit: {card, bg, hp, hp_text}
var _opp_cards: Array = []
var _team_trainer: TextureRect
var _opp_trainer: TextureRect
var _team_chip: Label
var _team_chip_bg: StyleBoxFlat
var _opp_chip: Label
var _opp_chip_bg: StyleBoxFlat
var _log: RichTextLabel
var _next_btn: Button
var _auto_btn: Button
var _skip_btn: Button
var _continue_btn: Button

func _ready() -> void:
	# Sized to stay inside the 1152×648 design viewport with room to spare.
	var col := _init_window(920, 0)
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

	_title = _title_label("Battle", 20)
	col.add_child(_title)

	# SKIP centred at the top, like the reference
	var skip_row := HBoxContainer.new()
	skip_row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(skip_row)
	_skip_btn = _button("SKIP", _on_skip, 28)
	_skip_btn.custom_minimum_size = Vector2(80, 28)
	_skip_btn.add_theme_font_size_override("font_size", 16)
	skip_row.add_child(_skip_btn)

	# the two dark team columns
	var versus := HBoxContainer.new()
	versus.add_theme_constant_override("separation", 14)
	versus.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(versus)
	var left := _team_column(versus, "YOUR TEAM", true)
	_team_box = left.box
	_team_trainer = left.trainer
	_team_chip = left.chip
	_team_chip_bg = left.chip_bg
	var right := _team_column(versus, "ENEMY", false)
	_opp_box = right.box
	_opp_trainer = right.trainer
	_opp_chip = right.chip
	_opp_chip_bg = right.chip_bg

	# compact battle log on a dark strip so it reads over the green field
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.custom_minimum_size = Vector2(0, 62)
	_log.add_theme_font_size_override("normal_font_size", 14)
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
	col.add_child(_log)

	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 8)
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(controls)
	_next_btn = _button("Next Round", _on_next, 32)
	_next_btn.add_theme_font_size_override("font_size", 16)
	controls.add_child(_next_btn)
	_auto_btn = _button("Auto", _on_auto, 32)
	_auto_btn.add_theme_font_size_override("font_size", 16)
	controls.add_child(_auto_btn)
	for s in [1, 2, 3]:
		var sp := _button("%dx" % s, _on_speed.bind(float(s)), 32)
		sp.add_theme_font_size_override("font_size", 16)
		controls.add_child(sp)
	_continue_btn = _button("Continue", func(): finished.emit(_won), 32)
	_continue_btn.add_theme_font_size_override("font_size", 16)
	_continue_btn.hide()
	controls.add_child(_continue_btn)
	hide()

# One dark column: trainer sprite + type chip header, then the card stack.
func _team_column(parent: Control, header: String, is_player: bool) -> Dictionary:
	var panel_col := PanelContainer.new()
	panel_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = COLUMN_BG
	sb.corner_radius_top_left = 10
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10
	sb.corner_radius_bottom_right = 10
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 5
	panel_col.add_theme_stylebox_override("panel", sb)
	parent.add_child(panel_col)

	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 4)
	panel_col.add_child(side)

	# big trainer portrait, top-centre like the reference
	var trainer := TextureRect.new()
	trainer.custom_minimum_size = Vector2(0, 40)
	trainer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	trainer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	trainer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	trainer.flip_h = not is_player
	side.add_child(trainer)

	# header strip: side label + type badge
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	side.add_child(head)
	var head_lbl := Label.new()
	head_lbl.text = header
	head_lbl.add_theme_font_size_override("font_size", 13)
	head_lbl.modulate = Color(1, 1, 1, 0.65)
	head_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(head_lbl)

	var chip := PanelContainer.new()
	var chip_bg := StyleBoxFlat.new()
	chip_bg.bg_color = TYPE_COLORS["Normal"]
	chip_bg.corner_radius_top_left = 6
	chip_bg.corner_radius_top_right = 6
	chip_bg.corner_radius_bottom_left = 6
	chip_bg.corner_radius_bottom_right = 6
	chip_bg.content_margin_left = 8
	chip_bg.content_margin_right = 8
	chip_bg.content_margin_top = 2
	chip_bg.content_margin_bottom = 2
	chip.add_theme_stylebox_override("panel", chip_bg)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(chip)
	var chip_lbl := Label.new()
	chip_lbl.add_theme_font_size_override("font_size", 12)
	chip_lbl.text = "— T1"
	chip.add_child(chip_lbl)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(box)
	return {"box": box, "trainer": trainer, "chip": chip_lbl, "chip_bg": chip_bg}

func present(team: Array, opp_team: Array, title: String, player_color: Color = Color.WHITE, atk_mod: int = 0,
		player_trainer: Array = [], enemy_trainer: Array = []) -> void:
	# trainer portraits (named sprites from Assets/Trainer, with fallbacks)
	_team_trainer.texture = GameData.trainer_texture(player_trainer)
	_team_trainer.visible = _team_trainer.texture != null
	_opp_trainer.texture = GameData.trainer_texture(enemy_trainer)
	_opp_trainer.visible = _opp_trainer.texture != null
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
	_auto_running = false
	_speed = 1.0
	_round_num = 0
	_star_credits = {}
	_log.text = ""
	_continue_btn.hide()
	_next_btn.disabled = false
	_auto_btn.disabled = false
	_skip_btn.disabled = false
	_title.text = title
	if atk_mod > 0:
		_logln("[color=#9f9]Blessed! ATK +%d this battle.[/color]" % atk_mod)
	elif atk_mod < 0:
		_logln("[color=#f99]Spooked! ATK %d this battle.[/color]" % atk_mod)
	_logln("Battle start! Go, %s!" % _team[_active].get("name", "?"))
	# match-start abilities can reorder a team (U-Turn), so cards come after
	_apply_match_start()
	_build_cards()
	_on_entry(true)
	_on_entry(false)
	_refresh()
	_fit_to_screen()

# Hard guarantee the window fits the game view: after layout, if the panel is
# taller/wider than the screen, scale the whole thing down around its centre.
func _fit_to_screen() -> void:
	panel.scale = Vector2.ONE
	await get_tree().process_frame
	if not visible and panel.size.y <= 0.0:
		return
	var avail: Vector2 = get_viewport_rect().size - Vector2(24, 24)
	var s: float = minf(1.0, minf(avail.x / maxf(1.0, panel.size.x), avail.y / maxf(1.0, panel.size.y)))
	panel.pivot_offset = panel.size / 2.0
	panel.scale = Vector2(s, s)

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
		c["current_hp"] = c.get("hp", 1)
		c["_oi"] = i   # index into the caller's array, for star credits
		# remember battle-start stats so the cards can show buffs/debuffs
		for key in ["atk", "def", "spd"]:
			c["_base_" + key] = int(c.get(key, 1))
		out.append(c)
	return out

func _credit_stars(mon: Dictionary, amount: float) -> void:
	var oi: int = int(mon.get("_oi", -1))
	if oi >= 0:
		_star_credits[oi] = float(_star_credits.get(oi, 0.0)) + amount

# ---------------- spirit cards ----------------

func _build_cards() -> void:
	for box in [_team_box, _opp_box]:
		for c in box.get_children():
			c.queue_free()
	_team_cards = []
	_opp_cards = []
	for m in _team:
		_team_cards.append(_make_card(m, true))
	for m in _opp:
		_opp_cards.append(_make_card(m, false))

func _make_card(mon: Dictionary, is_player: bool) -> Dictionary:
	# a little grass-field scene per spirit, like the reference
	var card := PanelContainer.new()
	var bg := StyleBoxFlat.new()
	bg.bg_color = CARD_BG
	bg.corner_radius_top_left = 6
	bg.corner_radius_top_right = 6
	bg.corner_radius_bottom_left = 6
	bg.corner_radius_bottom_right = 6
	bg.content_margin_left = 6
	bg.content_margin_right = 6
	bg.content_margin_top = 3
	bg.content_margin_bottom = 3
	card.add_theme_stylebox_override("panel", bg)
	(_team_box if is_player else _opp_box).add_child(card)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	card.add_child(vb)

	# dark name banner, centred like the reference
	var banner := PanelContainer.new()
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = BANNER_BG
	bsb.corner_radius_top_left = 5
	bsb.corner_radius_top_right = 5
	bsb.corner_radius_bottom_left = 5
	bsb.corner_radius_bottom_right = 5
	bsb.content_margin_left = 8
	bsb.content_margin_right = 8
	bsb.content_margin_top = 1
	bsb.content_margin_bottom = 1
	banner.add_theme_stylebox_override("panel", bsb)
	vb.add_child(banner)
	var name_lbl := Label.new()
	name_lbl.text = "%s %s" % [mon.get("name", "?"), SpiritsData.star_text(mon.get("stars", 0))]
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_child(name_lbl)

	# HP bar in a dark frame + numbers/stats row below it
	var hp := ProgressBar.new()
	hp.show_percentage = false
	hp.custom_minimum_size = Vector2(0, 9)
	hp.max_value = mon.get("hp", 1)
	var hp_bg := StyleBoxFlat.new()
	hp_bg.bg_color = Color(0.07, 0.1, 0.06, 0.9)
	hp_bg.corner_radius_top_left = 4
	hp_bg.corner_radius_top_right = 4
	hp_bg.corner_radius_bottom_left = 4
	hp_bg.corner_radius_bottom_right = 4
	hp.add_theme_stylebox_override("background", hp_bg)
	vb.add_child(hp)

	var info := HBoxContainer.new()
	vb.add_child(info)
	var hp_text := Label.new()
	hp_text.add_theme_font_size_override("font_size", 11)
	hp_text.add_theme_color_override("font_color", Color(0.12, 0.25, 0.1))
	info.add_child(hp_text)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(spacer)
	# live stat line: buffs show green ▲, debuffs red ▼
	var stats := RichTextLabel.new()
	stats.bbcode_enabled = true
	stats.fit_content = true
	stats.scroll_active = false
	stats.custom_minimum_size = Vector2(200, 14)
	stats.add_theme_font_size_override("normal_font_size", 11)
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(stats)

	# sprite standing on the forest grass floor
	var stage := Control.new()
	stage.custom_minimum_size = Vector2(0, SPRITE_H)
	vb.add_child(stage)
	if ResourceLoader.exists(PLATFORM_TEX):
		var platform := TextureRect.new()
		platform.texture = load(PLATFORM_TEX)
		platform.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		platform.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		platform.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		platform.anchor_left = 0.18
		platform.anchor_right = 0.82
		platform.anchor_top = 0.45
		platform.anchor_bottom = 1.0
		stage.add_child(platform)
	else:
		# fallback ellipse until the texture is imported
		var platform2 := Panel.new()
		var psb := StyleBoxFlat.new()
		psb.bg_color = PLATFORM_GREEN
		psb.corner_radius_top_left = 999
		psb.corner_radius_top_right = 999
		psb.corner_radius_bottom_left = 999
		psb.corner_radius_bottom_right = 999
		platform2.add_theme_stylebox_override("panel", psb)
		platform2.anchor_left = 0.2
		platform2.anchor_right = 0.8
		platform2.anchor_top = 0.72
		platform2.anchor_bottom = 0.96
		stage.add_child(platform2)
	var sprite := TextureRect.new()
	# your side shows the spirit from behind, the enemy faces you
	sprite.texture = SpiritsData.sprite_tex(mon.get("name", ""), "back" if is_player else "front")
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.set_anchors_preset(Control.PRESET_FULL_RECT)
	sprite.offset_bottom = -3
	stage.add_child(sprite)

	return {"card": card, "bg": bg, "hp": hp, "hp_text": hp_text, "stats": stats}

func _refresh() -> void:
	_refresh_side(_team, _team_cards, _active)
	_refresh_side(_opp, _opp_cards, _opp_active)
	_refresh_chip(_team, _active, _team_chip, _team_chip_bg)
	_refresh_chip(_opp, _opp_active, _opp_chip, _opp_chip_bg)

# The column's type badge follows the ACTIVE spirit (e.g. "GRASS T1").
func _refresh_chip(team: Array, active: int, chip: Label, chip_bg: StyleBoxFlat) -> void:
	var i: int = mini(active, team.size() - 1)
	var mon: Dictionary = team[i]
	var type: String = str(mon.get("type", "Normal"))
	chip.text = "%s T%d" % [type.to_upper(), int(mon.get("stage", 1))]
	chip_bg.bg_color = TYPE_COLORS.get(type, Color(0.54, 0.44, 0.96))

# "ATK 4▲2  DEF 2  SPD 3▼1" — green when buffed above the battle-start
# value, red when debuffed, plain grey otherwise.
func _stat_line(mon: Dictionary) -> String:
	var parts: Array = []
	for pair in [["atk", "ATK"], ["def", "DEF"], ["spd", "SPD"]]:
		var cur: int = int(mon.get(pair[0], 1))
		var base: int = int(mon.get("_base_" + pair[0], cur))
		if cur > base:
			parts.append("[color=#0d5c17]%s %d▲%d[/color]" % [pair[1], cur, cur - base])
		elif cur < base:
			parts.append("[color=#8e1f1f]%s %d▼%d[/color]" % [pair[1], cur, base - cur])
		else:
			parts.append("[color=#2d4426]%s %d[/color]" % [pair[1], cur])
	return "  ".join(parts)

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
	if not _over:
		_round()

func _on_auto() -> void:
	if _auto_running or _over:
		return
	_auto_running = true
	_next_btn.disabled = true
	_auto_btn.disabled = true
	while not _over:
		_round()
		await get_tree().create_timer(BASE_DELAY / _speed).timeout
	_auto_running = false

# Resolve the whole battle instantly.
func _on_skip() -> void:
	_skip_btn.disabled = true
	while not _over:
		_round()

func _on_speed(s: float) -> void:
	_speed = s
	_logln("[i]Speed ×%d[/i]" % int(s))

func _round() -> void:
	if _over:
		return
	_round_num += 1
	var me: Dictionary = _team[_active]
	var op: Dictionary = _opp[_opp_active]
	# status ticks decide who can act this round
	var me_acts := _process_status(me)
	var op_acts := _process_status(op)
	_round_start_abilities(me, op)
	_round_start_abilities(op, me)
	_bench_round_abilities(_team, _active)
	_bench_round_abilities(_opp, _opp_active)
	if me.get("spd", 0) >= op.get("spd", 0):
		if me_acts:
			_strike(me, op, true)
		if op["current_hp"] > 0 and op_acts:
			_strike(op, me, false)
	else:
		if op_acts:
			_strike(op, me, false)
		if me["current_hp"] > 0 and me_acts:
			_strike(me, op, true)
	# Helping Hand: a bench ally leaps in front of a hurt lead
	_helping_hand(_team, _active)
	_helping_hand(_opp, _opp_active)
	# Vengeance fires before faint checks so its KOs resolve this round
	if me["current_hp"] <= 0:
		_vengeance(_team, op)
	if op["current_hp"] <= 0:
		_vengeance(_opp, me)
	# Independent checks (not elif): abilities like Destiny Bond / Explosion
	# can take both fighters down in the same round.
	if op["current_hp"] <= 0:
		_logln("[color=#9f9]%s fainted![/color]" % op.get("name", "?"))
		_opp_active += 1
		if _opp_active >= _opp.size():
			_end(true)
		else:
			_logln("Opponent sends out %s!" % _opp[_opp_active].get("name", "?"))
			_on_entry(false)
	if not _over and me["current_hp"] <= 0:
		_logln("[color=#f99]%s fainted![/color]" % me.get("name", "?"))
		_active += 1
		if _active >= _team.size():
			_end(false)
		else:
			_logln("Go, %s!" % _team[_active].get("name", "?"))
			_on_entry(true)
	_refresh()

# Living bench members with Vengeance avenge a fallen ally on the enemy lead.
func _vengeance(side: Array, enemy_active: Dictionary) -> void:
	for j in side.size():
		var b: Dictionary = side[j]
		if int(b.get("current_hp", 0)) > 0 and _ab(b) == "vengeance" and int(enemy_active.get("current_hp", 0)) > 0:
			var hit: int = maxi(1, int(b.get("atk", 1)) * 20)
			enemy_active["current_hp"] = maxi(0, int(enemy_active.get("current_hp", 0)) - hit)
			_logln("[color=#f99]%s's Vengeance! %d damage to %s![/color]" % [
				b.get("name", "?"), hit, enemy_active.get("name", "?")])
			if int(enemy_active["current_hp"]) <= 0 and side == _team:
				_credit_stars(b, _ko_credit(b, enemy_active))

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
		if int(b.get("current_hp", 0)) > 0 and _ab(b) == "helping_hand" and not b.get("_hh_used", false):
			b["_hh_used"] = true
			side[active] = b
			side[j] = lead
			_logln("[color=#8fff8f]%s leaps in front of %s — Helping Hand![/color]" % [
				b.get("name", "?"), lead.get("name", "?")])
			_build_cards()
			_on_entry(side == _team)
			return

# Bench abilities that fire each round (Healer supports the lead from behind).
func _bench_round_abilities(side: Array, active: int) -> void:
	if active >= side.size():
		return
	var lead: Dictionary = side[active]
	for j in side.size():
		if j == active:
			continue
		var b: Dictionary = side[j]
		if int(b.get("current_hp", 0)) <= 0 or b.get("_taunted", false):
			continue
		if _ab(b) == "healer" and int(lead.get("current_hp", 0)) > 0 and int(lead.get("current_hp", 0)) < int(lead.get("hp", 1)):
			_heal_mon(lead, 40)
			_logln("[color=#8fff8f]%s's Healer restores 40 HP to %s.[/color]" % [b.get("name", "?"), lead.get("name", "?")])

# ---------------- abilities & held items ----------------

func _ab(mon: Dictionary) -> String:
	return String(mon.get("ability", ""))

func _held(mon: Dictionary) -> StringName:
	return mon.get("held_item", &"")

func _buff(mon: Dictionary, stat: String, delta: int) -> void:
	mon[stat] = clampi(int(mon.get(stat, 1)) + delta, 1, 9)

func _heal_mon(mon: Dictionary, amount: int) -> void:
	mon["current_hp"] = mini(int(mon.get("hp", 1)), int(mon.get("current_hp", 0)) + amount)

# Match-start abilities: fire once per battle from anywhere in the lineup.
func _apply_match_start() -> void:
	_side_match_start(_team, _opp, "Your")
	_side_match_start(_opp, _team, "Enemy")
	# U-Turn last: the lead hits and rotates to the back
	_u_turn(_team, _opp)
	_u_turn(_opp, _team)

func _count_type(side: Array, type: String) -> int:
	var n := 0
	for a in side:
		if String(a.get("type", "")) == type:
			n += 1
	return n

func _side_match_start(mine: Array, theirs: Array, who: String) -> void:
	for m in mine:
		match _ab(m):
			"intimidate":
				for o in theirs:
					_buff(o, "atk", -2)
				_logln("%s %s's Intimidate! Opposing ATK -2." % [who, m.get("name", "?")])
			"screech":
				_buff(theirs[0], "def", -2)
				_logln("%s %s's Screech! %s DEF -2." % [who, m.get("name", "?"), theirs[0].get("name", "?")])
			"drought":
				for a in mine:
					_buff(a, "atk", 1)
				_logln("%s %s's Drought! Team ATK +1." % [who, m.get("name", "?")])
			"tailwind":
				for a in mine:
					_buff(a, "spd", 3)
				_logln("%s %s's Tailwind! Team SPD +3." % [who, m.get("name", "?")])
			"speed_boost":
				for a in mine:
					_buff(a, "atk", 1)
					_buff(a, "spd", 1)
				_logln("%s %s's Speed Boost! Team ATK/SPD +1." % [who, m.get("name", "?")])
			"reflect":
				for a in mine:
					_buff(a, "def", 2)
				_logln("%s %s's Reflect! Team DEF +2." % [who, m.get("name", "?")])
			"veteran":
				if int(m.get("stars", 0)) >= 2:
					_buff(m, "atk", 2)
					_logln("%s %s's Veteran pride! ATK +2." % [who, m.get("name", "?")])
			"thunder_wave":
				_apply_status(theirs[0], "stun", 2, m)
			"confuse_ray":
				_apply_status(theirs[0], "confuse", randi_range(2, 3), m)
			"taunt":
				for o in theirs:
					o["_taunted"] = true
				_logln("[color=#ffd24d]%s %s's Taunt! The other side can't heal or inflict status.[/color]" % [who, m.get("name", "?")])
			"sniper":
				var living: Array = theirs.filter(func(o): return int(o.get("current_hp", 0)) > 0)
				if not living.is_empty():
					var target: Dictionary = living[randi() % living.size()]
					var hit: int = maxi(1, int(m.get("atk", 1)) * 12)
					target["current_hp"] = maxi(1, int(target.get("current_hp", 1)) - hit)
					_logln("%s %s snipes %s for %d!" % [who, m.get("name", "?"), target.get("name", "?"), hit])
			"spikes":
				for o in theirs:
					o["_spikes_pending"] = true
				_logln("%s %s scatters Spikes on the enemy side!" % [who, m.get("name", "?")])
			"monument":
				if mine.size() == 1:
					_buff(m, "atk", 3)
					_buff(m, "def", 3)
					_buff(m, "spd", 3)
					_logln("%s %s is a Monument! +3 to everything." % [who, m.get("name", "?")])
			"fire_bond":
				_buff(m, "atk", 2 * _count_type(mine, "Fire"))
				for a in mine:
					_buff(a, "def", 1)
				_logln("%s %s's Fire Bond! ATK up, team DEF +1." % [who, m.get("name", "?")])
			"water_bond":
				_buff(m, "atk", _count_type(mine, "Water"))
				for a in mine:
					_buff(a, "def", 3)
				_logln("%s %s's Water Bond! ATK up, team DEF +3." % [who, m.get("name", "?")])
			"grass_bond":
				_buff(m, "atk", _count_type(mine, "Grass"))
				for a in mine:
					a["hp"] = int(a.get("hp", 60)) + 30
					_heal_mon(a, 30)
				_logln("%s %s's Grass Bond! ATK up, team +30 HP." % [who, m.get("name", "?")])
			"electric_bond":
				_buff(m, "atk", _count_type(mine, "Electric"))
				for a in mine:
					_buff(a, "spd", 3)
				_logln("%s %s's Electric Bond! ATK up, team SPD +3." % [who, m.get("name", "?")])
			"fighting_bond":
				_buff(m, "atk", 3 * _count_type(mine, "Fighting"))
				_logln("%s %s's Fighting Bond! Huge ATK boost." % [who, m.get("name", "?")])
			"psychic_bond":
				_buff(m, "atk", _count_type(mine, "Psychic"))
				for a in mine:
					a["_status_immune"] = true
				_logln("%s %s's Psychic Bond! Team immune to status." % [who, m.get("name", "?")])
			"dark_bond":
				_buff(m, "atk", _count_type(mine, "Dark"))
				for o in theirs:
					_buff(o, "def", -2)
				_logln("%s %s's Dark Bond! Opposing DEF -2." % [who, m.get("name", "?")])

# U-Turn: the lead lands a free hit, rotates to the back, and hypes the ally
# who takes its place.
func _u_turn(mine: Array, theirs: Array) -> void:
	if mine.size() < 2 or _ab(mine[0]) != "u_turn":
		return
	var m: Dictionary = mine[0]
	var foe: Dictionary = theirs[0]
	var hit: int = maxi(1, int(DamageCalculator.calculate(m, foe) * 0.4))
	foe["current_hp"] = maxi(1, int(foe.get("current_hp", 1)) - hit)
	mine.remove_at(0)
	mine.append(m)
	_buff(mine[0], "atk", 1)
	_logln("%s hits for %d and U-Turns out — %s steps up with ATK +1!" % [
		m.get("name", "?"), hit, mine[0].get("name", "?")])

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
			_logln("%s's Choice Band! ATK +1." % m.get("name", "?"))
		&"vanguard_shield":
			_buff(m, "def", 1)
			_logln("%s's Vanguard Shield! DEF +1." % m.get("name", "?"))
		&"battle_drum":
			if their_idx < theirs.size():
				var foe: Dictionary = theirs[their_idx]
				var hit: int = maxi(1, int(DamageCalculator.calculate(m, foe) * 0.4))
				foe["current_hp"] = maxi(1, int(foe.get("current_hp", 1)) - hit)
				_logln("%s's Battle Drum! Free hit for %d." % [m.get("name", "?"), hit])
		&"trophy":
			var living := 0
			for a in mine:
				if int(a.get("current_hp", 0)) > 0:
					living += 1
			if living <= 1:
				_buff(m, "atk", 1)
				m["_trophy_on"] = true
				_logln("%s raises the Trophy! ATK +1, but it takes more damage." % m.get("name", "?"))
	# stepping onto Spikes
	if m.get("_spikes_pending", false):
		m.erase("_spikes_pending")
		m["current_hp"] = maxi(1, int(m.get("current_hp", 1)) - 30)
		_logln("[color=#ffd24d]%s is hurt by Spikes! -30 HP.[/color]" % m.get("name", "?"))
	match _ab(m):
		"shell_smash":
			_buff(m, "def", -3)
			_buff(m, "atk", 3)
			_buff(m, "spd", 1)
			_logln("%s's Shell Smash! ATK +3, SPD +1, DEF -3." % m.get("name", "?"))
		"all_for_one":
			if mine.size() == 1:
				_buff(m, "atk", 3)
				_buff(m, "def", 3)
				_buff(m, "spd", 3)
				_logln("%s stands alone — All For One! +3 to everything." % m.get("name", "?"))
		"hypnosis":
			if not m.get("_hyp_used", false) and their_idx < theirs.size():
				m["_hyp_used"] = true
				_apply_status(theirs[their_idx], "sleep", 2, m)
		"encore":
			if their_idx < theirs.size():
				theirs[their_idx]["_suppressed"] = 3
				_logln("[color=#ffd24d]%s's Encore! %s's ability is suppressed for 3 rounds.[/color]" % [
					m.get("name", "?"), theirs[their_idx].get("name", "?")])

# ---------------- status effects ----------------

const STATUS_NAMES := {
	"stun": "stunned", "sleep": "asleep", "poison": "poisoned",
	"burn": "burned", "confuse": "confused",
}

func _apply_status(target: Dictionary, kind: String, rounds: int, inflictor: Dictionary = {}) -> void:
	if not inflictor.is_empty() and inflictor.get("_taunted", false):
		return   # taunted spirits can't inflict status
	if target.get("_status_immune", false):
		return
	if _ab(target) == "veteran" and int(target.get("stars", 0)) >= 2:
		return
	if target.has("_status"):
		return   # one status at a time
	target["_status"] = {"kind": kind, "rounds": rounds}
	if kind == "burn":
		_buff(target, "atk", -1)
	_logln("[color=#ffd24d]%s is %s![/color]" % [target.get("name", "?"), STATUS_NAMES.get(kind, kind)])

# Tick the active fighter's status at round start. Returns false if the
# status stops it from attacking this round. Status damage never KOs.
func _process_status(m: Dictionary) -> bool:
	if not m.has("_status"):
		return true
	var st: Dictionary = m["_status"]
	var kind: String = st.get("kind", "")
	var can_act := true
	match kind:
		"poison", "burn":
			m["current_hp"] = maxi(1, int(m.get("current_hp", 1)) - 10)
			_logln("[color=#ffd24d]%s is hurt by %s! -10 HP.[/color]" % [m.get("name", "?"), kind])
		"stun", "sleep":
			can_act = false
			_logln("[color=#ffd24d]%s is %s and can't move![/color]" % [m.get("name", "?"), STATUS_NAMES[kind]])
		"confuse":
			if randf() < 0.5:
				can_act = false
				m["current_hp"] = maxi(1, int(m.get("current_hp", 1)) - 15)
				_logln("[color=#ffd24d]%s hurt itself in confusion! -15 HP.[/color]" % m.get("name", "?"))
	st["rounds"] = int(st.get("rounds", 1)) - 1
	if int(st["rounds"]) <= 0:
		m.erase("_status")
		_logln("%s recovered from being %s." % [m.get("name", "?"), STATUS_NAMES.get(kind, kind)])
	return can_act

# Round-start abilities for the active fighter. Damage here never KOs (it
# leaves at least 1 HP) so the strike order stays clean.
func _round_start_abilities(m: Dictionary, foe: Dictionary) -> void:
	# Encore suppression: no round-start ability while suppressed
	if int(m.get("_suppressed", 0)) > 0:
		m["_suppressed"] = int(m["_suppressed"]) - 1
		return
	# Taunt blocks the healing abilities
	var taunted: bool = m.get("_taunted", false)
	if taunted and _ab(m) in ["dynasty", "regenerator", "wish", "medic"]:
		return
	match _ab(m):
		"fortress":
			if int(m.get("_fortress", 0)) < 3:
				m["_fortress"] = int(m.get("_fortress", 0)) + 1
				_buff(m, "def", 1)
				_logln("%s's Fortress hardens! DEF +1." % m.get("name", "?"))
		"iron_will":
			if int(m.get("current_hp", 0)) >= int(m.get("hp", 1)):
				_buff(m, "atk", 1)
				_logln("%s's Iron Will! ATK +1." % m.get("name", "?"))
		"leech_seed":
			var drain: int = 20 if foe.has("_status") else 10
			foe["current_hp"] = maxi(1, int(foe.get("current_hp", 1)) - drain)
			_heal_mon(m, drain)
			_logln("[color=#8fff8f]%s's Leech Seed drains %d HP from %s.[/color]" % [
				m.get("name", "?"), drain, foe.get("name", "?")])
		"berserker":
			_buff(m, "atk", 2)
			m["current_hp"] = maxi(1, int(m.get("current_hp", 1)) - 20)
			_logln("%s goes Berserk! ATK +2, -20 HP." % m.get("name", "?"))
		"dynasty":
			if int(m.get("current_hp", 0)) < int(m.get("hp", 1)):
				_heal_mon(m, 20)
				_logln("%s's Dynasty restores 20 HP." % m.get("name", "?"))
		"regenerator":
			if int(m.get("current_hp", 0)) < int(m.get("hp", 1)):
				var amount: int = int(m.get("hp", 1) * 0.3)
				_heal_mon(m, amount)
				_logln("%s's Regenerator restores %d HP." % [m.get("name", "?"), amount])
		"wish":
			var mine: Array = _team if _team.has(m) else _opp
			for a in mine:
				if int(a.get("current_hp", 0)) > 0:
					_heal_mon(a, 20)
			_logln("%s makes a Wish — the team heals 20." % m.get("name", "?"))
		"drain_punch":
			var hit: int = maxi(1, int(m.get("atk", 1)) * 12)
			foe["current_hp"] = maxi(1, int(foe.get("current_hp", 1)) - hit)
			_heal_mon(m, hit / 2)
			_logln("%s's Drain Punch! %d damage drained." % [m.get("name", "?"), hit])
		"medic":
			if not m.get("_medic_used", false) and randf() < 0.3:
				var mine2: Array = _team if _team.has(m) else _opp
				for a in mine2:
					if int(a.get("current_hp", 0)) <= 0:
						a["current_hp"] = int(a.get("hp", 1) * 0.25)
						m["_medic_used"] = true
						_logln("%s's Medic revives %s!" % [m.get("name", "?"), a.get("name", "?")])
						break

func _strike(att: Dictionary, def_: Dictionary, attacker_is_me: bool) -> void:
	# attacker items / abilities
	var item_mult := 1.2 if _held(att) == &"expert_belt" else 1.0
	if _ab(att) == "reckless":
		item_mult *= 1.25
	var dmg: int = DamageCalculator.calculate(att, def_, 1.0, 1.0, item_mult)
	# absorb abilities can negate the hit outright
	if _ab(def_) == "flash_fire" and randf() < 0.25:
		_buff(def_, "atk", 2)
		_logln("[color=#8fff8f]%s's Flash Fire absorbs the hit! ATK +2.[/color]" % def_.get("name", "?"))
		return
	if _ab(def_) == "volt_absorb" and randf() < 0.35:
		_heal_mon(def_, dmg)
		_logln("[color=#8fff8f]%s's Volt Absorb turns the hit into %d HP![/color]" % [def_.get("name", "?"), dmg])
		return
	# defender reductions
	var taken := float(dmg)
	if _held(def_) == &"assault_vest":
		taken *= 0.85
	if _ab(def_) == "thick_fat":
		taken *= 0.8
	if _ab(def_) == "reckless":
		taken *= 1.15
	var ratio := float(def_.get("current_hp", 0)) / float(maxi(1, def_.get("hp", 1)))
	if _ab(def_) == "grit" and ratio < 0.3:
		taken *= 0.7
	if _ab(def_) == "bulwark" and ratio > 0.5:
		taken *= 0.8
	if _ab(def_) == "battle_armor" and _round_num <= 2:
		taken *= 0.5
	if _ab(def_) == "multiscale" and def_.get("current_hp", 0) == def_.get("hp", 1) and not def_.get("_ms_used", false):
		taken *= 0.5
		def_["_ms_used"] = true
	if def_.get("_trophy_on", false):
		taken *= 1.2
	var final := maxi(1, int(round(taken)))
	var hp_after: int = int(def_.get("current_hp", 0)) - final
	# survive-lethal effects
	if hp_after <= 0:
		if _held(def_) == &"focus_sash" and not def_.get("_sash_used", false):
			def_["_sash_used"] = true
			hp_after = 1
			_logln("%s hangs on with its Focus Sash!" % def_.get("name", "?"))
		elif _ab(def_) == "sturdy" and not def_.get("_sturdy_used", false):
			def_["_sturdy_used"] = true
			hp_after = 1
			_logln("%s endures the hit — Sturdy!" % def_.get("name", "?"))
		elif _ab(def_) == "anger_point" and not def_.get("_anger_used", false):
			def_["_anger_used"] = true
			hp_after = 1
			_buff(def_, "atk", 3)
			_logln("%s hits its Anger Point! Survives at 1 HP, ATK +3!" % def_.get("name", "?"))
	def_["current_hp"] = maxi(0, hp_after)
	var tag := "[color=#cfe]" if attacker_is_me else "[color=#fdd]"
	var t_mult: float = SpiritsData.type_mult(att.get("type", ""), def_.get("type", ""))
	var eff := ""
	if t_mult > 1.0:
		eff = "  Super effective!"
	elif t_mult < 1.0:
		eff = "  Not very effective…"
	_logln("%s%s hits %s for %d!%s[/color]" % [tag, att.get("name", "?"), def_.get("name", "?"), final, eff])
	# on-hit items / abilities
	if _held(att) == &"shell_bell":
		var sip: int = maxi(1, final / 10)
		_heal_mon(att, sip)
		_logln("%s's Shell Bell restores %d HP." % [att.get("name", "?"), sip])
	if _held(def_) == &"rocky_helmet":
		att["current_hp"] = maxi(1, int(att.get("current_hp", 1)) - 15)
		_logln("%s is hurt by the Rocky Helmet! -15 HP." % att.get("name", "?"))
	if _ab(att) == "thief" and int(att.get("_thief_stacks", 0)) < 3:
		att["_thief_stacks"] = int(att.get("_thief_stacks", 0)) + 1
		_buff(att, "atk", 1)
		_buff(def_, "atk", -1)
		_logln("%s steals power — Thief! ATK +1." % att.get("name", "?"))
	if _ab(def_) == "counter" and final >= 50 and def_["current_hp"] > 0:
		var payback: int = int(final * 0.4)
		att["current_hp"] = maxi(0, int(att.get("current_hp", 0)) - payback)
		_logln("[color=#f99]%s Counters for %d![/color]" % [def_.get("name", "?"), payback])
	# contact statuses punish the attacker
	if def_["current_hp"] > 0:
		match _ab(def_):
			"static":
				if randf() < 0.3:
					_apply_status(att, "stun", 1, def_)
			"poison_point":
				_apply_status(att, "poison", 3, def_)
			"flame_body":
				_apply_status(att, "burn", 3, def_)
			"spore":
				_apply_status(att, ["stun", "poison", "burn", "confuse", "sleep"][randi() % 5], 2, def_)
	# defender recovery / threshold abilities
	if def_["current_hp"] > 0:
		var new_ratio := float(def_["current_hp"]) / float(maxi(1, def_.get("hp", 1)))
		if _held(def_) == &"sitrus_berry" and new_ratio < 0.5 and not def_.get("_berry_used", false):
			def_["_berry_used"] = true
			_heal_mon(def_, int(def_.get("hp", 1) * 0.3))
			_logln("%s munches its Sitrus Berry — HP restored!" % def_.get("name", "?"))
		if _ab(def_) == "blaze" and new_ratio < 0.33 and not def_.get("_blaze_used", false):
			def_["_blaze_used"] = true
			_buff(def_, "atk", 4)
			_buff(def_, "spd", 2)
			_logln("%s's Blaze ignites! ATK +4, SPD +2!" % def_.get("name", "?"))
		if _ab(def_) == "overgrow" and new_ratio < 0.5 and not def_.get("_overgrow_used", false):
			def_["_overgrow_used"] = true
			_buff(def_, "atk", 2)
			_buff(def_, "def", 1)
			_logln("%s's Overgrow surges! ATK +2, DEF +1!" % def_.get("name", "?"))
	else:
		# on-KO effects
		if _held(def_) == &"phoenix_ash" and not def_.get("_phoenix_used", false):
			def_["_phoenix_used"] = true
			def_["current_hp"] = maxi(1, int(def_.get("hp", 1) * 0.25))
			_logln("%s rises from the Phoenix Ash!" % def_.get("name", "?"))
			return
		# star credit: a full star for beating an equal/higher-stage spirit,
		# half a star for a lower one
		if attacker_is_me:
			var credit := _ko_credit(att, def_)
			_credit_stars(att, credit)
			_logln("[color=#d3a8ff]%s earns %s star for the KO![/color]" % [
				att.get("name", "?"), "a" if credit >= 1.0 else "half a"])
		if _ab(def_) == "destiny_bond":
			att["current_hp"] = 0
			_logln("%s's Destiny Bond drags %s down with it!" % [def_.get("name", "?"), att.get("name", "?")])
		elif _ab(def_) == "explosion":
			var boom: int = int(def_.get("hp", 1) * 0.6)
			att["current_hp"] = maxi(0, int(att.get("current_hp", 0)) - boom)
			_logln("%s explodes for %d damage!" % [def_.get("name", "?"), boom])
		if _ab(att) == "moxie":
			_buff(att, "atk", 2)
			_logln("%s's Moxie! ATK +2." % att.get("name", "?"))
		elif _ab(att) == "soul_heart":
			_buff(att, "atk", 1)
			_buff(att, "def", 1)
			_logln("%s's Soul Heart! ATK/DEF +1." % att.get("name", "?"))

func _ko_credit(att: Dictionary, def_: Dictionary) -> float:
	return 1.0 if int(def_.get("stage", 1)) >= int(att.get("stage", 1)) else 0.5

func _end(player_won: bool) -> void:
	_over = true
	_won = player_won
	_next_btn.disabled = true
	_auto_btn.disabled = true
	_skip_btn.disabled = true
	if player_won:
		_logln("[color=#9f9]You won the battle![/color]")
		# survivors share the glory: half a star each
		var survivors: Array = []
		for m in _team:
			if int(m.get("current_hp", 0)) > 0:
				_credit_stars(m, 0.5)
				survivors.append(m.get("name", "?"))
		if not survivors.is_empty():
			_logln("[color=#d3a8ff]%s earn%s half a star for surviving![/color]" % [
				", ".join(survivors), "s" if survivors.size() == 1 else ""])
	else:
		_logln("[color=#f99]Your team was defeated…[/color]")
	_continue_btn.show()

func _logln(t: String) -> void:
	_log.append_text(t + "\n")
