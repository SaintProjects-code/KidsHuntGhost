extends MenuWindow
## The wild-ghost HUNT, start to finish (no battles):
##   1) "A wild X appeared!" — the Spook Duel odds are shown up front
##   2) SPOOK DUEL: your lead's power + 🎲d6 vs the ghost's + 🎲d6 (ties to you).
##      Lose → it runs away. Win → it's spooked (+bonus to every throw).
##   3) CAPTURE: Balance.CATCH_THROWS throws of d100 + jar/badge/spooked/lure
##      bonus ≥ target. Each miss raises the target; out of throws → it flees.
## present(idx, spirit, spooked); emits done("caught" | "fled" | "left").
## `spooked` skips the duel (an event spirit you already beat in battle).
## CPU hunts play themselves in the same window. Keys: 1–4 jars, Space acts.

signal done(outcome: String)

var _idx := -1
var _spirit: Dictionary
var _cpu := false
var _phase := ""          # intro / duel / throw / over
var _busy := false
var _jar := &"ghost_jar"
var _title: Label
var _sprite: TextureRect
var _info: Label
var _duel_row: HBoxContainer
var _lead_die: DiceView
var _ghost_die: DiceView
var _jar_row: HBoxContainer
var _odds: Label
var _die: DiceView
var _sum: Label
var _result: Label
var _main_btn: Button
var _leave_btn: Button

func _ready() -> void:
	var col := _init_window(560, 0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	_title = _title_label("", 24)
	col.add_child(_title)
	_sprite = UIKit.sprite(null, Vector2(120, 120))
	_sprite.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(_sprite)
	_info = UIKit.wrap_label("", 15, 520)
	col.add_child(_info)
	_duel_row = UIKit.hbox(12)
	_duel_row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(_duel_row)
	_lead_die = DiceView.new(52, 6, Color("cfe8ff"))
	_ghost_die = DiceView.new(52, 6, Color("ffd0d0"))
	_duel_row.add_child(_lead_die)
	_duel_row.add_child(UIKit.label("vs", 18))
	_duel_row.add_child(_ghost_die)
	_jar_row = UIKit.hbox(8)
	_jar_row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(_jar_row)
	_odds = UIKit.wrap_label("", 15, 520)
	_odds.add_theme_color_override("font_color", UIKit.GOLD)
	col.add_child(_odds)
	var roll_row := UIKit.hbox(14)
	roll_row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(roll_row)
	_die = DiceView.new(64, 100, Color("cfe8ff"))
	roll_row.add_child(_die)
	_sum = UIKit.label("", 22)
	_sum.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	roll_row.add_child(_sum)
	_result = UIKit.wrap_label("", 17, 520)
	col.add_child(_result)
	var actions := UIKit.hbox(10)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(actions)
	_main_btn = _button("", _on_main, 44)
	_main_btn.custom_minimum_size.x = 200
	actions.add_child(_main_btn)
	_leave_btn = _button("Leave", func(): _finish("left"), 44)
	actions.add_child(_leave_btn)
	EventBus.catch_succeeded.connect(_on_succeeded)
	EventBus.catch_failed.connect(_on_failed)
	hide()

func _player() -> PlayerData:
	return GameState.players[_idx]

func _inv() -> PlayerData.Inventory:
	return _player().inventory

func present(idx: int, spirit: Dictionary, spooked: bool = false) -> void:
	_idx = idx
	_spirit = spirit
	_cpu = _player().is_cpu
	_busy = false
	_result.text = ""
	_sum.text = ""
	_die.show_face(100)
	_sprite.texture = SpiritsData.sprite_tex(spirit.get("name", ""), "front")
	_sprite.modulate = Color.WHITE
	_sprite.scale = Vector2.ONE
	_sprite.rotation = 0.0
	_title.text = "A wild %s appeared!" % spirit.get("name", "?")
	_info.text = "%s  ·  Stage %d  ·  %s%s" % [SpiritsData.type_text(spirit), spirit.get("stage", 1),
		SpiritsData.star_text(spirit.get("stars", 0)), "  ·  🍬 lured" if spirit.get("_lured", false) else ""]
	_jar = _best_jar()
	if spooked:
		spirit["_spooked"] = true
		_enter_throw_phase()
	else:
		_enter_intro()
	if _cpu:
		_cpu_run()

# ── phases ────────────────────────────────────────────────────────────────────

func _enter_intro() -> void:
	_phase = "intro"
	_duel_row.modulate.a = 0.35
	_jar_row.hide()
	_die.hide()
	var lead := _player().lead()
	var edge := CatchSystem.type_edge(lead, _spirit)
	_odds.text = "👻 Spook Duel: %s (power %d%s) vs %s (power %d)  →  %d%% to spook it" % [
		lead.get("name", "?"), CatchSystem.duel_power(lead), (" %+d type" % edge) if edge != 0 else "",
		_spirit.get("name", "?"), CatchSystem.duel_power(_spirit), int(round(CatchSystem.duel_chance(lead, _spirit) * 100))]
	_odds.text += "\nLose and it runs away. Win and you get %d throws (+%d each)." % [Balance.CATCH_THROWS, Balance.DUEL_BONUS]
	_main_btn.text = "1 · 👻 Spook Duel  [Space]"
	_main_btn.disabled = _cpu
	_leave_btn.text = "2 · Leave"
	_leave_btn.disabled = _cpu
	if _inv().total_jars() <= 0:
		_main_btn.disabled = true
		_result.text = "No jars left — you can't catch it!"

func _enter_throw_phase() -> void:
	_phase = "throw"
	_duel_row.modulate.a = 0.35
	_jar_row.show()
	_die.show()
	_main_btn.text = "🫙 Throw!  [Space]"
	_leave_btn.text = "Leave"
	_refresh_throw()

func _refresh_throw() -> void:
	UIKit.clear(_jar_row)
	var n := 0
	for jar in CatchSystem.JAR_ORDER:
		var count: int = _inv().jar_count(jar)
		if count <= 0:
			continue
		n += 1
		var b := UIKit.small_button("%d · %s ×%d" % [n, CatchSystem.jar_name(jar), count], _pick_jar.bind(jar), 13)
		b.disabled = _cpu or _busy
		if jar == _jar:
			b.modulate = Color(1.3, 1.2, 0.6)
		_jar_row.add_child(b)
	var has_jar := _inv().jar_count(_jar) > 0
	_main_btn.disabled = not has_jar or _cpu or _busy
	_leave_btn.disabled = _cpu or _busy
	var left := Balance.CATCH_THROWS - int(_spirit.get("catch_fails", 0))
	if not has_jar:
		_odds.text = "No jars left!"
		return
	var parts: Array = CatchSystem.bonus_parts(_idx, _spirit, _jar).filter(func(pt): return int(pt[1]) != 0)
	_odds.text = "Throws left: %d   ·   d100%s ≥ %d   →  %d%%" % [left,
		("  + " + " + ".join(parts.map(func(pt): return "%s %d" % pt))) if not parts.is_empty() else "",
		CatchSystem.target_for(_spirit), CatchSystem.chance(_idx, _spirit, _jar)]

# Humans start on the plainest jar; CPUs take the cheapest one with decent odds
# and save the Soul Lantern for legendaries.
func _best_jar() -> StringName:
	var owned: Array = CatchSystem.JAR_ORDER.filter(func(j): return _inv().jar_count(j) > 0)
	if owned.is_empty():
		return &"ghost_jar"
	if not _cpu:
		return owned[0]
	if SpiritsData.is_legendary(String(_spirit.get("name", ""))) and owned.has(&"soul_lantern"):
		return &"soul_lantern"
	var normal: Array = owned.filter(func(j): return j != &"soul_lantern")
	for jar in normal:
		if CatchSystem.chance(_idx, _spirit, jar) >= 60:
			return jar
	return normal.back() if not normal.is_empty() else owned[0]

func _pick_jar(jar: StringName) -> void:
	_jar = jar
	Sfx.play("click")
	_refresh_throw()

func _on_main() -> void:
	match _phase:
		"intro": await _duel()
		"throw": await _throw()

# ── the duel ──────────────────────────────────────────────────────────────────

func _duel() -> void:
	if _busy:
		return
	_busy = true
	_main_btn.disabled = true
	_leave_btn.disabled = true
	_phase = "duel"
	var lead := _player().lead()
	var mine := CatchSystem.duel_power(lead) + CatchSystem.type_edge(lead, _spirit)
	var theirs := CatchSystem.duel_power(_spirit)
	var a := randi_range(1, 6)
	var b := randi_range(1, 6)
	_duel_row.modulate.a = 1.0
	Sfx.play("boo", 1.2)
	_ghost_die.roll(b, 0.8)
	await _lead_die.roll(a, 0.8)
	var won := mine + a >= theirs + b
	_sum.text = "%d + 🎲%d = %d   vs   %d + 🎲%d = %d" % [mine, a, mine + a, theirs, b, theirs + b]
	Juice.pop(_sum, 1.25)
	await get_tree().create_timer(0.4).timeout
	_busy = false
	if not won:
		_result.text = "%s isn't scared at all… it vanishes into the mist!" % _spirit.get("name", "?")
		_result.add_theme_color_override("font_color", UIKit.BAD)
		Sfx.play("escape")
		var tw := _sprite.create_tween().set_parallel(true)
		tw.tween_property(_sprite, "modulate:a", 0.0, 0.6)
		tw.tween_property(_sprite, "position:y", _sprite.position.y - 40.0, 0.6)
		await get_tree().create_timer(1.3).timeout
		_finish("fled")
		return
	_spirit["_spooked"] = true
	_result.text = "%s is spooked! Quick — throw a jar!" % _spirit.get("name", "?")
	_result.add_theme_color_override("font_color", UIKit.GOOD)
	Sfx.play("caught", 1.3)
	Juice.shake(_sprite, 10.0)
	_sum.text = ""
	_enter_throw_phase()

# ── throwing ──────────────────────────────────────────────────────────────────

func _throw() -> void:
	if _busy or _inv().jar_count(_jar) <= 0:
		return
	_busy = true
	_inv().add_jars(_jar, -1)
	_refresh_throw()
	var roll := randi_range(1, 100)
	var bonus := CatchSystem.total_bonus(_idx, _spirit, _jar)
	var target := CatchSystem.target_for(_spirit)
	Sfx.play("whoosh")
	await _die.roll(roll, 0.9)
	_sum.text = "%d + %d = %d  vs %d" % [roll, bonus, roll + bonus, target]
	Juice.pop(_sum)
	for k in 3:   # the jar wobbles…
		Sfx.play("wobble", 1.0 + k * 0.08)
		_sprite.pivot_offset = _sprite.size * 0.5
		var tw := _sprite.create_tween()
		tw.tween_property(_sprite, "rotation", 0.25, 0.08)
		tw.tween_property(_sprite, "rotation", -0.25, 0.12)
		tw.tween_property(_sprite, "rotation", 0.0, 0.08)
		await tw.finished
		await get_tree().create_timer(0.12).timeout
	_spirit["_roll"] = roll
	EventBus.catch_attempted.emit(_idx, _spirit, _jar)

func _on_succeeded(idx: int, spirit: Dictionary) -> void:
	if not visible or idx != _idx or spirit != _spirit:
		return
	_phase = "over"
	Sfx.play("caught")
	var tw := _sprite.create_tween().set_parallel(true)
	tw.tween_property(_sprite, "scale", Vector2(0.2, 0.2), 0.25)
	tw.tween_property(_sprite, "modulate", Color(1.5, 1.5, 2.0, 0.0), 0.25)
	var where := "sent to the Spirit Box (team full)" if _player().pc.has(spirit) else "caught"
	_result.text = "Gotcha! %s was %s!" % [spirit.get("name", "?"), where]
	_result.add_theme_color_override("font_color", UIKit.GOOD)
	await get_tree().create_timer(1.3).timeout
	_finish("caught")

func _on_failed(idx: int, s: Dictionary) -> void:
	if not visible or idx != _idx or s != _spirit:
		return
	Sfx.play("escape")
	Juice.shake(_sprite, 10.0)
	_busy = false
	_result.add_theme_color_override("font_color", UIKit.BAD)
	if int(s.get("catch_fails", 0)) >= Balance.CATCH_THROWS or _inv().total_jars() == 0:
		_phase = "over"
		_result.text = "Oh no! %s broke free and fled!" % _spirit.get("name", "?")
		_refresh_throw()
		_main_btn.disabled = true
		await get_tree().create_timer(1.3).timeout
		_finish("fled")
		return
	_result.text = "It broke free! It's warier now (target +%d)." % Balance.CATCH_FAIL_PENALTY
	_refresh_throw()

func _finish(outcome: String) -> void:
	if outcome != "caught":
		EventBus.log_entry.emit(_idx, "The wild %s got away." % _spirit.get("name", "?") if outcome == "fled"
			else "%s leaves the wild %s alone." % [_player().player_name, _spirit.get("name", "?")], "#aaaaaa")
	_phase = "over"
	done.emit(outcome)

# ── CPU ───────────────────────────────────────────────────────────────────────

# A CPU hunts if it has jars (a full team still hunts — catches level its lead).
func _cpu_run() -> void:
	await get_tree().create_timer(1.1).timeout
	if _phase == "intro":
		if _inv().total_jars() <= 0:
			_finish("left")
			return
		await _duel()
	while visible and _phase == "throw":
		await get_tree().create_timer(0.6).timeout
		_jar = _best_jar()
		if _inv().jar_count(_jar) <= 0:
			_finish("left")
			return
		await _throw()
		while _busy and visible:
			await get_tree().process_frame
		await get_tree().process_frame

func _unhandled_key_input(ev: InputEvent) -> void:
	if not visible or _cpu or _busy:
		return
	if Controls.confirm_pressed(ev) and not _main_btn.disabled:
		get_viewport().set_input_as_handled()
		_on_main()
		return
	var n := Controls.number_pressed(ev)
	if _phase == "intro":
		if n == 0 and not _main_btn.disabled:
			get_viewport().set_input_as_handled()
			_on_main()
		elif n == 1:
			get_viewport().set_input_as_handled()
			_finish("left")
	elif _phase == "throw" and n >= 0 and n < _jar_row.get_child_count():
		get_viewport().set_input_as_handled()
		(_jar_row.get_child(n) as Button).pressed.emit()
