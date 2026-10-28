extends CompGame
## 🧗 Spirit Climb — Doodle-Jump style. Every player has their own tall column:
## the spirit bounces automatically off glowing platforms and you STEER it
## left/right (wrapping around the column edges) to climb as high as you can.
## Platforms: normal, drifting (purple), crumbling (cracked — one bounce) and
## spring pads (gold — a huge bounce). Fall off the bottom and you're out.
## Highest climb wins (35 s limit). Heavy spirits (DEF + HP) bounce lower;
## SPD steers faster.

const R := 15.0               # spirit radius (px)
const JUMP_V := 640.0         # bounce speed (px/s)
const SPRING_V := 1050.0
const GRAVITY := 1200.0
const PLAT_W := 0.22          # platform width, as a fraction of the column
const TIME_LIMIT := 35.0

var eliminated: Array = []

func _init_game() -> void:
	layout = Layout.COLUMNS
	record_key = "spirit_climb"
	how_to = "Bounce up the platforms — steer LEFT / RIGHT. Don't fall off the bottom! Highest climb wins."
	custom_minimum_size = Vector2(640, 440)
	for lane in lanes:
		var s: Dictionary = lane["spirit"]
		var weight := int(s.get("def", 0)) + int(s.get("hp_stat", 0))
		lane.merge({
			"x": 0.5, "y": 0.0, "vy": JUMP_V, "cam": 0.0, "best": 0.0, "alive": true, "out_t": 0.0,
			"jump": JUMP_V * (1.08 - maxf(0.0, weight - 2.0) * 0.012),   # weight 2 → ×1.08 … 12 → ×0.96
			"steer": 0.55 + int(s.get("spd", 2)) * 0.07,                 # columns per second
			"squash": Vector2.ONE, "plats": [], "next_y": 0.0, "fx": [],
			"face": 1.0,
			# CPU climber: reaction + aim noise
			"think": 0.0, "target_x": 0.5, "skill": randf_range(0.6, 0.95),
		})
		_spawn_plats(lane, 900.0)
		lane["plats"][0]["x"] = 0.5   # always a platform under the start
		lane["plats"][0]["kind"] = "normal"

# Fill platforms up to world height `top`. Gaps grow with height.
func _spawn_plats(lane: Dictionary, top: float) -> void:
	while lane["next_y"] < top:
		var y: float = lane["next_y"]
		var difficulty := clampf(y / 4000.0, 0.0, 1.0)
		var roll := randf()
		var kind := "normal"
		if roll < 0.06 + difficulty * 0.04:
			kind = "spring"
		elif roll < 0.22 + difficulty * 0.18:
			kind = "move"
		elif roll < 0.32 + difficulty * 0.2 and y > 300:
			kind = "crumble"
		lane["plats"].append({"x": randf_range(0.12, 0.88), "y": y, "kind": kind,
			"dx": randf_range(0.15, 0.3) * [-1.0, 1.0].pick_random(), "gone": false})
		lane["next_y"] = y + randf_range(70.0, 95.0) + difficulty * 55.0

func _tick(delta: float) -> void:
	for i in lanes.size():
		var lane: Dictionary = lanes[i]
		_step_fx(lane, delta)
		if not lane["alive"]:
			continue
		var r := lane_rect(i)
		var dir := steer(lane) if lane["human"] else _cpu_steer(lane, delta)
		if dir != 0.0:
			lane["face"] = dir
		lane["x"] = fposmod(lane["x"] + dir * lane["steer"] * delta, 1.0)
		var prev_y: float = lane["y"]
		lane["vy"] -= GRAVITY * delta
		lane["y"] += lane["vy"] * delta
		for p in lane["plats"]:
			if p["kind"] == "move":
				p["x"] += p["dx"] * delta
				if p["x"] < 0.1 or p["x"] > 0.9:
					p["dx"] *= -1.0
		# landing: only while falling, crossing a platform's top
		if lane["vy"] < 0.0:
			for p in lane["plats"]:
				if p["gone"] or prev_y < p["y"] or lane["y"] > p["y"]:
					continue
				if absf(_wrap_dx(lane["x"], p["x"])) < PLAT_W * 0.5 + R / maxf(1.0, r.size.x):
					_bounce(lane, p)
					break
		lane["best"] = maxf(lane["best"], lane["y"])
		lane["cam"] = maxf(lane["cam"], lane["y"] - r.size.y * 0.45)
		_spawn_plats(lane, lane["cam"] + r.size.y + 200.0)
		lane["plats"] = lane["plats"].filter(func(p): return p["y"] > lane["cam"] - 60.0)
		if lane["y"] < lane["cam"] - 40.0:
			lane["alive"] = false
			lane["out_t"] = t
			eliminated.append(lane["idx"])
			Sfx.play("faint")
	result_value = _best_height()
	if t > TIME_LIMIT or lanes.all(func(l): return not l["alive"]):
		finish()

func _bounce(lane: Dictionary, p: Dictionary) -> void:
	var spring: bool = p["kind"] == "spring"
	lane["vy"] = SPRING_V if spring else lane["jump"]
	lane["squash"] = Vector2(1.35, 0.7)
	for k in 6:
		lane["fx"].append({"p": Vector2(lane["x"], p["y"]), "v": Vector2(randf_range(-0.25, 0.25), randf_range(20, 80)),
			"life": 0.4, "c": UIKit.GOLD if spring else Color(0.6, 1.0, 0.85)})
	if p["kind"] == "crumble":
		p["gone"] = true
		Sfx.play("crash", 1.4, -8.0)
	elif lane["human"]:
		Sfx.play("collect" if spring else "jump", 1.0 if spring else randf_range(1.1, 1.25), -6.0)

func _step_fx(lane: Dictionary, delta: float) -> void:
	lane["squash"] = lane["squash"].lerp(Vector2.ONE, clampf(delta * 9.0, 0, 1))
	for f in lane["fx"]:
		f["p"] += f["v"] * delta * Vector2(1, -1)
		f["life"] -= delta
	lane["fx"] = lane["fx"].filter(func(f): return f["life"] > 0.0)

# Shortest horizontal distance on the wrapping column.
func _wrap_dx(a: float, b: float) -> float:
	return fposmod(b - a + 0.5, 1.0) - 0.5

# CPU: pick the next reachable platform above and steer towards it.
func _cpu_steer(lane: Dictionary, delta: float) -> float:
	lane["think"] -= delta
	if lane["think"] <= 0.0:
		lane["think"] = randf_range(0.1, 0.25) / lane["skill"]
		var reach: float = lane["y"] + lane["vy"] * lane["vy"] / (2.0 * GRAVITY) if lane["vy"] > 0.0 else lane["y"]
		var best = null
		for p in lane["plats"]:
			if p["gone"] or p["y"] > reach - 10.0 or p["y"] < lane["y"] - 140.0:
				continue
			if best == null or p["y"] > best["y"]:
				best = p
		if best != null:
			lane["target_x"] = fposmod(best["x"] + randf_range(-0.06, 0.06) / lane["skill"], 1.0)
	var dx := _wrap_dx(lane["x"], lane["target_x"])
	return 0.0 if absf(dx) < 0.03 else signf(dx)

func _on_action(_lane: Dictionary, _action: String) -> void:
	pass   # steering is held input (see steer())

func keys_text(lane: Dictionary) -> String:
	return "hold %s / %s to steer (or hold the mouse on a side of your column)" % [
		Controls.key_name(lane["slot"], "left"), Controls.key_name(lane["slot"], "right")]

func _best_height() -> float:
	var best := 0.0
	for lane in lanes:
		best = maxf(best, lane["best"])
	return best / 10.0   # metres

func ranks() -> Array:
	var sorted := lanes.duplicate()
	sorted.sort_custom(func(a, b): return a["best"] > b["best"])
	return sorted.map(func(l): return l["idx"])

func result_text() -> String:
	var best := _lane_by_idx(ranks()[0])
	return "🧗 %s climbs %dm!" % [best["name"], int(best["best"] / 10.0)]

func _draw_game() -> void:
	for i in lanes.size():
		var lane: Dictionary = lanes[i]
		var r := lane_rect(i)
		var alt := clampf(lane["cam"] / 5000.0, 0.0, 1.0)   # the sky changes as you climb
		lane_card(lane, r, Color("0b0d2e").lerp(Color("2a0b3a"), alt), Color("2c2a6a").lerp(Color("0f5a5a"), alt))
		var base_y := r.end.y - 8.0
		var to_screen := func(wx: float, wy: float) -> Vector2:
			return Vector2(r.position.x + 6 + wx * (r.size.x - 12), base_y - (wy - lane["cam"]))
		# parallax stars
		for k in 14:
			var sy := fposmod(k * 83.0 + lane["cam"] * 0.25, r.size.y)
			draw_circle(Vector2(r.position.x + fmod(k * 53.0, r.size.x - 12) + 6, r.position.y + sy), 1.2,
				Color(1, 1, 1, 0.3 + 0.3 * sin(t * 3.0 + k)))
		for p in lane["plats"]:
			if p["gone"]:
				continue
			var c: Vector2 = to_screen.call(p["x"], p["y"])
			if c.y < r.position.y - 10 or c.y > r.end.y + 10:
				continue
			var w := PLAT_W * (r.size.x - 12)
			var col: Color = {"normal": Color("4be0a8"), "move": Color("a978ff"), "crumble": Color("8a8aa0"),
				"spring": UIKit.GOLD}[p["kind"]]
			glow(c, w * 0.35, Color(col, 0.6), 4)
			rrect(Rect2(c - Vector2(w * 0.5, 5), Vector2(w, 10)), col, 5)
			draw_rect(Rect2(c - Vector2(w * 0.5 - 4, 4), Vector2(w - 8, 2)), Color(1, 1, 1, 0.35))
			if p["kind"] == "crumble":
				draw_line(c + Vector2(-w * 0.15, -5), c + Vector2(-w * 0.05, 5), Color(0, 0, 0, 0.5), 1.5)
				draw_line(c + Vector2(w * 0.12, -5), c + Vector2(w * 0.2, 5), Color(0, 0, 0, 0.5), 1.5)
			elif p["kind"] == "spring":
				draw_line(c + Vector2(-6, -5), c + Vector2(6, -12), Color.WHITE, 2.0)
				draw_line(c + Vector2(6, -12), c + Vector2(-6, -17), Color.WHITE, 2.0)
		for f in lane["fx"]:
			draw_circle(to_screen.call(f["p"].x, f["p"].y), 2.5, Color(f["c"], f["life"] * 2.0))
		if lane["alive"]:
			var me: Vector2 = to_screen.call(lane["x"], lane["y"]) - Vector2(0, R)
			draw_spirit(lane, me, R, Color.WHITE, lane["squash"])
			if me.x < r.position.x + R:   # wrap-around ghost image
				draw_spirit(lane, me + Vector2(r.size.x - 12, 0), R, Color(1, 1, 1, 0.5), lane["squash"], 0.0)
			elif me.x > r.end.x - R:
				draw_spirit(lane, me - Vector2(r.size.x - 12, 0), R, Color(1, 1, 1, 0.5), lane["squash"], 0.0)
		else:
			text(Vector2(r.position.x, r.get_center().y), "✗ fell at %dm" % int(lane["best"] / 10.0), 18,
				Color(1, 0.6, 0.6), r.size.x, 5)
		# altitude pill at the bottom of the column
		var alt_txt := "%dm" % int(lane["best"] / 10.0)
		rrect(Rect2(r.get_center().x - 34, r.end.y - 30, 68, 22), Color(0.05, 0.04, 0.12, 0.75), 11)
		text(Vector2(r.position.x, r.end.y - 14), alt_txt, 14, UIKit.GOLD, r.size.x, 0)
		_column_plate(lane, r)
	if running:
		rrect(Rect2(size.x * 0.5 - 46, 4, 92, 22), Color(0.05, 0.04, 0.12, 0.75), 11)
		text(Vector2(size.x * 0.5 - 46, 20), "⏱ %.0f" % maxf(0.0, TIME_LIMIT - t), 13, Color.WHITE, 92, 0)

# A compact nameplate centred at the top of a column.
func _column_plate(lane: Dictionary, r: Rect2) -> void:
	var label: String = "%s %s" % [lane["name"], key_hint(lane, "left").replace("]", "/" + Controls.key_name(lane["slot"], "right") + "]") if lane["human"] else "(CPU)"]
	var w := minf(r.size.x - 12, text_width(label, 13) + 24)
	var pr := Rect2(r.get_center().x - w * 0.5, r.position.y + 30, w, 22)
	rrect(pr, Color(0.05, 0.04, 0.12, 0.75), 11, 1, Color(lane["color"], 0.6))
	text(Vector2(pr.position.x, pr.position.y + 16), label, 13, lane["color"].lightened(0.3), pr.size.x, 0)
