extends CompGame
## 🌀 Dark Maze — everyone races their own maze at once, each in a panel lit
## only by a flickering lantern. Spirits walk automatically (SPD = walking
## speed); at each 3-way crossroad pick LEFT / MIDDLE / RIGHT (your keys, or
## the buttons). One arm is the way on; the others are a trap (−30 HP), a dead
## end, or a wrong turn (back one fork). A high HP tier shakes off traps
## faster. Hints show in the light: cap wall,
## red spikes, grey arrow, gold star. First one out wins.

var order: Array = []   # player indices in escape order

func _init_game() -> void:
	layout = Layout.GRID
	how_to = "At each crossroad pick LEFT / MIDDLE / RIGHT. Read the hints in the lantern light!"
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
	if order.size() >= lanes.size():
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
	var phase := "walk"        # walk / fork / back / out
	var t := 0.0
	var walk_time := 1.6
	var back_time := BACK_TIME
	var forks_passed := 0
	var arms := {}             # dir -> "path" | "trap" | "dead" | "back"
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
		custom_minimum_size = Vector2(320, 208)
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
		for d in DIRS:
			revealed[d] = randf() < (HINT_PATH if arms[d] == "path" else HINT_HAZARD)
		msg = "Which way?"
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
		t = 0.0
		back_time = BACK_TIME
		match arms.get(dir, "dead"):
			"path":
				forks_passed += 1
				phase = "walk"
				msg = ""
				Sfx.play("collect", 0.8)
			"trap":
				var s: Dictionary = lane["spirit"]
				s["current_hp"] = maxi(1, int(s.get("current_hp", s.get("hp", 60))) - 30)
				phase = "back"
				msg = "💥 A trap! −30 HP"
				# HP 1 → 1.6s stuck … HP 6 → 0.8s
				back_time = 1.76 - int(s.get("hp_stat", 2)) * 0.16
				_flash = 1.0
				_shake = 9.0
				Sfx.play("crash")
			"dead":
				phase = "back"
				msg = "🧱 Dead end!"
				Sfx.play("error")
			"back":
				forks_passed = maxi(0, forks_passed - 1)
				phase = "back"
				msg = "↩ Wrong turn — back one fork!"
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
		elif phase == "fork":
			_draw_fork(font, c, rx, ry, xl, xr)
		var bob := sin(game.t * 8.0) * 2.0 if phase == "walk" else 0.0
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
		var head := "%s%s   fork %d/%d   ♥%d" % [lane["name"], keys, mini(forks_passed + 1, FORKS), FORKS,
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
			if revealed.get(d, false):
				_draw_hint(font, d, String(arms[d]), spots[d], y_top, y_near, xl, xr, c)

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
