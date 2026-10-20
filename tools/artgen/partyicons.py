"""Party menu icons: a crisp 32x32 two-frame icon for every creature, like the Emerald party and PC icons, made from the
creature's generated battle sprite (no API calls): majority-vote downscale, a 1-pixel dark outline, and a second frame
that hops a pixel. Output: assets/creatures/icons/<id>.png (64x32: frame 1 | frame 2).

python3 tools/artgen/partyicons.py
"""
import numpy as np
from PIL import Image

from common import ROOT, species
from pixel import mode_resize

SRC = ROOT / "assets" / "creatures"
OUT = SRC / "icons"


def icon(sid: str) -> Image.Image | None:
	p = SRC / f"{sid}.png"
	if not p.exists():
		return None
	im = Image.open(p).convert("RGBA")
	box = im.getbbox()
	if box is None:
		return None
	im = im.crop(box)
	k = 26 / max(im.size)
	w, h = max(1, round(im.width * k)), max(1, round(im.height * k))
	small = np.array(mode_resize(im, (w, h), 16))
	# 1-pixel outline in a darkened version of the nearest body color, like the handheld icons
	a = small[..., 3] > 0
	pad = np.zeros((h + 2, w + 2, 4), np.uint8)
	pad[1:-1, 1:-1] = small
	ap = pad[..., 3] > 0
	ring = np.zeros_like(ap)
	for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
		ring |= np.roll(np.roll(ap, dy, 0), dx, 1)
	ring &= ~ap
	pad[ring] = (40, 40, 48, 255)
	sprite = Image.fromarray(pad, "RGBA")
	strip = Image.new("RGBA", (64, 32))
	x, y = (32 - sprite.width) // 2, 32 - sprite.height - 1
	strip.paste(sprite, (x, y), sprite)
	strip.paste(sprite, (32 + x, y - 2), sprite)
	return strip


if __name__ == "__main__":
	OUT.mkdir(parents=True, exist_ok=True)
	n = 0
	for sid in species():
		s = icon(sid)
		if s:
			s.save(OUT / f"{sid}.png")
			n += 1
	print(n, "icons")
