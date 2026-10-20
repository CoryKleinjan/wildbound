"""Overworld walking sprites in the Emerald style, drawn by Nano Banana Pro as a 3x3 sheet
(rows: facing down, up, left; columns: standing, left foot forward, right foot forward), then reduced
to real 16x24 pixel frames. Output: assets/trainers/<palette>_walk.png, 48x72 (3 columns x 3 rows).

python3 tools/artgen/walkers.py generate [palette ...]   # all palettes when none given
python3 tools/artgen/walkers.py process [palette ...]
"""
import sys
from concurrent.futures import ThreadPoolExecutor

import numpy as np
from PIL import Image

from common import RAW, ROOT, generate_image, misc
from pixel import _largest_blobs, erode, key_background, mode_resize
from trainers import WHO, colors

MODEL = "gemini-3-pro-image"
OUT = ROOT / "assets" / "trainers"
FW, FH = 16, 24


def prompt(name: str, pal: dict) -> str:
	return (
		f"A Pokemon Emerald (Game Boy Advance) overworld walking sprite sheet of {WHO.get(name, 'a trainer')}. "
		f"Colors: {colors(pal)}. "
		"Exactly 9 sprites of the same character in a 3 by 3 grid, evenly spaced with lots of empty space between them. "
		"Row 1: facing DOWN toward the viewer. Row 2: facing UP, away from the viewer (back of the head). Row 3: facing LEFT in side profile. "
		"Column 1: standing still. Column 2: mid-step with the left foot forward. Column 3: mid-step with the right foot forward. "
		"Authentic Gen 3 overworld sprite proportions exactly like the player and NPC sprites in Pokemon Ruby, Sapphire and Emerald: "
		"each sprite is about 16 pixels wide and 22 pixels tall, a large round head about half the height, short body, tiny legs, "
		"1-pixel dark outline, 2-3 shades per color, drawn as real low-resolution pixel art and enlarged with big crisp square pixels "
		"(every sprite pixel is the same size, no anti-aliasing, no gradients). "
		"Plain solid flat magenta (#FF00FF) background, no shadows, no ground, no grid lines, no text, no labels."
	)


# The template the model fills: a 72x96 canvas (3:4) of 16x24 cells, shown at 12x with each pixel's grid.
S, GAP = 12, 6
CW, CH = 72, 96


def cell_origin(i: int) -> tuple[int, int]:
	return GAP + (i % 3) * (FW + GAP), GAP + (i // 3) * (FH + GAP)


def template() -> "Path":
	p = RAW / "walk" / "_template.png"
	im = np.zeros((CH * S, CW * S, 3), np.uint8)
	im[:] = (255, 0, 255)
	for i in range(9):
		x0, y0 = cell_origin(i)
		box = im[y0 * S:(y0 + FH) * S, x0 * S:(x0 + FW) * S]
		box[:] = (240, 120, 240)
		box[::S, :] = (200, 60, 200)
		box[:, ::S] = (200, 60, 200)
	p.parent.mkdir(parents=True, exist_ok=True)
	Image.fromarray(im).save(p)
	return p


def generate(name: str, pal: dict) -> None:
	ref = OUT / f"{name}.png"
	refs = [template()] + ([ref] if ref.exists() else [])
	generate_image(prompt(name, pal) + (
		" The first image is the exact canvas to draw on: nine boxes, each exactly 16 pixels wide and 24 pixels tall, where every small grid square is ONE sprite pixel. "
		"Draw one sprite inside each box, filling each grid square with a single flat color, the character about 14 squares wide and 22 squares tall standing at the bottom of its box. "
		"Keep the boxes in the same places; outside the character, every square is plain magenta #FF00FF. Remove the grid lines in the final image."
		+ (" The second image shows the character's design: match it." if len(refs) > 1 else "")),
		RAW / "walk" / f"{name}.png", refs, "3:4", MODEL)


def _runs(flags) -> list[tuple[int, int]]:
	out, start = [], None
	for i, f in enumerate(list(flags) + [False]):
		if f and start is None:
			start = i
		elif not f and start is not None:
			out.append((start, i))
			start = None
	return out


def _three(runs: list[tuple[int, int]]) -> list[tuple[int, int]]:
	"""Merge small gaps until three groups remain (a sprite can have a gap between its legs)."""
	runs = list(runs)
	while len(runs) > 3:
		gaps = [runs[i + 1][0] - runs[i][1] for i in range(len(runs) - 1)]
		i = int(np.argmin(gaps))
		runs[i:i + 2] = [(runs[i][0], runs[i + 1][1])]
	return runs


def frames_grid(name: str) -> Image.Image | None:
	"""Reads the sprite pixels straight off the template grid: the most common color of each square's center."""
	src = RAW / "walk" / f"{name}.png"
	if not src.exists():
		return None
	rgb = np.array(Image.open(src).convert("RGB").resize((CW * S, CH * S), Image.Resampling.NEAREST)).astype(int)
	sheet = np.zeros((FH * 3, FW * 3, 4), np.uint8)
	for i in range(9):
		x0, y0 = cell_origin(i)
		for y in range(FH):
			for x in range(FW):
				blk = rgb[(y0 + y) * S + 3:(y0 + y + 1) * S - 3, (x0 + x) * S + 3:(x0 + x + 1) * S - 3].reshape(-1, 3)
				c = np.median(blk, axis=0)
				r, g, b = c
				if r > 150 and b > 150 and g < 0.75 * min(r, b):  # magenta (any shade) = empty
					continue
				sheet[(i // 3) * FH + y, (i % 3) * FW + x] = (*c.astype(np.uint8), 255)
	return Image.fromarray(sheet, "RGBA")


def frames(name: str) -> Image.Image | None:
	src = RAW / "walk" / f"{name}.png"
	if not src.exists():
		return None
	rgb = np.array(Image.open(src).convert("RGB"))
	mask = _largest_blobs(key_background(rgb), 0.02)
	rows = _three([r for r in _runs(mask.any(axis=1)) if r[1] - r[0] > 8])
	if len(rows) != 3:
		print("WARN", name, "rows", len(rows))
		return None
	rgba = np.dstack([rgb, np.where(erode(mask, 1), 255, 0).astype(np.uint8)])
	boxes = []
	for y0, y1 in rows:
		cols = _three([c for c in _runs(mask[y0:y1].any(axis=0)) if c[1] - c[0] > 4])
		if len(cols) != 3:
			print("WARN", name, "cols", len(cols))
			return None
		for x0, x1 in cols:
			sub = mask[y0:y1, x0:x1]
			ys = np.where(sub.any(axis=1))[0]
			boxes.append((x0, y0 + ys[0], x1, y0 + ys[-1] + 1))
	# one scale for every frame: the tallest standing pose becomes 22 px
	k = 22 / max(b[3] - b[1] for b in boxes)
	sheet = Image.new("RGBA", (FW * 3, FH * 3))
	for i, (x0, y0, x1, y1) in enumerate(boxes):
		crop = Image.fromarray(rgba[y0:y1, x0:x1], "RGBA")
		w, h = min(FW, max(1, round((x1 - x0) * k))), min(FH, max(1, round((y1 - y0) * k)))
		small = mode_resize(crop, (w, h), 16)
		sheet.paste(small, ((i % 3) * FW + (FW - w) // 2, (i // 3) * FH + FH - h), small)
	return sheet


def process(name: str) -> None:
	s = frames_grid(name)
	if s:
		s.save(OUT / f"{name}_walk.png")


if __name__ == "__main__":
	pals = misc()["palettes"]
	cmd, names = sys.argv[1], sys.argv[2:] or list(pals)
	if cmd == "generate":
		with ThreadPoolExecutor(6) as ex:
			list(ex.map(lambda n: (generate(n, pals[n]), print("got", n, flush=True)), names))
	for n in names:
		process(n)
		print("done", n, flush=True)
