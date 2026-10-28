class_name CompChips
## Round portrait chips used by the competition window.

# A spirit as a small clickable circle with its A/D/S stats underneath, and
# (in selection) its rating for the announced event.
class SpiritChip:
	extends Control
	signal picked(chip)
	var spirit: Dictionary
	var selected := false
	var rating_text := ""
	var _tex: Texture2D

	func _init(s: Dictionary, rating: String = "") -> void:
		spirit = s
		rating_text = rating
		custom_minimum_size = Vector2(64, 92 if rating != "" else 78)
		tooltip_text = String(s.get("name", "?"))
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_tex = SpiritsData.sprite_tex(s.get("name", ""), "front")

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			picked.emit(self)

	func set_selected(v: bool) -> void:
		selected = v
		if v:
			Juice.pop(self, 1.15)
		queue_redraw()

	func _draw() -> void:
		var d := minf(size.x, size.y - (30.0 if rating_text != "" else 16.0))
		var c := Vector2(size.x * 0.5, d * 0.5)
		var r := d * 0.5 - 2.0
		if selected:
			draw_circle(c, r, Color.WHITE)
		draw_circle(c, r - 3.0, SpiritsData.type_color(spirit.get("type", "")))
		if _tex:
			var side := r * 1.5
			draw_texture_rect(_tex, Rect2(c - Vector2(side, side) * 0.5, Vector2(side, side)), false)
		var font := ThemeDB.fallback_font
		var txt := "A%d D%d S%d" % [int(spirit.get("atk", 0)), int(spirit.get("def", 0)), int(spirit.get("spd", 0))]
		var y := d + 12.0
		draw_string(font, Vector2(0, y), txt, HORIZONTAL_ALIGNMENT_CENTER, size.x, 10, Color(1, 1, 1, 0.9))
		if rating_text != "":
			draw_string(font, Vector2(0, y + 14.0), rating_text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 12, UIKit.GOLD)

# The player's trainer portrait in a big circle tinted with the player's colour.
class TrainerChip:
	extends Control
	var _tex: Texture2D
	var _color: Color

	func _init(tex: Texture2D, color: Color) -> void:
		_tex = tex
		_color = color
		custom_minimum_size = Vector2(84, 84)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 2.0
		draw_circle(c, r, _color)
		draw_circle(c, r - 4.0, _color.darkened(0.45))
		if _tex:
			var ts := _tex.get_size()
			var s := (r * 1.5) / maxf(ts.x, ts.y)
			draw_texture_rect(_tex, Rect2(c - ts * s * 0.5, ts * s), false)
