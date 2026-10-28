extends MenuWindow
## EVENT tile: plays the authored encounters from Data/EventsData.gd.
##   ┌ situation card ─────────┐┌ big portrait (trainer │
##   │ "A burly hiker blocks   ││   or wild spirit)     │
##   │  the bridge…"           │└───────────────────────┘
##   └─────────────────────────┘┌ choice banners        │
##   ┌ your lead + stats ──────┐│ 💪 Arm-wrestle (ATK 4)│
##   └─────────────────────────┘│ 💨 Dash past  (SPD 3) │
##
## Multi-page descriptions show a "Next ▶" button between pages. A choice
## with a stat runs a CONTEST: lead's stat + 🎲d6 vs option power + 🎲d6
## (ties go to the player; "luck" = pure roll-off). The outcome then applies
## whatever the event data says: gold/items/damage/heals/joins/traits/fights.
## present(player_index); emits closed(). resolve_cpu() = same rules, no UI.

signal closed()

const CARD_BG := Color(0.08, 0.07, 0.16, 0.95)
const STAT_LABELS := {"atk": "ATK", "def": "DEF", "spd": "SPD", "hp_stat": "HP", "luck": "LUCK"}

var _player_index: int = -1
var _event: Dictionary = {}
var _spirit: Dictionary = {}       # the wild spirit behind this event
var _pages: Array = []
var _page: int = 0
var _pending_fight: Dictionary = {}
var _situation: Label
var _portrait: TextureRect
var _lead_sprite: TextureRect
var _lead_stats: Label
var _choices_box: VBoxContainer
var _result: Label
var _ok: Button

func _ready() -> void:
	var col := _init_window(760, 0)
	col.add_theme_constant_override("separation", 10)

	# top row: situation card (left) + portrait (right)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	col.add_child(top)

	var situation_card := _card()
	situation_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(situation_card)
	_situation = Label.new()
	_situation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_situation.add_theme_font_size_override("font_size", 20)
	_situation.custom_minimum_size = Vector2(380, 130)
	_situation.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_situation.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	situation_card.add_child(_situation)

	var portrait_card := _card()
	portrait_card.custom_minimum_size = Vector2(220, 150)
	top.add_child(portrait_card)
	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(140, 140)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait_card.add_child(_portrait)

	# bottom row: your lead + stats (left) + choice banners (right)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	col.add_child(bottom)

	var lead_card := _card()
	lead_card.custom_minimum_size = Vector2(250, 0)
	bottom.add_child(lead_card)
	var lead_row := HBoxContainer.new()
	lead_row.add_theme_constant_override("separation", 8)
	lead_card.add_child(lead_row)
	_lead_sprite = TextureRect.new()
	_lead_sprite.custom_minimum_size = Vector2(96, 96)
	_lead_sprite.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_lead_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_lead_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_lead_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	lead_row.add_child(_lead_sprite)
	_lead_stats = Label.new()
	_lead_stats.add_theme_font_size_override("font_size", 15)
	_lead_stats.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lead_row.add_child(_lead_stats)

	_choices_box = VBoxContainer.new()
	_choices_box.add_theme_constant_override("separation", 8)
	_choices_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_choices_box.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_child(_choices_box)

	_result = Label.new()
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result.add_theme_font_size_override("font_size", 18)
	_result.custom_minimum_size = Vector2(700, 0)
	col.add_child(_result)

	_ok = _button("OK", func(): closed.emit(), 40)
	_ok.hide()
	col.add_child(_ok)
	hide()

func _card() -> PanelContainer:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = CARD_BG
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(0.541, 0.435, 0.965, 0.5)
	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_left = 12
	sb.corner_radius_bottom_right = 12
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	card.add_theme_stylebox_override("panel", sb)
	return card

# The board (TileController) calls this after the window closes; a non-empty
# result means "the event turned into a fight vs this spirit".
func take_pending_fight() -> Dictionary:
	var f := _pending_fight
	_pending_fight = {}
	return f

# ── setup ─────────────────────────────────────────────────────────────────────

# Pick a random event the player is eligible for. Events with a "min_badges"
# gate (the legendary encounter needs 2+) only enter the pool once earned.
func _pick_event() -> Dictionary:
	var badges: int = GameState.players[_player_index].progress.badge_count()
	var pool: Array = EventsData.EVENTS.filter(func(e): return badges >= int(e.get("min_badges", 0)))
	return pool.pick_random() if not pool.is_empty() else EventsData.EVENTS.pick_random()

func present(player_index: int) -> void:
	_player_index = player_index
	_pending_fight = {}
	_event = _pick_event()
	_setup_event()
	var p: PlayerData = GameState.players[player_index]
	var lead: Dictionary = p.team[0]
	_lead_sprite.texture = SpiritsData.sprite_tex(lead.get("name", ""), "back")
	_lead_stats.text = "%s\nHP %d/%d\nATK %d   DEF %d\nSPD %d   🪙 %d" % [
		lead.get("name", "?"), lead.get("current_hp", 0), lead.get("hp", 0),
		lead.get("atk", 0), lead.get("def", 0), lead.get("spd", 0), p.inventory.gold]
	_result.text = ""
	_ok.hide()
	_page = 0
	_show_page()

# Resolve the event's cast: the wild spirit behind it and the portrait shown.
# Fight spirits scale with the player's badges (tier 1 weak → tier 3 strong).
func _setup_event() -> void:
	var tier: int = GameData.challenge_tier(
		GameState.players[_player_index].progress.badge_count())
	var portrait = _event.get("portrait", "")
	if String(_event.get("kind", "spirit")) == "trainer":
		# trainer portrait, with fallbacks; the fight spirit is a random wild
		_spirit = SpiritsData.random_spirit(1 if tier == 1 else 2)
		var candidates: Array = portrait if portrait is Array else [String(portrait)]
		_portrait.texture = GameData.trainer_texture(candidates + ["acetrainer", "acetrainer-gen1"])
	elif String(portrait) == "@legendary":
		# the legendary event — the ONLY place a legendary spirit appears
		_spirit = SpiritsData.random_legendary()
		_portrait.texture = SpiritsData.sprite_tex(_spirit.get("name", ""), "front")
	else:
		var sp_name := String(portrait)
		_spirit = SpiritsData.get_spirit(sp_name) if sp_name != "" else SpiritsData.random_spirit(1)
		if _spirit.is_empty():
			_spirit = SpiritsData.random_spirit(1)
		_portrait.texture = SpiritsData.sprite_tex(_spirit.get("name", ""), "front")
	_spirit["stars"] = tier - 1   # tougher events for badge-heavy trainers

# "{lead}" / "{spirit}" placeholders → real names.
func _fmt(text: String) -> String:
	var lead: Dictionary = GameState.players[_player_index].team[0]
	return text.replace("{lead}", String(lead.get("name", "?"))) \
		.replace("{spirit}", String(_spirit.get("name", "?")))

# ── pages & choices ───────────────────────────────────────────────────────────

func _show_page() -> void:
	var desc = _event.get("desc", "")
	_pages = desc if desc is Array else [String(desc)]
	_situation.text = _fmt(String(_pages[_page]))
	for c in _choices_box.get_children():
		c.queue_free()
	if _page < _pages.size() - 1:
		_choices_box.add_child(_button("Next ▶", _next_page, 44))
	else:
		_build_options()

func _next_page() -> void:
	_page += 1
	_show_page()

func _build_options() -> void:
	var lead: Dictionary = GameState.players[_player_index].team[0]
	for opt in _event.get("options", []):
		var o: Dictionary = opt
		var label: String = _fmt(String(o.get("label", "?")))
		var stat := String(o.get("stat", ""))
		if stat == "luck":
			label += "   (🎲 luck)"
		elif stat != "":
			label += "   (%s %d)" % [STAT_LABELS.get(stat, stat), int(lead.get(stat, 0))]
		var b := _button(label, _on_option.bind(o), 44)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_choices_box.add_child(b)

func _on_option(opt: Dictionary) -> void:
	for c in _choices_box.get_children():
		c.queue_free()
	var lead: Dictionary = GameState.players[_player_index].team[0]
	var stat := String(opt.get("stat", ""))
	var prefix := ""
	var success := true
	if stat != "":
		# the contest: lead's stat + d6 vs the option's power + d6, ties to you
		var mine: int = 0 if stat == "luck" else int(lead.get(stat, 0))
		var power: int = int(opt.get("power", 3))
		var my_roll := randi_range(1, 6)
		var ev_roll := randi_range(1, 6)
		success = mine + my_roll >= power + ev_roll
		prefix = "You %d+🎲%d = %d   vs   %d+🎲%d = %d\n" % [
			mine, my_roll, mine + my_roll, power, ev_roll, power + ev_roll]
	var outcome: Dictionary = opt.get("win", {}) if success else opt.get("lose", {})
	var msg := _apply_outcome(outcome)
	_result.text = prefix + msg
	_result.add_theme_color_override("font_color", Color("9fff9f") if success else Color("ff9f9f"))
	EventBus.log_entry.emit(_player_index, "%s: %s" % [_event.get("title", "Event"), msg],
		"#9fff9f" if success else "#ff9f9f")
	_ok.show()

# ── outcome effects ───────────────────────────────────────────────────────────

func _apply_outcome(out: Dictionary) -> String:
	var p: PlayerData = GameState.players[_player_index]
	var lead: Dictionary = p.team[0]
	var parts: Array = []
	if out.has("text"):
		parts.append(_fmt(String(out["text"])))
	if out.has("gold"):
		var g: int = int(out["gold"])
		if g < 0:
			g = -mini(-g, p.inventory.gold)   # can't go below 0
		p.inventory.gold += g
		parts.append("%+d gold." % g)
	if out.has("item"):
		parts.append(_give_item(p, String(out["item"])))
	if out.get("lose_item", false):
		parts.append(_lose_item(p))
	if out.has("damage"):
		parts.append(_damage_lead(p, int(out["damage"])))
	if out.has("heal"):
		if String(out["heal"]) == "full" or not (out["heal"] is int):
			lead["current_hp"] = lead.get("hp", 0)
			parts.append("%s is fully healed!" % lead.get("name", "?"))
		else:
			lead["current_hp"] = mini(int(lead.get("hp", 0)), int(lead.get("current_hp", 0)) + int(out["heal"]))
			parts.append("%s heals %d HP." % [lead.get("name", "?"), int(out["heal"])])
	if out.get("heal_team", false):
		for m in p.team:
			m["current_hp"] = m.get("hp", 0)
		parts.append("The whole team is fully healed!")
	if out.get("join", false):
		parts.append(_join_spirit(p))
	if out.get("lose_spirit", false):
		parts.append(_lose_spirit(p))
	if out.has("battle_mod"):
		p.next_battle_mod = int(out["battle_mod"])
		parts.append("(ATK %+d next battle)" % int(out["battle_mod"]))
	if out.get("star", false):
		SpiritsProgressionSystem._award_star(_player_index, lead)
		parts.append("%s gains a star! ★" % lead.get("name", "?"))
	if out.has("trait"):
		parts.append(_grant_trait(lead, String(out["trait"])))
	if out.get("fight", false):
		_pending_fight = _spirit.duplicate(true)
		if String(_event.get("kind", "spirit")) == "trainer":
			_pending_fight["_no_catch"] = true   # a trainer's spirit: no catching
	return " ".join(parts)

func _give_item(p: PlayerData, kind: String) -> String:
	var item: Dictionary
	match kind:
		"potion":        item = {"name": "Potion", "kind": "potion", "amount": 40}
		"super_potion":  item = {"name": "Super Potion", "kind": "potion", "amount": 80}
		"revive":        item = {"name": "Revive", "kind": "revive"}
		"held_random":   item = GameData.held_item_entry(GameData.random_held_key())
		"ball":
			p.inventory.balls[&"spirit_ball"] = p.inventory.ball_count(&"spirit_ball") + 1
			return "You get a Spirit Ball!"
		_:               return ""
	if p.inventory.add_item(item):
		return "You receive a %s!" % item["name"]
	p.inventory.balls[&"spirit_ball"] = p.inventory.ball_count(&"spirit_ball") + 1
	return "Bag full — you get a Spirit Ball instead!"

func _lose_item(p: PlayerData) -> String:
	if p.inventory.items.is_empty():
		var amount := mini(10, p.inventory.gold)
		p.inventory.gold -= amount
		return "Nothing to steal but coins… -%d gold." % amount
	var entry: Dictionary = p.inventory.items[randi() % p.inventory.items.size()]
	var nm: String = entry.get("name", "Item")
	p.inventory.consume_item(entry)
	return "It makes off with a %s!" % nm

func _damage_lead(p: PlayerData, amount: int) -> String:
	var lead: Dictionary = p.team[0]
	lead["current_hp"] = maxi(0, int(lead.get("current_hp", 0)) - amount)
	var fainted := ""
	if int(lead["current_hp"]) <= 0:
		fainted = " %s fainted!" % lead.get("name", "?")
	return "%s takes %d damage!%s" % [lead.get("name", "?"), amount, fainted]

func _join_spirit(p: PlayerData) -> String:
	var joiner: Dictionary = _spirit.duplicate(true)
	joiner["current_hp"] = joiner.get("hp", 1)
	joiner["stars"] = 0
	if p.team.size() < 6:
		p.team.append(joiner)
		return "%s joins your team!" % joiner.get("name", "?")
	p.pc.append(joiner)
	return "%s joins you — sent to the PC (team full)!" % joiner.get("name", "?")

func _lose_spirit(p: PlayerData) -> String:
	if p.team.size() <= 1:
		return _damage_lead(p, 20)
	var idx := 1 + randi() % (p.team.size() - 1)   # never the lead
	var gone: Dictionary = p.team[idx]
	p.team.remove_at(idx)
	return "%s gets scared and runs away!" % gone.get("name", "?")

# A permanent quirk for the lead (max 2 per spirit — EventsData enforces it).
func _grant_trait(lead: Dictionary, key: String) -> String:
	return EventsData.grant_trait(lead, key)

# ── CPU paths ─────────────────────────────────────────────────────────────────

# Watchable CPU event: the same window opens (a random event, as always),
# pages flip on their own, a random option gets picked after a beat, the
# result lingers, then the window closes itself.
func present_cpu(player_index: int) -> void:
	present(player_index)
	_cpu_run()

func _cpu_run() -> void:
	_lock_buttons()
	await get_tree().create_timer(1.4).timeout
	while visible and _page < _pages.size() - 1:
		_next_page()
		_lock_buttons()
		await get_tree().create_timer(1.4).timeout
	if not visible:
		return
	var options: Array = _event.get("options", [])
	if options.is_empty():
		closed.emit()
		return
	await get_tree().create_timer(0.7).timeout
	if not visible:
		return
	_on_option(options[randi() % options.size()])
	_ok.hide()   # no OK for a CPU — the window closes on its own
	await get_tree().create_timer(2.4).timeout
	if visible:
		closed.emit()

# Humans shouldn't click for the CPU.
func _lock_buttons() -> void:
	for c in _choices_box.get_children():
		if c is Button:
			c.disabled = true

# Silent resolver (kept for all-CPU games): same rules, no window.
func resolve_cpu(player_index: int) -> void:
	_player_index = player_index
	_pending_fight = {}
	_event = _pick_event()
	_setup_event()
	var options: Array = _event.get("options", [])
	var opt: Dictionary = options[randi() % options.size()]
	var lead: Dictionary = GameState.players[player_index].team[0]
	var stat := String(opt.get("stat", ""))
	var success := true
	if stat != "":
		var mine: int = 0 if stat == "luck" else int(lead.get(stat, 0))
		success = mine + randi_range(1, 6) >= int(opt.get("power", 3)) + randi_range(1, 6)
	var outcome: Dictionary = opt.get("win", {}) if success else opt.get("lose", {})
	var msg := _apply_outcome(outcome)
	EventBus.log_entry.emit(player_index, "%s: %s" % [_event.get("title", "Event"), msg],
		"#9fff9f" if success else "#ff9f9f")
