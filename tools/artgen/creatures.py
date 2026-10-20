"""Creature front/back sprite prompts and the 64x64 pixel-art post-process.

python3 tools/artgen/creatures.py sample id1 id2 ...   # synchronous, for previews
python3 tools/artgen/creatures.py process              # raw/*.png -> assets/creatures/*.png
"""
import sys
from pathlib import Path

from common import RAW, ROOT, STYLE, generate_image, species
from pixel import to_sprite

OUT = ROOT / "assets" / "creatures"

BODY = {
	"quad": "a four-legged animal-like creature",
	"biped": "a creature standing upright on two legs",
	"bird": "a bird-like creature",
	"bug": "an insect-like bug creature",
	"blob": "a round, soft blob-like creature",
	"rock": "a creature made of stone and rock",
	"ghost": "a floating spectral ghost creature",
	"fish": "a fish-like aquatic creature",
	"serpent": "a long serpentine creature",
}
FEATURE = {
	"spikes": "spikes", "crest": "a head crest", "tail": "a tail", "ears": "ears", "antenna": "antennae",
	"horn": "a horn", "wings": "wings", "mane": "a mane", "fin": "fins", "tusks": "tusks", "longEars": "long ears",
	"boltTail": "a lightning-bolt shaped tail", "shell": "a shell", "tailFlame": "a flame on its tail tip",
	"bigLeaf": "a large leaf", "flame": "flames on its body", "mushroom": "a mushroom cap", "leaf": "a leaf sprout",
	"flower": "a flower", "cheeks": "round colored cheeks",
}


def stage_word(s: dict) -> str:
	size = float(s["sprite"]["size"])
	if size < 0.6:
		return "small, cute, basic-stage"
	if size < 0.8:
		return "medium-sized, middle-stage"
	return "large, powerful, fully evolved"


def front_prompt(s: dict) -> str:
	sp = s["sprite"]
	feats = ", ".join(FEATURE.get(f, f) for f in sp["features"]) or "no special features"
	return (
		f"A single original monster named {s['name']}: {BODY.get(sp['body'], 'a creature')}, "
		f"{'/'.join(s['types'])} type, {stage_word(s)}. "
		f"Main color {sp['main']}, accent color {sp['accent']}, belly/highlight color {sp['belly']}. "
		f"Notable features: {feats}. Concept (for inspiration only, do not write it): {s['dexText']} "
		f"Front-facing three-quarter view facing left, full body visible, centered, filling most of the frame. "
		f"{STYLE} Give it a distinctive, unique silhouette that does not resemble any existing monster from other games. "
		"Plain solid flat magenta (#FF00FF) background, no shadow, no ground, no border. Absolutely no text, letters, captions or labels anywhere. Only the one creature."
	)


def back_prompt(s: dict) -> str:
	return (
		f"This is {s['name']}. Draw the exact same creature, same design, colors and proportions, "
		"seen from BEHIND (back view, like the player's own monster in a battle), three-quarter rear view facing right, "
		"full body visible, centered. Same pixel art style. "
		"Plain solid flat magenta (#FF00FF) background, no shadow, no ground. Absolutely no text, letters or captions. Only the one creature."
	)


def raw_path(sid: str, back: bool) -> Path:
	return RAW / "creatures" / f"{sid}{'_back' if back else ''}.png"


def fit_for(s: dict) -> int:
	# Same scale idea as the procedural art: small basics fill less of the 64px box.
	return round(64 * (0.62 + float(s["sprite"]["size"]) * 0.38))


def process(sid: str, s: dict) -> None:
	OUT.mkdir(parents=True, exist_ok=True)
	for back in (False, True):
		src = raw_path(sid, back)
		if src.exists():
			img = to_sprite(src, 64, fit_for(s), colors=16)
			img.save(OUT / f"{sid}{'_back' if back else ''}.png")


def sample(ids: list[str]) -> None:
	db = species()
	for sid in ids:
		s = db[sid]
		front = generate_image(front_prompt(s), raw_path(sid, False))
		generate_image(back_prompt(s), raw_path(sid, True), [front])
		process(sid, s)
		print("done", sid, flush=True)


if __name__ == "__main__":
	if sys.argv[1] == "sample":
		sample(sys.argv[2:])
	elif sys.argv[1] == "process":
		db = species()
		for sid, s in db.items():
			process(sid, s)
