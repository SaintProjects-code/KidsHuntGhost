class_name CompGame
extends Control
## Base for the competition minigames. Handles what every game shares:
##   • one LANE per entrant (entrant dicts: idx, spirit, human, color, name, slot, tex)
##   • shared-keyboard input: each human plays on their Controls slot
##     (P1 W/ASD, P2 I/JKL, P3 ↑/←↓→, P4 Num8/456) or clicks their lane
##   • the 3-2-1-GO countdown (with beeps), the finish banner, sounds
##   • an all-time RECORD per game (higher = better unless record_lower_better)
## A game overrides _tick(delta), _draw_game(), _on_action(lane, action) and
## ranks(). Call finish() when it's over; `finished(ranks)` follows a beat later.

signal finished(ranks: Array)

const ORDINAL := ["1st", "2nd", "3rd", "4th", "5th", "6th"]
const RECORDS_PATH := "user://comp_records.save"

var lanes: Array = []          # one Dictionary per entrant (games add their own fields)
var t := 0.0                   # seconds since GO
var running := false
var ended := false
var use_countdown := true
var record_key := ""           # "" = this game keeps no record
var record_lower_better := false
var record := 0.0              # the stored all-time best (0 = none yet)
var result_value := 0.0        # this run's record-able score (set by the game)
var _countdown := 3.0
var _last_beep := 4
var _end_t := 0.0
var _emitted := false
var _overlay: Control           # banners draw above any child panels

func setup(entries: Array) -> void:
	for e in entries:
		var lane: Dictionary = e.duplicate()
		lane["slot"] = Controls.slot_of(e["idx"]) if e["human"] else -1
		lane["tex"] = SpiritsData.sprite_tex(String(e["spirit"].get("name", "")), "front")
		lanes.append(lane)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	if not use_countdown:
		_countdown = 0.0
		running = true
	_init_game()
	if record_key != "":
		record = float(_load_records().get(record_key, 0.0))

# ── for games to override ─────────────────────────────────────────────────────

func _init_game() -> void:
	pass

func _tick(_delta: float) -> void:
	pass

func _draw_game() -> void:
	pass

func _on_action(_lane: Dictionary, _action: String) -> void:
	pass

func ranks() -> Array:
	return lanes.map(func(l): return l["idx"])

# The winner banner text ("Wispy wins — 12.3s!").
func result_text() -> String:
	var r := ranks()
	return "🏁 %s wins!" % _lane_by_idx(r[0])["name"] if not r.is_empty() else "🏁 Done!"

# ── shared flow ───────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if _emitted:
		return
	if ended:
		_end_t += delta
		_overlay.queue_redraw()
		if _end_t > 1.4:
			_emitted = true
			set_process(false)
			_save_record_if_beaten()
			finished.emit(ranks())
		return
	if _countdown > 0.0:
		_countdown -= delta
		var n := int(ceil(_countdown))
		if n != _last_beep:
			_last_beep = n
			Sfx.play("go" if n <= 0 else "beep")
		if _countdown <= 0.0:
			running = true
		queue_redraw()
		_overlay.queue_redraw()
		return
	t += delta
	_tick(delta)
	queue_redraw()
	_overlay.queue_redraw()

func finish() -> void:
	if ended:
		return
	ended = true
	running = false
	Sfx.play("win")

func beat_record() -> bool:
	if record_key == "" or result_value <= 0.0:
		return false
	if record <= 0.0:
		return true
	return result_value < record if record_lower_better else result_value > record

func _save_record_if_beaten() -> void:
	if beat_record():
		var all := _load_records()
		all[record_key] = result_value
		var f := FileAccess.open(RECORDS_PATH, FileAccess.WRITE)
		if f:
			f.store_var(all)

func _load_records() -> Dictionary:
	var f := FileAccess.open(RECORDS_PATH, FileAccess.READ)
	if f == null:
		return {}
	var d = f.get_var()
	return d if d is Dictionary else {}

# ── input ─────────────────────────────────────────────────────────────────────

func _unhandled_key_input(ev: InputEvent) -> void:
	var hit := Controls.lookup(ev)
	if hit.is_empty() or not running:
		return
	for lane in lanes:
		if lane["human"] and lane["slot"] == hit[0]:
			get_viewport().set_input_as_handled()
			_on_action(lane, hit[1])

# Clicking / tapping a lane = that lane's ACTION (lanes stack top to bottom).
func _gui_input(ev: InputEvent) -> void:
	var pressed: bool = (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT) \
		or (ev is InputEventScreenTouch and ev.pressed)
	if not pressed or not running or lanes.is_empty():
		return
	var i := int(ev.position.y / (size.y / lanes.size()))
	if i >= 0 and i < lanes.size() and lanes[i]["human"]:
		_on_action(lanes[i], "action")

func is_held(lane: Dictionary) -> bool:
	if not lane["human"]:
		return false
	if Controls.is_held(lane["slot"], "action"):
		return true
	# mouse held over this lane
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var m := get_local_mouse_position()
		var h := size.y / lanes.size()
		return Rect2(0, lanes.find(lane) * h, size.x, h).has_point(m)
	return false

# "[W]" for humans, "(CPU)" otherwise.
func key_hint(lane: Dictionary, action: String = "action") -> String:
	return "[%s]" % Controls.key_name(lane["slot"], action) if lane["human"] else "(CPU)"

func _lane_by_idx(idx: int) -> Dictionary:
	for lane in lanes:
		if lane["idx"] == idx:
			return lane
	return {"name": "?"}

# ── drawing ───────────────────────────────────────────────────────────────────

func _draw() -> void:
	_draw_game()

func _draw_overlay() -> void:
	var font := ThemeDB.fallback_font
	if _countdown > 0.0:
		var n := int(ceil(_countdown))
		var pulse: float = 1.0 + (ceil(_countdown) - _countdown) * 0.5
		banner(font, "%d" % n if n > 0 else "GO!", 0.0, int(44 * pulse))
	elif ended:
		banner(font, result_text())
		if beat_record():
			banner(font, "🎉 NEW RECORD! (+%d pts)" % Balance.RECORD_BONUS, 42.0, 28)

func banner(font: Font, text: String, dy: float = 0.0, fs: int = 34) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var p := Vector2((size.x - w) * 0.5, size.y * 0.5 + dy)
	_overlay.draw_string(font, p + Vector2(3, 3), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.75))
	_overlay.draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UIKit.GOLD)

# A spirit in a player-coloured ring (the token every game uses).
func draw_spirit(lane: Dictionary, c: Vector2, r: float, tint := Color.WHITE, squash := Vector2.ONE) -> void:
	draw_circle(c, r + 3.0, lane["color"] * tint)
	draw_circle(c, r, Color(0.12, 0.12, 0.2) * tint)
	if lane["tex"]:
		var side := Vector2(r * 1.6, r * 1.6) * squash
		draw_texture_rect(lane["tex"], Rect2(c - side * 0.5, side), false, tint)

func lane_label(lane: Dictionary, i: int, extra: String, lane_h: float) -> void:
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(10, i * lane_h + 20), "%s  %s  %s" % [lane["name"], key_hint(lane), extra],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, lane["color"])
