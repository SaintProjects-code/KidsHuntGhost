extends CompGame
## 🎃 Pumpkin Toss — a timing game. A power meter swings up and down; press
## your ACTION key to throw when it's high. Three throws, the longest total
## distance wins. ATK = how far a full-power throw flies, SPD = a slower,
## easier-to-time meter.

const THROWS := 3
const FLIGHT := 0.9          # seconds a pumpkin is in the air

func _init_game() -> void:
	record_key = "pumpkin_toss"
	layout = Layout.COLUMNS
	how_to = "Press your key when the power meter is HIGH to toss the pumpkin. 3 throws — farthest total wins!"
	custom_minimum_size = Vector2(640, 440)
	for lane in lanes:
		var s: Dictionary = lane["spirit"]
		lane.merge({
			"throws": [], "power": 0.0, "dir": 1.0,
			"speed": 1.9 - int(s.get("spd", 2)) * 0.12,   # meter sweeps per second (lower = easier)
			"reach": 30.0 + int(s.get("atk", 2)) * 6.0,   # metres at full power
			"fly_t": -1.0, "fly_d": 0.0,
			"cpu_aim": randf_range(0.72, 0.97),
		})

func _total(lane: Dictionary) -> float:
	var sum := 0.0
	for d in lane["throws"]:
		sum += d
	return sum

func _tick(delta: float) -> void:
	for lane in lanes:
		if lane["fly_t"] >= 0.0:
			lane["fly_t"] += delta
			if lane["fly_t"] >= FLIGHT:
				lane["fly_t"] = -1.0
			continue
		if lane["throws"].size() >= THROWS:
			continue
		lane["power"] += lane["dir"] * lane["speed"] * delta
		if lane["power"] >= 1.0:
			lane["power"] = 1.0
			lane["dir"] = -1.0
		elif lane["power"] <= 0.0:
			lane["power"] = 0.0
			lane["dir"] = 1.0
		if not lane["human"] and lane["dir"] > 0.0 and lane["power"] >= lane["cpu_aim"]:
			_throw(lane)
			lane["cpu_aim"] = randf_range(0.7, 0.97)
	if lanes.all(func(l): return l["throws"].size() >= THROWS and l["fly_t"] < 0.0):
		result_value = _total(_lane_by_idx(ranks()[0]))
		finish()

func _throw(lane: Dictionary) -> void:
	if lane["throws"].size() >= THROWS or lane["fly_t"] >= 0.0:
		return
	# the top of the meter is the sweet spot; overshooting doesn't exist, a
	# low press just flies short
	var d: float = lane["reach"] * pow(lane["power"], 1.4)
	lane["throws"].append(d)
	lane["fly_d"] = d
	lane["fly_t"] = 0.0
	lane["power"] = 0.0
	lane["dir"] = 1.0
	Sfx.play("whoosh", 0.8 + lane["fly_d"] / 80.0)

func _on_action(lane: Dictionary, action: String) -> void:
	if action == "action":
		_throw(lane)

func ranks() -> Array:
	var sorted := lanes.duplicate()
	sorted.sort_custom(func(a, b): return _total(a) > _total(b))
	return sorted.map(func(l): return l["idx"])

func result_text() -> String:
	var best := _lane_by_idx(ranks()[0])
	return "🎃 %s tosses %.1f m in total!" % [best["name"], _total(best)]

func _draw_game() -> void:
	for i in lanes.size():
		var lane: Dictionary = lanes[i]
		var r := lane_rect(i)
		lane_card(lane, r, Color("1d1338"), Color("5a2a12"))
		var ground_y := r.end.y - 40.0
		grad_rect(Rect2(r.position.x + 4, ground_y, r.size.x - 8, 36), Color(0.2, 0.12, 0.05), Color(0.08, 0.05, 0.02))
		# distance markers up the column (the field runs "upward")
		var top := r.position.y + 70.0
		var per_m: float = (ground_y - top - 40.0) / 80.0
		for m in [20, 40, 60, 80]:
			var y: float = ground_y - 40.0 - m * per_m
			draw_line(Vector2(r.position.x + 8, y), Vector2(r.end.x - 34, y), Color(1, 1, 1, 0.1), 1.0)
			text(Vector2(r.position.x + 10, y - 3), "%dm" % m, 11, Color(1, 1, 1, 0.45), -1, 0)
		var cx := r.get_center().x - 12.0
		var me := Vector2(cx, ground_y - 22)
		shadow(Vector2(cx, ground_y + 4), 22, 6)
		draw_spirit(lane, me, 20.0)
		# landed pumpkins
		for d in lane["throws"]:
			if lane["fly_t"] >= 0.0 and d == lane["throws"].back():
				continue
			draw_circle(Vector2(cx + 18, ground_y - 40.0 - d * per_m), 6, Color(0.95, 0.5, 0.1, 0.8))
		# the pumpkin in flight: rises then drops onto its mark
		if lane["fly_t"] >= 0.0:
			var f: float = lane["fly_t"] / FLIGHT
			var land_y: float = ground_y - 40.0 - lane["fly_d"] * per_m
			var y: float = lerpf(me.y, land_y, f) - sin(f * PI) * 40.0
			glow(Vector2(cx + 18 * f, y), 12, Color(1, 0.6, 0.2, 0.6), 4)
			draw_circle(Vector2(cx + 18 * f, y), 9, Color(0.95, 0.5, 0.1))
		# power meter on the right
		var bar := Rect2(r.end.x - 26, r.position.y + 64, 16, r.size.y - 110)
		rrect(bar, Color(0, 0, 0, 0.55), 8, 1, Color(1, 1, 1, 0.18))
		var h: float = (bar.size.y - 4) * lane["power"]
		if h > 0.0:
			rrect(Rect2(bar.position.x + 2, bar.end.y - 2 - h, bar.size.x - 4, h), Color("4dd0ff").lerp(Color("ffd24d"), lane["power"]), 6)
		var status := "%d/%d  %.1fm" % [lane["throws"].size(), THROWS, _total(lane)]
		nameplate(lane, r.position + Vector2(8, 30), status)

# ── 3D (3D maps) ──────────────────────────────────────────────────────────────
# Lanes run down a long field (1 m = 0.5 units). A power meter stands by each
# spirit; the pumpkin arcs out, and a flag in the player's colour marks every
# landing (they stay).
const M3 := 0.5

func _build_3d(v) -> void:
	var gap := 4.2
	v.sky(Color("6a9ad8"), 0.85)
	v.aim(Vector3(0, 13 + lanes.size(), 20 + lanes.size() * 1.5), Vector3(0, 0, -12))
	v.box(Vector3(lanes.size() * gap + 4, 0.2, 80), Color("5a9a4a"), Vector3(0, -0.1, -30))
	for z in range(-5, -70, -5):
		v.box(Vector3(lanes.size() * gap + 4, 0.03, 0.14), Color.WHITE, Vector3(0, 0.01, z), true)
		v.tag(Vector3(-(lanes.size() * gap + 4) / 2 - 0.4, 0, z), "%dm" % int(-z / M3), Color(1, 1, 1, 0.8), 0.2, 12)
	for i in lanes.size():
		var lane: Dictionary = lanes[i]
		var x: float = v.lane_x(i, lanes.size(), gap)
		lane["x3"] = x
		lane["n3"] = v.spirit(lane["tex"], lane["color"], Vector3(x, 0, 2), 0.03)
		v.box(Vector3(0.4, 3, 0.08), Color("222222"), Vector3(x + 1.2, 1.5, 1.9), true)
		lane["bar3"] = v.box(Vector3(0.3, 1, 0.1), Color("ffd24d"), Vector3(x + 1.2, 0, 1.95), true)
		lane["pk3"] = v.ball(0.42, Color("ff8a20"), Vector3(x, 1.2, 1.6))
		lane["flags3"] = 0
		var l := lane
		v.tag(lane["n3"], func(): return "%s %s  %dm" % [l["name"], key_hint(l), int(_total(l))], lane["color"].lightened(0.25), 2.2, 14)

func _update_3d(v, _delta: float) -> void:
	for lane in lanes:
		var x: float = lane["x3"]
		lane["bar3"].scale.y = maxf(0.01, lane["power"] * 3.0)
		lane["bar3"].position.y = lane["power"] * 1.5
		var pk: MeshInstance3D = lane["pk3"]
		if lane["fly_t"] >= 0.0:
			var u: float = lane["fly_t"] / FLIGHT
			pk.position = Vector3(x, 1.2 + sin(u * PI) * (2.0 + lane["fly_d"] * 0.12), 1.6 - lane["fly_d"] * M3 * u)
			pk.rotation.x += 0.3
		else:
			pk.position = Vector3(x, 1.2, 1.6)
		# a landed throw leaves its flag (it stays)
		var landed: int = lane["throws"].size() - (1 if lane["fly_t"] >= 0.0 else 0)
		while lane["flags3"] < landed:
			var d: float = lane["throws"][lane["flags3"]]
			var at := Vector3(x, 0.7, 1.6 - d * M3)
			v.box(Vector3(0.08, 1.4, 0.08), lane["color"], at, true)
			v.box(Vector3(0.5, 0.3, 0.04), lane["color"], at + Vector3(0.25, 0.55, 0), true)
			v.pop(at, "%dm" % int(d), Color("ffd24d"), 1.4)
			lane["flags3"] += 1
