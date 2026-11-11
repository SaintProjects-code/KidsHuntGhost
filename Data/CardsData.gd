class_name CardsData
## Every card in the game. Players hold up to Balance.HAND_SIZE in their hand.
##
## kind:
##   capture — Lanterns: spent when you roll to catch a wild ghost (more dice)
##   field  — played on the board during your turn (heals, dice, lures…)
##   tactic — played in battle, one per round (shields, haste, fury…). Tactics
##            marked "charm" are ONE-USE charms: played in battle, the charm
##            goes on your lead for the rest of that battle (effects live in
##            BattleRules), then the card is gone
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
		"desc": "Your lead takes only 40% damage this round"},
	"battle_cry":    {"name": "Battle Cry",     "kind": "tactic", "icon": "📣", "cost": 20, "weight": 6, "value": 4,
		"desc": "Your lead gets +4 ATK this round"},
	"haste":         {"name": "Haste",          "kind": "tactic", "icon": "💨", "cost": 15, "weight": 5, "value": 3,
		"desc": "Your lead strikes first this round; team SPD +1 for the battle"},
	"switcheroo":    {"name": "Switcheroo",     "kind": "tactic", "icon": "🔄", "cost": 15, "weight": 4, "value": 3,
		"desc": "Swap your lead with your healthiest ally, who heals 25%"},
	"ecto_patch":    {"name": "Ecto Patch",     "kind": "tactic", "icon": "🩹", "cost": 20, "weight": 6, "value": 4,
		"desc": "Heal your lead 75 HP"},
	"purify":        {"name": "Purify",         "kind": "tactic", "icon": "✨", "cost": 15, "weight": 4, "value": 3,
		"desc": "Cure your lead's status; immune this round and next"},
	"boo":           {"name": "BOO!",           "kind": "tactic", "icon": "👻", "cost": 25, "weight": 4, "value": 5,
		"desc": "Scare the enemy lead — it skips this round and loses 1 SPD"},
	"fury":          {"name": "Fury",           "kind": "tactic", "icon": "💢", "cost": 30, "weight": 3, "value": 6,
		"desc": "Your lead attacks twice this round with +1 ATK"},
	"soul_siphon":   {"name": "Soul Siphon",    "kind": "tactic", "icon": "🌀", "cost": 25, "weight": 4, "value": 5,
		"desc": "Drain 50 HP from the enemy lead into yours"},
	"hold_on":       {"name": "Hold On!",       "kind": "tactic", "icon": "✊", "cost": 20, "weight": 4, "value": 4,
		"desc": "Your lead can't faint this round and heals 10%"},
	"rally":         {"name": "Rally",          "kind": "tactic", "icon": "🚩", "cost": 30, "weight": 3, "value": 6,
		"desc": "Whole team +1 ATK and +1 DEF for the battle, and heals 10 HP"},
	"mirror_veil":   {"name": "Mirror Veil",    "kind": "tactic", "icon": "🪞", "cost": 25, "weight": 3, "value": 5,
		"desc": "Bounce 60% of the damage your lead takes this round"},
	# ── charms: tactic cards whose effect lasts the rest of the battle ────────
	"power_band":    {"name": "Power Band",     "kind": "tactic", "charm": true, "icon": "💪", "cost": 20, "weight": 2, "value": 4,
		"desc": "This battle: lead deals +25% damage"},
	"ghost_cloak":   {"name": "Ghost Cloak",    "kind": "tactic", "charm": true, "icon": "🧥", "cost": 22, "weight": 2, "value": 4,
		"desc": "This battle: lead takes 20% less damage"},
	"brave_ribbon":  {"name": "Brave Ribbon",   "kind": "tactic", "charm": true, "icon": "🎀", "cost": 25, "weight": 2, "value": 4,
		"desc": "This battle: lead +2 ATK, then +1 more each time it re-enters"},
	"guard_pin":     {"name": "Guard Pin",      "kind": "tactic", "charm": true, "icon": "📌", "cost": 22, "weight": 2, "value": 4,
		"desc": "This battle: lead +2 DEF, then +1 more each time it re-enters"},
	"moon_berry":    {"name": "Moon Berry",     "kind": "tactic", "charm": true, "icon": "🫐", "cost": 10, "weight": 2, "value": 3,
		"desc": "This battle: lead heals 50% once when below 50% HP"},
	"lucky_scarf":   {"name": "Lucky Scarf",    "kind": "tactic", "charm": true, "icon": "🧣", "cost": 20, "weight": 2, "value": 4,
		"desc": "This battle: lead survives one KO with 15% HP"},
	"echo_bell":     {"name": "Echo Bell",      "kind": "tactic", "charm": true, "icon": "🔔", "cost": 20, "weight": 2, "value": 4,
		"desc": "This battle: lead heals 15% of the damage it deals"},
	"spiky_helm":    {"name": "Spiky Helm",     "kind": "tactic", "charm": true, "icon": "⛑", "cost": 18, "weight": 2, "value": 3,
		"desc": "This battle: lead's attackers take 20 recoil"},
	"phoenix_feather":{"name": "Phoenix Feather","kind": "tactic", "charm": true, "icon": "🪶", "cost": 25, "weight": 2, "value": 5,
		"desc": "This battle: lead revives once at 35% HP"},
	"war_drum":      {"name": "War Drum",       "kind": "tactic", "charm": true, "icon": "🥁", "cost": 20, "weight": 2, "value": 4,
		"desc": "Free hit at 70% ATK now (and on re-entry)"},
	"last_trophy":   {"name": "Last Trophy",    "kind": "tactic", "charm": true, "icon": "🏆", "cost": 28, "weight": 2, "value": 4,
		"desc": "This battle: last spirit standing gets +2 ATK and +2 DEF"},
}

const KIND_COLORS := {
	"capture": Color("2b8c9a"),
	"field":  Color("3d8b5a"),
	"tactic": Color("b0473f"),
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

static func is_charm(key: String) -> bool:
	return bool(card(key).get("charm", false))

# "charm" picks the charm tactics (events still hand out charms as prizes).
static func keys_of_kind(kind: String) -> Array:
	if kind == "charm":
		return CARDS.keys().filter(func(k): return CARDS[k].get("charm", false))
	return CARDS.keys().filter(func(k): return CARDS[k]["kind"] == kind)

# Field cards a phone player may play while it's someone else's turn: ones
# that don't need the board, a roll or a popup.
const OFF_TURN := ["glow_tonic", "mega_tonic", "wake_bell", "group_hug", "loaded_die", "spooky_lure", "salt_circle", "lucky_coin"]

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
