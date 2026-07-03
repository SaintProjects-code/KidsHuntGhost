extends CanvasLayer
## Owns and sequences the non-PKMN tile windows (EVENT / ITEM / COMPETITION /
## CITY → Gym / Shop / Elite Four / Gary) and the WinScreen. Added by Board.gd.
##
## Listens for EventBus.tile_action and emits EventBus.tile_resolved when done.
## Also watches EventBus.game_won and shows the WinScreen.

var _event: Control
var _item: Control
var _comp: Control
var _city: Control
var _shop: Control
var _battle: Control
var _select: Control
var _pc: Control
var _win: Control

func _ready() -> void:
	layer = 12
	_event = preload("res://Scenes/UI/SpiritEventWindow.gd").new()
	_item = preload("res://Scenes/UI/ItemWindow.gd").new()
	_comp = preload("res://Scenes/UI/CompetitionWindow.gd").new()
	_city = preload("res://Scenes/UI/CityWindow.gd").new()
	_shop = preload("res://Scenes/UI/ShopWindow.gd").new()
	_battle = preload("res://Scenes/UI/BattleScreen.gd").new()
	_select = preload("res://Scenes/UI/BattleTeamSelect.gd").new()
	_pc = preload("res://Scenes/UI/PCWindow.gd").new()
	_win = preload("res://Scenes/UI/WinScreen.gd").new()
	_win.process_mode = Node.PROCESS_MODE_ALWAYS   # works while the tree is paused
	for w in [_event, _item, _comp, _city, _shop, _battle, _select, _pc, _win]:
		add_child(w)
	EventBus.tile_action.connect(_on_tile_action)
	EventBus.game_won.connect(_on_game_won)

func _on_tile_action(player_index: int, kind: StringName) -> void:
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
	elif GameData.GYMS.has(k):
		await _run_city(player_index, k)
	_finish()

func _finish() -> void:
	UIManager.close()
	EventBus.tile_resolved.emit()

func _is_human(idx: int) -> bool:
	return not GameState.players[idx].is_cpu

# ─── EVENT ────────────────────────────────────────────────────────────────────
# Mewgenics-style: a trainer/spirit + stat-based choices (SpiritEventWindow).
func _run_event(idx: int) -> void:
	if _is_human(idx):
		_event.present(idx)
		UIManager.open(_event)
		await _event.closed
	else:
		_event.resolve_cpu(idx)
	# A "fight" outcome hands off to the normal wild-encounter flow.
	var foe: Dictionary = _event.take_pending_fight()
	if not foe.is_empty():
		UIManager.close()
		EventBus.wild_encounter_started.emit(idx, foe)
		await EventBus.encounter_finished

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
			SpiritsProgressionSystem.award_stars(idx, team[int(i)], credits[i])

# ─── ITEM ─────────────────────────────────────────────────────────────────────
func _run_item(idx: int) -> void:
	var item: Dictionary = GameData.random_item()
	if _is_human(idx):
		_item.present_reward(idx, item)
		UIManager.open(_item)
		await _item.closed
	else:
		_item.grant(idx, item)

# ─── COMPETITION ──────────────────────────────────────────────────────────────
func _run_competition(idx: int) -> void:
	_comp.present(idx)   # scores all players and awards the winner
	if _is_human(idx):
		UIManager.open(_comp)
		await _comp.closed

# ─── CITY ─────────────────────────────────────────────────────────────────────
func _run_city(idx: int, city: String) -> void:
	if not _is_human(idx):
		return   # CPUs skip city actions for now
	_city.present(idx, city)
	UIManager.open(_city)
	while true:
		var action: String = await _city.chose
		match action:
			"leave":
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
	var gym_team: Array = GameData.build_team(gym.get("team", []), 1)
	var team: Array = await _pick_team(idx, "vs %s   [%s]" % [gym.get("name", "Gym"), gym.get("type", "")], gym_team)
	if team.is_empty():
		return
	_battle.present(team, gym_team, "Gym: %s" % gym.get("name", ""), GameState.players[idx].color, _take_mod(idx),
		GameData.player_trainer(GameState.players[idx].player_name), GameData.gym_trainer(gym.get("type", "")))
	UIManager.open(_battle)
	var won: bool = await _battle.finished
	_grant_battle_stars(idx, team)
	if won:
		GameState.players[idx].progress.badges[gym.get("badge", "")] = true
		EventBus.badge_earned.emit(idx, gym.get("name", ""))
		GameState.award_points(idx, 3)

func _run_elite(idx: int) -> void:
	# One pick for the whole gauntlet (Elite Four, then Gary); the preview
	# shows the first Elite's lineup.
	var first_team: Array = GameData.build_team(GameData.ELITE_FOUR[0].get("team", []), 2)
	var team: Array = await _pick_team(idx, "vs the Elite Four!", first_team)
	if team.is_empty():
		return
	var pt: Array = GameData.player_trainer(GameState.players[idx].player_name)
	for e in GameData.ELITE_FOUR:
		# try the elite's own name as a portrait (e.g. "agatha"), else generic
		var ename: String = String(e.get("name", "")).to_lower().split(" ")[-1]
		_battle.present(team, GameData.build_team(e.get("team", []), 2), e.get("name", "Elite"),
			GameState.players[idx].color, _take_mod(idx), pt, [ename, "agatha-gen1", "acetrainer"])
		UIManager.open(_battle)
		var won: bool = await _battle.finished
		_grant_battle_stars(idx, team)
		if not won:
			return
	# Champion Gary
	_battle.present(team, GameData.build_team(GameData.GARY.get("team", []), 3), "Champion Gary",
		GameState.players[idx].color, 0, pt, ["gary", "blue-gen1", "blue", "acetrainer-gen1"])
	UIManager.open(_battle)
	var beat: bool = await _battle.finished
	_grant_battle_stars(idx, team)
	if beat:
		GameState.players[idx].progress.gary_defeated = true
		GameState.award_points(idx, 10)   # also triggers the win check

# ─── Win ──────────────────────────────────────────────────────────────────────
# Shown directly (not via UIManager) so the controllers' cleanup can't hide it.
# It sits on top (last child, process_mode = Always) and pauses the game.
func _on_game_won(player_index: int) -> void:
	_win.show_win(player_index)
	_win.show()
	get_tree().paused = true
