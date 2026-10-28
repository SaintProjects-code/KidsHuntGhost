class_name BattleSetup
## Builds BattleScreen setups and runs a battle start-to-finish for one
## player (shared by the encounter and tile controllers).

# Card-spending appetite per kind of fight (see BattleScreen `stakes`).
const STAKES := {"wild": 0.2, "trainer": 0.4, "gym": 0.7, "warden": 0.9, "champion": 1.0, "pvp": 0.8}

# A player's team vs an NPC (or wild) team. `foe_deck` are the NPC's tactic cards.
static func vs_npc(idx: int, team: Array, opp: Array, title: String, foe_trainer: Array,
		kind: String, foe_deck: Array = []) -> Dictionary:
	var p: PlayerData = GameState.players[idx]
	var mod := p.next_battle_mod
	p.next_battle_mod = 0   # a blessing/curse lasts one battle
	return {
		"team": team, "opp": opp, "title": title, "color": p.color, "atk_mod": mod,
		"trainer": GameData.player_trainer(p), "foe_trainer": foe_trainer, "my_name": p.player_name,
		"hand": p.inventory.hand, "hand_owner": idx, "human": not p.is_cpu,
		"opp_hand": foe_deck, "opp_owner": -1, "opp_human": false,
		"stakes": STAKES.get(kind, 0.5),
	}

static func pvp(a: int, b: int, team_a: Array, team_b: Array) -> Dictionary:
	var pa: PlayerData = GameState.players[a]
	var pb: PlayerData = GameState.players[b]
	return {
		"team": team_a, "opp": team_b, "title": "%s vs %s" % [pa.player_name, pb.player_name],
		"color": pa.color, "trainer": GameData.player_trainer(pa), "foe_trainer": GameData.player_trainer(pb),
		"pvp_names": [pa.player_name, pb.player_name],
		"hand": pa.inventory.hand, "hand_owner": a, "human": not pa.is_cpu,
		"opp_hand": pb.inventory.hand, "opp_owner": b, "opp_human": not pb.is_cpu,
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

# A CPU's squad: its strongest living spirits (real dicts, so damage sticks),
# favouring types that beat the opponent's. Strongest goes first.
static func cpu_team(idx: int, opp: Array = []) -> Array:
	var squad: Array = GameState.players[idx].living_team()
	squad.sort_custom(func(a, b): return _power(a, opp) > _power(b, opp))
	return squad.slice(0, Balance.BATTLE_PICK_MAX)

static func _power(m: Dictionary, opp: Array) -> float:
	var v := float(m.get("current_hp", 0)) / 30.0 + float(m.get("atk", 1)) * 1.5 + float(m.get("def", 1)) \
		+ float(m.get("spd", 1)) * 0.5 + float(m.get("stars", 0)) * 1.5
	for o in opp:
		v += (SpiritsData.type_mult(m.get("type", ""), o.get("type", "")) - 1.0) * 3.0   # ±1.5 per foe
		v -= (SpiritsData.type_mult(o.get("type", ""), m.get("type", "")) - 1.0) * 2.0
	return v
