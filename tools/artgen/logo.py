"""The WILDBOUND title logo, drawn by Nano Banana Pro in the style of the Pokemon Emerald logo. Output: assets/ui/logo.png.

python3 tools/artgen/logo.py
"""
import numpy as np
from PIL import Image

from common import RAW, ROOT, generate_image
from pixel import key_background, _largest_blobs, erode

MODEL = "gemini-3-pro-image"

if __name__ == "__main__":
	raw = RAW / "title" / "logo.png"
	raw.parent.mkdir(parents=True, exist_ok=True)
	generate_image(
		"A video game title logo that reads exactly \"WILDBOUND\" (one word, these nine letters, spelled W-I-L-D-B-O-U-N-D), in the "
		"style of the Pokemon Ruby, Sapphire and Emerald logos: chunky bold letters with a thick dark blue outline, a warm "
		"yellow-to-orange fill with a light highlight on top, slightly arched, with a small green leaf accent. Crisp Game Boy "
		"Advance pixel art with big square pixels. Centered on a plain flat magenta #FF00FF background, nothing else.",
		raw, None, "21:9", MODEL)
	rgb = np.array(Image.open(raw).convert("RGB"))
	mask = _largest_blobs(key_background(rgb), 0.002)
	ys, xs = np.where(mask)
	rgba = np.dstack([rgb, np.where(erode(mask, 1), 255, 0).astype(np.uint8)])[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
	im = Image.fromarray(rgba, "RGBA")
	k = 200 / im.width
	im = im.resize((200, max(1, round(im.height * k))), Image.Resampling.LANCZOS)
	a = np.array(im)
	a[..., 3] = np.where(a[..., 3] > 128, 255, 0)
	Image.fromarray(a, "RGBA").save(ROOT / "assets" / "ui" / "logo.png")
	print("logo", im.size)
