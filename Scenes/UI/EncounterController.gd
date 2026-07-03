extends CanvasLayer
## Owns and sequences the wild-encounter windows (Encounter → Catch, or
## → Team Select → Battle → Catch). Added to the board by Board.gd.
##
## Listens for EventBus.wild_encounter_started and, when the flow ends, emits
## EventBus.encounter_finished (which the board awaits before ending the turn).

var _encounter: Control
var _catch: Control
var _select: Control
var _battle: Control

func _ready() -> void:
	layer = 12
	_encounter = preload("res://Scenes/UI/EncounterWindow.gd").new()
	_catch = preload("res://Scenes/UI/CatchWindow.gd").new()
	_select = preload("res://Scenes/UI/BattleTeamSelect.gd").new()
	_battle = preload("res://Scenes/UI/BattleScreen.gd").new()
	add_child(_encounter)
	add_child(_catch)
	add_child(_select)
	add_child(_battle)
	EventBus.wild_encounter_started.connect(_on_started)

func _on_started(player_index: int, spirit: Dictionary) -> void:
	var p: PlayerData = GameState.players[player_index]
	if p.is_cpu:
		# CPUs never battle trainer spirits and can't catch them either
		if not spirit.get("_no_catch", false):
			_auto_resolve(player_index, spirit)
		# Yield a frame so the board reaches its `await encounter_finished` before
		# we emit it (otherwise the CPU's instant resolve would be missed).
		await get_tree().process_frame
		_finish()
		return
	# A trainer's spirit (event fights): battle only — no catch, ever.
	if spirit.get("_no_catch", false):
		await _run_fight(p, spirit)
		_finish()
		return
	# Human: Fight or Catch?
	_encounter.present(spirit)
	UIManager.open(_encounter)
	var action: String = await _encounter.chose
	if action == "catch":
		# A missed throw can turn into a fight; a won fight offers a
		# weakened catch.
		var outcome: String = await _run_catch(player_index, spirit, false)
		if outcome == "fight" and await _run_fight(p, spirit):
			await _run_catch(player_index, spirit, true)
	else:
		if await _run_fight(p, spirit):
			# Weakened — offer a catch with the fight bonus context.
			await _run_catch(player_index, spirit, true)
	_finish()

# Catch window; returns "caught", "left", or "fight".
func _run_catch(player_index: int, spirit: Dictionary, fought_first: bool) -> String:
	_catch.present(player_index, spirit, fought_first)
	UIManager.open(_catch)
	return await _catch.done

# Team select + battle; returns true if the player won (false on back-out).
func _run_fight(p: PlayerData, spirit: Dictionary) -> bool:
	_select.present(p, "vs Wild %s" % spirit.get("name", "?"), [spirit])
	UIManager.open(_select)
	var team: Array = await _select.chosen
	if team.is_empty():
		return false
	var mod: int = p.next_battle_mod
	p.next_battle_mod = 0
	_battle.present(team, [spirit], "Wild Battle vs %s!" % spirit.get("name", "?"), p.color, mod,
		GameData.player_trainer(p.player_name), [])   # wild spirits have no trainer
	UIManager.open(_battle)
	var won: bool = await _battle.finished
	# stars earned in battle (KOs + surviving a win) go to the real spirits
	var player_index: int = GameState.players.find(p)
	var credits: Dictionary = _battle.take_star_credits()
	for i in credits:
		if int(i) < team.size():
			SpiritsProgressionSystem.award_stars(player_index, team[int(i)], credits[i])
	return won

# CPU: quietly throw a ball if it has one (no windows).
func _auto_resolve(player_index: int, spirit: Dictionary) -> void:
	var inv = GameState.players[player_index].inventory
	if inv.ball_count(&"spirit_ball") > 0:
		inv.balls[&"spirit_ball"] -= 1
		EventBus.catch_attempted.emit(player_index, spirit, &"spirit_ball")

func _finish() -> void:
	UIManager.close()
	EventBus.encounter_finished.emit()
