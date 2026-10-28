extends MenuWindow
## Spend gold on capture jars and a rotating rack of cards (rerolled each
## visit), or pay to scrub a trait off a spirit. present(player_index);
## emits closed(). cpu_shop(idx) is the CPU's shopping list (no window).

signal closed()

const TRAIT_REMOVAL_COST := 10

var _gold_lbl: Label
var _list: VBoxContainer
var _rack: HBoxContainer
var _player_index := -1
var _offers: Array = []   # card keys on the rack this visit

func _ready() -> void:
	var col := _init_window(560, 0)
	col.add_child(_title_label("🛒 Shop", 26))
	_gold_lbl = UIKit.label("", 18, UIKit.GOLD)
	_gold_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_gold_lbl)
	_list = UIKit.vbox(6)
	col.add_child(_list)
	col.add_child(_heading("— Cards (they go to your hand) —"))
	_rack = UIKit.hbox(8)
	_rack.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(_rack)
	col.add_child(_button("Done", func(): closed.emit()))
	hide()

func present(player_index: int) -> void:
	_player_index = player_index
	_offers = CardsData.shop_pool()
	_offers.shuffle()
	_offers = _offers.slice(0, Balance.SHOP_CARD_OFFERS)
	_refresh()

func _inv() -> PlayerData.Inventory:
	return GameState.players[_player_index].inventory

func _refresh() -> void:
	var inv := _inv()
	_gold_lbl.text = "🪙 %d gold   ·   🃏 %d/%d cards" % [inv.gold, inv.hand.size(), Balance.HAND_SIZE]
	UIKit.clear(_list)
	for jar in [&"ghost_jar", &"silver_jar", &"golden_jar"]:
		var d: Dictionary = CatchSystem.JARS[jar]
		_list.add_child(_row("%s  (+%d to catch)  — %dg   · own %d" % [d["name"], d["bonus"], d["cost"], inv.jar_count(jar)],
			int(d["cost"]), _buy_jar.bind(jar)))
	var team: Array = GameState.players[_player_index].team
	if team.any(func(m): return not m.get("traits", []).is_empty()):
		_list.add_child(_heading("— Trait Removal —"))
		for m in team:
			for key in m.get("traits", []):
				var info: Dictionary = EventsData.trait_of(String(key))
				_list.add_child(_row("%s: ✦%s (%d turns left) — %dg" % [m["name"], info["name"],
					EventsData.trait_turns_left(m, String(key)), TRAIT_REMOVAL_COST], TRAIT_REMOVAL_COST,
					_remove_trait.bind(m, String(key))))
	UIKit.clear(_rack)
	for key in _offers:
		var col := UIKit.vbox(2)
		var cv := CardView.new(key, Vector2(96, 128))
		cv.disabled = inv.gold < int(CardsData.card(key)["cost"])
		cv.pressed.connect(_buy_card.bind(key))
		col.add_child(cv)
		var price := UIKit.label("%dg" % int(CardsData.card(key)["cost"]), 14, UIKit.GOLD)
		price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(price)
		_rack.add_child(col)

func _heading(text: String) -> Label:
	var head := UIKit.label(text, 14)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.modulate = Color(1, 1, 1, 0.7)
	return head

func _row(text: String, cost: int, cb: Callable) -> Control:
	var row := UIKit.hbox(8)
	var lbl := UIKit.label(text, 15)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	var buy := UIKit.small_button("Buy", cb)
	buy.disabled = _inv().gold < cost
	row.add_child(buy)
	return row

func _pay(cost: int) -> bool:
	if _inv().gold < cost:
		Sfx.play("error")
		return false
	_inv().gold -= cost
	Sfx.play("coin")
	return true

func _buy_jar(jar: StringName) -> void:
	if _pay(int(CatchSystem.JARS[jar]["cost"])):
		_inv().add_jars(jar, 1)
	_refresh()

func _buy_card(key: String) -> void:
	if _pay(int(CardsData.card(key)["cost"])):
		_offers.erase(key)   # one of each per visit
		await CardSystem.give(_player_index, key)
	_refresh()

func _remove_trait(mon: Dictionary, key: String) -> void:
	if not _pay(TRAIT_REMOVAL_COST):
		return
	mon.get("traits", []).erase(key)
	mon.get("trait_turns", {}).erase(key)
	EventBus.log_entry.emit(_player_index, "%s had ✦%s removed at the shop (−%dg)." % [
		mon["name"], EventsData.trait_of(key)["name"], TRAIT_REMOVAL_COST], "#7fe0d0")
	_refresh()

# CPU shopping list: keep 3 jars, then buy one useful card if it can afford it.
func cpu_shop(idx: int) -> void:
	var inv: PlayerData.Inventory = GameState.players[idx].inventory
	var bought: Array = []
	while inv.total_jars() < 3 and inv.gold >= 10:
		inv.gold -= 10
		inv.add_jars(&"ghost_jar", 1)
		bought.append("Ghost Jar")
	if inv.gold >= 60 and inv.jar_count(&"silver_jar") == 0:
		inv.gold -= 25
		inv.add_jars(&"silver_jar", 1)
		bought.append("Silver Jar")
	if not inv.hand_full() and inv.gold >= 40:
		var key: String = ["ecto_patch", "spirit_shield", "glow_tonic", "battle_cry", "wake_bell"].pick_random()
		inv.gold -= int(CardsData.card(key)["cost"])
		inv.hand.append(key)
		bought.append(CardsData.card(key)["name"])
		EventBus.hand_changed.emit(idx)
	if not bought.is_empty():
		EventBus.log_entry.emit(idx, "%s shops: %s" % [GameState.players[idx].player_name, ", ".join(bought)], "#f0c36a")
