class_name DiceView
extends Control
## One animated die. A d6 shows pips; any other size (the d100 capture roll)
## shows its number on a gem. `await die.roll(5)` tumbles through random faces,
## bounces, lands on 5 with a thud, and returns once it has settled.

const PIP_LAYOUT := {
	1: [Vector2(0.5, 0.5)],
	2: [Vector2(0.25, 0.25), Vector2(0.75, 0.75)],
	3: [Vector2(0.25, 0.25), Vector2(0.5, 0.5), Vector2(0.75, 0.75)],
	4: [Vector2(0.25, 0.25), Vector2(0.75, 0.25), Vector2(0.25, 0.75), Vector2(0.75, 0.75)],
	5: [Vector2(0.25, 0.25), Vector2(0.75, 0.25), Vector2(0.5, 0.5), Vector2(0.25, 0.75), Vector2(0.75, 0.75)],
	6: [Vector2(0.25, 0.22), Vector2(0.75, 0.22), Vector2(0.25, 0.5), Vector2(0.75, 0.5),
		Vector2(0.25, 0.78), Vector2(0.75, 0.78)],
}

var sides := 6
var face := 1
var tint := Color.WHITE          # body colour
var pip_color := Color(0.12, 0.1, 0.2)
var settled := true
var _tilt := 0.0

func _init(die_size: float = 56.0, die_sides: int = 6, body: Color = Color.WHITE) -> void:
	custom_minimum_size = Vector2(die_size, die_size)
	sides = die_sides
	tint = body
	face = sides
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func show_face(value: int) -> void:
	face = value
	settled = true
	queue_redraw()

# Tumble, then land on `value`. Pitch varies a little per die so a pair of
# dice doesn't sound like one.
func roll(value: int, duration: float = 0.7) -> void:
	settled = false
	pivot_offset = size * 0.5
	var t := 0.0
	var pitch := randf_range(0.9, 1.15)
	while t < duration:
		face = randi_range(1, sides)
		_tilt = randf_range(-0.35, 0.35)
		position.y -= 0.0
		queue_redraw()
		Sfx.play("tick", pitch)
		var step := lerpf(0.045, 0.12, t / duration)   # slows down as it lands
		await get_tree().create_timer(step).timeout
		t += step
	face = value
	_tilt = 0.0
	settled = true
	queue_redraw()
	Sfx.play("dice", pitch)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(1.3, 1.3), 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2.ONE, 0.14)
	await tw.finished

func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := size * 0.5
	draw_set_transform(c, _tilt, Vector2.ONE)
	var r := Rect2(Vector2(-s, -s) * 0.5, Vector2(s, s))
	if sides == 6:
		_rounded_rect(r.grow(2), Color(0, 0, 0, 0.55))
		_rounded_rect(r, tint)
		var pip_r := s * 0.085
		for p in PIP_LAYOUT.get(face, []):
			draw_circle(r.position + p * s, pip_r, pip_color)
	else:
		# a gem for big dice (d100)
		var pts := PackedVector2Array()
		for i in 6:
			var a := TAU * i / 6.0 + PI / 6.0
			pts.append(Vector2(cos(a), sin(a)) * s * 0.52)
		draw_colored_polygon(pts, Color(0, 0, 0, 0.55))
		var inner := PackedVector2Array()
		for p in pts:
			inner.append(p * 0.92)
		draw_colored_polygon(inner, tint)
		var font := ThemeDB.fallback_font
		var txt := str(face)
		var fs := int(s * (0.42 if face < 100 else 0.34))
		var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2(-w * 0.5, fs * 0.35), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, pip_color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _rounded_rect(r: Rect2, col: Color) -> void:
	var rad := r.size.x * 0.18
	draw_rect(Rect2(r.position + Vector2(rad, 0), r.size - Vector2(rad * 2, 0)), col)
	draw_rect(Rect2(r.position + Vector2(0, rad), r.size - Vector2(0, rad * 2)), col)
	for corner in [r.position + Vector2(rad, rad), r.position + Vector2(r.size.x - rad, rad),
			r.position + Vector2(rad, r.size.y - rad), r.position + r.size - Vector2(rad, rad)]:
		draw_circle(corner, rad, col)
