extends Control
## Board HUD drawn over the map:
##   • top-left play timer
##   • top-right info card for the active player (PlayerPanel.tscn)
##   • bottom-right HAND: the active player's cards. Click a field card
##     to play it on your turn; tactic cards (charms too) are played in battle.
##   • the dice tray that animates every board roll
##   • TEAM / MAP / LOG / DEV buttons (nodes in Board.tscn, wired here)
## Menus opened here go through UIManager's overlay slot.

const PLAYER_PANEL := preload("res://Scenes/Board/PlayerPanel.tscn")
const CARD_SCALE := 0.9   # (was 0.72 — too small to read on a TV)
const HAND_CARD := Vector2(60, 82)   # 7 fit beside the action bar

var board                        # the Board (set right after it adds us)
var elapsed: float = 0.0         # play time, saved with the game

var _players_col: Control
var _timer_label: Label
var _room_label: Label           # 📱 "Room KXRT · 192.168.1.20:8080" while phones can join
var _last_sig := ""
var _hand_title: Label
var _hand_row: HBoxContainer
var _dice_tray: HBoxContainer
var _dice_total: Label
var _stats_menu: Control
var _team_menu: Control
var _dev_window: Control
var _log_window: Control
var _target_window: Control

func _ready() -> void:
	_wire_buttons()
	_timer_label = UIKit.label("00:00", 22)
	_timer_label.position = Vector2(176, 24)
	add_child(_timer_label)
	_room_label = UIKit.label("", 14, UIKit.GOLD)
	_room_label.position = Vector2(176, 52)
	_room_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_room_label.add_theme_constant_override("outline_size", 4)
	add_child(_room_label)
	_build_player_column()
	_build_hand()
	_build_dice_tray()
	# action menus live on their OWN high layer, above the event/battle windows
	var menu_layer := CanvasLayer.new()
	menu_layer.layer = 30
	menu_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(menu_layer)
	_stats_menu = preload("res://Scenes/UI/StatsMenu.gd").new()
	_team_menu = preload("res://Scenes/UI/TeamMenu.gd").new()
	_dev_window = preload("res://Scenes/UI/DevWindow.gd").new()
	_log_window = preload("res://Scenes/UI/LogWindow.gd").new()   # hears EventBus from turn 1
	_target_window = preload("res://Scenes/UI/CardTargetWindow.gd").new()
	for m in [_stats_menu, _team_menu, _dev_window, _log_window, _target_window]:
		menu_layer.add_child(m)
		m.process_mode = Node.PROCESS_MODE_ALWAYS
	_stats_menu.closed.connect(_open_team)   # Stats goes BACK to the party screen
	_team_menu.stats_requested.connect(func(s):
		_stats_menu.show_spirit(s)
		UIManager.open_overlay(_stats_menu))
	for m in [_dev_window, _log_window]:
		m.closed.connect(func(): UIManager.close_overlay())
	EventBus.turn_started.connect(_on_turn_started)
	EventBus.hand_changed.connect(_on_hand_changed)
	EventBus.points_awarded.connect(_on_points)
	_refresh_all()

func _process(delta: float) -> void:
	elapsed += delta
	_timer_label.text = "%02d:%02d" % [int(elapsed) / 60, int(elapsed) % 60]
	_room_label.text = "📱 Room %s · %s" % [Remote.code, Remote.phone_url().trim_prefix("http://")] if Remote.is_on() else ""
	# gold, cards, badges and spirits change all over the place — poll a
	# cheap snapshot instead of wiring every signal
	var sig := _player_sig()
	if sig != _last_sig:
		_last_sig = sig
		_refresh_players()

func _player_sig() -> String:
	var i: int = GameState.current_player_index
	if i < 0 or i >= GameState.players.size():
		return "-"
	var p: PlayerData = GameState.players[i]
	return "%d|%d|%d|%s|%s|%s" % [i, p.progress.points, p.inventory.gold, str(p.progress.badges),
		str(p.inventory.hand), str(p.team.map(func(m): return m.get("name", "")))]

func _on_turn_started(_i: int) -> void:
	UIManager.close_overlay()
	_refresh_all()

func _on_hand_changed(_i: int) -> void:
	_refresh_hand()

func _refresh_all() -> void:
	_refresh_players()
	_refresh_hand()

# ---------------- buttons ----------------

func _wire_buttons() -> void:
	var root := get_parent()
	var bar := root.get_node("ActionBar")
	(bar.get_node("TeamButton") as Button).pressed.connect(_open_team)
	(bar.get_node("MapButton") as Button).pressed.connect(func(): root._on_view_map_pressed())
	var util := root.get_node("UtilRow")
	(util.get_node("LogButton") as Button).pressed.connect(func(): UIManager.open_overlay(_log_window))
	var dev_btn: Button = util.get_node("DevButton")
	dev_btn.visible = GameState.dev_mode   # only games started from the menu's DEV button
	dev_btn.pressed.connect(func():
		_dev_window.present(GameState.current_player_index)
		UIManager.open_overlay(_dev_window))

func _open_team() -> void:
	_team_menu.present(GameState.current_player_index)
	UIManager.open_overlay(_team_menu)

# ---------------- player card ----------------

func _build_player_column() -> void:
	# a plain Control so the card's scale is respected (containers ignore it)
	_players_col = Control.new()
	_players_col.anchor_left = 1.0
	_players_col.anchor_right = 1.0
	_players_col.anchor_bottom = 1.0
	_players_col.offset_top = 12.0
	_players_col.offset_right = -16.0
	_players_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_players_col)

func _refresh_players() -> void:
	UIKit.clear(_players_col)
	var i: int = GameState.current_player_index
	if i < 0 or i >= GameState.players.size():
		return
	var card: Control = PLAYER_PANEL.instantiate()
	_players_col.add_child(card)
	card.scale = Vector2(CARD_SCALE, CARD_SCALE)
	card.present(GameState.players[i], true)
	var sz: Vector2 = card.get_combined_minimum_size()
	card.size = sz
	_players_col.offset_left = -(sz.x * card.scale.x + 16.0)

func _on_points(i: int, amount: int) -> void:
	Sfx.play("points")
	if i == GameState.current_player_index:
		Juice.float_text(self, Vector2(size.x - 140, 150), "+%d pts" % amount, UIKit.GOLD, 26)

# ---------------- hand ----------------

func _build_hand() -> void:
	var box := UIKit.vbox(2)
	box.anchor_left = 1.0
	box.anchor_right = 1.0
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.offset_left = -(HAND_CARD.x + 6) * Balance.HAND_SIZE - 16
	box.offset_right = -16
	box.offset_top = -HAND_CARD.y - 40
	box.offset_bottom = -12
	box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_hand_title = UIKit.label("🃏 Hand", 15, UIKit.GOLD)
	_hand_title.add_theme_color_override("font_outline_color", Color.BLACK)
	_hand_title.add_theme_constant_override("outline_size", 4)
	box.add_child(_hand_title)
	_hand_row = UIKit.hbox(6)
	_hand_row.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(_hand_row)

func _refresh_hand() -> void:
	if _hand_row == null:
		return
	UIKit.clear(_hand_row)
	var i: int = GameState.current_player_index
	if i < 0 or i >= GameState.players.size():
		return
	var p: PlayerData = GameState.players[i]
	_hand_title.text = "🃏 %s's hand  %d/%d" % [p.player_name, p.inventory.hand.size(), Balance.HAND_SIZE]
	for key in p.inventory.hand:
		var cv := CardView.new("" if p.is_cpu else key, HAND_CARD)
		cv.face_down = Remote.has_phone(i)   # 📱 a phone player's hand is on their phone
		if not p.is_cpu:
			cv.pressed.connect(_on_card_pressed.bind(i, key, cv))
		_hand_row.add_child(cv)

func _on_card_pressed(i: int, key: String, cv: CardView) -> void:
	if board == null or not board.can_act_on_board(i):
		_nope(cv, "Wait for your turn")
		return
	var kind := CardsData.kind_of(key)
	if kind == "tactic":
		_nope(cv, "Play tactics in battle!")
		return
	if kind == "capture":
		_nope(cv, "Lanterns are for catching ghosts!")
		return
	var target = await _pick_target(i, key)
	if target == null:
		return
	if key == "warp_door" and not board.before_roll(i):
		_nope(cv, "Warp before you roll")
		return
	var msg: String = await CardSystem.play_field(i, key, target)
	if msg != "":
		Juice.float_text(self, Vector2(size.x * 0.5, size.y * 0.45), msg, Color("7fe0d0"), 22)

# What the card is played on. null = cancelled / nothing valid.
func _pick_target(i: int, key: String):
	var p: PlayerData = GameState.players[i]
	match String(CardsData.card(key).get("target", "")):
		"spirit", "fainted":
			_target_window.present(p, key)
			UIManager.open_overlay(_target_window)
			var t = await _target_window.chose
			UIManager.close_overlay()
			return t
		"player":
			var others: Array = []
			for j in GameState.players.size():
				if j != i and not GameState.players[j].inventory.hand.is_empty():
					others.append(j)
			if others.is_empty():
				Juice.float_text(self, size * 0.5, "Nobody has cards to steal", UIKit.BAD)
				return null
			var labels: Array = others.map(func(j): return "%s (%d cards)" % [GameState.players[j].player_name, GameState.players[j].inventory.hand.size()])
			labels.append("✖ Cancel")
			var pick: int = await board._show_choice("Steal from whom?", labels)
			return others[pick] if pick < others.size() else null
		"city":
			if not board.before_roll(i):
				return null
			var town: String = await board.pick_town("Warp to which town?", board.visited_towns(i))
			return town if town != "" else null
	return true

func _nope(cv: Control, text: String) -> void:
	Sfx.play("error")
	Juice.shake(cv, 5.0)
	Juice.float_text(self, Vector2(size.x - 220, size.y - 150), text, UIKit.BAD, 18)

# ---------------- dice tray ----------------

func _build_dice_tray() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var col := UIKit.vbox(8)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(col)
	_dice_tray = UIKit.hbox(18)
	_dice_tray.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(_dice_tray)
	_dice_total = UIKit.label("", 40, UIKit.GOLD)
	_dice_total.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dice_total.add_theme_color_override("font_outline_color", Color.BLACK)
	_dice_total.add_theme_constant_override("outline_size", 8)
	col.add_child(_dice_total)
	col.modulate.a = 0.0

# Tumble the board dice in the middle of the screen, show the total, fade out.
func show_roll(faces: Array, bonus: int, color: Color) -> void:
	var col: Control = _dice_tray.get_parent()
	UIKit.clear(_dice_tray)
	_dice_total.text = ""
	col.modulate.a = 1.0
	var dice: Array = []
	for f in faces:
		var d := DiceView.new(72, 6, Color.WHITE.lerp(color, 0.25))
		_dice_tray.add_child(d)
		dice.append(d)
	await get_tree().process_frame
	for k in dice.size() - 1:
		dice[k].roll(faces[k], 0.75)
	await dice.back().roll(faces.back(), 0.75)
	var total := bonus
	for f in faces:
		total += int(f)
	_dice_total.text = ("%d" % total) if bonus == 0 and faces.size() == 1 else \
		"%s%s = %d" % [" + ".join(faces.map(func(f): return str(f))), (" + %d" % bonus) if bonus != 0 else "", total]
	Juice.pop(_dice_total, 1.4, 0.3)
	await get_tree().create_timer(0.55).timeout
	var tw := col.create_tween()
	tw.tween_property(col, "modulate:a", 0.0, 0.25)
	await tw.finished
