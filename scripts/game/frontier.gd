class_name Frontier
## The Battle Frontier (reached by ferry from Saltmarsh once you're Champion). Six facilities with their own rules,
## all at level 50 with three creatures (no legendaries, no two of a species):
##   Factory - rent three of six random creatures; after each win you may swap one for one of the loser's.
##   Arena   - three-turn match-ups judged on Mind, Skill and Body; no switching or items.
##   Palace  - your creatures choose their own moves, as their natures tell them; no items.
##   Dome    - a four-round tournament: see the next rival's team, then pick two of your three.
##   Pike    - fourteen rooms, three doors each: battles, wild creatures, healing, or traps.
##   Pyramid - seven dark maze floors of wild creatures and trainers; you can only use items found inside.
## Arena, Palace and Factory run sets of seven battles (the seventh against the facility's Frontier Brain). Each
## cleared set, tournament, Pike or Pyramid pays Battle Points, spent at the Exchange Service Corner.

const NAMES := {"factory": "Battle Factory", "arena": "Battle Arena", "palace": "Battle Palace", "dome": "Battle Dome",
	"pike": "Battle Pike", "pyramid": "Battle Pyramid"}
const BRAINS := {"factory": "Factory Head Torin", "arena": "Arena Tycoon Mara", "palace": "Palace Maven Opal",
	"dome": "Dome Ace Silas", "pike": "Pike Queen Lysa", "pyramid": "Pyramid King Brann"}
const BP := {"factory": 3, "arena": 3, "palace": 3, "dome": 5, "pike": 4, "pyramid": 5}
const PYRAMID_FLOORS := 7
const PYRAMID_ITEMS := ["potion", "superPotion", "hyperPotion", "fullHeal", "revive", "ether", "fullRestore", "xAttack",
	"xDefend", "xSpeed", "oranBerry", "sitrusBerry", "lumBerry"]

static func record(gs: Dictionary, fid: String) -> Dictionary:
	if not gs.frontier.has(fid):
		gs.frontier[fid] = {"streak": 0, "best": 0}
	return gs.frontier[fid]

static func _won(gs: Dictionary, fid: String) -> int:
	var rec := record(gs, fid)
	rec.streak = int(rec.streak) + 1
	rec.best = maxi(int(rec.best), int(rec.streak))
	return int(rec.streak)

static func _lost(gs: Dictionary, fid: String) -> void:
	record(gs, fid).streak = 0

static func _award(gs: Dictionary, fid: String, lines: Array) -> void:
	var streak := int(record(gs, fid).streak)
	var bp: int = int(BP[fid]) + mini(6, streak / 3)
	gs.bp += bp
	Audio.sfx("badge")
	Game.say(lines + ["You earned %d Battle Points!" % bp])

# ---------- entry ----------
static func start(o: OverworldScene, fid: String) -> void:
	var gs: Dictionary = Game.gs
	if not gs.flags.get("champion", false):
		Game.say(["The %s is open to League Champions only." % NAMES[fid]])
		return
	var rec := record(gs, fid)
	var ask := "Your record: %d in a row (best %d). Take the challenge?" % [rec.streak, rec.best]
	if fid == "factory":
		ask = "Your record: %d in a row (best %d). Rent three creatures and take the challenge?" % [rec.streak, rec.best]
	Game.ask(ask, ["YES", "NO"], func(c: int) -> void:
		if c != 0:
			Game.say(["We hope to see you again."])
			return
		if fid == "factory":
			_factory_rent(o)
			return
		_pick_team(3, func(team: Array) -> void: _enter(o, fid, team)))

static func _enter(o: OverworldScene, fid: String, team: Array) -> void:
	match fid:
		"arena":
			_run_set(o, fid, team, 0, {"arena": true, "noSwitch": true, "noBag": true})
		"palace":
			_run_set(o, fid, team, 0, {"palace": true, "noBag": true})
		"dome":
			_dome(o, team)
		"pike":
			_pike(o, team, 1)
		"pyramid":
			_pyramid_start(o, team)

## Choose `count` creatures for a facility; on_done(level-50 copies).
static func _pick_team(count: int, on_done: Callable, picked: Array = []) -> void:
	if picked.size() == count:
		on_done.call(picked.map(func(m: Dictionary) -> Dictionary: return Tower._copy(m)))
		return
	Services.pick_creature("Choose creature %d of %d." % [picked.size() + 1, count], func(m: Dictionary) -> String:
		if picked.has(m):
			return "That one's already chosen."
		for p in picked:
			if p.species == m.species:
				return "You can't enter two of the same species."
		return "" if DB.species(m.species).get("rarity", "") != "legendary" else "Legendary creatures can't enter.",
	func(m: Dictionary) -> void: _pick_team(count, on_done, picked + [m]),
	func() -> void: Game.say(["Come back anytime."]))

## A Frontier trainer for battle n of a set (the seventh is the facility's Frontier Brain).
static func _opponent(fid: String, n: int) -> Dictionary:
	var opp := Tower._opponent(n)
	if n >= 6:
		opp.trainer.name = BRAINS[fid]
		opp.trainer.intro = "So you're the one everyone's talking about. Show me what you've got!"
		opp.trainer.defeat = "Superb! You've earned my respect."
	return opp

## One Frontier battle. on_result(result, battle).
static func _battle(o: OverworldScene, team: Array, opp: Dictionary, extra: Dictionary, on_result: Callable) -> void:
	var t: Dictionary = opp.trainer
	Game.say([t.intro], func() -> void:
		var ref := {}
		var setup := {"kind": "trainer", "double": false, "trainer": t, "trainerParty": opp.party, "party": team,
			"noExp": true, "noPrize": true}
		setup.merge(extra, true)
		setup.onEnd = func(result: String, battle) -> void:
			Game.transition(func() -> void:
				Game.pop(ref.scene)
				Audio.play_music(OverworldScene.map_track(o.map))
				on_result.call(result, battle))
		o._flash_then(func() -> void:
			setup.bg = BattleScene.backdrop_for(o.map)
			var scene := BattleScene.new(setup)
			ref.scene = scene
			Game.push(scene)))

## Sets of seven (Arena, Palace, Factory). between(team, opp, next) runs after a win, before the next battle.
static func _run_set(o: OverworldScene, fid: String, team: Array, n: int, extra: Dictionary, between: Callable = Callable()) -> void:
	var gs: Dictionary = Game.gs
	var opp := _opponent(fid, n)
	_battle(o, team, opp, extra, func(result: String, _battle_ref) -> void:
		if result != "win":
			_lost(gs, fid)
			Game.say(["Your streak ended at battle %d of this set. Better luck next time!" % (n + 1)])
			return
		var streak := _won(gs, fid)
		for m in team:
			Creatures.heal_fully(m)
		if n == 6:
			_award(gs, fid, ["Congratulations! You won seven battles in a row! (%d in a row)" % streak])
			return
		var go_on := func() -> void:
			Game.ask("You've won %d in a row. Keep going?" % (n + 1), ["YES", "REST"], func(c: int) -> void:
				if c == 0:
					_run_set(o, fid, team, n + 1, extra, between)
				else:
					record(gs, fid).streak = maxi(0, int(record(gs, fid).streak) - (n + 1))
					Game.say(["You left before finishing the set, so this set's wins don't count. Come back anytime!"]))
		if between.is_valid():
			between.call(team, opp, go_on)
		else:
			go_on.call())

# ---------- Battle Factory ----------
static func _rental(sp: String) -> Dictionary:
	var rng := Rng.global_rng
	var ivs := {}
	for s in DB.STAT_KEYS:
		ivs[s] = 10 + rng.int_below(16)
	var mon := Creatures.create_creature(sp, 50, {"owner": 0, "ivs": ivs})
	var held: String = Tower.HELD[rng.int_below(Tower.HELD.size())]
	mon.item = held if DB.ITEMS.has(held) else null
	return mon

static func _factory_rent(o: OverworldScene) -> void:
	var pool: Array = DB.TOWER.pool.duplicate()
	pool.shuffle()
	var offer: Array = []
	for i in 6:
		offer.append(_rental(pool[i]))
	_factory_choose(o, offer, [])

static func _mon_label(m: Dictionary) -> Dictionary:
	var sp: Dictionary = DB.species(m.species)
	return {"label": sp.name, "right": "/".join(sp.types)}

static func _factory_choose(o: OverworldScene, offer: Array, chosen: Array) -> void:
	if chosen.size() == 3:
		Game.say(["Your rental team is ready. Good luck!"], func() -> void:
			_run_set(o, "factory", chosen, 0, {}, _factory_swap))
		return
	var items: Array = []
	for m in offer:
		var it := _mon_label(m)
		if chosen.has(m):
			it.disabled = true
			it.right = "TAKEN"
		items.append(it)
	var ref := {}
	var menu := ListMenu.new({
		"x": 76, "y": 4, "w": 160, "player": 0, "title": "Rent which? (%d/3)" % (chosen.size() + 1), "items": items,
		"footer": func(i: int) -> String:
			var m: Dictionary = offer[i]
			var mv: Array = m.moves.map(func(x: Dictionary) -> String: return DB.move(x.id).name)
			return ", ".join(mv) + (" / " + DB.item(m.item).name if m.item != null else ""),
		"on_cancel": func() -> void:
			if chosen.is_empty():
				Game.pop(ref.menu)
				Game.say(["Come back anytime."])
			else:
				Game.pop(ref.menu)
				_factory_choose(o, offer, chosen.slice(0, chosen.size() - 1)),
		"on_select": func(i: int) -> void:
			Game.pop(ref.menu)
			_factory_choose(o, offer, chosen + [offer[i]]),
	})
	ref.menu = menu
	Game.push(menu)

## After a Factory win: swap one rental for one of the beaten trainer's creatures.
static func _factory_swap(team: Array, opp: Dictionary, next: Callable) -> void:
	Game.ask("Would you like to swap one of your rentals for one of %s's creatures?" % opp.trainer.name, ["YES", "NO"], func(c: int) -> void:
		if c != 0:
			next.call()
			return
		var mine: Array = []
		for m in team:
			mine.append(_mon_label(m))
		var ref := {}
		var menu := ListMenu.new({
			"x": 76, "y": 4, "w": 160, "player": 0, "title": "Give up which?", "items": mine,
			"on_cancel": func() -> void:
				Game.pop(ref.menu)
				next.call(),
			"on_select": func(i: int) -> void:
				Game.pop(ref.menu)
				var theirs: Array = []
				for m in opp.party:
					theirs.append(_mon_label(m))
				var ref2 := {}
				var menu2 := ListMenu.new({
					"x": 76, "y": 4, "w": 160, "player": 0, "title": "Take which?", "items": theirs,
					"on_cancel": func() -> void:
						Game.pop(ref2.menu)
						next.call(),
					"on_select": func(j: int) -> void:
						Game.pop(ref2.menu)
						var got: Dictionary = opp.party[j].duplicate(true)
						got.owner = 0
						Creatures.heal_fully(got)
						var old: String = Creatures.display_name(team[i])
						team[i] = got
						Game.say(["Swapped %s for %s!" % [old, Creatures.display_name(got)]], next),
				})
				ref2.menu = menu2
				Game.push(menu2),
		})
		ref.menu = menu
		Game.push(menu))

# ---------- Battle Dome ----------
static func _dome(o: OverworldScene, team: Array) -> void:
	var rivals: Array = []
	for r in 4:
		rivals.append(_opponent("dome", 6 if r == 3 else r * 2))
	_dome_round(o, team, rivals, 0)

static func _dome_round(o: OverworldScene, team: Array, rivals: Array, r: int) -> void:
	var gs: Dictionary = Game.gs
	var opp: Dictionary = rivals[r]
	var names: Array = opp.party.map(func(m: Dictionary) -> String: return DB.species(m.species).name)
	var title: String = ["First round", "Second round", "Semifinal", "Final"][r]
	Game.say(["%s! Your opponent is %s." % [title, opp.trainer.name], "Their team: %s." % ", ".join(names),
		"Choose two of your three creatures for this match."], func() -> void:
		_choose_two(team, [], func(two: Array) -> void:
			# Their best two come out too.
			var foe: Dictionary = {"trainer": opp.trainer, "party": opp.party.slice(0, 2)}
			_battle(o, two, foe, {}, func(result: String, _b) -> void:
				for m in team:
					Creatures.heal_fully(m)
				if result != "win":
					_lost(gs, "dome")
					Game.say(["You were knocked out in the %s. Better luck next time!" % title.to_lower()])
					return
				if r == 3:
					var streak := _won(gs, "dome")
					_award(gs, "dome", ["You won the tournament! (%d tournaments in a row)" % streak])
					return
				_dome_round(o, team, rivals, r + 1))))

static func _choose_two(team: Array, chosen: Array, on_done: Callable) -> void:
	if chosen.size() == 2:
		on_done.call(chosen)
		return
	var items: Array = []
	for m in team:
		var it := _mon_label(m)
		if chosen.has(m):
			it.disabled = true
			it.right = "IN"
		items.append(it)
	var ref := {}
	var menu := ListMenu.new({
		"x": 76, "y": 4, "w": 160, "player": 0, "title": "Pick %d of 2" % (chosen.size() + 1), "items": items,
		"on_select": func(i: int) -> void:
			Game.pop(ref.menu)
			_choose_two(team, chosen + [team[i]], on_done),
	})
	ref.menu = menu
	Game.push(menu)

# ---------- Battle Pike ----------
const PIKE_ROOMS := ["trainer", "trainer", "trainer", "wild", "wild", "heal", "status", "hurt", "nothing"]
const PIKE_HINTS := {"trainer": "the presence of people", "wild": "the presence of creatures", "heal": "a nostalgic scent",
	"status": "a strange smell", "hurt": "a dreadful aura", "nothing": "nothing at all"}

static func _pike_alive(team: Array) -> bool:
	for m in team:
		if m.hp > 0:
			return true
	return false

static func _pike(o: OverworldScene, team: Array, room: int) -> void:
	var gs: Dictionary = Game.gs
	if room > 14:
		var streak := _won(gs, "pike")
		_award(gs, "pike", ["You made it through all fourteen rooms of the Battle Pike! (%d in a row)" % streak])
		return
	var rng := Rng.global_rng
	var doors: Array = []
	for i in 3:
		doors.append(PIKE_ROOMS[rng.int_below(PIKE_ROOMS.size())])
	if room == 14:
		doors = ["brain", "brain", "brain"]
	var hint_door := rng.int_below(3)
	var hint: String = "a fearsome presence" if room == 14 else PIKE_HINTS[doors[hint_door]]
	Game.say(["Room %d of 14." % room, "I sense %s behind the %s door..." % [hint, ["left", "center", "right"][hint_door]]], func() -> void:
		Game.ask("Which door will you take?", ["LEFT", "CENTER", "RIGHT"], func(c: int) -> void:
			_pike_room(o, team, room, doors[c])))

static func _pike_room(o: OverworldScene, team: Array, room: int, kind: String) -> void:
	var gs: Dictionary = Game.gs
	var rng := Rng.global_rng
	var next := func() -> void: _pike(o, team, room + 1)
	var lost := func() -> void:
		_lost(gs, "pike")
		Game.say(["Your team can't go on. The Battle Pike challenge is over."])
	var after := func(result: String, _b) -> void:
		if result == "lose" or not _pike_alive(team):
			lost.call()
		else:
			next.call()
	match kind:
		"trainer", "brain":
			var opp := _opponent("pike", 6 if kind == "brain" else mini(5, room / 3))
			_battle(o, team, opp, {}, after)
		"wild":
			var pool: Array = DB.FRONTIER.get("pyramidWild", DB.TOWER.pool)
			var mon := Creatures.create_creature(pool[rng.int_below(pool.size())], 50, {"owner": 9})
			Game.say(["A wild creature leapt out!"], func() -> void:
				var ref := {}
				var setup := {"kind": "wild", "double": false, "wild": [mon], "party": team, "noExp": true, "noBag": true}
				setup.onEnd = func(result: String, battle) -> void:
					Game.transition(func() -> void:
						Game.pop(ref.scene)
						Audio.play_music(OverworldScene.map_track(o.map))
						after.call(result, battle))
				o._flash_then(func() -> void:
					var scene := BattleScene.new(setup)
					ref.scene = scene
					Game.push(scene)))
		"heal":
			for m in team:
				Creatures.heal_fully(m)
			Audio.sfx("heal")
			Game.say(["A kind lady healed your team!"], next)
		"status":
			var alive: Array = team.filter(func(m: Dictionary) -> bool: return m.hp > 0 and m.status == null)
			if alive.is_empty():
				Game.say(["The room was empty."], next)
				return
			var m: Dictionary = alive[rng.int_below(alive.size())]
			var st: String = ["psn", "par", "brn", "slp"][rng.int_below(4)]
			m.status = st
			if st == "slp":
				m.sleepTurns = 1 + rng.int_below(3)
			Game.say(["A strange gas filled the room!", "%s was %s!" % [Creatures.display_name(m), {"psn": "poisoned", "par": "paralyzed", "brn": "burned", "slp": "put to sleep"}[st]]], next)
		"hurt":
			for m in team:
				if m.hp > 0:
					m.hp = maxi(1, m.hp / 2)
			Game.say(["Something lunged out of the dark and struck your team!"], next)
		_:
			Game.say(["The room was empty."], next)

# ---------- Battle Pyramid ----------
static func _pyramid_start(o: OverworldScene, team: Array) -> void:
	var gs: Dictionary = Game.gs
	gs.pyramid = {"floor": 1, "party": gs.players[0].party, "bag": gs.bag, "run": int(gs.flags.get("pyramid_runs", 0)) + 1,
		"surfing": gs.get("surfing", false)}
	gs.flags.pyramid_runs = gs.pyramid.run
	gs.players[0].party = team
	gs.bag = {}
	Game.say(["Your own bag stays here. You can only use items you find inside the Pyramid.", "Reach the top of all seven floors!"],
		func() -> void: _pyramid_warp(o))

static func _pyramid_warp(o: OverworldScene) -> void:
	var gs: Dictionary = Game.gs
	var m := pyramid_floor(int(gs.pyramid.floor), int(gs.pyramid.run))
	DB.MAPS[m.id] = m
	Field._warp(o, m.id, int(m.start.x), int(m.start.y), "up", false)

## Climbed the ladder: the next floor, or the top.
static func pyramid_next_floor(o: OverworldScene) -> void:
	var gs: Dictionary = Game.gs
	gs.pyramid.floor = int(gs.pyramid.floor) + 1
	if int(gs.pyramid.floor) > PYRAMID_FLOORS:
		_pyramid_end(gs)
		var streak := _won(gs, "pyramid")
		Field._warp(o, "frontier_pyramid", 7, 9, "down", false)
		_award(gs, "pyramid", ["You reached the top of the Battle Pyramid! (%d in a row)" % streak])
		return
	Game.say(["Floor %d..." % gs.pyramid.floor], func() -> void: _pyramid_warp(o))

static func pyramid_lost(o: OverworldScene) -> void:
	var gs: Dictionary = Game.gs
	_pyramid_end(gs)
	_lost(gs, "pyramid")
	o.load_map("frontier_pyramid", 7, 9, "down")
	gs.x = 7
	gs.y = 9
	Game.say(["Your team was defeated in the Pyramid. You've been brought back to the entrance."])

## Gives back the real team and bag.
static func _pyramid_end(gs: Dictionary) -> void:
	if gs.get("pyramid") == null:
		return
	gs.players[0].party = gs.pyramid.party
	gs.bag = gs.pyramid.bag
	gs.surfing = false
	gs.pyramid = null
	for f in gs.flags.keys():
		if str(f).begins_with("pyr_"):
			gs.flags.erase(f)

## Loading a save made inside the Pyramid ends that run at the entrance.
static func restore_after_load(gs: Dictionary) -> void:
	if gs.get("pyramid") == null:
		return
	_pyramid_end(gs)
	gs.map = "frontier_pyramid"
	gs.x = 7
	gs.y = 9
	gs.dir = "down"

## A dark maze floor: a winding cave with wild creatures, trainers, items and a ladder up.
static func pyramid_floor(floor: int, run: int) -> Dictionary:
	var rng := Rng.new(run * 101 + floor * 7919)
	var W := 21
	var H := 15
	var g: Array = []
	for y in H:
		var row: Array = []
		row.resize(W)
		row.fill("x")
		g.append(row)
	var start := Vector2i(1, H - 2)
	var stack: Array = [start]
	var seen := {start: true}
	g[start.y][start.x] = "g"
	while not stack.is_empty():
		var c: Vector2i = stack.back()
		var nb: Array = []
		for d in [Vector2i(0, -2), Vector2i(0, 2), Vector2i(-2, 0), Vector2i(2, 0)]:
			var n: Vector2i = c + d
			if n.x > 0 and n.y > 0 and n.x < W - 1 and n.y < H - 1 and not seen.has(n):
				nb.append(d)
		if nb.is_empty():
			stack.pop_back()
			continue
		var d: Vector2i = nb[rng.int_below(nb.size())]
		g[c.y + d.y / 2][c.x + d.x / 2] = "g"
		var n2: Vector2i = c + d
		g[n2.y][n2.x] = "g"
		seen[n2] = true
		stack.append(n2)
	# Knock out some walls so it isn't a perfect maze.
	for i in 14:
		var x := 1 + rng.int_below(W - 2)
		var y := 1 + rng.int_below(H - 2)
		if g[y][x] == "x" and ((g[y][x - 1] == "g" and g[y][x + 1] == "g") or (g[y - 1][x] == "g" and g[y + 1][x] == "g")):
			g[y][x] = "g"
	# The ladder goes on the cell farthest from the start.
	var dist := {start: 0}
	var q: Array = [start]
	var far := start
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		if dist[c] > dist[far]:
			far = c
		for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
			var n: Vector2i = c + d
			if g[n.y][n.x] == "g" and not dist.has(n):
				dist[n] = dist[c] + 1
				q.append(n)
	g[far.y][far.x] = "y"
	# Dead ends get items; trainers stand in corridors along the way.
	var dead: Array = []
	var corridor: Array = []
	for c in dist:
		if c == start or c == far or dist[c] < 4:
			continue
		var open := 0
		for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
			if g[c.y + d.y][c.x + d.x] != "x":
				open += 1
		if open == 1:
			dead.append(c)
		elif open == 2:
			corridor.append(c)
	var items: Array = []
	for i in mini(3, dead.size()):
		var c: Vector2i = dead.pop_at(rng.int_below(dead.size()))
		items.append({"id": "pyr_%d_%d_i%d" % [run, floor, i], "x": c.x, "y": c.y, "item": PYRAMID_ITEMS[rng.int_below(PYRAMID_ITEMS.size())],
			"count": 1, "hidden": false})
	var trainers: Array = []
	var pool: Array = DB.TOWER.pool
	var names := ["Hiker", "Psychic", "Ace", "Veteran", "Beauty", "Ruin Maniac"]
	var palettes := ["hiker", "psychic", "ace", "old", "beauty", "hiker"]
	for i in mini(2 + floor / 3, corridor.size()):
		var c: Vector2i = corridor.pop_at(rng.int_below(corridor.size()))
		var dir := "down"
		for d in ["up", "down", "left", "right"]:
			var v: Vector2i = OverworldScene.DX[d]
			if g[c.y + v.y][c.x + v.x] == "g":
				dir = d
		var k := rng.int_below(names.size())
		var party: Array = []
		for j in 2 + (1 if floor >= 4 else 0):
			party.append([pool[rng.int_below(pool.size())], 50])
		trainers.append({"id": "pyr_%d_%d_t%d" % [run, floor, i], "name": "%s %s" % [names[k], ["Lee", "Moss", "Rhea", "Dax", "Ivo", "Kit"][rng.int_below(6)]],
			"palette": palettes[k], "x": c.x, "y": c.y, "dir": dir, "sight": 3, "pay": 0, "party": party, "double": false,
			"intro": "You won't reach the top while I'm here!", "defeat": "The Pyramid swallows the weak... but not you.",
			"after": "Keep climbing."})
	var wild: Array = DB.FRONTIER.get("pyramidWild", pool)
	var enc: Array = []
	for i in 5:
		enc.append({"species": wild[rng.int_below(wild.size())], "min": 50, "max": 50, "weight": [30, 25, 20, 15, 10][i]})
	var tiles: Array = []
	for row in g:
		tiles.append("".join(row))
	return {
		"id": "pyramidfloor", "name": "Battle Pyramid %dF" % floor, "tiles": tiles, "cave": true, "dark": true,
		"connections": {}, "npcs": [], "trainers": trainers, "items": items, "encounters": enc, "encounterRate": 12,
		"warps": {"%d,%d" % [far.x, far.y]: {"map": "pyramidfloor", "x": start.x, "y": start.y, "dir": "up", "script": "pyramidUp"}},
		"start": {"x": start.x, "y": start.y}, "theme": "#a89878", "music": "route",
	}
