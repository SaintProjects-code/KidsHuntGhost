extends Node
## Spirit (Pokémon) database. Autoloaded as `SpiritsData`.
##
## get_spirit(name) -> fresh battle-ready dict:
##   name, type, hp, current_hp, hp_stat, atk, def, spd, stage, stars,
##   evolution, ability, rarity, sprite_path
##
## Scale:  hp = 60 + hp_stat×30 (tier 1=90 … 6=240).  atk/def/spd are 1–6 tiers.
##
## Sprites: each Assets/Pokemon/*.png is a 129×163 sheet (header + 2×2 grid of
## front / front-shiny / back / back-shiny). sprite_tex(name, view) slices out one
## frame so different screens can show different views (front in menus, back for
## your own battler, etc.).

const SPRITE_DIR := "res://Assets/Pokemon/"

# Sub-rectangles within a 129×163 sheet. Tweak here if a frame looks off-centre.
const SHEET_REGIONS := {
	"front":       Rect2(2, 36, 60, 60),
	"front_shiny": Rect2(67, 36, 60, 60),
	"back":        Rect2(2, 100, 60, 60),
	"back_shiny":  Rect2(67, 100, 60, 60),
	# Centred on the header icon (all sheets draw it centred at ~(81, 21));
	# sized to cover the largest icons (Onix) and stop above the underline row.
	"icon":        Rect2(65, 9, 32, 24),
}

# ─── Type effectiveness ───────────────────────────────────────────────────────
# Super-effective hits deal ×1.5 (was ×2.0 — one-shot city) and resisted ×0.5.
const TYPE_CHART := {
	"Fire":     {"Grass": 1.5,    "Water": 0.5},
	"Water":    {"Fire": 1.5,     "Electric": 0.5},
	"Grass":    {"Electric": 1.5, "Fire": 0.5},
	"Electric": {"Water": 1.5,    "Grass": 0.5},
	"Dark":     {"Psychic": 1.5,  "Fighting": 0.5},
	"Psychic":  {"Fighting": 1.5, "Dark": 0.5},
	"Fighting": {"Dark": 1.5,     "Psychic": 0.5},
}

const TYPE_COLORS := {
	"Fire": Color("e8623a"), "Water": Color("4aa3df"), "Grass": Color("4caf50"),
	"Electric": Color("f4d03f"), "Dark": Color("8e6fd6"), "Psychic": Color("e86fb0"),
	"Fighting": Color("d06a3a"),
}

# ─── Abilities (ported from the reference game) ───────────────────────────────
const ABILITY_DATA := {
	"intimidate":    {"name":"Intimidate",    "cat":"Match Start", "desc":"Match start: opponent team loses -3 ATK"},
	"drought":       {"name":"Drought",       "cat":"Round Start", "desc":"Round start: your whole team gains +1 ATK"},
	"thunder_wave":  {"name":"Thunder Wave",  "cat":"Match Start", "desc":"Match start: Stun the opponent lead for 2 rounds"},
	"veteran":       {"name":"Veteran",       "cat":"Match Start", "desc":"Match start: 2+ stars: +3 ATK, immune to status and abilities"},
	"screech":       {"name":"Screech",       "cat":"Match Start", "desc":"Match start: opponent lead loses -2 DEF"},
	"spikes":        {"name":"Spikes",        "cat":"Match Start", "desc":"Match start: each opponent takes 30 dmg on first entry"},
	"confuse_ray":   {"name":"Confuse Ray",   "cat":"Match Start", "desc":"Match start: Confuse the opponent lead 2–3 rounds"},
	"tailwind":      {"name":"Tailwind",      "cat":"Match Start", "desc":"Match start: your whole team gains +3 SPD"},
	"speed_boost":   {"name":"Speed Boost",   "cat":"Match Start", "desc":"Match start: self +2 ATK; your team gains +1 SPD and +1 ATK"},
	"taunt":         {"name":"Taunt",         "cat":"Match Start", "desc":"Match start: opponent cannot heal or inflict status"},
	"sniper":        {"name":"Sniper",        "cat":"Match Start", "desc":"Match start: deal 40 to a random opponent"},
	"fire_bond":     {"name":"Fire Bond",     "cat":"Match Start", "desc":"Match start: +2 ATK per Fire ally; allies +1 DEF"},
	"water_bond":    {"name":"Water Bond",    "cat":"Match Start", "desc":"Match start: +1 ATK per Water ally; allies +2 DEF"},
	"grass_bond":    {"name":"Grass Bond",    "cat":"Match Start", "desc":"Match start: +1 ATK per Grass ally; allies +2 HP"},
	"electric_bond": {"name":"Electric Bond", "cat":"Match Start", "desc":"Match start: +1 ATK per Electric ally; allies +2 SPD"},
	"fighting_bond": {"name":"Fighting Bond", "cat":"Match Start", "desc":"Match start: +2 ATK per Fighting ally; allies +2 ATK"},
	"psychic_bond":  {"name":"Psychic Bond",  "cat":"Match Start", "desc":"Match start: +1 ATK per Psychic ally; allies immune to status"},
	"dark_bond":     {"name":"Dark Bond",     "cat":"Match Start", "desc":"Match start: +1 ATK per Dark ally; opponent team -2 DEF"},
	"u_turn":        {"name":"U-Turn",        "cat":"Match Start · Lead", "desc":"Match start: hit the lead for 20, then switch out (ally +2 ATK)"},
	"wish":          {"name":"Wish",          "cat":"Round Start", "desc":"Round start: heal all team spirits 20 HP"},
	"regenerator":   {"name":"Regenerator",   "cat":"Round Start", "desc":"Round start: heal 30% max HP; if full, +1 ATK (max 3)"},
	"medic":         {"name":"Medic",         "cat":"Round Start · Once", "desc":"Round start: 30% to revive a downed ally to full HP"},
	"leech_seed":    {"name":"Leech Seed",    "cat":"Round Start · Lead", "desc":"Round start: drain 10 HP from the lead (2× if statused)"},
	"berserker":     {"name":"Berserker",     "cat":"Round Start · Lead", "desc":"Round start: +2 ATK, lose 10 HP"},
	"drain_punch":   {"name":"Drain Punch",   "cat":"Round Start · Lead", "desc":"Round start: deal 30 to the lead and heal 20"},
	"healer":        {"name":"Healer",        "cat":"Round Start", "desc":"Round start: heal the lead 30 HP (not while leading)"},
	"dynasty":       {"name":"Dynasty",       "cat":"Round Start · Lead", "desc":"Round start: heal 20 HP while leading"},
	"helping_hand":  {"name":"Helping Hand",  "cat":"Passive", "desc":"If lead drops below 45% HP: heal 20, swap in and soak the hit"},
	"vengeance":     {"name":"Vengeance",     "cat":"Passive", "desc":"When any ally faints, deal 30 to a lead"},
	"encore":        {"name":"Encore",        "cat":"Passive", "desc":"Lead: opponent's lead ability is suppressed"},
	"static":        {"name":"Static",        "cat":"Passive · Lead", "desc":"30% to Stun the attacker when hit"},
	"poison_point":  {"name":"Poison Point",  "cat":"Passive · Lead", "desc":"Poison the attacker when hit"},
	"flame_body":    {"name":"Flame Body",    "cat":"Passive · Lead", "desc":"Burn the attacker when hit"},
	"thick_fat":     {"name":"Thick Fat",     "cat":"Passive · Lead", "desc":"All incoming damage reduced by 20%"},
	"thief":         {"name":"Thief",         "cat":"Passive · Lead", "desc":"On hit: steal +1 ATK (no max)"},
	"moxie":         {"name":"Moxie",         "cat":"Passive · Lead", "desc":"On KO: gain +2 ATK"},
	"battle_armor":  {"name":"Battle Armor",  "cat":"Passive · Lead", "desc":"Lead: incoming damage halved for the first 2 rounds"},
	"grit":          {"name":"Grit",          "cat":"Passive · Lead", "desc":"Below 50% HP: incoming damage reduced by 40%"},
	"counter":       {"name":"Counter",       "cat":"Passive · Lead", "desc":"75% chance when hit: deal back 40% of that damage"},
	"sturdy":        {"name":"Sturdy",        "cat":"Passive · Lead · Once", "desc":"Survive one KO per battle at 1 HP"},
	"hypnosis":      {"name":"Hypnosis",      "cat":"Passive · Lead · Once", "desc":"Lead: opponent falls Asleep"},
	"all_for_one":   {"name":"All For One",   "cat":"Passive · Lead · Once", "desc":"Lead: self +4 ATK/DEF/SPD; rest of your team −4 ATK/DEF/SPD"},
	"reflect":       {"name":"Reflect",       "cat":"Passive · Lead · Once", "desc":"Lead: your whole team gains +2 DEF"},
	"shell_smash":   {"name":"Shell Smash",   "cat":"Passive · Lead · Once", "desc":"Lead: DEF -3, ATK +3, SPD +3"},
	"explosion":     {"name":"Explosion",     "cat":"Passive · Lead · Once", "desc":"On faint: deal 60% max HP; opponent team -2 ATK/DEF"},
	"destiny_bond":  {"name":"Destiny Bond",  "cat":"Passive · Lead · Once", "desc":"On faint: the killer also faints"},
	"anger_point":   {"name":"Anger Point",   "cat":"Passive · Lead · Once", "desc":"On a KO blow: survive at 1 HP and gain +3 ATK"},
	"multiscale":    {"name":"Multiscale",    "cat":"Passive · Lead · Once", "desc":"Lead: if full HP, take 50% less from the first hit"},
	"overgrow":      {"name":"Overgrow",      "cat":"Passive · Lead · Once", "desc":"Below 50% HP: +4 DEF for the battle"},
	"blaze":         {"name":"Blaze",         "cat":"Passive · Lead · Once", "desc":"Below 33% HP: permanently +4 ATK and +2 SPD"},
	"flash_fire":    {"name":"Flash Fire",    "cat":"Passive · Lead", "desc":"25% when hit: negate damage and gain +2 ATK"},
	"volt_absorb":   {"name":"Volt Absorb",   "cat":"Passive · Lead", "desc":"35% when hit: absorb the damage as HP"},
	"soul_heart":    {"name":"Soul Heart",    "cat":"Passive", "desc":"When an ally faints: opponent team gets -2 ATK and -2 DEF (stacks)"},
	"bulwark":       {"name":"Bulwark",       "cat":"Passive · Lead", "desc":"Lead: -2 DEF to the opponent lead when hit"},
	"fortress":      {"name":"Fortress",      "cat":"Passive · Lead", "desc":"Lead: +1 DEF per round survived (no max)"},
	"iron_will":     {"name":"Iron Will",     "cat":"Round Start · Lead", "desc":"Round start: gain +1 ATK"},
	"monument":      {"name":"Monument",      "cat":"Passive", "desc":"Match start: if your last spirit, +3 to all stats"},
	"reckless":      {"name":"Reckless",      "cat":"Passive · Lead", "desc":"Deal +25% damage but take +15% damage"},
	"spore":         {"name":"Spore",         "cat":"Passive · Lead", "desc":"When hit: inflict a random status on the attacker"},
	# ── interactive set ──────────────────────────────────────────────────────
	"mayhem":        {"name":"Mayhem",        "cat":"Match Start", "desc":"Match start: shuffle the opponent's whole team randomly"},
	"fallen":        {"name":"Fallen",        "cat":"Passive", "desc":"+1 ATK and +1 DEF each time an ally faints"},
	"electric_field":{"name":"Electric Field","cat":"Round Start", "desc":"Round start: deal 10 to two random opponents (bench included)"},
	"mind_hold":     {"name":"Mind Hold",     "cat":"Match Start", "desc":"Match start: cancel two opponent spirits' abilities for the battle"},
	"bodyguard":     {"name":"Bodyguard",     "cat":"Passive", "desc":"Redirect the first hit each round away from a hurt ally"},
	"phoenix":       {"name":"Phoenix",       "cat":"Passive · Once", "desc":"On faint: revive once at 30% HP"},
}

const TYPE_ABILITY_POOLS := {
	"Fire":     ["drought", "fire_bond", "moxie", "sniper", "explosion", "flame_body", "berserker", "shell_smash", "blaze", "flash_fire", "reckless", "phoenix"],
	"Water":    ["thick_fat", "sturdy", "u_turn", "water_bond", "multiscale", "bulwark", "wish", "reflect", "drain_punch", "static"],
	"Grass":    ["leech_seed", "poison_point", "screech", "spikes", "wish", "healer", "medic", "grass_bond", "drain_punch", "overgrow", "spore"],
	"Electric": ["thunder_wave", "electric_bond", "speed_boost", "soul_heart", "anger_point", "static", "berserker", "volt_absorb", "electric_field", "tailwind"],
	"Psychic":  ["hypnosis", "confuse_ray", "encore", "psychic_bond", "helping_hand", "reflect", "wish", "destiny_bond", "mind_hold"],
	"Fighting": ["veteran", "intimidate", "fighting_bond", "battle_armor", "monument", "fortress", "iron_will", "berserker", "drain_punch", "all_for_one", "grit", "counter", "fallen", "bodyguard"],
	"Dark":     ["thief", "taunt", "vengeance", "dynasty", "dark_bond", "destiny_bond", "poison_point", "mayhem"],
}

const HIDDEN_ABILITY_BY_TYPE := {
	"Fire": "berserker", "Water": "shell_smash", "Grass": "regenerator",
	"Electric": "all_for_one", "Psychic": "drain_punch", "Fighting": "reflect", "Dark": "destiny_bond",
}

# ─── Dual types ───────────────────────────────────────────────────────────────
# A second type grants access to BOTH types' ability pools (the ability rolled
# at creation AND bonus-reward choices). Mostly final forms, legendaries and
# standalone spirits — evolving into one unlocks the second pool. The primary
# type still decides stats, the type chart and colours.
const DUAL_TYPE := {
	# Fire
	"Charizard": "Fighting", "Dragonite": "Water", "Moltres": "Psychic",
	# Water
	"Gyarados": "Dark", "Kabutops": "Fighting", "Cloyster": "Dark", "Articuno": "Psychic",
	# Grass
	"Venusaur": "Dark", "Vileplume": "Dark", "Exeggutor": "Psychic",
	"Scyther": "Fighting", "Pinsir": "Fighting",
	# Electric
	"Starmie": "Psychic", "Aerodactyl": "Dark", "Zapdos": "Fighting",
	# Psychic
	"Butterfree": "Grass", "Slowbro": "Water", "Lapras": "Water", "Jynx": "Water",
	"Mewtwo": "Dark", "Mew": "Grass",
	# Fighting
	"Poliwrath": "Water", "Golem": "Fire", "Rhydon": "Fire", "Snorlax": "Psychic",
	# Dark
	"Gengar": "Psychic", "Beedrill": "Grass", "Venomoth": "Psychic",
	"Parasect": "Grass", "Tentacruel": "Water", "Muk": "Water",
}

# ─── Roster source: national-dex table ────────────────────────────────────────
# [dex, name, type(mapped to the 7), evolves_into]. Stage and stats are derived.
const LEGENDARIES := [144, 145, 146, 150, 151]
const SPRITE_OVERRIDE := {1: "Bulbasaur.png", 4: "Charmander.png", 7: "Squirtle.png", 16: "Pidgey.png", 25: "Pikachu.png", 95: "Onix.png"}

# Base stats per evolution stage, before a small type-flavour tweak.
const STAGE_BASE := {
	1: {"hp_stat": 1, "atk": 2, "def": 2, "spd": 2},
	2: {"hp_stat": 2, "atk": 3, "def": 3, "spd": 3},
	3: {"hp_stat": 4, "atk": 5, "def": 4, "spd": 4},
}

# Real Gen-1 base stats per dex number: [HP, ATK, DEF, SPD], where ATK is the
# higher of the game's Attack/Special (one attack stat here). Source:
# Bulbapedia "List of Pokémon by base stats (Generation I)". Each spirit gets
# +5 tier points split across its stats in proportion to these numbers, so a
# Chansey is an HP wall and an Abra a glass cannon — same stage or not.
const BASE_STATS := {
	1: [45, 65, 49, 45], 2: [60, 80, 63, 60], 3: [80, 100, 83, 80],
	4: [39, 52, 43, 65], 5: [58, 65, 58, 80], 6: [78, 85, 78, 100],
	7: [44, 50, 65, 43], 8: [59, 65, 80, 58], 9: [79, 85, 100, 78],
	10: [45, 30, 35, 45], 11: [50, 25, 55, 30], 12: [60, 80, 50, 70],
	13: [40, 35, 30, 50], 14: [45, 25, 50, 35], 15: [65, 80, 40, 75],
	16: [40, 45, 40, 56], 17: [63, 60, 55, 71], 18: [83, 80, 75, 91],
	19: [30, 56, 35, 72], 20: [55, 81, 60, 97],
	21: [40, 60, 30, 70], 22: [65, 90, 65, 100],
	23: [35, 60, 44, 55], 24: [60, 85, 69, 80],
	25: [35, 55, 30, 90], 26: [60, 90, 55, 100],
	27: [50, 75, 85, 40], 28: [75, 100, 110, 65],
	29: [55, 47, 52, 41], 30: [70, 62, 67, 56], 31: [90, 82, 87, 76],
	32: [46, 57, 40, 50], 33: [61, 72, 57, 65], 34: [81, 92, 77, 85],
	35: [70, 60, 48, 35], 36: [95, 85, 73, 60],
	37: [38, 65, 40, 65], 38: [73, 100, 75, 100],
	39: [115, 45, 20, 20], 40: [140, 70, 45, 45],
	41: [40, 45, 35, 55], 42: [75, 80, 70, 90],
	43: [45, 75, 55, 30], 44: [60, 85, 70, 40], 45: [75, 100, 85, 50],
	46: [35, 70, 55, 25], 47: [60, 95, 80, 30],
	48: [60, 55, 50, 45], 49: [70, 90, 60, 90],
	50: [10, 55, 25, 95], 51: [35, 80, 50, 120],
	52: [40, 45, 35, 90], 53: [65, 70, 60, 115],
	54: [50, 52, 48, 55], 55: [80, 82, 78, 85],
	56: [40, 80, 35, 70], 57: [65, 105, 60, 95],
	58: [55, 70, 45, 60], 59: [90, 110, 80, 95],
	60: [40, 50, 40, 90], 61: [65, 65, 65, 90], 62: [90, 85, 95, 70],
	63: [25, 105, 15, 90], 64: [40, 120, 30, 105], 65: [55, 135, 45, 120],
	66: [70, 80, 50, 35], 67: [80, 100, 70, 45], 68: [90, 130, 80, 55],
	69: [50, 75, 35, 40], 70: [65, 90, 50, 55], 71: [80, 105, 65, 70],
	72: [40, 100, 35, 70], 73: [80, 120, 65, 100],
	74: [40, 80, 100, 20], 75: [55, 95, 115, 35], 76: [80, 110, 130, 45],
	77: [50, 85, 55, 90], 78: [65, 100, 70, 105],
	79: [90, 65, 65, 15], 80: [95, 80, 110, 30],
	81: [25, 95, 70, 45], 82: [50, 120, 95, 70],
	83: [52, 65, 55, 60],
	84: [35, 85, 45, 75], 85: [60, 110, 70, 100],
	86: [65, 70, 55, 45], 87: [90, 95, 80, 70],
	88: [80, 80, 50, 25], 89: [105, 105, 75, 50],
	90: [30, 65, 100, 40], 91: [50, 95, 180, 70],
	92: [30, 100, 30, 80], 93: [45, 115, 45, 95], 94: [60, 130, 60, 110],
	95: [35, 45, 160, 70],
	96: [60, 90, 45, 42], 97: [85, 115, 70, 67],
	98: [30, 105, 90, 50], 99: [55, 130, 115, 75],
	100: [40, 55, 50, 100], 101: [60, 80, 70, 140],
	102: [60, 60, 80, 40], 103: [95, 125, 85, 55],
	104: [50, 50, 95, 35], 105: [60, 80, 110, 45],
	106: [50, 120, 53, 87], 107: [50, 105, 79, 76],
	108: [90, 60, 75, 30],
	109: [40, 65, 95, 35], 110: [65, 90, 120, 60],
	111: [80, 85, 95, 25], 112: [105, 130, 120, 40],
	113: [250, 105, 5, 50], 114: [65, 100, 115, 60], 115: [105, 95, 80, 90],
	116: [30, 70, 70, 60], 117: [55, 95, 95, 85],
	118: [45, 67, 60, 63], 119: [80, 92, 65, 68],
	120: [30, 70, 55, 85], 121: [60, 100, 85, 115],
	122: [40, 100, 65, 90], 123: [70, 110, 80, 105], 124: [65, 95, 35, 95],
	125: [65, 85, 57, 105], 126: [65, 95, 57, 93], 127: [65, 125, 100, 85], 128: [75, 100, 95, 110],
	129: [20, 20, 55, 80], 130: [95, 125, 79, 81],
	131: [130, 95, 80, 60], 132: [48, 48, 48, 48],
	133: [55, 65, 50, 55], 134: [130, 110, 60, 65], 135: [65, 110, 60, 130], 136: [65, 130, 60, 65],
	137: [65, 75, 70, 40],
	138: [35, 90, 100, 35], 139: [70, 115, 125, 55],
	140: [30, 80, 90, 55], 141: [60, 115, 105, 80],
	142: [80, 105, 65, 130], 143: [160, 110, 65, 30],
	144: [90, 125, 100, 85], 145: [90, 125, 85, 100], 146: [90, 125, 90, 90],
	147: [41, 64, 45, 50], 148: [61, 84, 65, 70], 149: [91, 134, 95, 80],
	150: [106, 154, 90, 130], 151: [100, 100, 100, 100],
	152: [45, 49, 65, 45], 153: [60, 63, 80, 60], 154: [80, 83, 100, 80],
}
const TYPE_PROFILE := {
	"Fire":     {"atk": 1, "spd": 1},
	"Water":    {"def": 1},
	"Grass":    {"def": 1},
	"Electric": {"spd": 2, "atk": 1, "def": -1},
	"Psychic":  {"spd": 1, "atk": 1, "def": -1},
	"Fighting": {"atk": 2, "def": 1, "spd": -1},
	"Dark":     {"atk": 1, "spd": 1, "def": -1},
}

const DEX := [
	[1,"Bulbasaur","Grass","Ivysaur"], [2,"Ivysaur","Grass","Venusaur"], [3,"Venusaur","Grass",""],
	[4,"Charmander","Fire","Charmeleon"], [5,"Charmeleon","Fire","Charizard"], [6,"Charizard","Fire",""],
	[7,"Squirtle","Water","Wartortle"], [8,"Wartortle","Water","Blastoise"], [9,"Blastoise","Water",""],
	[10,"Caterpie","Psychic","Metapod"], [11,"Metapod","Psychic","Butterfree"], [12,"Butterfree","Psychic",""],
	[13,"Weedle","Dark","Kakuna"], [14,"Kakuna","Dark","Beedrill"], [15,"Beedrill","Dark",""],
	[16,"Pidgey","Electric","Pidgeotto"], [17,"Pidgeotto","Electric","Pidgeot"], [18,"Pidgeot","Electric",""],
	[19,"Rattata","Electric","Raticate"], [20,"Raticate","Electric",""],
	[21,"Spearow","Electric","Fearow"], [22,"Fearow","Electric",""],
	[23,"Ekans","Dark","Arbok"], [24,"Arbok","Dark",""],
	[25,"Pikachu","Electric","Raichu"], [26,"Raichu","Electric",""],
	[27,"Sandshrew","Fire","Sandslash"], [28,"Sandslash","Fire",""],
	[29,"Nidoran-F","Grass","Nidorina"], [30,"Nidorina","Grass","Nidoqueen"], [31,"Nidoqueen","Grass",""],
	[32,"Nidoran-M","Grass","Nidorino"], [33,"Nidorino","Grass","Nidoking"], [34,"Nidoking","Grass",""],
	[35,"Clefairy","Psychic","Clefable"], [36,"Clefable","Psychic",""],
	[37,"Vulpix","Fire","Ninetales"], [38,"Ninetales","Fire",""],
	[39,"Jigglypuff","Psychic","Wigglytuff"], [40,"Wigglytuff","Psychic",""],
	[41,"Zubat","Dark","Golbat"], [42,"Golbat","Dark",""],
	[43,"Oddish","Grass","Gloom"], [44,"Gloom","Grass","Vileplume"], [45,"Vileplume","Grass",""],
	[46,"Paras","Dark","Parasect"], [47,"Parasect","Dark",""],
	[48,"Venonat","Dark","Venomoth"], [49,"Venomoth","Dark",""],
	[50,"Diglett","Fighting","Dugtrio"], [51,"Dugtrio","Fighting",""],
	[52,"Meowth","Dark","Persian"], [53,"Persian","Dark",""],
	[54,"Psyduck","Water","Golduck"], [55,"Golduck","Water",""],
	[56,"Mankey","Fire","Primeape"], [57,"Primeape","Fire",""],
	[58,"Growlithe","Fire","Arcanine"], [59,"Arcanine","Fire",""],
	[60,"Poliwag","Fighting","Poliwhirl"], [61,"Poliwhirl","Fighting","Poliwrath"], [62,"Poliwrath","Fighting",""],
	[63,"Abra","Psychic","Kadabra"], [64,"Kadabra","Psychic","Alakazam"], [65,"Alakazam","Psychic",""],
	[66,"Machop","Fighting","Machoke"], [67,"Machoke","Fighting","Machamp"], [68,"Machamp","Fighting",""],
	[69,"Bellsprout","Grass","Weepinbell"], [70,"Weepinbell","Grass","Victreebel"], [71,"Victreebel","Grass",""],
	[72,"Tentacool","Dark","Tentacruel"], [73,"Tentacruel","Dark",""],
	[74,"Geodude","Fighting","Graveler"], [75,"Graveler","Fighting","Golem"], [76,"Golem","Fighting",""],
	[77,"Ponyta","Fire","Rapidash"], [78,"Rapidash","Fire",""],
	[79,"Slowpoke","Psychic","Slowbro"], [80,"Slowbro","Psychic",""],
	[81,"Magnemite","Electric","Magneton"], [82,"Magneton","Electric",""],
	[83,"Farfetch'd","Fighting",""],
	[84,"Doduo","Electric","Dodrio"], [85,"Dodrio","Electric",""],
	[86,"Seel","Water","Dewgong"], [87,"Dewgong","Water",""],
	[88,"Grimer","Dark","Muk"], [89,"Muk","Dark",""],
	[90,"Shellder","Water","Cloyster"], [91,"Cloyster","Water",""],
	[92,"Gastly","Dark","Haunter"], [93,"Haunter","Dark","Gengar"], [94,"Gengar","Dark",""],
	[95,"Onix","Fighting",""],
	[96,"Drowzee","Psychic","Hypno"], [97,"Hypno","Psychic",""],
	[98,"Krabby","Water","Kingler"], [99,"Kingler","Water",""],
	[100,"Voltorb","Electric","Electrode"], [101,"Electrode","Electric",""],
	[102,"Exeggcute","Grass","Exeggutor"], [103,"Exeggutor","Grass",""],
	[104,"Cubone","Fighting","Marowak"], [105,"Marowak","Fighting",""],
	[106,"Hitmonlee","Fighting",""], [107,"Hitmonchan","Fighting",""],
	[108,"Lickitung","Fighting",""],
	[109,"Koffing","Dark","Weezing"], [110,"Weezing","Dark",""],
	[111,"Rhyhorn","Fighting","Rhydon"], [112,"Rhydon","Fighting",""],
	[113,"Chansey","Psychic",""], [114,"Tangela","Water",""], [115,"Kangaskhan","Fighting",""],
	[116,"Horsea","Fire","Seadra"], [117,"Seadra","Fire",""],
	[118,"Goldeen","Water","Seaking"], [119,"Seaking","Water",""],
	[120,"Staryu","Electric","Starmie"], [121,"Starmie","Electric",""],
	[122,"Mr. Mime","Psychic",""], [123,"Scyther","Grass",""], [124,"Jynx","Psychic",""],
	[125,"Electabuzz","Electric",""], [126,"Magmar","Fire",""], [127,"Pinsir","Grass",""], [128,"Tauros","Fire",""],
	[129,"Magikarp","Water","Gyarados"], [130,"Gyarados","Water",""],
	[131,"Lapras","Psychic",""], [132,"Ditto","Psychic",""],
	[133,"Eevee","Psychic",""], [134,"Vaporeon","Water",""], [135,"Jolteon","Electric",""], [136,"Flareon","Fire",""],
	[137,"Porygon","Electric",""],
	[138,"Omanyte","Water","Omastar"], [139,"Omastar","Water",""],
	[140,"Kabuto","Water","Kabutops"], [141,"Kabutops","Water",""],
	[142,"Aerodactyl","Electric",""], [143,"Snorlax","Fighting",""],
	[144,"Articuno","Water",""], [145,"Zapdos","Electric",""], [146,"Moltres","Fire",""],
	[147,"Dratini","Fire","Dragonair"], [148,"Dragonair","Fire","Dragonite"], [149,"Dragonite","Fire",""],
	[150,"Mewtwo","Psychic",""], [151,"Mew","Psychic",""],
	[152,"Chikorita","Grass","Bayleef"], [153,"Bayleef","Grass","Meganium"], [154,"Meganium","Grass",""],
]

var SPIRITS := {}   # name -> base stats, built from DEX at startup

func _ready() -> void:
	_build_roster()

func _build_roster() -> void:
	# child -> parent, so we can work out each spirit's evolution stage.
	var parent := {}
	for e in DEX:
		if e[3] != "":
			parent[e[3]] = e[1]
	for e in DEX:
		var dex_id: int = e[0]
		var nm: String = e[1]
		var typ: String = e[2]
		var evo: String = e[3]
		var stage: int = _stage(nm, parent)
		var base: Dictionary = STAGE_BASE[stage]
		var prof: Dictionary = TYPE_PROFILE.get(typ, {})
		var hp_stat: int = base["hp_stat"]
		var atk: int = base["atk"] + int(prof.get("atk", 0))
		var def_: int = base["def"] + int(prof.get("def", 0))
		var spd: int = base["spd"] + int(prof.get("spd", 0))
		if dex_id in LEGENDARIES:
			hp_stat += 1; atk += 1; def_ += 1; spd += 1
		# +5 personality points, split in proportion to the spirit's REAL
		# base stats — so Chansey walls, Abra nukes, Onix tanks.
		var split: Array = _bonus_split(BASE_STATS.get(dex_id, [50, 50, 50, 50]))
		hp_stat += split[0]
		atk += split[1]
		def_ += split[2]
		spd += split[3]
		SPIRITS[nm] = {
			"type": typ,
			"type2": DUAL_TYPE.get(nm, ""),
			"hp_stat": clampi(hp_stat, 1, 6),
			"atk": clampi(atk, 1, 6),
			"def": clampi(def_, 1, 6),
			"spd": clampi(spd, 1, 6),
			"stage": stage,
			"evolution": evo,
			"rarity": ["Basic", "Mid", "Final"][stage - 1],
			"sprite": SPRITE_OVERRIDE.get(dex_id, "Pokemon%d.png" % dex_id),
		}

func _stage(nm: String, parent: Dictionary) -> int:
	var s: int = 1
	var n: String = nm
	while parent.has(n):
		n = parent[n]
		s += 1
	return mini(s, 3)

# Split BONUS_POINTS across [hp, atk, def, spd] in proportion to the real
# base stats (largest-remainder method, so the total is always exactly +5).
const BONUS_POINTS := 5

func _bonus_split(base: Array) -> Array:
	var total := 0.0
	for v in base:
		total += float(v)
	if total <= 0.0:
		return [1, 2, 1, 1]
	var exact: Array = []
	var floors: Array = []
	var used := 0
	for v in base:
		var e: float = BONUS_POINTS * float(v) / total
		exact.append(e)
		floors.append(int(e))
		used += int(e)
	# hand the leftover points to the largest fractional remainders
	var order := [0, 1, 2, 3]
	order.sort_custom(func(a, b): return (exact[a] - floors[a]) > (exact[b] - floors[b]))
	for i in BONUS_POINTS - used:
		floors[order[i]] += 1
	return floors

# ─── Lookups ──────────────────────────────────────────────────────────────────

func get_spirit(spirit_name: String) -> Dictionary:
	if not SPIRITS.has(spirit_name):
		push_warning("SpiritsData: unknown spirit '%s'" % spirit_name)
		return {}
	var base: Dictionary = SPIRITS[spirit_name]
	var s: Dictionary = base.duplicate(true)
	s["name"] = spirit_name
	s["hp"] = 60 + int(base.get("hp_stat", 1)) * 30
	s["current_hp"] = s["hp"]
	s["stars"] = 0
	s["ability"] = pick_ability_for_type(base["type"], base.get("type2", ""))
	s["sprite_path"] = SPRITE_DIR + base["sprite"]
	return s

# The 7 starter spirits (one per trainer) are EXCLUSIVE — never found in the
# wild or in events, so only their trainer owns one. Legendaries are barred
# from the wild too; they appear ONLY through the legendary event.
const STARTER_NAMES := ["Charmander", "Squirtle", "Bulbasaur", "Pikachu", "Machop", "Gastly", "Abra"]
const LEGENDARY_NAMES := ["Articuno", "Zapdos", "Moltres", "Mewtwo", "Mew"]

# A random wild spirit of the given stage — never a starter or a legendary.
func random_spirit(stage: int = 1) -> Dictionary:
	var pool: Array = []
	for k in SPIRITS:
		if _wild_ok(k) and SPIRITS[k]["stage"] == stage:
			pool.append(k)
	if pool.is_empty():
		for k in SPIRITS:
			if _wild_ok(k):
				pool.append(k)
	return get_spirit(pool[randi() % pool.size()])

func _wild_ok(spirit_name: String) -> bool:
	return not STARTER_NAMES.has(spirit_name) and not LEGENDARY_NAMES.has(spirit_name)

# A random wild BASIC (stage 1), split by whether it can evolve:
#   evolving = true  → only basics that grow into a stage 2/3 (PINK / GREEN tiles)
#   evolving = false → only STANDALONE basics with no evolution (RED tiles)
func random_basic(evolving: bool) -> Dictionary:
	var pool: Array = []
	for k in SPIRITS:
		if _wild_ok(k) and int(SPIRITS[k].get("stage", 1)) == 1 \
				and (String(SPIRITS[k].get("evolution", "")) != "") == evolving:
			pool.append(k)
	if pool.is_empty():
		return random_spirit(1)   # fallback: any basic
	return get_spirit(pool[randi() % pool.size()])

# A random legendary — only used by the legendary event.
func random_legendary() -> Dictionary:
	return get_spirit(LEGENDARY_NAMES[randi() % LEGENDARY_NAMES.size()])

# "★2" or "★1.5" — stars can be earned in halves from battles.
func star_text(stars: float) -> String:
	if absf(stars - roundf(stars)) < 0.01:
		return "★%d" % int(roundf(stars))
	return "★%.1f" % stars

func sprite_for(spirit_name: String) -> Texture2D:
	if SPIRITS.has(spirit_name):
		return load(SPRITE_DIR + SPIRITS[spirit_name]["sprite"]) as Texture2D
	return null

# A single frame from a spirit's sheet. view: front / front_shiny / back /
# back_shiny / icon. Used so each screen can show a different pose.
func sprite_tex(spirit_name: String, view: String = "front") -> Texture2D:
	var sheet: Texture2D = sprite_for(spirit_name)
	if sheet == null:
		return null
	var at := AtlasTexture.new()
	at.atlas = sheet
	at.region = SHEET_REGIONS.get(view, SHEET_REGIONS["front"])
	return at

# ─── Type / ability helpers ───────────────────────────────────────────────────

func type_mult(att_type: String, def_type: String) -> float:
	return TYPE_CHART.get(att_type, {}).get(def_type, 1.0)

# Effectiveness of an attack against a whole spirit — a DUAL-type defender is
# checked against BOTH its types (their multipliers combine), so it can have two
# weaknesses (e.g. 1.5 × 1.5) or double-resist (0.5 × 0.5).
func effectiveness(att_type: String, defender: Dictionary) -> float:
	var m: float = type_mult(att_type, String(defender.get("type", "")))
	var t2: String = String(defender.get("type2", ""))
	if t2 != "":
		m *= type_mult(att_type, t2)
	return m

# Legendaries are the hardest catch (one winning number) regardless of stage.
func is_legendary(spirit_name: String) -> bool:
	return LEGENDARY_NAMES.has(spirit_name)

func strong_against(type: String) -> Array:
	var out: Array = []
	for d in TYPE_CHART.get(type, {}):
		if TYPE_CHART[type][d] > 1.0:
			out.append(d)
	return out

func weak_against(type: String) -> Array:
	var out: Array = []
	for d in TYPE_CHART.get(type, {}):
		if TYPE_CHART[type][d] < 1.0:
			out.append(d)
	return out

func type_color(type: String) -> Color:
	return TYPE_COLORS.get(type, Color.WHITE)

func ability_of(key: String) -> Dictionary:
	return ABILITY_DATA.get(key, {"name": key, "cat": "", "desc": ""})

# The ability pool for a type — or the MERGED pool when a second type is
# given (dual types draw from both).
func _pool_of(ptype: String, ptype2: String = "") -> Array:
	var pool: Array = TYPE_ABILITY_POOLS.get(ptype, []).duplicate()
	for a in TYPE_ABILITY_POOLS.get(ptype2, []):
		if not pool.has(a):
			pool.append(a)
	return pool

func pick_ability_for_type(ptype: String, ptype2: String = "") -> String:
	var pool: Array = _pool_of(ptype, ptype2)
	if pool.is_empty():
		return ""
	return pool[randi() % pool.size()]

# Up to `count` distinct abilities from a type's pool (both pools for duals),
# skipping any excluded (already-held) keys. Shuffled, so the player is
# offered a fresh set each time.
func ability_options(ptype: String, exclude: Array, count: int, ptype2: String = "") -> Array:
	var pool: Array = _pool_of(ptype, ptype2)
	pool = pool.filter(func(a): return not exclude.has(a))
	pool.shuffle()
	return pool.slice(0, mini(count, pool.size()))

# A random ability from a type's pool (both pools for duals), skipping any the
# spirit already holds. Falls back to the full pool, or "" if none exist.
func random_ability_for_type(ptype: String, exclude: Array = [], ptype2: String = "") -> String:
	var pool: Array = _pool_of(ptype, ptype2)
	if pool.is_empty():
		return ""
	var choices: Array = pool.filter(func(a): return not exclude.has(a))
	if choices.is_empty():
		choices = pool
	return choices[randi() % choices.size()]

# "Fire" or "Fire/Dark" — for type labels in menus.
func type_text(s: Dictionary) -> String:
	var t2 := String(s.get("type2", ""))
	if t2 != "":
		return "%s/%s" % [s.get("type", ""), t2]
	return String(s.get("type", ""))

func all_names() -> Array:
	return SPIRITS.keys()
