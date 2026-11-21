extends Node
## DEV TEST ONLY: the VS banner over the 3D board (frames saved to user://vstest).
func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir() + "/vstest")
	GameState.reset()
	GameState.active_map = 3
	for t in [["Ivy", "Mossprig", Color("5ad26a")], ["Ember", "Cinderwisp", Color("ff7a3a")]]:
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
	await get_tree().create_timer(1.5).timeout
	var pa: PlayerData = GameState.players[0]
	var pb: PlayerData = GameState.players[1]
	var setup := {"team": pa.team.slice(0, 3), "opp": pb.team.slice(0, 3), "pvp_names": [pa.player_name, pb.player_name],
		"color": pa.color, "opp_color": pb.color, "trainer": GameData.player_trainer(pa), "foe_trainer": GameData.player_trainer(pb), "human": true}
	preload("res://Scenes/UI/Battle/VsBanner.gd").play(get_tree(), setup)
	var t0 := Time.get_ticks_msec()
	for at in [0.2, 0.42, 0.5, 0.62, 0.8, 1.4, 3.65]:
		while (Time.get_ticks_msec() - t0) / 1000.0 < at:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/vstest/vs_%04d.png" % int(at * 1000))
	get_tree().quit()
