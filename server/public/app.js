// Kids Hunt Ghost phone controller. Joins a room on the server, then shows
// whatever the game sends: buttons to press on your turn, a gamepad during
// minigames, or a waiting screen. All game logic runs in the game itself.
(() => {
  const $ = (id) => document.getElementById(id);
  const saved = JSON.parse(localStorage.getItem("khg") || "{}");
  const qs = new URLSearchParams(location.search);
  $("code").value = (qs.get("code") || saved.code || "").toUpperCase();
  $("name").value = saved.name || "";

  let ws = null, me = { id: saved.id || null, code: saved.code || null, name: saved.name || "" };
  let rev = 0, retry = 0, joined = false, wantJoin = false;

  function save() {
    try { localStorage.setItem("khg", JSON.stringify(me)); } catch (e) { /* private mode */ }
  }
  function status(text) { $("status").textContent = text; }
  function sendMsg(data) {
    if (ws && ws.readyState === 1) ws.send(JSON.stringify({ t: "msg", data }));
  }

  function connect() {
    // the game's built-in server says where its websocket is (config.js);
    // the online server uses the same host at /ws
    const proto = location.protocol === "https:" ? "wss" : "ws";
    ws = new WebSocket(window.KHG_WS || `${proto}://${location.host}/ws`);
    ws.onopen = () => {
      retry = 0;
      if (wantJoin) ws.send(JSON.stringify({ t: "join", code: me.code, name: me.name, id: me.id }));
    };
    ws.onmessage = (ev) => {
      const m = JSON.parse(ev.data);
      if (m.t === "joined") {
        joined = true;
        me.id = m.id;
        me.code = m.code;
        save();
        $("join").classList.add("hidden");
        $("play").classList.remove("hidden");
        status(`Room ${m.code}`);
      } else if (m.t === "error") {
        wantJoin = false;
        $("joinErr").textContent = m.text;
        ws.close();
      } else if (m.t === "host_gone") {
        render({ screen: "wait", text: "The game disconnected — waiting for it to come back…" });
      } else if (m.t === "msg" && m.data && m.data.view) {
        render(m.data.view);
      }
    };
    ws.onclose = () => {
      if (!wantJoin) return;
      status("Reconnecting…");
      setTimeout(connect, Math.min(5000, 500 * 2 ** retry++));
    };
  }

  $("joinBtn").onclick = () => {
    const code = $("code").value.trim().toUpperCase();
    const name = $("name").value.trim();
    if (code.length !== 4) { $("joinErr").textContent = "The room code has 4 letters."; return; }
    if (!name) { $("joinErr").textContent = "Type your name."; return; }
    if (code !== me.code) me.id = null;   // a new room = a new seat
    me.code = code;
    me.name = name;
    save();
    $("joinErr").textContent = "";
    wantJoin = true;
    if (ws) ws.close(); else connect();
  };
  // came back to the page mid-game: rejoin the same seat straight away
  if (me.code && me.id && me.name && qs.get("code") === null) {
    wantJoin = true;
    connect();
  }

  // ─── views ────────────────────────────────────────────────────────────────
  function el(tag, cls, text) {
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text !== undefined) e.textContent = text;
    return e;
  }

  function renderMe(m) {
    if (!m) return;
    $("meName").textContent = m.name;
    $("me").style.borderLeftColor = m.color || "";
    $("meStats").textContent = [m.pts !== undefined ? `⭐ ${m.pts} pts` : "", m.gold !== undefined ? `🪙 ${m.gold}` : ""]
      .filter(Boolean).join("   ");
  }

  function render(v) {
    rev = v.rev || 0;
    renderMe(v.me);
    const box = $("view");
    box.replaceChildren();
    if (v.title) box.append(el("div", "title", v.title));
    for (const line of v.lines || []) box.append(el("div", "line", line));
    if (v.screen === "buttons") {
      const grid = el("div", "btns");
      (v.buttons || []).forEach((b, i) => {
        const btn = el("button", (b.gold ? "gold " : "") + ((v.buttons.length % 2 && i === v.buttons.length - 1) || b.label.length > 22 ? "wide" : ""), b.label);
        btn.onclick = () => {
          sendMsg({ press: i, rev });
          grid.querySelectorAll("button").forEach((x) => (x.disabled = true));   // wait for the next view
          if (navigator.vibrate) navigator.vibrate(15);
        };
        grid.append(btn);
      });
      box.append(grid);
    } else if (v.screen === "pad") {
      const pad = el("div", "pad");
      for (const [k, label] of [["action", v.action || "ACTION"], ["left", "◀"], ["middle", "●"], ["right", "▶"]]) {
        const b = el("button", k === "action" ? "action" : "", label);
        const down = (e) => { e.preventDefault(); b.classList.add("down"); sendMsg({ pad: k, down: true }); };
        const up = (e) => { e.preventDefault(); b.classList.remove("down"); sendMsg({ pad: k, down: false }); };
        b.addEventListener("touchstart", down, { passive: false });
        b.addEventListener("touchend", up, { passive: false });
        b.addEventListener("touchcancel", up, { passive: false });
        b.addEventListener("mousedown", down);
        b.addEventListener("mouseup", up);
        b.addEventListener("mouseleave", (e) => b.classList.contains("down") && up(e));
        pad.append(b);
      }
      box.append(pad);
    } else {
      const w = el("div", "wait");
      w.append(el("span", "ghost", "👻"), document.createTextNode(v.text || "Waiting…"));
      box.append(w);
    }
    if (v.me && v.me.cards && v.me.cards.length) {
      const cards = el("div", "cards");
      for (const c of v.me.cards) cards.append(el("span", "", c));
      box.append(cards);
    }
  }
})();
