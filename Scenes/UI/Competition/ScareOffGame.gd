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
	var font := ThemeDB.fallback_font
	for i in lanes.size():
		var lane: Dictionary = lanes[i]
		var top := i * LANE_H
		var mid := top + LANE_H * 0.58
		draw_rect(Rect2(0, top + 2, size.x, LANE_H - 4), Color(0.13, 0.08, 0.05))
		draw_rect(Rect2(0, top + LANE_H - 14, size.x, 12), Color(0.22, 0.14, 0.06))   # field
		var fill: float = lane["meter"] / GOAL
		# your spirit puffs up as the meter fills
		var grow: float = 1.0 + fill * 0.7 + lane["pulse"] * 0.12
		var shake := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * fill * 3.0
		draw_spirit(lane, Vector2(90, mid) + shake, 22.0 * grow)
		# fright meter
		var bar := Rect2(150, mid - 9, 330, 18)
		draw_rect(bar, Color(0, 0, 0, 0.6))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * fill, bar.size.y)), Color(0.55, 0.2, 0.75).lerp(Color(1, 0.3, 0.2), fill))
		draw_rect(bar, Color(1, 1, 1, 0.5), false, 1.5)
		# the scarecrow trembles more as the meter fills, then flees
		var sx: float = 580.0 + lane["run_x"]
		var tremble := Vector2(randf_range(-1, 1), 0) * fill * 5.0
		if sx < size.x + 40:
			var base := Vector2(sx, mid) + tremble
			draw_line(base + Vector2(0, -6), base + Vector2(0, 26), Color(0.45, 0.3, 0.15), 4.0)
			draw_line(base + Vector2(-20, 6), base + Vector2(20, 6), Color(0.45, 0.3, 0.15), 4.0)
			draw_circle(base + Vector2(0, -18), 15, Color(0.95, 0.5, 0.1))
			draw_colored_polygon(PackedVector2Array([base + Vector2(-8, -22), base + Vector2(-3, -22), base + Vector2(-5, -17)]), Color.BLACK)
			draw_colored_polygon(PackedVector2Array([base + Vector2(3, -22), base + Vector2(8, -22), base + Vector2(5, -17)]), Color.BLACK)
			var mouth := 3.0 + fill * 6.0
			draw_rect(Rect2(base + Vector2(-6, -12), Vector2(12, mouth)), Color.BLACK)
		if lane["done_t"] >= 0.0 and lane["boo_t"] < 1.2:
			var fs := int(30 + lane["boo_t"] * 20)
			draw_string(font, Vector2(150, mid + 12), "BOO!", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 1.0 - lane["boo_t"] / 1.2))
		var status: String = "BOO! %.1fs" % lane["done_t"] if lane["done_t"] >= 0.0 else "%d%%" % int(fill * 100)
		lane_label(lane, i, "MASH!  " + status, LANE_H)
	if running:
		draw_string(font, Vector2(size.x - 120, 20), "⏱ %.1f" % maxf(0.0, TIME_LIMIT - t), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.75))
