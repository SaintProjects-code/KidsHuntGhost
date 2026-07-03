extends MenuWindow
## Debug helpers for testing. present(player_index); emits closed().

signal closed()

var _player_index: int = -1

func _ready() -> void:
	var col := _init_window(360, 320)
	col.add_child(_title_label("⚡ Dev", 26))
	col.add_child(_button("+5 points (you)", func(): GameState.award_points(_player_index, 5)))
	col.add_child(_button("+50 gold", func(): GameState.players[_player_index].inventory.gold += 50))
	col.add_child(_button("+3 Spirit Balls", func(): GameState.players[_player_index].inventory.balls[&"spirit_ball"] += 3))
	col.add_child(_button("Give all badges", _all_badges))
	col.add_child(_button("Heal team", _heal))
	col.add_child(_button("Close", func(): closed.emit()))
	hide()

func present(player_index: int) -> void:
	_player_index = player_index

func _all_badges() -> void:
	var b = GameState.players[_player_index].progress.badges
	for k in b.keys():
		b[k] = true
	EventBus.badge_earned.emit(_player_index, "DEV")

func _heal() -> void:
	for m in GameState.players[_player_index].team:
		m["current_hp"] = m.get("hp", 0)
