extends Node
## Autoloaded. Saves the match at the START of every turn (a calm moment: no
## token mid-move, no window open) and resumes it from the main menu.
##
## The file holds GameState (players, cards, badges…) plus the board's own
## state (token positions, visited towns, the play timer), which the board
## hands over through `board_state_provider`.

const SAVE_PATH := "user://savegame.dat"
const VERSION := 2

var board_state_provider: Callable = Callable()   # set by Board: returns a Dictionary
var pending_board_state: Dictionary = {}          # filled by load_game() for the next Board

func _ready() -> void:
	EventBus.turn_started.connect(_on_turn_started)
	EventBus.game_won.connect(_on_game_won)

func _on_turn_started(_idx: int) -> void:
	save_game.call_deferred()

func _on_game_won(_idx: int) -> void:
	delete_save()

func save_game() -> void:
	if GameState.players.is_empty() or GameState.winner_index != -1:
		return
	var data := {
		"version": VERSION,
		"game": GameState.to_dict(),
		"board": board_state_provider.call() if board_state_provider.is_valid() else {},
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_var(data)

func has_save() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var data = _read()
	return data is Dictionary and int(data.get("version", 0)) == VERSION

# Load into GameState and park the board state for the Board scene to pick up.
func load_game() -> bool:
	var data = _read()
	if not (data is Dictionary) or int(data.get("version", 0)) != VERSION:
		return false
	GameState.from_dict(data.get("game", {}))
	pending_board_state = data.get("board", {})
	return not GameState.players.is_empty()

func take_pending_board_state() -> Dictionary:
	var s := pending_board_state
	pending_board_state = {}
	return s

func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

func _read():
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	return f.get_var() if f else null
