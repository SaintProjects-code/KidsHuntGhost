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
