extends CompGame
## The quick stat contests (Haunted Dash, Coffin Lift, Spooky Stare-Down,
## Midnight Marathon, Moonlight Pageant), played out in three paced steps:
##   1) ROLL — every player rolls their die (humans press their key or click
##      their column; CPUs roll on their own)
##   2) PERFORM — the spirits really do the event as their score counts up:
##        spd / hp_stat → a RACE: everyone runs down a shared track
##        atk           → a LIFT: each spirit pumps a barbell, one rep per point
##        beauty        → a PAGEANT: three judges (each loves one stat) score
##                        the spirits one at a time from their stand
##        def           → each spirit climbs its column's glowing track
##   3) RESULTS — placings are revealed from last to first
## `stat` / `label` / `event_name` are set before setup().

const PERFORM_TIME := 3.6
const REVEAL_GAP := 0.75
const RACE_TIME := 5.0            # races and lifts run a little longer to be watched
const PAGEANT_WALK := 0.7         # pageant: walk to the spotlight…
const PAGEANT_VOTE := 0.6         # …each judge's card…
const PAGEANT_HOLD := 0.6         # …then a beat before the next spirit
# Pageant judges (portraits are placeholder trainer art; names are ours).
const JUDGES := [
	{"name": "Count Cobweb", "art": ["karen", "acetrainer"]},
	{"name": "Madame Murk", "art": ["sabrina", "acetrainer-gen1"]},
	{"name": "Old Hollow", "art": ["blaine", "acetrainer"]},
]
const JUDGE_STATS := {"atk": "ATK", "def": "DEF", "spd": "SPD", "hp_stat": "HP"}

var stat := "spd"
var label := "Speed"
var event_name := "Contest"
var _phase := "roll"       # roll / perform / results
var _phase_t := 0.0
var _revealed := 0
var _max_score := 1
var _judges: Array = []           # pageant: {name, tex, likes}

func _init_game() -> void:
	layout = Layout.COLUMNS
	use_countdown = false
	how_to = "Score = %s × 2 + stars + a die roll. Roll your die, then watch your spirit perform!" % label
	custom_minimum_size = Vector2(640, 440)
	if stat == "beauty":
		var likes: Array = JUDGE_STATS.keys()
		likes.shuffle()
		for k in JUDGES.size():
			_judges.append({"name": JUDGES[k]["name"], "tex": GameData.trainer_texture(JUDGES[k]["art"]), "likes": likes[k]})
		how_to = "Three judges each love one stat (%s). Score = their votes + stars + a die roll!" % \
			", ".join(_judges.map(func(j): return JUDGE_STATS[j["likes"]]))
	for lane in lanes:
		var s: Dictionary = lane["spirit"]
		var die := DiceView.new(64)
		add_child(die)
		var votes: Array = _judges.map(func(j): return int(s.get(j["likes"], 0)))
		var base := int(s.get(stat, 0)) * 2 + int(s.get("stars", 0))
		if stat == "beauty":
			base = votes.reduce(func(a, v): return a + v, 0) + int(s.get("stars", 0))
		lane.merge({"base": base, "votes": votes, "roll": 0, "rolled": false,
			"rolling": false, "die": die, "show": 0.0, "place": 0,
			"cpu_wait": randf_range(0.9, 2.2)})

func _is_race() -> bool:
	return stat == "spd" or stat == "hp_stat"

func _perform_time() -> float:
	if stat == "beauty":
		return lanes.size() * (PAGEANT_WALK + JUDGES.size() * PAGEANT_VOTE + PAGEANT_HOLD)
	return RACE_TIME if _is_race() or stat == "atk" else PERFORM_TIME

# Pageant timeline: whose turn it is (-1 = done) and how many votes are shown.
func _pageant_at(time: float) -> Vector2i:
	var per := PAGEANT_WALK + JUDGES.size() * PAGEANT_VOTE + PAGEANT_HOLD
	var who := int(time / per)
	if who >= lanes.size():
		return Vector2i(-1, JUDGES.size())
	var into := time - who * per
	return Vector2i(who, clampi(int((into - PAGEANT_WALK) / PAGEANT_VOTE) + 1, 0, JUDGES.size()) if into > PAGEANT_WALK else 0)

func keys_text(lane: Dictionary) -> String:
	return "press %s to roll your die (or click your column)" % Controls.key_name(lane["slot"], "action")

func _process(delta: float) -> void:
	for i in lanes.size():   # keep each die centred in its column
		var r := lane_rect(i)
		lanes[i]["die"].position = Vector2(r.get_center().x - 32, r.position.y + r.size.y * 0.42)
	super._process(delta)

func _score(lane: Dictionary) -> int:
	return int(lane["base"]) + int(lane["roll"])

func _on_action(lane: Dictionary, action: String) -> void:
	if action == "action" and _phase == "roll":
		_roll(lane)

func _roll(lane: Dictionary) -> void:
	if lane["rolled"] or lane["rolling"]:
		return
	lane["rolling"] = true
	lane["roll"] = randi_range(1, 6)
	await lane["die"].roll(lane["roll"], 0.9)
	lane["rolling"] = false
	lane["rolled"] = true

func _tick(delta: float) -> void:
	_phase_t += delta
	match _phase:
		"roll":
			for lane in lanes:
				if not lane["human"] and not lane["rolled"] and not lane["rolling"]:
					lane["cpu_wait"] -= delta
					if lane["cpu_wait"] <= 0.0:
						_roll(lane)
			if lanes.all(func(l): return l["rolled"]) and _phase_t > 0.5:
				_max_score = 1
				for lane in lanes:
					_max_score = maxi(_max_score, _score(lane))
				_phase = "perform"
				_phase_t = 0.0
				Sfx.play("go")
		"perform":
			if stat == "beauty":
				_tick_pageant()
			else:
				var k := clampf(_phase_t / _perform_time(), 0.0, 1.0)
				# races run at a steady pace (the fastest crosses the line last
				# frame); the column events ease out like a meter filling
				var eased := k if _is_race() else 1.0 - pow(1.0 - k, 3.0)
				for lane in lanes:
					var before: int = int(lane["show"])
					lane["show"] = _score(lane) * eased
					if int(lane["show"]) != before and int(lane["show"]) > 0:
						Sfx.play("tick", 0.8 + lane["show"] / float(_max_score), -10.0)
			if _phase_t > _perform_time() + 0.6:
				_phase = "results"
				_phase_t = 0.0
		"results":
			var order := ranks()
			var want := mini(order.size(), int(_phase_t / REVEAL_GAP) + 1)
			while _revealed < want:
				# reveal from LAST place up to the winner
				var place := order.size() - _revealed
				var placed: Dictionary = _lane_by_idx(order[place - 1])
				placed["place"] = place
				_revealed += 1
				Sfx.play("win" if place == 1 else "points", 1.0 if place == 1 else 0.9 + 0.1 * (order.size() - place))
			if _revealed >= order.size() and _phase_t > order.size() * REVEAL_GAP + 0.6:
				finish()

# Votes appear judge by judge; the die and stars join the total once a
# spirit's judging is over.
func _tick_pageant() -> void:
	var at := _pageant_at(_phase_t)
	for i in lanes.size():
		var lane: Dictionary = lanes[i]
		var before := int(lane["show"])
		if at.x == -1 or i < at.x:
			lane["show"] = float(_score(lane))
		elif i == at.x:
			lane["show"] = float(lane["votes"].slice(0, at.y).reduce(func(a, v): return a + v, 0))
		if int(lane["show"]) != before:
			Sfx.play("points" if i != at.x else "tick", 0.9 + 0.1 * at.y)

func ranks() -> Array:
	var sorted := lanes.duplicate()
	sorted.sort_custom(func(a, b): return _score(a) > _score(b))
	return sorted.map(func(l): return l["idx"])

func result_text() -> String:
	var best := _lane_by_idx(ranks()[0])
	return "🏆 %s wins the %s!" % [best["name"], event_name]

func _draw_game() -> void:
	if _phase != "roll":
		if _is_race():
			_draw_race()
			_draw_title()
			return
		if stat == "beauty":
			_draw_pageant()
			_draw_title()
			return
	for i in lanes.size():
		var lane: Dictionary = lanes[i]
		var r := lane_rect(i)
		var s: Dictionary = lane["spirit"]
		lane_card(lane, r, Color("150f33"), Color("2b1d55"))
		nameplate(lane, r.position + Vector2(10, 6), "")
		# the track: a glowing column the spirit climbs during PERFORM (lifters stand instead)
		var track := Rect2(r.get_center().x - 10, r.position.y + 54, 20, r.size.y - 120)
		var climbs := stat != "atk"
		if climbs:
			rrect(track, Color(0, 0, 0, 0.45), 10, 1, Color(1, 1, 1, 0.12))
			for k in 5:
				var ty := track.end.y - track.size.y * k / 4.0
				draw_line(Vector2(track.position.x - 6, ty), Vector2(track.end.x + 6, ty), Color(1, 1, 1, 0.1), 1.0)
		var frac: float = float(lane["show"]) / float(maxi(1, _max_score + 2))
		if frac > 0.0 and climbs:
			var h := (track.size.y - 4) * frac
			rrect(Rect2(track.position.x + 2, track.end.y - 2 - h, track.size.x - 4, h), Color(lane["color"], 0.85), 8)
		var climber := Vector2(track.get_center().x, track.end.y - (track.size.y - 4) * frac - 18)
		if _phase != "roll" and stat == "atk":
			_draw_lifter(lane, i, r)
		elif _phase != "roll":
			var bob := sin(t * 10.0 + i) * 2.0 if _phase == "perform" else 0.0
			draw_spirit(lane, climber + Vector2(0, bob), 20)
			text(Vector2(r.position.x, climber.y - 30), "%d" % int(lane["show"]), 22, UIKit.GOLD, r.size.x, 5)
		else:
			draw_spirit(lane, Vector2(r.get_center().x, r.position.y + 90), 26)
			var prompt := "%s %d ×2 + ★%d" % [label.to_upper(), int(s.get(stat, 0)), int(s.get("stars", 0))]
			if stat == "beauty":
				prompt = "judges' votes %d + ★%d" % [int(lane["base"]) - int(s.get("stars", 0)), int(s.get("stars", 0))]
			text(Vector2(r.position.x, r.position.y + 140), prompt, 14, Color(1, 1, 1, 0.9), r.size.x, 3)
			var hint: String = "🎲 %d!" % lane["roll"] if lane["rolled"] else \
				("press %s / click" % Controls.key_name(lane["slot"], "action") if lane["human"] else "CPU rolling…")
			text(Vector2(r.position.x, r.position.y + r.size.y * 0.42 + 92), hint, 15,
				UIKit.GOLD if lane["rolled"] else Color(0.75, 0.9, 1.0, 0.6 + 0.4 * sin(t * 6.0)), r.size.x, 3)
		# hide the die once the performance starts
		lane["die"].visible = _phase == "roll"
		if lane["place"] > 0:
			var medal: String = ["🥇", "🥈", "🥉"][lane["place"] - 1] if lane["place"] <= 3 else ORDINAL[lane["place"] - 1]
			rrect(Rect2(r.get_center().x - 50, r.end.y - 58, 100, 44), Color(0.06, 0.04, 0.14, 0.9), 14, 2,
				Color(UIKit.GOLD if lane["place"] == 1 else Color(1, 1, 1, 0.3)))
			text(Vector2(r.position.x, r.end.y - 28), "%s  %d" % [medal, _score(lane)], 20,
				UIKit.GOLD if lane["place"] == 1 else Color.WHITE, r.size.x, 4)
	_draw_title()

func _draw_title() -> void:
	var title: String = {"roll": "%s — roll your dice!" % event_name, "perform": "%s!" % event_name,
		"results": "Results"}[_phase]
	rrect(Rect2(size.x * 0.5 - 160, 2, 320, 26), Color(0.05, 0.04, 0.12, 0.8), 13)
	text(Vector2(size.x * 0.5 - 160, 21), title, 15, UIKit.GOLD, 320, 0)

func _medal(place: int) -> String:
	return ["🥇", "🥈", "🥉"][place - 1] if place <= 3 else ORDINAL[place - 1]

# ── RACE: one shared track, a lane per runner, left → right ──────────────────
func _draw_race() -> void:
	var area := Rect2(16, 36, size.x - 32, size.y - 48)
	grad_rect(area, Color("1d1440"), Color("0d0a20"))
	# moon + distant hills for the haunted night
	glow(Vector2(area.end.x - 70, area.position.y + 40), 26, Color(1, 0.95, 0.7, 0.5), 6)
	draw_circle(Vector2(area.end.x - 70, area.position.y + 40), 20, Color("fff3c4"))
	var n := lanes.size()
	var top := area.position.y + 74
	var lane_h := (area.end.y - top - 10) / float(maxi(1, n))
	var start_x := area.position.x + 120
	var finish_x := area.end.x - 46
	for i in n:
		var lane: Dictionary = lanes[i]
		var row := Rect2(area.position.x + 6, top + i * lane_h, area.size.x - 12, lane_h - 4)
		rrect(row, Color("3a2a1e") if i % 2 == 0 else Color("33251a"), 8, 1, Color(lane["color"], 0.5))
		for k in 12:   # track markings scroll past while running
			var mx := start_x + fposmod(k * 60.0 - (t * 120.0 if _phase == "perform" else 0.0), finish_x - start_x)
			draw_line(Vector2(mx, row.get_center().y), Vector2(mx + 22, row.get_center().y), Color(1, 1, 1, 0.12), 2.0)
		text(Vector2(row.position.x + 10, row.get_center().y + 6), lane["name"], 15, lane["color"].lightened(0.3), -1, 3)
	# start + checkered finish lines
	draw_line(Vector2(start_x, top), Vector2(start_x, top + n * lane_h - 4), Color(1, 1, 1, 0.5), 3.0)
	for k in int((n * lane_h) / 10.0):
		for c in 2:
			draw_rect(Rect2(finish_x + c * 8, top + k * 10, 8, 10), Color.WHITE if (k + c) % 2 == 0 else Color.BLACK)
	text(Vector2(finish_x - 40, top - 8), "FINISH", 13, UIKit.GOLD, 96, 3)
	for i in n:
		var lane: Dictionary = lanes[i]
		var frac: float = clampf(float(lane["show"]) / float(maxi(1, _max_score)), 0.0, 1.0)
		var cy := top + i * lane_h + (lane_h - 4) * 0.5
		var x := start_x + 22 + (finish_x - start_x - 40) * frac
		var running: bool = _phase == "perform" and frac < 1.0
		var hop := absf(sin(t * 14.0 + i * 1.7)) * 7.0 if running else 0.0
		if running:   # dust puffs kicked up behind
			for k in 3:
				var dx := 14.0 + k * 9.0 + fposmod(t * 40.0 + k * 7.0, 9.0)
				draw_circle(Vector2(x - dx, cy + 12), 4.0 - k, Color(0.8, 0.7, 0.55, 0.35 - k * 0.1))
		var r := minf(20.0, lane_h * 0.36)
		draw_spirit(lane, Vector2(x, cy - hop), r, Color.WHITE, Vector2(1.0 + hop * 0.01, 1.0 - hop * 0.01))
		text(Vector2(x - 40, cy - r - 6 - hop), "%d" % int(lane["show"]), 15, UIKit.GOLD, 80, 3)
		lane["die"].visible = false
		if lane["place"] > 0:
			text(Vector2(finish_x - 110, cy + 7), "%s %d" % [_medal(lane["place"]), _score(lane)], 18,
				UIKit.GOLD if lane["place"] == 1 else Color.WHITE, -1, 4)

# ── LIFT: the spirit pumps a barbell — one rep for every point it scores ─────
func _draw_lifter(lane: Dictionary, i: int, r: Rect2) -> void:
	var show: float = lane["show"]
	var reps := int(show)
	var pumping: bool = _phase == "perform" and show < float(_score(lane)) - 0.01
	# 0 = bar at the chest, 1 = locked out overhead
	var lift := 0.5 - 0.5 * cos((show - floor(show)) * TAU) if pumping else (1.0 if _phase == "results" else 0.0)
	var body := Vector2(r.get_center().x, r.end.y - 110)
	var rad := minf(34.0, r.size.x * 0.22)
	var bar_y := body.y - rad * 0.4 - lift * rad * 1.5
	var half := minf(r.size.x * 0.42, 70.0)
	var plate := 10.0 + int(lane["spirit"].get("atk", 1)) * 2.5   # heavier plates for stronger spirits
	# arms (under the sprite), bar, plates
	for side in [-1, 1]:
		draw_line(body + Vector2(side * rad * 0.7, 0), Vector2(body.x + side * half * 0.55, bar_y), Color(lane["color"].lightened(0.3), 0.9), 5.0)
	draw_spirit(lane, body, rad, Color.WHITE, Vector2(1.0 + lift * 0.06, 1.0 - lift * 0.06))
	draw_line(Vector2(body.x - half, bar_y), Vector2(body.x + half, bar_y), Color("c9ced6"), 5.0)
	for side in [-1, 1]:
		for k in 2:
			var px: float = body.x + side * (half - 6 - k * 9)
			rrect(Rect2(px - 4, bar_y - plate * (1.0 - k * 0.25), 8, plate * 2 * (1.0 - k * 0.25)), Color("2a2a33") if k == 0 else Color("4a4a58"), 3, 1, Color(1, 1, 1, 0.2))
	if pumping and lift > 0.9:
		glow(Vector2(body.x, bar_y), 18, Color(UIKit.GOLD, 0.35), 4)
	text(Vector2(r.position.x, r.position.y + 66), "Reps: %d" % reps, 22, UIKit.GOLD, r.size.x, 5)
	if pumping:
		text(Vector2(r.position.x, r.position.y + 92), ["HUP!", "HNNG!", "LIFT!"][reps % 3], 15, Color(1, 1, 1, 0.75), r.size.x, 3)

# ── PAGEANT: judges' stand on top, spirits take the spotlight one by one ─────
func _draw_pageant() -> void:
	var area := Rect2(16, 36, size.x - 32, size.y - 48)
	grad_rect(area, Color("2a1240"), Color("120820"))
	var at := _pageant_at(_phase_t) if _phase == "perform" else Vector2i(-1, JUDGES.size())
	# the judges' stand
	var stand := Rect2(area.position.x + area.size.x * 0.12, area.position.y + 6, area.size.x * 0.76, 128)
	rrect(Rect2(stand.position + Vector2(0, 74), Vector2(stand.size.x, 54)), Color("5a2d1a"), 10, 2, Color("c9893a"))
	text(Vector2(stand.position.x, stand.position.y + 120), "✨ JUDGES ✨", 14, Color("ffd9a0"), stand.size.x, 3)
	var jw := stand.size.x / float(JUDGES.size())
	for k in _judges.size():
		var j: Dictionary = _judges[k]
		var c := Vector2(stand.position.x + jw * (k + 0.5), stand.position.y + 46)
		draw_circle(c, 30, Color(0.1, 0.06, 0.18))
		if j["tex"]:
			var ts: Vector2 = j["tex"].get_size()
			var sc := 56.0 / maxf(ts.x, ts.y)
			draw_texture_rect(j["tex"], Rect2(c - ts * sc * 0.5, ts * sc), false)
		text(Vector2(c.x - jw * 0.5, stand.position.y + 98), "%s ♥ %s" % [j["name"], JUDGE_STATS[j["likes"]]], 12, Color.WHITE, jw, 3)
		# the score card this judge holds up for the spirit on stage
		if at.x >= 0 and k < at.y:
			var vote: int = lanes[at.x]["votes"][k]
			var card := Rect2(c.x + 18, c.y - 44, 34, 30)
			rrect(card, Color.WHITE, 5, 2, UIKit.GOLD)
			text(Vector2(card.position.x, card.end.y - 7), str(vote), 20, Color("2a1240"), card.size.x, 0)
	# the stage + spotlight
	var stage_y := area.end.y - 64
	rrect(Rect2(area.position.x + 30, stage_y + 20, area.size.x - 60, 26), Color("3b1f4f"), 8, 1, Color(1, 1, 1, 0.2))
	var centre := Vector2(area.get_center().x, stage_y - 40)
	if at.x >= 0:
		draw_colored_polygon(PackedVector2Array([Vector2(centre.x - 18, stand.end.y), Vector2(centre.x + 18, stand.end.y),
			Vector2(centre.x + 70, stage_y + 30), Vector2(centre.x - 70, stage_y + 30)]), Color(1, 0.95, 0.7, 0.10))
	var n := lanes.size()
	var wait_w := (area.size.x - 80) / float(maxi(1, n))
	for i in n:
		var lane: Dictionary = lanes[i]
		lane["die"].visible = false
		var home := Vector2(area.position.x + 40 + wait_w * (i + 0.5), stage_y + 8)
		var pos := home
		var rad := 18.0
		if i == at.x:
			var per := PAGEANT_WALK + JUDGES.size() * PAGEANT_VOTE + PAGEANT_HOLD
			var walk := clampf((_phase_t - i * per) / PAGEANT_WALK, 0.0, 1.0)
			pos = home.lerp(centre, 1.0 - pow(1.0 - walk, 2.0))
			rad = lerpf(18.0, 34.0, walk)
			pos.y += sin(t * 5.0) * 3.0   # a little twirl on stage
		var done: bool = at.x == -1 or i < at.x
		draw_spirit(lane, pos, rad, Color(1, 1, 1, 1.0 if (done or i == at.x) else 0.75))
		text(Vector2(home.x - wait_w * 0.5, stage_y + 44), lane["name"], 12, lane["color"].lightened(0.3), wait_w, 3)
		if done or i == at.x:
			text(Vector2(pos.x - 40, pos.y - rad - 8), "%d" % int(lane["show"]), 16, UIKit.GOLD, 80, 3)
		if lane["place"] > 0:
			text(Vector2(home.x - 50, home.y - 26), "%s %d" % [_medal(lane["place"]), _score(lane)], 16,
				UIKit.GOLD if lane["place"] == 1 else Color.WHITE, 100, 4)

# ── 3D (3D maps) ──────────────────────────────────────────────────────────────
# The same three steps (roll → perform → results), staged in 3D:
#   race (SPD / HP): lanes down a track · lift (ATK): a barbell, one rep per
#   point · climb (DEF): up a glowing pillar · pageant: a stage, three judges.
func _build_3d(v) -> void:
	var n := lanes.size()
	var gap := 3.4
	v.sky(Color("2a2452"), 0.75)
	match _kind3():
		"race":
			v.aim(Vector3(0, 12, 19), Vector3(0, 0, -9))
			for i in n:
				v.box(Vector3(3.2, 0.1, 40), Color("3a3266") if i % 2 else Color("443a74"), Vector3(v.lane_x(i, n, gap), -0.05, -16))
			v.box(Vector3(n * gap, 0.12, 0.5), Color.WHITE, Vector3(0, 0, -32), true)
		"lift":
			gap = 4.4
			v.aim(Vector3(0, 5, 12 + n * 2.0), Vector3(0, 2, 0))
			v.box(Vector3(n * gap + 2, 0.3, 5), Color("3a3266"), Vector3(0, -0.15, 0))
		"climb":
			gap = 4.0
			v.aim(Vector3(0, 6, 14 + n * 2.0), Vector3(0, 4, 0))
			for i in n:
				v.box(Vector3(0.6, 10, 0.6), Color("4a3a9a"), Vector3(v.lane_x(i, n, gap), 5, -0.8), true)
		"pageant":
			gap = 3.6
			v.aim(Vector3(0, 5, 13 + n * 1.5), Vector3(0, 1.8, 0))
			v.box(Vector3(n * gap + 4, 0.4, 6), Color("5a2a5a"), Vector3(0, -0.2, 0))
			for k in _judges.size():
				var jn: Node3D = v.spirit(_judges[k]["tex"], Color(0, 0, 0, 0), Vector3((k - 1) * 3.0, 0, -3.6), 0.03)
				v.tag(jn, "%s (loves %s)" % [_judges[k]["name"], JUDGE_STATS[_judges[k]["likes"]]], Color("e8d0ff"), 2.6, 12)
			_spot3 = v.lamp(Color("fff0c0"), Vector3(0, 5, 2.5), 0.0, 8)
	for i in n:
		var lane: Dictionary = lanes[i]
		var x: float = v.lane_x(i, n, gap)
		lane["x3"] = x
		lane["n3"] = v.spirit(lane["tex"], lane["color"], Vector3(x, 0, 1.2), 0.03)
		if _kind3() == "lift":
			var bar := Node3D.new()
			v.world.add_child(bar)
			v.box(Vector3(2.2, 0.1, 0.1), Color("c8c8d0"), Vector3.ZERO, false, bar)
			for sx in [-1.0, 1.0]:
				v.ball(0.35, Color("33333a"), Vector3(sx * 1.1, 0, 0), false, bar)
			lane["bar3"] = bar
		lane["placed3"] = false
		var l := lane
		v.tag(lane["n3"], func(): return "%s  %s" % [l["name"], ("🎲 %d" % l["roll"]) if l["rolled"] and _phase == "roll" else str(int(l["show"])) if _phase != "roll" else key_hint(l)],
			lane["color"].lightened(0.25), 2.3, 14)

var _spot3: OmniLight3D
var _votes_seen3 := Vector2i(-1, 0)

func _kind3() -> String:
	if stat == "beauty":
		return "pageant"
	if _is_race():
		return "race"
	return "lift" if stat == "atk" else "climb"

func _update_3d(v, _delta: float) -> void:
	var kind := _kind3()
	for lane in lanes:
		var n: Node3D = lane["n3"]
		var x: float = lane["x3"]
		var k: float = lane["show"] / float(maxi(1, _max_score))
		match kind:
			"race":
				n.position = Vector3(x, absf(sin(t * 12.0 + lane["idx"])) * 0.3 if _phase == "perform" else 0.0, 1.2 - k * 33.0)
			"lift":
				var lift: float = absf(sin(lane["show"] * PI)) if _phase == "perform" else 0.0
				lane["bar3"].position = Vector3(x, 1.7 + lift * 1.4, 1.2)
				n.scale = Vector3(1.0 + (1.0 - lift) * 0.1, 1.0 - (1.0 - lift) * 0.1, 1.0)
			"climb":
				n.position = Vector3(x, k * 8.5, 1.2 - 1.6)
			"pageant":
				pass
		if lane["place"] > 0 and not lane["placed3"]:
			lane["placed3"] = true
			var medal: String = ["🥇 1st", "🥈 2nd", "🥉 3rd"][lane["place"] - 1] if lane["place"] <= 3 else ORDINAL[lane["place"] - 1]
			v.pop(n, medal, Color("ffd24d") if lane["place"] == 1 else Color.WHITE, 3.2, 3.0, 22)
	if kind == "pageant":
		var at := _pageant_at(_phase_t) if _phase == "perform" else Vector2i(-1, 0)
		for i in lanes.size():
			var star: bool = at.x == i
			var n2: Node3D = lanes[i]["n3"]
			n2.position = n2.position.lerp(Vector3(0, 0, 2.2) if star else Vector3(lanes[i]["x3"], 0, 0.6 if at.x >= 0 else 1.2), 0.12)
		_spot3.light_energy = 3.0 if at.x >= 0 else 0.0
		if at.x >= 0:
			_spot3.position = lanes[at.x]["n3"].position + Vector3(0, 4, 1)
			if at != _votes_seen3 and at.y > 0:
				_votes_seen3 = at
				var vote: int = lanes[at.x]["votes"][at.y - 1]
				v.pop(Vector3((at.y - 2) * 3.0, 0, -3.6), "%d" % vote, Color("ffd24d"), 3.2, 1.2, 28)
