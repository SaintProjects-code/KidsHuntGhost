// Kids Hunt Ghost — phone controller server.
//
// The GAME (the "host", running on the TV/PC) and the PHONES both connect
// here over WebSocket (/ws) and meet in a ROOM by its 4-letter code, like
// Jackbox. This server only relays messages; all the game logic stays in the
// Godot game.
//
//   host  → {t:"host", code?}            ← {t:"room", code}
//   phone → {t:"join", code, name, id?}   ← {t:"joined", id, code} | {t:"error", text}
//   host  ← {t:"join"|"leave", id, name}  (a phone arrived / dropped)
//   host  → {t:"send", id, data}          → phone ← {t:"msg", data}
//   phone → {t:"msg", data}               → host  ← {t:"msg", id, data}
//
// It also serves the phone page (public/) at /, and — if you export the game
// for the web into ./game — the game itself at /game/.
//
// Run: npm install && npm start   (PORT env var, default 8080)

const http = require("http");
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const { WebSocketServer } = require("ws");

const PORT = parseInt(process.env.PORT || "8080", 10);
const PUBLIC = path.join(__dirname, "public");
const GAME = path.join(__dirname, "game");
const TYPES = {
  ".html": "text/html; charset=utf-8", ".js": "text/javascript", ".css": "text/css", ".json": "application/json",
  ".png": "image/png", ".svg": "image/svg+xml", ".ico": "image/x-icon", ".wasm": "application/wasm",
  ".pck": "application/octet-stream", ".webmanifest": "application/manifest+json",
};

// ─── static files ───────────────────────────────────────────────────────────
function serveFile(res, root, rel, extraHeaders) {
  const file = path.normalize(path.join(root, rel));
  if (!file.startsWith(root)) {
    res.writeHead(403).end();
    return;
  }
  fs.stat(file, (err, st) => {
    if (err || !st.isFile()) {
      res.writeHead(404, { "Content-Type": "text/plain" }).end("Not found");
      return;
    }
    res.writeHead(200, { "Content-Type": TYPES[path.extname(file)] || "application/octet-stream", ...extraHeaders });
    fs.createReadStream(file).pipe(res);
  });
}

const server = http.createServer((req, res) => {
  const url = decodeURIComponent((req.url || "/").split("?")[0]);
  if (url === "/health") {
    res.writeHead(200, { "Content-Type": "application/json" }).end(JSON.stringify({ ok: true, rooms: rooms.size }));
    return;
  }
  if (url === "/config.js") {
    // the game's built-in server sends a websocket address here; online, the
    // phone page just uses this host's /ws
    res.writeHead(200, { "Content-Type": "text/javascript", "Cache-Control": "no-cache" }).end("");
    return;
  }
  if (url === "/game" || url.startsWith("/game/")) {
    // Godot web builds need cross-origin isolation (SharedArrayBuffer).
    const rel = url === "/game" || url === "/game/" ? "index.html" : url.slice("/game/".length);
    serveFile(res, GAME, rel, { "Cross-Origin-Opener-Policy": "same-origin", "Cross-Origin-Embedder-Policy": "require-corp" });
    return;
  }
  serveFile(res, PUBLIC, url === "/" ? "index.html" : url, { "Cache-Control": "no-cache" });
});

// ─── rooms ──────────────────────────────────────────────────────────────────
// code -> { host: ws|null, phones: Map<id, {ws, name}>, emptySince: ms|null }
const rooms = new Map();
const ROOM_GRACE_MS = 10 * 60 * 1000;   // a room survives a host reconnect for 10 min
const LETTERS = "ABCDEFGHJKLMNPQRSTUVWXYZ";   // no I/O (they look like 1/0)

function newCode() {
  for (;;) {
    let c = "";
    for (let i = 0; i < 4; i++) c += LETTERS[crypto.randomInt(LETTERS.length)];
    if (!rooms.has(c)) return c;
  }
}

function send(ws, obj) {
  if (ws && ws.readyState === 1) ws.send(JSON.stringify(obj));
}

const wss = new WebSocketServer({ server, path: "/ws", maxPayload: 64 * 1024 });

wss.on("connection", (ws) => {
  ws.isAlive = true;
  ws.on("pong", () => (ws.isAlive = true));
  let role = null;     // "host" | "phone"
  let room = null;
  let code = null;
  let id = null;

  ws.on("message", (raw) => {
    let m;
    try {
      m = JSON.parse(raw.toString());
    } catch {
      return;
    }
    if (role === null && m.t === "host") {
      // a host may reclaim its old room after a reconnect
      code = typeof m.code === "string" && rooms.has(m.code.toUpperCase()) ? m.code.toUpperCase() : newCode();
      room = rooms.get(code) || { host: null, phones: new Map(), emptySince: null };
      rooms.set(code, room);
      if (room.host && room.host !== ws) room.host.close();
      room.host = ws;
      room.emptySince = null;
      role = "host";
      send(ws, { t: "room", code });
      for (const [pid, p] of room.phones) if (p.ws) send(ws, { t: "join", id: pid, name: p.name });
      return;
    }
    if (role === null && m.t === "join") {
      const c = String(m.code || "").trim().toUpperCase();
      const r = rooms.get(c);
      if (!r || !r.host) {
        send(ws, { t: "error", text: "No game with code " + c + " — check the code on the TV." });
        return;
      }
      const name = String(m.name || "Player").trim().slice(0, 14) || "Player";
      // rejoin the same seat if the phone remembers its id
      id = typeof m.id === "string" && r.phones.has(m.id) ? m.id : crypto.randomBytes(4).toString("hex");
      const old = r.phones.get(id);
      if (old && old.ws && old.ws !== ws) old.ws.close();
      r.phones.set(id, { ws, name });
      role = "phone";
      room = r;
      code = c;
      send(ws, { t: "joined", id, code: c });
      send(r.host, { t: "join", id, name });
      return;
    }
    if (role === "host" && m.t === "send") {
      const p = room.phones.get(String(m.id));
      if (p) send(p.ws, { t: "msg", data: m.data });
      return;
    }
    if (role === "phone" && m.t === "msg") {
      send(room.host, { t: "msg", id, data: m.data });
    }
  });

  ws.on("close", () => {
    if (role === "host" && room && room.host === ws) {
      room.host = null;
      room.emptySince = Date.now();
      for (const p of room.phones.values()) send(p.ws, { t: "host_gone" });
    } else if (role === "phone" && room) {
      const p = room.phones.get(id);
      if (p && p.ws === ws) {
        p.ws = null;   // keep the seat for a rejoin
        send(room.host, { t: "leave", id });
      }
    }
  });
});

// keep-alive pings, and forget rooms whose host has been gone a while
setInterval(() => {
  for (const ws of wss.clients) {
    if (!ws.isAlive) {
      ws.terminate();
      continue;
    }
    ws.isAlive = false;
    ws.ping();
  }
  const now = Date.now();
  for (const [c, r] of rooms) if (!r.host && r.emptySince && now - r.emptySince > ROOM_GRACE_MS) rooms.delete(c);
}, 30000);

server.listen(PORT, () => console.log(`Kids Hunt Ghost server on http://localhost:${PORT}  (phones: /, websocket: /ws)`));
