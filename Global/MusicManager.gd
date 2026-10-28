extends Node
## Autoloaded as `MusicManager`. Plays ONE looping background track at a time:
##
##   • MENU   — the main menu and the setup screen
##   • MAP    — the board: rolling, moving, tiles, events, shops, cities
##   • BATTLE — team select and the battle screen itself
##
## Scenes set the "context" track (menu or map) from their _ready. The battle
## track is automatic: this listens to UIManager and takes over whenever a
## battle window is the open menu, then hands back to the context track when it
## closes. Nothing else needs to know about music.

enum Track { NONE, MENU, MAP, BATTLE }

const TRACKS := {
	Track.MENU: "res://Assets/music/menuMusic.mp3",
	Track.MAP: "res://Assets/music/MapMusic.mp3",
	Track.BATTLE: "res://Assets/music/BattleMusic.mp3",
}

# The windows that own the battle track, by script path (both are built in code
# and opened via UIManager, so there's no scene node to match on).
const BATTLE_WINDOWS := [
	"res://Scenes/UI/BattleTeamSelect.gd",
	"res://Scenes/UI/Battle/BattleScreen.gd",
]

var _player: AudioStreamPlayer
var _current: Track = Track.NONE
var _context: Track = Track.NONE   # what plays when no battle window is up

func _ready() -> void:
	# Events and battles hold the tree paused — the music must not pause with it.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = AudioStreamPlayer.new()
	_player.process_mode = Node.PROCESS_MODE_ALWAYS
	_player.bus = &"Master"   # the settings sliders drive the Master bus
	add_child(_player)
	UIManager.menu_opened.connect(_on_menu_opened)
	UIManager.menu_closed.connect(_on_menu_closed)

# ---------------- Scene hooks ----------------

func play_menu() -> void:
	_set_context(Track.MENU)

func play_map() -> void:
	_set_context(Track.MAP)

func _set_context(track: Track) -> void:
	_context = track
	if not _battle_window_open():
		_play(track)

# ---------------- Battle takeover ----------------

func _on_menu_opened(menu: Control) -> void:
	if _is_battle_window(menu):
		_play(Track.BATTLE)

func _on_menu_closed(_menu: Control) -> void:
	# UIManager.open() closes the old menu before showing the new one, so the
	# team-select → battle handoff has a moment with nothing open. Re-check at
	# the end of the frame rather than cutting back to the map in between.
	_recheck.call_deferred()

func _recheck() -> void:
	_play(Track.BATTLE if _battle_window_open() else _context)

func _battle_window_open() -> bool:
	return UIManager.is_open() and _is_battle_window(UIManager.current())

func _is_battle_window(menu: Node) -> bool:
	if menu == null:
		return false
	var script: Script = menu.get_script() as Script
	return script != null and BATTLE_WINDOWS.has(script.resource_path)

# ---------------- Playback ----------------

func _play(track: Track) -> void:
	if track == _current and _player.playing:
		return
	_current = track
	if not TRACKS.has(track):
		_player.stop()
		return
	var stream: AudioStream = load(TRACKS[track])
	# The mp3s import with loop=false; these are background tracks, so loop them.
	if stream is AudioStreamMP3:
		stream.loop = true
	_player.stream = stream
	_player.play()
