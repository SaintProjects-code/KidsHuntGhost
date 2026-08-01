extends CanvasLayer
## Owns and sequences the non-PKMN tile windows (EVENT / ITEM / COMPETITION /
## CITY → Gym / Shop / Elite Four / Gary) and the WinScreen. Added by Board.gd.
##
## Listens for EventBus.tile_action and emits EventBus.tile_resolved when done.
## Also watches EventBus.game_won and shows the WinScreen.

const GYM_GOLD := 25   # gold prize for beating a gym (on top of badge + points)

var _event: Control
var _item: Control
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
	# The board pauses while a tile event runs; these windows must keep working.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_event = preload("res://Scenes/UI/SpiritEventWindow.gd").new()
	_item = preload("res://Scenes/UI/ItemWindow.gd").new()
	_comp = preload("res://Scenes/UI/CompetitionWindow.gd").new()
	_city = preload("res://Scenes/UI/CityWindow.gd").new()
	_shop = preload("res://Scenes/UI/ShopWindow.gd").new()
	_battle = preload("res://Scenes/UI/BattleScreen.gd").new()
	_select = preload("res://Scenes/UI/BattleTeamSelect.gd").new()
	_pc = preload("res://Scenes/UI/PCWindow.gd").new()
	_trade = preload("res://Scenes/UI/TradeWindow.gd").new()
	for w in [_event, _item, _comp, _city, _shop, _battle, _select, _pc, _trade]:
		add_child(w)
		w.set_click_through(true)   # action bar (lower layer) stays pressable
	# The win screen lives on its OWN high layer (above the board chrome at 15
	# and the pop-ups here at 12) so nothing renders on top of the winner.
	var win_layer := CanvasLayer.new()
	win_layer.layer = 60
	win_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(win_layer)
	_win = preload("res://Scenes/UI/WinScreen.gd").new()
	_win.process_mode = Node.PROCESS_MODE_ALWAYS   # works while the tree is paused
	win_layer.add_child(_win)
	EventBus.tile_action.connect(_on_tile_action)
	EventBus.game_won.connect(_on_game_won)
	EventBus.dev_battle_requested.connect(_on_dev_battle_requested)
	EventBus.pvp_started.connect(_on_pvp_started)

# DEV: run a battle flow with NO rewards (stars/points/badges). PvP fights the
# two chosen players; Elite Four / Gary run their gauntlet for player `a`.
func _on_dev_battle_requested(kind: StringName, a: int, b: int) -> void:
	UIManager.hold_pause()
	match String(kind):
		"ELITE":
			await _run_elite(a, false)
		"GARY":
			await _run_gary(a, false)
		"PVP":
			await _run_pvp(a, b)
	UIManager.close()
	UIManager.release_pause()

func _copy_team(team: Array) -> Array:
	var out: Array = []
	for m in team:
		out.append(m.duplicate(true))
	return out

# A dev fight between two players. BOTH pick their own team, blind to the other's
# choice (no opponent lineup shown); CPUs auto-pick. Teams are copied so nothing
# real changes, and there are no rewards.
func _run_pvp(a: int, b: int) -> void:
	if a == b or a < 0 or b < 0:
		return
	if GameState.players[a].team.is_empty() or GameState.players[b].team.is_empty():
		return
	var team_a: Array
	var team_b: Array
	if not GameState.players[a].is_cpu and not GameState.players[b].is_cpu:
		# Both human: pick at the same time on one screen.
		_select.present_pvp(GameState.players[a], GameState.players[b])
		UIManager.open(_select)
		var res: Array = await _select.chosen_pvp
		if res.size() < 2:
			return   # backed out
		team_a = _copy_team(res[0])
		team_b = _copy_team(res[1])
	else:
		# A CPU is involved: it auto-picks, the human picks blind.
		team_a = await _pvp_pick(a)
		if team_a.is_empty():
			return
		team_b = await _pvp_pick(b)
		if team_b.is_empty():
			return
	_battle.present(team_a, team_b,
		"%s vs %s" % [GameState.players[a].player_name, GameState.players[b].player_name],
		GameState.players[a].color, 0,
		GameData.player_trainer(GameState.players[a].player_name),
		GameData.player_trainer(GameState.players[b].player_name),
		[GameState.players[a].player_name, GameState.players[b].player_name])
	UIManager.open(_battle)
	await _battle.finished   # dev fight: no stars/points

# One side's team for a PvP fight: a human picks it (with NO opponent lineup shown,
# so the other player's spirits stay hidden); a CPU auto-picks its first few.
func _pvp_pick(picker: int) -> Array:
	if GameState.players[picker].is_cpu:
		return _copy_team(GameState.players[picker].team.slice(0, 4))
	var picked: Array = await _pick_team(picker, "%s — pick your team" % GameState.players[picker].player_name, [])
	return _copy_team(picked)

func _on_tile_action(player_index: int, kind: StringName) -> void:
	UIManager.hold_pause()   # game (HUD timer, board) pauses for the event
	# Yield once so the board reaches its `await tile_resolved` before any
	# synchronous (CPU) path emits it.
	await get_tree().process_frame
	var k := String(kind)
	if k == "EVENT":
		await _run_event(player_index)
	elif k == "ITEM":
		await _run_item(player_index)
	elif k == "COMPETITION":
		await _run_competition(player_index)
	elif k == "E4":
		# Victory Road tile: ONE random Elite battle (Gary is in the pool).
		# Win two of these and the game is yours. CPUs fight with a full team.
		await _run_e4_tile(player_index)
	elif GameData.GYMS.has(k):
		await _run_city(player_index, k)
	_finish()

func _finish() -> void:
	UIManager.close()
	UIManager.release_pause()
	EventBus.tile_resolved.emit()

# ─── ⚔ PvP clashes (walk-past choice or forced landing) ──────────────────────

func _on_pvp_started(a: int, b: int, mode: String) -> void:
	UIManager.hold_pause()
	await get_tree().process_frame
	if mode == "trade":
		_trade.present(a, b)
		UIManager.open(_trade)
		await _trade.closed
	else:
		await _pvp_battle(a, b)
	UIManager.close()
	UIManager.release_pause()
	EventBus.pvp_finished.emit()

# A REAL PvP battle: both sides pick blind, damage sticks, and the winner
# takes 4 points plus up to TWO of the loser's items.
func _pvp_battle(a: int, b: int) -> void:
	var pa: PlayerData = GameState.players[a]
	var pb: PlayerData = GameState.players[b]
	if pa.team.is_empty() or pb.team.is_empty():
		return
	var team_a: Array
	var team_b: Array
	if not pa.is_cpu and not pb.is_cpu:
		_select.present_pvp(pa, pb)
		UIManager.open(_select)
		var res: Array = await _select.chosen_pvp
		if res.size() < 2:
			return   # backed out — no fight
		team_a = res[0]
		team_b = res[1]
	else:
		team_a = await _pvp_pick_real(a)
		team_b = await _pvp_pick_real(b)
	if team_a.is_empty() or team_b.is_empty():
		return
	_battle.present(team_a, team_b, "%s vs %s" % [pa.player_name, pb.player_name],
		pa.color, 0, GameData.player_trainer(pa.player_name),
		GameData.player_trainer(pb.player_name), [pa.player_name, pb.player_name])
	UIManager.open(_battle)
	var won: bool
	if pa.is_cpu and pb.is_cpu:
		await _battle.autoplay()
		won = _battle._won
	else:
		won = await _battle.finished
	await _grant_battle_stars(a, team_a)
	var wi: int = a if won else b
	var li: int = b if won else a
	GameState.award_points(wi, 4)
	var stolen: Array = []
	for _n in 2:
		var inv_l = GameState.players[li].inventory
		if inv_l.items.is_empty():
			break
		var entry: Dictionary = inv_l.items[randi() % inv_l.items.size()]
		var loot := {"name": entry.get("name", "Item"), "kind": entry.get("kind", ""),
			"amount": entry.get("amount", 0)}
		inv_l.consume_item(entry)
		GameState.players[wi].inventory.add_item(loot)
		stolen.append(String(loot["name"]))
	EventBus.log_entry.emit(wi, "⚔ %s wins the PvP battle! +4 pts%s" % [
		GameState.players[wi].player_name,
		"" if stolen.is_empty() else ", takes: " + ", ".join(stolen)], "#ffd24d")

# One side's REAL team for a PvP clash: humans pick blind, CPUs auto-pick.
func _pvp_pick_real(i: int) -> Array:
	var p: PlayerData = GameState.players[i]
	if p.is_cpu:
		return p.team.filter(func(m): return int(m.get("current_hp", 0)) > 0).slice(0, 4)
	return await _pick_team(i, "%s — pick your team (⚔ PvP!)" % p.player_name, [])

func _is_human(idx: int) -> bool:
	return not GameState.players[idx].is_cpu

# ─── CPU helpers ──────────────────────────────────────────────────────────────

# The CPU's battle squad: its first 4 living spirits (real dicts, so battle
# damage and star credits land on the actual team).
func _cpu_team(idx: int) -> Array:
	var p: PlayerData = GameState.players[idx]
	return p.team.filter(func(m): return int(m.get("current_hp", 0)) > 0).slice(0, 4)

# Run a CPU battle ON SCREEN, always: the battle window opens and plays
# itself at a watchable pace (full engine: abilities, traits, HP write-back).
func _cpu_battle(idx: int, team: Array, opp: Array, title: String, foe_trainer: Array) -> bool:
	if team.is_empty():
		return false
	_battle.present(team, opp, title, GameState.players[idx].color, _take_mod(idx),
		GameData.player_trainer(GameState.players[idx].player_name), foe_trainer)
	UIManager.open(_battle)      # visible: the intro starts on open
	await _battle.autoplay()
	var won: bool = _battle._won
	# feed the CPU's momentum: a win pushes it toward gyms/E4, a loss toward training
	var pl: PlayerData = GameState.players[idx]
	pl.cpu_momentum = clampi(pl.cpu_momentum + (1 if won else -3), -6, 6)
	await _grant_battle_stars(idx, team)
	EventBus.log_entry.emit(idx, "%s %s the battle: %s" % [
		GameState.players[idx].player_name, "won" if won else "lost", title],
		"#9fff9f" if won else "#ff9f9f")
	return won

# CPU shopping list: keep 3 balls, one potion and one revive in the bag.
# Purchases are announced in the game log.
func _cpu_shop(idx: int) -> void:
	var inv = GameState.players[idx].inventory
	var bought: Array = []
	while inv.ball_count(&"spirit_ball") < 3 and inv.gold >= 10:
		inv.gold -= 10
		inv.balls[&"spirit_ball"] = inv.ball_count(&"spirit_ball") + 1
		bought.append("Spirit Ball")
	if inv.gold >= 15 and not _has_item_kind(inv, "potion"):
		if inv.add_item({"name": "Potion", "kind": "potion", "amount": 40}):
			inv.gold -= 15
			bought.append("Potion")
	if inv.gold >= 35 and not _has_item_kind(inv, "revive"):
		if inv.add_item({"name": "Revive", "kind": "revive"}):
			inv.gold -= 35
			bought.append("Revive")
	if not bought.is_empty():
		EventBus.log_entry.emit(idx, "%s shops: %s" % [
			GameState.players[idx].player_name, ", ".join(bought)], "#f0c36a")

func _has_item_kind(inv, kind: String) -> bool:
	for e in inv.items:
		if String(e.get("kind", "")) == kind:
			return true
	return false

# CPU city visit: stock up, challenge the gym (needs a 4-spirit team), and
# head for Victory Road once it has 3 badges and a full team of 6.
func _cpu_city(idx: int, city: String) -> void:
	var p: PlayerData = GameState.players[idx]
	_cpu_shop(idx)
	var gym: Dictionary = GameData.gym_for_city(city)
	# Whether to actually take on the gym / Victory Road is governed purely by the
	# CPU's momentum — a losing streak makes it skip and go train instead.
	if gym.get("badge", "") != "" and not p.progress.badges.get(gym.get("badge", ""), false) \
			and p.team.size() >= 4 and GameData.cpu_will_gym(p):
		await _run_gym(idx, city)
	if GameState.winner_index == -1 and p.progress.badge_count() >= 3 \
			and p.team_ready_for_victory() and GameData.cpu_will_gym(p):
		EventBus.victory_road_entered.emit(idx)

# ─── EVENT ────────────────────────────────────────────────────────────────────
# Mewgenics-style: a trainer/spirit + stat-based choices (SpiritEventWindow).
# Some EVENT tiles are instead a full TRAINER BATTLE (team vs team).
func _run_event(idx: int) -> void:
	# ~30% of events are a trainer battle (needs a team to field one)
	# trainer battles only challenge players with a real squad (3+ spirits)
	if GameState.players[idx].team.size() >= 3 and randf() < 0.3:
		await _run_trainer_battle(idx)
		return
	# CPU landings ALWAYS show the window — it plays itself (pages, pick, result)
	if _is_human(idx):
		_event.present(idx)
	else:
		_event.present_cpu(idx)
	UIManager.open(_event)
	await _event.closed
	# A "fight" outcome hands off to the normal wild-encounter flow.
	var foe: Dictionary = _event.take_pending_fight()
	if not foe.is_empty():
		UIManager.close()
		EventBus.wild_encounter_started.emit(idx, foe)
		await EventBus.encounter_finished

# A themed trainer challenges you to a team battle. Their team scales with your
# badges; a win pays points + gold (no badge). Humans pick a team, CPUs auto.
func _run_trainer_battle(idx: int) -> void:
	var t: Dictionary = GameData.TRAINER_BATTLES.pick_random()
	var tier: int = GameData.challenge_tier(GameState.players[idx].progress.badge_count())
	# ⚔-tagged challengers face the trainer's full roster; before that, 1-2.
	var entries: Array = t.get("team", [])
	var size: int = GameData.trainer_team_size(GameState.players[idx].pvp_tag, entries.size())
	var foe_team: Array = GameData.build_team_designed(entries.slice(0, size), tier)
	var portrait: Array = t.get("portrait", ["acetrainer"])
	var won: bool
	if _is_human(idx):
		var team: Array = await _pick_team(idx, "vs %s!" % t.get("name", "Trainer"), foe_team)
		if team.is_empty():
			return   # backed out — no battle
		_battle.present(team, foe_team, String(t.get("name", "Trainer")),
			GameState.players[idx].color, _take_mod(idx),
			GameData.player_trainer(GameState.players[idx].player_name), portrait)
		UIManager.open(_battle)
		won = await _battle.finished
		await _grant_battle_stars(idx, team)
	else:
		won = await _cpu_battle(idx, _cpu_team(idx), foe_team, String(t.get("name", "Trainer")), portrait)
	if won:
		GameState.players[idx].inventory.gold += int(t.get("gold", 15))
		GameState.award_points(idx, int(t.get("pts", 1)))
		EventBus.log_entry.emit(idx, "%s beat %s! +%d pts, +%d gold." % [
			GameState.players[idx].player_name, t.get("name", "Trainer"),
			int(t.get("pts", 1)), int(t.get("gold", 15))], "#ffd24d")

# Read-and-clear the player's event status effect (blessed/spooked ATK mod);
# it applies to their next battle only.
func _take_mod(idx: int) -> int:
	var mod: int = GameState.players[idx].next_battle_mod
	GameState.players[idx].next_battle_mod = 0
	return mod

# Stars earned in the battle (KOs + surviving a win) go to the real spirits.
func _grant_battle_stars(idx: int, team: Array) -> void:
	var credits: Dictionary = _battle.take_star_credits()
	for i in credits:
		if int(i) < team.size():
			# Awaited: a spirit hitting 3 stars pops the bonus-reward flow, and
			# the battle sequence waits for the player to resolve it.
			await SpiritsProgressionSystem.award_stars(idx, team[int(i)], credits[i])

# ─── ITEM ─────────────────────────────────────────────────────────────────────
func _run_item(idx: int) -> void:
	var item: Dictionary = GameData.random_item()
	_item.present_reward(idx, item)
	UIManager.open(_item)
	if _is_human(idx):
		await _item.closed
	else:
		# CPU landing: the found-item window shows briefly, then moves on
		await get_tree().create_timer(1.8).timeout

# ─── COMPETITION ──────────────────────────────────────────────────────────────
func _run_competition(idx: int) -> void:
	# EVERYONE competes, no matter who landed the tile. In an all-CPU game
	# nobody can press the phase buttons, so the window drives itself.
	_comp.present(idx)
	UIManager.open(_comp)
	if not _any_human():
		_comp.run_cpu_auto()
	await _comp.closed

func _any_human() -> bool:
	for p in GameState.players:
		if not p.is_cpu:
			return true
	return false

# ─── CITY ─────────────────────────────────────────────────────────────────────
func _run_city(idx: int, city: String) -> void:
	if not _is_human(idx):
		# show the town menu (locked) so everyone sees the CPU's visit…
		_city.present_cpu(idx, city)
		UIManager.open(_city)
		await get_tree().create_timer(1.6).timeout
		# …then its choices play out (shop log, gym battle, Victory Road)
		await _cpu_city(idx, city)
		return
	_city.present(idx, city)
	UIManager.open(_city)
	while true:
		var action: String = await _city.chose
		match action:
			"leave":
				break
			"victory":
				# teleport to Victory Road; the city visit (and move) is over
				EventBus.victory_road_entered.emit(idx)
				break
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
			"elite":
				await _run_elite(idx)
		if GameState.winner_index != -1:
			break
		_city.present(idx, city)
		UIManager.open(_city)

# Let the player pick their battle team (up to 4, click order = battle order),
# with the enemy lineup shown alongside. Returns [] if they back out.
func _pick_team(idx: int, vs_text: String, opp_team: Array) -> Array:
	if GameState.players[idx].team.is_empty():
		return []
	_select.present(GameState.players[idx], vs_text, opp_team)
	UIManager.open(_select)
	return await _select.chosen

func _run_gym(idx: int, city: String) -> void:
	var gym: Dictionary = GameData.gym_for_city(city)
	# the gym's team scales with the challenger's badges (1 weak → 3 strong)
	var tier: int = GameData.challenge_tier(GameState.players[idx].progress.badge_count())
	var gym_team: Array = GameData.build_team_designed(gym.get("team", []), tier)
	var won: bool
	if _is_human(idx):
		var team: Array = await _pick_team(idx, "vs %s   [%s]" % [gym.get("name", "Gym"), gym.get("type", "")], gym_team)
		if team.is_empty():
			return
		_battle.present(team, gym_team, "Gym: %s" % gym.get("name", ""), GameState.players[idx].color, _take_mod(idx),
			GameData.player_trainer(GameState.players[idx].player_name), GameData.gym_trainer(gym.get("type", "")))
		UIManager.open(_battle)
		won = await _battle.finished
		await _grant_battle_stars(idx, team)
	else:
		won = await _cpu_battle(idx, _cpu_team(idx), gym_team, "Gym: %s" % gym.get("name", ""),
			GameData.gym_trainer(gym.get("type", "")))
	if won:
		GameState.players[idx].progress.badges[gym.get("badge", "")] = true
		EventBus.badge_earned.emit(idx, gym.get("name", ""))
		GameState.award_points(idx, 3)
		GameState.players[idx].inventory.gold += GYM_GOLD
		EventBus.log_entry.emit(idx, "Beat %s! +%d gold prize." % [gym.get("name", "the gym"), GYM_GOLD], "ffd24d")

# Victory Road E4 tile: battle ONE random member — the four Elites or Gary.
# Their teams scale with the challenger's badges. Each win counts toward the
# championship: TWO wins and the game is won (checked in GameState).
# CPUs fight too, but only with a full team of 6.
func _run_e4_tile(idx: int) -> void:
	if not _is_human(idx) and GameState.players[idx].team.size() < 6:
		return   # a CPU won't face the Elite without a full squad
	var pool: Array = GameData.ELITE_FOUR.duplicate()
	pool.append(GameData.GARY)
	var foe: Dictionary = pool.pick_random()
	var tier: int = GameData.challenge_tier(GameState.players[idx].progress.badge_count())
	var foe_team: Array = GameData.build_team_designed(foe.get("team", []), tier)
	var ename: String = String(foe.get("name", "elite")).to_lower().split(" ")[-1]
	var won: bool
	if _is_human(idx):
		var team: Array = await _pick_team(idx, "vs %s!" % foe.get("name", "Elite"), foe_team)
		if team.is_empty():
			return
		_battle.present(team, foe_team, String(foe.get("name", "Elite")),
			GameState.players[idx].color, _take_mod(idx),
			GameData.player_trainer(GameState.players[idx].player_name),
			[ename, "agatha-gen1", "acetrainer"])
		UIManager.open(_battle)
		won = await _battle.finished
		await _grant_battle_stars(idx, team)
	else:
		won = await _cpu_battle(idx, _cpu_team(idx), foe_team,
			String(foe.get("name", "Elite")), [ename, "agatha-gen1", "acetrainer"])
	var prog = GameState.players[idx].progress
	if won:
		prog.elite_four += 1
		EventBus.log_entry.emit(idx, "%s defeated %s! Elite wins: %d/2" % [
			GameState.players[idx].player_name, foe.get("name", "?"), prog.elite_four], "#ffd24d")
		GameState.award_points(idx, 5)   # +5 pts; also runs the win check
	else:
		# a single Victory Road loss ends the run — back to Cobweb City, and
		# the win streak resets (you must take both Elites without a loss)
		prog.elite_four = 0
		EventBus.log_entry.emit(idx, "%s lost to %s and is sent back to Cobweb City!" % [
			GameState.players[idx].player_name, foe.get("name", "?")], "#ff9f9f")
		EventBus.victory_road_failed.emit(idx)

func _run_elite(idx: int, award := true) -> void:
	# One pick for the whole gauntlet (Elite Four, then Gary); the preview
	# shows the first Elite's lineup. Teams scale with the challenger's badges.
	var tier: int = GameData.challenge_tier(GameState.players[idx].progress.badge_count())
	var first_team: Array = GameData.build_team_designed(GameData.ELITE_FOUR[0].get("team", []), tier)
	var picked: Array = await _pick_team(idx, "vs the Elite Four!", first_team)
	if picked.is_empty():
		return
	var team: Array = picked if award else _copy_team(picked)
	var pt: Array = GameData.player_trainer(GameState.players[idx].player_name)
	for e in GameData.ELITE_FOUR:
		# try the elite's own name as a portrait (e.g. "agatha"), else generic
		var ename: String = String(e.get("name", "")).to_lower().split(" ")[-1]
		_battle.present(team, GameData.build_team_designed(e.get("team", []), tier), e.get("name", "Elite"),
			GameState.players[idx].color, (_take_mod(idx) if award else 0), pt, [ename, "agatha-gen1", "acetrainer"])
		UIManager.open(_battle)
		var won: bool = await _battle.finished
		if award:
			await _grant_battle_stars(idx, team)
		if not won:
			return
	await _gary_battle(idx, team, pt, award)

# Dev "Gary" button: pick a team, then fight the Champion (no rewards).
func _run_gary(idx: int, award := true) -> void:
	var preview: Array = GameData.build_team(GameData.GARY.get("team", []), 3)
	var picked: Array = await _pick_team(idx, "vs Champion Gary!", preview)
	if picked.is_empty():
		return
	var team: Array = picked if award else _copy_team(picked)
	await _gary_battle(idx, team, GameData.player_trainer(GameState.players[idx].player_name), award)

func _gary_battle(idx: int, team: Array, pt: Array, award := true) -> void:
	var tier: int = GameData.challenge_tier(GameState.players[idx].progress.badge_count())
	_battle.present(team, GameData.build_team_designed(GameData.GARY.get("team", []), tier), "Champion Gary",
		GameState.players[idx].color, 0, pt, ["gary", "blue-gen1", "blue", "acetrainer-gen1"])
	UIManager.open(_battle)
	var beat: bool = await _battle.finished
	if award:
		await _grant_battle_stars(idx, team)
		if beat:
			GameState.players[idx].progress.gary_defeated = true
			GameState.award_points(idx, 10)   # also triggers the win check

# ─── Win ──────────────────────────────────────────────────────────────────────
# Shown directly (not via UIManager) so the controllers' cleanup can't hide it.
# It sits on top (last child, process_mode = Always) and pauses the game.
func _on_game_won(player_index: int) -> void:
	_win.show_win(player_index)
	_win.show()
	# A permanent hold: the event flow that triggered the win releases its own
	# hold, and this one keeps the tree paused under the win screen.
	UIManager.hold_pause()

