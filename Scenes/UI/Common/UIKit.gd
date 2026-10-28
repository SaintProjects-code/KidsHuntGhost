class_name UIKit
## Shared look-and-feel helpers so windows don't each rebuild the same
## StyleBoxes, sprite rects and HP bars by hand.

const GOLD := Color("ffd24d")
const PURPLE := Color(0.541, 0.435, 0.965)
const PURPLE_DARK := Color(0.345, 0.247, 0.737)
const NIGHT := Color(0.106, 0.086, 0.196)
const CARD_BG := Color(0.08, 0.07, 0.16, 0.95)
const GOOD := Color("9fff9f")
const BAD := Color("ff9f9f")
const HP_GREEN := Color(0.4, 0.85, 0.35)
const HP_YELLOW := Color(0.95, 0.85, 0.3)
const HP_RED := Color(0.9, 0.3, 0.25)

# A rounded flat box. pad = content margin (x, y).
static func box(bg: Color, radius: int = 8, border: int = 0, border_color := Color(0, 0, 0, 0),
		pad := Vector2.ZERO) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(border)
	sb.border_color = border_color
	sb.content_margin_left = pad.x
	sb.content_margin_right = pad.x
	sb.content_margin_top = pad.y
	sb.content_margin_bottom = pad.y
	return sb

# The game's standard dark card panel with a soft purple border.
static func card_panel(min_size := Vector2.ZERO, bg: Color = CARD_BG) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = min_size
	card.add_theme_stylebox_override("panel", box(bg, 12, 2, Color(PURPLE, 0.5), Vector2(12, 10)))
	return card

static func label(text: String, size: int = 16, color = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	if color != null:
		l.add_theme_color_override("font_color", color)
	return l

static func wrap_label(text: String, size: int, width: float) -> Label:
	var l := label(text, size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(width, 0)
	return l

# A pixel-art sprite slot that keeps its aspect and never blurs.
static func sprite(tex: Texture2D, size := Vector2(48, 48)) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.custom_minimum_size = size
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return r

static func spirit_sprite(spirit: Dictionary, size := Vector2(48, 48), view := "front") -> TextureRect:
	return sprite(SpiritsData.sprite_tex(String(spirit.get("name", "")), view), size)

static func hp_color(ratio: float) -> Color:
	return HP_GREEN if ratio > 0.5 else (HP_YELLOW if ratio > 0.2 else HP_RED)

static func hp_bar(height: int = 10) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, height)
	bar.add_theme_stylebox_override("background", box(Color(0.07, 0.1, 0.06, 0.9), 4))
	return bar

# Point an HP bar at a spirit (value, max and the green→red fill colour).
static func set_hp(bar: ProgressBar, hp_now: int, hp_max: int) -> void:
	bar.max_value = maxi(1, hp_max)
	bar.value = hp_now
	bar.add_theme_stylebox_override("fill", box(hp_color(float(hp_now) / float(maxi(1, hp_max))), 4))

# Compact purple button for dense rows (the theme's padding is too chunky).
static func small_button(text: String, cb: Callable, font_size: int = 14) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", font_size)
	var states := {"normal": PURPLE, "hover": Color(0.651, 0.565, 1.0),
		"pressed": Color(0.435, 0.337, 0.847), "disabled": Color(0.396, 0.388, 0.471)}
	for state in states:
		var sb := box(states[state], 7, 0, PURPLE_DARK, Vector2(10, 3))
		sb.border_width_bottom = 2
		b.add_theme_stylebox_override(state, sb)
	b.pressed.connect(func():
		Sfx.play("click")
		cb.call())
	return b

static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()

static func hbox(sep: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h

static func vbox(sep: int = 6) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v

# Buttons need their child controls to ignore the mouse so clicks land.
static func pass_through(node: Control) -> void:
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in node.get_children():
		if c is Control:
			pass_through(c)
