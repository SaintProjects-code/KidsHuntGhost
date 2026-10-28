extends Control
class_name MenuWindow
## Base for all pop-up windows. Builds a full-screen dim + a CenterContainer so the
## panel is ALWAYS centred on screen (fixes the off-centre windows), regardless of
## viewport size. Subclasses call _init_window(w, h) and fill the returned VBox.

var panel: PanelContainer
var _dim: ColorRect
var _center: CenterContainer

func _init_window(w: float, h: float = 0.0) -> VBoxContainer:
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # the root never eats clicks
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# All pop-ups share the game's purple theme (same as the board chrome and
	# player-info card), instead of Godot's default grey.
	theme = load("res://Scenes/Menu/MenuTheme.tres")

	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.55)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)

	var center := CenterContainer.new()
	_center = center
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The centering layer never catches clicks itself — empty space around the
	# panel falls through to the dim below (and, on click-through windows, all
	# the way to the board's action buttons). Only the panel stays interactive.
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(w, h)
	center.add_child(panel)
	# a panel taller/wider than the screen shrinks to fit instead of being cut off
	panel.resized.connect(_fit_panel)
	resized.connect(_fit_panel)

	var margin := MarginContainer.new()
	for s in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + s, 16)
	panel.add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	margin.add_child(vb)
	return vb

const FIT_MARGIN := 0.96   # keep a sliver of screen around a shrunk panel

# Containers reset their children's scale on every layout pass, so the
# centering layer (a plain child of this root) is what gets scaled, around the
# screen centre.
func _fit_panel() -> void:
	var avail: Vector2 = size if size.x > 0.0 else get_viewport_rect().size
	if panel.size.x <= 0.0 or panel.size.y <= 0.0 or avail.x <= 0.0:
		return
	var k: float = minf(1.0, minf(avail.x * FIT_MARGIN / panel.size.x, avail.y * FIT_MARGIN / panel.size.y))
	# an oversized panel stretches the centering layer downward past the
	# screen, so recentre it on the screen before scaling
	var extra := Vector2(maxf(0.0, panel.size.x - avail.x), maxf(0.0, panel.size.y - avail.y)) * 0.5
	_center.offset_left = -extra.x
	_center.offset_right = extra.x
	_center.offset_top = -extra.y
	_center.offset_bottom = extra.y
	_center.pivot_offset = avail * 0.5 + extra
	_center.scale = Vector2(k, k)

# Let clicks in the DIMMED area fall through to whatever's behind this window
# (used by the tile-flow windows so the board's action buttons — rendered on a
# lower layer — stay pressable while the window is up). The window's own panel
# still catches its clicks. Overlay menus keep the default (blocking) dim.
func set_click_through(on: bool) -> void:
	if _dim != null:
		_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE if on else Control.MOUSE_FILTER_STOP

# Convenience: a centered title label.
func _title_label(text: String, size: int = 26) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color("ffd24d"))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

# A themed button. Its look comes from the label (Cancel / Close → dark,
# Quit → red, everything else → purple) unless `kind` is given; `min_h`
# picks the size (≤34 small, ≤46 medium, else large).
func _button(text: String, cb: Callable, min_h: int = 44, kind: String = "") -> Button:
	var b := Button.new()
	b.text = text
	UIKit.style_button(b, kind if kind != "" else UIKit.kind_for(text), UIKit.size_for(min_h))
	b.pressed.connect(func():
		Sfx.play("click")
		cb.call())
	return b
