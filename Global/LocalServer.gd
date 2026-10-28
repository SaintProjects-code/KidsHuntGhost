class_name LocalServer
extends RefCounted
## 📱 The phone server built into the game, for playing on your own Wi-Fi with
## nothing else installed (Remote uses it in "this computer" mode):
##   • HTTP on http_port serves the phone page (server/public/) plus a tiny
##     config.js that points the page at…
##   • WebSockets on http_port + 1, where phones join with the room code.
## The first free pair in PORTS is used (8080 may be taken by `npm start` or
## another app).
## It speaks the same messages as server/server.js, handing them to Remote as
## if they came from that server ({t: "room" | "join" | "leave" | "msg"}).
## Remote calls poll() every frame and send_to() to talk to a phone.

const PORTS := [8080, 8090, 8180, 9080, 9180]   # HTTP; the websocket is the next port
const PUBLIC := "res://server/public/"
const TYPES := {"html": "text/html; charset=utf-8", "js": "text/javascript", "css": "text/css"}
const LETTERS := "ABCDEFGHJKLMNPQRSTUVWXYZ"

var code := ""
var http_port := 0
var page_loads := 0              # times a browser loaded the phone page (shown on the TV)
var last_visitor := ""           # IP of the last browser that reached us
var https_tries := 0             # browsers that tried https:// — we only speak http
var error := ""                  # why it couldn't start ("" = running)
var _on_message: Callable        # (Dictionary) -> void, the Remote side
var _http := TCPServer.new()
var _ws := TCPServer.new()
var _requests: Array = []        # {peer: StreamPeerTCP, buf: PackedByteArray, t: float}
var _phones: Array = []          # {ws: WebSocketPeer, id: String, name: String, open: bool}
var _names := {}                 # id -> name, kept so a phone can rejoin its seat

func _init(on_message: Callable) -> void:
	_on_message = on_message

func start() -> bool:
	http_port = 0
	for port in PORTS:
		if _http.listen(port) != OK:
			continue
		if _ws.listen(port + 1) != OK:
			_http.stop()
			continue
		http_port = port
		break
	if http_port == 0:
		error = "Ports %s are all busy — close other servers (like npm start) and try again." % str(PORTS)
		return false
	if code == "":
		for i in 4:
			code += LETTERS[randi() % LETTERS.length()]
	error = ""
	_on_message.call({"t": "room", "code": code})
	return true

func stop() -> void:
	_http.stop()
	_ws.stop()
	for p in _phones:
		p["ws"].close()
	_phones.clear()
	_requests.clear()

# This computer's home-network IPv4s, likeliest first: Wi-Fi / Ethernet before
# the virtual adapters Windows adds for WSL, Hyper-V, VirtualBox, VPNs…
const VIRTUAL := ["vethernet", "virtual", "vmware", "vbox", "hyper-v", "wsl", "docker", "loopback", "vpn",
	"tap", "tun", "zerotier", "tailscale", "hamachi", "bluetooth"]

static func lan_ips() -> Array:
	var scored: Array = []
	for iface in IP.get_local_interfaces():
		var label := (String(iface.get("friendly", "")) + " " + String(iface.get("name", ""))).to_lower()
		for ip in iface.get("addresses", []):
			if ip.count(".") != 3 or ip.begins_with("127.") or ip.begins_with("169.254."):
				continue
			var second := int(ip.get_slice(".", 1))
			var score := -1
			if ip.begins_with("192.168."):
				score = 0 if not ip.begins_with("192.168.56.") else 4   # .56 = VirtualBox host-only
			elif ip.begins_with("10."):
				score = 1
			elif ip.begins_with("172.") and second >= 16 and second <= 31:
				score = 2   # usually Docker / WSL / Hyper-V
			if score < 0:
				continue
			if VIRTUAL.any(func(v): return label.contains(v)):
				score += 5
			elif label.contains("wi-fi") or label.contains("wlan") or label.contains("wireless") or label.begins_with("wl"):
				score -= 1
			scored.append([score, ip])
	scored.sort_custom(func(a, b): return a[0] < b[0])
	var out: Array = []
	for pair in scored:
		if not out.has(pair[1]):
			out.append(pair[1])
	return out

# The addresses phones can open.
static func lan_urls(port: int) -> Array:
	return lan_ips().map(func(ip): return "http://%s:%d" % [ip, port])

func send_to(id: String, data) -> void:
	for p in _phones:
		if p["id"] == id and p["ws"].get_ready_state() == WebSocketPeer.STATE_OPEN:
			p["ws"].send_text(JSON.stringify({"t": "msg", "data": data}))

func poll(delta: float) -> void:
	_poll_http(delta)
	_poll_ws()

# ─── the phone page ───────────────────────────────────────────────────────────

func _poll_http(delta: float) -> void:
	while _http.is_connection_available():
		_requests.append({"peer": _http.take_connection(), "buf": PackedByteArray(), "t": 0.0})
	for r in _requests.duplicate():
		var peer: StreamPeerTCP = r["peer"]
		peer.poll()
		r["t"] += delta
		var n := peer.get_available_bytes()
		if n > 0:
			r["buf"].append_array(peer.get_data(n)[1])
		var buf: PackedByteArray = r["buf"]
		if buf.size() > 0 and (buf[0] == 0x16 or buf[0] >= 0x80):
			# not HTTP: 0x16 starts a TLS hello (the browser tried https://).
			# Hang up at once so it falls back to http:// instead of waiting.
			if buf[0] == 0x16:
				https_tries += 1
			peer.disconnect_from_host()
			_requests.erase(r)
			continue
		# a request line + headers are plain ASCII (never parse them as UTF-8)
		var head: String = buf.get_string_from_ascii()
		if head.contains("\r\n\r\n") or buf.size() > 16384:
			_respond(peer, head.get_slice(" ", 1))
			_requests.erase(r)
		elif r["t"] > 5.0 or peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			peer.disconnect_from_host()
			_requests.erase(r)

func _respond(peer: StreamPeerTCP, path: String) -> void:
	path = path.get_slice("?", 0)
	if path == "/":
		page_loads += 1
		last_visitor = peer.get_connected_host()
	var body := PackedByteArray()
	var type := "text/plain"
	var status := "200 OK"
	if path == "/config.js":
		body = ("window.KHG_WS = \"ws://\" + location.hostname + \":%d\";" % (http_port + 1)).to_utf8_buffer()
		type = TYPES["js"]
	else:
		var file := "index.html" if path == "/" else path.trim_prefix("/")
		if file.contains("..") or not FileAccess.file_exists(PUBLIC + file):
			status = "404 Not Found"
			body = "Not found".to_utf8_buffer()
		else:
			body = FileAccess.get_file_as_bytes(PUBLIC + file)
			type = TYPES.get(file.get_extension(), "application/octet-stream")
	var header := "HTTP/1.1 %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n" % [
		status, type, body.size()]
	peer.put_data(header.to_utf8_buffer())
	peer.put_data(body)
	peer.disconnect_from_host()

# ─── phones (websocket) ───────────────────────────────────────────────────────

func _poll_ws() -> void:
	while _ws.is_connection_available():
		var ws := WebSocketPeer.new()
		ws.accept_stream(_ws.take_connection())
		_phones.append({"ws": ws, "id": "", "name": "", "open": true})
	for p in _phones.duplicate():
		var ws: WebSocketPeer = p["ws"]
		ws.poll()
		match ws.get_ready_state():
			WebSocketPeer.STATE_OPEN:
				while ws.get_available_packet_count() > 0:
					var m = JSON.parse_string(ws.get_packet().get_string_from_utf8())
					if m is Dictionary:
						_on_phone(p, m)
			WebSocketPeer.STATE_CLOSED:
				_phones.erase(p)
				if p["id"] != "" and not _phones.any(func(q): return q["id"] == p["id"]):
					_on_message.call({"t": "leave", "id": p["id"]})

func _on_phone(p: Dictionary, m: Dictionary) -> void:
	var ws: WebSocketPeer = p["ws"]
	match String(m.get("t", "")):
		"join":
			if String(m.get("code", "")).strip_edges().to_upper() != code:
				ws.send_text(JSON.stringify({"t": "error", "text": "Wrong code — use the code shown on the TV."}))
				return
			var id := String(m.get("id", ""))
			if not _names.has(id):
				id = "%08x" % randi()
			# a rejoin replaces the old connection for that seat
			for q in _phones:
				if q != p and q["id"] == id:
					q["id"] = ""
					q["ws"].close()
			var name := String(m.get("name", "Player")).strip_edges().left(14)
			p["id"] = id
			_names[id] = name if name != "" else "Player"
			ws.send_text(JSON.stringify({"t": "joined", "id": id, "code": code}))
			_on_message.call({"t": "join", "id": id, "name": _names[id]})
		"msg":
			if p["id"] != "":
				_on_message.call({"t": "msg", "id": p["id"], "data": m.get("data", {})})
