extends Control
## The "VS" strip that slams in over the dark board before a 3D battle: a torn
## black strip, each side's trainer in a big circle with the spirits they're
## bringing underneath, and a lightning-slash VS in the middle. (A wild spirit
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
	if not _flashed and _t >= IN_TIME + SIDES_TIME * 0.6:
		_flashed = true
		Sfx.play("crit", 0.8)
	if _t >= IN_TIME + SIDES_TIME + _hold + OUT_TIME:
		set_process(false)
		done.emit()
		return
	queue_redraw()

func _ease(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - x, 3.0)

func _draw() -> void:
	var vp := get_viewport_rect().size
	var out_k := clampf((_t - (IN_TIME + SIDES_TIME + _hold)) / OUT_TIME, 0.0, 1.0)
	var a := 1.0 - out_k
	# the board behind goes dark
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.55 * a))
	var cy := vp.y * 0.45
	var slide := (1.0 - _ease(_t / IN_TIME)) * -vp.x
	var tilt := -0.04
	draw_set_transform(Vector2(vp.x * 0.5 + slide, cy), tilt, Vector2(1, 1.0 + out_k * 0.3))
	# the torn paper strip (with a drop shadow)
	var w := vp.x * 1.1
	for pass_i in 2:
		var off := Vector2(0, 6) if pass_i == 0 else Vector2.ZERO
		# a black strip with a faint purple edge glow behind it
		var col := Color(0.55, 0.45, 0.95, 0.35 * a) if pass_i == 0 else Color(0.04, 0.035, 0.07, a)
		var pts := PackedVector2Array()
		for i in _tear_top.size():
			pts.append(off + Vector2(-w / 2 + w * i / 40.0, -STRIP_H / 2 + _tear_top[i]))
		for i in range(_tear_bot.size() - 1, -1, -1):
			pts.append(off + Vector2(-w / 2 + w * i / 40.0, STRIP_H / 2 + _tear_bot[i]))
		draw_colored_polygon(pts, col)
	# the two sides slide in from opposite ends
	var sk := _ease((_t - IN_TIME) / SIDES_TIME)
	var side_off := (1.0 - sk) * vp.x * 0.5
	_draw_side(_left, Vector2(-vp.x * 0.3 - side_off, 0), a * sk)
	_draw_side(_right, Vector2(vp.x * 0.3 + side_off, 0), a * sk)
	# the lightning slash and VS
	var vk := _ease((_t - IN_TIME - SIDES_TIME * 0.5) / (SIDES_TIME * 0.6))
	if vk > 0.0:
		_draw_vs(vk, a)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# a white flash as the VS lands
	var fk := _t - (IN_TIME + SIDES_TIME * 0.6)
	if fk > 0.0 and fk < 0.25:   # a quick flash as the VS lands
		draw_rect(Rect2(Vector2.ZERO, vp), Color(1, 1, 1, 0.25 * (1.0 - fk / 0.25)))

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

func _draw_vs(k: float, a: float) -> void:
	# a jagged bolt slashing across the strip, then the letters on top
	var s := 0.6 + k * 0.4
	var bolt := PackedVector2Array([
		Vector2(-30, -150), Vector2(40, -150), Vector2(10, -40), Vector2(55, -40),
		Vector2(-35, 150), Vector2(-5, 20), Vector2(-50, 20)])
	for i in bolt.size():
		bolt[i] = bolt[i] * s
	var outline := PackedVector2Array()
	for p in bolt:
		outline.append(p * 1.12)
	draw_colored_polygon(outline, Color(0.1, 0.08, 0.16, a))
	draw_colored_polygon(bolt, Color(1.0, 0.82, 0.2, a))
	var font := ThemeDB.fallback_font
	var size := int(84 * s)
	var vs := "VS"
	var w := font.get_string_size(vs, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var pos := Vector2(-w / 2, size * 0.35)
	draw_string_outline(font, pos, vs, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 14, Color(0.1, 0.08, 0.16, a))
	draw_string(font, pos, vs, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(1, 0.3, 0.25, a))
