extends Node
## DEV TEST ONLY: starts a 2-CPU game on a map and fires a PvP battle so the
## battle screen can be recorded. Map from the command line: -- map=3

func _ready() -> void:
	var map := 3
	var human := false   # -- human : player 1 picks their team (shows the team select)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("map="):
			map = int(a.substr(4))
		elif a == "human":
			human = true
	GameState.reset()
	GameState.active_map = map
	var picks := [["Ember", "Cinderwisp", Color("ff7a3a")], ["Brooke", "Puddleboo", Color("4aa3df")]]
	if "players=6" in OS.get_cmdline_user_args():
		picks += [["Ivy", "Mossprig", Color("5ad26a")], ["Zap", "Zapkin", Color("ffd24d")],
			["Rex", "Brawlboo", Color("e0563a")], ["Shade", "Wispy", Color("8e6fd6")]]
	for t in picks:
		var p := PlayerData.new()
		p.player_name = t[0]
		p.is_cpu = not (human and t[0] == "Ember")
		p.color = t[2]
		p.team.append(SpiritsData.get_spirit(t[1]))
		for i in 3:
			p.team.append(SpiritsData.random_spirit(1))
		p.inventory.hand = ["spirit_shield", "battle_cry", "haste"]
		GameState.players.append(p)
	# the board goes in beside this node (so this one stays alive to drive the test)
	var board: Node = load("res://Scenes/Board/Board.tscn").instantiate()
	get_tree().root.add_child.call_deferred(board)
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().current_scene = board
	await get_tree().create_timer(1.5).timeout
	if "players=6" in OS.get_cmdline_user_args():
		return   # just the board with six players
	var kind := "PVP"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("kind="):
			kind = a.substr(5)
	if kind == "EVENT":
		EventBus.tile_action.emit(0, &"EVENT")
		return
	if kind == "TRAINER" or kind == "GYM":
		var tc := _find_battle(get_tree().root).get_parent()
		var roster := [SpiritsData.random_spirit(1), SpiritsData.random_spirit(2), SpiritsData.random_spirit(1)]
		UIManager.hold_pause()
		await tc._npc_battle(0, roster, "Test %s" % kind.capitalize(), ["acetrainer"], kind.to_lower())
		UIManager.close()
		UIManager.release_pause()
	elif kind == "WILD":
		var battle := _find_battle(get_tree().root)
		var p0: PlayerData = GameState.players[0]
		var setup := BattleSetup.vs_npc(0, p0.team.slice(0, 3), [], [SpiritsData.random_spirit(2)], "Wild battle", [], "wild")
		UIManager.hold_pause()
		await BattleSetup.run(battle, setup, 0)
		UIManager.close()
		UIManager.release_pause()
	else:
		EventBus.dev_battle_requested.emit(StringName(kind), 0, 1)

func _find_battle(n: Node) -> Node:
	if n.get_script() and String(n.get_script().resource_path).ends_with("BattleScreen.gd") and n.get_parent().get_script() 			and String(n.get_parent().get_script().resource_path).ends_with("TileController.gd"):
		return n
	for c in n.get_children():
		var f := _find_battle(c)
		if f:
			return f
	return null
