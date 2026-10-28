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
	if key == "":
		_panel(r, Color(0.2, 0.15, 0.4), Color(0.6, 0.5, 1.0))
		var t := "👻"
		var fs := int(size.y * 0.32)
		draw_string(font, Vector2((size.x - font.get_string_size(t, 0, -1, fs).x) * 0.5, size.y * 0.62), t,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		return
	var c := CardsData.card(key)
	var kind_col: Color = CardsData.KIND_COLORS.get(c["kind"], Color.GRAY)
	var frame := UIKit.GOLD if armed else kind_col.lightened(0.25)
	_panel(r, kind_col.darkened(0.55), frame)
	if armed:
		draw_rect(r.grow(3), Color(UIKit.GOLD, 0.35), false, 3.0)
	# kind ribbon
	draw_rect(Rect2(4, 4, size.x - 8, 12), kind_col)
	var kt := String(c["kind"]).to_upper()
	draw_string(font, Vector2(0, 14), kt, HORIZONTAL_ALIGNMENT_CENTER, size.x, 9, Color.WHITE)
	# icon
	var icon := String(c.get("icon", "?"))
	var ifs := int(size.y * 0.26)
	draw_string(font, Vector2(0, size.y * 0.47), icon, HORIZONTAL_ALIGNMENT_CENTER, size.x, ifs)
	# name + short effect
	draw_string(font, Vector2(2, size.y * 0.63), String(c["name"]), HORIZONTAL_ALIGNMENT_CENTER, size.x - 4,
		int(clampf(size.x / 7.5, 9, 13)), Color.WHITE)
	if size.y >= 100:
		_wrapped(font, String(c["desc"]), Rect2(5, size.y * 0.7, size.x - 10, size.y * 0.28), 9)
	if disabled:
		draw_rect(r, Color(0, 0, 0, 0.45))

func _panel(r: Rect2, bg: Color, border: Color) -> void:
	draw_style_box(UIKit.box(bg, 8, 2, border), r)

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
