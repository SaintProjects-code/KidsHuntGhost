extends Control
## The "VS" banner before a 3D battle: two coloured halves slam together on a
## diagonal seam, each side's trainer in a big circle with the spirits they're
## bringing underneath, and a VS bouncing onto the seam. (A wild spirit
## takes the circle itself.) await play(setup) — it removes itself when done.

signal done

const STRIP_H := 270.0
const IN_TIME := 0.45
const SIDES_TIME := 0.45
const OUT_TIME := 0.4

var _left := {}     # {tex, color, name, team: Array of textures}
var _right := {}
var _hold := 1.6
var _t := 0.0
var _tear_top: PackedFloat32Array
var _tear_bot: PackedFloat32Array
var _flashed := false

# Show it and wait. `setup` is the battle setup (see BattleScreen.present);
# CPU-only fights get a shorter hold.
static func play(tree: SceneTree, setup: Dictionary) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 40
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	tree.root.add_child(layer)
	var b = load("res://Scenes/UI/Battle/VsBanner.gd").new()
	b.process_mode = Node.PROCESS_MODE_ALWAYS
	b._setup(setup)
	layer.add_child(b)
	await b.done
	layer.queue_free()

func _setup(setup: Dictionary) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var names: Array = setup.get("pvp_names", [])
	var team: Array = setup.get("team", [])
	var opp: Array = setup.get("opp", [])
	_left = {"tex": GameData.trainer_texture(setup.get("trainer", [])), "color": setup.get("color", Color("5aa6ff")),
		"name": names[0] if names.size() == 2 else String(setup.get("my_name", "You")), "team": _icons(team), "portrait": true}
	var foe_trainer: Array = setup.get("foe_trainer", [])
	if foe_trainer.is_empty() and not opp.is_empty():
		# a wild spirit: it IS the opponent
		_right = {"tex": SpiritsData.sprite_tex(String(opp[0].get("name", "")), "front"), "color": Color("8fd17a"),
			"name": "Wild %s" % opp[0].get("name", "?"), "team": [], "portrait": false}
	else:
		var title := String(setup.get("title", "Rival"))
		_right = {"tex": GameData.trainer_texture(foe_trainer), "color": setup.get("opp_color", Color("ff6a6a")),
			"name": names[1] if names.size() == 2 else title.trim_prefix("vs ").trim_suffix("!"), "team": _icons(opp), "portrait": true}
	_hold = 2.6 if (setup.get("human", true) or setup.get("opp_human", false)) else 1.8
	# a torn edge, fixed for this banner
	_tear_top = PackedFloat32Array()
	_tear_bot = PackedFloat32Array()
	for i in 41:
		_tear_top.append(randf_range(-10, 10))
		_tear_bot.append(randf_range(-10, 10))
	Sfx.play("whoosh")

func _icons(team: Array) -> Array:
	return team.map(func(m): return SpiritsData.sprite_tex(String(m.get("name", "")), "front"))

func _gui_input(ev: InputEvent) -> void:
	# a click skips straight to the battle
	if ev is InputEventMouseButton and ev.pressed and _t < IN_TIME + SIDES_TIME + _hold:
		_t = IN_TIME + SIDES_TIME + _hold

func _process(delta: float) -> void:
	_t += delta
	if not _flashed and _t >= IN_TIME:
		_flashed = true   # the two halves slam together
		Sfx.play("crit", 0.8)
	if _t >= IN_TIME + SIDES_TIME + _hold + OUT_TIME:
		set_process(false)
		done.emit()
		return
	queue_redraw()

func _ease(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - x, 3.0)

# A slash that leans right: the seam runs from (+SLANT, top) to (-SLANT, bottom).
const SLANT := 70.0
const SHAKE_TIME := 0.32
var _center_pt := Vector2.ZERO

func _draw() -> void:
	var vp := get_viewport_rect().size
	var out_t := _t - (IN_TIME + SIDES_TIME + _hold)
	var out_k := _ease(out_t / OUT_TIME) if out_t > 0.0 else 0.0
	var a := 1.0 - out_k
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.55 * a))   # the board behind goes dark
	# the halves rush in from opposite sides, slam, then fly back out
	var in_k := clampf(_t / IN_TIME, 0.0, 1.0)
	var gap := (1.0 - in_k * in_k) * vp.x * 0.75 + out_k * vp.x * 0.75
	var since := _t - IN_TIME
	var shake := Vector2.ZERO
	if since > 0.0 and since < SHAKE_TIME:
		shake = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 16.0 * (1.0 - since / SHAKE_TIME)
	var c := Vector2(vp.x * 0.5, vp.y * 0.45) + shake
	draw_set_transform(c, 0.0, Vector2.ONE)
	_center_pt = c
	var h := STRIP_H * 0.5
	var far := vp.x
	_draw_half(PackedVector2Array([Vector2(-far, -h), Vector2(SLANT, -h), Vector2(-SLANT, h), Vector2(-far, h)]),
		Vector2(-gap, 0), _left["color"], a, -1.0)
	_draw_half(PackedVector2Array([Vector2(SLANT, -h), Vector2(far, -h), Vector2(far, h), Vector2(-SLANT, h)]),
		Vector2(gap, 0), _right["color"], a, 1.0)
	# the bright seam where they meet
	if since > 0.0:
		var glow := clampf(1.0 - since / 0.6, 0.0, 1.0)
		var top := Vector2(SLANT, -h - 30) * (1.0 + glow * 0.4)
		var bot := Vector2(-SLANT, h + 30) * (1.0 + glow * 0.4)
		draw_line(top, bot, Color(1, 0.95, 0.8, (0.25 + glow * 0.5) * a), 26.0 + glow * 30.0)
		draw_line(top, bot, Color(1, 1, 1, a), 5.0 + glow * 4.0)
	# each side rides in on its half
	var sk := _ease(since / SIDES_TIME) if since > 0.0 else 0.0
	_draw_side(_left, Vector2(-vp.x * 0.3 - gap - (1.0 - sk) * 60.0, 0), a * sk)
	_draw_side(_right, Vector2(vp.x * 0.3 + gap + (1.0 - sk) * 60.0, 0), a * sk)
	if since > 0.0:
		_draw_vs(since, a)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if since > 0.0 and since < 0.2:   # a white flash as they hit
		draw_rect(Rect2(Vector2.ZERO, vp), Color(1, 1, 1, 0.35 * (1.0 - since / 0.2)))

# One half: black fading to the side's colour at the seam, a bright rim, and
# speed streaks racing away from the hit. dir = -1 left half, +1 right half.
func _draw_half(pts: PackedVector2Array, off: Vector2, col: Color, a: float, dir: float) -> void:
	var dark := Color(0.04, 0.035, 0.07, a)
	var lit := Color(col.darkened(0.25), a)
	var shadow := PackedVector2Array()
	var moved := PackedVector2Array()
	var cols := PackedColorArray()
	for p in pts:
		moved.append(p + off)
		shadow.append(p + off + Vector2(0, 8))
		# the seam corners glow with the side's colour, the far ends stay black
		cols.append(lit if absf(p.x) <= SLANT + 1.0 else dark)
	draw_colored_polygon(shadow, Color(0.55, 0.45, 0.95, 0.3 * a))
	draw_colored_polygon(moved, dark)
	# a softer colour wash that only reaches part way out
	var wash := PackedVector2Array()
	var wash_c := PackedColorArray()
	for p in pts:
		var q := p
		if absf(p.x) > SLANT + 1.0:
			q.x = p.x / absf(p.x) * 520.0
		wash.append(q + off)
		wash_c.append(Color(col, 0.0) if absf(p.x) > SLANT + 1.0 else lit)
	draw_polygon(wash, wash_c)
	# rims along the top and bottom
	draw_line(moved[0], moved[1], Color(col.lightened(0.3), a), 4.0)
	draw_line(moved[2], moved[3], Color(col.lightened(0.3), a), 4.0)
	# speed streaks
	var h := STRIP_H * 0.5
	for i in 7:
		var y := -h + 24.0 + i * (STRIP_H - 48.0) / 6.0
		var ph := fmod(_t * 1.6 + i * 0.37, 1.0)
		var x0 := dir * (140.0 + ph * 700.0) + off.x
		var ln := 60.0 + 80.0 * fmod(i * 0.61, 1.0)
		draw_line(Vector2(x0, y), Vector2(x0 + dir * ln, y), Color(1, 1, 1, 0.18 * (1.0 - ph) * a), 3.0)

func _draw_side(s: Dictionary, c: Vector2, a: float) -> void:
	if a <= 0.0:
		return
	var r := 74.0
	var ctr := c + Vector2(0, -30)
	var col: Color = s["color"]
	draw_circle(ctr, r + 6, Color(0.92, 0.9, 1.0, a))
	draw_circle(ctr, r, Color(col.r, col.g, col.b, a))
	draw_circle(ctr, r - 6, Color(col.darkened(0.45).r, col.darkened(0.45).g, col.darkened(0.45).b, a))
	var tex: Texture2D = s["tex"]
	if tex:
		var ts := tex.get_size()
		if s["portrait"]:
			# head and shoulders: the top part of the full-body portrait
			var src := Rect2(0, 0, ts.x, minf(ts.y, ts.x * 1.1))
			var box := (r - 8) * 1.6
			var k := box / maxf(src.size.x, src.size.y)
			var dst := Rect2(ctr - src.size * k * 0.5 + Vector2(0, 4), src.size * k)
			draw_texture_rect_region(tex, dst, src, Color(1, 1, 1, a))
		else:
			var box2 := (r - 6) * 1.8
			var k2 := box2 / maxf(ts.x, ts.y)
			draw_texture_rect(tex, Rect2(ctr - ts * k2 * 0.5, ts * k2), false, Color(1, 1, 1, a))
	var font := ThemeDB.fallback_font
	var name_s := String(s["name"])
	var nw := font.get_string_size(name_s, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
	draw_string_outline(font, ctr + Vector2(-nw / 2, r + 30), name_s, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, 6, Color(0.1, 0.08, 0.16, a))
	draw_string(font, ctr + Vector2(-nw / 2, r + 30), name_s, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1, a))
	# the spirits they're bringing, in a row under the name
	var icons: Array = s["team"]
	var step := 52.0
	var x0 := ctr.x - (icons.size() - 1) * step * 0.5
	for i in icons.size():
		var it: Texture2D = icons[i]
		if it == null:
			continue
		var p := Vector2(x0 + i * step, ctr.y + r + 62)
		draw_circle(p, 24, Color(0.35, 0.3, 0.5, a))
		draw_circle(p, 22, Color(0.16, 0.13, 0.26, a))
		draw_texture_rect(it, Rect2(p - Vector2(24, 24), Vector2(48, 48)), false, Color(1, 1, 1, a))

func _draw_vs(since: float, a: float) -> void:
	# VS drops onto the seam with a springy bounce, tilted along the slash
	var s := 1.0 + 0.9 * exp(-since * 7.0) * cos(since * 22.0)
	if since < 0.06:
		s = 2.2 - since / 0.06 * 0.3
	var font := ThemeDB.fallback_font
	var size := int(96 * s)
	var vs := "VS"
	var w := font.get_string_size(vs, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var rot := -atan2(SLANT * 2.0, STRIP_H) * 0.5
	draw_set_transform(_center_pt, rot, Vector2.ONE)
	var pos := Vector2(-w / 2, size * 0.35)
	draw_string_outline(font, pos + Vector2(6, 6), vs, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 16, Color(0, 0, 0, 0.6 * a))
	draw_string_outline(font, pos, vs, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 16, Color(0.1, 0.08, 0.16, a))
	draw_string_outline(font, pos, vs, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 6, Color(1, 1, 1, a))
	draw_string(font, pos, vs, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(1, 0.3, 0.25, a))
