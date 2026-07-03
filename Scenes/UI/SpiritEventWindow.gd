extends MenuWindow
## Mewgenics/Isaac-style EVENT tile:
##   ┌ situation card ─────────┐┌ big portrait (trainer │
##   │ "A shady trainer eyes   ││   or wild spirit)     │
##   │  Bulbasaur's bag!"      │└───────────────────────┘
##   └─────────────────────────┘┌ choice banners        │
##   ┌ your lead + stats ──────┐│ ⚔ Fight it off  🟢    │
##   └─────────────────────────┘│ 💨 Outrun it    🔴    │
## Most events are TRAINER encounters (sprites in Assets/Trainers); some are
## wild spirits. No numbers on the choices — a 🟢 marks the approach your
## lead spirit likes best (its strongest stat for the situation) and a 🔴
## marks the one it wants to avoid.
##
## Outcomes range across: healing a spirit, gaining items/gold, gaining a
## star, evolving, a new spirit joining, next-battle blessings — or losing
## items/gold/a spirit, taking damage, next-battle curses, or being dragged
## into a fight (the board runs the encounter after this window closes; see
## take_pending_fight()).
## present(player_index); emits closed(). resolve_cpu() = same rules, no UI.

signal closed()

const TRAINER_DIR := "res://Assets/Trainer/"

const CHOICES := [
	{"label": "⚔ Fight it off",      "stat": "atk"},
	{"label": "🛡 Stand your ground", "stat": "def"},
	{"label": "💨 Outrun it",         "stat": "spd"},
	{"label": "💚 Befriend it",       "stat": "hp_stat"},
]
# %s = lead spirit name
const TRAINER_SITUATIONS := [
	"A shady trainer eyes %s's bag!",
	"A wandering trainer challenges %s to a contest!",
	"A stranger offers %s a suspicious deal!",
	"A show-off trainer makes fun of %s!",
	"A mysterious trainer blocks %s's path!",
]
# %s = wild spirit name, %s = lead spirit name
const SPIRIT_SITUATIONS := [
	"A wild %s blocks the way forward in front of %s!",
	"A hungry %s is eyeing %s's bag!",
	"A mischievous %s challenges %s with a grin!",
	"A wild %s guards something shiny from %s!",
]

const CARD_BG := Color(0.08, 0.07, 0.16, 0.95)

var _trainer_paths: Array = []   # every portrait in Assets/Trainer, loaded lazily
var _player_index: int = -1
var _spirit: Dictionary          # the wild spirit behind this event
var _is_trainer: bool = false
var _pending_fight: Dictionary = {}
var _situation: Label
var _portrait: TextureRect
var _lead_sprite: TextureRect
var _lead_stats: Label
var _choices_box: VBoxContainer
var _result: Label
var _ok: Button

func _ready() -> void:
	# collect every trainer portrait in the folder (named Showdown-style
	# sprites); textures load lazily when an event actually uses one
	var dir := DirAccess.open(TRAINER_DIR)
	if dir != null:
		for f in dir.get_files():
			if f.ends_with(".png"):
				_trainer_paths.append(TRAINER_DIR + f)
			elif f.ends_with(".png.import"):
				# exported builds list the import stubs instead of the source
				var p := TRAINER_DIR + f.trim_suffix(".import")
				if not _trainer_paths.has(p):
					_trainer_paths.append(p)
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
	_situation.add_theme_font_size_override("font_size", 22)
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
	_result.add_theme_font_size_override("font_size", 20)
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

func present(player_index: int) -> void:
	_player_index = player_index
	_pending_fight = {}
	var p: PlayerData = GameState.players[player_index]
	var lead: Dictionary = p.team[0]
	_spirit = SpiritsData.random_spirit(1 if randi() % 3 != 0 else 2)
	# Mostly trainers; wild spirits some of the time (and always when no
	# trainer art has been imported yet).
	var trainer_tex: Texture2D = null
	if not _trainer_paths.is_empty() and randf() < 0.7:
		var path: String = _trainer_paths[randi() % _trainer_paths.size()]
		if ResourceLoader.exists(path):
			trainer_tex = load(path)
	_is_trainer = trainer_tex != null
	if _is_trainer:
		_portrait.texture = trainer_tex
		_situation.text = TRAINER_SITUATIONS[randi() % TRAINER_SITUATIONS.size()] % lead.get("name", "?")
	else:
		_portrait.texture = SpiritsData.sprite_tex(_spirit.get("name", ""), "front")
		_situation.text = SPIRIT_SITUATIONS[randi() % SPIRIT_SITUATIONS.size()] % [
			_spirit.get("name", "?"), lead.get("name", "?")]
	_lead_sprite.texture = SpiritsData.sprite_tex(lead.get("name", ""), "back")
	_lead_stats.text = "%s\nHP %d/%d\nATK %d   DEF %d\nSPD %d   🪙 %d" % [
		lead.get("name", "?"), lead.get("current_hp", 0), lead.get("hp", 0),
		lead.get("atk", 0), lead.get("def", 0), lead.get("spd", 0), p.inventory.gold]
	_result.text = ""
	_ok.hide()
	_build_choices(lead)

# Offer 3 random approaches with NO numbers: a 🟢 on the one the lead likes
# best (best stat vs hidden difficulty) and a 🔴 on the one it wants to avoid.
func _build_choices(lead: Dictionary) -> void:
	for c in _choices_box.get_children():
		c.queue_free()
	var pool := CHOICES.duplicate()
	pool.shuffle()
	var offers: Array = []
	for i in 3:
		var choice: Dictionary = pool[i]
		var difficulty: int = randi_range(2, 5)
		var score: int = int(lead.get(choice["stat"], 1)) - difficulty
		offers.append({"choice": choice, "difficulty": difficulty, "score": score})
	var best := 0
	var worst := 0
	for i in offers.size():
		if offers[i]["score"] > offers[best]["score"]:
			best = i
		if offers[i]["score"] < offers[worst]["score"]:
			worst = i
	for i in offers.size():
		var mark := ""
		if i == best and offers[best]["score"] != offers[worst]["score"]:
			mark = "  🟢"
		elif i == worst and offers[best]["score"] != offers[worst]["score"]:
			mark = "  🔴"
		var o: Dictionary = offers[i]
		var b := _button("%s%s" % [o["choice"]["label"], mark], _on_choice.bind(o["choice"], o["difficulty"]), 44)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_choices_box.add_child(b)

func _on_choice(choice: Dictionary, difficulty: int) -> void:
	for c in _choices_box.get_children():
		c.queue_free()
	var lead: Dictionary = GameState.players[_player_index].team[0]
	var stat: int = int(lead.get(choice["stat"], 1))
	if _roll(stat, difficulty):
		var msg := _apply_reward()
		_result.text = "Success!  " + msg
		_result.add_theme_color_override("font_color", Color("9fff9f"))
		EventBus.log_entry.emit(_player_index, "event: " + msg, "#9fff9f")
	else:
		var msg := _apply_mishap()
		_result.text = "Oh no!  " + msg
		_result.add_theme_color_override("font_color", Color("ff9f9f"))
		EventBus.log_entry.emit(_player_index, "event: " + msg, "#ff9f9f")
	_ok.show()

# Higher stat vs difficulty = better odds (10%–90%).
func _roll(stat: int, difficulty: int) -> bool:
	var chance := clampf(0.5 + 0.15 * float(stat - difficulty), 0.1, 0.9)
	return randf() < chance

# ── outcomes ──────────────────────────────────────────────────────────────────

func _apply_reward() -> String:
	var p: PlayerData = GameState.players[_player_index]
	var lead: Dictionary = p.team[0]
	match ["heal_one", "items", "gold", "star", "evolve", "join", "bless"][randi() % 7]:
		"heal_one":
			var target := _most_hurt(p)
			if target.is_empty():
				return _gain_gold(p)
			target["current_hp"] = target.get("hp", 0)
			return "%s is fully healed!" % target.get("name", "?")
		"items":
			# 30% chance the prize is a held battle item instead of a heal
			var item: Dictionary
			if randf() < 0.3:
				item = GameData.held_item_entry(GameData.random_held_key())
			else:
				item = [
					{"name": "Potion", "kind": "potion", "amount": 40},
					{"name": "Super Potion", "kind": "potion", "amount": 80},
					{"name": "Revive", "kind": "revive"},
				][randi() % 3]
			if p.inventory.add_item(item):
				return "You receive a %s!" % item["name"]
			p.inventory.balls[&"spirit_ball"] = p.inventory.ball_count(&"spirit_ball") + 1
			return "Your bag is full — you get a Spirit Ball instead!"
		"gold":
			return _gain_gold(p)
		"star":
			SpiritsProgressionSystem._award_star(_player_index, lead)
			return "%s gains a star! ★" % lead.get("name", "?")
		"evolve":
			if String(lead.get("evolution", "")) != "":
				SpiritsProgressionSystem._trigger_evolution(_player_index, lead)
				return "%s is evolving!" % lead.get("name", "?")
			SpiritsProgressionSystem._award_star(_player_index, lead)
			return "%s gains a star! ★" % lead.get("name", "?")
		"join":
			var joiner: Dictionary = _spirit.duplicate(true)
			joiner["current_hp"] = joiner.get("hp", 1)
			joiner["stars"] = 0
			if p.team.size() < 6:
				p.team.append(joiner)
				return "%s joins your team!" % joiner.get("name", "?")
			p.pc.append(joiner)
			return "%s joins you — sent to the PC (team full)!" % joiner.get("name", "?")
		"bless":
			p.next_battle_mod = 1
			return "Blessed! Your team gets ATK +1 in its next battle."
	return ""

func _apply_mishap() -> String:
	var p: PlayerData = GameState.players[_player_index]
	var lead: Dictionary = p.team[0]
	match ["curse", "lose_item", "lose_gold", "lose_spirit", "fight", "damage"][randi() % 6]:
		"curse":
			p.next_battle_mod = -1
			return "Spooked! Your team gets ATK -1 in its next battle."
		"lose_item":
			if p.inventory.items.is_empty():
				return _lose_gold(p)
			var entry: Dictionary = p.inventory.items[randi() % p.inventory.items.size()]
			var nm: String = entry.get("name", "Item")
			p.inventory.consume_item(entry)
			return "It makes off with a %s!" % nm
		"lose_gold":
			return _lose_gold(p)
		"lose_spirit":
			if p.team.size() <= 1:
				return _damage_lead(p)
			var idx := 1 + randi() % (p.team.size() - 1)   # never the lead
			var gone: Dictionary = p.team[idx]
			p.team.remove_at(idx)
			return "%s gets scared and runs away!" % gone.get("name", "?")
		"fight":
			_pending_fight = _spirit
			if _is_trainer:
				return "The trainer sends out a wild %s — battle stations!" % _spirit.get("name", "?")
			return "%s attacks — battle stations!" % _spirit.get("name", "?")
		"damage":
			return _damage_lead(p)
	return ""

func _gain_gold(p: PlayerData) -> String:
	var amount := randi_range(20, 40)
	p.inventory.gold += amount
	return "You find a pouch of gold! +%d gold" % amount

func _lose_gold(p: PlayerData) -> String:
	var amount := mini(randi_range(10, 25), p.inventory.gold)
	p.inventory.gold -= amount
	return "It swipes your coin pouch! -%d gold" % amount

func _damage_lead(p: PlayerData) -> String:
	var lead: Dictionary = p.team[0]
	var amount := randi_range(15, 30)
	lead["current_hp"] = maxi(0, int(lead.get("current_hp", 0)) - amount)
	var fainted: String = ""
	if int(lead["current_hp"]) <= 0:
		fainted = " %s fainted!" % lead.get("name", "?")
	return "%s takes %d damage!%s" % [lead.get("name", "?"), amount, fainted]

# Most-hurt living team member (for heal_one); {} if everyone is at full HP.
func _most_hurt(p: PlayerData) -> Dictionary:
	var target: Dictionary = {}
	var worst_ratio := 1.0
	for m in p.team:
		var ratio := float(m.get("current_hp", 0)) / float(maxi(1, m.get("hp", 1)))
		if ratio < worst_ratio:
			worst_ratio = ratio
			target = m
	return target

# CPU path: same rules, no window.
func resolve_cpu(player_index: int) -> void:
	_player_index = player_index
	_pending_fight = {}
	_spirit = SpiritsData.random_spirit(1)
	_is_trainer = false
	var choice: Dictionary = CHOICES[randi() % CHOICES.size()]
	var difficulty: int = randi_range(2, 5)
	var lead: Dictionary = GameState.players[player_index].team[0]
	var stat: int = int(lead.get(choice["stat"], 1))
	if _roll(stat, difficulty):
		EventBus.log_entry.emit(player_index, "event: " + _apply_reward(), "#9fff9f")
	else:
		EventBus.log_entry.emit(player_index, "event: " + _apply_mishap(), "#ff9f9f")
