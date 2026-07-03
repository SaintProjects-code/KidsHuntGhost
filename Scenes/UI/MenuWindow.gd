extends Control
class_name MenuWindow
## Base for all pop-up windows. Builds a full-screen dim + a CenterContainer so the
## panel is ALWAYS centred on screen (fixes the off-centre windows), regardless of
## viewport size. Subclasses call _init_window(w, h) and fill the returned VBox.

var panel: PanelContainer

func _init_window(w: float, h: float = 0.0) -> VBoxContainer:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# All pop-ups share the game's purple theme (same as the board chrome and
	# player-info card), instead of Godot's default grey.
	theme = load("res://Scenes/Menu/MenuTheme.tres")

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(w, h)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for s in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + s, 16)
	panel.add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	margin.add_child(vb)
	return vb

# Convenience: a centered title label.
func _title_label(text: String, size: int = 26) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color("ffd24d"))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

func _button(text: String, cb: Callable, min_h: int = 44) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, min_h)
	b.pressed.connect(cb)
	return b
