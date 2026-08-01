extends Node
## Milestone "bonus reward" flow. SpiritsProgressionSystem calls
## `await BonusReward.run(idx, spirit, star_level)` for each WHOLE star a spirit
## crosses (1, 2, 3). EVERY spirit earns the same three bonuses in order:
##   1) swap its ability   2) +2 to a stat   3) add a stacking 2nd ability
## What differs is WHEN each lands, so the last always hits the final form at 3★:
##   • standalone (no evo) → bonus 1 / 2 / 3 at 1★ / 2★ / 3★
##   • 2-stage line        → bonus 1 on evolving (basic 3★), then 2★ and 3★
##   • 3-stage line        → bonus 1 & 2 on its two evolutions, bonus 3 at 3★
## Rule: an evolvable spirit delivers its stage's bonus when it evolves at 3★;
## a final form delivers bonus L at star L for every level from its stage up.

const MAX_ABILITIES := 2

var _win: Control

func _ready() -> void:
	# Bonus rewards pop mid-event (after battles) while the game is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	var layer := CanvasLayer.new()
	layer.layer = 20   # above the battle screen (12) and other pop-ups
	add_child(layer)
	_win = preload("res://Scenes/UI/BonusRewardWindow.gd").new()
	_win.hide()
	layer.add_child(_win)

# One milestone bonus for a spirit that just crossed `star_level` (1/2/3).
func run(player_idx: int, spirit: Dictionary, star_level: int) -> void:
	var has_evo: bool = String(spirit.get("evolution", "")) != ""
	var stage: int = int(spirit.get("stage", 1))
	if has_evo:
		# Only the 3-star evolution carries a bonus (this stage's level), then the
		# spirit grows into its next form.
		if star_level == 3:
			await _grant_level(player_idx, spirit, stage)
			_evolve(player_idx, spirit)
	elif star_level >= stage:
		# Final form: hand out the bonus for this star level. Levels below its
		# stage were already granted by the evolutions that produced it.
		await _grant_level(player_idx, spirit, star_level)

# Deliver bonus `level`: 1 = swap ability, 2 = +2 to a stat, 3 = add a 2nd
# ability. Every spirit walks this same 1 -> 2 -> 3 ladder over its lifetime.
func _grant_level(player_idx: int, spirit: Dictionary, level: int) -> void:
	var human: bool = not GameState.players[player_idx].is_cpu
	match level:
		1:
			await _reward_ability(player_idx, spirit, level, true, human)
		2:
			await _reward_stat(player_idx, spirit, level, human)
		3:
			await _reward_ability(player_idx, spirit, level, false, human)

# ── rewards ───────────────────────────────────────────────────────────────────

# lvl 1 replaces the primary ability; lvl 3 adds a second (stacking, cap 2).
func _reward_ability(player_idx: int, spirit: Dictionary, lvl: int, replace: bool, human: bool) -> void:
	var a1 := String(spirit.get("ability", ""))
	var a2 := String(spirit.get("ability2", ""))
	var held: Array = []
	if a1 != "":
		held.append(a1)
	if a2 != "":
		held.append(a2)
	var ptype := String(spirit.get("type", ""))
	var ptype2 := String(spirit.get("type2", ""))   # duals draw from both pools
	var new_ab: String
	if human:
		# Offer 4 abilities to choose from, each shown with its description.
		var options: Array = SpiritsData.ability_options(ptype, held, 4, ptype2)
		if options.is_empty():
			return
		_win.present_ability(spirit, lvl, options, a1 if replace else "")
		_win.show()
		new_ab = await _win.chose_ability
		_win.hide()
	else:
		new_ab = SpiritsData.random_ability_for_type(ptype, held, ptype2)
	if new_ab == "":
		# Player chose "Keep" (or no ability was available) — leave abilities as-is.
		EventBus.emit_signal("log_entry", player_idx,
			"%s kept its ability." % spirit.get("name", "?"), "#7fe0d0")
		return
	if replace or a1 == "":
		spirit["ability"] = new_ab   # lvl 1: swap the primary ability
	else:
		spirit["ability2"] = new_ab  # lvl 3: stack a second ability (cap 2)
	EventBus.emit_signal("log_entry", player_idx, "%s %s: %s" % [
		spirit.get("name", "?"),
		"swapped ability" if replace else "learned a 2nd ability",
		SpiritsData.ability_of(new_ab).get("name", new_ab)], "#7fe0d0")
	EventBus.emit_signal("star_awarded", player_idx, spirit)

func _reward_stat(player_idx: int, spirit: Dictionary, lvl: int, human: bool) -> void:
	var stat: String
	if human:
		_win.present_stat(spirit, lvl)
		_win.show()
		stat = await _win.chose_stat
		_win.hide()
	else:
		stat = ["hp", "atk", "def", "spd"][randi() % 4]
	if stat == "hp":
		spirit["hp"] = int(spirit.get("hp", 60)) + 60
		spirit["current_hp"] = int(spirit["hp"])
	else:
		spirit[stat] = clampi(int(spirit.get(stat, 1)) + 2, 1, 6)
	EventBus.emit_signal("log_entry", player_idx, "%s gained +2 %s!" % [
		spirit.get("name", "?"), stat.to_upper()], "#7fe0d0")
	EventBus.emit_signal("star_awarded", player_idx, spirit)

# ── evolution ─────────────────────────────────────────────────────────────────

# Force an evolution outside the star flow (e.g. an "evolve" event reward).
func evolve(player_idx: int, spirit: Dictionary) -> void:
	_evolve(player_idx, spirit)

# Turn `spirit` into its evolution IN PLACE: identity (name/type/stage/sprite)
# swaps to the evolved form, but stats, HP, abilities and bonus level all carry
# over; only the stars reset.
func _evolve(player_idx: int, spirit: Dictionary) -> void:
	var evo_name := String(spirit.get("evolution", ""))
	var base: Dictionary = SpiritsData.get_spirit(evo_name)
	if base.is_empty():
		return
	var evolved: Dictionary = spirit.duplicate(true)
	evolved["name"] = evo_name
	evolved["type"] = base["type"]
	evolved["type2"] = base.get("type2", "")   # evolving can unlock a 2nd pool
	evolved["stage"] = base["stage"]
	evolved["evolution"] = base["evolution"]
	evolved["rarity"] = base["rarity"]
	evolved["sprite"] = base["sprite"]
	evolved["sprite_path"] = base["sprite_path"]
	evolved["stars"] = 0
	var p: PlayerData = GameState.players[player_idx]
	var i: int = p.team.find(spirit)
	if i != -1:
		p.team[i] = evolved
	else:
		var j: int = p.pc.find(spirit)
		if j != -1:
			p.pc[j] = evolved
	EventBus.emit_signal("spirit_evolved", player_idx, evolved)
