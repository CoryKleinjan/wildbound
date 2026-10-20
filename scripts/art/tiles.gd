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
	return _make("void", func(p: Callable): p.call(0, 0, 16, 16, "#000000"))
