extends Node
## Autoloaded. Game-wide signals so systems and windows never reference each
## other directly. Flows that "hand off and wait" come in pairs (_started /
## _finished): the board emits the first and awaits the second.

# Turn flow
signal turn_started(player_index: int)
signal turn_ended(player_index: int)
signal dice_rolled(result: int, faces: Array)
signal space_landed(player_index: int, space_type: StringName)

# Capture
signal catch_attempted(player_index: int, spirit: Dictionary, lanterns: Array)
signal catch_succeeded(player_index: int, spirit: Dictionary)
signal catch_failed(player_index: int, spirit: Dictionary)

# Wild encounter flow (ghost tiles)
signal wild_encounter_started(player_index: int, spirit: Dictionary)
signal encounter_finished()

# Every other tile (EVENT / ITEM / COMPETITION / a town / the trail)
signal tile_action(player_index: int, kind: StringName)
signal tile_resolved()

# ⚔ PvP clashes. mode: "battle" | "trade".
signal pvp_started(a: int, b: int, mode: String)
signal pvp_finished()

# Cards
signal hand_changed(player_index: int)
signal card_played(player_index: int, key: String)
signal warp_requested(player_index: int, city: String)   # Warp Door card

# Progress
signal star_awarded(player_index: int, spirit: Dictionary)
signal spirit_evolved(player_index: int, spirit: Dictionary)
signal trail_entered(player_index: int)    # town → Spectral Trail teleport
signal trail_failed(player_index: int)     # lost to a warden → back to Cobweb City
signal badge_earned(player_index: int, gym_name: String)
signal points_awarded(player_index: int, amount: int)
signal game_won(player_index: int)
signal weather_changed(kind: String)   # "" = clear skies

# Free-form entry for the game log (LOG button). color is a hex string.
signal log_entry(player_index: int, text: String, color: String)

# DEV tools (DevWindow only): step on a tile, or run a no-reward battle.
signal dev_tile_requested(kind: StringName)
signal dev_battle_requested(kind: StringName, a: int, b: int)
