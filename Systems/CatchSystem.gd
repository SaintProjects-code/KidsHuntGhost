extends Node
## Dice catch. Each wild spirit has a set of winning d6 faces — its "catch
## numbers" (e.g. a Mankey might be {1, 3, 4}). A throw rolls 1d6; landing on a
## winning number catches it. Rarer spirits have fewer winning numbers:
##   basic → 3 numbers,  stage 2 → 2,  stage 3 / legendary → 1.
## A Spirit Ball adds one random UNUSED winning number for that throw; a Master
## Ball auto-catches. Beating the spirit in a fight adds +2 permanent numbers.
## Each player gets MAX_TRIES throws before the spirit runs away.

const TEAM_MAX := 6
const DIE := 6
const MAX_TRIES := 2

func _ready() -> void:
	EventBus.catch_attempted.connect(_on_catch_attempted)

# How many winning numbers a fresh wild spirit gets.
func base_catch_count(spirit: Dictionary) -> int:
	if SpiritsData.is_legendary(String(spirit.get("name", ""))):
		return 1
	match int(spirit.get("stage", 1)):
		1: return 3
		2: return 2
		_: return 1

# Ensure the spirit has rolled its random winning numbers (once per encounter).
func ensure_catch_numbers(spirit: Dictionary) -> Array:
	if not spirit.has("catch_numbers"):
		spirit["catch_numbers"] = _pick_faces([], base_catch_count(spirit))
	return spirit["catch_numbers"]

# Permanently add `count` random unused winning faces (the fight bonus).
func add_catch_numbers(spirit: Dictionary, count: int) -> Array:
	spirit["catch_numbers"] = _pick_faces(ensure_catch_numbers(spirit), count)
	return spirit["catch_numbers"]

# `existing` plus up to `count` more distinct faces from 1..DIE, sorted.
func _pick_faces(existing: Array, count: int) -> Array:
	var avail: Array = []
	for f in range(1, DIE + 1):
		if not existing.has(f):
			avail.append(f)
	avail.shuffle()
	var out: Array = existing.duplicate()
	for f in avail.slice(0, maxi(0, count)):
		out.append(f)
	out.sort()
	return out

func _on_catch_attempted(player_idx: int, spirit: Dictionary, ball: StringName) -> void:
	ensure_catch_numbers(spirit)
	if ball == &"master_ball":
		spirit["_roll"] = 0   # 0 = auto-catch, no roll
		spirit["_throw_numbers"] = spirit["catch_numbers"]
		_succeed(player_idx, spirit)
		return
	# A Spirit Ball adds one unused winning number for THIS throw only.
	var winning: Array = (spirit["catch_numbers"] as Array).duplicate()
	if ball == &"spirit_ball":
		winning = _pick_faces(winning, 1)
	var roll: int = randi_range(1, DIE)
	spirit["_roll"] = roll
	spirit["_throw_numbers"] = winning
	if winning.has(roll):
		_succeed(player_idx, spirit)
	else:
		spirit["catch_tries"] = int(spirit.get("catch_tries", 0)) + 1
		EventBus.emit_signal("catch_failed", player_idx, spirit)

func _succeed(player_idx: int, spirit: Dictionary) -> void:
	var p := GameState.players[player_idx]
	spirit["current_hp"] = spirit["hp"]
	spirit["stars"] = 0
	# Full team (6) → the catch is stored in the PC (withdraw at any town).
	if p.team.size() < TEAM_MAX:
		p.team.append(spirit)
	else:
		p.pc.append(spirit)
	# SpiritsProgressionSystem subscribes and handles duplicates / stars. Emitted
	# BEFORE the cleanup below so the catch window can still read the winning roll.
	EventBus.emit_signal("catch_succeeded", player_idx, spirit)
	GameState.award_points(player_idx, 1)
	p.inventory.gold += 10   # catch bounty
	EventBus.log_entry.emit(player_idx, "%s caught %s! +10 gold." % [
		p.player_name, spirit.get("name", "?")], "#f0c36a")
	# strip the encounter-only bookkeeping now that it's on the team
	for k in ["catch_numbers", "catch_tries", "_roll", "_throw_numbers", "fought"]:
		spirit.erase(k)
