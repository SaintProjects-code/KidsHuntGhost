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

signal closed()

const STAT_LABELS := {"atk": "ATK", "def": "DEF", "spd": "SPD", "hp_stat": "HP", "luck": "LUCK"}

var _idx := -1
var _event: Dictionary = {}
var _spirit: Dictionary = {}       # the wild spirit behind this event
var _pages: Array = []
var _page := 0
var _options: Array = []
var _pending_fight: Dictionary = {}
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

func _ready() -> void:
	var col := _init_window(780, 0)
	col.add_theme_constant_override("separation", 10)
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
	_my_die = DiceView.new(48, 6, Color("cfe8ff"))
	_dice_row.add_child(_my_die)
	_dice_row.add_child(UIKit.label("vs", 16))
	_ev_die = DiceView.new(48, 6, Color("ffd0d0"))
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
	_ok = _button("OK  [Space]", func(): closed.emit(), 40)
	_ok.hide()
	col.add_child(_ok)
	hide()

# The board calls this after the window closes; non-empty = "fight this spirit".
func take_pending_fight() -> Dictionary:
	var f := _pending_fight
	_pending_fight = {}
	return f

func _player() -> PlayerData:
	return GameState.players[_idx]

func _lead() -> Dictionary:
	return _player().lead()

# ── setup ─────────────────────────────────────────────────────────────────────

func present(player_index: int) -> void:
	_idx = player_index
	_cpu = _player().is_cpu
	_pending_fight = {}
	var badges: int = _player().progress.badge_count()
	var pool: Array = EventsData.EVENTS.filter(func(e): return badges >= int(e.get("min_badges", 0)))
	_event = pool.pick_random()
	_setup_cast()
	_result.text = ""
	_dice_text.text = ""
	_dice_row.modulate.a = 0.35
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
	if String(_event.get("kind", "spirit")) == "trainer":
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
	_lead_sprite.texture = SpiritsData.sprite_tex(lead.get("name", ""), "back")
	_lead_stats.text = "%s  [%s]\nHP %d/%d\nATK %d   DEF %d\nSPD %d   🪙 %d" % [
		lead.get("name", "?"), lead.get("type", ""), lead.get("current_hp", 0), lead.get("hp", 0),
		lead.get("atk", 0), lead.get("def", 0), lead.get("spd", 0), _player().inventory.gold]

func _fmt(text: String) -> String:
	return text.replace("{lead}", String(_lead().get("name", "?"))).replace("{spirit}", String(_spirit.get("name", "?")))

# ── pages & choices ───────────────────────────────────────────────────────────

func _show_story(pages: Array, options: Array) -> void:
	_pages = pages
	_options = options
	_page = 0
	_show_page()

func _show_page() -> void:
	_situation.text = _fmt(String(_pages[_page]))
	Juice.slide_in(_situation, 12.0, 0.2)
	UIKit.clear(_choices_box)
	if _page < _pages.size() - 1:
		_choices_box.add_child(_button("Next ▶  [Space]", _next_page, 44))
	else:
		_build_options()

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
			label += "   (%s %d%s → %d%%)" % [STAT_LABELS.get(stat, stat), _stat_of(stat),
				(" +%d type" % bonus) if bonus > 0 else "", int(round(win_chance(o) * 100))]
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
		_dice_row.modulate.a = 1.0
		_dice_text.text = "rolling…"
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
		Juice.shake(_lead_sprite, 8.0)
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
		if _ok.visible:
			closed.emit()
		elif _choices_box.get_child_count() == 1 and _page < _pages.size() - 1:
			_next_page()
		return
	var n := Controls.number_pressed(ev)
	var buttons: Array = _choices_box.get_children().filter(func(c): return c is Button)
	if n >= 0 and n < buttons.size() and not buttons[n].disabled:
		get_viewport().set_input_as_handled()
		buttons[n].pressed.emit()
