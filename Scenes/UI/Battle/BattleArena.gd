class_name BattleArena
extends Control
## The battle's 3D stage (replaces the old spirit cards). A pitch floats over
## the board (transparent background); each side's active spirit roams its half
## and leaps in to attack, backups wait off the pitch beside their trainer, and
## the trainers are the walking board tokens. HP / charge bars, names, status,
## buff tags and damage numbers are drawn flat on top.
##
## It never decides anything: BattleView calls attack() / hurt() / ability() /
## special() / float_text(), and every frame it reads the live battle state
## (HP, charge, active index, fainted) straight from the view.

const FIELD := Rect2(80, 40, 520, 290)   # pitch in "pixel" space; 20 px = 1 unit
const HOME := [Vector2(220, 185), Vector2(460, 185)]
const TRAINER_X := [30.0, 650.0]
const SPIRIT_PIX := 0.08                 # Sprite3D pixel size: a 60 px frame ≈ 4.8 units
const BENCH_SCALE := 0.55
const TOKEN_SHEET := "res://Assets/Player/Male_Spritesheet.png"
const TOKEN_FRAME := Vector2i(16, 32)
const NPC_COLOR := Color(0.78, 0.78, 0.82)
const TOKEN_NUDGE := 0.0    # px toward the camera, if the token ever needs to sit further forward
const TOKEN_EMPTY_ROWS := 13   # blank rows under the feet in each token frame

const MoveFXScript := preload("res://Scenes/UI/Battle/MoveFX.gd")
# How each charged move looks. Ranged: beam (the big glowing beam), bolt
# (chain lightning), sky (lightning from above), wave (a wall across the
# pitch), lob (an orb arcing over), cloud / rings / spiral (around the target),
# dread (a dark shockwave). Melee (still a leap-in): slam, spark, shadow,
# bubble, shield, combo. Self (no attack): aura, bloom.
const MOVE_STYLE := {
	"ember_burst": "beam", "inferno": "beam", "soak": "beam", "mind_blast": "beam", "vine_drain": "beam",
	"chain_bolt": "bolt", "thunderclap": "sky", "heat_wave": "wave", "curse": "lob",
	"spore_cloud": "cloud", "hex_sleep": "rings", "whirlpool": "spiral", "dread": "dread",
	"haymaker": "slam", "spark_rush": "spark", "shadow_sneak": "shadow", "tidal_guard": "bubble",
	"iron_guard": "shield", "combo_strike": "combo",
	"calm_mind": "aura", "bloom": "bloom",
}
const RANGED := ["beam", "bolt", "sky", "wave", "lob", "cloud", "rings", "spiral", "dread"]
const TYPE_COLOR := {
	"Fire": Color("ff7a1f"), "Water": Color("3aa6ff"), "Grass": Color("5ad84a"), "Electric": Color("ffe23a"),
	"Psychic": Color("ff5cc8"), "Dark": Color("9a4dff"), "Fighting": Color("ff5a3a"),
}
const STATUS_ABBR := {"stun": "STN", "sleep": "SLP", "poison": "PSN", "burn": "BRN", "confuse": "CNF"}
const STATUS_COLORS := {
	"stun": Color(0.8, 0.68, 0.1), "sleep": Color(0.42, 0.47, 0.62),
	"poison": Color(0.55, 0.28, 0.7), "burn": Color(0.85, 0.4, 0.12), "confuse": Color(0.8, 0.35, 0.55),
}

var view   # the BattleView that owns this (reads _team/_opp/_active/_speed…)
var _vp: SubViewport
var _cam: Camera3D
var _world: Node3D
var _mfx   # MoveFX: beams, explosions…
var _overlay: Control
var _fighters := {}          # fid -> fighter Dictionary
var _next_fid := 1
var _trainers: Array = [null, null]   # AnimatedSprite3D per side (null = wild, no trainer)
var _trainer_names: Array = ["", ""]
var _pops: Array = []
var _fx: Array = []
var _t := 0.0
var _shake := 0.0

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(1040, 470)
	var box := SubViewportContainer.new()
	box.stretch = true
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_vp = SubViewport.new()
	_vp.own_world_3d = true          # never shares the 3D board's world
	_vp.transparent_bg = true        # the board shows around the pitch
	_vp.msaa_3d = Viewport.MSAA_2X
	box.add_child(_vp)
	_world = Node3D.new()
	_vp.add_child(_world)
	_mfx = MoveFXScript.new(_world)
	_build_world()
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)

func _w(x: float, y: float, h: float = 0.0) -> Vector3:
	return Vector3((x - 340.0) / 20.0, h, (y - 185.0) / 20.0)

func _mat(c: Color, unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m

func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.82, 0.8)
	e.ambient_light_energy = 0.75
	env.environment = e
	_world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	_world.add_child(sun)
	_cam = Camera3D.new()
	_cam.fov = 38
	# (built before the arena is in the tree, so aim it with a transform —
	# look_at() only works inside the tree and would leave it facing nowhere)
	_cam.transform = Transform3D(Basis(), Vector3(0, 20, 20.5)).looking_at(Vector3(0, 0, 0.6), Vector3.UP)
	_world.add_child(_cam)
	# the pitch: stripes, outline, centre line + circle, on a slab
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
	var slab := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(36, 0.5, 20)
	slab.mesh = sm
	slab.material_override = _mat(Color("4f8a48"))
	slab.position = Vector3(0, -0.26, 0)
	_world.add_child(slab)
	var pitch := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(26, 14.5)
	pitch.mesh = pm
	var pmat := StandardMaterial3D.new()
	pmat.albedo_texture = ImageTexture.create_from_image(img)
	pitch.material_override = pmat
	pitch.position = Vector3(0, 0.01, 0)
	_world.add_child(pitch)
	for k in 2:
		var pad := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(3, 0.2, 5.5)
		pad.mesh = bm
		pad.material_override = _mat(Color("e8e2d0"))
		pad.position = _w(TRAINER_X[k], 185, 0.1)
		_world.add_child(pad)

# The board's own UI (Roll / End Turn, hand, player cards, top buttons) hides
# while a 3D battle or its team pick is up; the 3D map stays dark behind.
static func board_ui_shown(tree: SceneTree, on: bool) -> void:
	var board := tree.current_scene
	if board == null:
		return
	for path in ["BoardUI", "TopUI"]:
		var layer := board.get_node_or_null(path) as CanvasLayer
		if layer:
			layer.visible = on

# ── setup ─────────────────────────────────────────────────────────────────────

# A new battle: clear the stage, place the trainers (`trainer_colors[k]` is
# null for a side with no trainer, e.g. a wild spirit) and every spirit.
func begin(trainer_colors: Array, names: Array) -> void:
	for f in _fighters.values():
		_free_fighter(f)
	_fighters.clear()
	for p in _fx:
		p["m"].queue_free()
	_fx.clear()
	_pops.clear()
	_mfx.clear()
	_trainer_names = names
	for k in 2:
		if _trainers[k]:
			_trainers[k].queue_free()
			_trainers[k] = null
		if trainer_colors[k] != null:
			_trainers[k] = _make_token(trainer_colors[k], k)
	rebuild(true)

func _make_token(color: Color, side: int) -> AnimatedSprite3D:
	var sheet: Texture2D = load(TOKEN_SHEET)
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	for anim in [["side", 2], ["down", 0]]:
		sf.add_animation(anim[0])
		sf.set_animation_loop(anim[0], true)
		sf.set_animation_speed(anim[0], 8.0)
		for col in [1, 0, 1, 2]:
			var tex := AtlasTexture.new()
			tex.atlas = sheet
			tex.region = Rect2(col * TOKEN_FRAME.x, anim[1] * TOKEN_FRAME.y, TOKEN_FRAME.x, TOKEN_FRAME.y)
			sf.add_frame(anim[0], tex)
	var s := AnimatedSprite3D.new()
	s.sprite_frames = sf
	s.animation = "side"
	s.flip_h = side == 0          # the sheet's side view faces left
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED   # faces the camera fully: no squash, stands mid-tile
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.shaded = false
	s.pixel_size = 0.17
	# the character fills only the top 19 rows of each 32-row frame: put
	# its feet (not the frame's empty bottom) on the tile
	s.offset.y = TOKEN_FRAME.y * 0.5 - TOKEN_EMPTY_ROWS
	s.modulate = color.lightened(0.35)   # the sheet is dark; tint it lighter
	# centred on its white tile (the token sheet leaves empty rows under the
	# feet, so the sprite stands a little toward the camera to look centred)
	s.position = _w(TRAINER_X[side], 185 + TOKEN_NUDGE, 0.2)
	_world.add_child(s)
	return s

func _side_list(k: int) -> Array:
	return view._team if k == 0 else view._opp

func _active_idx(k: int) -> int:
	return view._active if k == 0 else view._opp_active

# Line-up changed (start, a switch, U-Turn, Mayhem…): make sure every spirit has
# a fighter, then the per-frame sync sorts out who stands where.
func rebuild(snap := false) -> void:
	var live := {}
	for k in 2:
		for mon in _side_list(k):
			if not mon.has("_fid"):
				mon["_fid"] = _next_fid
				_next_fid += 1
			var fid: int = mon["_fid"]
			live[fid] = true
			if not _fighters.has(fid):
				_fighters[fid] = _make_fighter(mon, k)
			_fighters[fid]["mon"] = mon
			_fighters[fid]["side"] = k
	for fid in _fighters.keys():
		if not live.has(fid):
			_free_fighter(_fighters[fid])
			_fighters.erase(fid)
	_place(snap)

func _make_fighter(mon: Dictionary, k: int) -> Dictionary:
	var node := Node3D.new()
	_world.add_child(node)
	var spr := Sprite3D.new()
	spr.texture = SpiritsData.sprite_tex(String(mon.get("name", "")), "front")
	spr.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	spr.shaded = false
	spr.pixel_size = SPIRIT_PIX
	spr.flip_h = k == 0           # front sprites face left; yours face right
	if spr.texture:
		spr.offset.y = spr.texture.get_height() * 0.4
	node.add_child(spr)
	var shadow := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.1
	cm.bottom_radius = 1.1
	cm.height = 0.02
	shadow.mesh = cm
	shadow.material_override = _mat(Color(0, 0, 0, 0.3), true)
	_world.add_child(shadow)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.45
	tm.outer_radius = 1.7
	ring.mesh = tm
	ring.material_override = _mat(Color("ffd400"), true)
	ring.visible = false
	_world.add_child(ring)
	return {"mon": mon, "side": k, "node": node, "spr": spr, "shadow": shadow, "ring": ring,
		"x": TRAINER_X[k], "y": 185.0, "h": 0.0, "tx": 0.0, "ty": 0.0, "bx": 0.0, "by": 0.0,
		"role": "", "st": "idle", "timer": 0.0, "scale": BENCH_SCALE, "squash": 0.0,
		"flash": 0.0, "hurt_flash": 0.0, "move_name": "", "vx": 0.0, "target": null, "fainted": false, "pending": {}, "fx": {}}

func _free_fighter(f: Dictionary) -> void:
	for key in ["node", "shadow", "ring"]:
		if is_instance_valid(f[key]):
			f[key].queue_free()

# Who stands on the pitch, who waits on the bench (and where).
func _place(snap: bool) -> void:
	for k in 2:
		var side := _side_list(k)
		var act := _active_idx(k)
		var slot := 0
		for i in side.size():
			var mon: Dictionary = side[i]
			var f: Dictionary = _fighters[mon["_fid"]]
			if mon.get("_gone", false) or (int(mon.get("current_hp", 1)) <= 0 and f["st"] in ["faint", "gone"]):
				if f["st"] != "faint":
					f["role"] = "gone"
					f["st"] = "gone"
				continue
			var bench_pos := _bench_pos(k, slot)
			if i == act:
				if f["role"] != "field":
					f["role"] = "field"
					f["st"] = "enter"
					f["timer"] = 0.0
					if snap:
						f["x"] = TRAINER_X[k] if _trainers[k] else HOME[k].x + (120.0 if k == 1 else -120.0)
						f["y"] = 185.0
				continue
			f["bx"] = bench_pos.x
			f["by"] = bench_pos.y
			slot += 1
			if f["role"] != "bench":
				f["role"] = "bench"
				f["st"] = "tobench"
				if snap:
					f["x"] = bench_pos.x
					f["y"] = bench_pos.y
					f["st"] = "idle"
					f["scale"] = BENCH_SCALE

# Backups wait OFF the pitch beside their trainer, two per column (more
# columns step outward for 4v4 / 6v6).
func _bench_pos(k: int, slot: int) -> Vector2:
	var row := slot % 2
	var col := slot / 2
	if k == 0:   # yours: off the pitch, in front of your trainer
		return Vector2(22.0 - col * 48.0, 288.0 + row * 50.0)
	return Vector2(658.0 + col * 48.0, 288.0 + row * 50.0)   # theirs: in front of their trainer, mirrored

# ── called by the battle (animations) ─────────────────────────────────────────

func _f(mon: Dictionary) -> Dictionary:
	if mon.has("_fid") and _fighters.has(mon["_fid"]):
		return _fighters[mon["_fid"]]
	return {}

func _foe_on_field(k: int) -> Dictionary:
	for f in _fighters.values():
		if f["side"] != k and f["role"] == "field":
			return f
	return {}

func _chest(f: Dictionary) -> Vector3:
	return _w(f["x"], f["y"], f["h"] + 2.0 * maxf(0.3, f["scale"]))

func _feet(f: Dictionary) -> Vector3:
	return _w(f["x"], f["y"], 0.1)

func _move_color(key: String) -> Color:
	return TYPE_COLOR.get(String(SpiritsData.move_of(key).get("type", "")), Color("ffd400"))

func attack(mon: Dictionary) -> void:
	var f := _f(mon)
	if f.is_empty():
		return
	var target := _foe_on_field(f["side"])
	var mv: Dictionary = f.get("pending", {})
	f["pending"] = {}
	if f["role"] != "field" or target.is_empty():
		f["st"] = "hop"
		f["timer"] = 0.0
		return
	f["target"] = target
	f["ox"] = f["x"]
	f["oy"] = f["y"]
	f["fx"] = mv            # the charged move this attack carries ({} = a plain hit)
	_cheer(f["side"])
	var style := String(mv.get("style", ""))
	if style in RANGED:
		f["st"] = "cast"
		f["timer"] = 0.0
		_cast(f, target, mv)
		return
	f["st"] = "windup"
	f["timer"] = 0.0
	if style == "bubble" or style == "shield":
		_mfx.aura(func(): return _feet(f), Color("7fd0ff") if style == "bubble" else Color("c8d0e0"), 0.7)

# Ranged moves: the spirit plants its feet and fires.
func _cast(f: Dictionary, t: Dictionary, mv: Dictionary) -> void:
	var col: Color = mv["col"]
	var from := func(): return _chest(f)
	var to := func(): return _chest(t)
	match String(mv["style"]):
		"beam":
			_mfx.beam(from, to, col, 0.8 if mv["key"] == "inferno" else 0.55, 0.8)
		"bolt":
			_mfx.bolt(from, to, col, 0.55)
			_mfx.bolt(from, to, Color.WHITE, 0.35, 6, 0.08)
		"sky":
			_mfx.sky_bolt(to, col)
		"wave":
			var dir := 1.0 if f["side"] == 0 else -1.0
			_mfx.wave(_w(f["x"], 185).x + dir * 1.5, _w(t["x"], 185).x + dir * 4.0, col, 0.55)
		"lob":
			_mfx.lob(from, to, col, 0.3)
		"cloud":
			_mfx.cloud(func(): return _feet(t), col.lerp(Color("c080ff"), 0.4))
		"rings":
			_mfx.rings_in(func(): return _feet(t), col, 0.55)
		"spiral":
			_mfx.spiral(func(): return _feet(t), col)
		"dread":
			_mfx.shockwave(_feet(f), col, 9.0, 0.5)
			_mfx.aura(func(): return _feet(t), col.darkened(0.3), 0.6)

func hurt(mon: Dictionary) -> void:
	var d := _f(mon)
	if d.is_empty():
		return
	d["hurt_flash"] = 0.3
	var a := _foe_on_field(d["side"])
	var mv: Dictionary = {} if a.is_empty() else a.get("fx", {})
	if mv.is_empty():
		_shake = maxf(_shake, 0.25)
		_burst(d["x"], d["y"], Color.WHITE, 8)
	else:
		_impact(a, d, mv)
	if d["role"] == "field":
		var from_x: float = HOME[1 - d["side"]].x
		if not a.is_empty():
			from_x = a["x"]
			if a["st"] in ["dash", "contact"]:
				a["st"] = "back"
				a["timer"] = 0.0
			elif a["st"] == "cast":
				a["timer"] = maxf(a["timer"], 0.55)   # wrap up shortly after the hit
		d["st"] = "hurt"
		d["timer"] = 0.0
		d["vx"] = (1.0 if d["x"] > from_x else -1.0) * (260.0 if not mv.is_empty() else 170.0)

# Where a charged move lands: an explosion in its colour (bigger for the
# heavy hitters), plus each move's own after-touch.
func _impact(a: Dictionary, d: Dictionary, mv: Dictionary) -> void:
	var col: Color = mv["col"]
	var at := _chest(d)
	var style := String(mv["style"])
	var key := String(mv["key"])
	var big: bool = key in ["inferno", "haymaker", "heat_wave"]
	_shake = maxf(_shake, 0.6 if big else 0.4)
	match style:
		"cloud", "rings":
			_mfx.smoke(at, 4, col.lerp(Color.WHITE, 0.4))
			_mfx.shockwave(_feet(d), col, 3.0)
		"spiral":
			_mfx.shockwave(_feet(d), col, 4.0)
			_mfx.debris(at, col.lightened(0.3), 8)
			_mfx.aura(func(): return _feet(a), col, 0.6)   # Whirlpool heals its user
		_:
			_mfx.explosion(at, col, big)
			_mfx.debris(at, col.lightened(0.2), 12 if big else 8)
	if key == "vine_drain":
		_mfx.drain(func(): return _chest(d), func(): return _chest(a), Color("7aff9a"))
	if style == "slam":
		_mfx.shockwave(_feet(d), Color("ffd0a0"), 7.0, 0.6)
	if key != "combo_strike":
		a["fx"] = {}   # one big impact per move (Combo Strike's 2nd hit is plain)

func ability(mon: Dictionary) -> void:
	var f := _f(mon)
	if f.is_empty():
		return
	if f["st"] in ["idle", "tobench"]:
		f["st"] = "hop"
		f["timer"] = 0.0
	_burst(f["x"], f["y"], Color("ffe98a"), 6)

func special(mon: Dictionary, move_name: String) -> void:
	var f := _f(mon)
	if f.is_empty():
		return
	f["flash"] = 1.4
	f["move_name"] = move_name
	_shake = maxf(_shake, 0.15)
	_cheer(f["side"])
	var key := SpiritsData.move_key(mon)
	var mv := {"key": key, "style": String(MOVE_STYLE.get(key, "combo")), "col": _move_color(key), "t": 1.6}
	match mv["style"]:
		"aura":   # Calm Mind: a calm glow with rings rising (no attack of its own)
			_mfx.aura(func(): return _feet(f), mv["col"], 1.1, true)
		"bloom":  # Bloom: petals rain on the whole team
			var spots: Array = []
			for g in _fighters.values():
				if g["side"] == f["side"] and g["role"] in ["field", "bench"]:
					spots.append(_feet(g))
			_mfx.petals(spots, Color("ffb0d8"))
		_:
			f["pending"] = mv   # the next attack() carries it

func float_text(mon: Dictionary, text: String, color: Color) -> void:
	var f := _f(mon)
	if f.is_empty():
		return
	_pops.append({"x": f["x"], "y": f["y"], "h": 4.6 if f["role"] == "field" else 2.6, "txt": text, "col": color, "life": 1.1})

# A tactic card going off: a small tag pops up over the spirit of the side that
# played it (side -1 = neither: over the middle of the pitch).
var _card_tags: Array = []

func card_pop(side: int, icon: String, text: String, color: Color) -> void:
	_card_tags.append({"side": side, "txt": "%s %s" % [icon, text], "col": color, "life": 1.8})
	if side >= 0:
		_cheer(side)

# The trainer steps in place while their spirit goes for it.
func _cheer(k: int) -> void:
	var tr: AnimatedSprite3D = _trainers[k]
	if tr == null:
		return
	tr.play("side")
	get_tree().create_timer(0.8).timeout.connect(func():
		if is_instance_valid(tr):
			tr.stop()
			tr.frame = 0)

func _burst(x: float, y: float, col: Color, n: int) -> void:
	for i in n:
		var m := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3.ONE * 0.25
		m.mesh = b
		m.material_override = _mat(col, true)
		m.position = _w(x, y, 1.6)
		_world.add_child(m)
		_fx.append({"m": m, "v": Vector3(randf_range(-7, 7), randf_range(2, 10), randf_range(-7, 7)), "life": 0.6})

# ── per frame ─────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if not is_visible_in_tree() or view == null:
		return
	var spd: float = view._speed
	var dt := minf(delta, 0.05) * spd
	_t += dt
	_shake = maxf(0.0, _shake - dt * 1.5)
	_place(false)
	for f in _fighters.values():
		_step(f, dt)
		_sync(f)
	for p in _pops:
		p["h"] += dt * 1.3
		p["life"] -= dt
	_pops = _pops.filter(func(p): return p["life"] > 0)
	for c in _card_tags:
		c["life"] -= dt
	_card_tags = _card_tags.filter(func(c): return c["life"] > 0)
	for p in _fx:
		var v: Vector3 = p["v"]
		v.y -= 25 * dt
		p["v"] = v
		p["m"].position += v * dt
		p["m"].position.y = maxf(0.1, p["m"].position.y)
		p["life"] -= dt
		if p["life"] <= 0:
			p["m"].queue_free()
	_fx = _fx.filter(func(p): return p["life"] > 0)
	_mfx.tick(dt)
	_cam.h_offset = randf_range(-0.5, 0.5) * _shake
	_overlay.queue_redraw()

func _pick_spot(f: Dictionary) -> void:
	var k: int = f["side"]
	var mid := FIELD.position.x + FIELD.size.x / 2
	var lo: float = FIELD.position.x + 50 if k == 0 else mid + 50
	var hi: float = mid - 50 if k == 0 else FIELD.end.x - 50
	f["tx"] = randf_range(lo, hi)
	f["ty"] = randf_range(FIELD.position.y + 55, FIELD.end.y - 45)

func _step(f: Dictionary, dt: float) -> void:
	f["timer"] += dt
	f["flash"] = maxf(0.0, f["flash"] - dt)
	f["hurt_flash"] = maxf(0.0, f["hurt_flash"] - dt)
	var mon: Dictionary = f["mon"]
	# down to 0 HP: once the hit has landed, it spins away
	if int(mon.get("current_hp", 1)) <= 0 and f["st"] not in ["hurt", "faint", "gone"]:
		f["st"] = "faint"
		f["timer"] = 0.0
	var pend: Dictionary = f.get("pending", {})
	if not pend.is_empty():
		pend["t"] = float(pend["t"]) - dt
		if pend["t"] <= 0.0:
			f["pending"] = {}
	match f["st"]:
		"cast":
			# firing: feet planted, a small recoil, then back to roaming
			f["h"] = 0.15 + sin(minf(f["timer"], 0.3) / 0.3 * PI) * 0.4
			f["squash"] = 0.4 if f["timer"] < 0.15 else 0.0
			if f["timer"] > 0.9:
				f["st"] = "idle"
				f["squash"] = 0.0
				f["fx"] = {}
				_pick_spot(f)
		"enter":
			var h: Vector2 = HOME[f["side"]]
			f["x"] = lerpf(f["x"], h.x, minf(1.0, dt * 4))
			f["y"] = lerpf(f["y"], h.y, minf(1.0, dt * 4))
			f["scale"] = lerpf(f["scale"], 1.0, minf(1.0, dt * 5))
			f["h"] = absf(sin(f["timer"] * 8)) * 0.9
			if Vector2(f["x"], f["y"]).distance_to(h) < 5:
				f["st"] = "idle"
				f["h"] = 0.0
				_pick_spot(f)
		"tobench":
			f["x"] = lerpf(f["x"], f["bx"], minf(1.0, dt * 4))
			f["y"] = lerpf(f["y"], f["by"], minf(1.0, dt * 4))
			f["scale"] = lerpf(f["scale"], BENCH_SCALE, minf(1.0, dt * 5))
			f["h"] = absf(sin(f["timer"] * 8)) * 0.6
			if Vector2(f["x"], f["y"]).distance_to(Vector2(f["bx"], f["by"])) < 3:
				f["st"] = "idle"
		"idle":
			if f["role"] == "field":
				f["x"] = lerpf(f["x"], f["tx"], minf(1.0, dt * 1.4))
				f["y"] = lerpf(f["y"], f["ty"], minf(1.0, dt * 1.4))
				f["h"] = absf(sin(_t * 5 + f["side"] * 1.7)) * 0.25
				if Vector2(f["x"], f["y"]).distance_to(Vector2(f["tx"], f["ty"])) < 6:
					_pick_spot(f)
			else:
				f["x"] = lerpf(f["x"], f["bx"], minf(1.0, dt * 4))
				f["y"] = lerpf(f["y"], f["by"], minf(1.0, dt * 4))
				f["scale"] = lerpf(f["scale"], BENCH_SCALE, minf(1.0, dt * 5))
				f["h"] = absf(sin(_t * 3 + f["bx"] * 0.1)) * 0.12
		"hop":
			f["h"] = sin(clampf(f["timer"] / 0.35, 0, 1) * PI) * 1.2
			if f["timer"] > 0.35:
				f["st"] = "idle"
				f["h"] = 0.0
		"windup":
			var tgt: Dictionary = f["target"]
			f["x"] += (-1.0 if f["x"] < tgt["x"] else 1.0) * dt * 40
			f["h"] = 0.0
			f["squash"] = minf(1.0, f["timer"] * 8)
			if f["timer"] > 0.1:
				f["st"] = "dash"
				f["timer"] = 0.0
				f["sx"] = f["x"]
				f["sy"] = f["y"]
				f["squash"] = 0.0
		"dash":
			var d: Dictionary = f["target"]
			var to := Vector2(d["x"] - f["x"], d["y"] - f["y"])
			var dist := to.length()
			var tot := maxf(1.0, Vector2(d["x"] - f["sx"], d["y"] - f["sy"]).length())
			var style := String(f.get("fx", {}).get("style", ""))
			f["h"] = sin(clampf(1.0 - dist / tot, 0, 1) * PI) * (4.5 if style == "slam" else 1.8)
			if style == "spark":
				_mfx.trail(_chest(f), Color("ffe23a"))
			if dist < 60:
				f["st"] = "contact"
				f["timer"] = 0.0
				f["h"] = 0.0
			else:
				var v := (to / dist) * maxf(600.0, tot / 0.2) * dt
				f["x"] += v.x
				f["y"] += v.y
		"contact":
			if f["timer"] > 0.6:   # no hit came (a miss, a shield…): head back
				f["st"] = "back"
				f["timer"] = 0.0
		"back":
			f["x"] = lerpf(f["x"], f.get("ox", f["x"]), minf(1.0, dt * 6))
			f["y"] = lerpf(f["y"], f.get("oy", f["y"]), minf(1.0, dt * 6))
			f["h"] = maxf(0.0, f["h"] - dt * 6)
			if f["timer"] > 0.45:
				f["st"] = "idle"
				_pick_spot(f)
		"hurt":
			if f["role"] == "field":
				f["x"] = clampf(f["x"] + f["vx"] * dt, FIELD.position.x + 30, FIELD.end.x - 30)
				f["vx"] *= 0.9
			f["h"] = maxf(0.0, sin(f["timer"] * 7) * 0.7)
			if f["timer"] > 0.45:
				f["st"] = "idle"
				if f["role"] == "field":
					_pick_spot(f)
		"faint":
			f["scale"] = maxf(0.0, 1.0 - f["timer"] * 1.6)
			f["h"] = f["timer"] * 0.8
			if f["timer"] > 0.7:
				f["role"] = "gone"
				f["st"] = "gone"
		"gone":
			f["scale"] = 0.0

func _sync(f: Dictionary) -> void:
	var node: Node3D = f["node"]
	node.position = _w(f["x"], f["y"], f["h"])
	var sq: float = f["squash"]
	var s: float = maxf(0.001, f["scale"])
	node.scale = Vector3(1.0 + sq * 0.15, 1.0 - sq * 0.2, 1.0 + sq * 0.15) * s
	node.visible = f["st"] != "gone"
	var spr: Sprite3D = f["spr"]
	spr.modulate = Color(1.7, 0.6, 0.6) if f["hurt_flash"] > 0 else Color.WHITE
	if String(f.get("fx", {}).get("style", "")) == "shadow" and f["st"] in ["windup", "dash"]:
		spr.modulate = Color(0.3, 0.15, 0.45, 0.25)   # Shadow Sneak: melts into shadow, reappears on the hit
	spr.flip_h = (f["side"] == 0) != (f["st"] == "faint" and int(_t * 14) % 2 == 0)
	var ring: MeshInstance3D = f["ring"]
	ring.visible = f["flash"] > 0 and node.visible
	ring.position = _w(f["x"], f["y"], 0.08)
	ring.scale = Vector3.ONE * (1.0 + sin(_t * 20) * 0.1)
	var sh: MeshInstance3D = f["shadow"]
	sh.visible = node.visible
	sh.position = _w(f["x"], f["y"], 0.03)
	sh.scale = Vector3.ONE * s * clampf(1.0 - f["h"] * 0.15, 0.4, 1.0)

# ── flat overlay ──────────────────────────────────────────────────────────────

func _proj(x: float, y: float, h: float) -> Vector2:
	var p := _cam.unproject_position(_w(x, y, h))
	return p * (_overlay.size / Vector2(_vp.size)) if _vp.size.x > 0 else p

func _text(s: String, p: Vector2, col: Color, size: int, outline := 5) -> void:
	var font := ThemeDB.fallback_font
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_overlay.draw_string_outline(font, p - Vector2(w / 2, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, Color(0, 0, 0, 0.85 * col.a))
	_overlay.draw_string(font, p - Vector2(w / 2, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

func _bars(mon: Dictionary, p: Vector2, w: float, big: bool) -> void:
	var hh := 11.0 if big else 6.0
	var cost := int(SpiritsData.move_of(SpiritsData.move_key(mon)).get("charge", 3))
	var ch := mini(int(mon.get("_charge", 0)), cost)
	_overlay.draw_rect(Rect2(p.x - w / 2 - 2, p.y - 2, w + 4, hh + (7 if big else 5) + 4), Color(0, 0, 0, 0.6))
	var hp := float(mon.get("current_hp", 0))
	var mx := maxf(1.0, float(mon.get("hp", 1)))
	var fr := clampf(hp / mx, 0, 1)
	_overlay.draw_rect(Rect2(p.x - w / 2, p.y, w * fr, hh),
		Color("2ad05a") if fr > 0.5 else (Color("f0b020") if fr > 0.25 else Color("f03030")))
	if big:
		_text("%d / %d" % [int(hp), int(mx)], p + Vector2(0, hh - 1), Color.WHITE, 11, 3)
	# charge: one segment per charge the move needs
	var cy := p.y + hh + 2
	var ch_h := 5.0 if big else 3.0
	var seg := (w - 2.0 * (cost - 1)) / float(cost)
	for i in cost:
		var c := Color("ffd400") if i < ch else Color(1, 1, 1, 0.15)
		if i < ch and ch >= cost - 1:
			c = Color("fff07a")
		_overlay.draw_rect(Rect2(p.x - w / 2 + i * (seg + 2.0), cy, seg, ch_h), c)

# Buff/debuff tags only while one is active: "A▲" blue, "D▼2" red…
func _stat_tags(mon: Dictionary, p: Vector2, size: int) -> void:
	var tags: Array = []
	for pair in [["atk", "A"], ["def", "D"], ["spd", "S"]]:
		var cur: int = int(mon.get(pair[0], 1))
		var base: int = int(mon.get("_base_" + pair[0], cur))
		if cur != base:
			var n := absi(cur - base)
			tags.append([pair[1] + ("▲" if cur > base else "▼") + (str(n) if n > 1 else ""), Color("6a8cff") if cur > base else Color("ff5060")])
	var st: Dictionary = mon.get("_status", {})
	if not st.is_empty() and int(mon.get("current_hp", 0)) > 0:
		var kind := String(st.get("kind", ""))
		tags.append(["%s %d" % [STATUS_ABBR.get(kind, kind.to_upper()), maxi(1, int(st.get("rounds", 1)))], STATUS_COLORS.get(kind, Color.GRAY).lightened(0.3)])
	var x := p.x - (tags.size() - 1) * size * 1.4
	for tag in tags:
		_text(tag[0], Vector2(x, p.y), tag[1], size, 4)
		x += size * 2.8

func _draw_overlay() -> void:
	if view == null:
		return
	for k in 2:
		if _trainers[k] and _trainer_names[k] != "":
			var tp := _proj(TRAINER_X[k], 185 + TOKEN_NUDGE, 3.8)
			_text(_trainer_names[k], tp, Color(1, 1, 1, 0.9), 15)
	for f in _fighters.values():
		var mon: Dictionary = f["mon"]
		if f["st"] == "gone":
			continue
		if f["role"] == "field" and f["st"] != "faint":
			var p := _proj(f["x"], f["y"], f["h"] + 5.0)
			_text("%s %s" % [mon.get("name", "?"), SpiritsData.star_text(mon.get("stars", 0))], p + Vector2(0, -8), Color.WHITE, 17)
			_bars(mon, p, 104, true)
			_stat_tags(mon, p + Vector2(0, 40), 14)
			if f["flash"] > 0:
				_text("✦ " + String(f["move_name"]), p + Vector2(0, -30), Color("ffd400"), 22, 6)
		elif f["role"] == "bench" and f["st"] == "idle":
			var bp := _proj(f["x"], f["y"], 0)
			_bars(mon, bp + Vector2(0, 6), 50, false)
			_stat_tags(mon, bp + Vector2(0, 30), 11)
	var stack := [0, 0, 0]
	for tag in _card_tags:
		var side: int = tag["side"]
		var anchor := _proj(340, 150, 6.5)
		if side >= 0:
			var f := _foe_on_field(1 - side)   # (the field fighter OF this side)
			if not f.is_empty():
				anchor = _proj(f["x"], f["y"], f["h"] + 5.0) + Vector2(0, -52)
		var rise: float = (1.8 - tag["life"]) * 14.0
		var pos: Vector2 = anchor + Vector2(0, -rise - stack[side + 1] * 26)
		stack[side + 1] += 1
		var a := minf(1.0, tag["life"] * 3.0)
		var font := ThemeDB.fallback_font
		var w := font.get_string_size(tag["txt"], HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 16
		var bg: Color = Color(0.06, 0.04, 0.14, 0.92 * a)
		var edge: Color = tag["col"]
		edge.a = a
		_overlay.draw_rect(Rect2(pos.x - w / 2, pos.y - 17, w, 23), bg)
		_overlay.draw_rect(Rect2(pos.x - w / 2, pos.y - 17, w, 23), edge, false, 2.0)
		var tc: Color = tag["col"]
		tc.a = a
		_text(tag["txt"], pos, tc, 14, 3)
	for pp in _pops:
		var q := _proj(pp["x"], pp["y"], pp["h"])
		var c: Color = pp["col"]
		c.a = minf(1.0, pp["life"] * 2)
		_text(pp["txt"], q, c, 24, 6)
