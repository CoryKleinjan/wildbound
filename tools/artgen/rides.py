"""The players riding the Bicycle and Surfing (also used while diving), as 3x3 sheets of 24x24 frames:
rows face down, up, left; columns are the animation frames. Output: assets/trainers/<p1|p2>_<bike|surf>_walk.png.

python3 tools/artgen/rides.py generate | process
"""
import sys

import walkers as w
from common import misc
from trainers import WHO

w.FW, w.FH = 24, 24
w.CW = w.CH = 3 * 24 + 4 * w.GAP

RIDES = {
	"bike": "riding a sporty bicycle, seen in the Pokemon Emerald overworld view. Column 1: coasting. Columns 2 and 3: pedaling, "
		"the pedals and legs in opposite positions. In the side view the whole bicycle is visible, wheels on the bottom row of the box.",
	"surf": "sitting on the back of a big friendly blue sea creature that is swimming (the Surf ride in Pokemon Emerald), "
		"seen in the overworld view; only the rider and the creature, no water drawn. Columns 1-3: the creature bobbing and paddling.",
}


def prompt(name: str, pal: dict) -> str:
	who, ride = name.rsplit("_", 1)
	return (
		f"A Pokemon Emerald (Game Boy Advance) overworld sprite sheet of {WHO[who]} {RIDES[ride]} "
		f"Rider colors: {w.colors(pal)}. "
		"Exactly 9 sprites in a 3 by 3 grid. Row 1: facing DOWN toward the viewer. Row 2: facing UP, away from the viewer. "
		"Row 3: facing LEFT in side profile. Authentic Gen 3 overworld proportions (big head, small body), 1-pixel dark outline, 2-3 shades "
		"per color, real low-resolution pixel art enlarged with big crisp square pixels, no anti-aliasing. "
		"Plain solid flat magenta (#FF00FF) background, no shadows, no ground, no grid lines, no text."
	)


w.prompt = prompt

if __name__ == "__main__":
	pals = misc()["palettes"]
	names = sys.argv[2:] or [f"{p}_{r}" for p in ("p1", "p2") for r in RIDES]
	for n in names:
		pals[n] = pals[n.split("_")[0]]
	if sys.argv[1] == "generate":
		from concurrent.futures import ThreadPoolExecutor

		def gen(n: str) -> None:
			# Keep the attempt with the fewest problems (a surf creature may fill its box, so that's not one).
			src = w.RAW / "walk" / f"{n}.png"
			best = None
			for attempt in range(5):
				w.generate(n, pals[n], n.split("_")[0])
				bad = [b for b in w.problems(n) if not (n.endswith("surf") and "clipped" in b)]
				keep = w.RAW / "walk" / f"{n}_try{attempt}.png"
				src.rename(keep)
				if best is None or len(bad) < best[0]:
					best = (len(bad), keep)
				if not bad:
					break
				print("retry", n, bad, flush=True)
			best[1].rename(src)
		with ThreadPoolExecutor(4) as ex:
			list(ex.map(gen, names))
	for n in names:
		w.process(n)
		print("done", n, flush=True)
