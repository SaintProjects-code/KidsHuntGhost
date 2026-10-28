extends MenuWindow
## The wild-ghost CATCH, a dice roll:
##   pick which Lantern cards to spend (click them, or press 1–7) — each adds
##   dice to your 1 free die — then ROLL. Add the dice up; reach the target and
##   it's caught. Two tries: a miss raises the target, a second miss and it
##   flees. A Soul Lantern is a sure catch. Your chance is shown before you roll.
## present(idx, spirit); emits done("caught" | "fled" | "left").
## CPU catches play themselves in the same window.

signal done(outcome: String)

const CARD := Vector2(60, 82)

var _idx := -1
var _spirit: Dictionary
var _cpu := false
var _busy := false
var _over := false
var _picked: Array = []   # Lantern cards chosen for the next roll
var _title: Label
var _sprite: TextureRect
var _info: Label
var _target_lbl: Label
var _cards_row: HBoxContainer
var _odds: Label
var _dice_row: HBoxContainer
var _sum: Label
var _result: Label
var _roll_btn: Button
var _leave_btn: Button

func _ready() -> void:
	var col := _init_window(620, 0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	_title = _title_label("", 24)
	col.add_child(_title)
	# the ghost beside its info, to keep the window short enough for the screen
	var top := UIKit.hbox(14)
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(top)
	_sprite = UIKit.sprite(null, Vector2(96, 96))
	_sprite.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_sprite)
	var facts := UIKit.vbox(4)
	facts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(facts)
	_info = UIKit.label("", 15)
	facts.add_child(_info)
	_target_lbl = UIKit.label("", 20, UIKit.GOLD)
	facts.add_child(_target_lbl)
	_cards_row = UIKit.hbox(6)
	_cards_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_cards_row.custom_minimum_size.y = CARD.y + 8
	col.add_child(_cards_row)
	_odds = UIKit.wrap_label("", 16, 580)
	col.add_child(_odds)
	var roll_row := UIKit.hbox(16)
	roll_row.alignment = BoxContainer.ALIGNMENT_CENTER
	roll_row.custom_minimum_size.y = 60
	col.add_child(roll_row)
	_dice_row = UIKit.hbox(10)
	roll_row.add_child(_dice_row)
	_sum = UIKit.label("", 22)
	_sum.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	roll_row.add_child(_sum)
	_result = UIKit.wrap_label("", 17, 580)
	col.add_child(_result)
	var actions := UIKit.hbox(10)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(actions)
	_roll_btn = _button("🎲 Roll!  [Space]", _roll, 48, "gold")
	_roll_btn.custom_minimum_size.x = 220
	actions.add_child(_roll_btn)
	_leave_btn = _button("Leave", func(): _finish("left"), 48)
	actions.add_child(_leave_btn)
	EventBus.catch_succeeded.connect(_on_succeeded)
	EventBus.catch_failed.connect(_on_failed)
	hide()

func _player() -> PlayerData:
	return GameState.players[_idx]

func present(idx: int, spirit: Dictionary, _unused: bool = false) -> void:
	_idx = idx
	_spirit = spirit
	_cpu = _player().is_cpu
	_busy = false
	_over = false
	_picked = []
	_result.text = ""
	_sum.text = ""
	UIKit.clear(_dice_row)
	_sprite.texture = SpiritsData.sprite_tex(spirit.get("name", ""), "front")
	_sprite.modulate = Color.WHITE
	_sprite.scale = Vector2.ONE
	_sprite.rotation = 0.0
	_title.text = "A wild %s appeared!" % spirit.get("name", "?")
	_info.text = "%s  ·  Stage %d%s" % [SpiritsData.type_text(spirit), spirit.get("stage", 1),
		"  ·  🍬 lured (+%d to the roll)" % Balance.CATCH_LURE_BONUS if spirit.get("_lured", false) else ""]
	_refresh()
	if _cpu:
		_cpu_run()

func _refresh() -> void:
	var tries := Balance.CATCH_THROWS - int(_spirit.get("catch_fails", 0))
	var need_dice := CatchSystem.min_dice(_spirit)
	_target_lbl.text = "🎯 Roll %d+ to catch it%s  ·  tries left: %d" % [
		CatchSystem.target_for(_spirit) - CatchSystem.bonus_for(_spirit),
		"  (needs %d+ dice)" % need_dice if need_dice > 1 else "", tries]
	UIKit.clear(_cards_row)
	var lanterns: Array = _player().inventory.lanterns()
	var claimed := _picked.duplicate()
	for key in lanterns:
		var cv := CardView.new(key, CARD)
		cv.armed = claimed.has(key)
		if cv.armed:
			claimed.erase(key)
		cv.disabled = _cpu or _busy or _over
		cv.pressed.connect(_toggle.bind(key, cv))
		_cards_row.add_child(cv)
	if lanterns.is_empty():
		_cards_row.add_child(UIKit.label("— no Lanterns: you roll just the free die —", 13))
	var dice := CatchSystem.dice_for(_picked)
	_odds.text = "✨ Soul Lantern — a sure catch!" if CatchSystem.is_sure(_picked) else \
		"Tap Lanterns for more dice  ·  Roll %d %s  →  %d%% chance" % [dice, "die" if dice == 1 else "dice",
			CatchSystem.chance(_spirit, _picked)]
	_roll_btn.text = ("✨ Catch!  [Space]" if CatchSystem.is_sure(_picked) else "🎲 Roll %d!  [Space]" % dice)
	_roll_btn.disabled = _cpu or _busy or _over
	_leave_btn.disabled = _cpu or _busy or _over

func _toggle(key: String, cv: CardView) -> void:
	if _busy or _over:
		return
	if cv.armed:
		_picked.erase(key)
	else:
		_picked.append(key)
	Sfx.play("card", 1.2)
	_refresh()

func _roll() -> void:
	if _busy or _over:
		return
	_busy = true
	var used := _picked.duplicate()
	_picked = []
	for k in used:
		CardSystem.remove(_idx, k)   # Lanterns are spent, hit or miss
	_refresh()
	Sfx.play("whoosh")
	var total := 0
	UIKit.clear(_dice_row)
	if not CatchSystem.is_sure(used):
		var dice: Array = []
		var faces: Array = []
		for d in CatchSystem.dice_for(used):
			var die := DiceView.new(54)
			_dice_row.add_child(die)
			dice.append(die)
			faces.append(randi_range(1, 6))
			total += faces.back()
		await get_tree().process_frame
		for k in dice.size() - 1:
			dice[k].roll(faces[k], 0.8)
		await dice.back().roll(faces.back(), 0.8)
		var bonus := CatchSystem.bonus_for(_spirit)
		_sum.text = "%s%s = %d   vs   %d" % [" + ".join(faces.map(func(f): return str(f))),
			(" + %d lure" % bonus) if bonus > 0 else "", total + bonus, CatchSystem.target_for(_spirit)]
		Juice.pop(_sum)
	for k in 3:   # the lantern's glow pulls at the ghost…
		Sfx.play("wobble", 1.0 + k * 0.08)
		_sprite.pivot_offset = _sprite.size * 0.5
		var tw := _sprite.create_tween()
		tw.tween_property(_sprite, "rotation", 0.25, 0.08)
		tw.tween_property(_sprite, "rotation", -0.25, 0.12)
		tw.tween_property(_sprite, "rotation", 0.0, 0.08)
		await tw.finished
		await get_tree().create_timer(0.1).timeout
	_spirit["_roll"] = total
	EventBus.catch_attempted.emit(_idx, _spirit, used)

func _on_succeeded(idx: int, spirit: Dictionary) -> void:
	if not visible or idx != _idx or spirit != _spirit:
		return
	_over = true
	Sfx.play("caught")
	var tw := _sprite.create_tween().set_parallel(true)
	tw.tween_property(_sprite, "scale", Vector2(0.2, 0.2), 0.25)
	tw.tween_property(_sprite, "modulate", Color(1.5, 1.5, 2.0, 0.0), 0.25)
	var where := "sent to the Spirit Box (team full)" if _player().pc.has(spirit) else "caught"
	_result.text = "Gotcha! %s was %s!" % [spirit.get("name", "?"), where]
	_result.add_theme_color_override("font_color", UIKit.GOOD)
	_refresh()
	await get_tree().create_timer(1.3).timeout
	_finish("caught")

func _on_failed(idx: int, s: Dictionary) -> void:
	if not visible or idx != _idx or s != _spirit:
		return
	Sfx.play("escape")
	Juice.shake(_sprite, 10.0)
	_busy = false
	_result.add_theme_color_override("font_color", UIKit.BAD)
	if int(s.get("catch_fails", 0)) >= Balance.CATCH_THROWS:
		_over = true
		_result.text = "Oh no! %s slipped away into the mist!" % _spirit.get("name", "?")
		_refresh()
		var tw := _sprite.create_tween().set_parallel(true)
		tw.tween_property(_sprite, "modulate:a", 0.0, 0.6)
		await get_tree().create_timer(1.3).timeout
		_finish("fled")
		return
	_result.text = "So close! It's warier now — the target is +%d. One more try!" % Balance.CATCH_FAIL_PENALTY
	_refresh()

func _finish(outcome: String) -> void:
	_over = true
	if outcome != "caught":
		EventBus.log_entry.emit(_idx, "The wild %s got away." % _spirit.get("name", "?") if outcome == "fled"
			else "%s leaves the wild %s alone." % [_player().player_name, _spirit.get("name", "?")], "#aaaaaa")
	done.emit(outcome)

# ── CPU ───────────────────────────────────────────────────────────────────────

# CPU: a Soul Lantern for legendaries; otherwise the fewest Lanterns that give
# good odds (all of them if it never gets there).
func _cpu_pick() -> Array:
	var lanterns: Array = _player().inventory.lanterns()
	if lanterns.has("soul_lantern") and SpiritsData.is_legendary(String(_spirit.get("name", ""))):
		return ["soul_lantern"]
	var pool: Array = lanterns.filter(func(k): return k != "soul_lantern")
	pool.sort_custom(func(a, b): return CardsData.card(a)["dice"] < CardsData.card(b)["dice"])
	var pick: Array = []
	for k in pool:
		if CatchSystem.chance(_spirit, pick) >= 65:
			break
		pick.append(k)
	return pick

func _cpu_run() -> void:
	await get_tree().process_frame   # present() runs before UIManager shows us
	while visible and not _over:
		await get_tree().create_timer(1.0).timeout
		if _over or not visible:
			return
		_picked = _cpu_pick()
		if CatchSystem.chance(_spirit, _picked) <= 0:
			_finish("left")   # out of reach with these Lanterns: keep them for later
			return
		_refresh()
		await get_tree().create_timer(0.7).timeout
		await _roll()
		while _busy and visible and not _over:
			await get_tree().process_frame

func _unhandled_key_input(ev: InputEvent) -> void:
	if not visible or _cpu or _busy or _over:
		return
	if Controls.confirm_pressed(ev):
		get_viewport().set_input_as_handled()
		_roll()
		return
	var n := Controls.number_pressed(ev)
	if n >= 0 and n < _cards_row.get_child_count() and _cards_row.get_child(n) is CardView:
		get_viewport().set_input_as_handled()
		(_cards_row.get_child(n) as CardView).pressed.emit()
