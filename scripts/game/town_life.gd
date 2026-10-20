class_name TownLife
## The last of Emerald's townsfolk and odds and ends: the Move Deleter, the Glass Workshop (ash, flutes), rare
## fishing spots, mass outbreaks, the trendy phrase, the Quiz Lady, the Fan Club and Effort Ribbon, the national
## dex, fossils and the Shell Bell maker in Shoal Cave. Data comes from DB.EMERALD (tools/build_features.py).

# ---------- Move Deleter ----------
static func move_deleter(text: Array) -> void:
	Game.say(text, func() -> void:
		Services.pick_creature("Which creature should forget a move?", func(m: Dictionary) -> String:
			return "" if m.moves.size() > 1 else "%s only knows one move." % Creatures.display_name(m),
		func(m: Dictionary) -> void:
			var items: Array = []
			for mv in m.moves:
				items.append({"label": DB.move(mv.id).name, "right": "%d/%d" % [mv.pp, mv.maxPp]})
			items.append({"label": "CANCEL"})
			var ref := {}
			var menu := ListMenu.new({
				"x": 92, "y": 8, "w": 144, "player": 0, "title": "Forget which move?", "items": items,
				"footer": func(i: int) -> String: return DB.move(m.moves[i].id).desc if i < m.moves.size() else "",
				"on_cancel": func() -> void: Game.pop(ref.menu),
				"on_select": func(i: int) -> void:
					Game.pop(ref.menu)
					if i >= m.moves.size():
						return
					var name: String = DB.move(m.moves[i].id).name
					Game.ask("Make %s forget %s?" % [Creatures.display_name(m), name], ["YES", "NO"], func(c: int) -> void:
						if c != 0:
							return
						m.moves.remove_at(i)
						Audio.sfx("confirm")
						Game.say(["1, 2, and... Poof!", "%s forgot %s completely." % [Creatures.display_name(m), name]])),
			})
			ref.menu = menu
			Game.push(menu)))

# ---------- Glass Workshop: ash and flutes ----------
static func glass(text: Array) -> void:
	var gs: Dictionary = Game.gs
	if gs.bag.get("sootSack", 0) <= 0:
		Game.say(text + ["Here, take this Soot Sack. Walk through the ashy grass outside and it'll fill with ash."], func() -> void:
			gs.bag.sootSack = 1
			Audio.sfx("item")
			Game.say(["%s received the Soot Sack!" % gs.players[0].name]))
		return
	var wares: Array = DB.EMERALD.get("glass", [])
	var items: Array = []
	for w in wares:
		items.append({"label": DB.item(w[0]).name, "right": "%d ash" % w[1]})
	items.append({"label": "CANCEL"})
	var ref := {}
	var menu := ListMenu.new({
		"x": 92, "y": 8, "w": 144, "player": 0, "title": "Ash: %d" % int(gs.ash), "items": items,
		"footer": func(i: int) -> String: return DB.item(wares[i][0]).desc if i < wares.size() else "",
		"on_cancel": func() -> void: Game.pop(ref.menu),
		"on_select": func(i: int) -> void:
			Game.pop(ref.menu)
			if i >= wares.size():
				return
			var id: String = wares[i][0]
			var cost: int = wares[i][1]
			if int(gs.ash) < cost:
				Game.say(["You need %d ash for that. Your Soot Sack holds %d." % [cost, int(gs.ash)]])
				return
			var key: bool = DB.item(id).effect.kind == "key" or DB.item(id).effect.kind == "deco"
			if key and gs.bag.get(id, 0) > 0 or DB.item(id).effect.kind == "deco" and gs.decor.has(id):
				Game.say(["You already have a %s." % DB.item(id).name])
				return
			gs.ash = int(gs.ash) - cost
			if DB.item(id).effect.kind == "deco":
				gs.decor.append(id)
			else:
				gs.bag[id] = gs.bag.get(id, 0) + 1
			Audio.sfx("item")
			Game.say(["I made you a %s! Here you go." % DB.item(id).name]),
	})
	ref.menu = menu
	Game.push(menu)

## Ash falls on the tall grass of an ashy route; the Soot Sack collects it as you walk through.
static func on_step(o: OverworldScene, here: String) -> void:
	var gs: Dictionary = Game.gs
	if here == "," and o.map.get("weather", "") == "ash" and gs.bag.get("sootSack", 0) > 0:
		gs.ash = mini(9999, int(gs.ash) + 1)

## Playing the White or Black Flute: more or fewer wild creatures until you play it again.
static func play_flute(id: String) -> void:
	var gs: Dictionary = Game.gs
	var mode: String = DB.item(id).effect.mode
	Audio.sfx("confirm")
	if gs.flute == mode:
		gs.flute = ""
		Game.say(["%s stopped playing the %s." % [gs.players[0].name, DB.item(id).name]])
	else:
		gs.flute = mode
		Game.say(["%s played the %s." % [gs.players[0].name, DB.item(id).name],
			"Wild creatures will appear more often!" if mode == "more" else "Wild creatures will keep away!"])

## The encounter rate with a flute playing.
static func flute_rate(rate: int) -> int:
	match Game.gs.get("flute", ""):
		"more":
			return rate * 3 / 2
		"fewer":
			return rate / 2
	return rate

# ---------- rare fishing spots and mass outbreaks ----------
## Today's rare fishing spots: a few water tiles, chosen by the trendy phrase.
static func rare_spots(gs: Dictionary) -> Array:
	var rf: Dictionary = DB.EMERALD.get("rareFish", {})
	if rf.is_empty():
		return []
	var tiles: Array = rf.tiles.duplicate()
	var r := RandomNumberGenerator.new()
	r.seed = hash("rarefish" + String(gs.get("trendy", "")))
	var out: Array = []
	for i in mini(int(rf.spots), tiles.size()):
		out.append(tiles.pop_at(r.randi_range(0, tiles.size() - 1)))
	return out

## Fishing at one of the spots: half the bites are the rare creature. Returns the table to use.
static func fishing_table(o: OverworldScene, tx: int, ty: int, table: Array) -> Array:
	var rf: Dictionary = DB.EMERALD.get("rareFish", {})
	if rf.is_empty() or o.map.id != rf.map or not rare_spots(Game.gs).has("%d,%d" % [tx, ty]):
		return table
	if Rng.global_rng.int_below(2) == 0:
		return [{"species": rf.species, "min": int(rf.min), "max": int(rf.max), "weight": 100}]
	return table

## Today's outbreak {map, species}, or {} before the second badge.
static func outbreak(gs: Dictionary) -> Dictionary:
	var pool: Array = DB.EMERALD.get("outbreaks", [])
	var routes: Array = DB.EMERALD.get("outbreakRoutes", [])
	if pool.is_empty() or routes.is_empty() or not gs.flags.get("badge2", false):
		return {}
	var day := Options.today()
	return {"map": routes[absi(hash("outbreak%d" % day)) % routes.size()], "species": pool[absi(hash("swarm%d" % day)) % pool.size()]}

## On the outbreak's route, half the grass encounters are the swarming creature.
static func outbreak_table(o: OverworldScene, table: Array) -> Array:
	var ob := outbreak(Game.gs)
	if ob.is_empty() or o.map.id != ob.map or table.is_empty() or Rng.global_rng.int_below(2) != 0:
		return table
	var lo := 100
	var hi := 1
	for e in table:
		lo = mini(lo, int(e.min))
		hi = maxi(hi, int(e.max))
	return [{"species": ob.species, "min": lo, "max": hi, "weight": 100}]

# ---------- trendy phrase ----------
static func trendy(text: Array) -> void:
	var gs: Dictionary = Game.gs
	Game.say(text + ["Right now everyone's saying \"%s\"!" % gs.trendy], func() -> void:
		Game.ask("Want to start a new trend?", ["YES", "NO"], func(c: int) -> void:
			if c != 0:
				return
			Mail.compose(0, func(t: String) -> void:
				if t == "":
					Game.say(["Oh, never mind then."])
					return
				gs.trendy = t.substr(0, 24)
				Audio.sfx("badge")
				Game.say(["\"%s\"... That's so cool! Everyone will be saying it by tomorrow!" % gs.trendy]), [])))

# ---------- Quiz Lady ----------
static func quiz(text: Array) -> void:
	var gs: Dictionary = Game.gs
	var today := Options.today()
	if int(gs.flags.get("quiz_day", -1)) == today:
		Game.say(["That's all my questions for today. Come back tomorrow!"])
		return
	var types: Array = DB.TYPE_CHART.keys()
	var r := RandomNumberGenerator.new()
	r.seed = hash("quiz%d" % today)
	# Find an attacking type with exactly one super-effective answer among three defenders.
	for _try in 50:
		var atk: String = types[r.randi_range(0, types.size() - 1)]
		var good: Array = types.filter(func(t: String) -> bool: return DB.type_multiplier10(atk, t) > 10)
		var plain: Array = types.filter(func(t: String) -> bool: return DB.type_multiplier10(atk, t) == 10)
		if good.is_empty() or plain.size() < 2:
			continue
		var answer: String = good[r.randi_range(0, good.size() - 1)]
		var opts: Array = [answer, plain[r.randi_range(0, plain.size() - 1)]]
		while opts.size() < 3:
			var t: String = plain[r.randi_range(0, plain.size() - 1)]
			if not opts.has(t):
				opts.append(t)
		opts.shuffle()
		Game.say(text, func() -> void:
			Game.ask("Which type is %s super effective against?" % atk.to_upper(), opts.map(func(t: String) -> String: return t.to_upper()), func(c: int) -> void:
				gs.flags.quiz_day = today
				if opts[c] != answer:
					Audio.sfx("cancel")
					Game.say(["Oh, too bad! The answer was %s." % answer.to_upper(), "Come back tomorrow for another question!"])
					return
				var prizes: Array = DB.EMERALD.get("quizPrizes", ["ppUp"])
				var prize: String = prizes[r.randi_range(0, prizes.size() - 1)]
				gs.bag[prize] = gs.bag.get(prize, 0) + 1
				Audio.sfx("badge")
				Game.say(["Correct! Here's your prize!", "%s received the %s!" % [gs.players[0].name, DB.item(prize).name]])))
		return
	Game.say(text)

# ---------- Fan Club ----------
## How famous you are: badges, the Championship, Battle Tower and Frontier records, contest ribbons.
static func fame(gs: Dictionary) -> int:
	var n := 0
	for i in 8:
		if gs.flags.get("badge%d" % (i + 1), false):
			n += 1
	if gs.flags.get("champion", false):
		n += 3
	n += mini(3, int(gs.tower.get("best", 0)) / 7)
	for fid in gs.frontier:
		n += mini(2, int(gs.frontier[fid].get("best", 0)) / 7)
	n += mini(3, gs.contest.size())
	return n

static func fan_club(text: Array) -> void:
	var gs: Dictionary = Game.gs
	var needs: Array = DB.EMERALD.get("fanNeeds", [3, 6, 10])
	var fans := 0
	for k in needs:
		if fame(gs) >= int(k):
			fans += 1
	Game.say(text + ["You have %d fan%s in our club!" % [fans, "" if fans == 1 else "s"] if fans > 0
		else "Nobody here is your fan yet... Win more battles and you'll get noticed!"])

static func fan(npc: Dictionary, text: Array) -> void:
	var gs: Dictionary = Game.gs
	var i: int = npc.fan
	var need: int = DB.EMERALD.get("fanNeeds", [3, 6, 10])[i]
	if fame(gs) < need:
		Game.say(text)
		return
	var key := "fan%d_day" % i
	var today := Options.today()
	if int(gs.flags.get(key, -1)) == today:
		Game.say(["I'm your biggest fan! Good luck out there, %s!" % gs.players[0].name])
		return
	var gifts: Array = DB.EMERALD.fanGifts[i]
	var id: String = gifts[absi(hash("fan%d%d" % [i, today])) % gifts.size()]
	gs.flags[key] = today
	gs.bag[id] = gs.bag.get(id, 0) + 1
	Audio.sfx("item")
	Game.say(["Oh! It's %s! I'm your fan! Please take this!" % gs.players[0].name, "%s received the %s!" % [gs.players[0].name, DB.item(id).name]])

## The Effort Ribbon: for a creature whose base stats training (EVs) is complete.
static func effort_ribbon(text: Array) -> void:
	Game.say(text, func() -> void:
		Services.pick_creature("Show which creature?", func(_m: Dictionary) -> String: return "",
		func(m: Dictionary) -> void:
			var total := 0
			for k in DB.STAT_KEYS:
				total += int(m.evs.get(k, 0))
			if (m.ribbons as Array).has("Effort"):
				Game.say(["%s already has my Effort Ribbon. Wonderful!" % Creatures.display_name(m)])
			elif total < 510:
				Game.say(["Hmm... %s could still train harder. Come back when it's done all it can!" % Creatures.display_name(m)])
			else:
				m.ribbons.append("Effort")
				Audio.sfx("badge")
				Game.say(["What a hard worker! %s received the Effort Ribbon!" % Creatures.display_name(m)])))

# ---------- national dex ----------
static func national_dex(text: Array) -> void:
	var gs: Dictionary = Game.gs
	if gs.flags.get("nationalDex", false):
		Game.say(["PROF. ALDER: Your dex now covers every creature known. Fill it up!"])
		return
	if not gs.flags.get("champion", false):
		Game.say(text + ["Become Champion and I'll upgrade it to cover creatures from beyond Wildbound!"])
		return
	gs.flags.nationalDex = true
	Audio.sfx("badge")
	Game.say(text + ["You're the Champion now! Let me upgrade it...", "%s's dex was upgraded to the NATIONAL DEX!" % gs.players[0].name])

## Species shown in the dex: the regional dex leaves out legendaries until the upgrade.
static func dex_species(gs: Dictionary) -> Array:
	var list: Array = DB.SPECIES.values()
	if not gs.flags.get("nationalDex", false):
		list = list.filter(func(sp: Dictionary) -> bool: return sp.get("rarity", "") != "legendary")
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.dex < b.dex)
	return list

# ---------- fossils ----------
static func fossil_pick(text: Array) -> void:
	var gs: Dictionary = Game.gs
	if gs.flags.get("fossil_picked", false):
		Game.say(["Take that fossil to the Fossil Lab in Stonecrest. They can bring it back to life!"])
		return
	Game.say(text, func() -> void:
		Game.ask("Which fossil will you take?", ["ROOT FOSSIL", "CLAW FOSSIL"], func(c: int) -> void:
			var id: String = ["rootFossil", "clawFossil"][c]
			gs.flags.fossil_picked = true
			gs.bag[id] = 1
			Audio.sfx("item")
			Game.say(["%s received the %s!" % [gs.players[0].name, DB.item(id).name],
				"Take it to the Fossil Lab in Stonecrest. They can bring it back to life!"])))

static func fossil_lab(text: Array) -> void:
	var gs: Dictionary = Game.gs
	if gs.fossil != null:
		if int(gs.steps) - int(gs.fossil.steps) < 50:
			Game.say(["The machine is still working on your fossil. Go for a walk and come back."])
			return
		var sp: String = gs.fossil.species
		var mon := Creatures.create_creature(sp, int(DB.EMERALD.get("fossilLevel", 20)), {"owner": 0, "otId": gs.players[0].otId})
		gs.fossil = null
		var where := GameState.receive_creature(gs, mon, 0)
		if not gs.seen.has(sp):
			gs.seen.append(sp)
		Audio.sfx("badge")
		Game.say(["It's done! Your fossil came back to life as %s!" % DB.species(sp).name] + (["It was sent to storage."] if where == "box" else []))
		return
	for id in ["rootFossil", "clawFossil"]:
		if gs.bag.get(id, 0) > 0:
			Game.say(text, func() -> void:
				Game.ask("Shall I revive your %s?" % DB.item(id).name, ["YES", "NO"], func(c: int) -> void:
					if c != 0:
						return
					gs.bag.erase(id)
					gs.fossil = {"species": DB.item(id).effect.fossil, "steps": int(gs.steps)}
					Game.say(["Leave it with me. The machine takes a while, so go for a walk and come back."])))
			return
	Game.say(text)

# ---------- Shell Bell ----------
static func shell_bell(text: Array) -> void:
	var gs: Dictionary = Game.gs
	if gs.bag.get("shoalSalt", 0) < 4 or gs.bag.get("shoalShell", 0) < 4:
		Game.say(text + ["You have %d Shoal Salt and %d Shoal Shells." % [gs.bag.get("shoalSalt", 0), gs.bag.get("shoalShell", 0)],
			"The tide hides some of them. Come back when the water's low."])
		return
	Game.ask("You've got four of each! Shall I make you a Shell Bell?", ["YES", "NO"], func(c: int) -> void:
		if c != 0:
			return
		gs.bag.shoalSalt -= 4
		gs.bag.shoalShell -= 4
		gs.bag.shellBell = gs.bag.get("shellBell", 0) + 1
		Audio.sfx("item")
		Game.say(["Here's your Shell Bell! A creature holding it heals a little whenever it deals damage."]))
