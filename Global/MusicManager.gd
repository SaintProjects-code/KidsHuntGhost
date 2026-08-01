extends Node
## Autoloaded as `MusicManager`. Plays one background context at a time:
##
##   • MENU   — the main menu and the setup screen (single looping track)
##   • MAP    — the board: rolling, moving, tiles, events, shops, cities.
##              A PLAYLIST — cycles through every map song, then repeats.
##   • BATTLE — team select and the battle screen itself (single looping track)
##
## Scenes set the "context" track (menu or map) from their _ready. The battle
## track is automatic: this listens to UIManager and takes over whenever a
## battle window is the open menu, then hands back to the context track when it
## closes. Nothing else needs to know about music.

enum Track { NONE, MENU, MAP, BATTLE }

const TRACKS := {
	Track.MENU: "res://Assets/music/menuMusic.mp3",
	Track.BATTLE: "res://Assets/music/BattleMusic.mp3",
}

# The map track is a PLAYLIST: it plays each song in order, then loops back to
# the top and starts over. Add or reorder songs here — one entry per file.
const MAP_PLAYLIST := [
	"res://Assets/music/MapMusic.mp3",
	"res://Assets/music/MapMusicP5_1.mp3",
	"res://Assets/music/MapMusicP5_2.mp3",
	"res://Assets/music/MapMusicPT_1.mp3",
]

# The windows that own the battle track, by script path (both are built in code
# and opened via UIManager, so there's no scene node to match on).
const BATTLE_WINDOWS := [
	"res://Scenes/UI/BattleTeamSelect.gd",
	"res://Scenes/UI/BattleScreen.gd",
]

var _player: AudioStreamPlayer
var _current: Track = Track.NONE
var _context: Track = Track.NONE   # what plays when no battle window is up
var _map_index: int = 0            # which MAP_PLAYLIST song is playing

func _ready() -> void:
	# Start the game quiet: the Master bus (which every track and the volume
	# sliders drive) begins at 5%. Players can raise it from Setup/Pause.
	AudioServer.set_bus_volume_db(0, linear_to_db(0.05))
	# Events and battles hold the tree paused — the music must not pause with it.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = AudioStreamPlayer.new()
	_player.process_mode = Node.PROCESS_MODE_ALWAYS
	_player.bus = &"Master"   # the settings sliders drive the Master bus
	add_child(_player)
	# When a non-looping map song ends, roll on to the next one in the playlist.
	_player.finished.connect(_on_track_finished)
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
	# The map is a playlist that cycles through every song, so it's handled on
	# its own; it resumes at whichever song it left off on.
	if track == Track.MAP:
		_play_map(_map_index)
		return
	if not TRACKS.has(track):
		_player.stop()
		return
	var stream: AudioStream = load(TRACKS[track])
	# The mp3s import with loop=false; menu/battle are single background tracks,
	# so loop them.
	if stream is AudioStreamMP3:
		stream.loop = true
	_player.stream = stream
	_player.play()

# Play one song from the map playlist. Songs must NOT loop — they need to end so
# _on_track_finished can advance to the next (and wrap back to the top).
func _play_map(index: int) -> void:
	if MAP_PLAYLIST.is_empty():
		_player.stop()
		return
	_map_index = index % MAP_PLAYLIST.size()
	var stream: AudioStream = load(MAP_PLAYLIST[_map_index])
	if stream is AudioStreamMP3:
		stream.loop = false
	_player.stream = stream
	_player.play()

# A track ended on its own. Only the map playlist advances — menu and battle
# tracks loop, so they never reach here.
func _on_track_finished() -> void:
	if _current == Track.MAP:
		_play_map(_map_index + 1)
