class_name CardsData
## Every card in the game. Players hold up to Balance.HAND_SIZE in their hand.
##
## kind:
##   capture — Lanterns: spent when you roll to catch a wild ghost (more dice)
##   field  — played on the board during your turn (heals, dice, lures…)
##   tactic — played in battle, one per round (shields, haste, fury…)
##   charm  — attached to a spirit; it stays on that spirit (battle effects
##            live in BattleRules) until it's taken back into the hand
## target: "spirit" (a living team spirit) | "fainted" | "player" | "city" | ""
## weight: how often ITEM tiles / events draw it.  value: CPU trade/discard worth.

const CARDS := {
	# ── capture ──────────────────────────────────────────────────────────────
	"spirit_lantern":{"name": "Spirit Lantern", "kind": "capture", "icon": "🏮", "cost": 10, "weight": 14, "value": 2, "dice": 1,
		"desc": "Catching: roll +1 die"},
	"grand_lantern": {"name": "Grand Lantern",  "kind": "capture", "icon": "🏮", "cost": 25, "weight": 5, "value": 4, "dice": 2,
		"desc": "Catching: roll +2 dice"},
	"soul_lantern":  {"name": "Soul Lantern",   "kind": "capture", "icon": "✨", "cost": 0,  "weight": 1, "value": 9, "dice": 0,
		"desc": "Catching: a sure catch, no roll"},
	# ── field ────────────────────────────────────────────────────────────────
	"glow_tonic":    {"name": "Glow Tonic",     "kind": "field", "icon": "🧪", "cost": 15, "weight": 10, "value": 3, "target": "spirit",
		"desc": "Heal one spirit 50 HP"},
	"mega_tonic":    {"name": "Mega Tonic",     "kind": "field", "icon": "⚗", "cost": 30, "weight": 5, "value": 5, "target": "spirit",
		"desc": "Heal one spirit 100 HP"},
	"wake_bell":     {"name": "Wake Bell",      "kind": "field", "icon": "🔔", "cost": 35, "weight": 5, "value": 5, "target": "fainted",
		"desc": "Wake a fainted spirit at half HP"},
	"group_hug":     {"name": "Group Hug",      "kind": "field", "icon": "🤗", "cost": 30, "weight": 4, "value": 5, "target": "",
		"desc": "Heal your whole team 40 HP"},
	"loaded_die":    {"name": "Loaded Die",     "kind": "field", "icon": "🎲", "cost": 15, "weight": 6, "value": 3, "target": "",
		"desc": "Your next roll gets +2"},
	"twin_dice":     {"name": "Twin Dice",      "kind": "field", "icon": "🎲", "cost": 20, "weight": 4, "value": 4, "target": "",
		"desc": "Roll an extra die this turn"},
	"spooky_lure":   {"name": "Spooky Lure",    "kind": "field", "icon": "🍬", "cost": 20, "weight": 5, "value": 4, "target": "",
		"desc": "Next wild spirit is one stage stronger and +10 to catch"},
	"salt_circle":   {"name": "Salt Circle",    "kind": "field", "icon": "🧂", "cost": 10, "weight": 4, "value": 2, "target": "",
		"desc": "Ignore the next wild spirit or event you land on"},
	"star_candy":    {"name": "Star Candy",     "kind": "field", "icon": "⭐", "cost": 45, "weight": 2, "value": 7, "target": "spirit",
		"desc": "Give one spirit a star"},
	"warp_door":     {"name": "Warp Door",      "kind": "field", "icon": "🚪", "cost": 30, "weight": 3, "value": 5, "target": "city",
		"desc": "Instead of rolling, step through to any town you've visited"},
	"sticky_fingers":{"name": "Sticky Fingers", "kind": "field", "icon": "🧤", "cost": 25, "weight": 3, "value": 4, "target": "player",
		"desc": "Steal a random card from another player"},
	"lucky_coin":    {"name": "Lucky Coin",     "kind": "field", "icon": "🪙", "cost": 0,  "weight": 5, "value": 3, "target": "",
		"desc": "Cash it in for 25 gold"},
	# ── tactic ───────────────────────────────────────────────────────────────
	"spirit_shield": {"name": "Spirit Shield",  "kind": "tactic", "icon": "🛡", "cost": 20, "weight": 6, "value": 4,
		"desc": "Your lead takes half damage this round"},
	"battle_cry":    {"name": "Battle Cry",     "kind": "tactic", "icon": "📣", "cost": 20, "weight": 6, "value": 4,
		"desc": "Your lead gets +3 ATK this round"},
	"haste":         {"name": "Haste",          "kind": "tactic", "icon": "💨", "cost": 15, "weight": 5, "value": 3,
		"desc": "Your lead strikes first this round"},
	"switcheroo":    {"name": "Switcheroo",     "kind": "tactic", "icon": "🔄", "cost": 15, "weight": 4, "value": 3,
		"desc": "Swap your lead with your healthiest ally"},
	"ecto_patch":    {"name": "Ecto Patch",     "kind": "tactic", "icon": "🩹", "cost": 20, "weight": 6, "value": 4,
		"desc": "Heal your lead 60 HP"},
	"purify":        {"name": "Purify",         "kind": "tactic", "icon": "✨", "cost": 15, "weight": 4, "value": 3,
		"desc": "Cure your lead's status; immune this round"},
	"boo":           {"name": "BOO!",           "kind": "tactic", "icon": "👻", "cost": 25, "weight": 4, "value": 5,
		"desc": "Scare the enemy lead — it skips this round"},
	"fury":          {"name": "Fury",           "kind": "tactic", "icon": "💢", "cost": 30, "weight": 3, "value": 6,
		"desc": "Your lead attacks twice this round"},
	"soul_siphon":   {"name": "Soul Siphon",    "kind": "tactic", "icon": "🌀", "cost": 25, "weight": 4, "value": 5,
		"desc": "Drain 40 HP from the enemy lead into yours"},
	"hold_on":       {"name": "Hold On!",       "kind": "tactic", "icon": "✊", "cost": 20, "weight": 4, "value": 4,
		"desc": "Your lead can't faint this round"},
	"rally":         {"name": "Rally",          "kind": "tactic", "icon": "🚩", "cost": 30, "weight": 3, "value": 6,
		"desc": "Whole team +1 ATK and +1 DEF for the battle"},
	"mirror_veil":   {"name": "Mirror Veil",    "kind": "tactic", "icon": "🪞", "cost": 25, "weight": 3, "value": 5,
		"desc": "Bounce half the damage your lead takes this round"},
	# ── charms (old held items) ──────────────────────────────────────────────
	"power_band":    {"name": "Power Band",     "kind": "charm", "icon": "💪", "cost": 20, "weight": 2, "value": 4,
		"desc": "+20% damage on all attacks", "target": "spirit"},
	"ghost_cloak":   {"name": "Ghost Cloak",    "kind": "charm", "icon": "🧥", "cost": 22, "weight": 2, "value": 4,
		"desc": "Take 15% less damage", "target": "spirit"},
	"brave_ribbon":  {"name": "Brave Ribbon",   "kind": "charm", "icon": "🎀", "cost": 25, "weight": 2, "value": 4,
		"desc": "+1 ATK when entering battle", "target": "spirit"},
	"guard_pin":     {"name": "Guard Pin",      "kind": "charm", "icon": "📌", "cost": 22, "weight": 2, "value": 4,
		"desc": "+1 DEF when entering battle", "target": "spirit"},
	"moon_berry":    {"name": "Moon Berry",     "kind": "charm", "icon": "🫐", "cost": 10, "weight": 2, "value": 3,
		"desc": "Below 50% HP: heal 30% (once per battle)", "target": "spirit"},
	"lucky_scarf":   {"name": "Lucky Scarf",    "kind": "charm", "icon": "🧣", "cost": 20, "weight": 2, "value": 4,
		"desc": "Survive a KO at 1 HP (once per battle)", "target": "spirit"},
	"echo_bell":     {"name": "Echo Bell",      "kind": "charm", "icon": "🔔", "cost": 20, "weight": 2, "value": 4,
		"desc": "Heal 10% of the damage you deal", "target": "spirit"},
	"spiky_helm":    {"name": "Spiky Helm",     "kind": "charm", "icon": "⛑", "cost": 18, "weight": 2, "value": 3,
		"desc": "Attackers take 15 recoil damage", "target": "spirit"},
	"phoenix_feather":{"name": "Phoenix Feather","kind": "charm", "icon": "🪶", "cost": 25, "weight": 2, "value": 5,
		"desc": "On KO: revive at 25% HP (once per battle)", "target": "spirit"},
	"war_drum":      {"name": "War Drum",       "kind": "charm", "icon": "🥁", "cost": 20, "weight": 2, "value": 4,
		"desc": "Free hit at 40% ATK when entering battle", "target": "spirit"},
	"last_trophy":   {"name": "Last Trophy",    "kind": "charm", "icon": "🏆", "cost": 28, "weight": 2, "value": 4,
		"desc": "Last spirit standing: +1 ATK but +20% damage taken", "target": "spirit"},
}

const KIND_COLORS := {
	"capture": Color("2b8c9a"),
	"field":  Color("3d8b5a"),
	"tactic": Color("b0473f"),
	"charm":  Color("6a4fc4"),
}

static func card(key: String) -> Dictionary:
	return CARDS.get(key, {"name": key, "kind": "field", "icon": "?", "desc": "", "cost": 0, "weight": 0, "value": 0})

static func card_name(key: String) -> String:
	var c := card(key)
	return "%s %s" % [c.get("icon", ""), c.get("name", key)]

static func kind_of(key: String) -> String:
	return String(card(key).get("kind", ""))

static func value_of(key: String) -> int:
	return int(card(key).get("value", 0))

static func keys_of_kind(kind: String) -> Array:
	return CARDS.keys().filter(func(k): return CARDS[k]["kind"] == kind)

# A weighted random card, optionally of one kind ("" = any).
static func random_card(kind: String = "") -> String:
	var pool: Array = CARDS.keys() if kind == "" else keys_of_kind(kind)
	var total := 0
	for k in pool:
		total += int(CARDS[k]["weight"])
	var roll := randi_range(1, maxi(1, total))
	for k in pool:
		roll -= int(CARDS[k]["weight"])
		if roll <= 0:
			return k
	return pool.back()

# Cards for the shop's rotating rack (Lanterns have their own shelf; free
# cash-in cards aren't for sale).
static func shop_pool() -> Array:
	return CARDS.keys().filter(func(k): return int(CARDS[k]["cost"]) > 0 and CARDS[k]["kind"] != "capture")

# A short battle deck for gym leaders / the Haunted Four / the Champion.
static func npc_deck(count: int) -> Array:
	var deck: Array = []
	for i in count:
		deck.append(random_card("tactic"))
	return deck
