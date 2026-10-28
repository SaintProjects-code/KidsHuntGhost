extends CompGame
## The quick stat contests (Haunted Dash, Coffin Lift, Spooky Stare-Down,
## Midnight Marathon), played out in three paced steps:
##   1) ROLL — every player rolls their die (humans press their key or click
##      their column; CPUs roll on their own)
##   2) PERFORM — the spirits do the event: each climbs its column's glowing
##      track as its score (stat × 2 + stars + 🎲) counts up
##   3) RESULTS — placings are revealed from last to first
## `stat` / `label` / `event_name` are set before setup().

const PERFORM_TIME := 3.6
const REVEAL_GAP := 0.75

var stat := "spd"
var label := "Speed"
var event_name := "Contest"
var _phase := "roll"       # roll / perform / results
var _phase_t := 0.0
var _revealed := 0
var _max_score := 1

func _init_game() -> void:
	layout = Layout.COLUMNS
	use_countdown = false
	how_to = "Score = %s × 2 + stars + a die roll. Roll your die, then watch your spirit perform!" % label
	custom_minimum_size = Vector2(640, 440)
	for lane in lanes:
		var s: Dictionary = lane["spirit"]
		var die := DiceView.new(64)
		add_child(die)
		lane.merge({"base": int(s.get(stat, 0)) * 2 + int(s.get("stars", 0)), "roll": 0, "rolled": false,
			"rolling": false, "die": die, "show": 0.0, "place": 0,
			"cpu_wait": randf_range(0.9, 2.2)})

func keys_text(lane: Dictionary) -> String:
	return "press %s to roll your die (or click your column)" % Controls.key_name(lane["slot"], "action")

func _process(delta: float) -> void:
	for i in lanes.size():   # keep each die centred in its column
		var r := lane_rect(i)
		lanes[i]["die"].position = Vector2(r.get_center().x - 32, r.position.y + r.size.y * 0.42)
	super._process(delta)

func _score(lane: Dictionary) -> int:
	return int(lane["base"]) + int(lane["roll"])

func _on_action(lane: Dictionary, action: String) -> void:
	if action == "action" and _phase == "roll":
		_roll(lane)

func _roll(lane: Dictionary) -> void:
	if lane["rolled"] or lane["rolling"]:
		return
	lane["rolling"] = true
	lane["roll"] = randi_range(1, 6)
	await lane["die"].roll(lane["roll"], 0.9)
	lane["rolling"] = false
	lane["rolled"] = true

func _tick(delta: float) -> void:
	_phase_t += delta
	match _phase:
		"roll":
			for lane in lanes:
				if not lane["human"] and not lane["rolled"] and not lane["rolling"]:
					lane["cpu_wait"] -= delta
					if lane["cpu_wait"] <= 0.0:
						_roll(lane)
			if lanes.all(func(l): return l["rolled"]) and _phase_t > 0.5:
				_max_score = 1
				for lane in lanes:
					_max_score = maxi(_max_score, _score(lane))
				_phase = "perform"
				_phase_t = 0.0
				Sfx.play("go")
		"perform":
			var k := clampf(_phase_t / PERFORM_TIME, 0.0, 1.0)
			var eased := 1.0 - pow(1.0 - k, 3.0)
			for lane in lanes:
				var before: int = int(lane["show"])
				lane["show"] = _score(lane) * eased
				if int(lane["show"]) != before and int(lane["show"]) > 0:
					Sfx.play("tick", 0.8 + lane["show"] / float(_max_score), -10.0)
			if _phase_t > PERFORM_TIME + 0.6:
				_phase = "results"
				_phase_t = 0.0
		"results":
			var order := ranks()
			var want := mini(order.size(), int(_phase_t / REVEAL_GAP) + 1)
			while _revealed < want:
				# reveal from LAST place up to the winner
				var place := order.size() - _revealed
				var placed: Dictionary = _lane_by_idx(order[place - 1])
				placed["place"] = place
				_revealed += 1
				Sfx.play("win" if place == 1 else "points", 1.0 if place == 1 else 0.9 + 0.1 * (order.size() - place))
			if _revealed >= order.size() and _phase_t > order.size() * REVEAL_GAP + 0.6:
				finish()

func ranks() -> Array:
	var sorted := lanes.duplicate()
	sorted.sort_custom(func(a, b): return _score(a) > _score(b))
	return sorted.map(func(l): return l["idx"])

func result_text() -> String:
	var best := _lane_by_idx(ranks()[0])
	return "🏆 %s wins the %s!" % [best["name"], event_name]

func _draw_game() -> void:
	for i in lanes.size():
		var lane: Dictionary = lanes[i]
		var r := lane_rect(i)
		var s: Dictionary = lane["spirit"]
		lane_card(lane, r, Color("150f33"), Color("2b1d55"))
		nameplate(lane, r.position + Vector2(10, 6), "")
		# the track: a glowing column the spirit climbs during PERFORM
		var track := Rect2(r.get_center().x - 10, r.position.y + 54, 20, r.size.y - 120)
		rrect(track, Color(0, 0, 0, 0.45), 10, 1, Color(1, 1, 1, 0.12))
		for k in 5:
			var ty := track.end.y - track.size.y * k / 4.0
			draw_line(Vector2(track.position.x - 6, ty), Vector2(track.end.x + 6, ty), Color(1, 1, 1, 0.1), 1.0)
		var frac: float = float(lane["show"]) / float(maxi(1, _max_score + 2))
		if frac > 0.0:
			var h := (track.size.y - 4) * frac
			rrect(Rect2(track.position.x + 2, track.end.y - 2 - h, track.size.x - 4, h), Color(lane["color"], 0.85), 8)
		var climber := Vector2(track.get_center().x, track.end.y - (track.size.y - 4) * frac - 18)
		if _phase != "roll":
			var bob := sin(t * 10.0 + i) * 2.0 if _phase == "perform" else 0.0
			draw_spirit(lane, climber + Vector2(0, bob), 20)
			text(Vector2(r.position.x, climber.y - 30), "%d" % int(lane["show"]), 22, UIKit.GOLD, r.size.x, 5)
		else:
			draw_spirit(lane, Vector2(r.get_center().x, r.position.y + 90), 26)
			var prompt := "%s %d ×2 + ★%d" % [label.to_upper(), int(s.get(stat, 0)), int(s.get("stars", 0))]
			text(Vector2(r.position.x, r.position.y + 140), prompt, 14, Color(1, 1, 1, 0.9), r.size.x, 3)
			var hint: String = "🎲 %d!" % lane["roll"] if lane["rolled"] else \
				("press %s / click" % Controls.key_name(lane["slot"], "action") if lane["human"] else "CPU rolling…")
			text(Vector2(r.position.x, r.position.y + r.size.y * 0.42 + 92), hint, 15,
				UIKit.GOLD if lane["rolled"] else Color(0.75, 0.9, 1.0, 0.6 + 0.4 * sin(t * 6.0)), r.size.x, 3)
		# hide the die once the performance starts
		lane["die"].visible = _phase == "roll"
		if lane["place"] > 0:
			var medal: String = ["🥇", "🥈", "🥉"][lane["place"] - 1] if lane["place"] <= 3 else ORDINAL[lane["place"] - 1]
			rrect(Rect2(r.get_center().x - 50, r.end.y - 58, 100, 44), Color(0.06, 0.04, 0.14, 0.9), 14, 2,
				Color(UIKit.GOLD if lane["place"] == 1 else Color(1, 1, 1, 0.3)))
			text(Vector2(r.position.x, r.end.y - 28), "%s  %d" % [medal, _score(lane)], 20,
				UIKit.GOLD if lane["place"] == 1 else Color.WHITE, r.size.x, 4)
	var title: String = {"roll": "%s — roll your dice!" % event_name, "perform": "%s!" % event_name,
		"results": "Results"}[_phase]
	rrect(Rect2(size.x * 0.5 - 160, 2, 320, 26), Color(0.05, 0.04, 0.12, 0.8), 13)
	text(Vector2(size.x * 0.5 - 160, 21), title, 15, UIKit.GOLD, 320, 0)
