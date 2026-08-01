extends Node

const SAVE_PATH := "user://save.tres"

func _ready() -> void:
	EventBus.turn_ended.connect(_on_turn_ended)

func _on_turn_ended(_idx: int) -> void:
	save()

func save() -> void:
	var snapshot := SaveSnapshot.new()
	snapshot.players = GameState.players
	snapshot.current_player_index = GameState.current_player_index
	snapshot.turn_count = GameState.turn_count
	snapshot.win_threshold = GameState.win_threshold
	snapshot.active_map = GameState.active_map
	snapshot.remainder_gyms = GameState.remainder_gyms
	ResourceSaver.save(snapshot, SAVE_PATH)

func has_save() -> bool:
	return ResourceLoader.exists(SAVE_PATH)

func load_save() -> void:
	var snapshot: SaveSnapshot = ResourceLoader.load(SAVE_PATH)
	GameState.players = snapshot.players
	GameState.current_player_index = snapshot.current_player_index
	GameState.turn_count = snapshot.turn_count
	GameState.win_threshold = snapshot.win_threshold
	GameState.active_map = snapshot.active_map
	GameState.remainder_gyms = snapshot.remainder_gyms

func delete_save() -> void:
	DirAccess.remove_absolute(SAVE_PATH)
