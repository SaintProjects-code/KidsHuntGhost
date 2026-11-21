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
	var humans := 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("humans="):
			humans = int(a.substr(7))
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
	if humans > 0:   # picks done → these players become humans as the game starts
		var comp: Node = null
		while comp == null or comp._picks.size() < GameState.players.size():
			await get_tree().process_frame
			comp = _find(get_tree().root, "CompetitionWindow.gd")
		for k in humans:
			GameState.players[k].is_cpu = false
	await get_tree().create_timer(2.5).timeout
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/mgtest/%s_m%d_p%d_pick.png" % [ev, map, GameState.players.size()])
	if humans > 0:   # the how-to card waits for Start: show it, then press it
		var g: Node = null
		while g == null or g.get("_start_btn") == null:
			await get_tree().process_frame
			g = _find(get_tree().root, "Game.gd")
		await get_tree().create_timer(2.0).timeout
		get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/mgtest/%s_m%d_p%d_start.png" % [ev, map, GameState.players.size()])
		g._press_start()
	if "burst" in OS.get_cmdline_user_args():   # a frame every 0.4s for 12s
		for k in 30:
			await get_tree().create_timer(0.4).timeout
			get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/mgtest/burst_%s_m%d_%02d.png" % [ev, map, k])
		get_tree().quit()
		return
	for s in [10.0, 15.0, 20.0]:
		await get_tree().create_timer(s - (10.0 if s == 10.0 else s - 5.0) if s == 10.0 else 5.0).timeout
		get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/mgtest/%s_m%d_p%d_%d.png" % [ev, map, GameState.players.size(), int(s)])
	get_tree().quit()

func _find(n: Node, end: String) -> Node:
	if n.get_script() and String(n.get_script().resource_path).ends_with(end):
		return n
	for c in n.get_children():
		var f := _find(c, end)
		if f:
			return f
	return null
