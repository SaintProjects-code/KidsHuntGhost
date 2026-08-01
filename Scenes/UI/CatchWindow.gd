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
var _cpu_view: bool = false   # spectating a CPU's throw: buttons stay locked
var _title: Label
var _sprite: TextureRect
var _info: Label
var _catch_lbl: Label
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

	_catch_lbl = Label.new()
	_catch_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_catch_lbl.add_theme_color_override("font_color", Color("f0c36a"))
	col.add_child(_catch_lbl)

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
	_cpu_view = false
	_leave_btn.disabled = false
	_result.text = ""
	_fight_btn.hide()
	_title.text = "Catch %s?" % spirit.get("name", "?")
	_sprite.texture = SpiritsData.sprite_tex(spirit.get("name", ""), "front")
	var note := "  (weakened from battle!)" if fought_first else ""
	_info.text = "Type: %s  |  %s%s" % [SpiritsData.type_text(spirit), SpiritsData.star_text(spirit.get("stars", 0)), note]
	CatchSystem.ensure_catch_numbers(spirit)
	_update_catch_label()
	_refresh_balls()

# The wild spirit's winning d6 faces + how many throws remain.
func _update_catch_label() -> void:
	var parts: Array = []
	for n in _spirit.get("catch_numbers", []):
		parts.append(str(n))
	var left: int = maxi(0, CatchSystem.MAX_TRIES - int(_spirit.get("catch_tries", 0)))
	_catch_lbl.text = "🎲 Catches on %s   ·   %d roll%s left" % [
		", ".join(parts), left, "" if left == 1 else "s"]

# Spectator mode for CPU throws: everything locked, the window just narrates.
func lock_for_cpu() -> void:
	_cpu_view = true
	_throw_btn.disabled = true
	_leave_btn.disabled = true
	_fight_btn.hide()

# Fill the ball dropdown: the balls the player has, plus a bare-handed option.
func _refresh_balls() -> void:
	_ball_option.clear()
	_balls.clear()
	var inv = GameState.players[_player_index].inventory
	for ball in [&"spirit_ball", &"master_ball"]:
		var n: int = inv.ball_count(ball)
		if n > 0:
			_ball_option.add_item("%s ×%d" % [BALL_LABELS.get(ball, String(ball)), n])
			_balls.append(ball)
	# You can always try bare-handed — no ball bonus, just the base d6 roll.
	_ball_option.add_item("Bare hands (no bonus)")
	_balls.append(&"none")
	_throw_btn.disabled = _cpu_view
	_ball_option.visible = true

func _on_throw() -> void:
	if _balls.is_empty():
		return
	var ball: StringName = _balls[_ball_option.selected]
	# a real ball is consumed; bare hands cost nothing (and add no bonus)
	if ball == &"spirit_ball" or ball == &"master_ball":
		GameState.players[_player_index].inventory.balls[ball] -= 1
	_throw_btn.disabled = true
	EventBus.catch_attempted.emit(_player_index, _spirit, ball)

func _on_succeeded(idx: int, spirit: Dictionary) -> void:
	if not visible or idx != _player_index:
		return
	var roll: int = int(spirit.get("_roll", 0))
	var rolled: String = "Auto-catch! " if roll == 0 else "You rolled a %d! " % roll
	if GameState.players[idx].pc.has(spirit):
		_result.text = "%sGotcha! %s was sent to the PC (team full)!" % [rolled, spirit.get("name", "?")]
	else:
		_result.text = "%sGotcha! %s was caught!" % [rolled, spirit.get("name", "?")]
	await get_tree().create_timer(1.1).timeout
	done.emit("caught")

# A miss keeps the window open: throw again, fight it, or leave — unless the
# spirit has broken free too many times, in which case it runs away.
func _on_failed(idx: int, s: Dictionary) -> void:
	if not visible or idx != _player_index:
		return
	var roll: int = int(s.get("_roll", 0))
	_update_catch_label()
	if int(s.get("catch_tries", 0)) >= CatchSystem.MAX_TRIES:
		_result.text = "You rolled a %d… %s ran away!" % [roll, _spirit.get("name", "?")]
		_throw_btn.disabled = true
		_ball_option.visible = false
		_fight_btn.hide()
		await get_tree().create_timer(1.2).timeout
		done.emit("left")
		return
	_result.text = "You rolled a %d — it broke free! Try again?" % roll
	_refresh_balls()
	if _balls.is_empty():
		_result.text = "You rolled a %d — it broke free! No balls left…" % roll
	if not _fought_first and not _cpu_view:
		_fight_btn.show()
