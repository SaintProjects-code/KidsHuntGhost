extends Control
## Board HUD: the on-screen layout drawn on top of the board.
##
##   • ITEM / PKMN / MAP / LOG / DEV buttons live as real nodes in Board.tscn
##     (ActionBar + UtilRow, under BoardUI/Root) — this script just wires them.
##   • top-left play timer
##   • top-right player-info panels (name, badges, items, points, party), with
##     the active player highlighted
##
## Parented under BoardUI/Root by Board.gd so everything here inherits
## MenuTheme.tres like Roll Dice / End Turn / Settings do.
## Menus opened from here go through UIManager so only one is ever visible.

# The card layout lives in its own scene so it can be edited in the editor.
# To resize the WHOLE card, set Transform -> Scale on the scene's root node;
# the column here follows both the card's content size and its scale.
const PLAYER_PANEL := preload("res://Scenes/Board/PlayerPanel.tscn")
const CARD_GAP := 10.0
const CARD_SCALE := 0.72   # shrink the whole player card

var _players_col: Control
var _timer_label: Label
var _elapsed: float = 0.0
var _last_sig: String = ""            # snapshot of the shown player's state
var _placeholders: Dictionary = {}   # button name -> placeholder Control
var _stats_menu: Control             # the per-spirit Stats screen
var _team_menu: Control              # the party screen (PKMN button)
var _bag_window: Control             # ITEM button → inventory/bag
var _dev_window: Control             # DEV button → debug helpers
var _log_window: Control             # LOG button → colour-coded game log

func _ready() -> void:
	_wire_buttons()
	_build_timer()
	_build_player_column()
	_refresh_players()
	# The action-button menus live on their OWN high layer (above the event/
	# battle windows at 12) so they always pop ON TOP — while the action bar
	# itself renders on the board chrome BELOW those windows.
	var menu_layer := CanvasLayer.new()
	menu_layer.layer = 30
	menu_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(menu_layer)
	_stats_menu = preload("res://Scenes/UI/StatsMenu.gd").new()
	menu_layer.add_child(_stats_menu)
	# Stats is always opened from a team card, so closing it goes BACK to the
	# party screen instead of dismissing the overlay entirely.
	_stats_menu.closed.connect(_open_team)
	_team_menu = preload("res://Scenes/UI/TeamMenu.gd").new()
	menu_layer.add_child(_team_menu)
	_team_menu.stats_requested.connect(_on_stats_requested)
	_bag_window = preload("res://Scenes/UI/ItemWindow.gd").new()
	menu_layer.add_child(_bag_window)
	_bag_window.closed.connect(func(): UIManager.close_overlay())
	_dev_window = preload("res://Scenes/UI/DevWindow.gd").new()
	menu_layer.add_child(_dev_window)
	_dev_window.closed.connect(func(): UIManager.close_overlay())
	# Created at game start so it hears every EventBus signal from turn 1.
	_log_window = preload("res://Scenes/UI/LogWindow.gd").new()
	menu_layer.add_child(_log_window)
	_log_window.closed.connect(func(): UIManager.close_overlay())
	# The action menus stay clickable even while the game is paused for an
	# event (the HUD itself is Pausable so the timer still stops).
	for m in [_stats_menu, _team_menu, _bag_window, _dev_window, _log_window]:
		m.process_mode = Node.PROCESS_MODE_ALWAYS
	# Keep the panels live as the game changes.
	for sig in ["turn_started", "points_awarded", "catch_succeeded", "spirit_evolved", "badge_earned"]:
		if EventBus.has_signal(sig):
			EventBus.connect(sig, Callable(self, "_on_state_changed"))
	# A new turn clears any lingering action menu.
	EventBus.turn_started.connect(func(_i): UIManager.close_overlay())

func _process(delta: float) -> void:
	_elapsed += delta
	if _timer_label:
		_timer_label.text = _format_time(_elapsed)
	# Catch every game change (gold, items, badges, spirits in/out, points) — the
	# few EventBus signals below miss item/gold changes, so poll a cheap snapshot.
	var sig := _player_sig()
	if sig != _last_sig:
		_last_sig = sig
		_refresh_players()

func _on_state_changed(_a = null, _b = null) -> void:
	_refresh_players()
	_last_sig = _player_sig()

# A compact snapshot of everything the card shows for the active player.
func _player_sig() -> String:
	var i: int = GameState.current_player_index
	if i < 0 or i >= GameState.players.size():
		return "-"
	var p: PlayerData = GameState.players[i]
	var team_sig := ""
	for m in p.team:
		team_sig += String(m.get("name", "")) + ","
	return "%d|%d|%d|%s|%s|%s|%s" % [
		i, p.progress.points, p.inventory.gold,
		str(p.progress.badges), str(p.inventory.balls),
		str(p.inventory.items), team_sig,
	]

# ---------------- action buttons (nodes live in Board.tscn) ----------------

func _wire_buttons() -> void:
	var root := get_parent()
	var bar := root.get_node("ActionBar")
	(bar.get_node("BagButton") as Button).pressed.connect(func():
		_bag_window.present_bag(GameState.current_player_index)
		UIManager.open_overlay(_bag_window))
	(bar.get_node("PkmnButton") as Button).pressed.connect(_open_team)
	(bar.get_node("MapButton") as Button).pressed.connect(func():
		if root.has_method("_on_view_map_pressed"):
			root._on_view_map_pressed())
	var util := root.get_node("UtilRow")
	(util.get_node("LogButton") as Button).pressed.connect(func():
		_log_window.present()
		UIManager.open_overlay(_log_window))
	# DEV tools only exist in games started from the menu's DEV button;
	# normal (local) games never show it.
	var dev_btn: Button = util.get_node("DevButton")
	dev_btn.visible = GameState.dev_mode
	dev_btn.pressed.connect(func():
		_dev_window.present(GameState.current_player_index)
		UIManager.open_overlay(_dev_window))

# PKMN button → the active player's party screen.
func _open_team() -> void:
	var p: PlayerData = GameState.players[GameState.current_player_index]
	_team_menu.present(p)
	UIManager.open_overlay(_team_menu)

# A team card's "Stats" button → the per-spirit Stats screen.
func _on_stats_requested(spirit: Dictionary) -> void:
	_stats_menu.show_spirit(spirit)
	UIManager.open_overlay(_stats_menu)

# ---------------- top-left timer ----------------

func _build_timer() -> void:
	_timer_label = Label.new()
	_timer_label.add_theme_font_size_override("font_size", 22)
	_timer_label.position = Vector2(176, 24)
	_timer_label.text = "00:00"
	add_child(_timer_label)

func _format_time(t: float) -> String:
	var total := int(t)
	return "%02d:%02d" % [total / 60, total % 60]

# ---------------- top-right player panels ----------------

func _build_player_column() -> void:
	# A plain Control (not a VBoxContainer) so the cards' Scale is respected —
	# containers ignore scale when laying children out. Cards are stacked
	# manually in _refresh_players using their scaled sizes.
	_players_col = Control.new()
	_players_col.anchor_left = 1.0
	_players_col.anchor_top = 0.0
	_players_col.anchor_right = 1.0
	_players_col.anchor_bottom = 1.0
	_players_col.offset_left = -16.0   # widened per-card below
	_players_col.offset_top = 12.0
	_players_col.offset_right = -16.0
	_players_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_players_col)

func _refresh_players() -> void:
	if _players_col == null:
		return
	for c in _players_col.get_children():
		c.queue_free()
	# Only the active player's card is shown; it re-renders on turn_started
	# (and the other refresh signals), so it swaps as turns change.
	var i: int = GameState.current_player_index
	if i < 0 or i >= GameState.players.size():
		return
	var card: Control = PLAYER_PANEL.instantiate()
	_players_col.add_child(card)
	card.scale = Vector2(CARD_SCALE, CARD_SCALE)   # make the whole card smaller
	card.present(GameState.players[i], true)
	# Size to content (never below the scene's Custom Minimum Size), then
	# anchor so the card ends 16px from the right edge, honouring its Scale.
	var sz: Vector2 = card.get_combined_minimum_size()
	card.size = sz
	card.position = Vector2.ZERO
	_players_col.offset_left = -(sz.x * card.scale.x + 16.0)

# ---------------- placeholder menus (replaced as real menus are built) ----------------

func _get_placeholder(btn_name: String) -> Control:
	if _placeholders.has(btn_name) and is_instance_valid(_placeholders[btn_name]):
		return _placeholders[btn_name]
	var panel := Panel.new()
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -210.0
	panel.offset_top = -100.0
	panel.offset_right = 210.0
	panel.offset_bottom = 100.0
	panel.hide()
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 24.0
	vb.offset_top = 24.0
	vb.offset_right = -24.0
	vb.offset_bottom = -24.0
	vb.add_theme_constant_override("separation", 18)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vb)
	var lbl := Label.new()
	lbl.text = "%s — coming soon" % btn_name
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(lbl)
	var close := Button.new()
	close.text = "Close"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func(): UIManager.close())
	vb.add_child(close)
	add_child(panel)
	_placeholders[btn_name] = panel
	return panel
