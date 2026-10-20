extends SceneTree
## Art preview: a grid of creature sprites (front / back / shiny for every 5th species), silhouettes and tiles,
## then a page of trainers. Same layout as the TS reference page, for side-by-side comparison.
## Usage: xvfb-run -a godot --path . --rendering-driver opengl3 -s res://tests/art_preview.gd -- <out_dir> [tile_cases.json]
## Saves <out_dir>/preview.png (1200x1000, 1x) and <out_dir>/trainers.png (720x480, 3x).

var node := Node2D.new()
var page := "grid"
var cases: Array = []

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "/tmp/claude-0/shots/gd_art"
	DirAccess.make_dir_recursive_absolute(out)
	if args.size() > 1:
		cases = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	else:
		for ch in ".,=F~#vSrpbknw_|oehlmju?":
			for x in 4:
				cases.append([ch, x, 0, x % 2, "", "", "#d8d0c0"])
	node.draw.connect(_draw_page)
	root.add_child(node)
	await process_frame
	root.content_scale_size = Vector2i(1200, 1000)
	DisplayServer.window_set_size(Vector2i(1200, 1000))
	root.size = Vector2i(1200, 1000)
	node.queue_redraw()
	for i in 4:
		await process_frame
	root.get_texture().get_image().save_png(out + "/preview.png")
	page = "trainers"
	root.content_scale_size = Vector2i(240, 160)
	DisplayServer.window_set_size(Vector2i(720, 480))
	root.size = Vector2i(720, 480)
	node.queue_redraw()
	for i in 4:
		await process_frame
	root.get_texture().get_image().save_png(out + "/trainers.png")
	node.queue_free()
	await process_frame
	CreatureArt.clear_cache()
	Tiles.clear_cache()
	quit()

func _draw_page() -> void:
	Gfx.ci = node
	var db = root.get_node("DB")
	if page == "grid":
		Gfx.rect(0, 0, 1200, 1000, "#a0a8b8")
		var ids: Array = db.SPECIES.keys()
		ids.sort_custom(func(a, b): return db.SPECIES[a].dex < db.SPECIES[b].dex)
		for i in 40:
			var id: String = ids[i * 5]
			var x0 := (i % 5) * 204
			var y0 := (i / 5) * 66
			Gfx.image(CreatureArt.creature_sprite(id, false, false), x0, y0)
			Gfx.image(CreatureArt.creature_sprite(id, false, true), x0 + 66, y0)
			Gfx.image(CreatureArt.creature_sprite(id, true, false), x0 + 132, y0)
		Gfx.image(CreatureArt.silhouette(CreatureArt.creature_sprite(ids[3]), "#ffffff"), 1030, 0)
		Gfx.image(CreatureArt.silhouette(CreatureArt.creature_sprite(ids[3]), "#303040"), 1100, 0)
		for i in cases.size():
			var c: Array = cases[i]
			var tex := Tiles.tile_texture(c[0], int(c[1]), int(c[2]), int(c[3]), c[4], c[5], c[6])
			Gfx.image(tex, (i % 36) * 33, 540 + (i / 36) * 33, {"scale": 2.0})
	else:
		Gfx.rect(0, 0, 240, 160, "#a0a8b8")
		var names: Array = db.PALETTES.keys()
		var dirs := ["down", "up", "left", "right"]
		for i in names.size():
			for d in 4:
				TrainerArt.draw_char((i % 9) * 26 + (d % 2) * 12, (i / 9) * 35 + 3 + (d / 2) * 17, dirs[d], d % 3, db.PALETTES[names[i]])
		TrainerArt.draw_trainer_big(0, 106, db.PALETTES.p1, false)
		TrainerArt.draw_trainer_big(50, 106, db.PALETTES.rival, true)
		TrainerArt.draw_trainer_big(100, 106, db.PALETTES.gymWater, false)
