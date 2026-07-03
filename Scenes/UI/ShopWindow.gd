extends MenuWindow
## Spend gold on balls, healing items, and a rotating rack of held battle
## items (3 random offers per visit). present(player_index); emits closed().

signal closed()

const STOCK := [
	{"name": "Spirit Ball", "kind": "ball",   "amount": 1,  "cost": 10},
	{"name": "Potion",      "kind": "potion", "amount": 40, "cost": 15},
	{"name": "Super Potion","kind": "potion", "amount": 80, "cost": 30},
	{"name": "Revive",      "kind": "revive",               "cost": 35},
]
const HELD_OFFERS := 3

var _title: Label
var _gold_lbl: Label
var _list: VBoxContainer
var _player_index: int = -1
var _held_offer: Array = []   # held-item keys on the rack, rerolled per visit

func _ready() -> void:
	var col := _init_window(460, 0)
	_title = _title_label("🛒 Shop", 26)
	col.add_child(_title)
	_gold_lbl = Label.new()
	_gold_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_gold_lbl)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_list)
	col.add_child(_button("Done", func(): closed.emit()))
	hide()

func present(player_index: int) -> void:
	_player_index = player_index
	# reroll the battle-item rack each visit
	var keys: Array = GameData.HELD_ITEMS.keys()
	keys.shuffle()
	_held_offer = keys.slice(0, HELD_OFFERS)
	_refresh()

func _refresh() -> void:
	var inv = GameState.players[_player_index].inventory
	_gold_lbl.text = "Gold: %d" % inv.gold
	for c in _list.get_children():
		c.queue_free()
	for item in STOCK:
		_list.add_child(_stock_row(item["name"], "", int(item["cost"]), _on_buy.bind(item), inv))
	# held battle items
	var head := Label.new()
	head.text = "— Battle Items (equip from your bag) —"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 14)
	head.modulate = Color(1, 1, 1, 0.7)
	_list.add_child(head)
	for key in _held_offer:
		var d: Dictionary = GameData.HELD_ITEMS[key]
		_list.add_child(_stock_row(d["name"], d["desc"], int(d["cost"]), _on_buy_held.bind(key), inv))

func _stock_row(name: String, desc: String, cost: int, cb: Callable, inv) -> Control:
	var row := HBoxContainer.new()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(col)
	var lbl := Label.new()
	lbl.text = "%s — %dg" % [name, cost]
	lbl.add_theme_font_size_override("font_size", 16)
	col.add_child(lbl)
	if desc != "":
		var sub := Label.new()
		sub.text = desc
		sub.add_theme_font_size_override("font_size", 12)
		sub.modulate = Color(1, 1, 1, 0.65)
		sub.clip_text = true
		col.add_child(sub)
	var buy := _small_btn("Buy", cb)
	buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	buy.disabled = inv.gold < cost
	row.add_child(buy)
	return row

# Compact purple button — the theme's default padding makes 7 rows too tall
# for the screen.
func _small_btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 14)
	for state in [["normal", Color(0.541, 0.435, 0.965)], ["hover", Color(0.651, 0.565, 1.0)], ["pressed", Color(0.435, 0.337, 0.847)], ["disabled", Color(0.396, 0.388, 0.471)]]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = state[1]
		sb.border_width_bottom = 2
		sb.border_color = Color(0.345, 0.247, 0.737)
		sb.corner_radius_top_left = 7
		sb.corner_radius_top_right = 7
		sb.corner_radius_bottom_left = 7
		sb.corner_radius_bottom_right = 7
		sb.content_margin_left = 12.0
		sb.content_margin_right = 12.0
		sb.content_margin_top = 4.0
		sb.content_margin_bottom = 4.0
		b.add_theme_stylebox_override(state[0], sb)
	b.pressed.connect(cb)
	return b

func _on_buy(item: Dictionary) -> void:
	var inv = GameState.players[_player_index].inventory
	if inv.gold < item["cost"]:
		return
	match item["kind"]:
		"ball":
			inv.gold -= item["cost"]
			inv.balls[&"spirit_ball"] = inv.ball_count(&"spirit_ball") + int(item.get("amount", 1))
		"potion", "revive":
			# Only charge if the bag can take it (7 kinds max, stacks of 5).
			if inv.add_item({"name": item["name"], "kind": item["kind"], "amount": item.get("amount", 0)}):
				inv.gold -= item["cost"]
	_refresh()

func _on_buy_held(key: StringName) -> void:
	var inv = GameState.players[_player_index].inventory
	var cost: int = int(GameData.HELD_ITEMS[key]["cost"])
	if inv.gold < cost:
		return
	if inv.add_item(GameData.held_item_entry(key)):
		inv.gold -= cost
	_refresh()
