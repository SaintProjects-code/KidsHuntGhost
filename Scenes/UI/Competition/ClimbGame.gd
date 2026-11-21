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
const PLAT_COLORS := {"normal": Color("4be0a8"), "move": Color("a978ff"), "crumble": Color("8a8aa0"),
	"spring": Color("ffd24d"), "cloud": Color("eef4ff"), "ghost": Color("b8a8ff"), "rocket": Color("ff6a3a")}

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
		# special tiles get more common (and new ones appear) the higher you go:
		#   spring (gold), cloud (soft, slow bounce, from 80m), ghost (only
		#   solid while visible, from 150m), rocket (a huge launch, from 220m)
		if y > 2200 and roll < 0.05 + difficulty * 0.03:
			kind = "rocket"
		elif roll < 0.10 + difficulty * 0.08:
			kind = "spring"
		elif y > 800 and roll < 0.20 + difficulty * 0.1:
			kind = "cloud"
		elif y > 1500 and roll < 0.30 + difficulty * 0.12:
			kind = "ghost"
		elif roll < 0.42 + difficulty * 0.14:
			kind = "move"
		elif roll < 0.52 + difficulty * 0.16 and y > 300:
			kind = "crumble"
		lane["plats"].append({"x": randf_range(0.12, 0.88), "y": y, "kind": kind,
			"dx": randf_range(0.15, 0.3) * [-1.0, 1.0].pick_random(), "gone": false, "phase": randf() * TAU})
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
				if p["gone"] or prev_y < p["y"] or lane["y"] > p["y"] or not _solid(p):
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
	# one climber left: it's over once they're the highest (no one else can catch up)
	var alive := lanes.filter(func(l): return l["alive"])
	var last_wins: bool = alive.size() == 1 and lanes.size() > 1 and alive[0]["best"] >= _best_height() * 10.0
	if t > TIME_LIMIT or alive.is_empty() or last_wins:
		finish()

# A ghost platform fades in and out — you can only land while it's there.
func _solid(p: Dictionary) -> bool:
	return p["kind"] != "ghost" or sin(t * 2.2 + p["phase"]) > -0.2

const ROCKET_V := 1500.0

func _bounce(lane: Dictionary, p: Dictionary) -> void:
	var spring: bool = p["kind"] == "spring" or p["kind"] == "rocket"
	match p["kind"]:
		"rocket": lane["vy"] = ROCKET_V
		"spring": lane["vy"] = SPRING_V
		"cloud": lane["vy"] = lane["jump"] * 0.8
		_: lane["vy"] = lane["jump"]
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
			var col: Color = PLAT_COLORS.get(p["kind"], Color("4be0a8"))
			if p["kind"] == "ghost":
				col.a = 0.25 if not _solid(p) else 0.85
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

# ── 3D (3D maps) ──────────────────────────────────────────────────────────────
# Columns side by side; platforms are glowing slabs (y: 60 px = 1 unit).
# The camera follows whoever is highest.
const U := 60.0
const COL_W := 3.4

func _build_3d(v) -> void:
	v.sky(Color("1c1844"), 0.75)
	for i in lanes.size():
		var lane: Dictionary = lanes[i]
		var cx: float = v.lane_x(i, lanes.size(), COL_W + 2.0)
		lane["cx3"] = cx
		for sx in [-1.0, 1.0]:
			v.box(Vector3(0.06, 600, 0.06), Color("3a3478"), Vector3(cx + sx * (COL_W * 0.5 + 0.4), 280, -0.8), true)
		lane["n3"] = v.spirit(lane["tex"], lane["color"], Vector3(cx, 0, 0), 0.028)
		lane["p3"] = []   # [platform, node] pairs
		var l := lane
		v.tag(Vector3(cx, 0, 0), func(): return "", Color.WHITE)
		v.tag(lane["n3"], func(): return "%s  %dm" % [l["name"], int(l["best"] / 10.0)] if l["alive"] else "✗ %dm" % int(l["best"] / 10.0),
			lane["color"].lightened(0.25), 1.8, 14)
	_cam_y3 = 2.0

var _cam_y3 := 2.0

func _update_3d(v, delta: float) -> void:
	var top := 0.0
	for lane in lanes:
		var pairs: Array = lane["p3"]
		for p in lane["plats"]:
			p["_seen3"] = Engine.get_process_frames()
			if not p.has("_n3"):
				p["_n3"] = v.box(Vector3(COL_W * PLAT_W * 1.6, 0.22, 1.2), PLAT_COLORS.get(p["kind"], Color.WHITE), Vector3.ZERO, true)
				pairs.append([p, p["_n3"]])
			var m: MeshInstance3D = p["_n3"]
			m.visible = not p["gone"]
			m.position = Vector3(lane["cx3"] + (p["x"] - 0.5) * COL_W, p["y"] / U, 0)
			if p["kind"] == "ghost":
				m.material_override.albedo_color = Color(PLAT_COLORS["ghost"], 0.85 if _solid(p) else 0.2)
		for pr in pairs.duplicate():
			if pr[0].get("_seen3", -1) != Engine.get_process_frames():
				pr[1].queue_free()
				pairs.erase(pr)
		var n: Node3D = lane["n3"]
		n.position = Vector3(lane["cx3"] + (lane["x"] - 0.5) * COL_W, lane["y"] / U, 0)
		var sq: Vector2 = lane["squash"]
		n.scale = Vector3(sq.x, sq.y, 1.0)
		n.visible = lane["alive"]
		if lane["alive"]:
			top = maxf(top, lane["y"] / U)   # follow the leader
	_cam_y3 = lerpf(_cam_y3, top, minf(1.0, delta * 2.0))
	var dist := 14.0 + lanes.size() * 3.0
	v.aim(Vector3(0, _cam_y3 + 2.0, dist), Vector3(0, _cam_y3 + 2.0, 0))
