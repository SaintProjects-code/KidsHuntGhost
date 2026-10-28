class_name GameData
## Static game content: the 8 town gyms, the Haunted Four, Champion Vesper,
## trainer battles, trainer portraits and the ITEM-tile reward table.
## Used as GameData.<thing> — no autoload needed.

# ─── Gyms: one per town (A..H), each grants a badge ───────────────────────────
# badge keys match PlayerData.Progress.badges. Each gym is a MONO-TYPE team
# built around synergy: a bond ability (bigger the more same-type allies), a
# team buff or disruptor, and support. Entries can be a plain name (random
# ability) or {name, ability, ability2?, stars?}. Badge tier adds stars, so at
# the cap (tier 3) the "threat" members hit ★3 with two abilities.
const GYMS := {
	"A": {"name": "Ashen Gym",   "type": "Fire",     "badge": "cinder", "team": [
		{"name": "Flickerfoal", "ability": "drought",   "ability2": "blaze",      "stars": 1},  # threat
		{"name": "Magmawraith", "ability": "fire_bond", "ability2": "flame_body", "stars": 1},  # threat
		{"name": "Emberpup",    "ability": "sniper"},
		{"name": "Foxfire",     "ability": "moxie"}]},
	"B": {"name": "Bayou Gym",   "type": "Water",    "badge": "bayou",  "team": [
		{"name": "Frostpup",    "ability": "water_bond", "ability2": "reflect",   "stars": 1},  # threat
		{"name": "Clamshade",   "ability": "multiscale", "ability2": "bulwark",   "stars": 1},  # threat
		{"name": "Pinchling",   "ability": "sturdy"},
		{"name": "Quackle",     "ability": "wish"}]},
	"C": {"name": "Cobweb Gym",  "type": "Grass",    "badge": "cobweb", "team": [
		{"name": "Vinewisp",    "ability": "grass_bond", "ability2": "leech_seed",  "stars": 1},  # threat
		{"name": "Rootling",    "ability": "spore",      "ability2": "poison_point","stars": 1},  # threat
		{"name": "Seedlings",   "ability": "healer",     "ability2": "wish",        "stars": 1},  # threat
		{"name": "Leaflet",     "ability": "overgrow"}]},
	"D": {"name": "Dusk Gym",    "type": "Electric", "badge": "dusk",   "team": [
		{"name": "Zapkin",      "ability": "electric_bond","ability2": "static",   "stars": 1},  # threat
		{"name": "Buzzghast",   "ability": "speed_boost",  "ability2": "berserker","stars": 1},  # threat
		{"name": "Sparkbolt",   "ability": "thunder_wave"},
		{"name": "Zaporb",      "ability": "explosion"}]},
	"E": {"name": "Echo Gym",    "type": "Psychic",  "badge": "echo",   "team": [
		{"name": "Drowsel",     "ability": "hypnosis",    "ability2": "confuse_ray", "stars": 1},  # threat
		{"name": "Moonmote",    "ability": "psychic_bond","ability2": "reflect",     "stars": 1},  # threat
		{"name": "Lullaboo",    "ability": "wish",        "ability2": "helping_hand","stars": 1},  # threat
		{"name": "Snoozle",     "ability": "encore"}]},
	"F": {"name": "Foggy Gym",   "type": "Fighting", "badge": "fog",    "team": [
		{"name": "Brawlboo",    "ability": "intimidate",   "ability2": "counter",  "stars": 1},  # threat
		{"name": "Pebblewisp",  "ability": "fighting_bond","ability2": "fortress", "stars": 1},  # threat
		{"name": "Hornling",    "ability": "battle_armor"},
		{"name": "Kickghast",   "ability": "grit"}]},
	"G": {"name": "Ghoul Gym",   "type": "Dark",     "badge": "ghoul",  "team": [
		{"name": "Sludgling",   "ability": "dark_bond", "ability2": "vengeance", "stars": 1},  # threat
		{"name": "Wispy",       "ability": "taunt",     "ability2": "thief",     "stars": 1},  # threat
		{"name": "Batling",     "ability": "poison_point"},
		{"name": "Smogling",    "ability": "destiny_bond"}]},
	"H": {"name": "Harbor Gym",  "type": "Water",    "badge": "harbor", "team": [
		{"name": "Puddlegeist", "ability": "water_bond", "ability2": "reflect", "stars": 1},  # threat
		{"name": "Spiralshade", "ability": "multiscale", "ability2": "sturdy",  "stars": 1},  # threat
		{"name": "Clamshade",   "ability": "bulwark",    "ability2": "reflect", "stars": 1},  # threat
		{"name": "Frostpup",    "ability": "dynasty"}]},
}

# ─── The Haunted Four: the Spectral Trail's wardens ───────────────────────────
# Each fields an ★3 ACE plus two more ★3-at-cap threats — all with two abilities.
const HAUNTED_FOUR := [
	{"name": "Warden Willow", "portrait": ["will", "agatha-gen1"], "team": [
		{"name": "Snoozelord",   "ability": "reflect",     "ability2": "wish",        "stars": 3},  # ace
		{"name": "Trancewraith", "ability": "hypnosis",    "ability2": "confuse_ray", "stars": 1},  # threat
		{"name": "Lullabanshee", "ability": "psychic_bond","ability2": "helping_hand","stars": 1},  # threat
		{"name": "Dreamseer",    "ability": "encore"}]},
	{"name": "Warden Kage",   "portrait": ["koga", "agatha-gen1"], "team": [
		{"name": "Sludgeghast",  "ability": "dark_bond",   "ability2": "vengeance",   "stars": 3},  # ace
		{"name": "Smogwraith",   "ability": "explosion",   "ability2": "poison_point","stars": 1},  # threat
		{"name": "Batwraith",    "ability": "poison_point","ability2": "thief",       "stars": 1},  # threat
		{"name": "Stingspecter", "ability": "screech"}]},
	{"name": "Warden Brutus", "portrait": ["bruno", "agatha-gen1"], "team": [
		{"name": "Swirlwrath",   "ability": "intimidate",   "ability2": "counter",     "stars": 3},  # ace
		{"name": "Brawltitan",   "ability": "fighting_bond","ability2": "grit",        "stars": 1},  # threat
		{"name": "Gravegolem",   "ability": "fortress",     "ability2": "battle_armor","stars": 1},  # threat
		{"name": "Skullguard",   "ability": "sturdy"}]},
	{"name": "Warden Karma",  "portrait": ["karen", "agatha-gen1"], "team": [
		{"name": "Hauntking",    "ability": "hypnosis", "ability2": "destiny_bond", "stars": 3},  # ace
		{"name": "Purrphantom",  "ability": "thief",    "ability2": "moxie",        "stars": 1},  # threat
		{"name": "Hissperor",    "ability": "taunt",    "ability2": "poison_point", "stars": 1},  # threat
		{"name": "Mothgeist",    "ability": "spore"}]},
]

# ─── Champion Vesper, keeper of the Spectral Peak ─────────────────────────────
const CHAMPION := {
	"name": "Champion Vesper",
	"portrait": ["gary", "blue-gen1", "blue", "acetrainer-gen1"],
	"team": [
		{"name": "Dreamseer",    "ability": "psychic_bond","ability2": "hypnosis",   "stars": 3},  # ace
		{"name": "Floodserpent", "ability": "moxie",       "ability2": "water_bond", "stars": 1},  # threat
		{"name": "Tidetomb",     "ability": "reflect",     "ability2": "multiscale", "stars": 1},  # threat
		{"name": "Emberhound",   "ability": "drought"}],
}

# ─── Trainer battles: random team fights on EVENT tiles ───────────────────────
# Themed trainers with synergy teams that scale with the challenger's badges.
# On a win: points + gold (no badge). Untagged challengers face only the first
# 1-2 of the roster (see trainer_team_size), so the threat listed first is
# always in.
const TRAINER_BATTLES := [
	{"name": "Bug Catcher Bex", "portrait": ["bugcatcher", "acetrainer"], "pts": 1, "gold": 15, "team": [
		{"name": "Gloomoth",     "ability": "confuse_ray", "ability2": "spore", "stars": 1},  # threat
		{"name": "Stingspecter", "ability": "thief"},
		{"name": "Mothgeist",    "ability": "poison_point"},
		{"name": "Reaperling",   "ability": "screech"}]},
	{"name": "Hiker Rocky",     "portrait": ["hiker", "acetrainer"], "pts": 1, "gold": 15, "team": [
		{"name": "Cryptcoil",    "ability": "fortress", "ability2": "battle_armor", "stars": 1},  # threat
		{"name": "Pebblewisp",   "ability": "fighting_bond"},
		{"name": "Hornling",     "ability": "grit"},
		{"name": "Brawlboo",     "ability": "intimidate"}]},
	{"name": "Swimmer Sana",    "portrait": ["swimmer", "swimmerf", "acetrainerf"], "pts": 1, "gold": 15, "team": [
		{"name": "Frostpup",     "ability": "water_bond", "ability2": "reflect", "stars": 1},  # threat
		{"name": "Pinchling",    "ability": "sturdy"},
		{"name": "Clamshade",    "ability": "bulwark"},
		{"name": "Finwisp",      "ability": "wish"}]},
	{"name": "Firebug Cole",    "portrait": ["blackbelt", "acetrainer"], "pts": 2, "gold": 20, "team": [
		{"name": "Magmawraith",  "ability": "fire_bond", "ability2": "flame_body", "stars": 1},  # threat
		{"name": "Emberpup",     "ability": "drought"},
		{"name": "Foxfire",      "ability": "sniper"},
		{"name": "Flickerfoal",  "ability": "blaze"}]},
	{"name": "Medium Mona",     "portrait": ["psychic", "acetrainerf"], "pts": 2, "gold": 20, "team": [
		{"name": "Dreamshade",   "ability": "hypnosis", "ability2": "encore", "stars": 1},  # threat
		{"name": "Drowsel",      "ability": "confuse_ray"},
		{"name": "Frostsong",    "ability": "reflect"},
		{"name": "Snoozle",      "ability": "psychic_bond"}]},
	{"name": "Punk Zane",       "portrait": ["punkguy", "acetrainer"], "pts": 2, "gold": 20, "team": [
		{"name": "Sludgling",    "ability": "dark_bond", "ability2": "vengeance", "stars": 1},  # threat
		{"name": "Smogling",     "ability": "destiny_bond"},
		{"name": "Batling",      "ability": "poison_point"},
		{"name": "Hissper",      "ability": "taunt"}]},
	{"name": "Rival Sparky",    "portrait": ["blue-gen1", "acetrainer"], "pts": 3, "gold": 25, "team": [
		{"name": "Zapparition",  "ability": "electric_bond", "ability2": "static",    "stars": 1},  # threat
		{"name": "Sparkkit",     "ability": "speed_boost",   "ability2": "berserker", "stars": 1},  # threat
		{"name": "Sparkcluster", "ability": "thunder_wave"},
		{"name": "Buzzghast",    "ability": "moxie"}]},
]

# Until the challenger earns the ⚔ tag (at Cobweb City) trainers stay small —
# a random 1-2, rolled per battle. Once tagged, they field their FULL roster.
const TRAINER_TEAM_MAX_UNTAGGED := 2

static func trainer_team_size(pvp_tag: bool, roster_size: int) -> int:
	if pvp_tag:
		return roster_size
	return randi_range(1, maxi(1, mini(roster_size, TRAINER_TEAM_MAX_UNTAGGED)))

# ─── Trainer portraits (Assets/Trainer) ───────────────────────────────────────
# Resolution walks a candidate list so missing files fall back gracefully.
const TRAINER_DIR := "res://Assets/Trainer/"
const PLAYER_TRAINERS := {
	"Ember": "alain", "Brooke": "adaman", "Ivy": "akari", "Zap": "acerola",
	"Rex": "alder", "Shade": "allister", "Luna": "amarys",
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

static func player_trainer(p: PlayerData) -> Array:
	return [p.trainer_key, PLAYER_TRAINERS.get(p.player_name, ""), "acetrainer-gen1", "acetrainer"]

static func gym_trainer(type: String) -> Array:
	return [GYM_TRAINERS.get(type, ""), "acetrainer", "acetrainer-gen1"]

# ─── ITEM tiles ───────────────────────────────────────────────────────────────
# What an ITEM tile hands out, by weight: mostly a card, sometimes jars/gold.
const ITEM_REWARDS := [
	{"kind": "card",  "amount": 1, "weight": 60},
	{"kind": "card",  "amount": 2, "weight": 10},
	{"kind": "jars",  "amount": 2, "weight": 18},
	{"kind": "gold",  "amount": 20, "weight": 12},
]

static func random_item_reward() -> Dictionary:
	var total := 0
	for r in ITEM_REWARDS:
		total += int(r["weight"])
	var roll := randi_range(1, total)
	for r in ITEM_REWARDS:
		roll -= int(r["weight"])
		if roll <= 0:
			return r
	return ITEM_REWARDS[0]

# Enemy difficulty tier from the CHALLENGER's badge count. Scaling STOPS after
# 3 badges: 0–1 → 1 (weakest), 2 → 2, 3+ → 3 (strongest).
static func challenge_tier(badges: int) -> int:
	return clampi(badges, 1, 3)

# Tier for the Spectral Trail's wardens and the Champion (see Balance).
static func trail_tier(badges: int) -> int:
	return clampi(badges - Balance.TRAIL_BADGE_OFFSET, 1, 3)

# Build a DESIGNED team from entries that are either a plain name (random
# ability) or {name, ability, ability2?, stars?}. NPC teams GROW with the tier:
#   tier 1 — one ability each; listed stars −1 (a "★1 threat" starts at ★0)
#   tier 2 — second abilities unlock; listed stars as written
#   tier 3 — everyone +1 star on top (capped at 3)
# Plain members get tier − 1 stars.
# Rosters hold 4; the NPC counter-picks 3 of them once it sees your team
# (BattleSetup.counter_pick).
static func build_team(entries: Array, tier: int) -> Array:
	var team: Array = []
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
				if e.has("ability2") and tier >= 2:
					s["ability2"] = String(e["ability2"])
				base_stars = int(e.get("stars", 0))
		if s.is_empty():
			continue
		var stars: int = base_stars + tier - 2 if base_stars > 0 else tier - 1
		s["stars"] = clampi(stars, 0, 3)
		team.append(s)
	return team

static func gym_for_city(city: String) -> Dictionary:
	return GYMS.get(city, {})

static func badge_name(key: String) -> String:
	return key.capitalize() + " Badge"
