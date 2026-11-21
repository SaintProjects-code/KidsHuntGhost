extends MenuWindow
## EVENT tile: plays the authored encounters from Data/EventsData.gd.
##   ┌ situation text ───────────┐┌ portrait (trainer / spirit) ┐
##   ├ your lead + stats ────────┤├ choices, each with its odds │
##   └ 🎲 your die  vs  their die ┘└ result + OK                 ┘
## A choice with a stat is a CONTEST: lead's stat (+ type bonus) + 🎲d6 vs the
## option's power + 🎲d6, ties to you — both dice tumble on screen. Outcomes
## can CHAIN into a follow-up page ("go deeper?"). Your lead always takes the
## challenge. Keys: 1–4 pick a choice, Space = Next / OK.
## present(player_index); emits closed(). CPU visits play themselves.
##
## 3D maps use a SCENE layout instead: the event's spirit (or trainer) on a
## platform top-right, your player icon on a platform bottom-left,
## and a dialogue box along the bottom holding the story, your lead's stats
## (they still decide the contests) and the choices.

signal closed()

const STAT_LABELS := {"atk": "ATK", "def": "DEF", "spd": "SPD", "hp_stat": "HP", "luck": "LUCK"}

var _idx := -1
var _event: Dictionary = {}
var _spirit: Dictionary = {}       # the wild spirit behind this event
var _pages: Array = []
var _page := 0
var _options: Array = []
var _pending_fight: Dictionary = {}
var _pending_gang := false        # a Grim Gang fight once the window closes
var _pending_challenge := -1      # a PvP challenge against this player index
var _cpu := false
var _situation: Label
var _portrait: TextureRect
var _lead_sprite: TextureRect
var _lead_stats: Label
var _choices_box: VBoxContainer
var _dice_row: HBoxContainer
var _my_die: DiceView
var _ev_die: DiceView
var _dice_text: Label
var _result: Label
var _ok: Button
var _col: VBoxContainer
var _classic: Array = []            # the card layout's rows (hidden in scene mode)
var _scene_on := false
var _stage: Control                 # scene mode: platforms + the two figures
var _token: TextureRect             # scene mode: your player icon
var _dice3d: SubViewportContainer   # scene mode: the 3D dice

const STAGE_SIZE := Vector2(900, 330)

func _ready() -> void:
	var col := _init_window(780, 0)
	col.add_theme_constant_override("separation", 10)
	_col = col
	var top := UIKit.hbox(12)
	col.add_child(top)
	var situation_card := UIKit.card_panel()
	situation_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(situation_card)
	_situation = UIKit.wrap_label("", 19, 400)
	_situation.custom_minimum_size.y = 130
	_situation.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	situation_card.add_child(_situation)
	var portrait_card := UIKit.card_panel(Vector2(220, 150))
	top.add_child(portrait_card)
	_portrait = UIKit.sprite(null, Vector2(140, 140))
	portrait_card.add_child(_portrait)

	var bottom := UIKit.hbox(12)
	col.add_child(bottom)
	var left := UIKit.vbox(8)
	left.custom_minimum_size.x = 260
	bottom.add_child(left)
	var lead_card := UIKit.card_panel()
	left.add_child(lead_card)
	var lead_row := UIKit.hbox(8)
	lead_card.add_child(lead_row)
	_lead_sprite = UIKit.sprite(null, Vector2(84, 84))
	lead_row.add_child(_lead_sprite)
	_lead_stats = UIKit.label("", 14)
	_lead_stats.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lead_row.add_child(_lead_stats)
	_dice_row = UIKit.hbox(10)
	_dice_row.alignment = BoxContainer.ALIGNMENT_CENTER
	left.add_child(_dice_row)
	_my_die = DiceView.new(48, 6, Color.WHITE)
	_dice_row.add_child(_my_die)
	_dice_row.add_child(UIKit.label("vs", 16))
	_ev_die = DiceView.new(48, 6, Color.WHITE)
	_dice_row.add_child(_ev_die)
	_dice_text = UIKit.label("", 15, UIKit.GOLD)
	_dice_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(_dice_text)

	_choices_box = UIKit.vbox(8)
	_choices_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_choices_box.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_child(_choices_box)
	_result = UIKit.wrap_label("", 18, 720)
	col.add_child(_result)
	_ok = _button("OK", func(): closed.emit(), 40)
	_ok.hide()
	col.add_child(_ok)
	_classic = [top, bottom]
	hide()

# ── 3D maps: the scene layout ─────────────────────────────────────────────────
# Built once, from the same widgets (so the phone mirror and the event logic
# don't change): the stage on top, the dialogue box below.
func _to_scene_layout() -> void:
	_scene_on = true
	var col := _col
	for row in _classic:
		row.hide()
	panel.custom_minimum_size.x = STAGE_SIZE.x + 32
	_stage = Control.new()
	_stage.custom_minimum_size = STAGE_SIZE
	_stage.draw.connect(_draw_stage)
	col.add_child(_stage)
	col.move_child(_stage, 0)
	# the event's spirit / trainer stands on the far platform
	_portrait.reparent(_stage)
	_portrait.custom_minimum_size = Vector2(170, 170)
	_portrait.size = Vector2(170, 170)
	_portrait.position = Vector2(STAGE_SIZE.x * 0.72 - 85, STAGE_SIZE.y * 0.48 - 160)
	# your player icon on the near platform (its picture is set per event)
	_token = TextureRect.new()
	_token.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_token.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_token.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_token.size = Vector2(170, 210)
	_token.position = Vector2(STAGE_SIZE.x * 0.24 - _token.size.x * 0.5, STAGE_SIZE.y - _token.size.y - 4)
	_stage.add_child(_token)
	# the contest dice sit between the two
	_dice_row.reparent(_stage)
	_dice_row.position = Vector2(STAGE_SIZE.x * 0.5 - 70, STAGE_SIZE.y * 0.55)
	_dice3d = preload("res://Scenes/UI/Common/Dice3D.gd").new(Vector2(340, 170))
	_dice3d.position = Vector2(STAGE_SIZE.x * 0.5 - 170, STAGE_SIZE.y * 0.5 - 85)
	_dice3d.visible = false
	_stage.add_child(_dice3d)
	_dice_text.reparent(_stage)
	_dice_text.position = Vector2(STAGE_SIZE.x * 0.5 - 200, STAGE_SIZE.y * 0.55 + 74)
	_dice_text.custom_minimum_size.x = 400
	# the dialogue box: story, whose stats count, the choices, the result, OK
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UIKit.box(Color(0.06, 0.05, 0.12, 0.95), 14, 3, Color(0.92, 0.9, 1.0), Vector2(18, 12)))
	col.add_child(box)
	col.move_child(box, 1)
	box.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed:
			_finish_typing())
	# the story on the left; the choices pop up on the right once it's read
	var inner := UIKit.hbox(16)
	box.add_child(inner)
	var left := UIKit.vbox(8)
	left.size_flags_horizontal = Control.SIZE_FILL   # fixed width: no re-wrap when the choices appear
	inner.add_child(left)
	_situation.reparent(left)
	_situation.custom_minimum_size = Vector2(STAGE_SIZE.x - 440, 96)
	_situation.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_situation.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_lead_stats.reparent(left)
	_lead_stats.add_theme_color_override("font_color", Color("9fdcff"))
	_lead_stats.add_theme_font_size_override("font_size", 13)
	_result.reparent(left)
	_result.custom_minimum_size.x = STAGE_SIZE.x - 440
	_ok.reparent(left)
	_choices_box.reparent(inner)
	_choices_box.custom_minimum_size.x = 380
	_choices_box.size_flags_horizontal = Control.SIZE_SHRINK_END

# ── scene mode: the story types itself out, then the choices pop up ───────────
const TYPE_SPEED := 40.0   # characters per second
var _typing: Tween

func _type_out() -> void:
	if _typing and _typing.is_valid():
		_typing.kill()
	_choices_box.visible = false
	_situation.visible_ratio = 0.0
	var n := _situation.get_total_character_count()
	_typing = create_tween()
	_typing.tween_property(_situation, "visible_ratio", 1.0, maxf(0.3, n / TYPE_SPEED))
	_typing.tween_callback(_reveal_choices)

# A click (or Space) while it's still typing shows the rest at once.
func _finish_typing() -> bool:
	if not _scene_on or _typing == null or not _typing.is_valid() or not _typing.is_running():
		return false
	_typing.kill()
	_situation.visible_ratio = 1.0
	_reveal_choices()
	return true

func _reveal_choices() -> void:
	_choices_box.visible = true
	var i := 0
	for b in _choices_box.get_children():
		var c := b as Control
		c.modulate.a = 0.0
		var tw := c.create_tween()
		tw.tween_interval(i * 0.09)
		tw.tween_property(c, "modulate:a", 1.0, 0.18)
		Juice.pop(c, 1.08, 0.2)
		i += 1
	Sfx.play("pop", 1.1)

# Two oval platforms, like a battle stage: theirs far right, yours near left.
func _draw_stage() -> void:
	var w := STAGE_SIZE.x
	var h := STAGE_SIZE.y
	_stage.draw_rect(Rect2(Vector2.ZERO, STAGE_SIZE), Color(0.12, 0.1, 0.22, 0.55))
	_ellipse(Vector2(w * 0.72, h * 0.48), Vector2(150, 36), Color(0.62, 0.6, 0.8), Color(0.4, 0.37, 0.58))
	_ellipse(Vector2(w * 0.24, h - 8), Vector2(190, 44), Color(0.62, 0.6, 0.8), Color(0.4, 0.37, 0.58))

func _ellipse(c: Vector2, r: Vector2, fill: Color, rim: Color) -> void:
	for pass_i in 2:
		var rr := r if pass_i == 0 else r * Vector2(0.88, 0.78)
		var pts := PackedVector2Array()
		for i in 48:
			var a := i / 48.0 * TAU
			pts.append(c + Vector2(cos(a) * rr.x, sin(a) * rr.y + (0.0 if pass_i == 0 else -3.0)))
		_stage.draw_colored_polygon(pts, rim if pass_i == 0 else fill)

# The board calls this after the window closes; non-empty = "fight this spirit".
func take_pending_fight() -> Dictionary:
	var f := _pending_fight
	_pending_fight = {}
	return f

func take_pending_gang() -> bool:
	var g := _pending_gang
	_pending_gang = false
	return g

func take_pending_challenge() -> int:
	var c := _pending_challenge
	_pending_challenge = -1
	return c

const GANG_PORTRAIT := ["rocketgrunt", "rocketgruntf", "aetherfoundation"]

func _player() -> PlayerData:
	return GameState.players[_idx]

func _lead() -> Dictionary:
	return _player().lead()

# ── setup ─────────────────────────────────────────────────────────────────────

func present(player_index: int, pool_kind := "", only_title := "") -> void:
	_idx = player_index
	_cpu = _player().is_cpu
	if not _scene_on and bool(GameData.map_info(GameState.active_map).get("view_3d", false)):
		_to_scene_layout()
	if _token:
		_token.texture = GameData.trainer_texture(GameData.player_trainer(_player()))
	_pending_fight = {}
	_pending_gang = false
	_pending_challenge = -1
	var badges: int = _player().progress.badge_count()
	var pool: Array = EventsData.EVENTS.filter(func(e): return badges >= int(e.get("min_badges", 0)) \
		and (String(e.get("kind", "")) == "gang_hideout") == (pool_kind == "gang_hideout") \
		and (GameState.players.size() > 1 or not e.get("needs_rival", false)))
	if only_title != "":   # (dev / tests: a specific event)
		pool = EventsData.EVENTS.filter(func(e): return e.get("title", "") == only_title)
	_event = pool.pick_random()
	_setup_cast()
	_result.text = ""
	_dice_text.text = ""
	_dice_row.visible = false   # the dice only appear once a choice is rolled
	if _dice3d:
		_dice3d.visible = false
	_ok.hide()
	_refresh_lead()
	var desc = _event.get("desc", "")
	_show_story(desc if desc is Array else [String(desc)], _event.get("options", []))
	if _cpu:
		_cpu_run()

# The wild spirit behind the event (scaled to the player's badges) + portrait.
func _setup_cast() -> void:
	var tier: int = GameData.challenge_tier(_player().progress.badge_count())
	var portrait = _event.get("portrait", "")
	if String(_event.get("kind", "")) in ["gang", "gang_hideout"]:
		_spirit = SpiritsData.random_spirit(1 if tier == 1 else 2)
		_portrait.texture = GameData.trainer_texture(GANG_PORTRAIT + ["acetrainer"])
	elif String(_event.get("kind", "spirit")) == "trainer":
		_spirit = SpiritsData.random_spirit(1 if tier == 1 else 2)
		var cands: Array = portrait if portrait is Array else [String(portrait)]
		_portrait.texture = GameData.trainer_texture(cands + ["acetrainer", "acetrainer-gen1"])
	else:
		if String(portrait) == "@legendary":
			_spirit = SpiritsData.random_legendary()
		elif String(portrait) != "":
			_spirit = SpiritsData.get_spirit(String(portrait))
		if _spirit.is_empty() or String(portrait) == "":
			_spirit = SpiritsData.random_spirit(1)
		_portrait.texture = SpiritsData.sprite_tex(_spirit.get("name", ""), "front")
	_spirit["stars"] = tier - 1

func _refresh_lead() -> void:
	var lead := _lead()
	if _scene_on:
		# your trainer is on stage; the lead's stats still decide the contests
		_lead_stats.text = "Using %s's stats  [%s]   HP %d/%d · ATK %d · DEF %d · SPD %d   🪙 %d" % [
			lead.get("name", "?"), lead.get("type", ""), lead.get("current_hp", 0), lead.get("hp", 0),
			lead.get("atk", 0), lead.get("def", 0), lead.get("spd", 0), _player().inventory.gold]
		return
	_lead_sprite.texture = SpiritsData.sprite_tex(lead.get("name", ""), "back")
	_lead_stats.text = "%s  [%s]\nHP %d/%d\nATK %d   DEF %d\nSPD %d   🪙 %d" % [
		lead.get("name", "?"), lead.get("type", ""), lead.get("current_hp", 0), lead.get("hp", 0),
		lead.get("atk", 0), lead.get("def", 0), lead.get("spd", 0), _player().inventory.gold]

func _fmt(text: String) -> String:
	return text.replace("{lead}", String(_lead().get("name", "?"))).replace("{spirit}", String(_spirit.get("name", "?")))

# ── pages & choices ───────────────────────────────────────────────────────────

func _show_story(pages: Array, options: Array) -> void:
	_dice_row.visible = false   # a new page: no dice until the next roll
	if _dice3d:
		_dice3d.visible = false
	_dice_text.text = ""
	_pages = pages
	_options = options
	_page = 0
	_show_page()

func _show_page() -> void:
	_situation.text = _fmt(String(_pages[_page]))
	Juice.slide_in(_situation, 12.0, 0.2)
	UIKit.clear(_choices_box)
	if _page < _pages.size() - 1:
		_choices_box.add_child(_button("Next ▶", _next_page, 44))
	else:
		_build_options()
	if _scene_on:
		_type_out()

func _next_page() -> void:
	_page += 1
	Sfx.play("click")
	_show_page()

# Options you can't take (no card / not enough gold) are hidden or locked.
func _visible_options() -> Array:
	return _options.filter(func(o): return String(o.get("need_card", "")) == "" \
		or _player().inventory.has_card(String(o["need_card"])))

func _build_options() -> void:
	var opts := _visible_options()
	for i in opts.size():
		var o: Dictionary = opts[i]
		var stat := String(o.get("stat", ""))
		var label := "%d · %s" % [i + 1, _fmt(String(o.get("label", "?")))]
		if o.has("need_card"):
			label += "   (uses %s — sure thing!)" % CardsData.card_name(o["need_card"])
		elif stat != "":
			var bonus := _type_bonus(o)
			label += "   (%s %d%s)" % [STAT_LABELS.get(stat, stat), _stat_of(stat),
				(" +%d type" % bonus) if bonus > 0 else ""]
		var b := _button(label, _on_option.bind(o), 44)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var cost := int(o.get("cost", 0))
		if cost > 0 and _player().inventory.gold < cost:
			b.disabled = true
			b.text += "  — need %dg" % cost
		b.disabled = b.disabled or _cpu
		_choices_box.add_child(b)

func _stat_of(stat: String) -> int:
	return 0 if stat == "luck" else int(_lead().get(stat, 0))

func _type_bonus(o: Dictionary) -> int:
	return int(o.get("type_bonus", {}).get(String(_lead().get("type", "")), 0))

func _power_of(o: Dictionary) -> int:
	return int(o.get("power", 0 if String(o.get("stat", "")) == "luck" else 3))

# Exact odds of stat + bonus + d6 ≥ power + d6.
func win_chance(o: Dictionary) -> float:
	if String(o.get("stat", "")) == "" or o.has("need_card"):
		return 1.0
	var mine := _stat_of(String(o["stat"])) + _type_bonus(o)
	var wins := 0
	for a in range(1, 7):
		for b in range(1, 7):
			if mine + a >= _power_of(o) + b:
				wins += 1
	return wins / 36.0

func _on_option(opt: Dictionary) -> void:
	UIKit.clear(_choices_box)
	Sfx.play("click")
	var p := _player()
	p.inventory.gold -= int(opt.get("cost", 0))
	if opt.has("need_card"):
		CardSystem.remove(_idx, String(opt["need_card"]))
		Sfx.play("card")
	var stat := String(opt.get("stat", ""))
	var success := true
	if stat != "" and not opt.has("need_card"):
		var mine := _stat_of(stat) + _type_bonus(opt)
		var power := _power_of(opt)
		var my_roll := randi_range(1, 6)
		var ev_roll := randi_range(1, 6)
		success = mine + my_roll >= power + ev_roll
		_dice_text.text = "rolling…"
		if _scene_on:
			_dice3d.visible = true
			await _dice3d.roll([my_roll, ev_roll])   # yours on the left, theirs on the right
		else:
			_dice_row.visible = true
			Juice.pop(_dice_row, 1.15)
			_ev_die.roll(ev_roll, 0.7)
			await _my_die.roll(my_roll, 0.7)
		_dice_text.text = "You %d+🎲%d = %d   vs   %d+🎲%d = %d" % [mine, my_roll, mine + my_roll, power, ev_roll, power + ev_roll]
		Juice.pop(_dice_text, 1.25)
		await get_tree().create_timer(0.3).timeout
	var outcome: Dictionary = opt.get("win", {}) if success else opt.get("lose", {})
	var msg := await _apply_outcome(outcome)
	_result.text = msg
	_result.add_theme_color_override("font_color", UIKit.GOOD if success else UIKit.BAD)
	Juice.pop(_result, 1.06)
	Sfx.play("caught" if success else "lose")
	if not success:
		Juice.shake(_token if _scene_on else _lead_sprite, 8.0)
	_refresh_lead()
	EventBus.log_entry.emit(_idx, "%s: %s" % [_event.get("title", "Event"), msg], "#9fff9f" if success else "#ff9f9f")
	# the story may continue (push your luck!)
	var nxt: Dictionary = outcome.get("next", {})
	if not nxt.is_empty():
		await get_tree().create_timer(0.4).timeout
		_show_story([String(nxt.get("desc", ""))], nxt.get("options", []))
		if _cpu:
			_cpu_choose()
		return
	if not _cpu:
		_ok.show()

# ── outcome effects ───────────────────────────────────────────────────────────

func _apply_outcome(out: Dictionary) -> String:
	var p := _player()
	var lead := _lead()
	var parts: Array = []
	if out.has("text"):
		parts.append(_fmt(String(out["text"])))
	if out.has("gold"):
		var g: int = maxi(int(out["gold"]), -p.inventory.gold)   # never below 0
		p.inventory.gold += g
		parts.append("%+d gold." % g)
		if g > 0:
			Sfx.play("coin")
	if out.has("lanterns") and int(out["lanterns"]) < 0:
		var lanterns: Array = p.inventory.lanterns()
		if not lanterns.is_empty():
			CardSystem.remove(_idx, lanterns[0])
			parts.append("You lose a %s!" % CardsData.card_name(lanterns[0]))
	if out.has("damage"):
		lead["current_hp"] = maxi(0, int(lead.get("current_hp", 0)) - int(out["damage"]))
		parts.append("%s takes %d damage!%s" % [lead["name"], out["damage"], " It fainted!" if int(lead["current_hp"]) <= 0 else ""])
	if out.has("heal"):
		var full := String(out["heal"]) == "full"
		lead["current_hp"] = int(lead["hp"]) if full else mini(int(lead["hp"]), int(lead["current_hp"]) + int(out["heal"]))
		parts.append("%s is %s!" % [lead["name"], "fully healed" if full else "healed"])
	if out.get("heal_team", false):
		for m in p.team:
			m["current_hp"] = m.get("hp", 0)
		parts.append("The whole team is fully healed!")
		Sfx.play("heal")
	if out.get("join", false):
		parts.append(_join_spirit(p))
	if out.get("lose_spirit", false) and p.team.size() > 1:
		var gone: Dictionary = p.team.pop_at(1 + randi() % (p.team.size() - 1))   # never the lead
		parts.append("%s gets scared and runs away!" % gone["name"])
	if out.get("lose_card", false):
		if p.inventory.hand.is_empty():
			var amount := mini(10, p.inventory.gold)
			p.inventory.gold -= amount
			parts.append("No cards to grab… it takes %d gold instead." % amount)
		else:
			var key: String = p.inventory.hand.pick_random()
			CardSystem.remove(_idx, key)
			parts.append("It makes off with your %s!" % CardsData.card_name(key))
	if out.has("battle_mod"):
		p.next_battle_mod = int(out["battle_mod"])
		parts.append("(ATK %+d next battle)" % int(out["battle_mod"]))
	if out.has("trait"):
		parts.append(EventsData.grant_trait(lead, String(out["trait"])))
	if out.get("star", false):
		parts.append("%s gains a star! ★" % lead["name"])
	if out.get("fight", false):
		_pending_fight = _spirit.duplicate(true)
		_pending_fight["_event_fight"] = true   # a real battle, not a hunt
		if String(_event.get("kind", "spirit")) == "trainer":
			_pending_fight["_no_catch"] = true   # a trainer's spirit: no catching
			var por = _event.get("portrait", [])
			_pending_fight["_portrait"] = (por if por is Array else [String(por)]) + ["acetrainer"]
			_pending_fight["_trainer_name"] = String(_event.get("title", "Trainer"))
	parts.append_array(_board_outcome(out))
	var msg := " ".join(parts)
	# cards and stars may pop their own windows (hand full / bonus reward)
	for n in maxi(0, int(out.get("lanterns", 0))):
		msg += " You get a Spirit Lantern!"
		await CardSystem.give(_idx, "spirit_lantern")
	if out.has("card"):
		var kind := String(out["card"])
		var key := CardsData.random_card(kind if kind in ["field", "tactic", "charm"] else "") \
			if kind in ["random", "field", "tactic", "charm"] else kind
		msg += " You get %s!" % CardsData.card_name(key)
		await CardSystem.give(_idx, key)
	if out.get("star", false):
		await SpiritsProgressionSystem.award_star(_idx, lead)
	return msg

# ── outcomes that change the board and the other players ─────────────────────

func _board() -> Node:
	var b := get_tree().current_scene
	return b if b and b.has_method("shift_player") else null

# Another player: "leader" (most points, not you), "last" (fewest), "random".
func _other(which: String) -> int:
	var others: Array = []
	for j in GameState.players.size():
		if j != _idx:
			others.append(j)
	if others.is_empty():
		return -1
	match which:
		"leader":
			others.sort_custom(func(a, b): return GameState.players[a].progress.points > GameState.players[b].progress.points)
		"last":
			others.sort_custom(func(a, b): return GameState.players[a].progress.points < GameState.players[b].progress.points)
		_:
			others.shuffle()
	return others[0]

func _board_outcome(out: Dictionary) -> Array:
	var parts: Array = []
	var p := _player()
	var board := _board()
	if out.has("move") and board:
		var n := int(out["move"])
		board.shift_player(_idx, n)
		parts.append("%s %s %d space%s." % [p.player_name, "moves ahead" if n > 0 else "is pushed back", absi(n), "" if absi(n) == 1 else "s"])
	if out.has("others_move") and board:
		var n2 := int(out["others_move"])
		for j in GameState.players.size():
			if j != _idx:
				board.shift_player(j, n2)
		parts.append("Everyone else %s %d!" % ["moves ahead" if n2 > 0 else "is pushed back", absi(n2)])
	if out.has("warp") and board:
		var towns: Array = board.town_cities()
		var city := ""
		match String(out["warp"]):
			"hideout":
				city = GameState.gang_hideout
			"home":
				city = towns[0] if not towns.is_empty() else ""
			_:
				city = towns.pick_random() if not towns.is_empty() else ""
		if city != "":
			board.warp_player(_idx, city)
			parts.append("%s is whisked away to %s!" % [p.player_name, board.graph.label(city)])
	if out.has("swap") and board:
		var j := _other(String(out["swap"]))
		if j >= 0:
			board.swap_players(_idx, j)
			parts.append("%s swaps places with %s!" % [p.player_name, GameState.players[j].player_name])
	if out.get("skip", false):
		p.skip_turns += 1
		parts.append("%s will miss a turn!" % p.player_name)
	if out.has("weather"):
		var kind := String(out["weather"])
		if kind == "@spirit":
			kind = WeatherData.for_type(String(_spirit.get("type", "")))
		elif kind == "random":
			kind = WeatherData.KINDS.keys().pick_random()
		GameState.set_weather(kind)
		var w := WeatherData.info(kind)
		parts.append("%s %s rolls in for 2 rounds!" % [w["icon"], w["name"]])
	if out.has("points"):
		GameState.award_points(_idx, int(out["points"]))
		parts.append("+%d pt!" % int(out["points"]))
	if out.has("gold_from_all"):
		var got := 0
		for j in GameState.players.size():
			if j != _idx:
				var g := mini(int(out["gold_from_all"]), GameState.players[j].inventory.gold)
				GameState.players[j].inventory.gold -= g
				got += g
		p.inventory.gold += got
		parts.append("Every player pays you — +%d gold!" % got)
	if out.get("leader_pays_all", 0) != 0:
		var lead_j := -1
		for j in GameState.players.size():
			if lead_j < 0 or GameState.players[j].progress.points > GameState.players[lead_j].progress.points:
				lead_j = j
		var each := int(out["leader_pays_all"])
		var payer: PlayerData = GameState.players[lead_j]
		for j in GameState.players.size():
			if j != lead_j:
				var g2 := mini(each, payer.inventory.gold)
				payer.inventory.gold -= g2
				GameState.players[j].inventory.gold += g2
		parts.append("%s (the leader) pays everyone %d gold!" % [payer.player_name, each])
	if out.get("all_lantern", false):
		for j in GameState.players.size():
			if not GameState.players[j].inventory.hand_full():
				GameState.players[j].inventory.hand.append("spirit_lantern")
				EventBus.hand_changed.emit(j)
		parts.append("Every player gets a Spirit Lantern!")
	if out.has("all_trait"):
		for q in GameState.players:
			if not q.team.is_empty():
				EventsData.grant_trait(q.lead(), String(out["all_trait"]))
		parts.append("It spreads to EVERY player's lead!")
	if out.get("hex", false):
		parts.append(CardSystem.hex_leader(_idx))
	if out.get("gang_fight", false):
		_pending_gang = true
		parts.append("☠ The Grim Gang attacks!")
	if out.has("challenge"):
		_pending_challenge = _other(String(out["challenge"]))
		if _pending_challenge >= 0:
			parts.append("⚔ %s is challenged to a battle!" % GameState.players[_pending_challenge].player_name)
	return parts

const WeatherData := preload("res://Data/WeatherData.gd")

func _join_spirit(p: PlayerData) -> String:
	var joiner: Dictionary = _spirit.duplicate(true)
	joiner["current_hp"] = joiner.get("hp", 1)
	joiner["stars"] = 0
	Sfx.play("caught")
	if p.team.size() < Balance.TEAM_MAX:
		p.team.append(joiner)
		return "%s joins your team!" % joiner["name"]
	p.pc.append(joiner)
	return "%s joins you — sent to the Spirit Box (team full)!" % joiner["name"]

# ── CPU: the same window plays itself ─────────────────────────────────────────

func _cpu_run() -> void:
	await get_tree().create_timer(1.3).timeout
	while visible and _page < _pages.size() - 1:
		_next_page()
		await get_tree().create_timer(1.3).timeout
	if visible:
		_cpu_choose()

# The CPU takes the option with the best odds, nudged by how good the win
# looks (sure things that cost cards/gold are taken when affordable).
func _cpu_choose() -> void:
	await get_tree().create_timer(0.8).timeout
	if not visible:
		return
	var opts: Array = _visible_options().filter(func(o): return _player().inventory.gold >= int(o.get("cost", 0)))
	if opts.is_empty():
		closed.emit()
		return
	var best: Dictionary = opts[0]
	var best_v := -1.0
	for o in opts:
		var v := win_chance(o) + randf_range(0.0, 0.25)
		if v > best_v:
			best_v = v
			best = o
	await _on_option(best)
	if _ok.visible or _choices_box.get_child_count() == 0:
		await get_tree().create_timer(2.2).timeout
		if visible:
			closed.emit()

func _unhandled_key_input(ev: InputEvent) -> void:
	if not visible or _cpu:
		return
	if Controls.confirm_pressed(ev):
		get_viewport().set_input_as_handled()
		if _finish_typing():
			return
		if _ok.visible:
			closed.emit()
		elif _choices_box.get_child_count() == 1 and _page < _pages.size() - 1:
			_next_page()
		return
	var n := Controls.number_pressed(ev)
	if not _choices_box.visible:
		return
	var buttons: Array = _choices_box.get_children().filter(func(c): return c is Button)
	if n >= 0 and n < buttons.size() and not buttons[n].disabled:
		get_viewport().set_input_as_handled()
		buttons[n].pressed.emit()
