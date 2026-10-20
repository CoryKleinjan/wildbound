"""Asks a Gemini model to review each generated track (vocals? fits the brief?)."""
import base64, concurrent.futures as cf, json, sys
from common import API, _post
from music import TRACKS, OUT, BASE

def check(t):
	b = base64.b64encode((OUT / f"{t}.ogg").read_bytes()).decode()
	q = ("You are reviewing music for a retro handheld creature RPG. The brief was: " + TRACKS[t][1] +
		" Answer JSON {\"vocals\": true/false (any singing, rapping, spoken words or vocal chops/stabs), "
		"\"fits\": 1-10, \"notes\": short string}.")
	body = {"contents": [{"role": "user", "parts": [{"inline_data": {"mime_type": "audio/ogg", "data": b}}, {"text": q}]}],
		"generationConfig": {"responseMimeType": "application/json"}}
	r = _post(f"{API}/models/gemini-3.5-flash:generateContent", body)
	return t, json.loads(r["candidates"][0]["content"]["parts"][-1]["text"])

if __name__ == "__main__":
	names = sys.argv[1:] or list(TRACKS)
	with cf.ThreadPoolExecutor(4) as ex:
		for t, res in ex.map(check, names):
			print(t, json.dumps(res), flush=True)
