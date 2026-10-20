"""Shared helpers for the Gemini art/music generators (run from the repo root)."""
import base64
import json
import os
import time
from pathlib import Path

import requests

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / "tools" / "artgen" / "raw"  # full-size model output (gitignored)
API = "https://generativelanguage.googleapis.com/v1beta"
IMAGE_MODEL = "gemini-2.5-flash-image"

STYLE = (
	"Game Boy Advance era pixel art, in the style of a Generation 3 handheld monster-collecting RPG battle sprite. "
	"Clean dark outlines, flat cel shading with 2-3 tones per color, limited palette, crisp readable silhouette. "
	"Original design, not any existing franchise character."
)


def key() -> str:
	return os.environ["GEMINI_API_KEY"]


def species() -> dict:
	return json.loads((ROOT / "data" / "species.json").read_text())


def misc() -> dict:
	return json.loads((ROOT / "data" / "misc.json").read_text())


def _post(url: str, body: dict, tries: int = 6) -> dict:
	for i in range(tries):
		r = requests.post(url, params={"key": key()}, json=body, timeout=300)
		if r.status_code == 200:
			return r.json()
		if r.status_code in (429, 500, 502, 503, 504) and i < tries - 1:
			time.sleep(2 ** (i + 1))
			continue
		raise RuntimeError(f"{r.status_code}: {r.text[:500]}")
	raise RuntimeError("unreachable")


def image_request(prompt: str, ref_images: list[Path] | None = None, aspect: str = "1:1") -> dict:
	parts: list[dict] = []
	for p in ref_images or []:
		parts.append({"inline_data": {"mime_type": "image/png", "data": base64.b64encode(p.read_bytes()).decode()}})
	parts.append({"text": prompt})
	return {
		"contents": [{"role": "user", "parts": parts}],
		"generationConfig": {"responseModalities": ["IMAGE"], "imageConfig": {"aspectRatio": aspect}},
	}


def extract_image(resp: dict) -> bytes | None:
	for c in resp.get("candidates", []):
		for part in c.get("content", {}).get("parts", []):
			d = part.get("inlineData") or part.get("inline_data")
			if d:
				return base64.b64decode(d["data"])
	return None


def generate_image(prompt: str, out: Path, ref_images: list[Path] | None = None, aspect: str = "1:1", model: str = IMAGE_MODEL) -> Path:
	"""Synchronous call (used for samples and retries). Skips work if out already exists."""
	if out.exists():
		return out
	for attempt in range(3):
		resp = _post(f"{API}/models/{model}:generateContent", image_request(prompt, ref_images, aspect))
		data = extract_image(resp)
		if data:
			out.parent.mkdir(parents=True, exist_ok=True)
			out.write_bytes(data)
			return out
	raise RuntimeError(f"no image for {out.name}: {json.dumps(resp)[:400]}")


def ask_vision(image: Path, question: str, model: str = "gemini-3.5-flash") -> str:
	"""Short text answer about an image (used to check generated sheets)."""
	body = {
		"contents": [{"role": "user", "parts": [
			{"inline_data": {"mime_type": "image/png", "data": base64.b64encode(image.read_bytes()).decode()}},
			{"text": question}]}],
		"generationConfig": {"responseMimeType": "application/json"},
	}
	resp = _post(f"{API}/models/{model}:generateContent", body)
	return resp["candidates"][0]["content"]["parts"][-1]["text"]
