extends Node
## Autoloaded. The match being played: players, whose turn it is, settings.

var players: Array[PlayerData] = []
var current_player_index: int = 0
var turn_count: int = 0
var win_threshold: int = 40          # tested best: points, wardens and Champion all win often
var infinite_points: bool = false   # setup setting: points never win — only the trail does
var active_map: int = 1
var winner_index: int = -1          # set once someone wins
var dev_mode: bool = false          # only for games started from the menu's DEV button

func current_player() -> PlayerData:
	return players[current_player_index]

# Award points and check for a win.
func award_points(player_index: int, amount: int) -> void:
	if player_index < 0 or player_index >= players.size():
		return
	players[player_index].progress.points += amount
	EventBus.points_awarded.emit(player_index, amount)
	check_win(player_index)

# Win by: points (unless infinite-points mode), beating the Champion, or
# Balance.ELITE_WINS_TO_WIN Haunted Four wins in a row on the Spectral Trail.
func check_win(player_index: int) -> void:
	if winner_index != -1:
		return
	var p: PlayerData = players[player_index]
	var points_win: bool = p.progress.points >= win_threshold and not infinite_points
	if points_win or p.progress.champion_defeated or p.progress.elite_wins >= Balance.ELITE_WINS_TO_WIN:
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
		"map": active_map, "dev": dev_mode,
	}

func from_dict(d: Dictionary) -> void:
	reset()
	for pd in d.get("players", []):
		players.append(PlayerData.from_dict(pd))
	current_player_index = d.get("current", 0)
	turn_count = d.get("turn", 0)
	win_threshold = d.get("win_threshold", 40)
	infinite_points = d.get("infinite", false)
	active_map = d.get("map", 1)
	dev_mode = d.get("dev", false)
