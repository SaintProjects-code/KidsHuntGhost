extends Node
## DEV TEST ONLY: a 4-CPU game on a 3D map (or -- map=1) that runs one
## competition event (-- ev=<key>) and saves screenshots to user://mgtest/.
func _ready() -> void:
	var ev := "climb"
	var map := 3
	for a in OS.get_cmdline_user_args():
		if a.begins_with("ev="):
			ev = a.substr(3)
		elif a.begins_with("map="):
			map = int(a.substr(4))
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir() + "/mgtest")
	GameState.reset()
	GameState.active_map = map
	var picks := [["Ivy", "Mossprig", Color("5ad26a")], ["Brooke", "Puddleboo", Color("4aa3df")], ["Ember", "Cinderwisp", Color("ff7a3a")], ["Zap", "Zapkin", Color("ffd24d")],
		["Rex", "Brawlboo", Color("e0563a")], ["Shade", "Wispy", Color("8e6fd6")]]
	var count := 4
	for a in OS.get_cmdline_user_args():
		if a.begins_with("players="):
			count = int(a.substr(8))
	for t in picks.slice(0, count):
		var p := PlayerData.new()
		p.player_name = t[0]
		p.color = t[2]
		p.is_cpu = true
		p.team.append(SpiritsData.get_spirit(t[1]))
		for k in 2:
			p.team.append(SpiritsData.random_spirit(1))
		GameState.players.append(p)
	var board: Node = load("res://Scenes/Board/Board.tscn").instantiate()
	get_tree().root.add_child.call_deferred(board)
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().current_scene = board
	preload("res://Scenes/UI/Competition/CompetitionWindow.gd").dev_forced_event = ev
	await get_tree().create_timer(0.8).timeout
	EventBus.tile_action.emit(0, &"COMPETITION")
	for s in [10.0, 15.0, 20.0]:
		await get_tree().create_timer(s - (10.0 if s == 10.0 else s - 5.0) if s == 10.0 else 5.0).timeout
		get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/mgtest/%s_m%d_p%d_%d.png" % [ev, map, GameState.players.size(), int(s)])
	get_tree().quit()
