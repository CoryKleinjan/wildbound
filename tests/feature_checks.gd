extends RefCounted
## The checks behind tests/feature_test.gd. Loaded at runtime, after the autoloads exist.

var failures := 0

func check(name: String, cond: bool, extra: String = "") -> void:
	if not cond:
		failures += 1
		print("FAIL %s %s" % [name, extra])
	else:
		print("ok   %s" % name)

## Answers the dialogs on top of the stack: choice for questions, OK for messages. Returns every line shown.
func _drain(choice: int = 0, max_steps: int = 40) -> Array:
	var lines: Array = []
	for i in max_steps:
		var top = Game.top
		if not (top is Dialog):
			break
		for page in top._lines:
			lines.append(" ".join(page))
		var o: Dictionary = top._o
		Game.pop(top)
		if o.get("choices", []).size():
			if o.has("on_choice"):
				o.on_choice.call(choice)
		elif o.has("on_done") and (o.on_done as Callable).is_valid():
			o.on_done.call()
	return lines

## Runs the game loop for a while (fades, walking, scripts).
func _tick(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		Game.update(1.0 / 60.0)
		t += 1.0 / 60.0

func _mon(sp: String, level: int, moves: Array = []) -> Dictionary:
	var m: Dictionary = Creatures.create_creature(sp, level, {"owner": 0, "otId": Game.gs.players[0].otId})
	if not moves.is_empty():
		m.moves = moves.map(func(id: String) -> Dictionary: return Creatures.move_slot(id))
	return m

func _new_world(map_id: String, x: int, y: int, dir: String) -> OverworldScene:
	Game.gs = GameState.new_game("solo")
	Game.gs.flags.starter = true
	Game.gs.flags.intro_mom = true
	Game.gs.players[0].party.append(_mon("sproutle", 30, ["cut", "surf", "rockSmash", "secretPower"]))
	Game.gs.map = map_id
	Game.gs.x = x
	Game.gs.y = y
	Game.gs.dir = dir
	var ow := OverworldScene.new()
	Game.replace(ow)
	_tick(0.1)
	_drain()
	return ow

func _place(ow: OverworldScene, x: int, y: int, dir: String) -> void:
	ow.player.x = x
	ow.player.y = y
	ow.player.dir = dir
	ow.player.move = null
	Game.gs.x = x
	Game.gs.y = y

func run() -> void:
	_evolution_tests()
	_save_migration_test()
	_field_tests()
	_daycare_tests()
	_item_tests()
	_bag_close_tests()
	_misc_tests()
	_rest_of_emerald_tests()
	_frontier_tests()

func _evolution_tests() -> void:
	Game.gs = GameState.new_game("solo")
	var f := _mon("flintail", 10)
	check("stone evolution", Creatures.pending_evolution(f, "fireStone") == "forgecrest" and Creatures.pending_evolution(f) == null)
	var n := _mon("nibbit", 10)
	n.friendship = 100
	var before = Creatures.pending_evolution(n)
	n.friendship = 230
	check("friendship evolution", before == null and Creatures.pending_evolution(n) == "gnawlord")
	var j := _mon("joltfang", 10)
	check("trade evolution", Creatures.pending_evolution(j, "trade") == "kiloclaw")
	j.item = "everstone"
	check("everstone stops trade evolution", Creatures.pending_evolution(j, "trade") == null)
	var lv := _mon("sproutle", 40)
	lv.item = "everstone"
	check("everstone stops level evolution", Creatures.pending_evolution(lv) == null)
	var f0: int = n.friendship
	Creatures.gain_exp(n, Creatures.exp_for_level(DB.species("nibbit").growth, 11) - int(n.exp))
	check("level up raises friendship", int(n.friendship) > f0)

func _save_migration_test() -> void:
	GameState.SAVE_PATH = "user://feature-test-save.json"
	var old := GameState.new_game("solo")
	for k in ["daycare", "berries", "repel", "bike", "safari", "secretBase", "decor", "bp", "tower", "roamers", "steps", "rematch", "fly", "contest"]:
		old.erase(k)
	var m := Creatures.create_creature("sproutle", 8)
	for k in ["item", "friendship", "ball", "metLevel", "egg", "eggSteps", "ribbons", "condition"]:
		m.erase(k)
	old.players[0].party.append(m)
	var f := FileAccess.open(GameState.SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(old))
	f.close()
	var gs: Dictionary = GameState.load_game()
	var lm: Dictionary = gs.players[0].party[0]
	check("old save gets new fields", gs.has("daycare") and gs.has("tower") and gs.fly.has("fernhollow"))
	check("old creature gets new fields", lm.has("item") and lm.item == null and int(lm.friendship) == 70 and lm.egg == false)
	DirAccess.remove_absolute(GameState.SAVE_PATH)

func _field_tests() -> void:
	var r3: Dictionary = DB.MAPS.route3
	# Item ball lying on the route.
	var item: Dictionary = r3.items.filter(func(i: Dictionary) -> bool: return not i.hidden)[0]
	var ow := _new_world("route3", item.x, item.y + 1, "up")
	if not ow._walkable(item.x, item.y + 1):
		_place(ow, item.x, item.y - 1, "down")
	var had: int = Game.gs.bag.get(item.item, 0)
	check("item blocks its tile", not ow._walkable(item.x, item.y))
	ow._interact()
	_drain()
	check("pick up item", Game.gs.bag.get(item.item, 0) == had + int(item.count) and Game.gs.flags.get(item.id, false))
	check("picked item no longer blocks", ow._walkable(item.x, item.y))

	# Cut tree.
	var cut := _find(r3, "T")
	_place(ow, cut.x, cut.y + 1, "up")
	if not ow._walkable(cut.x, cut.y + 1, true):
		_place(ow, cut.x - 1, cut.y, "right")
	Game.gs.flags.badge1 = true
	ow._interact()
	_drain(0)
	check("cut a tree", Field.tile(ow, cut.x, cut.y) == "." and ow._walkable(cut.x, cut.y))

	# Berry tree that starts grown.
	var bk: String = r3.berries.keys()[0]
	var bp := bk.split(",")
	var bx := int(bp[0])
	var by := int(bp[1])
	var berry: String = r3.berries[bk]
	_place(ow, bx, by + 1, "up")
	var b0: int = Game.gs.bag.get(berry, 0)
	ow._interact()
	_drain(0)
	check("pick berries", Game.gs.bag.get(berry, 0) >= b0 + 2, str(Game.gs.bag.get(berry, 0)))
	ow._interact()
	_drain(0)
	# The bag opens on the berry pocket: pick the first berry.
	if Game.top is Menus.PocketSwitch:
		Game.stack[Game.stack.size() - 2]._o.on_select.call(0)
	_drain()
	var e: Dictionary = Game.gs.berries.route3[bk]
	check("plant a berry", e.get("berry", null) != null and Field.berry_stage(e) == 0)
	e.t = Options.now() - 3600 * 100
	check("berry grows with the clock", Field.berry_stage(e) == 4)

	# Secret Base.
	var sp: String = r3.secretSpots[0]
	var sx := int(sp.split(",")[0])
	var sy := int(sp.split(",")[1])
	_place(ow, sx, sy + 1, "up")
	ow._interact()
	_drain(0)
	_tick(0.8)
	check("make a secret base", Game.gs.secretBase != null and Game.gs.secretBase.map == "route3" and ow.map.id == "secretbase")
	Game.gs.decor.append("decoDesk")
	SecretBase.open_pc(ow)
	_drain(0)
	if Game.top is ListMenu:
		Game.top._o.on_select.call(0)
	_drain()
	check("place a decoration", Game.gs.secretBase.decor.size() == 1)

	# Surf.
	var w := _find(r3, "~")
	ow = _new_world("route3", w.x - 1, w.y, "right")
	if not ow._walkable(w.x - 1, w.y, true):
		_place(ow, w.x, w.y + 1, "up")
		w = Vector2i(w.x, w.y)
	Game.gs.flags.badge5 = true
	ow._interact()
	_drain(0)
	_tick(0.5)
	check("surf", Game.gs.surfing and Maps.tile_at(ow.map, ow.player.x, ow.player.y) == "~", "%s at %d,%d" % [Game.gs.get("surfing"), ow.player.x, ow.player.y])

	# Boulder push with Strength.
	var cave: Dictionary = DB.MAPS.granitecave
	var bo := _find(cave, "O")
	ow = _new_world("granitecave", 13, 15, "up")
	var from := Vector2i(-1, -1)
	var dir := ""
	for d in OverworldScene.DX:
		var v: Vector2i = OverworldScene.DX[d]
		var stand := bo - v
		var beyond := bo + v
		if Maps.WALKABLE.has(Maps.tile_at(cave, stand.x, stand.y)) and Maps.WALKABLE.has(Maps.tile_at(cave, beyond.x, beyond.y)):
			from = stand
			dir = d
			break
	if dir == "":
		check("boulder can be pushed", false, "no side to push from")
	else:
		ow.field.strength = true
		_place(ow, from.x, from.y, dir)
		var moved := Field.on_bump(ow, dir, bo.x, bo.y)
		var v2: Vector2i = OverworldScene.DX[dir]
		check("push a boulder", moved and Field.tile(ow, bo.x + v2.x, bo.y + v2.y) == "O" and Field.tile(ow, bo.x, bo.y) == "g")
	check("dark cave", cave.get("dark", false))

	# Fly to a visited town.
	ow = _new_world("route3", 20, 10, "down")
	Game.gs.fly.append("stonecrest")
	Field.fly_to(ow, "stonecrest")
	_tick(0.8)
	check("fly", ow.map.id == "stonecrest" and Maps.WALKABLE.has(Maps.tile_at(ow.map, ow.player.x, ow.player.y)))

	# Repel keeps weak creatures away.
	Game.gs.repel = 50
	check("repel", Field.repelled(5) and not Field.repelled(40))
	Game.gs.repel = 0

	# Rematches.
	var t: Dictionary = DB.MAPS.route3.trainers[0]
	Game.gs.flags[t.id] = true
	for i in 3:
		Field._ready_rematch(Game.gs)
	check("trainer wants a rematch", Field.rematch_ready(Game.gs, t) and not Field.ready_trainers(Game.gs).is_empty())

	# Dive pairs up with the seafloor.
	var r13: Dictionary = DB.MAPS.route13
	var dv := _find(r13, "D")
	check("dive spot matches seafloor", r13.diveTo == "seafloor" and Maps.tile_at(DB.MAPS.seafloor, dv.x, dv.y) == "D")

func _find(m: Dictionary, ch: String) -> Vector2i:
	for y in m.tiles.size():
		var x: int = (m.tiles[y] as String).find(ch)
		if x >= 0:
			return Vector2i(x, y)
	return Vector2i(-1, -1)

func _daycare_tests() -> void:
	Game.gs = GameState.new_game("solo")
	Game.gs.players[0].party.append(_mon("sproutle", 10))
	# Find a male and a female of one species.
	var male: Dictionary = {}
	var female: Dictionary = {}
	for i in 200:
		var m := _mon("nibbit", 20, ["tackle"])
		if Creatures.gender_of(m) == "M" and male.is_empty():
			male = m
		if Creatures.gender_of(m) == "F" and female.is_empty():
			female = m
	check("breeding compatible", DayCare.compatibility(male, female) > 0 and DayCare.compatibility(male, male) == 0)
	Game.gs.daycare.mons = [female, male]
	female.dcLevel = 20
	male.dcLevel = 20
	var exp0: int = male.exp
	for i in 300:
		DayCare.on_step(Game.gs)
	check("day care gives EXP", int(male.exp) == exp0 + 300)
	var egg := DayCare.make_egg(Game.gs)
	check("egg is the base form", egg.egg and egg.species == DayCare.base_form("nibbit") and Creatures.display_name(egg) == "Egg")
	check("base form of an evolved species", DayCare.base_form("gnawlord") == "nibbit")
	Game.gs.players[0].party.append(egg)
	egg.eggSteps = 1
	var hatched := Eggs.on_step(Game.gs)
	var lines := _drain()
	check("egg hatches", hatched and not egg.egg and lines.size() > 0 and Game.gs.caught.has(egg.species))
	check("eggs can't battle", not Battle.can_battle({"hp": 10, "egg": true}))

## The bag must take all of its scenes off the stack, the pocket switcher too. A switcher left on top of the
## battle swallowed every update, so throwing a Capture Orb froze the game.
func _bag_close_tests() -> void:
	Game.gs = GameState.new_game("solo")
	Game.gs.bag.orb = 3
	var base := Menus.FnScene.new(func() -> void: pass)
	Game.replace(base)
	var picked := []
	Menus.open_bag({"player": 0, "in_battle": true, "can_throw": true, "pocket": 1, "on_close": func() -> void: pass,
		"on_pick": func(id: String, done: Callable) -> void:
			picked.append(id)
			done.call()})
	check("bag opens on top", Game.stack.size() > 1)
	var menu = null
	for sc in Game.stack:
		if sc is ListMenu:
			menu = sc
	menu._o.on_select.call(0)
	check("picking an item closes the whole bag", picked == ["orb"] and Game.stack.size() == 1 and Game.top == base,
		str(Game.stack))
	var closed := [false]
	Menus.open_bag({"player": 0, "in_battle": false, "can_throw": false, "on_close": func() -> void: closed[0] = true,
		"on_pick": func(_id: String, _done: Callable) -> void: pass})
	for sc in Game.stack:
		if sc is ListMenu:
			menu = sc
	menu._o.on_cancel.call()
	check("closing the bag closes the whole bag", closed[0] and Game.stack.size() == 1 and Game.top == base, str(Game.stack))

func _item_tests() -> void:
	Game.gs = GameState.new_game("solo")
	var m := _mon("sproutle", 20, ["tackle"])
	Game.gs.players[0].party.append(m)
	Game.gs.bag.protein = 2
	var atk0: int = Creatures.calc_stats(m).atk
	var r = Menus.use_item_on(Game.gs, "protein", m)
	check("vitamin", r != null and int(m.evs.atk) == 10 and Game.gs.bag.protein == 1 and Creatures.calc_stats(m).atk >= atk0)
	Game.gs.bag.ppUp = 1
	var max0: int = m.moves[0].maxPp
	Menus.use_pp_item(Game.gs, "ppUp", m, 0)
	check("PP Up", int(m.moves[0].maxPp) > max0)
	m.moves[0].pp = 0
	Game.gs.bag.ether = 1
	Menus.use_pp_item(Game.gs, "ether", m, 0)
	check("Ether", int(m.moves[0].pp) == mini(10, int(m.moves[0].maxPp)))
	Game.gs.bag.leftovers = 1
	Menus.give_item(m, "leftovers", 0)
	_drain()
	check("give held item", m.item == "leftovers" and Game.gs.bag.leftovers == 0)
	check("bag pockets", Menus.pocket_of("orb") == "balls" and Menus.pocket_of("tm01") == "tms" and Menus.pocket_of("oranBerry") == "berries" and Menus.pocket_of("bike") == "key")
	check("mart stock grows with badges", Menus.mart_stock(4).has("maxRepel") and not Menus.mart_stock(0).has("maxRepel"))
	check("TM compatibility data", Creatures.can_learn_tm(m, DB.species("sproutle").tms[0]))

func _misc_tests() -> void:
	Game.gs = GameState.new_game("solo")
	var m := _mon("voltick", 12)
	var c := Tower._copy(m)
	check("tower copy is level 50", c.level == 50 and m.level == 12 and c.hp == Creatures.max_hp(c))
	var before: int = m.condition.cool
	Contest.feed(m, {"flavor": [40, 0, 0, 0, 0], "sheen": 20})
	check("treat block raises condition", int(m.condition.cool) > before and int(m.condition.sheen) == 20)
	# Safari Zone battle: bait, rocks and Safari Orbs.
	var wild := Creatures.create_creature("nibbit", 5, {"owner": 9})
	var b := Battle.new({"kind": "safari", "double": false, "rng": Rng.new(3), "sides": [
		[{"name": "P", "party": [_mon("sproutle", 10)], "controller": "human", "slots": [0], "player": 0}],
		[{"name": "Wild", "party": [wild], "controller": "wild", "slots": [0]}]]})
	b.start()
	b.submit({"0:0": {"kind": "bait"}})
	check("safari bait", b.safari.catch < 10 or b.phase == "over")
	var turns := 0
	while b.phase != "over" and turns < 40:
		b.submit({"0:0": {"kind": "item", "itemId": "safariOrb", "target": {"side": 1, "slot": 0}}})
		turns += 1
	check("safari battle ends", b.phase == "over" and (b.result == "ran" or not b.caught.is_empty()))
	check("hidden power", Battle.hidden_power(m).type in Battle.HP_TYPES and Battle.hidden_power(m).power >= 30)
	Options._put("text", "FAST")
	check("options saved", Options.text_speed() > 200.0)
	Options._put("text", "MID")

func _rest_of_emerald_tests() -> void:
	# Region map: every town has a spot, and buildings point at their town.
	var towns_ok := true
	for id in DB.FLY_POINTS:
		if not DB.REGION_MAP.has(id):
			towns_ok = false
	check("region map has every town", towns_ok and DB.REGION_MAP.size() >= 26)
	check("buildings map to their town", TownMapScene.region_id("gym1") == "stonecrest" and TownMapScene.region_id("frontier_dome") == "battlefrontier")
	var ow := _new_world("route3", 12, 16, "down")
	var gs: Dictionary = Game.gs
	# Itemfinder: points toward the buried item, then digs it up underfoot.
	gs.bag.itemfinder = 1
	Field.itemfinder(ow)
	var lines := _drain()
	check("itemfinder points at an item", " ".join(lines).contains("response"), str(lines))
	_place(ow, 12, 17, "down")
	Field.itemfinder(ow)
	_drain()
	check("itemfinder digs it up", gs.bag.get("nugget", 0) == 1)
	# PC item storage.
	gs.pcItems = {"superPotion": 1}
	Pc._withdraw(func() -> void: pass, false)
	(Game.top as ListMenu)._o.on_select.call(0)
	_drain(3)
	check("withdraw from PC", gs.bag.get("superPotion", 0) == 1 and not gs.pcItems.has("superPotion"))
	# Hall of Fame and the Trainer Card.
	HallOfFameScene.record(gs)
	check("hall of fame entry", gs.hallOfFame.size() == 1 and gs.hallOfFame[0].team.size() == 1)
	gs.flags.champion = true
	check("trainer card", TrainerCardScene.stars(gs).size() >= 1 and TrainerCardScene.id_no(gs).length() == 5)
	# Mail: write a letter, then file it in the mailbox.
	var m: Dictionary = gs.players[0].party[0]
	gs.bag.orangeMail = 1
	Mail.give(m, "orangeMail", 0, func() -> void: pass)
	(Game.top as ListMenu)._o.on_select.call(0)
	(Game.top as ListMenu)._o.on_select.call(Mail.WORDS.size() + 1)
	_drain()
	check("mail written", m.item == "orangeMail" and m.mail != null and m.mail.text == "HELLO", str(m.get("mail")))
	Mail.take(m, 0)
	_drain(0)
	check("mail to mailbox", m.item == null and gs.mailbox.size() == 1 and gs.mailbox[0].text == "HELLO")
	# Pokerus spreads in the party and wears off after a few days.
	var m2 := _mon("nibbit", 20)
	gs.players[0].party.append(m2)
	Pokerus.infect(m, 2)
	for i in 40:
		Pokerus.after_battle(gs, gs.players[0].party, [])
	check("pokerus spreads", Pokerus.infected(m2))
	gs.lastDay = Options.today() - 9
	Pokerus.on_step(gs)
	check("pokerus wears off", not Pokerus.infected(m) and Pokerus.ever_had(m))
	# Slot machine: three 7s pay 300 coins.
	gs.coins = 10
	gs.bag.coinCase = 1
	var slots := GameCorner.SlotsScene.new(func() -> void: pass)
	slots._pos = [0.0, 0.0, 0.0]
	slots._payout()
	check("slots jackpot", gs.coins == 310)
	# Lottery: one draw a day.
	Services._lottery()
	_drain()
	Services._lottery()
	check("lottery once a day", " ".join(_drain()).contains("tomorrow"))
	# Mirage Island: hidden water most days; land when one of your creatures matches today's number.
	var target := absi(hash("mirage%d" % Options.today())) % 16
	m.personality = (int(m.personality) & ~0xffff) | target
	check("mirage visible", Field.mirage_visible(gs))
	ow.load_map("route13", 5, 5, "down")
	check("mirage island is land", Field.tile(ow, 24, 4) == "," and ow.map.encounters.size() == 1)
	ow.field.mirage = false
	check("mirage island hidden", Field.tile(ow, 24, 4) == "~")
	# Trick House: prizes after each solved room; rooms have a way through.
	gs.trick.level = 0
	Trick.solved(1)
	Trick.prize(["You solved it!"])
	_drain()
	check("trick house prize", gs.bag.get(DB.TRICK.prizes[0][0], 0) >= 1)
	for i in range(1, 4):
		var pm: Dictionary = DB.MAPS["trickpuzzle%d" % i]
		check("trick puzzle %d exit" % i, pm.tiles[1].contains("X"))
	# Match Call: registered trainers call when they want a rematch.
	gs.bag.naviGear = 1
	var reg := ""
	for mid in DB.MAPS:
		for t in DB.MAPS[mid].get("trainers", []):
			if reg == "" and MatchCall.can_register(t) and absi(hash(t.id)) % 2 == 0:
				reg = t.id
				MatchCall.after_win(gs, t, [])
				gs.flags[t.id] = true
				gs.flags["ready_" + t.id] = true
	MatchCall.queue_ready(gs, reg)
	gs.steps = 15
	var called := false
	for i in 20:
		gs.steps += 1
		if MatchCall.on_step(gs):
			called = " ".join(_drain()).contains("rematch")
			break
	check("match call", gs.matchCall.has(reg) and called)
	check("game corner prizes", DB.PRIZES.creatures.size() == 3 and DB.PRIZES.items.size() > 5)

func _frontier_tests() -> void:
	var ow := _new_world("frontier_pyramid", 7, 9, "up")
	var gs: Dictionary = Game.gs
	gs.flags.champion = true
	var real_party: Array = gs.players[0].party
	gs.bag.potion = 3
	# Pyramid floors: a ladder you can reach, trainers and items.
	var f := Frontier.pyramid_floor(3, 1)
	var start := Vector2i(f.start.x, f.start.y)
	var seen := {start: true}
	var q: Array = [start]
	var ladder := false
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		if Maps.tile_at(f, c.x, c.y) == "y":
			ladder = true
		for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
			var n: Vector2i = c + d
			if not seen.has(n) and Maps.tile_at(f, n.x, n.y) in ["g", "y"]:
				seen[n] = true
				q.append(n)
	check("pyramid ladder reachable", ladder and f.trainers.size() >= 2 and f.items.size() >= 1)
	# Entering swaps in the level-50 team and an empty bag; losing gives them back.
	var team: Array = [Tower._copy(real_party[0])]
	Frontier._pyramid_start(ow, team)
	_drain()
	_tick(1.0)
	check("pyramid entered", gs.pyramid != null and ow.map.id == "pyramidfloor" and gs.players[0].party[0].level == 50 and gs.bag.is_empty())
	Frontier.pyramid_lost(ow)
	_drain()
	check("pyramid lost restores", gs.pyramid == null and gs.players[0].party == real_party and gs.bag.potion == 3 and ow.map.id == "frontier_pyramid")
	# A save made inside the Pyramid loads at the entrance with the real team.
	gs.pyramid = {"floor": 2, "party": real_party, "bag": {"potion": 3}, "run": 9}
	gs.players[0].party = team
	Frontier.restore_after_load(gs)
	check("pyramid save restored", gs.pyramid == null and gs.players[0].party == real_party and gs.map == "frontier_pyramid")
	# Battle Palace: creatures pick their own moves, so no requests come back.
	var p := Battle.new({"kind": "trainer", "double": false, "rng": Rng.new(5), "palace": true, "sides": [
		[{"name": "P", "party": [Tower._copy(_mon("voltick", 30))], "controller": "palace", "slots": [0], "player": 0}],
		[{"name": "F", "party": [Tower._copy(_mon("nibbit", 30))], "controller": "ai", "slots": [0]}]]})
	p.start()
	check("palace needs no input", p.requests().is_empty())
	var turns := 0
	while p.phase != "over" and turns < 60:
		p.submit({})
		turns += 1
	check("palace battle finishes", p.phase == "over")
	# Battle Arena: after three turns the judge decides the match-up.
	var a := Battle.new({"kind": "trainer", "double": false, "rng": Rng.new(5), "arena": true, "sides": [
		[{"name": "P", "party": [_mon("voltick", 30, ["growl"])], "controller": "human", "slots": [0], "player": 0}],
		[{"name": "F", "party": [_mon("nibbit", 30, ["growl"])], "controller": "ai", "slots": [0]}]]})
	a.start()
	for i in 3:
		a.submit({"0:0": {"kind": "move", "moveIdx": 0, "target": {"side": 1, "slot": 0}}})
	check("arena judge decides", a.phase == "over")
	# Factory rentals are level 50.
	check("factory rental", Frontier._rental(DB.TOWER.pool[0]).level == 50)
	# Records and Battle Points.
	gs.bp = 0
	Frontier._won(gs, "dome")
	Frontier._award(gs, "dome", [])
	_drain()
	check("frontier record and BP", int(gs.frontier.dome.best) == 1 and gs.bp >= 5)
