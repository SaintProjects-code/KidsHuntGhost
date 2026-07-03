class_name DamageCalculator
## Reference damage model:
##   damage = ATK × 25 × type_mult,  then reduced by DEF × 10% per point.
##   type_mult: 2.0 super-effective, 0.5 resisted, 1.0 neutral (SpiritsData chart).
##   Each star adds +1 effective ATK tier.

static func calculate(
		attacker: Dictionary,
		defender: Dictionary,
		terrain_mult: float = 1.0,
		ability_mult: float = 1.0,
		item_mult: float = 1.0) -> int:
	var atk: float = float(attacker.get("atk", 0) + attacker.get("stars", 0))
	var t_mult: float = SpiritsData.type_mult(attacker.get("type", ""), defender.get("type", ""))
	var raw: float = atk * 25.0 * t_mult * terrain_mult * ability_mult * item_mult
	var def_reduction: float = minf(0.9, float(defender.get("def", 0)) * 0.10)
	var dmg: float = raw * (1.0 - def_reduction)
	return maxi(1, int(round(dmg)))
