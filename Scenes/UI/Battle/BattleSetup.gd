class_name BattleSetup
## Builds BattleScreen setups and runs a battle start-to-finish for one
## player (shared by the encounter and tile controllers).

# Card-spending appetite per kind of fight (see BattleScreen `stakes`).
const STAKES := {"wild": 0.2, "trainer": 0.4, "gym": 0.7, "warden": 0.9, "champion": 1.0, "pvp": 0.8}

const BATTLE_CARDS := 2   # tactic cards each side brings into a battle

# Pick a battle team AND the 2 tactic cards to bring. Humans use the team-select
# window; CPUs auto-pick (counter-picking against `opp_pool`, the other side's
# FULL roster — nobody sees the 3 the other side actually brings).
# Returns {team, cards}, or {} if a human backed out.
static func pick_for(select: Control, idx: int, vs_text: String, opp_pool: Array) -> Dictionary:
	var p: PlayerData = GameState.players[idx]
	if p.is_cpu:
		return {"team": cpu_team(idx, opp_pool), "cards": cpu_cards(p)}
	if p.living_team().is_empty():
		return {}
	select.present(p, vs_text, opp_pool)
	UIManager.open(select)
	return await select.chosen

# A CPU brings its two most valuable tactic cards.
static func cpu_cards(p: PlayerData) -> Array:
	var tactics: Array = p.inventory.cards_of_kind("tactic")
	tactics.sort_custom(func(a, b): return CardsData.value_of(a) > CardsData.value_of(b))
	return tactics.slice(0, BATTLE_CARDS)

# A player's team vs an NPC (or wild) team. `cards` = the 2 they brought;
# `foe_deck` = the NPC's tactic cards.
static func vs_npc(idx: int, team: Array, cards: Array, opp: Array, title: String, foe_trainer: Array,
		kind: String, foe_deck: Array = []) -> Dictionary:
	var p: PlayerData = GameState.players[idx]
	var mod := p.next_battle_mod
	p.next_battle_mod = 0   # a blessing/curse lasts one battle
	return {
		"team": team, "opp": opp, "title": title, "color": p.color, "atk_mod": mod,
		"trainer": GameData.player_trainer(p), "foe_trainer": foe_trainer, "my_name": p.player_name,
		"hand": cards.duplicate(), "hand_source": p.inventory.hand, "hand_owner": idx, "human": not p.is_cpu,
		"opp_hand": foe_deck, "opp_owner": -1, "opp_human": false,
		"stakes": STAKES.get(kind, 0.5),
	}

static func pvp(a: int, b: int, pick_a: Dictionary, pick_b: Dictionary) -> Dictionary:
	var pa: PlayerData = GameState.players[a]
	var pb: PlayerData = GameState.players[b]
	return {
		"team": pick_a["team"], "opp": pick_b["team"], "title": "%s vs %s" % [pa.player_name, pb.player_name],
		"color": pa.color, "trainer": GameData.player_trainer(pa), "foe_trainer": GameData.player_trainer(pb),
		"pvp_names": [pa.player_name, pb.player_name],
		"hand": pick_a["cards"].duplicate(), "hand_source": pa.inventory.hand, "hand_owner": a, "human": not pa.is_cpu,
		"opp_hand": pick_b["cards"].duplicate(), "opp_source": pb.inventory.hand, "opp_owner": b, "opp_human": not pb.is_cpu,
		"stakes": STAKES["pvp"],
	}

# Open the battle, wait for it (humans press Continue, CPU-only fights play
# themselves), then hand the stars earned to the real spirits. Returns true if
# the bottom side (the player) won.
static func run(battle: Control, setup: Dictionary, idx: int) -> bool:
	battle.present(setup)
	UIManager.open(battle)
	var won: bool
	if setup.get("human", true) or setup.get("opp_human", false):
		won = await battle.finished
	else:
		await battle.autoplay()
		won = battle.won()
	await grant_stars(battle, idx, setup.get("team", []))
	return won

# Stars earned in battle go to the real spirits (a 3-star spirit pops the
# bonus-reward flow, which the battle sequence waits for).
static func grant_stars(battle: Control, idx: int, team: Array) -> void:
	var credits: Dictionary = battle.take_star_credits()
	for i in credits:
		if int(i) < team.size():
			await SpiritsProgressionSystem.award_stars(idx, team[int(i)], credits[i])

# A CPU player's squad: counter-picked from its living spirits (real dicts,
# so damage sticks).
static func cpu_team(idx: int, opp: Array = []) -> Array:
	return counter_pick(GameState.players[idx].living_team(), opp)

# Pick the best `n` of `pool` against `opp`, then order them: the LEAD is the
# pick that does best against the opponent's lead, the rest strongest-first.
# Used by CPU players AND by gyms / wardens / trainers once they see your team.
static func counter_pick(pool: Array, opp: Array, n: int = Balance.BATTLE_PICK_MAX) -> Array:
	var squad: Array = pool.duplicate()
	squad.sort_custom(func(a, b): return _power(a, opp) > _power(b, opp))
	squad = squad.slice(0, n)
	if not opp.is_empty() and squad.size() > 1:
		var their_lead: Array = [opp[0]]
		var best := 0
		for i in squad.size():
			if _power(squad[i], their_lead) > _power(squad[best], their_lead):
				best = i
		squad.push_front(squad.pop_at(best))
	return squad

static func _power(m: Dictionary, opp: Array) -> float:
	var v := float(m.get("current_hp", 0)) / 30.0 + float(m.get("atk", 1)) * 1.5 + float(m.get("def", 1)) \
		+ float(m.get("spd", 1)) * 0.5 + float(m.get("stars", 0)) * 1.5
	for o in opp:
		v += (SpiritsData.type_mult(m.get("type", ""), o.get("type", "")) - 1.0) * 3.0   # ±1.5 per foe
		v -= (SpiritsData.type_mult(o.get("type", ""), m.get("type", "")) - 1.0) * 2.0
	return v
