class_name Gfx
## Immediate-mode drawing helpers on the 240x160 logical screen.
## Colors may be Color values or "#rrggbb" / "#rrggbbaa" strings.

const W := 240
const H := 160
## Canvas item everything draws on (set by main.gd each frame). While hosting LAN co-op it is a
## DrawRecorder, which has the same draw methods.
static var ci
static var _font: FontFile

static func font() -> FontFile:
	if _font == null:
		_font = load("res://assets/fonts/Wildbound.ttf")
		_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		_font.hinting = TextServer.HINTING_NONE
	return _font

static func col(c: Variant) -> Color:
	return c if c is Color else Color(c)

static func rect(x: float, y: float, w: float, h: float, color: Variant) -> void:
	ci.draw_rect(Rect2(x, y, w, h), col(color))

static func ellipse(cx: float, cy: float, rx: float, ry: float, color: Variant) -> void:
	var pts := PackedVector2Array()
	for i in 16:
		var a := TAU * i / 16.0
		pts.append(Vector2(cx + cos(a) * rx, cy + sin(a) * ry))
	ci.draw_colored_polygon(pts, col(color))

## Draws a texture with its top-left at (x, y). opts: scale (float), flip_h (bool), modulate (Color).
static func image(tex: Texture2D, x: float, y: float, opts: Dictionary = {}) -> void:
	var s: float = opts.get("scale", 1.0)
	var size := Vector2(tex.get_width(), tex.get_height()) * s
	if opts.get("flip_h", false):
		size.x = -size.x  # mirrored in place: Godot keeps the rect's position
	ci.draw_texture_rect(tex, Rect2(Vector2(x, y), size), false, col(opts.get("modulate", Color.WHITE)))

## Text with its top-left (or top-center / top-right by align) at (x, y).
## opts: color, size (logical px, default 7), align ("left" | "center" | "right"), shadow (color, or null for none).
static func text(str: String, x: float, y: float, opts: Dictionary = {}) -> void:
	var size: int = opts.get("size", 7)
	var f := font()
	var px := size * 3
	var w := f.get_string_size(str, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x / 3.0
	var align: String = opts.get("align", "left")
	if align == "center":
		x -= w / 2.0
	elif align == "right":
		x -= w
	# Fonts are rasterised at 3x and drawn scaled down, so they stay crisp in the scaled window.
	var base := y + f.get_ascent(px) / 3.0
	ci.draw_set_transform(Vector2.ZERO, 0, Vector2(1.0 / 3.0, 1.0 / 3.0))
	var shadow: Variant = opts.get("shadow", Color(0, 0, 0, 0.18))
	if shadow != null:
		ci.draw_string(f, Vector2(roundf(x * 3) + 2, roundf(base * 3) + 2), str, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col(shadow))
	ci.draw_string(f, Vector2(roundf(x * 3), roundf(base * 3)), str, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col(opts.get("color", "#303030")))
	ci.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

static func text_width(str: String, size: int = 7) -> float:
	return font().get_string_size(str, HORIZONTAL_ALIGNMENT_LEFT, -1, size * 3).x / 3.0

static func wrap(str: String, max_w: float, size: int = 7) -> Array[String]:
	var out: Array[String] = []
	for para in str.split("\n"):
		var line := ""
		for word in para.split(" "):
			var t := (line + " " + word) if line != "" else word
			if text_width(t, size) > max_w and line != "":
				out.append(line)
				line = word
			else:
				line = t
		out.append(line)
	return out

## GBA-style rounded window. style: "light" | "dark" | "battle".
## A menu screen's backdrop: the generated assets/screens/<name>.png, or a flat color with a header band.
static func screen(name: String, fill: Variant, header: Variant, header_h: float = 16) -> void:
	var tex := ArtAssets.texture("screens/" + name)
	if tex != null:
		image(tex, 0, 0)
		return
	rect(0, 0, W, H, fill)
	rect(0, 0, W, header_h, header)

static var _frames: Dictionary = {}

## A generated nine-slice window frame (assets/ui/panel_<style>.png, 24x24 with 8 px corners), or null.
static func _frame(style: String) -> StyleBoxTexture:
	if not _frames.has(style):
		var tex := ArtAssets.texture("ui/panel_" + style)
		var sb: StyleBoxTexture = null
		if tex != null:
			sb = StyleBoxTexture.new()
			sb.texture = tex
			for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
				sb.set_texture_margin(side, 8)
		_frames[style] = sb
	return _frames[style]

## Draws tex stretched over r with its m-pixel border unstretched, through ci's draw calls (a StyleBox can't draw
## onto the DrawRecorder that stands in for the canvas while recording a joined friend's view).
static func _nine_slice(tex: Texture2D, r: Rect2, m: float) -> void:
	var ts := tex.get_size()
	var sx := [0.0, m, ts.x - m, ts.x]
	var sy := [0.0, m, ts.y - m, ts.y]
	var dx := [r.position.x, r.position.x + m, r.end.x - m, r.end.x]
	var dy := [r.position.y, r.position.y + m, r.end.y - m, r.end.y]
	for j in 3:
		for i in 3:
			ci.draw_texture_rect_region(tex, Rect2(dx[i], dy[j], dx[i + 1] - dx[i], dy[j + 1] - dy[j]),
				Rect2(sx[i], sy[j], sx[i + 1] - sx[i], sy[j + 1] - sy[j]))

static func panel(x: float, y: float, w: float, h: float, style: String = "light") -> void:
	var sb := _frame(style)
	if sb != null and w >= 16 and h >= 16:
		_nine_slice(sb.texture, Rect2(x, y, w, h), 8)
		return
	var border := "#283048" if style == "dark" else "#48506a"
	var fill := "#384060" if style == "dark" else ("#f8f8f0" if style == "battle" else "#f8f8f8")
	rect(x + 1, y, w - 2, h, border)
	rect(x, y + 1, w, h - 2, border)
	rect(x + 2, y + 1, w - 4, h - 2, fill)
	rect(x + 1, y + 2, w - 2, h - 4, fill)
	if style == "light":
		rect(x + 2, y + 2, w - 4, 1, "#d8e0f0")

static func cursor(x: float, y: float, color: Variant = "#303030") -> void:
	ci.draw_colored_polygon(PackedVector2Array([Vector2(x, y), Vector2(x + 4, y + 3), Vector2(x, y + 6)]), col(color))

static func hp_color(frac: float) -> String:
	return "#40c850" if frac > 0.5 else ("#f0c020" if frac > 0.2 else "#e83838")

static func bar(x: float, y: float, w: float, frac: float, color: Variant, h: float = 3) -> void:
	rect(x - 1, y - 1, w + 2, h + 2, "#404858")
	rect(x, y, w, h, "#586078")
	rect(x, y, maxf(0, roundf(w * clampf(frac, 0, 1))), h, color)

static func type_badge(t: String, x: float, y: float) -> void:
	rect(x, y, 32, 9, DB.TYPE_COLORS[t])
	rect(x, y + 8, 32, 1, Color(0, 0, 0, 0.25))
	text(t.to_upper().substr(0, 8), x + 16, y + 2, {"color": "#ffffff", "size": 5, "align": "center", "shadow": Color(0, 0, 0, 0.4)})

const STATUS_LABEL := {
	"brn": ["BRN", "#e07030"], "par": ["PAR", "#c8b020"], "psn": ["PSN", "#a040a0"], "tox": ["PSN", "#a040a0"],
	"slp": ["SLP", "#8890a0"], "frz": ["FRZ", "#60b8e0"],
}

static func status_badge(s: Variant, x: float, y: float) -> void:
	if s == null or s == "":
		return
	var lc: Array = STATUS_LABEL[s]
	rect(x, y, 19, 7, lc[1])
	text(lc[0], x + 2, y + 1, {"color": "#ffffff", "size": 5, "shadow": null})

## Lightens (f > 0) or darkens (f < 0) a color.
static func shade(c: Variant, f: float) -> Color:
	var k := col(c)
	if f < 0:
		return Color(k.r * (1 + f), k.g * (1 + f), k.b * (1 + f), k.a)
	return Color(k.r + (1 - k.r) * f, k.g + (1 - k.g) * f, k.b + (1 - k.b) * f, k.a)

static func hue_shift(c: Variant, deg: float) -> Color:
	var k := col(c)
	return Color.from_hsv(fposmod(k.h + deg / 360.0, 1.0), k.s, k.v, k.a)
