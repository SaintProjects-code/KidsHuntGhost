class_name GameData
## Static game content: the 8 city gyms, the Elite Four, Gary the champion, the
## event-card deck, and the item pool. Pulls spirits from SpiritsData.
## Used as GameData.<thing> — no autoload needed.

# ─── Gyms: one per city (A..H), each grants a badge ───────────────────────────
# badge keys match PlayerData.Progress.badges.
const GYMS := {
	"A": {"name": "Ashen Gym",   "type": "Fire",     "badge": "boulder", "team": ["Charmander", "Vulpix", "Growlithe"]},
	"B": {"name": "Bayou Gym",   "type": "Water",    "badge": "fog",     "team": ["Squirtle", "Psyduck", "Poliwag"]},
	"C": {"name": "Cobweb Gym",  "type": "Grass",    "badge": "marsh",   "team": ["Bulbasaur", "Oddish", "Bellsprout"]},
	"D": {"name": "Dusk Gym",    "type": "Electric", "badge": "rain",    "team": ["Pikachu", "Magnemite", "Voltorb"]},
	"E": {"name": "Echo Gym",    "type": "Psychic",  "badge": "soul",    "team": ["Abra", "Drowzee", "Clefairy"]},
	"F": {"name": "Foggy Gym",   "type": "Fighting", "badge": "earth",   "team": ["Machop", "Mankey", "Geodude"]},
	"G": {"name": "Ghoul Gym",   "type": "Dark",     "badge": "volt",    "team": ["Gastly", "Zubat", "Meowth"]},
	"H": {"name": "Harbor Gym",  "type": "Water",    "badge": "glacier", "team": ["Wartortle", "Seel", "Shellder"]},
}

# ─── Elite Four: four sequential battles ──────────────────────────────────────
const ELITE_FOUR := [
	{"name": "Elite Will",  "team": ["Kadabra", "Hypno", "Wigglytuff"]},
	{"name": "Elite Koga",  "team": ["Muk", "Weezing", "Golbat"]},
	{"name": "Elite Bruno", "team": ["Machoke", "Graveler", "Marowak"]},
	{"name": "Elite Karen", "team": ["Haunter", "Persian", "Arbok"]},
]

# ─── Gary, the Champion ───────────────────────────────────────────────────────
const GARY := {
	"name": "Gary",
	"team": ["Pidgeot", "Alakazam", "Rhydon", "Gyarados", "Arcanine", "Blastoise"],
}

# ─── Event cards: a deck of simple effects resolved by TileController ──────────
# kind: "points" | "gold" | "ball" | "heal" | "skip" | "ambush"
const EVENT_CARDS := [
	{"title": "Lucky Find!",     "desc": "You found a stash. +2 points!",            "kind": "points", "amount": 2},
	{"title": "Hidden Coins",    "desc": "Coins glitter in the grass. +15 gold.",     "kind": "gold",   "amount": 15},
	{"title": "Free Ball",       "desc": "A kind trainer hands you a Spirit Ball.",    "kind": "ball",   "amount": 1},
	{"title": "Healing Spring",  "desc": "Your whole team is fully restored!",         "kind": "heal"},
	{"title": "Lost in Fog",     "desc": "You wander off — nothing happens.",          "kind": "skip"},
	{"title": "Berry Snack",     "desc": "Your team nibbles berries and recovers!",     "kind": "heal"},
	{"title": "Festival Bonus",  "desc": "The town celebrates with you. +1 point.",    "kind": "points", "amount": 1},
	{"title": "Treasure Chest",  "desc": "A chest of gold! +25 gold.",                 "kind": "gold",   "amount": 25},
]

# ─── Trainer portraits (Assets/Trainer, Showdown-style names) ─────────────────
# Resolution walks a candidate list so missing files fall back gracefully
# (e.g. "red" → "acetrainer-gen1" → first file in the folder).
const TRAINER_DIR := "res://Assets/Trainer/"
const PLAYER_TRAINERS := {"Red": "red", "Blue": "blue", "Leaf": "leaf", "Ash": "ash"}
const GYM_TRAINERS := {
	"Fire": "blaine", "Water": "misty", "Grass": "erika", "Electric": "ltsurge",
	"Psychic": "sabrina", "Fighting": "chuck", "Dark": "karen",
}

static func trainer_texture(candidates: Array) -> Texture2D:
	for k in candidates:
		if String(k) == "":
			continue
		var path := TRAINER_DIR + String(k) + ".png"
		if ResourceLoader.exists(path):
			return load(path)
	return null

static func player_trainer(player_name: String) -> Array:
	return [PLAYER_TRAINERS.get(player_name, ""), "acetrainer-gen1", "acetrainer"]

static func gym_trainer(type: String) -> Array:
	return [GYM_TRAINERS.get(type, ""), "acetrainer", "acetrainer-gen1"]

# ─── Held battle items (equip one per spirit; the bag's "Use" equips it) ──────
# Effects run inside BattleScreen on the battle copies.
const HELD_ITEMS := {
	&"expert_belt":     {"name": "Expert Belt",     "cost": 20, "desc": "+20% damage on all attacks"},
	&"assault_vest":    {"name": "Assault Vest",    "cost": 22, "desc": "Take 15% less damage"},
	&"choice_band":     {"name": "Choice Band",     "cost": 25, "desc": "+1 ATK when entering battle"},
	&"vanguard_shield": {"name": "Vanguard Shield", "cost": 22, "desc": "+1 DEF when entering battle"},
	&"sitrus_berry":    {"name": "Sitrus Berry",    "cost": 10, "desc": "Below 50% HP: heal 30% (once per battle)"},
	&"focus_sash":      {"name": "Focus Sash",      "cost": 20, "desc": "Survive a KO at 1 HP (once per battle)"},
	&"shell_bell":      {"name": "Shell Bell",      "cost": 20, "desc": "Heal 10% of the damage you deal"},
	&"rocky_helmet":    {"name": "Rocky Helmet",    "cost": 18, "desc": "Attackers take 15 recoil damage"},
	&"phoenix_ash":     {"name": "Phoenix Ash",     "cost": 25, "desc": "On KO: revive at 25% HP (once per battle)"},
	&"battle_drum":     {"name": "Battle Drum",     "cost": 20, "desc": "Free hit at 40% ATK when entering battle"},
	&"trophy":          {"name": "Trophy",          "cost": 28, "desc": "Last spirit standing: +1 ATK but +20% damage taken"},
}

static func held_item_entry(key: StringName) -> Dictionary:
	var d: Dictionary = HELD_ITEMS.get(key, {})
	return {"name": d.get("name", "Item"), "kind": "held", "key": key}

static func random_held_key() -> StringName:
	return HELD_ITEMS.keys()[randi() % HELD_ITEMS.size()]

# ─── Item pool for ITEM tiles ─────────────────────────────────────────────────
# kind: "ball" | "potion" | "revive" | "gold" | "held"
const ITEM_POOL := [
	{"name": "Spirit Ball", "kind": "ball",   "amount": 1},
	{"name": "Spirit Ball", "kind": "ball",   "amount": 2},
	{"name": "Potion",      "kind": "potion", "amount": 40},
	{"name": "Super Potion","kind": "potion", "amount": 80},
	{"name": "Revive",      "kind": "revive"},
	{"name": "Gold Pouch",  "kind": "gold",   "amount": 20},
	{"name": "?",           "kind": "held"},   # a random held battle item
]

# Build a battle-ready team (array of spirit dicts) from a list of names. Each
# member can get bonus stars (gyms/E4/Gary get tougher deeper in).
static func build_team(names: Array, stars: int = 0) -> Array:
	var team: Array = []
	for n in names:
		var s: Dictionary = SpiritsData.get_spirit(n)
		if s.is_empty():
			continue
		s["stars"] = stars
		team.append(s)
	return team

static func gym_for_city(city: String) -> Dictionary:
	return GYMS.get(city, {})

static func random_event() -> Dictionary:
	return EVENT_CARDS[randi() % EVENT_CARDS.size()]

static func random_item() -> Dictionary:
	# duplicate: const pool entries are read-only, and receivers annotate the
	# item (e.g. resolving the random "held" reward)
	return ITEM_POOL[randi() % ITEM_POOL.size()].duplicate(true)
