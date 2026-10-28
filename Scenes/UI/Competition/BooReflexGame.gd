extends CompGame
## 👻 Boo Reflex — a reaction duel. Everyone waits in the dark; when the ghost
## jumps out shouting BOO!, press your ACTION key first. Press too early and
## you're out of that round. 3 rounds: most round wins, then the fastest total
## reaction. SPD = quicker CPU reflexes and a longer early-press grace.

const ROUNDS := 3
const RESULT_TIME := 1.4

var _round := 0
var _state := "wait"        # wait / boo / result
var _state_t := 0.0
var _boo_at := 0.0

func _init_game() -> void:
	record_key = "boo_reflex"
	record_lower_better = true   # fastest single reaction
	layout = Layout.COLUMNS
	how_to = "Wait for the BOO!… then press your key FIRST. Too early and you sit out the round!"
	custom_minimum_size = Vector2(640, 440)
	for lane in lanes:
		lane.merge({"wins": 0, "react": [], "pressed": -1.0, "early": false,
			"cpu_react": 0.0, "spd": int(lane["spirit"].get("spd", 2))})
	_new_round()

func _new_round() -> void:
	_state = "wait"
	_state_t = 0.0
	_boo_at = randf_range(1.4, 3.6)
	for lane in lanes:
		lane["pressed"] = -1.0
		lane["early"] = false
		lane["cpu_react"] = randf_range(0.22, 0.5) - lane["spd"] * 0.02

func _tick(delta: float) -> void:
	_state_t += delta
	match _state:
		"wait":
			if _state_t >= _boo_at:
				_state = "boo"
				_state_t = 0.0
				Sfx.play("boo")
		"boo":
			for lane in lanes:
				if not lane["human"] and lane["pressed"] < 0.0 and _state_t >= lane["cpu_react"]:
					_press(lane)
			var waiting := lanes.filter(func(l): return l["pressed"] < 0.0 and not l["early"])
			if waiting.is_empty() or _state_t > 2.5:
				_score_round()
		"result":
			if _state_t >= RESULT_TIME:
				_round += 1
				if _round >= ROUNDS:
					var best := 99.0
					for lane in lanes:
						for v in lane["react"]:
							best = minf(best, v)
					result_value = best if best < 99.0 else 0.0
					finish()
				else:
					_new_round()

func _press(lane: Dictionary) -> void:
	if lane["pressed"] >= 0.0 or lane["early"]:
		return
	if _state == "wait":
		lane["early"] = true
		Sfx.play("error")
	elif _state == "boo":
		lane["pressed"] = _state_t
		lane["react"].append(_state_t)

func _score_round() -> void:
	var best: Dictionary = {}
	for lane in lanes:
		if lane["pressed"] >= 0.0 and (best.is_empty() or lane["pressed"] < best["pressed"]):
			best = lane
	if not best.is_empty():
		best["wins"] += 1
		Sfx.play("pop")
	_state = "result"
	_state_t = 0.0

func _on_action(lane: Dictionary, action: String) -> void:
	if action == "action":
		_press(lane)

func _total_react(lane: Dictionary) -> float:
	var sum := 0.0
	for v in lane["react"]:
		sum += v
	return sum + (ROUNDS - lane["react"].size()) * 3.0   # a missed round costs 3s

func ranks() -> Array:
	var sorted := lanes.duplicate()
	sorted.sort_custom(func(a, b):
		if a["wins"] != b["wins"]:
			return a["wins"] > b["wins"]
		return _total_react(a) < _total_react(b))
	return sorted.map(func(l): return l["idx"])

func result_text() -> String:
	var best := _lane_by_idx(ranks()[0])
	return "👻 %s has the fastest reflexes! (%d wins)" % [best["name"], best["wins"]]

func _draw_game() -> void:
	var boo := _state == "boo" or (_state == "result" and _state_t < 0.6)
	for i in lanes.size():
		var lane: Dictionary = lanes[i]
		var r := lane_rect(i)
		lane_card(lane, r, Color("05040c") if not boo else Color("3a0d4a"), Color("120a24") if not boo else Color("7a1a3a"))
		var c := r.get_center() + Vector2(0, 30)
		var tint := Color(1, 1, 1, 0.35) if lane["early"] else Color.WHITE
		shadow(c + Vector2(0, 30), 22, 6)
		draw_spirit(lane, c, 24.0, tint)
		if boo and lane["pressed"] < 0.0 and not lane["early"]:
			text(Vector2(r.position.x, c.y - 70), "BOO!", 40, Color(1, 0.9, 0.3), r.size.x, 8)
		if lane["early"]:
			text(Vector2(r.position.x, c.y - 60), "Too early!", 20, Color(1, 0.4, 0.4), r.size.x, 5)
		elif lane["pressed"] >= 0.0:
			text(Vector2(r.position.x, c.y - 60), "%.2fs" % lane["pressed"], 22, Color(0.6, 1, 0.7), r.size.x, 5)
		for k in lane["wins"]:
			draw_circle(Vector2(r.position.x + 20 + k * 18, r.end.y - 20), 7, UIKit.GOLD)
		nameplate(lane, r.position + Vector2(8, 30), "round %d/%d" % [mini(_round + 1, ROUNDS), ROUNDS])
	if _state == "wait" and running:
		text(Vector2(0, size.y - 14), "…wait for it…", 16, Color(1, 1, 1, 0.6), size.x, 3)
