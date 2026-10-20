"""Gemini Batch API (half price) for the image jobs.

python3 tools/artgen/batch.py submit <stage>   # stage: fronts | backs | trainers | scenery
python3 tools/artgen/batch.py wait <stage>     # polls, then writes every finished image to raw/
python3 tools/artgen/batch.py retry <stage>    # synchronous calls for anything still missing
Stages run in that order: backs use the front images as references.
"""
import base64
import io
import json
import sys
import time

import requests
from PIL import Image

import creatures
import scenery
import trainers
from common import API, IMAGE_MODEL, RAW, extract_image, generate_image, image_request, key, misc, species

STATE = RAW / "batches.json"


def _ref(path) -> list:
	"""Reference image, shrunk to keep the JSONL small."""
	im = Image.open(path).convert("RGB")
	im.thumbnail((512, 512))
	buf = io.BytesIO()
	im.save(buf, "PNG")
	return [buf.getvalue()]


def jobs(stage: str) -> list[tuple[str, object, str, list, str]]:
	"""(key, out path, prompt, reference image bytes, aspect)"""
	out = []
	if stage == "fronts":
		for sid, s in species().items():
			out.append((sid, creatures.raw_path(sid, False), creatures.front_prompt(s), [], "1:1"))
	elif stage == "backs":
		for sid, s in species().items():
			front = creatures.raw_path(sid, False)
			if front.exists():
				out.append((sid + "_back", creatures.raw_path(sid, True), creatures.back_prompt(s), _ref(front), "1:1"))
	elif stage == "trainers":
		for n, pal in misc()["palettes"].items():
			out.append((n + "_sheet", trainers.sheet_raw(n), trainers.sheet_prompt(n, pal), [], "16:9"))
			out.append((n + "_portrait", RAW / "trainers" / f"{n}_portrait.png", trainers.portrait_prompt(n, pal), [], "1:1"))
	elif stage == "scenery":
		for kind, n, p, a in scenery.jobs():
			out.append((f"{kind}/{n}", scenery.raw(kind, n), p, [], a))
	return [j for j in out if not j[1].exists()]


def _request(prompt: str, refs: list, aspect: str) -> dict:
	body = image_request(prompt, None, aspect)
	for data in refs:
		body["contents"][0]["parts"].insert(0, {"inline_data": {"mime_type": "image/png", "data": base64.b64encode(data).decode()}})
	return body


def _state() -> dict:
	return json.loads(STATE.read_text()) if STATE.exists() else {}


def submit(stage: str) -> None:
	js = jobs(stage)
	if not js:
		print("nothing to do")
		return
	lines = "\n".join(json.dumps({"key": k, "request": _request(p, refs, a)}) for k, _, p, refs, a in js).encode()
	# resumable upload of the JSONL input
	start = requests.post(f"https://generativelanguage.googleapis.com/upload/v1beta/files", params={"key": key()},
		headers={"X-Goog-Upload-Protocol": "resumable", "X-Goog-Upload-Command": "start",
			"X-Goog-Upload-Header-Content-Length": str(len(lines)), "X-Goog-Upload-Header-Content-Type": "application/jsonl",
			"Content-Type": "application/json"},
		json={"file": {"display_name": f"wildbound-{stage}"}}, timeout=120)
	start.raise_for_status()
	up = requests.post(start.headers["X-Goog-Upload-URL"], headers={"X-Goog-Upload-Command": "upload, finalize",
		"X-Goog-Upload-Offset": "0", "Content-Length": str(len(lines))}, data=lines, timeout=600)
	up.raise_for_status()
	file_name = up.json()["file"]["name"]
	r = requests.post(f"{API}/models/{IMAGE_MODEL}:batchGenerateContent", params={"key": key()},
		json={"batch": {"display_name": f"wildbound-{stage}", "input_config": {"file_name": file_name}}}, timeout=120)
	r.raise_for_status()
	name = r.json()["name"]
	st = _state()
	st[stage] = name
	STATE.write_text(json.dumps(st, indent=1))
	print("submitted", stage, name, len(js), "requests")


def wait(stage: str) -> None:
	name = _state()[stage]
	while True:
		r = requests.get(f"{API}/{name}", params={"key": key()}, timeout=60).json()
		meta = r.get("metadata", {})
		state = meta.get("state")
		print(time.strftime("%H:%M:%S"), state, meta.get("batchStats"), flush=True)
		if r.get("done") or state in ("BATCH_STATE_SUCCEEDED", "BATCH_STATE_FAILED", "BATCH_STATE_CANCELLED", "BATCH_STATE_EXPIRED"):
			break
		time.sleep(60)
	resp = r.get("response", {})
	file_name = resp.get("responsesFile") or meta.get("output", {}).get("responsesFile")
	if not file_name:
		print("no results file:", json.dumps(r)[:1000])
		return
	data = requests.get(f"https://generativelanguage.googleapis.com/download/v1beta/{file_name}:download",
		params={"key": key(), "alt": "media"}, timeout=600).content
	paths = {k: p for k, p, *_ in jobs(stage)}
	ok = bad = 0
	for line in data.decode().splitlines():
		if not line.strip():
			continue
		row = json.loads(line)
		img = extract_image(row.get("response", {}))
		p = paths.get(row.get("key"))
		if img and p:
			p.parent.mkdir(parents=True, exist_ok=True)
			p.write_bytes(img)
			ok += 1
		else:
			bad += 1
	print("wrote", ok, "images;", bad, "failed or skipped")


def retry(stage: str) -> None:
	for k, p, prompt, refs, aspect in jobs(stage):
		tmp = []
		for i, data in enumerate(refs):
			t = RAW / f"_ref{i}.png"
			t.write_bytes(data)
			tmp.append(t)
		try:
			generate_image(prompt, p, tmp, aspect)
			print("retried", k, flush=True)
		except Exception as e:  # keep going; the procedural art covers anything missing
			print("FAILED", k, e, flush=True)


if __name__ == "__main__":
	{"submit": submit, "wait": wait, "retry": retry}[sys.argv[1]](sys.argv[2])
