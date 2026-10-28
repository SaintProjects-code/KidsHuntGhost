extends CanvasLayer
## Runs the wild-ghost encounter windows: Fight or Catch → (team select →
## battle) → catch. Listens for EventBus.wild_encounter_started and emits
## encounter_finished when done (the board waits for it). CPU encounters play
## out on screen with the same windows, locked.

var _encounter: Control
var _catch: Control
var _select: Control
var _battle: Control

func _ready() -> void:
	layer = 12
	process_mode = Node.PROCESS_MODE_ALWAYS   # the board pauses meanwhile
	_encounter = preload("res://Scenes/UI/EncounterWindow.gd").new()
	_catch = preload("res://Scenes/UI/CatchWindow.gd").new()
	_select = preload("res://Scenes/UI/BattleTeamSelect.gd").new()
	_battle = preload("res://Scenes/UI/Battle/BattleScreen.gd").new()
	for w in [_encounter, _catch, _select, _battle]:
		add_child(w)
		w.set_click_through(true)
	EventBus.wild_encounter_started.connect(_on_started)
	EventBus.catch_succeeded.connect(_on_caught)
	EventBus.catch_failed.connect(_on_escaped)

func _on_started(idx: int, spirit: Dictionary) -> void:
	UIManager.hold_pause()
	# yield so the board reaches its `await encounter_finished` first
	await get_tree().process_frame
	var p: PlayerData = GameState.players[idx]
	if p.is_cpu:
		await _cpu_encounter(idx, spirit)
	elif spirit.get("_no_catch", false):
		await _fight(idx, spirit)   # a trainer's spirit: battle only
	else:
		_encounter.present(spirit)
		UIManager.open(_encounter)
		var action: String = await _encounter.chose
		if action == "catch":
			# a missed throw can turn into a fight; a won fight offers a weakened catch
			if await _run_catch(idx, spirit, false) == "fight" and await _fight(idx, spirit):
				await _run_catch(idx, spirit, true)
		elif await _fight(idx, spirit):
			await _run_catch(idx, spirit, true)
	UIManager.close()
	UIManager.release_pause()
	EventBus.encounter_finished.emit()

func _run_catch(idx: int, spirit: Dictionary, fought_first: bool) -> String:
	_catch.present(idx, spirit, fought_first)
	UIManager.open(_catch)
	return await _catch.done

# Team select (humans) + battle. Returns true on a win.
func _fight(idx: int, spirit: Dictionary) -> bool:
	var p: PlayerData = GameState.players[idx]
	var team: Array
	if p.is_cpu:
		team = BattleSetup.cpu_team(idx, [spirit])
	else:
		_select.present(p, "vs Wild %s" % spirit.get("name", "?"), [spirit])
		UIManager.open(_select)
		team = await _select.chosen
	if team.is_empty():
		return false
	var setup := BattleSetup.vs_npc(idx, team, [spirit], "Wild battle vs %s!" % spirit.get("name", "?"), [], "wild")
	var won := await BattleSetup.run(_battle, setup, idx)
	if won:
		p.inventory.gold += Balance.GOLD_WILD_WIN
	EventBus.log_entry.emit(idx, "%s %s a wild battle vs %s!%s" % [p.player_name, "won" if won else "lost",
		spirit.get("name", "?"), " +%d gold." % Balance.GOLD_WILD_WIN if won else ""],
		"#9fff9f" if won else "#ff9f9f")
	return won

# ── CPU ───────────────────────────────────────────────────────────────────────

func _cpu_encounter(idx: int, spirit: Dictionary) -> void:
	var p: PlayerData = GameState.players[idx]
	var action := _cpu_choice(p, spirit)
	if action == "skip":
		_encounter.present(spirit)
		UIManager.open(_encounter)
		await get_tree().create_timer(1.2).timeout
		EventBus.log_entry.emit(idx, "%s walks past the wild %s." % [p.player_name, spirit.get("name", "?")], "#aaaaaa")
		return
	_encounter.present_cpu(spirit, action)
	UIManager.open(_encounter)
	await get_tree().create_timer(1.4).timeout
	if action == "fight":
		if not await _fight(idx, spirit) or p.inventory.total_jars() == 0 or p.team.size() >= Balance.TEAM_MAX:
			return
	# throw until caught, out of jars, or it flees
	_catch.present(idx, spirit, action == "fight")
	_catch.lock_for_cpu()
	UIManager.open(_catch)
	await get_tree().create_timer(0.6).timeout
	while p.inventory.jar_count(_catch.cpu_jar()) > 0:
		_catch.cpu_throw()
		var outcome: String = await _catch_result(idx)
		if outcome != "missed" or int(spirit.get("catch_fails", 0)) >= Balance.CATCH_MAX_FAILS:
			break
		_catch.lock_for_cpu()
		await get_tree().create_timer(0.5).timeout
	await get_tree().create_timer(0.8).timeout

# Waits for the throw's result: "caught" | "fled" | "missed".
var _throw_result := ""
var _thrower := -1

func _catch_result(idx: int) -> String:
	_throw_result = ""
	_thrower = idx
	while _throw_result == "" and is_inside_tree():
		await get_tree().process_frame
	return _throw_result

func _on_caught(i: int, _s: Dictionary) -> void:
	if i == _thrower:
		_throw_result = "caught"

func _on_escaped(i: int, s: Dictionary) -> void:
	if i == _thrower:
		_throw_result = "fled" if int(s.get("catch_fails", 0)) >= Balance.CATCH_MAX_FAILS else "missed"

# "catch" / "fight" / "skip". A full team mostly walks past (new spirits
# only clog the Spirit Box); a tough spirit gets fought first.
func _cpu_choice(p: PlayerData, spirit: Dictionary) -> String:
	if spirit.get("_no_catch", false):
		return "fight"
	var living := p.living_team().size()
	var has_jar := p.inventory.total_jars() > 0
	if p.team.size() >= Balance.TEAM_MAX:
		# a full team only fights for stars — keenly while it's still too green
		# for the trail, rarely once it's ready
		var keen := 0.3 if CpuBrain.ready_for_trail(p) else 0.75
		return "fight" if randf() < keen and living >= 2 else "skip"
	if has_jar:
		var idx := GameState.players.find(p)
		var odds := CatchSystem.chance(idx, spirit, &"ghost_jar")
		return "fight" if odds < 50 and living >= 2 else "catch"
	return "fight" if living >= 2 else "skip"
