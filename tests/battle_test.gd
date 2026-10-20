extends SceneTree
## Battle / menu driver. Sets up a scenario, then runs drive.gd-style steps and saves screenshots.
## Usage: xvfb-run -a godot --path . --rendering-driver opengl3 -s res://tests/battle_test.gd -- <out_dir> <scenario> <steps...>
## Scenarios: solo_wild, solo_trainer, coop_wild, solo_menus (overworld-free menu tests: no battle, empty stack)
## Steps: key:<KEY>[:frames], wait:<frames>, shot:<name>, open:party|bag|shop|storage|summary|evolve|learn

var C := {}

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
	C.GameState = load("res://scripts/game/game_state.gd")
	C.Creatures = load("res://scripts/engine/creature.gd")
	C.Menus = load("res://scripts/game/menus.gd")
	C.BattleScene = load("res://scripts/game/battle_scene.gd")
	C.StorageScreen = load("res://scripts/game/storage_screen.gd")
	C.SummaryScreen = load("res://scripts/game/summary_screen.gd")
	C.EvolutionScene = load("res://scripts/game/evolution_scene.gd")
	C.Gfx = load("res://scripts/core/gfx.gd")
	_setup(game, args[1])
	for step in args.slice(2):
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
			"open":
				_open(game, rest)
			"stack":
				print("stack: ", game.stack.map(func(s): return s.get_script().get_global_name() if s.get_script().get_global_name() != "" else str(s)))
	quit()

func _setup(game, scenario: String) -> void:
	match scenario:
		"solo_wild", "solo_menus", "solo_trainer", "solo_levelup", "solo_lose":
			game.gs = C.GameState.new_game("solo", ["sproutle"])
			game.input.coop = false
			var p: Array = game.gs.players[0].party
			p[0] = C.Creatures.create_creature("sproutle", 15, {"owner": 0, "otId": game.gs.players[0].otId})
			p.append(C.Creatures.create_creature("cindercub", 12, {"owner": 0}))
			p[1].hp = 0
			p.append(C.Creatures.create_creature("voltick", 10, {"owner": 0}))
			p[2].status = "par"
			game.gs.bag.superPotion = 2
			game.gs.bag.antidote = 1
			if scenario == "solo_lose":
				p[0].hp = 1
				p[2].hp = 1
			if scenario == "solo_levelup":
				p[0].exp = C.Creatures.exp_for_level("mediumSlow", 16) - 1
		"coop_wild":
			game.gs = C.GameState.new_game("coop", ["sproutle", "cindercub"])
			game.input.coop = true
	game.replace(C.Menus.FnScene.new(func() -> void: C.Gfx.rect(0, 0, 240, 160, "#000000")))
	var on_end := func(result: String, battle) -> void:
		print("BATTLE END: ", result, " caught=", battle.caught.size(), " money=", game.gs.money)
		game.pop()
	match scenario:
		"solo_wild", "solo_levelup":
			game.push(C.BattleScene.new({"kind": "wild", "double": false, "wild": [C.Creatures.create_creature("nibbit", 4)], "onEnd": on_end}))
		"coop_wild":
			game.push(C.BattleScene.new({"kind": "wild", "double": true, "wild": [C.Creatures.create_creature("nibbit", 3), C.Creatures.create_creature("chirpling", 3)], "onEnd": on_end}))
		"solo_lose":
			game.push(C.BattleScene.new({"kind": "wild", "double": false, "wild": [C.Creatures.create_creature("infernox", 60)], "onEnd": on_end}))
		"solo_trainer":
			var t := {"id": "t1", "name": "Hiker Ben", "palette": "hiker", "pay": 20, "defeat": "Whoa, you're tough!", "party": [["pebblin", 6]]}
			game.push(C.BattleScene.new({"kind": "trainer", "double": false, "trainer": t, "trainerParty": [C.Creatures.create_creature("pebblin", 6)], "onEnd": on_end}))

func _open(game, what: String) -> void:
	var noop := func() -> void: pass
	match what:
		"party": C.Menus.open_party_menu(0, noop)
		"bag": C.Menus.open_bag_overworld(0, noop)
		"shop": C.Menus.open_shop(0, noop)
		"storage":
			game.gs.box.append(C.Creatures.create_creature("nibbit", 5))
			var ref := {}
			ref.s = C.StorageScreen.new(0, func() -> void: game.pop(ref.s))
			game.push(ref.s)
		"summary":
			var ref := {}
			ref.s = C.SummaryScreen.new(game.gs.players[0].party[0], 0, func() -> void: game.pop(ref.s))
			game.push(ref.s)
		"evolve":
			C.EvolutionScene.new(game.gs.players[0].party[0], "thornvale", 0, func() -> void: print("EVOLVED: ", game.gs.players[0].party[0].species))
		"learn":
			var m: Dictionary = game.gs.players[0].party[0]
			while m.moves.size() < 4:
				m.moves.append(C.Creatures.move_slot("tackle" if m.moves.size() == 0 else ["growl", "absorb", "leechSeed"][m.moves.size() - 1]))
			C.Menus.learn_move_flow(m, "razorLeaf", 0, func() -> void: print("LEARN DONE: ", m.moves.map(func(x): return x.id)))

func _key(code: int, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = down
	Input.parse_input_event(ev)
