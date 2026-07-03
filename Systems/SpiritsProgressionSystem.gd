extends Node

func _ready() -> void:
	EventBus.catch_succeeded.connect(_on_catch)
	EventBus.battle_ended.connect(_on_battle_ended)

# ── Catch handling ────────────────────────────────────────────────────────────

func _on_catch(player_idx: int, spirit: Dictionary) -> void:
	var p := GameState.players[player_idx]
	var existing := _find_owned(p, spirit["name"])
	if existing and existing != spirit:
		# Duplicate — remove the new one (wherever it landed), award a star
		p.team.erase(spirit)
		p.pc.erase(spirit)
		_award_star(player_idx, existing)
	# Fresh catch needs no star handling

# ── Battle handling ───────────────────────────────────────────────────────────

func _on_battle_ended(winner_idx: int, _loser_idx: int) -> void:
	var p := GameState.players[winner_idx]
	if p.team.size() > 0:
		_award_star(winner_idx, p.team[0])  # star goes to lead

# ── Star logic ────────────────────────────────────────────────────────────────

func _award_star(player_idx: int, spirit: Dictionary) -> void:
	award_stars(player_idx, spirit, 1.0)

# Stars can come in halves (battle results). Each WHOLE star crossed grants
# the star bonus: +1 to a random battle stat (capped at tier 6) and +10 max
# HP. Stars also add +1 effective ATK each in the damage formula.
func award_stars(player_idx: int, spirit: Dictionary, amount: float) -> void:
	var prev: float = float(spirit.get("stars", 0))
	if prev >= 3.0 or amount <= 0.0:
		return  # already maxed
	var new_val: float = minf(3.0, prev + amount)
	spirit["stars"] = new_val
	EventBus.log_entry.emit(player_idx, "%s gained %s star%s (%s)" % [
		spirit.get("name", "?"),
		str(amount) if amount != 0.5 else "half a",
		"s" if amount > 1.0 else "",
		SpiritsData.star_text(new_val)], "#d3a8ff")
	var whole_gained: int = int(floor(new_val)) - int(floor(prev))
	for i in whole_gained:
		var stat: String = ["atk", "def", "spd"][randi() % 3]
		spirit[stat] = clampi(int(spirit.get(stat, 1)) + 1, 1, 6)
		spirit["hp"] = int(spirit.get("hp", 60)) + 10
		spirit["current_hp"] = mini(int(spirit["hp"]), int(spirit.get("current_hp", 0)) + 10)
		EventBus.log_entry.emit(player_idx, "%s ★ bonus: +1 %s, +10 HP!" % [
			spirit.get("name", "?"), stat.to_upper()], "#d3a8ff")
	EventBus.emit_signal("star_awarded", player_idx, spirit)
	if new_val >= 3.0:
		_trigger_evolution(player_idx, spirit)

# ── Evolution ─────────────────────────────────────────────────────────────────

func _trigger_evolution(player_idx: int, spirit: Dictionary) -> void:
	var evo_name: String = spirit.get("evolution", "")
	if evo_name == "":
		# No evolution — bonus point instead
		GameState.award_points(player_idx, 1)
		return
	var p := GameState.players[player_idx]
	var evolved: Dictionary = SpiritsData.get_spirit(evo_name).duplicate()
	evolved["stars"] = 0
	evolved["current_hp"] = evolved["hp"]
	p.team.erase(spirit)
	p.team.append(evolved)
	EventBus.emit_signal("spirit_evolved", player_idx, evolved)

# ── Helpers ───────────────────────────────────────────────────────────────────

func _find_owned(p: PlayerData, name: String) -> Dictionary:
	for mon in p.team:
		if mon["name"] == name: return mon
	for mon in p.pc:
		if mon["name"] == name: return mon
	return {}
