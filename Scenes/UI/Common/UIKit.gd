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

# ── Buttons ───────────────────────────────────────────────────────────────────
# One look for every button in the game: a rounded "3D" pill (thicker bottom
# edge) in the game's palette. kind: primary (purple) · secondary (dark, for
# Cancel / Close / Leave) · gold (big moments: Roll, Fly, Trade) · danger (Quit).
# size: s / m / l.

const BUTTON_KINDS := {
	"primary":   [Color(0.46, 0.36, 0.86), Color(0.58, 0.48, 0.97), Color(0.36, 0.27, 0.72), Color(1.0, 0.85, 0.35, 0.85)],
	"secondary": [Color(0.15, 0.12, 0.28), Color(0.22, 0.18, 0.4), Color(0.1, 0.08, 0.2), Color(0.6, 0.5, 1.0, 0.7)],
	"gold":      [Color(0.86, 0.62, 0.12), Color(0.96, 0.74, 0.24), Color(0.7, 0.48, 0.08), Color(1.0, 0.95, 0.75, 0.9)],
	"danger":    [Color(0.6, 0.18, 0.25), Color(0.74, 0.26, 0.32), Color(0.44, 0.12, 0.18), Color(1.0, 0.65, 0.65, 0.8)],
}
const BUTTON_SIZES := {
	"s": {"font": 13, "h": 30, "pad": 10, "r": 9},
	"m": {"font": 16, "h": 40, "pad": 16, "r": 12},
	"l": {"font": 20, "h": 54, "pad": 22, "r": 16},
}

static func style_button(b: Button, kind: String = "primary", size: String = "m") -> Button:
	var c: Array = BUTTON_KINDS.get(kind, BUTTON_KINDS["primary"])
	var z: Dictionary = BUTTON_SIZES.get(size, BUTTON_SIZES["m"])
	var states := {"normal": c[0], "hover": c[1], "pressed": c[2], "disabled": Color(0.3, 0.28, 0.4, 0.75)}
	for st in states:
		var sb := box(states[st], z["r"], 2, c[3] if st != "disabled" else Color(1, 1, 1, 0.12), Vector2(z["pad"], 4))
		sb.border_width_bottom = 2 if st == "pressed" else 5   # pressed = pushed in
		sb.border_color = c[3] if st != "disabled" else Color(1, 1, 1, 0.12)
		if st != "pressed":
			sb.shadow_color = Color(0, 0, 0, 0.3)
			sb.shadow_size = 3
			sb.shadow_offset = Vector2(0, 2)
		sb.content_margin_top = 6 if st == "pressed" else 4
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_font_size_override("font_size", z["font"])
	b.add_theme_color_override("font_color", Color.WHITE if kind != "gold" else Color(0.18, 0.1, 0.02))
	b.add_theme_color_override("font_hover_color", Color.WHITE if kind != "gold" else Color(0.1, 0.05, 0.0))
	b.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 0.85) if kind != "gold" else Color(0.2, 0.12, 0.02))
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.4))
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = maxf(b.custom_minimum_size.y, z["h"])
	return b

# Pick a kind from the label, so Cancel / Close / Quit read right everywhere.
static func kind_for(text: String) -> String:
	var t := text.to_lower()
	if t.contains("quit"):
		return "danger"
	for w in ["cancel", "close", "leave", "back", "keep", "skip", "not today", "walk away"]:
		if t.contains(w):
			return "secondary"
	return "primary"

static func size_for(min_h: int) -> String:
	return "s" if min_h <= 34 else ("m" if min_h <= 46 else "l")

# Compact button for dense rows (jar pickers, team cards, shop rows).
static func small_button(text: String, cb: Callable, _font_size: int = 14) -> Button:
	var b := Button.new()
	b.text = text
	style_button(b, kind_for(text), "s")
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
