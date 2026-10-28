extends Node

# Pauses that give a CPU turn the same unhurried rhythm as a human's (who takes a
# beat to press Roll, then End Turn).
const CPU_ROLL_DELAY := 0.7   # after its turn starts, before it rolls

# The board can take over a CPU's move BEFORE the roll (e.g. ✈ flying to a
# city with 3+ badges). If the callable returns true, the move was handled
# (including ending the turn) and no dice are rolled.
var cpu_turn_override: Callable = Callable()

func start_game() -> void:
	GameState.turn_count = 0
	GameState.current_player_index = 0
	_begin_turn()

func _begin_turn() -> void:
	var idx := GameState.current_player_index
	GameState.phase = &"rolling"
	EventBus.emit_signal("turn_started", idx)
	if GameState.current_player().is_cpu:
		await get_tree().create_timer(CPU_ROLL_DELAY).timeout
		if GameState.winner_index != -1:
			return
		if cpu_turn_override.is_valid() and await cpu_turn_override.call(idx):
			return
		roll_dice()

func roll_dice() -> void:
	var fast_mode := GameState.turn_count >= 24
	var result := randi_range(1, 6)
	if fast_mode:
		result += randi_range(1, 6)
	EventBus.emit_signal("dice_rolled", result)

func advance_turn() -> void:
	var idx := GameState.current_player_index
	EventBus.emit_signal("turn_ended", idx)
	GameState.current_player_index = (idx + 1) % GameState.players.size()
	GameState.turn_count += 1
	_begin_turn()
