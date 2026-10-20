"""Small sprites for the slot machine, contests, overworld effects, weather, egg hatching, trades and the battle HUD,
drawn on pixel-grid sheets (gridsheet.py). Output: assets/fx/<name>.png and assets/ui/<name>.png.

python3 tools/artgen/extras.py [sheet ...]     # sheets: small, hud
"""
import sys

from common import RAW, ROOT
from gridsheet import Sheet, opaque

SMALL = Sheet(cols=4, rows=5, w=24, h=24, gap=4, scale=10)
HUD = Sheet(cols=2, rows=6, w=64, h=16, gap=4, scale=10)

SHEETS = {
	"small": (SMALL, "fx", [
		("slot_7", "a slot machine reel symbol: a big bold red number seven with a dark outline"),
		("slot_bar", "a slot machine reel symbol: a black bar plate with three gold stripes (no letters)"),
		("slot_orb", "a slot machine reel symbol: a round red-and-white capture orb"),
		("slot_leaf", "a slot machine reel symbol: a bright green leaf"),
		("slot_grape", "a slot machine reel symbol: a bunch of purple berries with a green stem"),
		("contest_heart", "a small bright pink heart, the contest appeal heart, centered and filling half the box"),
		("contest_star", "a small orange-gold star, a contest appeal point, centered and filling half the box"),
		("emote_exclaim", "the white speech bubble with a red exclamation mark that pops over a trainer who spots you"),
		("fx_rustle", "a tuft of tall grass rustling: leaves flicking outward, as when a creature walks through grass"),
		("fx_wake", "a small white-and-blue water splash ring, the wake around a swimmer"),
		("shadow", "a soft dark grey oval ground shadow, wide and flat, centered at the bottom"),
		("wx_rain", "two thin pale blue diagonal rain streaks"),
		("wx_sand", "a few tan sand grains blowing sideways"),
		("wx_ash", "a few grey volcanic ash flakes drifting"),
		("wx_fog", "a soft white wisp of fog, filling the box width"),
		("sparkle", "a four-pointed white and pale yellow twinkle sparkle"),
		("egg_crack1", "a creature Egg (cream with green spots) with a small crack at the top"),
		("egg_crack2", "the same Egg with big cracks all over, light shining through"),
		("egg_burst", "egg shell pieces bursting apart in a bright white flash"),
		("trade_orb", "a glowing capture orb surrounded by a bright cyan aura, flying"),
	]),
	"hud": (HUD, "ui", [
		("hp_frame", "the Pokemon Emerald battle HP bar frame: a small gold 'HP' tag shape on the left (draw it as a plain gold "
			"rounded tag, no letters) and a long empty dark grey bar slot to its right with a thin dark outline, filling the box"),
		("exp_frame", "a thin empty experience bar slot: a long dark blue-grey groove with a thin outline, centered vertically"),
		("plate", "a plain white rounded pill-shaped label plate with a soft grey bottom shadow and a highlight on top, filling the box"),
		("platform_field", "a battle platform: a flat oval patch of light green grass with a darker rim, seen from a low angle"),
		("platform_forest", "a battle platform: a flat oval of dark green moss and leaves with a darker rim"),
		("platform_beach", "a battle platform: a flat oval of pale sand with a darker rim"),
		("platform_mountain", "a battle platform: a flat oval of brown rocky ground with a darker rim"),
		("platform_town", "a battle platform: a flat oval of grey paving stones with a darker rim"),
		("platform_gym", "a battle platform: a flat oval of polished stone tiles with a gold rim"),
		("platform_league", "a battle platform: a flat oval of royal purple tiles with a gold rim"),
		("platform_night", "a battle platform: a flat oval of dark blue-green grass under moonlight with a darker rim"),
	]),
}


def run(name: str) -> None:
	sheet, folder, subjects = SHEETS[name]
	lines = "\n".join(f"Box {i + 1} (row {i // sheet.cols + 1}, column {i % sheet.cols + 1}): {d}" for i, (_, d) in enumerate(subjects))
	raw = RAW / "extras" / f"{name}.png"
	raw.parent.mkdir(parents=True, exist_ok=True)
	sheet.generate("Draw one sprite in each box, centered. Leave boxes with no subject empty. No text or letters anywhere.\n" + lines, raw)
	out = ROOT / "assets" / folder
	out.mkdir(parents=True, exist_ok=True)
	for (sid, _), img in zip(subjects, sheet.read(raw)):
		if opaque(img) < 0.02:
			print("WARN empty", sid)
			continue
		img.save(out / f"{sid}.png")


if __name__ == "__main__":
	for n in sys.argv[1:] or list(SHEETS):
		run(n)
		print("done", n, flush=True)
