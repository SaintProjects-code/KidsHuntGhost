extends MenuWindow
## Capture a wild spirit: pick a jar, roll the d100. The jar's bonus (plus
## badges, a worn-out spirit, a lure) is added to the roll, and the total has
## to reach the spirit's target. The window shows the odds and animates the
## roll: d100 tumbles → bonus counts up → the jar wobbles → caught / escaped.
##
## present(player_index, spirit, fought_first); emits done("caught"|"left"|"fight").
## A miss keeps the window open (target +10 each time) until the spirit flees.
## Keys: 1–4 pick a jar, Space throws.

signal done(outcome: String)

var _player_index := -1
var _spirit: Dictionary
var _fought_first := false
var _cpu_view := false
var _busy := false
var _title: Label
var _sprite: TextureRect
var _info: Label
var _jar_row: HBoxContainer
var _odds: Label
var _die: DiceView
var _sum: Label
var _throw_btn: Button
var _fight_btn: Button
var _leave_btn: Button
var _result: Label
var _jar := &"ghost_jar"

func _ready() -> void:
	var col := _init_window(520, 0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	_title = _title_label("Catch!", 24)
	col.add_child(_title)
	_sprite = UIKit.sprite(null, Vector2(110, 110))
	_sprite.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(_sprite)
	_info = UIKit.label("", 15)
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_info)
	_jar_row = UIKit.hbox(8)
	_jar_row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(_jar_row)
	_odds = UIKit.label("", 15, UIKit.GOLD)
	_odds.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_odds)
	var roll_row := UIKit.hbox(14)
	roll_row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(roll_row)
	_die = DiceView.new(64, 100, Color("cfe8ff"))
	roll_row.add_child(_die)
	_sum = UIKit.label("", 22)
	_sum.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	roll_row.add_child(_sum)
	_result = UIKit.wrap_label("", 17, 480)
	col.add_child(_result)
	var actions := UIKit.hbox(10)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(actions)
	_throw_btn = _button("🫙 Throw! ⏎", _on_throw, 40)
	_throw_btn.custom_minimum_size.x = 150
	actions.add_child(_throw_btn)
	_fight_btn = _button("⚔ Fight it instead", func(): done.emit("fight"), 40)
	actions.add_child(_fight_btn)
	_leave_btn = _button("Leave", func(): done.emit("left"), 40)
	actions.add_child(_leave_btn)
	hide()

func present(player_index: int, spirit: Dictionary, fought_first: bool = false) -> void:
	_player_index = player_index
	_spirit = spirit
	_fought_first = fought_first
	if fought_first:
		spirit["_fought"] = true
	_cpu_view = false
	_busy = false
	_leave_btn.disabled = false
	_fight_btn.hide()
	_result.text = ""
	_sum.text = ""
	_die.show_face(100)
	_title.text = "Catch %s?" % spirit.get("name", "?")
	_sprite.texture = SpiritsData.sprite_tex(spirit.get("name", ""), "front")
	_sprite.modulate = Color.WHITE
	_sprite.scale = Vector2.ONE
	_info.text = "%s  ·  %s%s" % [SpiritsData.type_text(spirit), SpiritsData.star_text(spirit.get("stars", 0)),
		"  ·  worn out from battle!" if fought_first else ""]
	_jar = _best_owned_jar(false)
	_refresh()

# Spectator mode for CPU throws: everything locked, the window narrates.
func lock_for_cpu() -> void:
	_cpu_view = true
	_jar = _best_owned_jar(true)
	_refresh()

func cpu_jar() -> StringName:
	return _jar

func _inv() -> PlayerData.Inventory:
	return GameState.players[_player_index].inventory

# Humans start on the plainest jar they own. CPUs take the cheapest jar with
# decent odds, and save the Soul Lantern for legendaries.
func _best_owned_jar(cpu: bool) -> StringName:
	var owned: Array = CatchSystem.JAR_ORDER.filter(func(j): return _inv().jar_count(j) > 0)
	if owned.is_empty():
		return &"ghost_jar"
	if not cpu:
		return owned[0]
	var legend := SpiritsData.is_legendary(String(_spirit.get("name", "")))
	if legend and owned.has(&"soul_lantern"):
		return &"soul_lantern"
	var normal: Array = owned.filter(func(j): return j != &"soul_lantern")
	for jar in normal:
		if CatchSystem.chance(_player_index, _spirit, jar) >= 60:
			return jar
	return normal.back() if not normal.is_empty() else owned[0]

func _refresh() -> void:
	UIKit.clear(_jar_row)
	var n := 0
	for jar in CatchSystem.JAR_ORDER:
		var count: int = _inv().jar_count(jar)
		if count <= 0:
			continue
		n += 1
		var b := UIKit.small_button("%d · %s ×%d" % [n, CatchSystem.jar_name(jar), count], _pick_jar.bind(jar), 13)
		b.disabled = _cpu_view or _busy
		if jar == _jar:
			b.modulate = Color(1.3, 1.2, 0.6)
		_jar_row.add_child(b)
	var has_jar: bool = _inv().jar_count(_jar) > 0
	_throw_btn.disabled = not has_jar or _cpu_view or _busy
	_leave_btn.disabled = _cpu_view or _busy
	if not has_jar:
		_odds.text = "No jars left!"
		return
	var target := CatchSystem.target_for(_spirit)
	var parts: Array = CatchSystem.bonus_parts(_player_index, _spirit, _jar)
	var bonus_txt: Array = parts.filter(func(pt): return int(pt[1]) != 0).map(func(pt): return "%s +%d" % [pt[0], pt[1]])
	_odds.text = "Roll d100%s  ≥ %d   →  %d%% chance" % [
		("  + " + " + ".join(bonus_txt)) if not bonus_txt.is_empty() else "", target,
		CatchSystem.chance(_player_index, _spirit, _jar)]

func _pick_jar(jar: StringName) -> void:
	_jar = jar
	_refresh()

func _on_throw() -> void:
	if _busy or _inv().jar_count(_jar) <= 0:
		return
	_busy = true
	_inv().add_jars(_jar, -1)
	_refresh()
	var roll := randi_range(1, 100)
	var bonus := CatchSystem.total_bonus(_player_index, _spirit, _jar)
	var target := CatchSystem.target_for(_spirit)
	Sfx.play("whoosh")
	await _die.roll(roll, 0.9)
	_sum.text = "%d + %d = %d  vs %d" % [roll, bonus, roll + bonus, target]
	Juice.pop(_sum)
	# the jar wobbles three times…
	for k in 3:
		Sfx.play("wobble", 1.0 + k * 0.08)
		var tw := _sprite.create_tween()
		_sprite.pivot_offset = _sprite.size * 0.5
		tw.tween_property(_sprite, "rotation", 0.25, 0.08)
		tw.tween_property(_sprite, "rotation", -0.25, 0.12)
		tw.tween_property(_sprite, "rotation", 0.0, 0.08)
		await tw.finished
		await get_tree().create_timer(0.12).timeout
	_spirit["_roll"] = roll
	EventBus.catch_attempted.emit(_player_index, _spirit, _jar)

# Called by EventBus (through CatchSystem) after a throw.
func _on_succeeded(idx: int, spirit: Dictionary) -> void:
	if not visible or idx != _player_index:
		return
	Sfx.play("caught")
	var tw := _sprite.create_tween()
	tw.tween_property(_sprite, "scale", Vector2(0.2, 0.2), 0.25)
	tw.parallel().tween_property(_sprite, "modulate", Color(1.5, 1.5, 2.0, 0.0), 0.25)
	var where := "sent to the Spirit Box (team full)" if GameState.players[idx].pc.has(spirit) else "caught"
	_result.text = "Gotcha! %s was %s!" % [spirit.get("name", "?"), where]
	_result.add_theme_color_override("font_color", UIKit.GOOD)
	await get_tree().create_timer(1.2).timeout
	done.emit("caught")

func _on_failed(idx: int, s: Dictionary) -> void:
	if not visible or idx != _player_index:
		return
	Sfx.play("escape")
	Juice.shake(_sprite, 10.0)
	_busy = false
	_result.add_theme_color_override("font_color", UIKit.BAD)
	if int(s.get("catch_fails", 0)) >= Balance.CATCH_MAX_FAILS:
		_result.text = "Oh no! %s vanished into the mist!" % _spirit.get("name", "?")
		_busy = true
		_refresh()
		await get_tree().create_timer(1.2).timeout
		done.emit("left")
		return
	_result.text = "It broke free! It's warier now (target +%d)." % Balance.CATCH_FAIL_PENALTY
	_refresh()
	if not _fought_first and not _cpu_view:
		_fight_btn.show()

func _enter_tree() -> void:
	if not EventBus.catch_succeeded.is_connected(_on_succeeded):
		EventBus.catch_succeeded.connect(_on_succeeded)
		EventBus.catch_failed.connect(_on_failed)

func _unhandled_key_input(ev: InputEvent) -> void:
	if not visible or _cpu_view:
		return
	if Controls.confirm_pressed(ev):
		get_viewport().set_input_as_handled()
		_on_throw()
		return
	var n := Controls.number_pressed(ev)
	if n >= 0 and n < _jar_row.get_child_count():
		get_viewport().set_input_as_handled()
		(_jar_row.get_child(n) as Button).pressed.emit()

# CPU throw: same animation, driven from EncounterController.
func cpu_throw() -> void:
	_cpu_view = false
	await _on_throw()
	_cpu_view = true
	_refresh()
