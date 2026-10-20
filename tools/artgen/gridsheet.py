"""Pixel-grid templates: the model draws on a canvas of boxes where every grid square is one sprite pixel, so the result
reads back as real low-resolution pixel art (see walkers.py and icons.py, which do the same with fixed sizes).

A Sheet is cols x rows boxes of w x h sprite pixels. template() writes the canvas, read() returns each box as RGBA.
"""
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image

from common import RAW, generate_image

MODEL = "gemini-3-pro-image"
ASPECTS = {"1:1": 1, "4:3": 4 / 3, "3:4": 3 / 4, "3:2": 1.5, "2:3": 2 / 3, "16:9": 16 / 9, "9:16": 9 / 16, "5:4": 1.25, "4:5": 0.8, "21:9": 21 / 9}


@dataclass
class Sheet:
	cols: int
	rows: int
	w: int
	h: int
	gap: int = 4
	scale: int = 10

	@property
	def size(self) -> tuple[int, int]:
		return self.cols * self.w + (self.cols + 1) * self.gap, self.rows * self.h + (self.rows + 1) * self.gap

	@property
	def aspect(self) -> str:
		r = self.size[0] / self.size[1]
		return min(ASPECTS, key=lambda k: abs(np.log(ASPECTS[k] / r)))

	def origin(self, i: int) -> tuple[int, int]:
		return self.gap + (i % self.cols) * (self.w + self.gap), self.gap + (i // self.cols) * (self.h + self.gap)

	def template(self) -> Path:
		p = RAW / "grid" / f"_t{self.cols}x{self.rows}_{self.w}x{self.h}.png"
		cw, ch = self.size
		S = self.scale
		im = np.zeros((ch * S, cw * S, 3), np.uint8)
		im[:] = (255, 0, 255)
		for i in range(self.cols * self.rows):
			x0, y0 = self.origin(i)
			box = im[y0 * S:(y0 + self.h) * S, x0 * S:(x0 + self.w) * S]
			box[:] = (240, 120, 240)
			box[::S, :] = (200, 60, 200)
			box[:, ::S] = (200, 60, 200)
		p.parent.mkdir(parents=True, exist_ok=True)
		Image.fromarray(im).save(p)
		return p

	def canvas_text(self) -> str:
		return (f"The first image is the exact canvas to draw on: a {self.cols} by {self.rows} grid of boxes, each exactly {self.w} pixels "
			f"wide and {self.h} pixels tall, where every small grid square is ONE sprite pixel. Fill each grid square with a single flat "
			"color, no anti-aliasing, 1-pixel dark outlines, 2-4 shades per color, authentic Game Boy Advance (Pokemon Emerald) pixel art. "
			"Keep the boxes in the same places; outside the drawings every square is plain magenta #FF00FF; remove the grid lines. ")

	def generate(self, prompt: str, out: Path, refs: list[Path] | None = None) -> Path:
		return generate_image(self.canvas_text() + prompt, out, [self.template()] + (refs or []), self.aspect, MODEL)

	def read(self, src: Path) -> list[Image.Image]:
		cw, ch = self.size
		S = self.scale
		rgb = np.array(Image.open(src).convert("RGB").resize((cw * S, ch * S), Image.Resampling.NEAREST)).astype(int)
		out = []
		m = max(1, S // 3)
		for i in range(self.cols * self.rows):
			x0, y0 = self.origin(i)
			box = np.zeros((self.h, self.w, 4), np.uint8)
			for y in range(self.h):
				for x in range(self.w):
					blk = rgb[(y0 + y) * S + m:(y0 + y + 1) * S - m, (x0 + x) * S + m:(x0 + x + 1) * S - m].reshape(-1, 3)
					r, g, b = c = np.median(blk, axis=0)
					if r > 110 and b > 110 and g < 0.7 * min(r, b):  # magenta, any shade
						continue
					box[y, x] = (*c.astype(np.uint8), 255)
			out.append(Image.fromarray(box, "RGBA"))
		return out


def opaque(img: Image.Image) -> float:
	return float((np.array(img)[..., 3] > 0).mean())
