extends Node
## Autoloaded. The match being played: players, whose turn it is, settings.

var players: Array[PlayerData] = []
var current_player_index: int = 0
var turn_count: int = 0
var win_threshold: int = 30          # 40 made full games drag (playtest: ~22 pts by turn 43)
var infinite_points: bool = false   # setup "No pts": only the Spirit Lord wins (beat 2 Haunted Four in a row to face him)
var active_map: int = 1
var battle_size: int = 3:          # 3v3 / 4v4 / 6v6, chosen in Game Settings
	set(v):
		battle_size = v if v in [3, 4, 6] else 3
		Balance.BATTLE_PICK_MAX = battle_size
# Badges needed to enter the Spectral Trail (the Haunted Four) and to Fly,
# chosen in Game Settings.
var trail_badges: int = Balance.FLY_BADGES:
	set(v):
		trail_badges = clampi(v, 1, 8)
var winner_index: int = -1          # set once someone wins
var dev_mode: bool = false          # only for games started from the menu's DEV button

# ── end-of-game stats: counted from game events into each PlayerData.stats ────
func _ready() -> void:
	EventBus.turn_started.connect(func(i): _stat(i, "turns"))
	EventBus.dice_rolled.connect(func(total, _f):
		_stat(current_player_index, "rolls")
		_stat(current_player_index, "dice_total", total))
	EventBus.space_landed.connect(_on_landed)
	EventBus.catch_succeeded.connect(func(i, _s): _stat(i, "catches"))
	EventBus.catch_failed.connect(func(i, _s): _stat(i, "escapes"))
	EventBus.card_played.connect(func(i, _k): _stat(i, "cards_played"))
	EventBus.spirit_evolved.connect(func(i, _s): _stat(i, "evolutions"))
	EventBus.trail_failed.connect(func(i): _stat(i, "trail_losses"))

func _stat(i: int, key: String, amount: int = 1) -> void:
	if i >= 0 and i < players.size():
		players[i].add_stat(key, amount)

func _on_landed(i: int, type: StringName) -> void:
	match String(type):
		"WISP", "GHOST", "PHANTOM": _stat(i, "ghost_tiles")
		"EVENT": _stat(i, "events")
		"ITEM": _stat(i, "item_tiles")
		"COMPETITION": _stat(i, "comps")
		"CLASH": _stat(i, "clash_tiles")
		"CITY": _stat(i, "town_visits")

# Every battle (wild, Warden, Haunted Four, Clash) reports here; see BattleSetup.
func record_battle(i: int, won: bool) -> void:
	_stat(i, "battles")
	_stat(i, "wins" if won else "losses")

func current_player() -> PlayerData:
	return players[current_player_index]

# Award points and check for a win.
func award_points(player_index: int, amount: int) -> void:
	if player_index < 0 or player_index >= players.size():
		return
	players[player_index].progress.points += amount
	EventBus.points_awarded.emit(player_index, amount)
	check_win(player_index)

# Win by: points, beating the Spirit Lord, or Balance.ELITE_WINS_TO_WIN
# Haunted Four wins in a row on the Spectral Trail. In "No pts" mode only the
# Spirit Lord wins — the Haunted Four streak just unlocks his fight.
func check_win(player_index: int) -> void:
	if winner_index != -1:
		return
	var p: PlayerData = players[player_index]
	var points_win: bool = p.progress.points >= win_threshold and not infinite_points
	var trail_win: bool = p.progress.elite_wins >= Balance.ELITE_WINS_TO_WIN and not infinite_points
	if points_win or trail_win or p.progress.champion_defeated:
		winner_index = player_index
		EventBus.game_won.emit(player_index)

func reset() -> void:
	players.clear()
	current_player_index = 0
	turn_count = 0
	winner_index = -1
	dev_mode = false

# ── save / load ───────────────────────────────────────────────────────────────

func to_dict() -> Dictionary:
	var ps: Array = []
	for p in players:
		ps.append(p.to_dict())
	return {
		"players": ps, "current": current_player_index, "turn": turn_count,
		"win_threshold": win_threshold, "infinite": infinite_points,
		"map": active_map, "dev": dev_mode, "battle_size": battle_size, "trail_badges": trail_badges,
	}

func from_dict(d: Dictionary) -> void:
	reset()
	for pd in d.get("players", []):
		players.append(PlayerData.from_dict(pd))
	current_player_index = d.get("current", 0)
	turn_count = d.get("turn", 0)
	win_threshold = d.get("win_threshold", 30)
	infinite_points = d.get("infinite", false)
	active_map = d.get("map", 1)
	battle_size = int(d.get("battle_size", 3))
	trail_badges = int(d.get("trail_badges", Balance.FLY_BADGES))   # older saves: the old fixed 3
	dev_mode = d.get("dev", false)
