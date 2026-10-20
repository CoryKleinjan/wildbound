"""Turns a large model-drawn image into small game pixel art: key out the flat background,
crop, downscale, quantize to a small palette and clean up the alpha edge."""
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image


def key_background(rgb: np.ndarray, tol: float = 90.0, fringe: bool = True) -> np.ndarray:
	"""Alpha mask (bool, True = keep). Background = pixels close to the border's dominant color,
	flood-filled from the edges so same-colored pixels inside the subject survive."""
	h, w, _ = rgb.shape
	border = np.concatenate([rgb[0], rgb[-1], rgb[:, 0], rgb[:, -1]]).astype(np.int32)
	vals, counts = np.unique(border // 16, axis=0, return_counts=True)
	bg = border[(border // 16 == vals[counts.argmax()]).all(axis=1)].mean(axis=0)
	near = np.sqrt(((rgb.astype(np.float32) - bg) ** 2).sum(axis=2)) < tol
	# magenta-ish fringe (antialiased edge between subject and #FF00FF)
	r, g, b = rgb[..., 0].astype(int), rgb[..., 1].astype(int), rgb[..., 2].astype(int)
	if fringe and bg[0] > 200 and bg[2] > 200 and bg[1] < 80:
		near |= (r - g > 90) & (b - g > 90)
	seen = np.zeros((h, w), bool)
	q = deque()
	for x in range(w):
		for y in (0, h - 1):
			if near[y, x] and not seen[y, x]:
				seen[y, x] = True
				q.append((y, x))
	for y in range(h):
		for x in (0, w - 1):
			if near[y, x] and not seen[y, x]:
				seen[y, x] = True
				q.append((y, x))
	while q:
		y, x = q.popleft()
		for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
			ny, nx = y + dy, x + dx
			if 0 <= ny < h and 0 <= nx < w and near[ny, nx] and not seen[ny, nx]:
				seen[ny, nx] = True
				q.append((ny, nx))
	return ~seen


def _largest_blobs(mask: np.ndarray, min_frac: float = 0.02) -> np.ndarray:
	"""Drops specks: keeps connected components at least min_frac of the biggest one."""
	from scipy import ndimage  # noqa: optional dependency check below
	lab, n = ndimage.label(mask)
	if n <= 1:
		return mask
	sizes = ndimage.sum(mask, lab, range(1, n + 1))
	keep = [i + 1 for i, s in enumerate(sizes) if s >= sizes.max() * min_frac]
	return np.isin(lab, keep)


def quantize(img: Image.Image, colors: int) -> Image.Image:
	"""Palette-reduce opaque pixels; alpha becomes 0/255."""
	a = np.array(img)[..., 3]
	rgb = img.convert("RGB")
	q = rgb.quantize(colors=colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
	out = np.dstack([np.array(q), np.where(a >= 128, 255, 0).astype(np.uint8)])
	return Image.fromarray(out, "RGBA")


def outline(img: Image.Image) -> Image.Image:
	"""Darkens opaque pixels that touch transparency so the silhouette reads at small size."""
	arr = np.array(img).astype(np.int32)
	op = arr[..., 3] > 0
	pad = np.pad(op, 1)
	edge = op & ~(pad[:-2, 1:-1] & pad[2:, 1:-1] & pad[1:-1, :-2] & pad[1:-1, 2:])
	dark = arr[..., :3] * 0.35
	arr[..., :3] = np.where(edge[..., None], np.minimum(arr[..., :3], dark + 16), arr[..., :3])
	return Image.fromarray(arr.astype(np.uint8), "RGBA")


def to_sprite(src: Path, size: int, fit: int, colors: int = 16, bottom: bool = True, do_outline: bool = True, key_tol: float = 55.0) -> Image.Image:
	"""size x size RGBA sprite, subject scaled to fit `fit` px, centered horizontally and
	(if bottom) standing on the bottom edge like the GBA battle sprites."""
	im = Image.open(src).convert("RGB")
	rgb = np.array(im)
	mask = key_background(rgb, tol=key_tol, fringe=key_tol >= 90)
	try:
		mask = _largest_blobs(mask)
	except ImportError:
		pass
	if key_tol < 90:
		mask = erode(mask, 3)  # tight key: shave the antialiased background fringe instead
	ys, xs = np.nonzero(mask)
	if len(xs) == 0:
		raise ValueError(f"empty subject in {src}")
	rgba = np.dstack([rgb, np.where(mask, 255, 0).astype(np.uint8)])
	crop = Image.fromarray(rgba[ys.min():ys.max() + 1, xs.min():xs.max() + 1], "RGBA")
	w, h = crop.size
	k = fit / max(w, h)
	nw, nh = max(1, round(w * k)), max(1, round(h * k))
	# premultiplied box downscale so the keyed background does not bleed into edge colors
	small = _premul_resize(crop, (nw, nh))
	small = quantize(small, colors)
	if do_outline:
		small = outline(small)
	canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
	ox = (size - nw) // 2
	oy = size - nh - 1 if bottom else (size - nh) // 2
	canvas.paste(small, (ox, max(0, oy)), small)
	return canvas


def _premul_resize(img: Image.Image, size: tuple[int, int]) -> Image.Image:
	arr = np.array(img).astype(np.float32) / 255.0
	a = arr[..., 3:4]
	pm = np.concatenate([arr[..., :3] * a, a], axis=2)
	pm_img = Image.fromarray((pm * 255).astype(np.uint8), "RGBA")
	small = np.array(pm_img.resize(size, Image.Resampling.BOX)).astype(np.float32) / 255.0
	sa = small[..., 3:4]
	rgb = np.where(sa > 0, small[..., :3] / np.maximum(sa, 1e-6), 0)
	return Image.fromarray((np.dstack([np.clip(rgb, 0, 1), sa]) * 255).astype(np.uint8), "RGBA")


def to_image(src: Path, size: tuple[int, int], colors: int = 32) -> Image.Image:
	"""Opaque image (backgrounds, title art): downscale + palette reduce."""
	im = Image.open(src).convert("RGB")
	w, h = im.size
	tw, th = size
	k = max(tw / w, th / h)
	im = im.resize((round(w * k), round(h * k)), Image.Resampling.BOX)
	l, t = (im.width - tw) // 2, (im.height - th) // 2
	im = im.crop((l, t, l + tw, t + th))
	return im.quantize(colors=colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")


def erode(mask: np.ndarray, px: int) -> np.ndarray:
	"""Shrinks the keep-mask by px pixels (drops the antialiased background fringe)."""
	try:
		from scipy import ndimage
	except ImportError:
		return mask
	return ndimage.binary_erosion(mask, iterations=px) if px > 0 else mask


def mode_resize(img: Image.Image, size: tuple[int, int], colors: int) -> Image.Image:
	"""Crisp downscale: quantize at full size, then each output pixel takes the most common
	palette color of its source block (transparent if under half the block is opaque)."""
	arr = np.array(img)
	a = arr[..., 3] >= 128
	q = Image.fromarray(arr[..., :3]).quantize(colors=colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
	pal = np.array(q.getpalette()[:colors * 3]).reshape(-1, 3)
	idx = np.array(q)
	h, w = idx.shape
	tw, th = size
	out = np.zeros((th, tw, 4), np.uint8)
	for ty in range(th):
		for tx in range(tw):
			y0, y1 = ty * h // th, max(ty * h // th + 1, (ty + 1) * h // th)
			x0, x1 = tx * w // tw, max(tx * w // tw + 1, (tx + 1) * w // tw)
			blk_a = a[y0:y1, x0:x1]
			if blk_a.mean() < 0.5:
				continue
			vals = idx[y0:y1, x0:x1][blk_a]
			c = np.bincount(vals, minlength=colors).argmax()
			out[ty, tx, :3] = pal[c]
			out[ty, tx, 3] = 255
	return Image.fromarray(out, "RGBA")


def grid_cells(src: Path, cols: int, rows: int, inset: float = 0.03) -> list[Image.Image]:
	"""Splits a tile sheet into cols x rows cells, trimming a small inset to drop gutter lines."""
	im = Image.open(src).convert("RGBA")
	w, h = im.size
	cells = []
	for r in range(rows):
		for c in range(cols):
			x0, x1 = c * w / cols, (c + 1) * w / cols
			y0, y1 = r * h / rows, (r + 1) * h / rows
			dx, dy = (x1 - x0) * inset, (y1 - y0) * inset
			cells.append(im.crop((round(x0 + dx), round(y0 + dy), round(x1 - dx), round(y1 - dy))))
	return cells


def trim_light_border(im: Image.Image, thresh: int = 225) -> Image.Image:
	"""Crops away near-white or light gutter lines along the edges of a sheet cell."""
	a = np.array(im.convert("RGB")).astype(int)
	light = (a.min(axis=2) > thresh)
	t, b, l, r = 0, a.shape[0], 0, a.shape[1]
	while t < b - 1 and light[t, l:r].mean() > 0.3:
		t += 1
	while b > t + 1 and light[b - 1, l:r].mean() > 0.3:
		b -= 1
	while l < r - 1 and light[t:b, l].mean() > 0.3:
		l += 1
	while r > l + 1 and light[t:b, r - 1].mean() > 0.3:
		r -= 1
	return im.crop((l, t, r, b))
