extends MenuWindow
## ⚔ Trade: each side offers ONE thing — a spirit or a card — then "Trade!"
## swaps them. With two humans both pick on one screen. Against a CPU you pick
## what you give AND what you want; the CPU accepts if the deal is fair to it.
## present(a, b); emits closed().

signal closed()

var _a := -1
var _b := -1
var _pick_a: Dictionary = {}   # {"kind": "sp"|"card", "i": index}
var _pick_b: Dictionary = {}
var _title: Label
var _cols: HBoxContainer
var _note: Label
var _trade_btn: Button

func _ready() -> void:
	var col := _init_window(820, 0)
	_title = _title_label("🔁 Trade", 26)
	col.add_child(_title)
	_cols = UIKit.hbox(24)
	col.add_child(_cols)
	_note = UIKit.wrap_label("", 15, 760)
	col.add_child(_note)
	var row := UIKit.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)
	_trade_btn = _button("🔁 Trade!", _do_trade, 40)
	_trade_btn.custom_minimum_size.x = 160
	row.add_child(_trade_btn)
	var cancel := _button("Cancel", func(): closed.emit(), 40)
	cancel.custom_minimum_size.x = 120
	row.add_child(cancel)
	hide()

func present(a: int, b: int) -> void:
	_a = a
	_b = b
	_pick_a = {}
	_pick_b = {}
	var pb: PlayerData = GameState.players[b]
	_title.text = "🔁 %s  ⇄  %s" % [GameState.players[a].player_name, pb.player_name]
	_note.text = "Pick what you give and what you want — %s says yes if it's a fair deal." % pb.player_name \
		if pb.is_cpu else "Each player picks one thing to offer."
	_note.remove_theme_color_override("font_color")
	_rebuild()

func _rebuild() -> void:
	UIKit.clear(_cols)
	_cols.add_child(_side_column(_a, _pick_a, true))
	_cols.add_child(_side_column(_b, _pick_b, false))
	_trade_btn.disabled = _pick_a.is_empty() or _pick_b.is_empty()

# One player's offer list: spirits (never their last one) and cards.
func _side_column(idx: int, pick: Dictionary, is_a: bool) -> Control:
	var p: PlayerData = GameState.players[idx]
	var box := UIKit.vbox(6)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(UIKit.label("%s %s:" % [p.player_name, "offers" if is_a or not p.is_cpu else "has"], 20, p.color))
	for i in p.team.size():
		var s: Dictionary = p.team[i]
		var btn := _offer_btn("%s %s" % [s["name"], SpiritsData.star_text(s.get("stars", 0))], pick, {"kind": "sp", "i": i}, is_a)
		if p.team.size() <= 1:
			btn.disabled = true
			btn.text += "  (last spirit)"
		box.add_child(btn)
	var cards := UIKit.hbox(4)
	for i in p.inventory.hand.size():
		var key: String = p.inventory.hand[i]
		var cv := CardView.new(key, Vector2(70, 94))
		var what := {"kind": "card", "i": i}
		cv.armed = pick.get("kind", "") == "card" and pick.get("i", -1) == i
		cv.pressed.connect(_select.bind(what, is_a))
		cards.add_child(cv)
	box.add_child(cards)
	return box

func _offer_btn(text: String, pick: Dictionary, what: Dictionary, is_a: bool) -> Button:
	var selected: bool = pick.get("kind", "") == what["kind"] and pick.get("i", -1) == what["i"]
	var b := _button(("✔ " if selected else "") + text, _select.bind(what, is_a), 34)
	b.add_theme_font_size_override("font_size", 14)
	if selected:
		b.modulate = Color(1.2, 1.1, 0.6)
	return b

func _select(what: Dictionary, is_a: bool) -> void:
	if is_a:
		_pick_a = what
	else:
		_pick_b = what
	Sfx.play("click")
	_rebuild()

func _offer(idx: int, pick: Dictionary) -> Dictionary:
	var p: PlayerData = GameState.players[idx]
	if pick["kind"] == "sp":
		return {"kind": "sp", "spirit": p.team[pick["i"]]}
	return {"kind": "card", "key": p.inventory.hand[pick["i"]]}

func _do_trade() -> void:
	if _pick_a.is_empty() or _pick_b.is_empty():
		return
	var give_a := _offer(_a, _pick_a)
	var give_b := _offer(_b, _pick_b)
	if GameState.players[_b].is_cpu and CardSystem.offer_value(give_a) < CardSystem.offer_value(give_b):
		_note.text = "%s shakes its head — offer something better!" % GameState.players[_b].player_name
		_note.add_theme_color_override("font_color", UIKit.BAD)
		Sfx.play("error")
		Juice.shake(_note)
		return
	_take(_a, give_a)
	_take(_b, give_b)
	await _give(_b, give_a)
	await _give(_a, give_b)
	Sfx.play("caught")
	EventBus.log_entry.emit(_a, "%s and %s traded!" % [GameState.players[_a].player_name, GameState.players[_b].player_name], "#7fe0d0")
	closed.emit()

func _take(idx: int, offer: Dictionary) -> void:
	var p: PlayerData = GameState.players[idx]
	if offer["kind"] == "sp":
		p.team.erase(offer["spirit"])
	else:
		CardSystem.remove(idx, offer["key"])

func _give(idx: int, offer: Dictionary) -> void:
	var p: PlayerData = GameState.players[idx]
	if offer["kind"] == "card":
		await CardSystem.give(idx, offer["key"])
	elif p.team.size() < Balance.TEAM_MAX:
		p.team.append(offer["spirit"])
	else:
		p.pc.append(offer["spirit"])   # team full → the Spirit Box keeps it
