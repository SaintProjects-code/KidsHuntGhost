# Map generator for the small boards (Map 2-4).
#
# Each map is described ONCE below: towns/junctions (tile coords), roads with
# their tile types, ponds. Running this writes, per map:
#   Scenes/Board/MapN.gd    — the board data (extends Map1.gd, same format)
#   Scenes/Board/MapN.tscn  — the scene, with the terrain PAINTED into its
#                             TileMap (grass, dirt roads, town squares, houses,
#                             ponds, forest), so it can still be touched up by
#                             hand in the Godot editor afterwards
# and, with --preview <dir>, a PNG of each board (needs Pillow).
#
# usage: python3 tools/gen_maps.py [--preview DIR]
# Re-running overwrites MapN.gd / MapN.tscn (hand edits to them are lost).

import math, random, sys, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
T = 16                       # px per tile
ROAD_HALF = 2                # roads are 5 tiles wide
PLAZA_HALF = 5               # town squares are 11×11
SPACE_GAP = 7.0              # rough tiles between spaces (only used by previews)

# Tileset sources (Assets/Tilesets/board_tileset.tres)
GRASS = [(0, 3, 0), (0, 3, 1), (0, 3, 2), (0, 3, 3)]
PATH_SRC = 0                 # 3×3 dirt 9-slice at atlas (0..2, 0..2)
HOUSE_SRC, LAB_SRC, TALL_SRC, WATER_SRC, TREE_SRC = 1, 2, 3, 4, 5

def S(*names):               # shorthand for a list of tile types
    return list(names)

E, I, C, W, G, P, X, B, R = "EVENT", "ITEM", "COMPETITION", "WISP", "GHOST", "PHANTOM", "CLASH", "BATTLE", "WARDEN"

MAPS = {
# ─── Map 2: Hollow Coast — a small REGION in the style of a classic overworld:
# towns spread around a lake, bending routes along the coasts, a forest
# shortcut and a north pass. Routes are short and every road leads back to
# Cobweb City in the middle (five roads meet there), so players keep
# crossing paths instead of wandering alone.
2: {
    "title": "Hollow Coast",
    "size": (120, 94),
    "nodes": {"A": (16, 74), "B": (14, 30), "C": (58, 40), "D": (100, 16), "E": (98, 70),
              "J1": (36, 58), "J2": (78, 56), "J3": (40, 14), "J4": (76, 26),
              "VEnter": (40, 88), "VEnd": (66, 88)},
    "cities": ["A", "B", "C", "D", "E"],
    "names": {"A": "Ashen Hollow", "B": "Boo Bayou", "C": "Cobweb City", "D": "Dusk Den", "E": "Echo End",
              "J1": "Mossy Fork", "J2": "Lantern Bridge", "J3": "North Pass", "J4": "Crow Hill",
              "VEnter": "Spectral Trail", "VEnd": "Spectral Peak"},
    "routes": [
        # west coast and the north pass
        ("A", "B", [(8, 62), (8, 42)], S(W, E, X, I, W)),
        ("B", "J3", [(24, 16)], S(G, I, C, G)),
        ("J3", "D", [(60, 8), (84, 10)], S(G, E, X, I, G)),
        ("J3", "C", [(46, 26)], S(X, E, I)),
        # east side
        ("D", "J4", [(92, 24)], S(W, C, W)),
        ("J4", "C", [], S(I, X, E)),
        ("J4", "E", [(110, 34), (110, 56)], S(G, I, E, C, G)),
        ("E", "J2", [(88, 62)], S(W, X, I)),
        ("J2", "C", [(68, 48)], S(E, G, X)),
        # the south road round the lake, and the forest shortcut
        ("J2", "A", [(70, 78), (36, 80)], S(C, W, E, X, I)),
        ("A", "J1", [(26, 66)], S(I, W, X)),
        ("J1", "C", [(46, 46)], S(G, C, X)),
        ("J1", "B", [(30, 44), (22, 36)], S(E, G, W, X)),
        ("VEnter", "VEnd", [], S(I, R, I, R, R)),
    ],
    "ponds": [(46, 56, 20, 12), (60, 17, 12, 7)],
    "seed": 2,
},
# ─── Map 3: Festival Grounds — a figure-8 race track. Two loops cross at
# the fairground in the middle, and the lanes are packed with 🏅 Competition
# tiles (and the 4 extra minigames).
3: {
    "title": "Festival Grounds",
    "size": (120, 96),
    "nodes": {"A": (32, 72), "B": (80, 72), "C": (8, 48), "D": (104, 48), "E": (56, 48),
              "J1": (80, 24), "J2": (32, 24),
              "VEnter": (114, 84), "VEnd": (114, 58)},
    "cities": ["A", "B", "C", "D", "E"],
    "names": {"A": "Ashen Hollow", "B": "Boo Bayou", "C": "Cobweb City", "D": "Dusk Den", "E": "Echo Fairground",
              "J1": "Ferris Hill", "J2": "Carousel Hill",
              "VEnter": "Spectral Trail", "VEnd": "Spectral Peak"},
    "routes": [
        # left loop (centre 32,48)
        ("E", "A", ("arc", (32, 48)), S(C, W, I, C)),
        ("A", "C", ("arc", (32, 48)), S(C, E, G, C)),
        ("C", "J2", ("arc", (32, 48)), S(W, C, I, C)),
        ("J2", "E", ("arc", (32, 48)), S(C, X, E, C)),
        # right loop (centre 80,48)
        ("E", "B", ("arc", (80, 48)), S(C, G, I, C)),
        ("B", "D", ("arc", (80, 48)), S(C, E, W, C)),
        ("D", "J1", ("arc", (80, 48)), S(G, C, I, C)),
        ("J1", "E", ("arc", (80, 48)), S(C, X, E, C)),
        ("VEnter", "VEnd", [], S(I, R, I, R, R)),
    ],
    "ponds": [(26, 42, 12, 12), (74, 42, 12, 12)],
    "seed": 3,
},
# ─── Map 4: Spirit Colosseum — a round arena. The outer ring links four
# towns; four spokes run into the central arena (Cobweb City). Mostly
# ⚔ Battle and Clash tiles; everyone starts with 3 spirits for 3v3 fights.
4: {
    "title": "Spirit Colosseum",
    "size": (112, 104),
    "nodes": {"A": (54, 92), "B": (12, 52), "C": (54, 52), "D": (96, 52), "E": (54, 12),
              "VEnter": (106, 92), "VEnd": (106, 64)},
    "cities": ["A", "B", "C", "D", "E"],
    "names": {"A": "Ashen Gate", "B": "Boo Bastion", "C": "Cobweb Arena", "D": "Dusk Tower", "E": "Echo Keep",
              "VEnter": "Spectral Trail", "VEnd": "Spectral Peak"},
    "routes": [
        ("A", "B", "ring", S(G, B, X, I, B, W)),
        ("B", "E", "ring", S(W, B, E, X, B, G)),
        ("E", "D", "ring", S(G, B, X, I, B, W)),
        ("D", "A", "ring", S(W, B, E, X, B, G)),
        ("A", "C", [], S(B, I, X)),
        ("B", "C", [], S(B, E, X)),
        ("E", "C", [], S(B, I, X)),
        ("D", "C", [], S(B, E, X)),
        ("VEnter", "VEnd", [], S(R, I, R, R)),
    ],
    "ponds": [],
    "seed": 4,
},
}

# ─── geometry ────────────────────────────────────────────────────────────────

def ring_corners(m, a, b, centre=None):
    """Corners along the circle round `centre` (default: town C) from node a
    to node b, going the short way round, every 15 degrees."""
    cx, cy = centre or m["nodes"]["C"]
    ax, ay = m["nodes"][a]
    bx, by = m["nodes"][b]
    r = math.hypot(ax - cx, ay - cy)
    t0 = math.atan2(ay - cy, ax - cx)
    t1 = math.atan2(by - cy, bx - cx)
    d = (t1 - t0 + math.pi) % (2 * math.pi) - math.pi
    steps = max(2, int(abs(d) / math.radians(15)))
    return [(round(cx + r * math.cos(t0 + d * k / steps)), round(cy + r * math.sin(t0 + d * k / steps)))
            for k in range(1, steps)]

def route_cells(m, r):
    a, b, corners, _ = r
    if corners == "ring":
        corners = ring_corners(m, a, b)
    elif isinstance(corners, tuple) and corners[0] == "arc":
        corners = ring_corners(m, a, b, corners[1])
    return [m["nodes"][a]] + list(corners) + [m["nodes"][b]], corners

# ─── painting ────────────────────────────────────────────────────────────────

def paint(m):
    rnd = random.Random(m["seed"])
    w, h = m["size"]
    ground, objects = {}, {}
    for x in range(w):
        for y in range(h):
            ground[(x, y)] = rnd.choices(GRASS, weights=[7, 7, 6, 6])[0]
    road = set()
    def stamp(cx, cy, half):
        for dx in range(-half, half + 1):
            for dy in range(-half, half + 1):
                if 0 <= cx + dx < w and 0 <= cy + dy < h:
                    road.add((cx + dx, cy + dy))
    for r in m["routes"]:
        pts, _ = route_cells(m, r)
        for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
            n = int(max(abs(x1 - x0), abs(y1 - y0)) * 2) + 1
            for k in range(n + 1):
                stamp(round(x0 + (x1 - x0) * k / n), round(y0 + (y1 - y0) * k / n), ROAD_HALF)
    for c in m["cities"]:
        stamp(*m["nodes"][c], PLAZA_HALF)
    # dirt 9-slice: edges where a neighbour isn't road
    for (x, y) in road:
        n, s_, wv, e = (x, y - 1) in road, (x, y + 1) in road, (x - 1, y) in road, (x + 1, y) in road
        ax = 1 if (wv and e) or (not wv and not e) else (0 if not wv else 2)
        ay = 1 if (n and s_) or (not n and not s_) else (0 if not n else 2)
        ground[(x, y)] = (PATH_SRC, ax, ay)
    used = set(road)
    def free(x, y, bw, bh, pad=1):
        return all(0 <= xx < w and 0 <= yy < h and (xx, yy) not in used
                   for xx in range(x - pad, x + bw + pad) for yy in range(y - pad, y + bh + pad))
    def block(x, y, bw, bh, src, pad=0):
        for xx in range(bw):
            for yy in range(bh):
                objects[(x + xx, y + yy)] = (src, xx, yy)
        for xx in range(x - pad, x + bw + pad):
            for yy in range(y - pad, y + bh + pad):
                used.add((xx, yy))
    # ponds (water 9-slice)
    for (px, py, pw, ph) in m["ponds"]:
        if free(px, py, pw, ph, 1):
            for xx in range(pw):
                for yy in range(ph):
                    ax = 0 if xx == 0 else (2 if xx == pw - 1 else 1)
                    ay = 0 if yy == 0 else (2 if yy == ph - 1 else 1)
                    objects[(px + xx, py + yy)] = (WATER_SRC, ax, ay)
            for xx in range(px - 1, px + pw + 1):
                for yy in range(py - 1, py + ph + 1):
                    used.add((xx, yy))
    # buildings beside each town square: a lab at the arena/city, houses elsewhere
    for c in m["cities"]:
        cx, cy = m["nodes"][c]
        spots = [(cx - PLAZA_HALF - 6, cy - 2), (cx + PLAZA_HALF + 2, cy - 2), (cx - 2, cy - PLAZA_HALF - 6),
                 (cx - 2, cy + PLAZA_HALF + 2), (cx - PLAZA_HALF - 6, cy - PLAZA_HALF - 5), (cx + PLAZA_HALF + 2, cy + PLAZA_HALF + 1)]
        placed = 0
        for (hx, hy) in spots:
            bw = 7 if (c == "C" and placed == 0) else 5
            if placed < 2 and free(hx, hy, bw, 5, 1):
                block(hx, hy, bw, 5, LAB_SRC if bw == 7 else HOUSE_SRC, 1)
                placed += 1
    # tall grass patches
    for _ in range(int(w * h / 260)):
        x, y = rnd.randrange(w), rnd.randrange(h)
        pw, ph = rnd.randint(3, 6), rnd.randint(2, 4)
        if free(x, y, pw, ph, 1):
            for xx in range(pw):
                for yy in range(ph):
                    objects[(x + xx, y + yy)] = (TALL_SRC, rnd.randint(0, 1), 0)
                    used.add((x + xx, y + yy))
    # forest: a 2×3 tree wherever there's room, thicker toward the edges
    for y in range(0, h - 2, 3):
        for x in range(0, w - 1, 2):
            edge = min(x, y, w - 1 - x, h - 1 - y)
            if (edge < 6 or rnd.random() < 0.55) and free(x, y, 2, 3, 0) and \
                    all((xx, yy) not in road for xx in range(x - 2, x + 4) for yy in range(y - 2, y + 5)):
                block(x, y, 2, 3, TREE_SRC)
    return ground, objects

def packed(cells):
    out = []
    for (x, y), (src, ax, ay) in sorted(cells.items(), key=lambda kv: (kv[0][1], kv[0][0])):
        pos = ((y & 0xffff) << 16) | (x & 0xffff)
        if pos >= 1 << 31:
            pos -= 1 << 32
        out += [pos, src | (ax << 16), ay]
    return ", ".join(str(v) for v in out)

# ─── output ──────────────────────────────────────────────────────────────────

def gd_value(v):
    if isinstance(v, tuple):
        return "Vector2i(%d, %d)" % v
    return '"%s"' % v

def write_script(n, m):
    lines = ["extends \"res://Scenes/Board/Map1.gd\"",
             "## %s — GENERATED by tools/gen_maps.py from its map spec; edit the spec" % m["title"],
             "## there and re-run instead of editing this file (it gets overwritten).",
             "", "func _init() -> void:", "\tNODES = {"]
    for k, v in m["nodes"].items():
        lines.append("\t\t\"%s\": %s," % (k, gd_value(v)))
    lines.append("\t}")
    lines.append("\tCITIES = [%s]" % ", ".join('"%s"' % c for c in m["cities"]))
    lines.append("\tNAMES = {")
    for k, v in m["names"].items():
        lines.append("\t\t\"%s\": \"%s\"," % (k, v))
    lines.append("\t}")
    lines.append("\tROUTES = [")
    for r in m["routes"]:
        _, corners = route_cells(m, r)
        lines.append("\t\t{ \"from\": \"%s\", \"to\": \"%s\", \"corners\": [%s], \"spaces\": %d," % (
            r[0], r[1], ", ".join(gd_value(c) for c in corners), len(r[3])))
        lines.append("\t\t\t\"types\": [%s] }," % ", ".join('&"%s"' % t for t in r[3]))
    lines.append("\t]")
    open(f"{ROOT}/Scenes/Board/Map{n}.gd", "w").write("\n".join(lines) + "\n")

def write_scene(n, m, ground, objects):
    s = f"""[gd_scene load_steps=3 format=3 uid="uid://cboardmap000{n}"]

[ext_resource type="Script" path="res://Scenes/Board/Map{n}.gd" id="1_board"]
[ext_resource type="TileSet" uid="uid://vlw2ij8ikwkx" path="res://Assets/Tilesets/board_tileset.tres" id="2_tiles"]

[node name="Map{n}" type="Node2D"]
script = ExtResource("1_board")

[node name="TileMap" type="TileMap" parent="."]
tile_set = ExtResource("2_tiles")
format = 2
layer_0/name = "Ground"
layer_0/tile_data = PackedInt32Array({packed(ground)})
layer_1/name = "Objects"
layer_1/enabled = true
layer_1/modulate = Color(1, 1, 1, 1)
layer_1/y_sort_enabled = false
layer_1/y_sort_origin = 0
layer_1/z_index = 0
layer_1/tile_data = PackedInt32Array({packed(objects)})
"""
    open(f"{ROOT}/Scenes/Board/Map{n}.tscn", "w").write(s)

COLORS = {"WISP": "f7a8c0", "GHOST": "2fa84f", "PHANTOM": "e03131", "EVENT": "f4d03f", "ITEM": "f08a2e",
          "COMPETITION": "8e8e93", "WARDEN": "7b5cd6", "CLASH": "e64ad8", "BATTLE": "d9480f"}

def preview(n, m, out_dir):
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from render_map import render
    from PIL import ImageDraw
    def overlay(img, x0, y0):
        d = ImageDraw.Draw(img)
        world = lambda c: ((c[0] - x0) * T + T / 2, (c[1] - y0) * T + T / 2)
        for r in m["routes"]:
            pts, _ = route_cells(m, r)
            wp = [world(p) for p in pts]
            d.line(wp, fill=(0, 0, 0, 180), width=4)
            # same spacing rule as Map1._fill_along
            total = sum(math.dist(a, b) for a, b in zip(wp, wp[1:]))
            cf = 1.0 if r[0] in m["cities"] else 0.5
            ct = 1.0 if r[1] in m["cities"] else 0.5
            k_n = len(r[3])
            gap = total / (cf + ct + k_n - 1)
            for k, typ in enumerate(r[3]):
                dist = gap * (cf + k)
                for a, b in zip(wp, wp[1:]):
                    seg = math.dist(a, b)
                    if dist <= seg:
                        p = (a[0] + (b[0] - a[0]) * dist / seg, a[1] + (b[1] - a[1]) * dist / seg)
                        break
                    dist -= seg
                col = tuple(int(COLORS[typ][i:i + 2], 16) for i in (0, 2, 4))
                d.ellipse([p[0] - 16, p[1] - 16, p[0] + 16, p[1] + 16], fill=col, outline=(0, 0, 0))
        for c in m["cities"]:
            p = world(m["nodes"][c])
            d.ellipse([p[0] - 22, p[1] - 22, p[0] + 22, p[1] + 22], fill=(47, 107, 208), outline=(0, 0, 0))
            d.text((p[0] - 4, p[1] - 6), c, fill=(255, 255, 255))
    render(f"{ROOT}/Scenes/Board/Map{n}.tscn", f"{out_dir}/map{n}.png", 0.4, overlay)

if __name__ == "__main__":
    out_dir = sys.argv[sys.argv.index("--preview") + 1] if "--preview" in sys.argv else None
    for n, m in MAPS.items():
        ground, objects = paint(m)
        write_script(n, m)
        write_scene(n, m, ground, objects)
        print(f"Map{n} ({m['title']}): {sum(len(r[3]) for r in m['routes'])} spaces, {len(m['routes'])} roads")
        if out_dir:
            preview(n, m, out_dir)
