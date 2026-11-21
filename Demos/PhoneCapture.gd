extends Node
## DEV TEST ONLY: puts the game into one situation and saves what a phone would
## be shown (Remote's view) as JSON in user://phone_views/<state>.json, so the
## real phone page can be screenshotted with it. Usage: -- state=<name>
##   turn, offturn (main/team/mon/hand pages), event, catch, select, battle,
##   vote, bonus, minigame

const PHONE := "PHONE1"
var _state := "turn"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("state="):
			_state = a.substr(6)
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir() + "/phone_views")
	GameState.reset()
	GameState.active_map = 3
	# which seat the phone plays: off-turn views need someone else to go first,
	# the vote needs the phone to be out of the fight
	var phone_seat := 0
	var picks := [["Ivy", "Mossprig", Color("5ad26a")], ["Brooke", "Puddleboo", Color("4aa3df")], ["Zap", "Zapkin", Color("ffd24d")]]
	for i in picks.size():
		var p := PlayerData.new()
		p.player_name = picks[i][0]
		p.trainer_key = ["akari", "adaman", "acerola"][i]
		p.color = picks[i][2]
		p.is_cpu = i != phone_seat
		p.team.append(SpiritsData.get_spirit(picks[i][1]))
		for k in 3:
			p.team.append(SpiritsData.random_spirit(1))
		p.inventory.hand = ["spirit_lantern", "spirit_shield", "battle_cry", "haste"]
		p.inventory.gold = 35
		p.progress.points = [7, 5, 4][i]
		if i == phone_seat:
			p.remote_id = PHONE
		GameState.players.append(p)
	Remote.phones[PHONE] = {"name": picks[phone_seat][0], "online": true}
	var board: Node = load("res://Scenes/Board/Board.tscn").instantiate()
	get_tree().root.add_child.call_deferred(board)
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().current_scene = board
	await _wait(0.3)
	# ONE play-through: every phone screen in a row
	_save("1_your_turn")
	GameState.current_player_index = 1   # someone else's turn → the idle menu pages
	for page in [{"p": "main"}, {"p": "team"}, {"p": "mon", "i": 0}, {"p": "hand"}]:
		Remote._page[PHONE] = page
		_save("2_off_turn_" + String(page["p"]))
	Remote._page[PHONE] = {"p": "main"}
	GameState.current_player_index = 0
	EventBus.tile_action.emit(0, &"EVENT")
	await _wait(5.0)
	_save("3_event")
	var ev := _find(get_tree().root, "SpiritEventWindow.gd")
	if ev:
		ev.closed.emit()
	await _wait(1.0)
	BonusReward.run(0, GameState.players[0].team[0])
	await _wait(0.8)
	_save("4_bonus_reward")
	var bw := _find(get_tree().root, "BonusRewardWindow.gd")
	if bw:
		bw.chose_ability.emit("")
		bw.chose_stat.emit("atk")
	await _wait(0.5)
	var tc := _find(get_tree().root, "TileController.gd")
	var roster := [SpiritsData.random_spirit(1), SpiritsData.random_spirit(2), SpiritsData.random_spirit(1)]
	tc._npc_battle(0, roster, "Ashen Warden", ["acetrainer"], "gym")
	await _wait(1.2)
	_save("5_team_select")
	var sel := _find(get_tree().root, "BattleTeamSelect.gd")
	if sel:
		sel._cancel()
	await _wait(0.5)
	# a second phone sits out the fight, to show the spectator vote
	GameState.players[2].remote_id = "PHONE2"
	Remote.phones["PHONE2"] = {"name": "Zap", "online": true}
	var battle := _find(get_tree().root, "BattleScreen.gd")
	var p0: PlayerData = GameState.players[0]
	var setup := BattleSetup.vs_npc(0, p0.team.slice(0, 3), ["spirit_shield", "battle_cry"], [SpiritsData.random_spirit(2)], "Wild battle", [], "wild")
	UIManager.hold_pause()
	BattleSetup.run(battle, setup, 0)
	await _wait(1.5)
	_save("6_vs_banner")
	await _wait(4.5)
	_save("7_battle")
	_save("8_spectator_vote", "PHONE2")
	get_tree().quit()

func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout

func _save(name: String, phone := PHONE) -> void:
	var v: Dictionary = Remote._build_view(phone)
	v.erase("_actions")
	var f := FileAccess.open(OS.get_user_data_dir() + "/phone_views/%s.json" % name, FileAccess.WRITE)
	f.store_string(JSON.stringify(v))
	print("SAVED ", name, " screen=", v.get("screen", "?"), " title=", String(v.get("title", "")).left(50))

func _find(n: Node, script_end: String) -> Node:
	if n.get_script() and String(n.get_script().resource_path).ends_with(script_end):
		if script_end != "BattleScreen.gd" or (n.get_parent().get_script() and String(n.get_parent().get_script().resource_path).ends_with("TileController.gd")):
			return n
	for c in n.get_children():
		var f := _find(c, script_end)
		if f:
			return f
	return null
