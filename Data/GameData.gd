class_name GameData
## Static game content: the 8 city gyms, the Elite Four, Gary the champion, the
## event-card deck, and the item pool. Pulls spirits from SpiritsData.
## Used as GameData.<thing> — no autoload needed.

# ─── Gyms: one per city (A..H), each grants a badge ───────────────────────────
# badge keys match PlayerData.Progress.badges. Each gym is a MONO-TYPE team
# built around synergy: a bond ability (bigger the more same-type allies), a
# team buff or disruptor, and support. Entries can be a plain name (random
# ability) or {name, ability, ability2?, stars?}. Badge tier adds stars.
# At the badge cap (tier 3) every team fields 3-STAR spirits with TWO abilities:
# gyms have 2–3 of them (marked with stars:1 + a second ability, so they hit
# ★3 exactly at 3 badges), the Elite Four have 3 each (an ★3 ace + two more).
const GYMS := {
	"A": {"name": "Ashen Gym",   "type": "Fire",     "badge": "boulder", "team": [
		{"name": "Ponyta",   "ability": "drought",   "ability2": "blaze",      "stars": 1},  # threat
		{"name": "Magmar",   "ability": "fire_bond", "ability2": "flame_body", "stars": 1},  # threat
		{"name": "Growlithe","ability": "sniper"},
		{"name": "Vulpix",   "ability": "moxie"}]},
	"B": {"name": "Bayou Gym",   "type": "Water",    "badge": "fog",     "team": [
		{"name": "Seel",     "ability": "water_bond", "ability2": "reflect",   "stars": 1},  # threat
		{"name": "Shellder", "ability": "multiscale", "ability2": "bulwark",   "stars": 1},  # threat
		{"name": "Krabby",   "ability": "sturdy"},
		{"name": "Psyduck",  "ability": "wish"}]},
	"C": {"name": "Cobweb Gym",  "type": "Grass",    "badge": "marsh",   "team": [
		{"name": "Bellsprout","ability": "grass_bond", "ability2": "leech_seed","stars": 1},  # threat
		{"name": "Oddish",   "ability": "spore",      "ability2": "poison_point","stars": 1}, # threat
		{"name": "Exeggcute","ability": "healer",     "ability2": "wish",       "stars": 1},  # threat
		{"name": "Chikorita","ability": "overgrow"}]},
	"D": {"name": "Dusk Gym",    "type": "Electric", "badge": "rain",    "team": [
		{"name": "Pikachu",  "ability": "electric_bond","ability2": "static",   "stars": 1},  # threat
		{"name": "Electabuzz","ability": "speed_boost", "ability2": "berserker","stars": 1},  # threat
		{"name": "Magnemite","ability": "thunder_wave"},
		{"name": "Voltorb",  "ability": "explosion"}]},
	"E": {"name": "Echo Gym",    "type": "Psychic",  "badge": "soul",    "team": [
		{"name": "Drowzee",  "ability": "hypnosis",    "ability2": "confuse_ray","stars": 1},  # threat
		{"name": "Clefairy", "ability": "psychic_bond","ability2": "reflect",    "stars": 1},  # threat
		{"name": "Jigglypuff","ability": "wish",       "ability2": "helping_hand","stars": 1},  # threat
		{"name": "Slowpoke", "ability": "encore"}]},
	"F": {"name": "Foggy Gym",   "type": "Fighting", "badge": "earth",   "team": [
		{"name": "Machop",   "ability": "intimidate",   "ability2": "counter",  "stars": 1},  # threat
		{"name": "Geodude",  "ability": "fighting_bond","ability2": "fortress",  "stars": 1},  # threat
		{"name": "Rhyhorn",  "ability": "battle_armor"},
		{"name": "Hitmonlee","ability": "grit"}]},
	"G": {"name": "Ghoul Gym",   "type": "Dark",     "badge": "volt",    "team": [
		{"name": "Grimer",   "ability": "dark_bond", "ability2": "vengeance",   "stars": 1},  # threat
		{"name": "Gastly",   "ability": "taunt",     "ability2": "thief",       "stars": 1},  # threat
		{"name": "Zubat",    "ability": "poison_point"},
		{"name": "Koffing",  "ability": "destiny_bond"}]},
	"H": {"name": "Harbor Gym",  "type": "Water",    "badge": "glacier", "team": [
		{"name": "Wartortle","ability": "water_bond", "ability2": "reflect",    "stars": 1},  # threat
		{"name": "Omanyte",  "ability": "multiscale", "ability2": "sturdy",     "stars": 1},  # threat
		{"name": "Shellder", "ability": "bulwark",    "ability2": "reflect",    "stars": 1},  # threat
		{"name": "Seel",     "ability": "dynasty"}]},
}

# ─── Elite Four: four sequential battles ──────────────────────────────────────
# Each fields an ★3 ACE plus two more ★3-at-cap threats — all with two abilities.
const ELITE_FOUR := [
	{"name": "Elite Will",  "team": [
		{"name": "Slowbro",   "ability": "reflect",     "ability2": "wish",        "stars": 3},  # ace
		{"name": "Hypno",     "ability": "hypnosis",    "ability2": "confuse_ray", "stars": 1},  # threat
		{"name": "Wigglytuff","ability": "psychic_bond","ability2": "helping_hand","stars": 1},  # threat
		{"name": "Alakazam",  "ability": "encore"}]},
	{"name": "Elite Koga",  "team": [
		{"name": "Muk",       "ability": "dark_bond",   "ability2": "vengeance",   "stars": 3},  # ace
		{"name": "Weezing",   "ability": "explosion",   "ability2": "poison_point","stars": 1},  # threat
		{"name": "Golbat",    "ability": "poison_point","ability2": "thief",       "stars": 1},  # threat
		{"name": "Beedrill",  "ability": "screech"}]},
	{"name": "Elite Bruno", "team": [
		{"name": "Poliwrath", "ability": "intimidate",   "ability2": "counter",    "stars": 3},  # ace
		{"name": "Machamp",   "ability": "fighting_bond","ability2": "grit",       "stars": 1},  # threat
		{"name": "Golem",     "ability": "fortress",     "ability2": "battle_armor","stars": 1}, # threat
		{"name": "Marowak",   "ability": "sturdy"}]},
	{"name": "Elite Karen", "team": [
		{"name": "Gengar",    "ability": "hypnosis", "ability2": "destiny_bond",   "stars": 3},  # ace
		{"name": "Persian",   "ability": "thief",    "ability2": "moxie",          "stars": 1},  # threat
		{"name": "Arbok",     "ability": "taunt",    "ability2": "poison_point",   "stars": 1},  # threat
		{"name": "Venomoth",  "ability": "spore"}]},
]

# ─── Gary, the Champion (an ★3 ace + two more ★3-at-cap threats) ──────────────
const GARY := {
	"name": "Gary",
	"team": [
		{"name": "Alakazam", "ability": "psychic_bond","ability2": "hypnosis",   "stars": 3},  # ace
		{"name": "Gyarados", "ability": "moxie",       "ability2": "water_bond", "stars": 1},  # threat
		{"name": "Blastoise","ability": "reflect",     "ability2": "multiscale", "stars": 1},  # threat
		{"name": "Arcanine", "ability": "drought"}],
}

# ─── Trainer battle events: random team fights on EVENT tiles ─────────────────
# Themed trainers with synergy teams that scale with the challenger's badges.
# On a win: reward points + gold (no badge). CPUs fight; humans pick a team.
#
# Untagged challengers face only a slice of the roster below, taken from the top
# (see trainer_team_size) — so the themed threat listed first is always in, and
# the rosters read biggest-threat-first.
const TRAINER_BATTLES := [
	{"name": "Bug Catcher Bex", "portrait": ["bugcatcher", "acetrainer"], "pts": 1, "gold": 15, "team": [
		{"name": "Butterfree", "ability": "confuse_ray", "ability2": "spore", "stars": 1},  # threat
		{"name": "Beedrill",   "ability": "thief"},
		{"name": "Venomoth",   "ability": "poison_point"},
		{"name": "Scyther",    "ability": "screech"}]},
	{"name": "Hiker Rocky",     "portrait": ["hiker", "acetrainer"], "pts": 1, "gold": 15, "team": [
		{"name": "Onix",       "ability": "fortress", "ability2": "battle_armor", "stars": 1},  # threat
		{"name": "Geodude",    "ability": "fighting_bond"},
		{"name": "Rhyhorn",    "ability": "grit"},
		{"name": "Machop",     "ability": "intimidate"}]},
	{"name": "Swimmer Sana",    "portrait": ["swimmer", "swimmerf", "acetrainerf"], "pts": 1, "gold": 15, "team": [
		{"name": "Seel",       "ability": "water_bond", "ability2": "reflect", "stars": 1},  # threat
		{"name": "Krabby",     "ability": "sturdy"},
		{"name": "Shellder",   "ability": "bulwark"},
		{"name": "Goldeen",    "ability": "wish"}]},
	{"name": "Firebug Cole",    "portrait": ["blackbelt", "acetrainer"], "pts": 2, "gold": 20, "team": [
		{"name": "Magmar",     "ability": "fire_bond", "ability2": "flame_body", "stars": 1},  # threat
		{"name": "Growlithe",  "ability": "drought"},
		{"name": "Vulpix",     "ability": "sniper"},
		{"name": "Ponyta",     "ability": "blaze"}]},
	{"name": "Psychic Mona",    "portrait": ["psychic", "acetrainerf"], "pts": 2, "gold": 20, "team": [
		{"name": "Kadabra",    "ability": "hypnosis", "ability2": "encore", "stars": 1},  # threat
		{"name": "Drowzee",    "ability": "confuse_ray"},
		{"name": "Jynx",       "ability": "reflect"},
		{"name": "Slowpoke",   "ability": "psychic_bond"}]},
	{"name": "Punk Zane",       "portrait": ["punkguy", "acetrainer"], "pts": 2, "gold": 20, "team": [
		{"name": "Grimer",     "ability": "dark_bond", "ability2": "vengeance", "stars": 1},  # threat
		{"name": "Koffing",    "ability": "destiny_bond"},
		{"name": "Zubat",      "ability": "poison_point"},
		{"name": "Ekans",      "ability": "taunt"}]},
	{"name": "Rival Sparky",    "portrait": ["blue-gen1", "acetrainer"], "pts": 3, "gold": 25, "team": [
		{"name": "Raichu",     "ability": "electric_bond", "ability2": "static",    "stars": 1},  # threat
		{"name": "Jolteon",    "ability": "speed_boost",   "ability2": "berserker", "stars": 1},  # threat
		{"name": "Magneton",   "ability": "thunder_wave"},
		{"name": "Electabuzz", "ability": "moxie"}]},
]

# How many spirits a trainer brings. Until the challenger earns the ⚔ PvP tag
# (at Cobweb City) trainers stay small — a random 1-2, rolled per battle. Once
# tagged, every trainer fields their FULL roster.
const TRAINER_TEAM_MAX_UNTAGGED := 2

static func trainer_team_size(pvp_tag: bool, roster_size: int) -> int:
	if pvp_tag:
		return roster_size
	return randi_range(1, maxi(1, mini(roster_size, TRAINER_TEAM_MAX_UNTAGGED)))

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
const PLAYER_TRAINERS := {
	"Ember": "alain", "Brooke": "adaman", "Ivy": "akari", "Zap": "acerola",
	"Rex": "alder", "Shade": "allister", "Luna": "amarys",
	"Red": "red", "Blue": "blue", "Leaf": "leaf", "Ash": "ash",   # legacy names
}
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

# Enemy difficulty tier from the CHALLENGER's badge count. Scaling STOPS after
# 3 badges — everything past that stays tier 3.
#   0–1 badges → 1 (weakest), 2 badges → 2 (mid), 3+ badges → 3 (strongest, capped).
static func challenge_tier(badges: int) -> int:
	return clampi(badges, 1, 3)

# Build an enemy team scaled to a tier: each tier above 1 evolves the roster
# one stage (stats follow the new stage) and grants a star (+1 effective ATK).
# Tier 1 = the listed names as-is; tier 3 = final forms with 2 stars.
static func build_team_scaled(names: Array, tier: int) -> Array:
	var team: Array = []
	for raw in names:
		var n: String = raw
		for _e in tier - 1:
			var evo: String = String(SpiritsData.SPIRITS.get(n, {}).get("evolution", ""))
			if evo != "":
				n = evo
		var s: Dictionary = SpiritsData.get_spirit(n)
		if s.is_empty():
			continue
		s["stars"] = tier - 1
		team.append(s)
	return team

# Build a DESIGNED team from entries that are either a plain name (random
# ability) or {name, ability, ability2?, stars?}. Badge tier adds +0/+1/+2
# stars on top of each member's base, capped at 3 — synergy stays intact,
# power scales. Used by gyms, the Elite Four, Gary and trainer battles.
static func build_team_designed(entries: Array, tier: int) -> Array:
	var team: Array = []
	var bonus: int = clampi(tier - 1, 0, 2)
	for raw in entries:
		var s: Dictionary
		var base_stars := 0
		if raw is String:
			s = SpiritsData.get_spirit(raw)
		else:
			var e: Dictionary = raw
			s = SpiritsData.get_spirit(String(e.get("name", "")))
			if not s.is_empty():
				if e.has("ability"):
					s["ability"] = String(e["ability"])
				if e.has("ability2"):
					s["ability2"] = String(e["ability2"])
				base_stars = int(e.get("stars", 0))
		if s.is_empty():
			continue
		s["stars"] = mini(3, base_stars + bonus)
		team.append(s)
	return team

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
