extends MenuWindow
## Shown when someone wins. show_win(player_index).

var _title: Label
var _sub: Label

func _ready() -> void:
	var col := _init_window(460, 280)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	_title = _title_label("🏆 Winner!", 34)
	col.add_child(_title)
	_sub = Label.new()
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_sub)
	col.add_child(_button("Main Menu", _on_menu))
	col.add_child(_button("Quit", _on_quit))
	hide()

func show_win(player_index: int) -> void:
	var p: PlayerData = GameState.players[player_index]
	_title.text = "🏆 %s Wins!" % p.player_name
	_sub.text = "%d points · %d badges" % [p.progress.points, p.progress.badge_count()]

func _on_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://Scenes/Menu/MainMenu.tscn")

func _on_quit() -> void:
	get_tree().quit()
