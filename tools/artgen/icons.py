"""Small pixel icons (24x24), drawn by Nano Banana Pro on a pixel-grid template, 16 per sheet:
every item (TMs share one disc, tinted by type in the game), the Egg, and the eight gym badges.
Output: assets/icons/<id>.png.

python3 tools/artgen/icons.py generate     # all sheets (skips sheets already generated)
python3 tools/artgen/icons.py process
"""
import json
import sys
from concurrent.futures import ThreadPoolExecutor

import numpy as np
from PIL import Image

from common import RAW, ROOT, generate_image, misc

MODEL = "gemini-3-pro-image"
OUT = ROOT / "assets" / "icons"
N, PX, S, GAP = 4, 24, 10, 4  # 4x4 boxes of 24x24 sprite pixels, each shown as a 10x10 square
CW = N * PX + (N + 1) * GAP


def subjects() -> list[tuple[str, str]]:
	items = json.loads((ROOT / "data" / "items.json").read_text())
	for k, v in json.loads((ROOT / "data" / "features.json").read_text())["items"].items():
		items.setdefault(k, {}).update(v)
	out = []
	for k, v in items.items():
		if v.get("effect", {}).get("kind") == "tm":
			continue
		out.append((k, f"{v.get('name', k)} ({v.get('desc', '')})"))
	out.append(("tm", "a TM: a round shiny data disc in a plain white/grey color with a small hole in the middle"))
	out.append(("egg", "a creature Egg: cream white with green spots"))
	for g in misc()["gyms"]:
		out.append((f"badge{g['badge']}", f"the {g['badgeName']} gym badge: a small shiny metal badge themed on the {g['type']} type"))
	return out


def origin(i: int) -> tuple[int, int]:
	return GAP + (i % N) * (PX + GAP), GAP + (i // N) * (PX + GAP)


def template() -> "Path":
	p = RAW / "icons" / "_template.png"
	im = np.zeros((CW * S, CW * S, 3), np.uint8)
	im[:] = (255, 0, 255)
	for i in range(N * N):
		x0, y0 = origin(i)
		box = im[y0 * S:(y0 + PX) * S, x0 * S:(x0 + PX) * S]
		box[:] = (240, 120, 240)
		box[::S, :] = (200, 60, 200)
		box[:, ::S] = (200, 60, 200)
	p.parent.mkdir(parents=True, exist_ok=True)
	Image.fromarray(im).save(p)
	return p


# Window frames for the menus, text box and battle boxes: drawn as nine-slice textures (8 px corners) by Gfx.panel.
UI = [
	("panel_light", "a menu window frame like the Pokemon Emerald start menu and text box: a rounded frame 3-4 pixels thick in "
		"light blue-grey and white with a dark outline, hugging the edges of the box, and a plain flat off-white inside"),
	("panel_dark", "the same kind of rounded window frame but dark navy blue with a lighter blue border, plain flat dark navy inside"),
	("panel_battle", "a Pokemon Emerald battle HP info box frame: a rounded frame 3 pixels thick in dark green-grey with a light "
		"cream bevel, hugging the edges of the box, and a plain flat cream inside"),
	("panel_sign", "a signpost text window frame: a rounded wooden-brown frame 3 pixels thick hugging the box edges, plain flat cream inside"),
]
FRAMES = {k for k, _ in UI}

# Battle effects drawn over the target: one per move type when a move hits, and the stat/status/heal effects.
FX_LOOK = {
	"Normal": "a white star-shaped impact burst", "Fire": "a burst of orange and yellow flames", "Water": "a splash of blue water droplets",
	"Grass": "a swirl of sharp green leaves", "Electric": "crackling yellow lightning bolts", "Ice": "sharp pale-blue ice shards",
	"Fighting": "a punching fist impact with orange burst lines", "Poison": "purple poison bubbles", "Ground": "brown rocks and dirt bursting up",
	"Flying": "white wind slashes and feathers", "Psychic": "pink psychic rings rippling outward", "Bug": "a green buzzing swarm slash",
	"Rock": "grey jagged rocks smashing", "Ghost": "a dark purple ghostly flame wisp", "Dragon": "a blue and purple dragon energy claw slash",
	"Dark": "a black crescent bite slash", "Steel": "silver metal sparks and a shining slash", "Fairy": "pink sparkles and hearts",
}
FX = [(f"fx_{t.lower()}", f"a battle move hit effect: {d}, bold and readable, filling most of the box") for t, d in FX_LOOK.items()] + [
	("fx_stat_up", "a battle effect: orange upward arrows and sparkles rising"),
	("fx_stat_down", "a battle effect: blue downward arrows sinking"),
	("fx_heal", "a battle effect: green healing sparkles and plus signs"),
	("fx_status", "a battle effect: purple swirling status spiral with small stars"),
]


def prompt(batch: list[tuple[str, str]]) -> str:
	lines = "\n".join(f"Row {i // N + 1}, column {i % N + 1}: {d}" for i, (_, d) in enumerate(batch))
	frames = all(k in FRAMES for k, _ in batch)
	return (
		("Pokemon Emerald (Game Boy Advance) user interface window frames, each one filling its whole box edge to edge "
			"(they will be stretched as nine-slice frames, so the corners are 8 pixels and the edges repeat). " if frames
			else "Pokemon Emerald (Game Boy Advance) battle effect sprites. " if batch[0][0].startswith("fx_")
			else "Pokemon Emerald (Game Boy Advance) bag item icons. ")
		+ "The image is the exact canvas to draw on: a 4 by 4 grid of boxes, "
		"each exactly 24 by 24 pixels, where every small grid square is ONE sprite pixel. Draw one " + ("frame" if frames else "icon")
		+ " inside each box, centered, "
		"filling each grid square with a single flat color: authentic Gen 3 item icon style, 1-pixel dark outline, 3-4 shades per color, "
		"simple readable shapes, no anti-aliasing. Outside the icons every square is plain magenta #FF00FF; remove the grid lines. "
		"Leave boxes without a subject empty. No text or letters anywhere.\n" + lines
	)


def batches() -> list[list[tuple[str, str]]]:
	s = subjects()
	return [s[i:i + N * N] for i in range(0, len(s), N * N)] + [UI, FX[:16], FX[16:]]


def generate(k: int, batch: list) -> None:
	generate_image(prompt(batch), RAW / "icons" / f"sheet{k:02d}.png", [template()], "1:1", MODEL)


def process(k: int, batch: list) -> None:
	src = RAW / "icons" / f"sheet{k:02d}.png"
	if not src.exists():
		return
	rgb = np.array(Image.open(src).convert("RGB").resize((CW * S, CW * S), Image.Resampling.NEAREST)).astype(int)
	OUT.mkdir(parents=True, exist_ok=True)
	for i, (id_, _) in enumerate(batch):
		x0, y0 = origin(i)
		icon = np.zeros((PX, PX, 4), np.uint8)
		for y in range(PX):
			for x in range(PX):
				blk = rgb[(y0 + y) * S + 3:(y0 + y + 1) * S - 3, (x0 + x) * S + 3:(x0 + x + 1) * S - 3].reshape(-1, 3)
				r, g, b = c = np.median(blk, axis=0)
				if r > 110 and b > 110 and g < 0.7 * min(r, b):
					continue
				icon[y, x] = (*c.astype(np.uint8), 255)
		if (icon[..., 3] > 0).mean() < 0.05:
			print("WARN empty icon", id_)
			continue
		dest = ROOT / "assets" / ("ui" if id_ in FRAMES else ("fx" if id_.startswith("fx_") else "icons"))
		dest.mkdir(parents=True, exist_ok=True)
		Image.fromarray(icon, "RGBA").save(dest / f"{id_}.png")


if __name__ == "__main__":
	bs = batches()
	if sys.argv[1] == "generate":
		with ThreadPoolExecutor(6) as ex:
			list(ex.map(lambda kb: (generate(*kb), print("got", kb[0], flush=True)), enumerate(bs)))
	for k, b in enumerate(bs):
		process(k, b)
	print(len(bs), "sheets")
