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
	var font := ThemeDB.fallback_font
	var tree_w := _tree_w()
	for i in lanes.size():
		var lane: Dictionary = lanes[i]
		var top := i * LANE_H
		var ground := top + LANE_H - 10.0
		var shake := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * float(lane["shake"])
		draw_set_transform(shake, 0.0, Vector2.ONE)
		# night sky, stars, moon, rolling hills (parallax)
		var alive: bool = lane["alive"]
		draw_rect(Rect2(0, top + 2, size.x, LANE_H - 4), Color(0.07, 0.07, 0.17) if alive else Color(0.16, 0.08, 0.1))
		for s in _stars:
			var tw := 0.5 + 0.5 * sin(t * 3.0 + s.z)
			draw_circle(Vector2(fposmod(s.x - _scroll * 0.05, size.x), top + 6 + s.y * (LANE_H - 30)), 1.2, Color(1, 1, 1, 0.3 + 0.5 * tw))
		draw_circle(Vector2(size.x - 60, top + 22), 11, Color(1, 0.96, 0.8, 0.85))
		for hx in range(-1, 9):
			var x := fposmod(hx * 110.0 - _scroll * 0.25, size.x + 110.0) - 55.0
			draw_circle(Vector2(x, ground + 18), 46, Color(0.09, 0.16, 0.12))
		draw_line(Vector2(0, ground), Vector2(size.x, ground), Color(0.35, 0.65, 0.35) if alive else Color(0.4, 0.3, 0.3), 2.0)
		for tr in lane["trees"]:
			draw_texture_rect(TREE_TEX, Rect2(tr["x"], ground - TREE_H, tree_w, TREE_H), false,
				Color.WHITE if alive else Color(1, 1, 1, 0.4))
		for d in lane["dust"]:
			draw_circle(Vector2(d["p"].x, ground + d["p"].y), 3.0, Color(0.8, 0.8, 0.9, d["life"] * 2.0))
		var c := Vector2(RUN_X, ground - R + lane["y"])
		draw_spirit(lane, c, R, Color.WHITE if alive else Color(1, 1, 1, 0.35), lane["squash"])
		var extra := ""
		if not alive:
			extra = "✗ OUT — %s (%.1fs)" % [ORDINAL[clampi(lane["out_pos"] - 1, 0, 5)], float(lane["time"])]
		lane_label(lane, i, extra, LANE_H)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if running:
		var hud := "⏱ %.1fs   🏆 best %.1fs   speed ×%.1f" % [t, record, speed / START_SPEED]
		draw_string(font, Vector2(size.x - 300, 20), hud, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
			UIKit.GOLD if record > 0.0 and t > record else Color(1, 1, 1, 0.7))
