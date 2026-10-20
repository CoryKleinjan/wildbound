extends SceneTree
## Screenshots of the generated art in the real scenes.
## xvfb-run -a godot --path . --rendering-driver opengl3 -s res://tests/art_shot.gd -- <out_dir> [battle|overworld|title] [args...]
## battle <map_id> <mode solo|coop> <foe species...> [vs <own species...>] [trainer <palette>]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 3:
		await process_frame
	var game = root.get_node("Game")
	var what: String = args[1] if args.size() > 1 else "title"
	if what == "title":
		for i in 30:
			await process_frame
	else:
		var map_id: String = args[2]
		var mode: String = args[3]
		var foes: Array = []
		var own: Array = []
		var pal := ""
		var dest := foes
		var i := 4
		while i < args.size():
			if args[i] == "vs":
				dest = own
			elif args[i] == "trainer":
				i += 1
				pal = args[i]
			elif not args[i].is_valid_int():
				dest.append(args[i])
			i += 1
		if own.is_empty():
			own = ["cindercub", "ripplet"] if mode == "coop" else ["cindercub"]
		game.gs = load("res://scripts/game/game_state.gd").new_game(mode, own)
		game.gs.map = map_id
		var spawn := _walkable(root.get_node("DB").MAPS[map_id])
		game.gs.x = spawn.x
		game.gs.y = spawn.y
		var ow = load("res://scripts/game/overworld.gd").new()
		game.replace(ow)
		for k in 10:
			await process_frame
		if what == "overworld":
			await _shot(out + "/overworld_%s.png" % map_id)
			quit()
			return
		var wild: Array = []
		for s in foes:
			wild.append(load("res://scripts/engine/creature.gd").create_creature(s, 30, {"owner": 9}))
		var setup := {"kind": "wild", "double": wild.size() > 1, "wild": wild}
		if pal != "":
			setup = {"kind": "trainer", "double": wild.size() > 1, "trainer": {"id": "t", "name": "Test", "palette": pal, "party": []}, "trainerParty": wild}
		ow._run_battle(setup)
		for k in (int(args[-1]) if args[-1].is_valid_int() else 200):
			await process_frame
		await _shot(out + "/battle_%s_%s.png" % [map_id, "_".join(foes)])
		if pal == "":
			quit()
			return
		for k in 200:
			await process_frame
		await _shot(out + "/battle2_%s_%s.png" % [map_id, "_".join(foes)])
	await _shot(out + "/%s.png" % what)
	quit()

func _walkable(m: Dictionary) -> Vector2i:
	for y in range(m.tiles.size() / 2, m.tiles.size()):
		var row: String = m.tiles[y]
		for x in range(row.length() / 2, row.length()):
			if load("res://scripts/game/maps.gd").WALKABLE.has(row[x]) and row[x] != ",":
				return Vector2i(x, y)
	return Vector2i(1, 1)

func _shot(path: String) -> void:
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
