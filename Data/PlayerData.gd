class_name PlayerData
extends RefCounted
## One player's whole state. to_dict()/from_dict() turn it into plain data for
## the save file (the inner classes aren't Resources, so they can't be saved
## directly — that's why saving used to lose badges, gold and items).

class Progress:
	var badges := {
		"cinder": false, "bayou": false,
		"cobweb": false, "dusk":  false,
		"echo":   false, "fog":   false,
		"ghoul":  false, "harbor": false,
	}
	var elite_wins: int = 0          # Haunted Four wins in a row on the Spectral Trail
	var champion_defeated: bool = false
	var points: int = 0

	func badge_count() -> int:
		return badges.values().count(true)

class Inventory:
	var gold: int = Balance.GOLD_START
	var hand: Array = []                             # card keys, max Balance.HAND_SIZE

	# Lantern (capture) cards in the hand.
	func lanterns() -> Array:
		return cards_of_kind("capture")

	func hand_full() -> bool:
		return hand.size() >= Balance.HAND_SIZE

	func has_card(key: String) -> bool:
		return hand.has(key)

	func cards_of_kind(kind: String) -> Array:
		return hand.filter(func(k): return CardsData.kind_of(k) == kind)

var player_name: String = ""
var trainer_key: String = ""    # trainer sprite key (e.g. "alain")
var color: Color = Color.WHITE  # token tint
var is_cpu: bool = false
var pvp_tag: bool = false       # earned by reaching Cobweb City (C): unlocks PvP clashes
var remote_id: String = ""      # 📱 the phone playing this seat ("" = keyboard / CPU), see Remote
var team: Array = []
var pc: Array = []              # the Spirit Box: spirits beyond the team of 6
var progress := Progress.new()
var inventory := Inventory.new()

# Short-lived effects from events and field cards.
var next_battle_mod: int = 0    # ATK +1 (blessed) / -1 (spooked) for the next battle only
var roll_bonus: int = 0         # Loaded Die
var extra_die: bool = false     # Twin Dice
var lure: bool = false          # Spooky Lure: next wild spirit is stronger + easier to catch
var salt: bool = false          # Salt Circle: ignore the next wild spirit / event
var skip_turns: int = 0         # turns to sit out (Quicksand, a Hex…)
var stolen: Array = []          # spirits the Grim Gang snatched — win them back at the hideout

# Running totals for the end-of-game stats (GameState counts them).
var stats: Dictionary = {}

func add_stat(key: String, amount: int = 1) -> void:
	stats[key] = int(stats.get(key, 0)) + amount

func stat(key: String) -> int:
	return int(stats.get(key, 0))

func living_team() -> Array:
	return team.filter(func(m): return int(m.get("current_hp", 0)) > 0)

func lead() -> Dictionary:
	return team[0] if not team.is_empty() else {}

# ── save / load ───────────────────────────────────────────────────────────────

func to_dict() -> Dictionary:
	return {
		"name": player_name, "trainer": trainer_key, "color": color, "cpu": is_cpu,
		"pvp_tag": pvp_tag, "team": team.duplicate(true), "pc": pc.duplicate(true),
		"badges": progress.badges.duplicate(), "elite_wins": progress.elite_wins,
		"champion": progress.champion_defeated, "points": progress.points,
		"gold": inventory.gold, "hand": inventory.hand.duplicate(),
		"battle_mod": next_battle_mod, "roll_bonus": roll_bonus, "extra_die": extra_die,
		"lure": lure, "salt": salt, "remote_id": remote_id, "stats": stats.duplicate(),
		"skip_turns": skip_turns, "stolen": stolen.duplicate(true),
	}

static func from_dict(d: Dictionary) -> PlayerData:
	var p := PlayerData.new()
	p.player_name = d.get("name", "")
	p.trainer_key = d.get("trainer", "")
	p.color = d.get("color", Color.WHITE)
	p.is_cpu = d.get("cpu", false)
	p.pvp_tag = d.get("pvp_tag", false)
	p.remote_id = d.get("remote_id", "")
	p.team = d.get("team", [])
	p.pc = d.get("pc", [])
	for k in d.get("badges", {}):
		if p.progress.badges.has(k):
			p.progress.badges[k] = d["badges"][k]
	p.progress.elite_wins = d.get("elite_wins", 0)
	p.progress.champion_defeated = d.get("champion", false)
	p.progress.points = d.get("points", 0)
	p.inventory.gold = d.get("gold", 0)
	p.inventory.hand = d.get("hand", [])
	p.next_battle_mod = d.get("battle_mod", 0)
	p.roll_bonus = d.get("roll_bonus", 0)
	p.extra_die = d.get("extra_die", false)
	p.lure = d.get("lure", false)
	p.salt = d.get("salt", false)
	p.stats = d.get("stats", {})
	p.skip_turns = int(d.get("skip_turns", 0))
	p.stolen = d.get("stolen", [])
	# old saves: spirits could stack a 2nd ability; now each has one
	for mon in p.team + p.pc:
		mon.erase("ability2")
	# old saves: charms used to be worn by spirits; now they're cards again
	for mon in p.team + p.pc:
		if mon.has("charm"):
			if not p.inventory.hand_full():
				p.inventory.hand.append(String(mon["charm"]))
			mon.erase("charm")
	return p
