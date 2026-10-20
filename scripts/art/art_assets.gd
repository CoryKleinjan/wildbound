class_name ArtAssets
## Generated art in res://assets (PNG). Every lookup returns null when the file is missing,
## so callers fall back to the procedural art.

static var _cache: Dictionary = {}

## Image for res://assets/<rel>.png (decompressed, RGBA8), or null.
static func image(rel: String) -> Image:
	if _cache.has(rel):
		return _cache[rel]
	var path := "res://assets/%s.png" % rel
	var img: Image = null
	if ResourceLoader.exists(path):
		var tex: Texture2D = load(path)
		if tex != null:
			img = tex.get_image()
			if img.is_compressed():
				img.decompress()
			img.convert(Image.FORMAT_RGBA8)
	_cache[rel] = img
	return img

## Texture for res://assets/<rel>.png, or null.
static func texture(rel: String) -> Texture2D:
	var key := "tex|" + rel
	if _cache.has(key):
		return _cache[key]
	var path := "res://assets/%s.png" % rel
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_cache[key] = tex
	return tex

## Shiny recolor for generated sprites: rotates the hue of colored pixels (outlines and greys stay).
static func hue_rotate(src: Image, deg: float) -> Image:
	var img := src.duplicate() as Image
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a == 0 or c.s < 0.15 or c.v < 0.2:
				continue
			img.set_pixel(x, y, Color.from_hsv(fposmod(c.h + deg / 360.0, 1.0), c.s, c.v, c.a))
	return img
