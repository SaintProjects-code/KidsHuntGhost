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
	# The board pauses while an encounter runs; these windows must keep working.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_encounter = preload("res://Scenes/UI/EncounterWindow.gd").new()
	_catch = preload("res://Scenes/UI/CatchWindow.gd").new()
	_select = preload("res://Scenes/UI/BattleTeamSelect.gd").new()
	_battle = preload("res://Scenes/UI/BattleScreen.gd").new()
	for w in [_encounter, _catch, _select, _battle]:
		add_child(w)
		w.set_click_through(true)   # action bar (lower layer) stays pressable
	EventBus.wild_encounter_started.connect(_on_started)

func _on_started(player_index: int, spirit: Dictionary) -> void:
	UIManager.hold_pause()   # game (HUD timer, board) pauses for the encounter
	var p: PlayerData = GameState.players[player_index]
	if p.is_cpu:
		# Every step of a CPU encounter is ALWAYS on screen: the Fight-or-Catch
		# decision, then the catch window or the auto-playing battle.
		var action := _cpu_encounter_choice(p, spirit)
		if action == "skip":
			# show the wild spirit, then have the CPU visibly walk away
			_encounter.present(spirit)
			UIManager.open(_encounter)
			await get_tree().create_timer(1.2).timeout
			EventBus.log_entry.emit(player_index, "%s walks past the wild %s." % [
				p.player_name, spirit.get("name", "?")], "#aaaaaa")
		else:
			await _cpu_show_choice(spirit, action)
			if action == "catch":
				await _cpu_catch(player_index, spirit)
			else:
				await _cpu_fight(player_index, spirit)
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
			_grant_fight_bonus(spirit)
			await _run_catch(player_index, spirit, true)
	else:
		if await _run_fight(p, spirit):
			# Weakened — offer a catch with the fight bonus context.
			_grant_fight_bonus(spirit)
			await _run_catch(player_index, spirit, true)
	_finish()

# Beating a wild spirit tags it: +2 winning catch numbers, once per encounter.
func _grant_fight_bonus(spirit: Dictionary) -> void:
	if not spirit.get("fought", false):
		spirit["fought"] = true
		CatchSystem.add_catch_numbers(spirit, 2)

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
			await SpiritsProgressionSystem.award_stars(player_index, team[int(i)], credits[i])
	if won:
		p.inventory.gold += 10   # bounty for beating a wild spirit
		EventBus.log_entry.emit(player_index, "%s beat the wild %s! +10 gold." % [
			p.player_name, spirit.get("name", "?")], "#f0c36a")
	return won

# What the CPU does at a wild encounter: "catch" / "fight" / "skip".
# A FULL team (6+ spirits) makes it battle and catch far less — it mostly
# walks past, since new spirits only clog its PC.
func _cpu_encounter_choice(p: PlayerData, spirit: Dictionary) -> String:
	# a trainer's spirit (event fight) can't be caught or skipped — fight it
	if spirit.get("_no_catch", false):
		return "fight"
	var has_ball: bool = p.inventory.ball_count(&"spirit_ball") > 0
	var living: int = 0
	for m in p.team:
		if int(m.get("current_hp", 0)) > 0:
			living += 1
	if p.team.size() >= 6:
		# full team: 70% skip, 20% fight (stars), 10% catch (to PC)
		var r := randf()
		if r < 0.7 or living < 2:
			return "skip"
		if r < 0.9 and living >= 2:
			return "fight"
		return "catch" if has_ball else "skip"
	# A struggling CPU (negative momentum) trains: the deeper the slump, the more
	# it fights wild spirits for stars instead of catching them.
	if p.cpu_momentum <= -2 and living >= 2 and randf() < minf(0.85, 0.25 + 0.15 * -p.cpu_momentum):
		return "fight"
	# room to grow: catch when it can, else fight if it has some muscle
	if has_ball:
		return "catch"
	return "fight" if living >= 2 else "skip"

# The CPU's Fight-or-Catch moment, shown to everyone: the encounter window
# opens locked with the CPU's pick lit up, holds a beat, then the action runs.
func _cpu_show_choice(spirit: Dictionary, action: String) -> void:
	_encounter.present_cpu(spirit, action)
	UIManager.open(_encounter)
	await get_tree().create_timer(1.6).timeout

# CPU catch, on screen: the locked catch window opens and throws by itself.
func _cpu_catch(player_index: int, spirit: Dictionary) -> void:
	var inv = GameState.players[player_index].inventory
	_catch.present(player_index, spirit, false)
	_catch.lock_for_cpu()
	UIManager.open(_catch)
	# Watch for a successful catch (works even for duplicates, which the catch
	# handler removes from the team again).
	var caught := [false]
	var on_ok := func(i: int, _s: Dictionary):
		if i == player_index:
			caught[0] = true
	EventBus.catch_succeeded.connect(on_ok)
	# The CPU throws up to its allotted tries, stopping early on a catch.
	for _t in CatchSystem.MAX_TRIES:
		if inv.ball_count(&"spirit_ball") <= 0:
			break
		await get_tree().create_timer(1.2).timeout
		inv.balls[&"spirit_ball"] -= 1
		EventBus.catch_attempted.emit(player_index, spirit, &"spirit_ball")
		await get_tree().create_timer(1.6).timeout
		if caught[0]:
			break
	EventBus.catch_succeeded.disconnect(on_ok)

# A CPU wild battle, always ON SCREEN: the window opens and plays itself
# (full engine: abilities, traits, damage write-back, star credits).
func _cpu_fight(player_index: int, spirit: Dictionary) -> void:
	var p: PlayerData = GameState.players[player_index]
	var team: Array = p.team.filter(func(m): return int(m.get("current_hp", 0)) > 0).slice(0, 4)
	if team.is_empty():
		EventBus.log_entry.emit(player_index, "%s backs away from the wild %s…" % [
			p.player_name, spirit.get("name", "?")], "#aaaaaa")
		return
	_battle.present(team, [spirit], "Wild Battle vs %s!" % spirit.get("name", "?"),
		p.color, p.next_battle_mod, GameData.player_trainer(p.player_name), [])
	p.next_battle_mod = 0
	UIManager.open(_battle)      # visible: the intro starts on open
	await _battle.autoplay()
	var credits: Dictionary = _battle.take_star_credits()
	for i in credits:
		if int(i) < team.size():
			await SpiritsProgressionSystem.award_stars(player_index, team[int(i)], credits[i])
	if _battle._won:
		p.inventory.gold += 10   # bounty for beating a wild spirit
		if p.cpu_momentum < 0:   # training paid off — climb out of the slump toward neutral
			p.cpu_momentum += 1
	EventBus.log_entry.emit(player_index, "%s %s a wild battle vs %s!%s" % [
		p.player_name, "won" if _battle._won else "lost", spirit.get("name", "?"),
		" +10 gold." if _battle._won else ""],
		"#9fff9f" if _battle._won else "#ff9f9f")

func _finish() -> void:
	UIManager.close()
	UIManager.release_pause()
	EventBus.encounter_finished.emit()
