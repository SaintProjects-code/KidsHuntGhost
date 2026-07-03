extends Node

const BALL_BONUS := {
	&"spirit_ball": 85,    # the standard ball
	&"master_ball": 100,   # never fails (handled below)
}
# With no badges these give 80% / 70% / 60% by stage (badges add +2 each).
const STAGE_MULT := { 1: 0.95, 2: 0.83, 3: 0.71 }

func _ready() -> void:
	EventBus.catch_attempted.connect(_on_catch_attempted)

func _on_catch_attempted(player_idx: int, spirit: Dictionary, ball: StringName) -> void:
	var p := GameState.players[player_idx]
	var badge_bonus := p.progress.badge_count() * 2
	var base: int = BALL_BONUS.get(ball, 0) + badge_bonus
	var stage: int = spirit.get("stage", 1)
	var chance := mini(100, int(float(base) * float(STAGE_MULT.get(stage, 1.0))))
	if ball == &"master_ball" or randi_range(1, 100) <= chance:
		_succeed(player_idx, spirit)
	else:
		EventBus.emit_signal("catch_failed", player_idx, spirit)

const TEAM_MAX := 6

func _succeed(player_idx: int, spirit: Dictionary) -> void:
	var p := GameState.players[player_idx]
	spirit["current_hp"] = spirit["hp"]
	spirit["stars"] = 0
	# Full team (6) → the catch is stored in the PC (withdraw at any town).
	if p.team.size() < TEAM_MAX:
		p.team.append(spirit)
	else:
		p.pc.append(spirit)
	# SpiritsProgressionSystem subscribes and handles duplicates / stars
	EventBus.emit_signal("catch_succeeded", player_idx, spirit)
	GameState.award_points(player_idx, 1)
