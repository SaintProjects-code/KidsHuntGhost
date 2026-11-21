extends Node
## DEV TEST ONLY: screenshots of the top-centre time/turn pill, the turn
## banner fading in and out under it, and the Settings menu with room info.
func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir() + "/topbar")
	GameState.reset()
	GameState.active_map = 3
	for t in [["Ivy", "Mossprig", Color("5ad26a")], ["Brooke", "Puddleboo", Color("4aa3df")]]:
		var p := PlayerData.new()
		p.player_name = t[0]
		p.color = t[2]
		p.is_cpu = t[0] != "Ivy"
		p.team.append(SpiritsData.get_spirit(t[1]))
		GameState.players.append(p)
	GameState.turn_count = 8
	var board: Node = load("res://Scenes/Board/Board.tscn").instantiate()
	get_tree().root.add_child.call_deferred(board)
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().current_scene = board
	await _wait(0.12)
	_shot("1_banner_fading_in")
	await _wait(1.2)
	_shot("2_banner_shown")
	await _wait(3.0)
	_shot("3_banner_faded_out")
	board.info_label.text = "Ivy rolled 5"
	await _wait(1.0)
	_shot("4_next_message")
	board.get_node("BoardUI/Root/PauseMenu")._on_settings_pressed() if board.has_node("BoardUI/Root/PauseMenu") else _open_settings(board)
	await _wait(0.5)
	_shot("5_settings_room_info")
	get_tree().quit()

func _open_settings(board: Node) -> void:
	for n in board.find_children("*", "Control", true, false):
		if n.has_method("_on_settings_pressed"):
			n._on_settings_pressed()
			return

func _wait(t: float) -> void:
	await get_tree().create_timer(t, true, false, true).timeout

func _shot(name: String) -> void:
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/topbar/%s.png" % name)
	print("SHOT ", name)
