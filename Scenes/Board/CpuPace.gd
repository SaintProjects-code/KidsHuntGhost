extends Node
## CPU turns run on a faster game clock (Engine.time_scale = CPU_SPEED): the
## roll, token steps, event / catch / battle timers all hurry along. Back to 1x
## the moment a human is involved — a competition (everyone plays), a battle,
## team pick or trade with a human side, or any window a human owns — and
## while someone is looking around in View Map. The Board adds this node.

const CPU_SPEED := 2.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # windows pause the board; this must keep checking

func _process(_delta: float) -> void:
	var want := CPU_SPEED if _cpu_only() else 1.0
	if Engine.time_scale != want:
		Engine.time_scale = want

func _exit_tree() -> void:
	Engine.time_scale = 1.0

func _cpu_only() -> bool:
	var cur: int = GameState.current_player_index
	if cur < 0 or cur >= GameState.players.size() or not GameState.players[cur].is_cpu or GameState.winner_index >= 0:
		return false
	var pm: Node = Remote._pause_menu()
	if pm and pm.in_view_mode():
		return false
	for w in Remote._find_all(get_tree().root, func(n): return n is MenuWindow and n.is_visible_in_tree()):
		var path := String(w.get_script().resource_path) if w.get_script() else ""
		if path.ends_with("CompetitionWindow.gd") or path.ends_with("TradeWindow.gd"):
			return false
		var owners: Array = w.remote_owners() if w.has_method("remote_owners") else [Remote._owner_of(w)]
		for o in owners:
			if o is int and o >= 0 and o < GameState.players.size() and not GameState.players[o].is_cpu:
				return false
	return true
