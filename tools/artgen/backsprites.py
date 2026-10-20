"""The players seen from behind at the start of a battle, head and shoulders cut off by the screen's bottom edge, throwing a
Capture Orb, like the Gen 3 player back sprites:
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
		f"Draw the Pokemon Emerald battle 'player back sprite' of {WHO[name]}: seen from BEHIND, a big close view of the back of "
		"the head and the shoulders and upper back only, cut off flat at the chest by the BOTTOM EDGE of each box (no waist, no legs), "
		"exactly like Brendan and May at the bottom left of the Gen 3 battle screen. The head is large and fills the upper part of "
		f"the box; the near shoulder and throwing arm can reach the box edge. Colors: {colors(pal)}. "
		"Box 1 (top left): still, the arm down holding a small round red-and-white capture orb at the shoulder. Box 2 (top right): "
		"winding up, the orb raised beside the head. Box 3 (bottom left): mid-throw, the arm swinging forward and up. Box 4 (bottom "
		"right): follow-through, the hand open and empty. Same character, same size and position in every box, always touching the "
		"bottom edge. The second image shows the character's design. No text.",
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
