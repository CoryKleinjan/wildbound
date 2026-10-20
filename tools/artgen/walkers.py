"""Overworld walking sprites in the Emerald style, drawn by Nano Banana Pro as a 3x3 sheet
(rows: facing down, up, left; columns: standing, left foot forward, right foot forward), then reduced
to real 16x24 pixel frames (the sprite fills the bottom 16x20, chibi like Emerald's NPCs). Every frame's facing is
checked by a vision model; left/right mix-ups are mirrored, other mistakes retried. Output: assets/trainers/<palette>_walk.png, 48x72 (3 columns x 3 rows).

python3 tools/artgen/walkers.py generate [palette ...]   # all palettes when none given
python3 tools/artgen/walkers.py process [palette ...]
python3 tools/artgen/walkers.py audit [palette ...]      # re-check the facing of the saved sheets (walk_facing.json)
"""
import hashlib
import json
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import numpy as np
from PIL import Image

from common import RAW, ROOT, ask_vision, generate_image, misc
from pixel import _largest_blobs, erode, key_background, mode_resize
from trainers import WHO, colors

MODEL = "gemini-3-pro-image"
OUT = ROOT / "assets" / "trainers"
FW, FH = 16, 24
BH = 20  # drawn height inside each frame; the top rows stay empty
FACING = OUT / "walk_facing.json"
WANT = ["down"] * 3 + ["up"] * 3 + ["left"] * 3


def prompt(name: str, pal: dict) -> str:
	return (
		f"A Pokemon Emerald (Game Boy Advance) overworld walking sprite sheet of {WHO.get(name, 'a trainer')}. "
		f"Colors: {colors(pal)}. "
		"Row 1: all three sprites face DOWN toward the viewer (we see the face). Row 2: all three face UP, away from the viewer "
		"(we see the back of the head, no face). Row 3: all three face LEFT in side profile (the nose points to the LEFT edge of the image). "
		"Column 1: standing still. Column 2: mid-step with one foot forward. Column 3: mid-step with the other foot forward. "
		"Every sprite in a row faces the same way. "
		"Exact Gen 3 chibi overworld proportions, like Brendan, May and the NPCs in Pokemon Ruby, Sapphire and Emerald: short and stocky, "
		"a big round head (with hair or hat) that takes up the top HALF of the sprite and is almost as wide as the box, a small square body, "
		"very short stubby legs of 2-3 pixels, small hands at the sides. Not tall, not slim, no long legs. "
		"1-pixel dark outline, 2-3 shades per color, no anti-aliasing, no gradients. "
		"No shadows, no ground, no text, no labels."
	)


# The template the model fills: a 72x84 canvas of 16x20 cells, shown at 12x with each pixel's grid.
S, GAP = 12, 6
CW, CH = 72, 84


def cell_origin(i: int) -> tuple[int, int]:
	return GAP + (i % 3) * (FW + GAP), GAP + (i // 3) * (BH + GAP)


def template() -> "Path":
	p = RAW / "walk" / f"_template{FW}x{BH}.png"
	im = np.zeros((CH * S, CW * S, 3), np.uint8)
	im[:] = (255, 0, 255)
	for i in range(9):
		x0, y0 = cell_origin(i)
		box = im[y0 * S:(y0 + BH) * S, x0 * S:(x0 + FW) * S]
		box[:] = (240, 120, 240)
		box[::S, :] = (200, 60, 200)
		box[:, ::S] = (200, 60, 200)
	p.parent.mkdir(parents=True, exist_ok=True)
	Image.fromarray(im).save(p)
	return p


LABEL_W = 260  # template pixels of row labels on the left, cut off before reading


def labelled_template() -> "Path":
	"""A canvas with three rows of three empty boxes, each row labelled FRONT / BACK / LEFT SIDE in its left margin."""
	from PIL import ImageDraw, ImageFont
	p = RAW / "walk" / "_labelled.png"
	cell, gap = 200, 60
	w, h = LABEL_W + 3 * cell + 4 * gap, 3 * int(cell * 1.25) + 4 * gap
	im = Image.new("RGB", (w, h), (255, 0, 255))
	d = ImageDraw.Draw(im)
	try:
		font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 40)
	except OSError:
		font = ImageFont.load_default()
	for r, label in enumerate(("FRONT", "BACK", "LEFT\nSIDE")):
		y = gap + r * (int(cell * 1.25) + gap)
		d.rectangle((0, y, LABEL_W - 20, y + int(cell * 1.25)), fill=(255, 255, 255))
		d.multiline_text((20, y + 80), label, fill=(0, 0, 0), font=font)
		for c in range(3):
			x = LABEL_W + gap + c * (cell + gap)
			d.rectangle((x, y, x + cell, y + int(cell * 1.25)), outline=(200, 60, 200), width=3)
	im.save(p)
	return p


def generate(name: str, pal: dict, design: str = "") -> None:
	"""Draws the sheet on a canvas whose rows are labelled FRONT / BACK / LEFT SIDE (labels keep the directions straight far
	better than prose), with the old sprite sheet as the outfit reference."""
	old = RAW / "walk" / "old_walk" / f"{name}_walk.png"
	ref = RAW / "walk" / f"_ref_{name}.png"
	Image.open(old).convert("RGBA").resize((48 * 8, 72 * 8), Image.Resampling.NEAREST).save(ref)
	generate_image(
		f"Draw a Game Boy Advance overworld walking sprite sheet of {WHO.get(name, 'a trainer')} on the first image, one sprite "
		"centered in each of the nine boxes. Each row's white label says which way all three sprites in that row face: "
		"FRONT = facing the viewer (we see the face), BACK = facing away (we see the back of the head, no face), "
		"LEFT SIDE = side profile walking toward the left edge of the image (nose points left). "
		"Columns: standing, step with the left foot forward, step with the right foot forward. "
		"Use the exact chibi proportions of the Pokemon Ruby, Sapphire and Emerald overworld sprites (Brendan, May and the NPCs): "
		"short and stocky, a big round head taking up the top half of the sprite, a small body and short stubby legs. "
		"Each sprite is real low-resolution pixel art about 16 pixels wide and 20 pixels tall, enlarged with big crisp square pixels, "
		"1-pixel dark outline, no anti-aliasing. "
		f"The second image shows the character's outfit and colors ({colors(pal)}): keep them. "
		"Keep the white labels exactly as they are, plain flat magenta #FF00FF everywhere else, remove the box outlines.",
		RAW / "walk" / f"{name}.png", [labelled_template(), ref], "4:3", MODEL)


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
		for y in range(BH):
			for x in range(FW):
				blk = rgb[(y0 + y) * S + 3:(y0 + y + 1) * S - 3, (x0 + x) * S + 3:(x0 + x + 1) * S - 3].reshape(-1, 3)
				c = np.median(blk, axis=0)
				r, g, b = c
				if r > 110 and b > 110 and g < 0.7 * min(r, b):  # magenta (any shade, incl. fringe) = empty
					continue
				sheet[(i // 3) * FH + FH - BH + y, (i % 3) * FW + x] = (*c.astype(np.uint8), 255)
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


TARGET_H = 21


def sprites_free(name: str) -> list[Image.Image] | None:
	"""The nine sprites cut out by their outlines (the model rarely keeps the template boxes exactly), all at one scale so the
	tallest becomes TARGET_H pixels, each bottom-aligned in a 16x24 frame."""
	src = RAW / "walk" / f"{name}.png"
	im = Image.open(src).convert("RGB")
	tw, _ = Image.open(labelled_template()).size
	rgb = np.array(im)[:, round(im.width * LABEL_W / tw):]
	mask = _largest_blobs(key_background(rgb), 0.02)
	rows = _three([r for r in _runs(mask.any(axis=1)) if r[1] - r[0] > 8])
	if len(rows) != 3:
		return None
	rgba = np.dstack([rgb, np.where(erode(mask, 1), 255, 0).astype(np.uint8)])
	boxes = []
	for y0, y1 in rows:
		cols = _three([c for c in _runs(mask[y0:y1].any(axis=0)) if c[1] - c[0] > 4])
		if len(cols) != 3:
			return None
		for x0, x1 in cols:
			ys = np.where(mask[y0:y1, x0:x1].any(axis=1))[0]
			boxes.append((x0, y0 + ys[0], x1, y0 + ys[-1] + 1))
	k = TARGET_H / max(b[3] - b[1] for b in boxes)
	out = []
	for x0, y0, x1, y1 in boxes:
		crop = Image.fromarray(rgba[y0:y1, x0:x1], "RGBA")
		w, h = min(FW, max(1, round((x1 - x0) * k))), min(FH, max(1, round((y1 - y0) * k)))
		fr = Image.new("RGBA", (FW, FH))
		small = mode_resize(crop, (w, h), 16)
		fr.paste(small, ((FW - w) // 2, FH - h), small)
		out.append(fr)
	return out


def assemble(frames9: list[Image.Image], tag: str, need: int = 2) -> tuple[Image.Image | None, str]:
	"""Builds the down/up/left sheet from frames sorted by the facing a vision model sees, whatever row the model drew them in.
	Right-facing frames are mirrored to left; a missing second step mirrors the first (as Emerald does for front and back)."""
	board = Image.new("RGBA", (FW * 3, FH * 3))
	for i, f in enumerate(frames9):
		board.paste(f, ((i % 3) * FW, (i // 3) * FH))
	seen = facing(board, tag)
	by: dict[str, list[Image.Image]] = {"down": [], "up": [], "left": []}
	for f, d in zip(frames9, seen):
		if d == "right":
			by["left"].append(f.transpose(Image.Transpose.FLIP_LEFT_RIGHT))
		elif d in by:
			by[d].append(f)
	missing = [d for d in by if len(by[d]) < need]
	if missing:
		return None, f"missing {missing} (saw {seen})"
	sheet = Image.new("RGBA", (FW * 3, FH * 3))
	for r, d in enumerate(("down", "up", "left")):
		fs = by[d]
		if len(fs) == 1:  # only a standing pose: it walks with the body bob alone
			fs = fs * 2
		row = [fs[0], fs[1], fs[2] if len(fs) > 2 else fs[1].transpose(Image.Transpose.FLIP_LEFT_RIGHT) if d != "left" else fs[0]]
		for c, f in enumerate(row):
			sheet.paste(f, (c * FW, r * FH))
	return sheet, ""


def problems(name: str) -> list[str]:
	"""Why a generated sheet can't be used: the model ignored the template (background not magenta), or
	sprites spill out of their boxes (clipped at the edges), or a frame is empty."""
	src = RAW / "walk" / f"{name}.png"
	rgb = np.array(Image.open(src).convert("RGB").resize((CW * S, CH * S), Image.Resampling.NEAREST)).astype(int)
	gap = np.concatenate([rgb[:GAP * S - S].reshape(-1, 3), rgb[:, :GAP * S - S].reshape(-1, 3)])
	mag = (gap[:, 0] > 110) & (gap[:, 2] > 110) & (gap[:, 1] < 0.7 * np.minimum(gap[:, 0], gap[:, 2]))
	out = []
	if mag.mean() < 0.9:
		out.append("background")
	sheet = np.array(frames_grid(name))
	for i in range(9):
		a = sheet[(i // 3) * FH + FH - BH:(i // 3 + 1) * FH, (i % 3) * FW:(i % 3 + 1) * FW, 3] > 0
		ring = np.concatenate([a[0], a[:, 0], a[:, -1]])
		if a.mean() < 0.15:
			out.append(f"frame {i} empty")
		elif ring.mean() > 0.25:
			out.append(f"frame {i} clipped")
	return out


def facing(sheet: Image.Image, tag: str) -> list[str]:
	"""Which way each of the 9 frames faces, as a vision model sees it (down, up, left or right)."""
	fw, fh = sheet.width // 3, sheet.height // 3
	k = 8
	board = Image.new("RGB", (3 * (fw * k + 30), 3 * (fh * k + 30)), (255, 255, 255))
	for i in range(9):
		fr = sheet.crop(((i % 3) * fw, (i // 3) * fh, (i % 3 + 1) * fw, (i // 3 + 1) * fh)).resize((fw * k, fh * k), Image.Resampling.NEAREST)
		board.paste(fr, ((i % 3) * (fw * k + 30) + 15, (i // 3) * (fh * k + 30) + 15), fr)
	p = RAW / "walk" / f"_facing_{tag}.png"
	board.save(p)
	a = json.loads(ask_vision(p, "These are 9 frames (3 rows of 3, read left to right, top to bottom) of one game character sprite. "
		"For each frame, say which way the character faces from the viewer's point of view: \"down\" (toward the viewer, we see the face), "
		"\"up\" (we see the back of the head), \"left\" (side profile, nose pointing to the left edge of the image) or \"right\" "
		"(nose pointing to the right edge). Answer JSON: {\"1\": \"...\", ..., \"9\": \"...\"}"))
	return [str(a.get(str(i + 1), "?")).lower() for i in range(9)]


def fix_facing(sheet: Image.Image, tag: str) -> tuple[Image.Image, list[int]]:
	"""Mirrors side frames that face right (the game mirrors row 3 for right). Returns the sheet and the frames still wrong."""
	got = facing(sheet, tag)
	fw, fh = sheet.width // 3, sheet.height // 3
	for i in range(6, 9):
		if got[i] == "right":
			box = ((i % 3) * fw, 2 * fh, (i % 3 + 1) * fw, 3 * fh)
			flipped = sheet.crop(box).transpose(Image.Transpose.FLIP_LEFT_RIGHT)
			sheet.paste(flipped, box[:2])
			got[i] = "left"
	return sheet, [i for i in range(9) if got[i] != WANT[i]]


def record(path) -> None:
	"""Notes that this sheet's facing was checked, keyed by its md5 so tests can tell a changed sheet."""
	data = json.loads(FACING.read_text()) if FACING.exists() else {}
	data[path.stem] = hashlib.md5(path.read_bytes()).hexdigest()
	FACING.write_text(json.dumps(dict(sorted(data.items())), indent=1) + "\n")


def checked_sheet(name: str) -> tuple[Image.Image | None, list[int]]:
	s = frames_grid(name)
	if s is None:
		return None, list(range(9))
	return fix_facing(s, name)


def audit(path) -> list[int]:
	s = Image.open(path).convert("RGBA")
	s, bad = fix_facing(s, path.stem)
	if not bad:
		s.save(path)
		record(path)
	return bad


if __name__ == "__main__":
	pals = misc()["palettes"]
	cmd, names = sys.argv[1], sys.argv[2:] or list(pals)
	if cmd == "generate":
		def gen(n: str) -> None:
			for attempt in range(2):
				raw = RAW / "walk" / f"{n}.png"
				if raw.exists():
					raw.rename(RAW / "walk" / f"{n}_old{attempt}.png")
				generate(n, pals[n])
				fr = sprites_free(n)
				sheet, why = assemble(fr, n, 2 - attempt) if fr else (None, "could not cut out 9 sprites")
				if sheet is not None:
					sheet, wrong = fix_facing(sheet, n)
					if not wrong:
						out = OUT / f"{n}_walk.png"
						sheet.save(out)
						record(out)
						print("got", n, flush=True)
						return
					why = f"wrong frames {wrong}"
				print("retry", n, why, flush=True)
			print("FAILED", n, flush=True)
		with ThreadPoolExecutor(6) as ex:
			list(ex.map(gen, names))
	elif cmd == "check":
		for n in names:
			print(n, problems(n))
	elif cmd == "audit":
		for n in names:
			print(n, audit(OUT / f"{n}.png" if n.endswith("_walk") else OUT / f"{n}_walk.png"), flush=True)
	else:
		for n in names:
			s = frames_grid(n)
			if s:
				s.save(OUT / f"{n}_walk.png")
			print("done", n, flush=True)


# --- Chibi redraw (2026-10-20): Emerald proportions with directions that can't get mixed up ---------------------------
# Only the three standing poses are drawn by the model, four characters per call, as an edit of their old standing frames
# (an edit keeps each sprite's place and facing). The step frames are made from the standing pose, as the handheld does:
# one leg lifts a pixel (front/back) or the legs spread a pixel (side), and the body bobs.
GROUP = 4
CHIBI = RAW / "walk" / "chibi"


def old_stands(name: str) -> list[Image.Image] | None:
	"""The old sheet's down, up and left standing frames, taking any frame of the row that faces the right way."""
	im = Image.open(RAW / "walk" / "old_walk" / f"{name}_walk.png").convert("RGBA")
	seen = facing(im, "old_" + name)
	out = []
	for r, want in enumerate(("down", "up", "left")):
		pick = None
		for i in range(9):
			fr = im.crop(((i % 3) * FW, (i // 3) * FH, (i % 3 + 1) * FW, (i // 3 + 1) * FH))
			if seen[i] == want and (pick is None or i // 3 == r):
				pick = fr
				if i // 3 == r:
					break
			elif want == "left" and seen[i] == "right" and pick is None:
				pick = fr.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
		out.append(pick)  # None when no frame faces this way: the model draws that view in an empty spot
	return out


def chibi_generate(names: list[str], tag: str) -> Path:
	ref = CHIBI / f"_ref_{tag}.png"
	ref.parent.mkdir(parents=True, exist_ok=True)
	pad = 8
	sheet = Image.new("RGBA", (3 * (FW + pad) + pad, GROUP * (FH + pad) + pad), (255, 0, 255, 255))
	for r, n in enumerate(names):
		for c, fr in enumerate(old_stands(n)):
			if fr is not None:
				sheet.paste(fr, (pad + c * (FW + pad), pad + r * (FH + pad)), fr)
	sheet.convert("RGB").resize((sheet.width * 12, sheet.height * 12), Image.Resampling.NEAREST).save(ref)
	who = "; ".join(f"row {i + 1}: {WHO.get(n, 'a trainer')}" for i, n in enumerate(names))
	out = CHIBI / f"{tag}.png"
	generate_image(
		f"This is a Game Boy Advance overworld sprite sheet of {len(names)} characters ({who}). In every row the first sprite faces "
		"down toward the viewer (we see the face), the second faces up away from the viewer (back of the head, no face), and the third "
		"faces left in side profile (nose toward the left edge). "
		"Redraw the SAME sheet: keep every sprite in exactly the same place and facing exactly the same direction, standing still, with "
		"the same outfit and colors, but with the chibi proportions of the Pokemon Ruby, Sapphire and Emerald overworld sprites "
		"(Brendan, May and the NPCs): short and stocky, a big round head taking up the top half of the sprite, a small body and short "
		"stubby legs. Where a spot is empty, draw the missing view of that row's character there. Exactly three sprites per row. "
		"Each sprite is real low-resolution pixel art about 16 pixels wide and 20 pixels tall, enlarged with big crisp "
		"square pixels, 1-pixel dark outline, no anti-aliasing. Plain flat magenta #FF00FF background, no text.",
		out, [ref], "3:4", MODEL)
	return out


def pixel_pitch(rgb: np.ndarray, lo: float = 5.0, hi: float = 24.0) -> float:
	"""The size of one sprite pixel in the enlarged image, from the spacing of color edges along rows and columns."""
	gaps = []
	for arr in (rgb, rgb.transpose(1, 0, 2)):
		for y in range(0, arr.shape[0], 7):
			e = np.where(np.abs(np.diff(arr[y].astype(int), axis=0)).sum(1) > 40)[0]
			if len(e) < 2:
				continue
			e = e[np.insert(np.diff(e) > 2, 0, True)]
			gaps.extend(np.diff(e).tolist())
	g = np.array([x for x in gaps if 4 <= x <= 120], float)
	best, err = 8.0, 1e18
	for p in np.arange(lo, hi, 0.05):
		m = np.maximum(1, np.round(g / p))
		e = (np.abs(g - m * p) / m).sum() + len(g) * 0.02 * p  # small bias against multiples of the pitch
		if e < err:
			best, err = p, e
	return best


def chibi_cut(src: Path, rows: int) -> list[list[Image.Image]] | None:
	"""rows x 3 standing sprites, cut out by their outlines and read back at their real pixel size (one sample per drawn pixel)."""
	rgb = np.array(Image.open(src).convert("RGB"))
	mask = _largest_blobs(key_background(rgb), 0.005)
	rr = [r for r in _runs(mask.any(axis=1)) if r[1] - r[0] > 8]
	while len(rr) > rows:
		gaps = [rr[i + 1][0] - rr[i][1] for i in range(len(rr) - 1)]
		i = int(np.argmin(gaps))
		rr[i:i + 2] = [(rr[i][0], rr[i + 1][1])]
	if len(rr) != rows:
		return None
	boxes, counts = [], []
	for y0, y1 in rr:
		cols = [c for c in _runs(mask[y0:y1].any(axis=0)) if c[1] - c[0] > 4]
		i = 0
		while i < len(cols) - 1:  # a gap narrower than a few pixels is inside one sprite (between the legs)
			if cols[i + 1][0] - cols[i][1] < (y1 - y0) * 0.05:
				cols[i:i + 2] = [(cols[i][0], cols[i + 1][1])]
			else:
				i += 1
		if not 3 <= len(cols) <= 5:
			return None
		counts.append(len(cols))
		for x0, x1 in cols:
			ys = np.where(mask[y0:y1, x0:x1].any(axis=1))[0]
			boxes.append((x0, y0 + ys[0], x1, y0 + ys[-1] + 1))
	guess = float(np.median([b[3] - b[1] for b in boxes])) / 21  # a sprite is about 21 pixels tall
	p = pixel_pitch(rgb, guess * 0.85, guess * 1.25)
	out = []
	for x0, y0, x1, y1 in boxes:
		w, h = max(1, round((x1 - x0) / p)), max(1, round((y1 - y0) / p))
		small = np.zeros((h, w, 4), np.uint8)
		for yy in range(h):
			for xx in range(w):
				cy, cx = int(y0 + (yy + 0.5) * p), int(x0 + (xx + 0.5) * p)
				m = max(1, int(p / 4))
				if not mask[min(cy, mask.shape[0] - 1), min(cx, mask.shape[1] - 1)]:
					continue
				blk = rgb[cy - m:cy + m + 1, cx - m:cx + m + 1].reshape(-1, 3)
				r, g, b = c = np.median(blk, axis=0)
				if r > 110 and b > 110 and g < 0.7 * min(r, b):  # magenta fringe
					continue
				small[yy, xx] = (*c.astype(np.uint8), 255)
		sm = Image.fromarray(small, "RGBA")
		if w > FW or h > TARGET_H + 1:  # drawn finer than asked: shrink to the handheld size
			k = min(FW / w, (TARGET_H + 1) / h)
			w, h = max(1, int(w * k)), max(1, int(h * k))
			sm = mode_resize(sm, (w, h), 16)
		fr = Image.new("RGBA", (FW, FH))
		fr.paste(sm, ((FW - w) // 2, FH - h), sm)
		out.append(fr)
	res, k = [], 0
	for c in counts:
		res.append(out[k:k + c])
		k += c
	return res


def _legs_top(a: np.ndarray) -> int:
	ys = np.where(a[..., 3].any(axis=1))[0]
	return ys[-1] - 3 if len(ys) else FH - 4


def step_frame(stand: Image.Image, side: bool, which: int) -> Image.Image:
	"""A walking frame from the standing pose. Front/back: the bottom 3 rows of one half (the lifted leg) move up a pixel.
	Side: the bottom 3 rows spread, the front half a pixel forward (left) and the back half a pixel back."""
	a = np.array(stand)
	out = a.copy()
	top = _legs_top(a)
	legs = a[top:].copy()
	out[top:] = 0
	mid = FW // 2
	if side:
		front, back = legs.copy(), legs.copy()
		front[:, mid:] = 0
		back[:, :mid] = 0
		d = 1 if which == 1 else 0
		region = out[top:]
		for src, dx in ((back, d), (front, -1 if which == 1 else -d)):
			sh = np.roll(src, dx, axis=1)
			m = sh[..., 3] > 0
			region[m] = sh[m]
	else:
		lift, stay = legs.copy(), legs.copy()
		if which == 1:
			lift[:, mid:] = 0
			stay[:, :mid] = 0
		else:
			lift[:, :mid] = 0
			stay[:, mid:] = 0
		region = out[top - 1:]
		up = np.zeros_like(region)
		up[:-1][: legs.shape[0]] = lift
		m = up[..., 3] > 0
		region[m] = up[m]
		down = out[top:]
		m = stay[..., 3] > 0
		down[m] = stay[m]
	return Image.fromarray(out, "RGBA")


def _whole(f: Image.Image) -> bool:
	b = f.getbbox()
	return b is not None and b[3] - b[1] >= 16 and b[2] - b[0] >= 8


def choose_views(row: list[Image.Image], tag: str) -> list[Image.Image] | None:
	"""The down, up and left views from one row of sprites, by the facing a vision model sees (the model sometimes adds a
	fourth sprite or swaps two), checking that each is a whole sprite of a sensible size."""
	ok = []
	for f in row:
		b = f.getbbox()
		ok.append(b is not None and b[3] - b[1] >= 16 and b[2] - b[0] >= 8)
	if len(row) == 3 and all(ok):
		return row  # the order the prompt asked for; fix_facing verifies it
	board = Image.new("RGBA", (FW * 3, FH * 3))
	for i, f in enumerate(row[:9]):
		board.paste(f, ((i % 3) * FW, (i // 3) * FH))
	seen = facing(board, "row_" + tag)[:len(row)]
	out = []
	for want in ("down", "up", "left"):
		got = next((f for f, d, g in zip(row, seen, ok) if d == want and g), None)
		if got is None and want == "left":
			got = next((f.transpose(Image.Transpose.FLIP_LEFT_RIGHT) for f, d, g in zip(row, seen, ok) if d == "right" and g), None)
		if got is None:
			print("no", want, "view for", tag, seen, flush=True)
			return None
		out.append(got)
	return out


def chibi_sheet(stands: list[Image.Image]) -> Image.Image:
	sheet = Image.new("RGBA", (FW * 3, FH * 3))
	for r, st in enumerate(stands):
		for c in range(3):
			fr = st if c == 0 else step_frame(st, r == 2, c)
			sheet.paste(fr, (c * FW, r * FH))
	return sheet


def chibi(names: list[str], only: set | None = None) -> list[str]:
	"""Redraws names in groups; returns the ones that still need another try. With only, the others in a group are just
	company for the model (a lone character in a tall canvas comes out muddled) and are not saved."""
	groups = [names[i:i + GROUP] for i in range(0, len(names), GROUP)]
	failed: list[str] = []

	def run(g: list[str]) -> None:
		tag = "_".join(g)
		src = chibi_generate(g, tag)
		cut = chibi_cut(src, len(g))
		if cut is None:
			print("cut failed", tag, flush=True)
			failed.extend(g)
			return
		for n, row in zip(g, cut):
			if only is not None and n not in only:
				continue
			stands = choose_views(row, n)
			if stands is None:
				failed.append(n)
				continue
			sheet = chibi_sheet(stands)
			sheet, wrong = fix_facing(sheet, n)
			if wrong or any(not _whole(st) for st in stands):
				print("wrong facing or size", n, wrong, flush=True)
				failed.append(n)
				continue
			out = OUT / f"{n}_walk.png"
			sheet.save(out)
			record(out)
			print("got", n, flush=True)

	with ThreadPoolExecutor(5) as ex:
		list(ex.map(run, groups))
	return failed


def pick_views(src: Path, tag: str) -> list[Image.Image] | None:
	"""Fallback when the model's rows came out muddled: every sprite in the image is cut out, its facing checked, and the
	first down, up and left (or mirrored right) view taken."""
	rgb = np.array(Image.open(src).convert("RGB"))
	mask = _largest_blobs(key_background(rgb), 0.005)
	from scipy import ndimage
	lab, n = ndimage.label(ndimage.binary_closing(mask, iterations=3))
	boxes = [s for s in ndimage.find_objects(lab) if (s[0].stop - s[0].start) > rgb.shape[0] * 0.08]
	boxes.sort(key=lambda s: (s[0].start // 50, s[1].start))
	if not boxes:
		return None
	# cut each as its own one-row sheet so chibi_cut's pitch-exact sampling applies
	frames = []
	for sl in boxes:
		crop = Image.fromarray(rgb[sl[0].start:sl[0].stop, max(0, sl[1].start - 4):sl[1].stop + 4])
		pad = Image.new("RGB", (crop.width * 3 + 40, crop.height + 20), (255, 0, 255))
		for c in range(3):
			pad.paste(crop, (10 + c * (crop.width + 10), 10))
		tmp = CHIBI / f"_one_{tag}.png"
		pad.save(tmp)
		cut = chibi_cut(tmp, 1)
		if cut:
			frames.append(cut[0][0])
	board = Image.new("RGBA", (FW * len(frames), FH))
	for i, f in enumerate(frames):
		board.paste(f, (i * FW, 0))
	seen = []
	for i in range(0, len(frames), 9):
		chunk = frames[i:i + 9] + [Image.new("RGBA", (FW, FH))] * (9 - len(frames[i:i + 9]))
		b = Image.new("RGBA", (FW * 3, FH * 3))
		for j, f in enumerate(chunk):
			b.paste(f, ((j % 3) * FW, (j // 3) * FH))
		seen += facing(b, f"pick_{tag}_{i}")[:len(frames[i:i + 9])]
	out = []
	for want in ("down", "up", "left"):
		got = next((f for f, d in zip(frames, seen) if d == want), None)
		if got is None and want == "left":
			got = next((f.transpose(Image.Transpose.FLIP_LEFT_RIGHT) for f, d in zip(frames, seen) if d == "right"), None)
		if got is None:
			print("pick: no", want, "in", seen)
			return None
		out.append(got)
	return out
