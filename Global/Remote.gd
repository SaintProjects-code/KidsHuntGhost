extends Node
## Autoloaded as `Remote`. 📱 Phone play, Jackbox style: this game is the HOST.
## connect_to(address) hosts a room (phones join it with a 4-letter ROOM CODE):
##   • this computer's IP → start_local(ip): the game runs its own little phone
##     server (LocalServer); phones on the same network open http://ip:port
##   • a website / ws(s):// address → start(url): an online relay server
##     (server/server.js), for playing over the internet
##
## Each phone is tied to one player (PlayerData.remote_id). Several times a
## second the host builds every phone's VIEW and sends it when it changed:
##   • "buttons" — the player's turn (or a window that belongs to them): every
##     visible, enabled button of the top window / board is MIRRORED onto the
##     phone; a tap presses the real button here
##   • "pad"     — a competition minigame is running: ACTION + LEFT/MIDDLE/RIGHT,
##     injected as that player's shared-keyboard keys (see Controls)
##   • idle menu — someone else's turn: who's playing, plus 🃏 your hand (play
##     the field cards in CardsData.OFF_TURN) and 👻 your team (stats, reorder)
## A window can supply its own phone view with remote_view(player_idx) (the
## competition pick step does, so everyone picks their own spirit at once),
## and a spectator section with spectator_view(player_idx) (battle voting).
## The setup screen gives each joining phone a player card (see SetupScreen).

signal room_changed(code: String)
signal phones_changed()
signal phone_pressed(id: String, index: int)   # for scenes with their own views (setup)

const CFG_PATH := "user://remote.cfg"
const DEFAULT_URL := "ws://localhost:8080/ws"
const VIEW_INTERVAL := 0.15
# board chrome a phone never needs
const SKIP_BUTTONS := ["SettingsButton", "DevButton", "LogButton"]
# always at the bottom of the phone screen, where a thumb finds them
const BOTTOM_BUTTONS := ["RollButton", "EndTurnButton"]
# View Map mode: phone arrows → held directions (PauseMenu.phone_hold)
const MAP_HOLDS := [{"k": "up", "label": "▲"}, {"k": "left", "label": "◀"}, {"k": "right", "label": "▶"},
	{"k": "down", "label": "▼"}, {"k": "zoom_in", "label": "＋ Zoom in"}, {"k": "zoom_out", "label": "－ Zoom out"}]

var url := DEFAULT_URL
var code := ""                   # room code, "" until the server gives one
var phones := {}                 # id -> {"name": String, "online": bool}
var lobby_view: Callable = Callable()   # set by the setup screen: (id) -> view Dictionary

var _ws: WebSocketPeer
var _local: LocalServer          # set while hosting on this computer
var _local_error := ""
var _local_ip := ""              # the address the host typed for this computer
var _connect_t := 0.0            # seconds spent trying to reach the relay
var _connect_error := ""         # why the relay can't be reached ("" = fine so far)
const CONNECT_TIMEOUT := 8.0
var _want := false               # stay connected (reconnect on drops)
var _was_open := false
var _retry_t := 0.0
var _view_t := 0.0
var _sent := {}                  # id -> last view JSON sent
var _actions := {}               # id -> Array of Callables behind the last view's buttons
var _rev := {}                   # id -> view revision
var _held := {}                  # id -> {pad key: true} currently held (released on drop)
var _page := {}                  # id -> idle-menu page {"p": "main"|"hand"|"card"|"team"|"mon", "key", "i"}
var _img_cache := {}             # "name@px" -> data: URL of a spirit sprite

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # windows pause the board; phones must keep working
	var cfg := ConfigFile.new()
	if cfg.load(CFG_PATH) == OK:
		url = String(cfg.get_value("remote", "url", DEFAULT_URL))

func is_on() -> bool:
	if _local:
		return code != ""
	return _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN and code != ""

func is_local() -> bool:
	return _local != null

# Is this player seat being played from a phone that's connected right now?
func has_phone(idx: int) -> bool:
	if idx < 0 or idx >= GameState.players.size():
		return false
	var id: String = GameState.players[idx].remote_id
	return id != "" and phones.has(id) and phones[id]["online"]

func status_text() -> String:
	if _local_error != "":
		return _local_error
	if _connect_error != "":
		return _connect_error
	if _local:
		return "room %s" % code
	if _ws == null:
		return "off"
	match _ws.get_ready_state():
		WebSocketPeer.STATE_CONNECTING: return "connecting…"
		WebSocketPeer.STATE_OPEN: return "room %s" % code if code != "" else "joining…"
	return "reconnecting…" if _want else "off"

# The Connect button: decide from the address what kind of room to host.
#   ""/localhost/one of this computer's IPs → host here
#   another bare IP → an error naming this computer's real IPs
#   anything else → an online relay (bare domains get wss://<domain>/ws)
func connect_to(address: String) -> void:
	var a := address.strip_edges().trim_suffix("/")
	var mine := LocalServer.lan_ips()
	var host := a.trim_prefix("http://").get_slice("/", 0).get_slice(":", 0)
	if a == "" or host in ["localhost", "127.0.0.1"] or mine.has(host):
		start_local(host if mine.has(host) else "")
		return
	if host.is_valid_ip_address() and not a.begins_with("ws"):
		stop()
		_local_error = "%s isn't this computer. Use one of: %s" % [host, ", ".join(mine) if not mine.is_empty() else "(no network found)"]
		room_changed.emit("")
		return
	if a.begins_with("https://"):
		a = "wss://" + a.trim_prefix("https://")
	elif a.begins_with("http://"):
		a = "ws://" + a.trim_prefix("http://")
	elif not a.begins_with("ws"):
		a = "wss://" + a
	if not a.ends_with("/ws"):
		a += "/ws"
	start(a)

# Host on this computer: the game serves the phone page itself.
func start_local(ip := "") -> void:
	stop()
	_local_ip = ip
	_local = LocalServer.new(_on_server)
	if not _local.start():
		_local_error = _local.error
		_local = null
		room_changed.emit("")

# Host through an online relay server (or restart with a new address).
func start(server_url: String) -> void:
	stop()
	url = server_url.strip_edges()
	var cfg := ConfigFile.new()
	cfg.set_value("remote", "url", url)
	cfg.save(CFG_PATH)
	_want = true
	_open()

func stop() -> void:
	_want = false
	_local_error = ""
	_connect_error = ""
	_connect_t = 0.0
	if _local:
		_local.stop()
		_local = null
	if _ws:
		_ws.close()
	_ws = null
	code = ""
	phones.clear()
	room_changed.emit("")
	phones_changed.emit()

# The web address phones open (the http(s) twin of the websocket url, or this
# computer's home-network address when hosting locally).
func phone_url() -> String:
	if _local:
		if _local_ip != "":
			return "http://%s:%d" % [_local_ip, _local.http_port]
		var urls := LocalServer.lan_urls(_local.http_port)
		return urls[0] if not urls.is_empty() else "(no network found)"
	var u := url.replace("wss://", "https://").replace("ws://", "http://").trim_suffix("/ws")
	# a relay on this computer: phones can't open "localhost", give them our LAN address
	for host in ["localhost", "127.0.0.1"]:
		if u.contains("//" + host):
			var lan := LocalServer.lan_ips()
			if not lan.is_empty():
				u = u.replace("//" + host, "//" + lan[0])
	return u

# Other addresses of this computer, in case the first one doesn't work.
func other_urls() -> Array:
	if not _local:
		return []
	return LocalServer.lan_urls(_local.http_port).filter(func(u): return u != phone_url())

# Diagnostics for the TV: did any phone's browser reach us yet?
func local_stats() -> Dictionary:
	if not _local:
		return {}
	return {"loads": _local.page_loads, "visitor": _local.last_visitor, "https": _local.https_tries}

func _open() -> void:
	_ws = WebSocketPeer.new()
	_was_open = false
	if _ws.connect_to_url(url) != OK:
		_retry_t = 3.0

func _process(delta: float) -> void:
	if _local:
		_local.poll(delta)
		_view_t -= delta
		if _view_t <= 0.0:
			_view_t = VIEW_INTERVAL
			_push_views()
		return
	if _ws == null:
		return
	_ws.poll()
	var st := _ws.get_ready_state()
	if st != WebSocketPeer.STATE_OPEN and not _was_open and code == "":
		_connect_t += delta
		if _connect_t > CONNECT_TIMEOUT and _connect_error == "":
			_connect_error = "Can't reach %s — is the server running? (Home play: type this computer's IP instead.)" % url
			room_changed.emit("")
	if st == WebSocketPeer.STATE_OPEN:
		_connect_error = ""
		if not _was_open:
			_was_open = true
			_raw({"t": "host", "code": code})   # reclaim our room after a drop
		while _ws.get_available_packet_count() > 0:
			var m = JSON.parse_string(_ws.get_packet().get_string_from_utf8())
			if m is Dictionary:
				_on_server(m)
		_view_t -= delta
		if _view_t <= 0.0:
			_view_t = VIEW_INTERVAL
			_push_views()
	elif st == WebSocketPeer.STATE_CLOSED:
		if _was_open:
			_was_open = false
			for id in phones:
				phones[id]["online"] = false
			phones_changed.emit()
		if _want:
			_retry_t -= delta
			if _retry_t <= 0.0:
				_retry_t = 3.0
				_open()

func _raw(obj: Dictionary) -> void:
	if _local:
		if obj.get("t") == "send":
			_local.send_to(LocalServer.text(obj.get("id")), obj["data"])
		return
	if _ws and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify(obj))

func send_view(id: String, view: Dictionary) -> void:
	_raw({"t": "send", "id": id, "data": {"view": view}})

func _on_server(m: Dictionary) -> void:
	match LocalServer.text(m.get("t")):
		"room":
			code = LocalServer.text(m.get("code"))
			_sent.clear()
			room_changed.emit(code)
		"join":
			var id := LocalServer.text(m.get("id"))
			phones[id] = {"name": LocalServer.text(m.get("name"), "Player"), "online": true}
			_sent.erase(id)
			phones_changed.emit()
		"leave":
			var id := LocalServer.text(m.get("id"))
			if phones.has(id):
				phones[id]["online"] = false
			_release_all(id)
			phones_changed.emit()
		"msg":
			_on_phone(LocalServer.text(m.get("id")), m.get("data", {}))

# ─── phone input ──────────────────────────────────────────────────────────────

func _on_phone(id: String, data) -> void:
	if not (data is Dictionary):
		return
	if data.has("press"):
		if not (data["press"] is float or data["press"] is int):
			return
		var i := int(data["press"])
		var rev = data.get("rev")
		if not (rev is float or rev is int) or int(rev) != int(_rev.get(id, 0)):
			return   # stale: the screen changed since the phone drew it
		var acts: Array = _actions.get(id, [])
		if i >= 0 and i < acts.size():
			(acts[i] as Callable).call()
			_sent.erase(id)   # redraw right away
		else:
			phone_pressed.emit(id, i)
	elif data.has("pad"):
		_pad(id, LocalServer.text(data["pad"]), data.get("down") == true)
	elif data.has("hold"):
		var pm := _pause_menu()
		if pm and player_of(id) == GameState.current_player_index:
			pm.phone_hold(LocalServer.text(data["hold"]), data.get("down") == true)

# A minigame button: press/release that player's shared-keyboard key.
func _pad(id: String, action: String, down: bool) -> void:
	var idx := player_of(id)
	if idx < 0 or not (action in ["action", "left", "middle", "right"]):
		return
	var k := Controls.key(Controls.slot_of(idx), action)
	if k == KEY_NONE:
		return
	if not _held.has(id):
		_held[id] = {}
	if down:
		_held[id][action] = true
	else:
		_held[id].erase(action)
	var ev := InputEventKey.new()
	ev.keycode = k
	ev.physical_keycode = k
	ev.pressed = down
	Input.parse_input_event(ev)

func _release_all(id: String) -> void:
	for action in _held.get(id, {}).keys():
		_pad(id, action, false)
	var pm := _pause_menu()
	if pm and player_of(id) == GameState.current_player_index:
		pm.phone_release()

func player_of(id: String) -> int:
	for i in GameState.players.size():
		if GameState.players[i].remote_id == id:
			return i
	return -1

# ─── views ────────────────────────────────────────────────────────────────────

func _push_views() -> void:
	for id in phones:
		if not phones[id]["online"]:
			continue
		var view: Dictionary = _build_view(id)
		var acts: Array = view.get("_actions", [])
		view.erase("_actions")
		var key := JSON.stringify(view)
		if _sent.get(id, "") == key:
			continue
		_sent[id] = key
		_rev[id] = int(_rev.get(id, 0)) + 1
		_actions[id] = acts
		view["rev"] = _rev[id]
		send_view(id, view)

func _build_view(id: String) -> Dictionary:
	var scene := get_tree().current_scene
	var idx := player_of(id)
	if idx < 0 or scene == null or scene.name != "Board":
		if lobby_view.is_valid():
			return lobby_view.call(id)
		return {"screen": "wait", "text": "Joined! Waiting for the game to start…", "me": {"name": phones[id]["name"]}}
	var p: PlayerData = GameState.players[idx]
	var me := {"name": p.player_name, "color": "#" + p.color.to_html(false), "pts": p.progress.points,
		"gold": p.inventory.gold, "cards": p.inventory.hand.map(func(k): return CardsData.card_name(k))}
	var view := _game_view(scene, idx)
	view["me"] = me
	return view

func _game_view(scene: Node, idx: int) -> Dictionary:
	if GameState.winner_index >= 0:
		return {"screen": "wait", "text": "🏆 %s wins the game!" % GameState.players[GameState.winner_index].player_name}
	# a minigame running → gamepad for every human lane
	var game := _find(get_tree().root, func(n): return n is CompGame and n.is_visible_in_tree() and not n.ended)
	if game != null:
		for lane in game.lanes:
			if lane["idx"] == idx and lane["human"]:
				return {"screen": "pad", "title": "🎮 " + String(game.how_to).left(60), "action": "ACTION"}
		return {"screen": "wait", "text": "Watch the minigame!"}
	var pm := _pause_menu()
	if pm and pm.in_view_mode() and idx == GameState.current_player_index:
		return {"screen": "dpad", "title": "🗺 Map", "lines": ["Hold an arrow to look around the board."],
			"holds": MAP_HOLDS, "buttons": [{"label": "◀ Back to the game", "gold": true}],
			"_actions": [func(): pm.exit_view()]}
	var win := _top_window()
	if win != null:
		if win.has_method("remote_view"):
			var custom: Dictionary = win.remote_view(idx)
			if not custom.is_empty():
				return custom
		var owners: Array = win.remote_owners() if win.has_method("remote_owners") else [_owner_of(win)]
		if owners.has(idx):
			return _mirror(win, idx)
		var extra: Dictionary = win.spectator_view(idx) if win.has_method("spectator_view") else {}
		return _idle_view(idx, extra)
	if idx != GameState.current_player_index:
		return _idle_view(idx, {})
	# the board itself: a choice prompt, a message, or the action bar + hand
	for path in ["BoardUI/Root/ChoicePanel", "BoardUI/Root/EventPanel"]:
		var panel := scene.get_node_or_null(path) as Control
		if panel and panel.visible:
			return _mirror(panel, idx)
	var view := _mirror(scene, idx, false)
	var info := scene.get_node_or_null("BoardUI/Root/InfoLabel") as Label
	view["title"] = "🎲 Your turn!"
	view["lines"] = [info.text] if info and info.text != "" else []
	return view

func _waiting_text() -> String:
	var cur := GameState.current_player_index
	if cur >= 0 and cur < GameState.players.size():
		return "%s's turn…" % GameState.players[cur].player_name
	return "Waiting…"

# The window on top: the highest canvas layer, then the latest in the tree.
func _top_window() -> MenuWindow:
	var best: MenuWindow = null
	var best_layer := -1000
	for w in _find_all(get_tree().root, func(n): return n is MenuWindow and n.is_visible_in_tree()):
		var layer := 0
		var up: Node = w.get_parent()   # the CanvasLayer the window sits on
		while up != null and not (up is CanvasLayer):
			up = up.get_parent()
		if up:
			layer = (up as CanvasLayer).layer
		if layer >= best_layer:
			best_layer = layer
			best = w
	return best

# Whose window this is: windows remember their player as _idx, _player_index
# or _player; anything else belongs to whoever's turn it is.
func _owner_of(win: Node) -> int:
	for prop in ["remote_owner", "_idx", "_player_index"]:
		var v = win.get(prop)
		if v is int and v >= 0:
			return v
	var pl = win.get("_player")
	if pl is PlayerData:
		return GameState.players.find(pl)
	return GameState.current_player_index

# Every visible button under `root`, as phone buttons, plus the window's title
# and text lines. A label in the same ROW as a button becomes that button's
# description (shown under it on the phone) instead of a loose line. Cards
# carry their effect text; cards that can't be used come along greyed out.
func _mirror(root: Node, _idx: int, with_text := true) -> Dictionary:
	var buttons: Array = []
	var actions: Array = []
	var bottom: Array = []   # [entry, action]: Roll / End Turn go last
	var lines: Array = []
	var title := ""
	var nodes := _find_all(root, func(x): return (x is BaseButton or x is Label) and x.is_visible_in_tree())
	var desc_of := {}
	var used := {}
	for n in nodes:
		# a card's own price/note label sits beside it in its little column
		var own_box: bool = n is CardView and n.get_parent().get_children().filter(func(c): return c is BaseButton).size() == 1
		if n is BaseButton and (own_box or (not (n is CardView) and n.get_parent() is HBoxContainer)):
			var parts: Array = []
			for sib in n.get_parent().get_children():
				if sib is Label and sib.is_visible_in_tree() and String(sib.text).strip_edges() != "":
					parts.append(String(sib.text).strip_edges())
					used[sib] = true
			if not parts.is_empty():
				desc_of[n] = " · ".join(parts)
	for n in nodes:
		if n is Label:
			if not with_text or used.has(n):
				continue
			var s := String(n.text).strip_edges()
			if s == "" or n.get_parent() is BaseButton:
				continue
			if title == "":
				title = s.left(300)
			elif lines.size() < 10:
				lines.append(s.left(400))
			continue
		var b := n as BaseButton
		if SKIP_BUTTONS.has(String(b.name)):
			continue
		var entry := _entry_of(b, root)
		if entry.is_empty() or (b.disabled and not entry.has("off")):
			continue
		if desc_of.has(b):
			entry["desc"] = (String(entry["desc"]) + " · " if entry.has("desc") else "") + String(desc_of[b])
		if BOTTOM_BUTTONS.has(String(b.name)):
			bottom.append([entry, press_action(b)])
		else:
			buttons.append(entry)
			actions.append(press_action(b))
	for pair in bottom:
		buttons.append(pair[0])
		actions.append(pair[1])
	if buttons.is_empty():
		return {"screen": "wait", "title": title, "lines": lines, "text": "…"}
	return {"screen": "buttons", "title": title, "lines": lines, "buttons": buttons, "_actions": actions}

# One phone button for a real button. Cards: name (+ price), effect text,
# "card": true (the phone shows the text on the first tap, uses it on the
# second) and "off" with a reason when it can't be used here.
func _entry_of(b: BaseButton, root: Node) -> Dictionary:
	if b is CardView:
		var key := String(b.key)
		if key == "":
			return {}
		var c := CardsData.card(key)
		var label := CardsData.card_name(key)
		if b.has_meta("price"):
			label += "  — %dg" % int(b.get_meta("price"))
		if b.armed:
			label += "  ✓"
		var e := {"label": label, "desc": String(c.get("desc", "")), "card": true}
		var off := ""
		if b.disabled:
			off = String(b.get_meta("off_reason", "Can't use this right now"))
		elif root.name == "Board":
			match String(c.get("kind", "")):
				"tactic": off = "Play this in a battle"
				"capture": off = "Use it when catching a ghost"
		if off != "":
			e["off"] = off
		return e
	var s := _label_of(b)
	if s == "":
		return {}
	var e := {"label": s, "gold": "Roll" in s or "Catch" in s or s.begins_with("End Turn")}
	var tip := String(b.tooltip_text).strip_edges()
	if tip != "" and not tip.begins_with(s):
		e["desc"] = tip.left(300)
	return e

func _label_of(b: BaseButton) -> String:
	if b is CardView:
		var key := String(b.key)
		return ("🃏 " + CardsData.card_name(key) + (" ✓" if b.armed else "")) if key != "" else ""
	var s := String(b.get("text") if "text" in b else "").replace("\n", " ").strip_edges()
	if s == "":
		s = String(b.tooltip_text).get_slice("\n", 0).strip_edges()
	if b.toggle_mode:
		s += "  ✓" if b.button_pressed else ""
	return s.left(120)

func press_action(b: BaseButton) -> Callable:
	return func():
		if not is_instance_valid(b) or b.disabled or not b.is_visible_in_tree():
			return
		if b.toggle_mode:
			b.button_pressed = not b.button_pressed
		b.pressed.emit()

# ─── idle menu (someone else's turn) ──────────────────────────────────────────

func _go(id: String, page: Dictionary) -> Callable:
	return func(): _page[id] = page

func _idle_view(idx: int, extra: Dictionary) -> Dictionary:
	var id: String = GameState.players[idx].remote_id
	var page: Dictionary = _page.get(id, {"p": "main"})
	var p: PlayerData = GameState.players[idx]
	var buttons: Array = []
	var actions: Array = []
	var lines: Array = []
	var title := ""
	var top_img := ""
	match String(page["p"]):
		"hand":
			title = "🃏 Your hand  %d/%d" % [p.inventory.hand.size(), Balance.HAND_SIZE]
			lines.append("Tap a card to read it, tap it again to play it.")
			for key in p.inventory.hand:
				var c := CardsData.card(key)
				var e := {"label": CardsData.card_name(key), "desc": String(c.get("desc", "")), "card": true}
				var off := ""
				match String(c.get("kind", "")):
					"tactic": off = "Play this in a battle"
					"capture": off = "Use it when catching a ghost"
					_:
						if idx == GameState.current_player_index:
							off = "Play it from your turn screen"
						elif not key in CardsData.OFF_TURN:
							off = "Only on your own turn"
				if off != "":
					e["off"] = off
				buttons.append(e)
				actions.append(_play_off_turn.bind(idx, key))
			if p.inventory.hand.is_empty():
				lines = ["No cards yet."]
		"card":
			var key: String = page["key"]
			title = "%s — on which spirit?" % CardsData.card_name(key)
			lines.append(String(CardsData.card(key).get("desc", "")))
			for i in p.team.size():
				var m: Dictionary = p.team[i]
				if CardSystem.can_target(key, m):
					buttons.append({"label": "%s  ❤ %d/%d" % [m["name"], int(m["current_hp"]), int(m["hp"])], "gold": true,
						"img": sprite_url(m, 40)})
					actions.append(_play_off_turn.bind(idx, key, m))
			if buttons.is_empty():
				lines.append("No spirit needs this right now.")
		"team":
			title = "👻 Your team (top = lead)"
			lines.append("Tap a spirit for its stats, move and abilities, or to change the order.")
			for i in p.team.size():
				var m: Dictionary = p.team[i]
				buttons.append({"label": "%d. %s %s  ❤ %d/%d" % [i + 1, m["name"], SpiritsData.star_text(m.get("stars", 0)),
					int(m["current_hp"]), int(m["hp"])], "desc": _spirit_desc(m), "img": sprite_url(m, 48)})
				actions.append(_go(id, {"p": "mon", "i": i}))
			if not p.pc.is_empty():
				lines.append("Spirit Box: %d more spirit%s" % [p.pc.size(), "" if p.pc.size() == 1 else "s"])
		"mon":
			var i: int = page["i"]
			if i >= p.team.size():
				_page[id] = {"p": "team"}
				return _idle_view(idx, extra)
			var m: Dictionary = p.team[i]
			title = "%s  %s%s" % [m["name"], SpiritsData.star_text(m.get("stars", 0)), "  (lead)" if i == 0 else ""]
			var mv := SpiritsData.move_of(SpiritsData.move_key(m))
			# each heading with its own description right under it
			lines = [{"t": "❤ HP %d/%d   ATK %d · DEF %d · SPD %d" % [int(m["current_hp"]), int(m["hp"]), int(m.get("atk", 0)),
					int(m.get("def", 0)), int(m.get("spd", 0))], "d": "Type: %s · Stage %d" % [SpiritsData.type_text(m), int(m.get("stage", 1))]},
				{"t": "✦ Move: %s" % mv.get("name", "?"), "d": String(mv.get("desc", ""))}]
			for ab_key in [m.get("ability", ""), m.get("ability2", "")]:
				if String(ab_key) != "":
					var ab := SpiritsData.ability_of(String(ab_key))
					lines.append({"t": "◆ Ability: %s" % ab.get("name", ab_key), "d": String(ab.get("desc", ""))})
			top_img = sprite_url(m, 112)
			if i > 0:
				buttons.append({"label": "⭐ Make lead", "gold": true})
				actions.append(_move_mon.bind(idx, i, -i, id))
				buttons.append({"label": "▲ Move up"})
				actions.append(_move_mon.bind(idx, i, -1, id))
			if i < p.team.size() - 1:
				buttons.append({"label": "▼ Move down"})
				actions.append(_move_mon.bind(idx, i, 1, id))
		_:
			title = String(extra.get("title", _waiting_text()))
			lines = extra.get("lines", []).duplicate()
			if extra.has("title"):
				lines.push_front(_waiting_text())
			buttons = extra.get("buttons", []).duplicate()
			actions = extra.get("_actions", []).duplicate()
			buttons.append({"label": "🃏 My hand (%d)" % p.inventory.hand.size()})
			actions.append(_go(id, {"p": "hand"}))
			buttons.append({"label": "👻 My team"})
			actions.append(_go(id, {"p": "team"}))
	if String(page["p"]) != "main":
		buttons.append({"label": "◀ Back"})
		actions.append(_go(id, {"p": "team"} if page["p"] == "mon" else ({"p": "hand"} if page["p"] == "card" else {"p": "main"})))
		if not extra.is_empty():
			lines.push_front("🗳 " + String(extra.get("title", "")).trim_prefix("🗳 "))
	var view := {"screen": "buttons", "title": title, "lines": lines, "buttons": buttons, "_actions": actions}
	if top_img != "":
		view["img"] = top_img
	return view

func _play_off_turn(idx: int, key: String, target = null) -> void:
	var p: PlayerData = GameState.players[idx]
	var id := p.remote_id
	if not p.inventory.hand.has(key) or idx == GameState.current_player_index or not key in CardsData.OFF_TURN:
		return
	var kind := String(CardsData.card(key).get("target", ""))
	if target == null and kind in ["spirit", "fainted"]:
		_page[id] = {"p": "card", "key": key}
		return
	if target == null:
		target = true
	if not CardSystem.can_target(key, target):
		return
	CardSystem.play_field(idx, key, target)   # OFF_TURN cards never await
	_page[id] = {"p": "hand"}

func _move_mon(idx: int, i: int, dir: int, id: String) -> void:
	var team: Array = GameState.players[idx].team
	var j := i + dir
	if j < 0 or j >= team.size():
		return
	var m = team[i]
	team.remove_at(i)
	team.insert(j, m)
	_page[id] = {"p": "mon", "i": j}
	EventBus.log_entry.emit(idx, "%s's lead is now %s." % [GameState.players[idx].player_name, team[0]["name"]], "#a9b0c4")

# The board's pause / View Map overlay (null off the board).
func _pause_menu() -> Node:
	var scene := get_tree().current_scene
	if scene == null or scene.name != "Board":
		return null
	return _find(scene, func(n): return n.has_method("phone_hold"))

# A spirit's sprite as a small PNG data: URL, so phones can show it whether
# they're on this computer's server or an online relay. "" if unavailable.
func sprite_url(s: Dictionary, px := 56) -> String:
	var name := String(s.get("name", ""))
	var key := "%s@%d" % [name, px]
	if _img_cache.has(key):
		return _img_cache[key]
	var url := ""
	var tex = SpiritsData.sprite_tex(name, "front")
	if tex is AtlasTexture and tex.atlas != null:
		var img: Image = tex.atlas.get_image()
		if img != null and not img.is_empty():
			if img.is_compressed():
				img.decompress()
			img = img.get_region(Rect2i(tex.region))
			var k := float(px) / float(maxi(1, maxi(img.get_width(), img.get_height())))
			img.resize(maxi(1, int(img.get_width() * k)), maxi(1, int(img.get_height() * k)), Image.INTERPOLATE_NEAREST)
			url = "data:image/png;base64," + Marshalls.raw_to_base64(img.save_png_to_buffer())
	_img_cache[key] = url
	return url

func _spirit_desc(m: Dictionary) -> String:
	return "ATK %d · DEF %d · SPD %d · ✦ %s" % [int(m.get("atk", 0)), int(m.get("def", 0)), int(m.get("spd", 0)),
		SpiritsData.move_of(SpiritsData.move_key(m))["name"]]

# Helpers: depth-first search of the scene tree.
func _find(root: Node, pred: Callable) -> Node:
	if pred.call(root):
		return root
	for c in root.get_children():
		var hit := _find(c, pred)
		if hit != null:
			return hit
	return null

func _find_all(root: Node, pred: Callable) -> Array:
	var out: Array = []
	if pred.call(root):
		out.append(root)
	for c in root.get_children():
		if c is CanvasItem and not c.visible:
			continue   # hidden branches can't have visible buttons
		out.append_array(_find_all(c, pred))
	return out
