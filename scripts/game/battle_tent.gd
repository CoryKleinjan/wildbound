class_name BattleTent
## Battle Tents: small Frontier facilities in three towns, open before you're Champion. Everyone fights at level 30
## (higher creatures are brought down to it), a set is three battles in a row, and a cleared set wins an item.
##   Saltmarsh  - Factory rules: rent three of six random creatures.
##   Harrowfield - Palace rules: your creatures pick their own moves.
##   Bramblegate - Arena rules: three-turn match-ups judged on Mind, Skill and Body.

const LEVEL := 30
const SET := 3

static func record(gs: Dictionary, fid: String) -> Dictionary:
	if not gs.tents.has(fid):
		gs.tents[fid] = {"streak": 0, "best": 0}
	return gs.tents[fid]

static func at_level(m: Dictionary, lv: int) -> Dictionary:
	var c: Dictionary = m.duplicate(true)
	if int(c.level) > lv:
		c.level = lv
		c.exp = Creatures.exp_for_level(DB.species(c.species).growth, lv)
	Creatures.heal_fully(c)
	return c

static func start(o: OverworldScene, fid: String) -> void:
	var gs: Dictionary = Game.gs
	var rec := record(gs, fid)
	Game.ask("Your record: %d in a row (best %d). Take the challenge?" % [rec.streak, rec.best], ["YES", "NO"], func(c: int) -> void:
		if c != 0:
			Game.say(["We hope to see you again."])
			return
		if fid == "factory":
			_rent(o, [], _offer())
		else:
			Frontier._pick_team(3, func(team: Array) -> void:
				_run(o, fid, team.map(func(m: Dictionary) -> Dictionary: return at_level(m, LEVEL)), 0)))

static func _offer() -> Array:
	var pool: Array = DB.TOWER.pool.duplicate()
	pool.shuffle()
	var out: Array = []
	for i in 6:
		out.append(at_level(Frontier._rental(pool[i]), LEVEL))
	return out

static func _rent(o: OverworldScene, chosen: Array, offer: Array) -> void:
	if chosen.size() == 3:
		Game.say(["Your rental team is ready. Good luck!"], func() -> void: _run(o, "factory", chosen, 0))
		return
	var items: Array = []
	for m in offer:
		items.append(Frontier._mon_label(m))
	var ref := {}
	var menu := ListMenu.new({
		"x": 92, "y": 8, "w": 144, "player": 0, "title": "Rent creature %d of 3" % (chosen.size() + 1), "items": items,
		"on_cancel": func() -> void:
			Game.pop(ref.menu)
			Game.say(["Come back anytime."]),
		"on_select": func(i: int) -> void:
			Game.pop(ref.menu)
			var rest: Array = offer.duplicate()
			var m: Dictionary = rest.pop_at(i)
			_rent(o, chosen + [m], rest),
	})
	ref.menu = menu
	Game.push(menu)

static func _opponent(n: int) -> Dictionary:
	var opp := Tower._opponent(n)
	opp.trainer.intro = "Battle %d of %d. Here I come!" % [n + 1, SET]
	opp.trainer.name = opp.trainer.name if n < SET - 1 else "Tent Master"
	opp.party = opp.party.map(func(m: Dictionary) -> Dictionary:
		var c := Creatures.create_creature(m.species, LEVEL, {"owner": 9, "ivs": m.ivs})
		c.item = m.get("item")
		return c)
	return opp

static func _run(o: OverworldScene, fid: String, team: Array, n: int) -> void:
	var gs: Dictionary = Game.gs
	var extra := {}
	if fid == "palace":
		extra = {"palace": true, "noBag": true}
	elif fid == "arena":
		extra = {"arena": true, "noSwitch": true, "noBag": true}
	Frontier._battle(o, team, _opponent(n), extra, func(result: String, _b) -> void:
		var rec := record(gs, fid)
		if result != "win":
			rec.streak = 0
			Game.say(["Your challenge ended at battle %d. Better luck next time!" % (n + 1)])
			return
		rec.streak = int(rec.streak) + 1
		rec.best = maxi(int(rec.best), int(rec.streak))
		for m in team:
			Creatures.heal_fully(m)
		if n < SET - 1:
			_run(o, fid, team, n + 1)
			return
		var prizes: Array = DB.EMERALD.get("tentPrizes", ["ppUp"])
		var prize: String = prizes[Rng.global_rng.int_below(prizes.size())]
		gs.bag[prize] = gs.bag.get(prize, 0) + 1
		Audio.sfx("badge")
		Game.say(["Congratulations! You won all three battles! (%d in a row)" % int(rec.streak),
			"Please accept this prize: a %s!" % DB.item(prize).name]))
