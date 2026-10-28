extends MenuWindow
## Shown when someone wins. show_win(player_index).

var _title: Label
var _sub: Label
var _teams_box: VBoxContainer
var _teams_btn: Button

func _ready() -> void:
	var col := _init_window(460, 280)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	_title = _title_label("🏆 Winner!", 34)
	col.add_child(_title)
	_sub = Label.new()
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_sub)
	# collapsible final-teams overview
	_teams_box = VBoxContainer.new()
	_teams_box.add_theme_constant_override("separation", 6)
	_teams_box.hide()
	col.add_child(_teams_box)
	_teams_btn = _button("👥 View Player Teams", _toggle_teams)
	col.add_child(_teams_btn)
	col.add_child(_button("Main Menu", _on_menu))
	col.add_child(_button("Quit", _on_quit))
	hide()

func show_win(player_index: int) -> void:
	var p: PlayerData = GameState.players[player_index]
	_title.text = "🏆 %s Wins!" % p.player_name
	_sub.text = "%d points · %d badges" % [p.progress.points, p.progress.badge_count()]
	_teams_box.hide()
	_teams_btn.text = "👥 View Player Teams"

func _toggle_teams() -> void:
	if _teams_box.visible:
		_teams_box.hide()
		_teams_btn.text = "👥 View Player Teams"
		return
	_fill_teams()
	_teams_box.show()
	_teams_btn.text = "▲ Hide Teams"

# One row per player: name in their colour, then their spirits with stars.
func _fill_teams() -> void:
	for c in _teams_box.get_children():
		c.queue_free()
	for p in GameState.players:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var nm := Label.new()
		nm.text = "%s — %d pts" % [p.player_name, p.progress.points]
		nm.custom_minimum_size = Vector2(140, 0)
		nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		nm.add_theme_color_override("font_color", p.color)
		row.add_child(nm)
		if p.team.is_empty():
			var none := Label.new()
			none.text = "— no spirits —"
			none.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			row.add_child(none)
		for s in p.team:
			var cell := VBoxContainer.new()
			var icon := TextureRect.new()
			icon.texture = SpiritsData.sprite_tex(s.get("name", ""), "front")
			icon.custom_minimum_size = Vector2(40, 40)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			icon.tooltip_text = "%s %s" % [s.get("name", "?"), SpiritsData.star_text(s.get("stars", 0))]
			cell.add_child(icon)
			var st := Label.new()
			st.text = SpiritsData.star_text(s.get("stars", 0))
			st.add_theme_font_size_override("font_size", 10)
			st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cell.add_child(st)
			row.add_child(cell)
		_teams_box.add_child(row)

func _on_menu() -> void:
	UIManager.reset_pause()
	get_tree().change_scene_to_file("res://Scenes/Menu/MainMenu.tscn")

func _on_quit() -> void:
	get_tree().quit()
