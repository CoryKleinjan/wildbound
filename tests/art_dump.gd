extends SceneTree
## Generates every creature sprite (front/back x normal/shiny) and a list of tile cases, checks for errors,
## and optionally saves them as PNGs for pixel comparison with the TS build.
## Usage: godot --headless --path . -s res://tests/art_dump.gd -- [out_dir] [tile_cases.json]

func _initialize() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else ""
	var db = root.get_node("DB")
	if out != "":
		DirAccess.make_dir_recursive_absolute(out + "/sprites")
		DirAccess.make_dir_recursive_absolute(out + "/tiles")
	var t0 := Time.get_ticks_msec()
	var count := 0
	for id in db.SPECIES.keys():
		for s in [0, 1]:
			for b in [0, 1]:
				var tex := CreatureArt.creature_sprite(id, s == 1, b == 1)
				assert(tex.get_width() == 64 and tex.get_height() == 64)
				count += 1
				if out != "":
					tex.get_image().save_png("%s/sprites/%s_%d_%d.png" % [out, id, s, b])
	var dt := Time.get_ticks_msec() - t0
	print("sprites: %d in %d ms (%.1f ms each)" % [count, dt, float(dt) / count])
	var sil := CreatureArt.silhouette(CreatureArt.creature_sprite("sproutle"), "#ffffff")
	assert(sil.get_width() == 64)
	print("floating sproutle: ", CreatureArt.is_floating("sproutle"))
	if args.size() > 1:
		var cases: Array = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
		for i in cases.size():
			var c: Array = cases[i]
			var tex := Tiles.tile_texture(c[0], int(c[1]), int(c[2]), int(c[3]), c[4], c[5], c[6])
			if out != "":
				tex.get_image().save_png("%s/tiles/%d.png" % [out, i])
		print("tiles: %d" % cases.size())
	CreatureArt.clear_cache()
	Tiles.clear_cache()
	quit()
