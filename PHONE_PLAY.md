# 📱 Phone play — setup, GitHub and your server

Kids Hunt Ghost can be played Jackbox-style: the game runs on one computer
(hooked up to the TV), and every player uses **their own phone** as the
controller. Phones open a web page, type a 4-letter room code, and from then on
their turns, choices, battles and minigame buttons show up on the phone.

```
 phones (browser) ──┐                         ┌── the game (Godot, on the TV/PC)
                    ├──►  server/server.js  ◄─┤   hosts a room, shows the code
 https://your-site ─┘     (Node, on your server)
```

The server only passes messages along; the game itself runs on the TV computer.

---

## 1. Play at home (nothing to install)

The game has its own little phone server built in. The computer and the
phones just need to be on the **same network** — your Wi-Fi, or a phone
hotspot (see *No Wi-Fi?* below). No internet is needed.

1. Run the game → **New Game** → **📱 Phones**.
2. **Server IP** is already filled in with this computer's IP (the line under
   it lists all of them). Press **Connect**. A **room code** appears, plus the
   address for phones, e.g. `http://192.168.1.20:8080`.
3. On each phone, open that address in the browser — type it exactly,
   starting with `http://` (not https). Type the **room code** and your name →
   **Join!** Everyone in the room is listed on the TV and on every phone.
4. Each phone takes a player card. Phones can flip through trainers with
   **◀ Change trainer ▶**. Add CPUs on the computer if you like.
5. Press **▶ Start Game**. The room code stays in the top-left corner of the
   board, so a phone that drops out can rejoin.

**Phone says "can't reach this page"?** Watch the panel — it tells you whether
any phone reached the computer yet.
- *"No phone has reached this computer yet"* → Windows is blocking it. Press
  **🛡 Allow phones through Windows Firewall** (Windows asks for permission),
  then reload the page on the phone. Also check the phone is on the same
  network (not mobile data, not a *guest* Wi-Fi).
- *"A phone tried https://"* → retype the address starting with `http://`.
- Still nothing? Try the other addresses listed under "This computer:" (PCs
  with WSL, Hyper-V, VirtualBox or a VPN have extra network adapters).
- You don't need `npm start` for home play.

### No Wi-Fi? Use a phone hotspot

1. On one phone, turn on **Hotspot / Personal Hotspot**.
2. Connect the **computer** and **every other phone** to that hotspot.
3. In the game, the Server IP fills in with the computer's hotspot address
   (often `192.168.43.x`, `172.20.10.x` or `10.x`) → **Connect** → play as above.
   The phone running the hotspot can play too: it opens the same address.

The game traffic stays on the hotspot, so it doesn't use mobile data. (A
Windows PC can also make its own hotspot: Settings → Network → **Mobile
hotspot**; its address is then `192.168.137.1`.)

Or play **over the internet** with everyone on mobile data: put the Node server
on a website (section 3) and type its address in Server IP.

What a phone does during the game:
- **Your turn:** the buttons on the TV's current window are copied to your phone
  (Roll, card plays, fork choices, the catch roll, shop, Warden challenge, events…).
  Your cards show face-down on the TV — only your phone shows what they are.
- **Your battles:** pick your team and cards on the phone; during the fight
  tap a tactic card (or charm) to play it next round. In a ⚔ player battle
  each phone picks its own side and the TV hides both hands.
- **Someone else's battle:** 🗳 vote on who wins during the first 2 rounds.
  Guess right → +1 card (or ★ on a spirit if your hand is full).
- **Someone else's turn:** 🃏 *My hand* — look at your cards and play healing /
  dice / lure / salt / coin cards; 👻 *My team* — see stats and change your lead
  or order.
- **Competitions:** everyone picks their spirit on their own phone, then the phone
  becomes a **gamepad** (ACTION + ◀ ● ▶) for the minigame.

You can mix phones, keyboard players and CPUs in one game.

---

## 2. Upload the project to GitHub

> ⚠️ Make the repository **Private**. The game still uses Pokémon sprites as
> placeholder art, and a public repo would publish them.

1. Create a GitHub account if needed, then **New repository** →
   name `kids-hunt-ghost` → **Private** → *don't* add a README → **Create**.
2. In a terminal in the project folder (`Kids Hunt Ghost/`):
   ```bash
   git add -A
   git commit -m "Maps 2-4, new minigames, phone play"
   git remote add origin https://github.com/YOUR-NAME/kids-hunt-ghost.git
   git push -u origin master
   ```
3. When git asks for a password, use a **Personal Access Token**, not your
   GitHub password: GitHub → Settings → Developer settings → Personal access
   tokens → *Fine-grained* → give it access to this repo with **Contents:
   Read and write**. (Or install GitHub CLI and run `gh auth login` once.)

Later changes: `git add -A && git commit -m "what changed" && git push`.

`server/node_modules/` is git-ignored, so `npm install` must be run again on the server.

The Node server (below) is only for playing **over the internet**.

---

## 3. Run the server on your website

You need a server that can run **Node.js** and keep a connection open (a VPS such
as DigitalOcean, Linode or Hetzner, or a Node host such as Render or Railway).
Ordinary "shared web hosting" that only serves PHP/HTML files **can't** run it.

### Option A — your own Linux VPS (Ubuntu)

SSH into the server, then:

```bash
# Node.js 20
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs git nginx

# the code (a private repo asks for your GitHub user + token)
git clone https://github.com/YOUR-NAME/kids-hunt-ghost.git
cd kids-hunt-ghost/server
npm ci --omit=dev

# keep it running (and restart it after reboots)
sudo npm install -g pm2
PORT=8080 pm2 start server.js --name khg
pm2 save
pm2 startup        # run the command it prints
```

Check it works: `curl http://localhost:8080/health` → `{"ok":true,...}`.

**Put it behind your domain with HTTPS.** Phones need `https://`, and the game
then connects with `wss://`. Point your domain's DNS (an `A` record, e.g.
`ghost.yourdomain.com`) at the server's IP, then create
`/etc/nginx/sites-available/khg`:

```nginx
server {
    server_name ghost.yourdomain.com;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;     # needed for the websocket
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_read_timeout 3600s;                   # keep idle games connected
    }
}
```

```bash
sudo ln -s /etc/nginx/sites-available/khg /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
sudo apt-get install -y certbot python3-certbot-nginx
sudo certbot --nginx -d ghost.yourdomain.com     # free HTTPS certificate
sudo ufw allow 'Nginx Full'                       # if the firewall is on
```

### Option B — Render (no server admin)

1. render.com → **New → Web Service** → connect your GitHub repo.
2. **Root directory:** `server` · **Build command:** `npm install` · **Start command:** `npm start`.
3. Deploy. Render gives you `https://your-app.onrender.com` with HTTPS and
   websockets already set up. (Free instances sleep when idle: open the site once
   and wait ~30 s before starting the room.)

### Play over the internet

In the game: **📱 Phones** → Server IP `ghost.yourdomain.com` (or
`your-app.onrender.com`) → **Connect**. Phones open
`https://ghost.yourdomain.com`, type the code, and play.

### Updating the server later

```bash
cd kids-hunt-ghost && git pull && cd server && npm ci --omit=dev && pm2 restart khg
```

---

## 4. (Optional) the game itself in a browser

The server also serves a Godot **web export** at `/game/`, with the special
headers Godot web builds need. In the Godot editor: Project → Export → Add…
**Web** (install the export templates when asked) → export to
`server/game/index.html`, upload that folder to the server, and open
`https://ghost.yourdomain.com/game/` on the TV computer's browser. The desktop
game works just as well; this only saves installing anything on the TV computer.

---

## Notes and limits

- Rooms live in the server's memory. If the game drops off for a moment it
  reclaims its room, and phones that reload rejoin their seat. Restarting the
  server ends all rooms.
- Anyone with the code can join a room while there are free seats (4 players max).
- If a phone disconnects mid-game, that player waits until it rejoins (same
  phone, same browser), or someone plays the turn on the computer with the mouse.
- Files: `server/server.js` (relay), `server/public/` (phone page),
  `Global/Remote.gd` (the game side), and the **📱 Phones** panel in `SetupScreen.gd`.
