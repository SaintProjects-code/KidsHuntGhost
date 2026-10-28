extends CompGame
## 😱 Scare-Off (NEW) — a button-mash race. Each spirit faces a pumpkin-headed
## scarecrow; MASH your ACTION key (or click your lane) to puff up and fill the
## fright meter. It drains if you stop. Fill it first and BOO! — the scarecrow
## runs for it. ATK = how much each press scares, DEF = how slowly the meter
## drains. 12 seconds, then the fullest meter wins.

const GOAL := 100.0
const DRAIN := 7.0           # meter lost per second
const TIME_LIMIT := 12.0

func _init_game() -> void:
	record_key = "scare_off"
	record_lower_better = true   # fastest BOO
	layout = Layout.COLUMNS
	how_to = "MASH your key to puff up and fill the fright meter. Fill it first — BOO!"
	custom_minimum_size = Vector2(640, 440)
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
			lane["run_x"] += delta * 520.0   # the scarecrow flies up and away
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

func keys_text(lane: Dictionary) -> String:
	return "MASH %s (or click your column fast)" % Controls.key_name(lane["slot"], "action")

func _draw_game() -> void:
	for i in lanes.size():
		var lane: Dictionary = lanes[i]
		var r := lane_rect(i)
		var fill: float = lane["meter"] / GOAL
		var cx := r.get_center().x - 14.0
		# dusk sky reddens as the fright builds
		lane_card(lane, r, Color("2a1236").lerp(Color("4a0f1a"), fill), Color("8a3a1a").lerp(Color("c2401a"), fill))
		draw_circle(Vector2(cx, r.end.y), r.size.x * 0.7, Color(1, 0.6, 0.2, 0.06))
		grad_rect(Rect2(r.position.x + 4, r.end.y - 34, r.size.x - 8, 30), Color(0.16, 0.08, 0.04), Color(0.08, 0.04, 0.02))
		for k in 4:   # pumpkins in the patch
			draw_circle(Vector2(r.position.x + 16 + k * (r.size.x - 50) / 3.0, r.end.y - 16), 6, Color(0.9, 0.45, 0.1, 0.7))
		# the scarecrow near the top: trembles, then flies off
		var sy: float = r.position.y + 110.0 - lane["run_x"]
		if sy > r.position.y - 60:
			var base := Vector2(cx, sy) + Vector2(randf_range(-1, 1), 0) * fill * 6.0
			draw_line(base + Vector2(0, -4), base + Vector2(0, 34), Color(0.5, 0.33, 0.16), 4.0)
			draw_line(base + Vector2(-24, 8), base + Vector2(24, 8), Color(0.5, 0.33, 0.16), 4.0)
			glow(base + Vector2(0, -22), 16, Color(1, 0.6, 0.2, 0.5 + fill * 0.5), 4)
			draw_circle(base + Vector2(0, -22), 18, Color(0.95, 0.5, 0.1))
			draw_circle(base + Vector2(-6, -27), 6, Color(1, 0.7, 0.35, 0.5))
			draw_rect(Rect2(base + Vector2(-2, -44), Vector2(4, 6)), Color(0.3, 0.5, 0.15))
			var eye := Color(1, 0.9, 0.3) if fill > 0.5 else Color.BLACK
			draw_colored_polygon(PackedVector2Array([base + Vector2(-10, -28), base + Vector2(-3, -28), base + Vector2(-6, -21)]), eye)
			draw_colored_polygon(PackedVector2Array([base + Vector2(3, -28), base + Vector2(10, -28), base + Vector2(6, -21)]), eye)
			draw_rect(Rect2(base + Vector2(-7, -16), Vector2(14, 3.0 + fill * 7.0)), Color.BLACK)
		# your spirit at the bottom puffs up
		var grow: float = 1.0 + fill * 0.9 + lane["pulse"] * 0.15
		var me := Vector2(cx, r.end.y - 70) + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * fill * 3.0
		shadow(Vector2(cx, r.end.y - 38), 24 * grow, 6)
		draw_spirit(lane, me, 22.0 * grow, Color.WHITE, Vector2.ONE, 0.6 + fill)
		# tall fright meter on the right, filling upward
		var bar := Rect2(r.end.x - 26, r.position.y + 64, 16, r.size.y - 110)
		rrect(bar, Color(0, 0, 0, 0.55), 8, 1, Color(1, 1, 1, 0.18))
		if fill > 0.0:
			var h := (bar.size.y - 4) * fill
			rrect(Rect2(bar.position.x + 2, bar.end.y - 2 - h, bar.size.x - 4, h), Color("8a4dff").lerp(Color("ff4a3a"), fill), 6)
		if fill > 0.85 and lane["done_t"] < 0.0:
			glow(Vector2(bar.get_center().x, bar.position.y), 14, Color(1, 0.4, 0.2, 0.8), 5)
		if lane["done_t"] >= 0.0 and lane["boo_t"] < 1.4:
			var a: float = 1.0 - lane["boo_t"] / 1.4
			glow(me, 50 + lane["boo_t"] * 60, Color(1, 1, 1, a * 0.5), 6)
			text(Vector2(r.position.x, me.y - 60), "BOO!", int(36 + lane["boo_t"] * 26), Color(1, 1, 1, a), r.size.x, 8)
		var status: String = "BOO! %.1fs" % lane["done_t"] if lane["done_t"] >= 0.0 else "%d%%" % int(fill * 100)
		var label: String = "%s %s  %s" % [lane["name"], key_hint(lane), status]
		var w := minf(r.size.x - 12, text_width(label, 13) + 24)
		var pr := Rect2(r.get_center().x - w * 0.5, r.position.y + 30, w, 22)
		rrect(pr, Color(0.05, 0.04, 0.12, 0.75), 11, 1, Color(lane["color"], 0.6))
		text(Vector2(pr.position.x, pr.position.y + 16), label, 13, lane["color"].lightened(0.3), pr.size.x, 0)
	if running:
		rrect(Rect2(size.x * 0.5 - 46, 4, 92, 22), Color(0.05, 0.04, 0.12, 0.75), 11)
		text(Vector2(size.x * 0.5 - 46, 20), "⏱ %.1f" % maxf(0.0, TIME_LIMIT - t), 13, Color.WHITE, 92, 0)
