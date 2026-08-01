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
		await _award_star(player_idx, existing)
	# Fresh catch needs no star handling

# ── Battle handling ───────────────────────────────────────────────────────────

func _on_battle_ended(winner_idx: int, _loser_idx: int) -> void:
	var p := GameState.players[winner_idx]
	if p.team.size() > 0:
		await _award_star(winner_idx, p.team[0])  # star goes to lead

# ── Star logic ────────────────────────────────────────────────────────────────

func _award_star(player_idx: int, spirit: Dictionary) -> void:
	await award_stars(player_idx, spirit, 1.0)

# Stars can come in halves (battle results). Stars add +1 effective ATK each in
# the damage formula. Each WHOLE star just crossed also fires a milestone bonus
# reward (BonusReward decides what, by star level and the spirit's evo line).
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
	EventBus.emit_signal("star_awarded", player_idx, spirit)
	# One bonus reward per whole star crossed (1 -> 2 -> 3). Evolving at 3 stars
	# replaces the spirit dict, so 3 is always the last level handled here.
	for lvl in range(int(floor(prev)) + 1, int(floor(new_val)) + 1):
		await BonusReward.run(player_idx, spirit, lvl)

# ── Helpers ───────────────────────────────────────────────────────────────────

func _find_owned(p: PlayerData, name: String) -> Dictionary:
	for mon in p.team:
		if mon["name"] == name: return mon
	for mon in p.pc:
		if mon["name"] == name: return mon
	return {}
