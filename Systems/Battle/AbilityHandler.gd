class_name AbilityHandler

# Add new abilities here — nothing else needs to change
static var ABILITIES := {
	"Intimidate": {
		"trigger": &"match_start",
		"fn": func(ctx): ctx.defender_lead["atk"] -= 15
	},
	"Speed Boost": {
		"trigger": &"turn_start",
		"fn": func(ctx): ctx.user["spd"] += 5
	},
	"Destiny Bond": {
		"trigger": &"on_death",
		"fn": func(ctx): ctx.opponent_active["current_hp"] = 0
	},
	"Regenerator": {
		"trigger": &"on_swap",
		"fn": func(ctx): ctx.user["current_hp"] = mini(
			ctx.user["hp"], ctx.user["current_hp"] + ctx.user["hp"] / 3)
	},
	"Thick Fat": {
		"trigger": &"passive",
		"fn": func(ctx): ctx.damage_mult *= 0.8
	},
}

static func fire(trigger: StringName, context: Dictionary, spirit: Dictionary) -> void:
	var entry: Dictionary = ABILITIES.get(spirit.get("ability", ""), {})
	if not entry.is_empty() and entry["trigger"] == trigger:
		context["user"] = spirit
		entry["fn"].call(context)
