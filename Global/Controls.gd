class_name Controls
## Shared-keyboard layout: up to 4 players play the minigames on ONE keyboard,
## each with their own cluster. Every cluster has an ACTION key (jump / snap /
## scare / float) plus LEFT / MIDDLE / RIGHT for the maze's three paths.
##
##   P1  W  + A S D          P3  ↑        + ← ↓ →
##   P2  I  + J K L          P4  Num 8    + Num 4 5 6
##
## Menus also take keys: 1–9 pick the matching button, Space/Enter confirms.

const LAYOUT := [
	{"action": KEY_W,    "left": KEY_A,    "middle": KEY_S,    "right": KEY_D,
		"names": ["W", "A", "S", "D"]},
	{"action": KEY_I,    "left": KEY_J,    "middle": KEY_K,    "right": KEY_L,
		"names": ["I", "J", "K", "L"]},
	{"action": KEY_UP,   "left": KEY_LEFT, "middle": KEY_DOWN, "right": KEY_RIGHT,
		"names": ["↑", "←", "↓", "→"]},
	{"action": KEY_KP_8, "left": KEY_KP_4, "middle": KEY_KP_5, "right": KEY_KP_6,
		"names": ["Num8", "Num4", "Num5", "Num6"]},
]

# The keyboard slot a player plays on: humans are numbered in seat order, so
# with CPUs in the game the humans still get P1, P2, … keys.
static func slot_of(player_idx: int) -> int:
	var slot := 0
	for i in GameState.players.size():
		if i == player_idx:
			return slot if slot < LAYOUT.size() else -1
		if not GameState.players[i].is_cpu:
			slot += 1
	return -1

static func key(slot: int, action: String) -> int:
	if slot < 0 or slot >= LAYOUT.size():
		return KEY_NONE
	return int(LAYOUT[slot].get(action, KEY_NONE))

# "W" / "A" … for on-screen hints.
static func key_name(slot: int, action: String) -> String:
	if slot < 0 or slot >= LAYOUT.size():
		return "?"
	var i: int = ["action", "left", "middle", "right"].find(action)
	return String(LAYOUT[slot]["names"][maxi(0, i)])

# Which (slot, action) a key event belongs to, or [] if none.
static func lookup(ev: InputEvent) -> Array:
	if not (ev is InputEventKey) or not ev.pressed or ev.echo:
		return []
	for slot in LAYOUT.size():
		for action in ["action", "left", "middle", "right"]:
			if ev.keycode == LAYOUT[slot][action] or ev.physical_keycode == LAYOUT[slot][action]:
				return [slot, action]
	return []

static func is_held(slot: int, action: String) -> bool:
	var k := key(slot, action)
	return k != KEY_NONE and (Input.is_key_pressed(k) or Input.is_physical_key_pressed(k))

# Number key 1–9 → 0-based index, else -1 (menus).
static func number_pressed(ev: InputEvent) -> int:
	if not (ev is InputEventKey) or not ev.pressed or ev.echo:
		return -1
	var k: int = ev.keycode
	if k >= KEY_1 and k <= KEY_9:
		return k - KEY_1
	if k >= KEY_KP_1 and k <= KEY_KP_9:
		return k - KEY_KP_1
	return -1

static func confirm_pressed(ev: InputEvent) -> bool:
	return ev is InputEventKey and ev.pressed and not ev.echo \
		and (ev.keycode == KEY_SPACE or ev.keycode == KEY_ENTER or ev.keycode == KEY_KP_ENTER)
