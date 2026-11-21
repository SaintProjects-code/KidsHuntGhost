extends Node
## Autoloaded. Whose turn it is and the dice. The board animates the roll and
## moves the token; this only decides the numbers.

# Pause that gives a CPU turn a human's rhythm (a beat before it rolls).
const CPU_ROLL_DELAY := 0.7

# The board can take over a CPU's move BEFORE the roll (flying to a town,
# a Warp Door…). If the callable returns true the move — and the turn — was
# handled and no dice are rolled.
var cpu_turn_override: Callable = Callable()

# Bumped whenever a game starts or the board goes away, so a CPU turn still
# waiting from an OLD game can't wake up inside the next one.
var _generation := 0

func start_game() -> void:
	_generation += 1
	GameState.turn_count = 0
	GameState.current_player_index = 0
	_begin_turn()

# Continue a loaded game: same player, same turn number.
func resume_game() -> void:
	_generation += 1
	_begin_turn()

# The board is leaving (quit to menu): drop any pending CPU turn.
func stop() -> void:
	_generation += 1
	cpu_turn_override = Callable()

func _begin_turn() -> void:
	var idx := GameState.current_player_index
	var gen := _generation
	EventBus.turn_started.emit(idx)
	# stuck (Quicksand, a Hex…): sit this turn out
	var p := GameState.current_player()
	if p.skip_turns > 0:
		p.skip_turns -= 1
		EventBus.log_entry.emit(idx, "%s is stuck and skips this turn!" % p.player_name, "#ff9f9f")
		await get_tree().create_timer(1.2).timeout
		if gen == _generation and idx == GameState.current_player_index and GameState.winner_index == -1:
			advance_turn()
		return
	if GameState.current_player().is_cpu:
		await get_tree().create_timer(CPU_ROLL_DELAY).timeout
		if gen != _generation or GameState.winner_index != -1 or idx != GameState.current_player_index:
			return
		if cpu_turn_override.is_valid() and await cpu_turn_override.call(idx):
			return
		roll_dice()

# One die early on, two from Balance.FAST_MODE_TURN, plus card bonuses
# (Twin Dice adds a die, Loaded Die adds +2). Bonuses are used up.
func roll_dice() -> void:
	var p := GameState.current_player()
	var count := 2 if GameState.turn_count >= Balance.FAST_MODE_TURN else 1
	if p.extra_die:
		count += 1
		p.extra_die = false
	var faces: Array = []
	var total := 0
	for i in count:
		var f := randi_range(1, 6)
		faces.append(f)
		total += f
	total += p.roll_bonus
	p.roll_bonus = 0
	EventBus.dice_rolled.emit(total, faces)

func advance_turn() -> void:
	var idx := GameState.current_player_index
	EventBus.turn_ended.emit(idx)
	GameState.current_player_index = (idx + 1) % GameState.players.size()
	GameState.turn_count += 1
	GameState.tick_weather()
	_begin_turn()
