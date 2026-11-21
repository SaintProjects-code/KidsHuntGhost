extends RefCounted
## Move effects for the 3D battle arena: glowing beams, lightning, impact
## explosions (flash + spikes + shockwave + debris + smoke), waves, clouds,
## orbs and auras. Every effect is a set of unshaded, additive meshes that
## live for a moment; BattleArena calls tick(dt) every frame.
## Positions can be Callables (returning Vector3) so a beam follows a spirit
## that's knocked back while it fires.

var world: Node3D
var _live: Array = []          # {nodes: Array, life, max, tick: Callable}
var _mats := {}

func _init(w: Node3D) -> void:
	world = w

# ── materials / meshes ────────────────────────────────────────────────────────

func glow(c: Color, alpha := 1.0, additive := false) -> StandardMaterial3D:
	var key := "%s|%.2f|%s" % [c.to_html(), alpha, additive]
	if _mats.has(key):
		return (_mats[key] as StandardMaterial3D).duplicate()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	m.albedo_color = Color(c.r, c.g, c.b, alpha)
	_mats[key] = m
	return m.duplicate()

func flat(c: Color, alpha := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(c.r, c.g, c.b, alpha)
	return m

func _prio(m: StandardMaterial3D, p: int) -> StandardMaterial3D:
	m.render_priority = p
	return m

func _mesh(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mi)
	return mi

func _cyl(r: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = 1.0
	c.radial_segments = 12
	c.rings = 1
	return c

func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2
	s.radial_segments = 16
	s.rings = 8
	return s

func _torus(r: float, thick: float) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = r - thick
	t.outer_radius = r
	t.rings = 32
	t.ring_segments = 6
	return t

func _pos(p) -> Vector3:
	return p.call() if p is Callable else p

# Stretch a unit-height cylinder from a to b.
func _span(mi: MeshInstance3D, a: Vector3, b: Vector3, r_scale := 1.0) -> void:
	var d := b - a
	var len := d.length()
	if len < 0.001:
		mi.visible = false
		return
	mi.visible = true
	# rotate the unit cylinder onto a→b, then stretch it along its OWN axis
	var basis := Basis(Quaternion(Vector3.UP, d / len)) * Basis.from_scale(Vector3(r_scale, len, r_scale))
	mi.transform = Transform3D(basis, (a + b) * 0.5)

func _add(nodes: Array, life: float, tick: Callable) -> void:
	_live.append({"nodes": nodes, "life": life, "max": life, "tick": tick})

func tick(dt: float) -> void:
	for e in _live:
		e["life"] -= dt
		var k: float = 1.0 - clampf(e["life"] / e["max"], 0.0, 1.0)   # 0 → 1 over its life
		e["tick"].call(k, dt)
		if e["life"] <= 0.0:
			for n in e["nodes"]:
				if is_instance_valid(n):
					n.queue_free()
	_live = _live.filter(func(e): return e["life"] > 0.0)

func clear() -> void:
	for e in _live:
		for n in e["nodes"]:
			if is_instance_valid(n):
				n.queue_free()
	_live.clear()

func _fade(mi: MeshInstance3D, a: float) -> void:
	var m := mi.material_override as StandardMaterial3D
	if m:
		var c := m.albedo_color
		c.a = a
		m.albedo_color = c

# ── beams ─────────────────────────────────────────────────────────────────────

# A thick glowing beam: a coloured glow, a bright inner layer and a white core,
# pulsing, with rings racing down it. It shoots out over the first 15% of its
# life and thins away over the last 25%.
func beam(from, to, col: Color, width := 0.55, life := 0.75) -> void:
	# layers drawn outside-in (render_priority) so the hot core shows through
	var outer := _mesh(_cyl(width), _prio(glow(col, 0.4), 0))
	var mid := _mesh(_cyl(width * 0.62), _prio(glow(col.lightened(0.35), 0.85), 1))
	var core := _mesh(_cyl(width * 0.3), _prio(glow(Color(1, 1, 0.9), 1.0), 2))
	var rings: Array = []
	for i in 4:
		rings.append(_mesh(_torus(width * 1.25, width * 0.25), glow(col.lightened(0.3), 0.8)))
	var muzzle := _mesh(_sphere(width * 0.95), glow(col.lightened(0.35), 0.85))
	var nodes: Array = [outer, mid, core, muzzle] + rings
	_add(nodes, life, func(k: float, _dt: float):
		var a := _pos(from)
		var b := _pos(to)
		var reach := clampf(k / 0.15, 0.0, 1.0)
		var end := a.lerp(b, reach)
		var thin := 1.0 - clampf((k - 0.75) / 0.25, 0.0, 1.0)
		var pulse := 1.0 + sin(k * 60.0) * 0.12
		_span(outer, a, end, pulse * thin)
		_span(mid, a, end, (2.0 - pulse) * thin)
		_span(core, a, end, thin)
		muzzle.position = a
		muzzle.scale = Vector3.ONE * pulse * thin
		var dir := (b - a).normalized()
		for i in rings.size():
			var r: MeshInstance3D = rings[i]
			var t := fmod(k * 3.0 + i / float(rings.size()), 1.0) * reach
			r.visible = thin > 0.2
			r.transform = Transform3D(Basis(Quaternion(Vector3.UP, dir)) * Basis.from_scale(Vector3.ONE * thin * (0.6 + t * 0.6)), a.lerp(b, t)))

# Jagged lightning between two points, re-drawn every few frames.
func bolt(from, to, col: Color, life := 0.45, segs := 8, width := 0.16) -> void:
	var parts: Array = []
	for i in segs:
		parts.append(_mesh(_cyl(width), glow(col, 0.9)))
	var cores: Array = []
	for i in segs:
		cores.append(_mesh(_cyl(width * 0.4), glow(Color.WHITE, 1.0)))
	var state := {"t": 0.0, "pts": []}
	_add(parts + cores, life, func(k: float, dt: float):
		state["t"] -= dt
		var a := _pos(from)
		var b := _pos(to)
		if state["t"] <= 0.0 or state["pts"].size() != segs + 1:
			state["t"] = 0.05
			var pts: Array = [a]
			var side := (b - a).cross(Vector3.UP).normalized()
			for i in range(1, segs):
				var p := a.lerp(b, i / float(segs))
				p += side * randf_range(-0.9, 0.9) + Vector3.UP * randf_range(-0.6, 0.6)
				pts.append(p)
			pts.append(b)
			state["pts"] = pts
		var fade := 1.0 - clampf((k - 0.6) / 0.4, 0.0, 1.0)
		for i in segs:
			_span(parts[i], state["pts"][i], state["pts"][i + 1], fade)
			_span(cores[i], state["pts"][i], state["pts"][i + 1], fade))

# ── impacts ───────────────────────────────────────────────────────────────────

# The big hit: a white-hot flash in the move's colour, spikes bursting out,
# a ground shockwave and smoke.
func explosion(at: Vector3, col: Color, big := false) -> void:
	var s := 1.5 if big else 1.0
	var ball := _mesh(_sphere(1.0), _prio(glow(col, 0.75), 3))
	var hot := _mesh(_sphere(0.6), _prio(glow(Color(1, 0.97, 0.85), 1.0), 4))
	var spikes: Array = []
	var dirs: Array = []
	for i in (16 if big else 11):
		spikes.append(_mesh(_cyl(0.09), _prio(glow(col.lightened(0.5), 1.0), 5)))
		dirs.append(Vector3(randf_range(-1, 1), randf_range(-0.3, 1), randf_range(-1, 1)).normalized())
	_add([ball, hot] + spikes, 0.45, func(k: float, _dt: float):
		var r := s * (0.4 + k * 2.4)
		ball.position = at
		ball.scale = Vector3.ONE * r
		_fade(ball, 0.9 * (1.0 - k))
		hot.position = at
		hot.scale = Vector3.ONE * s * (1.0 - k) * 1.4
		for i in spikes.size():
			var d: Vector3 = dirs[i]
			_span(spikes[i], at + d * r * 0.5, at + d * r * (1.6 + k), 1.0 - k))
	shockwave(Vector3(at.x, 0.15, at.z), col, 4.0 * s)
	smoke(at, 6 if big else 4)

func shockwave(at: Vector3, col: Color, radius := 4.0, life := 0.5) -> void:
	var ring := _mesh(_torus(1.0, 0.18), glow(col.lightened(0.3), 0.9))
	_add([ring], life, func(k: float, _dt: float):
		ring.position = at
		ring.scale = Vector3(1, 0.4, 1) * (0.3 + k * radius)
		_fade(ring, 0.9 * (1.0 - k)))

func smoke(at: Vector3, n := 4, col := Color(0.82, 0.82, 0.86)) -> void:
	for i in n:
		var puff := _mesh(_sphere(0.7), flat(col, 0.55))
		var off := Vector3(randf_range(-1.2, 1.2), randf_range(0, 0.8), randf_range(-1.0, 1.0))
		var life := randf_range(0.8, 1.3)
		_add([puff], life, func(k: float, _dt: float):
			puff.position = at + off + Vector3(0, k * 1.8, 0)
			puff.scale = Vector3.ONE * (0.6 + k * 1.4)
			_fade(puff, 0.55 * (1.0 - k)))

# Little cubes thrown out of a hit.
func debris(at: Vector3, col: Color, n := 10) -> void:
	for i in n:
		var c := _mesh(BoxMesh.new(), flat(col))
		c.scale = Vector3.ONE * randf_range(0.18, 0.32)
		var v := Vector3(randf_range(-7, 7), randf_range(3, 11), randf_range(-7, 7))
		var st := {"p": at, "v": v}
		_add([c], 0.7, func(_k: float, dt: float):
			var vv: Vector3 = st["v"] + Vector3(0, -28, 0) * dt
			var pp: Vector3 = st["p"] + vv * dt
			pp.y = maxf(0.1, pp.y)
			st["v"] = vv
			st["p"] = pp
			c.position = pp
			c.rotation += Vector3(8, 5, 0) * dt)

# ── other move shapes ─────────────────────────────────────────────────────────

# An orb flung in an arc; `on_land` fires when it arrives.
func lob(from, to, col: Color, life := 0.35) -> void:
	var orb := _mesh(_sphere(0.6), glow(col, 0.9))
	var core := _mesh(_sphere(0.3), glow(Color.WHITE, 1.0))
	_add([orb, core], life, func(k: float, _dt: float):
		var p := _pos(from).lerp(_pos(to), k) + Vector3(0, sin(k * PI) * 3.0, 0)
		orb.position = p
		core.position = p
		orb.scale = Vector3.ONE * (1.0 + sin(k * 40.0) * 0.15))

# A bolt from the sky straight down onto a spot.
func sky_bolt(to, col: Color) -> void:
	var top := func(): return _pos(to) + Vector3(randf_range(-0.5, 0.5), 14.0, 0)
	bolt(top, to, col, 0.4, 10, 0.22)
	flash_column(to, col)

func flash_column(at, col: Color) -> void:
	var col_mesh := _mesh(_cyl(1.2), glow(col, 0.5))
	_add([col_mesh], 0.3, func(k: float, _dt: float):
		var p := _pos(at)
		_span(col_mesh, Vector3(p.x, 0, p.z), Vector3(p.x, 14, p.z), 1.0 - k))

# A wall of fire/energy sweeping across the pitch from one side to the other.
func wave(from_x: float, to_x: float, col: Color, life := 0.6) -> void:
	var wall := _mesh(BoxMesh.new(), glow(col, 0.6))
	var crest := _mesh(BoxMesh.new(), glow(col.lightened(0.5), 0.9))
	_add([wall, crest], life, func(k: float, _dt: float):
		var x := lerpf(from_x, to_x, k)
		var h := 2.5 + sin(k * PI) * 1.5
		wall.position = Vector3(x, h * 0.5, 0)
		wall.scale = Vector3(1.4, h, 14.0)
		crest.position = Vector3(x, h, 0)
		crest.scale = Vector3(0.6, 0.35, 14.0)
		_fade(wall, 0.6 * (1.0 - k * 0.6))
		_fade(crest, 0.9 * (1.0 - k * 0.6)))

# Rings closing in on a target (hypnosis / sleep).
func rings_in(at, col: Color, life := 0.6) -> void:
	var rings: Array = []
	for i in 3:
		rings.append(_mesh(_torus(1.0, 0.12), glow(col, 0.9)))
	_add(rings, life, func(k: float, _dt: float):
		var p := _pos(at)
		for i in rings.size():
			var t := clampf(k * 1.6 - i * 0.25, 0.0, 1.0)
			var r: MeshInstance3D = rings[i]
			r.position = p + Vector3(0, 0.3 + i * 0.4, 0)
			r.scale = Vector3(1, 0.5, 1) * (3.5 * (1.0 - t) + 0.3)
			_fade(r, 0.9 * (1.0 - t * 0.7)))

# A puffy cloud blooming around a target (spores).
func cloud(at, col: Color) -> void:
	for i in 7:
		var puff := _mesh(_sphere(0.8), flat(col, 0.6))
		var off := Vector3(randf_range(-1.6, 1.6), randf_range(0.3, 2.4), randf_range(-1.2, 1.2))
		_add([puff], randf_range(0.8, 1.2), func(k: float, _dt: float):
			puff.position = _pos(at) + off * (0.4 + k)
			puff.scale = Vector3.ONE * (0.4 + k * 1.2)
			_fade(puff, 0.6 * (1.0 - k)))

# Water spiralling up around a target.
func spiral(at, col: Color, life := 0.7) -> void:
	var drops: Array = []
	for i in 14:
		drops.append(_mesh(_sphere(0.28), glow(col, 0.9)))
	_add(drops, life, func(k: float, _dt: float):
		var p := _pos(at)
		for i in drops.size():
			var a := k * 14.0 + i * TAU / drops.size()
			var r := 2.2 * (1.0 - k * 0.5)
			(drops[i] as MeshInstance3D).position = p + Vector3(cos(a) * r, k * 4.0 + i * 0.08, sin(a) * r)
			_fade(drops[i], 0.9 * (1.0 - k)))

# A glowing shell around a spirit (guard / bubble / calm mind).
func aura(at, col: Color, life := 0.8, rising := false) -> void:
	var shell := _mesh(_sphere(2.0), glow(col, 0.35))
	var rings: Array = []
	if rising:
		for i in 3:
			rings.append(_mesh(_torus(1.6, 0.1), glow(col.lightened(0.3), 0.9)))
	_add([shell] + rings, life, func(k: float, _dt: float):
		var p := _pos(at)
		shell.position = p + Vector3(0, 2.0, 0)
		shell.scale = Vector3.ONE * (0.8 + sin(k * PI) * 0.35)
		_fade(shell, 0.35 * sin(k * PI))
		for i in rings.size():
			var t := fmod(k * 1.5 + i / 3.0, 1.0)
			var r: MeshInstance3D = rings[i]
			r.position = p + Vector3(0, t * 4.5, 0)
			r.scale = Vector3(1, 0.5, 1) * (1.2 - t * 0.5)
			_fade(r, 0.9 * (1.0 - t)))

# Petals drifting down over a list of spots (healing bloom).
func petals(spots: Array, col: Color) -> void:
	for at in spots:
		for i in 6:
			var p := _mesh(BoxMesh.new(), flat(col))
			p.scale = Vector3(0.35, 0.06, 0.25)
			var off := Vector3(randf_range(-1.5, 1.5), randf_range(5, 7), randf_range(-1.2, 1.2))
			var spin := randf_range(3, 7)
			_add([p], 1.1, func(k: float, _dt: float):
				p.position = _pos(at) + off - Vector3(sin(k * 6.0) * 0.5, k * off.y, 0)
				p.rotation = Vector3(k * spin, k * spin * 0.7, 0))
		aura(at, Color("7aff9a"), 0.9, true)

# Orbs drifting from one spot to another (drain: life flowing back).
func drain(from, to, col: Color) -> void:
	for i in 6:
		var o := _mesh(_sphere(0.25), glow(col, 0.9))
		var delay := i * 0.06
		var wob := randf_range(-1.2, 1.2)
		_add([o], 0.7 + delay, func(k: float, _dt: float):
			var t := clampf((k * (0.7 + delay) - delay) / 0.7, 0.0, 1.0)
			o.visible = t > 0.0
			o.position = _pos(from).lerp(_pos(to), t) + Vector3(0, sin(t * PI) * 2.0, sin(t * PI) * wob))

# A sparkling trail left behind a spirit (spark rush).
func trail(at, col: Color, life := 0.4) -> void:
	var s := _mesh(_sphere(0.35), glow(col, 0.9))
	var p0 := _pos(at)
	_add([s], life, func(k: float, _dt: float):
		s.position = p0 + Vector3(0, k * 0.6, 0)
		s.scale = Vector3.ONE * (1.0 - k)
		_fade(s, 0.9 * (1.0 - k)))
