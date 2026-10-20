class_name TrainerArt
## Trainer art (TS gfx.ts "trainers"): overworld characters and battle-intro portraits, drawn directly
## with Gfx.rect onto the current canvas (call inside _draw). Palettes are DB.PALETTES[name] dicts of
## hex strings: hat, shirt, pants, hair, skin.

const OL := "#282830"

## Draws a 16x20 overworld character with its feet at (x+8, y+16) in logical pixels.
## dir: "up" | "down" | "left" | "right"; step 0..2 (1 and 2 lift one leg).
## name: the palette's key in DB.PALETTES; when assets/trainers/<name>_walk.png exists it is drawn instead.
static func draw_char(x: float, y: float, dir: String, step: int, pal: Dictionary, name: String = "") -> void:
	var walk := ArtAssets.texture("trainers/%s_walk" % name) if name != "" else null
	if walk != null:
		_draw_walk(walk, x, y, dir, step)
		return
	var p := func(dx: float, dy: float, w: float, h: float, c: Variant) -> void:
		Gfx.rect(x + dx, y + dy, w, h, c)
	var leg_a := 1 if step == 1 else 0
	var leg_b := 1 if step == 2 else 0
	# shadow
	Gfx.ellipse(x + 8, y + 15, 6, 2, Color(0, 0, 0, 0.2))
	# legs
	p.call(4, 11 - leg_a, 3, 4, OL)
	p.call(9, 11 - leg_b, 3, 4, OL)
	p.call(5, 11 - leg_a, 1, 3, pal.pants)
	p.call(10, 11 - leg_b, 1, 3, pal.pants)
	# body
	p.call(3, 6, 10, 6, OL)
	p.call(4, 7, 8, 4, pal.shirt)
	if dir == "left":
		p.call(4, 8, 3, 3, Gfx.shade(pal.shirt, -0.2))
	if dir == "right":
		p.call(9, 8, 3, 3, Gfx.shade(pal.shirt, -0.2))
	# head
	p.call(3, -2, 10, 9, OL)
	p.call(4, -1, 8, 7, pal.skin)
	# hair/hat
	p.call(3, -3, 10, 4, OL)
	p.call(4, -2, 8, 3, pal.hat)
	if dir == "up":
		p.call(4, 0, 8, 6, pal.hair)
	elif dir == "down":
		p.call(5, 2, 1, 2, OL)
		p.call(10, 2, 1, 2, OL)
		p.call(4, 1, 1, 2, pal.hair)
		p.call(11, 1, 1, 2, pal.hair)
		p.call(4, -3, 8, 1, Gfx.shade(pal.hat, 0.3))
	elif dir == "left":
		p.call(5, 2, 1, 2, OL)
		p.call(9, 0, 3, 5, pal.hair)
		p.call(2, 0, 3, 1, pal.hat)
	else:
		p.call(10, 2, 1, 2, OL)
		p.call(4, 0, 3, 5, pal.hair)
		p.call(11, 0, 3, 1, pal.hat)

## Larger trainer portrait for the battle intro (48px tall).
static func draw_trainer_big(x: float, y: float, pal: Dictionary, back_view: bool, name: String = "") -> void:
	var tex := ArtAssets.texture("trainers/" + name) if name != "" and not back_view else null
	if tex != null:
		# 64x64 portrait standing where the procedural one stands (feet at y + 52).
		Gfx.image(tex, x - 8, y - 10)
		return
	var p := func(dx: float, dy: float, w: float, h: float, c: Variant) -> void:
		Gfx.rect(x + dx, y + dy, w, h, c)
	p.call(10, 30, 28, 22, OL)
	p.call(12, 32, 24, 20, pal.shirt)
	p.call(14, 6, 20, 24, OL)
	p.call(16, 8, 16, 20, pal.skin)
	p.call(12, 2, 24, 10, OL)
	p.call(14, 4, 20, 7, pal.hat)
	if back_view:
		p.call(16, 10, 16, 16, pal.hair)
	else:
		p.call(19, 16, 2, 4, OL)
		p.call(27, 16, 2, 4, OL)
		p.call(21, 23, 6, 1, "#a05040")
	p.call(6, 34, 6, 14, OL)
	p.call(36, 34, 6, 14, OL)
	p.call(7, 35, 4, 12, pal.shirt)
	p.call(37, 35, 4, 12, pal.shirt)

## Generated overworld strip: 48x20, frames down | up | left (right is left mirrored).
## Walking frames bob the body up a pixel and keep one foot planted.
static func _draw_walk(tex: Texture2D, x: float, y: float, dir: String, step: int) -> void:
	Gfx.ellipse(x + 8, y + 15, 6, 2, Color(0, 0, 0, 0.2))
	if tex.get_height() > 20:
		# 3x3 sheet (16x24 walking, 24x24 riding): rows face down, up, left (right mirrors left); columns stand, step 1, step 2
		var fw := tex.get_width() / 3
		var fh := tex.get_height() / 3
		var row: int = {"down": 0, "up": 1, "left": 2, "right": 2}.get(dir, 0)
		var fl := dir == "right"
		var left := x - (fw - 16) / 2.0
		var dst := Rect2(left + (fw if fl else 0), y + 16 - fh - (1 if step != 0 else 0), -fw if fl else fw, fh)
		Gfx.ci.draw_texture_rect_region(tex, dst, Rect2(clampi(step, 0, 2) * fw, row * fh, fw, fh))
		return
	var col: int = {"down": 0, "up": 1, "left": 2, "right": 2}.get(dir, 0)
	var flip := dir == "right"
	var top := y - 4
	var lift := 1 if step != 0 else 0
	_region(tex, col, 0, 17, x, top - lift, flip)
	if step == 0:
		_region(tex, col, 17, 3, x, top, flip)
	else:
		# the planted half of the feet stays down, the other half lifts with the body
		var planted_left := (step == 1) != flip
		_region_part(tex, col, 17, 3, x, top - lift, flip, not planted_left)
		_region_part(tex, col, 17, 3, x, top, flip, planted_left)

static func _region(tex: Texture2D, col: int, sy: int, h: int, x: float, top: float, flip: bool) -> void:
	var dst := Rect2(x + (16 if flip else 0), top + sy, -16 if flip else 16, h)
	Gfx.ci.draw_texture_rect_region(tex, dst, Rect2(col * 16, sy, 16, h))

static func _region_part(tex: Texture2D, col: int, sy: int, h: int, x: float, top: float, flip: bool, left_half: bool) -> void:
	# left_half is in screen space
	var sx := 0 if (left_half != flip) else 8
	var dx := x + (0 if left_half else 8)
	var dst := Rect2(dx + (8 if flip else 0), top + sy, -8 if flip else 8, h)
	Gfx.ci.draw_texture_rect_region(tex, dst, Rect2(col * 16 + sx, sy, 8, h))
