"""The region map for the Town Map and Fly screens: the layout the screen draws (land, routes, the sea route) rendered
at screen size, repainted by Nano Banana Pro as an Emerald-style region map. Output: assets/screens/townmap.png (240x160).
The screen still draws the town squares, the you-are-here marker and the cursor on top.

python3 tools/artgen/townmap.py
"""
import json

from PIL import Image, ImageDraw

from common import RAW, ROOT, generate_image

MODEL = "gemini-3-pro-image"
W, H = 240, 160


def layout() -> Image.Image:
	"""Same geometry as TownMapScene: scale to fit, centered below the 18 px header and above the footer."""
	rm = json.loads((ROOT / "data" / "features.json").read_text())["regionMap"]
	rm = {k: v for k, v in rm.items() if k != "battlefrontier"}  # shown only after the League; drawn by the game
	maxx = max(1.0, max(r["x"] + r["w"] for r in rm.values()))
	maxy = max(1.0, max(r["y"] + r["h"] for r in rm.values()))
	full = json.loads((ROOT / "data" / "features.json").read_text())["regionMap"]
	maxx = max(maxx, max(r["x"] + r["w"] for r in full.values()))
	maxy = max(maxy, max(r["y"] + r["h"] for r in full.values()))
	s = min((W - 24) / maxx, (H - 46) / maxy)
	ox, oy = (W - maxx * s) / 2, 22 + (H - 46 - maxy * s) / 2
	im = Image.new("RGB", (W, H), (56, 112, 184))
	d = ImageDraw.Draw(im)
	# Land: a rounded coast a few pixels around every route and town.
	for k, r in rm.items():
		if k != "route13":
			d.rounded_rectangle([ox + r["x"] * s - 9, oy + r["y"] * s - 9, ox + (r["x"] + r["w"]) * s + 9, oy + (r["y"] + r["h"]) * s + 9], 7, fill=(232, 216, 160))
	for k, r in rm.items():
		if k != "route13":
			d.rounded_rectangle([ox + r["x"] * s - 7, oy + r["y"] * s - 7, ox + (r["x"] + r["w"]) * s + 7, oy + (r["y"] + r["h"]) * s + 7], 6, fill=(120, 184, 88))
	for k, r in rm.items():
		if r.get("town"):
			continue
		cx, cy, w, h = ox + (r["x"] + r["w"] / 2) * s, oy + (r["y"] + r["h"] / 2) * s, r["w"] * s, r["h"] * s
		if k == "route13":
			d.rectangle([cx - w / 2, cy - 1, cx + w / 2, cy + 1], fill=(168, 208, 248))
		elif w > h:
			d.rectangle([cx - w / 2, cy - 2, cx + w / 2, cy + 2], fill=(232, 208, 152))
		else:
			d.rectangle([cx - 2, cy - h / 2, cx + 2, cy + h / 2], fill=(232, 208, 152))
	for k, r in rm.items():
		if r.get("town"):
			cx, cy = ox + (r["x"] + r["w"] / 2) * s, oy + (r["y"] + r["h"] / 2) * s
			d.rectangle([cx - 5, cy - 5, cx + 5, cy + 5], fill=(224, 80, 64))
	return im


if __name__ == "__main__":
	lay = layout()
	ref = RAW / "screens" / "townmap_layout.png"
	ref.parent.mkdir(parents=True, exist_ok=True)
	lay.resize((W * 4, H * 4), Image.NEAREST).save(ref)
	out = RAW / "screens" / "townmap.png"
	generate_image(
		"This is the exact layout of a region map screen in a Game Boy Advance monster RPG: green land with a sandy coast, sandy "
		"route paths, red squares for towns, a pale sea route, blue sea. Restyle it (do not redesign it) as a beautiful region map like the Hoenn map in "
		"Pokemon Emerald's Town Map / Fly screen: crisp GBA pixel art with big square pixels, small forests and hills on the green land, "
		"routes drawn as clear light paths, towns as small bright red square markers, deep blue sea with a gentle wave pattern. "
		"CRITICAL: this is a tracing job. Every route, every town square and the coastline stay in exactly the same pixel position, "
		"size and shape as the reference; the land must not grow, shrink or change shape, and no towns or routes are added or removed. Leave the top 18 pixel rows and the bottom 22 pixel rows as plain dark blue bands. No text, labels or legend.",
		out, [ref], "3:2", MODEL)
	im = Image.open(out).convert("RGB").resize((W, H), Image.Resampling.LANCZOS)
	im = im.quantize(colors=64, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
	(ROOT / "assets" / "screens").mkdir(parents=True, exist_ok=True)
	im.save(ROOT / "assets" / "screens" / "townmap.png")
	print("done")
