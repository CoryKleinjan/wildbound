"""Emerald-style overworld art: ground tile sheet, 2x2 trees, whole buildings and door tiles.

python3 tools/artgen/emerald.py generate   # synchronous (a handful of images)
python3 tools/artgen/emerald.py process    # -> assets/tiles/*.png, assets/buildings/*.png
"""
import json
import sys

import numpy as np
from PIL import Image

from common import RAW, ROOT, ask_vision, generate_image
from pixel import trim_light_border, grid_cells, key_background, mode_resize, _largest_blobs

EM = ("in the visual style of the Pokemon Emerald / Ruby / Sapphire (Game Boy Advance, Hoenn region) overworld tileset: "
	"saturated bright colors, light green grass with tiny darker green tufts, crisp 1-pixel dark outlines on objects, soft 2-3 tone shading, "
	"light from the top-left. Original art, no text, no characters.")
HEAD = ("A top-down RPG tileset sheet: an exact grid of 4 columns by 4 rows of square map tiles, all the same size, touching edge to edge "
	"with no gaps, no gutters, no grid lines and no labels. Each tile is genuine low-resolution pixel art (16x16 pixels each, shown enlarged), ")

GROUND = [
	("grass", "plain short grass (#88d070) with a few tiny darker tufts"),
	("grass2", "plain short grass, different tuft placement"),
	("tallgrass", "tall wild grass: four leafy grass tufts with dark green outlines, darker green between them, filling the tile"),
	("flowers", "short grass with two small red and white flowers"),
	("path", "plain light sandy dirt path (#e0c890) filling the whole tile"),
	("path_top", "sandy path with a soft grass edge along the top"),
	("path_left", "sandy path with a soft grass edge along the left"),
	("sand", "sandy beach sand with tiny specks"),
	("water", "calm blue sea water (#5898e8) filling the tile with small white ripple marks"),
	("shore", "blue water with a sandy shoreline along the top"),
	("ledge", "grass with a one-way rocky ledge along the bottom: a light top lip and a darker brown cliff face"),
	("sign", "a small wooden signpost with a dark outline on grass"),
	("fence", "a short wooden fence segment on grass"),
	("floor", "a light grey stone floor tile for indoors"),
	("iwall", "a dark purple-grey indoor wall"),
	("mat", "a red exit doormat on a light grey floor"),
]
DOORS = [
	("door_h", "a brown wooden house front door set in a cream wall, filling the tile"),
	("door_l", "a pink glass sliding door set in a cream wall, filling the tile"),
	("door_m", "a blue glass sliding door set in a cream wall, filling the tile"),
	("door_j", "a heavy grey metal double door with gold trim set in a grey stone wall, filling the tile"),
	("door_u", "a grand purple double door with gold trim set in a white marble wall, filling the tile"),
	("wall", "a plain cream house wall"),
	("window", "a cream house wall with one small square window with a dark frame"),
	("statue", "a small grey stone creature statue on a pedestal on light grey floor"),
	("flowers2", "short grass with three tiny yellow and pink flowers"),
	("rock", "a small grey boulder with a dark outline on grass"),
	("bush", "a small round green bush with a dark outline on grass"),
	("tallgrass2", "tall wild grass tufts with dark green outlines, filling the tile, slightly different arrangement"),
	("water2", "calm blue sea water filling the tile with small white ripple marks in different spots"),
	("shore_left", "blue water with a sandy shoreline along the left edge"),
	("path_right", "sandy path with a soft grass edge along the right"),
	("path_bottom", "sandy path with a soft grass edge along the bottom"),
]
# building type: (tiles wide, tiles tall incl. the wall row, description)
BUILDINGS = {
	"house": (4, 3, "a cozy family house with a big red sloped roof (#d05040)"),
	"lodge": (5, 3, "a creature healing center (rest lodge) with a pink roof (#e86888) and a red cross sign on the roof"),
	"mart": (5, 3, "a small shop with a blue roof (#4878d0) and a blue shop sign on the roof"),
	"gym": (7, 4, "a large gym building with a grey slate roof (#787890) and a big gold emblem on the roof"),
	"league": (7, 4, "a grand champion league hall with a royal purple roof (#7858b8), gold trim and pillars"),
}


def sheet_prompt(cells):
	return HEAD + EM + " " + " ".join(
		f"Row {r + 1}: " + "; ".join(f"({c + 1}) {cells[r * 4 + c][1]}" for c in range(4)) + "." for r in range(4))


def building_prompt(kind):
	w, h, desc = BUILDINGS[kind]
	return (f"A single RPG town building seen from the front and slightly above, as on an overworld map: {desc}. "
		f"It is genuine low-resolution pixel art exactly {w * 16} pixels wide and {h * 16} pixels tall, shown enlarged with crisp square pixels. "
		f"The roof covers the top {h - 1} of {h} rows; the bottom {16} pixel row is the front wall with small windows. "
		"Draw the front wall WITHOUT any door (a door is added separately). Flat front elevation: no side walls visible, rectangular outline, "
		"the building fills the whole image width. " + EM +
		" Plain solid flat magenta (#FF00FF) background around it, no ground, no shadow.")


def generate():
	generate_image(sheet_prompt(GROUND), RAW / "tiles" / "em_ground.png")
	generate_image(sheet_prompt(DOORS), RAW / "tiles" / "em_doors.png")
	generate_image(
		"A top-down RPG sprite sheet of 4 big trees in a 2 by 2 grid, each tree filling its whole square cell edge to edge with no gaps. "
		"Each tree is genuine low-resolution pixel art, 32x32 pixels (a 2x2 tile tree), shown enlarged: a big round puffy dark green canopy with "
		"lighter green highlights on the upper left, a dark outline, and a short brown trunk at the bottom center, on light green grass. "
		"The canopy reaches the left, right and top edges of its cell so that trees placed side by side form a dense forest wall. " + EM,
		RAW / "tiles" / "em_trees.png")
	for kind, (w, h, _) in BUILDINGS.items():
		generate_image(building_prompt(kind), RAW / "buildings" / f"{kind}.png", aspect="4:3" if w * 3 <= h * 4 + 1 else "16:9")


def labels(sheet, cells):
	cache = RAW / "tiles" / f"{sheet}_labels.json"
	if not cache.exists():
		options = "\n".join(f"- {n}: {d}" for n, d in cells)
		cache.write_text(ask_vision(RAW / "tiles" / f"{sheet}.png",
			"This tileset image is a 4x4 grid of tiles. For each of the 16 cells in reading order (row by row, left to right), give the "
			"name from this list that best describes it, or null if none fits. Use each name at most once.\n" + options +
			"\nAnswer with a JSON array of 16 strings or nulls."))
	return json.loads(cache.read_text())


def process():
	out = ROOT / "assets" / "tiles"
	out.mkdir(parents=True, exist_ok=True)
	for sheet, cells in (("em_ground", GROUND), ("em_doors", DOORS)):
		src = RAW / "tiles" / f"{sheet}.png"
		if not src.exists():
			continue
		lab = labels(sheet, cells)
		ims = grid_cells(src, 4, 4, 0.09)
		for n, _ in cells:
			if n in lab:
				mode_resize(trim_light_border(ims[lab.index(n)]), (16, 16), 12).convert("RGB").save(out / f"{n}.png")
			else:
				print("WARN no cell for", n)
	src = RAW / "tiles" / "em_trees.png"
	if src.exists():
		for i, im in enumerate(grid_cells(src, 2, 2, 0.02)):
			im = trim_light_border(im)
			rgb = np.array(im.convert("RGB"))
			mask = _largest_blobs(key_background(rgb, tol=60), 0.2)  # drop the grass around the tree
			im = Image.fromarray(np.dstack([rgb, np.where(mask, 255, 0).astype(np.uint8)]), "RGBA")
			mode_resize(im, (32, 32), 14).save(out / f"tree32_{i}.png")
	bout = ROOT / "assets" / "buildings"
	bout.mkdir(parents=True, exist_ok=True)
	for kind, (w, h, _) in BUILDINGS.items():
		src = RAW / "buildings" / f"{kind}.png"
		if not src.exists():
			continue
		rgb = np.array(Image.open(src).convert("RGB"))
		mask = _largest_blobs(key_background(rgb), 0.2)
		ys, xs = np.nonzero(mask)
		rgba = np.dstack([rgb, np.where(mask, 255, 0).astype(np.uint8)])[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
		img = mode_resize(Image.fromarray(rgba, "RGBA"), (w * 16, h * 16), 16)
		img.save(bout / f"{kind}.png")


if __name__ == "__main__":
	{"generate": generate, "process": process}[sys.argv[1]]()
	if sys.argv[1] == "generate":
		process()
