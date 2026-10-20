"""Puts the Mistwood Path tall grass (tallgrass.py) into every map painting: each tall grass cell (',') gets the tile.
Uses the fitted tiles (data/map_fit.json). Also run after repainting or refitting a map. (Dark grass painted on other cells
turned out to be tree edges, so only ',' cells change.)

python3 tools/artgen/fixgrass.py [--dry] [ids]
"""
import json
import sys

import numpy as np
from PIL import Image

from common import RAW, ROOT

MAPS = ROOT / "assets" / "maps"
TILES = [np.array(Image.open(ROOT / "assets" / "tiles" / n).convert("RGB")) for n in ("tallgrass.png", "tallgrass2.png")]


def tiles_of(mid: str, m: dict, fit: dict) -> list[list[str]]:
	rows = [list(r) for r in m["tiles"]]
	for k, ch in fit.get(mid, {}).items():
		x, y = map(int, k.split(","))
		rows[y][x] = ch
	return rows


def fix(mid: str, rows: list[list[str]], dry: bool) -> int:
	p = MAPS / f"{mid}.png"
	im = np.array(Image.open(p).convert("RGB"))
	H, W = len(rows), len(rows[0])
	cell = lambda x, y: im[y * 16:y * 16 + 16, x * 16:x * 16 + 16]
	tall = 0
	for y in range(H):
		for x in range(W):
			if rows[y][x] == ",":
				cell(x, y)[:] = TILES[(x + y) % 2]
				tall += 1
	if not dry:
		Image.fromarray(im).save(p)
	return tall


if __name__ == "__main__":
	args = [a for a in sys.argv[1:] if a != "--dry"]
	dry = "--dry" in sys.argv
	maps = json.loads((RAW / "dump" / "maps.json").read_text())
	fit = json.loads((ROOT / "data" / "map_fit.json").read_text())
	for mid in args or sorted(p.stem for p in MAPS.glob("*.png")):
		if mid in maps:
			n = fix(mid, tiles_of(mid, maps[mid], fit), dry)
			if n:
				print(mid, "tall grass cells", n, flush=True)
