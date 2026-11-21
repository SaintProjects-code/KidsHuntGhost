extends Node
## DEV TEST ONLY: screenshots of weather, the Grim Gang and new events.
const OUT := "user://shots/"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir() + "/shots")
	GameState.reset()
	var battles := "battles" in OS.get_cmdline_user_args()
	GameState.active_map = 1 if "map=1" in OS.get_cmdline_user_args() else 3
	for t in [["Ivy", "Mossprig", Color("5ad26a")], ["Brooke", "Puddleboo", Color("4aa3df")], ["Zap", "Zapkin", Color("ffd24d")]]:
		var p := PlayerData.new()
		p.player_name = t[0]
		p.color = t[2]
		p.is_cpu = t[0] != "Ivy"
		p.team.append(SpiritsData.get_spirit(t[1]))
		for k in 3:
			p.team.append(SpiritsData.random_spirit(1))
		p.inventory.gold = 40
		GameState.players.append(p)
	var board: Node = load("res://Scenes/Board/Board.tscn").instantiate()
	get_tree().root.add_child.call_deferred(board)
	await _wait(0.6)
	get_tree().current_scene = board
	print("HIDEOUT ", GameState.gang_hideout, " = ", board.graph.label(GameState.gang_hideout))
	if battles:
		# CPU vs CPU battles in each weather
		for p in GameState.players:
			p.is_cpu = true
		var kinds := ["storm"] if GameState.active_map == 1 else ["storm", "sun", "mist", "sand"]
		for w in kinds:
			GameState.set_weather(w)
			EventBus.dev_battle_requested.emit(&"PVP", 0, 1)
			await _wait(6.5)
			_shot("battle_%s_map%d" % [w, GameState.active_map])
			var bs := _find_battle(get_tree().root)
			if bs:
				bs._on_skip()
			await _wait(3.0)
		get_tree().quit()
		return
	if not "dice" in OS.get_cmdline_user_args():
		for w in ["storm", "sun", "mist", "sand"]:
			GameState.set_weather(w)
			await _wait(1.2)
			_shot("weather_" + w)
	GameState.set_weather("")
	GameState.weather = ""
	board.warp_player(0, GameState.gang_hideout)
	board.camera.position = board.graph.node_pos[GameState.gang_hideout]
	await _wait(1.0)
	_shot("hideout_town")
	var ev := _find(get_tree().root, "SpiritEventWindow.gd")
	UIManager.hold_pause()
	if "dice" in OS.get_cmdline_user_args():
		ev.present(0, "", "Storm Caller")
		UIManager.open(ev)
		await _wait(4.5)
		_shot("dice_before_choice")
		ev._on_option(ev._visible_options()[0])
		await _wait(0.4)
		_shot("dice_rolling")
		await _wait(1.0)
		_shot("dice_result")
		get_tree().quit()
		return
	for title in ["Grim Gang Ambush", "Storm Caller", "The Vault"]:
		ev.present(0, "", title)
		UIManager.open(ev)
		await _wait(4.5)
		_shot("event_" + title.replace(" ", "_").to_lower())
		UIManager.close()
	var tc := _find(get_tree().root, "TileController.gd")
	tc._steal_lead(0)
	await _wait(0.8)
	_shot("lead_stolen")
	await _wait(2.0)
	tc._run_hideout(0)
	await _wait(2.6)
	_shot("boss_vs")
	await _wait(4.0)
	_shot("boss_battle")
	get_tree().quit()

func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout

func _shot(name: String) -> void:
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/shots/%s.png" % name)
	print("SHOT ", name)

func _find(n: Node, script_end: String) -> Node:
	if n.get_script() and String(n.get_script().resource_path).ends_with(script_end):
		return n
	for c in n.get_children():
		var f := _find(c, script_end)
		if f:
			return f
	return null

func _find_battle(n: Node) -> Node:
	if n.get_script() and String(n.get_script().resource_path).ends_with("BattleScreen.gd") and n.is_visible_in_tree():
		return n
	for c in n.get_children():
		var f := _find_battle(c)
		if f:
			return f
	return null
