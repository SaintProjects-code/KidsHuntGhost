extends MenuWindow
## Throw a ball at the wild spirit. Shown via UIManager.
## present(player_index, spirit, fought_first); emits done(outcome) where
## outcome is "caught", "left", or "fight".
##
## A miss does NOT end the encounter: the spirit stays, and the player can
## throw again (if they have balls), switch to fighting it, or leave.
## After a battle (fought_first) the fight option stays hidden.
##
## Uses the existing catch pipeline: emits EventBus.catch_attempted and listens
## for catch_succeeded / catch_failed (so SpiritsProgressionSystem still runs).

signal done(outcome: String)

const BALL_LABELS := { &"spirit_ball": "Spirit Ball", &"master_ball": "Master Ball" }

var _player_index: int = -1
var _spirit: Dictionary
var _fought_first: bool = false
var _title: Label
var _sprite: TextureRect
var _info: Label
var _ball_option: OptionButton
var _throw_btn: Button
var _fight_btn: Button
var _leave_btn: Button
var _result: Label
var _balls: Array = []   # ball StringNames available, parallel to option items

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	EventBus.catch_succeeded.connect(_on_succeeded)
	EventBus.catch_failed.connect(_on_failed)
	hide()

func _build() -> void:
	var col := _init_window(480, 0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 22)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_title)

	_sprite = TextureRect.new()
	_sprite.custom_minimum_size = Vector2(110, 110)
	_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(_sprite)

	_info = Label.new()
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_info)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)
	_ball_option = OptionButton.new()
	row.add_child(_ball_option)
	_throw_btn = Button.new()
	_throw_btn.text = "Throw!"
	_throw_btn.focus_mode = Control.FOCUS_NONE
	_throw_btn.pressed.connect(_on_throw)
	row.add_child(_throw_btn)

	_result = Label.new()
	_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_result)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(actions)
	_fight_btn = _button("⚔ Fight it instead", func(): done.emit("fight"), 38)
	_fight_btn.hide()
	actions.add_child(_fight_btn)
	_leave_btn = _button("Leave", func(): done.emit("left"), 38)
	actions.add_child(_leave_btn)

func present(player_index: int, spirit: Dictionary, fought_first: bool = false) -> void:
	_player_index = player_index
	_spirit = spirit
	_fought_first = fought_first
	_result.text = ""
	_fight_btn.hide()
	_title.text = "Catch %s?" % spirit.get("name", "?")
	_sprite.texture = SpiritsData.sprite_tex(spirit.get("name", ""), "front")
	var note := "  (weakened from battle!)" if fought_first else ""
	_info.text = "Type: %s  |  %s%s" % [spirit.get("type", ""), SpiritsData.star_text(spirit.get("stars", 0)), note]
	_refresh_balls()

# Fill the ball dropdown with whatever the player actually has.
func _refresh_balls() -> void:
	_ball_option.clear()
	_balls.clear()
	var inv = GameState.players[_player_index].inventory
	for ball in [&"spirit_ball", &"master_ball"]:
		var n: int = inv.ball_count(ball)
		if n > 0:
			_ball_option.add_item("%s ×%d" % [BALL_LABELS.get(ball, String(ball)), n])
			_balls.append(ball)
	_throw_btn.disabled = _balls.is_empty()
	_ball_option.visible = not _balls.is_empty()
	if _balls.is_empty() and _result.text == "":
		_result.text = "No balls left!"

func _on_throw() -> void:
	if _balls.is_empty():
		return
	var ball: StringName = _balls[_ball_option.selected]
	GameState.players[_player_index].inventory.balls[ball] -= 1
	_throw_btn.disabled = true
	EventBus.catch_attempted.emit(_player_index, _spirit, ball)

func _on_succeeded(idx: int, spirit: Dictionary) -> void:
	if not visible or idx != _player_index:
		return
	if GameState.players[idx].pc.has(spirit):
		_result.text = "Gotcha! %s was sent to the PC (team full)!" % spirit.get("name", "?")
	else:
		_result.text = "Gotcha! %s was caught!" % spirit.get("name", "?")
	await get_tree().create_timer(1.1).timeout
	done.emit("caught")

# A miss keeps the window open: throw again, fight it, or leave.
func _on_failed(idx: int, _s: Dictionary) -> void:
	if not visible or idx != _player_index:
		return
	_result.text = "It broke free! Try again?"
	_refresh_balls()
	if _balls.is_empty():
		_result.text = "It broke free! No balls left…"
	if not _fought_first:
		_fight_btn.show()
