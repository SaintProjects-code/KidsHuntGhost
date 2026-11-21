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

# ── 3D (3D maps) ──────────────────────────────────────────────────────────────
func _build_3d(v) -> void:
	var gap := 4.6
	v.sky(Color("06050c"), 0.12, 0.15)
	v.aim(Vector3(0, 6, 10 + lanes.size() * 2.3), Vector3(0, 1.5, 0))
	v.box(Vector3(lanes.size() * gap + 4, 0.4, 7), Color("2a2040"), Vector3(0, -0.2, 0.5))
	v.box(Vector3(3, 2, 2), Color("5a3a20"), Vector3(0, 1, -2.5))
	for i in lanes.size():
		var lane: Dictionary = lanes[i]
		lane["n3"] = v.spirit(lane["tex"], lane["color"], Vector3(v.lane_x(i, lanes.size(), gap), 0, 2), 0.04)
		lane["j3"] = 0.0
		lane["pop3"] = false
		var l := lane
		v.tag(lane["n3"], func(): return "%s %s  %s" % [l["name"], key_hint(l), "★".repeat(l["wins"])], lane["color"].lightened(0.2), 2.8, 15)
	_boo3 = v.spirit(SpiritsData.sprite_tex("Wispy", "front"), Color(0, 0, 0, 0), Vector3(0, 0, -2.5), 0.12)
	_boo3.scale = Vector3.ONE * 0.01
	_spot3 = v.lamp(Color.WHITE, Vector3(0, 6, 3), 0.0, 20)

var _boo3: Node3D
var _spot3: OmniLight3D
var _boo_popped := false

func _update_3d(v, delta: float) -> void:
	var out := _state == "boo" or _state == "result"
	_boo3.scale = Vector3.ONE * (minf(1.0, _boo3.scale.x + delta * 7.0) if out else 0.01)
	_boo3.position.y = minf(1.8, _boo3.position.y + delta * 9.0) if out else 0.0
	_spot3.light_energy = 3.0 if out else 0.0
	if _state == "boo" and not _boo_popped:
		_boo_popped = true
		v.pop(_boo3, "BOO!", Color.WHITE, 5.5, 1.2, 48)
	if _state == "wait":
		_boo_popped = false
	var best := {}
	for lane in lanes:
		if lane["pressed"] >= 0.0 and (best.is_empty() or lane["pressed"] < best["pressed"]):
			best = lane
	for lane in lanes:
		var n: Node3D = lane["n3"]
		var jumped: bool = lane["pressed"] >= 0.0
		lane["j3"] = minf(1.0, lane["j3"] + delta * 6.0) if jumped else maxf(0.0, lane["j3"] - delta * 3.0)
		n.position.y = sin(lane["j3"] * PI) * 1.6
		v.sprite_of(n).modulate = Color(1.6, 0.5, 0.5) if lane["early"] else Color.WHITE
		if _state == "wait":
			lane["pop3"] = false
		elif not lane["pop3"] and (jumped or lane["early"]):
			lane["pop3"] = true
			if lane["early"]:
				v.pop(n, "Too early!", Color("ff6a6a"), 3.0)
			else:
				v.pop(n, "%d ms" % int(lane["pressed"] * 1000.0), Color.WHITE, 3.0)
		if _state == "result" and lane == best and not lane.get("first3", false):
			lane["first3"] = true
			v.pop(n, "FIRST!", Color("ffd24d"), 3.6, 1.3, 28)
		if _state == "wait":
			lane["first3"] = false
