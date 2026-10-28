extends Control
## Title screen: Start → (Continue | Adventure | Multiplayer → Local/Online).
## Continue only shows when a saved game exists.

const DEV_TRAINERS := [
	{"name": "Ember", "starter": "Cinderwisp", "color": Color("ff7a3a"), "portrait": "alain"},
	{"name": "Brooke", "starter": "Puddleboo", "color": Color("4aa3df"), "portrait": "adaman"},
	{"name": "Ivy", "starter": "Mossprig", "color": Color("5ad26a"), "portrait": "akari"},
]

func _ready() -> void:
	MusicManager.play_menu()
	$MultiplayerMenuButton.hide()
	$StartingScreenButton.show()
	$MainMenuButton.hide()
	if SaveManager.has_save():
		var cont := Button.new()
		cont.text = "▶ Continue"
		cont.focus_mode = Control.FOCUS_NONE
		cont.pressed.connect(_on_continue_pressed)
		$MainMenuButton.add_child(cont)
		$MainMenuButton.move_child(cont, 0)

func _on_start_game_pressed() -> void:
	Sfx.play("click")
	$StartingScreenButton.hide()
	$MainMenuButton.show()

func _on_adventure_mode_pressed() -> void:
	$MultiplayerMenuButton.hide()

func _on_multiplayer_pressed() -> void:
	$MultiplayerMenuButton.visible = not $MultiplayerMenuButton.visible
	$StartingScreenButton.hide()
	$MainMenuButton.hide()

func _on_setting_pressed() -> void:
	pass   # settings live in the setup screen and the in-game pause menu

func _on_online_pressed() -> void:
	_start_setup()

func _on_local_pressed() -> void:
	_start_setup()

func _start_setup() -> void:
	get_tree().change_scene_to_file("res://Scenes/Menu/SetupScreen.tscn")

func _on_continue_pressed() -> void:
	if SaveManager.load_game():
		get_tree().change_scene_to_file("res://Scenes/Board/Board.tscn")
	else:
		Sfx.play("error")

# DEV shortcut: skips setup — 3 players with full teams, plenty of jars, gold
# and cards, and dev_mode on (the only thing that shows the in-game DEV button).
func _on_dev_pressed() -> void:
	GameState.reset()
	GameState.dev_mode = true
	for t in DEV_TRAINERS:
		var p := PlayerData.new()
		p.player_name = t["name"]
		p.trainer_key = t["portrait"]
		p.color = t["color"]
		p.team.append(SpiritsData.get_spirit(t["starter"]))
		for i in 3:
			p.team.append(SpiritsData.random_spirit(1))
		for i in 2:
			p.team.append(SpiritsData.random_spirit(2))
		p.inventory.add_jars(&"ghost_jar", 5)
		p.inventory.gold = 200
		p.inventory.hand = ["ecto_patch", "spirit_shield", "glow_tonic", "warp_door", "boo"]
		GameState.players.append(p)
	get_tree().change_scene_to_file("res://Scenes/Board/Board.tscn")
