"""Whole-map art: Nano Banana repaints each map from an exact layout reference, and the game draws the
result over the tile grid (collision still comes from the tiles).

python3 tools/artgen/mapart.py layout <map_id> ...    # just the reference images (raw/maps/<id>_layout.png)
python3 tools/artgen/mapart.py generate <map_id> ...  # reference + generation + assets/maps/<id>.png
python3 tools/artgen/mapart.py process <map_id> ...   # redo the downscale from the raw output
"""
import json
import sys

import numpy as np
from PIL import Image

from common import RAW, ROOT, generate_image

MAP_MODEL = "gemini-3-pro-image"  # Nano Banana Pro keeps the layout far better than 2.5 flash

TILES = ROOT / "assets" / "tiles"
BUILD = ROOT / "assets" / "buildings"
OUT = ROOT / "assets" / "maps"
KIND = {"r": "house", "p": "lodge", "b": "mart", "k": "gym", "n": "league"}
SIMPLE = {".": "grass", ",": "tallgrass", "=": "path", "F": "flowers", "~": "water2", "v": "ledge", "S": "sign",
	"_": "floor", "|": "iwall", "o": "statue", "e": "mat", "h": "door_h", "l": "door_l", "m": "door_m", "j": "door_j", "u": "door_u"}
ASPECTS = {"1:1": 1, "4:3": 4 / 3, "3:4": 3 / 4, "3:2": 1.5, "2:3": 2 / 3, "16:9": 16 / 9, "9:16": 9 / 16, "5:4": 1.25, "4:5": 0.8, "21:9": 21 / 9}


def maps() -> dict:
	return json.loads((ROOT / "data" / "maps.json").read_text())


def styles() -> dict:
	p = ROOT / "data" / "town_styles.json"
	return json.loads(p.read_text()) if p.exists() else {}


def tile_img(name: str) -> Image.Image:
	return Image.open(TILES / f"{name}.png").convert("RGBA")


def layout(m: dict) -> Image.Image:
	"""The map drawn with the plain hand-made tiles: exact positions for the model to keep."""
	rows = m["tiles"]
	H, W = len(rows), len(rows[0])
	im = Image.new("RGBA", (W * 16, H * 16), (0, 0, 0, 255))
	at = lambda x, y: rows[y][x] if 0 <= y < H and 0 <= x < W else "#"
	for y in range(H):
		for x in range(W):
			ch = rows[y][x]
			name = SIMPLE.get(ch, "grass")
			if ch == "~" and at(x, y - 1) != "~":
				name = "shore"
			if ch == "=" and at(x, y - 1) not in "=hlmju":
				name = "path_top"
			im.alpha_composite(tile_img(name), (x * 16, y * 16))
	# trees, row by row so lower ones overlap
	for y in range(H):
		for x in range(W):
			if rows[y][x] == "#" and not m.get("indoor"):
				t = tile_img(f"tree32_{(x * 7 + y * 3) % 4}")
				im.alpha_composite(t, (x * 16 - 8, y * 16 - 16)) if x * 16 - 8 >= 0 and y * 16 - 16 >= 0 else _paste_clip(im, t, x * 16 - 8, y * 16 - 16)
	# buildings: roof block plus the wall row(s) under it
	for y in range(H):
		for x in range(W):
			ch = rows[y][x]
			if ch not in KIND or at(x - 1, y) == ch or at(x, y - 1) == ch:
				continue
			w = 0
			while at(x + w, y) == ch:
				w += 1
			h = 0
			while at(x, y + h) == ch:
				h += 1
			doors = []
			while at(x, y + h) in "whlmju":
				doors += [(x + i, y + h, at(x + i, y + h)) for i in range(w) if at(x + i, y + h) != "w"]
				h += 1
			p = BUILD / f"{KIND[ch]}_{w}x{h}.png"
			b = Image.open(p if p.exists() else BUILD / f"{KIND[ch]}.png").convert("RGBA").resize((w * 16, h * 16), Image.NEAREST)
			im.alpha_composite(b, (x * 16, y * 16))
			for dx, dy, d in doors:
				im.alpha_composite(tile_img(SIMPLE[d]), (dx * 16, dy * 16))
	return im


def _paste_clip(im, t, x, y):
	sx, sy = max(0, -x), max(0, -y)
	crop = t.crop((sx, sy, t.width, t.height))
	im.alpha_composite(crop, (x + sx, y + sy))


def prompt(m: dict, style: dict) -> str:
	kind = "indoor gym interior" if m.get("indoor") else ("town" if m.get("town") or not m.get("route") else "route between towns")
	about = style.get("about", "")
	return (
		f"This image is the exact top-down layout of '{m['name']}', a {kind} map in a Game Boy Advance monster RPG, on a 16x16 pixel tile grid. "
		"Repaint it as a finished, beautiful overworld map in the exact visual style of Pokemon Emerald / Ruby / Sapphire (Hoenn): "
		"crisp GBA pixel art, bright saturated colors, clean dark outlines, rich detailed grass texture, Hoenn-style round trees that stack into dense staggered forest rows, "
		"tall grass patches with distinct leafy tufts, sandy paths with soft grassy edges, oblique-view buildings with detailed shingled roofs, eaves, framed windows and doors, "
		"water with gentle highlights and sandy shores, ledges with shaded cliff lips. "
		+ (f"Town character: {about} " if about else "")
		+ "CRITICAL: keep the layout identical. Every building, door, path, tree, tall-grass patch, ledge, sign, flower patch and water area must stay in exactly the same "
		"position and size as in the reference, aligned to the same grid, so walkable areas still match. Do not add, remove or move buildings, paths or trees. "
		"Same framing and scale as the reference, filling the whole image edge to edge. No characters, no people, no creatures, no text, no labels, no UI, no border."
	)


def aspect_for(w: int, h: int) -> str:
	r = w / h
	return min(ASPECTS, key=lambda k: abs(np.log(ASPECTS[k] / r)))


def process(mid: str, m: dict) -> None:
	src = RAW / "maps" / f"{mid}.png"
	if not src.exists():
		return
	W, H = len(m["tiles"][0]) * 16, len(m["tiles"]) * 16
	im = Image.open(src).convert("RGB").resize((W, H), Image.Resampling.LANCZOS)
	im = im.quantize(colors=96, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
	OUT.mkdir(parents=True, exist_ok=True)
	im.save(OUT / f"{mid}.png")


def generate(mid: str, m: dict, style: dict) -> None:
	lay = layout(m)
	(RAW / "maps").mkdir(parents=True, exist_ok=True)
	ref = RAW / "maps" / f"{mid}_layout.png"
	lay.resize((lay.width * 3, lay.height * 3), Image.NEAREST).save(ref)
	generate_image(prompt(m, style), RAW / "maps" / f"{mid}.png", [ref], aspect_for(lay.width, lay.height), MAP_MODEL)
	process(mid, m)


if __name__ == "__main__":
	ms, st = maps(), styles()
	cmd, ids = sys.argv[1], sys.argv[2:] or list(maps())
	for mid in ids:
		if cmd == "layout":
			layout(ms[mid]).save(RAW / "maps" / f"{mid}_layout.png")
		elif cmd == "generate":
			generate(mid, ms[mid], st.get(mid, {}))
		else:
			process(mid, ms[mid])
		print("done", mid, flush=True)
