extends CompGame
## The quick stat contests (Haunted Dash, Coffin Lift, Spooky Stare-Down,
## Midnight Marathon). Each entrant's score = stat × 2 + stars + 🎲d6, revealed
## row by row: the stat bar fills, the die tumbles, the total pops, then the
## rows re-sort into the final standings. `stat` / `label` are set before setup().

var stat := "spd"
var label := "Speed"
var _rows: Array = []    # {lane, box, bar, die, total, score}
var _list: VBoxContainer

func _init_game() -> void:
	use_countdown = false
	running = true
	custom_minimum_size = Vector2(620, 70 * lanes.size() + 10)
	_list = UIKit.vbox(8)
	_list.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_list)
	move_child(_list, 0)
	for lane in lanes:
		var s: Dictionary = lane["spirit"]
		var row := UIKit.hbox(12)
		row.custom_minimum_size = Vector2(0, 62)
		var who := UIKit.label(lane["name"], 16, lane["color"])
		who.custom_minimum_size = Vector2(120, 0)
		who.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(who)
		row.add_child(UIKit.spirit_sprite(s, Vector2(48, 48)))
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(200, 18)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.max_value = 6 * 2 + 3 + 6
		bar.add_theme_stylebox_override("background", UIKit.box(Color(0, 0, 0, 0.5), 6))
		bar.add_theme_stylebox_override("fill", UIKit.box(lane["color"], 6))
		row.add_child(bar)
		var die := DiceView.new(46)
		die.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(die)
		var total := UIKit.label("", 22, UIKit.GOLD)
		total.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(total)
		_list.add_child(row)
		var base := int(s.get(stat, 0)) * 2 + int(s.get("stars", 0))
		_rows.append({"lane": lane, "box": row, "bar": bar, "die": die, "total": total,
			"base": base, "roll": randi_range(1, 6)})

func _ready() -> void:
	_reveal()

func _reveal() -> void:
	await get_tree().create_timer(0.4).timeout
	for r in _rows:
		var s: Dictionary = r["lane"]["spirit"]
		var tw: Tween = r["bar"].create_tween()
		tw.tween_property(r["bar"], "value", float(r["base"]), 0.35)
		await tw.finished
		await r["die"].roll(r["roll"], 0.6)
		r["score"] = r["base"] + r["roll"]
		r["bar"].create_tween().tween_property(r["bar"], "value", float(r["score"]), 0.2)
		r["total"].text = "%d  (%s %d×2 + ★%d + 🎲%d)" % [r["score"], label, int(s.get(stat, 0)), int(s.get("stars", 0)), r["roll"]]
		Juice.pop(r["total"], 1.3)
		await get_tree().create_timer(0.25).timeout
	# re-sort the rows into the standings
	var order := ranks()
	for k in order.size():
		for r in _rows:
			if r["lane"]["idx"] == order[k]:
				_list.move_child(r["box"], k)
	Juice.flash(_rows.filter(func(r): return r["lane"]["idx"] == order[0])[0]["box"], Color(1.6, 1.5, 0.8), 0.6)
	finish()

func ranks() -> Array:
	var sorted := _rows.duplicate()
	sorted.sort_custom(func(a, b): return int(a.get("score", 0)) > int(b.get("score", 0)))
	return sorted.map(func(r): return r["lane"]["idx"])

func result_text() -> String:
	return ""   # the rows themselves show the result

func _gui_input(_ev: InputEvent) -> void:
	pass
