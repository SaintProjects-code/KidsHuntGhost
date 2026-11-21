extends "res://Scenes/UI/Battle/BattleView.gd"
## Battle screen, layer 2 of 3: the RULES. Abilities (match start, entry,
## round start, passives), status effects, event traits, charms, and the hit
## itself (_strike). Tactic-card effects show up here as per-round flags on a
## fighter ("_r_shield", "_r_hold"…) that BattleScreen sets and clears.

const STATUS_NAMES := {
	"stun": "stunned", "sleep": "asleep", "poison": "poisoned",
	"burn": "burned", "confuse": "confused",
}

# Balance numbers used in more than one place (balance pass: Wish 20 → 15,
# Healer 40 → 30; both won ~59% of simulated battles).
const WISH_HEAL := 15
const HEALER_HEAL := 30

var _star_credits: Dictionary = {}   # index into the caller's team -> stars earned
var _ko_stars: Dictionary = {}       # same key -> KO stars this battle (capped)

# ---------------- small helpers ----------------

# A spirit has ONE ability (plus its one charged move). Slot 1 is kept so the
# ability checks below read the same, but it's always empty; an "ability2"
# left on an old save is ignored.
func _ability_slot(mon: Dictionary, slot: int) -> String:
	return String(mon.get("ability", "")) if slot == 0 else ""

func _has(mon: Dictionary, ability: String) -> bool:
	return _ability_slot(mon, 0) == ability or _ability_slot(mon, 1) == ability

func _charm(mon: Dictionary) -> String:
	return String(mon.get("charm", ""))

func _alive(mon: Dictionary) -> bool:
	return int(mon.get("current_hp", 0)) > 0

func _side_of(mon: Dictionary) -> Array:
	return _team if _team.has(mon) else _opp

func _foes_of(mon: Dictionary) -> Array:
	return _opp if _team.has(mon) else _team

func _buff(mon: Dictionary, stat: String, delta: int) -> void:
	mon[stat] = clampi(int(mon.get(stat, 1)) + delta, 1, 9)

func _heal_mon(mon: Dictionary, amount: int) -> void:
	var before := int(mon.get("current_hp", 0))
	mon["current_hp"] = mini(int(mon.get("hp", 1)), before + amount)
	if int(mon["current_hp"]) > before:
		_float_on(mon, "+%d" % (int(mon["current_hp"]) - before), UIKit.GOOD)

# Non-lethal chip damage (abilities, statuses): never drops below 1 HP.
func _chip(mon: Dictionary, amount: int) -> void:
	mon["current_hp"] = maxi(1, int(mon.get("current_hp", 1)) - amount)
	_float_on(mon, "-%d" % amount, Color("ffb070"))

func _count_type(side: Array, type: String) -> int:
	return side.filter(func(a): return String(a.get("type", "")) == type).size()

func _needs_healing(side: Array) -> bool:
	for m in side:
		if _alive(m) and int(m["current_hp"]) < int(m.get("hp", 1)):
			return true
	return false

# Credit stars to one of the caller's spirits. KO stars are capped per battle.
func _credit_stars(mon: Dictionary, amount: float, from_ko: bool = true) -> float:
	var oi: int = int(mon.get("_oi", -1))
	if oi < 0 or not _team.has(mon):
		return 0.0
	if from_ko:
		var so_far: float = float(_ko_stars.get(oi, 0.0))
		amount = minf(amount, Balance.MAX_KO_STARS - so_far)
		if amount <= 0.0:
			return 0.0
		_ko_stars[oi] = so_far + amount
	_star_credits[oi] = float(_star_credits.get(oi, 0.0)) + amount
	return amount

# A full star for beating an equal/higher-stage spirit, half for a lower one.
func _ko_credit(att: Dictionary, def_: Dictionary) -> float:
	return 1.0 if int(def_.get("stage", 1)) >= int(att.get("stage", 1)) else 0.5

# ---------------- traits (temporary quirks from events) ----------------

const TRAIT_START_BUFFS := {
	"swift_soul": ["spd", 3], "heavy_boots": ["spd", -3], "brave_heart": ["atk", 2],
	"timid": ["atk", -2], "stone_skin": ["def", 2], "brittle_bones": ["def", -2],
}

func _apply_traits() -> void:
	for side in [_team, _opp]:
		for m in side:
			for key in m.get("traits", []):
				var b: Array = TRAIT_START_BUFFS.get(String(key), [])
				if b.is_empty():
					continue
				_buff(m, b[0], b[1])
				await _ability_note(m, "[Trait] ✦%s %s %s %+d" % [
					EventsData.trait_of(String(key))["name"], _who(m), String(b[0]).to_upper(), b[1]])

func _has_trait(m: Dictionary, key: String) -> bool:
	return m.get("traits", []).has(key)

# Round-start trait ticks for an active fighter; can cancel its action.
func _trait_tick(m: Dictionary, acts: bool) -> bool:
	if _has_trait(m, "sleepyhead") and _round_num == 1:
		acts = false
		_logln("[Trait] ✦Sleepyhead %s snoozes through round 1!" % _who(m))
		await _beat(0.45)
	if _has_trait(m, "cursed_wound"):
		_chip(m, 3)
		_logln("[Trait] ✦Cursed Wound %s loses 3 HP." % _who(m))
		await _beat(0.3)
	if _has_trait(m, "regrowth") and int(m.get("current_hp", 0)) < int(m.get("hp", 1)):
		_heal_mon(m, 3)
		_logln("[Trait] ✦Regrowth %s heals 3 HP." % _who(m))
		await _beat(0.3)
	return acts

# ---------------- match start ----------------

# Match-start abilities fire once, from anywhere in the lineup, in SPD order.
func _apply_match_start() -> void:
	var actors: Array = _team + _opp
	actors.sort_custom(func(a, b): return int(a.get("spd", 0)) > int(b.get("spd", 0)))
	for m in actors:
		for slot in 2:
			await _match_start_ability(m, _side_of(m), _foes_of(m), _ability_slot(m, slot))
	# U-Turn last: the lead hits and rotates to the back
	await _u_turn(_team, _opp)
	await _u_turn(_opp, _team)

func _match_start_ability(m: Dictionary, mine: Array, theirs: Array, ab: String) -> void:
	match ab:
		"intimidate":   # (was: whole enemy team — balance sim 58% win rate)
			for o in theirs.slice(0, 2):
				_buff(o, "atk", -1)
			await _ability_line("Match Start", m, "Intimidate", "first two enemies ATK −1")
		"screech":
			_buff(theirs[0], "def", -2)
			await _ability_line("Match Start", m, "Screech", "%s DEF −2" % _who(theirs[0]))
		"drought":
			for a in mine:
				_buff(a, "atk", 1)
			await _ability_line("Match Start", m, "Drought", "team ATK +1")
		"tailwind":   # (was +3)
			for a in mine:
				_buff(a, "spd", 2)
			await _ability_line("Match Start", m, "Tailwind", "team SPD +2")
		"speed_boost":   # (was team ATK and SPD +1)
			for a in mine:
				_buff(a, "spd", 1)
			_buff(m, "atk", 1)
			await _ability_line("Match Start", m, "Speed Boost", "team SPD +1, self ATK +1")
		"reflect":   # (was +2)
			for a in mine:
				_buff(a, "def", 1)
			await _ability_line("Match Start", m, "Reflect", "team DEF +1")
		"veteran":
			if float(m.get("stars", 0)) >= 1.0:
				_buff(m, "atk", 2)
				await _ability_line("Match Start", m, "Veteran", "self ATK +2")
		"thunder_wave":
			await _apply_status(theirs[0], "stun", 2, m)
		"confuse_ray":
			await _apply_status(theirs[0], "confuse", randi_range(2, 3), m)
		"taunt":
			for o in theirs:
				o["_taunted"] = true
			await _ability_line("Match Start", m, "Taunt", "enemy can't heal or inflict status")
		"sniper":
			var living: Array = theirs.filter(_alive)
			if not living.is_empty():
				var target: Dictionary = living.pick_random()
				var hit: int = maxi(1, int(m.get("atk", 1)) * 12)
				_chip(target, hit)
				await _ability_line("Match Start", m, "Sniper", "snipes %s for %d" % [_who(target), hit])
		"spikes":   # (damage raised 30 → 45, see _on_entry)
			for o in theirs:
				o["_spikes_pending"] = true
			await _ability_line("Match Start", m, "Spikes", "set on the enemy team")
		"focus_energy":   # (buffed: now also ATK +1)
			m["_charge"] = maxi(0, _move_cost(m) - 1)
			_buff(m, "atk", 1)
			await _ability_line("Match Start", m, "Focus Energy", "its move is almost ready! ATK +1")
		"fire_bond":   # (was team DEF +1)
			_buff(m, "atk", _count_type(mine, "Fire"))
			_buff(m, "def", 1)
			await _ability_line("Match Start", m, "Fire Bond", "self ATK up, self DEF +1")
		"water_bond":   # (was team DEF +3 — balance sim 77% win rate)
			_buff(m, "atk", _count_type(mine, "Water"))
			for a in mine:
				_buff(a, "def", 1)
			await _ability_line("Match Start", m, "Water Bond", "self ATK up, team DEF +1")
		"grass_bond":
			_buff(m, "atk", _count_type(mine, "Grass"))
			for a in mine:
				a["hp"] = int(a.get("hp", 60)) + 30
				_heal_mon(a, 30)
			await _ability_line("Match Start", m, "Grass Bond", "self ATK up, team +30 HP")
		"electric_bond":   # (was team SPD +3)
			_buff(m, "atk", _count_type(mine, "Electric"))
			for a in mine:
				_buff(a, "spd", 1)
			await _ability_line("Match Start", m, "Electric Bond", "self ATK up, team SPD +1")
		"fighting_bond":   # (was team DEF +1)
			_buff(m, "atk", _count_type(mine, "Fighting"))
			_buff(m, "def", 1)
			await _ability_line("Match Start", m, "Fighting Bond", "self ATK up, self DEF +1")
		"psychic_bond":
			_buff(m, "atk", _count_type(mine, "Psychic"))
			for a in mine:
				a["_status_immune"] = true
			await _ability_line("Match Start", m, "Psychic Bond", "team ATK up, status immune")
		"dark_bond":
			_buff(m, "atk", _count_type(mine, "Dark"))
			for o in theirs:
				_buff(o, "def", -2)
			await _ability_line("Match Start", m, "Dark Bond", "self ATK up, enemy DEF −2")
		"mayhem":   # (buffed: now also enemy team SPD −1)
			theirs.shuffle()   # scramble the enemy line-up — their lead can change
			for o in theirs:
				_buff(o, "spd", -1)
			_build_cards()
			await _ability_line("Match Start", m, "Mayhem", "scrambles the enemy line-up! Enemy SPD −1")
		"mind_hold":
			var targets: Array = theirs.filter(_alive)
			targets.shuffle()
			var held: Array = []
			for t in targets.slice(0, 2):
				t["ability"] = ""
				t["ability2"] = ""
				t["_suppressed"] = 999
				held.append(_who(t))
			if not held.is_empty():
				await _ability_line("Match Start", m, "Mind Hold", "seals the minds of %s!" % ", ".join(held))

# U-Turn: the lead lands a free hit, rotates to the back, and hypes the ally
# who takes its place.
func _u_turn(mine: Array, theirs: Array) -> void:
	if mine.size() < 2 or not _has(mine[0], "u_turn"):
		return
	var m: Dictionary = mine[0]
	var hit: int = maxi(1, int(DamageCalculator.calculate(m, theirs[0]) * 0.7))   # U-Turn (was 0.4)
	_chip(theirs[0], hit)
	mine.remove_at(0)
	mine.append(m)
	_buff(mine[0], "atk", 1)
	_build_cards()
	await _ability_line("Match Start", m, "U-Turn", "hits %d, %s steps up ATK +1" % [hit, _who(mine[0])])

# ---------------- entering battle ----------------

# Charms + entry abilities whenever a spirit becomes the active fighter.
func _on_entry(is_me: bool) -> void:
	var mine: Array = _team if is_me else _opp
	var theirs: Array = _opp if is_me else _team
	var idx: int = _active if is_me else _opp_active
	var their_idx: int = _opp_active if is_me else _active
	if idx >= mine.size():
		return
	var m: Dictionary = mine[idx]
	m["_fought"] = true   # (battle copy) it took the field — for balance checks
	if not m.has("_charge"):
		m["_charge"] = mini(_move_cost(m) - 1, Balance.START_CHARGE)
	_charm_entry(is_me)
	if m.get("_spikes_pending", false):
		m.erase("_spikes_pending")
		_chip(m, 45)
		_anim_shake(m)
		_logln("%s is hurt by Spikes! -45 HP." % _who(m))
		await _beat(0.45)
	for slot in 2:
		await _entry_ability(m, mine, theirs, their_idx, _ability_slot(m, slot))

# The "on entry" half of a charm: runs when a charmed spirit becomes the active
# fighter, and right away when a charm card is played on the lead.
func _charm_entry(is_me: bool) -> void:
	var mine: Array = _team if is_me else _opp
	var theirs: Array = _opp if is_me else _team
	var idx: int = _active if is_me else _opp_active
	var their_idx: int = _opp_active if is_me else _active
	if idx >= mine.size():
		return
	var m: Dictionary = mine[idx]
	match _charm(m):
		"brave_ribbon":   # (now +2 the first time, then +1)
			var first_r: bool = not m.get("_ribbon_used", false)
			m["_ribbon_used"] = true
			_buff(m, "atk", 2 if first_r else 1)
			_logln("%s's Brave Ribbon! ATK +%d." % [_who(m), 2 if first_r else 1])
		"guard_pin":   # (now +2 the first time, then +1)
			var first_p: bool = not m.get("_pin_used", false)
			m["_pin_used"] = true
			_buff(m, "def", 2 if first_p else 1)
			_logln("%s's Guard Pin! DEF +%d." % [_who(m), 2 if first_p else 1])
		"war_drum":   # (redesign: 70% ATK, was 40%)
			if their_idx < theirs.size():
				var hit: int = maxi(1, int(DamageCalculator.calculate(m, theirs[their_idx]) * 0.7))
				_chip(theirs[their_idx], hit)
				_logln("%s's War Drum! Free hit for %d." % [_who(m), hit])
		"last_trophy":   # (redesign: +2 ATK +2 DEF, no longer takes extra damage)
			if mine.filter(_alive).size() <= 1 and not m.get("_trophy_used", false):
				m["_trophy_used"] = true
				_buff(m, "atk", 2)
				_buff(m, "def", 2)
				_logln("%s raises the Last Trophy! ATK +2, DEF +2!" % _who(m))

func _entry_ability(m: Dictionary, mine: Array, theirs: Array, their_idx: int, ab: String) -> void:
	match ab:
		"shell_smash":
			_buff(m, "def", -3)
			_buff(m, "atk", 3)
			_buff(m, "spd", 1)
			await _ability_note(m, "%s's %s! ATK +3, SPD +1, DEF -3." % [_who(m), _abn("Shell Smash")])
		"all_for_one":
			if theirs.filter(_alive).size() > mine.filter(_alive).size():
				_buff(m, "atk", 2)
				_buff(m, "spd", 2)
				await _ability_note(m, "%s won't back down — %s! ATK/SPD +2." % [_who(m), _abn("Underdog")])
		"monument":
			if mine.filter(_alive).size() == 1 and not m.get("_last_stand", false):
				m["_last_stand"] = true
				for st in ["atk", "def", "spd"]:
					_buff(m, st, 2)
				await _ability_note(m, "%s makes its %s! +2 to everything." % [_who(m), _abn("Last Stand")])
		"hypnosis":
			if not m.get("_hyp_used", false) and their_idx < theirs.size():
				m["_hyp_used"] = true
				await _apply_status(theirs[their_idx], "sleep", 2, m)
		"encore":   # (was 3 rounds)
			if their_idx < theirs.size():
				theirs[their_idx]["_suppressed"] = 5
				await _ability_note(m, "%s's %s! %s's ability is suppressed for 5 rounds." % [
					_who(m), _abn("Encore"), _who(theirs[their_idx])])

# ---------------- status effects ----------------

func _apply_status(target: Dictionary, kind: String, rounds: int, inflictor: Dictionary = {}) -> void:
	if not inflictor.is_empty() and inflictor.get("_taunted", false):
		return   # taunted spirits can't inflict status
	if target.get("_r_immune", false):
		_tactic_banner("✨", "Purify!", "%s shrugs off the %s" % [target.get("name", "?"), kind], Color("7be0a0"))
		return
	if target.get("_status_immune", false):
		return
	if _has(target, "veteran") and float(target.get("stars", 0)) >= 1.0:
		return
	if target.has("_status"):
		return   # one status at a time
	target["_status"] = {"kind": kind, "rounds": rounds}
	if kind == "burn":
		_buff(target, "atk", -1)
	_anim_shake(target)
	_logln("%s is %s!" % [_who(target), STATUS_NAMES.get(kind, kind)])
	await _beat(0.45)

# Tick the active fighter's status at round start. Returns false if it can't
# attack this round. Status damage never KOs.
func _process_status(m: Dictionary) -> bool:
	if not m.has("_status"):
		return true
	var st: Dictionary = m["_status"]
	var kind: String = st.get("kind", "")
	var can_act := true
	match kind:
		"poison", "burn":
			_chip(m, 10)
			_anim_shake(m)
			_logln("%s is hurt by %s! -10 HP." % [_who(m), kind])
			await _beat(0.45)
		"stun", "sleep":
			can_act = false
			_logln("%s is %s and can't move!" % [_who(m), STATUS_NAMES[kind]])
			await _beat(0.45)
		"confuse":
			if randf() < 0.5:
				can_act = false
				_chip(m, 15)
				_anim_shake(m)
				_logln("%s hurt itself in confusion! -15 HP." % _who(m))
				await _beat(0.45)
	st["rounds"] = int(st.get("rounds", 1)) - 1
	if int(st["rounds"]) <= 0:
		m.erase("_status")
		_logln("%s recovered from being %s." % [_who(m), STATUS_NAMES.get(kind, kind)])
		await _beat(0.4)
	return can_act

# ---------------- round start ----------------

# Round-start abilities for the active fighter. Their damage never KOs.
func _round_start_abilities(m: Dictionary, foe: Dictionary, slot: int) -> void:
	# Encore: no round-start ability while suppressed (ticks once per round)
	if int(m.get("_suppressed", 0)) > 0:
		if slot == 0:
			m["_suppressed"] = int(m["_suppressed"]) - 1
		return
	var ab := _ability_slot(m, slot)
	if m.get("_taunted", false) and ab in ["dynasty", "regenerator", "wish", "medic"]:
		return   # Taunt blocks healing
	match ab:
		"fortress":
			if int(m.get("_fortress", 0)) < 3:
				m["_fortress"] = int(m.get("_fortress", 0)) + 1
				_buff(m, "def", 1)
				await _ability_line("Round Start", m, "Fortress", "self DEF +1")
		"iron_will":
			if int(m.get("current_hp", 0)) >= int(m.get("hp", 1)):
				_buff(m, "atk", 1)
				await _ability_line("Round Start", m, "Iron Will", "self ATK +1")
		"leech_seed":
			var drain: int = 20 if foe.has("_status") else 10
			_chip(foe, drain)
			_heal_mon(m, drain)
			await _ability_line("Round Start", m, "Leech Seed", "drains %d HP from %s" % [drain, _who(foe)])
		"berserker":
			_buff(m, "atk", 2)
			_chip(m, 20)
			await _ability_line("Round Start", m, "Berserker", "self ATK +2, −20 HP")
		"dynasty":
			if int(m.get("current_hp", 0)) < int(m.get("hp", 1)):
				_heal_mon(m, 20)
				await _ability_line("Round Start", m, "Dynasty", "heals 20 HP")
		"regenerator":
			if int(m.get("current_hp", 0)) < int(m.get("hp", 1)):
				var amount: int = int(m.get("hp", 1) * 0.3)
				_heal_mon(m, amount)
				await _ability_line("Round Start", m, "Regenerator", "heals %d HP" % amount)
		"wish":   # (was 20 HP)
			if _needs_healing(_side_of(m)):
				for a in _side_of(m).filter(_alive):
					_heal_mon(a, WISH_HEAL)
				await _ability_line("Round Start", m, "Wish", "team heals %d HP" % WISH_HEAL)
		"drain_punch":   # (was 25% ATK — balance sim 73% win rate)
			var hit: int = maxi(1, int(m.get("atk", 1)) * 15 / 4)
			_chip(foe, hit)
			_heal_mon(m, hit)
			await _ability_line("Round Start", m, "Drain Punch", "deals %d and heals %d" % [hit, hit])
		"electric_field":
			# 30% ATK to TWO random living opponents — bench included (was 50%)
			var foes: Array = _foes_of(m).filter(_alive)
			foes.shuffle()
			var zap: int = maxi(1, int(m.get("atk", 1)) * 15 / 2)
			var hit_names: Array = []
			for t in foes.slice(0, 2):
				_chip(t, zap)
				_anim_shake(t)
				hit_names.append(_who(t))
			if not hit_names.is_empty():
				await _ability_line("Round Start", m, "Electric Field", "zaps %s for %d each" % [", ".join(hit_names), zap])
		"medic":   # (was a 30% chance, revive to 25%)
			if not m.get("_medic_used", false) and randf() < 0.5:
				for a in _side_of(m):
					if not _alive(a):
						a["current_hp"] = int(a.get("hp", 1) * 0.35)
						a.erase("_gone")
						m["_medic_used"] = true
						await _ability_line("Round Start", m, "Medic", "revives %s" % _who(a))
						_requeue_revived(a)
						break

# Bench abilities that fire each round (Healer and Wish work from behind).
func _bench_round_abilities(side: Array, active: int) -> void:
	if active >= side.size():
		return
	var lead: Dictionary = side[active]
	for j in side.size():
		var b: Dictionary = side[j]
		if j == active or not _alive(b) or b.get("_taunted", false):
			continue
		if _has(b, "healer") and _alive(lead) and int(lead["current_hp"]) < int(lead.get("hp", 1)):
			_heal_mon(lead, HEALER_HEAL)
			await _ability_line("Round Start", b, "Healer", "restores %d HP to %s" % [HEALER_HEAL, _who(lead)])
		if _has(b, "wish") and _needs_healing(side):
			for a in side.filter(_alive):
				_heal_mon(a, WISH_HEAL)
			await _ability_line("Round Start", b, "Wish", "team heals %d HP" % WISH_HEAL)

# A revived ally is stranded behind the active index; move it to just behind
# the current fighter so it steps up next.
func _requeue_revived(a: Dictionary) -> void:
	var is_me: bool = _team.has(a)
	var side: Array = _side_of(a)
	var active: int = _active if is_me else _opp_active
	var idx: int = side.find(a)
	if idx == -1 or idx >= active:
		return
	side.remove_at(idx)
	active -= 1
	side.insert(active + 1, a)
	if is_me:
		_active = active
	else:
		_opp_active = active
	_build_cards()
	_refresh()

# Living bench members with Vengeance avenge a fallen ally on the enemy lead.
func _vengeance(side: Array, enemy_active: Dictionary) -> void:
	for b in side:
		if _alive(b) and _has(b, "vengeance") and _alive(enemy_active):
			var hit: int = maxi(1, int(b.get("atk", 1)) * 25)
			enemy_active["current_hp"] = maxi(0, int(enemy_active["current_hp"]) - hit)
			_float_on(enemy_active, "-%d" % hit, UIKit.BAD)
			await _ability_line("Passive", b, "Vengeance", "%d damage to %s" % [hit, _who(enemy_active)])
			if not _alive(enemy_active) and side == _team:
				_credit_stars(b, _ko_credit(b, enemy_active))

# Helping Hand: once per battle each, a bench ally swaps in for a lead below 45%.
func _helping_hand(side: Array, active: int) -> void:
	if active >= side.size():
		return
	var lead: Dictionary = side[active]
	if not _alive(lead) or float(lead["current_hp"]) / float(maxi(1, lead.get("hp", 1))) >= 0.45:
		return
	for j in side.size():
		var b: Dictionary = side[j]
		if j != active and _alive(b) and _has(b, "helping_hand") and not b.get("_hh_used", false):
			b["_hh_used"] = true
			side[active] = b
			side[j] = lead
			_buff(b, "def", 2)   # (buffed: now steps in braced, DEF +2)
			await _ability_line("Passive", b, "Helping Hand", "steps in for %s, DEF +2" % _who(lead))
			_build_cards()
			await _on_entry(side == _team)
			return

# ---------------- the hit ----------------

# One hit. `mult` scales it (moves); `ignore_def` skips the defender's DEF.
func _strike(att: Dictionary, def_: Dictionary, attacker_is_me: bool, mult: float = 1.0, ignore_def := false) -> void:
	_anim_attack(att)
	await _beat(0.3)
	# Bodyguard: a bench ally throws itself in front of a HURT lead, once per round
	if float(def_.get("current_hp", 0)) / float(maxi(1, def_.get("hp", 1))) < 0.5:
		for b in _side_of(def_):
			if b != def_ and _alive(b) and _has(b, "bodyguard") and int(b.get("_bg_round", -1)) != _round_num:
				b["_bg_round"] = _round_num
				await _ability_note(b, "%s's %s! It shields %s and takes the hit!" % [_who(b), _abn("Bodyguard"), _who(def_)])
				def_ = b
				break
	var item_mult := 1.25 if _charm(att) == "power_band" else 1.0   # (was 1.2)
	if _has(att, "reckless"):
		item_mult *= 1.25
	var target_stats: Dictionary = {"type": def_.get("type", ""), "def": 0} if ignore_def else def_
	var dmg: int = DamageCalculator.calculate(att, target_stats, 1.0, mult, item_mult)
	# absorb abilities can negate the hit outright
	if _has(def_, "flash_fire") and randf() < 0.25:
		_buff(def_, "atk", 2)
		await _ability_line("Passive", def_, "Flash Fire", "absorbs the hit, ATK +2")
		return
	if _has(def_, "volt_absorb") and randf() < 0.35:
		_heal_mon(def_, dmg)
		await _ability_line("Passive", def_, "Volt Absorb", "turns the hit into %d HP" % dmg)
		return
	var taken := float(dmg) * _damage_taken_mult(def_)
	await _log_reductions(def_)
	var final := maxi(1, int(round(taken)))
	var hp_after: int = int(def_.get("current_hp", 0)) - final
	def_["current_hp"] = maxi(0, hp_after)
	var t_mult: float = SpiritsData.type_mult(att.get("type", ""), def_.get("type", ""))
	var eff := "  Super effective!" if t_mult > 1.0 else ("  Not very effective…" if t_mult < 1.0 else "")
	_anim_shake(def_)
	_float_on(def_, "-%d" % final, Color("ff5050") if t_mult > 1.0 else UIKit.BAD)
	if not _quiet():
		Sfx.play("crit" if t_mult > 1.0 else "hit", randf_range(0.9, 1.1))
	_logln("%s hits %s for %d!%s" % [_who(att), _who(def_), final, eff])
	await _beat(0.5)
	if def_.get("_r_mirror", false) and _alive(att):
		var back := maxi(1, final * 6 / 10)   # Mirror Veil (was half)
		att["current_hp"] = maxi(0, int(att["current_hp"]) - back)
		_anim_shake(att)
		_float_on(att, "-%d" % back, UIKit.BAD)
		_logln("🪞 The Mirror Veil bounces %d back at %s!" % [back, _who(att)])
		_tactic_banner("🪞", "Mirror Veil!", "%d damage bounced back" % back, Color("8fd6ff"))
		await _beat(0.35)
	if hp_after <= 0:
		await _survive_lethal(def_)
	await _on_hit_effects(att, def_, final)
	if _alive(def_):
		await _threshold_abilities(def_)
	else:
		await _on_ko(att, def_, attacker_is_me)

# Multiplier on damage a defender takes (charms, abilities, tactic cards).
func _damage_taken_mult(def_: Dictionary) -> float:
	var m := 1.0
	var ratio := float(def_.get("current_hp", 0)) / float(maxi(1, def_.get("hp", 1)))
	if _charm(def_) == "ghost_cloak":
		m *= 0.8   # (was 0.85)
	if _has(def_, "thick_fat"):
		m *= 0.8
	if _has(def_, "reckless"):
		m *= 1.15
	if _has(def_, "grit") and ratio < 0.3:
		m *= 0.7
	if _has(def_, "bulwark") and ratio > 0.5:
		m *= 0.65   # (was 0.8)
	if _has(def_, "battle_armor") and _round_num <= 2:
		m *= 0.5
	if _has(def_, "multiscale") and ratio >= 1.0 and not def_.get("_ms_used", false):
		m *= 0.5
		def_["_ms_used"] = true
	if def_.get("_r_shield", false):
		m *= 0.4   # Spirit Shield (was 0.5)
	if def_.get("_guard_next", false):
		m *= 0.5
		def_.erase("_guard_next")
	return m

# First-time log lines for the passive reductions that just applied.
func _log_reductions(def_: Dictionary) -> void:
	if _has(def_, "thick_fat"):
		await _passive_once(def_, "thick_fat", "incoming damage ×0.8")
	if _has(def_, "battle_armor") and _round_num <= 2:
		await _passive_once(def_, "battle_armor", "×0.5 in early rounds")
	if def_.get("_r_shield", false) and not def_.get("_r_shield_logged", false):
		def_["_r_shield_logged"] = true
		_logln("🛡 The Spirit Shield blocks most of the blow!")
		_tactic_banner("🛡", "Spirit Shield!", "%s takes only 40%% damage" % def_.get("name", "?"), Color("8fd6ff"))

# Lucky Scarf / Sturdy / Anger Point / Hold On! keep a spirit at 1 HP.
func _survive_lethal(def_: Dictionary) -> void:
	if def_.get("_r_hold", false):
		def_["current_hp"] = 1
		_logln("✊ %s holds on!" % _who(def_))
		_tactic_banner("✊", "Hold On!", "%s survives with 1 HP" % def_.get("name", "?"), Color("ffd24d"))
		await _beat(0.4)
	elif _charm(def_) == "lucky_scarf" and not def_.get("_sash_used", false):
		def_["_sash_used"] = true
		def_["current_hp"] = maxi(1, int(def_.get("hp", 1)) * 15 / 100)   # (was 1 HP)
		_logln("%s hangs on with its Lucky Scarf!" % _who(def_))
		await _beat(0.45)
	elif _has(def_, "sturdy") and not def_.get("_sturdy_used", false):
		def_["_sturdy_used"] = true
		def_["current_hp"] = 1
		await _ability_note(def_, "%s endures the hit — %s!" % [_who(def_), _abn("Sturdy")])
	elif _has(def_, "anger_point") and not def_.get("_anger_used", false):
		def_["_anger_used"] = true
		def_["current_hp"] = 1
		_buff(def_, "atk", 3)
		await _ability_note(def_, "%s hits its %s! Survives at 1 HP, ATK +3!" % [_who(def_), _abn("Anger Point")])

func _on_hit_effects(att: Dictionary, def_: Dictionary, final: int) -> void:
	if _charm(att) == "echo_bell":
		var sip: int = maxi(1, final * 15 / 100)   # Echo Bell (was 10%)
		_heal_mon(att, sip)
		_logln("%s's Echo Bell restores %d HP." % [_who(att), sip])
	if _charm(def_) == "spiky_helm":
		_chip(att, 20)   # (was 15)
		_logln("%s is hurt by the Spiky Helm! -20 HP." % _who(att))
	if _has(att, "thief") and int(att.get("_thief_stacks", 0)) < 3:
		att["_thief_stacks"] = int(att.get("_thief_stacks", 0)) + 1
		_buff(att, "atk", 1)
		_buff(def_, "atk", -1)
		await _ability_note(att, "%s steals power — %s! ATK +1." % [_who(att), _abn("Thief")])
	if _has(def_, "counter") and final >= 30 and _alive(def_):   # (was 50+ for 40%)
		var payback: int = int(final * 0.5)
		att["current_hp"] = maxi(0, int(att.get("current_hp", 0)) - payback)
		_anim_shake(att)
		_float_on(att, "-%d" % payback, UIKit.BAD)
		await _ability_note(def_, "%s Counters for %d!" % [_who(def_), payback])
	# contact statuses punish the attacker
	if _alive(def_):
		if _has(def_, "static") and randf() < 0.5:   # (was 30%)
			await _apply_status(att, "stun", 1, def_)
		if _has(def_, "poison_point"):   # (buffed: 4 rounds, and the first hit saps ATK)
			await _apply_status(att, "poison", 4, def_)
			if not att.get("_pp_sapped", false):
				att["_pp_sapped"] = true
				_buff(att, "atk", -1)
		if _has(def_, "flame_body"):
			await _apply_status(att, "burn", 3, def_)
		if _has(def_, "spore"):
			await _apply_status(att, ["stun", "poison", "burn", "confuse", "sleep"].pick_random(), 2, def_)

# Once-per-battle boosts when a defender drops below a threshold.
func _threshold_abilities(def_: Dictionary) -> void:
	var ratio := float(def_["current_hp"]) / float(maxi(1, def_.get("hp", 1)))
	if _charm(def_) == "moon_berry" and ratio < 0.5 and not def_.get("_berry_used", false):
		def_["_berry_used"] = true
		_heal_mon(def_, int(def_.get("hp", 1) * 0.5))   # Moon Berry (redesign: was 30%)
		_logln("%s munches its Moon Berry — HP restored!" % _who(def_))
	if _has(def_, "blaze") and ratio < 0.33 and not def_.get("_blaze_used", false):
		def_["_blaze_used"] = true
		_buff(def_, "atk", 3)   # (was ATK +4, SPD +2)
		_buff(def_, "spd", 1)
		await _ability_note(def_, "%s's %s ignites! ATK +3, SPD +1!" % [_who(def_), _abn("Blaze")])
	if _has(def_, "overgrow") and ratio < 0.5 and not def_.get("_overgrow_used", false):
		def_["_overgrow_used"] = true
		_buff(def_, "atk", 3)   # (was ATK +2, DEF +1)
		_buff(def_, "def", 2)
		await _ability_note(def_, "%s's %s surges! ATK +3, DEF +2!" % [_who(def_), _abn("Overgrow")])

func _on_ko(att: Dictionary, def_: Dictionary, attacker_is_me: bool) -> void:
	if _charm(def_) == "phoenix_feather" and not def_.get("_phoenix_used", false):
		def_["_phoenix_used"] = true
		def_["current_hp"] = maxi(1, int(def_.get("hp", 1) * 0.35))   # (was 25%)
		_logln("%s rises on its Phoenix Feather!" % _who(def_))
		return
	if _has(def_, "phoenix") and not def_.get("_phoenix_ab_used", false):
		def_["_phoenix_ab_used"] = true
		def_["current_hp"] = maxi(1, int(def_.get("hp", 1) * 0.3))
		await _ability_note(def_, "%s is reborn from the ashes — %s!" % [_who(def_), _abn("Phoenix")])
		return
	if attacker_is_me:
		var granted := _credit_stars(att, _ko_credit(att, def_))
		if granted > 0.0:
			_logln("[color=#d3a8ff]%s earns %s star for the KO![/color]" % [att.get("name", "?"), "a" if granted >= 1.0 else "half a"])
	if _has(def_, "destiny_bond"):
		att["current_hp"] = 0
		_anim_shake(att)
		await _ability_note(def_, "%s's %s drags %s down with it!" % [_who(def_), _abn("Destiny Bond"), _who(att)])
	elif _has(def_, "explosion"):
		var boom: int = int(def_.get("hp", 1) * 0.6)
		att["current_hp"] = maxi(0, int(att.get("current_hp", 0)) - boom)
		_anim_shake(att)
		_float_on(att, "-%d" % boom, Color("ff5050"))
		Sfx.play("crash")
		await _ability_note(def_, "%s explodes for %d damage!" % [_who(def_), boom])
	if _has(att, "moxie"):   # (buffed: now also SPD +1)
		_buff(att, "atk", 2)
		_buff(att, "spd", 1)
		await _ability_note(att, "%s's %s! ATK +2, SPD +1." % [_who(att), _abn("Moxie")])
	elif _has(att, "soul_heart"):
		_buff(att, "atk", 1)
		_buff(att, "def", 1)
		await _ability_note(att, "%s's %s! ATK/DEF +1." % [_who(att), _abn("Soul Heart")])

# ---------------- signature moves ----------------

func _move_cost(m: Dictionary) -> int:
	return int(SpiritsData.move_of(SpiritsData.move_key(m)).get("charge", 3))

# The attacker's turn: a charge is gained; a full gauge fires the move. A move
# that hits replaces the normal hit; a move that doesn't (Calm Mind, Bloom) is
# followed by the normal hit, so a spirit always attacks.
func _attack_or_move(att: Dictionary, def_: Dictionary, is_me: bool) -> void:
	att["_charge"] = int(att.get("_charge", 0)) + 1
	var hp_before := int(def_.get("current_hp", 0))
	var attacked := false
	if int(att["_charge"]) >= _move_cost(att):
		att["_charge"] = 0
		attacked = float(SpiritsData.move_of(SpiritsData.move_key(att)).get("power", 1.0)) > 0.0
		await _use_move(att, def_, is_me)
	if not attacked and _alive(att) and _alive(def_):
		await _strike(att, def_, is_me)
	# taking a hit builds the defender's gauge too (never past "ready")
	if Balance.CHARGE_ON_HIT and _alive(def_) and int(def_.get("current_hp", 0)) < hp_before:
		def_["_charge"] = mini(_move_cost(def_) - 1, int(def_.get("_charge", 0)) + 1)

func _use_move(att: Dictionary, def_: Dictionary, is_me: bool) -> void:
	var key := SpiritsData.move_key(att)
	var mv := SpiritsData.move_of(key)
	var boost := 1.6 if _has(att, "overcharge") else 1.0   # (was 1.3)
	var power: float = float(mv.get("power", 1.0)) * boost
	att["_moves_used"] = int(att.get("_moves_used", 0)) + 1
	var c := _card_of(att)
	if not _quiet():
		Sfx.play("crit", 0.8)
		if c:
			Juice.flash(c, Color(2.0, 1.8, 0.6), 0.35)
		_flash_special(att, String(mv["name"]))
	_logln("[color=#ffd24d]✦ %s uses %s![/color]" % [_who(att), mv["name"]])
	await _beat(0.35)
	var foes: Array = _foes_of(att).filter(_alive)
	match key:
		"heat_wave", "chain_bolt":
			var hits: Array = foes if key == "heat_wave" else foes.slice(0, 3)
			for f in hits:
				if _alive(att):
					await _strike(att, f, is_me, power)
		"combo_strike":
			await _strike(att, def_, is_me, power)
			if _alive(att) and _alive(def_):
				await _strike(att, def_, is_me, power)
		"mind_blast":
			await _strike(att, def_, is_me, power, true)
		"shadow_sneak":
			var low := float(def_.get("current_hp", 0)) / float(maxi(1, def_.get("hp", 1))) < 0.5
			await _strike(att, def_, is_me, power * (2.0 if low else 1.0))
		"vine_drain":
			var before := int(def_.get("current_hp", 0))
			await _strike(att, def_, is_me, power)
			_heal_mon(att, maxi(1, (before - int(def_.get("current_hp", 0))) / 2))
		"bloom":
			for a in _side_of(att).filter(_alive):
				_heal_mon(a, int(50 * boost))
			if not _quiet():
				Sfx.play("heal")
			_logln("🌸 The whole team blooms back to health!")
			await _beat(0.4)
		"calm_mind":   # (buffed: was ATK/DEF +1 only — balance sim 32% win rate)
			_buff(att, "atk", 2)
			_buff(att, "def", 1)
			att.erase("_status")
			_heal_mon(att, int(att.get("hp", 1)) / 5)
			_anim_ability(att)
			_logln("%s centres itself — ATK +2, DEF +1, heals 20%%." % _who(att))
			await _beat(0.4)
		_:
			if power > 0.0:
				await _strike(att, def_, is_me, power)
	# after-effects that need the target standing
	if _alive(def_):
		match key:
			"ember_burst": await _apply_status(def_, "burn", 2, att)
			"thunderclap": await _apply_status(def_, "stun", 1, att)
			"hex_sleep": await _apply_status(def_, "sleep", 2, att)
			"curse": await _apply_status(def_, "poison", 4, att)
			"spore_cloud":
				await _apply_status(def_, "sleep", 1, att)
				if not def_.has("_status"):
					await _apply_status(def_, "poison", 3, att)
			"soak": _buff(def_, "spd", -2)
			"dread": _buff(def_, "atk", -2)
	if _alive(att):
		match key:
			"tidal_guard": att["_guard_next"] = true
			"whirlpool": _heal_mon(att, int(att.get("hp", 1) * 0.25 * boost))
			"spark_rush": _buff(att, "spd", 1)
			"haymaker": _buff(att, "def", -1)
			"iron_guard": _buff(att, "def", 2)
		if _has(att, "rally_call") and int(att.get("_rallies", 0)) < 2:
			att["_rallies"] = int(att.get("_rallies", 0)) + 1
			for a in _side_of(att).filter(_alive):
				_buff(a, "atk", 1)
			await _ability_line("Passive", att, "Rally Call", "team ATK +1")
	_refresh()
