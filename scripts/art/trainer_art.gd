class_name TrainerArt
## Trainer art (TS gfx.ts "trainers"): overworld characters and battle-intro portraits, drawn directly
## with Gfx.rect onto the current canvas (call inside _draw). Palettes are DB.PALETTES[name] dicts of
## hex strings: hat, shirt, pants, hair, skin.

const OL := "#282830"

## Draws a 16x20 overworld character with its feet at (x+8, y+16) in logical pixels.
## dir: "up" | "down" | "left" | "right"; step 0..2 (1 and 2 lift one leg).
static func draw_char(x: float, y: float, dir: String, step: int, pal: Dictionary) -> void:
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
static func draw_trainer_big(x: float, y: float, pal: Dictionary, back_view: bool) -> void:
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
