extends Node3D
## DEMO ONLY (not wired into the game): a 3D "active" battle arena. Two spirits
## roam their halves of a pitch, leap across to attack, charge special moves,
## and backups hop in from beside each trainer. Run this scene on its own
## (F6 in the editor) to watch it loop.

const RED := ["Cinderwisp", "Zapkin", "Mossprig"]
const BLUE := ["Puddleboo", "Wispy", "Dreamwisp"]
const MOVES := ["Ember Burst", "Thunderclap", "Leaf Storm", "Soak", "Shadow Sneak", "Mind Blast"]
const FIELD := Rect2(80, 40, 520, 290)   # arena in "pixel" space; 20 px = 1 unit
const PIX := 0.085                       # Sprite3D pixel size (60 px frame → ~5 units)

var cam: Camera3D
var ui: Control
var log_label: Label
var sides: Array = []
var pops: Array = []
var fx: Array = []
var t := 0.0
var shake := 0.0
var turn := 0
var cool := 1.2
var over := false
var restart_t := 0.0

func _ready() -> void:
	randomize()
	_build_world()
	_reset()

func _w(x: float, y: float, h: float = 0.0) -> Vector3:
	return Vector3((x - 340.0) / 20.0, h, (y - 185.0) / 20.0)

# ── world ─────────────────────────────────────────────────────────────────────
func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("9fd0ea")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.8, 0.75)
	e.ambient_light_energy = 0.7
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	add_child(sun)
	cam = Camera3D.new()
	cam.fov = 40
	cam.position = Vector3(0, 21, 22)
	add_child(cam)
	cam.look_at(Vector3(0, 0, 1))
	# grass around the pitch
	var ground := MeshInstance3D.new()
	var gm := PlaneMesh.new()
	gm.size = Vector2(120, 80)
	ground.mesh = gm
	ground.position.y = -0.02
	ground.material_override = _mat(Color("5f9e55"))
	add_child(ground)
	# the pitch: stripes, outline, centre line and circle
	var img := Image.create(1040, 580, false, Image.FORMAT_RGB8)
	for i in 16:
		img.fill_rect(Rect2i(i * 65, 0, 65, 580), Color("7cc46a") if i % 2 else Color("8fd17a"))
	var white := Color(1, 1, 1)
	for r in [Rect2i(0, 0, 1040, 8), Rect2i(0, 572, 1040, 8), Rect2i(0, 0, 8, 580), Rect2i(1032, 0, 8, 580), Rect2i(516, 0, 8, 580)]:
		img.fill_rect(r, white)
	for a in 720:
		var ang := a / 720.0 * TAU
		for th in range(-4, 4):
			img.set_pixel(int(520 + cos(ang) * (95 + th)), int(290 + sin(ang) * (95 + th)), white)
	var pitch := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(26, 14.5)
	pitch.mesh = pm
	var pmat := StandardMaterial3D.new()
	pmat.albedo_texture = ImageTexture.create_from_image(img)
	pitch.material_override = pmat
	pitch.position = _w(340, 185)
	add_child(pitch)
	_trainer(30, "alain")
	_trainer(650, "adaman")
	# the bars / names / damage numbers are drawn flat on top
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.draw.connect(_draw_ui)
	layer.add_child(ui)
	log_label = Label.new()
	log_label.add_theme_font_size_override("font_size", 22)
	log_label.add_theme_color_override("font_outline_color", Color.BLACK)
	log_label.add_theme_constant_override("outline_size", 6)
	log_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	log_label.position.y -= 50
	log_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	log_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	layer.add_child(log_label)

func _mat(c: Color, unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m

func _trainer(x: float, key: String) -> void:
	var pad := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(3, 0.2, 5.5)
	pad.mesh = bm
	pad.material_override = _mat(Color("e8e2d0"))
	pad.position = _w(x, 185, 0.1)
	add_child(pad)
	var s := _sprite(GameData.trainer_texture([key, "acetrainer"]))
	s.pixel_size = 0.05
	s.position = _w(x, 185, 0.2)
	s.flip_h = x > 340
	add_child(s)

func _sprite(tex: Texture2D) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = tex
	s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.shaded = false
	s.centered = true
	if tex:
		s.offset.y = tex.get_height() * 0.4   # feet on the ground (frames have empty space below)
	return s

# ── fighters ──────────────────────────────────────────────────────────────────
func _mk(spirit_name: String, team: int, i: int) -> Dictionary:
	var node := Node3D.new()
	add_child(node)
	var spr := _sprite(SpiritsData.sprite_tex(spirit_name, "front"))
	spr.pixel_size = PIX
	spr.flip_h = team == 0   # face the other side
	node.add_child(spr)
	var shadow := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = 0.02
	shadow.mesh = cm
	var sm := _mat(Color(0, 0, 0, 0.3), true)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow.material_override = sm
	add_child(shadow)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.35
	tm.outer_radius = 1.6
	ring.mesh = tm
	ring.material_override = _mat(Color("ffd400"), true)
	ring.visible = false
	node.add_child(ring)
	return {"name": spirit_name, "team": team, "hp": 100.0, "max": 100.0, "ch": 0, "cost": 3 + i % 2,
		"atk": 12 + i * 2, "up": 0, "dn": 0, "x": 0.0, "y": 0.0, "h": 0.0, "tx": 0.0, "ty": 0.0,
		"st": "idle", "timer": 0.0, "r": 34.0, "alive": true, "flash": 0.0, "move": MOVES[(i + team * 3) % 6],
		"scale": 1.0, "squash": 0.0, "hurt_flash": 0.0, "node": node, "spr": spr, "shadow": shadow, "ring": ring}

func _reset() -> void:
	for s in sides:
		for m in [s["active"]] + s["bench"]:
			if m:
				m["node"].queue_free()
				m["shadow"].queue_free()
	for p in fx:
		p["m"].queue_free()
	fx.clear()
	pops.clear()
	sides = [
		{"tx": 30.0, "bench": [], "home": Vector2(220, 185), "slots": [Vector2(80, 60), Vector2(30, 60)]},
		{"tx": 650.0, "bench": [], "home": Vector2(460, 185), "slots": [Vector2(600, 312), Vector2(650, 312)]},
	]
	for k in 2:
		var names: Array = RED if k == 0 else BLUE
		for i in names.size():
			sides[k]["bench"].append(_mk(names[i], k, i))
		var a: Dictionary = sides[k]["bench"].pop_front()
		sides[k]["active"] = a
		a["x"] = sides[k]["tx"]
		a["y"] = 185.0
		a["st"] = "enter"
		_lay_bench(sides[k])
	over = false
	turn = 0
	cool = 1.2
	_say("Battle start!")

func _lay_bench(s: Dictionary) -> void:
	for j in s["bench"].size():
		var b: Dictionary = s["bench"][j]
		b["x"] = s["slots"][j].x
		b["y"] = s["slots"][j].y
		b["scale"] = 0.6

func _say(text: String) -> void:
	log_label.text = text

func _pick(a: Dictionary, k: int) -> void:
	var lo: float = FIELD.position.x + 50 if k == 0 else FIELD.position.x + FIELD.size.x / 2 + 50
	var hi: float = FIELD.position.x + FIELD.size.x / 2 - 50 if k == 0 else FIELD.end.x - 50
	a["tx"] = randf_range(lo, hi)
	a["ty"] = randf_range(FIELD.position.y + 50, FIELD.end.y - 50)

func _start_attack(k: int) -> bool:
	var a = sides[k]["active"]
	var d = sides[1 - k]["active"]
	if a == null or d == null or not a["alive"] or not d["alive"] or a["st"] != "idle" or d["st"] == "hurt":
		return false
	a["ch"] += 1
	a["special"] = a["ch"] >= a["cost"]
	a["st"] = "windup"
	a["timer"] = 0.0
	a["ox"] = a["x"]
	a["oy"] = a["y"]
	a["target"] = d
	if a["special"]:
		a["ch"] = 0
		a["flash"] = 1.3
		_say("%s uses %s!" % [a["name"], a["move"]])
	return true

func _burst(x: float, y: float, col: Color, n: int) -> void:
	for i in n:
		var m := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3.ONE * 0.25
		m.mesh = b
		m.material_override = _mat(col, true)
		m.position = _w(x, y, 1.4)
		add_child(m)
		fx.append({"m": m, "v": Vector3(randf_range(-7, 7), randf_range(2, 10), randf_range(-7, 7)), "life": 0.6})

func _hit(a: Dictionary, d: Dictionary) -> void:
	var sp: bool = a["special"]
	var dmg := roundi(a["atk"] * (1.0 + 0.15 * a["up"] - 0.1 * d["dn"]) * (1.8 if sp else 1.0) * randf_range(0.85, 1.15))
	d["hp"] = maxf(0.0, d["hp"] - dmg)
	d["st"] = "hurt"
	d["timer"] = 0.0
	d["hurt_flash"] = 0.3
	d["vx"] = (1.0 if d["x"] > a["x"] else -1.0) * (280.0 if sp else 170.0)
	shake = 0.5 if sp else 0.25
	pops.append({"x": d["x"], "y": d["y"], "h": 4.2, "txt": "-%d" % dmg, "col": Color("ffd400") if sp else Color("ff4040"), "life": 1.0})
	_burst(d["x"], d["y"], Color("ffd400") if sp else Color("ffffff"), 18 if sp else 9)
	if sp:
		if randf() < 0.5:
			a["up"] = mini(2, a["up"] + 1)
			pops.append({"x": a["x"], "y": a["y"], "h": 4.6, "txt": "ATK up", "col": Color("6a8cff"), "life": 1.2})
		else:
			d["dn"] = mini(2, d["dn"] + 1)
			pops.append({"x": d["x"], "y": d["y"], "h": 5.0, "txt": "DEF down", "col": Color("ff6070"), "life": 1.2})
	if d["hp"] > 0 and d["ch"] < d["cost"] - 1:
		d["ch"] += 1
	if d["hp"] <= 0:
		d["alive"] = false
		d["st"] = "faint"
		d["timer"] = 0.0
		_say("%s fainted!" % d["name"])

func _process(delta: float) -> void:
	var dt := minf(delta, 0.05)
	t += dt
	shake = maxf(0.0, shake - dt * 1.5)
	for k in 2:
		_step(k, dt)
	if not over:
		cool -= dt
		if cool <= 0.0:
			if _start_attack(turn % 2):
				turn += 1
				cool = randf_range(1.1, 1.7)
			else:
				cool = 0.2
	else:
		restart_t += dt
		if restart_t > 3.0:
			restart_t = 0.0
			_reset()
	for p in pops:
		p["h"] += dt * 1.2
		p["life"] -= dt
	pops = pops.filter(func(p): return p["life"] > 0)
	for p in fx:
		var v: Vector3 = p["v"]
		v.y -= 25 * dt
		p["v"] = v
		p["m"].position += v * dt
		p["m"].position.y = maxf(0.1, p["m"].position.y)
		p["m"].rotation.x += dt * 8
		p["life"] -= dt
		if p["life"] <= 0:
			p["m"].queue_free()
	fx = fx.filter(func(p): return p["life"] > 0)
	for s in sides:
		if s["active"]:
			_sync(s["active"])
		for b in s["bench"]:
			b["h"] = absf(sin(t * 3 + b["atk"])) * 0.15
			_sync(b)
	cam.h_offset = randf_range(-0.5, 0.5) * shake
	ui.queue_redraw()

func _step(k: int, dt: float) -> void:
	var s: Dictionary = sides[k]
	var a = s["active"]
	if a == null:
		return
	a["timer"] += dt
	a["flash"] = maxf(0.0, a["flash"] - dt)
	a["hurt_flash"] = maxf(0.0, a["hurt_flash"] - dt)
	match a["st"]:
		"enter":
			var h: Vector2 = s["home"]
			a["x"] = lerpf(a["x"], h.x, minf(1.0, dt * 3))
			a["y"] = lerpf(a["y"], h.y, minf(1.0, dt * 3))
			a["scale"] = lerpf(a["scale"], 1.0, minf(1.0, dt * 4))
			a["h"] = absf(sin(a["timer"] * 6)) * 0.8
			if Vector2(a["x"], a["y"]).distance_to(h) < 4:
				a["st"] = "idle"
				a["h"] = 0.0
				_pick(a, k)
		"idle":
			a["x"] = lerpf(a["x"], a["tx"], minf(1.0, dt * 1.5))
			a["y"] = lerpf(a["y"], a["ty"], minf(1.0, dt * 1.5))
			a["h"] = absf(sin(t * 5 + a["atk"])) * 0.25
			if Vector2(a["x"], a["y"]).distance_to(Vector2(a["tx"], a["ty"])) < 6:
				_pick(a, k)
		"windup":
			a["x"] += (-1.0 if a["x"] < a["target"]["x"] else 1.0) * dt * 40
			a["h"] = 0.0
			a["squash"] = minf(1.0, a["timer"] * 3)
			if a["timer"] > (0.6 if a["special"] else 0.3):
				a["st"] = "dash"
				a["timer"] = 0.0
				a["sx"] = a["x"]
				a["sy"] = a["y"]
				a["squash"] = 0.0
		"dash":
			var d: Dictionary = a["target"]
			var to := Vector2(d["x"] - a["x"], d["y"] - a["y"])
			var dist := to.length()
			var tot := maxf(1.0, Vector2(d["x"] - a["sx"], d["y"] - a["sy"]).length())
			a["h"] = sin(clampf(1.0 - dist / tot, 0, 1) * PI) * (3.0 if a["special"] else 1.6)
			if dist < a["r"] + d["r"]:
				_hit(a, d)
				a["st"] = "back"
				a["timer"] = 0.0
			else:
				var v := (to / dist) * (800.0 if a["special"] else 600.0) * dt
				a["x"] += v.x
				a["y"] += v.y
		"back":
			a["x"] = lerpf(a["x"], a["ox"], minf(1.0, dt * 5))
			a["y"] = lerpf(a["y"], a["oy"], minf(1.0, dt * 5))
			a["h"] = maxf(0.0, a["h"] - dt * 6)
			if a["timer"] > 0.5:
				a["st"] = "idle"
				_pick(a, k)
		"hurt":
			a["x"] = clampf(a["x"] + a["vx"] * dt, FIELD.position.x + a["r"], FIELD.end.x - a["r"])
			a["vx"] *= 0.9
			a["h"] = maxf(0.0, sin(a["timer"] * 7) * 0.8)
			if a["timer"] > 0.45:
				a["st"] = "idle" if a["alive"] else "faint"
				if a["alive"]:
					_pick(a, k)
		"faint":
			a["scale"] = maxf(0.0, 1.0 - a["timer"] * 1.2)
			if a["timer"] > 1.0:
				a["node"].queue_free()
				a["shadow"].queue_free()
				if not s["bench"].is_empty():
					var n: Dictionary = s["bench"].pop_front()
					n["st"] = "enter"
					n["timer"] = 0.0
					s["active"] = n
					_say(("Opponent sends out %s!" if k == 1 else "Go, %s!") % n["name"])
					_lay_bench(s)
				else:
					s["active"] = null
					over = true
					_say("%s side wins!" % ("Red" if k == 1 else "Blue"))

func _sync(m: Dictionary) -> void:
	var node: Node3D = m["node"]
	node.position = _w(m["x"], m["y"], m["h"])
	var sq: float = m["squash"]
	node.scale = Vector3(1.0 + sq * 0.15, 1.0 - sq * 0.2, 1.0 + sq * 0.15) * maxf(0.001, m["scale"])
	var spr: Sprite3D = m["spr"]
	spr.modulate = Color(1.6, 0.6, 0.6) if m["hurt_flash"] > 0 else Color.WHITE
	if m["st"] == "faint":
		spr.flip_h = int(t * 12) % 2 == 0   # a dizzy spin
	var ring: MeshInstance3D = m["ring"]
	ring.visible = m["flash"] > 0
	ring.position.y = 0.1 - m["h"]
	ring.scale = Vector3.ONE * (1.0 + sin(t * 20) * 0.1)
	var sh: MeshInstance3D = m["shadow"]
	sh.position = _w(m["x"], m["y"], 0.03)
	sh.scale = Vector3.ONE * m["scale"] * clampf(1.0 - m["h"] * 0.15, 0.4, 1.0)

# ── flat overlay: names, HP/charge bars, buff arrows, damage numbers ──────────
func _proj(x: float, y: float, h: float) -> Vector2:
	return cam.unproject_position(_w(x, y, h))

func _bars(m: Dictionary, p: Vector2, w: float, thin: bool) -> void:
	var hh := 6.0 if thin else 9.0
	ui.draw_rect(Rect2(p.x - w / 2 - 2, p.y - 2, w + 4, hh * 2 + 3), Color(0, 0, 0, 0.55))
	var f: float = m["hp"] / m["max"]
	ui.draw_rect(Rect2(p.x - w / 2, p.y, w * f, hh), Color("2ad05a") if f > 0.5 else (Color("f0b020") if f > 0.25 else Color("f03030")))
	ui.draw_rect(Rect2(p.x - w / 2, p.y + hh + 1, w * minf(1.0, float(m["ch"]) / m["cost"]), hh - 2), Color("ffd400"))

func _text(s: String, p: Vector2, col: Color, size: int) -> void:
	var font := ThemeDB.fallback_font
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	ui.draw_string_outline(font, p - Vector2(w / 2, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 6, Color(0, 0, 0, 0.8))
	ui.draw_string(font, p - Vector2(w / 2, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

func _arrows(m: Dictionary, p: Vector2, size: int) -> void:
	_text("▲" + ("2" if m["up"] > 1 else ""), p + Vector2(-size, 0), Color("6a8cff") if m["up"] else Color(0.42, 0.55, 1, 0.3), size)
	_text("▼" + ("2" if m["dn"] > 1 else ""), p + Vector2(size, 0), Color("ff5060") if m["dn"] else Color(1, 0.31, 0.38, 0.3), size)

func _draw_ui() -> void:
	for s in sides:
		for b in s["bench"]:
			var bp := _proj(b["x"], b["y"], 0)
			_bars(b, bp + Vector2(0, 10), 56, true)
			_arrows(b, bp + Vector2(0, 44), 14)
		var a = s["active"]
		if a and a["st"] != "faint":
			var p := _proj(a["x"], a["y"], a["h"] + 5.0)
			_text(a["name"], p + Vector2(0, -6), Color.WHITE, 20)
			_bars(a, p + Vector2(0, 2), 96, false)
			_arrows(a, p + Vector2(76, 18), 18)   # beside the bars, clear of the sprite
			if a["flash"] > 0:
				_text("✦ " + a["move"], p + Vector2(0, -32), Color("ffd400"), 24)
	for pp in pops:
		var q := _proj(pp["x"], pp["y"], pp["h"])
		var c: Color = pp["col"]
		c.a = minf(1.0, pp["life"] * 2)
		_text(pp["txt"], q, c, 26)
