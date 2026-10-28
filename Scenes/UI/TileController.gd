extends CanvasLayer
## Runs every non-ghost tile: EVENT, ITEM, COMPETITION, a town (gym / shop /
## Spirit Box / Spectral Trail), WARDEN tiles, plus ⚔ PvP clashes, the dev
## battles and the win screen. Listens for EventBus.tile_action and emits
## tile_resolved when done.

var _event: Control
var _reward: Control
var _comp: Control
var _city: Control
var _shop: Control
var _battle: Control
var _select: Control
var _pc: Control
var _trade: Control
var _win: Control

func _ready() -> void:
	layer = 12
	process_mode = Node.PROCESS_MODE_ALWAYS   # the board pauses meanwhile
	_event = preload("res://Scenes/UI/SpiritEventWindow.gd").new()
	_reward = preload("res://Scenes/UI/RewardWindow.gd").new()
	_comp = preload("res://Scenes/UI/Competition/CompetitionWindow.gd").new()
	_city = preload("res://Scenes/UI/CityWindow.gd").new()
	_shop = preload("res://Scenes/UI/ShopWindow.gd").new()
	_battle = preload("res://Scenes/UI/Battle/BattleScreen.gd").new()
	_select = preload("res://Scenes/UI/BattleTeamSelect.gd").new()
	_pc = preload("res://Scenes/UI/PCWindow.gd").new()
	_trade = preload("res://Scenes/UI/TradeWindow.gd").new()
	for w in [_event, _reward, _comp, _city, _shop, _battle, _select, _pc, _trade]:
		add_child(w)
		w.set_click_through(true)   # the action bar stays pressable
	# the win screen sits on its own top layer so nothing covers the winner
	var win_layer := CanvasLayer.new()
	win_layer.layer = 60
	win_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(win_layer)
	_win = preload("res://Scenes/UI/WinScreen.gd").new()
	_win.process_mode = Node.PROCESS_MODE_ALWAYS
	win_layer.add_child(_win)
	EventBus.tile_action.connect(_on_tile_action)
	EventBus.game_won.connect(_on_game_won)
	EventBus.dev_battle_requested.connect(_on_dev_battle_requested)
	EventBus.pvp_started.connect(_on_pvp_started)

func _on_tile_action(idx: int, kind: StringName) -> void:
	UIManager.hold_pause()
	await get_tree().process_frame   # let the board reach its await first
	match String(kind):
		"EVENT": await _run_event(idx)
		"ITEM": await _run_item(idx)
		"COMPETITION": await _run_competition(idx)
		"WARDEN": await _run_warden_tile(idx)
		var k:
			if GameData.GYMS.has(k):
				await _run_city(idx, k)
	UIManager.close()
	UIManager.release_pause()
	EventBus.tile_resolved.emit()

func _human(idx: int) -> bool:
	return not GameState.players[idx].is_cpu

func _name(idx: int) -> String:
	return GameState.players[idx].player_name

# Let a human pick a battle team (enemy lineup shown alongside); CPUs auto-pick.
func _pick_team(idx: int, vs_text: String, opp_team: Array) -> Array:
	if not _human(idx):
		return BattleSetup.cpu_team(idx, opp_team)
	if GameState.players[idx].team.is_empty():
		return []
	_select.present(GameState.players[idx], vs_text, opp_team)
	UIManager.open(_select)
	return await _select.chosen

# Fight an NPC team end to end. Returns true on a win, null if backed out.
func _npc_battle(idx: int, foe_team: Array, title: String, portrait: Array, kind: String, deck_size: int):
	var team: Array = await _pick_team(idx, "vs %s!" % title, foe_team)
	if team.is_empty():
		return null
	var setup := BattleSetup.vs_npc(idx, team, foe_team, title, portrait, kind, CardsData.npc_deck(deck_size))
	var won := await BattleSetup.run(_battle, setup, idx)
	EventBus.log_entry.emit(idx, "%s %s the battle: %s" % [_name(idx), "won" if won else "lost", title],
		"#9fff9f" if won else "#ff9f9f")
	return won

# ─── EVENT ────────────────────────────────────────────────────────────────────
# ~30% of events (for players with 3+ spirits) are a trainer battle; the rest
# are story events with stat/dice choices (SpiritEventWindow).
func _run_event(idx: int) -> void:
	if GameState.players[idx].team.size() >= 3 and randf() < 0.3:
		await _run_trainer_battle(idx)
		return
	_event.present(idx)
	UIManager.open(_event)
	await _event.closed
	var foe: Dictionary = _event.take_pending_fight()
	if not foe.is_empty():
		UIManager.close()
		EventBus.wild_encounter_started.emit(idx, foe)
		await EventBus.encounter_finished

func _run_trainer_battle(idx: int) -> void:
	var p: PlayerData = GameState.players[idx]
	var t: Dictionary = GameData.TRAINER_BATTLES.pick_random()
	var tier: int = GameData.challenge_tier(p.progress.badge_count())
	var entries: Array = t.get("team", [])
	var size: int = GameData.trainer_team_size(p.pvp_tag, entries.size())
	var foe_team: Array = GameData.build_team(entries.slice(0, size), tier)
	var won = await _npc_battle(idx, foe_team, String(t["name"]), t.get("portrait", ["acetrainer"]), "trainer",
		1 if p.pvp_tag else 0)
	if won == true:
		p.inventory.gold += int(t.get("gold", 15))
		GameState.award_points(idx, int(t.get("pts", 1)))
		EventBus.log_entry.emit(idx, "%s beat %s! +%d pts, +%d gold." % [p.player_name, t["name"],
			int(t.get("pts", 1)), int(t.get("gold", 15))], "#ffd24d")

# ─── ITEM ─────────────────────────────────────────────────────────────────────
func _run_item(idx: int) -> void:
	var p: PlayerData = GameState.players[idx]
	var r: Dictionary = GameData.random_item_reward()
	var cards: Array = []
	var text := ""
	match String(r["kind"]):
		"card":
			for n in int(r["amount"]):
				cards.append(CardsData.random_card())
			text = "You found %s!" % ("a card" if cards.size() == 1 else "%d cards" % cards.size())
		"jars":
			p.inventory.add_jars(&"ghost_jar", int(r["amount"]))
			text = "You found %d Ghost Jars!" % int(r["amount"])
		"gold":
			p.inventory.gold += int(r["amount"])
			text = "You found %d gold!" % int(r["amount"])
			Sfx.play("coin")
	_reward.present("🎁 Item!", text, cards)
	UIManager.open(_reward)
	if _human(idx):
		await _reward.closed
	else:
		await get_tree().create_timer(1.6).timeout
	for key in cards:
		await CardSystem.give(idx, key)

# ─── COMPETITION ──────────────────────────────────────────────────────────────
# EVERYONE competes, whoever landed. With no humans the window drives itself.
func _run_competition(idx: int) -> void:
	_comp.present(idx)
	UIManager.open(_comp)
	if not GameState.players.any(func(p): return not p.is_cpu):
		_comp.run_cpu_auto()
	await _comp.closed

# ─── TOWN ─────────────────────────────────────────────────────────────────────
func _run_city(idx: int, city: String) -> void:
	if not _human(idx):
		_city.present_cpu(idx, city)   # everyone sees the CPU's visit
		UIManager.open(_city)
		await get_tree().create_timer(1.4).timeout
		await _cpu_city(idx, city)
		return
	while GameState.winner_index == -1:
		_city.present(idx, city)
		UIManager.open(_city)
		match await _city.chose:
			"leave":
				return
			"trail":
				EventBus.trail_entered.emit(idx)   # the visit (and move) is over
				return
			"gym":
				await _run_gym(idx, city)
			"shop":
				_shop.present(idx)
				UIManager.open(_shop)
				await _shop.closed
			"pc":
				_pc.present(idx)
				UIManager.open(_pc)
				await _pc.closed

func _run_gym(idx: int, city: String) -> void:
	var p: PlayerData = GameState.players[idx]
	var gym: Dictionary = GameData.gym_for_city(city)
	var tier: int = GameData.challenge_tier(p.progress.badge_count())
	var gym_team: Array = GameData.build_team(gym.get("team", []), tier)
	var won = await _npc_battle(idx, gym_team, String(gym["name"]), GameData.gym_trainer(gym.get("type", "")),
		"gym", tier - 1)
	if won == true:
		p.progress.badges[gym["badge"]] = true
		EventBus.badge_earned.emit(idx, gym["name"])
		GameState.award_points(idx, Balance.PTS_GYM)
		p.inventory.gold += Balance.GOLD_GYM
		Sfx.play("win")
		EventBus.log_entry.emit(idx, "Beat %s! %s, +%d gold." % [gym["name"], GameData.badge_name(gym["badge"]),
			Balance.GOLD_GYM], "#ffd24d")

# CPU town visit: restock, challenge the gym when ready, head for the trail
# once it has the badges and a full team.
func _cpu_city(idx: int, city: String) -> void:
	var p: PlayerData = GameState.players[idx]
	_shop.cpu_shop(idx)
	if not p.progress.badges.get(GameData.gym_for_city(city).get("badge", ""), false) and CpuBrain.ready_for_gym(p):
		await _run_gym(idx, city)
	if GameState.winner_index == -1 and CpuBrain.ready_for_trail(p):
		EventBus.trail_entered.emit(idx)

# ─── WARDEN tiles on the Spectral Trail ───────────────────────────────────────
# One random fight: a Haunted Four warden or Champion Vesper. Teams scale with
# badges beyond the entry requirement (GameData.trail_tier). Two warden wins in a row (or beating the Champion)
# wins the game; one loss sends you back to Cobweb City (the trail's only exit
# besides winning — so every warden tile is a real fight).
func _run_warden_tile(idx: int) -> void:
	var p: PlayerData = GameState.players[idx]
	# no skipping: the trail is a dead end, and losing is the way back down
	var pool: Array = GameData.HAUNTED_FOUR.duplicate()
	pool.append(GameData.CHAMPION)
	var foe: Dictionary = pool.pick_random()
	var champion: bool = foe == GameData.CHAMPION
	var tier: int = GameData.trail_tier(p.progress.badge_count())
	var foe_team: Array = GameData.build_team(foe["team"], tier)
	var won = await _npc_battle(idx, foe_team, String(foe["name"]), foe.get("portrait", []) + ["acetrainer"],
		"champion" if champion else "warden", GameData.CHAMPION_DECK if champion else GameData.WARDEN_DECK)
	if won == null:
		# backing out = retreating down the trail (the streak resets)
		p.progress.elite_wins = 0
		EventBus.log_entry.emit(idx, "%s retreats from %s, back to Cobweb City." % [p.player_name, foe["name"]], "#ff9f9f")
		EventBus.trail_failed.emit(idx)
		return
	if won:
		if champion:
			p.progress.champion_defeated = true
			GameState.award_points(idx, Balance.PTS_CHAMPION)   # also runs the win check
		else:
			p.progress.elite_wins += 1
			EventBus.log_entry.emit(idx, "%s defeated %s! Warden wins: %d/%d" % [p.player_name, foe["name"],
				p.progress.elite_wins, Balance.ELITE_WINS_TO_WIN], "#ffd24d")
			GameState.award_points(idx, Balance.PTS_ELITE_WIN)
	else:
		p.progress.elite_wins = 0   # the streak must be unbroken
		EventBus.log_entry.emit(idx, "%s lost to %s and is sent back to Cobweb City!" % [p.player_name, foe["name"]], "#ff9f9f")
		EventBus.trail_failed.emit(idx)

# ─── ⚔ PvP (walk-past choice or forced landing) ──────────────────────────────

func _on_pvp_started(a: int, b: int, mode: String) -> void:
	UIManager.hold_pause()
	await get_tree().process_frame
	if mode == "trade":
		_trade.present(a, b)
		UIManager.open(_trade)
		await _trade.closed
	else:
		await _pvp_battle(a, b, true)
	UIManager.close()
	UIManager.release_pause()
	EventBus.pvp_finished.emit()

# Both sides pick blind. A REAL clash: damage sticks, and the winner takes
# points plus up to TWO random cards from the loser's hand.
func _pvp_battle(a: int, b: int, real: bool) -> void:
	var pa: PlayerData = GameState.players[a]
	var pb: PlayerData = GameState.players[b]
	if pa.living_team().is_empty() or pb.living_team().is_empty():
		return
	var teams := await _pvp_teams(a, b)
	if teams.is_empty():
		return
	if not real:
		teams = [teams[0].map(func(m): return m.duplicate(true)), teams[1].map(func(m): return m.duplicate(true))]
	var setup := BattleSetup.pvp(a, b, teams[0], teams[1])
	if not real:
		setup["hand"] = pa.inventory.hand.duplicate()
		setup["opp_hand"] = pb.inventory.hand.duplicate()
	var won := await BattleSetup.run(_battle, setup, a)
	if not real:
		return
	var wi: int = a if won else b
	var li: int = b if won else a
	GameState.award_points(wi, Balance.PTS_PVP_WIN)
	var stolen: Array = []
	for _n in 2:
		var key := await CardSystem.steal(li, wi)
		if key != "":
			stolen.append(CardsData.card_name(key))
	EventBus.log_entry.emit(wi, "⚔ %s wins the PvP battle! +%d pts%s" % [_name(wi), Balance.PTS_PVP_WIN,
		"" if stolen.is_empty() else ", takes: " + ", ".join(stolen)], "#ffd24d")

# [team_a, team_b] — two humans pick together on one screen; otherwise each
# side picks (humans) or auto-picks (CPUs). [] if someone backs out.
func _pvp_teams(a: int, b: int) -> Array:
	if _human(a) and _human(b):
		_select.present_pvp(GameState.players[a], GameState.players[b])
		UIManager.open(_select)
		return await _select.chosen_pvp
	var team_a: Array = await _pick_team(a, "⚔ PvP vs %s — pick your team" % _name(b), [])
	var team_b: Array = await _pick_team(b, "⚔ PvP vs %s — pick your team" % _name(a), [])
	return [] if team_a.is_empty() or team_b.is_empty() else [team_a, team_b]

# ─── DEV battles (no rewards; teams are copies) ───────────────────────────────

func _on_dev_battle_requested(kind: StringName, a: int, b: int) -> void:
	UIManager.hold_pause()
	match String(kind):
		"WARDEN", "CHAMPION":
			var foe: Dictionary = GameData.CHAMPION if kind == &"CHAMPION" else GameData.HAUNTED_FOUR.pick_random()
			var foe_team := GameData.build_team(foe["team"], 3)
			var team: Array = await _pick_team(a, "vs %s!" % foe["name"], foe_team)
			if not team.is_empty():
				var copies: Array = team.map(func(m): return m.duplicate(true))
				var setup := BattleSetup.vs_npc(a, copies, foe_team, String(foe["name"]), foe["portrait"], "warden",
					CardsData.npc_deck(2))
				setup["hand"] = GameState.players[a].inventory.hand.duplicate()
				await BattleSetup.run(_battle, setup, a)
		"PVP":
			if a != b:
				await _pvp_battle(a, b, false)
	UIManager.close()
	UIManager.release_pause()

# ─── Win ──────────────────────────────────────────────────────────────────────
# Shown directly (not via UIManager) and held paused under the winner.
func _on_game_won(idx: int) -> void:
	_win.show_win(idx)
	_win.show()
	UIManager.hold_pause()
