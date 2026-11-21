extends Node
## DEV TEST ONLY: the setup screen → Game Settings → Minigames window (two
## games turned off) → back to the Game card. Shots in user://setupshots.
func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir() + "/setupshots")
	var s: Node = load("res://Scenes/Menu/SetupScreen.tscn").instantiate()
	get_tree().root.add_child.call_deferred(s)
	await get_tree().process_frame
	await get_tree().process_frame
	s._settings_win.show()
	await get_tree().create_timer(0.6).timeout
	_shot("1_settings")
	s._games_btn.pressed.emit()
	await get_tree().process_frame
	var boxes: Array = s._games_win.find_children("*", "CheckBox", true, false)
	boxes[1].button_pressed = false
	boxes[4].button_pressed = false
	await get_tree().create_timer(0.6).timeout
	_shot("2_minigames_window")
	s._games_win.hide()
	s._settings_win.hide()
	await get_tree().create_timer(0.4).timeout
	_shot("3_game_card")
	print("OFF ", GameState.minigames_off)
	get_tree().quit()

func _shot(n: String) -> void:
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/setupshots/%s.png" % n)
