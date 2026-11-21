class_name CompGame
extends Control
## Base for the competition minigames. Handles what every game shares:
##   • one LANE per entrant (entrant dicts: idx, spirit, human, color, name, slot, tex),
##     laid out as ROWS, side-by-side COLUMNS, or a 2×2 GRID (lane_rect)
##   • a "how to play" card, then the 3-2-1-GO countdown, then the finish banner
##   • shared-keyboard input: each human plays on their Controls slot
##     (P1 W/ASD, P2 I/JKL, P3 ↑/←↓→, P4 Num8/456) or clicks their lane
##   • the 3-2-1-GO countdown (with beeps), the finish banner, sounds
##   • an all-time RECORD per game (higher = better unless record_lower_better)
## A game overrides _tick(delta), _draw_game(), _on_action(lane, action) and
## ranks(). Call finish() when it's over; `finished(ranks)` follows a beat later.

signal finished(ranks: Array)

const ORDINAL := ["1st", "2nd", "3rd", "4th", "5th", "6th"]
enum Layout { ROWS, COLUMNS, GRID }
const GAP := 10.0
const INTRO_TIME := 2.6       # the how-to-play card stays this long
const END_HOLD := 2.2         # the result banner stays this long
const RECORDS_PATH := "user://comp_records.save"

var lanes: Array = []          # one Dictionary per entrant (games add their own fields)
var t := 0.0                   # seconds since GO
var running := false
var ended := false
var use_countdown := true
var use_intro := true
var layout := Layout.COLUMNS
var how_to := ""               # one line shown on the intro card
var record_key := ""           # "" = this game keeps no record
var record_lower_better := false
var record := 0.0              # the stored all-time best (0 = none yet)
var result_value := 0.0        # this run's record-able score (set by the game)
var _intro := INTRO_TIME
var _countdown := 3.0
var _last_beep := 4
var _end_t := 0.0
var _emitted := false
var _overlay: Control           # banners draw above any child panels
# 3D maps: games that have _build_3d(stage) / _update_3d(stage, delta) draw
# into a MiniStage3D instead of their 2D playfield (same rules, new look).
var stage3d: Control = null

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
	_init_game()
	if has_method("_build_3d") and bool(GameData.map_info(GameState.active_map).get("view_3d", false)):
		stage3d = preload("res://Scenes/UI/Competition/MiniStage3D.gd").new()
		stage3d.lanes_n = lanes.size()   # cameras pull back to fit 5–6 players
		add_child(stage3d)
		move_child(stage3d, 0)   # under the banners and any child widgets (dice…)
		call("_build_3d", stage3d)
	if not use_countdown:
		_countdown = 0.0
	if not use_intro or how_to == "":
		_intro = 0.0
	if _intro > 0.0:
		move_child(_overlay, -1)   # the how-to card covers the game's own widgets (dice…)
	if _intro > 0.0 and lanes.any(func(l): return l["human"]):
		# people are playing: the how-to card waits for Start so they can read it
		_start_btn = Button.new()
		_start_btn.text = "▶  Start!"
		UIKit.style_button(_start_btn, "primary", "l")
		_start_btn.add_theme_font_size_override("font_size", 22)
		_start_btn.custom_minimum_size = Vector2(220, 52)
		_start_btn.pressed.connect(_press_start)
		add_child(_start_btn)
	if record_key != "":
		record = float(_load_records().get(record_key, 0.0))

# ── for games to override ─────────────────────────────────────────────────────

func _init_game() -> void:
	pass

func _tick(_delta: float) -> void:
	pass

# Called once when play begins (games without a countdown).
func _on_start() -> void:
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
	if stage3d and not _emitted:
		call("_update_3d", stage3d, delta)
	if _emitted:
		return
	if ended:
		_end_t += delta
		_overlay.queue_redraw()
		if _end_t > END_HOLD:
			_emitted = true
			set_process(false)
			_save_record_if_beaten()
			finished.emit(ranks())
		return
	if _intro > 0.0:
		if _start_btn:   # hold the card up (fully shown) until Start
			_intro = maxf(_intro - delta, INTRO_TIME - 0.31)
			var r := _intro_rect()
			_start_btn.size = _start_btn.custom_minimum_size
			_start_btn.position = Vector2(r.get_center().x - _start_btn.size.x * 0.5, r.end.y - 66.0)
			_start_btn.modulate.a = clampf((INTRO_TIME - _intro) / 0.3, 0.0, 1.0)
		else:
			_intro -= delta
		_overlay.queue_redraw()
		queue_redraw()
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
	if not running:
		running = true   # no countdown: play starts right after the intro
		_on_start()
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
	if _start_btn and ev.is_pressed() and not ev.is_echo():
		# Enter / Space, or any player's own key, also starts
		var k := (ev as InputEventKey).keycode if ev is InputEventKey else 0
		if k in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE] or (not hit.is_empty() and lanes.any(func(l): return l["human"] and l["slot"] == hit[0])):
			get_viewport().set_input_as_handled()
			_press_start()
		return
	if hit.is_empty() or not running:
		return
	for lane in lanes:
		if lane["human"] and lane["slot"] == hit[0]:
			get_viewport().set_input_as_handled()
			_on_action(lane, hit[1])

# Where lane `i` sits inside the game area.
func lane_rect(i: int) -> Rect2:
	var n := maxi(1, lanes.size())
	match layout:
		Layout.ROWS:
			var h := (size.y - GAP * (n - 1)) / n
			return Rect2(0, i * (h + GAP), size.x, h)
		Layout.GRID:
			var cols := 1 if n == 1 else (2 if n <= 4 else 3)   # 5–6 players: 3 × 2
			var rows := ceili(float(n) / cols)
			var w := (size.x - GAP * (cols - 1)) / cols
			var h := (size.y - GAP * (rows - 1)) / rows
			return Rect2((i % cols) * (w + GAP), (i / cols) * (h + GAP), w, h)
	var cw := (size.x - GAP * (n - 1)) / n
	return Rect2(i * (cw + GAP), 0, cw, size.y)

func lane_at(pos: Vector2) -> int:
	for i in lanes.size():
		if lane_rect(i).has_point(pos):
			return i
	return -1

# Clicking / tapping a lane = that lane's ACTION.
func _gui_input(ev: InputEvent) -> void:
	var pressed: bool = (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT) \
		or (ev is InputEventScreenTouch and ev.pressed)
	if not pressed or not running:
		return
	var i := lane_at(ev.position)
	if i >= 0 and lanes[i]["human"]:
		_on_action(lanes[i], "action")

# Held input for a human lane: its key, or the mouse held down on the lane
# (for "left"/"right": on that half of the lane).
func is_held(lane: Dictionary, action: String = "action") -> bool:
	if not lane["human"] or not running:
		return false
	if Controls.is_held(lane["slot"], action):
		return true
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var r := lane_rect(lanes.find(lane))
		var m := get_local_mouse_position()
		if not r.has_point(m):
			return false
		match action:
			"left": return m.x < r.get_center().x
			"right": return m.x >= r.get_center().x
			_: return true
	return false

# -1 / 0 / +1 from the lane's held left/right.
func steer(lane: Dictionary) -> float:
	return (1.0 if is_held(lane, "right") else 0.0) - (1.0 if is_held(lane, "left") else 0.0)

# "[W]" for humans, "(CPU)" otherwise.
func key_hint(lane: Dictionary, action: String = "action") -> String:
	return "[%s]" % Controls.key_name(lane["slot"], action) if lane["human"] else "(CPU)"

func _lane_by_idx(idx: int) -> Dictionary:
	for lane in lanes:
		if lane["idx"] == idx:
			return lane
	return {"name": "?"}

# ── drawing kit (shared modern look) ──────────────────────────────────────────
# Soft gradients, glows, shadows, rounded glass panels and outlined text, so
# every game reads as one polished style.

const INK := Color(0.04, 0.03, 0.09)

func _draw() -> void:
	if stage3d:
		if has_method("_draw_3d_hud"):
			call("_draw_3d_hud")   # a 3D game's flat extras (a timer, meters…)
		return
	_draw_game()

# Vertical gradient (top → bottom).
func grad_rect(r: Rect2, top: Color, bottom: Color) -> void:
	draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([top, top, bottom, bottom]))

# Horizontal gradient (left → right).
func grad_rect_h(r: Rect2, left: Color, right: Color) -> void:
	draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([left, right, right, left]))

# A soft radial glow: stacked translucent circles fading outward.
func glow(c: Vector2, r: float, col: Color, rings: int = 7) -> void:
	for k in range(rings, 0, -1):
		var f := float(k) / rings
		draw_circle(c, r * (0.4 + f * 1.1), Color(col, col.a * 0.16 * (1.0 - f * 0.7)))

# A soft elliptical drop shadow on the ground.
func shadow(c: Vector2, w: float, h: float, alpha: float = 0.35) -> void:
	draw_set_transform(c, 0.0, Vector2(1.0, h / w))
	for k in 4:
		draw_circle(Vector2.ZERO, w * (1.0 - k * 0.18), Color(0, 0, 0, alpha * 0.25))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func rrect(r: Rect2, col: Color, radius: int = 10, border: int = 0, border_col := Color(1, 1, 1, 0.15)) -> void:
	draw_style_box(UIKit.box(col, radius, border, border_col), r)

# Crisp outlined text. width > 0 = centred inside that width.
func text(pos: Vector2, s: String, fs: int, col: Color = Color.WHITE, width: float = -1.0, outline: int = 4) -> void:
	var font := ThemeDB.fallback_font
	var align := HORIZONTAL_ALIGNMENT_CENTER if width > 0.0 else HORIZONTAL_ALIGNMENT_LEFT
	if outline > 0:
		draw_string_outline(font, pos, s, align, width, fs, outline, Color(INK, 0.9 * col.a))
	draw_string(font, pos, s, align, width, fs, col)

func text_width(s: String, fs: int) -> float:
	return ThemeDB.fallback_font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x

# A rounded progress bar with a glossy gradient fill.
func pill_bar(r: Rect2, fill: float, from: Color, to: Color) -> void:
	rrect(r, Color(0, 0, 0, 0.55), int(r.size.y * 0.5), 1, Color(1, 1, 1, 0.18))
	if fill > 0.0:
		var inner := Rect2(r.position + Vector2(2, 2), Vector2((r.size.x - 4) * clampf(fill, 0, 1), r.size.y - 4))
		rrect(inner, from.lerp(to, fill), int(inner.size.y * 0.5))
		draw_rect(Rect2(inner.position + Vector2(4, 1), Vector2(maxf(0, inner.size.x - 8), inner.size.y * 0.35)), Color(1, 1, 1, 0.22))

# The lane card behind each player's playfield: a rounded dark glass panel
# with a gradient sky inside and a thin border in the player's colour.
func lane_card(lane: Dictionary, r: Rect2, sky_top: Color, sky_bottom: Color) -> void:
	rrect(r.grow(2), Color(0, 0, 0, 0.35), 14)
	grad_rect(r.grow(-3), sky_top, sky_bottom)
	draw_style_box(UIKit.box(Color(0, 0, 0, 0), 12, 2, Color(lane["color"], 0.55)), r)

# Frosted nameplate: colour stripe, name, key chip, then live status text.
func nameplate(lane: Dictionary, at: Vector2, status: String) -> void:
	var key := key_hint(lane)
	var w := text_width(lane["name"], 14) + text_width(key, 12) + text_width(status, 13) + 54
	var r := Rect2(at, Vector2(w, 24))
	rrect(r, Color(0.05, 0.04, 0.12, 0.72), 12, 1, Color(1, 1, 1, 0.12))
	rrect(Rect2(at + Vector2(6, 6), Vector2(4, 12)), lane["color"], 2)
	text(at + Vector2(16, 17), lane["name"], 14, lane["color"].lightened(0.25), -1, 3)
	var kx := at.x + 22 + text_width(lane["name"], 14)
	rrect(Rect2(kx, at.y + 4, text_width(key, 12) + 10, 16), Color(1, 1, 1, 0.14), 6)
	text(Vector2(kx + 5, at.y + 16), key, 12, Color(1, 1, 1, 0.9), -1, 0)
	text(Vector2(kx + text_width(key, 12) + 18, at.y + 17), status, 13, Color(1, 1, 1, 0.85), -1, 3)

# A spirit token: ground shadow, coloured glow, ring, sprite.
func draw_spirit(lane: Dictionary, c: Vector2, r: float, tint := Color.WHITE, squash := Vector2.ONE, glow_amt: float = 1.0) -> void:
	if glow_amt > 0.0:
		glow(c, r * 1.3, Color(lane["color"], 0.9 * tint.a * glow_amt), 5)
	draw_circle(c, r + 3.0, Color(lane["color"].lightened(0.2), tint.a))
	draw_circle(c, r, Color(0.08, 0.07, 0.16, tint.a))
	draw_arc(c, r - 1.5, PI * 1.1, PI * 1.9, 16, Color(1, 1, 1, 0.25 * tint.a), 2.0)   # glossy rim
	if lane["tex"]:
		var side := Vector2(r * 1.6, r * 1.6) * squash
		draw_texture_rect(lane["tex"], Rect2(c - side * 0.5, side), false, tint)

func _draw_overlay() -> void:
	var font := ThemeDB.fallback_font
	# soft vignette over every game
	var o := _overlay
	var edge := 26.0
	var dark := Color(0, 0, 0, 0.35)
	var clear := Color(0, 0, 0, 0.0)
	o.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), Vector2(size.x, edge), Vector2(0, edge)]),
		PackedColorArray([dark, dark, clear, clear]))
	o.draw_polygon(PackedVector2Array([Vector2(0, size.y - edge), Vector2(size.x, size.y - edge), size, Vector2(0, size.y)]),
		PackedColorArray([clear, clear, dark, dark]))
	if _intro > 0.0:
		_draw_intro(font)
	elif _countdown > 0.0:
		var n := int(ceil(_countdown))
		var frac: float = ceil(_countdown) - _countdown          # 0 → 1 within each second
		var fs := int(64 + 40 * (1.0 - frac))
		var label := "%d" % n if n > 0 else "GO!"
		var c := size * 0.5
		for k in range(6, 0, -1):
			o.draw_circle(c, 40.0 + k * 14.0 * (1.0 - frac * 0.5), Color(UIKit.GOLD, 0.05))
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var p := Vector2(c.x - w * 0.5, c.y + fs * 0.35)
		o.draw_string_outline(font, p, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 10, Color(INK, 0.95))
		o.draw_string(font, p, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.95, 0.7).lerp(UIKit.GOLD, frac))
	elif ended and result_text() != "":
		var appear := clampf(_end_t / 0.35, 0.0, 1.0)
		banner(font, result_text(), -10.0 * (1.0 - appear), 32, appear)
		if beat_record():
			banner(font, "🎉 NEW RECORD!  +%d pts" % Balance.RECORD_BONUS, 48.0, 24, appear)

var _start_btn: Button

func _press_start() -> void:
	if _start_btn == null:
		return
	Sfx.play("click")
	_start_btn.queue_free()
	_start_btn = null
	_intro = 0.0   # on to the countdown
	_overlay.queue_redraw()

func _intro_lines() -> Array:
	var lines: Array = []
	for lane in lanes:
		if lane["human"]:
			lines.append("%s — %s" % [lane["name"], keys_text(lane)])
	return lines

func _intro_rect() -> Rect2:
	var appear := clampf((INTRO_TIME - _intro) / 0.3, 0.0, 1.0)
	var w := minf(size.x - 40.0, 920.0)   # wide enough for the longest rule line
	var h := 96.0 + _intro_lines().size() * 24.0 + (80.0 if _start_btn else 0.0)
	return Rect2((size.x - w) * 0.5, (size.y - h) * 0.5 + (1.0 - appear) * 20.0, w, h)

# The how-to-play card: the rule line plus every human's keys (and, with
# people playing, a Start button so they can read it first).
func _draw_intro(font: Font) -> void:
	var o := _overlay
	var appear := clampf((INTRO_TIME - _intro) / 0.3, 0.0, 1.0)
	var lines := _intro_lines()
	var r := _intro_rect()
	var w := r.size.x
	o.draw_style_box(UIKit.box(Color(0.06, 0.04, 0.14, 0.92 * appear), 18, 2, Color(UIKit.GOLD, 0.8 * appear)), r)
	o.draw_string(font, r.position + Vector2(0, 36), "HOW TO PLAY", HORIZONTAL_ALIGNMENT_CENTER, w, 22, Color(UIKit.GOLD, appear))
	o.draw_string(font, r.position + Vector2(0, 66), how_to, HORIZONTAL_ALIGNMENT_CENTER, w, 16, Color(1, 1, 1, appear))
	for k in lines.size():
		o.draw_string(font, r.position + Vector2(0, 94 + k * 24), lines[k], HORIZONTAL_ALIGNMENT_CENTER, w, 15,
			Color(0.75, 0.9, 1.0, appear))

# The keys a human uses in this game (override for direction games).
func keys_text(lane: Dictionary) -> String:
	return "press %s (or click your area)" % Controls.key_name(lane["slot"], "action")

func banner(font: Font, s: String, dy: float = 0.0, fs: int = 34, alpha: float = 1.0) -> void:
	var o := _overlay
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var r := Rect2(Vector2((size.x - w) * 0.5 - 26, size.y * 0.5 + dy - fs * 0.95), Vector2(w + 52, fs * 1.45))
	o.draw_style_box(UIKit.box(Color(0.06, 0.04, 0.14, 0.88 * alpha), 18, 2, Color(UIKit.GOLD, 0.7 * alpha)), r)
	var p := Vector2((size.x - w) * 0.5, size.y * 0.5 + dy)
	o.draw_string_outline(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(INK, alpha))
	o.draw_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(UIKit.GOLD, alpha))
