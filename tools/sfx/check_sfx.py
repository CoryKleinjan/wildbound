"""Asks a Gemini model to rate each rendered sound effect (dev aid)."""
import base64, concurrent.futures as cf, json, sys
sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parents[1] / "artgen"))
from common import API, _post
from make_sfx import NAMES, OUT

def check(n):
	b = base64.b64encode((OUT / f"{n}.wav").read_bytes()).decode()
	q = (f"This is the '{n}' sound effect for a Game Boy Advance style creature RPG (polished retro style). "
		"Rate how well it fits that purpose and its production quality. Answer JSON {\"fit\": 1-10, \"quality\": 1-10, \"issue\": short string or empty}.")
	body = {"contents": [{"role": "user", "parts": [{"inline_data": {"mime_type": "audio/wav", "data": b}}, {"text": q}]}],
		"generationConfig": {"responseMimeType": "application/json"}}
	r = _post(f"{API}/models/gemini-3.5-flash:generateContent", body)
	return n, json.loads(r["candidates"][0]["content"]["parts"][-1]["text"])

with cf.ThreadPoolExecutor(6) as ex:
	for n, res in ex.map(check, sys.argv[1:] or NAMES):
		print(n, json.dumps(res), flush=True)
