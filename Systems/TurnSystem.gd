extends Node

# Pauses that give a CPU turn the same unhurried rhythm as a human's (who takes a
# beat to press Roll, then End Turn).
const CPU_ROLL_DELAY := 0.7   # after its turn starts, before it rolls

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
