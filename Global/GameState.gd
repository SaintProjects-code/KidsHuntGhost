extends Node

var players: Array[PlayerData] = []
var current_player_index: int = 0
var turn_count: int = 0 
var win_threshold: int = 30
var active_map: int = 1
var phase: StringName = &'menu'
var winner_index: int = -1   # set once someone wins
var dev_mode: bool = false   # true only for games started from the menu's DEV button

func current_player() -> PlayerData:
	return players[current_player_index]

# Award points and check for a win. Returns true if this win ends the game.
func award_points(player_index: int, amount: int) -> void:
	if player_index < 0 or player_index >= players.size():
		return
	players[player_index].progress.points += amount
	EventBus.points_awarded.emit(player_index, amount)
	_check_win(player_index)

func _check_win(player_index: int) -> void:
	if winner_index != -1:
		return
	var p: PlayerData = players[player_index]
	if p.progress.points >= win_threshold or p.progress.gary_defeated:
		winner_index = player_index
		EventBus.game_won.emit(player_index)

func reset() -> void:
	players.clear()
	current_player_index = 0
	turn_count = 0
	winner_index = -1
	phase = &'menu'
	dev_mode = false
