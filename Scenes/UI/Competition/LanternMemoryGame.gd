extends CompGame
## 🏮 Lantern Memory — a "repeat the pattern" game. Three lanterns flash in a
## sequence; everyone then repeats it with LEFT / MIDDLE / RIGHT. Each round
## adds a flash. A wrong press costs a life; the longest memory wins.
## HP = an extra life, SPD = sharper CPU memory.

const MAX_ROUNDS := 8
const FLASH := 0.55          # seconds per flash while showing
const LANE_KEYS := ["left", "middle", "right"]

var _seq: Array = []
var _state := "show"         # show / input / pause
var _state_t := 0.0

func _init_game() -> void:
	record_key = "lantern_memory"
	layout = Layout.COLUMNS
	how_to = "Watch the lanterns flash, then repeat the pattern with LEFT / MIDDLE / RIGHT!"
	custom_minimum_size = Vector2(640, 440)
	for k in 2:
		_seq.append(randi() % 3)
	for lane in lanes:
		var s: Dictionary = lane["spirit"]
		lane.merge({"lives": 1 + (1 if int(s.get("hp_stat", s.get("hp", 2))) >= 4 else 0), "pos": 0, "done": false,
			"best": 0, "out": false, "flash": -1, "flash_t": 0.0, "cpu_t": 0.0,
			"sharp": 0.9 + int(s.get("spd", 2)) * 0.012})
	_start_show()

func _start_show() -> void:
	_seq.append(randi() % 3)
	_state = "show"
	_state_t = 0.0

func _start_input() -> void:
	_state = "input"
	_state_t = 0.0
	for lane in lanes:
		lane["pos"] = 0
		lane["done"] = lane["out"]
		lane["cpu_t"] = randf_range(0.4, 0.8)

func _tick(delta: float) -> void:
	_state_t += delta
	for lane in lanes:
		lane["flash_t"] = maxf(0.0, lane["flash_t"] - delta)
	match _state:
		"show":
			if _state_t >= _seq.size() * FLASH + 0.4:
				_start_input()
		"input":
			for lane in lanes:
				if lane["human"] or lane["done"]:
					continue
				lane["cpu_t"] -= delta
				if lane["cpu_t"] <= 0.0:
					lane["cpu_t"] = randf_range(0.3, 0.6)
					var right: int = _seq[lane["pos"]]
					_press(lane, right if randf() < pow(lane["sharp"], _seq.size()) * 1.25 else (right + 1 + randi() % 2) % 3)
			if lanes.all(func(l): return l["done"]) or _state_t > 4.0 + _seq.size() * 1.2:
				for lane in lanes:   # too slow counts as a miss
					if not lane["done"]:
						_miss(lane)
				var alive := lanes.filter(func(l): return not l["out"])
				if alive.size() <= (0 if lanes.size() == 1 else 1) or _seq.size() >= MAX_ROUNDS + 2:
					result_value = float(_lane_by_idx(ranks()[0])["best"])
					finish()
				else:
					_state = "pause"
					_state_t = 0.0
		"pause":
			if _state_t >= 0.8:
				_start_show()

func _press(lane: Dictionary, k: int) -> void:
	if _state != "input" or lane["done"]:
		return
	lane["flash"] = k
	lane["flash_t"] = 0.25
	if _seq[lane["pos"]] != k:
		_miss(lane)
		return
	lane["pos"] += 1
	if lane["human"]:
		Sfx.play("pop", 0.8 + k * 0.2, -4.0)
	if lane["pos"] >= _seq.size():
		lane["done"] = true
		lane["best"] = _seq.size()

func _miss(lane: Dictionary) -> void:
	lane["done"] = true
	lane["lives"] -= 1
	Sfx.play("error")
	if lane["lives"] <= 0:
		lane["out"] = true

func _on_action(lane: Dictionary, action: String) -> void:
	var k := LANE_KEYS.find(action)
	if k >= 0:
		_press(lane, k)

func _gui_input(ev: InputEvent) -> void:
	var pressed: bool = (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT) \
		or (ev is InputEventScreenTouch and ev.pressed)
	if not pressed or not running:
		return
	var i := lane_at(ev.position)
	if i >= 0 and lanes[i]["human"]:
		var r := lane_rect(i)
		_press(lanes[i], clampi(int((ev.position.x - r.position.x) / r.size.x * 3.0), 0, 2))

func ranks() -> Array:
	var sorted := lanes.duplicate()
	sorted.sort_custom(func(a, b):
		if a["best"] != b["best"]:
			return a["best"] > b["best"]
		return a["lives"] > b["lives"])
	return sorted.map(func(l): return l["idx"])

func result_text() -> String:
	var best := _lane_by_idx(ranks()[0])
	return "🏮 %s remembered %d lanterns!" % [best["name"], best["best"]]

func keys_text(lane: Dictionary) -> String:
	return "%s / %s / %s for the three lanterns (or tap them)" % [Controls.key_name(lane["slot"], "left"),
		Controls.key_name(lane["slot"], "middle"), Controls.key_name(lane["slot"], "right")]

# Which lantern the shared pattern lights right now (-1 = none).
func _showing() -> int:
	if _state != "show":
		return -1
	var k := int(_state_t / FLASH)
	if k >= _seq.size() or fmod(_state_t, FLASH) > FLASH * 0.75:
		return -1
	return _seq[k]

func _draw_game() -> void:
	var lit := _showing()
	for i in lanes.size():
		var lane: Dictionary = lanes[i]
		var r := lane_rect(i)
		lane_card(lane, r, Color("140a26"), Color("2a1030"))
		var cw := (r.size.x - 16) / 3.0
		var ly := r.position.y + r.size.y * 0.42
		for k in 3:
			var c := Vector2(r.position.x + 8 + (k + 0.5) * cw, ly)
			var on: bool = lit == k or (lane["flash"] == k and lane["flash_t"] > 0.0)
			var col: Color = [Color("ff6a3a"), Color("ffd24d"), Color("4dd0ff")][k]
			if on:
				glow(c, 26, col, 6)
			draw_line(c + Vector2(0, -34), c + Vector2(0, -20), Color(0.6, 0.5, 0.4), 2.0)
			draw_circle(c, 16, col if on else col.darkened(0.7))
		var me := Vector2(r.get_center().x, r.end.y - 50)
		draw_spirit(lane, me, 20.0, Color(1, 1, 1, 0.3) if lane["out"] else Color.WHITE)
		var status: String = "out" if lane["out"] else ("✓" if lane["done"] and _state == "input" else "%d/%d" % [lane["pos"], _seq.size()]) \
			+ "  " + "♥".repeat(maxi(0, lane["lives"]))
		nameplate(lane, r.position + Vector2(8, 30), status)
	var msg: String = {"show": "Watch the lanterns…", "input": "Your turn — repeat it!", "pause": "Next round!"}.get(_state, "")
	if running:
		text(Vector2(0, size.y - 14), "%s  (pattern of %d)" % [msg, _seq.size()], 16, Color(1, 1, 1, 0.75), size.x, 3)
