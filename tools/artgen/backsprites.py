"""The players seen from behind at the start of a battle, throwing a Capture Orb, like the Gen 3 player back sprites:
four 64x64 frames (standing, winding up, throwing, follow-through). Output: assets/trainers/<p1|p2>_back.png (256x64).

python3 tools/artgen/backsprites.py
"""
from PIL import Image

from common import RAW, ROOT, misc
from gridsheet import Sheet, opaque
from trainers import WHO, colors

SHEET = Sheet(cols=2, rows=2, w=64, h=64, gap=4, scale=6)
OUT = ROOT / "assets" / "trainers"


def make(name: str) -> None:
	pal = misc()["palettes"][name]
	raw = RAW / "back" / f"{name}.png"
	raw.parent.mkdir(parents=True, exist_ok=True)
	SHEET.generate(
		f"Draw the Pokemon Emerald battle 'player back sprite' of {WHO[name]}: seen from BEHIND and slightly to the side, from the "
		f"waist up, filling most of each box, as in the moment a Gen 3 player sends out a creature. Colors: {colors(pal)}. "
		"Box 1 (top left): standing, holding a small round red-and-white capture orb. Box 2 (top right): winding up, the orb arm "
		"pulled back. Box 3 (bottom left): mid-throw, arm forward. Box 4 (bottom right): follow-through, hand empty. Same character, "
		"same size and position in every box. The second image shows the character's design. No text.",
		raw, [OUT / f"{name}.png"])
	frames = SHEET.read(raw)
	if min(opaque(f) for f in frames) < 0.1:
		print("WARN", name, "empty frame")
	strip = Image.new("RGBA", (256, 64))
	for i, f in enumerate(frames):
		strip.paste(f, (i * 64, 0))
	strip.save(OUT / f"{name}_back.png")


if __name__ == "__main__":
	for n in ("p1", "p2"):
		make(n)
		print("done", n, flush=True)
