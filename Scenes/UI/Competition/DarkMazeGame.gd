extends CompGame
## 🌀 Dark Maze — everyone races their own maze at once, each in a panel lit
## only by a flickering lantern. Spirits walk automatically (SPD = walking
## speed); at each 3-way crossroad pick LEFT / MIDDLE / RIGHT (your keys, or
## the buttons). One arm is the way on; the others are a trap (−30 HP), a dead
## end, or a wrong turn (back one room). A high HP tier shakes off traps
## faster. Hints show in the light: cap wall,
## red spikes, grey arrow, gold star. First one out wins.

var order: Array = []   # player indices in escape order

func _init_game() -> void:
	layout = Layout.GRID
	how_to = "Each room has 3 doors — pick LEFT / MIDDLE / RIGHT. Every room gives a different clue: marks, a sign, candles, a quick peek or a glow. Pick fast for a speed boost!"
	custom_minimum_size = Vector2(650, 440)
	for lane in lanes:
		var panel := MazePanel.new(lane, self)
		panel.escaped.connect(_on_escaped)
		add_child(panel)
		move_child(panel, 0)   # banners draw above the panels
		lane["panel"] = panel

func keys_text(lane: Dictionary) -> String:
	return "%s / %s / %s for left / middle / right (or click the buttons)" % [Controls.key_name(lane["slot"], "left"),
		Controls.key_name(lane["slot"], "middle"), Controls.key_name(lane["slot"], "right")]

# Panels fill the 2×2 grid, whatever the window size.
func _process(delta: float) -> void:
	for i in lanes.size():
		var r := lane_rect(i)
		lanes[i]["panel"].position = r.position
		lanes[i]["panel"].size = r.size
	super._process(delta)

func _on_escaped(idx: int) -> void:
	order.append(idx)
	_lane_by_idx(idx)["panel"].place = order.size()
	result_value = t
	if one_left(lanes.size() - order.size()):   # the last one in the maze comes last anyway
		finish()

func _on_action(lane: Dictionary, action: String) -> void:
	if action in ["left", "middle", "right"]:
		lane["panel"].choose(action)

func _gui_input(_ev: InputEvent) -> void:
	pass   # the panels have their own buttons

func ranks() -> Array:
	var out: Array = order.duplicate()
	for lane in lanes:
		if not out.has(lane["idx"]):
			out.append(lane["idx"])
	return out

func result_text() -> String:
	return "🏁 %s escapes first!" % _lane_by_idx(ranks()[0])["name"]

# One player's maze: walk (walls scrolling by) → fork (Left/Middle/Right) →
# back (walk of shame) → out.
class MazePanel:
	extends Control

	signal escaped(idx: int)

	const FORKS := 5
	const BACK_TIME := 0.9
	const HINT_HAZARD := 0.6   # chance a hazard arm shows its marker
	const HINT_PATH := 0.35    # chance the path arm shows its star
	const BG := Color(0.02, 0.02, 0.05)
	const WALL := Color(0.08, 0.07, 0.12)
	const DIRS := ["left", "middle", "right"]

	var lane: Dictionary
	var game
	var place := 0
	var phase := "walk"        # walk / fork / enter / back / out
	const ENTER_TIME := 0.9    # walking through the chosen door
	const QUICK := 1.6         # pick the right door this fast → a speed boost
	const HINTS := ["marks", "peek", "sign", "candles", "glow"]
	var hint := "marks"        # this room's kind of clue
	var clue := ""             # what the room says (shown while choosing)
	var candles := {}          # dir -> 1..3 (the "candles" clue)
	var pending := ""          # the door being walked through
	var quick := false
	var t := 0.0
	var walk_time := 1.6
	var back_time := BACK_TIME
	var forks_passed := 0      # rooms cleared
	var arms := {}             # dir -> "path" | "trap" | "dead" | "back"
	var treasure := ""         # a "path" door can be a treasure room (a quicker next walk)
	var last_pick := ""        # the door just chosen (the 3D view walks through it)
	var revealed := {}
	var msg := ""
	var smart := 0.8
	var _step_t := 0.0
	var _flash := 0.0
	var _shake := 0.0
	var _sparkles: Array = []
	var _buttons := {}

	func _init(l: Dictionary, owner_game) -> void:
		lane = l
		game = owner_game
		custom_minimum_size = Vector2(220, 160)   # small enough for a 3 × 2 grid of six
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		# SPD 1 → ~2.3s per corridor, SPD 6 → ~0.8s
		walk_time = clampf(2.6 - 0.3 * float(lane["spirit"].get("spd", 2)), 0.8, 2.6)
		smart = randf_range(0.6, 0.95)

	func _ready() -> void:
		var x := {"left": [0.0, 8, 100], "middle": [0.5, -52, 52], "right": [1.0, -100, -8]}
		for d in DIRS:
			var b := Button.new()
			b.text = {"left": "⬅ ", "middle": "⬆ ", "right": "➡ "}[d] + (Controls.key_name(lane["slot"], d) if lane["human"] else "")
			b.focus_mode = Control.FOCUS_NONE
			b.anchor_left = x[d][0]
			b.anchor_right = x[d][0]
			b.offset_left = x[d][1]
			b.offset_right = x[d][2]
			b.offset_top = 30
			b.offset_bottom = 64
			b.add_theme_stylebox_override("normal", UIKit.box(Color(0.1, 0.45, 0.75, 0.9), 12, 2, Color(0.6, 0.9, 1.0, 0.6)))
			b.add_theme_stylebox_override("hover", UIKit.box(Color(0.25, 0.6, 0.9), 12, 2, Color(0.8, 1.0, 1.0, 0.8)))
			b.add_theme_stylebox_override("pressed", UIKit.box(Color(0.05, 0.3, 0.55), 12, 2, Color(0.6, 0.9, 1.0, 0.6)))
			b.pressed.connect(func(): choose(d))
			add_child(b)
			_buttons[d] = b
		_set_buttons(false)

	func _set_buttons(on: bool) -> void:
		for d in _buttons:
			_buttons[d].visible = on and lane["human"]

	func _process(delta: float) -> void:
		if not game.running and phase != "out":
			queue_redraw()
			return   # wait for GO
		_flash = maxf(0.0, _flash - delta * 2.5)
		_shake = maxf(0.0, _shake - delta * 25.0)
		for s in _sparkles:
			s["p"] += s["v"] * delta
			s["life"] -= delta
		_sparkles = _sparkles.filter(func(s): return s["life"] > 0.0)
		match phase:
			"enter":
				t += delta
				if t >= ENTER_TIME:
					_resolve(pending)
			"fork":
				t += delta
			"walk", "back":
				t += delta
				_step_t += delta
				if _step_t > 0.32 and lane["human"]:
					_step_t = 0.0
					Sfx.play("step", randf_range(0.8, 1.0), -8.0)
				if t >= (walk_time if phase == "walk" else back_time):
					if phase == "walk" and forks_passed >= FORKS:
						_escape()
					else:
						_enter_fork()
		queue_redraw()

	func _enter_fork() -> void:
		phase = "fork"
		t = 0.0
		var dirs := DIRS.duplicate()
		dirs.shuffle()
		var hazards := ["trap", "dead", "back"]
		hazards.shuffle()
		arms = {dirs[0]: "path", dirs[1]: hazards[0], dirs[2]: hazards[1]}
		treasure = dirs[0] if randf() < 0.3 else ""
		hint = HINTS.pick_random() if forks_passed > 0 else "marks"

		for d in DIRS:
			revealed[d] = hint == "marks" and randf() < (HINT_PATH if arms[d] == "path" else HINT_HAZARD)
		match hint:
			"marks":
				clue = "Look for marks in the light"
			"peek":
				clue = "👀 Quick — watch the doors!"
			"sign":
				clue = "🪧 Not %s, not %s" % [dirs[1].to_upper(), dirs[2].to_upper()]
			"candles":
				var most := randf() < 0.5
				var n := [3, 2, 1] if most else [1, 2, 3]
				candles = {dirs[0]: n[0], dirs[1]: n[1], dirs[2]: n[2]}
				if randf() < 0.5:
					candles[dirs[1]] = n[2]
					candles[dirs[2]] = n[1]
				clue = "🕯 Go %s candles" % ("MOST" if most else "FEWEST")
			"glow":
				clue = "✨ Watch for the glow"
		msg = clue
		if lane["human"]:
			_set_buttons(true)
		else:
			_cpu_pick()

	# CPU: follows a visible star, avoids visible hazards, guesses the rest.
	func _cpu_pick() -> void:
		await get_tree().create_timer(randf_range(0.5, 1.1)).timeout
		if phase != "fork":
			return
		var pick := ""
		var path_d := ""
		for d in DIRS:
			if arms[d] == "path":
				path_d = d
		if hint != "marks":
			# reading / remembering / spotting the clue — usually right
			var odds := {"peek": 0.85, "sign": 1.0, "candles": 0.95, "glow": 0.8}
			choose(path_d if randf() < smart * float(odds.get(hint, 1.0)) else DIRS.pick_random())
			return
		if randf() < smart:
			for d in DIRS:
				if revealed[d] and arms[d] == "path":
					pick = d
			if pick == "":
				var safe: Array = DIRS.filter(func(d): return not (revealed[d] and arms[d] != "path"))
				if not safe.is_empty():
					pick = safe.pick_random()
		choose(pick if pick != "" else DIRS.pick_random())

	func choose(dir: String) -> void:
		if phase != "fork":
			return
		_set_buttons(false)
		quick = t <= QUICK
		t = 0.0
		last_pick = dir
		pending = dir
		phase = "enter"   # walk up to the door and through it first
		msg = "…"

	# What's behind the door, once the spirit is through it.
	func shows(d: String) -> bool:
		if phase == "enter":
			return d == pending
		if phase != "fork":
			return false
		match hint:
			"marks":
				return revealed.get(d, false)
			"peek":
				return t < 0.8
			"glow":
				return arms.get(d, "") == "path" and fmod(t, 1.4) > 1.1
		return false

	func _resolve(dir: String) -> void:
		t = 0.0
		back_time = BACK_TIME
		match arms.get(dir, "dead"):
			"path":
				forks_passed += 1
				phase = "walk"
				if dir == treasure:
					msg = "💰 Treasure room!"
					t = walk_time * 0.4   # a head start into the next corridor
					Sfx.play("coin")
				elif quick:
					msg = "⚡ Quick! Speed boost"
					t = walk_time * 0.35
				else:
					msg = "✓ Right way!"
				Sfx.play("collect", 0.8)
			"trap":
				var s: Dictionary = lane["spirit"]
				s["current_hp"] = maxi(1, int(s.get("current_hp", s.get("hp", 60))) - 30)
				phase = "back"
				msg = "💥 Spikes! −30 HP"
				# HP 1 → 1.6s stuck … HP 6 → 0.8s
				back_time = 1.76 - int(s.get("hp_stat", 2)) * 0.16
				_flash = 1.0
				_shake = 9.0
				Sfx.play("crash")
			"dead":
				phase = "back"
				msg = "🕳 Trap door!"
				Sfx.play("error")
			"back":
				forks_passed = maxi(0, forks_passed - 1)
				phase = "back"
				msg = "↩ Wrong way — back a room!"
				Sfx.play("whoosh")

	func _escape() -> void:
		phase = "out"
		_set_buttons(false)
		msg = "🎉 Out!"
		for k in 24:
			var a := randf() * TAU
			_sparkles.append({"p": size * 0.5, "v": Vector2(cos(a), sin(a)) * randf_range(40, 140), "life": randf_range(0.5, 1.0)})
		Sfx.play("caught")
		escaped.emit(lane["idx"])

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		draw_set_transform(Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake, 0.0, Vector2.ONE)
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(UIKit.box(BG, 14, 2, Color(lane["color"], 0.5)), r)
		# the lantern: a warm radial falloff that flickers (walls only exist inside it)
		var c := Vector2(size.x * 0.5, size.y * 0.56)
		var flicker := 1.0 + sin(game.t * 17.0 + lane["idx"]) * 0.02 + randf_range(-0.015, 0.015)
		var rx := 104.0 * flicker
		var ry := 68.0 * flicker
		var light := Color(1.0, 0.86, 0.6) if phase != "out" else Color(0.7, 1.0, 0.8)
		light = light.lerp(Color(1, 0.3, 0.3), _flash)
		for k in range(8, 0, -1):
			var f := float(k) / 8.0
			_oval(c, rx * (0.55 + f * 0.7), ry * (0.55 + f * 0.7), Color(light, 0.05 + (1.0 - f) * 0.12))
		_oval(c, rx * 0.95, ry * 0.95, Color(light, 0.55))
		_oval(c, rx * 0.7, ry * 0.7, Color(light.lightened(0.2), 0.35))
		var xl := c.x - 52.0
		var xr := c.x + 52.0
		if phase == "walk" or phase == "back":
			var speed_px := 150.0 / walk_time
			var dir := 1.0 if phase == "walk" else -1.5
			var y := c.y - ry - 30.0 + fposmod(t * speed_px * dir, 30.0)
			while y < c.y + ry:
				_wall(Rect2(xl - 8, y, 8, 22))
				_wall(Rect2(xr, y, 8, 22))
				y += 30.0
		elif phase == "fork" or phase == "enter":
			_draw_fork(font, c, rx, ry, xl, xr)
		var bob := sin(game.t * 8.0) * 2.0 if phase == "walk" or phase == "enter" else 0.0
		if phase == "enter":   # up to the chosen door and in
			var k := minf(1.0, t / (ENTER_TIME * 0.8))
			var door := {"left": Vector2(-80, -7), "middle": Vector2(0, -48), "right": Vector2(80, -7)}
			c += (door.get(pending, Vector2.ZERO) as Vector2) * k
		_oval(c + Vector2(0, 34), 22, 6, Color(0, 0, 0, 0.35))
		draw_circle(c + Vector2(0, 8 + bob), 33.0, Color(lane["color"], 0.25))
		if lane["tex"]:
			draw_texture_rect(lane["tex"], Rect2(c + Vector2(-26, -18 + bob), Vector2(52, 52)), false)
		draw_arc(c + Vector2(0, 8 + bob), 31.0, 0, TAU, 48, lane["color"].lightened(0.2), 3.0)
		for sp in _sparkles:
			draw_circle(sp["p"], 2.5, Color(1, 0.85, 0.3, sp["life"]))
		# header pill + message pill
		var keys := "" if not lane["human"] else "  %s / %s / %s" % [Controls.key_name(lane["slot"], "left"),
			Controls.key_name(lane["slot"], "middle"), Controls.key_name(lane["slot"], "right")]
		var head := "%s%s   room %d/%d   ♥%d" % [lane["name"], keys, mini(forks_passed + 1, FORKS), FORKS,
			int(lane["spirit"].get("current_hp", 0))]
		draw_style_box(UIKit.box(Color(0.05, 0.04, 0.12, 0.8), 10, 1, Color(1, 1, 1, 0.1)),
			Rect2(6, 6, font.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 18, 22))
		draw_rect(Rect2(10, 11, 4, 12), lane["color"])
		draw_string(font, Vector2(18, 22), head, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, lane["color"].lightened(0.3))
		if msg != "":
			var mw := font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 24
			draw_style_box(UIKit.box(Color(0.05, 0.04, 0.12, 0.85), 10), Rect2((size.x - mw) * 0.5, size.y - 28, mw, 22))
			draw_string(font, Vector2(0, size.y - 12), msg, HORIZONTAL_ALIGNMENT_CENTER, size.x, 14, Color.WHITE)
		if phase == "out" and place > 0:
			var label: String = "🎉 %s!" % CompGame.ORDINAL[clampi(place - 1, 0, 5)]
			draw_string_outline(font, Vector2(0, c.y - ry - 4), label, HORIZONTAL_ALIGNMENT_CENTER, size.x, 28, 6, Color.BLACK)
			draw_string(font, Vector2(0, c.y - ry - 4), label, HORIZONTAL_ALIGNMENT_CENTER, size.x, 28, UIKit.GOLD)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	func _oval(c: Vector2, rx: float, ry: float, col: Color) -> void:
		var pts := PackedVector2Array()
		for i in 36:
			var a := TAU * float(i) / 36.0
			pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
		draw_colored_polygon(pts, col)

	# A stone wall block: dark body with a faint lit top edge.
	func _wall(r: Rect2) -> void:
		draw_rect(r, WALL)
		draw_rect(Rect2(r.position, Vector2(r.size.x, 2)), Color(1, 0.9, 0.7, 0.18))

	# The crossroad: the far wall has a centre gap (middle path), the arms
	# open left and right; hints appear per arm.
	func _draw_fork(font: Font, c: Vector2, rx: float, ry: float, xl: float, xr: float) -> void:
		var y_top := c.y - 36.0
		var y_near := c.y + 16.0
		_wall(Rect2(c.x - rx, y_top, (xl - 7.0) - (c.x - rx), 8))
		_wall(Rect2(xr, y_top, (c.x + rx) - xr, 8))
		_wall(Rect2(xl - 7, y_top - 22, 8, 22))
		_wall(Rect2(xr, y_top - 22, 8, 22))
		_wall(Rect2(c.x - rx, y_near, (xl - 7.0) - (c.x - rx), 8))
		_wall(Rect2(xr, y_near, (c.x + rx) - xr, 8))
		_wall(Rect2(xl - 7, y_near, 8, c.y + ry - y_near))
		_wall(Rect2(xr, y_near, 8, c.y + ry - y_near))
		var mid_y := (y_top + y_near) * 0.5 + 3.0
		var spots := {"middle": Vector2(c.x, y_top - 12.0), "left": Vector2(c.x - 80.0, mid_y), "right": Vector2(c.x + 80.0, mid_y)}
		for d in DIRS:
			if shows(d):
				_draw_hint(font, d, String(arms[d]), spots[d], y_top, y_near, xl, xr, c)
			if hint == "candles" and phase == "fork":
				var n: int = candles.get(d, 1)
				for i in n:
					var cp: Vector2 = spots[d] + Vector2((i - (n - 1) * 0.5) * 9.0, -16.0)
					draw_rect(Rect2(cp.x - 2, cp.y, 4, 8), Color(0.95, 0.92, 0.8))
					draw_circle(cp + Vector2(0, -2), 2.6 + sin(game.t * 14.0 + i) * 0.5, Color(1, 0.7, 0.25))

	func _draw_hint(font: Font, dir: String, kind: String, p: Vector2, y_top: float, y_near: float, xl: float, xr: float, c: Vector2) -> void:
		match kind:
			"dead":
				if dir == "middle":
					draw_rect(Rect2(xl - 7, y_top - 22, (xr - xl) + 14, 7), BG)
				else:
					draw_rect(Rect2(c.x + (-91.0 if dir == "left" else 84.0), y_top, 7, y_near - y_top + 7), BG)
			"trap":
				for i in 3:
					var sx := p.x - 12.0 + i * 12.0
					draw_colored_polygon(PackedVector2Array([Vector2(sx - 4, p.y + 4), Vector2(sx + 4, p.y + 4), Vector2(sx, p.y - 6)]), Color(0.85, 0.15, 0.15))
			"back":
				draw_rect(Rect2(p.x - 2, p.y - 8, 4, 10), Color(0.35, 0.35, 0.4))
				draw_colored_polygon(PackedVector2Array([Vector2(p.x - 6, p.y + 2), Vector2(p.x + 6, p.y + 2), Vector2(p.x, p.y + 10)]), Color(0.35, 0.35, 0.4))
			"path":
				var twinkle := 0.75 + 0.25 * sin(game.t * 9.0)
				for k in range(4, 0, -1):
					draw_circle(p, 5.0 + k * 3.0 * twinkle, Color(1, 0.8, 0.2, 0.08))
				draw_string(font, Vector2(p.x - 8, p.y + 6), "★", HORIZONTAL_ALIGNMENT_LEFT, -1, int(16 * twinkle + 4), Color(1.0, 0.85, 0.3))

# ── 3D (3D maps) ──────────────────────────────────────────────────────────────
# Four dark panels (2×2). The spirit walks a stone path lit by its lantern;
# at a room a wall with three doors slides in (hint markers over some), it
# walks THROUGH the chosen door and what's behind it shows: right way,
# treasure room, trap door, spikes or wrong way.
const PANEL3 := Vector2(9.0, 6.0)
const MARK3 := {"path": Color("ffd24d"), "trap": Color("ff4040"), "dead": Color("8a5ad0"), "back": Color("9a9aa8")}

func _build_3d(v) -> void:
	v.sky(Color("020204"), 0.05, 0.1)
	var cols := 2 if lanes.size() <= 4 else 3
	v.aim(Vector3(0, 25, 6), Vector3(0, 0, 0.3), 0.8 if cols == 2 else 1.08)   # the whole grid in view
	for i in lanes.size():
		var lane: Dictionary = lanes[i]
		lane["panel"].visible = false   # the 2D panel keeps running the logic, unseen
		var rows := ceili(lanes.size() / float(cols))
		var o := Vector3((i % cols - (cols - 1) * 0.5) * 10.4, 0, (i / cols - (rows - 1) * 0.5) * 7.2)
		lane["o3"] = o
		v.box(Vector3(PANEL3.x, 0.1, PANEL3.y), Color("06060c"), o + Vector3(0, -0.06, 0))
		for side in [[Vector3(PANEL3.x, 0.12, 0.12), Vector3(0, 0, -PANEL3.y / 2)], [Vector3(PANEL3.x, 0.12, 0.12), Vector3(0, 0, PANEL3.y / 2)],
				[Vector3(0.12, 0.12, PANEL3.y), Vector3(-PANEL3.x / 2, 0, 0)], [Vector3(0.12, 0.12, PANEL3.y), Vector3(PANEL3.x / 2, 0, 0)]]:
			v.box(side[0], lane["color"], o + side[1], true)
		v.box(Vector3(2.0, 0.05, PANEL3.y - 0.4), Color("3a3646"), o)
		var walls: Array = []
		for w in 7:
			for sx in [-1.0, 1.0]:
				walls.append(v.box(Vector3(0.45, 1.1, 0.75), Color("2c2a3a"), o + Vector3(sx * 1.25, 0.55, -2.7 + w * 0.9)))
		lane["walls3"] = walls
		var dw := Node3D.new()
		v.world.add_child(dw)
		v.box(Vector3(7.6, 1.6, 0.4), Color("2c2a3a"), Vector3(0, 0.8, 0), false, dw)
		var doors := {}
		for a in 3:
			var d: String = DIRS3[a]
			var fx := (a - 1) * 2.4
			v.box(Vector3(1.3, 1.5, 0.45), Color("6a4a2a"), Vector3(fx, 0.76, 0.02), false, dw)
			var gap: MeshInstance3D = v.box(Vector3(0.95, 1.25, 0.5), Color("0a0a10"), Vector3(fx, 0.68, 0.03), true, dw)
			var mark: MeshInstance3D = v.box(Vector3(0.45, 0.45, 0.2), Color.WHITE, Vector3(fx, 1.8, 0.15), true, dw)
			doors[d] = {"gap": gap, "mark": mark}
		dw.visible = false
		lane["dw3"] = dw
		var pl = lane["panel"]
		# the room's clue along the bottom of the panel (clear of the name tag)
		v.tag(o + Vector3(0, 0, PANEL3.y / 2 - 0.55), func(): return pl.clue if pl.phase == "fork" and pl.hint != "marks" else "", Color("ffe9a8"), 0.0, 13 if lanes.size() > 4 else 15)
		for a2 in 3:
			var d2: String = DIRS3[a2]
			v.tag(doors[d2]["gap"], func(): return "🕯".repeat(int(pl.candles.get(d2, 1))) if pl.phase == "fork" and pl.hint == "candles" else "",
				Color("ffcf70"), 1.1, 15)
		lane["doors3"] = doors
		lane["n3"] = v.spirit(lane["tex"], lane["color"], o + Vector3(0, 0, 1.6), 0.034, true)
		lane["lamp3"] = v.lamp(Color("ffc870"), o + Vector3(0, 2.2, 1.6), 2.6, 5.0)
		lane["ph3"] = "walk"
		lane["pt3"] = 0.0
		var l := lane
		v.tag(o + Vector3(0, 0, -PANEL3.y / 2), func():
			var p = l["panel"]
			return "%s %s — room %d / %d" % [l["name"], key_hint(l, "left").replace("]", "/" + Controls.key_name(l["slot"], "middle") + "/" + Controls.key_name(l["slot"], "right") + "]") if l["human"] else "(CPU)",
				mini(p.forks_passed + 1, p.FORKS), p.FORKS] if p.phase != "out" else "%s — out! 🎉" % l["name"],
			lane["color"].lightened(0.25), 0.6, 16)

const DIRS3 := ["left", "middle", "right"]

func _update_3d(v, delta: float) -> void:
	for lane in lanes:
		var p = lane["panel"]
		var o: Vector3 = lane["o3"]
		var n: Node3D = lane["n3"]
		var dw: Node3D = lane["dw3"]
		lane["pt3"] += delta
		var scroll := 0.0
		# follow the panel's phase, adding the walk-through-the-door beat
		if p.phase == "fork" and lane["ph3"] != "doors":
			lane["ph3"] = "doors"
			lane["pt3"] = 0.0
			dw.visible = true
			dw.position = o + Vector3(0, 0, -2.6)
			for d in DIRS3:
				var kind: String = p.arms.get(d, "dead")
				lane["doors3"][d]["gap"].material_override = v.mat(Color("0a0a10"), true)
				lane["doors3"][d]["mark"].material_override = v.mat(MARK3[kind], true)
				lane["doors3"][d]["mark"].visible = p.revealed.get(d, false)
		elif p.phase == "enter" and lane["ph3"] == "doors":
			lane["ph3"] = "through"   # a door was picked: walk to it and through
			lane["pt3"] = 0.0
			var kind2: String = p.arms.get(p.last_pick, "dead")
			lane["doors3"][p.last_pick]["gap"].material_override = v.mat(MARK3[kind2], true)
		match lane["ph3"]:
			"doors":
				for d in DIRS3:   # this room's clue: marks, a peek, a glow…
					lane["doors3"][d]["mark"].visible = p.shows(d)
				dw.position.z = lerpf(o.z - 2.6, o.z - 1.4, minf(1.0, lane["pt3"] / 0.6))
				scroll = 2.2 * (1.0 - minf(1.0, lane["pt3"] / 0.6))
			"through":
				var door_x: float = o.x + (DIRS3.find(p.last_pick) - 1) * 2.4
				if p.t < p.ENTER_TIME * 0.5:
					n.position.x = lerpf(n.position.x, door_x, minf(1.0, delta * 6.0))
					n.position.z = lerpf(n.position.z, dw.position.z + 0.4, minf(1.0, delta * 6.0))
				else:
					n.position.z -= delta * 2.0
					n.scale = Vector3.ONE * maxf(0.05, 1.0 - (p.t - p.ENTER_TIME * 0.5) * 2.2)
					if p.msg.begins_with("🕳"):
						n.position.y -= delta * 3.0
				if p.phase != "enter":   # through: show what was behind the door
					v.pop(o + Vector3(0, 0, PANEL3.y / 2 - 0.9), p.msg, Color("ffd24d") if p.phase == "walk" else Color("ff9a9a"), 1.8, 1.1, 13 if lanes.size() > 4 else 16)
					if p.msg.begins_with("💥"):
						lane["lamp3"].light_color = Color("ff5050")
					elif p.msg.begins_with("💰"):
						lane["lamp3"].light_color = Color("ffe070")
					n.scale = Vector3.ONE
					n.position = o + Vector3(0, 0, 1.6)
					lane["ph3"] = "walk"
					lane["pt3"] = 0.0
					if p.phase == "walk":
						dw.visible = false
			"walk":
				scroll = 2.2 if p.phase == "walk" else (-2.4 if p.phase == "back" else 0.0)
				if dw.visible:
					dw.position.z += delta * scroll
					if absf(dw.position.z - o.z) > 2.8:
						dw.visible = false
				if lane["pt3"] > 0.6:
					lane["lamp3"].light_color = Color("ffc870") if p.phase != "out" else Color("b0ffc8")
		for w in lane["walls3"]:
			w.position.z += delta * scroll
			if w.position.z > o.z + 3.0:
				w.position.z -= 6.3
			elif w.position.z < o.z - 3.3:
				w.position.z += 6.3
			w.visible = not dw.visible or w.position.z > dw.position.z + 0.5
		if scroll != 0.0:
			n.position.y = absf(sin(t * 8.0 + lane["idx"])) * 0.12
		lane["lamp3"].position = n.position + Vector3(0, 2.2, 0)
		lane["lamp3"].light_energy = 2.5 + sin(t * 17.0 + lane["idx"]) * 0.3 + randf() * 0.2
