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
	EventBus.catch_succeeded.connect(func(i, s): _add(i, "caught %s!" % s.get("name", "?"), C_GOOD))
	EventBus.catch_failed.connect(func(i, s): _add(i, "%s broke free!" % s.get("name", "?"), C_BAD))
	EventBus.badge_earned.connect(func(i, gym): _add(i, "earned a badge at %s!" % gym, C_GOLD))
	EventBus.points_awarded.connect(func(i, n): _add(i, "+%d point%s" % [n, "s" if n > 1 else ""], C_GOLD))
	EventBus.spirit_evolved.connect(func(i, s): _add(i, "%s evolved!" % s.get("name", "?"), C_EVO))
	EventBus.star_awarded.connect(func(i, s): _add(i, "%s gained a star ★" % s.get("name", "?"), C_EVO))
	EventBus.game_won.connect(func(i): _add(i, "WINS THE GAME! 🏆", C_GOLD))
	EventBus.log_entry.connect(_add)

func present() -> void:
	pass   # the log is always up to date; nothing to rebuild

# ── entry builders ────────────────────────────────────────────────────────────

func _on_turn_started(i: int) -> void:
	var p := _player(i)
	if p == null:
		return
	_log.append_text("\n[color=%s]── %s's turn ──[/color]\n" % [p.color.to_html(false), p.player_name])

func _on_dice_rolled(result: int) -> void:
	_add(GameState.current_player_index, "rolled a %d" % result, C_DICE)

func _on_space_landed(i: int, type: StringName) -> void:
	var pretty := String(type).replace("PKMN_", "SP ").capitalize()
	_add(i, "landed on %s" % pretty, C_TILE)

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
