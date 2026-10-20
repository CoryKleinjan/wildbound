"""Fits a map's walkable grid to its painting (assets/maps/<id>.png), instead of the other way round.

1. A vision model compares the painting (with a labeled cell grid) against the authored grid, three times,
   and lists the cells that look different.
2. Each proposed cell is then checked on its own: a close-up of its neighbourhood with the cell outlined,
   asking what that one cell shows. Only cells whose close-up disagrees with the grid are changed.

Doors, signs and NPC spots never move. The result is data/map_fit.json: {map_id: {"x,y": tile}}, applied on top
of maps.json while the painting is present.

python3 tools/artgen/mapfit.py [map_id ...]        # writes data/map_fit.json and raw/fit/<id>.png previews
"""
import json
import os
import sys
from concurrent.futures import ThreadPoolExecutor

from PIL import Image, ImageDraw, ImageFont

from common import RAW, ROOT, ask_vision

MODEL = "gemini-3.1-pro-preview"  # whole-map comparison
CELL_MODEL = "gemini-3.5-flash"  # one-cell close-ups: easy, and there are many
PASSES = int(os.environ.get("FIT_PASSES", "3"))  # whole-map proposal runs; 1 is about a third of the cost
FIT = ROOT / "data" / "map_fit.json"
BUILDING = "rpbknw"
DOORS = "hlmju"
OUTDOOR = {
	".": "short grass or plain ground (walkable)",
	",": "tall grass, the leafy tufts where wild creatures hide (walkable)",
	"=": "dirt or sand path (walkable)",
	"F": "flowers on grass (walkable)",
	"a": "sand (walkable)",
	"#": "tree, bush or forest (blocked)",
	"~": "water (blocked)",
	"v": "one-way ledge: a low cliff lip you hop down",
	"w": "any part of a building, roof or wall (blocked)",
}
CAVE = {
	"g": "cave or ruins floor (walkable)",
	"a": "sand (walkable)",
	"x": "rock wall, cliff or boulder pile (blocked)",
	"~": "water (blocked)",
}
INDOOR = {
	"_": "floor, rug or mat (walkable)",
	"|": "wall (blocked)",
	"o": "furniture, counter, shelf, plant, statue or any obstacle (blocked)",
}
# Cells the fit may rewrite, per kind of map; every other tile (doors, signs, ladders, soil, furniture with a use) stays.
EDITABLE = {"out": set(".,=Fa#~vw") | set(BUILDING), "cave": set("gax~#"), "in": set("_o|")}
# A building cell is written as plain wall.
GROUP = {c: "w" for c in BUILDING}


def kind(m: dict) -> str:
	return "cave" if m.get("cave") else ("in" if m.get("indoor") else "out")


def legend_for(m: dict) -> dict:
	return {"cave": CAVE, "in": INDOOR, "out": OUTDOOR}[kind(m)]


def legend(m: dict) -> str:
	return "\n".join(f"{k} {v}" for k, v in legend_for(m).items())


def grid_image(mid: str, W: int, H: int) -> "Path":
	S = 64
	im = Image.open(ROOT / "assets" / "maps" / f"{mid}.png").convert("RGB").resize((W * S, H * S), Image.NEAREST)
	d = ImageDraw.Draw(im)
	f = ImageFont.load_default(size=14)
	for x in range(W + 1):
		d.line([(x * S, 0), (x * S, H * S)], fill=(255, 255, 255))
	for y in range(H + 1):
		d.line([(0, y * S), (W * S, y * S)], fill=(255, 255, 255))
	for y in range(H):
		for x in range(W):
			d.text((x * S + 3, y * S + 2), f"{x},{y}", fill=(255, 255, 0), font=f, stroke_width=2, stroke_fill=(0, 0, 0))
	p = RAW / "fit" / f"{mid}_grid.png"
	p.parent.mkdir(parents=True, exist_ok=True)
	im.save(p)
	return p


def proposals(mid: str, m: dict) -> set[tuple[int, int]]:
	rows = m["tiles"]
	H, W = len(rows), len(rows[0])
	p = grid_image(mid, W, H)
	q = (f"This is a painted top-down game map with a white grid of {W}x{H} cells; each cell is labeled 'x,y'.\n"
		"Below is the current collision grid for it, one character per cell, row y=0 first:\n"
		+ "\n".join(f"{y:2d} {r}" for y, r in enumerate(rows))
		+ f"\nLegend:\n{legend(m)}\nBuilding letters r,p,b,k,n are all 'w'. Other letters are special objects (doors, signs, ladders, furniture) and are right.\n"
		"Find every cell where the grid does NOT match what is painted (for example tall grass painted where the grid says "
		"short grass, a building shifted by a cell, water painted as sand, a path where the grid has grass). "
		"A cell counts as tree/building/water if that covers most of the cell.\n"
		'Return JSON: a list of {"x": int, "y": int, "tile": "<legend char>"} only for the cells that differ.')
	cells: set[tuple[int, int]] = set()

	def run(_):
		try:
			return json.loads(ask_vision(p, q, MODEL))
		except Exception as e:  # one bad run is fine, the others still count
			print("WARN", mid, e)
			return []

	with ThreadPoolExecutor(3) as ex:
		for res in ex.map(run, range(PASSES)):
			cells |= {(int(e["x"]), int(e["y"])) for e in res if 0 <= int(e["x"]) < W and 0 <= int(e["y"]) < H}
	return cells


def closeup(mid: str, x: int, y: int) -> "Path":
	S, R = 48, 2
	src = Image.open(ROOT / "assets" / "maps" / f"{mid}.png").convert("RGB")
	im = Image.new("RGB", ((2 * R + 1) * 16, (2 * R + 1) * 16), (0, 0, 0))
	im.paste(src.crop(((x - R) * 16, (y - R) * 16, (x + R + 1) * 16, (y + R + 1) * 16)), (0, 0))
	im = im.resize((im.width * S // 16, im.height * S // 16), Image.NEAREST)
	d = ImageDraw.Draw(im)
	d.rectangle([R * S - 2, R * S - 2, (R + 1) * S + 1, (R + 1) * S + 1], outline=(255, 0, 0), width=3)
	p = RAW / "fit" / "cells" / f"{mid}_{x}_{y}.png"
	p.parent.mkdir(parents=True, exist_ok=True)
	im.save(p)
	return p


def check(mid: str, m: dict, x: int, y: int) -> str | None:
	q = ("This is a close-up of a top-down game map. What does the cell inside the red square show? "
		"Judge only what covers most of that one square, using the surrounding cells as context.\n"
		f"Options:\n{legend(m)}\n"
		'Return JSON: {"tile": "<one option character>"}')
	try:
		t = json.loads(ask_vision(closeup(mid, x, y), q, CELL_MODEL)).get("tile")
	except Exception as e:
		print("WARN", mid, x, y, e)
		return None
	return t if t in legend_for(m) else None


def fit(mid: str, m: dict) -> dict:
	rows = m["tiles"]
	keep = set(m.get("doors", {})) | set(m.get("signs", {})) | set(m.get("warps", {})) | set(m.get("berries", {}))
	keep |= set(m.get("soil", [])) | set(m.get("secretSpots", []) if isinstance(m.get("secretSpots"), list) else m.get("secretSpots", {}))
	for key in ("npcs", "trainers", "items", "statics"):
		keep |= {f"{n['x']},{n['y']}" for n in m.get(key, []) if "x" in n}
	editable = EDITABLE[kind(m)]
	ok = lambda x, y: f"{x},{y}" not in keep and rows[y][x] in editable
	cand = [(x, y) for x, y in sorted(proposals(mid, m)) if ok(x, y)]
	H, W = len(rows), len(rows[0])
	out: dict[str, str] = {}
	done: set[tuple[int, int]] = set()
	# Check the proposals, then the neighbours of every changed cell, until nothing new changes
	# (the overall comparison tends to catch a patch but miss its edges).
	while cand:
		done |= set(cand)
		with ThreadPoolExecutor(8) as ex:
			seen = list(ex.map(lambda c: check(mid, m, *c), cand))
		nxt = set()
		for (x, y), t in zip(cand, seen):
			cur = rows[y][x]
			if t == "v" and (y + 1 >= H or rows[y + 1][x] == "#"):
				t = "#"  # a "ledge" into the tree line is just the forest edge
			if t is not None and t != GROUP.get(cur, cur):
				out[f"{x},{y}"] = t
				nxt |= {(x + dx, y + dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))}
		cand = [(x, y) for x, y in sorted(nxt - done) if 0 <= x < W and 0 <= y < H
			and ok(x, y)]
	return out


def preview(mid: str, changes: dict) -> None:
	im = Image.open(ROOT / "assets" / "maps" / f"{mid}.png").convert("RGB")
	im = im.resize((im.width * 2, im.height * 2), Image.NEAREST)
	d = ImageDraw.Draw(im)
	for k, ch in changes.items():
		x, y = map(int, k.split(","))
		d.rectangle([x * 32, y * 32, x * 32 + 31, y * 32 + 31], outline=(255, 0, 0))
		d.text((x * 32 + 12, y * 32 + 8), ch, fill=(255, 255, 255), stroke_width=1, stroke_fill=(0, 0, 0))
	im.save(RAW / "fit" / f"{mid}.png")


def protected(maps: dict) -> dict[str, set[tuple[int, int]]]:
	"""Cells the fit must leave alone, per map: the map's edges (where connections arrive), every spot where a warp
	lands, and everything next to a person, item, sign, door or warp, so they stay reachable and can be talked to."""
	out: dict[str, set[tuple[int, int]]] = {k: set() for k in maps}
	near = lambda x, y: {(x + dx, y + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1)}
	for mid, m in maps.items():
		rows = m["tiles"]
		H, W = len(rows), len(rows[0])
		out[mid] |= {(x, y) for x in range(W) for y in (0, 1, H - 2, H - 1)} | {(x, y) for y in range(H) for x in (0, 1, W - 2, W - 1)}
		spots = [tuple(map(int, k.split(","))) for key in ("doors", "signs", "warps", "berries") for k in m.get(key, {})]
		spots += [tuple(map(int, k.split(","))) for k in m.get("soil", [])]
		for key in ("npcs", "trainers", "items", "statics"):
			spots += [(n["x"], n["y"]) for n in m.get(key, []) if "x" in n]
		for x, y in spots:
			out[mid] |= near(x, y)
		for w in m.get("warps", {}).values():
			if w.get("map") in out:
				out[w["map"]] |= near(int(w["x"]), int(w["y"]))
	return out


def clean(data: dict, maps: dict) -> dict:
	keep = protected(maps)
	return {mid: {k: t for k, t in ch.items() if tuple(map(int, k.split(","))) not in keep.get(mid, set())} for mid, ch in data.items()}


if __name__ == "__main__":
	maps = json.loads((RAW / "dump" / "maps.json").read_text())  # see mapart.py
	data = json.loads(FIT.read_text()) if FIT.exists() else {}
	if sys.argv[1:] == ["clean"]:
		before = sum(map(len, data.values()))
		data = clean(data, maps)
		FIT.write_text(json.dumps(data, indent="\t", sort_keys=True) + "\n")
		print("kept", sum(map(len, data.values())), "of", before)
		sys.exit()
	ids = sys.argv[1:] or sorted(p.stem for p in (ROOT / "assets" / "maps").glob("*.png") if p.stem not in data)
	def one(mid: str) -> None:
		data[mid] = clean({mid: fit(mid, maps[mid])}, maps)[mid]
		preview(mid, data[mid])
		print(mid, len(data[mid]), "cells changed", flush=True)
		FIT.write_text(json.dumps(data, indent="\t", sort_keys=True) + "\n")

	with ThreadPoolExecutor(10) as ex:
		list(ex.map(one, ids))
