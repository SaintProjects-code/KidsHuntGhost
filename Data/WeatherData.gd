extends RefCounted
## Weather: set by events (or the Weather Charm card) and lasts 2 full rounds.
## Each kind boosts two types' damage +25% (and weakens one by 25%) and has
## its own extra effect in battle and on the board. GameState holds the
## current weather; this holds the rules. Use via preload (no class_name).

const ROUNDS := 2
const BOOST := 1.25
const WEAKEN := 0.75
const MIST_MISS := 0.2          # chance an attack misses in the mist
const STORM_BOLT_CHANCE := 0.4  # per battle round: lightning hits a fighter
const STORM_BOLT_PCT := 0.10    # … for this share of its max HP
const SAND_TICK_PCT := 0.06     # per battle round, every fighter
const BOARD_BOLT_CHANCE := 0.3  # at each turn start, lightning hits a spirit on the board
const BOARD_BOLT_DMG := 15

const KINDS := {
	"storm": {"name": "Storm", "icon": "⛈", "boost": ["Water", "Electric"], "weak": ["Fire"], "immune": ["Water", "Electric"],
		"desc": "Water & Electric hit 25% harder, Fire 25% softer. Lightning strikes random spirits — in battle and on the board."},
	"sun": {"name": "Blazing Sun", "icon": "☀", "boost": ["Fire", "Grass"], "weak": ["Water"], "immune": ["Fire", "Grass"],
		"desc": "Fire & Grass hit 25% harder, Water 25% softer. The heat saps everyone else (ATK −1 in battle). Catching is easier (+1)."},
	"mist": {"name": "Ghost Mist", "icon": "🌫", "boost": ["Psychic", "Dark"], "weak": ["Fighting"], "immune": ["Psychic", "Dark"],
		"desc": "Psychic & Dark hit 25% harder, Fighting 25% softer. Attacks miss 20% of the time. Wild spirits are stronger."},
	"sand": {"name": "Sandstorm", "icon": "🏜", "boost": ["Fighting"], "weak": ["Electric"], "immune": ["Fighting"],
		"desc": "Fighting hits 25% harder, Electric 25% softer. Sand whips every fighter each round. Everyone moves 1 less."},
}

static func info(kind: String) -> Dictionary:
	return KINDS.get(kind, {})

static func current() -> String:
	return GameState.weather

static func is_on(kind: String) -> bool:
	return GameState.weather == kind

# A spirit shrugs off its weather's side effects when it's one of the boosted types.
static func immune(mon: Dictionary) -> bool:
	var w := info(GameState.weather)
	if w.is_empty():
		return true
	return w["immune"].has(String(mon.get("type", ""))) or w["immune"].has(String(mon.get("type2", "")))

# Damage multiplier for an attacker in the current weather.
static func damage_mult(att: Dictionary) -> float:
	var w := info(GameState.weather)
	if w.is_empty():
		return 1.0
	var types := [String(att.get("type", "")), String(att.get("type2", ""))]
	for t in types:
		if w["boost"].has(t):
			return BOOST
	for t in types:
		if w["weak"].has(t):
			return WEAKEN
	return 1.0

# The weather that suits a type (A Legend Stirs, CPU Weather Charm picks).
static func for_type(type: String) -> String:
	for k in KINDS:
		if KINDS[k]["boost"].has(type):
			return k
	return KINDS.keys().pick_random()

static func label() -> String:
	var w := info(GameState.weather)
	if w.is_empty():
		return ""
	var left := GameState.weather_rounds_left()
	return "%s %s — %d round%s left" % [w["icon"], w["name"], left, "" if left == 1 else "s"]
