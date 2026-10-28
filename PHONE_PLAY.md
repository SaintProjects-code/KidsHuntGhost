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

## 1. Try it at home first (no server needed)

Everything on the same Wi-Fi.

1. Install **Node.js 18+** on the game computer (https://nodejs.org, LTS).
2. In a terminal:
   ```bash
   cd "Kids Hunt Ghost/server"
   npm install
   npm start
   ```
   It prints `Kids Hunt Ghost server on http://localhost:8080`.
3. Find the computer's local IP (Windows: `ipconfig` → "IPv4 Address", e.g. `192.168.1.20`).
4. Run the game → **New Game** → **📱 Phones**. Set the server to
   `ws://192.168.1.20:8080/ws` (your IP) and press **Start room**. A room code appears.
5. On each phone open `http://192.168.1.20:8080`, type the code and a name → **Join!**
   Each phone takes a player card (it fills in the name). Phones can flip
   through trainers with **◀ Change trainer ▶**.
6. Press **▶ Start Game** on the computer.

If phones can't connect, allow Node through the Windows firewall (Windows asks
the first time `npm start` runs — tick "Private networks").

What a phone does during the game:
- **Your turn:** the buttons on the TV's current window are copied to your phone
  (Roll, card plays, fork choices, the catch roll, shop, Warden challenge, events…).
- **Battles:** pick your team and tactic cards on the phone. In a ⚔ player battle
  each phone picks its own side.
- **Competitions:** everyone picks their spirit on their own phone, then the phone
  becomes a **gamepad** (ACTION + ◀ ● ▶) for the minigame.
- **Someone else's turn:** the phone says whose turn it is.

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

In the game: **📱 Phones** → server `wss://ghost.yourdomain.com/ws` (or
`wss://your-app.onrender.com/ws`) → **Start room**. Phones open
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
