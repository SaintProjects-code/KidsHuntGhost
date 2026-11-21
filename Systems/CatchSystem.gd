extends Node
## Autoloaded. Catching a wild ghost is a dice roll:
##   roll 1 free die + 1 die per Spirit Lantern (+2 per Grand Lantern), add
##   them up (+2 if it was lured) and meet the ghost's target. A Soul Lantern
##   is a sure catch. Two tries per ghost; each miss raises the target.
## The catch window animates the dice; this owns the maths and the outcome.
## A catch pays points + gold and gives your lead stars.

func _ready() -> void:
	EventBus.catch_attempted.connect(_on_catch_attempted)

# The number the dice total has to reach.
static func target_for(spirit: Dictionary) -> int:
	var base: int = Balance.LEGEND_TARGET if SpiritsData.is_legendary(String(spirit.get("name", ""))) \
		else int(Balance.CATCH_TARGET.get(int(spirit.get("stage", 1)), 8))
	return base + int(spirit.get("catch_fails", 0)) * Balance.CATCH_FAIL_PENALTY

# The fewest dice that can reach the target at all (6 per die).
static func min_dice(spirit: Dictionary) -> int:
	return maxi(1, ceili(float(target_for(spirit) - bonus_for(spirit)) / 6.0))

static func bonus_for(spirit: Dictionary) -> int:
	var b := Balance.CATCH_LURE_BONUS if spirit.get("_lured", false) else 0
	if GameState.weather == "sun":   # ☀ Blazing Sun: catching is easier
		b += 1
	return b

# Dice rolled for a set of Lantern cards (the free die included).
static func dice_for(lanterns: Array) -> int:
	var n := 1
	for k in lanterns:
		n += int(CardsData.card(k).get("dice", 0))
	return n

static func is_sure(lanterns: Array) -> bool:
	return lanterns.has("soul_lantern")

# Chance in percent that the roll catches it.
static func chance(spirit: Dictionary, lanterns: Array) -> int:
	if is_sure(lanterns):
		return 100
	return int(round(sum_at_least(dice_for(lanterns), target_for(spirit) - bonus_for(spirit)) * 100.0))

# P(sum of n six-sided dice ≥ need), counted exactly.
static func sum_at_least(n: int, need: int) -> float:
	var ways := {0: 1.0}
	for d in n:
		var next := {}
		for total in ways:
			for f in range(1, 7):
				next[total + f] = float(next.get(total + f, 0.0)) + ways[total]
		ways = next
	var hit := 0.0
	for total in ways:
		if total >= need:
			hit += ways[total]
	return hit / pow(6.0, n)

# The window rolls first (so it can animate the dice) and stores the total in
# spirit["_roll"]; a missing total is rolled here (silent paths).
func _on_catch_attempted(player_idx: int, spirit: Dictionary, lanterns: Array) -> void:
	var total: int = int(spirit.get("_roll", -1))
	if total < 0:
		total = 0
		for d in dice_for(lanterns):
			total += randi_range(1, 6)
	spirit.erase("_roll")
	if is_sure(lanterns) or total + bonus_for(spirit) >= target_for(spirit):
		_succeed(player_idx, spirit)
	else:
		spirit["catch_fails"] = int(spirit.get("catch_fails", 0)) + 1
		EventBus.catch_failed.emit(player_idx, spirit)

func _succeed(player_idx: int, spirit: Dictionary) -> void:
	var p: PlayerData = GameState.players[player_idx]
	for k in ["catch_fails", "_lured"]:
		spirit.erase(k)
	spirit["current_hp"] = spirit["hp"]
	spirit["stars"] = 0
	# Full team → the catch goes to the Spirit Box (withdraw at any town).
	if p.team.size() < Balance.TEAM_MAX:
		p.team.append(spirit)
	else:
		p.pc.append(spirit)
	# SpiritsProgressionSystem subscribes and handles duplicates / stars
	EventBus.catch_succeeded.emit(player_idx, spirit)
	if Balance.PTS_CATCH > 0:
		GameState.award_points(player_idx, Balance.PTS_CATCH)
	p.inventory.gold += Balance.GOLD_CATCH
	EventBus.log_entry.emit(player_idx, "%s caught %s! +%d gold." % [
		p.player_name, spirit.get("name", "?"), Balance.GOLD_CATCH], "#f0c36a")
	# the hunt levels your lead up (a duplicate catch already gave its star)
	var lead: Dictionary = p.lead()
	if not lead.is_empty() and lead != spirit:
		var stars: float = Balance.CATCH_LEAD_STARS_STRONG if int(spirit.get("stage", 1)) >= 2 else Balance.CATCH_LEAD_STARS
		SpiritsProgressionSystem.award_stars(player_idx, lead, stars)
