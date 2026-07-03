extends Node
## Spirit (Pokémon) database. Autoloaded as `SpiritsData`.
##
## get_spirit(name) -> fresh battle-ready dict:
##   name, type, hp, current_hp, hp_stat, atk, def, spd, stage, stars,
##   evolution, ability, rarity, sprite_path
##
## Scale:  hp = 30 + hp_stat×30 (tier 1=60 … 6=210).  atk/def/spd are 1–6 tiers.
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
const TYPE_CHART := {
	"Fire":     {"Grass": 2.0,    "Water": 0.5},
	"Water":    {"Fire": 2.0,     "Electric": 0.5},
	"Grass":    {"Electric": 2.0, "Fire": 0.5},
	"Electric": {"Water": 2.0,    "Grass": 0.5},
	"Dark":     {"Psychic": 2.0,  "Fighting": 0.5},
	"Psychic":  {"Fighting": 2.0, "Dark": 0.5},
	"Fighting": {"Dark": 2.0,     "Psychic": 0.5},
}

const TYPE_COLORS := {
	"Fire": Color("e8623a"), "Water": Color("4aa3df"), "Grass": Color("4caf50"),
	"Electric": Color("f4d03f"), "Dark": Color("8e6fd6"), "Psychic": Color("e86fb0"),
	"Fighting": Color("d06a3a"),
}

# ─── Abilities (ported from the reference game) ───────────────────────────────
const ABILITY_DATA := {
	"intimidate":    {"name":"Intimidate",    "cat":"Match Start", "desc":"Match start: opponent team loses -2 ATK"},
	"drought":       {"name":"Drought",       "cat":"Round Start · Lead", "desc":"Round start: your whole team gains +1 ATK"},
	"thunder_wave":  {"name":"Thunder Wave",  "cat":"Match Start", "desc":"Match start: Stun the opponent lead for 2 rounds"},
	"veteran":       {"name":"Veteran",       "cat":"Match Start", "desc":"Match start: 2+ stars: +2 ATK and immune to status"},
	"screech":       {"name":"Screech",       "cat":"Match Start", "desc":"Match start: opponent lead loses -2 DEF"},
	"spikes":        {"name":"Spikes",        "cat":"Match Start", "desc":"Match start: each opponent takes 30 dmg on first entry"},
	"confuse_ray":   {"name":"Confuse Ray",   "cat":"Match Start", "desc":"Match start: Confuse the opponent lead 2–3 rounds"},
	"tailwind":      {"name":"Tailwind",      "cat":"Match Start", "desc":"Match start: your whole team gains +3 SPD"},
	"speed_boost":   {"name":"Speed Boost",   "cat":"Match Start", "desc":"Match start: your team gains +1 SPD and +1 ATK"},
	"taunt":         {"name":"Taunt",         "cat":"Match Start", "desc":"Match start: opponent cannot heal or inflict status"},
	"sniper":        {"name":"Sniper",        "cat":"Match Start", "desc":"Match start: deal 25×(ATK/2) to a random opponent"},
	"fire_bond":     {"name":"Fire Bond",     "cat":"Match Start", "desc":"Match start: +2 ATK per Fire ally; team +1 DEF"},
	"water_bond":    {"name":"Water Bond",    "cat":"Match Start", "desc":"Match start: +1 ATK per Water ally; team +3 DEF"},
	"grass_bond":    {"name":"Grass Bond",    "cat":"Match Start", "desc":"Match start: +1 ATK per Grass ally; team +2 HP Tier"},
	"electric_bond": {"name":"Electric Bond", "cat":"Match Start", "desc":"Match start: +1 ATK per Electric ally; team +3 SPD"},
	"fighting_bond": {"name":"Fighting Bond", "cat":"Match Start", "desc":"Match start: +3 ATK per Fighting ally"},
	"psychic_bond":  {"name":"Psychic Bond",  "cat":"Match Start", "desc":"Match start: +1 ATK per Psychic ally; team immune to status"},
	"dark_bond":     {"name":"Dark Bond",     "cat":"Match Start", "desc":"Match start: +1 ATK per Dark ally; opponent team -2 DEF"},
	"u_turn":        {"name":"U-Turn",        "cat":"Match Start · Lead", "desc":"Match start: hit the lead, then switch out (ally +1 ATK)"},
	"wish":          {"name":"Wish",          "cat":"Round Start", "desc":"Round start: heal all team Pokémon 20 HP"},
	"regenerator":   {"name":"Regenerator",   "cat":"Round Start", "desc":"Round start: heal 30% max HP; if full, +1 ATK (max 3)"},
	"medic":         {"name":"Medic",         "cat":"Round Start · Once", "desc":"Round start: 30% to revive a downed ally to 25% HP"},
	"leech_seed":    {"name":"Leech Seed",    "cat":"Round Start · Lead", "desc":"Round start: drain 10 HP from the lead (2× if statused)"},
	"berserker":     {"name":"Berserker",     "cat":"Round Start · Lead", "desc":"Round start: +2 ATK, lose 20 HP"},
	"drain_punch":   {"name":"Drain Punch",   "cat":"Round Start · Lead", "desc":"Round start: deal 50% ATK to the lead and heal half"},
	"healer":        {"name":"Healer",        "cat":"Round Start", "desc":"Round start: heal the lead 40 HP (not while leading)"},
	"dynasty":       {"name":"Dynasty",       "cat":"Round Start · Lead", "desc":"Round start: heal 20 HP while leading"},
	"helping_hand":  {"name":"Helping Hand",  "cat":"Passive", "desc":"If lead drops below 45% HP, swap in and soak the hit"},
	"vengeance":     {"name":"Vengeance",     "cat":"Passive", "desc":"When any ally faints, deal 2× ATK to the lead"},
	"encore":        {"name":"Encore",        "cat":"Passive", "desc":"Lead: opponent's ability suppressed for 3 rounds"},
	"static":        {"name":"Static",        "cat":"Passive · Lead", "desc":"30% to Stun the attacker when hit"},
	"poison_point":  {"name":"Poison Point",  "cat":"Passive · Lead", "desc":"Poison the attacker when hit"},
	"flame_body":    {"name":"Flame Body",    "cat":"Passive · Lead", "desc":"Burn the attacker when hit"},
	"thick_fat":     {"name":"Thick Fat",     "cat":"Passive · Lead", "desc":"All incoming damage reduced by 20%"},
	"thief":         {"name":"Thief",         "cat":"Passive · Lead", "desc":"On hit: steal +1 ATK (max 3×)"},
	"moxie":         {"name":"Moxie",         "cat":"Passive · Lead", "desc":"On KO: gain +2 ATK"},
	"battle_armor":  {"name":"Battle Armor",  "cat":"Passive · Lead", "desc":"Lead: incoming damage halved for the first 2 rounds"},
	"grit":          {"name":"Grit",          "cat":"Passive · Lead", "desc":"Below 30% HP: incoming damage reduced by 30%"},
	"counter":       {"name":"Counter",       "cat":"Passive · Lead", "desc":"When hit for 50+: deal back 40% of that damage"},
	"sturdy":        {"name":"Sturdy",        "cat":"Passive · Lead · Once", "desc":"Survive one KO per battle at 1 HP"},
	"hypnosis":      {"name":"Hypnosis",      "cat":"Passive · Lead · Once", "desc":"Lead: opponent falls Asleep"},
	"all_for_one":   {"name":"All For One",   "cat":"Passive · Lead · Once", "desc":"Lead: if your only Pokémon, +3 ATK/DEF/SPD"},
	"reflect":       {"name":"Reflect",       "cat":"Passive · Lead · Once", "desc":"Lead: your whole team gains +2 DEF"},
	"shell_smash":   {"name":"Shell Smash",   "cat":"Passive · Lead · Once", "desc":"Lead: DEF -3, ATK +3, SPD +1"},
	"explosion":     {"name":"Explosion",     "cat":"Passive · Lead · Once", "desc":"On faint: deal 60% max HP as damage"},
	"destiny_bond":  {"name":"Destiny Bond",  "cat":"Passive · Lead · Once", "desc":"On faint: the killer also faints"},
	"anger_point":   {"name":"Anger Point",   "cat":"Passive · Lead · Once", "desc":"On a KO blow: survive at 1 HP and gain +3 ATK"},
	"multiscale":    {"name":"Multiscale",    "cat":"Passive · Lead · Once", "desc":"Lead: if full HP, take 50% less from the first hit"},
	"overgrow":      {"name":"Overgrow",      "cat":"Passive · Lead · Once", "desc":"Below 50% HP: +2 ATK and +1 DEF for the battle"},
	"blaze":         {"name":"Blaze",         "cat":"Passive · Lead · Once", "desc":"Below 33% HP: permanently +4 ATK and +2 SPD"},
	"flash_fire":    {"name":"Flash Fire",    "cat":"Passive · Lead", "desc":"25% when hit: negate damage and gain +2 ATK"},
	"volt_absorb":   {"name":"Volt Absorb",   "cat":"Passive · Lead", "desc":"35% when hit: absorb the damage as HP"},
	"soul_heart":    {"name":"Soul Heart",    "cat":"Passive · Lead", "desc":"On KO: gain +1 ATK and +1 DEF (stacks)"},
	"bulwark":       {"name":"Bulwark",       "cat":"Passive · Lead", "desc":"Lead: +2 DEF while above 50% HP"},
	"fortress":      {"name":"Fortress",      "cat":"Passive · Lead", "desc":"Lead: +1 DEF per round survived (max +3)"},
	"iron_will":     {"name":"Iron Will",     "cat":"Round Start · Lead", "desc":"Round start: if full HP, gain +1 ATK"},
	"monument":      {"name":"Monument",      "cat":"Match Start", "desc":"Match start: if your last Pokémon, +3 to all stats"},
	"reckless":      {"name":"Reckless",      "cat":"Passive · Lead", "desc":"Deal +25% damage but take +15% damage"},
	"spore":         {"name":"Spore",         "cat":"Passive · Lead", "desc":"When hit: inflict a random status on the attacker"},
}

const TYPE_ABILITY_POOLS := {
	"Fire":     ["drought", "fire_bond", "moxie", "sniper", "explosion", "flame_body", "berserker", "shell_smash", "blaze", "flash_fire", "reckless"],
	"Water":    ["thick_fat", "sturdy", "u_turn", "water_bond", "multiscale", "bulwark", "wish", "reflect", "drain_punch", "static"],
	"Grass":    ["leech_seed", "poison_point", "screech", "spikes", "wish", "healer", "medic", "grass_bond", "drain_punch", "overgrow", "spore"],
	"Electric": ["thunder_wave", "electric_bond", "speed_boost", "soul_heart", "anger_point", "static", "berserker", "volt_absorb"],
	"Psychic":  ["hypnosis", "confuse_ray", "encore", "psychic_bond", "helping_hand", "reflect", "wish", "destiny_bond"],
	"Fighting": ["veteran", "intimidate", "fighting_bond", "battle_armor", "monument", "fortress", "iron_will", "berserker", "drain_punch", "all_for_one", "grit", "counter"],
	"Dark":     ["thief", "taunt", "vengeance", "dynasty", "dark_bond", "destiny_bond", "poison_point"],
}

const HIDDEN_ABILITY_BY_TYPE := {
	"Fire": "berserker", "Water": "shell_smash", "Grass": "regenerator",
	"Electric": "all_for_one", "Psychic": "drain_punch", "Fighting": "reflect", "Dark": "destiny_bond",
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
	[10,"Caterpie","Grass","Metapod"], [11,"Metapod","Grass","Butterfree"], [12,"Butterfree","Grass",""],
	[13,"Weedle","Grass","Kakuna"], [14,"Kakuna","Grass","Beedrill"], [15,"Beedrill","Grass",""],
	[16,"Pidgey","Fighting","Pidgeotto"], [17,"Pidgeotto","Fighting","Pidgeot"], [18,"Pidgeot","Fighting",""],
	[19,"Rattata","Dark","Raticate"], [20,"Raticate","Dark",""],
	[21,"Spearow","Fighting","Fearow"], [22,"Fearow","Fighting",""],
	[23,"Ekans","Grass","Arbok"], [24,"Arbok","Grass",""],
	[25,"Pikachu","Electric","Raichu"], [26,"Raichu","Electric",""],
	[27,"Sandshrew","Fighting","Sandslash"], [28,"Sandslash","Fighting",""],
	[29,"Nidoran-F","Grass","Nidorina"], [30,"Nidorina","Grass","Nidoqueen"], [31,"Nidoqueen","Grass",""],
	[32,"Nidoran-M","Grass","Nidorino"], [33,"Nidorino","Grass","Nidoking"], [34,"Nidoking","Grass",""],
	[35,"Clefairy","Psychic","Clefable"], [36,"Clefable","Psychic",""],
	[37,"Vulpix","Fire","Ninetales"], [38,"Ninetales","Fire",""],
	[39,"Jigglypuff","Psychic","Wigglytuff"], [40,"Wigglytuff","Psychic",""],
	[41,"Zubat","Dark","Golbat"], [42,"Golbat","Dark",""],
	[43,"Oddish","Grass","Gloom"], [44,"Gloom","Grass","Vileplume"], [45,"Vileplume","Grass",""],
	[46,"Paras","Grass","Parasect"], [47,"Parasect","Grass",""],
	[48,"Venonat","Grass","Venomoth"], [49,"Venomoth","Grass",""],
	[50,"Diglett","Fighting","Dugtrio"], [51,"Dugtrio","Fighting",""],
	[52,"Meowth","Dark","Persian"], [53,"Persian","Dark",""],
	[54,"Psyduck","Water","Golduck"], [55,"Golduck","Water",""],
	[56,"Mankey","Fighting","Primeape"], [57,"Primeape","Fighting",""],
	[58,"Growlithe","Fire","Arcanine"], [59,"Arcanine","Fire",""],
	[60,"Poliwag","Water","Poliwhirl"], [61,"Poliwhirl","Water","Poliwrath"], [62,"Poliwrath","Water",""],
	[63,"Abra","Psychic","Kadabra"], [64,"Kadabra","Psychic","Alakazam"], [65,"Alakazam","Psychic",""],
	[66,"Machop","Fighting","Machoke"], [67,"Machoke","Fighting","Machamp"], [68,"Machamp","Fighting",""],
	[69,"Bellsprout","Grass","Weepinbell"], [70,"Weepinbell","Grass","Victreebel"], [71,"Victreebel","Grass",""],
	[72,"Tentacool","Water","Tentacruel"], [73,"Tentacruel","Water",""],
	[74,"Geodude","Fighting","Graveler"], [75,"Graveler","Fighting","Golem"], [76,"Golem","Fighting",""],
	[77,"Ponyta","Fire","Rapidash"], [78,"Rapidash","Fire",""],
	[79,"Slowpoke","Water","Slowbro"], [80,"Slowbro","Water",""],
	[81,"Magnemite","Electric","Magneton"], [82,"Magneton","Electric",""],
	[83,"Farfetch'd","Fighting",""],
	[84,"Doduo","Fighting","Dodrio"], [85,"Dodrio","Fighting",""],
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
	[113,"Chansey","Psychic",""], [114,"Tangela","Grass",""], [115,"Kangaskhan","Fighting",""],
	[116,"Horsea","Water","Seadra"], [117,"Seadra","Water",""],
	[118,"Goldeen","Water","Seaking"], [119,"Seaking","Water",""],
	[120,"Staryu","Water","Starmie"], [121,"Starmie","Water",""],
	[122,"Mr. Mime","Psychic",""], [123,"Scyther","Grass",""], [124,"Jynx","Psychic",""],
	[125,"Electabuzz","Electric",""], [126,"Magmar","Fire",""], [127,"Pinsir","Grass",""], [128,"Tauros","Fighting",""],
	[129,"Magikarp","Water","Gyarados"], [130,"Gyarados","Water",""],
	[131,"Lapras","Water",""], [132,"Ditto","Psychic",""],
	[133,"Eevee","Psychic",""], [134,"Vaporeon","Water",""], [135,"Jolteon","Electric",""], [136,"Flareon","Fire",""],
	[137,"Porygon","Psychic",""],
	[138,"Omanyte","Water","Omastar"], [139,"Omastar","Water",""],
	[140,"Kabuto","Water","Kabutops"], [141,"Kabutops","Water",""],
	[142,"Aerodactyl","Fighting",""], [143,"Snorlax","Fighting",""],
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
		SPIRITS[nm] = {
			"type": typ,
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

# ─── Lookups ──────────────────────────────────────────────────────────────────

func get_spirit(spirit_name: String) -> Dictionary:
	if not SPIRITS.has(spirit_name):
		push_warning("SpiritsData: unknown spirit '%s'" % spirit_name)
		return {}
	var base: Dictionary = SPIRITS[spirit_name]
	var s: Dictionary = base.duplicate(true)
	s["name"] = spirit_name
	s["hp"] = 30 + int(base.get("hp_stat", 1)) * 30
	s["current_hp"] = s["hp"]
	s["stars"] = 0
	s["ability"] = pick_ability_for_type(base["type"])
	s["sprite_path"] = SPRITE_DIR + base["sprite"]
	return s

func random_spirit(stage: int = 1) -> Dictionary:
	var pool: Array = []
	for k in SPIRITS:
		if SPIRITS[k]["stage"] == stage:
			pool.append(k)
	if pool.is_empty():
		pool = SPIRITS.keys()
	return get_spirit(pool[randi() % pool.size()])

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

func strong_against(type: String) -> Array:
	var out: Array = []
	for d in TYPE_CHART.get(type, {}):
		if TYPE_CHART[type][d] >= 2.0:
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

func pick_ability_for_type(ptype: String) -> String:
	var pool: Array = TYPE_ABILITY_POOLS.get(ptype, [])
	if pool.is_empty():
		return ""
	return pool[randi() % pool.size()]

func all_names() -> Array:
	return SPIRITS.keys()
