extends MenuWindow
## Battle screen, layer 1 of 3: the LOOK. Builds the layout (enemy row on top,
## your row below, log + tactic-card hand + buttons along the bottom), the
## spirit cards, and every animation/log helper the rules layers call.
##   BattleView  →  BattleRules (abilities, statuses, hits)  →  BattleScreen (flow, cards)

signal finished(player_won: bool)

const CARD_SIZE := Vector2(150, 150)   # fixed slot so cards can animate freely
const TRAINER_W := 96.0
const LUNGE := 26.0
const HAND_CARD := Vector2(62, 84)

const CARD_BG := Color(0.55, 0.76, 0.47)
const BANNER_BG := Color(0.07, 0.1, 0.06, 0.85)
const ENEMY_RED := Color(0.85, 0.3, 0.3)

const STATUS_ABBR := {"stun": "STN", "sleep": "SLP", "poison": "PSN", "burn": "BRN", "confuse": "CNF"}
const STATUS_COLORS := {
	"stun": Color(0.8, 0.68, 0.1), "sleep": Color(0.42, 0.47, 0.62),
	"poison": Color(0.55, 0.28, 0.7), "burn": Color(0.85, 0.4, 0.12),
	"confuse": Color(0.8, 0.35, 0.55),
}

# Battle-log palette: your side blue, enemy red, abilities yellow.
const LOG_YOU := "5aa6ff"
const LOG_ENEMY := "ff6a6a"
const LOG_ABILITY := "ffd24d"

# ── battle state shared by all layers ─────────────────────────────────────────
var _team: Array = []
var _opp: Array = []
var _active: int = 0
var _opp_active: int = 0
var _over: bool = false
var _won: bool = false
var _round_num: int = 0
var _speed: float = 1.0
var _skipping: bool = false           # resolving instantly: no animations/beats
var _busy: bool = false               # a sequence (opening / round) is playing
var _pvp_names: Array = []            # [your name, enemy name] in PvP battles

# ── widgets ───────────────────────────────────────────────────────────────────
var _title: Label
var _team_row: HBoxContainer
var _opp_row: HBoxContainer
var _team_cards: Array = []   # per spirit: {slot, card, bg, hp, hp_text, stats, status, status_bg}
var _opp_cards: Array = []
var _team_disc: TrainerDisc
var _opp_disc: TrainerDisc
var _team_name_lbl: Label
var _opp_name_lbl: Label
var _log: RichTextLabel
var _hand_box: HBoxContainer          # your tactic cards (bottom strip)
var _opp_hand_box: HBoxContainer      # the opponent's (face-down, or live in human PvP)
var _next_btn: Button
var _skip_btn: Button
var _continue_btn: Button
var _speed_btn: Button
var _auto_btn: Button
var _team_voters: HBoxContainer
var _opp_voters: HBoxContainer
var _auto := false                    # rounds play by themselves (never picks your cards)
var _detached := false
var _opening_pending := false

func _ready() -> void:
	var col := _init_window(1080, 0)
	col.add_theme_constant_override("separation", 6)
	panel.add_theme_stylebox_override("panel", UIKit.box(UIKit.NIGHT, 18, 3, Color(UIKit.PURPLE, 0.7)))

	var head := UIKit.hbox(12)
	col.add_child(head)
	_title = _title_label("Battle", 18)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_opp_hand_box = UIKit.hbox(4)
	head.add_child(_opp_hand_box)

	var opp_side := _make_team_row(col, false)
	_opp_row = opp_side["cards"]
	_opp_disc = opp_side["disc"]
	_opp_name_lbl = opp_side["name"]
	_opp_voters = opp_side["voters"]

	var vs := UIKit.label("VS", 20, UIKit.GOLD)
	vs.custom_minimum_size = Vector2(TRAINER_W, 0)
	vs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(vs)

	var team_side := _make_team_row(col, true)
	_team_row = team_side["cards"]
	_team_disc = team_side["disc"]
	_team_name_lbl = team_side["name"]
	_team_voters = team_side["voters"]

	# bottom strip: log | your tactic cards | buttons
	var bottom := UIKit.hbox(12)
	col.add_child(bottom)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.custom_minimum_size = Vector2(0, 140)
	_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log.add_theme_font_size_override("normal_font_size", 14)
	_log.add_theme_color_override("default_color", Color.WHITE)
	_log.scroll_following = true
	_log.add_theme_stylebox_override("normal", UIKit.box(Color(0.05, 0.05, 0.08, 0.85), 8, 0, Color.TRANSPARENT, Vector2(8, 4)))
	bottom.add_child(_log)

	var hand_col := UIKit.vbox(2)
	hand_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bottom.add_child(hand_col)
	var hand_hint := UIKit.label("Tactics", 11)
	hand_hint.modulate = Color(1, 1, 1, 0.65)
	hand_col.add_child(hand_hint)
	_hand_box = UIKit.hbox(4)
	_hand_box.custom_minimum_size = Vector2(0, HAND_CARD.y + 12)
	hand_col.add_child(_hand_box)

	var btns := UIKit.vbox(8)
	btns.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bottom.add_child(btns)
	var brow := UIKit.hbox(8)
	btns.add_child(brow)
	_next_btn = _small("Next Round", 110, func(): _on_next())
	brow.add_child(_next_btn)
	_skip_btn = _small("Skip", 70, func(): _on_skip())
	brow.add_child(_skip_btn)
	_continue_btn = _small("Continue", 110, func(): finished.emit(_won))
	_continue_btn.hide()
	brow.add_child(_continue_btn)
	var arow := UIKit.hbox(8)
	btns.add_child(arow)
	_auto_btn = _small("⏸ Auto", 110, _on_auto_toggle)
	arow.add_child(_auto_btn)
	_speed_btn = _small("1x", 70, _on_speed_toggle)
	arow.add_child(_speed_btn)

	# layout is only final once shown — refit every time the window opens,
	# and start the intro once it can actually be seen
	visibility_changed.connect(func():
		if visible:
			_fit_to_screen()
			if _opening_pending:
				_opening_pending = false
				_opening())
	hide()

func _small(text: String, w: float, cb: Callable) -> Button:
	var b := _button(text, cb, 36)
	b.add_theme_font_size_override("font_size", 14)
	b.custom_minimum_size = Vector2(w, 36)
	return b

# One team row: the trainer in a coloured circle (+ name) then the cards.
func _make_team_row(parent: Control, is_player: bool) -> Dictionary:
	var h := UIKit.hbox(12)
	parent.add_child(h)
	var tcol := VBoxContainer.new()
	tcol.custom_minimum_size = Vector2(TRAINER_W, 0)
	tcol.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(tcol)
	var disc := TrainerDisc.new()
	disc.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tcol.add_child(disc)
	var nm := UIKit.label("YOU" if is_player else "ENEMY", 12)
	nm.modulate = Color(1, 1, 1, 0.75)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tcol.add_child(nm)
	var voters := UIKit.hbox(2)   # 🗳 portraits of players who voted for this side
	voters.alignment = BoxContainer.ALIGNMENT_CENTER
	voters.custom_minimum_size = Vector2(0, 24)
	tcol.add_child(voters)
	var cards := UIKit.hbox(10)
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(cards)
	return {"cards": cards, "disc": disc, "name": nm, "voters": voters}

# Fit the window to the game view AND keep it centred. A CenterContainer can't
# lift an oversized child above the top edge, so the panel is placed by hand.
func _fit_to_screen() -> void:
	if not _detached:
		var cc: Node = panel.get_parent()
		if cc != self:
			cc.remove_child(panel)
			add_child(panel)
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
	panel.pivot_offset = Vector2.ZERO
	panel.scale = Vector2(s, s)
	panel.position = (vp - need * s) * 0.5

# ---------------- spirit cards ----------------

func _build_cards() -> void:
	UIKit.clear(_team_row)
	UIKit.clear(_opp_row)
	_team_cards = []
	_opp_cards = []
	for m in _team:
		_team_cards.append(_make_card(m, true))
	for m in _opp:
		_opp_cards.append(_make_card(m, false))

# Name banner, sprite, then HP bar (numbers inside), charge bar (one segment per
# charge the move needs), and the live stats. The card lives inside a fixed-size
# slot so its lunge/shake animations can move it without the row fighting back.
func _make_card(mon: Dictionary, is_player: bool) -> Dictionary:
	var slot := Control.new()
	slot.custom_minimum_size = CARD_SIZE
	slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	(_team_row if is_player else _opp_row).add_child(slot)

	var card := PanelContainer.new()
	card.clip_contents = true
	var bg := UIKit.box(CARD_BG, 8, 0, Color.TRANSPARENT, Vector2(6, 4))
	card.add_theme_stylebox_override("panel", bg)
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	slot.add_child(card)
	var vb := UIKit.vbox(2)
	card.add_child(vb)

	var banner := PanelContainer.new()
	banner.add_theme_stylebox_override("panel", UIKit.box(BANNER_BG, 5, 0, Color.TRANSPARENT, Vector2(6, 1)))
	vb.add_child(banner)
	var name_lbl := UIKit.label("%s %s" % [mon.get("name", "?"), SpiritsData.star_text(mon.get("stars", 0))], 11)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.clip_text = true
	banner.add_child(name_lbl)

	var mv := SpiritsData.move_of(SpiritsData.move_key(mon))
	slot.tooltip_text = "%s — move: %s (%s)\nAbility: %s" % [mon.get("name", "?"), mv["name"], mv["desc"],
		SpiritsData.ability_of(String(mon.get("ability", ""))).get("name", "—")]
	var sprite := UIKit.spirit_sprite(mon, Vector2(0, 56))
	sprite.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(sprite)

	var hp := UIKit.hp_bar(15)
	vb.add_child(hp)
	var hp_text := UIKit.label("", 11, Color.WHITE)
	hp_text.add_theme_color_override("font_outline_color", Color.BLACK)
	hp_text.add_theme_constant_override("outline_size", 3)
	hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hp_text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hp.add_child(hp_text)

	var charge := ChargeBar.new()
	charge.tooltip_text = "%s fires when the bar is full" % mv["name"]
	vb.add_child(charge)

	var stats := RichTextLabel.new()
	stats.bbcode_enabled = true
	stats.fit_content = false               # a long buffed line must never grow the card
	stats.autowrap_mode = TextServer.AUTOWRAP_OFF
	stats.clip_contents = true
	stats.scroll_active = false
	stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats.custom_minimum_size = Vector2(0, 14)
	stats.add_theme_font_size_override("normal_font_size", 11)
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(stats)

	# status badge ("SLP 2"…) pinned top-right, on the slot so it never dims
	var status_bg := UIKit.box(Color(0.5, 0.5, 0.5), 6, 1, Color(0, 0, 0, 0.6))
	var status := UIKit.label("", 10, Color.WHITE)
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
	slot.add_child(status)

	return {"slot": slot, "card": card, "bg": bg, "hp": hp, "hp_text": hp_text, "charge": charge,
		"stats": stats, "status": status, "status_bg": status_bg}

func _refresh() -> void:
	_refresh_side(_team, _team_cards, _active)
	_refresh_side(_opp, _opp_cards, _opp_active)

# Compact "A4▲1 D2 S3" line: green when buffed above the battle-start value,
# red when debuffed, plain otherwise.
func _stat_line(mon: Dictionary) -> String:
	var parts: Array = []
	for pair in [["atk", "ATK "], ["def", "DEF "], ["spd", "SPD "]]:
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
		UIKit.set_hp(c.hp, hp_now, hp_max)
		var cost := int(SpiritsData.move_of(SpiritsData.move_key(mon)).get("charge", 3))
		(c.hp_text as Label).text = "%d / %d" % [hp_now, hp_max]
		(c.charge as ChargeBar).set_gauge(mini(int(mon.get("_charge", 0)), cost), cost)
		(c.stats as RichTextLabel).text = "[center]%s[/center]" % _stat_line(mon)
		# a fainted spirit's card leaves the row once its faint has played out
		(c.slot as Control).visible = not mon.get("_gone", false)
		var st: Dictionary = mon.get("_status", {})
		var badge: Label = c.status
		if st.is_empty() or hp_now <= 0:
			badge.hide()
		else:
			var kind := String(st.get("kind", ""))
			badge.text = "%s %d" % [STATUS_ABBR.get(kind, kind.to_upper()), maxi(1, int(st.get("rounds", 1)))]
			(c.status_bg as StyleBoxFlat).bg_color = STATUS_COLORS.get(kind, Color(0.5, 0.5, 0.5))
			badge.show()
		var sb: StyleBoxFlat = c.bg
		if hp_now <= 0:
			(c.card as Control).modulate = Color(0.45, 0.45, 0.45, 0.7)
			_set_card_glow(sb, false)
		elif i == active and not _over:
			(c.card as Control).modulate = Color.WHITE
			_set_card_glow(sb, true)
		else:
			(c.card as Control).modulate = Color(0.82, 0.82, 0.85, 1)
			_set_card_glow(sb, false)

func _set_card_glow(sb: StyleBoxFlat, on: bool) -> void:
	sb.set_border_width_all(3 if on else 0)
	sb.border_color = UIKit.GOLD
	sb.shadow_color = Color(UIKit.GOLD, 0.5)
	sb.shadow_size = 6 if on else 0

# ---------------- animations ----------------

func _quiet() -> bool:
	return _skipping or not visible

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
	if c.has_meta("anim"):
		var old: Tween = c.get_meta("anim")
		if old.is_valid():
			old.kill()
	c.position = Vector2.ZERO
	var tw := c.create_tween()
	c.set_meta("anim", tw)
	return tw

# Attack: the card lunges toward the opposing row.
func _anim_attack(mon: Dictionary) -> void:
	var c := _card_of(mon)
	if _quiet() or c == null:
		return
	var dy: float = -LUNGE if _team.has(mon) else LUNGE
	var tw := _fresh_tween(c)
	tw.tween_property(c, "position:y", dy, 0.12 / _speed).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "position:y", 0.0, 0.16 / _speed).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	Sfx.play("whoosh", 1.4)

# Ability: a smooth left-right sway.
func _anim_ability(mon: Dictionary) -> void:
	var c := _card_of(mon)
	if _quiet() or c == null:
		return
	var tw := _fresh_tween(c)
	for off in [12.0, -12.0, 8.0, 0.0]:
		tw.tween_property(c, "position:x", off, 0.11 / _speed).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	Sfx.play("pop", 0.8)

# Taking damage: a fast rattle and a white flash.
func _anim_shake(mon: Dictionary) -> void:
	var c := _card_of(mon)
	if _quiet() or c == null:
		return
	var tw := _fresh_tween(c)
	for off in [6.0, -6.0, 5.0, -5.0, 3.0, 0.0]:
		tw.tween_property(c, "position:x", off, 0.035 / _speed)
	Juice.flash(c, Color(2.2, 2.2, 2.2), 0.2 / _speed)

# A number that floats up off a spirit's card ("-34", "+20").
func _float_on(mon: Dictionary, text: String, color: Color) -> void:
	var c := _card_of(mon)
	if _quiet() or c == null:
		return
	Juice.float_text(c.get_parent(), Vector2(CARD_SIZE.x * 0.5, 30), text, color, 24)

# A tactic card banner: slides in over the battle when a card is played and
# again when its effect kicks in ("🛡 Spirit Shield! — Wispy takes half
# damage"), then fades. A newer banner replaces the old one.
var _banner: Control

# A played card / card effect pops up in the empty space on the RIGHT of the
# battle window. side: 1 = your side (it slides up from the bottom), -1 = the
# enemy's (slides down from the top), 0 = neither (slides in from the right).
# It holds for a moment, then leaves the way it came. `key` shows the card itself.
func _tactic_banner(icon: String, headline: String, sub: String, color: Color, side := 0, key := "") -> void:
	if _quiet():
		return
	if is_instance_valid(_banner):
		_banner.queue_free()
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UIKit.box(Color(0.06, 0.04, 0.14, 0.95), 14, 3, color, Vector2(14, 10)))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := UIKit.vbox(6)
	box.add_child(col)
	if key != "":
		var cv := CardView.new(key, Vector2(96, 128))
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cv.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(cv)
	else:
		var ic := UIKit.label(icon, 34)
		ic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(ic)
	var head := UIKit.wrap_label(headline, 17, 190)
	head.add_theme_color_override("font_color", color)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(head)
	if sub != "":
		var sl := UIKit.wrap_label(sub, 13, 190)
		sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(sl)
	add_child(box)
	_banner = box
	box.reset_size()
	var bsize := box.get_combined_minimum_size()
	box.size = bsize
	# the right edge of the battle window, level with the VS line
	var pr := Rect2(panel.position, panel.size * panel.scale)
	var rest := Vector2(pr.end.x - bsize.x - 18, pr.position.y + pr.size.y * 0.42 - bsize.y * 0.5)
	var vp := get_viewport_rect().size
	rest.x = minf(rest.x, vp.x - bsize.x - 8)
	rest.y = clampf(rest.y, 8, vp.y - bsize.y - 8)
	var away := rest + Vector2(0, vp.y * 0.6) if side > 0 else (rest - Vector2(0, vp.y * 0.6) if side < 0 else rest + Vector2(bsize.x + 40, 0))
	box.position = away
	box.modulate.a = 0.0
	var tw := box.create_tween()
	tw.set_parallel(true)
	tw.tween_property(box, "position", rest, 0.28 / _speed).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(box, "modulate:a", 1.0, 0.15 / _speed)
	tw.chain().tween_interval(1.2 / _speed)
	tw.chain().tween_property(box, "position", away, 0.25 / _speed).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(box, "modulate:a", 0.0, 0.25 / _speed)
	tw.chain().tween_callback(box.queue_free)
	Sfx.play("card", 0.9)

# Every battle action plays one at a time: log line + animation, then a beat.
func _beat(time: float = 0.5) -> void:
	_refresh()
	if _quiet():
		return
	await get_tree().create_timer(time / _speed).timeout

func _logln(t: String) -> void:
	_log.append_text(t + "\n")

# A spirit's name coloured by side: yours blue, the enemy's red.
func _who(mon: Dictionary) -> String:
	return "[color=#%s]%s[/color]" % [LOG_YOU if _team.has(mon) else LOG_ENEMY, mon.get("name", "?")]

func _abn(ability_name: String) -> String:
	return "[color=#%s]%s[/color]" % [LOG_ABILITY, ability_name]

# [phase] Ability Spirit effect — sways the card, then holds a beat.
func _ability_line(phase: String, mon: Dictionary, ability_name: String, effect: String) -> void:
	_anim_ability(mon)
	_logln("[%s] %s %s %s" % [phase, _abn(ability_name), _who(mon), effect])
	await _beat(0.55)

func _ability_note(mon: Dictionary, text: String) -> void:
	_anim_ability(mon)
	_logln(text)
	await _beat(0.55)

# Log a passive only the FIRST time it fires this battle (no per-hit spam).
func _passive_once(mon: Dictionary, key: String, effect: String) -> void:
	if mon.get("_plog_" + key, false):
		return
	mon["_plog_" + key] = true
	await _ability_line("Passive", mon, String(SpiritsData.ability_of(key).get("name", key)), effect)

# ---------------- flow buttons (implemented by BattleScreen) ----------------

func _opening() -> void:
	pass

func _on_next() -> void:
	pass

func _on_skip() -> void:
	pass

func _on_auto_toggle() -> void:
	pass

# Battle speed: 1x ⇄ 3x (the label shows the current speed).
func _on_speed_toggle() -> void:
	_speed = {1.0: 2.0, 2.0: 3.0}.get(_speed, 1.0)   # 1x → 2x → 3x → 1x
	_speed_btn.text = "%dx" % int(_speed)
	Sfx.play("click")

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

# The move's charge gauge: one segment per charge it needs; filled segments
# glow gold, and a full gauge (move fires next attack) pulses.
class ChargeBar:
	extends Control
	var charge := 0
	var cost := 3

	func _init() -> void:
		custom_minimum_size = Vector2(0, 9)

	func set_gauge(c: int, total: int) -> void:
		if c != charge or total != cost:
			charge = c
			cost = maxi(1, total)
			queue_redraw()

	func _draw() -> void:
		var gap := 3.0
		var w := (size.x - gap * (cost - 1)) / float(cost)
		var ready := charge >= cost - 1   # one more step fires it
		for k in cost:
			var r := Rect2(k * (w + gap), 0, w, size.y)
			var filled := k < charge
			var col := Color("ffd24d") if filled else Color(0, 0, 0, 0.45)
			if filled and ready:
				col = Color("ffe98a")
			draw_style_box(UIKit.box(col, 3, 1, Color(1, 1, 1, 0.25)), r)

