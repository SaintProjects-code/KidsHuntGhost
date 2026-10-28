extends CompGame
## 🌳 Tree Jump — every entrant runs in its own moonlit lane and hops the
## trees that scroll in. DEF + HP is WEIGHT: heavy spirits fall faster (shorter
## hops). It speeds up over time; last one standing wins (the last runner keeps
## going to push the record). CPUs fumble more as the speed climbs.
## Juice: squash & stretch, dust puffs, a crash shake, parallax hills + stars.

const TREE_TEX := preload("res://Assets/Trees/tree1.png")
const LANE_H := 92.0
const VIEW_W := 720.0
const RUN_X := 84.0
const R := 24.0
const TREE_H := 34.0
const START_SPEED := 170.0
const ACCEL := 9.0
const MAX_SPEED := 560.0
const JUMP_V := 330.0
const BASE_G := 950.0

var speed := START_SPEED
var eliminated: Array = []
var _scroll := 0.0
var _stars: Array = []

func _init_game() -> void:
	record_key = "tree_jump"
	custom_minimum_size = Vector2(VIEW_W, LANE_H * lanes.size())
	for lane in lanes:
		var s: Dictionary = lane["spirit"]
		var weight: int = int(s.get("def", 0)) + int(s.get("hp_stat", 0))
		lane.merge({
			"gmult": 1.0 + maxf(0.0, weight - 2.0) * 0.055,   # weight 2 → 1.0 … 12 → 1.55
			"y": 0.0, "vy": 0.0, "air": false, "alive": true, "out_pos": 0, "time": 0.0,
			"trees": [], "gap": randf_range(320.0, 520.0), "squash": Vector2.ONE, "dust": [], "shake": 0.0,
			# per-CPU pilot: reaction window + steadiness
			"react": randf_range(0.26, 0.38), "skill": randf_range(0.65, 1.1),
		})
	for i in 40:
		_stars.append(Vector3(randf() * VIEW_W, randf() * 0.6, randf() * TAU))

func _tree_w() -> float:
	return TREE_H * TREE_TEX.get_size().x / TREE_TEX.get_size().y

func _tick(delta: float) -> void:
	speed = minf(MAX_SPEED, START_SPEED + ACCEL * t)
	_scroll += speed * delta
	for lane in lanes:
		_step_fx(lane, delta)
		if lane["alive"]:
			_step_lane(lane, delta)
	result_value = _best_time()
	if lanes.all(func(l): return not l["alive"]):
		finish()

func _step_fx(lane: Dictionary, delta: float) -> void:
	lane["squash"] = lane["squash"].lerp(Vector2.ONE, clampf(delta * 10.0, 0, 1))
	lane["shake"] = maxf(0.0, lane["shake"] - delta * 30.0)
	for d in lane["dust"]:
		d["p"] += d["v"] * delta
		d["life"] -= delta
	lane["dust"] = lane["dust"].filter(func(d): return d["life"] > 0.0)

func _puff(lane: Dictionary, n: int) -> void:
	for k in n:
		lane["dust"].append({"p": Vector2(RUN_X + randf_range(-10, 10), 0), "v": Vector2(randf_range(-90, -20), randf_range(-50, -10)), "life": randf_range(0.25, 0.45)})

func _step_lane(lane: Dictionary, delta: float) -> void:
	var trees: Array = lane["trees"]
	for tr in trees:
		tr["x"] -= speed * delta
	while not trees.is_empty() and trees[0]["x"] < -60.0:
		trees.pop_front()
	if trees.is_empty() or trees[-1]["x"] < VIEW_W - lane["gap"]:
		# clusters of 2 after 10s and 3 after 25s, once jumps carry far enough
		var count := 1
		var roll := randf()
		if t > 25.0 and roll < 0.15:
			count = 3
		elif t > 10.0 and roll < 0.45:
			count = 2
		for n in count:
			trees.append({"x": VIEW_W + 40.0 + n * _tree_w(), "seen": n > 0})
		lane["gap"] = randf_range(320.0, 520.0) + count * _tree_w()
	if lane["air"]:
		lane["vy"] += BASE_G * lane["gmult"] * delta
		lane["y"] += lane["vy"] * delta
		if lane["y"] >= 0.0:
			lane["y"] = 0.0
			lane["vy"] = 0.0
			lane["air"] = false
			lane["squash"] = Vector2(1.3, 0.7)   # landing squash
			_puff(lane, 4)
			if lane["human"]:
				Sfx.play("land", 1.2)
	if not lane["human"] and not lane["air"]:
		_cpu_pilot(lane, trees)
	var tree_w := _tree_w()
	for tr in trees:
		var cx: float = tr["x"] + tree_w * 0.5
		if absf(cx - RUN_X) < tree_w * 0.5 + R * 0.55 and lane["y"] > -(TREE_H - 12.0):
			lane["alive"] = false
			lane["time"] = t
			lane["shake"] = 10.0
			eliminated.append(lane["idx"])
			lane["out_pos"] = lanes.size() - eliminated.size() + 1
			Sfx.play("crash")
			break

# Jump when a tree enters this pilot's reaction window; fumble odds grow with
# speed and shrink with skill.
func _cpu_pilot(lane: Dictionary, trees: Array) -> void:
	for tr in trees:
		var dist: float = tr["x"] - RUN_X
		if dist > 0.0 and dist < speed * float(lane["react"]):
			if not tr["seen"]:
				tr["seen"] = true
				var fumble := minf(0.55, (0.02 + t * 0.012) * (2.0 - float(lane["skill"])))
				tr["skip"] = randf() < fumble
			if not tr.get("skip", false):
				_jump(lane)
			break

func _jump(lane: Dictionary) -> void:
	if running and lane["alive"] and not lane["air"]:
		lane["vy"] = -JUMP_V
		lane["air"] = true
		lane["squash"] = Vector2(0.75, 1.3)   # take-off stretch
		_puff(lane, 3)
		Sfx.play("jump", randf_range(0.95, 1.08))

func _on_action(lane: Dictionary, action: String) -> void:
	if action == "action":
		_jump(lane)

# Winner first: survivors, then the fallen in reverse order.
func ranks() -> Array:
	var out: Array = lanes.filter(func(l): return l["alive"]).map(func(l): return l["idx"])
	for i in range(eliminated.size() - 1, -1, -1):
		out.append(eliminated[i])
	return out

func _best_time() -> float:
	var best := 0.0
	for lane in lanes:
		best = maxf(best, t if lane["alive"] else float(lane["time"]))
	return best

func result_text() -> String:
	return "🏁 %s wins — %.1fs!" % [_lane_by_idx(ranks()[0])["name"], _best_time()]

func _draw_game() -> void:
	var tree_w := _tree_w()
	for i in lanes.size():
		var lane: Dictionary = lanes[i]
		var top := i * LANE_H
		var card := Rect2(4, top + 3, size.x - 8, LANE_H - 6)
		var ground := top + LANE_H - 16.0
		var alive: bool = lane["alive"]
		var shake := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * float(lane["shake"])
		draw_set_transform(shake, 0.0, Vector2.ONE)
		# moonlit sky: indigo → violet, dimmed red when out
		var sky_top := Color("141540") if alive else Color("2a1020")
		var sky_bot := Color("4a2a72") if alive else Color("40182a")
		lane_card(lane, card, sky_top, sky_bot)
		for s in _stars:
			var tw := 0.5 + 0.5 * sin(t * 3.0 + s.z)
			var sp := Vector2(fposmod(s.x - _scroll * 0.04, size.x - 20) + 10, top + 10 + s.y * (LANE_H - 40))
			draw_circle(sp, 1.1 + tw * 0.6, Color(1, 1, 1, 0.25 + 0.55 * tw))
		var moon := Vector2(size.x - 70, top + 26)
		glow(moon, 16, Color(1, 0.92, 0.7, 0.9), 6)
		draw_circle(moon, 11, Color(1, 0.97, 0.86))
		draw_circle(moon + Vector2(4, -3), 9, sky_top.lerp(sky_bot, 0.2))   # crescent
		# two hill layers at different parallax speeds
		for layer in [[0.18, 54.0, 150.0, Color(0.16, 0.12, 0.3)], [0.4, 34.0, 95.0, Color(0.1, 0.08, 0.2)]]:
			var spd: float = layer[0]
			var rad: float = layer[1]
			var gap: float = layer[2]
			var hx := -fposmod(_scroll * spd, gap)
			while hx < size.x + gap:
				draw_circle(Vector2(hx, ground + rad * 0.55), rad, layer[3])
				hx += gap
		# ground strip with a glowing edge
		grad_rect(Rect2(6, ground, size.x - 12, LANE_H - (ground - top) - 5), Color(0.13, 0.25, 0.18), Color(0.05, 0.1, 0.08))
		draw_line(Vector2(6, ground), Vector2(size.x - 6, ground), Color(0.45, 1.0, 0.65, 0.8 if alive else 0.25), 2.0)
		# speed streaks once it gets fast
		if alive and speed > START_SPEED * 1.8:
			for k in 4:
				var sx := fposmod(-_scroll * 1.6 + k * 190.0, size.x)
				draw_line(Vector2(sx, top + 24 + k * 13), Vector2(sx + 40, top + 24 + k * 13), Color(1, 1, 1, 0.08), 2.0)
		for tr in lane["trees"]:
			shadow(Vector2(tr["x"] + tree_w * 0.5, ground + 2), tree_w * 0.5, 4.0)
			draw_texture_rect(TREE_TEX, Rect2(tr["x"], ground - TREE_H, tree_w, TREE_H), false,
				Color(0.85, 0.9, 1.0) if alive else Color(1, 1, 1, 0.35))
		for d in lane["dust"]:
			draw_circle(Vector2(d["p"].x, ground + d["p"].y), 3.5, Color(0.85, 0.85, 1.0, d["life"] * 1.6))
		var c := Vector2(RUN_X, ground - R + lane["y"])
		var height := clampf(-float(lane["y"]) / 90.0, 0.0, 1.0)
		shadow(Vector2(RUN_X, ground + 1), R * (1.0 - height * 0.5), 5.0, 0.45 * (1.0 - height * 0.6))
		draw_spirit(lane, c, R, Color.WHITE if alive else Color(1, 1, 1, 0.4), lane["squash"], 1.0 if alive else 0.0)
		var status := "✗ OUT — %s · %.1fs" % [ORDINAL[clampi(lane["out_pos"] - 1, 0, 5)], float(lane["time"])] if not alive else ""
		nameplate(lane, Vector2(12, top + 8), status)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if running:
		var hud := "⏱ %.1fs   🏆 %.1fs   ×%.1f" % [t, record, speed / START_SPEED]
		var w := text_width(hud, 13) + 20
		rrect(Rect2(size.x - w - 90, 8, w, 22), Color(0.05, 0.04, 0.12, 0.7), 11)
		text(Vector2(size.x - w - 80, 24), hud, 13, UIKit.GOLD if record > 0.0 and t > record else Color(1, 1, 1, 0.85), -1, 0)
