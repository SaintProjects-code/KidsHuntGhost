class_name TerrainManager

var active_terrain: StringName = &""
var rounds_left: int = 0

const BOOSTED_TYPES := {
	&"Grassy":   ["Grass"],
	&"Electric": ["Electric"],
	&"Psychic":  ["Psychic"],
}

func set_terrain(terrain: StringName) -> void:
	active_terrain = terrain
	rounds_left = 4

func tick_round() -> void:
	if rounds_left > 0:
		rounds_left -= 1
		if rounds_left == 0:
			active_terrain = &""

func get_multiplier(spirit_type: String) -> float:
	if active_terrain == &"":
		return 1.0
	return 1.25 if spirit_type in BOOSTED_TYPES.get(active_terrain, []) else 1.0

func blocks_sleep() -> bool:
	return active_terrain == &"Electric"
