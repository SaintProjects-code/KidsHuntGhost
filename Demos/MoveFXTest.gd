extends Control
## DEV TEST ONLY: plays every charged move's effect in the 3D arena, one after
## another, and prints the frame of each impact (for screenshots).

const ArenaScript := preload("res://Scenes/UI/Battle/BattleArena.gd")
const MOVES := ["ember_burst", "inferno", "soak", "mind_blast", "vine_drain", "chain_bolt", "thunderclap",
	"heat_wave", "curse", "spore_cloud", "hex_sleep", "whirlpool", "dread", "haymaker", "spark_rush",
	"shadow_sneak", "tidal_guard", "iron_guard", "combo_strike", "calm_mind", "bloom"]

# the bits of BattleView the arena reads
var _team: Array = []
var _opp: Array = []
var _active := 0
var _opp_active := 0
var _speed := 1.0
var _over := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.14)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	for n in ["Cinderwisp", "Mossprig", "Zapkin"]:
		_team.append(_mon(n))
	for n in ["Puddleboo", "Wispy", "Dreamwisp"]:
		_opp.append(_mon(n))
	var arena = ArenaScript.new()
	arena.view = self
	arena.position = Vector2(120, 100)
	add_child(arena)
	arena.begin([Color("ff7a3a"), Color("4aa3df")], ["Ember", "Brooke"])
	await get_tree().create_timer(1.5).timeout
	for key in MOVES:
		var me: Dictionary = _team[0]
		var foe: Dictionary = _opp[0]
		me["move"] = key
		me["hp"] = 999
		me["current_hp"] = 999
		foe["current_hp"] = 999
		foe["hp"] = 999
		arena.special(me, String(SpiritsData.move_of(key)["name"]))
		await get_tree().create_timer(0.35).timeout
		var power := float(SpiritsData.move_of(key).get("power", 1.0))
		arena.attack(me)
		await get_tree().create_timer(0.3).timeout
		if power > 0.0:
			arena.hurt(foe)
		print("IMPACT ", key, " ", Engine.get_process_frames())
		await get_tree().create_timer(1.5).timeout
	get_tree().quit()

func _mon(n: String) -> Dictionary:
	var m := SpiritsData.get_spirit(n)
	m["current_hp"] = m["hp"]
	for k in ["atk", "def", "spd"]:
		m["_base_" + k] = m[k]
	return m
