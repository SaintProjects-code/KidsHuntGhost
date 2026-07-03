extends MenuWindow
## A quick contest: every player's lead spirit is scored; the strongest wins
## points. present(triggering_player_index); emits closed().

signal closed()

const WINNER_POINTS := 2

var _title: Label
var _body: VBoxContainer

func _ready() -> void:
	var col := _init_window(460, 340)
	_title = _title_label("🏅 Competition!", 26)
	col.add_child(_title)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 6)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_body)
	col.add_child(_button("OK", func(): closed.emit()))
	hide()

func present(_player_index: int) -> void:
	for c in _body.get_children():
		c.queue_free()
	# Score each player's lead spirit.
	var best_score: int = -1
	var best_player: int = -1
	var rows: Array = []
	for i in GameState.players.size():
		var p: PlayerData = GameState.players[i]
		var score: int = 0
		var lead_name := "—"
		if not p.team.is_empty():
			var lead: Dictionary = p.team[0]
			score = lead.get("atk", 0) + lead.get("spd", 0) + int(lead.get("stars", 0)) * 2 + int(lead.get("hp", 0) / 30)
			lead_name = lead.get("name", "?")
		rows.append({"name": p.player_name, "lead": lead_name, "score": score})
		if score > best_score:
			best_score = score
			best_player = i
	for r in rows:
		var l := Label.new()
		l.text = "%s — %s  (power %d)" % [r["name"], r["lead"], r["score"]]
		_body.add_child(l)
	if best_player != -1:
		var winner := Label.new()
		winner.add_theme_color_override("font_color", Color("9fff9f"))
		winner.text = "Winner: %s  (+%d points!)" % [GameState.players[best_player].player_name, WINNER_POINTS]
		_body.add_child(winner)
		GameState.award_points(best_player, WINNER_POINTS)
