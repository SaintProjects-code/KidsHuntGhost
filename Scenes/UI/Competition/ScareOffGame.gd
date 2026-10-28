extends CompGame
## 😱 Scare-Off (NEW) — a button-mash race. Each spirit faces a pumpkin-headed
## scarecrow; MASH your ACTION key (or click your lane) to puff up and fill the
## fright meter. It drains if you stop. Fill it first and BOO! — the scarecrow
## runs for it. ATK = how much each press scares, DEF = how slowly the meter
## drains. 12 seconds, then the fullest meter wins.

const LANE_H := 92.0
const VIEW_W := 720.0
const GOAL := 100.0
const DRAIN := 7.0           # meter lost per second
const TIME_LIMIT := 12.0

func _init_game() -> void:
	record_key = "scare_off"
	record_lower_better = true   # fastest BOO
	custom_minimum_size = Vector2(VIEW_W, LANE_H * lanes.size())
	for lane in lanes:
		var atk := int(lane["spirit"].get("atk", 2))
		lane.merge({
			"meter": 0.0, "power": 3.0 + atk * 0.6,
			"drain": DRAIN * (1.25 - int(lane["spirit"].get("def", 2)) * 0.07),   # DEF 1 → ×1.18 … 6 → ×0.83
			"done_t": -1.0, "pulse": 0.0,
			"run_x": 0.0, "boo_t": 0.0,
			# CPU masher: presses per second with a little rhythm wobble
			"rate": randf_range(6.0, 9.0), "next": randf_range(0.05, 0.2),
		})

func _tick(delta: float) -> void:
	for lane in lanes:
		lane["pulse"] = maxf(0.0, lane["pulse"] - delta * 6.0)
		if lane["done_t"] >= 0.0:
			lane["boo_t"] += delta
			lane["run_x"] += delta * 420.0
			continue
		lane["meter"] = maxf(0.0, lane["meter"] - lane["drain"] * delta)
		if not lane["human"]:
			lane["next"] -= delta
			if lane["next"] <= 0.0:
				lane["next"] = 1.0 / (lane["rate"] * randf_range(0.8, 1.2))
				_press(lane)
	var all_done := lanes.all(func(l): return l["done_t"] >= 0.0)
	if all_done or t > TIME_LIMIT:
		var winner := _lane_by_idx(ranks()[0])
		result_value = float(winner["done_t"]) if winner["done_t"] >= 0.0 else 0.0
		finish()

func _press(lane: Dictionary) -> void:
	if lane["done_t"] >= 0.0:
		return
	lane["meter"] = minf(GOAL, lane["meter"] + lane["power"])
	lane["pulse"] = 1.0
	if lane["human"]:
		Sfx.play("pop", 0.7 + lane["meter"] / GOAL * 0.8, -6.0)
	if lane["meter"] >= GOAL:
		lane["done_t"] = t
		Sfx.play("boo")

func _on_action(lane: Dictionary, action: String) -> void:
	if action == "action":
		_press(lane)

# Finished first, then by fullest meter.
func ranks() -> Array:
	var sorted := lanes.duplicate()
	sorted.sort_custom(func(a, b):
		var da: bool = a["done_t"] >= 0.0
		var db: bool = b["done_t"] >= 0.0
		if da and db:
			return a["done_t"] < b["done_t"]
		if da != db:
			return da
		return a["meter"] > b["meter"])
	return sorted.map(func(l): return l["idx"])

func result_text() -> String:
	var best := _lane_by_idx(ranks()[0])
	if best["done_t"] >= 0.0:
		return "😱 %s scares it off in %.1fs!" % [best["name"], best["done_t"]]
	return "😱 %s was scariest!" % best["name"]

func _draw_game() -> void:
	for i in lanes.size():
		var lane: Dictionary = lanes[i]
		var top := i * LANE_H
		var card := Rect2(4, top + 3, size.x - 8, LANE_H - 6)
		var mid := top + LANE_H * 0.6
		var fill: float = lane["meter"] / GOAL
		# dusk pumpkin patch; the sky reddens as the fright builds
		lane_card(lane, card, Color("2a1236").lerp(Color("4a0f1a"), fill), Color("8a3a1a").lerp(Color("c2401a"), fill))
		draw_circle(Vector2(size.x * 0.62, top + LANE_H - 8), 120, Color(1, 0.6, 0.2, 0.08))
		grad_rect(Rect2(7, top + LANE_H - 22, size.x - 14, 17), Color(0.16, 0.08, 0.04), Color(0.08, 0.04, 0.02))
		for k in 6:   # little pumpkins in the patch
			var px := 220.0 + k * 62.0
			draw_circle(Vector2(px, top + LANE_H - 16), 6, Color(0.9, 0.45, 0.1, 0.7))
		var grow: float = 1.0 + fill * 0.7 + lane["pulse"] * 0.12
		var shake := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * fill * 3.0
		shadow(Vector2(90, top + LANE_H - 14), 22 * grow, 5)
		draw_spirit(lane, Vector2(90, mid - 6) + shake, 20.0 * grow, Color.WHITE, Vector2.ONE, 0.6 + fill)
		# fright meter with tick marks
		var bar := Rect2(150, mid - 20, 320, 18)
		pill_bar(bar, fill, Color("8a4dff"), Color("ff4a3a"))
		for k in range(1, 4):
			var tx := bar.position.x + bar.size.x * k / 4.0
			draw_line(Vector2(tx, bar.position.y + 3), Vector2(tx, bar.end.y - 3), Color(1, 1, 1, 0.2), 1.0)
		if fill > 0.85 and lane["done_t"] < 0.0:
			glow(Vector2(bar.end.x, bar.get_center().y), 14, Color(1, 0.4, 0.2, 0.8), 5)
		# the scarecrow trembles, then flees
		var sx: float = 590.0 + lane["run_x"]
		if sx < size.x + 40:
			var base := Vector2(sx, mid) + Vector2(randf_range(-1, 1), 0) * fill * 5.0
			shadow(Vector2(sx, top + LANE_H - 14), 18, 4)
			draw_line(base + Vector2(0, -4), base + Vector2(0, 24), Color(0.5, 0.33, 0.16), 4.0)
			draw_line(base + Vector2(-20, 6), base + Vector2(20, 6), Color(0.5, 0.33, 0.16), 4.0)
			glow(base + Vector2(0, -18), 14, Color(1, 0.6, 0.2, 0.5 + fill * 0.5), 4)
			draw_circle(base + Vector2(0, -18), 15, Color(0.95, 0.5, 0.1))
			draw_circle(base + Vector2(-5, -22), 5, Color(1, 0.7, 0.35, 0.5))   # highlight
			draw_rect(Rect2(base + Vector2(-2, -36), Vector2(4, 5)), Color(0.3, 0.5, 0.15))
			var eye := Color(1, 0.9, 0.3) if fill > 0.5 else Color.BLACK
			draw_colored_polygon(PackedVector2Array([base + Vector2(-9, -23), base + Vector2(-3, -23), base + Vector2(-6, -17)]), eye)
			draw_colored_polygon(PackedVector2Array([base + Vector2(3, -23), base + Vector2(9, -23), base + Vector2(6, -17)]), eye)
			draw_rect(Rect2(base + Vector2(-6, -13), Vector2(12, 3.0 + fill * 6.0)), Color.BLACK)
		if lane["done_t"] >= 0.0 and lane["boo_t"] < 1.2:
			var a: float = 1.0 - lane["boo_t"] / 1.2
			glow(Vector2(300, mid - 12), 40 + lane["boo_t"] * 40, Color(1, 1, 1, a * 0.6), 6)
			text(Vector2(180, mid + 2), "BOO!", int(34 + lane["boo_t"] * 24), Color(1, 1, 1, a), 240, 8)
		var status: String = "BOO! %.1fs" % lane["done_t"] if lane["done_t"] >= 0.0 else "MASH!  %d%%" % int(fill * 100)
		nameplate(lane, Vector2(12, top + 8), status)
	if running:
		rrect(Rect2(size.x - 104, 8, 92, 22), Color(0.05, 0.04, 0.12, 0.7), 11)
		text(Vector2(size.x - 104, 24), "⏱ %.1f" % maxf(0.0, TIME_LIMIT - t), 13, Color.WHITE, 92, 0)
