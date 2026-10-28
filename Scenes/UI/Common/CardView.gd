class_name CardView
extends Button
## A playing card drawn as a button: kind-coloured frame, big icon, name, and
## the effect text (full text in the tooltip). `armed` lifts and glows it —
## used for "this card plays next round" in battle and for selections.
## A face-down card (key "") shows the card back.

var key := ""
var armed := false:
	set(v):
		armed = v
		_lift()
		queue_redraw()

func _init(card_key: String, card_size := Vector2(84, 112)) -> void:
	key = card_key
	custom_minimum_size = card_size
	focus_mode = Control.FOCUS_NONE
	flat = true
	clip_contents = false
	if key != "":
		var c := CardsData.card(key)
		tooltip_text = "%s (%s)\n%s" % [c["name"], c["kind"], c["desc"]]
	mouse_entered.connect(func():
		if not disabled:
			_lift(true))
	mouse_exited.connect(func(): _lift())

# Cards sit in containers (which own their position), so "lifting" is a scale.
func _lift(hover := false) -> void:
	pivot_offset = Vector2(size.x * 0.5, size.y)
	var s := 1.1 if armed else (1.05 if hover else 1.0)
	if is_inside_tree():
		create_tween().tween_property(self, "scale", Vector2(s, s), 0.1)

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var font := ThemeDB.fallback_font
	var rad := int(clampf(size.x * 0.12, 6, 12))
	# drop shadow
	draw_style_box(UIKit.box(Color(0, 0, 0, 0.35), rad), Rect2(r.position + Vector2(0, 3), r.size))
	if key == "":
		# card back: deep purple with a ghost emblem
		draw_style_box(UIKit.box(Color(0.2, 0.14, 0.42), rad, 2, Color(0.66, 0.56, 1.0, 0.9)), r)
		_grad(r.grow(-4), Color(0.32, 0.22, 0.62), Color(0.12, 0.08, 0.28))
		draw_style_box(UIKit.box(Color(0, 0, 0, 0), rad - 2, 1, Color(1, 1, 1, 0.2)), r.grow(-4))
		var fs := int(size.y * 0.34)
		draw_string(font, Vector2(0, size.y * 0.62), "👻", HORIZONTAL_ALIGNMENT_CENTER, size.x, fs)
		return
	var c := CardsData.card(key)
	var kind_col: Color = CardsData.KIND_COLORS.get(c["kind"], Color.GRAY)
	var frame := UIKit.GOLD if armed else kind_col.lightened(0.35)
	if armed:
		for k in range(4, 0, -1):
			draw_style_box(UIKit.box(Color(UIKit.GOLD, 0.08), rad + k * 2), r.grow(k * 2.5))
	# body: frame, then a gradient in the kind's colour, then a gloss band
	draw_style_box(UIKit.box(kind_col.darkened(0.2), rad, 2, frame), r)
	var inner := r.grow(-3)
	_grad(inner, kind_col.darkened(0.1), kind_col.darkened(0.6))
	draw_rect(Rect2(inner.position + Vector2(2, 1), Vector2(inner.size.x - 4, inner.size.y * 0.16)), Color(1, 1, 1, 0.12))
	# kind ribbon
	var rib := Rect2(inner.position + Vector2(4, 3), Vector2(inner.size.x - 8, clampf(size.y * 0.11, 9, 14)))
	draw_style_box(UIKit.box(Color(0, 0, 0, 0.35), 5), rib)
	draw_string(font, Vector2(rib.position.x, rib.end.y - 2), String(c["kind"]).to_upper(), HORIZONTAL_ALIGNMENT_CENTER,
		rib.size.x, int(clampf(size.y * 0.085, 7, 10)), Color(1, 1, 1, 0.9))
	# icon in a glowing circle
	var ic := Vector2(size.x * 0.5, size.y * 0.37)
	var ir := size.x * 0.24
	for k in range(4, 0, -1):
		draw_circle(ic, ir + k * 2.5, Color(kind_col.lightened(0.4), 0.06))
	draw_circle(ic, ir, Color(0, 0, 0, 0.35))
	draw_arc(ic, ir, 0, TAU, 24, Color(frame, 0.7), 1.5)
	var ifs := int(ir * 1.25)
	draw_string(font, Vector2(0, ic.y + ifs * 0.36), String(c.get("icon", "?")), HORIZONTAL_ALIGNMENT_CENTER, size.x, ifs)
	# name banner
	var nfs := int(clampf(size.x / 7.0, 8, 13))
	var nb := Rect2(inner.position.x + 2, size.y * 0.58, inner.size.x - 4, nfs + 6)
	draw_style_box(UIKit.box(Color(0, 0, 0, 0.45), 4), nb)
	draw_string(font, Vector2(nb.position.x, nb.end.y - 4), String(c["name"]), HORIZONTAL_ALIGNMENT_CENTER, nb.size.x,
		nfs, Color.WHITE)
	# effect text (big cards only) in a recessed box
	if size.y >= 100:
		var db := Rect2(inner.position.x + 4, nb.end.y + 3, inner.size.x - 8, inner.end.y - nb.end.y - 7)
		draw_style_box(UIKit.box(Color(0, 0, 0, 0.25), 5), db)
		_wrapped(font, String(c["desc"]), db.grow(-3), 9)
	if disabled:
		draw_style_box(UIKit.box(Color(0, 0, 0, 0.5), rad), r)

func _grad(r: Rect2, top: Color, bottom: Color) -> void:
	draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([top, top, bottom, bottom]))

func _wrapped(font: Font, text: String, area: Rect2, fs: int) -> void:
	var words := text.split(" ")
	var line := ""
	var y := area.position.y + fs
	for w in words:
		var test := w if line == "" else line + " " + w
		if font.get_string_size(test, 0, -1, fs).x > area.size.x and line != "":
			draw_string(font, Vector2(area.position.x, y), line, HORIZONTAL_ALIGNMENT_CENTER, area.size.x, fs, Color(1, 1, 1, 0.85))
			line = w
			y += fs + 2
			if y > area.end.y:
				return
		else:
			line = test
	draw_string(font, Vector2(area.position.x, y), line, HORIZONTAL_ALIGNMENT_CENTER, area.size.x, fs, Color(1, 1, 1, 0.85))
