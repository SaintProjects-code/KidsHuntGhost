extends CompGame
## 📸 Ghost Snap (NEW) — a timing game. A ghost flits back and forth across
## each lane; press your ACTION key (or click the lane) to snap a photo when
## it's inside your camera frame. Dead centre = PERFECT (3), inside = NICE (2),
## half in = BLURRY (1), else MISS. Five shots each; the ghost speeds up and
## jinks after every shot. SPD gives a wider frame; a high HP tier is a calm
## presence that keeps the ghost slower.
## Most points wins (ties: whoever finished first).

const LANE_H := 92.0
const VIEW_W := 720.0
const SHOTS := 5
const COOLDOWN := 0.55
const GHOST_R := 20.0
const TIME_LIMIT := 30.0

func _init_game() -> void:
	record_key = "ghost_snap"
	custom_minimum_size = Vector2(VIEW_W, LANE_H * lanes.size())
	for lane in lanes:
		var spd := int(lane["spirit"].get("spd", 2))
		var calm := 1.12 - int(lane["spirit"].get("hp_stat", 2)) * 0.04   # HP 1 → ×1.08 … 6 → ×0.88
		lane.merge({
			"gx": randf_range(120, VIEW_W - 120), "dir": [-1.0, 1.0].pick_random(),
			"speed": randf_range(170, 210) * calm, "wobble": randf() * TAU,
			"frame_w": 52.0 + spd * 7.0, "shots": [], "cool": 0.0, "done_t": -1.0,
			"flash": 0.0, "pop": "", "pop_t": 0.0,
			# CPU photographer: how close to centre it waits for, and its reflexes
			"aim": randf_range(0.15, 0.55), "react": randf_range(0.05, 0.16), "wait": 0.0,
		})

func _frame_x() -> float:
	return VIEW_W * 0.5

func _tick(delta: float) -> void:
	for lane in lanes:
		lane["flash"] = maxf(0.0, lane["flash"] - delta * 3.0)
		lane["pop_t"] = maxf(0.0, lane["pop_t"] - delta)
		if lane["shots"].size() >= SHOTS:
			continue
		lane["cool"] = maxf(0.0, lane["cool"] - delta)
		lane["wobble"] += delta * 3.0
		lane["gx"] += lane["dir"] * lane["speed"] * delta
		if lane["gx"] < 60 or lane["gx"] > VIEW_W - 60:
			lane["dir"] *= -1.0
			lane["gx"] = clampf(lane["gx"], 60, VIEW_W - 60)
		if not lane["human"]:
			_cpu(lane, delta)
	if t > TIME_LIMIT:
		for lane in lanes:
			while lane["shots"].size() < SHOTS:
				lane["shots"].append(0)
	if lanes.all(func(l): return l["shots"].size() >= SHOTS):
		result_value = float(_score(_lane_by_idx(ranks()[0])))
		finish()

# CPU: once the ghost is close enough to centre, shoot after its reaction time.
func _cpu(lane: Dictionary, delta: float) -> void:
	if lane["cool"] > 0.0:
		return
	var off: float = absf(lane["gx"] - _frame_x()) / (lane["frame_w"] * 0.5)
	if lane["wait"] > 0.0:
		lane["wait"] -= delta
		if lane["wait"] <= 0.0:
			_snap(lane)
	elif off < lane["aim"] + randf_range(0.0, 0.3):
		lane["wait"] = lane["react"]

func _on_action(lane: Dictionary, action: String) -> void:
	if action == "action" and lane["cool"] <= 0.0 and lane["shots"].size() < SHOTS:
		_snap(lane)

func _snap(lane: Dictionary) -> void:
	var off: float = absf(lane["gx"] - _frame_x())
	var half: float = lane["frame_w"] * 0.5
	var pts := 0
	if off < half * 0.25:
		pts = 3
	elif off < half:
		pts = 2
	elif off < half + GHOST_R:
		pts = 1
	lane["shots"].append(pts)
	lane["pop"] = ["MISS", "BLURRY", "NICE!", "PERFECT!"][pts]
	lane["pop_t"] = 0.8
	lane["flash"] = 1.0
	lane["cool"] = COOLDOWN
	lane["wait"] = 0.0
	# the ghost gets jumpier after every photo
	lane["speed"] *= randf_range(1.1, 1.22)
	if randf() < 0.5:
		lane["dir"] *= -1.0
	Sfx.play("shutter")
	if pts == 3:
		Sfx.play("collect")
	if lane["shots"].size() >= SHOTS:
		lane["done_t"] = t

func _score(lane: Dictionary) -> int:
	var n := 0
	for s in lane["shots"]:
		n += int(s)
	return n

func ranks() -> Array:
	var sorted := lanes.duplicate()
	sorted.sort_custom(func(a, b):
		var sa := _score(a)
		var sb := _score(b)
		return sa > sb if sa != sb else float(a["done_t"]) < float(b["done_t"]))
	return sorted.map(func(l): return l["idx"])

func result_text() -> String:
	var best := _lane_by_idx(ranks()[0])
	return "📸 %s wins with %d points!" % [best["name"], _score(best)]

func _draw_game() -> void:
	var font := ThemeDB.fallback_font
	for i in lanes.size():
		var lane: Dictionary = lanes[i]
		var top := i * LANE_H
		draw_rect(Rect2(0, top + 2, size.x, LANE_H - 4), Color(0.06, 0.08, 0.14))
		# drifting fog bands
		for k in 3:
			var fx := fposmod(t * (20 + k * 9) + k * 230, size.x + 200) - 100
			draw_rect(Rect2(fx, top + 30 + k * 16, 160, 10), Color(0.6, 0.65, 0.8, 0.06))
		# the camera frame: four corner brackets
		var fw: float = lane["frame_w"]
		var fr := Rect2(_frame_x() - fw * 0.5, top + 26, fw, LANE_H - 36)
		var col := Color(1, 1, 1, 0.85)
		var l := 12.0
		for corner in [fr.position, Vector2(fr.end.x, fr.position.y), Vector2(fr.position.x, fr.end.y), fr.end]:
			var sx := 1.0 if corner.x == fr.position.x else -1.0
			var sy := 1.0 if corner.y == fr.position.y else -1.0
			draw_line(corner, corner + Vector2(l * sx, 0), col, 2.0)
			draw_line(corner, corner + Vector2(0, l * sy), col, 2.0)
		draw_circle(Vector2(_frame_x(), fr.get_center().y), 2.0, Color(1, 0.3, 0.3, 0.8))
		# the ghost (translucent, bobbing)
		if lane["shots"].size() < SHOTS:
			var g := Vector2(lane["gx"], fr.get_center().y + sin(lane["wobble"]) * 8.0)
			var tint := Color(1, 1, 1, 0.55 + 0.3 * sin(lane["wobble"] * 2.0))
			if lane["tex"]:
				draw_texture_rect(lane["tex"], Rect2(g - Vector2(GHOST_R, GHOST_R) * 1.2, Vector2(GHOST_R, GHOST_R) * 2.4), false, tint)
		# camera flash
		if lane["flash"] > 0.0:
			draw_rect(Rect2(0, top + 2, size.x, LANE_H - 4), Color(1, 1, 1, lane["flash"] * 0.6))
		# film strip of results
		for s in SHOTS:
			var p := Vector2(size.x - 24 - (SHOTS - 1 - s) * 22, top + 14)
			var shot: int = lane["shots"][s] if s < lane["shots"].size() else -1
			draw_rect(Rect2(p - Vector2(9, 7), Vector2(18, 14)), Color(0.2, 0.2, 0.25))
			if shot >= 0:
				var sc: Color = [Color(0.5, 0.2, 0.2), Color(0.6, 0.6, 0.4), Color(0.4, 0.8, 0.5), UIKit.GOLD][shot]
				draw_rect(Rect2(p - Vector2(7, 5), Vector2(14, 10)), sc)
		if lane["pop_t"] > 0.0:
			draw_string(font, Vector2(_frame_x() - 60, top + 22 - (0.8 - lane["pop_t"]) * 18), lane["pop"],
				HORIZONTAL_ALIGNMENT_CENTER, 120, 18, Color(UIKit.GOLD, lane["pop_t"] / 0.8))
		lane_label(lane, i, "📷 %d   shots %d/%d" % [_score(lane), lane["shots"].size(), SHOTS], LANE_H)
