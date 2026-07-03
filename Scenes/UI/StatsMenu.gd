extends MenuWindow
## Per-spirit Stats screen (Image 2). Built in code, shown through UIManager.
## Call show_spirit(spirit_dict) before opening.
##
## Shows: name + stars, type, sprite, ability (name + effect), H/A/D/S stat bars,
## and a circular Type Chart (types on a ring with arrows = super-effective).

const STAT_COLORS := {
	"H": Color("4caf50"),   # green
	"A": Color("e03131"),   # red
	"D": Color("4aa3df"),   # blue
	"S": Color("f4d03f"),   # yellow
}

var _name_lbl: Label
var _type_lbl: Label
var _sprite: TextureRect
var _ability_lbl: Label
var _ability_desc: Label
var _stat_rows := {}        # "H"/"A"/"D"/"S" -> HBoxContainer of 6 boxes
var _chart: Control

func _ready() -> void:
	_build()
	hide()

func on_closed() -> void:
	pass

# ─── Build the static layout ──────────────────────────────────────────────────
func _build() -> void:
	# No fixed height: the window sizes to its (compact) content so it always
	# fits inside the 648px-tall game view.
	var col := _init_window(600, 0)
	col.add_theme_constant_override("separation", 8)

	# Header: name + stars + type
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	_name_lbl = Label.new()
	_name_lbl.add_theme_font_size_override("font_size", 30)
	_name_lbl.add_theme_color_override("font_color", Color("ffd24d"))
	_name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_name_lbl)
	_type_lbl = Label.new()
	_type_lbl.add_theme_font_size_override("font_size", 20)
	header.add_child(_type_lbl)
	col.add_child(header)

	# Middle: sprite + stat bars
	var mid := HBoxContainer.new()
	mid.add_theme_constant_override("separation", 16)
	col.add_child(mid)

	_sprite = TextureRect.new()
	_sprite.custom_minimum_size = Vector2(110, 110)
	_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mid.add_child(_sprite)

	var stats_col := VBoxContainer.new()
	stats_col.add_theme_constant_override("separation", 8)
	stats_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mid.add_child(stats_col)
	for key in ["H", "A", "D", "S"]:
		stats_col.add_child(_make_stat_row(key))

	# Ability
	_ability_lbl = Label.new()
	_ability_lbl.add_theme_font_size_override("font_size", 22)
	_ability_lbl.add_theme_color_override("font_color", Color("ff7a7a"))
	col.add_child(_ability_lbl)
	_ability_desc = Label.new()
	_ability_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ability_desc.add_theme_font_size_override("font_size", 18)
	col.add_child(_ability_desc)

	# Type chart (circular, with arrows)
	var chart_title := Label.new()
	chart_title.text = "⚡ Type Chart   (→ beats)"
	chart_title.add_theme_color_override("font_color", Color("ffd24d"))
	chart_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(chart_title)

	_chart = TypeChartView.new()
	_chart.custom_minimum_size = Vector2(0, 170)
	_chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(_chart)

	var close := Button.new()
	close.text = "Close"
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(0, 40)
	close.pressed.connect(func(): UIManager.close())
	col.add_child(close)

func _make_stat_row(key: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var lbl := Label.new()
	lbl.text = key + ":"
	lbl.custom_minimum_size = Vector2(24, 0)
	row.add_child(lbl)
	var boxes := HBoxContainer.new()
	boxes.add_theme_constant_override("separation", 4)
	row.add_child(boxes)
	_stat_rows[key] = boxes
	return row

# ─── Populate for a spirit ────────────────────────────────────────────────────
func show_spirit(s: Dictionary) -> void:
	_name_lbl.text = "%s  %s" % [s.get("name", "?"), SpiritsData.star_text(s.get("stars", 0))]
	_type_lbl.text = "[%s]" % s.get("type", "")
	_type_lbl.add_theme_color_override("font_color", SpiritsData.type_color(s.get("type", "")))
	_sprite.texture = SpiritsData.sprite_tex(s.get("name", ""), "front")

	var ab := SpiritsData.ability_of(s.get("ability", ""))
	_ability_lbl.text = "%s  ·  %s" % [ab.get("name", ""), ab.get("cat", "")]
	_ability_desc.text = ab.get("desc", "")

	_set_boxes("H", int(s.get("hp_stat", 1)))
	_set_boxes("A", int(s.get("atk", 0)))
	_set_boxes("D", int(s.get("def", 0)))
	_set_boxes("S", int(s.get("spd", 0)))

	_chart.set_type(s.get("type", ""))

func _set_boxes(key: String, value: int) -> void:
	var holder: HBoxContainer = _stat_rows[key]
	for c in holder.get_children():
		c.queue_free()
	for i in 6:
		var box := ColorRect.new()
		box.custom_minimum_size = Vector2(20, 18)
		box.color = STAT_COLORS[key] if i < value else Color(1, 1, 1, 0.12)
		holder.add_child(box)

func _star_string(stars: int) -> String:
	var out := ""
	for i in 3:
		out += "★" if i < stars else "☆"
	return out

# ─── Circular type chart drawn with arrows ────────────────────────────────────
class TypeChartView:
	extends Control
	# Ordered so each weakness cycle sits on adjacent points: a 4-ring then a 3-ring.
	const ORDER := ["Electric", "Water", "Fire", "Grass", "Dark", "Psychic", "Fighting"]
	const ABBR := {
		"Electric": "ELC", "Water": "WTR", "Fire": "FIR", "Grass": "GRS",
		"Dark": "DRK", "Psychic": "PSY", "Fighting": "FGT",
	}
	var current_type := ""

	func _ready() -> void:
		resized.connect(queue_redraw)

	func set_type(t: String) -> void:
		current_type = t
		queue_redraw()

	func _draw() -> void:
		var center := size * 0.5
		var radius := minf(size.x, size.y) * 0.5 - 28.0
		var pos := {}
		for i in ORDER.size():
			var ang := -PI / 2.0 + TAU * float(i) / float(ORDER.size())
			pos[ORDER[i]] = center + Vector2(cos(ang), sin(ang)) * radius
		# arrows: attacker -> defender where super-effective
		for att in SpiritsData.TYPE_CHART:
			for de in SpiritsData.TYPE_CHART[att]:
				if SpiritsData.TYPE_CHART[att][de] >= 2.0 and pos.has(att) and pos.has(de):
					_arrow(pos[att], pos[de])
		# nodes
		var font := ThemeDB.fallback_font
		for t in ORDER:
			var p: Vector2 = pos[t]
			if t == current_type:
				draw_circle(p, 21.0, Color.WHITE)
			draw_circle(p, 17.0, SpiritsData.type_color(t))
			var txt: String = ABBR.get(t, t)
			var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			draw_string(font, p + Vector2(-tw * 0.5, 4), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.BLACK)

	func _arrow(a: Vector2, b: Vector2) -> void:
		var dir := (b - a).normalized()
		var start := a + dir * 20.0
		var end := b - dir * 22.0
		draw_line(start, end, Color(1, 1, 1, 0.5), 2.0)
		var perp := dir.orthogonal()
		draw_colored_polygon(
			PackedVector2Array([end, end - dir * 9.0 + perp * 5.0, end - dir * 9.0 - perp * 5.0]),
			Color(1, 1, 1, 0.75))
