"""Soundtrack with Lyria via the Gemini API -> assets/music/<track>.ogg

python3 tools/artgen/music.py [track ...]   # all tracks when none given; existing raw files are reused
"""
import base64
import concurrent.futures as cf
import subprocess
import sys

from common import API, RAW, ROOT, _post

OUT = ROOT / "assets" / "music"
SONG = "lyria-3-pro-preview"   # full-length songs (~2-3 min)
CLIP = "lyria-3-clip-preview"  # 30 s clips for jingles

BASE = (
	"Instrumental video game music for a Game Boy Advance era monster-collecting adventure RPG. "
	"GBA sound chip style: square and pulse wave leads, triangle/pulse bass, noise-channel drums, a touch of synth brass and strings. "
	"Strictly instrumental: no vocals, no voice samples, no vocal chops, no spoken words. "
)

# track: (model, prompt, max seconds for non-looping tracks, loops). Names match Audio.play_music().
TRACKS = {
	"title": (SONG, "Title screen theme. Bright, heroic and adventurous with a memorable, catchy main melody that feels like the start of a journey. About 120 BPM.", None, True),
	"town": (SONG, "Peaceful hometown theme. Warm, gentle, cozy and nostalgic, a relaxed walking melody with soft chords. About 95 BPM.", None, True),
	"route": (SONG, "Overworld route theme for walking through grassy fields between towns. Upbeat, optimistic, bouncy, sense of exploration. About 130 BPM.", None, True),
	"battle_wild": (SONG, "Wild creature battle theme. Fast, energetic and tense with a driving bassline and urgent lead melody. About 160 BPM.", None, True),
	"battle_trainer": (SONG, "Trainer battle theme. Fast, competitive and confident, a punchy rival-of-the-road feel with a catchy fighting melody. About 165 BPM.", None, True),
	"battle_gym": (SONG, "Gym leader battle theme. Dramatic, powerful and intense, a boss fight against a master with heroic brass stabs. About 170 BPM.", None, True),
	"battle_rival": (SONG, "Rival battle theme. Cocky, energetic, a bit mischievous and very determined, a personal showdown with a friend. About 165 BPM.", None, True),
	"battle_villain": (SONG, "Villain team battle theme. Dark, menacing, ominous minor key with aggressive bass and sinister lead. About 160 BPM.", None, True),
	"battle_champion": (SONG, "Champion final battle theme. Epic, grand, climactic and emotional, the ultimate fight at the top of the league. About 175 BPM.", None, True),
	"gym": (SONG, "Inside a gym building theme. Determined, steady, a bit tense and focused, building toward a challenge. About 120 BPM.", None, True),
	"league": (SONG, "Champion league hall theme. Majestic, solemn and grand, a sense of final destination. About 100 BPM.", None, True),
	"ending": (SONG, "Ending credits theme. Emotional, triumphant and bittersweet, reflecting on a long journey with friends, building to a heartfelt finale.", 120, False),
	"victory_wild": (CLIP, "Victory fanfare after defeating a wild creature: a short triumphant fanfare, then a cheerful relaxed victory loop. About 130 BPM.", 30, True),
	"victory_trainer": (CLIP, "Victory fanfare after defeating a trainer: a proud triumphant fanfare, then an upbeat celebratory victory loop. About 140 BPM.", 30, True),
	"evolution": (CLIP, "Evolution scene: mysterious, shimmering, building wonder and anticipation, rising arpeggios, then a joyful resolution.", 30, True),
}


def raw_path(track: str):
	return RAW / "music" / f"{track}.mp3"


def generate(track: str) -> None:
	model, prompt, _, _ = TRACKS[track]
	dst = raw_path(track)
	if dst.exists():
		return
	body = {"contents": [{"role": "user", "parts": [{"text": BASE + prompt}]}], "generationConfig": {"responseModalities": ["AUDIO"]}}
	resp = _post(f"{API}/models/{model}:generateContent", body)
	for part in resp["candidates"][0]["content"]["parts"]:
		d = part.get("inlineData")
		if d:
			dst.parent.mkdir(parents=True, exist_ok=True)
			dst.write_bytes(base64.b64decode(d["data"]))
			print("generated", track, flush=True)
			return
	raise RuntimeError(f"no audio for {track}")


def encode(track: str) -> None:
	"""mp3 -> ogg vorbis: trims leading/trailing silence; caps length (with a fade) only on non-looping tracks.
	Every track loops in code (Audio autoload), so looping tracks keep a clean, unfaded end."""
	_, _, max_s, loops = TRACKS[track]
	OUT.mkdir(parents=True, exist_ok=True)
	filters = [
		"silenceremove=start_periods=1:start_threshold=-50dB",
		"areverse", "silenceremove=start_periods=1:start_threshold=-50dB", "areverse",
	]
	if max_s and not loops:
		filters += [f"atrim=0:{max_s}", f"afade=t=out:st={max(0, max_s - 1.5)}:d=1.5"]
	subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(raw_path(track)), "-af", ",".join(filters),
		"-c:a", "libvorbis", "-q:a", "4", "-ar", "44100", str(OUT / f"{track}.ogg")], check=True)


if __name__ == "__main__":
	names = sys.argv[1:] or list(TRACKS)
	with cf.ThreadPoolExecutor(4) as ex:
		for f in [ex.submit(generate, n) for n in names]:
			f.result()
	for n in names:
		encode(n)
		print("encoded", n)
