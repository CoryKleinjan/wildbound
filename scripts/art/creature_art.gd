class_name CreatureArt
## Procedural creature sprites (TS gfx.ts "procedural creature sprites").
## Each species' SpriteSpec (body plan, colors, features) is drawn as vector shapes into a 64x64 image with
## anti-aliased coverage, like Canvas2D, then pixelized: hard alpha, dark outline and a little edge shading
## so the shapes read as pixel art.

const SIZE := 64
## Vertical sub-scanlines per pixel for coverage (horizontal coverage is exact).
const SUB := 8

static var _sprite_cache: Dictionary = {}
static var _sil_cache: Dictionary = {}

# ---------- color utilities (exact ports of the TS hex helpers, including rounding) ----------

static func _hex_to_rgb(h: String) -> PackedInt32Array:
	var n := h.substr(1).hex_to_int()
	return PackedInt32Array([(n >> 16) & 255, (n >> 8) & 255, n & 255])

## JS Math.round.
static func _jround(v: float) -> int:
	return int(floorf(v + 0.5))

static func _rgb_to_hex(r: float, g: float, b: float) -> String:
	var s := "#"
	for v in [r, g, b]:
		s += "%02x" % clampi(_jround(v), 0, 255)
	return s

## Lightens (f > 0) or darkens (f < 0) a "#rrggbb" color. Same rounding as the TS.
static func shade_hex(h: String, f: float) -> String:
	var c := _hex_to_rgb(h)
	if f < 0:
		return _rgb_to_hex(c[0] * (1 + f), c[1] * (1 + f), c[2] * (1 + f))
	return _rgb_to_hex(c[0] + (255 - c[0]) * f, c[1] + (255 - c[1]) * f, c[2] + (255 - c[2]) * f)

## HSL hue rotation (shiny palettes).
static func hue_shift_hex(h: String, deg: float) -> String:
	var c := _hex_to_rgb(h)
	var r := c[0] / 255.0
	var g := c[1] / 255.0
	var b := c[2] / 255.0
	var mx := maxf(r, maxf(g, b))
	var mn := minf(r, minf(g, b))
	var hh := 0.0
	var s := 0.0
	var l := (mx + mn) / 2.0
	if mx != mn:
		var d := mx - mn
		s = d / (2 - mx - mn) if l > 0.5 else d / (mx + mn)
		if mx == r:
			hh = (g - b) / d + (6.0 if g < b else 0.0)
		elif mx == g:
			hh = (b - r) / d + 2
		else:
			hh = (r - g) / d + 4
		hh /= 6.0
	hh = fmod(hh + deg / 360.0 + 1.0, 1.0)
	var a := s * minf(l, 1 - l)
	var f := func(n: float) -> float:
		var k := fmod(n + hh * 12, 12.0)
		return l - a * maxf(-1, minf(minf(k - 3, 9 - k), 1))
	return _rgb_to_hex(f.call(0) * 255, f.call(8) * 255, f.call(4) * 255)

# ---------- public API ----------

static func creature_sprite(species_id: String, shiny: bool = false, back: bool = false) -> Texture2D:
	var key := "%s|%s|%s" % [species_id, shiny, back]
	if _sprite_cache.has(key):
		return _sprite_cache[key]
	var img := sprite_image(species_id, shiny, back)
	var tex := ImageTexture.create_from_image(img)
	_sprite_cache[key] = tex
	return tex

## The raw 64x64 RGBA8 image behind creature_sprite (uncached).
static func sprite_image(species_id: String, shiny: bool = false, back: bool = false) -> Image:
	var png := ArtAssets.image("creatures/%s%s" % [species_id, "_back" if back else ""])
	if png != null:
		return ArtAssets.hue_rotate(png, 140) if shiny else png.duplicate()
	return procedural_image(species_id, shiny, back)

## The procedural sprite (fallback when assets/creatures/<id>.png is missing).
static func procedural_image(species_id: String, shiny: bool = false, back: bool = false) -> Image:
	var spec0: Dictionary = _species(species_id).sprite
	var spec := spec0
	if shiny:
		spec = spec0.duplicate()
		spec.main = hue_shift_hex(spec0.main, 140)
		spec.accent = hue_shift_hex(spec0.accent, 100)
		spec.belly = hue_shift_hex(spec0.belly, 40)
	var k := 0.55 + float(spec.size) * 0.45
	var r := _Raster.new(32, 61, k)
	_draw_body(r, spec, back)
	var img := _pixelize(r, spec)
	if back:
		img.flip_x()
	return img

## Drops every cached texture (sprites and silhouettes).
static func clear_cache() -> void:
	_sprite_cache.clear()
	_sil_cache.clear()

## Single-color silhouette of a sprite (evolution flashes, trainer intros).
static func silhouette(tex: Texture2D, color: Variant) -> Texture2D:
	var c: Color = color if color is Color else Color(color)
	var key := "%d|%s" % [tex.get_instance_id(), c.to_html()]
	if _sil_cache.has(key):
		return _sil_cache[key]
	var src := tex.get_image()
	if src.is_compressed():
		src.decompress()
	var img := Image.create(src.get_width(), src.get_height(), false, Image.FORMAT_RGBA8)
	for y in src.get_height():
		for x in src.get_width():
			var a := src.get_pixel(x, y).a
			if a > 0:
				img.set_pixel(x, y, Color(c.r, c.g, c.b, c.a * a))
	var out := ImageTexture.create_from_image(img)
	_sil_cache[key] = out
	return out

## DB.species via the tree, so this class also compiles in `-s` test scripts (loaded before autoloads exist).
static func _species(id: String) -> Dictionary:
	return (Engine.get_main_loop() as SceneTree).root.get_node("DB").species(id)

static func is_floating(species_id: String) -> bool:
	var b: String = _species(species_id).sprite.body
	return b == "fish" or b == "ghost"

# ---------- rasterizer ----------

## Minimal anti-aliased vector rasterizer standing in for a Canvas2D context with a translate + uniform scale
## transform. Shapes are filled with source-over compositing into premultiplied float buffers.
class _Raster:
	var ox: float
	var oy: float
	var k: float
	var pr := PackedFloat32Array()
	var pg := PackedFloat32Array()
	var pb := PackedFloat32Array()
	var pa := PackedFloat32Array()
	var cov := PackedFloat32Array()

	func _init(tx: float, ty: float, scale: float) -> void:
		ox = tx
		oy = ty
		k = scale
		var n := SIZE * SIZE
		pr.resize(n)
		pg.resize(n)
		pb.resize(n)
		pa.resize(n)
		cov.resize(n)

	func _composite(x0: int, y0: int, x1: int, y1: int, color: String) -> void:
		var c := Color(color)
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				var i := y * SIZE + x
				var a: float = minf(cov[i], 1.0)
				if a <= 0.0:
					continue
				cov[i] = 0.0
				var ia := 1.0 - a
				pr[i] = c.r * a + pr[i] * ia
				pg[i] = c.g * a + pg[i] * ia
				pb[i] = c.b * a + pb[i] * ia
				pa[i] = a + pa[i] * ia

	## Adds horizontal span [sx0, sx1) on pixel row py with weight 1/SUB.
	func _span(py: int, sx0: float, sx1: float) -> void:
		sx0 = maxf(sx0, 0.0)
		sx1 = minf(sx1, SIZE)
		if sx1 <= sx0:
			return
		var w := 1.0 / SUB
		var a := int(floorf(sx0))
		var b := int(floorf(sx1))
		var row := py * SIZE
		if a == b:
			cov[row + a] += (sx1 - sx0) * w
			return
		cov[row + a] += (a + 1 - sx0) * w
		for x in range(a + 1, b):
			cov[row + x] += w
		if b < SIZE:
			cov[row + b] += (sx1 - b) * w

	## Ellipse in local coordinates, rotated by rot radians.
	func ell(x: float, y: float, rx: float, ry: float, color: String, rot: float = 0.0) -> void:
		var cx := ox + x * k
		var cy := oy + y * k
		var a := rx * k
		var b := ry * k
		var ext := maxf(a, b)
		var y0 := clampi(int(floorf(cy - ext)), 0, SIZE - 1)
		var y1 := clampi(int(floorf(cy + ext)), 0, SIZE - 1)
		var cs := cos(rot)
		var sn := sin(rot)
		var ia2 := 1.0 / (a * a)
		var ib2 := 1.0 / (b * b)
		var qa := cs * cs * ia2 + sn * sn * ib2
		var qb_f := 2.0 * sn * cs * (ia2 - ib2)
		var qc_f := sn * sn * ia2 + cs * cs * ib2
		var minx := SIZE
		var maxx := -1
		for py in range(y0, y1 + 1):
			for s in SUB:
				var dy := py + (s + 0.5) / SUB - cy
				var qb := qb_f * dy
				var qc := qc_f * dy * dy - 1.0
				var disc := qb * qb - 4.0 * qa * qc
				if disc <= 0.0:
					continue
				var sq := sqrt(disc)
				var xa := cx + (-qb - sq) / (2.0 * qa)
				var xb := cx + (-qb + sq) / (2.0 * qa)
				_span(py, xa, xb)
				minx = mini(minx, int(floorf(xa)))
				maxx = maxi(maxx, int(floorf(xb)))
		if maxx >= 0:
			_composite(clampi(minx, 0, SIZE - 1), y0, clampi(maxx, 0, SIZE - 1), y1, color)

	## Filled polygon from flat local [x0, y0, x1, y1, ...] (nonzero winding).
	func poly(pts: Array, color: String) -> void:
		var dev := PackedVector2Array()
		for i in range(0, pts.size(), 2):
			dev.append(Vector2(ox + pts[i] * k, oy + pts[i + 1] * k))
		poly_dev(dev, color)

	func poly_dev(dev: PackedVector2Array, color: String) -> void:
		var miny := INF
		var maxy := -INF
		var minx := INF
		var maxx := -INF
		for p in dev:
			miny = minf(miny, p.y)
			maxy = maxf(maxy, p.y)
			minx = minf(minx, p.x)
			maxx = maxf(maxx, p.x)
		var y0 := clampi(int(floorf(miny)), 0, SIZE - 1)
		var y1 := clampi(int(floorf(maxy)), 0, SIZE - 1)
		var n := dev.size()
		for py in range(y0, y1 + 1):
			for s in SUB:
				var sy := py + (s + 0.5) / SUB
				var xs: Array = []
				for i in n:
					var p := dev[i]
					var q := dev[(i + 1) % n]
					if (p.y <= sy and q.y > sy) or (q.y <= sy and p.y > sy):
						var t := (sy - p.y) / (q.y - p.y)
						xs.append([p.x + t * (q.x - p.x), 1 if q.y > p.y else -1])
				if xs.size() < 2:
					continue
				xs.sort_custom(func(u, v): return u[0] < v[0])
				var wind := 0
				for j in xs.size() - 1:
					wind += xs[j][1]
					if wind != 0:
						_span(py, xs[j][0], xs[j + 1][0])
		_composite(clampi(int(floorf(minx)), 0, SIZE - 1), y0, clampi(int(floorf(maxx)), 0, SIZE - 1), y1, color)

	## fillRect in local coordinates.
	func frect(x: float, y: float, w: float, h: float, color: String) -> void:
		poly([x, y, x + w, y, x + w, y + h, x, y + h], color)

	## Stroked line segment (butt caps), width in local units.
	func line(x0: float, y0: float, x1: float, y1: float, width: float, color: String) -> void:
		var d := Vector2(x1 - x0, y1 - y0).normalized()
		var nx := -d.y * width / 2.0
		var ny := d.x * width / 2.0
		poly([x0 + nx, y0 + ny, x1 + nx, y1 + ny, x1 - nx, y1 - ny, x0 - nx, y0 - ny], color)

# ---------- body plans ----------

static func _flame(g: _Raster, x: float, y: float, r: float) -> void:
	g.poly([x - r * 0.7, y + r * 0.4, x - r * 0.3, y - r * 1.2, x, y - r * 0.4, x + r * 0.4, y - r * 1.4, x + r * 0.7, y + r * 0.4], "#f86830")
	g.poly([x - r * 0.4, y + r * 0.4, x, y - r * 0.6, x + r * 0.4, y + r * 0.4], "#f8d848")

## Features drawn behind the body first.
static func _behind(g: _Raster, s: Dictionary, an: Dictionary) -> void:
	var feats: Array = s.features
	var accent: String = s.accent
	var main: String = s.main
	var bx: float = an.back.x
	var by: float = an.back.y
	var tx: float = an.tail.x
	var ty: float = an.tail.y
	if feats.has("wings"):
		g.ell(bx + 10, by - 8, 16, 9, shade_hex(accent, 0.25), -0.7)
		g.ell(bx - 4, by - 10, 14, 8, shade_hex(accent, 0.1), -1.1)
	if feats.has("tail"):
		g.ell(tx + 8, ty - 6, 10, 4, main, -0.8)
	if feats.has("tailFlame"):
		g.ell(tx + 7, ty - 4, 8, 3, main, -0.6)
		_flame(g, tx + 14, ty - 10, 7)
	if feats.has("boltTail"):
		g.poly([tx, ty, tx + 12, ty - 8, tx + 8, ty - 12, tx + 20, ty - 24, tx + 12, ty - 14, tx + 15, ty - 10], accent)
	if feats.has("bigLeaf"):
		g.ell(bx + 6, by - 10, 14, 7, shade_hex(accent, 0.15), -0.9)
	if feats.has("shell"):
		g.ell(bx + 2, by - 2, 16, 12, accent)

static func _anchors(hx: float, hy: float, hr: float, bx: float, by: float, tx: float, ty: float) -> Dictionary:
	return {"head": {"x": hx, "y": hy, "r": hr}, "back": {"x": bx, "y": by}, "tail": {"x": tx, "y": ty}}

static func _draw_body(g: _Raster, s: Dictionary, back: bool) -> void:
	var main: String = s.main
	var accent: String = s.accent
	var belly: String = s.belly
	var feats: Array = s.features
	var body: String = s.body
	var a: Dictionary
	match body:
		"quad":
			a = _anchors(-14, -32, 12, 6, -26, 20, -18)
			_behind(g, s, a)
			for lx in [-16, -6, 8, 16]:
				g.frect(lx - 3, -14, 7, 14, shade_hex(main, -0.15))
			g.ell(0, -18, 24, 13, main)
			g.ell(-4, -12, 15, 6, belly)
		"biped":
			a = _anchors(-2, -44, 14, 6, -28, 12, -10)
			_behind(g, s, a)
			g.ell(-8, -4, 7, 4, shade_hex(main, -0.15))
			g.ell(8, -4, 7, 4, shade_hex(main, -0.15))
			g.ell(0, -20, 14, 17, main)
			g.ell(-1, -17, 9, 11, belly)
			g.ell(-14, -24, 4, 8, main, 0.5)
			g.ell(13, -24, 4, 8, main, -0.5)
		"bird":
			a = _anchors(-8, -38, 11, 8, -26, 18, -16)
			g.line(-4, -8, -5, 0, 2, "#d8a030")
			g.line(4, -8, 5, 0, 2, "#d8a030")
			g.poly([12, -18, 28, -14, 24, -8], accent)
			_behind(g, s, a)
			g.ell(2, -20, 16, 13, main)
			g.ell(-2, -16, 9, 8, belly)
			g.ell(10, -21, 9, 7, shade_hex(main, -0.12), 0.3)
		"bug":
			a = _anchors(-14, -26, 9, 6, -24, 18, -12)
			_behind(g, s, a)
			for lx in [-8, 0, 8]:
				g.frect(lx, -8, 2, 8, shade_hex(accent, -0.2))
			g.ell(10, -14, 12, 9, main)
			g.ell(-2, -16, 10, 9, shade_hex(main, 0.08))
			g.ell(-2, -12, 7, 4, belly)
		"blob":
			a = _anchors(0, -30, 0, 0, -36, 18, -10)
			_behind(g, s, a)
			g.ell(0, -20, 22, 20, main)
			g.frect(-22, -20, 44, 20, main)
			g.ell(0, -10, 14, 8, belly)
			a.head = {"x": 0, "y": -26, "r": 14}
		"serpent":
			a = _anchors(-14, -30, 11, 4, -20, 24, -6)
			_behind(g, s, a)
			for seg in [[22, -6, 6], [14, -8, 8], [5, -10, 9], [-5, -16, 10]]:
				var r: float = seg[2]
				g.ell(seg[0], seg[1], r, r * 0.9, main)
				g.ell(seg[0] - 1, seg[1] + r * 0.4, r * 0.6, r * 0.35, belly)
		"rock":
			a = _anchors(0, -24, 14, 0, -40, 18, -10)
			_behind(g, s, a)
			g.poly([-22, -2, -26, -20, -14, -38, 6, -42, 22, -30, 24, -8, 14, 0], main)
			g.poly([-14, -38, 6, -42, 0, -30], shade_hex(main, 0.2))
			g.ell(-26, -16, 6, 8, accent)
			g.ell(26, -16, 6, 8, accent)
		"fish":
			a = _anchors(-12, -28, 0, 0, -40, 20, -26)
			g.poly([16, -28, 32, -40, 30, -26, 32, -14], accent)
			_behind(g, s, a)
			g.ell(-2, -28, 20, 13, main)
			g.ell(-6, -23, 12, 5, belly)
			g.poly([-4, -40, 8, -48, 10, -38], accent)
			a.head = {"x": -12, "y": -30, "r": 10}
		"ghost":
			a = _anchors(0, -34, 14, 0, -46, 14, -14)
			_behind(g, s, a)
			g.ell(0, -34, 18, 18, main)
			g.poly([-18, -34, 18, -34, 16, -14, 10, -18, 4, -10, -2, -16, -8, -8, -12, -16, -18, -12], main)
			g.ell(0, -26, 10, 6, belly)
	var hx: float = a.head.x
	var hy: float = a.head.y
	var hr: float = a.head.r
	var bx: float = a.back.x
	var by: float = a.back.y
	# Head.
	if body != "blob" and body != "rock" and body != "fish" and body != "ghost":
		g.ell(hx, hy, hr, hr * 0.92, main)
	if feats.has("mane"):
		for i in range(-2, 3):
			g.ell(hx + i * 5, hy + hr * 0.8, 5, 4, accent)
	if feats.has("ears"):
		g.poly([hx - hr * 0.8, hy - hr * 0.3, hx - hr * 0.7, hy - hr * 1.4, hx - hr * 0.1, hy - hr * 0.8], main)
		g.poly([hx + hr * 0.8, hy - hr * 0.3, hx + hr * 0.7, hy - hr * 1.4, hx + hr * 0.1, hy - hr * 0.8], main)
		g.poly([hx - hr * 0.65, hy - hr * 0.55, hx - hr * 0.62, hy - hr * 1.1, hx - hr * 0.3, hy - hr * 0.8], accent)
	if feats.has("longEars"):
		g.ell(hx - hr * 0.6, hy - hr * 1.2, 3.5, 9, main, -0.3)
		g.ell(hx + hr * 0.6, hy - hr * 1.2, 3.5, 9, main, 0.3)
		g.ell(hx - hr * 0.6, hy - hr * 1.25, 1.6, 6, accent, -0.3)
	if feats.has("crest"):
		for dx in [-4, 0, 4]:
			g.poly([hx + dx - 3, hy - hr * 0.7, hx + dx + 2, hy - hr * 1.6, hx + dx + 3, hy - hr * 0.7], accent)
	if feats.has("leaf"):
		g.frect(hx - 1, hy - hr - 4, 2, 5, shade_hex(accent, -0.2))
		g.ell(hx + 5, hy - hr - 6, 7, 3.5, accent, -0.5)
	if feats.has("flower"):
		for i in 5:
			var ang := i / 5.0 * PI * 2
			g.ell(bx + 4 + cos(ang) * 7, by - 12 + sin(ang) * 5, 6, 4, "#f088b0", ang)
		g.ell(bx + 4, by - 12, 4, 3, "#f8e070")
	if feats.has("flame"):
		_flame(g, hx + 2, hy - hr - 2, 8)
	if feats.has("mushroom"):
		g.ell(hx, hy - hr * 0.6, hr * 1.45, hr * 0.85, accent)
		g.frect(hx - hr * 1.45, hy - hr * 0.6, hr * 2.9, 3, accent)
		for d in [[-8, -12], [4, -15], [12, -8], [-14, -5]]:
			g.ell(hx + d[0], hy + d[1], 2.5, 2, "#ffffff")
	if feats.has("fin"):
		g.poly([bx - 6, by + 2, bx + 2, by - 14, bx + 8, by + 2], accent)
	if feats.has("spikes"):
		for dx in [-8, 0, 8]:
			g.poly([bx + dx - 4, by + 4, bx + dx, by - 6, bx + dx + 4, by + 4], shade_hex(accent, 0.1))
	if feats.has("horn"):
		g.poly([hx - 3, hy - hr * 0.7, hx - 1, hy - hr * 1.7, hx + 3, hy - hr * 0.7], "#f0e8c8")
	if feats.has("antenna"):
		var sc := shade_hex(main, -0.4)
		g.line(hx - 3, hy - hr * 0.8, hx - 8, hy - hr * 1.9, 1.5, sc)
		g.line(hx + 3, hy - hr * 0.8, hx + 6, hy - hr * 1.9, 1.5, sc)
		g.ell(hx - 8, hy - hr * 1.9, 2.5, 2.5, accent)
		g.ell(hx + 6, hy - hr * 1.9, 2.5, 2.5, accent)
	if back:
		return
	# Face.
	var eyes: String = s.get("eyes", "round")
	var eye_y := hy - hr * 0.05
	var ex := maxf(4, hr * 0.42)
	for x in [hx - ex, hx + ex]:
		if eyes == "sleepy":
			g.frect(x - 3, eye_y, 6, 1.6, "#202028")
			continue
		g.ell(x, eye_y, 3, 3.6, "#ffffff")
		g.ell(x - 0.6, eye_y + 0.6, 1.9, 2.5, "#202028")
		g.ell(x - 1.2, eye_y - 0.8, 0.8, 0.8, "#ffffff")
		if eyes == "fierce":
			# translate(x, eyeY - 3.5), rotate(+-0.35), fillRect(-3.5, -1, 7, 1.8)
			var rot := 0.35 if x < hx else -0.35
			var pts: Array = []
			for c in [[-3.5, -1.0], [3.5, -1.0], [3.5, 0.8], [-3.5, 0.8]]:
				var v := Vector2(c[0], c[1]).rotated(rot)
				pts.append(x + v.x)
				pts.append(eye_y - 3.5 + v.y)
			g.poly(pts, shade_hex(main, -0.5))
	if feats.has("cheeks"):
		g.ell(hx - ex - 3, eye_y + 5, 2.6, 1.8, "#f08080")
		g.ell(hx + ex + 3, eye_y + 5, 2.6, 1.8, "#f08080")
	if body == "bird":
		g.poly([hx - 3, hy + 3, hx - 12, hy + 5, hx - 3, hy + 7], "#e8b040")
	else:
		g.frect(hx - 2, eye_y + 5, 4, 1.4, "#402828")
	if feats.has("tusks"):
		g.poly([hx - 4, eye_y + 6, hx - 3, eye_y + 10, hx - 2, eye_y + 6], "#ffffff")
		g.poly([hx + 2, eye_y + 6, hx + 3, eye_y + 10, hx + 4, eye_y + 6], "#ffffff")

# ---------- pixelize ----------

## Hard alpha, dark outline and a little edge shading so the shapes read as pixel art.
## Mirrors the TS pass on Canvas2D image data (8-bit, un-premultiplied), including its rounding.
static func _pixelize(r: _Raster, spec: Dictionary) -> Image:
	var w := SIZE
	var h := SIZE
	var n := w * h
	var d := PackedByteArray()
	d.resize(n * 4)
	var solid := PackedByteArray()
	solid.resize(n)
	for i in n:
		# Canvas stores 8-bit premultiplied; getImageData un-premultiplies.
		var al := _jround(r.pa[i] * 255.0)
		if al >= 110:
			solid[i] = 1
			var f := 255.0 / al
			var m := f * 0.85 if al < 255 else 1.0
			var u := [r.pr[i], r.pg[i], r.pb[i]]
			for ch in 3:
				var pm := _jround(u[ch] * 255.0)
				var un := mini(255, _jround(pm * 255.0 / al))
				d[i * 4 + ch] = _round_even(minf(255.0, un * m))
			d[i * 4 + 3] = 255
		else:
			d[i * 4 + 3] = 0
	var oc := _hex_to_rgb(shade_hex(spec.main, -0.65))
	var out := d.duplicate()
	for y in h:
		for x in w:
			var i := y * w + x
			if solid[i] == 0:
				if _n(solid, x + 1, y) or _n(solid, x - 1, y) or _n(solid, x, y + 1) or _n(solid, x, y - 1):
					out[i * 4] = oc[0]
					out[i * 4 + 1] = oc[1]
					out[i * 4 + 2] = oc[2]
					out[i * 4 + 3] = 255
			elif not _n(solid, x + 1, y + 1) or not _n(solid, x, y + 2) or not _n(solid, x + 2, y):
				out[i * 4] = _round_even(out[i * 4] * 0.8)
				out[i * 4 + 1] = _round_even(out[i * 4 + 1] * 0.8)
				out[i * 4 + 2] = _round_even(out[i * 4 + 2] * 0.82)
			elif not _n(solid, x - 1, y - 1) or not _n(solid, x, y - 2):
				out[i * 4] = mini(255, out[i * 4] + 28)
				out[i * 4 + 1] = mini(255, out[i * 4 + 1] + 28)
				out[i * 4 + 2] = mini(255, out[i * 4 + 2] + 28)
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, out)

static func _n(solid: PackedByteArray, x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < SIZE and y < SIZE and solid[y * SIZE + x] == 1

## Uint8ClampedArray assignment rounds half to even.
static func _round_even(v: float) -> int:
	var f := floorf(v)
	var diff := v - f
	var r := int(f)
	if diff > 0.5 or (diff == 0.5 and r % 2 == 1):
		r += 1
	return clampi(r, 0, 255)
