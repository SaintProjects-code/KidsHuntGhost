extends Control
## The 3D stage a minigame draws into on the 3D maps (CompGame makes one when
## the game has _build_3d / _update_3d). It owns the SubViewport, camera,
## lights and a flat overlay for names, scores and pop-up text, plus small
## builders (boxes, balls, lights, spirit sprites). The game's rules don't
## change: its _update_3d just moves 3D things to match its lane state.

var vp: SubViewport
var world: Node3D
var cam: Camera3D
var env: Environment
var sun: DirectionalLight3D
var _overlay: Control
var tags: Array = []     # {at: Node3D|Vector3, text: Callable|String, col, h, size}
var pops: Array = []     # {at, text, col, h, life, size}

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := SubViewportContainer.new()
	box.stretch = true
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(box)
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_2X
	box.add_child(vp)
	world = Node3D.new()
	vp.add_child(world)
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("15122a")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.82, 0.9)
	env.ambient_light_energy = 0.7
	we.environment = env
	world.add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_energy = 0.9
	world.add_child(sun)
	cam = Camera3D.new()
	cam.fov = 42
	world.add_child(cam)
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)

# The game area is wide and short, so every camera moves in this much closer
# (less so with 5–6 players, so everyone stays in view).
const ZOOM := 0.66
var lanes_n := 4

func fit_zoom() -> float:
	return ZOOM + maxf(0.0, lanes_n - 4) * 0.13

# Camera placed with a transform (works before the stage is in the tree).
func aim(from: Vector3, at: Vector3, zoom := -1.0) -> void:
	if zoom < 0.0:
		zoom = fit_zoom()
	cam.transform = Transform3D(Basis(), at + (from - at) * zoom).looking_at(at, Vector3.UP)

func sky(col: Color, ambient: float, sun_energy := 0.9) -> void:
	env.background_color = col
	env.ambient_light_energy = ambient
	sun.light_energy = sun_energy

func _process(delta: float) -> void:
	for p in pops:
		p["life"] -= delta
		p["h"] += delta * 1.2
	pops = pops.filter(func(p): return p["life"] > 0.0)
	_overlay.queue_redraw()

# ── builders ──────────────────────────────────────────────────────────────────
func mat(c: Color, unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m

func box(sz: Vector3, c: Color, at: Vector3, unshaded := false, parent: Node = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = sz
	mi.mesh = b
	mi.material_override = mat(c, unshaded)
	mi.position = at
	(parent if parent else world).add_child(mi)
	return mi

func ball(r: float, c: Color, at: Vector3, unshaded := false, parent: Node = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2
	mi.mesh = s
	mi.material_override = mat(c, unshaded)
	mi.position = at
	(parent if parent else world).add_child(mi)
	return mi

func lamp(c: Color, at: Vector3, energy: float, rng: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = c
	l.light_energy = energy
	l.omni_range = rng
	l.position = at
	world.add_child(l)
	return l

# A spirit standing in the world: its sprite (always upright, facing the
# camera) and a ring in the player's colour under its feet.
func spirit(tex: Texture2D, col: Color, at: Vector3, px := 0.03, face_cam := false) -> Node3D:
	var n := Node3D.new()
	n.position = at
	world.add_child(n)
	var s := Sprite3D.new()
	s.name = "Sprite"
	s.texture = tex
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED if face_cam else BaseMaterial3D.BILLBOARD_FIXED_Y
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.shaded = false
	s.pixel_size = px
	s.offset.y = 24
	n.add_child(s)
	if col.a > 0.0:
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.75
		tm.outer_radius = 0.95
		ring.mesh = tm
		ring.material_override = mat(col, true)
		ring.position.y = 0.05
		ring.scale = Vector3.ONE * clampf(px / 0.05, 0.4, 1.0)
		n.add_child(ring)
	return n

static func sprite_of(n: Node3D) -> Sprite3D:
	return n.get_node("Sprite") as Sprite3D

# x of lane i of n, `gap` apart, centred on 0.
static func lane_x(i: int, n: int, gap: float) -> float:
	return (i - (n - 1) * 0.5) * gap

# ── overlay text ──────────────────────────────────────────────────────────────
# A label that follows a node (or sits at a point); `text` can be a Callable
# so it updates every frame.
func tag(at, text, col: Color, h := 2.2, size := 15) -> void:
	tags.append({"at": at, "text": text, "col": col, "h": h, "size": size})

func pop(at, text: String, col: Color, h := 2.2, life := 1.0, size := 22) -> void:
	pops.append({"at": at, "text": text, "col": col, "h": h, "life": life, "size": size})

func _pos(at) -> Vector3:
	if at is Node3D:
		return (at as Node3D).global_position if is_instance_valid(at) and (at as Node3D).is_inside_tree() else Vector3(0, -999, 0)
	return at

func _draw_overlay() -> void:
	var font := ThemeDB.fallback_font
	var k := _overlay.size / Vector2(maxi(1, vp.size.x), maxi(1, vp.size.y))
	for list in [tags, pops]:
		for p in list:
			var at := _pos(p["at"])
			if at.y < -900.0:
				continue
			var w3 := at + Vector3(0, p["h"], 0)
			if cam.is_position_behind(w3):
				continue
			var s := cam.unproject_position(w3) * k
			var txt := String(p["text"].call() if p["text"] is Callable else p["text"])
			if txt == "":
				continue
			var c: Color = p["col"]
			if p.has("life"):
				c.a = minf(1.0, p["life"] * 2.0)
			var size: int = p["size"]
			var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			_overlay.draw_string_outline(font, s - Vector2(w / 2, 0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 6, Color(0, 0, 0, 0.85 * c.a))
			_overlay.draw_string(font, s - Vector2(w / 2, 0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size, c)
