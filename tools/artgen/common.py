"""Shared helpers for the Gemini art/music generators (run from the repo root)."""
import base64
import json
import os
import threading
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
	"""All species, including those added by data/features.json (the Emerald legendaries)."""
	out = json.loads((ROOT / "data" / "species.json").read_text())
	out.update(json.loads((ROOT / "data" / "features.json").read_text()).get("species", {}))
	return out


def misc() -> dict:
	return json.loads((ROOT / "data" / "misc.json").read_text())


# ---------- spending guard ----------
# The key is prepaid and its balance can't be read through the API, so every call is costed here (estimated from the
# response's usage numbers, rounded up) and calls stop before the limit in raw/budget.json: {"limit": dollars}.
# The running total is in raw/spend.json. Set the limit to the account balance minus a safety margin.
SPEND = RAW / "spend.json"
BUDGET = RAW / "budget.json"
# Dollars per million tokens (input, output) and per output image; deliberately on the high side.
PRICES = {
	"gemini-3-pro-image": (2.0, 12.0, 0.14), "nano-banana-pro-preview": (2.0, 12.0, 0.14),
	"gemini-2.5-flash-image": (0.3, 2.5, 0.04), "gemini-3.1-pro-preview": (2.5, 15.0, 0.0),
	"gemini-3.5-flash": (0.5, 3.0, 0.0), "lyria": (0.0, 0.0, 0.08),
}
# Ledger estimates are multiplied by this, to stay under the real bill.
SAFETY = 1.5
# The most one call may cost, reserved before it is sent so parallel calls can't overshoot together.
RESERVE = 0.2
_lock = threading.Lock()
_pending = 0.0


class BudgetExceeded(RuntimeError):
	pass


def spent() -> float:
	return json.loads(SPEND.read_text()).get("total", 0.0) if SPEND.exists() else 0.0


def limit() -> float:
	return float(json.loads(BUDGET.read_text())["limit"]) if BUDGET.exists() else 0.0


def _cost(model: str, resp: dict) -> float:
	pin, pout, pimg = PRICES.get(model, PRICES["lyria"] if "lyria" in model else (2.5, 15.0, 0.14))
	u = resp.get("usageMetadata", {})
	images = sum(1 for c in resp.get("candidates", []) for p in c.get("content", {}).get("parts", []) if "inlineData" in p or "inline_data" in p)
	# thoughtsTokenCount is billed as output but not part of candidatesTokenCount; leaving it out made the ledger read
	# under half of the real spend (2026-10-20: the key ran dry with the ledger at $13.9 of $30).
	out = u.get("candidatesTokenCount", 0) + u.get("thoughtsTokenCount", 0)
	return (u.get("promptTokenCount", 0) * pin / 1e6 + out * pout / 1e6 + images * pimg) * SAFETY


def _reserve() -> None:
	global _pending
	with _lock:
		if spent() + _pending + RESERVE > limit():
			raise BudgetExceeded(f"stopping: ${spent():.2f} spent of the ${limit():.2f} limit in {BUDGET}")
		_pending += RESERVE


def _record(model: str, resp: dict | None) -> None:
	global _pending
	with _lock:
		_pending -= RESERVE
		if resp is None:
			return
		data = json.loads(SPEND.read_text()) if SPEND.exists() else {"total": 0.0, "by_model": {}}
		c = _cost(model, resp)
		data["total"] = data.get("total", 0.0) + c
		data["by_model"][model] = data["by_model"].get(model, 0.0) + c
		SPEND.parent.mkdir(parents=True, exist_ok=True)
		SPEND.write_text(json.dumps(data, indent=1))


def _post(url: str, body: dict, tries: int = 6) -> dict:
	model = url.split("/models/")[-1].split(":")[0] if "/models/" in url else ""
	if model:
		_reserve()
		try:
			resp = _post_raw(url, body, tries)
		except Exception:
			_record(model, None)
			raise
		_record(model, resp)
		return resp
	return _post_raw(url, body, tries)


def _post_raw(url: str, body: dict, tries: int) -> dict:
	for i in range(tries):
		r = requests.post(url, params={"key": key()}, json=body, timeout=300)
		if r.status_code == 200:
			return r.json()
		if r.status_code == 402:
			raise BudgetExceeded("HTTP 402 (prepaid credits, or a billing hiccup): " + r.text[:300])
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
