extends CanvasLayer
## Runs wild-ghost encounters. A wild ghost is never fought: the catch window
## runs the Lantern dice roll. Only spirits that pick a fight in an event get a
## real battle (then, unless they belong to a trainer, a catch roll).
## Listens for EventBus.wild_encounter_started; emits encounter_finished.

var _hunt: Control
var _select: Control
var _battle: Control

func _ready() -> void:
	layer = 12
	process_mode = Node.PROCESS_MODE_ALWAYS   # the board pauses meanwhile
	_hunt = preload("res://Scenes/UI/CatchWindow.gd").new()
	_select = preload("res://Scenes/UI/BattleTeamSelect.gd").new()
	_battle = preload("res://Scenes/UI/Battle/BattleScreen.gd").new()
	for w in [_hunt, _select, _battle]:
		add_child(w)
		w.set_click_through(true)
	EventBus.wild_encounter_started.connect(_on_started)

func _on_started(idx: int, spirit: Dictionary) -> void:
	UIManager.hold_pause()
	await get_tree().process_frame   # let the board reach its await first
	if spirit.get("_event_fight", false) or spirit.get("_no_catch", false):
		# an event spirit that wants a fight
		if await _fight(idx, spirit) and not spirit.get("_no_catch", false):
			await _hunt_it(idx, spirit, true)
	else:
		await _hunt_it(idx, spirit, false)
	UIManager.close()
	UIManager.release_pause()
	EventBus.encounter_finished.emit()

func _hunt_it(idx: int, spirit: Dictionary, spooked: bool) -> void:
	_hunt.present(idx, spirit, spooked)
	UIManager.open(_hunt)
	await _hunt.done

# Team + card select (humans) and a battle vs one event spirit. True on a win.
func _fight(idx: int, spirit: Dictionary) -> bool:
	var p: PlayerData = GameState.players[idx]
	var pick := await BattleSetup.pick_for(_select, idx, "vs %s" % spirit.get("name", "?"), [spirit])
	if pick.is_empty():
		return false
	var setup := BattleSetup.vs_npc(idx, pick["team"], pick["cards"], [spirit], "%s attacks!" % spirit.get("name", "?"), [], "wild")
	var won := await BattleSetup.run(_battle, setup, idx)
	EventBus.log_entry.emit(idx, "%s %s a wild battle vs %s!" % [p.player_name, "won" if won else "lost",
		spirit.get("name", "?")], "#9fff9f" if won else "#ff9f9f")
	return won
