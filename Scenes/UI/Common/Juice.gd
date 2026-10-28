class_name Juice
## Small reusable feel-good animations: pops, shakes, flashes and floating
## numbers. All are fire-and-forget tweens bound to the node they animate.

# Scale bounce (pivot is set to the centre so it grows in place).
static func pop(c: Control, amount: float = 1.18, time: float = 0.2) -> void:
	if not is_instance_valid(c):
		return
	c.pivot_offset = c.size * 0.5
	var tw := c.create_tween()
	tw.tween_property(c, "scale", Vector2(amount, amount), time * 0.4) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "scale", Vector2.ONE, time * 0.6) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)

# Rattle sideways and settle back.
static func shake(c: Control, strength: float = 7.0, time: float = 0.25) -> void:
	if not is_instance_valid(c):
		return
	var home: Vector2 = c.get_meta("shake_home", c.position)
	c.set_meta("shake_home", home)
	var tw := c.create_tween()
	var steps := 6
	for i in steps:
		var k := 1.0 - float(i) / steps
		tw.tween_property(c, "position", home + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * strength * k,
			time / steps)
	tw.tween_property(c, "position", home, 0.03)
	tw.tween_callback(func(): c.remove_meta("shake_home"))

# Brief over-bright tint (hits, catches).
static func flash(c: CanvasItem, color := Color(1.8, 1.8, 1.8), time: float = 0.25) -> void:
	if not is_instance_valid(c):
		return
	var tw := c.create_tween()
	c.modulate = color
	tw.tween_property(c, "modulate", Color.WHITE, time)

# A number/word that floats up and fades out above `at` (in `parent` space).
static func float_text(parent: Control, at: Vector2, text: String, color: Color = Color.WHITE,
		size: int = 22) -> void:
	if not is_instance_valid(parent):
		return
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.z_index = 50
	parent.add_child(l)
	l.position = at - Vector2(l.get_minimum_size().x * 0.5, 0)
	var tw := l.create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 46.0, 0.9).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(l, "modulate:a", 0.0, 0.9).set_delay(0.35)
	tw.chain().tween_callback(l.queue_free)

# Slide a control in from below while fading in.
static func slide_in(c: Control, from_y: float = 30.0, time: float = 0.25) -> void:
	if not is_instance_valid(c):
		return
	c.modulate.a = 0.0
	var tw := c.create_tween().set_parallel(true)
	tw.tween_property(c, "modulate:a", 1.0, time)
	tw.tween_property(c, "position:y", c.position.y, time).from(c.position.y + from_y) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
