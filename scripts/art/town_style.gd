class_name TownStyle
## Gives each town its own look by recoloring finished tile textures (procedural or generated PNG)
## with that town's style from data/town_styles.json. Styles are attached to maps by DB as map.style.
##
## Style keys (all optional):
##   grass / tree: {h, s, v} applied to the green pixels of ground tiles / trees (wood, flowers and signs keep their colors)
##   path / roof / water: {h, s, v} applied to every pixel of those tiles
##   wall: "#hex" multiplied into the light, unsaturated pixels of building walls and doors
##   iwall: {h, s, v} for indoor walls
##   treeShape: "pine" | "palm" | "rock" | "willow" | "blossom" to swap the town's trees for a signature shape
## {h, s, v}: h shifts hue in degrees, s and v multiply saturation and value.

static var _cache: Dictionary = {}

const GROUND := ".,FvSL"
const ROOFS := "rpbkn"
const WALLS := "whlmju"

static func clear_cache() -> void:
	_cache.clear()

## The texture for tile `ch` recolored with `style` (the same texture when the style has nothing for it).
static func apply(tex: Texture2D, ch: String, style: Dictionary) -> Texture2D:
	if style.is_empty() or tex == null:
		return tex
	if ch == "#" and style.has("treeShape"):
		return _shaped_tree(style)
	var cat := _category(ch)
	if cat == "" or not style.has(cat):
		return tex
	var key := "%d|%s|%s" % [tex.get_instance_id(), cat, style.get("id", "")]
	if _cache.has(key):
		return _cache[key]
	var img := tex.get_image()
	if img == null:
		return tex
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var op: Variant = style[cat]
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			img.set_pixel(x, y, _recolor(c, cat, op))
	var out := ImageTexture.create_from_image(img)
	_cache[key] = out
	return out

static func _category(ch: String) -> String:
	if ch == "#":
		return "tree"
	if GROUND.contains(ch):
		return "grass"
	if ch == "=":
		return "path"
	if ch == "~":
		return "water"
	if ROOFS.contains(ch):
		return "roof"
	if WALLS.contains(ch):
		return "wall"
	if ch == "|":
		return "iwall"
	return ""

static func _recolor(c: Color, cat: String, op: Variant) -> Color:
	if cat == "wall":
		# Tint the cream wall paint only, not windows, doors or outlines.
		if c.s > 0.25 or c.v < 0.7:
			return c
		var t := Color(op)
		return Color(c.r * t.r / 0.94, c.g * t.g / 0.91, c.b * t.b / 0.82, c.a).clamp()
	if (cat == "grass" or cat == "tree") and not _is_green(c):
		return c
	var h: float = c.h + float(op.get("h", 0.0)) / 360.0
	var out := Color.from_hsv(fposmod(h, 1.0), clampf(c.s * float(op.get("s", 1.0)), 0.0, 1.0), clampf(c.v * float(op.get("v", 1.0)), 0.0, 1.0), c.a)
	return out

static func _is_green(c: Color) -> bool:
	return c.s > 0.15 and c.h > 0.17 and c.h < 0.5

## The town's signature tree (recolored with its tree style) standing on the town's own grass.
static func _shaped_tree(style: Dictionary) -> Texture2D:
	var key := "tree|" + str(style.get("id", ""))
	if _cache.has(key):
		return _cache[key]
	var img := apply(Tiles.tile_texture(".", 0, 0, 0), ".", style).get_image().duplicate()
	img.convert(Image.FORMAT_RGBA8)
	var shape := tree_texture(style.treeShape).get_image()
	var op: Variant = style.get("tree", {})
	for y in 16:
		for x in 16:
			var c := shape.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			if op is Dictionary and not op.is_empty():
				c = _recolor(c, "tree", op)
			img.set_pixel(x, y, img.get_pixel(x, y).blend(c))
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex

## Signature tree shapes (16x16 on a transparent background), drawn once per shape.
static func tree_texture(shape: String) -> Texture2D:
	var key := "shape|" + shape
	if _cache.has(key):
		return _cache[key]
	var painter := Tiles._Painter.new()
	var p := painter.p
	match shape:
		"pine":
			p.call(7, 12, 2, 4, "#604028")
			for i in 4:
				var w := 4 + i * 3
				p.call(8 - w / 2, 1 + i * 3, w, 3, "#1f5a30")
				p.call(8 - w / 2 + 1, 1 + i * 3, maxi(1, w / 2 - 1), 1, "#3c8048")
			p.call(7, 0, 2, 2, "#1f5a30")
		"palm":
			p.call(8, 6, 2, 10, "#a07040")
			p.call(7, 9, 2, 7, "#a07040")
			p.call(9, 8, 1, 1, "#805028")
			p.call(8, 12, 1, 1, "#805028")
			p.call(2, 3, 6, 2, "#3c9040")
			p.call(10, 3, 6, 2, "#3c9040")
			p.call(1, 5, 3, 2, "#3c9040")
			p.call(13, 5, 3, 2, "#3c9040")
			p.call(5, 1, 7, 3, "#58b050")
			p.call(7, 5, 3, 2, "#7a5030")
		"rock":
			p.call(1, 5, 14, 10, "#585060")
			p.call(2, 3, 12, 11, "#888090")
			p.call(3, 4, 6, 4, "#a8a0b0")
			p.call(4, 4, 3, 1, "#c8c0d0")
			p.call(9, 9, 4, 1, "#686070")
			p.call(5, 11, 3, 1, "#686070")
			p.call(1, 14, 14, 2, Color(0, 0, 0, 0.2))
		"willow":
			p.call(7, 9, 2, 7, "#604028")
			p.call(2, 1, 12, 7, "#3c8060")
			p.call(1, 4, 14, 4, "#3c8060")
			for xx in [1, 3, 5, 10, 12, 14]:
				p.call(xx, 7, 1, 6, "#4c9070")
			p.call(4, 2, 4, 2, "#60a880")
		"blossom":
			p.call(7, 10, 2, 6, "#6a4030")
			p.call(5, 12, 2, 1, "#6a4030")
			p.call(2, 1, 12, 9, "#e890b8")
			p.call(1, 3, 14, 6, "#e890b8")
			p.call(3, 2, 4, 3, "#f8c8e0")
			p.call(9, 5, 3, 2, "#f8c8e0")
			p.call(5, 7, 2, 1, "#c86090")
			p.call(11, 2, 1, 1, "#c86090")
	var tex := ImageTexture.create_from_image(painter.img)
	_cache[key] = tex
	return tex
