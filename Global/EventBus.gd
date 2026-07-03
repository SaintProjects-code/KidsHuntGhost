extends Node

# Turn flow
signal turn_started(player_index: int)
signal turn_ended(player_index: int)
signal dice_rolled(result: int)
signal player_moved(player_index: int, space_index: int)
signal space_landed(player_index: int, space_type: StringName)

# Spirit & catching
signal catch_attempted(player_index: int, spirit: Dictionary, ball: StringName)
signal catch_succeeded(player_index: int, spirit: Dictionary)
signal catch_failed(player_index: int, spirit: Dictionary)

# Wild encounter flow (PKMN tile): the board emits _started and waits for _finished
signal wild_encounter_started(player_index: int, spirit: Dictionary)
signal encounter_finished()

# Non-PKMN tiles (EVENT / ITEM / COMPETITION / CITY): board emits tile_action and
# waits for tile_resolved (TileController runs the window).
signal tile_action(player_index: int, kind: StringName)
signal tile_resolved()

# Star & progression
signal star_awarded(player_index: int, spirit: Dictionary)
signal spirit_evolved(player_index: int, spirit: Dictionary)

# Battle
signal battle_started(attacker_index: int, defender_index: int)
signal battle_ended(winner_index: int, loser_index: int)

# Progress
signal badge_earned(player_index: int, gym_name: String)
signal points_awarded(player_index: int, amount: int)
signal game_won(player_index: int)

# Free-form entry for the game log (LOG button). color is a hex string.
signal log_entry(player_index: int, text: String, color: String)
