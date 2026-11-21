extends CompGame
## 🎈 Wisp Float (NEW) — HOLD your ACTION key (or hold the mouse on your lane)
## to float up, let go to sink. Glowing wisps drift in from the right — grab
## them (+1); bats knock one loose (−1) and stun you for a moment.
## SPD = how fast you rise, DEF = how quickly you shake off a bat. 20 seconds;
## most wisps wins.

const X := 110.0
const R := 16.0
const TIME_LIMIT := 20.0
const SCROLL := 180.0
const GRAVITY := 520.0

func _init_game() -> void:
	record_key = "wisp_float"
	layout = Layout.ROWS
	how_to = "HOLD your key to float up, let go to sink. Grab wisps, dodge the bats!"
	custom_minimum_size = Vector2(640, 440)
	for lane in lanes:
		lane.merge({
			"y": 0.5, "vy": 0.0, "score": 0, "items": [], "spawn": 0.4, "stun": 0.0,
			"lift": 820.0 + int(lane["spirit"].get("spd", 2)) * 70.0, "fx": [],
			"stun_time": 1.1 - int(lane["spirit"].get("def", 2)) * 0.1,   # DEF 1 → 1.0s … 6 → 0.5s
			# CPU pilot: how well it reads the wisps and dodges
			"skill": randf_range(0.55, 0.95), "hold": false, "think": 0.0,
		})

# A lane's playfield: its top and bottom y (inside the lane card).
func _field(i: int) -> Vector2:
	var r := lane_rect(i)
	return Vector2(r.position.y + 34.0, r.end.y - 12.0)

func keys_text(lane: Dictionary) -> String:
	return "hold %s to float (or hold the mouse on your lane)" % Controls.key_name(lane["slot"], "action")

func _tick(delta: float) -> void:
	for i in lanes.size():
		var lane: Dictionary = lanes[i]
		var f := _field(i)
		var h := f.y - f.x
		lane["stun"] = maxf(0.0, lane["stun"] - delta)
		var up: bool = (lane["hold"] if not lane["human"] else is_held(lane)) and lane["stun"] <= 0.0
		lane["vy"] += (-lane["lift"] if up else GRAVITY) * delta
		lane["vy"] = clampf(lane["vy"], -320.0, 320.0)
		lane["y"] = clampf(lane["y"] + lane["vy"] * delta / h, 0.0, 1.0)
		if lane["y"] <= 0.0 or lane["y"] >= 1.0:
			lane["vy"] = 0.0
		# spawn wisps (mostly) and bats
		lane["spawn"] -= delta
		if lane["spawn"] <= 0.0:
			lane["spawn"] = randf_range(0.45, 0.85)
			lane["items"].append({"x": size.x + 20.0, "y": randf_range(0.05, 0.95), "bat": randf() < 0.3 + t * 0.008})
		var me := Vector2(X, f.x + lane["y"] * h)
		for it in lane["items"]:
			it["x"] -= SCROLL * (1.0 + t * 0.02) * delta
			var p := Vector2(it["x"], f.x + it["y"] * h)
			if p.distance_to(me) < R + 10.0 and not it.get("hit", false):
				it["hit"] = true
				if it["bat"]:
					if lane["stun"] <= 0.0:
						lane["score"] = maxi(0, lane["score"] - 1)
						lane["stun"] = lane["stun_time"]
						_burst(lane, me, Color(0.9, 0.3, 0.3))
						Sfx.play("hit", 1.0, -4.0)
				else:
					lane["score"] += 1
					_burst(lane, p, Color(0.6, 1.0, 0.9))
					Sfx.play("collect", randf_range(0.95, 1.15), -6.0)
		lane["items"] = lane["items"].filter(func(it): return it["x"] > -30.0 and not it.get("hit", false))
		for fx in lane["fx"]:
			fx["p"] += fx["v"] * delta
			fx["life"] -= delta
		lane["fx"] = lane["fx"].filter(func(fx): return fx["life"] > 0.0)
		if not lane["human"]:
			_cpu(lane, delta)
	if t >= TIME_LIMIT:
		result_value = float(_lane_by_idx(ranks()[0])["score"])
		finish()

func _burst(lane: Dictionary, at: Vector2, col: Color) -> void:
	for k in 8:
		var a := randf() * TAU
		lane["fx"].append({"p": at, "v": Vector2(cos(a), sin(a)) * randf_range(40, 110), "life": 0.4, "c": col})

# CPU: aim for the nearest wisp ahead, dodge a bat that's about to hit.
func _cpu(lane: Dictionary, delta: float) -> void:
	lane["think"] -= delta
	if lane["think"] > 0.0:
		return
	lane["think"] = randf_range(0.04, 0.12) / lane["skill"]
	var target := 0.5
	var best := INF
	for it in lane["items"]:
		var dx: float = it["x"] - X
		if dx < -10.0 or dx > 320.0:
			continue
		if it["bat"]:
			if dx < 90.0 and absf(it["y"] - lane["y"]) < 0.25 and randf() < lane["skill"]:
				target = 0.95 if it["y"] < 0.5 else 0.05
				best = -1.0
				break
		elif dx < best:
			best = dx
			target = it["y"]
	if randf() > lane["skill"]:
		target += randf_range(-0.3, 0.3)
	lane["hold"] = lane["y"] > target + 0.04

func ranks() -> Array:
	var sorted := lanes.duplicate()
	sorted.sort_custom(func(a, b): return a["score"] > b["score"])
	return sorted.map(func(l): return l["idx"])

func result_text() -> String:
	var best := _lane_by_idx(ranks()[0])
	return "🎈 %s grabs %d wisps!" % [best["name"], best["score"]]

func _draw_game() -> void:
	for i in lanes.size():
		var lane: Dictionary = lanes[i]
		var f := _field(i)
		var h := f.y - f.x
		var card := lane_rect(i)
		lane_card(lane, card, Color("070a24"), Color("1c1450"))
		for k in 10:   # drifting stars
			var sx := fposmod(k * 137.0 - t * (20 + k * 2), size.x - 20) + 10
			draw_circle(Vector2(sx, f.x + fmod(k * 37.0, h)), 1.2, Color(1, 1, 1, 0.3 + 0.3 * sin(t * 4 + k)))
		draw_line(Vector2(8, f.y + 4), Vector2(size.x - 8, f.y + 4), Color(0.5, 0.6, 1.0, 0.15), 1.0)
		for it in lane["items"]:
			var p := Vector2(it["x"], f.x + it["y"] * h)
			if it["bat"]:
				var flap := sin(t * 18.0 + it["x"]) * 6.0
				var wing := Color(0.32, 0.12, 0.42)
				draw_colored_polygon(PackedVector2Array([p, p + Vector2(-18, -7 + flap), p + Vector2(-10, 1), p + Vector2(-6, 5)]), wing)
				draw_colored_polygon(PackedVector2Array([p, p + Vector2(18, -7 + flap), p + Vector2(10, 1), p + Vector2(6, 5)]), wing)
				draw_circle(p, 6, Color(0.38, 0.16, 0.48))
				glow(p, 4, Color(1, 0.2, 0.3, 0.5), 3)
				draw_circle(p + Vector2(-2, -1), 1.4, Color(1, 0.4, 0.4))
				draw_circle(p + Vector2(2, -1), 1.4, Color(1, 0.4, 0.4))
			else:
				var pulse := 0.6 + 0.4 * sin(t * 6.0 + it["x"] * 0.05)
				for k in 3:   # little comet tail
					draw_circle(p + Vector2(8 + k * 7, 0), 4.0 - k, Color(0.5, 1, 0.9, 0.18 - k * 0.05))
				glow(p, 9, Color(0.4, 1.0, 0.85, pulse), 6)
				draw_circle(p, 5, Color(0.85, 1, 0.97))
		for fx in lane["fx"]:
			draw_circle(fx["p"], 2.5, Color(fx["c"], fx["life"] * 2.5))
		var me := Vector2(X, f.x + lane["y"] * h)
		for k in 4:   # float trail
			draw_circle(me - Vector2(8 + k * 8, -lane["vy"] * 0.02 * k), R * (0.7 - k * 0.14), Color(lane["color"], 0.12))
		var stunned: bool = lane["stun"] > 0.0
		var tint := Color(1, 1, 1, 0.35 + 0.65 * float(int(t * 12) % 2)) if stunned else Color.WHITE
		draw_spirit(lane, me, R, tint)
		nameplate(lane, card.position + Vector2(10, 6), "✨ %d   HOLD to float" % lane["score"])
	if running:
		rrect(Rect2(size.x - 104, 8, 92, 22), Color(0.05, 0.04, 0.12, 0.7), 11)
		text(Vector2(size.x - 104, 24), "⏱ %.1f" % maxf(0.0, TIME_LIMIT - t), 13, Color.WHITE, 92, 0)

# ── 3D (3D maps) ──────────────────────────────────────────────────────────────
# Four stacked tunnels (side view). Wisps and bats come in from the right;
# the spirit floats up while held (lane y 0 = top … 1 = bottom).
const BAND3 := 3.6
const SPAN3 := 22.0

func _build_3d(v) -> void:
	v.sky(Color("101830"), 0.7)
	v.aim(Vector3(0, (lanes.size() - 1) * BAND3 * 0.5 + 1.4, 8 + lanes.size() * 3.4), Vector3(0, (lanes.size() - 1) * BAND3 * 0.5 + 1.4, 0), 0.95)
	for i in lanes.size():
		var lane: Dictionary = lanes[i]
		var y0 := (lanes.size() - 1 - i) * BAND3   # P1 on top
		lane["y03"] = y0
		v.box(Vector3(SPAN3 + 2, 0.1, 1.6), Color("22304a"), Vector3(0, y0 - 0.05, 0))
		v.box(Vector3(SPAN3 + 2, 0.1, 1.6), Color("22304a"), Vector3(0, y0 + 3.0, 0))
		lane["n3"] = v.spirit(lane["tex"], lane["color"], Vector3(-SPAN3 / 2 + 2.5, y0 + 1, 0), 0.02)
		lane["it3"] = []   # [item, node] pairs
		var l := lane
		v.tag(Vector3(-SPAN3 / 2 - 0.2, y0 + 2.6, 0), func(): return "%s %s  ✦ %d" % [l["name"], key_hint(l), l["score"]], lane["color"].lightened(0.25), 0.0, 14)

func _update_3d(v, _delta: float) -> void:
	for lane in lanes:
		var y0: float = lane["y03"]
		var n: Node3D = lane["n3"]
		n.position.y = y0 + 0.15 + (1.0 - lane["y"]) * 2.1
		n.rotation.z = sin(t * 30.0) * 0.4 if lane["stun"] > 0.0 else 0.0
		var pairs: Array = lane["it3"]
		for it in lane["items"]:
			it["_seen3"] = Engine.get_process_frames()
			if not it.has("_n3"):
				it["_n3"] = v.box(Vector3(0.7, 0.25, 0.4), Color("3a2050"), Vector3.ZERO) if it["bat"] else v.ball(0.25, Color("9fe8ff"), Vector3.ZERO, true)
				pairs.append([it, it["_n3"]])
			var m: MeshInstance3D = it["_n3"]
			m.position = Vector3(n.position.x + (it["x"] - X) * SPAN3 / maxf(1.0, size.x), y0 + 0.4 + (1.0 - it["y"]) * 2.1, 0)
		for pr in pairs.duplicate():
			if pr[0].get("_seen3", -1) != Engine.get_process_frames():
				if pr[0].get("hit", false):
					v.pop(n, "−1" if pr[0]["bat"] else "+1", Color("ff6a6a") if pr[0]["bat"] else Color("9fe8ff"), 1.4, 0.8, 18)
				pr[1].queue_free()
				pairs.erase(pr)
