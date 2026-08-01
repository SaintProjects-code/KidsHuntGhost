extends Control

func _ready() -> void:
	MusicManager.play_menu()
	# Sub-menus start hidden; the three main buttons reveal them.
	$MultiplayerMenuButton.hide()
	$StartingScreenButton.show()

	$MainMenuButton.hide()

func _on_adventure_mode_pressed() -> void:
	# Toggle the Start button, hide the other sub-menu.
	$MultiplayerMenuButton.hide()

func _on_multiplayer_pressed() -> void:
	# Toggle the Online/Local sub-menu, hide the other.
	$MultiplayerMenuButton.visible = not $MultiplayerMenuButton.visible
	$StartingScreenButton.hide()
	$MainMenuButton.hide()

func _on_setting_pressed() -> void:
	# Settings screen not built yet — placeholder.
	pass

func _on_online_pressed() -> void:
	_start_adventure()

func _on_local_pressed() -> void:
	_start_adventure()

func _on_start_game_pressed() -> void:
	$StartingScreenButton.hide()
	$MainMenuButton.show()
	

func _start_adventure() -> void:
	get_tree().change_scene_to_file("res://Scenes/Menu/SetupScreen.tscn")

# ---------------- DEV shortcut ----------------
# Skips setup entirely: Map 1, 3 loaded players, and dev_mode on (which is the
# only thing that shows the in-game DEV button — normal games never see it).

const DEV_TRAINERS := [
	{ "name": "Red",  "starter": "Charmander", "color": Color("ff7a3a") },
	{ "name": "Blue", "starter": "Squirtle",   "color": Color("4aa3df") },
	{ "name": "Leaf", "starter": "Bulbasaur",  "color": Color("5ad26a") },
]

func _on_dev_pressed() -> void:
	GameState.reset()
	GameState.dev_mode = true
	GameState.active_map = 1
	for t in DEV_TRAINERS:
		var p := PlayerData.new()
		p.player_name = t["name"]
		p.trainer_key = String(t["name"]).to_lower()
		p.color = t["color"]
		# Full team: starter up front, then random spirits to fill all 6 slots.
		p.team.append(SpiritsData.get_spirit(t["starter"]))
		for i in 3:
			p.team.append(SpiritsData.random_spirit(1))
		for i in 2:
			p.team.append(SpiritsData.random_spirit(2))
		# Full bag: plenty of balls and gold, and stacked heals (bag rules:
		# 7 kinds max, each stacking to 5).
		p.inventory.balls[&"spirit_ball"] = 10
		p.inventory.gold = 200
		for item in [
			{"name": "Potion",       "kind": "potion", "amount": 40},
			{"name": "Potion",       "kind": "potion", "amount": 40},
			{"name": "Super Potion", "kind": "potion", "amount": 80},
			{"name": "Super Potion", "kind": "potion", "amount": 80},
			{"name": "Revive",       "kind": "revive"},
			{"name": "Revive",       "kind": "revive"},
			{"name": "Revive",       "kind": "revive"},
		]:
			p.inventory.add_item(item)
		GameState.players.append(p)
	get_tree().change_scene_to_file("res://Scenes/Board/Board.tscn")
