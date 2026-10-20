"""Party menu icons: a small 32x32 two-frame icon for every creature, like the Emerald party and PC icons, drawn by
Nano Banana Pro from the creature's battle sprite. Output: assets/creatures/icons/<id>.png (64x32: frame 1 | frame 2).

python3 tools/artgen/partyicons.py generate [species ...] | process
"""
import sys
from concurrent.futures import ThreadPoolExecutor

from PIL import Image

from common import RAW, ROOT, species
from gridsheet import Sheet, opaque

OUT = ROOT / "assets" / "creatures" / "icons"
PER = 6  # creatures per sheet: 2 columns (frames) x 6 rows
SHEET = Sheet(cols=2, rows=PER, w=32, h=32, gap=4, scale=8)


def batches(ids: list[str]) -> list[list[str]]:
	return [ids[i:i + PER] for i in range(0, len(ids), PER)]


def prompt(batch: list[str], sp: dict) -> str:
	lines = "\n".join(f"Row {i + 1}: {sp[k]['name']} ({'/'.join(sp[k]['types'])} type), shown in reference image {i + 2}."
		for i, k in enumerate(batch))
	return ("Draw Pokemon Emerald party menu icons: each row is one creature as a tiny chibi icon, about 24 pixels across, facing "
		"slightly left, standing at the bottom of its box. Column 1 and column 2 are its two animation frames (column 2 hops or "
		"bounces one or two pixels up, or flaps/sways). Keep each creature's colors and silhouette exactly from its reference "
		"image, simplified to read at this tiny size. No text.\n" + lines)


def raw(k: int) -> "Path":
	return RAW / "partyicons" / f"sheet{k:03d}.png"


def generate(k: int, batch: list[str], sp: dict) -> None:
	refs = [ROOT / "assets" / "creatures" / f"{i}.png" for i in batch]
	for attempt in range(3):
		SHEET.generate(prompt(batch, sp), raw(k), refs)
		boxes = SHEET.read(raw(k))
		if all(opaque(b) > 0.08 for b in boxes[:len(batch) * 2]):
			return
		print("retry sheet", k, flush=True)
		raw(k).rename(raw(k).with_name(f"sheet{k:03d}_bad{attempt}.png"))
	print("WARN sheet", k, "kept failing", flush=True)


def process(k: int, batch: list[str]) -> None:
	if not raw(k).exists():
		return
	boxes = SHEET.read(raw(k))
	OUT.mkdir(parents=True, exist_ok=True)
	for i, sid in enumerate(batch):
		a, b = boxes[i * 2], boxes[i * 2 + 1]
		if opaque(a) < 0.08:
			continue
		strip = Image.new("RGBA", (64, 32))
		strip.paste(a, (0, 0))
		strip.paste(b if opaque(b) > 0.08 else a, (32, 0))
		strip.save(OUT / f"{sid}.png")


if __name__ == "__main__":
	sp = species()
	ids = sys.argv[2:] or list(sp)
	bs = batches(ids)
	if sys.argv[1] == "generate":
		raw(0).parent.mkdir(parents=True, exist_ok=True)
		with ThreadPoolExecutor(8) as ex:
			list(ex.map(lambda kb: generate(kb[0], kb[1], sp), enumerate(bs)))
	for k, b in enumerate(bs):
		process(k, b)
	print("done", len(bs), "sheets", flush=True)
