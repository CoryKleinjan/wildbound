"""The game font, drawn by Nano Banana Pro as pixel glyphs and turned into a TrueType font of square pixels:
assets/fonts/Wildbound.ttf (replaces Press Start 2P in Gfx.font()).

The model draws on a grid canvas where every square is one font pixel. Each box holds one character, sketched in light grey
from a system font so the model knows which character goes where; it redraws them as Emerald-style dialogue letters.
The model's squares drift off the grid, so the read-back has uneven strokes; font_glyphs.txt holds every glyph cleaned up to
even 1-pixel strokes, and build() uses it over the sheet.

python3 tools/artgen/fontgen.py generate | build | preview
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

from common import RAW, ROOT, generate_image
from gridsheet import MODEL, Sheet

CHARS = [chr(c) for c in range(33, 127)] + list("é◀▶♂♀★▲▼")
W, H = 6, 11        # box size in font pixels: row 0 accents, rows 1-7 capitals, baseline under row 7, rows 8-9 descenders
BASE = 8            # rows above the baseline
SHEET = Sheet(12, 9, W, H, gap=2, scale=12)
RAW_SHEET = RAW / "font" / "sheet.png"
OUT = ROOT / "assets" / "fonts" / "Wildbound.ttf"
GUIDE_FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"


def guide(ch: str) -> np.ndarray:
	"""A rough H x W bitmap of ch from a system font, placed on the baseline: the model's hint, not the result."""
	f = ImageFont.truetype(GUIDE_FONT, 80)
	im = Image.new("L", (160, 160), 0)
	ImageDraw.Draw(im).text((40, 20), ch, font=f, fill=255)
	cap = f.getbbox("H")
	scale = 7 / (cap[3] - cap[1])  # capitals 7 pixels tall
	y_base = 20 + cap[3]
	small = im.resize((round(160 * scale), round(160 * scale)), Image.Resampling.BOX)
	a = np.array(small) > 90
	ys, xs = np.nonzero(a)
	out = np.zeros((H, W), bool)
	if not len(xs):
		return out
	x0 = xs.min()
	top = round(y_base * scale) - BASE  # row of the box's top in the scaled image
	for y, x in zip(ys, xs):
		bx, by = x - x0 + max(0, (W - 1 - (xs.max() - x0 + 1)) // 2), y - top
		if 0 <= bx < W and 0 <= by < H:
			out[by, bx] = True
	return out


def template() -> "Path":
	p = RAW / "font" / "template.png"
	cw, chh = SHEET.size
	S = SHEET.scale
	im = np.zeros((chh * S, cw * S, 3), np.uint8)
	im[:] = (255, 0, 255)
	for i in range(SHEET.cols * SHEET.rows):
		x0, y0 = SHEET.origin(i)
		box = im[y0 * S:(y0 + H) * S, x0 * S:(x0 + W) * S]
		box[:] = (240, 120, 240)
		if i < len(CHARS):
			g = guide(CHARS[i])
			for y, x in zip(*np.nonzero(g)):
				box[y * S:(y + 1) * S, x * S:(x + 1) * S] = (200, 200, 200)
		box[BASE * S - 1:BASE * S + 1, :] = (150, 40, 150)  # baseline
		box[::S, :] = np.minimum(box[::S, :], (200, 60, 200))
		box[:, ::S] = np.minimum(box[:, ::S], (200, 60, 200))
	p.parent.mkdir(parents=True, exist_ok=True)
	Image.fromarray(im).save(p)
	return p


PROMPT = (
	f"The image is the exact canvas: a {SHEET.cols} by {SHEET.rows} grid of pink boxes, each exactly {W} grid squares wide and {H} "
	"tall, where every small grid square is ONE font pixel. Each box holds one character sketched in light grey, in reading order: "
	+ " ".join(CHARS) + " (the last boxes are empty). The darker line in each box is the baseline. "
	"Redraw every character as a crisp pixel-font glyph in the style of the Pokemon Emerald (Game Boy Advance) dialogue font: "
	"clean 1-pixel strokes, capitals 7 squares tall sitting on the baseline, lowercase x-height 5, descenders (g j p q y) going "
	"2 squares below the baseline, rounded but blocky letters, at most 5 squares wide (narrow letters like i l ! . , stay narrow). "
	"Each glyph is solid near-black #202020 squares only, no shading, no outline, no anti-aliasing. "
	"Every other square, inside and outside the boxes, becomes plain magenta #FF00FF; remove the grid lines, the grey sketches and "
	"the baselines. Keep every box in the same place and keep the characters in the same boxes."
)


def generate() -> None:
	generate_image(PROMPT, RAW_SHEET, [template()], SHEET.aspect, MODEL)


def _read_sheet() -> list[np.ndarray]:
	"""Reads each box at the model's own pixel size: the drawn squares drift off the canvas grid, so each glyph is taken from its
	ink bounding box, measured in font pixels (capital height / 7) and placed on its row's baseline."""
	rgb = np.array(Image.open(RAW_SHEET).convert("RGB")).astype(int)
	ink = rgb.sum(-1) < 330
	cw, chh = SHEET.size
	sx, sy = rgb.shape[1] / cw, rgb.shape[0] / chh
	boxes = []
	for i in range(len(CHARS)):
		ox, oy = SHEET.origin(i)
		x0, y0 = round((ox - 0.5) * sx), round((oy - 0.5) * sy)
		x1, y1 = round((ox + W + 0.5) * sx), round((oy + H + 0.5) * sy)
		ys, xs = np.nonzero(ink[y0:y1, x0:x1])
		boxes.append(None if not len(xs) else (x0 + xs.min(), y0 + ys.min(), x0 + xs.max() + 1, y0 + ys.max() + 1))
	caps = [b for c, b in zip(CHARS, boxes) if b and c in "BDEFHIKLMNRTUVWXZ"]
	u = float(np.median([(b[3] - b[1]) / 7 for b in caps]))
	sits = set("ABCDEFHIKLMNORSTUVWXZabcdehiklmnorstuvwxz0123456789")
	base = {}
	for r in range(SHEET.rows):
		bs = [b[3] for c, b, i in zip(CHARS, boxes, range(len(CHARS))) if b and c in sits and i // SHEET.cols == r]
		base[r] = float(np.median(bs)) if bs else None
	out = []
	for i, b in enumerate(boxes):
		m = np.zeros((H, W), bool)
		if b:
			bl = base[i // SHEET.cols] or (SHEET.origin(i)[1] + BASE) * sy
			nw = min(W - 1, max(1, round((b[2] - b[0]) / u)))
			top = BASE - round((bl - b[1]) / u)
			bot = BASE + round((b[3] - bl) / u)
			nh = max(1, bot - top)
			cu, ru = (b[2] - b[0]) / nw, (b[3] - b[1]) / nh
			for y in range(nh):
				for x in range(nw):
					blk = ink[int(b[1] + (y + 0.25) * ru):int(b[1] + (y + 0.75) * ru) + 1, int(b[0] + (x + 0.25) * cu):int(b[0] + (x + 0.75) * cu) + 1]
					if blk.mean() > 0.5 and 0 <= top + y < H:
						m[top + y, x] = True
		out.append(m)
	return out


def cleaned() -> dict[str, np.ndarray]:
	"""font_glyphs.txt: the glyphs redrawn from the generated sheet with even 1-pixel strokes."""
	out, ch, rows = {}, None, []
	for line in (Path(__file__).parent / "font_glyphs.txt").read_text().splitlines() + ["== "]:
		if line.startswith("# "):
			continue
		if line.startswith("== "):
			if ch:
				out[ch] = np.array([[c == "#" for c in r.ljust(W)[:W]] for r in rows] + [[False] * W] * (H - len(rows)))
			ch, rows = line[3:], []
		else:
			rows.append(line)
	return out


def glyphs() -> dict[str, np.ndarray]:
	"""Character -> H x W bool ink mask: the cleaned glyph where there is one, else the generated sheet's."""
	fixed = cleaned()
	return {ch: fixed.get(ch, ink) for ch, ink in zip(CHARS, _read_sheet())}


def build() -> None:
	from fontTools.fontBuilder import FontBuilder
	from fontTools.pens.ttGlyphPen import TTGlyphPen

	P = 100                 # font units per pixel
	EM = 8 * P              # size N draws capitals 7/8 N tall, like Press Start 2P
	g = glyphs()
	names = [".notdef", "space"] + [f"u{ord(c):04X}" for c in g]
	cmap = {32: "space"} | {ord(c): f"u{ord(c):04X}" for c in g}
	fb = FontBuilder(EM, isTTF=True)
	fb.setupGlyphOrder(names)
	fb.setupCharacterMap(cmap)
	glyf, metrics = {}, {}
	empty = TTGlyphPen(None).glyph()
	glyf[".notdef"], metrics[".notdef"] = empty, (4 * P, 0)
	glyf["space"], metrics["space"] = empty, (3 * P, 0)
	for ch, ink in g.items():
		pen = TTGlyphPen(None)
		cols = np.nonzero(ink.any(0))[0]
		x0 = cols.min() if len(cols) else 0
		for y, x in zip(*np.nonzero(ink)):
			x, y = int(x - x0), int(y)
			l, r = x * P, (x + 1) * P
			t, b = (BASE - y) * P, (BASE - y - 1) * P
			pen.moveTo((l, b)); pen.lineTo((l, t)); pen.lineTo((r, t)); pen.lineTo((r, b)); pen.closePath()
		w = (cols.max() - x0 + 2) if len(cols) else 3
		name = f"u{ord(ch):04X}"
		glyf[name], metrics[name] = pen.glyph(), (w * P, 0)
	fb.setupGlyf(glyf)
	fb.setupHorizontalMetrics(metrics)
	asc, desc = BASE * P, (H - BASE) * P
	fb.setupHorizontalHeader(ascent=asc, descent=-desc)
	fb.setupNameTable({"familyName": "Wildbound", "styleName": "Regular"})
	fb.setupOS2(sTypoAscender=asc, sTypoDescender=-desc, usWinAscent=asc, usWinDescent=desc)
	fb.setupPost()
	OUT.parent.mkdir(parents=True, exist_ok=True)
	fb.save(str(OUT))
	print("wrote", OUT)


def preview(dst="/mnt/project-files/art-previews/font.png") -> None:
	"""The glyph sheet at 4x, plus a sample line, for review."""
	g = glyphs()
	S = 4
	im = Image.new("RGB", (SHEET.cols * (W + 2) * S, SHEET.rows * (H + 2) * S), (248, 248, 240))
	px = im.load()
	for i, (ch, ink) in enumerate(g.items()):
		ox, oy = (i % SHEET.cols) * (W + 2) * S + S, (i // SHEET.cols) * (H + 2) * S + S
		for y, x in zip(*np.nonzero(ink)):
			for dy in range(S):
				for dx in range(S):
					px[ox + x * S + dx, oy + y * S + dy] = (32, 32, 32)
	im.save(dst)
	print("wrote", dst)


if __name__ == "__main__":
	{"generate": generate, "build": build, "preview": preview, "template": template}[sys.argv[1]]()
