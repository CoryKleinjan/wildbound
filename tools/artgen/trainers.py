"""Trainer art: 16x20 overworld frames (down/up/left; right is mirrored) and 64x64 battle portraits.

python3 tools/artgen/trainers.py sample p1 hiker ...   # synchronous
python3 tools/artgen/trainers.py process
"""
import json
import sys

import numpy as np
from PIL import Image

from common import RAW, ROOT, STYLE, ask_vision, generate_image, misc
from pixel import _largest_blobs, erode, key_background, mode_resize

OUT = ROOT / "assets" / "trainers"

WHO = {
	"p1": "a young boy hero adventurer with a baseball cap and a small backpack (the player character)",
	"p2": "a young girl hero adventurer with a bandana and a small bag (the second player character)",
	"mom": "a friendly mother in casual clothes with an apron",
	"old": "an elderly creature professor in a lab coat over a shirt",
	"girl": "a cheerful young girl trainer in a skirt",
	"boy": "a young boy trainer in shorts and a cap",
	"hiker": "a burly bearded hiker with a big backpack",
	"psychic": "a mysterious psychic trainer in flowing robes",
	"rival": "a cocky teenage rival trainer with spiky hair and a jacket",
	"clerk": "a shop clerk in a uniform and visor",
	"nurse": "a kind nurse who heals creatures, nurse cap",
	"bird": "a bird keeper trainer with a feathered cap",
	"blackbelt": "a martial artist black belt in a karate gi",
	"battlegirl": "a female martial artist battle girl with a headband",
	"hex": "a spooky hex maniac occult girl with long hair and a dark dress",
	"gentleman": "an elegant old gentleman in a suit and top hat",
	"beauty": "a glamorous young woman trainer (beauty)",
	"ace": "a skilled ace trainer in a sporty uniform",
	"swimmer": "a swimmer trainer in swimwear with goggles",
	"gymRock": "a tough rock-type gym leader, a rugged miner with a hard hat",
	"gymFighting": "a fighting-type gym leader, a muscular martial arts master",
	"gymElectric": "an electric-type gym leader, an eccentric inventor with goggles",
	"gymFire": "a fire-type gym leader with fiery wild hair and a scarf",
	"gymNormal": "a normal-type gym leader, a laid-back dad in a sweater vest",
	"gymFlying": "a flying-type gym leader, a pilot with a scarf and aviator cap",
	"gymPsychic": "a psychic-type gym leader, a calm twin-tailed mystic",
	"orderGrunt": "a grunt of a sinister secret cult called the Hollow Order, hooded grey uniform",
	"orderAdmin": "an admin of the sinister Hollow Order cult, sharp dark uniform with a crimson coat",
	"orderBoss": "Magister Vane, the cold and imposing leader of the Hollow Order cult, long dark coat with pale gold trim",
	"prof": "Professor Alder, a kind middle-aged creature professor in a white lab coat",
	"gymWater": "a water-type gym leader, a surfer with a wetsuit",
}


def colors(pal: dict) -> str:
	return f"hat {pal['hat']}, shirt {pal['shirt']}, pants {pal['pants']}, hair {pal['hair']}, skin {pal['skin']}"


def sheet_prompt(name: str, pal: dict) -> str:
	return (
		f"Overworld walking sprite turnaround sheet for {WHO.get(name, 'a trainer')}. "
		f"Colors: {colors(pal)}. Exactly three poses of the same character side by side in one row, evenly spaced, same size, "
		"in this order from left to right: 1) FRONT view facing the viewer, 2) BACK view facing away from the viewer "
		"(we see the back of the head), 3) LEFT side profile facing left. Standing still. "
		"Top-down RPG overworld chibi style like Game Boy Advance monster RPG towns: big head, small body, about 2 heads tall, "
		"very simple shapes and bold dark outlines so it reads at 16 pixels wide. "
		"Plain solid flat magenta (#FF00FF) background, no shadows, no ground, no text or labels."
	)


def portrait_prompt(name: str, pal: dict) -> str:
	return (
		f"Battle portrait of {WHO.get(name, 'a trainer')}, full body, facing the viewer slightly turned to the left, confident battle pose. "
		f"Colors: {colors(pal)}. {STYLE.replace('battle sprite', 'trainer battle sprite')} "
		"Plain solid flat magenta (#FF00FF) background, no shadow, no ground. Absolutely no text, letters or captions. Only the one person."
	)


def _blobs(mask: np.ndarray) -> list[tuple[int, int, int, int]]:
	"""Bounding boxes of the poses: splits the subject at empty columns, keeps the 3 widest groups."""
	cols = mask.any(axis=0)
	runs, start = [], None
	for x, c in enumerate(list(cols) + [False]):
		if c and start is None:
			start = x
		elif not c and start is not None:
			runs.append((start, x))
			start = None
	runs = sorted(sorted(runs, key=lambda r: r[0] - r[1])[:3])
	boxes = []
	for x0, x1 in runs:
		ys = np.nonzero(mask[:, x0:x1].any(axis=1))[0]
		boxes.append((x0, ys.min(), x1, ys.max() + 1))
	return boxes


def sheet_raw(name: str):
	return RAW / "trainers" / f"{name}_sheet.png"


def sheet_views(name: str) -> list[str]:
	"""Which way each of the 3 poses faces, left to right (asked once, cached next to the raw sheet)."""
	cache = RAW / "trainers" / f"{name}_views.json"
	if not cache.exists():
		ans = ask_vision(sheet_raw(name), "This sprite sheet shows poses of one character, left to right. For each pose, "
			"say which way the character faces: \"front\" (towards the viewer), \"back\" (away from the viewer), "
			"\"left\" or \"right\" (side profile, the way the nose points from the viewer's point of view). "
			"Answer with a JSON array of strings, one per pose.")
		cache.write_text(ans)
	return json.loads(cache.read_text())


def overworld_frames(name: str) -> list[Image.Image] | None:
	src = sheet_raw(name)
	if not src.exists():
		return None
	rgb = np.array(Image.open(src).convert("RGB"))
	mask = _largest_blobs(key_background(rgb), 0.1)
	boxes = _blobs(mask)
	if len(boxes) != 3:
		print("WARN", name, "found", len(boxes), "poses")
		return None
	rgba = np.dstack([rgb, np.where(erode(mask, 2), 255, 0).astype(np.uint8)])
	k = 19 / max(b[3] - b[1] for b in boxes)  # one scale so all poses match
	views = sheet_views(name)
	if sorted(v if v != "right" else "left" for v in views) != ["back", "front", "left"]:
		print("WARN", name, "views", views)
		return None
	frames = {}
	for (x0, y0, x1, y1), view in zip(boxes, views):
		crop = Image.fromarray(rgba[y0:y1, x0:x1], "RGBA")
		w, h = min(16, max(1, round((x1 - x0) * k))), max(1, round((y1 - y0) * k))
		small = mode_resize(crop, (w, h), 16)
		frame = Image.new("RGBA", (16, 20))
		frame.paste(small, ((16 - w) // 2, 20 - h), small)
		frames["left" if view == "right" else view] = frame.transpose(Image.Transpose.FLIP_LEFT_RIGHT) if view == "right" else frame
	return [frames["front"], frames["back"], frames["left"]]


def process(name: str) -> None:
	OUT.mkdir(parents=True, exist_ok=True)
	frames = overworld_frames(name)
	if frames:
		strip = Image.new("RGBA", (48, 20))
		for i, f in enumerate(frames):
			strip.paste(f, (i * 16, 0))
		strip.save(OUT / f"{name}_walk.png")
	src = RAW / "trainers" / f"{name}_portrait.png"
	if src.exists():
		from pixel import to_sprite
		to_sprite(src, 64, 62, colors=16).save(OUT / f"{name}.png")


def sample(names: list[str]) -> None:
	pals = misc()["palettes"]
	for n in names:
		generate_image(sheet_prompt(n, pals[n]), sheet_raw(n), aspect="16:9")
		generate_image(portrait_prompt(n, pals[n]), RAW / "trainers" / f"{n}_portrait.png")
		process(n)
		print("done", n, flush=True)


if __name__ == "__main__":
	if sys.argv[1] == "sample":
		sample(sys.argv[2:])
	else:
		for n in misc()["palettes"]:
			process(n)
