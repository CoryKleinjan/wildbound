class_name FieldTiles
## Tile art for the Emerald field features: Cut trees, smashable rocks, boulders, waterfalls, deep water,
## soft soil, caves, sand, the new buildings and Secret Base trees. Drawn into Tiles' texture cache.
##   T cut tree   R cracked rock   O boulder   W waterfall   D deep (dive) water   s soft soil
##   g cave floor   x cave wall   y cave mouth or ladder   a sand   i roof   d door   z secret-base tree   Q base PC
##   Y slot machine (Game Corner)   N TV   G painting on an easel (art museum)   Z Braille wall

const CHARS := "TROWDsgxyaidzQYNGZ"

static func handles(ch: String) -> bool:
	return ch.length() == 1 and CHARS.contains(ch)

static func texture(ch: String, x: int, y: int, frame: int, above: String, theme: String) -> Texture2D:
	var v := (x * 7 + y * 13) % 4
	match ch:
		"T":
			var inside := above == "_" or above == "|"
			return Tiles._make("fx_cut_in" + theme if inside else "fx_cut", func(p: Callable):
				if inside:
					p.call(0, 0, 16, 16, theme)
				else:
					Tiles._grass(p, 2)
				p.call(4, 2, 8, 9, "#2f7a3a")
				p.call(3, 4, 10, 6, "#2f7a3a")
				p.call(5, 3, 5, 4, "#4aa050")
				p.call(6, 4, 2, 2, "#70c068")
				p.call(7, 11, 2, 4, "#7a5a32"))
		"R":
			var bg: String = theme if above in ["x", "g", "_", "|"] else Tiles.GRASS
			return Tiles._make("fx_rock" + bg, func(p: Callable):
				p.call(0, 0, 16, 16, bg)
				p.call(2, 4, 12, 10, "#706860")
				p.call(3, 3, 10, 10, "#968e84")
				p.call(4, 4, 4, 3, "#b8b0a4")
				p.call(7, 6, 1, 5, "#504840")
				p.call(8, 9, 3, 1, "#504840")
				p.call(5, 8, 2, 1, "#504840"))
		"O":
			return Tiles._make("fx_boulder", func(p: Callable):
				p.call(0, 0, 16, 16, "#a89878")
				p.call(1, 2, 14, 13, "#5c544c")
				p.call(2, 1, 12, 13, "#7c746a")
				p.call(3, 2, 6, 4, "#a8a094")
				p.call(4, 3, 2, 1, "#d0c8bc"))
		"W":
			return Tiles._make("fx_fall%d" % (frame % 2), func(p: Callable):
				p.call(0, 0, 16, 16, "#4a88d8")
				for i in 5:
					var cx := i * 4 + (frame % 2) * 2
					p.call(cx % 16, 0, 1, 16, "#a8d8f8")
				p.call(0, (frame % 2) * 8, 16, 1, "#e8f8ff"))
		"D":
			return Tiles._make("fx_deep%d" % (frame % 2), func(p: Callable):
				p.call(0, 0, 16, 16, "#3060b8")
				var o := 3 if frame % 2 else 0
				p.call((3 + o) % 16, 5, 4, 1, "#5888d8")
				p.call((9 + o) % 16, 11, 4, 1, "#5888d8"))
		"s":
			return Tiles._make("fx_soil", func(p: Callable):
				Tiles._grass(p, 0)
				p.call(2, 3, 12, 11, "#7a5230")
				p.call(3, 4, 10, 9, "#946640")
				p.call(4, 6, 2, 1, "#6a4428")
				p.call(9, 9, 3, 1, "#6a4428"))
		"g":
			return Tiles._make("fx_cave%d" % v, func(p: Callable):
				p.call(0, 0, 16, 16, "#a88c68")
				p.call((v * 5) % 13, (v * 3) % 13, 2, 1, "#8c7254")
				p.call((v * 9) % 13 + 1, (v * 7) % 12 + 2, 1, 1, "#c0a682"))
		"x":
			return Tiles._make("fx_wall%d" % ((x + y) % 2), func(p: Callable):
				p.call(0, 0, 16, 16, "#5a4632")
				p.call(0, 0, 16, 3, "#6e5840")
				p.call(2 + (x + y) % 2 * 6, 6, 5, 3, "#4a3826")
				p.call(9 - (x + y) % 2 * 6, 11, 4, 2, "#4a3826"))
		"y":
			return Tiles._make("fx_mouth", func(p: Callable):
				p.call(0, 0, 16, 16, "#5a4632")
				p.call(2, 3, 12, 13, "#181010")
				p.call(4, 1, 8, 4, "#181010")
				p.call(3, 13, 10, 3, "#302018"))
		"a":
			return Tiles._make("fx_sand%d" % v, func(p: Callable):
				p.call(0, 0, 16, 16, "#e8d498")
				p.call((v * 5) % 13, (v * 3) % 13 + 1, 2, 1, "#d4bc7c")
				p.call((v * 9) % 13 + 1, (v * 7) % 12 + 2, 1, 1, "#f8ecc0"))
		"i":
			return Tiles._make("fx_roof%d" % (1 if above == "i" else 0), func(p: Callable):
				p.call(0, 0, 16, 16, "#8858b8")
				for r in [3, 8, 13]:
					p.call(0, r, 16, 1, "#683c98")
				if above != "i":
					p.call(0, 0, 16, 2, "#b088e0"))
		"d":
			return Tiles.tile_texture("h", x, y, frame, above, "", theme)
		"z":
			return Tiles._make("fx_base", func(p: Callable):
				var tree: Texture2D = Tiles.tile_texture("#", 0, 0, 0)
				var img := tree.get_image()
				for yy in 16:
					for xx in 16:
						p.call(xx, yy, 1, 1, img.get_pixel(xx, yy))
				p.call(6, 11, 4, 5, "#2a1c10"))
		"Q":
			return Tiles._make("fx_pc", func(p: Callable):
				p.call(0, 0, 16, 16, theme)
				p.call(3, 2, 10, 12, "#606878")
				p.call(4, 3, 8, 6, "#78c8f0")
				p.call(5, 11, 6, 2, "#303840"))
		"Y":
			return Tiles._make("fx_slots%d" % (frame % 2), func(p: Callable):
				p.call(0, 0, 16, 16, theme)
				p.call(2, 1, 12, 15, "#802030")
				p.call(3, 2, 10, 13, "#c03848")
				p.call(4, 4, 8, 5, "#f8f8f0")
				p.call(5, 5, 2, 3, "#e03030" if frame % 2 else "#303030")
				p.call(9, 5, 2, 3, "#303030" if frame % 2 else "#e03030")
				p.call(4, 11, 8, 2, "#f8d040")
				p.call(13, 3, 2, 1, "#c0c0c0")
				p.call(14, 2, 1, 4, "#c0c0c0"))
		"N":
			return Tiles._make("fx_tv%d%s" % [frame % 2, theme], func(p: Callable):
				p.call(0, 0, 16, 16, theme)
				p.call(3, 12, 10, 4, "#7a5a32")
				p.call(1, 2, 14, 11, "#383840")
				p.call(2, 3, 12, 8, "#78b8e8" if frame % 2 else "#88c8f0")
				p.call(3, 4, 4, 2, "#d8f0ff")
				p.call(12, 11, 1, 1, "#f04040"))
		"G":
			return Tiles._make("fx_easel" + theme, func(p: Callable):
				p.call(0, 0, 16, 16, theme)
				p.call(3, 12, 1, 4, "#7a5a32")
				p.call(12, 12, 1, 4, "#7a5a32")
				p.call(1, 1, 14, 12, "#c09838")
				p.call(2, 2, 12, 10, "#f0e8d0")
				p.call(4, 5, 8, 5, "#a8b8c8")
				p.call(6, 4, 4, 3, "#c8d0d8"))
		"Z":
			return Tiles._make("fx_braille%d" % ((x * 3 + y) % 3), func(p: Callable):
				p.call(0, 0, 16, 16, "#5a4632")
				p.call(1, 2, 14, 12, "#6e5840")
				for i in 6:
					if (x * 5 + y * 3 + i * 7) % 3 != 0:
						p.call(3 + (i % 2) * 3 + (i / 2 % 2) * 6, 4 + (i / 2) * 3, 2, 2, "#d8c8a0"))
	return Tiles.tile_texture(ch, x, y, frame, above, "", theme)

## A Capture Orb lying on the ground (an item to pick up).
static func item_orb() -> Texture2D:
	return Tiles._make("fx_item", func(p: Callable):
		p.call(5, 6, 6, 7, "#205860")
		p.call(4, 7, 8, 5, "#205860")
		p.call(5, 7, 6, 5, "#e04848")
		p.call(5, 10, 6, 2, "#f8f8f8")
		p.call(5, 9, 6, 1, "#303030")
		p.call(7, 9, 2, 1, "#f8f8f8")
		p.call(6, 7, 1, 1, "#f8b0b0"))

## A berry plant at growth stage 0 (planted) to 4 (ready to pick). color: the berry's color.
static func berry_plant(stage: int, color: String) -> Texture2D:
	return Tiles._make("fx_berry%d%s" % [stage, color], func(p: Callable):
		if stage == 0:
			p.call(7, 9, 2, 2, "#6a4428")
			return
		p.call(7, 15 - stage * 3, 2, stage * 3, "#3c7a30")
		if stage >= 2:
			p.call(4, 12 - stage * 2, 8, 3, "#4aa040")
		if stage >= 3:
			p.call(3, 7, 10, 4, "#58b048")
		if stage >= 4:
			for b in [[4, 6], [10, 6], [7, 4], [6, 9], [11, 9]]:
				p.call(b[0], b[1], 2, 2, color))

## A Secret Base decoration, drawn as a small block in its color.
static func decoration(id: String, color: String) -> Texture2D:
	return Tiles._make("fx_deco_" + id, func(p: Callable):
		p.call(2, 4, 12, 10, Color(color).darkened(0.35))
		p.call(3, 3, 10, 10, color)
		p.call(4, 4, 4, 2, Color(color).lightened(0.4)))
