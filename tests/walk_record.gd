extends SceneTree
## Records the player walking, one screenshot a frame, to check the walk animation.
## xvfb-run -a godot --path . --rendering-driver opengl3 --fixed-fps 60 -s res://tests/walk_record.gd -- <out_dir> <map_id> [dir] [steps] [run]
## Prints one line a frame: the frame, the player's screen position and the walk frame shown.

const KEYS := {"up": KEY_W, "down": KEY_S, "left": KEY_A, "right": KEY_D}

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var map_id: String = args[1]
	var dir: String = args[2] if args.size() > 2 else "right"
	var steps: int = int(args[3]) if args.size() > 3 else 4
	var run: bool = args.size() > 4 and args[4] == "run"
	DirAccess.make_dir_recursive_absolute(out)
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 3:
		await process_frame
	var game = root.get_node("Game")
	game.gs = load("res://scripts/game/game_state.gd").new_game("solo", ["cindercub"])
	game.gs.map = map_id
	var spawn := _clear_run(root.get_node("DB").MAPS[map_id], dir, steps + 1)
	game.gs.x = spawn.x
	game.gs.y = spawn.y
	game.gs.dir = dir
	var ow = load("res://scripts/game/overworld.gd").new()
	game.replace(ow)
	for k in 10:
		await process_frame
	var dur: float = ow.RUN if run else ow.WALK
	var frames := int(ceil(steps * dur * 60)) + 2
	if run:
		_key(KEY_X, true)
	_key(KEYS[dir], true)
	for f in frames + 12:
		if f == frames - 4:
			_key(KEYS[dir], false)
		await process_frame
		var ap: Dictionary = ow.actor_pixel(ow.player)
		var step := 0
		if ow.player.move != null and ow.player.move.t / ow.player.move.dur < 0.5:
			step = ow.player.step_count % 2 + 1
		print("frame %d tile %d,%d px %.2f,%.2f step %d" % [f, ow.player.x, ow.player.y, ap.x, ap.y, step])
		root.get_viewport().get_texture().get_image().save_png("%s/f%03d.png" % [out, f])
	_key(KEY_X, false)
	quit()

func _clear_run(m: Dictionary, dir: String, n: int) -> Vector2i:
	var d: Vector2i = {"up": Vector2i(0, -1), "down": Vector2i(0, 1), "left": Vector2i(-1, 0), "right": Vector2i(1, 0)}[dir]
	var walk: Dictionary = load("res://scripts/game/maps.gd").WALKABLE
	var h: int = m.tiles.size()
	for y in range(2, h - 2):
		for x in range(2, (m.tiles[y] as String).length() - 2):
			var ok := true
			for i in n + 1:
				var p := Vector2i(x, y) + d * i
				if p.y < 0 or p.y >= h or p.x < 0 or p.x >= (m.tiles[p.y] as String).length():
					ok = false
					break
				var c: String = (m.tiles[p.y] as String)[p.x]
				if not walk.has(c) or c == "," or m.get("warps", {}).has("%d,%d" % [p.x, p.y]):
					ok = false
					break
			if ok:
				return Vector2i(x, y)
	return Vector2i(1, 1)

func _key(code: int, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = down
	Input.parse_input_event(ev)
