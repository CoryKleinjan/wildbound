"""Hand-pixelled overworld tileset in the style of the Gen 3 handheld games (original art).

python3 tools/tileset/make_tiles.py      # -> assets/tiles/*.png, assets/buildings/*.png

Everything is drawn pixel by pixel on exact 16x16 tiles so the ground tiles tile seamlessly and
the buildings match the map footprints (roof rows + one wall row) the game draws them over.
"""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
TILES = ROOT / "assets" / "tiles"
BUILD = ROOT / "assets" / "buildings"


def hexc(h: str, a: int = 255) -> tuple:
	h = h.lstrip("#")
	return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def shade(c, f):
	if f >= 0:
		return tuple(int(v + (255 - v) * f) for v in c[:3]) + (c[3],)
	return tuple(int(v * (1 + f)) for v in c[:3]) + (c[3],)


# ---------------------------------------------------------------- palette
OUT = hexc("#283028")      # general dark outline
G = hexc("#88d070")        # grass
G_D = hexc("#68b050")      # grass tuft
G_L = hexc("#b0e898")      # grass light fleck
TG_BG = hexc("#4c9a3c")
TG_O = hexc("#20502a")
TG_M = hexc("#3f9238")
TG_L = hexc("#70c050")
TG_T = hexc("#a8e078")
P = hexc("#e8d0a0")        # path
P_D = hexc("#d0b478")
P_L = hexc("#f4e4c0")
EDGE = hexc("#508c3c")     # line where grass meets path
EDGE_S = hexc("#c8a870")   # path shadow under the grass edge
W = hexc("#5890e0")        # water
W_D = hexc("#4878c8")
W_L = hexc("#88c0f8")
W_F = hexc("#e0f0ff")
SAND = hexc("#f0dca8")
TR_O = hexc("#183820")
TR_D = hexc("#2a6a30")
TR_M = hexc("#3c8c3c")
TR_L = hexc("#5cb04c")
TR_H = hexc("#88d068")
TRUNK = hexc("#6a4428")
TRUNK_L = hexc("#946038")
WOOD = hexc("#b07840")
WOOD_D = hexc("#7a5028")
WOOD_L = hexc("#d8a060")
CLEAR = (0, 0, 0, 0)


class Canvas:
	def __init__(self, w, h, fill=CLEAR):
		self.im = Image.new("RGBA", (w, h), fill)
		self.w, self.h = w, h

	def px(self, x, y, c):
		if 0 <= x < self.w and 0 <= y < self.h:
			if c[3] == 255:
				self.im.putpixel((x, y), c)
			elif c[3] > 0:
				d = self.im.getpixel((x, y))
				a = c[3] / 255
				self.im.putpixel((x, y), tuple(int(c[i] * a + d[i] * (1 - a)) for i in range(3)) + (max(d[3], c[3]),))

	def rect(self, x, y, w, h, c):
		for yy in range(y, y + h):
			for xx in range(x, x + w):
				self.px(xx, yy, c)

	def get(self, x, y):
		return self.im.getpixel((x % self.w, y % self.h))

	def save(self, path):
		path.parent.mkdir(parents=True, exist_ok=True)
		self.im.save(path)


# ---------------------------------------------------------------- ground
def grass(c: Canvas, ox=0, oy=0, variant=0):
	c.rect(ox, oy, 16, 16, G)
	tufts = [(2, 3), (10, 1), (6, 8), (13, 9), (1, 12), (9, 13)] if variant == 0 else [(4, 2), (12, 4), (2, 8), (9, 9), (5, 13), (13, 14)]
	for x, y in tufts:
		c.px(ox + x, oy + y, G_D)
		c.px(ox + x + 2, oy + y, G_D)
		c.px(ox + x + 1, oy + y + 1, G_D)
	for x, y in ([(7, 4), (14, 6), (4, 10)] if variant == 0 else [(8, 6), (1, 4), (12, 11)]):
		c.px(ox + x, oy + y, G_L)


def tall_grass(c: Canvas):
	c.rect(0, 0, 16, 16, TG_BG)
	# four leafy tufts, one per 8x8 quarter, each a fan of three pointed blades
	for qx, qy in ((0, 0), (8, 0), (0, 8), (8, 8)):
		for bx, top, lean in ((1, 2, -1), (3, 0, 0), (5, 2, 1)):
			for y in range(top, 8):
				t = (y - top) / max(1, 7 - top)
				x = qx + bx + round(lean * (1 - t) * 1.0)
				wid = 1 if y - top < 2 else 2
				for k in range(wid):
					c.px(x + k, qy + y, TG_M if k == 0 else TG_L)
				c.px(x - 1, qy + y, TG_O)
				c.px(x + wid, qy + y, TG_O)
			c.px(qx + bx + lean, qy + top, TG_T)
			c.px(qx + bx + lean, qy + top - 1, TG_O)
		c.rect(qx, qy + 7, 8, 1, TG_O)


def path(c: Canvas, ox=0, oy=0):
	c.rect(ox, oy, 16, 16, P)
	for x, y in [(3, 2), (11, 5), (6, 11), (14, 13), (1, 8), (9, 15)]:
		c.px(ox + x, oy + y, P_D)
	for x, y in [(4, 2), (12, 6), (7, 12)]:
		c.px(ox + x, oy + y, P_L)


def path_top():
	"""Path with grass overhanging its top edge (rotated by the game for the other sides)."""
	c = Canvas(16, 16)
	path(c)
	prof = [3, 3, 4, 4, 3, 2, 2, 3, 3, 4, 4, 4, 3, 2, 2, 3]
	for x in range(16):
		d = prof[x]
		for y in range(d):
			c.px(x, y, G)
		c.px(x, d, EDGE)
		c.px(x, d + 1, EDGE_S)
	c.px(5, 0, G_D)
	c.px(11, 1, G_D)
	return c


def water(frame=0):
	c = Canvas(16, 16)
	c.rect(0, 0, 16, 16, W)
	o = 2 if frame else 0
	for x, y, n in [(1, 3, 4), (9, 2, 3), (4, 8, 4), (12, 9, 3), (2, 13, 3), (9, 14, 4)]:
		for k in range(n):
			c.px((x + k + o) % 16, y, W_L)
		c.px((x + o) % 16, y + 1, W_D)
		c.px((x + n - 1 + o) % 16, y + 1, W_D)
	c.px((6 + o) % 16, 3, W_F)
	c.px((14 + o) % 16, 9, W_F)
	return c


def shore():
	"""Water with a sandy bank and foam along the top (rotated by the game)."""
	c = water()
	prof = [3, 4, 4, 3, 3, 4, 5, 5, 4, 3, 3, 4, 4, 5, 4, 3]
	for x in range(16):
		d = prof[x]
		for y in range(d):
			c.px(x, y, SAND)
		c.px(x, d, W_F)
		c.px(x, d + 1, W_L)
	return c


def ledge():
	c = Canvas(16, 16)
	grass(c)
	c.rect(0, 9, 16, 1, G_L)
	c.rect(0, 10, 16, 3, hexc("#5a9a40"))
	c.rect(0, 13, 16, 1, OUT)
	c.rect(0, 14, 16, 2, G)
	for x in range(0, 16, 4):
		c.px(x + 1, 11, hexc("#4a8434"))
		c.px(x + 2, 12, hexc("#4a8434"))
	return c


def flowers(frame=0):
	c = Canvas(16, 16)
	grass(c, variant=1)
	cols = [(hexc("#f05050"), hexc("#f8e050")), (hexc("#f8f8f8"), hexc("#f8c030"))]
	for (fx, fy), (pet, mid) in zip([(4, 4), (11, 10)], cols):
		dx = 1 if frame else 0
		for x, y in ((0, -1), (-1, 0), (1, 0), (0, 1)):
			c.px(fx + x + dx, fy + y, pet)
		c.px(fx + dx, fy, mid)
		c.px(fx - 1 + dx, fy - 1, OUT)
		c.px(fx + 1 + dx, fy + 1, shade(pet, -0.3))
		c.px(fx, fy + 2, G_D)
	return c


def sign():
	c = Canvas(16, 16)
	grass(c)
	c.rect(7, 9, 2, 6, OUT)
	c.rect(7, 9, 1, 5, WOOD_D)
	c.rect(2, 2, 12, 8, OUT)
	c.rect(3, 3, 10, 6, WOOD)
	c.rect(3, 3, 10, 1, WOOD_L)
	c.rect(4, 5, 8, 1, WOOD_D)
	c.rect(4, 7, 6, 1, WOOD_D)
	c.rect(3, 14, 10, 1, G_D)
	return c


def fence():
	c = Canvas(16, 16)
	grass(c)
	for x in (2, 12):
		c.rect(x, 4, 3, 10, OUT)
		c.rect(x + 1, 5, 1, 8, WOOD)
	c.rect(0, 6, 16, 3, OUT)
	c.rect(0, 7, 16, 1, WOOD_L)
	c.rect(0, 10, 16, 3, OUT)
	c.rect(0, 11, 16, 1, WOOD)
	return c


def tree(variant=0):
	"""32x32 round leafy tree on a transparent background, trunk at the bottom centre."""
	c = Canvas(32, 32)
	cx, cy = 16, 13 + (variant % 2)
	import math
	# lumpy outline radius
	def r(a):
		return 13.2 + 1.2 * math.sin(a * 5 + variant) + 0.6 * math.sin(a * 9)
	for y in range(32):
		for x in range(32):
			dx, dy = x + 0.5 - cx, (y + 0.5 - cy) * 1.08
			d = math.hypot(dx, dy)
			a = math.atan2(dy, dx)
			R = r(a)
			if d < R:
				# light from the top-left
				l = (-dx * 0.55 - dy * 0.85) / R
				col = TR_D if l < -0.15 else TR_M if l < 0.35 else TR_L if l < 0.7 else TR_H
				c.px(x, y, col)
	# leaf clumps: darker crescent under each clump
	for (lx, ly) in [(10, 9), (19, 7), (24, 14), (8, 17), (16, 15), (21, 21), (12, 22)]:
		for k in range(-2, 3):
			c.px(lx + k, ly + 2, TR_D)
		c.px(lx - 3, ly + 1, TR_D)
		c.px(lx + 3, ly + 1, TR_D)
		c.px(lx, ly - 1, TR_H if ly < 14 else TR_L)
	# trunk
	c.rect(13, 25, 6, 6, OUT)
	c.rect(14, 25, 4, 5, TRUNK)
	c.rect(14, 25, 1, 5, TRUNK_L)
	# outline around the canopy
	snap = c.im.copy()
	for y in range(32):
		for x in range(32):
			if snap.getpixel((x, y))[3] == 0:
				n = [snap.getpixel((x + dx, y + dy))[3] if 0 <= x + dx < 32 and 0 <= y + dy < 32 else 0
					for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))]
				if max(n) > 0:
					c.px(x, y, TR_O)
	# soft shadow at the foot
	for x in range(9, 23):
		if c.im.getpixel((x, 31))[3] == 0:
			c.px(x, 31, (0, 0, 0, 60))
	return c


# ---------------------------------------------------------------- indoor bits
def floor():
	c = Canvas(16, 16)
	c.rect(0, 0, 16, 16, hexc("#d8d8d8"))
	c.rect(0, 15, 16, 1, hexc("#b8b8b8"))
	c.rect(15, 0, 1, 16, hexc("#c4c4c4"))
	c.rect(0, 0, 16, 1, hexc("#ececec"))
	return c


def iwall():
	c = Canvas(16, 16)
	c.rect(0, 0, 16, 16, hexc("#585068"))
	for y in (3, 8, 13):
		c.rect(0, y, 16, 1, hexc("#484058"))
	for y, xs in ((0, (5, 13)), (4, (1, 9)), (9, (5, 13))):
		for x in xs:
			c.rect(x, y, 1, 3 if y else 3, hexc("#484058"))
	c.rect(0, 0, 16, 1, hexc("#706880"))
	return c


def mat():
	c = floor()
	c.rect(1, 3, 14, 10, OUT)
	c.rect(2, 4, 12, 8, hexc("#d04848"))
	c.rect(3, 5, 10, 6, hexc("#e86060"))
	c.rect(4, 7, 8, 2, hexc("#f8b0b0"))
	return c


def statue():
	c = floor()
	c.rect(3, 11, 10, 4, OUT)
	c.rect(4, 12, 8, 2, hexc("#787080"))
	c.rect(4, 2, 8, 10, OUT)
	c.rect(5, 3, 6, 8, hexc("#a8a0b0"))
	c.rect(5, 3, 2, 3, hexc("#d8d0e0"))
	c.rect(5, 1, 6, 2, hexc("#e0c050"))
	return c


# ---------------------------------------------------------------- buildings
WALL = hexc("#f4ecd8")
WALL_D = hexc("#d8ccb0")
WALL_B = hexc("#b8a888")
GLASS = hexc("#80c0f0")
GLASS_L = hexc("#d8f0ff")
FRAME = hexc("#505868")

ROOFS = {
	"house": (hexc("#d05040"), hexc("#a83830"), hexc("#f08070")),
	"lodge": (hexc("#e86080"), hexc("#c04060"), hexc("#f8a0b8")),
	"mart": (hexc("#4878d0"), hexc("#3058a8"), hexc("#80a8f0")),
	"gym": (hexc("#80889c"), hexc("#5c6478"), hexc("#b0b8c8")),
	"league": (hexc("#7858b8"), hexc("#583890"), hexc("#a888e0")),
}


def window(c: Canvas, x, y, w=10, h=8):
	c.rect(x, y, w, h, FRAME)
	c.rect(x + 1, y + 1, w - 2, h - 2, GLASS)
	c.rect(x + 1, y + 1, w - 2, 1, GLASS_L)
	c.rect(x + 1, y + 1, 1, h - 3, GLASS_L)
	c.rect(x + w // 2, y + 1, 1, h - 2, FRAME)
	c.rect(x + 1, y + h, w - 2, 1, WALL_B)


def building(kind: str, tw: int, th: int, door_cols=()) -> Canvas:
	"""A tw x th tile building seen from the front and above: shingled roof over the top
	th-1 rows (with eaves overhanging the wall row) and a front wall in the last row."""
	W_, H_ = tw * 16, th * 16
	c = Canvas(W_, H_)
	base, dark, light = ROOFS[kind]
	door_top = (th - 1) * 16
	wall_top = door_top - 7  # the wall is taller than the door row, like the GBA houses
	wh = H_ - wall_top
	# front wall
	c.rect(0, wall_top - 2, W_, wh + 2, OUT)
	c.rect(1, wall_top - 1, W_ - 2, wh, WALL)
	c.rect(1, H_ - 4, W_ - 2, 3, WALL_D)
	c.rect(1, H_ - 2, W_ - 2, 1, WALL_B)
	c.rect(1, wall_top - 1, 1, wh, WALL_D)
	c.rect(W_ - 2, wall_top - 1, 1, wh, WALL_D)
	# windows in every wall column without a door
	for col in range(tw):
		if col in door_cols or (col == 0 and tw > 3) or (col == tw - 1 and tw > 3 and kind in ("gym", "league")):
			continue
		window(c, col * 16 + 2, wall_top + 4, 12, 11)
	if kind in ("gym", "league"):
		for col in (0, tw - 1):
			x = col * 16 + 5
			c.rect(x, wall_top + 2, 6, wh - 3, OUT)
			c.rect(x + 1, wall_top + 2, 4, wh - 4, hexc("#e8e0f0") if kind == "league" else hexc("#c8c8d0"))
			c.rect(x + 1, wall_top + 2, 1, wh - 4, (255, 255, 255, 255))
	# roof: slight trapezoid (narrower at the ridge), shingle rows, ridge highlight, eaves
	roof_bottom = wall_top + 3
	for y in range(0, roof_bottom):
		inset = max(0, 3 - y // 3)
		x0, x1 = inset, W_ - inset
		c.rect(x0, y, x1 - x0, 1, OUT)
		if y == 0:
			continue
		# the slope darkens toward the eave
		tone = shade(base, 0.12 - 0.3 * y / roof_bottom)
		c.rect(x0 + 1, y, x1 - x0 - 2, 1, tone)
		c.px(x0 + 1, y, dark)
		c.px(x1 - 2, y, dark)
		row = (y - 2) % 5
		if row == 4:
			c.rect(x0 + 1, y, x1 - x0 - 2, 1, dark)
		else:
			off = 0 if ((y - 2) // 5) % 2 else 4
			for x in range(x0 + 1 + off, x1 - 1, 8):
				c.px(x, y, dark)
		if row == 0:
			c.rect(x0 + 1, y, x1 - x0 - 2, 1, shade(base, 0.12))
	c.rect(4, 1, W_ - 8, 2, light)
	c.rect(1, roof_bottom - 3, W_ - 2, 2, dark)
	c.rect(0, roof_bottom - 1, W_, 1, OUT)
	c.rect(1, roof_bottom, W_ - 2, 1, (0, 0, 0, 70))  # eave shadow on the wall
	# roof decorations
	mid = W_ // 2
	if kind == "lodge":
		c.rect(mid - 8, 4, 16, 12, OUT)
		c.rect(mid - 7, 5, 14, 10, (255, 255, 255, 255))
		c.rect(mid - 2, 6, 4, 8, hexc("#e03040"))
		c.rect(mid - 5, 8, 10, 4, hexc("#e03040"))
	elif kind == "mart":
		c.rect(mid - 12, 5, 24, 10, OUT)
		c.rect(mid - 11, 6, 22, 8, hexc("#3858c8"))
		c.rect(mid - 9, 8, 18, 4, (255, 255, 255, 255))
		for k in range(0, 16, 4):
			c.rect(mid - 8 + k, 9, 2, 2, hexc("#3858c8"))
	elif kind == "gym":
		c.rect(mid - 9, 6, 18, 16, OUT)
		c.rect(mid - 8, 7, 16, 14, hexc("#e8c040"))
		c.rect(mid - 5, 10, 10, 8, hexc("#f8e890"))
		c.rect(mid - 2, 9, 4, 10, hexc("#c89820"))
	elif kind == "league":
		c.rect(4, roof_bottom - 5, W_ - 8, 2, hexc("#e8c040"))
		c.rect(mid - 7, 4, 14, 14, OUT)
		c.rect(mid - 6, 5, 12, 12, hexc("#e8c040"))
		c.rect(mid - 3, 8, 6, 6, hexc("#fff0a0"))
	elif kind == "house":
		# chimney
		c.rect(W_ - 16, 0, 6, 8, OUT)
		c.rect(W_ - 15, 1, 4, 6, hexc("#a06048"))
	return c


def door(ch: str) -> Canvas:
	c = Canvas(16, 16)
	c.rect(0, 0, 16, 16, WALL)
	c.rect(0, 13, 16, 3, WALL_D)
	c.rect(0, 15, 16, 1, WALL_B)
	if ch == "h":
		c.rect(3, 1, 10, 15, OUT)
		c.rect(4, 2, 8, 14, hexc("#9a6034"))
		c.rect(4, 2, 8, 1, hexc("#c08048"))
		c.rect(5, 4, 6, 4, hexc("#7a4824"))
		c.px(10, 10, hexc("#f8d860"))
	else:
		glass = {"l": hexc("#f8b0c8"), "m": hexc("#a8d0f8"), "j": hexc("#c8c8d0"), "u": hexc("#c8a8e8")}[ch]
		trim = {"l": hexc("#e05070"), "m": hexc("#3858c8"), "j": hexc("#e8c040"), "u": hexc("#e8c040")}[ch]
		c.rect(1, 1, 14, 15, OUT)
		c.rect(2, 2, 12, 14, glass)
		c.rect(7, 2, 2, 14, OUT)
		c.rect(2, 2, 12, 2, trim)
		c.rect(3, 5, 2, 6, (255, 255, 255, 200))
		c.rect(10, 5, 2, 6, (255, 255, 255, 200))
	return c


def main():
	TILES.mkdir(parents=True, exist_ok=True)
	for n, v in (("grass", 0), ("grass2", 1)):
		c = Canvas(16, 16)
		grass(c, variant=v)
		c.save(TILES / f"{n}.png")
	c = Canvas(16, 16)
	tall_grass(c)
	c.save(TILES / "tallgrass.png")
	c = Canvas(16, 16)
	path(c)
	c.save(TILES / "path.png")
	path_top().save(TILES / "path_top.png")
	water(0).save(TILES / "water2.png")
	shore().save(TILES / "shore.png")
	ledge().save(TILES / "ledge.png")
	flowers(0).save(TILES / "flowers.png")
	flowers(1).save(TILES / "flowers2.png")
	sign().save(TILES / "sign.png")
	fence().save(TILES / "fence.png")
	floor().save(TILES / "floor.png")
	iwall().save(TILES / "iwall.png")
	mat().save(TILES / "mat.png")
	statue().save(TILES / "statue.png")
	for ch in "hlmju":
		door(ch).save(TILES / f"door_{ch}.png")
	for i in range(4):
		tree(i).save(TILES / f"tree32_{i}.png")
	# buildings at every footprint the maps use: kind_WxH.png (+ the default kind.png)
	sizes = {"house": [(4, 3, (2,))], "lodge": [(5, 3, (2,)), (6, 3, (3,))], "mart": [(5, 3, (2,)), (4, 3, (1,))],
		"gym": [(7, 4, (3,))], "league": [(7, 4, (3,))]}
	for kind, lst in sizes.items():
		for i, (w, h, doors) in enumerate(lst):
			b = building(kind, w, h, doors)
			b.save(BUILD / f"{kind}_{w}x{h}.png")
			if i == 0:
				b.save(BUILD / f"{kind}.png")
	print("tiles written")


if __name__ == "__main__":
	main()
