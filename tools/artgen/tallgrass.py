"""The tall grass tile (',') drawn over every map painting: cory picked the tufted tall grass in the Mistwood Path (route2)
painting, so the tiles are cut from it (one tuft per 16x16 tile there). Output: assets/tiles/tallgrass.png, tallgrass2.png.

python3 tools/artgen/tallgrass.py
"""
from PIL import Image

from common import ROOT

SOURCE = ROOT / "assets" / "maps" / "route2.png"
CELLS = [(17, 11), (18, 11)]  # inside the tufted patch at x 16-21, y 10-12

if __name__ == "__main__":
	im = Image.open(SOURCE).convert("RGBA")
	for i, (x, y) in enumerate(CELLS):
		im.crop((x * 16, y * 16, x * 16 + 16, y * 16 + 16)).save(ROOT / "assets" / "tiles" / ("tallgrass.png" if i == 0 else "tallgrass2.png"))
