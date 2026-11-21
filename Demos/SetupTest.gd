extends Node
## DEV TEST ONLY: opens the setup screen with 6 player cards.
func _ready() -> void:
	var s: Node = load("res://Scenes/Menu/SetupScreen.tscn").instantiate()
	get_tree().root.add_child.call_deferred(s)
	await get_tree().process_frame
	await get_tree().process_frame
	for i in 4:
		s._on_add_player_pressed()
