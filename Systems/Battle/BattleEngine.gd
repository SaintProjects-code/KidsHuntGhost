extends Node

var _terrain := TerrainManager.new()

func run_battle(attacker_idx: int, defender_idx: int) -> void:
	var att_team := GameState.players[attacker_idx].team.slice(0, 3)
	var def_team := GameState.players[defender_idx].team.slice(0, 3)
	EventBus.emit_signal("battle_started", attacker_idx, defender_idx)

	# Match-start abilities fire once
	var ctx := { "attacker_lead": att_team[0], "defender_lead": def_team[0] }
	AbilityHandler.fire(&"match_start", ctx, att_team[0])
	AbilityHandler.fire(&"match_start", ctx, def_team[0])

	while _team_alive(att_team) and _team_alive(def_team):
		var attacker := _active(att_team)
		var defender := _active(def_team)
		AbilityHandler.fire(&"turn_start", {}, attacker)
		AbilityHandler.fire(&"turn_start", {}, defender)
		var att_can_act := StatusManager.tick(attacker)
		var def_can_act := StatusManager.tick(defender)
		if attacker["spd"] >= defender["spd"]:
			if att_can_act: _attack(attacker, defender)
			if _alive(defender) and def_can_act: _attack(defender, attacker)
		else:
			if def_can_act: _attack(defender, attacker)
			if _alive(attacker) and att_can_act: _attack(attacker, defender)
		_terrain.tick_round()
		await get_tree().process_frame

	var winner := attacker_idx if _team_alive(att_team) else defender_idx
	var loser  := defender_idx if winner == attacker_idx else attacker_idx
	EventBus.emit_signal("battle_ended", winner, loser)

func _attack(attacker: Dictionary, defender: Dictionary) -> void:
	var t_mult := _terrain.get_multiplier(attacker.get("type", ""))
	defender["current_hp"] -= DamageCalculator.calculate(attacker, defender, t_mult)

func _active(team: Array) -> Dictionary:
	return team.filter(func(m): return m["current_hp"] > 0)[0]

func _alive(mon: Dictionary) -> bool:
	return mon["current_hp"] > 0

func _team_alive(team: Array) -> bool:
	return team.any(func(m): return m["current_hp"] > 0)
