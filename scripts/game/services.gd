class_name Services
## What townsfolk with a "service" do when you talk to them (data/features.json gives each NPC its service):
## the Day Care, contests and the Berry Blender, the Dept. Store counters, the Battle Tower, gifts, Move Tutors,
## the Move Relearner, the friendship checker, the Name Rater, in-game trades and the daily berry, and the rest of
## the townsfolk in TownLife (Move Deleter, Glass Workshop, Quiz Lady, Fan Club, fossils, ...).

static func run(o: OverworldScene, npc: Dictionary, text: Array) -> void:
	var gs: Dictionary = Game.gs
	match npc.service:
		"daycare":
			Game.say(text, func() -> void: DayCare.lady())
		"daycareMan":
			DayCare.man(text)
		"contest":
			Game.say(text, func() -> void: Contest.start(0))
		"blender":
			Game.say(text, func() -> void: Contest.blender(0))
		"shop":
			Game.say(text, func() -> void:
				var done := func() -> void: Game.say(["Please come again!"])
				if npc.shop == "bp":
					Menus.open_bp_shop(0, done)
				else:
					Menus.open_shop(0, done, DB.SHOPS.get(npc.shop, [])))
		"tower":
			Game.say(text, func() -> void: Tower.start(o))
		"gift":
			_gift(npc, text)
		"tutor":
			_tutor(npc, text)
		"friendship":
			Game.say(text, func() -> void: _friendship())
		"relearner":
			Game.say(text, func() -> void: _relearner())
		"nameRater":
			Game.say(text, func() -> void: _name_rater())
		"npcTrade":
			Trade.npc_trade(npc)
		"berryGift":
			Game.say(text, func() -> void: _berry_gift(npc))
		"coins":
			GameCorner.coins_counter(text)
		"prizes":
			GameCorner.prizes(text)
		"lottery":
			Game.say(text, func() -> void: _lottery())
		"berryMaster":
			Game.say(text, func() -> void: _berry_master(npc, 2, 0))
		"berryWife":
			Game.say(text, func() -> void: _berry_master(npc, 1, 24))
		"mirageWatch":
			Game.say(text + (["Oh! I can see it! Mirage Island is out there east of here today!"] if Field.mirage_visible(gs)
				else ["No sign of it today... They say it only shows itself to certain creatures."]))
		"ferry":
			_ferry(o, npc, text)
		"frontier":
			Game.say(text, func() -> void: Frontier.start(o, npc.facility))
		"trickPrize":
			Trick.prize(text)
		"moveDeleter":
			TownLife.move_deleter(text)
		"glass":
			TownLife.glass(text)
		"trendy":
			TownLife.trendy(text)
		"quiz":
			TownLife.quiz(text)
		"fanClub":
			TownLife.fan_club(text)
		"fan":
			TownLife.fan(npc, text)
		"effortRibbon":
			TownLife.effort_ribbon(text)
		"museum":
			Museum.curator(text)
		"nationalDex":
			TownLife.national_dex(text)
		"fossilPick":
			TownLife.fossil_pick(text)
		"fossilLab":
			TownLife.fossil_lab(text)
		"tent":
			Game.say(text, func() -> void: BattleTent.start(o, npc.facility))
		"shellBell":
			TownLife.shell_bell(text)
		"ticket":
			Legends.ticket(npc, text)
		_:
			Game.say(text)

static func _gift(npc: Dictionary, text: Array) -> void:
	var gs: Dictionary = Game.gs
	if gs.flags.get(npc.flag, false):
		Game.say(npc.get("after", text))
		return
	Game.say(text, func() -> void:
		var id: String = npc.gift
		gs.flags[npc.flag] = true
		gs.bag[id] = gs.bag.get(id, 0) + 1
		Audio.sfx("item")
		var lines: Array = ["%s received the %s!" % [gs.players[0].name, DB.item(id).name]]
		lines.append_array(npc.get("after", []))
		Game.say(lines))

## The Lottery Corner: one draw a day, matched against the ID No. of every creature you have.
static func _lottery() -> void:
	var gs: Dictionary = Game.gs
	var today := Options.today()
	if int(gs.flags.get("lottery_day", -1)) == today:
		Game.say(["You've already drawn today. Please come back tomorrow!"])
		return
	gs.flags.lottery_day = today
	var draw := absi(hash("lottery%d" % today)) % 65536
	var number := "%05d" % draw
	var best := 0
	var best_mon: Variant = null
	for m in gs.players[0].party + gs.box:
		if m.get("egg", false):
			continue
		var id := "%05d" % (int(m.otId) % 65536)
		var n := 0
		while n < 5 and id[4 - n] == number[4 - n]:
			n += 1
		if n > best:
			best = n
			best_mon = m
	var lines: Array = ["Today's number is %s!" % number]
	if best < 2:
		Game.say(lines + ["I'm sorry, none of your creatures' ID numbers matched. Try again tomorrow!"])
		return
	var prize: String = {2: "ppUp", 3: "expShare", 4: "maxRevive", 5: "masterOrb"}[best]
	gs.bag[prize] = gs.bag.get(prize, 0) + 1
	Audio.sfx("badge" if best >= 4 else "item")
	Game.say(lines + ["%s's ID No. matched the last %d digits!" % [Creatures.display_name(best_mon), best],
		"You won the %s!" % DB.item(prize).name])

## The Berry Master gives n berries a day; his wife gives one rare berry (growing min_hours or longer).
static func _berry_master(npc: Dictionary, n: int, min_hours: int) -> void:
	var gs: Dictionary = Game.gs
	var today := Options.today()
	if int(gs.flags.get(npc.flag, -1)) == today:
		Game.say(["Come back tomorrow and I'll have more!"])
		return
	var pool: Array = DB.ITEMS.keys().filter(func(k: String) -> bool:
		return DB.ITEMS[k].effect.kind == "berry" and int(DB.ITEMS[k].get("growHours", 4)) >= min_hours)
	gs.flags[npc.flag] = today
	var lines: Array = []
	for i in n:
		var id: String = pool[Rng.global_rng.int_below(pool.size())]
		gs.bag[id] = gs.bag.get(id, 0) + 1
		lines.append("%s received one %s!" % [gs.players[0].name, DB.item(id).name])
	Audio.sfx("item")
	Game.say(lines)

## The ferry between Saltmarsh and the Battle Frontier (Champions only).
## With a ticket, it also sails to the event islands.
static func _ferry(o: OverworldScene, npc: Dictionary, text: Array) -> void:
	var stops := Legends.ferry_stops(npc)
	if stops.is_empty():
		Game.say(text + ["Sorry, the Battle Frontier is only open to League Champions."])
		return
	var labels: Array = stops.map(func(id: String) -> String: return DB.MAPS[id].name.to_upper())
	labels.append("CANCEL")
	var q := "%s Shall we set sail for %s?" % [" ".join(text), DB.MAPS[stops[0]].name] if stops.size() == 1 else "%s Where to?" % " ".join(text)
	Game.ask(q, ["YES", "NO"] if stops.size() == 1 else labels, func(c: int) -> void:
		if c >= stops.size():
			return
		var dest: String = stops[c]
		var spot := ferry_landing(dest)
		Audio.sfx("door")
		Game.say(["The ferry sets sail...", "... ... ..."], func() -> void:
			Field._warp(o, dest, spot.x, spot.y, "down", false)))

## Where the ferry lets you off: next to the ferry attendant on that map.
static func ferry_landing(map_id: String) -> Vector2i:
	var m: Dictionary = DB.MAPS[map_id]
	for n in m.get("npcs", []):
		if n.get("service", "") == "ferry":
			return Field.nearest_walkable(m, int(n.x) + 1, int(n.y))
	return Field.nearest_walkable(m, 5, 5)

## Pick a creature from the party (eggs can't be picked). filter(m) -> String: "" if OK, otherwise why not.
static func pick_creature(prompt: String, filter: Callable, on_pick: Callable, on_cancel: Callable = Callable()) -> void:
	var gs: Dictionary = Game.gs
	var party: Array = gs.players[0].party
	var ps := PartyScreen.new({"player": 0, "party": party, "prompt": prompt})
	ps.o.on_cancel = func() -> void:
		Game.pop(ps)
		if on_cancel.is_valid():
			on_cancel.call()
	ps.o.on_select = func(i: int) -> void:
		var m: Dictionary = party[i]
		var why: String = "An Egg can't do that." if m.get("egg", false) else filter.call(m)
		if why != "":
			Game.say([why], Callable(), 0)
			return
		Game.pop(ps)
		on_pick.call(m)
	Game.push(ps)

static func _tutor(npc: Dictionary, text: Array) -> void:
	var gs: Dictionary = Game.gs
	var mv: String = npc.move
	if gs.flags.get(npc.flag, false):
		Game.say(["I've taught you everything I know. Use %s well!" % DB.move(mv).name])
		return
	Game.say(text, func() -> void:
		Game.ask("Shall I teach %s to one of your creatures?" % DB.move(mv).name, ["YES", "NO"], func(c: int) -> void:
			if c != 0:
				return
			pick_creature("Teach which creature?", func(m: Dictionary) -> String:
				if Creatures.knows(m, mv):
					return "%s already knows %s." % [Creatures.display_name(m), DB.move(mv).name]
				return "" if Creatures.can_learn_tutor(m, mv) else "%s can't learn %s." % [Creatures.display_name(m), DB.move(mv).name],
			func(m: Dictionary) -> void:
				Menus.learn_move_flow(m, mv, 0, func() -> void:
					if Creatures.knows(m, mv):
						gs.flags[npc.flag] = true))))

static func _friendship() -> void:
	var m: Variant = Field.lead()
	if m == null:
		return
	var f: int = m.get("friendship", 70)
	var nm := Creatures.display_name(m)
	var line: String
	if f >= 255:
		line = "It looks really happy! It must love you a lot."
	elif f >= 200:
		line = "I get the feeling it really trusts you."
	elif f >= 150:
		line = "It's quite friendly toward you."
	elif f >= 100:
		line = "It's warming up to you."
	elif f >= 50:
		line = "It's not very used to you yet."
	else:
		line = "Hmm... It doesn't seem to like you much. Maybe it needs more kindness."
	Game.say(["Your %s... %s" % [nm, line]])

static func _relearner() -> void:
	var gs: Dictionary = Game.gs
	if gs.bag.get("heartScale", 0) <= 0:
		Game.say(["Bring me a Heart Scale and I'll help a creature remember a move."])
		return
	pick_creature("Which creature should remember a move?", func(m: Dictionary) -> String:
		return "" if not Creatures.relearnable(m).is_empty() else "There's no move %s can remember." % Creatures.display_name(m),
	func(m: Dictionary) -> void:
		var moves: Array = Creatures.relearnable(m)
		var items: Array = []
		for id in moves:
			items.append({"label": DB.move(id).name, "right": DB.move(id).type})
		items.append({"label": "CANCEL"})
		var ref := {}
		var menu := ListMenu.new({
			"x": 80, "y": 8, "w": 156, "player": 0, "title": "Remember which move?", "items": items, "max_visible": 7,
			"footer": func(i: int) -> String: return DB.move(moves[i]).desc if i < moves.size() else "",
			"on_cancel": func() -> void: Game.pop(ref.menu),
			"on_select": func(i: int) -> void:
				Game.pop(ref.menu)
				if i >= moves.size():
					return
				Menus.learn_move_flow(m, moves[i], 0, func() -> void:
					if Creatures.knows(m, moves[i]):
						gs.bag.heartScale -= 1
						Game.say(["%s handed over one Heart Scale in exchange." % gs.players[0].name])),
		})
		ref.menu = menu
		Game.push(menu))

static func _name_rater() -> void:
	var gs: Dictionary = Game.gs
	pick_creature("Rate which creature's nickname?", func(m: Dictionary) -> String:
		return "" if int(m.otId) == int(gs.players[0].otId) else "This one came from another trainer. I can't rename it.",
	func(m: Dictionary) -> void:
		Game.ask("%s, is it? A fine name! Would you like to give it a nicer one?" % Creatures.display_name(m), ["YES", "NO"], func(c: int) -> void:
			if c != 0:
				return
			var ref := {}
			var scene := NameEntryScene.new(0, "%s's nickname?" % DB.species(m.species).name, "boy", Creatures.display_name(m), func(n: String) -> void:
				Game.pop(ref.s)
				m.nickname = n if n != DB.species(m.species).name else null
				Game.say(["%s it is! That's a better name than before! Well done!" % Creatures.display_name(m)]))
			ref.s = scene
			Game.push(scene)))

static func _berry_gift(npc: Dictionary) -> void:
	var gs: Dictionary = Game.gs
	var today := Options.today()
	if int(gs.flags.get(npc.flag, -1)) == today:
		Game.say(["Come back tomorrow for another berry!"])
		return
	var berries: Array = DB.ITEMS.keys().filter(func(k: String) -> bool: return DB.ITEMS[k].effect.kind == "berry")
	var id: String = berries[Rng.global_rng.int_below(berries.size())]
	gs.flags[npc.flag] = today
	gs.bag[id] = gs.bag.get(id, 0) + 1
	Audio.sfx("item")
	Game.say(["%s received one %s!" % [gs.players[0].name, DB.item(id).name], "Plant it in soft soil and it'll grow."])
