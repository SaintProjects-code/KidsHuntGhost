extends MenuWindow
## Spend gold on cards — Lanterns (catching cards) on the top shelf, a rotating
## rack of special cards (rerolled each visit) below — or pay to scrub a trait
## off a spirit. Everything for sale is shown as a card with its price.
## present(player_index); emits closed(). cpu_shop(idx) is the CPU's list.

signal closed()

const TRAIT_REMOVAL_COST := 10

var _gold_lbl: Label
var _lanterns: HBoxContainer
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
	col.add_child(_heading("🏮 Lanterns"))
	_lanterns = UIKit.hbox(10)
	_lanterns.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(_lanterns)
	col.add_child(_heading("✨ Today's cards"))
	_rack = UIKit.hbox(8)
	_rack.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(_rack)
	_list = UIKit.vbox(6)
	col.add_child(_list)
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
	UIKit.clear(_lanterns)
	for key in ["spirit_lantern", "grand_lantern"]:
		_lanterns.add_child(_for_sale(key, "own %d" % inv.hand.count(key), false))
	UIKit.clear(_list)
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
		_rack.add_child(_for_sale(key, "", true))
	if _offers.is_empty():
		_rack.add_child(UIKit.label("— sold out —", 13))

# A card on the shelf: the card, its price and a note. `once` = one per visit.
func _for_sale(key: String, note: String, once: bool) -> Control:
	var cost := int(CardsData.card(key)["cost"])
	var col := UIKit.vbox(2)
	var cv := CardView.new(key, Vector2(96, 128))
	cv.disabled = _inv().gold < cost
	cv.set_meta("price", cost)   # 📱 the phone shows "— 10g" on the card
	cv.set_meta("off_reason", "Not enough gold")
	cv.pressed.connect(_buy_card.bind(key, once))
	col.add_child(cv)
	var price := UIKit.label("%dg%s" % [cost, ("  · " + note) if note != "" else ""], 14, UIKit.GOLD)
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(price)
	return col

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
	var buy := UIKit.small_button("Remove", cb)
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

func _buy_card(key: String, once := true) -> void:
	if _pay(int(CardsData.card(key)["cost"])):
		if once:
			_offers.erase(key)   # one of each special per visit; Lanterns restock
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

# CPU shopping list: keep 4 Lanterns (stage-3 ghosts need 3+), then buy one
# useful card if it can afford it.
func cpu_shop(idx: int) -> void:
	var inv: PlayerData.Inventory = GameState.players[idx].inventory
	var bought: Array = []
	while inv.lanterns().size() < 4 and inv.gold >= 10 and not inv.hand_full():
		inv.gold -= 10
		inv.hand.append("spirit_lantern")
		bought.append("Spirit Lantern")
	if inv.gold >= 60 and not inv.hand.has("grand_lantern") and not inv.hand_full():
		inv.gold -= 25
		inv.hand.append("grand_lantern")
		bought.append("Grand Lantern")
	if not inv.hand_full() and inv.gold >= 40:
		var key: String = ["ecto_patch", "spirit_shield", "glow_tonic", "battle_cry", "wake_bell"].pick_random()
		inv.gold -= int(CardsData.card(key)["cost"])
		inv.hand.append(key)
		bought.append(CardsData.card(key)["name"])
		EventBus.hand_changed.emit(idx)
	if not bought.is_empty():
		EventBus.log_entry.emit(idx, "%s shops: %s" % [GameState.players[idx].player_name, ", ".join(bought)], "#f0c36a")
