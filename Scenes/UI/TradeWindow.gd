extends MenuWindow
## ⚔ PvP trade (two humans, same screen): each side offers ONE thing — a
## spirit or an item — then "Trade!" swaps them. present(a, b); emits closed().

signal closed()

var _a: int = -1
var _b: int = -1
var _pick_a: Dictionary = {}   # {"kind": "sp"|"item", "i": index}
var _pick_b: Dictionary = {}
var _title: Label
var _cols: HBoxContainer
var _trade_btn: Button

func _ready() -> void:
	var col := _init_window(780, 0)
	_title = _title_label("🔁 Trade", 26)
	col.add_child(_title)
	_cols = HBoxContainer.new()
	_cols.add_theme_constant_override("separation", 24)
	col.add_child(_cols)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)
	_trade_btn = _button("🔁 Trade!", _do_trade, 40)
	_trade_btn.custom_minimum_size = Vector2(160, 40)
	row.add_child(_trade_btn)
	var cancel := _button("Cancel", func(): closed.emit(), 40)
	cancel.custom_minimum_size = Vector2(120, 40)
	row.add_child(cancel)
	hide()

func present(a: int, b: int) -> void:
	_a = a
	_b = b
	_pick_a = {}
	_pick_b = {}
	_title.text = "🔁 %s  ⇄  %s" % [
		GameState.players[a].player_name, GameState.players[b].player_name]
	_rebuild()

func _rebuild() -> void:
	for c in _cols.get_children():
		c.queue_free()
	_cols.add_child(_side_column(_a, _pick_a, true))
	_cols.add_child(_side_column(_b, _pick_b, false))
	_trade_btn.disabled = _pick_a.is_empty() or _pick_b.is_empty()

# One player's offer list: their spirits (can't offer the last one) and items.
func _side_column(idx: int, pick: Dictionary, is_a: bool) -> Control:
	var p: PlayerData = GameState.players[idx]
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nm := Label.new()
	nm.text = "%s offers:" % p.player_name
	nm.add_theme_color_override("font_color", p.color)
	nm.add_theme_font_size_override("font_size", 20)
	box.add_child(nm)
	for i in p.team.size():
		var s: Dictionary = p.team[i]
		var label := "%s %s" % [s.get("name", "?"), SpiritsData.star_text(s.get("stars", 0))]
		var btn := _offer_btn(label, pick, {"kind": "sp", "i": i}, is_a)
		if p.team.size() <= 1:
			btn.disabled = true
			btn.text += "  (last spirit)"
		box.add_child(btn)
	for i in p.inventory.items.size():
		var e: Dictionary = p.inventory.items[i]
		box.add_child(_offer_btn("%s ×%d" % [e.get("name", "Item"), int(e.get("count", 1))],
			pick, {"kind": "item", "i": i}, is_a))
	if p.team.size() <= 1 and p.inventory.items.is_empty():
		var none := Label.new()
		none.text = "nothing to trade"
		box.add_child(none)
	return box

func _offer_btn(text: String, pick: Dictionary, what: Dictionary, is_a: bool) -> Button:
	var selected: bool = pick.get("kind", "") == what["kind"] and pick.get("i", -1) == what["i"]
	var b := _button(("✔ " if selected else "") + text, func():
		if is_a:
			_pick_a = what
		else:
			_pick_b = what
		_rebuild(), 34)
	b.add_theme_font_size_override("font_size", 14)
	if selected:
		b.modulate = Color(1.2, 1.1, 0.6)
	return b

func _do_trade() -> void:
	if _pick_a.is_empty() or _pick_b.is_empty():
		return
	# grab both offers FIRST, then hand them across
	var give_a = _take(_a, _pick_a)
	var give_b = _take(_b, _pick_b)
	_give(_b, _pick_a["kind"], give_a)
	_give(_a, _pick_b["kind"], give_b)
	EventBus.log_entry.emit(_a, "%s and %s traded!" % [
		GameState.players[_a].player_name, GameState.players[_b].player_name], "#7fe0d0")
	closed.emit()

func _take(idx: int, pick: Dictionary):
	var p: PlayerData = GameState.players[idx]
	if pick["kind"] == "sp":
		var s: Dictionary = p.team[pick["i"]]
		p.team.remove_at(pick["i"])
		return s
	var e: Dictionary = p.inventory.items[pick["i"]]
	var loot := {"name": e.get("name", "Item"), "kind": e.get("kind", ""), "amount": e.get("amount", 0)}
	p.inventory.consume_item(e)
	return loot

func _give(idx: int, kind: String, thing) -> void:
	var p: PlayerData = GameState.players[idx]
	if kind == "sp":
		if p.team.size() < 6:
			p.team.append(thing)
		else:
			p.pc.append(thing)   # team full → the PC keeps it safe
	else:
		p.inventory.add_item(thing)
