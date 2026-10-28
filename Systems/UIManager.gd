extends Node
## Autoloaded as `UIManager`. Guarantees only ONE game menu is visible at a time.
##
## Menus are plain Control nodes living in the board scene. To show one:
##     UIManager.open(my_menu)
## It hides whatever was open first. UIManager.close() closes the current one.
## A menu can also tell the manager it closed itself via `notify_closed`.

signal menu_opened(menu: Control)
signal menu_closed(menu: Control)

var _current: Control = null

func open(menu: Control) -> void:
	if menu == null or menu == _current:
		return
	close()
	_current = menu
	menu.show()
	if menu.has_method("on_opened"):
		menu.on_opened()
	emit_signal("menu_opened", menu)

func close() -> void:
	if _current != null and is_instance_valid(_current):
		var m: Control = _current
		_current = null
		m.hide()
		if m.has_method("on_closed"):
			m.on_closed()
		emit_signal("menu_closed", m)
	else:
		_current = null

# A menu that hid itself (e.g. its own Close button) calls this to stay in sync.
func notify_closed(menu: Control) -> void:
	if menu == _current:
		_current = null
		emit_signal("menu_closed", menu)

func is_open() -> bool:
	return _current != null and is_instance_valid(_current)

func current() -> Control:
	return _current

# ─── Overlay slot ─────────────────────────────────────────────────────────────
# A SECOND, independent slot for the action-button menus (Bag / Team / Log /
# Dev). These layer ABOVE the main flow menu (events, battles) and DON'T close
# it — so a player can open their bag while an event window is up. Only one
# overlay shows at a time; it never touches the pause holds.
var _overlay: Control = null

func open_overlay(menu: Control) -> void:
	if menu == null or menu == _overlay:
		return
	close_overlay()
	_overlay = menu
	menu.show()
	if menu.has_method("on_opened"):
		menu.on_opened()

func close_overlay() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		var m: Control = _overlay
		_overlay = null
		m.hide()
		if m.has_method("on_closed"):
			m.on_closed()
	else:
		_overlay = null

func overlay_open() -> bool:
	return _overlay != null and is_instance_valid(_overlay)

# ─── Event pause ──────────────────────────────────────────────────────────────
# Game flows (encounters, tile events, the win screen) hold the tree paused
# while they run — the HUD timer and board stop, but the event windows and the
# Settings button keep working (they run with process_mode = Always). Holds
# nest (an event inside an event), and Settings layers its own pause on top:
# the tree only unpauses when every hold is gone.
var _pause_holds := 0

func hold_pause() -> void:
	_pause_holds += 1
	get_tree().paused = true

func release_pause() -> void:
	_pause_holds = maxi(0, _pause_holds - 1)
	if _pause_holds == 0:
		get_tree().paused = false

func pause_held() -> bool:
	return _pause_holds > 0

# Leaving the board entirely (main menu): drop any leftover holds.
func reset_pause() -> void:
	_pause_holds = 0
	get_tree().paused = false
