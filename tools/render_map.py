# Render a map scene's TileMap layers to a PNG preview (needs Pillow).
# usage: python3 tools/render_map.py Scenes/Board/Map1.tscn out.png [scale]
import re, sys
from PIL import Image

ROOT = __file__.rsplit("/tools/", 1)[0]
SOURCES = {0: "Assets/Tilesets/grass1_tileset.png", 1: "Assets/Buildings/house1.png", 2: "Assets/Buildings/oaks_lab.png",
           3: "Assets/Grass/tall_grass.png", 4: "Assets/Water/water_tileset1.png", 5: "Assets/Trees/tree1.png"}
T = 16

def layers(path):
    s = open(path).read()
    out = []
    for m in re.finditer(r'layer_\d+/tile_data = PackedInt32Array\(([^)]*)\)', s):
        a = [int(v) for v in m.group(1).split(",") if v.strip()]
        cells = []
        for i in range(0, len(a), 3):
            x, y = a[i] & 0xffff, (a[i] >> 16) & 0xffff
            x -= 0x10000 if x >= 0x8000 else 0
            y -= 0x10000 if y >= 0x8000 else 0
            cells.append((x, y, a[i + 1] & 0xffff, a[i + 1] >> 16, a[i + 2] & 0xffff))
        out.append(cells)
    return out

def render(path, out, scale=0.25, overlay=None):
    ls = layers(path)
    allc = [c for l in ls for c in l]
    x0, x1 = min(c[0] for c in allc), max(c[0] for c in allc)
    y0, y1 = min(c[1] for c in allc), max(c[1] for c in allc)
    img = Image.new("RGBA", ((x1 - x0 + 1) * T, (y1 - y0 + 1) * T), (30, 30, 40, 255))
    tex = {k: Image.open(f"{ROOT}/{v}").convert("RGBA") for k, v in SOURCES.items()}
    for l in ls:
        for x, y, src, ax, ay in l:
            t = tex[src].crop((ax * T, ay * T, ax * T + T, ay * T + T))
            img.alpha_composite(t, ((x - x0) * T, (y - y0) * T))
    if overlay:
        overlay(img, x0, y0)
    img = img.resize((int(img.width * scale), int(img.height * scale)), Image.NEAREST)
    img.save(out)
    return x0, y0

if __name__ == "__main__":
    render(sys.argv[1], sys.argv[2], float(sys.argv[3]) if len(sys.argv) > 3 else 0.25)
