"""Map tiles (16x16), battle backgrounds (240x112) and the title backdrop (240x160).

python3 tools/artgen/scenery.py sample [name ...]   # synchronous
python3 tools/artgen/scenery.py process
"""
import json
import sys

from common import RAW, ROOT, ask_vision, generate_image
from pixel import grid_cells, mode_resize, to_image

# Tiles come from 4x4 sheets: drawing many tiles in one picture keeps each one at the
# detail level of a real 16x16 tile (single-tile prompts come out far too detailed).
SHEET_HEAD = (
	"A Game Boy Advance era top-down RPG tileset sheet: an exact grid of 4 columns by 4 rows of square map tiles, all the same size, "
	"touching edge to edge with no gaps, no gutters, no grid lines, no borders and no labels. Each tile is genuine low-resolution pixel art "
	"(16x16 pixels each, shown enlarged), bright Generation 3 handheld monster RPG colors, clean pixel art, no text. "
	"Ground textures (grass, path, water, roof, wall, floor) fill their whole tile and tile seamlessly with copies of themselves. "
)
SHEETS = {
	"outdoor": [
		("grass", "plain short green grass (#88d070) with a few darker blades"),
		("grass2", "plain short green grass (#88d070), slightly different blade pattern"),
		("tallgrass", "dense tall wild grass filling the whole tile, rows of pointed blades, mid green (#58a848)"),
		("flowers", "short green grass with four tiny red, yellow, white and pink flowers"),
		("path", "plain sandy dirt (#e0c890) filling the whole tile with two tiny pebbles, no grass"),
		("water", "calm blue water (#5898e8) filling the whole tile with short light ripple lines"),
		("shore", "blue water with a pale foam shoreline along the top edge"),
		("tree", "one round leafy dark green tree with a short brown trunk on grass, filling the tile"),
		("ledge", "green grass with a small sandy one-way cliff ledge along the bottom quarter"),
		("sign", "a small wooden signpost on green grass"),
		("statue", "a small grey stone creature statue with a gold top on a pedestal, on plain light grey floor"),
		("mat", "a red exit doormat on plain light grey floor"),
		("floor", "plain light grey indoor floor tile (#d8d8d8) with subtle seams"),
		("iwall", "dark purple-grey (#504858) indoor stone wall"),
		("iwall_base", "dark purple-grey indoor wall with a lighter grey baseboard along the bottom half"),
		("wall", "plain cream house wall (#f0e8d0) with a thin shadow line at the bottom"),
	],
	"town": [
		("roof_r", "red roof shingles (#d05040) filling the tile"),
		("roof_p", "pink roof shingles (#e86888) filling the tile"),
		("roof_b", "blue roof shingles (#4878d0) filling the tile"),
		("roof_k", "grey slate roof tiles (#787890) with a gold stripe"),
		("roof_n", "royal purple roof tiles (#7858b8) with a gold stripe"),
		("wall2", "plain cream house wall (#f0e8d0)"),
		("window", "cream house wall with one square blue glass window with a dark frame"),
		("door_h", "a brown wooden front door in a cream wall, filling the tile height"),
		("door_l", "a pink glass sliding door in a cream wall with a small red cross sign above"),
		("door_m", "a blue glass sliding door in a cream wall with a small blue sign above"),
		("door_j", "a heavy gold and grey gym door in a cream wall"),
		("door_u", "a grand purple and gold league door in a cream wall"),
		("grass3", "plain short green grass (#88d070)"),
		("path2", "plain sandy dirt (#e0c890) filling the whole tile, no grass"),
		("tree2", "one round leafy dark green tree with a short brown trunk on grass, filling the tile"),
		("flowers2", "short green grass with three tiny flowers"),
	],
}


def sheet_labels(sheet: str) -> list:
	"""The model does not always keep the requested cell order, so a vision pass names each cell (cached)."""
	cache = RAW / "tiles" / f"{sheet}_labels.json"
	if not cache.exists():
		options = "\n".join(f"- {n}: {d}" for n, d in SHEETS[sheet])
		ans = ask_vision(raw("tiles", sheet), "This tileset image is a 4x4 grid of tiles. For each of the 16 cells in reading order "
			"(row by row, left to right), give the name from this list that best describes it, or null if none fits. "
			"Use each name at most once.\n" + options + "\nAnswer with a JSON array of 16 strings or nulls.")
		cache.write_text(ans)
	return json.loads(cache.read_text())


def sheet_prompt(cells: list[tuple[str, str]]) -> str:
	rows = []
	for r in range(4):
		rows.append(f"Row {r + 1}: " + "; ".join(f"({c + 1}) {cells[r * 4 + c][1]}" for c in range(4)) + ".")
	return SHEET_HEAD + " ".join(rows)


BG_STYLE = (
	"Game Boy Advance era monster RPG battle background, pixel art, wide panoramic scene, no characters, no creatures, "
	"no text, no UI. The bottom half is open flat ground where battle platforms will be drawn; scenery and horizon in the upper half. "
	"Soft bright colors, simple shapes."
)
BACKDROPS = {
	"field": "Open grassy meadow under a bright blue sky with small white clouds and distant green hills.",
	"forest": "Inside a sunlit forest clearing, tall trees and bushes in the background, soft green light.",
	"beach": "Sandy seaside shore with gentle blue ocean waves and a clear sky.",
	"mountain": "Rocky mountain pass with grey cliffs and boulders, pale sky, a few pine trees.",
	"town": "A quiet town square with small colorful houses and trees in the background, paved ground.",
	"gym": "Inside a gym arena, polished floor with a painted battle field, spotlights and banners on the walls.",
	"league": "Inside a grand champion league hall, purple and gold pillars, marble floor, dramatic lights.",
	"night": "A moonlit grassy field at night, dark blue sky with stars.",
}
TITLE = (
	"Title screen backdrop for a Game Boy Advance era monster-collecting adventure RPG called Wildbound: a sweeping view of "
	"green rolling hills, a winding path, a forest and distant mountains under a bright blue sky with clouds. Pixel art, bright, "
	"inviting, sense of adventure. Leave the top third mostly open sky for a logo and the bottom area as open grass. "
	"No text, no characters, no creatures."
)


def raw(kind: str, name: str):
	return RAW / kind / f"{name}.png"


def process() -> None:
	out = ROOT / "assets" / "tiles"
	out.mkdir(parents=True, exist_ok=True)
	for sheet, cells in SHEETS.items():
		if raw("tiles", sheet).exists():
			labels = sheet_labels(sheet)
			ims = grid_cells(raw("tiles", sheet), 4, 4, 0.06)
			for n, _ in cells:
				if n in labels:
					mode_resize(ims[labels.index(n)], (16, 16), 10).convert("RGB").save(out / f"{n}.png")
				else:
					print("WARN no cell for", n)
	out = ROOT / "assets" / "backdrops"
	out.mkdir(parents=True, exist_ok=True)
	for n in BACKDROPS:
		if raw("backdrops", n).exists():
			to_image(raw("backdrops", n), (240, 112), colors=32).save(out / f"{n}.png")
	if raw("title", "title").exists():
		to_image(raw("title", "title"), (240, 160), colors=48).save(ROOT / "assets" / "title.png")


def jobs() -> list[tuple[str, str, str, str]]:
	"""(kind, name, prompt, aspect) for every image."""
	j = [("tiles", n, sheet_prompt(c), "1:1") for n, c in SHEETS.items()]
	j += [("backdrops", n, f"{p} {BG_STYLE}", "21:9") for n, p in BACKDROPS.items()]
	j.append(("title", "title", TITLE, "3:2"))
	return j


if __name__ == "__main__":
	if sys.argv[1] == "sample":
		want = set(sys.argv[2:])
		for kind, n, p, a in jobs():
			if not want or n in want:
				generate_image(p, raw(kind, n), aspect=a)
				print("done", n, flush=True)
	process()
