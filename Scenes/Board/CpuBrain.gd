class_name CpuBrain
## Board decisions for CPU players: which road to take at a fork, whether to
## stop in a town, and where it would like to fly / warp. Each CPU has a
## personal bias (rolled at game start) so different CPUs play differently.

static func new_bias() -> Dictionary:
	return {"sp": randf_range(0.6, 1.5), "item": randf_range(0.6, 1.5),
		"badge": randf_range(0.6, 1.5), "pts": randf_range(0.6, 1.5)}

static func _has_badge(p: PlayerData, city: String) -> bool:
	return p.progress.badges.get(GameData.gym_for_city(city).get("badge", ""), false)

# A gym is worth trying with 4+ spirits whose best stars can match its tier
# (gyms grow with your badges — don't grind a full-strength gym with rookies).
static func ready_for_gym(p: PlayerData) -> bool:
	return p.team.size() >= 4 and top_stars(p) >= (GameData.challenge_tier(p.progress.badge_count()) - 1) * 2.0

# The trail needs the badges AND a seasoned squad (otherwise it's a loss loop).
static func ready_for_trail(p: PlayerData) -> bool:
	return p.progress.badge_count() >= Balance.FLY_BADGES and p.team.size() >= Balance.BATTLE_PICK_MAX \
		and top_stars(p) >= GameData.trail_tier(p.progress.badge_count()) * 2.0 + 2.0

# Total stars of the best four spirits.
static func top_stars(p: PlayerData) -> float:
	var stars: Array = p.team.map(func(m): return float(m.get("stars", 0)))
	stars.sort()
	stars.reverse()
	var total := 0.0
	for s in stars.slice(0, Balance.BATTLE_PICK_MAX):
		total += s
	return total

# Score every road out of a fork by what's ON it and where it LEADS, weighted
# by the CPU's needs and bias, then roulette-pick (so runs differ).
static func pick_route(graph: BoardGraph, p: PlayerData, bias: Dictionary, node_name: String,
		opts: Array, best_points: int) -> int:
	var need_sp: float = maxf(0.2, (6.0 - float(p.team.size())) / 3.0) \
		* (1.5 if p.inventory.total_jars() > 0 else 0.4)   # no jars → ghost tiles are risky
	var need_item: float = 1.5 if p.inventory.hand.size() < 2 else 0.6
	if p.inventory.total_jars() == 0:
		need_item += 0.8
	var need_badge: float = 2.0 if ready_for_gym(p) else 0.3
	var need_pts: float = 0.5 + 0.05 * maxf(0.0, float(best_points - p.progress.points))
	var scores: Array = []
	var total := 0.0
	for ri in opts:
		var s := 0.5   # base chance so no road is ever impossible
		for t in graph.routes[ri].get("types", []):
			match String(t):
				"WISP", "GHOST", "PHANTOM": s += need_sp * float(bias["sp"])
				"ITEM": s += need_item * float(bias["item"])
				"EVENT": s += 0.5 * need_pts * float(bias["pts"])
				"COMPETITION": s += need_pts * float(bias["pts"])
		var dest := graph.other_end(ri, node_name)
		if graph.is_city(dest):
			s += 0.5   # towns heal and restock
			if dest != "A" and not _has_badge(p, dest):
				s += 3.0 * need_badge * float(bias["badge"])
		scores.append(s)
		total += s
	var roll := randf() * total
	for i in scores.size():
		roll -= scores[i]
		if roll <= 0.0:
			return opts[i]
	return opts.back()

# Stop in a town when it's useful: an unbeaten gym it's ready for, trail
# prep, or restocking jars.
static func wants_stop(p: PlayerData, city: String) -> bool:
	var wants_gym := city != "A" and not _has_badge(p, city) and ready_for_gym(p)
	var needs_shop := p.inventory.total_jars() == 0 and p.inventory.gold >= 10
	return wants_gym or ready_for_trail(p) or needs_shop

# The town a CPU would like to jump to (fly / Warp Door), or "".
static func wanted_town(p: PlayerData, cities: Array, visited: Dictionary, here: String, visited_only: bool) -> String:
	if ready_for_gym(p):
		for c in cities:
			if c != "A" and c != here and not _has_badge(p, c) and (not visited_only or visited.has(c)):
				return c
	if ready_for_trail(p):
		for c in cities:
			if c != here and (not visited_only or visited.has(c)):
				return c   # any town → Spectral Trail
	return ""
