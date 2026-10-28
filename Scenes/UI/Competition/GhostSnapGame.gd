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
	for i in lanes.size():
		var lane: Dictionary = lanes[i]
		var top := i * LANE_H
		var card := Rect2(4, top + 3, size.x - 8, LANE_H - 6)
		lane_card(lane, card, Color("0e1a2a"), Color("1f3a3f"))
		# misty forest: trunk silhouettes + drifting fog bands
		for k in 9:
			var tx := fposmod(k * 97.0 + 30.0, size.x - 40) + 20
			draw_rect(Rect2(tx, top + 30, 7, LANE_H - 36), Color(0.03, 0.07, 0.09, 0.7))
		for k in 3:
			var fx := fposmod(t * (18 + k * 9) + k * 230, size.x + 220) - 110
			draw_circle(Vector2(fx, top + 48 + k * 12), 40, Color(0.75, 0.85, 0.95, 0.05))
			draw_circle(Vector2(fx + 50, top + 52 + k * 10), 30, Color(0.75, 0.85, 0.95, 0.04))
		var fw: float = lane["frame_w"]
		var fr := Rect2(_frame_x() - fw * 0.5, top + 30, fw, LANE_H - 40)
		var ghost_in: bool = lane["shots"].size() < SHOTS and absf(lane["gx"] - _frame_x()) < fw * 0.5
		var fcol := Color("7dffcf") if ghost_in else Color(1, 1, 1, 0.75)
		draw_rect(fr, Color(fcol, 0.06))
		var l := 13.0
		for corner in [fr.position, Vector2(fr.end.x, fr.position.y), Vector2(fr.position.x, fr.end.y), fr.end]:
			var sx := 1.0 if corner.x == fr.position.x else -1.0
			var sy := 1.0 if corner.y == fr.position.y else -1.0
			draw_line(corner, corner + Vector2(l * sx, 0), fcol, 3.0)
			draw_line(corner, corner + Vector2(0, l * sy), fcol, 3.0)
		draw_circle(fr.get_center(), 3.0, Color(1, 0.35, 0.35, 0.9))
		draw_arc(fr.get_center(), 8.0, 0, TAU, 20, Color(1, 0.35, 0.35, 0.5), 1.5)
		if lane["shots"].size() < SHOTS:
			var g := Vector2(lane["gx"], fr.get_center().y + sin(lane["wobble"]) * 8.0)
			var fade := 0.55 + 0.3 * sin(lane["wobble"] * 2.0)
			for k in 4:   # motion trail
				var tp: Vector2 = g - Vector2(lane["dir"] * (10 + k * 10), 0)
				draw_circle(tp, GHOST_R * (0.8 - k * 0.15), Color(0.7, 0.95, 1.0, 0.07))
			glow(g, GHOST_R * 1.2, Color(0.6, 0.9, 1.0, fade), 6)
			if lane["tex"]:
				draw_texture_rect(lane["tex"], Rect2(g - Vector2(GHOST_R, GHOST_R) * 1.2, Vector2(GHOST_R, GHOST_R) * 2.4),
					false, Color(1, 1, 1, fade))
		if lane["flash"] > 0.0:
			rrect(card.grow(-3), Color(1, 1, 1, lane["flash"] * 0.65), 12)
		# film strip
		var strip := Rect2(size.x - 26 - SHOTS * 24, top + 8, SHOTS * 24 + 12, 24)
		rrect(strip, Color(0.05, 0.04, 0.12, 0.75), 8)
		for k in SHOTS:
			var cell := Rect2(strip.position + Vector2(6 + k * 24, 4), Vector2(20, 16))
			var shot: int = lane["shots"][k] if k < lane["shots"].size() else -1
			rrect(cell, Color(1, 1, 1, 0.08), 4)
			if shot >= 0:
				var sc: Color = [Color("6b2a3a"), Color("8a8a5a"), Color("4fc98a"), UIKit.GOLD][shot]
				rrect(cell.grow(-2), sc, 3)
				if shot == 3:
					text(cell.position + Vector2(0, 13), "★", 12, Color.WHITE, cell.size.x, 0)
		if lane["pop_t"] > 0.0:
			var a: float = lane["pop_t"] / 0.8
			text(Vector2(_frame_x() - 80, top + 26 - (1.0 - a) * 16), lane["pop"], 20,
				Color(UIKit.GOLD if lane["pop"] == "PERFECT!" else Color.WHITE, a), 160, 5)
		nameplate(lane, Vector2(12, top + 8), "📷 %d pts · %d/%d" % [_score(lane), lane["shots"].size(), SHOTS])
