extends MenuWindow
## Game log (LOG button): a running, colour-coded record of every turn.
## Player names show in their token colour; event kinds have their own
## colours (green = catches, red = mishaps, gold = points/badges, …).
## Listens to EventBus from game start, so nothing is missed even while
## the window is closed. present(); emits closed().

signal closed()

const C_DICE := "#cfd8ff"      # rolls / movement
const C_TILE := "#a9b0c4"      # landed-on info
const C_GOOD := "#9fff9f"      # catches, heals, wins
const C_BAD := "#ff9f9f"       # failures, damage
const C_GOLD := "#ffd24d"      # points, badges, gold
const C_EVO := "#d3a8ff"       # evolutions / stars

var _log: RichTextLabel

func _ready() -> void:
	var col := _init_window(640, 520)
	col.add_child(_title_label("📜 Game Log", 26))
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.add_theme_font_size_override("normal_font_size", 16)
	col.add_child(_log)
	col.add_child(_button("Close", func(): closed.emit()))
	hide()

	EventBus.turn_started.connect(_on_turn_started)
	EventBus.dice_rolled.connect(_on_dice_rolled)
	EventBus.space_landed.connect(_on_space_landed)
	EventBus.catch_succeeded.connect(_on_caught)
	EventBus.catch_failed.connect(_on_escaped)
	EventBus.badge_earned.connect(_on_badge)
	EventBus.points_awarded.connect(_on_points)
	EventBus.spirit_evolved.connect(_on_evolved)
	EventBus.star_awarded.connect(_on_star)
	EventBus.game_won.connect(_on_won)
	EventBus.log_entry.connect(_add)

# ── entry builders ────────────────────────────────────────────────────────────
# (plain methods, not lambdas: EventBus outlives this window, and a lambda
# left connected to it after the board is freed can crash the engine)

func _on_dice_rolled(total: int, _faces: Array) -> void:
	_add(GameState.current_player_index, "rolled a %d" % total, C_DICE)

func _on_caught(i: int, s: Dictionary) -> void:
	_add(i, "caught %s!" % s.get("name", "?"), C_GOOD)

func _on_escaped(i: int, s: Dictionary) -> void:
	_add(i, "%s broke free!" % s.get("name", "?"), C_BAD)

func _on_badge(i: int, gym: String) -> void:
	_add(i, "earned a badge at %s!" % gym, C_GOLD)

func _on_points(i: int, n: int) -> void:
	_add(i, "+%d point%s" % [n, "s" if n > 1 else ""], C_GOLD)

func _on_evolved(i: int, s: Dictionary) -> void:
	_add(i, "%s evolved!" % s.get("name", "?"), C_EVO)

func _on_star(i: int, s: Dictionary) -> void:
	_add(i, "%s gained a star ★" % s.get("name", "?"), C_EVO)

func _on_won(i: int) -> void:
	_add(i, "WINS THE GAME! 🏆", C_GOLD)

func _on_turn_started(i: int) -> void:
	var p := _player(i)
	if p == null:
		return
	_log.append_text("\n[color=%s]── %s's turn ──[/color]\n" % [p.color.to_html(false), p.player_name])

func _on_space_landed(i: int, type: StringName) -> void:
	_add(i, "landed on %s" % String(type).capitalize(), C_TILE)

# One log line: colour-tagged player name + coloured message.
func _add(i: int, text: String, color: String) -> void:
	var p := _player(i)
	if p == null:
		return
	_log.append_text("[color=%s]%s[/color]  [color=%s]%s[/color]\n" % [
		p.color.to_html(false), p.player_name, color, text])

func _player(i: int) -> PlayerData:
	if i < 0 or i >= GameState.players.size():
		return null
	return GameState.players[i]
