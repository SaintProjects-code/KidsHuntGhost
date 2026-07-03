class_name StatusManager

# Returns true if the spirit can act this round
static func tick(spirit: Dictionary) -> bool:
	match spirit.get("status", &""):
		&"burn":
			if randf() < 0.5:
				spirit["current_hp"] -= 20
			return true
		&"poison":
			var stacks: int = spirit.get("poison_stacks", 1)
			spirit["current_hp"] -= stacks * 5
			spirit["poison_stacks"] = stacks + 1
			return true
		&"sleep", &"freeze":
			spirit["status_rounds"] = spirit.get("status_rounds", 1) - 1
			if spirit["status_rounds"] <= 0:
				spirit.erase("status")
			return false  # skip round
		&"stun":
			spirit.erase("status")
			return false
		&"confusion":
			if randf() < 0.25:
				spirit["current_hp"] -= 10
				return false
	return true

static func apply(spirit: Dictionary, status: StringName) -> void:
	spirit["status"] = status
	if status in [&"sleep", &"freeze"]:
		spirit["status_rounds"] = randi_range(1, 2)
