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
var _last_team: Array = []   # the spirits the player sent into the last NPC battle

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
		"BATTLE": await _run_battle_tile(idx)
		var k:
			if GameData.GYMS.has(k):
				if k == GameState.gang_hideout:
					await _run_hideout(idx)
				await _run_city(idx, k)
	UIManager.close()
	UIManager.release_pause()
	EventBus.tile_resolved.emit()

func _human(idx: int) -> bool:
	return not GameState.players[idx].is_cpu

func _name(idx: int) -> String:
	return GameState.players[idx].player_name

# Fight an NPC team end to end. Both sides pick BLIND from the other's full
# roster: you see their 4 and bring 3 (+2 tactic cards); they counter-pick 3
# against your whole living team. Returns true on a win, null if backed out.
func _npc_battle(idx: int, roster: Array, title: String, portrait: Array, kind: String):
	var foe_team := BattleSetup.counter_pick(roster, GameState.players[idx].living_team())
	var vs := "vs %s!" % title + ("  (brings %d of these)" % Balance.BATTLE_PICK_MAX if roster.size() > Balance.BATTLE_PICK_MAX else "")
	# you pick your team only for town Wardens and the Haunted Four / Spirit Lord;
	# trainer fights take your first spirits straight in
	var choose: bool = kind in ["gym", "warden", "champion", "gang_boss"]
	var pick: Dictionary = await BattleSetup.pick_for(_select, idx, vs, roster, choose)
	if pick.is_empty():
		return null
	_last_team = pick["team"]
	var setup := BattleSetup.vs_npc(idx, pick["team"], pick["cards"], foe_team, title, portrait, kind,
		CardsData.npc_deck(BattleSetup.BATTLE_CARDS))
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
	await _after_event(idx)

# What an event left to do once its window closes: a wild fight, a trainer
# battle (full strength for your badges), a Grim Gang fight, or a challenge.
func _after_event(idx: int) -> void:
	var foe: Dictionary = _event.take_pending_fight()
	var gang: bool = _event.take_pending_gang()
	var rival: int = _event.take_pending_challenge()
	if not foe.is_empty():
		UIManager.close()
		if foe.get("_no_catch", false):
			await _event_trainer_battle(idx, foe)
		else:
			EventBus.wild_encounter_started.emit(idx, foe)
			await EventBus.encounter_finished
	if gang:
		UIManager.close()
		await _gang_battle(idx, "Grim Gang Grunt")
	if rival >= 0 and rival < GameState.players.size():
		UIManager.close()
		await _pvp_battle(idx, rival, true)

# A trainer from an event: a full team, as strong as your badges say.
func _event_trainer_battle(idx: int, foe: Dictionary) -> void:
	var team := strong_team(idx, 3, 1)
	await _npc_battle(idx, team, String(foe.get("_trainer_name", "Trainer")), foe.get("_portrait", ["acetrainer"]), "trainer")

# ─── the Grim Gang ────────────────────────────────────────────────────────────
# Ghost bandits. Lose a fight to them and they take your LEAD to their hideout
# (one town, marked ☠). Stopping there starts a gang event — or, if they have
# one of your spirits, a fight with their boss to win it back.
const GANG_PORTRAIT := ["rocketgrunt", "rocketgruntf", "aetherfoundation"]
const BOSS_PORTRAIT := ["giovanni", "rocketboss", "aetherfoundation2"]

# A team scaled to the player's badges, `bonus` tiers tougher (max tier 3).
static func strong_team(idx: int, size: int, bonus: int) -> Array:
	var tier: int = clampi(GameData.challenge_tier(GameState.players[idx].progress.badge_count()) + bonus, 1, 3)
	var team: Array = []
	for k in size:
		var s: Dictionary = SpiritsData.random_spirit(mini(3, tier))
		if s.is_empty():
			continue
		s["stars"] = clampi(tier - 1 + bonus, 0, 3)
		team.append(s)
	return team

func _gang_battle(idx: int, title: String) -> void:
	var p: PlayerData = GameState.players[idx]
	if p.living_team().is_empty():
		return
	var won = await _npc_battle(idx, strong_team(idx, 3, 1), title, GANG_PORTRAIT, "gang")
	if won == true:
		p.inventory.gold += 20
		GameState.award_points(idx, 1)
		EventBus.log_entry.emit(idx, "%s beat the Grim Gang! +1 pt, +20 gold." % p.player_name, "#ffd24d")
	elif won == false:
		await _steal_lead(idx)

func _steal_lead(idx: int) -> void:
	var p: PlayerData = GameState.players[idx]
	if p.team.size() <= 1:
		EventBus.log_entry.emit(idx, "The Grim Gang laughs — %s has nothing worth taking." % p.player_name, "#ff9f9f")
		return
	var lead: Dictionary = p.team.pop_front()
	p.stolen.append(lead)
	Sfx.play("lose")
	var town: String = get_tree().current_scene.graph.label(GameState.gang_hideout) if get_tree().current_scene.get("graph") else "their hideout"
	EventBus.log_entry.emit(idx, "☠ The Grim Gang snatched %s's %s! Win it back at %s." % [p.player_name, lead.get("name", "?"), town], "#ff6a6a")
	var board := get_tree().current_scene
	if board and board.has_method("_show_flash"):
		await board._show_flash("☠ The Grim Gang took %s! Get it back at %s" % [lead.get("name", "?"), town], 2.0)

func _run_hideout(idx: int) -> void:
	var p: PlayerData = GameState.players[idx]
	if not p.stolen.is_empty():
		var board := get_tree().current_scene
		if board and board.has_method("_show_flash"):
			await board._show_flash("☠ The Grim Boss is waiting in the hideout…", 1.4)
		var boss := strong_team(idx, 4, 2)
		for m in boss:   # the boss's spirits are the real deal
			m["stars"] = 3
			m["atk"] = mini(6, int(m.get("atk", 1)) + 1)
			m["hp"] = int(m.get("hp", 90)) + 30
			m["current_hp"] = m["hp"]
		var won = await _npc_battle(idx, boss, "Grim Boss Vex", BOSS_PORTRAIT, "gang_boss")
		if won == true:
			var names: Array = []
			for m in p.stolen:
				m["current_hp"] = m.get("hp", 1)
				names.append(m.get("name", "?"))
				if p.team.size() < Balance.TEAM_MAX:
					p.team.append(m)
				else:
					p.pc.append(m)
			p.stolen.clear()
			p.inventory.gold += 40
			GameState.award_points(idx, 3)
			Sfx.play("win")
			EventBus.log_entry.emit(idx, "%s beat Grim Boss Vex and rescued %s! +3 pts, +40 gold." % [p.player_name, ", ".join(names)], "#ffd24d")
		elif won == false:
			EventBus.log_entry.emit(idx, "Grim Boss Vex throws %s out of the hideout!" % p.player_name, "#ff9f9f")
		return
	# nothing to rescue: the gang has something else in mind
	_event.present(idx, "gang_hideout")
	UIManager.open(_event)
	await _event.closed
	await _after_event(idx)

func _run_trainer_battle(idx: int) -> void:
	var p: PlayerData = GameState.players[idx]
	var t: Dictionary = GameData.TRAINER_BATTLES.pick_random()
	# trainers bring a full team, a tier above your badges (they're strong!)
	var tier: int = clampi(GameData.challenge_tier(p.progress.badge_count()) + 1, 1, 3)
	var entries: Array = t.get("team", [])
	var size: int = mini(entries.size(), maxi(3, Balance.BATTLE_PICK_MAX))
	var foe_team: Array = GameData.build_team(entries.slice(0, size), tier)
	var won = await _npc_battle(idx, foe_team, String(t["name"]), t.get("portrait", ["acetrainer"]), "trainer")
	if won == true:
		p.inventory.gold += int(t.get("gold", 15))
		var pts: int = int(t.get("pts", 1)) * Balance.PTS_TRAINER_MULT
		GameState.award_points(idx, pts)
		EventBus.log_entry.emit(idx, "%s beat %s! +%d pts, +%d gold." % [p.player_name, t["name"],
			pts, int(t.get("gold", 15))], "#ffd24d")

# ⚔ BATTLE tile (the Colosseum): a trainer fight — 3v3 once you have 3 spirits.
func _run_battle_tile(idx: int) -> void:
	if GameState.players[idx].living_team().is_empty():
		return
	await _run_trainer_battle(idx)

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
		"lanterns":
			for n in int(r["amount"]):
				cards.append("spirit_lantern")
			text = "You found %d Spirit Lanterns!" % int(r["amount"])
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
	var won = await _npc_battle(idx, gym_team, String(gym["name"]), GameData.gym_trainer(gym.get("type", "")), "gym")
	if won == true:
		p.progress.badges[gym["badge"]] = true
		EventBus.badge_earned.emit(idx, gym["name"])
		GameState.award_points(idx, Balance.PTS_GYM)
		p.inventory.gold += Balance.GOLD_GYM
		Sfx.play("win")
		EventBus.log_entry.emit(idx, "Beat %s! %s, +%d gold." % [gym["name"], GameData.badge_name(gym["badge"]),
			Balance.GOLD_GYM], "#ffd24d")
	elif won == false:
		# a loss still teaches: every spirit that fought grows a little
		for mon in _last_team:
			if p.team.has(mon):
				await SpiritsProgressionSystem.award_stars(idx, mon, Balance.WARDEN_LOSS_STARS)
		EventBus.log_entry.emit(idx, "%s's spirits learned from the loss: +%s★ each." % [p.player_name,
			str(Balance.WARDEN_LOSS_STARS)], "#c8b6ff")

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
# One random fight: one of the Haunted Four or Spirit Lord Vesper. Teams scale with
# badges beyond the entry requirement (GameData.trail_tier). Two warden wins in a row (or beating the Champion)
# wins the game; one loss sends you back to Cobweb City (the trail's only exit
# besides winning — so every warden tile is a real fight).
func _run_warden_tile(idx: int) -> void:
	var p: PlayerData = GameState.players[idx]
	# no skipping: the trail is a dead end, and losing is the way back down
	var pool: Array = GameData.HAUNTED_FOUR.duplicate()
	if not GameState.infinite_points:
		pool.append(GameData.CHAMPION)
	elif p.progress.elite_wins >= Balance.ELITE_WINS_TO_WIN:
		pool = [GameData.CHAMPION]   # No pts: the streak earns the Spirit Lord's fight
	var foe: Dictionary = pool.pick_random()
	var champion: bool = foe == GameData.CHAMPION
	var tier: int = GameData.trail_tier(p.progress.badge_count())
	var foe_team: Array = GameData.build_team(foe["team"], tier)
	var won = await _npc_battle(idx, foe_team, String(foe["name"]), foe.get("portrait", []) + ["acetrainer"],
		"champion" if champion else "warden")
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
			EventBus.log_entry.emit(idx, "%s defeated %s! Haunted Four wins: %d/%d%s" % [p.player_name, foe["name"],
				p.progress.elite_wins, Balance.ELITE_WINS_TO_WIN,
				" — Spirit Lord Vesper awaits!" if GameState.infinite_points and p.progress.elite_wins >= Balance.ELITE_WINS_TO_WIN else ""],
				"#ffd24d")
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
# points, gold and a random card from the loser's hand, and its lead gains a
# star.
func _pvp_battle(a: int, b: int, real: bool) -> void:
	var pa: PlayerData = GameState.players[a]
	var pb: PlayerData = GameState.players[b]
	if pa.living_team().is_empty() or pb.living_team().is_empty():
		return
	var picks := await _pvp_picks(a, b)
	if picks.is_empty():
		return
	if not real:   # dev fight: copies, and no cards are used up
		for pk in picks:
			pk["team"] = pk["team"].map(func(m): return m.duplicate(true))
	var setup := BattleSetup.pvp(a, b, picks[0], picks[1])
	if not real:
		setup["hand_source"] = []
		setup["opp_source"] = []
	var won := await BattleSetup.run(_battle, setup, a)
	if not real:
		return
	var wi: int = a if won else b
	var li: int = b if won else a
	var gold: int = mini(Balance.GOLD_PVP_TAKE, GameState.players[li].inventory.gold)
	GameState.players[li].inventory.gold -= gold
	GameState.players[wi].inventory.gold += gold
	var lead: Dictionary = GameState.players[wi].lead()
	if not lead.is_empty():
		await SpiritsProgressionSystem.award_stars(wi, lead, Balance.PVP_WIN_STARS)
	GameState.award_points(wi, Balance.PTS_PVP_WIN)
	var stolen: Array = []
	for _n in Balance.PVP_STEAL_CARDS:
		var key := await CardSystem.steal(li, wi)
		if key != "":
			stolen.append(CardsData.card_name(key))
	EventBus.log_entry.emit(wi, "⚔ %s wins the PvP battle! +%d pts, +%d gold, lead +%s★%s" % [_name(wi),
		Balance.PTS_PVP_WIN, gold, str(Balance.PVP_WIN_STARS),
		"" if stolen.is_empty() else ", takes: " + ", ".join(stolen)], "#ffd24d")

# [pick_a, pick_b] ({team, cards} each) — two humans pick together on one
# screen; otherwise each side picks (humans) or auto-picks (CPUs) against the
# other's full living team. [] if someone backs out.
func _pvp_picks(a: int, b: int) -> Array:
	if _human(a) and _human(b):
		_select.present_pvp(GameState.players[a], GameState.players[b])
		UIManager.open(_select)
		return await _select.chosen_pvp
	var pick_a: Dictionary = await BattleSetup.pick_for(_select, a, "⚔ PvP vs %s" % _name(b), GameState.players[b].living_team())
	var pick_b: Dictionary = await BattleSetup.pick_for(_select, b, "⚔ PvP vs %s" % _name(a), GameState.players[a].living_team())
	return [] if pick_a.is_empty() or pick_b.is_empty() else [pick_a, pick_b]

# ─── DEV battles (no rewards; teams are copies) ───────────────────────────────

func _on_dev_battle_requested(kind: StringName, a: int, b: int) -> void:
	UIManager.hold_pause()
	match String(kind):
		"WARDEN", "CHAMPION":
			var foe: Dictionary = GameData.CHAMPION if kind == &"CHAMPION" else GameData.HAUNTED_FOUR.pick_random()
			var roster := GameData.build_team(foe["team"], 3)
			var foe_team := BattleSetup.counter_pick(roster, GameState.players[a].living_team())
			var pick: Dictionary = await BattleSetup.pick_for(_select, a, "vs %s!" % foe["name"], roster)
			if not pick.is_empty():
				var copies: Array = pick["team"].map(func(m): return m.duplicate(true))
				var setup := BattleSetup.vs_npc(a, copies, pick["cards"], foe_team, String(foe["name"]), foe["portrait"],
					"warden", CardsData.npc_deck(BattleSetup.BATTLE_CARDS))
				setup["hand_source"] = []   # dev fight: cards aren't used up
				await BattleSetup.run(_battle, setup, a)
		"PVP":
			if a != b:
				await _pvp_battle(a, b, false)
	UIManager.close()
	UIManager.release_pause()

# ─── Win ──────────────────────────────────────────────────────────────────────
# Shown directly (not via UIManager) and held paused under the winner. If the
# winning points came mid-window (a podium, a battle), the win screen waits
# until that window is closed so the two never overlap.
func _on_game_won(idx: int) -> void:
	UIManager.hold_pause()
	await get_tree().process_frame
	while UIManager.is_open():
		await get_tree().process_frame
	UIManager.close_overlay()
	_win.show_win(idx)
	_win.show()
	Sfx.play("win")
