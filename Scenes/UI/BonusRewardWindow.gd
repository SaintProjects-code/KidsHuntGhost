extends MenuWindow
## The evolution / max-star "bonus reward" pop-up. A spirit climbs a per-spirit
## bonus level (1 → 2 → 3); each level grants a fixed reward, shown here:
##   1) a brand-new ability that REPLACES the old one
##   2) +2 to a stat the player chooses
##   3) a SECOND ability that stacks on top (spirits hold at most two)
## Ability rewards just announce + Continue; the stat reward waits for a pick.

signal chose_ability(key: String) # ability rewards: player picked one of the options
signal chose_stat(stat: String)   # stat reward: player picked a stat

const STAT_LABELS := {"hp": "HP", "atk": "ATK", "def": "DEF", "spd": "SPD"}

# lvl 1 (replace) or lvl 3 (add): the player chooses from `options` (ability
# keys), each shown with its description. `replaced` is the old key, or "".
func present_ability(spirit: Dictionary, lvl: int, options: Array, replaced: String) -> void:
	var vb := _build(spirit, lvl)
	# Replace (1st bonus) lets you opt out and keep your current ability; the
	# add (3rd bonus) is purely additive — you always gain a new second ability.
	var can_keep: bool = replaced != ""
	if can_keep:
		var old: Dictionary = SpiritsData.ability_of(replaced)
		vb.add_child(_subtitle("Pick a new ability to replace %s" % old.get("name", replaced)))
	else:
		vb.add_child(_subtitle("Pick a new second ability for %s" % spirit.get("name", "?")))
	for key in options:
		vb.add_child(_ability_option(String(key)))
	if can_keep:
		# "" = keep the current ability unchanged.
		vb.add_child(_button("Keep %s" % SpiritsData.ability_of(replaced).get("name", replaced),
			_pick_ability.bind(""), 34))

func present_stat(spirit: Dictionary, lvl: int) -> void:
	var vb := _build(spirit, lvl)
	vb.add_child(_subtitle("Choose a stat to raise +2"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	for key in ["hp", "atk", "def", "spd"]:
		var cur: int = _stat_now(spirit, key)
		var step: int = 60 if key == "hp" else 2
		var b := _button("%s   %d → %d" % [STAT_LABELS[key], cur, cur + step], _pick.bind(key))
		b.custom_minimum_size = Vector2(150, 46)
		grid.add_child(b)
	vb.add_child(grid)

func _pick(stat: String) -> void:
	chose_stat.emit(stat)

# ── layout helpers ────────────────────────────────────────────────────────────

func _build(spirit: Dictionary, lvl: int) -> VBoxContainer:
	# Rebuild fresh each time so re-presenting the window is clean.
	for c in get_children():
		c.queue_free()
	panel = null
	var vb := _init_window(380)
	vb.add_child(_title_label("★  Bonus Reward  %d  ★" % lvl, 26))
	var spr := TextureRect.new()
	spr.texture = SpiritsData.sprite_tex(String(spirit.get("name", "")), "front")
	spr.custom_minimum_size = Vector2(72, 72)
	spr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	spr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(spr)
	return vb

func _subtitle(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 18)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(340, 0)
	return l

# One clickable ability choice: a name button with its description underneath.
func _ability_option(key: String) -> Control:
	var info: Dictionary = SpiritsData.ability_of(key)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var b := _button(String(info.get("name", key)), _pick_ability.bind(key), 38)
	b.add_theme_font_size_override("font_size", 18)
	box.add_child(b)
	var d := Label.new()
	d.text = String(info.get("desc", ""))
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	d.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	d.add_theme_font_size_override("font_size", 13)
	d.custom_minimum_size = Vector2(360, 0)
	box.add_child(d)
	return box

func _pick_ability(key: String) -> void:
	chose_ability.emit(key)

func _stat_now(spirit: Dictionary, key: String) -> int:
	if key == "hp":
		return int(spirit.get("hp", 60))
	return int(spirit.get(key, 1))
