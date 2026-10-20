"""Whole-map art: Nano Banana Pro repaints each map from an exact layout reference, and the game draws the
result over the tile grid. Then tools/artgen/mapfit.py fits the walkable grid to the painting.

The maps and their layout images come from the game itself (all data patches applied, drawn with its own tiles):
MAP_FIT=off godot --headless --path . -s res://tests/map_dump.gd -- tools/artgen/raw/dump

python3 tools/artgen/mapart.py generate [map_id ...]  # all maps when none given; skips maps already painted
python3 tools/artgen/mapart.py process [map_id ...]   # redo the downscale from the raw output
"""
import json
import sys
from concurrent.futures import ThreadPoolExecutor

import numpy as np
from PIL import Image

from common import RAW, ROOT, generate_image

MODEL = "gemini-3-pro-image"  # Nano Banana Pro keeps the layout far better than 2.5 flash
DUMP = RAW / "dump"
OUT = ROOT / "assets" / "maps"
SKIP = {"secretbase"}  # decorated by the player, so it stays tiles
ASPECTS = {"1:1": 1, "4:3": 4 / 3, "3:4": 3 / 4, "3:2": 1.5, "2:3": 2 / 3, "16:9": 16 / 9, "9:16": 9 / 16, "5:4": 1.25, "4:5": 0.8, "21:9": 21 / 9}

COMMON = (
	"crisp GBA pixel art exactly like Pokemon Emerald / Ruby / Sapphire (Hoenn), bright saturated colors, clean dark outlines, "
	"the same oblique top-down view and 16x16 tile scale as those games. "
)


def maps() -> dict:
	return json.loads((DUMP / "maps.json").read_text())


def styles() -> dict:
	return json.loads((ROOT / "data" / "town_styles.json").read_text())


def describe(m: dict) -> str:
	name = m["name"]
	if m.get("underwater"):
		return (f"'{name}', an underwater seafloor area seen while diving, like the Dive areas of Pokemon Emerald: dark blue water tint, "
			"sandy seabed, seaweed, rocky reef walls. ")
	if m.get("cave"):
		return (f"'{name}', a cave or ruins dungeon like Granite Cave and the desert ruins in Pokemon Emerald: rocky cave walls with "
			"layered cliff faces, a dusty walkable floor, dark cave entrances and ladders. ")
	if m.get("interior"):
		return (f"'{name}', the inside of a building in a Pokemon Emerald town (house, shop or healing center): wooden or tiled floor, "
			"back wall with windows and shelves, furniture, rugs, counters and plants exactly where the reference has them. "
			"It is entirely indoors: nothing outdoors at all, no grass, trees, snow or houses outside; the side and front walls are plain dark wall edges, "
			"with the exit doormat at the front. ")
	if m.get("indoor"):
		return (f"'{name}', an indoor hall like a Pokemon Emerald gym, contest hall, department store or tower floor: polished floor, "
			"walls, statues, counters and obstacles exactly where the reference has them. Entirely indoors, nothing outdoors past the walls. ")
	kind = "city" if m.get("city") else ("town" if m.get("town") else "route between towns")
	return (f"'{name}', an outdoor {kind} overworld map in bright daytime light (never dark or night): rich grass texture, Hoenn-style round trees stacking into dense staggered "
		"forest rows, tall grass with distinct leafy tufts, sandy paths with soft edges, buildings with detailed shingled roofs, eaves, "
		"windows and doors, water with highlights and sandy shores, ledges with shaded cliff lips. ")


def prompt(m: dict, about: str) -> str:
	return (
		"This image is the exact top-down layout of " + describe(m)
		+ "Repaint it as a finished, beautiful map in that style: " + COMMON
		+ (f"Place character: {about} " if about else "")
		+ "CRITICAL: keep the layout identical. Every building, door, wall, path, tree, tall-grass patch, ledge, sign, piece of furniture, "
		"rock and water area must stay in exactly the same position and size as in the reference, aligned to the same grid, so walkable "
		"areas still match. Do not add, remove or move anything; open ground stays open ground. Same framing and scale as the reference, "
		"filling the whole image edge to edge. No characters, no people, no creatures, no items on the ground, no text, no labels, no UI, no border."
	)


def aspect_for(w: int, h: int) -> str:
	r = w / h
	return min(ASPECTS, key=lambda k: abs(np.log(ASPECTS[k] / r)))


def size(m: dict) -> tuple[int, int]:
	return len(m["tiles"][0]) * 16, len(m["tiles"]) * 16


def process(mid: str, m: dict) -> None:
	src = RAW / "maps" / f"{mid}.png"
	if not src.exists():
		return
	im = Image.open(src).convert("RGB").resize(size(m), Image.Resampling.LANCZOS)
	im = im.quantize(colors=96, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
	if m.get("indoor"):
		# Like the handheld games, a room's side and front walls are just black; this also drops any outdoor
		# scenery the painter put past the walls. The back wall (top two rows) keeps its art.
		rows = m["tiles"]
		px = im.load()
		for y, row in enumerate(rows):
			for x, ch in enumerate(row):
				edge = x == 0 or x == len(row) - 1 or y == len(rows) - 1
				if ch == "|" and edge and y >= 2:
					for yy in range(y * 16, y * 16 + 16):
						for xx in range(x * 16, x * 16 + 16):
							px[xx, yy] = (0, 0, 0)
	OUT.mkdir(parents=True, exist_ok=True)
	im.save(OUT / f"{mid}.png")


def generate(mid: str, m: dict, about: str) -> None:
	lay = Image.open(DUMP / f"{mid}_layout.png").convert("RGB")
	(RAW / "maps").mkdir(parents=True, exist_ok=True)
	ref = RAW / "maps" / f"{mid}_layout.png"
	k = max(1, 1024 // max(lay.size))
	lay.resize((lay.width * k, lay.height * k), Image.NEAREST).save(ref)
	generate_image(prompt(m, about), RAW / "maps" / f"{mid}.png", [ref], aspect_for(*lay.size), MODEL)
	process(mid, m)


if __name__ == "__main__":
	ms, st = maps(), styles()
	cmd, ids = sys.argv[1], sys.argv[2:] or [k for k in sorted(ms) if k not in SKIP]

	def one(mid: str) -> None:
		m = ms[mid]
		try:
			if cmd == "generate":
				generate(mid, m, st.get(m.get("townId", mid), {}).get("about", ""))
			else:
				process(mid, m)
			print("done", mid, flush=True)
		except Exception as e:
			print("FAIL", mid, e, flush=True)

	with ThreadPoolExecutor(8 if cmd == "generate" else 1) as ex:
		list(ex.map(one, ids))
