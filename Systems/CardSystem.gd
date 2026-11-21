extends Node
## Autoloaded. Owns players' hands: drawing (with the hand limit), playing
## FIELD cards on the board, stealing, and the CPU's card sense.
## Tactic cards are played inside BattleScreen; this only decides which one a
## CPU or NPC would pick.

var _discard_win: Control

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # cards arrive mid-event (paused)
	var layer := CanvasLayer.new()
	layer.layer = 22
	add_child(layer)
	_discard_win = preload("res://Scenes/UI/DiscardWindow.gd").new()
	layer.add_child(_discard_win)

# ── drawing ───────────────────────────────────────────────────────────────────

# Add a card to a hand. A full hand forces a discard first: humans choose
# (the new card is one of the options), CPUs drop their least useful card.
func give(idx: int, key: String) -> void:
	var p: PlayerData = GameState.players[idx]
	Sfx.play("draw")
	if not p.inventory.hand_full():
		p.inventory.hand.append(key)
	else:
		var options: Array = p.inventory.hand.duplicate()
		options.append(key)
		var drop: String
		if p.is_cpu:
			drop = _least_valuable(options)
		else:
			_discard_win.present(p, options)
			drop = await _discard_win.chose
		options.erase(drop)
		p.inventory.hand = options
		if drop != key:
			EventBus.log_entry.emit(idx, "%s discards %s." % [p.player_name, CardsData.card_name(drop)], "#a9b0c4")
	EventBus.log_entry.emit(idx, "%s draws %s." % [p.player_name, CardsData.card_name(key)], "#7fe0d0")
	EventBus.hand_changed.emit(idx)

func give_random(idx: int, kind: String = "") -> String:
	var key: String = CardsData.random_card(kind)
	await give(idx, key)
	return key

func remove(idx: int, key: String) -> bool:
	var hand: Array = GameState.players[idx].inventory.hand
	var i := hand.find(key)
	if i == -1:
		return false
	hand.remove_at(i)
	EventBus.hand_changed.emit(idx)
	return true

func _least_valuable(keys: Array) -> String:
	var worst: String = keys[0]
	for k in keys:
		if CardsData.value_of(k) < CardsData.value_of(worst):
			worst = k
	return worst

# ── field cards ───────────────────────────────────────────────────────────────

# Can `key` be played right now on this target? (UI greys out the rest.)
func can_target(key: String, target) -> bool:
	match String(CardsData.card(key).get("target", "")):
		"spirit":
			if not (target is Dictionary):
				return false
			if key == "star_candy":
				return true
			return int(target.get("current_hp", 0)) > 0 and int(target["current_hp"]) < int(target.get("hp", 1))
		"fainted":
			return target is Dictionary and int(target.get("current_hp", 0)) <= 0
		"player":
			return target is int and not GameState.players[target].inventory.hand.is_empty()
		"city":
			return target is String
	return true

# Play a field card. Returns the log/flash message.
func play_field(idx: int, key: String, target = null) -> String:
	var p: PlayerData = GameState.players[idx]
	if not remove(idx, key):
		return ""
	var msg := ""
	match key:
		"glow_tonic", "mega_tonic":
			var amount := 50 if key == "glow_tonic" else 100
			target["current_hp"] = mini(int(target["hp"]), int(target["current_hp"]) + amount)
			msg = "%s heals %d HP!" % [target["name"], amount]
			Sfx.play("heal")
		"wake_bell":
			target["current_hp"] = int(target["hp"]) / 2
			msg = "%s wakes up!" % target["name"]
			Sfx.play("heal")
		"group_hug":
			for m in p.living_team():
				m["current_hp"] = mini(int(m["hp"]), int(m["current_hp"]) + 40)
			msg = "Group hug! The team heals 40 HP."
			Sfx.play("heal")
		"loaded_die":
			p.roll_bonus += 2
			msg = "Next roll +2!"
		"twin_dice":
			p.extra_die = true
			msg = "An extra die this turn!"
		"spooky_lure":
			p.lure = true
			msg = "A sweet smell drifts out… something big is coming."
		"salt_circle":
			p.salt = true
			msg = "A salt circle keeps the next ghost or event away."
		"star_candy":
			msg = "%s gobbles the Star Candy!" % target["name"]
			await SpiritsProgressionSystem.award_star(idx, target)
		"warp_door":
			msg = "%s steps through the Warp Door!" % p.player_name
			EventBus.warp_requested.emit(idx, String(target))
		"sticky_fingers":
			var stolen := await steal(target, idx)
			msg = "Stole %s from %s!" % [CardsData.card_name(stolen), GameState.players[target].player_name] \
				if stolen != "" else "Nothing to steal…"
		"lucky_coin":
			p.inventory.gold += 25
			msg = "+25 gold!"
			Sfx.play("coin")
		"weather_charm":
			var kind := await _pick_weather(idx)
			GameState.set_weather(kind)
			var w: Dictionary = preload("res://Data/WeatherData.gd").info(kind)
			msg = "%s %s for 2 rounds!" % [w["icon"], w["name"]]
			Sfx.play("whoosh")
		"hex":
			msg = hex_leader(idx)
	Sfx.play("card")
	EventBus.card_played.emit(idx, key)
	EventBus.log_entry.emit(idx, "%s plays %s — %s" % [p.player_name, CardsData.card_name(key), msg], "#7fe0d0")
	return msg

# Weather Charm: a human picks (board choice), a CPU picks its lead's weather.
func _pick_weather(idx: int) -> String:
	var WD = preload("res://Data/WeatherData.gd")
	var kinds: Array = WD.KINDS.keys()
	var p: PlayerData = GameState.players[idx]
	var board := get_tree().current_scene
	if p.is_cpu or board == null or not board.has_method("_show_choice"):
		return WD.for_type(String(p.lead().get("type", ""))) if not p.team.is_empty() else kinds.pick_random()
	var labels: Array = kinds.map(func(k): return "%s %s" % [WD.KINDS[k]["icon"], WD.KINDS[k]["name"]])
	var pick: int = await board._show_choice("🌦 Weather Charm — pick the weather", labels)
	return kinds[pick]

# Grim Hex: the points leader (or the next best, if that's you) gets cursed.
func hex_leader(idx: int) -> String:
	var j := -1
	for k in GameState.players.size():
		if k != idx and (j < 0 or GameState.players[k].progress.points > GameState.players[j].progress.points):
			j = k
	if j < 0:
		return "Nobody to curse…"
	var q: PlayerData = GameState.players[j]
	var board := get_tree().current_scene
	match randi() % 3:
		0:
			var g := mini(15, q.inventory.gold)
			q.inventory.gold -= g
			GameState.players[idx].inventory.gold += g
			return "☠ %s loses %d gold to %s!" % [q.player_name, g, GameState.players[idx].player_name]
		1:
			if board and board.has_method("shift_player"):
				board.shift_player(j, -3)
			return "☠ %s is pushed back 3 spaces!" % q.player_name
		_:
			q.skip_turns += 1
			return "☠ %s will skip their next turn!" % q.player_name

# Move a random card from one hand to another. Returns the key ("" if none).
func steal(from_idx: int, to_idx: int) -> String:
	var hand: Array = GameState.players[from_idx].inventory.hand
	if hand.is_empty():
		return ""
	var key: String = hand[randi() % hand.size()]
	remove(from_idx, key)
	await give(to_idx, key)
	return key

# ── CPU ───────────────────────────────────────────────────────────────────────

# Start of a CPU turn: play whatever field cards make sense right now. Returns
# a town to warp to ("" = roll normally). `wanted_city` is the board's pick of
# a useful town (unbeaten gym / trail prep), or "".
func cpu_field_turn(idx: int, wanted_city: String) -> String:
	var p: PlayerData = GameState.players[idx]
	for key in p.inventory.hand.duplicate():
		var target = _cpu_target(p, idx, key, wanted_city)
		if target == null:
			continue
		if key == "warp_door":
			await play_field(idx, key, target)
			return String(target)
		await play_field(idx, key, target)
	return ""

# What a CPU would play `key` on right now, or null to hold the card.
func _cpu_target(p: PlayerData, idx: int, key: String, wanted_city: String):
	match key:
		"glow_tonic", "mega_tonic":
			for m in p.living_team():
				if float(m["current_hp"]) / float(m["hp"]) < 0.5:
					return m
		"wake_bell":
			for m in p.team:
				if int(m["current_hp"]) <= 0:
					return m
		"group_hug":
			var hurt := 0
			for m in p.living_team():
				if float(m["current_hp"]) / float(m["hp"]) < 0.7:
					hurt += 1
			if hurt >= 2:
				return true
		"star_candy":
			return p.lead() if not p.team.is_empty() else null
		"lucky_coin":
			return true if p.inventory.gold < 30 else null
		"spooky_lure":
			return true if p.team.size() < Balance.TEAM_MAX and not p.inventory.lanterns().is_empty() and not p.lure else null
		"salt_circle":
			return true if p.team.size() >= Balance.TEAM_MAX and not p.salt else null
		"loaded_die", "twin_dice":
			return true if randf() < 0.4 else null
		"warp_door":
			return wanted_city if wanted_city != "" else null
		"weather_charm":   # when the sky is clear, call up its lead's weather
			return true if GameState.weather == "" and randf() < 0.5 else null
		"hex":
			return true if randf() < 0.5 else null
		"sticky_fingers":
			for j in GameState.players.size():
				if j != idx and not GameState.players[j].inventory.hand.is_empty():
					return j
	return null

# Pick a tactic card for this round, or "" to save it. `me`/`foe` are the
# active fighters; `incoming` is roughly what the foe's next hit will deal;
# `stakes` (0..1) is how much the battle matters (wild = low, Champion = 1).
func pick_tactic(hand: Array, me: Dictionary, foe: Dictionary, incoming: int, outgoing: int, stakes: float) -> String:
	var tactics: Array = hand.filter(func(k): return CardsData.kind_of(k) == "tactic")
	if tactics.is_empty():
		return ""
	var hp := int(me.get("current_hp", 0))
	var lethal := incoming >= hp
	var can_ko := outgoing >= int(foe.get("current_hp", 1))
	var prefs: Array = []
	var charmed := me.has("charm")   # one charm per spirit at a time
	if lethal:
		prefs = ["hold_on", "spirit_shield", "boo", "ecto_patch", "switcheroo", "mirror_veil"]
		if not charmed:
			prefs += ["lucky_scarf", "phoenix_feather"]
	elif float(hp) / float(maxi(1, int(me.get("hp", 1)))) < 0.4:
		prefs = ["ecto_patch", "soul_siphon", "spirit_shield", "switcheroo"]
		if not charmed:
			prefs.append("moon_berry")
	elif me.has("_status"):
		prefs = ["purify"]
	elif not can_ko and outgoing * 2 >= int(foe.get("current_hp", 1)):
		prefs = ["fury", "battle_cry"]
	elif randf() < 0.3:
		prefs = ["rally", "haste", "soul_siphon", "battle_cry"]
	elif not charmed and float(hp) / float(maxi(1, int(me.get("hp", 1)))) > 0.6:
		# a healthy lead is worth charming for the long haul
		prefs = ["power_band", "ghost_cloak", "war_drum", "brave_ribbon", "guard_pin", "echo_bell", "spiky_helm", "last_trophy"]
	# Low-stakes fights only spend cards when it really counts.
	if stakes < 0.5 and not lethal and randf() > stakes:
		return ""
	for want in prefs:
		if tactics.has(want):
			return want
	return ""

# Rough trade value of what a player offers (cards + spirits), for CPU deals.
func offer_value(offer: Dictionary) -> int:
	match String(offer.get("kind", "")):
		"card":
			return CardsData.value_of(String(offer.get("key", "")))
		"sp":
			var s: Dictionary = offer.get("spirit", {})
			return int(s.get("stage", 1)) * 3 + int(float(s.get("stars", 0)) * 2)
	return 0
