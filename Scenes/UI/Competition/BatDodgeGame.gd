extends CompGame
## 🦇 Bat Dodge — survival. Bats swoop down your column in three lanes; jump
## to LEFT / MIDDLE / RIGHT to dodge. Each hit costs a heart; the last spirit
## flying (or the most hearts left after 25s) wins. SPD = quicker CPU dodges,
## DEF = an extra heart.

const TIME_LIMIT := 25.0
const LANE_KEYS := ["left", "middle", "right"]

func _init_game() -> void:
	record_key = "bat_dodge"
	layout = Layout.COLUMNS
	how_to = "Move LEFT / MIDDLE / RIGHT to dodge the bats. Last one flying wins!"
	custom_minimum_size = Vector2(640, 440)
	for lane in lanes:
		var s: Dictionary = lane["spirit"]
		lane.merge({"pos": 1, "hearts": 2 + (1 if int(s.get("def", 2)) >= 4 else 0), "out_t": -1.0,
			"bats": [], "spawn": randf_range(0.4, 0.9), "hurt": 0.0,
			"skill": 0.62 + int(s.get("spd", 2)) * 0.05})

func _speed() -> float:
	return 0.55 + t * 0.045   # column-heights per second, ramping up

func _tick(delta: float) -> void:
	for lane in lanes:
		lane["hurt"] = maxf(0.0, lane["hurt"] - delta * 3.0)
		if lane["out_t"] >= 0.0:
			continue
		lane["spawn"] -= delta
		if lane["spawn"] <= 0.0:
			lane["spawn"] = maxf(0.35, 1.0 - t * 0.025) * randf_range(0.8, 1.2)
			lane["bats"].append({"col": randi() % 3, "y": 0.0, "seen": false})
		for bat in lane["bats"]:
			bat["y"] += _speed() * delta
			# CPUs notice a bat coming at them partway down, and may dodge
			if not lane["human"] and not bat["seen"] and bat["y"] > 0.55 and bat["col"] == lane["pos"]:
				bat["seen"] = true
				if randf() < lane["skill"]:
					lane["pos"] = (lane["pos"] + [1, 2].pick_random()) % 3
		for bat in lane["bats"].duplicate():
			if bat["y"] >= 0.92 and bat["y"] < 1.0 and bat["col"] == lane["pos"]:
				lane["bats"].erase(bat)
				lane["hearts"] -= 1
				lane["hurt"] = 1.0
				Sfx.play("escape")
				if lane["hearts"] <= 0:
					lane["out_t"] = t
			elif bat["y"] >= 1.1:
				lane["bats"].erase(bat)
	var alive := lanes.filter(func(l): return l["out_t"] < 0.0)
	if alive.size() <= (0 if lanes.size() == 1 else 1) or t >= TIME_LIMIT:
		result_value = t
		finish()

func _on_action(lane: Dictionary, action: String) -> void:
	var k := LANE_KEYS.find(action)
	if k >= 0 and lane["out_t"] < 0.0:
		lane["pos"] = k

# Tapping a column picks the lane under the finger (left / middle / right third).
func _gui_input(ev: InputEvent) -> void:
	var pressed: bool = (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT) \
		or (ev is InputEventScreenTouch and ev.pressed)
	if not pressed or not running:
		return
	var i := lane_at(ev.position)
	if i >= 0 and lanes[i]["human"]:
		var r := lane_rect(i)
		_on_action(lanes[i], LANE_KEYS[clampi(int((ev.position.x - r.position.x) / r.size.x * 3.0), 0, 2)])

func ranks() -> Array:
	var sorted := lanes.duplicate()
	sorted.sort_custom(func(a, b):
		var ta: float = 999.0 if a["out_t"] < 0.0 else a["out_t"]
		var tb: float = 999.0 if b["out_t"] < 0.0 else b["out_t"]
		if ta != tb:
			return ta > tb
		return a["hearts"] > b["hearts"])
	return sorted.map(func(l): return l["idx"])

func result_text() -> String:
	return "🦇 %s dodged them all!" % _lane_by_idx(ranks()[0])["name"]

func keys_text(lane: Dictionary) -> String:
	return "%s / %s / %s to move (or tap a third of your column)" % [Controls.key_name(lane["slot"], "left"),
		Controls.key_name(lane["slot"], "middle"), Controls.key_name(lane["slot"], "right")]

func _draw_game() -> void:
	for i in lanes.size():
		var lane: Dictionary = lanes[i]
		var r := lane_rect(i)
		lane_card(lane, r, Color("0b1030"), Color("2a1446"))
		var field := Rect2(r.position.x + 8, r.position.y + 60, r.size.x - 16, r.size.y - 70)
		var cw := field.size.x / 3.0
		for k in 3:
			draw_rect(Rect2(field.position.x + k * cw + 2, field.position.y, cw - 4, field.size.y), Color(1, 1, 1, 0.03 + (0.04 if k == lane["pos"] else 0.0)))
		for bat in lane["bats"]:
			var p := Vector2(field.position.x + (bat["col"] + 0.5) * cw, field.position.y + bat["y"] * field.size.y)
			var flap := sin(t * 18.0 + bat["col"]) * 6.0
			draw_colored_polygon(PackedVector2Array([p, p + Vector2(-16, -6 + flap), p + Vector2(-6, 2)]), Color(0.1, 0.05, 0.15))
			draw_colored_polygon(PackedVector2Array([p, p + Vector2(16, -6 + flap), p + Vector2(6, 2)]), Color(0.1, 0.05, 0.15))
			draw_circle(p, 6, Color(0.18, 0.08, 0.25))
			draw_circle(p + Vector2(-2, -1), 1.5, Color(1, 0.3, 0.3))
			draw_circle(p + Vector2(2, -1), 1.5, Color(1, 0.3, 0.3))
		var me := Vector2(field.position.x + (lane["pos"] + 0.5) * cw, field.position.y + field.size.y * 0.95)
		var tint := Color(1, 0.5, 0.5) if lane["hurt"] > 0.0 else (Color(1, 1, 1, 0.3) if lane["out_t"] >= 0.0 else Color.WHITE)
		draw_spirit(lane, me, minf(18.0, cw * 0.35), tint)
		nameplate(lane, r.position + Vector2(8, 30), "♥".repeat(maxi(0, lane["hearts"])) if lane["out_t"] < 0.0 else "out")
	if running:
		rrect(Rect2(size.x * 0.5 - 46, 4, 92, 22), Color(0.05, 0.04, 0.12, 0.75), 11)
		text(Vector2(size.x * 0.5 - 46, 20), "⏱ %.1f" % maxf(0.0, TIME_LIMIT - t), 13, Color.WHITE, 92, 0)

# ── 3D (3D maps) ──────────────────────────────────────────────────────────────
# Each player's lane is a long track with three sub-lanes; bats fly in from
# the far end (their `y` 0 → 1 is far → the spirit) and the spirit hops.
const SUB := 1.4
const FAR := -24.0
const NEAR := 4.0

func _build_3d(v) -> void:
	var gap := 5.6
	v.sky(Color("1a1538"), 0.6)
	v.aim(Vector3(0, 9 + lanes.size() * 1.0, 15 + lanes.size() * 2.6), Vector3(0, 0, -5))
	for i in lanes.size():
		var lane: Dictionary = lanes[i]
		var cx: float = v.lane_x(i, lanes.size(), gap)
		v.box(Vector3(4.2, 0.2, 30), Color("2a2450"), Vector3(cx, -0.1, -9))
		for lx in [-0.7, 0.7]:
			v.box(Vector3(0.05, 0.03, 30), Color("6a62b0"), Vector3(cx + lx, 0.01, -9), true)
		lane["n3"] = v.spirit(lane["tex"], lane["color"], Vector3(cx, 0, NEAR), 0.032)
		lane["cx3"] = cx
		lane["bat3"] = []   # [bat dict, node] pairs (a bat's fields change, so not a dict key)
		var l := lane
		v.tag(lane["n3"], func(): return "%s %s  %s" % [l["name"], key_hint(l), "OUT" if l["out_t"] >= 0.0 else "♥".repeat(maxi(0, l["hearts"]))],
			lane["color"].lightened(0.2), 2.4, 15)

func _bat_node(v) -> Node3D:
	var b := Node3D.new()
	v.world.add_child(b)
	v.ball(0.3, Color("2a1a3a"), Vector3.ZERO, false, b)
	for side in [-1, 1]:
		v.box(Vector3(0.8, 0.06, 0.4), Color("4a2a66"), Vector3(side * 0.5, 0, 0), false, b)
	return b

func _update_3d(v, delta: float) -> void:
	for lane in lanes:
		var pairs: Array = lane["bat3"]
		for bat in lane["bats"]:
			bat["_seen3"] = Engine.get_process_frames()
			if not bat.has("_n3"):
				bat["_n3"] = _bat_node(v)
				pairs.append([bat, bat["_n3"]])
			var b: Node3D = bat["_n3"]
			b.position = Vector3(lane["cx3"] + (bat["col"] - 1) * SUB, 1.0, FAR + bat["y"] / 0.92 * (NEAR - FAR))
			b.get_child(1).rotation.z = sin(t * 22.0) * 0.6
			b.get_child(2).rotation.z = -sin(t * 22.0) * 0.6
		for pr in pairs.duplicate():
			if pr[0].get("_seen3", -1) != Engine.get_process_frames():
				pr[1].queue_free()
				pairs.erase(pr)
		var n: Node3D = lane["n3"]
		n.position.x = lerpf(n.position.x, lane["cx3"] + (lane["pos"] - 1) * SUB, minf(1.0, delta * 14.0))
		n.position.y = absf(sin(t * 8.0 + lane["idx"])) * 0.25 + lane["hurt"] * 0.6
		var spr: Sprite3D = v.sprite_of(n)
		spr.modulate = Color(0.4, 0.4, 0.45, 0.6) if lane["out_t"] >= 0.0 else (Color(1.6, 0.6, 0.6) if lane["hurt"] > 0.5 else Color.WHITE)
		if lane["hurt"] > 0.95:
			v.pop(n, "−1 ♥", Color("ff6a6a"))
