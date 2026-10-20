class_name Story
## Scripted story events: the opening in Fernhollow, the Route 1 starter rescue, the first
## rival battle and the ending. The rest of the story (Hollow Order trainers, town NPCs and
## Kai's lines) is data in data/story.json, built by tools/build_story.py.

static func player_names(gs: Dictionary) -> String:
	var names: Array = []
	for p in gs.players:
		names.append(p.name)
	return " and ".join(names)

## Called whenever the overworld loads a map.
static func on_map_loaded(ow: OverworldScene) -> void:
	var gs: Dictionary = Game.gs
	if ow.map.id == "fernhollow" and not gs.flags.get("intro_mom", false):
		gs.flags.intro_mom = true
		Game.say([
			"MOM: %s! Your first morning in Fernhollow!" % player_names(gs),
			"Prof. Alder stopped by looking for you. He went north to study creatures on Route 1.",
			"Go say hello! But stay out of the tall grass without a creature of your own.",
		])

## Returns true when a story event takes over this step.
static func intercept_move(ow: OverworldScene, dir: String, tx: int, ty: int) -> bool:
	var gs: Dictionary = Game.gs
	# Keyed on the party rather than flags.starter: a friend who joined can have creatures before the host does.
	if ow.map.id == "fernhollow" and dir == "up" and ty < 0 and gs.players[0].party.is_empty():
		_starter_event(ow)
		return true
	return false

# ---------- Route 1: PROF. ALDER's rescue ----------
static func _starter_event(ow: OverworldScene) -> void:
	var gs: Dictionary = Game.gs
	var p := ow.player
	var road_x := 10 if p.x == 11 else 11
	Game.say(["???: H-help! Somebody, help me!"], func() -> void:
		var alder := ow.add_actor(road_x, 0, "down", "prof")
		ow.exclaim(alder)
		p.dir = "left" if road_x < p.x else "right"
		Game.say([
			"PROF. ALDER: Oh, thank goodness, %s! A wild Nibbit chased me right out of the tall grass!" % player_names(gs),
			"It's right behind me! Quick, my bag!",
		], func() -> void:
			Game.push(StarterScene.new(gs.mode == "coop", func(picks: Array) -> void:
				for i in picks.size():
					GameState.give_starter(gs, i, picks[i])
				_rescue_battle(ow, alder)))))

static func _rescue_battle(ow: OverworldScene, alder) -> void:
	var gs: Dictionary = Game.gs
	var wild: Array = []
	for i in gs.players.size():
		wild.append(Creatures.create_creature("nibbit", 2, {"owner": 9}))
	ow.run_battle({"kind": "wild", "double": wild.size() > 1, "wild": wild, "storyEnd": func(_result: String) -> void:
		var names: Array = []
		for pl in gs.players:
			names.append(Creatures.display_name(pl.party[0]))
		gs.bag.orb = gs.bag.get("orb", 0) + 5
		Game.say([
			"PROF. ALDER: Whew... You saved me! You handled that like a natural.",
			"%s seems to like you already. Please, keep it. Consider it a thank-you." % " and ".join(names),
			"%s received %s!" % [player_names(gs), " and ".join(names)],
			"And take these. Capture Orbs, for catching creatures of your own.",
			"%s received 5 Capture Orbs! The Creaturedex was switched on!" % player_names(gs),
		], func() -> void: _kai_arrives(ow, alder))})

static func _kai_arrives(ow: OverworldScene, alder) -> void:
	var gs: Dictionary = Game.gs
	var kai := ow.add_actor(alder.x, maxi(0, alder.y), "down", "rival")
	ow.remove_actor(alder)
	alder = ow.add_actor(ow.player.x + (1 if ow.player.x < 20 else -1), ow.player.y + 1, "up", "prof")
	ow.exclaim(kai)
	var party: Array = [["shadepup", 5]]
	if gs.mode == "coop":
		party.append(["frostkit", 5])
	var trainer := {
		"id": "rival_intro", "name": "Rival Kai", "palette": "rival", "pay": 30, "party": party,
		"intro": "", "defeat": "Huh? I lost? To you?!", "after": "",
	}
	Game.say([
		"KAI: Grandpa! I heard yelling all the way from the lake!",
		"...Oh. Hey, %s. Did Grandpa just give you a creature?" % player_names(gs),
		"No fair! I picked mine out ages ago. Fine, then let's see what yours can do!",
	], func() -> void:
		var mons: Array = []
		for e in party:
			mons.append(Creatures.create_creature(e[0], e[1], {"owner": 9}))
		ow.run_battle({"kind": "trainer", "double": gs.mode == "coop", "trainer": trainer, "trainerParty": mons, "storyEnd": func(result: String) -> void:
			for m in GameState.all_party_mons(gs):
				Creatures.heal_fully(m)
			var first: Array = ["KAI: Not bad... for a first try!"] if result == "win" else ["KAI: Ha! Told you mine was the best!"]
			Game.say(first + [
				"I'm heading north to Stonecrest to win my first Gym badge. Bet I get it before you do!",
			], func() -> void:
				ow.remove_actor(kai)
				Game.say([
					"PROF. ALDER: Ah, that boy. Always in a hurry.",
					"%s, I healed your creatures. The Rest Lodge in town will do the same whenever you need it." % player_names(gs),
					"Eight Gym Leaders guard the road to the League at Summit Crown. Stonecrest's Gym is a good first goal.",
					"And keep your eyes open. I've heard strange rumors about people in grey cloaks...",
				], func() -> void:
					ow.remove_actor(alder)
					gs.flags.starter = true))}))

## A friend who joined with no creatures gets one from PROF. ALDER's bag right away.
static func gift_starter(host_name: String) -> void:
	Game.push(StarterScene.new(false, _on_gift, [
		"PROF. ALDER: Welcome to %s's world! You'll need a partner out there." % host_name,
		"Pick a creature from my bag!",
	]))

static func _on_gift(picks: Array) -> void:
	var gs: Dictionary = Game.gs
	GameState.give_starter(gs, 0, picks[0])
	gs.bag.orb = gs.bag.get("orb", 0) + 5
	Game.say(["PROF. ALDER: And take these 5 Capture Orbs. Good luck out there!"])
	GameState.save(gs)

# ---------- ending ----------
static func epilogue_lines(gs: Dictionary) -> Array:
	return [
		"PROF. ALDER: %s! You did it! The new Champion of Wildbound!" % player_names(gs),
		"KAI: Look up! The sky over Summit Crown is glowing!",
		"High above the League, the Starchime began to ring, a thousand years early.",
		"It didn't ring for the Order's stolen shards. It rang for the bond between you and your creatures.",
		"PROF. ALDER: The Starchime grants one wish. What will it be?",
		"%s wished that people and creatures would always stay free, side by side." % player_names(gs),
	]

static func ending(ow: OverworldScene) -> void:
	var gs: Dictionary = Game.gs
	Game.say(epilogue_lines(gs), func() -> void:
		Game.transition(func() -> void:
			Game.push(EndingScene.new(func() -> void:
				gs.flags.champion = true
				ow.load_map("summitcrown", 5, 17, "down")
				gs.x = 5
				gs.y = 17
				GameState.save(gs)
				Game.say(["Your journey was saved.", "Rumor has it the seven Wardens now roam Victory Road..."])))))
