extends Node
## DEV TEST ONLY: a DEV game (3 players) → open the Dev window (shot) →
## Add player twice → the board restarts with 5 players (shot).
func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir() + "/devshots")
	var menu: Node = load("res://Scenes/Menu/MainMenu.tscn").instantiate()
	get_tree().root.add_child.call_deferred(menu)
	await _wait(0.5)
	get_tree().current_scene = menu
	menu._on_dev_pressed()
	await _wait(1.5)
	var dev := _find(get_tree().root, "DevWindow.gd")
	dev.present(0)
	UIManager.open_overlay(dev)
	await _wait(0.6)
	_shot("1_dev_window")
	dev._add_player()
	await _wait(1.2)
	dev = _find(get_tree().root, "DevWindow.gd")
	dev._add_player()
	await _wait(2.0)
	_shot("2_board_after_adding_two")
	dev = _find(get_tree().root, "DevWindow.gd")
	dev.present(0)
	UIManager.open_overlay(dev)
	await _wait(0.6)
	_shot("3_dev_window_5_players")
	get_tree().quit()

func _wait(t: float) -> void:
	await get_tree().create_timer(t, true, false, true).timeout

func _shot(n: String) -> void:
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/devshots/%s.png" % n)
	print("SHOT ", n, " players=", GameState.players.size())

func _find(n: Node, end: String) -> Node:
	if n.get_script() and String(n.get_script().resource_path).ends_with(end):
		return n
	for c in n.get_children():
		var f := _find(c, end)
		if f:
			return f
	return null
