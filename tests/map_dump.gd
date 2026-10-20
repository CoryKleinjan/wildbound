extends SceneTree
## Dumps every map as the game builds it (maps.json + interiors + story + features), and a layout image of
## each drawn with the game's own tiles, for tools/artgen/mapart.py and mapfit.py. Run with MAP_FIT=off.
## MAP_FIT=off godot --headless --path . -s res://tests/map_dump.gd -- <out_dir> [map_id ...]

const DYNAMIC := "TRO"

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	await process_frame
	var db = root.get_node("DB")
	var ids: Array = args.slice(1) if args.size() > 1 else db.MAPS.keys()
	var f := FileAccess.open(out.path_join("maps.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(db.MAPS))
	f.close()
	for id in ids:
		_layout(db.MAPS[id]).save_png(out.path_join("%s_layout.png" % id))
	quit()

func _img(tex: Texture2D) -> Image:
	var i := tex.get_image()
	if i.is_compressed():
		i.decompress()
	i.convert(Image.FORMAT_RGBA8)
	return i

func _put(dst: Image, tex: Texture2D, x: int, y: int) -> void:
	if tex == null:
		return
	var i := _img(tex)
	dst.blend_rect(i, Rect2i(Vector2i.ZERO, i.get_size()), Vector2i(x, y))

func _layout(m: Dictionary) -> Image:
	var h: int = m.tiles.size()
	var w: int = m.tiles[0].length()
	var cave: bool = m.get("cave", false)
	var theme: String = m.get("theme", "#d8d0c0")
	var style: Dictionary = m.get("style", {})
	var gen_trees: bool = Tiles.tree_sprite(0, 0) != null and not style.has("treeShape") and not cave
	var img := Image.create(w * 16, h * 16, false, Image.FORMAT_RGBA8)
	img.fill(Color.BLACK)
	var at := func(x: int, y: int) -> String: return Maps.tile_at(m, x, y)
	for y in h:
		for x in w:
			var ch: String = at.call(x, y)
			var tex: Texture2D
			if DYNAMIC.contains(ch):
				ch = "g" if cave else "."
			if ch == "#" and cave:
				ch = "x"
			if FieldTiles.handles(ch):
				tex = FieldTiles.texture(ch, x, y, 0, at.call(x, y - 1), theme)
			elif ch == at.call(x, y):
				tex = TownStyle.apply(Tiles.map_tile(m, x, y, 0, theme), "." if ch == "#" and gen_trees else ch, style)
			else:
				tex = TownStyle.apply(Tiles.tile_texture(ch, x, y, 0, at.call(x, y - 1), at.call(x, y + 1), theme), ch, style)
			_put(img, tex, x * 16, y * 16)
	if gen_trees:
		for y in h + 1:
			for x in range(-1, w + 1):
				if at.call(x, y) == "#":
					_put(img, TownStyle.apply(Tiles.tree_sprite(x, y), "#", style), x * 16 - 8, y * 16 - 16)
	for b in Tiles.buildings(m):
		var r: Rect2i = b.rect
		var btex := ArtAssets.texture("buildings/%s_%dx%d" % [b.kind, r.size.x, r.size.y])
		if btex == null:
			btex = ArtAssets.texture("buildings/" + b.kind)
		if btex == null:
			continue
		var bi := _img(TownStyle.apply(btex, b.roof, style))
		bi.resize(r.size.x * 16, r.size.y * 16, Image.INTERPOLATE_NEAREST)
		img.blend_rect(bi, Rect2i(Vector2i.ZERO, bi.get_size()), r.position * 16)
		for d in b.doors:
			_put(img, TownStyle.apply(Tiles.tile_texture(d[2], d[0], d[1], 0), d[2], style), d[0] * 16, d[1] * 16)
	return img
