extends MenuWindow
## Shown when someone wins. show_win(player_index).

var _title: Label
var _sub: Label
var _teams_box: VBoxContainer
var _teams_btn: Button
var _stats_box: VBoxContainer
var _stats_btn: Button

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
	_stats_box = VBoxContainer.new()
	_stats_box.add_theme_constant_override("separation", 6)
	_stats_box.hide()
	col.add_child(_stats_box)
	_stats_btn = _button("📊 Game Stats", _toggle_stats)
	col.add_child(_stats_btn)
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
	_stats_box.hide()
	_stats_btn.text = "📊 Game Stats"

func _toggle_teams() -> void:
	if _teams_box.visible:
		_teams_box.hide()
		_teams_btn.text = "👥 View Player Teams"
		return
	_stats_box.hide()   # one panel at a time keeps the window on screen
	_stats_btn.text = "📊 Game Stats"
	_fill_teams()
	_teams_box.show()
	_teams_btn.text = "▲ Hide Teams"

func _toggle_stats() -> void:
	if _stats_box.visible:
		_stats_box.hide()
		_stats_btn.text = "📊 Game Stats"
		return
	_teams_box.hide()
	_teams_btn.text = "👥 View Player Teams"
	_fill_stats()
	_stats_box.show()
	_stats_btn.text = "▲ Hide Stats"

# The rows of the stats table: [label, Callable(PlayerData) -> String].
func _stat_rows() -> Array:
	return [
		["⭐ Points", func(p): return str(p.progress.points)],
		["🏅 Badges", func(p): return str(p.progress.badge_count())],
		["👻 Spirits caught", func(p): return str(p.stat("catches"))],
		["💨 Missed catches", func(p): return str(p.stat("escapes"))],
		["📦 Spirits owned", func(p): return str(p.team.size() + p.pc.size())],
		["✨ Evolutions", func(p): return str(p.stat("evolutions"))],
		["⚔ Battles won", func(p): return "%d / %d" % [p.stat("wins"), p.stat("battles")]],
		["🤺 Clash wins", func(p): return str(p.stat("clash_wins"))],
		["🌫 Haunted Four wins", func(p): return str(p.progress.elite_wins)],
		["🃏 Cards played", func(p): return str(p.stat("cards_played"))],
		["💰 Gold left", func(p): return str(p.inventory.gold)],
		["🎲 Average roll", func(p): return "%.1f" % (float(p.stat("dice_total")) / p.stat("rolls")) if p.stat("rolls") > 0 else "—"],
		["🔄 Turns", func(p): return str(p.stat("turns"))],
		["❓ Events", func(p): return str(p.stat("events"))],
		["🎮 Minigames", func(p): return str(p.stat("comps"))],
		["🏘 Town visits", func(p): return str(p.stat("town_visits"))],
	]

# A table: one column per player (name in their colour), one row per stat; the
# best value in each row is gold.
func _fill_stats() -> void:
	for c in _stats_box.get_children():
		c.queue_free()
	var head := Label.new()
	var mins := 0
	var board := get_tree().current_scene
	if board != null and board.get("hud") != null and board.hud.get("elapsed") != null:
		mins = int(float(board.hud.elapsed) / 60.0)
	head.text = "%d turns%s" % [GameState.turn_count, "  ·  %d min" % mins if mins > 0 else ""]
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 14)
	head.modulate = Color(1, 1, 1, 0.7)
	_stats_box.add_child(head)
	var grid := GridContainer.new()
	grid.columns = GameState.players.size() + 1
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 3)
	_stats_box.add_child(grid)
	grid.add_child(Label.new())
	for p in GameState.players:
		grid.add_child(_cell(p.player_name, p.color, 15))
	for row in _stat_rows():
		grid.add_child(_cell(row[0], Color(1, 1, 1, 0.85), 14, HORIZONTAL_ALIGNMENT_LEFT))
		var vals: Array = GameState.players.map(func(p): return String(row[1].call(p)))
		var best := -INF
		for v in vals:
			if v.is_valid_float() or v.split(" ")[0].is_valid_float():
				best = maxf(best, float(v.split(" ")[0]))
		for v in vals:
			var top: bool = best > 0 and v.split(" ")[0].is_valid_float() and float(v.split(" ")[0]) == best
			grid.add_child(_cell(v, Color("ffd24d") if top else Color.WHITE, 14))

func _cell(text: String, color: Color, size: int, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.custom_minimum_size.x = 70 if align == HORIZONTAL_ALIGNMENT_CENTER else 150
	return l

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
