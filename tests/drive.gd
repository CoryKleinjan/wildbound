extends SceneTree
## Drives the real game for testing: presses keys, runs expressions and saves screenshots.
## Usage: xvfb-run -a godot --path . --rendering-driver opengl3 -s res://tests/drive.gd -- <out_dir> <steps...>
## Steps: key:<KEYNAME>[:frames]   press a key (physical, e.g. key:F, key:W:20 holds 20 frames)
##        wait:<frames>            let the game run
##        shot:<name>              save <out_dir>/<name>.png
##        eval:<expr>              evaluate a GDScript expression with Game and DB in scope; result is printed
##        print:<expr>             same as eval
## Errors raised by the game show up on stderr as SCRIPT ERROR lines.

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	Engine.max_fps = 60
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 3:
		await process_frame
	var game = root.get_node("Game")
	var db = root.get_node("DB")
	for step in args.slice(1):
		var parts: PackedStringArray = step.split(":", true, 1)
		var cmd := parts[0]
		var rest := parts[1] if parts.size() > 1 else ""
		match cmd:
			"key":
				var kp := rest.split(":")
				var code := OS.find_keycode_from_string(kp[0])
				var frames := int(kp[1]) if kp.size() > 1 else 4
				_key(code, true)
				for i in frames:
					await process_frame
				_key(code, false)
				for i in 4:
					await process_frame
			"wait":
				for i in int(rest):
					await process_frame
			"shot":
				root.get_texture().get_image().save_png("%s/%s.png" % [out, rest])
			"eval", "print":
				var e := Expression.new()
				if e.parse(rest, ["Game", "DB"]) != OK:
					print("PARSE ERROR: ", e.get_error_text(), " in ", rest)
				else:
					var r = e.execute([game, db], null, true)
					if e.has_execute_failed():
						print("EXEC ERROR: ", e.get_error_text(), " in ", rest)
					else:
						print("=> ", r)
	quit()

func _key(code: int, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = down
	Input.parse_input_event(ev)
