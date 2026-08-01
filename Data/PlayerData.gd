class_name PlayerData
extends Resource

class Progress:
	# Named badges — readable anywhere
	var badges := {
		"boulder": false, "fog":     false,
		"marsh":   false, "rain":    false,
		"soul":    false, "earth":   false,
		"volt":    false,
	}
	var defeated_gyms: Array[String] = []
	var elite_four: int = 0
	var gary_defeated: bool = false
	var points: int = 0

	func badge_count() -> int:
		return badges.values().count(true)

	func has_all_badges() -> bool:
		return badges.values().all(func(b): return b)

class Inventory:
	const MAX_ITEM_KINDS := 7   # distinct item types the bag can hold
	const MAX_STACK := 5        # copies of one item type per stack

	# Each entry: {"name", "kind", "amount", "count"} — one entry per item
	# type, stacked via "count".
	var items: Array = []
	var gold: int = 0
	var balls := { &"spirit_ball": 5 }   # ball type -> count (used when catching)
	var battle_item: StringName = &""
	var battle_item_2: StringName = &""

	# Add one copy of `item` to the bag. Returns false if the bag is full
	# (7 kinds) or that item's stack is maxed (×5).
	func add_item(item: Dictionary) -> bool:
		var nm: String = item.get("name", "Item")
		for e in items:
			if e.get("name", "") == nm:
				if int(e.get("count", 1)) >= MAX_STACK:
					return false
				e["count"] = int(e.get("count", 1)) + 1
				return true
		if items.size() >= MAX_ITEM_KINDS:
			return false
		var entry: Dictionary = item.duplicate(true)
		entry["count"] = 1
		items.append(entry)
		return true

	# Remove one copy; drops the entry when its stack hits zero.
	func consume_item(entry: Dictionary) -> void:
		entry["count"] = int(entry.get("count", 1)) - 1
		if int(entry["count"]) <= 0:
			items.erase(entry)

	func ball_count(ball: StringName) -> int:
		return balls.get(ball, 0)

	func total_balls() -> int:
		var n := 0
		for c in balls.values():
			n += c
		return n

class Movement:
	var board_position: int = 0
	var active_bike: bool = false
	var active_trap_space: int = -1

var player_name: String = ""
var trainer_key: String = ""    # trainer sprite key (e.g. "red"); "" → derive from name
var color: Color = Color.WHITE  # token tint, assigned per player in setup
# Event-tile status effect: ATK delta applied to the NEXT battle only
# (+1 = blessed, -1 = spooked). Consumed when that battle starts.
var next_battle_mod: int = 0
var pvp_tag: bool = false       # earned by reaching Cobweb City (C): unlocks PvP clashes
var is_cpu: bool = false
var cpu_difficulty: int = 0
# CPU momentum meter (signed): a gym/trainer/E4 loss drops it, a win raises it.
# Negative = struggling → train on wild SP fights, avoid gyms. Positive =
# winning → chase gyms (and, via badges, the Elite Four).
var cpu_momentum: int = 0
var team: Array = []
var pc: Array = []
var progress := Progress.new()
var inventory := Inventory.new()
var movement := Movement.new()

# True only if the team is FULL (6) and HEALTHY — every member alive and above
# half HP. A CPU won't commit to Victory Road until this holds.
func team_ready_for_victory() -> bool:
	if team.size() < 6:
		return false
	for m in team:
		var hp: int = int(m.get("current_hp", 0))
		if hp <= 0 or hp * 2 < int(m.get("hp", 1)):
			return false
	return true
