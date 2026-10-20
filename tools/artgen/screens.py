"""Full-screen backgrounds (240x160) for the menu screens, drawn by Nano Banana Pro. The game draws its boxes and
text on top, so these are only the backdrop: assets/screens/<name>.png.

python3 tools/artgen/screens.py generate | process
"""
import sys
from concurrent.futures import ThreadPoolExecutor

from PIL import Image

from common import RAW, ROOT, generate_image

MODEL = "gemini-3-pro-image"
OUT = ROOT / "assets" / "screens"
BASE = (
	"A full-screen background for a menu screen in Pokemon Emerald (Game Boy Advance, 240x160 pixels), crisp GBA pixel art with "
	"big square pixels. Only the backdrop: no windows, boxes, buttons, text, letters, numbers, creatures or characters. "
)
HEADER = "Leave a plain darker header band across the top eighth of the screen. "
FULL = {"ending", "evolution", "halloffame", "gamecorner", "mail_orangeMail", "mail_harborMail", "mail_glitterMail", "mail_mechMail",
	"mail_woodMail", "mail_waveMail"}
LETTER = ("Mail stationery: a letter sheet filling the screen, with a decorated border about one sixth of the screen wide all around "
	"and a plain light writing area in the middle (no lines of text). The border: ")  # full scenes: no header band
SCREENS = {
	"party": "The party menu backdrop: a calm blue background with a subtle diagonal pattern of soft lighter-blue stripes and "
		"small rounded tile shapes, like the Emerald party screen.",
	"summary": "The creature summary screen backdrop: a light cream and pale blue background with a subtle grid pattern, "
		"a soft rounded panel area on the left for a creature portrait, like the Emerald summary screen.",
	"bag": "The bag screen backdrop: warm sandy orange background with a subtle woven pattern, and on the left side a big "
		"adventurer's backpack (a green and yellow travel bag) drawn in Emerald style.",
	"contest": "The creature contest hall screen backdrop: a festive stage with a pink and red theater curtain, spotlights and "
		"bunting, like the Emerald contest hall.",
	"storage": "The creature storage PC box backdrop: a light blue background with a soft wallpaper of rounded box shapes and "
		"little stars, like the Emerald PC box wallpaper.",
	"naming": "The name entry screen backdrop: a soft beige background with a subtle diagonal pattern, like the Emerald naming screen.",
	"halloffame": "The Hall of Fame room backdrop: a grand golden hall at night with marble pedestals in two rows, soft spotlights "
		"and a starry dark blue ceiling, like the Emerald Hall of Fame.",
	"gamecorner": "A game corner (casino arcade) backdrop: a dark red wall with rows of glowing slot machines and neon lights, "
		"seen from the front; the center of the screen is a plain dark area where a big slot machine will be drawn.",
	"ending": "An ending credits backdrop: a peaceful night sky full of stars over a grassy hill and a distant town with warm "
		"lights; the top center has open sky.",
	"evolution": "The evolution screen backdrop: a dark blue background with soft glowing rings and sparkles radiating from the center.",
	"mail_orangeMail": LETTER + "warm orange with a pattern of small round orange fruits and leaves.",
	"mail_harborMail": LETTER + "deep blue with little anchors, ships' wheels and waves, a harbor theme.",
	"mail_glitterMail": LETTER + "lavender with sparkles and tiny stars, glittering.",
	"mail_mechMail": LETTER + "steel grey with bolts, gears and metal plates, a mechanical theme.",
	"mail_woodMail": LETTER + "brown wood grain planks with small leaves, a forest cabin theme.",
	"mail_waveMail": LETTER + "sea blue with rolling white-capped waves and bubbles.",
	"starter": "A professor's lab backdrop: wooden floor, bookshelves and a lab desk at the back, warm light, like Professor Birch's lab.",
}


def generate(name: str) -> None:
	generate_image(BASE + ("The picture fills the whole screen, with no header band or border. " if name in FULL else HEADER) + SCREENS[name], RAW / "screens" / f"{name}.png", None, "3:2", MODEL)


def process(name: str) -> None:
	src = RAW / "screens" / f"{name}.png"
	if not src.exists():
		return
	im = Image.open(src).convert("RGB").resize((240, 160), Image.Resampling.LANCZOS)
	im = im.quantize(colors=64, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
	OUT.mkdir(parents=True, exist_ok=True)
	im.save(OUT / f"{name}.png")


if __name__ == "__main__":
	names = sys.argv[2:] or list(SCREENS)
	if sys.argv[1] == "generate":
		with ThreadPoolExecutor(5) as ex:
			list(ex.map(generate, names))
	for n in names:
		process(n)
		print("done", n, flush=True)
