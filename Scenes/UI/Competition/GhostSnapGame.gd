extends CompGame
## 📸 Ghost Snap — a timing game in open space. Each player has a haunted
## panel where a ghost flits around in every direction; press your ACTION key
## (or click your panel) to snap a photo when it's inside your camera frame.
## Dead centre = PERFECT (3), inside = NICE (2), half in = BLURRY (1), else MISS.
## Five shots each; the ghost speeds up and jinks after every shot.
## SPD = a bigger frame; a high HP tier = a calmer (slower) ghost.
## Most points wins (ties: whoever finished first).

const SHOTS := 5
const COOLDOWN := 0.6
const GHOST_R := 0.07         # ghost radius, fraction of the panel's short side
const TIME_LIMIT := 32.0

func _init_game() -> void:
	layout = Layout.GRID
	record_key = "ghost_snap"
	how_to = "Snap the ghost when it's inside your frame! 5 shots — dead centre scores PERFECT."
	custom_minimum_size = Vector2(640, 440)
	for lane in lanes:
		var s: Dictionary = lane["spirit"]
		var calm := 1.12 - int(s.get("hp_stat", 2)) * 0.04   # HP 1 → ×1.08 … 6 → ×0.88
		var a := randf() * TAU
		lane.merge({
			"g": Vector2(randf_range(0.2, 0.8), randf_range(0.25, 0.8)),
			"v": Vector2(cos(a), sin(a)) * randf_range(0.32, 0.4) * calm,
			"frame": 0.2 + int(s.get("spd", 2)) * 0.022,       # half-size of the frame (fraction)
			"wobble": randf() * TAU, "shots": [], "cool": 0.0, "done_t": -1.0,
			"flash": 0.0, "pop": "", "pop_t": 0.0, "trail": [],
			"aim": randf_range(0.15, 0.5), "react": randf_range(0.05, 0.15), "wait": 0.0,
		})

func _tick(delta: float) -> void:
	for lane in lanes:
		lane["flash"] = maxf(0.0, lane["flash"] - delta * 3.0)
		lane["pop_t"] = maxf(0.0, lane["pop_t"] - delta)
		if lane["shots"].size() >= SHOTS:
			continue
		lane["cool"] = maxf(0.0, lane["cool"] - delta)
		lane["wobble"] += delta * 3.0
		# drift with a little curve; bounce off the panel walls
		var v: Vector2 = lane["v"].rotated(sin(lane["wobble"] * 0.7) * delta * 1.2)
		var g: Vector2 = lane["g"] + v * delta
		if g.x < 0.1 or g.x > 0.9:
			g.x = clampf(g.x, 0.1, 0.9)
			v.x *= -1.0
		if g.y < 0.22 or g.y > 0.82:
			g.y = clampf(g.y, 0.22, 0.82)
			v.y *= -1.0
		lane["v"] = v
		lane["g"] = g
		lane["trail"].push_front(g)
		if lane["trail"].size() > 6:
			lane["trail"].pop_back()
		if not lane["human"]:
			_cpu(lane, delta)
	if t > TIME_LIMIT:
		for lane in lanes:
			while lane["shots"].size() < SHOTS:
				lane["shots"].append(0)
	if lanes.all(func(l): return l["shots"].size() >= SHOTS):
		result_value = float(_score(_lane_by_idx(ranks()[0])))
		finish()

# Distance from the frame centre in frame half-sizes (0 = dead centre).
func _offset(lane: Dictionary) -> float:
	return (lane["g"] - Vector2(0.5, 0.52)).length() / lane["frame"]

func _cpu(lane: Dictionary, delta: float) -> void:
	if lane["cool"] > 0.0:
		return
	if lane["wait"] > 0.0:
		lane["wait"] -= delta
		if lane["wait"] <= 0.0:
			_snap(lane)
	elif _offset(lane) < lane["aim"] + randf_range(0.0, 0.3):
		lane["wait"] = lane["react"]

func _on_action(lane: Dictionary, action: String) -> void:
	if action == "action" and lane["cool"] <= 0.0 and lane["shots"].size() < SHOTS:
		_snap(lane)

func _snap(lane: Dictionary) -> void:
	var off := _offset(lane)
	var pts := 0
	if off < 0.3:
		pts = 3
	elif off < 1.0:
		pts = 2
	elif off < 1.0 + GHOST_R / lane["frame"]:
		pts = 1
	lane["shots"].append(pts)
	lane["pop"] = ["MISS", "BLURRY", "NICE!", "PERFECT!"][pts]
	lane["pop_t"] = 0.9
	lane["flash"] = 1.0
	lane["cool"] = COOLDOWN
	lane["wait"] = 0.0
	# jumpier after every photo: faster and a sharp turn
	lane["v"] = lane["v"].rotated(randf_range(-1.6, 1.6)) * randf_range(1.1, 1.2)
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
		var r := lane_rect(i)
		var short := minf(r.size.x, r.size.y)
		var at := func(n: Vector2) -> Vector2:
			return r.position + Vector2(n.x * r.size.x, n.y * r.size.y)
		lane_card(lane, r, Color("0e1a2a"), Color("1f3a3f"))
		for k in 7:   # haunted forest trunks
			var tx := r.position.x + fposmod(k * 97.0 + 30.0, r.size.x - 30) + 10
			draw_rect(Rect2(tx, r.position.y + 40, 8, r.size.y - 46), Color(0.03, 0.07, 0.09, 0.6))
		for k in 4:   # drifting fog
			var fx := r.position.x + fposmod(t * (16 + k * 8) + k * 160, r.size.x + 200) - 100
			draw_circle(Vector2(fx, r.position.y + r.size.y * (0.3 + k * 0.17)), 46, Color(0.75, 0.85, 0.95, 0.05))
		# the camera frame (square, centred)
		var c: Vector2 = at.call(Vector2(0.5, 0.52))
		var half: float = lane["frame"] * short
		var fr := Rect2(c - Vector2(half, half), Vector2(half, half) * 2.0)
		var ghost_in: bool = lane["shots"].size() < SHOTS and _offset(lane) < 1.0
		var fcol := Color("7dffcf") if ghost_in else Color(1, 1, 1, 0.75)
		draw_rect(fr, Color(fcol, 0.05))
		var l := half * 0.3
		for corner in [fr.position, Vector2(fr.end.x, fr.position.y), Vector2(fr.position.x, fr.end.y), fr.end]:
			var sx := 1.0 if corner.x == fr.position.x else -1.0
			var sy := 1.0 if corner.y == fr.position.y else -1.0
			draw_line(corner, corner + Vector2(l * sx, 0), fcol, 3.0)
			draw_line(corner, corner + Vector2(0, l * sy), fcol, 3.0)
		draw_circle(c, 3.0, Color(1, 0.35, 0.35, 0.9))
		draw_arc(c, half * 0.3, 0, TAU, 28, Color(1, 0.35, 0.35, 0.45), 1.5)
		# the ghost with its trail and aura
		if lane["shots"].size() < SHOTS:
			var gr := GHOST_R * short
			for k in lane["trail"].size():
				draw_circle(at.call(lane["trail"][k]), gr * (0.9 - k * 0.12), Color(0.7, 0.95, 1.0, 0.05))
			var g: Vector2 = at.call(lane["g"]) + Vector2(0, sin(lane["wobble"] * 2.0) * 4.0)
			var fade := 0.55 + 0.3 * sin(lane["wobble"] * 2.0)
			glow(g, gr * 1.2, Color(0.6, 0.9, 1.0, fade), 6)
			if lane["tex"]:
				draw_texture_rect(lane["tex"], Rect2(g - Vector2(gr, gr) * 1.25, Vector2(gr, gr) * 2.5), false, Color(1, 1, 1, fade))
		if lane["flash"] > 0.0:
			rrect(r.grow(-3), Color(1, 1, 1, lane["flash"] * 0.65), 12)
		# film strip along the bottom
		var strip := Rect2(r.get_center().x - (SHOTS * 26 + 10) * 0.5, r.end.y - 34, SHOTS * 26 + 10, 26)
		rrect(strip, Color(0.05, 0.04, 0.12, 0.78), 9)
		for k in SHOTS:
			var cell := Rect2(strip.position + Vector2(6 + k * 26, 4), Vector2(22, 18))
			var shot: int = lane["shots"][k] if k < lane["shots"].size() else -1
			rrect(cell, Color(1, 1, 1, 0.08), 4)
			if shot >= 0:
				var sc: Color = [Color("6b2a3a"), Color("8a8a5a"), Color("4fc98a"), UIKit.GOLD][shot]
				rrect(cell.grow(-2), sc, 3)
				if shot == 3:
					text(cell.position + Vector2(0, 14), "★", 12, Color.WHITE, cell.size.x, 0)
		if lane["pop_t"] > 0.0:
			var a: float = lane["pop_t"] / 0.9
			text(Vector2(r.position.x, fr.position.y - 10 - (1.0 - a) * 18), lane["pop"], 22,
				Color(UIKit.GOLD if lane["pop"] == "PERFECT!" else Color.WHITE, a), r.size.x, 5)
		nameplate(lane, r.position + Vector2(10, 6), "📷 %d pts · %d/%d" % [_score(lane), lane["shots"].size(), SHOTS])

# ── 3D (3D maps) ──────────────────────────────────────────────────────────────
# A haunted room per player (2×2); the ghost (g: 0..1 across the panel) flits
# about, your camera frame sits in the middle, and a flash fires on a snap.
const ROOM3 := Vector2(5.2, 3.8)

func _build_3d(v) -> void:
	v.sky(Color("1c1830"), 0.55)
	v.aim(Vector3(0, 5, 21), Vector3(0, 2.6, 0))
	var ghosts := ["Wispy", "Haunty", "Lullaboo", "Wispy"]
	for i in lanes.size():
		var lane: Dictionary = lanes[i]
		var o := Vector3((i % 2 - 0.5) * 6.4, (1 - i / 2) * 4.8 - 1.2, -1.5)
		lane["o3"] = o
		v.box(Vector3(ROOM3.x + 0.4, ROOM3.y + 0.4, 0.2), Color("2a2240"), o + Vector3(0, ROOM3.y / 2, -0.6))
		v.box(Vector3(ROOM3.x + 0.4, 0.15, 1.4), Color("3a2e52"), o + Vector3(0, 0, 0))
		for sx in [-1.0, 1.0]:
			v.box(Vector3(0.15, ROOM3.y + 0.4, 1.4), lane["color"].darkened(0.3), o + Vector3(sx * (ROOM3.x / 2 + 0.2), ROOM3.y / 2, 0))
		lane["gh3"] = v.spirit(SpiritsData.sprite_tex(ghosts[i % 4], "front"), Color(0, 0, 0, 0), o, 0.032, true)
		# the camera frame (white) and its PERFECT spot (gold), from thin bars
		var f: float = lane["frame"]
		var fw := f * 2.0 * ROOM3.x
		var fh := f * 2.0 * ROOM3.y
		var c := o + Vector3(0, (1.0 - 0.52) * ROOM3.y, 0.3)
		for bar in [[Vector3(fw, 0.06, 0.02), Vector3(0, fh / 2, 0)], [Vector3(fw, 0.06, 0.02), Vector3(0, -fh / 2, 0)],
				[Vector3(0.06, fh, 0.02), Vector3(fw / 2, 0, 0)], [Vector3(0.06, fh, 0.02), Vector3(-fw / 2, 0, 0)]]:
			v.box(bar[0], Color.WHITE, c + bar[1], true)
		v.box(Vector3(fw * 0.3, fh * 0.3, 0.01), Color(1, 0.85, 0.3, 0.25), c, true)
		lane["fl3"] = v.lamp(Color.WHITE, o + Vector3(0, 2, 2.5), 0.0, 8)
		lane["popped3"] = 0
		var me: Node3D = v.spirit(lane["tex"], lane["color"], o + Vector3(-ROOM3.x / 2 + 0.6, 0.1, 0.6), 0.022)
		var l := lane
		v.tag(o + Vector3(0, ROOM3.y + 0.3, 0), func(): return "%s %s  📸 %d/%d  ★ %d" % [l["name"], key_hint(l), l["shots"].size(), SHOTS, _score(l)],
			lane["color"].lightened(0.25), 0.0, 14)

func _update_3d(v, _delta: float) -> void:
	for lane in lanes:
		var o: Vector3 = lane["o3"]
		var g: Vector2 = lane["g"]
		lane["gh3"].position = o + Vector3((g.x - 0.5) * ROOM3.x, (1.0 - g.y) * ROOM3.y - 0.5, 0.1)
		lane["fl3"].light_energy = lane["flash"] * 5.0
		if lane["shots"].size() > lane["popped3"]:
			lane["popped3"] = lane["shots"].size()
			var pts: int = lane["shots"][-1]
			v.pop(lane["gh3"], ["MISS", "BLURRY +1", "NICE +2", "PERFECT +3"][pts], [Color("ff6a6a"), Color("c8c8e0"), Color("7be0a0"), Color("ffd24d")][pts], 1.6)
