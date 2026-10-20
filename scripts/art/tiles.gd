class_name Tiles
## Tile art (TS tiles.ts), generated once into small 16x16 images and drawn scaled.

static var _cache: Dictionary = {}

const GRASS := "#88d070"
const GRASS_D := "#70b858"
const GRASS_L := "#a0e088"

## Pixel painter handed to each tile's draw callable: p.call(x, y, w, h, color).
## Colors are "#hex" strings or Color (translucent Colors are blended source-over like Canvas2D).
class _Painter:
	var img: Image

	func _init() -> void:
		img = Image.create(16, 16, false, Image.FORMAT_RGBA8)

	func p(x: int, y: int, w: int, h: int, color: Variant) -> void:
		var c: Color = color if color is Color else Color(color)
		var x0 := maxi(x, 0)
		var y0 := maxi(y, 0)
		var x1 := mini(x + w, 16)
		var y1 := mini(y + h, 16)
		if c.a >= 1.0:
			if x1 > x0 and y1 > y0:
				img.fill_rect(Rect2i(x0, y0, x1 - x0, y1 - y0), c)
			return
		for yy in range(y0, y1):
			for xx in range(x0, x1):
				var d := img.get_pixel(xx, yy)
				var a := c.a + d.a * (1.0 - c.a)
				if a <= 0.0:
					continue
				img.set_pixel(xx, yy, Color(
					(c.r * c.a + d.r * d.a * (1.0 - c.a)) / a,
					(c.g * c.a + d.g * d.a * (1.0 - c.a)) / a,
					(c.b * c.a + d.b * d.a * (1.0 - c.a)) / a, a))

## Drops every cached tile texture.
static func clear_cache() -> void:
	_cache.clear()

static func _make(key: String, draw: Callable) -> Texture2D:
	if _cache.has(key):
		return _cache[key]
	var painter := _Painter.new()
	draw.call(painter.p)
	var tex := ImageTexture.create_from_image(painter.img)
	_cache[key] = tex
	return tex

## Generated tile (assets/tiles/<name>.png) as a cached texture, with optional procedural overlays
## drawn on top (draw gets the same painter as _make). null when the PNG is missing.
static func _gen(key: String, name: String, draw: Callable = Callable(), tint: String = "", shift: int = 0) -> Texture2D:
	key = "png|" + key
	if _cache.has(key):
		return _cache[key]
	var src := ArtAssets.image("tiles/" + name)
	if src == null:
		return null
	var painter := _Painter.new()
	painter.img = src.duplicate()
	if shift != 0:
		var copy := painter.img.duplicate() as Image
		for y in 16:
			for x in 16:
				painter.img.set_pixel(x, y, copy.get_pixel((x + shift) % 16, y))
	if tint != "":
		_tint_greys(painter.img, Color(tint))
	if draw.is_valid():
		draw.call(painter.p)
	var tex := ImageTexture.create_from_image(painter.img)
	_cache[key] = tex
	return tex

## Multiplies the light, unsaturated pixels (generated floors) by the room's theme color.
static func _tint_greys(img: Image, theme: Color) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.s < 0.12 and c.v > 0.55:
				img.set_pixel(x, y, Color(c.r * theme.r / 0.85, c.g * theme.g / 0.85, c.b * theme.b / 0.85, c.a).clamp())

static func _grass(p: Callable, v: int) -> void:
	p.call(0, 0, 16, 16, GRASS)
	var spots := [[2, 3], [10, 2], [6, 9], [13, 11], [3, 13], [9, 6]]
	for i in spots.size():
		if (i + v) % 3 == 0:
			continue
		var x: int = spots[i][0]
		var y: int = spots[i][1]
		p.call(x, y, 1, 2, GRASS_D)
		p.call(x + 1, y + 1, 1, 1, GRASS_D)
	p.call((v * 5) % 14, (v * 7) % 14, 1, 1, GRASS_L)

## 16x16 texture for map tile char ch at map position (x, y). above/below are the neighbouring tile chars
## ("" for none), theme the interior floor color.
static func tile_texture(ch: String, x: int, y: int, frame: int, above: String = "", below: String = "", theme: String = "#d8d0c0") -> Texture2D:
	var v := (x * 7 + y * 13) % 4
	var gen := _generated(ch, x, y, frame, above, below, theme, v)
	if gen != null:
		return gen
	match ch:
		".":
			return _make("g%d" % v, func(p: Callable): _grass(p, v))
		",":
			return _make("t%d" % v, func(p: Callable):
				p.call(0, 0, 16, 16, "#58a848")
				for b in [[0, 2], [8, 2], [4, 9], [12, 9]]:
					var bx: int = b[0]
					var by: int = b[1]
					p.call(bx, by + 4, 8, 3, "#3f8a38")
					p.call(bx + 1, by, 2, 5, "#78c860")
					p.call(bx + 4, by + 1, 2, 4, "#68b850")
					p.call(bx + 6, by + 2, 1, 3, "#78c860")
					p.call(bx + 1, by, 1, 1, "#a8e890"))
		"=":
			return _make("d%d" % v, func(p: Callable):
				p.call(0, 0, 16, 16, "#e0c890")
				p.call((v * 3) % 12 + 2, (v * 5) % 12 + 2, 2, 1, "#c8b078")
				p.call((v * 7) % 12 + 1, (v * 11) % 12 + 3, 1, 1, "#c8b078")
				p.call(((v + 2) * 5) % 13, ((v + 1) * 3) % 13, 1, 1, "#f0e0b0"))
		"F":
			return _make("f%d%d" % [v, frame % 2], func(p: Callable):
				_grass(p, v)
				var cols := ["#f05858", "#f8e048", "#f8f8f8", "#f078c0"]
				for fl in [[3, 3, v], [10, 5, v + 1], [5, 11, v + 2], [12, 12, v + 3]]:
					var fx: int = fl[0]
					var fy: int = fl[1]
					var c: String = cols[fl[2] % 4]
					var o := 1 if frame % 2 else 0
					p.call(fx - 1 + o, fy, 3, 1, c)
					p.call(fx + o, fy - 1, 1, 3, c)
					p.call(fx + o, fy, 1, 1, "#f8c020"))
		"~":
			return _make("w%d%d" % [frame % 2, 1 if above == "~" else 0], func(p: Callable):
				p.call(0, 0, 16, 16, "#5898e8")
				var o := 3 if frame % 2 else 0
				p.call((2 + o) % 16, 4, 5, 1, "#88c0f8")
				p.call((10 + o) % 16, 9, 4, 1, "#88c0f8")
				p.call((5 + o) % 16, 13, 4, 1, "#88c0f8")
				if above != "~":
					p.call(0, 0, 16, 2, "#b0d8f8")
					p.call(0, 2, 16, 1, "#78b0f0"))
		"#":
			return _make("tree%d" % ((x + y) % 2), func(p: Callable):
				p.call(0, 0, 16, 16, GRASS_D)
				p.call(1, 1, 14, 11, "#286830")
				p.call(2, 0, 12, 13, "#286830")
				p.call(3, 1, 10, 10, "#3c9040")
				p.call(2, 3, 12, 6, "#3c9040")
				p.call(4, 2, 4, 3, "#58b050")
				p.call(9, 5, 3, 2, "#58b050")
				p.call(6, 12, 4, 4, "#705030")
				p.call(7, 12, 1, 4, "#906840"))
		"v":
			return _make("ledge%d" % v, func(p: Callable):
				_grass(p, v)
				p.call(0, 11, 16, 2, "#509840")
				p.call(0, 13, 16, 3, "#c8a868")
				p.call(0, 15, 16, 1, "#a08048"))
		"S":
			return _make("sign", func(p: Callable):
				_grass(p, 1)
				p.call(7, 9, 2, 6, "#705030")
				p.call(2, 3, 12, 7, "#604020")
				p.call(3, 4, 10, 5, "#c89858")
				p.call(4, 5, 8, 1, "#906838")
				p.call(4, 7, 6, 1, "#906838"))
		"r", "p", "b", "k", "n":
			var col: Array
			match ch:
				"r": col = ["#d05040", "#a83830", "#e87060"]
				"p": col = ["#e86888", "#c04868", "#f898b0"]
				"b": col = ["#4878d0", "#3058a8", "#78a0e8"]
				"k": col = ["#787890", "#585068", "#e8c050"]
				_: col = ["#7858b8", "#583890", "#e8d070"]
			var top := above != ch
			var bottom := below != ch
			return _make("roof%s%d%d" % [ch, 1 if top else 0, 1 if bottom else 0], func(p: Callable):
				p.call(0, 0, 16, 16, col[0])
				for yy in range(3, 16, 4):
					p.call(0, yy, 16, 1, col[1])
				for yy in range(0, 16, 4):
					for xx in range(0 if (yy / 4) % 2 else 4, 16, 8):
						p.call(xx, yy, 1, 3, col[1])
				if top:
					p.call(0, 0, 16, 2, col[2])
					p.call(0, 2, 16, 1, col[1])
				if bottom:
					p.call(0, 14, 16, 2, "#504048"))
		"w":
			return _make("wall%d" % (x % 2), func(p: Callable):
				p.call(0, 0, 16, 16, "#f0e8d0")
				p.call(0, 15, 16, 1, "#a89878")
				p.call(0, 0, 16, 1, "#d8ccb0")
				if x % 2:
					p.call(3, 3, 10, 8, "#505868")
					p.call(4, 4, 8, 6, "#90c8f0")
					p.call(4, 4, 3, 2, "#d0f0ff")
					p.call(7, 4, 1, 6, "#505868")
					p.call(4, 6, 8, 1, "#505868"))
		"_":
			return _make("floor%s%d" % [theme, (x + y) % 2], func(p: Callable):
				p.call(0, 0, 16, 16, theme)
				if (x + y) % 2:
					p.call(0, 0, 16, 16, Color(0, 0, 0, 0.06))
				p.call(0, 15, 16, 1, Color(0, 0, 0, 0.12))
				p.call(15, 0, 1, 16, Color(0, 0, 0, 0.08)))
		"|":
			return _make("iwall%d" % (1 if below == "|" else 0), func(p: Callable):
				p.call(0, 0, 16, 16, "#504858")
				p.call(0, 0, 16, 3, "#686078")
				if below != "|":
					p.call(0, 10, 16, 6, "#a098a8")
					p.call(0, 10, 16, 1, "#c0b8c8"))
		"o":
			return _make("statue%s" % theme, func(p: Callable):
				p.call(0, 0, 16, 16, theme)
				p.call(3, 11, 10, 4, "#787080")
				p.call(5, 2, 6, 10, "#a8a0b0")
				p.call(6, 3, 2, 3, "#d8d0e0")
				p.call(4, 1, 8, 3, "#e0c060"))
		"e":
			return _make("mat%s" % theme, func(p: Callable):
				p.call(0, 0, 16, 16, theme)
				p.call(1, 3, 14, 10, "#c04848")
				p.call(2, 4, 12, 8, "#e06060")
				p.call(4, 7, 8, 2, "#f8d0d0"))
		"h", "l", "m", "j", "u":
			return _make("door%s" % ch, func(p: Callable):
				p.call(0, 0, 16, 16, "#f0e8d0")
				p.call(0, 15, 16, 1, "#a89878")
				p.call(3, 2, 10, 14, "#504038")
				var door := {"l": "#e86888", "m": "#4878d0", "j": "#e8c050", "u": "#9070d0"}
				p.call(4, 3, 8, 13, door.get(ch, "#a87048"))
				p.call(5, 4, 6, 4, "#c89060" if ch == "h" else "#c8e8f8")
				p.call(10, 10, 1, 2, "#f8e070")
				if ch != "h":
					var sign := {"l": "#e83850", "m": "#3858c8", "j": "#585068"}
					p.call(2, 0, 12, 2, "#f8f8f8")
					p.call(6, 0, 4, 2, sign.get(ch, "#583890")))
		"c":
			return _make("counter%s%d%d" % [theme, 1 if above == "c" else 0, 1 if below == "c" else 0], func(p: Callable):
				p.call(0, 0, 16, 16, theme)
				p.call(0, 0 if above == "c" else 2, 16, 16, "#805838")
				p.call(1, 0 if above == "c" else 3, 14, 8 if below != "c" else 13, "#c89060")
				p.call(1, 0 if above == "c" else 3, 14, 1, "#e0b080")
				if below != "c":
					p.call(0, 12, 16, 4, "#604028")
					p.call(0, 15, 16, 1, Color(0, 0, 0, 0.25)))
		"t":
			return _make("table%s" % theme, func(p: Callable):
				p.call(0, 0, 16, 16, theme)
				p.call(0, 2, 16, 10, "#906040")
				p.call(1, 3, 14, 8, "#b88058")
				p.call(2, 4, 5, 1, "#d0a070")
				p.call(1, 12, 2, 3, "#604028")
				p.call(13, 12, 2, 3, "#604028"))
		"K":
			return _make("shelf%s" % theme, func(p: Callable):
				p.call(0, 0, 16, 16, "#684830")
				p.call(1, 1, 14, 6, "#402818")
				p.call(1, 9, 14, 6, "#402818")
				var books := ["#d05040", "#4878d0", "#e8c050", "#58a848", "#a060c0", "#f0f0e8"]
				for i in 6:
					p.call(2 + i * 2, 2 + (i % 2), 2, 5 - (i % 2), books[i])
					p.call(2 + i * 2, 10 + ((i + 1) % 2), 2, 5 - ((i + 1) % 2), books[(i + 3) % 6])
				p.call(0, 15, 16, 1, Color(0, 0, 0, 0.3)))
		"B":
			var head := above != "B"
			return _make("bed%s%d" % [theme, 1 if head else 0], func(p: Callable):
				p.call(0, 0, 16, 16, theme)
				p.call(1, 0 if not head else 1, 14, 15 if head else 14, "#705038")
				p.call(2, 0 if not head else 2, 12, 13 if head else 12, "#5878c8")
				if head:
					p.call(3, 3, 10, 5, "#f8f8f0")
					p.call(3, 7, 10, 1, "#c8c8c0")
				else:
					p.call(2, 0, 12, 2, "#7090e0")
					p.call(1, 13, 14, 2, "#604028"))
		"P":
			return _make("plant%s" % theme, func(p: Callable):
				p.call(0, 0, 16, 16, theme)
				p.call(4, 10, 8, 5, "#b06030")
				p.call(5, 10, 6, 1, "#d08048")
				p.call(3, 3, 10, 7, "#3c9040")
				p.call(5, 1, 6, 4, "#3c9040")
				p.call(4, 4, 3, 2, "#58b050")
				p.call(9, 2, 2, 3, "#58b050"))
		"q":
			var shade := x % 2
			return _make("mshelf%s%d" % [theme, shade], func(p: Callable):
				p.call(0, 0, 16, 16, "#a8b0b8")
				p.call(0, 0, 16, 1, "#d8e0e8")
				p.call(1, 2, 14, 5, "#606870")
				p.call(1, 9, 14, 5, "#606870")
				var goods := ["#e05050", "#58a8e0", "#f0d050", "#70c070"]
				for i in 4:
					p.call(2 + i * 3, 3, 2, 4, goods[(i + shade) % 4])
					p.call(2 + i * 3, 10, 2, 4, goods[(i + shade + 2) % 4])
				p.call(0, 15, 16, 1, Color(0, 0, 0, 0.3)))
		"M":
			return _make("machine%s" % theme, func(p: Callable):
				p.call(0, 0, 16, 16, theme)
				p.call(2, 0, 12, 15, "#585868")
				p.call(3, 1, 10, 7, "#203040")
				p.call(4, 2, 8, 5, "#58c0e8")
				p.call(5, 3, 3, 1, "#c8f0f8")
				p.call(4, 10, 3, 2, "#e05050")
				p.call(9, 10, 3, 2, "#50c050")
				p.call(2, 15, 12, 1, Color(0, 0, 0, 0.3)))
		"X":
			return _make("stairs%s" % theme, func(p: Callable):
				p.call(0, 0, 16, 16, "#605868")
				for i in 4:
					p.call(1, 1 + i * 4, 14, 3, Gfx.shade(Color(theme), -0.05 * (3 - i)))
					p.call(1, 3 + i * 4, 14, 1, "#807888")
				p.call(0, 0, 1, 16, "#403848")
				p.call(15, 0, 1, 16, "#403848"))
		"V":
			return _make("vending%s" % theme, func(p: Callable):
				p.call(0, 0, 16, 16, theme)
				p.call(2, 0, 12, 15, "#c83838")
				p.call(3, 1, 10, 7, "#f8f8f0")
				for i in 3:
					p.call(4 + i * 3, 2, 2, 5, ["#58a8e0", "#f0d050", "#f08040"][i])
				p.call(4, 10, 8, 2, "#402020")
				p.call(11, 9, 1, 1, "#f8e070")
				p.call(2, 15, 12, 1, Color(0, 0, 0, 0.3)))
		"L":
			return _make("lamp", func(p: Callable):
				_grass(p, 2)
				p.call(4, 14, 8, 2, Color(0, 0, 0, 0.2))
				p.call(5, 13, 6, 2, "#383840")
				p.call(7, 3, 2, 11, "#484850")
				p.call(5, 0, 6, 4, "#383840")
				p.call(6, 1, 4, 2, "#f8e890")
				p.call(4, 4, 8, 1, Color(1.0, 0.95, 0.6, 0.35)))
	return _make("void", func(p: Callable): p.call(0, 0, 16, 16, "#000000"))

## Generated-art version of tile_texture (null for anything without a PNG, so the procedural tile is used).
static func _generated(ch: String, x: int, y: int, frame: int, above: String, below: String, theme: String, v: int) -> Texture2D:
	match ch:
		".":
			return _gen("grass", "grass")
		",":
			return _gen("tallgrass", "tallgrass")
		"=":
			return _gen("path", "path")
		"F":
			var n := "flowers" if v % 2 == 0 else "flowers2"
			return _gen(n + str(frame % 2), n, Callable(), "", 0)
		"~":
			var n := "water" if above == "~" else "shore"
			return _gen("%s%d" % [n, frame % 2], n, Callable(), "", 3 if frame % 2 else 0)
		"#":
			var n := "tree" if (x + y) % 2 == 0 else "tree2"
			return _gen(n, n)
		"v":
			return _gen("ledge", "ledge")
		"S":
			return _gen("sign", "sign")
		"r", "p", "b", "k", "n":
			var top := above != ch
			var bottom := below != ch
			var hi: String = {"r": "#e87060", "p": "#f898b0", "b": "#78a0e8", "k": "#e8c050", "n": "#e8d070"}[ch]
			return _gen("roof%s%d%d" % [ch, 1 if top else 0, 1 if bottom else 0], "roof_" + ch, func(p: Callable):
				if top:
					p.call(0, 0, 16, 1, hi)
				if bottom:
					p.call(0, 14, 16, 2, "#504048"))
		"w":
			return _gen("wall%d" % (x % 2), "window" if x % 2 else "wall2")
		"_":
			return _gen("floor%s%d" % [theme, (x + y) % 2], "floor", func(p: Callable):
				if (x + y) % 2:
					p.call(0, 0, 16, 16, Color(0, 0, 0, 0.04)), theme)
		"|":
			var n := "iwall" if below == "|" else "iwall_base"
			return _gen(n, n)
		"o":
			return _gen("statue" + theme, "statue", Callable(), theme)
		"e":
			return _gen("mat" + theme, "mat", Callable(), theme)
		"h", "l", "m", "j", "u":
			return _gen("door" + ch, "door_" + ch)
	return null
