class_name DamageCalculator
## Reference damage model:
##   damage = ATK × DMG_PER_ATK × type_mult,  then reduced by DEF × 10% per point.
##   type_mult: 1.5 super-effective, 0.5 resisted, 1.0 neutral (SpiritsData chart).
##   Each star adds +1 effective ATK tier.

# Damage each point of (effective) ATK is worth. Kept low so hits chip rather
# than one-shot — a 5-ATK neutral hit deals ~75, not ~125.
const DMG_PER_ATK := 15.0

static func calculate(
		attacker: Dictionary,
		defender: Dictionary,
		terrain_mult: float = 1.0,
		ability_mult: float = 1.0,
		item_mult: float = 1.0) -> int:
	var atk: float = float(attacker.get("atk", 0) + attacker.get("stars", 0))
	# Dual-type defenders take the combined effectiveness of BOTH their types.
	var t_mult: float = SpiritsData.effectiveness(String(attacker.get("type", "")), defender)
	var raw: float = atk * DMG_PER_ATK * t_mult * terrain_mult * ability_mult * item_mult
	var def_reduction: float = minf(0.9, float(defender.get("def", 0)) * 0.10)
	var dmg: float = raw * (1.0 - def_reduction)
	return maxi(1, int(round(dmg)))
