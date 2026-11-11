extends Node
## Runs the max-star / evolution "bonus reward" flow. When a spirit reaches 3
## stars, SpiritsProgressionSystem calls `await BonusReward.run(idx, spirit)`.
##
## Each spirit tracks a bonus level ("_bonus_lvl") that climbs 1 → 2 → 3, and
## each level grants a fixed reward:
##   1) swap the spirit's ability for a new one (from its type pool)
##   2) +2 to a stat (player-chosen for humans, random for CPUs)
##   3) swap the ability again — a spirit only ever has ONE ability (and one move)
##
## How many bonuses one 3-star grants:
##   • has an evolution        → 1 bonus, then evolve (stats/abilities carry over)
##   • no evo, never rewarded  → 2 bonuses (a basic with nowhere to grow)
##   • no evo, already rewarded → 1 bonus (a fully-evolved final form)

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

# Full flow for one spirit that just hit 3 stars. Awaits any human input.
func run(player_idx: int, spirit: Dictionary) -> void:
	var has_evo: bool = String(spirit.get("evolution", "")) != ""
	var rewarded: bool = int(spirit.get("_bonus_lvl", 0)) > 0
	var count: int = 2 if (not has_evo and not rewarded) else 1
	for _n in count:
		await _grant_one(player_idx, spirit)
	if has_evo:
		_evolve(player_idx, spirit)

func _grant_one(player_idx: int, spirit: Dictionary) -> void:
	var lvl: int = int(spirit.get("_bonus_lvl", 0)) + 1
	spirit["_bonus_lvl"] = lvl
	var human: bool = not GameState.players[player_idx].is_cpu
	match lvl:
		2:
			await _reward_stat(player_idx, spirit, lvl, human)
		_:
			await _reward_ability(player_idx, spirit, lvl, human)   # levels 1 and 3

# ── rewards ───────────────────────────────────────────────────────────────────

# Swap the spirit's one ability for a new one (or keep it).
func _reward_ability(player_idx: int, spirit: Dictionary, lvl: int, human: bool) -> void:
	var a1 := String(spirit.get("ability", ""))
	var held: Array = [a1] if a1 != "" else []
	var ptype := String(spirit.get("type", ""))
	var ptype2 := String(spirit.get("type2", ""))   # duals draw from both pools
	var new_ab: String
	if human:
		# Offer 4 abilities to choose from, each shown with its description.
		var options: Array = SpiritsData.ability_options(ptype, held, 4, ptype2)
		if options.is_empty():
			return
		_win.present_ability(spirit, lvl, options, a1)
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
	spirit["ability"] = new_ab
	spirit.erase("ability2")
	EventBus.emit_signal("log_entry", player_idx, "%s swapped ability: %s" % [
		spirit.get("name", "?"), SpiritsData.ability_of(new_ab).get("name", new_ab)], "#7fe0d0")
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
