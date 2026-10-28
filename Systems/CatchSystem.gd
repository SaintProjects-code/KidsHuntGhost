extends Node
## Autoloaded. Wild-ghost rules (the catch window animates them):
##   1) SPOOK DUEL — lead power + 🎲d6 vs ghost power + 🎲d6. Lose: it flees.
##   2) CAPTURE — Balance.CATCH_THROWS throws of d100 + jar/badge/spooked/lure
##      bonuses ≥ the ghost's target (which rises after every miss).
## A catch pays points + gold and gives your lead stars.

const JARS := {
	&"ghost_jar":   {"name": "Ghost Jar",   "bonus": 0,  "cost": 10},
	&"silver_jar":  {"name": "Silver Jar",  "bonus": 16, "cost": 25},
	&"golden_jar":  {"name": "Golden Jar",  "bonus": 41, "cost": 50},
	&"soul_lantern":{"name": "Soul Lantern","bonus": 100, "cost": 0},   # never fails
}
const JAR_ORDER := [&"ghost_jar", &"silver_jar", &"golden_jar", &"soul_lantern"]

func _ready() -> void:
	EventBus.catch_attempted.connect(_on_catch_attempted)

static func jar_name(jar: StringName) -> String:
	return String(JARS.get(jar, {}).get("name", String(jar)))

# The number the roll + bonus has to reach.
static func target_for(spirit: Dictionary) -> int:
	var base: int = Balance.LEGEND_TARGET if SpiritsData.is_legendary(String(spirit.get("name", ""))) \
		else int(Balance.CATCH_TARGET.get(int(spirit.get("stage", 1)), 41))
	return base + int(spirit.get("catch_fails", 0)) * Balance.CATCH_FAIL_PENALTY

# Everything added to the d100, itemised for the catch window.
static func bonus_parts(player_idx: int, spirit: Dictionary, jar: StringName) -> Array:
	var p: PlayerData = GameState.players[player_idx]
	var parts: Array = [[jar_name(jar), int(JARS.get(jar, {}).get("bonus", 0))]]
	var badges := mini(p.progress.badge_count(), Balance.CATCH_BADGE_CAP)
	if badges > 0:
		parts.append(["Badges", badges * Balance.CATCH_BADGE_BONUS])
	if spirit.get("_spooked", false):
		parts.append(["Spooked", Balance.DUEL_BONUS])
	if spirit.get("_lured", false):
		parts.append(["Lure", Balance.CATCH_LURE_BONUS])
	return parts

static func total_bonus(player_idx: int, spirit: Dictionary, jar: StringName) -> int:
	var n := 0
	for part in bonus_parts(player_idx, spirit, jar):
		n += int(part[1])
	return n

# Chance in percent (for the window and the CPU's planning).
static func chance(player_idx: int, spirit: Dictionary, jar: StringName) -> int:
	if jar == &"soul_lantern":
		return 100
	var need := target_for(spirit) - total_bonus(player_idx, spirit, jar)
	return clampi(101 - need, 0, 100)

# ── Spook Duel ───────────────────────────────────────────────────────────────

# A spirit's duel power: rounded average of ATK/DEF/SPD, plus its stars.
static func duel_power(s: Dictionary) -> int:
	var avg := (float(s.get("atk", 1)) + float(s.get("def", 1)) + float(s.get("spd", 1))) / 3.0
	return int(round(avg)) + int(float(s.get("stars", 0)))

# +1 if the lead's type beats the ghost's, −1 if the ghost's beats the lead's.
static func type_edge(lead: Dictionary, ghost: Dictionary) -> int:
	var t1 := String(lead.get("type", ""))
	var t2 := String(ghost.get("type", ""))
	return (1 if SpiritsData.type_mult(t1, t2) > 1.0 else 0) - (1 if SpiritsData.type_mult(t2, t1) > 1.0 else 0)

# Chance (0..1) that the lead wins the duel (ties go to the lead).
static func duel_chance(lead: Dictionary, ghost: Dictionary) -> float:
	var mine := duel_power(lead) + type_edge(lead, ghost)
	var theirs := duel_power(ghost)
	var wins := 0
	for a in range(1, 7):
		for b in range(1, 7):
			if mine + a >= theirs + b:
				wins += 1
	return wins / 36.0

# ── Capture ──────────────────────────────────────────────────────────────────

# The window rolls first (so it can animate the die), then reports the roll
# here through catch_attempted with spirit["_roll"] set. A missing roll is
# rolled now (CPU / silent paths).
func _on_catch_attempted(player_idx: int, spirit: Dictionary, jar: StringName) -> void:
	var roll: int = int(spirit.get("_roll", randi_range(1, 100)))
	spirit.erase("_roll")
	var ok: bool = jar == &"soul_lantern" \
		or roll + total_bonus(player_idx, spirit, jar) >= target_for(spirit)
	if ok:
		_succeed(player_idx, spirit)
	else:
		spirit["catch_fails"] = int(spirit.get("catch_fails", 0)) + 1
		EventBus.catch_failed.emit(player_idx, spirit)

func _succeed(player_idx: int, spirit: Dictionary) -> void:
	var p: PlayerData = GameState.players[player_idx]
	for k in ["catch_fails", "_spooked", "_lured"]:
		spirit.erase(k)
	spirit["current_hp"] = spirit["hp"]
	spirit["stars"] = 0
	# Full team → the catch goes to the Spirit Box (withdraw at any town).
	if p.team.size() < Balance.TEAM_MAX:
		p.team.append(spirit)
	else:
		p.pc.append(spirit)
	# SpiritsProgressionSystem subscribes and handles duplicates / stars
	EventBus.catch_succeeded.emit(player_idx, spirit)
	GameState.award_points(player_idx, Balance.PTS_CATCH)
	p.inventory.gold += Balance.GOLD_CATCH
	EventBus.log_entry.emit(player_idx, "%s caught %s! +%d gold." % [
		p.player_name, spirit.get("name", "?"), Balance.GOLD_CATCH], "#f0c36a")
	# the hunt levels your lead up (a duplicate catch already gave its star)
	var lead: Dictionary = p.lead()
	if not lead.is_empty() and lead != spirit:
		var stars: float = Balance.CATCH_LEAD_STARS_STRONG if int(spirit.get("stage", 1)) >= 2 else Balance.CATCH_LEAD_STARS
		SpiritsProgressionSystem.award_stars(player_idx, lead, stars)
