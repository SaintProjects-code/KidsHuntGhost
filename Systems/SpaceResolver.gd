extends Node
## Autoloaded. Listens for `space_landed(player_idx, type)` (emitted by the board
## when a token finishes its move on a tile) and dispatches by type.
##
## The actual outcomes (catch/battle, event draws, item draws, competitions) are
## not built yet — these handlers are no-op hook points. For now the only visible
## effect of landing is the window the board pops naming the tile.

var _handlers: Dictionary

func _ready() -> void:
	_handlers = {
		&"PKMN_PINK":   _on_pkmn,
		&"PKMN_GREEN":  _on_pkmn,
		&"PKMN_RED":    _on_pkmn,
		&"EVENT":       _on_event,
		&"ITEM":        _on_item,
		&"COMPETITION": _on_competition,
	}
	EventBus.space_landed.connect(_on_space_landed)

func _on_space_landed(player_idx: int, space_type: StringName) -> void:
	if _handlers.has(space_type):
		_handlers[space_type].call(player_idx)

# A spirit (PKMN) tile — later: choose to catch or battle the wild spirit.
func _on_pkmn(_player_idx: int) -> void:
	pass

# A mystery event tile.
func _on_event(_player_idx: int) -> void:
	pass

# A mystery item tile.
func _on_item(_player_idx: int) -> void:
	pass

# A competition tile.
func _on_competition(_player_idx: int) -> void:
	pass
