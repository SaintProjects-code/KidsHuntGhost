extends Control
## Weather drawn over whatever it covers: ⛈ rain + lightning flashes, ☀ warm
## light and rays, 🌫 drifting fog, 🏜 blowing sand. Used on the board
## (WeatherOverlay) and over battles (BattleView). Follows GameState.weather.
## `strength` scales the tint (battles use less so the text stays readable).

var strength := 1.0
var _t := 0.0
var _flash := 0.0
var _drops: Array = []     # rain / sand streaks: [pos, speed]
var _fog: Array = []       # fog blobs: [pos, radius, drift]
var _kind := "-"

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS   # keeps moving while windows pause the board

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _reset() -> void:
	_kind = GameState.weather
	_drops.clear()
	_fog.clear()
	var vp := get_viewport_rect().size
	match _kind:
		"storm":
			for i in 140:
				_drops.append([Vector2(randf() * vp.x, randf() * vp.y), randf_range(700, 1000)])
		"sand":
			for i in 90:
				_drops.append([Vector2(randf() * vp.x, randf() * vp.y), randf_range(500, 800)])
		"mist":
			for i in 14:
				_fog.append([Vector2(randf() * vp.x, randf() * vp.y), randf_range(120, 260), randf_range(10, 30)])

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	if _kind != GameState.weather:
		_reset()
	_t += delta
	var vp := get_viewport_rect().size
	match _kind:
		"storm":
			for d in _drops:
				d[0] += Vector2(-0.25, 1.0) * d[1] * delta
				if d[0].y > vp.y:
					d[0] = Vector2(randf() * vp.x * 1.2, -20)
			_flash = maxf(0.0, _flash - delta * 3.0)
			if randf() < delta * 0.25:   # a flash every few seconds
				_flash = 1.0
		"sand":
			for d in _drops:
				d[0] += Vector2(1.0, 0.12) * d[1] * delta
				if d[0].x > vp.x:
					d[0] = Vector2(-40, randf() * vp.y)
		"mist":
			for f in _fog:
				f[0].x += f[2] * delta
				if f[0].x - f[1] > vp.x:
					f[0].x = -f[1]
	queue_redraw()

func _draw() -> void:
	var vp := get_viewport_rect().size
	var k := strength
	match _kind:
		"storm":
			draw_rect(Rect2(Vector2.ZERO, vp), Color(0.05, 0.08, 0.2, 0.32 * k))
			for d in _drops:
				draw_line(d[0], d[0] + Vector2(-5, 20), Color(0.7, 0.8, 1.0, 0.55), 1.5)
			if _flash > 0.0:
				draw_rect(Rect2(Vector2.ZERO, vp), Color(1, 1, 1, 0.45 * _flash * k))
		"sun":
			draw_rect(Rect2(Vector2.ZERO, vp), Color(1.0, 0.75, 0.3, 0.14 * k))
			var o := Vector2(vp.x * 0.92, -40)
			for i in 6:
				var a := deg_to_rad(105 + i * 9 + sin(_t * 0.4 + i) * 2.0)
				var tip := o + Vector2(cos(a), sin(a)) * vp.length()
				var side := Vector2(cos(a + 1.57), sin(a + 1.57)) * 40.0
				draw_colored_polygon(PackedVector2Array([o, tip + side, tip - side]), Color(1, 0.95, 0.7, 0.06 * k))
		"mist":
			draw_rect(Rect2(Vector2.ZERO, vp), Color(0.75, 0.75, 0.85, 0.18 * k))
			for f in _fog:
				draw_circle(f[0], f[1], Color(0.92, 0.92, 1.0, 0.13 * k))
		"sand":
			draw_rect(Rect2(Vector2.ZERO, vp), Color(0.85, 0.65, 0.35, 0.22 * k))
			for d in _drops:
				draw_line(d[0], d[0] + Vector2(26, 3), Color(0.95, 0.82, 0.55, 0.5), 2.0)
