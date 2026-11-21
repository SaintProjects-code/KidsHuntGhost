extends Node3D
## DEMO ONLY: what the minigames could look like in 3D on the 3D maps — four
## players each, real spirit sprites, inside a competition-style frame (title,
## how-to line, player score chips). Plays all ten in a row (GAME_TIME each),
## or one: -- game=<n>. Saves a screenshot of each to user://mg3d/.

const GAME_TIME := 7.0
const NAMES := ["Ivy", "Brooke", "Ember", "Zap"]
const SPIRITS := ["Mossprig", "Puddleboo", "Cinderwisp", "Zapkin"]
const COLORS := [Color("5ad26a"), Color("4aa3df"), Color("ff7a3a"), Color("ffd24d")]
const KEYS := ["W", "I", "↑", "Num8"]
const GAMES := [
	["🦇 Bat Dodge", "Bats swoop down your lane — hop LEFT / MIDDLE / RIGHT to dodge them.", "bat"],
	["👻 Boo Reflex", "Wait in the dark… when the ghost shouts BOO!, press ACTION first.", "boo"],
	["🧗 Spirit Climb", "Bounce up the glowing platforms and steer LEFT / RIGHT. Gold pads launch you!", "climb"],
	["🌀 Dark Maze", "Walk the path, then pick a door — LEFT / MIDDLE / RIGHT. What's behind it?", "maze"],
	["📸 Ghost Snap", "Press ACTION when the ghost is inside your frame. Dead centre = PERFECT.", "snap"],
	["🏮 Lantern Memory", "Watch your lanterns flash, then repeat the pattern with LEFT / MIDDLE / RIGHT.", "memory"],
	["🎃 Pumpkin Toss", "Press ACTION when your power meter is at the top. Longest throw wins.", "toss"],
	["😱 Scare-Off", "MASH ACTION to puff up and fill the fright meter — scare the scarecrow away!", "scare"],
	["🏁 Haunted Dash", "A stat contest: roll your die, then the spirits race — SPD decides the sprint.", "dash"],
	["🎈 Wisp Float", "HOLD ACTION to float, let go to sink. Grab wisps (+1), dodge bats (−1).", "float"],
]

var cam: Camera3D
var stage: Node3D
var ui: Control
var title_lbl: Label
var hint_lbl: Label
var chips: Array = []
var pops: Array = []
var frames: Array = []     # snap frames to draw: [world pos, size]
var t := 0.0
var g := {}                # the current game's state
var game_i := 0
var only := -1
var shot_taken := false

func _ready() -> void:
	randomize()
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir() + "/mg3d")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("game="):
			only = int(a.substr(5))
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment = e
	add_child(env)
	g["env"] = e
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	add_child(sun)
	g["sun"] = sun
	cam = Camera3D.new()
	cam.fov = 42
	add_child(cam)
	_build_ui()
	_start(only if only >= 0 else 0)

# ── frame (title, how-to, player chips) ───────────────────────────────────────
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.draw.connect(_draw_ui)
	layer.add_child(ui)
	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", UIKit.box(Color(UIKit.NIGHT, 0.88), 0, 0, Color.TRANSPARENT, Vector2(16, 8)))
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	layer.add_child(top)
	var tv := UIKit.vbox(2)
	top.add_child(tv)
	title_lbl = UIKit.label("", 26, UIKit.GOLD)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tv.add_child(title_lbl)
	hint_lbl = UIKit.label("", 15, Color(1, 1, 1, 0.8))
	hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tv.add_child(hint_lbl)
	var bot := PanelContainer.new()
	bot.add_theme_stylebox_override("panel", UIKit.box(Color(UIKit.NIGHT, 0.88), 0, 0, Color.TRANSPARENT, Vector2(16, 8)))
	bot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bot.grow_vertical = Control.GROW_DIRECTION_BEGIN
	layer.add_child(bot)
	var row := UIKit.hbox(14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	bot.add_child(row)
	for k in 4:
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", UIKit.box(Color(0.1, 0.08, 0.18), 10, 2, COLORS[k], Vector2(10, 4)))
		chip.custom_minimum_size.x = 230
		row.add_child(chip)
		var h := UIKit.hbox(8)
		chip.add_child(h)
		var icon := TextureRect.new()
		icon.texture = SpiritsData.sprite_tex(SPIRITS[k], "front")
		icon.custom_minimum_size = Vector2(40, 40)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		h.add_child(icon)
		var l := UIKit.label("", 16, Color.WHITE)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(l)
		chips.append(l)

func _draw_ui() -> void:
	var font := ThemeDB.fallback_font
	for p in pops:
		var pos: Vector3 = p["at"] if p["at"] is Vector3 else (p["at"] as Node3D).global_position
		if cam.is_position_behind(pos):
			continue
		var s := cam.unproject_position(pos + Vector3(0, p["h"], 0))
		var c: Color = p["col"]
		c.a = minf(1.0, p["life"] * 2.0)
		var size: int = p.get("size", 24)
		var w := font.get_string_size(p["txt"], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		ui.draw_string_outline(font, s - Vector2(w / 2, 0), p["txt"], HORIZONTAL_ALIGNMENT_LEFT, -1, size, 6, Color(0, 0, 0, c.a * 0.85))
		ui.draw_string(font, s - Vector2(w / 2, 0), p["txt"], HORIZONTAL_ALIGNMENT_LEFT, -1, size, c)
	for f in frames:   # Ghost Snap camera frames
		var c2 := cam.unproject_position(f[0])
		var r: Vector2 = f[1]
		ui.draw_rect(Rect2(c2 - r, r * 2), Color(1, 1, 1, 0.85), false, 3.0)
		ui.draw_rect(Rect2(c2 - r * 0.25, r * 0.5), Color("ffd24d"), false, 2.0)

func pop(at, txt: String, col: Color, h := 2.6, life := 1.1, size := 24) -> void:
	pops.append({"at": at, "txt": txt, "col": col, "h": h, "life": life, "size": size})

func tag(at: Node3D, k: int, h := 3.2) -> void:   # a name tag that never fades
	pops.append({"at": at, "txt": "%s [%s]" % [NAMES[k], KEYS[k]], "col": COLORS[k], "h": h, "life": 99999.0, "size": 16})

# ── building blocks ───────────────────────────────────────────────────────────
func mat(c: Color, unshaded := false, alpha := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c.r, c.g, c.b, alpha)
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m

func box(sz: Vector3, c: Color, at: Vector3, unshaded := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = sz
	mi.mesh = b
	mi.material_override = mat(c, unshaded)
	mi.position = at
	stage.add_child(mi)
	return mi

func ball(r: float, c: Color, at: Vector3, unshaded := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2
	mi.mesh = s
	mi.material_override = mat(c, unshaded)
	mi.position = at
	stage.add_child(mi)
	return mi

func light(c: Color, at: Vector3, energy: float, rng: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = c
	l.light_energy = energy
	l.omni_range = rng
	l.position = at
	stage.add_child(l)
	return l

# A spirit: its real front sprite, standing up (billboard), with a ring in the
# player's colour under its feet.
func spirit(k: int, at: Vector3, px := 0.05, name := "", face_cam := false) -> Node3D:
	var n := Node3D.new()
	n.position = at
	stage.add_child(n)
	var s := Sprite3D.new()
	s.texture = SpiritsData.sprite_tex(name if name != "" else SPIRITS[k], "front")
	# fully facing the camera for top-down views, so it isn't squashed flat
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED if face_cam else BaseMaterial3D.BILLBOARD_FIXED_Y
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.shaded = false
	s.pixel_size = px
	s.offset.y = 24
	n.add_child(s)
	if k >= 0:
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.75
		tm.outer_radius = 0.95
		ring.mesh = tm
		ring.material_override = mat(COLORS[k], true)
		ring.position.y = 0.05
		ring.scale = Vector3.ONE * clampf(px / 0.05, 0.5, 1.0)
		n.add_child(ring)
	return n

func lane_x(k: int, gap := 5.0) -> float:
	return (k - 1.5) * gap

# ── flow ──────────────────────────────────────────────────────────────────────
func _start(i: int) -> void:
	game_i = i
	t = 0.0
	shot_taken = false
	pops.clear()
	frames.clear()
	if stage:
		stage.queue_free()
	stage = Node3D.new()
	add_child(stage)
	var env: Environment = g["env"]
	var sun: DirectionalLight3D = g["sun"]
	g = {"env": env, "sun": sun, "score": [0, 0, 0, 0]}
	title_lbl.text = GAMES[i][0]
	hint_lbl.text = GAMES[i][1]
	call("_setup_" + GAMES[i][2])

func _process(delta: float) -> void:
	var dt := minf(delta, 0.05)
	t += dt
	call("_tick_" + GAMES[game_i][2], dt)
	for p in pops:
		if p["life"] < 1000.0:
			p["life"] -= dt
			p["h"] += dt * 1.2
	pops = pops.filter(func(p): return p["life"] > 0)
	for k in 4:
		chips[k].text = "%s   %s" % [NAMES[k], str(g["score"][k])]
	ui.queue_redraw()
	if not shot_taken and t > GAME_TIME * 0.6:
		shot_taken = true
		get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/mg3d/%02d_%s.png" % [game_i + 1, GAMES[game_i][2]])
	if t > GAME_TIME:
		if only >= 0 or game_i == GAMES.size() - 1:
			get_tree().quit()
		else:
			_start(game_i + 1)

func _sky(c: Color, amb: float) -> void:
	g["env"].background_color = c
	g["env"].ambient_light_color = Color(0.8, 0.82, 0.9)
	g["env"].ambient_light_energy = amb
	g["sun"].light_energy = 0.9 if amb > 0.4 else 0.15

# ── 🦇 Bat Dodge ──────────────────────────────────────────────────────────────
func _setup_bat() -> void:
	_sky(Color("1a1538"), 0.6)
	cam.position = Vector3(0, 13, 25)
	cam.look_at(Vector3(0, 0, -5))
	g["p"] = []
	g["bats"] = []
	for k in 4:
		var cx := lane_x(k, 5.6)
		box(Vector3(4.2, 0.2, 30), Color("2a2450"), Vector3(cx, -0.1, -9))
		for lx in [-0.7, 0.7]:
			box(Vector3(0.05, 0.03, 30), Color("6a62b0"), Vector3(cx + lx, 0.01, -9), true)
		var s := spirit(k, Vector3(cx, 0, 4), 0.032)
		tag(s, k, 2.4)
		g["p"].append({"n": s, "cx": cx, "lane": 1, "hit": 0.0})

func _tick_bat(dt: float) -> void:
	if randf() < dt * 3.0:
		var k := randi() % 4
		var ln := randi() % 3
		var b := Node3D.new()
		b.position = Vector3(g["p"][k]["cx"] + (ln - 1) * 1.4, 1.2, -24)
		stage.add_child(b)
		var body := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.3
		sm.height = 0.6
		body.mesh = sm
		body.material_override = mat(Color("2a1a3a"))
		b.add_child(body)
		for side in [-1, 1]:
			var w := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.8, 0.06, 0.4)
			w.mesh = bm
			w.material_override = mat(Color("4a2a66"))
			w.position.x = side * 0.5
			b.add_child(w)
		g["bats"].append({"b": b, "k": k, "ln": ln, "hit": false})
	for x in g["bats"]:
		x["b"].position.z += dt * 13
		x["b"].get_child(1).rotation.z = sin(t * 22) * 0.6
		x["b"].get_child(2).rotation.z = -sin(t * 22) * 0.6
		var p: Dictionary = g["p"][x["k"]]
		if x["b"].position.z > -4 and x["b"].position.z < 0 and p["lane"] == x["ln"] and randf() < 0.9:
			p["lane"] = (x["ln"] + 1 + randi() % 2) % 3
		if not x["hit"] and absf(x["b"].position.z - 4) < 0.5 and absf(p["n"].position.x - x["b"].position.x) < 0.6:
			x["hit"] = true
			p["hit"] = 0.4
			pop(p["n"], "−1 ♥", Color("ff6a6a"))
	for i in range(g["bats"].size() - 1, -1, -1):
		if g["bats"][i]["b"].position.z > 9:
			g["bats"][i]["b"].queue_free()
			g["bats"].remove_at(i)
	for k in 4:
		var p: Dictionary = g["p"][k]
		var tx: float = p["cx"] + (p["lane"] - 1) * 1.4
		p["n"].position.x = lerpf(p["n"].position.x, tx, minf(1.0, dt * 12))
		p["n"].position.y = absf(sin(t * 8 + k)) * 0.25 + (0.6 if p["hit"] > 0 else 0.0)
		p["hit"] -= dt
		g["score"][k] = "♥" .repeat(maxi(1, 3 - int(t / 3.0) % 3 + (k % 2)))

# ── 👻 Boo Reflex ─────────────────────────────────────────────────────────────
func _setup_boo() -> void:
	_sky(Color("06050c"), 0.12)
	cam.position = Vector3(0, 6, 19)
	cam.look_at(Vector3(0, 1.5, 0))
	box(Vector3(22, 0.4, 7), Color("2a2040"), Vector3(0, -0.2, 0.5))
	box(Vector3(3, 2, 2), Color("5a3a20"), Vector3(0, 1, -2.5))
	g["p"] = []
	for k in 4:
		var s := spirit(k, Vector3(lane_x(k, 4.6), 0, 2), 0.04)
		tag(s, k, 2.8)
		g["p"].append({"n": s, "j": 0.0, "delay": 0.0})
	g["boo"] = spirit(-1, Vector3(0, 0, -2.5), 0.12, "Wispy")
	g["boo"].scale = Vector3.ONE * 0.01
	g["spot"] = light(Color.WHITE, Vector3(0, 6, 3), 0.0, 20)
	g["phase"] = 0
	g["clock"] = 1.5

func _tick_boo(dt: float) -> void:
	g["clock"] -= dt
	if g["phase"] == 0 and g["clock"] <= 0:
		g["phase"] = 1
		g["clock"] = 1.8
		var best := 0
		for k in 4:
			g["p"][k]["delay"] = randf_range(0.12, 0.5)
			if g["p"][k]["delay"] < g["p"][best]["delay"]:
				best = k
		g["best"] = best
		pop(g["boo"], "BOO!", Color("ffffff"), 5.5, 1.2, 48)
	if g["phase"] == 1:
		g["boo"].scale = Vector3.ONE * minf(1.0, g["boo"].scale.x + dt * 7)
		g["boo"].position.y = minf(1.8, g["boo"].position.y + dt * 9)
		g["spot"].light_energy = 3.0
		for k in 4:
			var p: Dictionary = g["p"][k]
			p["delay"] -= dt
			if p["delay"] < 0 and p["delay"] > -dt:
				pop(p["n"], "%d ms" % randi_range(180, 420) if k != g["best"] else "FIRST!", Color("ffd24d") if k == g["best"] else Color.WHITE)
				if k == g["best"]:
					g["score"][k] += 1
			if p["delay"] < 0:
				p["j"] = minf(1.0, p["j"] + dt * 6)
		if g["clock"] <= 0:
			g["phase"] = 0
			g["clock"] = randf_range(1.5, 2.5)
			g["boo"].scale = Vector3.ONE * 0.01
			g["boo"].position.y = 0
			g["spot"].light_energy = 0.0
	for p in g["p"]:
		if g["phase"] == 0:
			p["j"] = maxf(0.0, p["j"] - dt * 3)
		p["n"].position.y = sin(p["j"] * PI) * 1.6

# ── 🧗 Spirit Climb ───────────────────────────────────────────────────────────
func _setup_climb() -> void:
	_sky(Color("1c1844"), 0.75)
	g["p"] = []
	for k in 4:
		var cx := lane_x(k, 5.4)
		box(Vector3(0.06, 400, 0.06), Color("3a3478"), Vector3(cx - 2.2, 150, -0.8), true)
		box(Vector3(0.06, 400, 0.06), Color("3a3478"), Vector3(cx + 2.2, 150, -0.8), true)
		var plats: Array = []
		for i in 80:
			var kind := "spring" if i % 9 == 8 else ("crack" if i % 5 == 3 else "n")
			var col := Color("ffd24d") if kind == "spring" else (Color("8a7a6a") if kind == "crack" else Color("7a62ff"))
			plats.append({"m": box(Vector3(1.5, 0.2, 1.2), col, Vector3(cx + randf_range(-1.4, 1.4), i * 1.7, 0), kind != "crack"), "kind": kind})
		var s := spirit(k, Vector3(cx, 0.3, 0), 0.028)
		g["p"].append({"n": s, "cx": cx, "vy": 6.0 + k, "plats": plats})

func _tick_climb(dt: float) -> void:
	var top := 0.0
	for k in 4:
		var p: Dictionary = g["p"][k]
		p["vy"] -= 18 * dt
		p["n"].position.y += p["vy"] * dt
		for q in p["plats"]:
			if q["m"].position.y > p["n"].position.y + 0.2:
				p["n"].position.x = lerpf(p["n"].position.x, q["m"].position.x, minf(1.0, dt * 2.5))
				break
		if p["vy"] < 0:
			for q in p["plats"]:
				if q["m"].visible and absf(p["n"].position.y - q["m"].position.y - 0.1) < 0.3 and absf(p["n"].position.x - q["m"].position.x) < 0.9:
					p["vy"] = 15.0 if q["kind"] == "spring" else 9.5
					if q["kind"] == "crack":
						q["m"].visible = false
					if q["kind"] == "spring":
						pop(p["n"], "BOING!", Color("ffd24d"))
					break
		# a fall (out, in the real game): the demo catches it on the platform below
		p["peak"] = maxf(p.get("peak", 0.0), p["n"].position.y)
		if p["n"].position.y < p["peak"] - 7.0:
			for q in p["plats"]:
				if q["m"].visible and q["m"].position.y > p["peak"] - 6.0:
					p["n"].position = q["m"].position + Vector3(0, 0.3, 0)
					p["vy"] = 9.5
					break
		top = maxf(top, p["n"].position.y)   # the camera follows the leader
		g["score"][k] = "%d m" % maxi(0, int(p["peak"]))
	g["cam_y"] = lerpf(g.get("cam_y", top), top, minf(1.0, dt * 2.0))   # smooth follow
	cam.position = Vector3(0, g["cam_y"] + 2, 26)
	cam.look_at(Vector3(0, g["cam_y"] + 2, 0))

# ── 🌀 Dark Maze ──────────────────────────────────────────────────────────────
# Like the 2D game: each player has their own dark panel (a 2×2 grid). The
# spirit stays in its lantern light while the corridor walls scroll past; at
# a crossroad three arms open (LEFT / MIDDLE / RIGHT) — hints in the light:
# gold star = the way on, red spikes = trap, grey arrow = wrong turn, a cap
# wall = dead end.
const MAZE_PANEL := Vector2(9.0, 6.0)
const MAZE_CENTERS := [Vector2(-5.2, -3.6), Vector2(5.2, -3.6), Vector2(-5.2, 3.6), Vector2(5.2, 3.6)]

func _setup_maze() -> void:
	_sky(Color("020204"), 0.05)
	cam.position = Vector3(0, 25, 6)
	cam.look_at(Vector3(0, 0, 0.3))
	g["p"] = []
	for k in 4:
		var c: Vector2 = MAZE_CENTERS[k]
		var o := Vector3(c.x, 0, c.y)
		box(Vector3(MAZE_PANEL.x, 0.1, MAZE_PANEL.y), Color("06060c"), o + Vector3(0, -0.06, 0))
		for side in [[Vector3(MAZE_PANEL.x, 0.12, 0.12), Vector3(0, 0, -MAZE_PANEL.y / 2)], [Vector3(MAZE_PANEL.x, 0.12, 0.12), Vector3(0, 0, MAZE_PANEL.y / 2)],
				[Vector3(0.12, 0.12, MAZE_PANEL.y), Vector3(-MAZE_PANEL.x / 2, 0, 0)], [Vector3(0.12, 0.12, MAZE_PANEL.y), Vector3(MAZE_PANEL.x / 2, 0, 0)]]:
			box(side[0], COLORS[k], o + side[1], true)
		# the walking path: a stone floor with wall blocks on both sides (they scroll)
		box(Vector3(2.0, 0.05, MAZE_PANEL.y - 0.4), Color("3a3646"), o)
		var walls: Array = []
		for w in 7:
			for sx in [-1.0, 1.0]:
				walls.append(box(Vector3(0.45, 1.1, 0.75), Color("2c2a3a"), o + Vector3(sx * 1.25, 0.55, -2.7 + w * 0.9)))
		# the crossroad: a wall across the path with three doors, a hint over each
		var door_wall := Node3D.new()
		door_wall.position = o + Vector3(0, 0, -1.4)
		stage.add_child(door_wall)
		var wall := MeshInstance3D.new()
		var wb := BoxMesh.new()
		wb.size = Vector3(7.6, 1.6, 0.4)
		wall.mesh = wb
		wall.material_override = mat(Color("2c2a3a"))
		wall.position.y = 0.8
		door_wall.add_child(wall)
		var doors: Array = []
		for a in 3:
			var frame := MeshInstance3D.new()
			var fb := BoxMesh.new()
			fb.size = Vector3(1.3, 1.5, 0.45)
			frame.mesh = fb
			frame.material_override = mat(Color("6a4a2a"))
			frame.position = Vector3((a - 1) * 2.4, 0.76, 0.02)
			door_wall.add_child(frame)
			var gap := MeshInstance3D.new()
			var gb := BoxMesh.new()
			gb.size = Vector3(0.95, 1.25, 0.5)
			gap.mesh = gb
			gap.material_override = mat(Color("0a0a10"), true)
			gap.position = frame.position + Vector3(0, -0.08, 0.01)
			door_wall.add_child(gap)
			var mark := MeshInstance3D.new()
			var mb := BoxMesh.new()
			mb.size = Vector3(0.45, 0.45, 0.2)
			mark.mesh = mb
			mark.position = frame.position + Vector3(0, 1.05, 0.15)
			door_wall.add_child(mark)
			doors.append({"gap": gap, "mark": mark})
		door_wall.visible = false
		var s := spirit(k, o + Vector3(0, 0, 1.6), 0.034, "", true)
		var lamp := light(Color("ffc870"), o + Vector3(0, 2.2, 1.6), 2.6, 5.0)
		g["p"].append({"n": s, "o": o, "lamp": lamp, "walls": walls, "dw": door_wall, "doors": doors,
			"phase": "walk", "t": 0.0, "walk": randf_range(1.3, 2.0), "fork": 0, "kinds": [], "pick": 1})
		pops.append({"at": o + Vector3(0, 0, -MAZE_PANEL.y / 2), "txt": "", "col": COLORS[k], "h": 0.6, "life": 99999.0, "size": 18, "maze": k})

# walk (the path scrolls) → doors (a wall with 3 doors slides in; the path's
# walls stop at it) → the spirit walks THROUGH its door → what's behind it:
#   ✓ right way · 💰 treasure room (right way + a prize) → on to the next room
#   🕳 trap door · 💥 spikes (−30 HP) · ↩ wrong way (back a room) → back out
const ROOM_GOOD := ["right", "treasure"]
const ROOM_BAD := ["trapdoor", "spikes", "wrong"]
const ROOM_MARK := {"right": Color("ffd24d"), "treasure": Color("ffd24d"), "trapdoor": Color("8a5ad0"),
	"spikes": Color("ff4040"), "wrong": Color("9a9aa8")}

func _tick_maze(dt: float) -> void:
	for k in 4:
		var p: Dictionary = g["p"][k]
		var o: Vector3 = p["o"]
		var n: Node3D = p["n"]
		p["t"] += dt
		p["lamp"].light_energy = 2.5 + sin(t * 17 + k) * 0.3 + randf() * 0.2
		var scroll := 0.0
		match p["phase"]:
			"walk":
				scroll = 2.2
				if p["t"] > p["walk"]:
					p["phase"] = "doors"
					p["t"] = 0.0
					var bad := ROOM_BAD.duplicate()
					bad.shuffle()
					var kinds := [ROOM_GOOD[0] if randf() < 0.7 else ROOM_GOOD[1], bad[0], bad[1]]
					kinds.shuffle()
					p["kinds"] = kinds
					p["dw"].visible = true
					p["dw"].position.z = o.z - 2.6
					for a in 3:
						var d: Dictionary = p["doors"][a]
						d["gap"].material_override = mat(Color("0a0a10"), true)
						d["mark"].material_override = mat(ROOM_MARK[kinds[a]], true)
						d["mark"].visible = randf() < (0.5 if kinds[a] in ROOM_GOOD else 0.65)
			"doors":   # the wall slides in as the spirit walks up to it
				scroll = 2.2 * (1.0 - minf(1.0, p["t"] / 0.6))
				p["dw"].position.z = lerpf(o.z - 2.6, o.z - 1.4, minf(1.0, p["t"] / 0.6))
				if p["t"] > 1.0:
					var pick := randi() % 3
					for a in 3:   # follow a visible good sign, avoid visible bad ones
						if p["doors"][a]["mark"].visible and p["kinds"][a] in ROOM_GOOD and randf() < 0.85:
							pick = a
					p["pick"] = pick
					p["phase"] = "to_door"
					p["t"] = 0.0
			"to_door":   # walk up to the chosen door…
				var door := Vector3(o.x + (p["pick"] - 1) * 2.4, 0, p["dw"].position.z + 0.4)
				n.position.x = lerpf(n.position.x, door.x, minf(1.0, dt * 4))
				n.position.z = lerpf(n.position.z, door.z, minf(1.0, dt * 4))
				if p["t"] > 0.6:
					p["phase"] = "in_door"
					p["t"] = 0.0
					p["doors"][p["pick"]]["gap"].material_override = mat(ROOM_MARK[p["kinds"][p["pick"]]], true)
			"in_door":   # …and through it (it fades into the doorway)
				n.position.z -= dt * 2.0
				n.scale = Vector3.ONE * maxf(0.05, 1.0 - p["t"] * 1.6)
				if p["t"] > 0.55:
					p["phase"] = "effect"
					p["t"] = 0.0
					_room_effect(k, p["kinds"][p["pick"]])
			"effect":   # the room behind the door does its thing
				var kind: String = p["kinds"][p["pick"]]
				if kind == "trapdoor":
					n.position.y -= dt * 4.0
				if p["t"] > 0.9:
					p["t"] = 0.0
					n.scale = Vector3.ONE
					n.position = Vector3(o.x, 0, o.z + 1.6)
					p["phase"] = "through" if kind in ROOM_GOOD else "back"
					if kind in ROOM_GOOD:
						p["dw"].visible = false   # on into the next room
			"through", "back":
				scroll = 2.4 if p["phase"] == "through" else -2.4
				if p["phase"] == "back":
					p["dw"].position.z -= dt * 2.4
				if p["t"] > 1.0:
					p["dw"].visible = false
					p["phase"] = "walk"
					p["t"] = 0.0
					p["walk"] = randf_range(1.3, 2.0)
					p["lamp"].light_color = Color("ffc870")
		# the path's walls scroll, and never poke past the door wall
		for w in p["walls"]:
			w.position.z += dt * scroll
			if w.position.z > o.z + 3.0:
				w.position.z -= 6.3
			elif w.position.z < o.z - 3.3:
				w.position.z += 6.3
			w.visible = not p["dw"].visible or w.position.z > p["dw"].position.z + 0.5
		if p["phase"] in ["walk", "through", "back"]:
			n.position.y = absf(sin(t * 8 + k)) * 0.12
		p["lamp"].position = n.position + Vector3(0, 2.2, 0)
		g["score"][k] = "room %d / 5" % p["fork"]
	for pp in pops:
		if pp.has("maze"):
			pp["txt"] = "%s [%s] — room %d / 5" % [NAMES[pp["maze"]], KEYS[pp["maze"]], g["p"][pp["maze"]]["fork"]]

func _room_effect(k: int, kind: String) -> void:
	var p: Dictionary = g["p"][k]
	var at: Vector3 = p["dw"].position + Vector3((p["pick"] - 1) * 2.4, 0, -0.4)
	match kind:
		"right":
			p["fork"] += 1
			pop(at, "✓ Right way!", Color("ffd24d"), 1.6, 1.0, 18)
		"treasure":
			p["fork"] += 1
			p["lamp"].light_color = Color("ffe070")
			pop(at, "💰 Treasure room! +10 gold", Color("ffd24d"), 1.6, 1.2, 18)
			for s in 10:
				var c := ball(0.12, Color("ffd24d"), at + Vector3(randf_range(-0.6, 0.6), randf_range(0.3, 1.4), randf_range(-0.3, 0.3)), true)
				get_tree().create_timer(0.9).timeout.connect(c.queue_free)
		"trapdoor":
			pop(at, "🕳 Trap door!", Color("c8a8ff"), 1.6, 1.0, 18)
		"spikes":
			p["lamp"].light_color = Color("ff5050")
			pop(at, "💥 Spikes! −30 HP", Color("ff6a6a"), 1.6, 1.0, 18)
		"wrong":
			p["fork"] = maxi(0, p["fork"] - 1)
			pop(at, "↩ Wrong way — back a room!", Color("c8c8e0"), 1.6, 1.0, 18)

# ── 📸 Ghost Snap ─────────────────────────────────────────────────────────────
func _setup_snap() -> void:
	_sky(Color("1c1830"), 0.55)
	cam.position = Vector3(0, 3.5, 25)
	cam.look_at(Vector3(0, 2.2, 0))
	g["p"] = []
	for k in 4:
		var cx := lane_x(k, 6.4)
		box(Vector3(5.6, 0.2, 6), Color("3a2e52"), Vector3(cx, -0.1, -1))
		box(Vector3(5.6, 5, 0.2), Color("2a2240"), Vector3(cx, 2.4, -4))
		for wx in [-2.8, 2.8]:
			box(Vector3(0.2, 5, 6), Color("221c36"), Vector3(cx + wx, 2.4, -1))
		var gh := spirit(-1, Vector3(cx, 1.4, -1.5), 0.035, ["Wispy", "Haunty", "Lullaboo", "Wispy"][k])
		var fl := light(Color.WHITE, Vector3(cx, 3, 2), 0.0, 9)
		frames.append([Vector3(cx, 2.4, -1.5), Vector2(46, 38)])
		var me := spirit(k, Vector3(cx, 0, 2.6), 0.024)
		tag(me, k, 2.2)
		g["p"].append({"gh": gh, "cx": cx, "fl": fl, "snap": randf_range(1.0, 2.0), "ph": randf() * 6})

func _tick_snap(dt: float) -> void:
	for k in 4:
		var p: Dictionary = g["p"][k]
		var ph: float = t * 1.4 + p["ph"]
		p["gh"].position = Vector3(p["cx"] + sin(ph) * 1.8, 1.2 + absf(sin(ph * 1.6)) * 1.8, -1.5 + cos(ph * 1.2) * 0.6)
		p["fl"].light_energy = maxf(0.0, p["fl"].light_energy - dt * 8)
		p["snap"] -= dt
		if p["snap"] <= 0:
			p["snap"] = randf_range(1.4, 2.4)
			p["fl"].light_energy = 4.0
			var d: float = (p["gh"].position - Vector3(p["cx"], 2.4, -1.5)).length()
			var r := ["PERFECT +3", Color("ffd24d"), 3] if d < 0.6 else (["NICE +2", Color("7be0a0"), 2] if d < 1.3 else (["BLURRY +1", Color("c8c8e0"), 1] if d < 1.9 else ["MISS", Color("ff6a6a"), 0]))
			pop(p["gh"], r[0], r[1], 2.6)
			g["score"][k] += r[2]

# ── 🏮 Lantern Memory ─────────────────────────────────────────────────────────
func _setup_memory() -> void:
	_sky(Color("0f0c1e"), 0.35)
	cam.position = Vector3(0, 6.5, 22)
	cam.look_at(Vector3(0, 1.6, 0))
	g["p"] = []
	g["seq"] = [0, 2]
	g["i"] = 0
	g["clock"] = 1.0
	g["mode"] = "show"
	for k in 4:
		var cx := lane_x(k, 6.2)
		box(Vector3(5.4, 0.2, 5), Color("2a2444"), Vector3(cx, -0.1, 0))
		var lans: Array = []
		for i in 3:
			var x: float = cx + (i - 1) * 1.6
			box(Vector3(0.1, 2.4, 0.1), Color("4a3a28"), Vector3(x, 1.2, -1.2))
			var l := ball(0.42, Color("553018"), Vector3(x, 2.6, -1.2), true)
			var pl := light(Color("ff9a40"), Vector3(x, 2.6, -0.8), 0.0, 4)
			lans.append({"l": l, "pl": pl})
		var s := spirit(k, Vector3(cx, 0, 1.4), 0.028)
		tag(s, k, 2.0)
		g["p"].append({"n": s, "cx": cx, "lans": lans})

func _tick_memory(dt: float) -> void:
	g["clock"] -= dt
	for p in g["p"]:
		for x in p["lans"]:
			x["l"].material_override.albedo_color = Color("553018")
			x["pl"].light_energy = 0.0
	var seq: Array = g["seq"]
	var lit := -1
	if g["mode"] == "show":
		if g["clock"] < 0.45 and g["clock"] > 0:
			lit = seq[g["i"]]
		if g["clock"] <= 0:
			g["i"] += 1
			g["clock"] = 0.7
			if g["i"] >= seq.size():
				g["mode"] = "copy"
				g["i"] = 0
				g["clock"] = 0.8
	else:
		if g["clock"] < 0.3:
			lit = seq[mini(g["i"], seq.size() - 1)]
		if g["clock"] <= 0:
			g["i"] += 1
			g["clock"] = 0.8
			if g["i"] >= seq.size():
				g["mode"] = "show"
				g["i"] = 0
				g["clock"] = 1.0
				seq.append(randi() % 3)
				for k in 4:
					g["score"][k] = "%d in a row" % (seq.size() - 1)
	for k in 4:
		var p: Dictionary = g["p"][k]
		if lit >= 0:
			p["lans"][lit]["l"].material_override.albedo_color = Color("ffd070")
			p["lans"][lit]["pl"].light_energy = 3.0
		var tx: float = p["cx"] + ((seq[mini(g["i"], seq.size() - 1)] - 1) * 1.6 if g["mode"] == "copy" else 0.0)
		p["n"].position.x = lerpf(p["n"].position.x, tx, minf(1.0, dt * 6))
		p["n"].position.y = absf(sin(t * 5 + k)) * 0.15

# ── 🎃 Pumpkin Toss ───────────────────────────────────────────────────────────
func _setup_toss() -> void:
	_sky(Color("6a9ad8"), 0.85)
	cam.position = Vector3(0, 15, 22)
	cam.look_at(Vector3(0, 0, -12))
	box(Vector3(18, 0.2, 70), Color("5a9a4a"), Vector3(0, -0.1, -26))
	for z in range(-5, -60, -5):
		box(Vector3(18, 0.03, 0.14), Color.WHITE, Vector3(0, 0.01, z), true)
	g["p"] = []
	for k in 4:
		var x := lane_x(k, 4.2)
		var s := spirit(k, Vector3(x, 0, 2), 0.03)
		tag(s, k, 2.2)
		box(Vector3(0.4, 3, 0.08), Color("222222"), Vector3(x + 1.2, 1.5, 1.9), true)
		var bar := box(Vector3(0.3, 1, 0.1), Color("ffd24d"), Vector3(x + 1.2, 0, 1.95), true)
		var pk := ball(0.42, Color("ff8a20"), Vector3(x, 1.2, 1.6))
		g["p"].append({"n": s, "x": x, "bar": bar, "pk": pk, "v": null, "pw": randf(), "dir": 1.0, "wait": randf() * 1.5, "total": 0})

func _tick_toss(dt: float) -> void:
	for k in 4:
		var p: Dictionary = g["p"][k]
		if p["v"] == null:
			p["pw"] += p["dir"] * dt * 1.4
			if p["pw"] > 1.0 or p["pw"] < 0.0:
				p["dir"] *= -1
			p["pw"] = clampf(p["pw"], 0, 1)
			p["bar"].scale.y = maxf(0.01, p["pw"] * 3.0)
			p["bar"].position.y = p["pw"] * 1.5
			p["wait"] -= dt
			if p["wait"] < 0 and p["pw"] > 0.75:
				p["v"] = Vector3(0, 7.5 * p["pw"], -15 * p["pw"])
		else:
			var v: Vector3 = p["v"]
			v.y -= 14 * dt
			p["v"] = v
			p["pk"].position += v * dt
			p["pk"].rotation.x += dt * 8
			if p["pk"].position.y < 0.42:
				var m := int(-p["pk"].position.z + 2)
				p["total"] += m
				pop(p["pk"], "%d m" % m, Color("ffd24d"))
				box(Vector3(0.08, 1.4, 0.08), COLORS[k], p["pk"].position + Vector3(0, 0.3, 0), true)   # the marker stays
				box(Vector3(0.5, 0.3, 0.04), COLORS[k], p["pk"].position + Vector3(0.25, 0.85, 0), true)
				p["pk"].position = Vector3(p["x"], 1.2, 1.6)
				p["v"] = null
				p["wait"] = randf_range(1.2, 2.0)
		g["score"][k] = "%d m" % p["total"]

# ── 😱 Scare-Off ──────────────────────────────────────────────────────────────
func _setup_scare() -> void:
	_sky(Color("e0884a"), 0.85)
	cam.position = Vector3(0, 8, 23)
	cam.look_at(Vector3(0, 1.2, -1))
	box(Vector3(26, 0.2, 12), Color("8a6a3a"), Vector3(0, -0.1, -1))
	g["p"] = []
	for k in 4:
		var x := lane_x(k, 5.8)
		var s := spirit(k, Vector3(x, 0, 2.6), 0.036)
		tag(s, k, 2.8)
		var sc := Node3D.new()
		sc.position = Vector3(x, 0, -2.5)
		stage.add_child(sc)
		for part in [[Vector3(0.16, 2.6, 0.16), Vector3(0, 1.3, 0), Color("6a4a2a")], [Vector3(2.0, 0.14, 0.14), Vector3(0, 1.9, 0), Color("6a4a2a")]]:
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = part[0]
			mi.mesh = bm
			mi.material_override = mat(part[2])
			mi.position = part[1]
			sc.add_child(mi)
		var head := MeshInstance3D.new()
		var hm := SphereMesh.new()
		hm.radius = 0.55
		hm.height = 1.1
		head.mesh = hm
		head.material_override = mat(Color("ff8a20"))
		head.position.y = 2.8
		sc.add_child(head)
		box(Vector3(0.35, 2.4, 0.08), Color("222222"), Vector3(x + 1.8, 1.4, 2.6), true)
		var meter := box(Vector3(0.28, 1, 0.1), Color("ff5a5a"), Vector3(x + 1.8, 0.2, 2.65), true)
		g["p"].append({"n": s, "sc": sc, "x": x, "m": meter, "f": 0.0, "rate": randf_range(0.22, 0.38), "run": 0.0})

func _tick_scare(dt: float) -> void:
	for k in 4:
		var p: Dictionary = g["p"][k]
		if p["run"] <= 0:
			p["f"] = maxf(0.0, p["f"] + (p["rate"] * dt * 4.0 if randf() < 0.5 else 0.0) - dt * 0.1)
			p["n"].scale = Vector3.ONE * (1.0 + absf(sin(t * (14 + k))) * 0.2 + p["f"] * 0.35)
			if p["f"] >= 1.0:
				p["run"] = 2.4
				pop(p["n"], "BOO!", Color("ffd24d"), 3.8, 1.2, 36)
				g["score"][k] += 1
		else:
			p["run"] -= dt
			p["sc"].position.z -= dt * 6
			p["sc"].rotation.y += dt * 7
			p["sc"].position.y = absf(sin(t * 14)) * 0.4
			if p["run"] <= 0:
				p["f"] = 0.0
				p["sc"].position = Vector3(p["x"], 0, -2.5)
				p["sc"].rotation.y = 0
				p["n"].scale = Vector3.ONE
		p["m"].scale.y = maxf(0.01, p["f"] * 2.4)
		p["m"].position.y = 0.2 + p["f"] * 1.2

# ── 🏁 Haunted Dash ───────────────────────────────────────────────────────────
func _setup_dash() -> void:
	_sky(Color("2a2452"), 0.75)
	for k in 4:
		box(Vector3(3.2, 0.1, 50), Color("3a3266") if k % 2 else Color("443a74"), Vector3(lane_x(k, 3.4), -0.05, -20))
	box(Vector3(14, 0.12, 0.5), Color.WHITE, Vector3(0, 0, -42), true)
	g["p"] = []
	g["place"] = 0
	for k in 4:
		var s := spirit(k, Vector3(lane_x(k, 3.4), 0, 0), 0.03)
		tag(s, k, 2.2)
		g["p"].append({"n": s, "sp": randf_range(5.0, 7.5), "done": false})

func _tick_dash(dt: float) -> void:
	var lead := 0.0
	for k in 4:
		var p: Dictionary = g["p"][k]
		if p["n"].position.z > -42:
			p["n"].position.z -= p["sp"] * dt * (0.85 + sin(t * 3 + k) * 0.15)
			p["n"].position.y = absf(sin(t * 12 + k)) * 0.35
		elif not p["done"]:
			p["done"] = true
			g["place"] += 1
			g["score"][k] = ["1st", "2nd", "3rd", "4th"][g["place"] - 1]
			pop(p["n"], g["score"][k] + "!", Color("ffd24d") if g["place"] == 1 else Color.WHITE)
		lead = minf(lead, p["n"].position.z)
	cam.position = Vector3(0, 12, lead + 19)
	cam.look_at(Vector3(0, 0, lead - 5))

# ── 🎈 Wisp Float ─────────────────────────────────────────────────────────────
func _setup_float() -> void:
	_sky(Color("101830"), 0.7)
	cam.position = Vector3(0, 6.5, 21)
	cam.look_at(Vector3(0, 6.5, 0))
	g["p"] = []
	g["things"] = []
	for k in 4:
		var y0 := (3 - k) * 3.6    # four stacked tunnels, P1 on top
		box(Vector3(26, 0.1, 1.6), Color("22304a"), Vector3(0, y0 - 0.05, 0))
		box(Vector3(26, 0.1, 1.6), Color("22304a"), Vector3(0, y0 + 3.1, 0))
		var s := spirit(k, Vector3(-8, y0 + 1, 0), 0.02)
		tag(s, k, 1.5)
		g["p"].append({"n": s, "y0": y0, "vy": 0.0, "stun": 0.0})

func _tick_float(dt: float) -> void:
	if randf() < dt * 5.0:
		var k := randi() % 4
		var bat := randf() < 0.3
		var y: float = g["p"][k]["y0"] + randf_range(0.4, 2.6)
		var m: MeshInstance3D = box(Vector3(0.7, 0.25, 0.4), Color("3a2050"), Vector3(13, y, 0)) if bat else ball(0.25, Color("9fe8ff"), Vector3(13, y, 0), true)
		g["things"].append({"m": m, "k": k, "bat": bat})
	for k in 4:
		var p: Dictionary = g["p"][k]
		var want := false
		for x in g["things"]:
			if not x["bat"] and x["k"] == k and x["m"].position.x < -4 and x["m"].position.x > -8:
				want = x["m"].position.y > p["n"].position.y + 0.4
		p["vy"] += (12.0 if want and p["stun"] <= 0 else -10.0) * dt
		p["vy"] *= 0.94
		p["n"].position.y = clampf(p["n"].position.y + p["vy"] * dt, p["y0"] + 0.1, p["y0"] + 2.2)
		p["stun"] -= dt
	for i in range(g["things"].size() - 1, -1, -1):
		var x: Dictionary = g["things"][i]
		x["m"].position.x -= dt * (6.0 if x["bat"] else 4.0)
		var p: Dictionary = g["p"][x["k"]]
		if absf(x["m"].position.x - p["n"].position.x) < 0.6 and absf(x["m"].position.y - p["n"].position.y - 0.7) < 0.8:
			pop(p["n"], "−1" if x["bat"] else "+1", Color("ff6a6a") if x["bat"] else Color("9fe8ff"), 1.8)
			g["score"][x["k"]] += -1 if x["bat"] else 1
			if x["bat"]:
				p["stun"] = 0.6
			x["m"].queue_free()
			g["things"].remove_at(i)
		elif x["m"].position.x < -13:
			x["m"].queue_free()
			g["things"].remove_at(i)
