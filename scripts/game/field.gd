class_name Field
## Emerald's field systems on top of the overworld: HM field moves (Cut, Fly, Surf, Strength, Flash, Rock Smash,
## Waterfall, Dive), items on the ground, berry soil, legendaries waiting in place, roaming legendaries, fishing,
## the bike, Repel, Escape Rope, wild encounters on water and in caves, the Safari Zone, eggs and the Day Care's
## steps, trainer rematches, overworld weather and dark caves.
## OverworldScene calls in at a few hooks (load, step, bump, interact, battle, draw); the per-map state for the
## current visit (cut trees, pushed boulders, Flash, Strength) lives in ow.field, and anything saved lives in gs.

const WATER := "~DW"
const PICKUP_TABLE := [
	[1, ["potion", "antidote", "superPotion", "greatOrb", "repel", "escapeRope", "xAttack", "fullHeal", "ultraOrb"]],
	[31, ["superPotion", "greatOrb", "repel", "hyperPotion", "ultraOrb", "rareCandy", "fullHeal", "nugget", "ppUp"]],
	[61, ["ultraOrb", "hyperPotion", "rareCandy", "fullHeal", "nugget", "ppUp", "maxPotion", "fullRestore", "maxRevive"]],
]
const BERRY_COLORS := ["#e04848", "#4878e0", "#e0a030", "#8848c8", "#48a848", "#f070b0", "#f0d040"]

static func fresh_state() -> Dictionary:
	return {"cleared": {}, "boulders": {}, "flash": false, "strength": false}

static func ow() -> OverworldScene:
	if Game.stack.size() and Game.stack[0] is OverworldScene:
		return Game.stack[0]
	return null

static func _key(x: int, y: int) -> String:
	return "%d,%d" % [x, y]

# ---------- tiles ----------
## The map tile with this visit's changes: cut trees and smashed rocks become floor, boulders move.
static func tile(o: OverworldScene, x: int, y: int) -> String:
	var k := _key(x, y)
	var f: Dictionary = o.field
	if f.boulders.has(k):
		return f.boulders[k]
	if f.cleared.has(k):
		return f.cleared[k]
	var mg: Variant = o.map.get("mirage")
	if mg != null and _in_mirage(mg, x, y):
		return (mg.tiles[y - int(mg.y)] as String)[x - int(mg.x)] if f.get("mirage", false) else "~"
	var t := Maps.tile_at(o.map, x, y)
	# Islands are surrounded by sea rather than trees.
	if o.map.has("outside") and (y < 0 or x < 0 or y >= o.map.tiles.size() or x >= (o.map.tiles[0] as String).length()):
		return o.map.outside
	# Shoal Cave's tide pools: water at high tide, cave floor at low tide.
	if t == "J":
		return "g" if f.get("low", false) else "~"
	return t

## Floor left behind by a cut tree, a smashed rock or a pushed boulder.
static func _floor(o: OverworldScene) -> String:
	if o.map.get("cave", false):
		return "g"
	return "_" if o.map.get("indoor", false) else "."

# ---------- Mirage Island ----------
static func _in_mirage(mg: Dictionary, x: int, y: int) -> bool:
	return x >= int(mg.x) and y >= int(mg.y) and y < int(mg.y) + mg.tiles.size() and x < int(mg.x) + (mg.tiles[0] as String).length()

## Mirage Island rises out of the sea on some days: when today's number matches one of your creatures.
static func mirage_visible(gs: Dictionary) -> bool:
	var day := Options.today()
	var target := absi(hash("mirage%d" % day)) % 16
	for m in gs.players[0].party:
		if not m.get("egg", false) and (int(m.personality) & 0xffff) % 16 == target:
			return true
	return false

## A berry tree or soil on Mirage Island can't be reached while the island is hidden.
static func _mirage_hidden(o: OverworldScene, k: String) -> bool:
	var mg: Variant = o.map.get("mirage")
	if mg == null or o.field.get("mirage", false):
		return false
	var p := k.split(",")
	return _in_mirage(mg, int(p[0]), int(p[1]))

static func surfing(o: OverworldScene) -> bool:
	return Game.gs.get("surfing", false)

## Extra walkable tiles: water while surfing, the seafloor's deep spots.
static func passable(o: OverworldScene, t: String) -> bool:
	if surfing(o) and (t == "~" or t == "D"):
		return true
	if o.map.get("underwater", false) and t == "D":
		return true
	return false

## Things on the map that block a tile: items lying there, legendaries waiting, solid Secret Base decorations.
static func blocked(o: OverworldScene, x: int, y: int) -> bool:
	var gs: Dictionary = Game.gs
	for it in o.map.get("items", []):
		if it.x == x and it.y == y and not it.hidden and not gs.flags.get(it.id, false):
			return true
	for s in _statics(o):
		if s.x == x and s.y == y:
			return true
	if o.map.get("secretBase", false) and gs.secretBase != null:
		for d in gs.secretBase.decor:
			if d.x == x and d.y == y and DB.DECORATIONS[d.id].get("solid", false):
				return true
	return o.map.has("shoal") and Shoal.blocked(o, x, y) or Legends.blocked(o, x, y)

## Legendaries standing on this map that haven't been caught or beaten.
static func _statics(o: OverworldScene) -> Array:
	var gs: Dictionary = Game.gs
	var out: Array = []
	for s in o.map.get("statics", []):
		if gs.flags.get(s.id, false):
			continue
		if s.has("requires") and not gs.flags.get(s.requires, false):
			continue
		if not Legends.eon_here(gs, s):
			continue
		out.append(s)
	return out

## Seconds per step: the bike is twice as fast as running, surfing is as fast as running.
static func step_time(o: OverworldScene, base: float) -> float:
	var gs: Dictionary = Game.gs
	if surfing(o):
		return OverworldScene.RUN
	if gs.get("bike", false) and not o.map.get("indoor", false):
		return OverworldScene.RUN / 2.0
	return base

# ---------- party helpers ----------
static func party(pl: int = 0) -> Array:
	return Game.gs.players[pl].party

## The first creature in the party that knows a move (eggs don't count), or null.
static func knower(move_id: String) -> Variant:
	for m in party():
		if not m.get("egg", false) and Creatures.knows(m, move_id):
			return m
	return null

static func has_badge_for(move_id: String) -> bool:
	var need: int = DB.HM_BADGES.get(move_id, 0)
	return need == 0 or Game.gs.flags.get("badge%d" % need, false)

## The lead creature: the first one that can battle.
static func lead() -> Variant:
	for m in party():
		if Battle.can_battle(m):
			return m
	return null

# ---------- map load ----------
static func on_map_loaded(o: OverworldScene) -> void:
	var gs: Dictionary = Game.gs
	o.field = fresh_state()
	var here := Maps.tile_at(o.map, o.player.x, o.player.y)
	if o.map.get("underwater", false):
		gs.surfing = false
	elif here == "~" or here == "D":
		gs.surfing = true
	elif Maps.WALKABLE.has(here):
		gs.surfing = false
	if o.map.get("indoor", false):
		gs.bike = false
	# Fly remembers every town you've been to.
	if DB.FLY_POINTS.has(o.map.id) and not gs.fly.has(o.map.id):
		gs.fly.append(o.map.id)
	if o.map.has("mirage"):
		o.field.mirage = mirage_visible(gs)
	if o.map.get("trickHouse", false):
		Trick.on_enter(o)
	Shoal.on_map_loaded(o)
	_move_roamers(gs)

# ---------- bumping into things ----------
## Called when the player walks into a tile they can't enter. True if something happened.
static func on_bump(o: OverworldScene, dir: String, tx: int, ty: int) -> bool:
	var t := tile(o, tx, ty)
	if t == "O" and o.field.strength:
		var d: Vector2i = OverworldScene.DX[dir]
		var bx := tx + d.x
		var by := ty + d.y
		var beyond := tile(o, bx, by)
		if Maps.WALKABLE.has(beyond) and not blocked(o, bx, by) and o._npc_at(bx, by) == null:
			o.field.boulders[_key(tx, ty)] = _floor(o)
			o.field.boulders[_key(bx, by)] = "O"
			Audio.sfx("bump")
			return true
	return false

# ---------- interaction (A) ----------
## A pressed while standing somewhere special (Dive / surfacing). True if handled.
static func interact_here(o: OverworldScene) -> bool:
	var gs: Dictionary = Game.gs
	var here := Maps.tile_at(o.map, o.player.x, o.player.y)
	if here != "D":
		return false
	if surfing(o) and o.map.has("diveTo"):
		if knower("dive") == null or not has_badge_for("dive"):
			Game.say(["The sea is deep here. A creature may be able to go underwater."])
			return true
		Game.ask("The sea is deep here. Would you like to use Dive?", ["YES", "NO"], func(c: int) -> void:
			if c == 0:
				_announce("dive", func() -> void: _warp(o, o.map.diveTo, o.player.x, o.player.y, o.player.dir, false)))
		return true
	if o.map.get("underwater", false) and o.map.has("surfaceTo"):
		Game.ask("Light is filtering down from above. Would you like to surface?", ["YES", "NO"], func(c: int) -> void:
			if c == 0:
				_warp(o, o.map.surfaceTo, o.player.x, o.player.y, o.player.dir, true))
		return true
	return false

## A pressed facing (tx, ty). True if a field feature answered.
static func interact(o: OverworldScene, tx: int, ty: int) -> bool:
	var gs: Dictionary = Game.gs
	var k := _key(tx, ty)
	# Items on the ground, visible or hidden.
	for it in o.map.get("items", []):
		if it.x == tx and it.y == ty and not gs.flags.get(it.id, false):
			gs.flags[it.id] = true
			gs.bag[it.item] = gs.bag.get(it.item, 0) + int(it.count)
			Audio.sfx("item")
			var name: String = DB.item(it.item).name
			Game.say(["%s found %s%s!" % [gs.players[0].name, name, (" x%d" % it.count) if it.count > 1 else ""],
				"%s put the %s in the %s pocket." % [gs.players[0].name, name, Menus.POCKET_NAMES[Menus.pocket_of(it.item)]]])
			return true
	for s in _statics(o):
		if s.x == tx and s.y == ty:
			_static_battle(o, s)
			return true
	if (o.map.get("soil", []).has(k) or o.map.get("berries", {}).has(k)) and not _mirage_hidden(o, k):
		_soil(o, k)
		return true
	if o.map.get("trickHouse", false) and Trick.interact(o, k):
		return true
	if tile(o, tx, ty) == "Y":
		GameCorner.slots(o)
		return true
	if o.map.has("shoal") and Shoal.interact(o, tx, ty):
		return true
	if Legends.interact(o, tx, ty) or Legends.triangle_interact(o, tx, ty):
		return true
	if tile(o, tx, ty) == "N":
		Tv.watch()
		return true
	if tile(o, tx, ty) == "G":
		Museum.view(o, tx)
		return true
	var t := tile(o, tx, ty)
	match t:
		"T":
			_obstacle(o, "cut", "This tree looks like it can be cut down!", func() -> void:
				o.field.cleared[k] = _floor(o))
			return true
		"R":
			_obstacle(o, "rockSmash", "It's a rugged rock, but a creature may be able to smash it.", func() -> void:
				o.field.cleared[k] = _floor(o))
			return true
		"O":
			if o.field.strength:
				Game.say(["Strength made it possible to move boulders around."])
			else:
				_obstacle(o, "strength", "It's a big boulder, but a creature may be able to push it aside.", func() -> void:
					o.field.strength = true)
			return true
		"W":
			if surfing(o) and o.player.dir == "up":
				_obstacle(o, "waterfall", "It's a large waterfall.", func() -> void: _climb_waterfall(o))
			else:
				Game.say(["A wall of water is crashing down with a mighty roar."])
			return true
		"~", "D":
			if not surfing(o) and not o.map.get("underwater", false):
				_obstacle(o, "surf", "The water is dyed a deep blue...", func() -> void: _start_surf(o, tx, ty), "Would you like to Surf?")
				return true
		"z":
			SecretBase.interact_tree(o, tx, ty)
			return true
		"Q":
			if o.map.get("secretBase", false):
				SecretBase.open_pc(o)
				return true
	if o.map.get("secretBase", false):
		return SecretBase.interact_decoration(o, tx, ty)
	return false

## Shared HM prompt: "<what>" then, with the badge and a creature that knows the move, "Would you like to use X?"
static func _obstacle(o: OverworldScene, move_id: String, what: String, act: Callable, question: String = "") -> void:
	var m: Variant = knower(move_id)
	var mv_name: String = DB.move(move_id).name
	if m == null or not has_badge_for(move_id):
		Game.say([what])
		return
	Game.ask(what + " " + (question if question != "" else "Would you like to use %s?" % mv_name), ["YES", "NO"], func(c: int) -> void:
		if c == 0:
			_announce(move_id, act, m))

static func _announce(move_id: String, act: Callable, m: Variant = null) -> void:
	if m == null:
		m = knower(move_id)
	var nm: String = Creatures.display_name(m) if m != null else "Your creature"
	Audio.sfx("confirm")
	Game.say(["%s used %s!" % [nm, DB.move(move_id).name]], act)

static func _start_surf(o: OverworldScene, tx: int, ty: int) -> void:
	var gs: Dictionary = Game.gs
	gs.surfing = true
	gs.bike = false
	_hop(o, tx, ty)

## Moves the player one tile with a little hop (getting on or off the water).
static func _hop(o: OverworldScene, tx: int, ty: int) -> void:
	var p := o.player
	p.move = {"fx": p.x, "fy": p.y, "t": 0.0, "dur": OverworldScene.WALK, "jump": true}
	p.x = tx
	p.y = ty

static func _climb_waterfall(o: OverworldScene) -> void:
	var st := {"wait": 0.0}
	o._script = func(dt: float) -> bool:
		if o.player.move != null:
			o._advance(o.player, dt)
			return false
		var p := o.player
		var gs: Dictionary = Game.gs
		gs.x = p.x
		gs.y = p.y
		var next := tile(o, p.x, p.y - 1)
		if Maps.tile_at(o.map, p.x, p.y) == "W" or next == "W":
			p.dir = "up"
			p.move = {"fx": p.x, "fy": p.y, "t": 0.0, "dur": OverworldScene.WALK, "jump": false}
			p.y -= 1
			return false
		return true

## Warp to another map, keeping surf state (Dive, surfacing, Fly, Escape Rope).
static func _warp(o: OverworldScene, map_id: String, x: int, y: int, dir: String, surf: bool) -> void:
	var gs: Dictionary = Game.gs
	Audio.sfx("door")
	Game.transition(func() -> void:
		gs.surfing = surf
		o.load_map(map_id, x, y, dir)
		gs.x = x
		gs.y = y
		gs.dir = dir)

# ---------- legendaries waiting in place ----------
static func _static_battle(o: OverworldScene, s: Dictionary) -> void:
	Game.say(s.get("text", ["..."]) if s.get("text") is Array else [s.get("text", "...")], func() -> void:
		Audio.sfx("encounter")
		var mon := Creatures.create_creature(s.species, s.level, {"owner": 9})
		o._flash_then(func() -> void:
			o._run_battle({"kind": "wild", "double": false, "wild": [mon], "static": s})))

# ---------- roaming legendaries ----------
static func _routes() -> Array:
	var out: Array = []
	for id in DB.MAPS:
		if DB.MAPS[id].has("route") and DB.MAPS[id].has("encounters") and not DB.MAPS[id].encounters.is_empty():
			out.append(id)
	return out

## After becoming Champion, the roaming legendaries move to a random route whenever you change maps.
static func _move_roamers(gs: Dictionary) -> void:
	if not gs.flags.get("champion", false):
		return
	if not gs.flags.get("roamers_released", false):
		gs.flags.roamers_released = true
		for sp in DB.ROAMERS:
			gs.roamers[sp] = {"map": "", "level": 50, "hp": -1}
	var routes := _routes()
	for sp in gs.roamers:
		gs.roamers[sp].map = routes[Rng.global_rng.int_below(routes.size())]

## The roamer on this map, if any: {species, data}.
static func _roamer_here(o: OverworldScene) -> Variant:
	var gs: Dictionary = Game.gs
	for sp in gs.roamers:
		if gs.roamers[sp].map == o.map.id:
			return {"species": sp, "data": gs.roamers[sp]}
	return null

# ---------- steps ----------
## Called after every step. True if it took over (a dialog or a warp started).
static func on_step(o: OverworldScene) -> bool:
	var gs: Dictionary = Game.gs
	gs.steps = int(gs.get("steps", 0)) + 1
	var here := Maps.tile_at(o.map, o.player.x, o.player.y)
	if surfing(o) and Maps.WALKABLE.has(here):
		gs.surfing = false
	var took := false
	# Friendship grows as you walk together.
	if gs.steps % 128 == 0:
		for m in party():
			Creatures.add_friendship(m, 1)
	if gs.steps % 256 == 0:
		_ready_rematch(gs)
	if gs.repel > 0:
		gs.repel -= 1
		if gs.repel == 0:
			Game.say(["Repel's effect wore off..."])
			took = true
	DayCare.on_step(gs)
	Pokerus.on_step(gs)
	TownLife.on_step(o, here)
	Legends.on_step(o)
	if Eggs.on_step(gs):
		took = true
	if not took and MatchCall.on_step(gs):
		took = true
	if gs.safari != null and o.map.get("safari", false):
		gs.safari.steps -= 1
		if gs.safari.steps <= 0:
			_end_safari(o, "PA: Ding-dong! Time's up! Please return to the gate.")
			return true
	return took

## Wild encounters on grass, water, cave floors and the seafloor. True if a battle starts.
static func encounter(o: OverworldScene, t: String) -> bool:
	var gs: Dictionary = Game.gs
	var m: Dictionary = o.map
	var table: Array = []
	var rate: int = m.get("encounterRate", 20)
	var extra := {}
	if surfing(o) and m.has("waterEncounters"):
		table = m.waterEncounters
		rate = 4
		extra.location = "water"
	elif t == "," and m.has("encounters"):
		table = TownLife.outbreak_table(o, m.encounters)
	elif m.get("cave", false) and m.has("encounters") and (t == "g" or t == "D"):
		table = m.encounters
		extra.location = "underwater" if m.get("underwater", false) else "cave"
	if table.is_empty():
		return false
	var lead_mon: Variant = lead()
	# Held items and abilities of the lead change the rate, as in Emerald.
	if lead_mon != null:
		var ab: String = Creatures.ability_of(lead_mon)
		if ab == "stench" or ab == "whiteSmoke" or (ab == "sandVeil" and m.get("weather", "") == "sand"):
			rate /= 2
		if ab == "illuminate" or ab == "arenaTrap":
			rate *= 2
		if lead_mon.get("item", null) == "cleanseTag":
			rate = rate * 2 / 3
	rate = TownLife.flute_rate(rate)
	if Rng.global_rng.int_below(2880) >= rate * 16:
		return false
	# A roamer on this route shows up in a quarter of the encounters.
	var roamer: Variant = _roamer_here(o)
	if roamer != null and t == "," and Rng.global_rng.int_below(4) == 0:
		var r: Dictionary = roamer.data
		var mon := Creatures.create_creature(roamer.species, r.level, {"owner": 9})
		if r.hp >= 0:
			mon.hp = mini(int(r.hp), Creatures.max_hp(mon))
		Audio.sfx("encounter")
		o._flash_then(func() -> void: o._run_battle({"kind": "wild", "double": false, "wild": [mon], "roamer": roamer.species}))
		return true
	if m.get("safari", false) and gs.safari != null:
		extra.kind = "safari"
	return o._start_wild(table, extra)

## Repel and Intimidate/Keen Eye: a wild creature this weak doesn't come out. Called for each wild creature.
static func repelled(level: int) -> bool:
	var gs: Dictionary = Game.gs
	var lead_mon: Variant = lead()
	if lead_mon == null:
		return false
	if gs.repel > 0 and level < int(lead_mon.level):
		return true
	var ab: String = Creatures.ability_of(lead_mon)
	if (ab == "intimidate" or ab == "keenEye") and level <= int(lead_mon.level) - 5 and Rng.global_rng.int_below(2) == 0:
		return true
	return false

# ---------- battles ----------
## Fills in battle options from the map: weather, where it is, the Safari Zone.
static func prepare_battle(o: OverworldScene, setup: Dictionary) -> void:
	if Game.gs.get("pyramid") != null:
		setup.noPrize = true
		setup.noExp = true
	var w: String = o.map.get("weather", "")
	if not setup.has("weather"):
		setup.weather = {"rain": "rain", "sand": "sand", "sun": "sun"}.get(w, null)
	if not setup.has("location"):
		if surfing(o):
			setup.location = "water"
		elif o.map.get("underwater", false):
			setup.location = "underwater"
		elif o.map.get("cave", false):
			setup.location = "cave"

## After any overworld battle (before the usual win/lose handling). Adds lines to msgs.
static func after_battle(o: OverworldScene, setup: Dictionary, result: String, battle, trainer: Variant, msgs: Array) -> void:
	var gs: Dictionary = Game.gs
	var caught_it: bool = not battle.caught.is_empty()
	if setup.has("static"):
		if caught_it or result == "win":
			gs.flags[setup.static.id] = true
			# The Eon creature on Southern Island stops roaming once it's caught or beaten there.
			if setup.static.get("eon", false):
				gs.roamers.erase(setup.static.species)
	if setup.has("roamer"):
		var sp: String = setup.roamer
		if caught_it or result == "win":
			gs.roamers.erase(sp)
		elif gs.roamers.has(sp):
			var foe: Variant = battle.battlers[1][0].mon
			if foe != null:
				gs.roamers[sp].hp = foe.hp
			msgs.append("%s fled!" % DB.species(sp).name)
	if setup.has("rematch") and result == "win":
		gs.rematch[trainer.id] = int(gs.rematch.get(trainer.id, 0)) + 1
		gs.flags.erase("ready_" + trainer.id)
	if setup.get("kind", "") == "safari" and gs.safari != null and gs.safari.balls <= 0:
		_end_safari(o, "")
	if result == "lose":
		gs.safari = null
		gs.surfing = false
	if result != "ran" or setup.get("kind", "") == "trainer":
		Pokerus.after_battle(gs, GameState.all_party_mons(gs), msgs)
	if trainer != null and result == "win" and not setup.has("rematch"):
		MatchCall.after_win(gs, trainer, msgs)
	# A gym leader also hands over their TM.
	if trainer != null and result == "win" and trainer.get("badge") and not setup.has("rematch"):
		var tm: String = DB.GYM_TMS.get(str(trainer.badge), "")
		if tm != "" and not gs.flags.get("gymtm%d" % trainer.badge, false):
			gs.flags["gymtm%d" % trainer.badge] = true
			gs.bag[tm] = gs.bag.get(tm, 0) + 1
			# Shown after the badge message.
			var late: Array = []
			setup.lateMsgs = late
			late.append("%s received %s from %s!" % [gs.players[0].name, DB.item(tm).name, trainer.name])
			var hm_move := ""
			for mv in DB.HM_BADGES:
				if int(DB.HM_BADGES[mv]) == int(trainer.badge):
					hm_move = mv
			if hm_move != "":
				late.append("With this badge, creatures can use %s outside of battle." % DB.move(hm_move).name)

## Losing a battle normally sends you back to the last Rest Lodge. True if something else happens instead
## (losing in the Battle Pyramid ends the run at its entrance).
static func on_whiteout(o: OverworldScene) -> bool:
	if Game.gs.get("pyramid") != null:
		Frontier.pyramid_lost(o)
		return true
	return false

## Pickup: creatures with the Pickup ability sometimes find an item after a battle.
static func pickup(gs: Dictionary, mons: Array) -> Array:
	var out: Array = []
	for m in mons:
		if m.get("egg", false) or m.get("item", null) != null or Creatures.ability_of(m) != "pickup":
			continue
		if Rng.global_rng.int_below(10) != 0:
			continue
		var table: Array = PICKUP_TABLE[0][1]
		for row in PICKUP_TABLE:
			if int(m.level) >= int(row[0]):
				table = row[1]
		var id: String = table[mini(table.size() - 1, Rng.global_rng.int_below(table.size()))]
		if DB.ITEMS.has(id):
			m.item = id
			out.append("%s picked up %s!" % [Creatures.display_name(m), DB.item(id).name])
	return out

# ---------- trainer rematches ----------
## Every 256 steps a beaten trainer may want a rematch (gym leaders only after becoming Champion).
static func _ready_rematch(gs: Dictionary) -> void:
	var beaten: Array = []
	var champion: bool = gs.flags.get("champion", false)
	for mid in DB.MAPS:
		for t in DB.MAPS[mid].get("trainers", []):
			if not gs.flags.get(t.id, false) or gs.flags.get("ready_" + t.id, false):
				continue
			if t.get("champion", false) or t.get("leaveAfter", false) or str(t.id).begins_with("elite") or str(t.id).begins_with("order_") or str(t.id).contains("rival") or str(t.id).begins_with("pyr_"):
				continue
			if t.get("badge") and not champion:
				continue
			beaten.append(t.id)
	if beaten.is_empty():
		return
	var ready := 0
	for f in gs.flags:
		if str(f).begins_with("ready_"):
			ready += 1
	if ready >= 6:
		return
	var pick: String = beaten[Rng.global_rng.int_below(beaten.size())]
	gs.flags["ready_" + pick] = true
	MatchCall.queue_ready(gs, pick)

static func rematch_ready(gs: Dictionary, t: Dictionary) -> bool:
	return gs.flags.get("ready_" + t.id, false)

## Offers a rematch with a beaten trainer who's ready. True if it took over the interaction.
static func offer_rematch(o: OverworldScene, n) -> bool:
	var gs: Dictionary = Game.gs
	var t: Dictionary = n.trainer
	if not rematch_ready(gs, t):
		return false
	Game.ask("%s: Hey! Let's battle again! I've been training." % t.name, ["YES", "NO"], func(c: int) -> void:
		if c != 0:
			return
		var times: int = int(gs.rematch.get(t.id, 0)) + 1
		var boost: int = 4 * times + (12 if t.get("badge") else 0)
		var party: Array = []
		for e in t.party:
			party.append(Creatures.create_creature(e[0], mini(100, int(e[1]) + boost), {"owner": 9}))
		var t2: Dictionary = t.duplicate()
		for k in ["leaveAfter", "badge", "champion"]:
			t2.erase(k)
		var setup := {"kind": "trainer", "double": t.get("double", false), "trainer": t2, "trainerParty": party, "rematch": true}
		prepare_battle(o, setup)
		o._flash_then(func() -> void: o._run_battle(setup, t2)), 0)
	return true

## Trainers ready for a rematch, as "Name (Map)" strings, for the Navi Gear.
static func ready_trainers(gs: Dictionary) -> Array:
	var out: Array = []
	for mid in DB.MAPS:
		for t in DB.MAPS[mid].get("trainers", []):
			if gs.flags.get("ready_" + t.id, false):
				out.append("%s (%s)" % [t.name, DB.MAPS[mid].name])
	return out

# ---------- party menu field moves ----------
static func use_field_move(player: int, m: Dictionary, move_id: String, close: Callable) -> void:
	var o := ow()
	var gs: Dictionary = Game.gs
	if o == null:
		return
	var nm := Creatures.display_name(m)
	var cant := func() -> void: Game.say(["You can't use that here."], Callable(), player)
	if gs.get("pyramid") != null and move_id in ["fly", "teleport", "dig"]:
		cant.call()
		return
	if DB.HM_BADGES.has(move_id) and not has_badge_for(move_id):
		Game.say(["You need the right badge to use %s outside of battle." % DB.move(move_id).name], Callable(), player)
		return
	match move_id:
		"fly":
			if o.map.get("indoor", false) or o.map.get("cave", false):
				cant.call()
				return
			open_fly_menu(player, func(town: String) -> void:
				close.call()
				Game.say(["%s used Fly!" % nm], func() -> void: fly_to(o, town), player))
		"flash":
			if not o.map.get("dark", false) or o.field.flash:
				cant.call()
				return
			close.call()
			Game.say(["%s used Flash!" % nm], func() -> void: o.field.flash = true, player)
		"teleport":
			if o.map.get("indoor", false) and not o.map.get("cave", false):
				cant.call()
				return
			close.call()
			Game.say(["%s used Teleport!" % nm], func() -> void:
				var r: Dictionary = gs.respawn
				_warp(o, r.map, r.x, r.y, "down", false), player)
		"dig":
			if not can_escape(gs):
				cant.call()
				return
			close.call()
			Game.say(["%s used Dig!" % nm], func() -> void: escape(player), player)
		"sweetScent":
			close.call()
			Game.say(["%s used Sweet Scent!" % nm], func() -> void:
				var t := Maps.tile_at(o.map, o.player.x, o.player.y)
				var table: Array = o.map.get("waterEncounters", []) if surfing(o) else o.map.get("encounters", [])
				if table.is_empty() or (t != "," and not surfing(o) and not o.map.get("cave", false)):
					Game.say(["Looks like there's nothing here..."], Callable(), player)
				else:
					o._start_wild(table, {}), player)
		"softBoiled", "milkDrink":
			var cost: int = Creatures.max_hp(m) / 5
			if m.hp <= cost:
				Game.say(["Not enough HP..."], Callable(), player)
				return
			var ps := PartyScreen.new({"player": player, "party": party(player), "prompt": "Use on which creature?"})
			ps.o.on_cancel = func() -> void: Game.pop(ps)
			ps.o.on_select = func(i: int) -> void:
				var t: Dictionary = party(player)[i]
				if is_same(t, m) or t.hp <= 0 or t.hp >= Creatures.max_hp(t) or t.get("egg", false):
					Game.say(["It won't have any effect."], Callable(), player)
					return
				m.hp -= cost
				t.hp = mini(Creatures.max_hp(t), t.hp + cost)
				Audio.sfx("recover")
				Game.say(["%s's HP was restored." % Creatures.display_name(t)], func() -> void: Game.pop(ps), player)
			Game.push(ps)
		"secretPower":
			var d: Vector2i = OverworldScene.DX[o.player.dir]
			if tile(o, o.player.x + d.x, o.player.y + d.y) != "z":
				cant.call()
				return
			close.call()
			SecretBase.interact_tree(o, o.player.x + d.x, o.player.y + d.y)
		_:
			# Cut, Surf, Strength, Rock Smash, Waterfall, Dive: face the obstacle and press A.
			var d: Vector2i = OverworldScene.DX[o.player.dir]
			close.call()
			if move_id == "dive":
				if not interact_here(o):
					cant.call()
			elif not interact(o, o.player.x + d.x, o.player.y + d.y):
				cant.call()

# ---------- Fly / Navi Gear ----------
static func open_fly_menu(player: int, on_pick: Callable) -> void:
	var ref := {}
	var scene := TownMapScene.new(player, true, func(town: String) -> void:
		Game.pop(ref.s)
		on_pick.call(town), func() -> void: Game.pop(ref.s))
	ref.s = scene
	Game.push(scene)

static func open_town_map(player: int, on_close: Callable) -> void:
	var ref := {}
	var scene := TownMapScene.new(player, false, Callable(), func() -> void:
		Game.pop(ref.s)
		on_close.call())
	ref.s = scene
	Game.push(scene)

static func fly_to(o: OverworldScene, town: String) -> void:
	var p: Dictionary = DB.FLY_POINTS[town]
	var spot := nearest_walkable(DB.MAPS[town], int(p.x), int(p.y))
	_warp(o, town, spot.x, spot.y, "down", false)

static func nearest_walkable(m: Dictionary, x: int, y: int) -> Vector2i:
	for r in 6:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var t := Maps.tile_at(m, x + dx, y + dy)
				if Maps.WALKABLE.has(t) and not "hlmjud".contains(t):
					return Vector2i(x + dx, y + dy)
	return Vector2i(x, y)

## The Navi Gear: the region map and Match Call.
static func open_navi(player: int, on_close: Callable) -> void:
	Game.ask("Navi Gear. It's %s." % Options.clock_text(), ["MAP", "MATCH CALL", "CANCEL"], func(c: int) -> void:
		if c == 0:
			open_town_map(player, func() -> void: open_navi(player, on_close))
		elif c == 1:
			MatchCall.open(player, func() -> void: open_navi(player, on_close))
		elif on_close.is_valid():
			on_close.call(), player)

# ---------- key items ----------
static func use_key_item(player: int, id: String, close: Callable) -> void:
	var gs: Dictionary = Game.gs
	var o := ow()
	var eff: Dictionary = DB.item(id).effect
	match eff.get("use", ""):
		"bike":
			if o == null or o.map.get("indoor", false) or surfing(o):
				Game.say(["You can't ride your bike here."], Callable(), player)
				return
			gs.bike = not gs.get("bike", false)
			close.call()
			Game.say(["%s got on the Bicycle." % gs.players[player].name if gs.bike else "%s got off the Bicycle." % gs.players[player].name], Callable(), player)
		"fish":
			close.call()
			fish(o, eff.rod)
		"water":
			close.call()
			if o == null:
				return
			var d: Vector2i = OverworldScene.DX[o.player.dir]
			var k := _key(o.player.x + d.x, o.player.y + d.y)
			if not water_berry(o, k):
				Game.say(["There's nothing to water here."], Callable(), player)
		"navi":
			open_navi(player, Callable())
		"finder":
			close.call()
			itemfinder(o)
		"coins":
			Game.say(["Your Coin Case holds %d coins." % int(gs.get("coins", 0))], Callable(), player)
		"blocks":
			Contest.open_block_case(player)
		"ash":
			Game.say(["The Soot Sack holds %d ash." % int(gs.ash)], Callable(), player)
		"flute":
			close.call()
			TownLife.play_flute(id)
		_:
			Game.say([DB.item(id).desc], Callable(), player)

# ---------- Itemfinder ----------
## Points toward the nearest hidden item on screen, or digs it up if you're standing on it.
static func itemfinder(o: OverworldScene) -> void:
	if o == null:
		return
	var gs: Dictionary = Game.gs
	var best: Variant = null
	var best_d := 999
	for it in o.map.get("items", []):
		if not it.hidden or gs.flags.get(it.id, false):
			continue
		var d := absi(int(it.x) - o.player.x) + absi(int(it.y) - o.player.y)
		if absi(int(it.x) - o.player.x) <= 7 and absi(int(it.y) - o.player.y) <= 5 and d < best_d:
			best = it
			best_d = d
	Audio.sfx("spotted" if best != null else "bump")
	if best == null:
		Game.say(["... ... ...", "Nope! There's no response."])
		return
	if best_d == 0:
		Game.say(["... ... ... Beep! Beep!", "There's an item buried right here!"], func() -> void: interact(o, best.x, best.y))
		return
	var dx := int(best.x) - o.player.x
	var dy := int(best.y) - o.player.y
	var dir := ""
	if absi(dx) >= absi(dy):
		dir = "right" if dx > 0 else "left"
	else:
		dir = "down" if dy > 0 else "up"
	o.player.dir = dir
	Game.say(["... ... ... Beep! Beep!", "There's a response! It's coming from %s!" % {"up": "the north", "down": "the south", "left": "the west", "right": "the east"}[dir]])

# ---------- fishing ----------
static func fish(o: OverworldScene, rod: String) -> void:
	if o == null:
		return
	var d: Vector2i = OverworldScene.DX[o.player.dir]
	var t := tile(o, o.player.x + d.x, o.player.y + d.y)
	if not (t == "~" or t == "D") and not surfing(o):
		Game.say(["You can't fish here. Face the water first."])
		return
	var table: Array = TownLife.fishing_table(o, o.player.x + d.x, o.player.y + d.y, o.map.get("fishing", {}).get(rod, []))
	Game.say(["... ... ..."], func() -> void:
		# Better rods get bites more often.
		var bite: int = {"old": 70, "good": 80, "super": 90}.get(rod, 70)
		if table.is_empty() or Rng.global_rng.int_below(100) >= bite:
			Game.say(["Not even a nibble..."])
			return
		Audio.sfx("spotted")
		Game.say(["Oh! A bite!"], func() -> void:
			o._start_wild(table, {"location": "water", "fishing": true})))

# ---------- Escape Rope / Dig ----------
static func can_escape(gs: Dictionary) -> bool:
	var o := ow()
	return gs.get("pyramid") == null and o != null and o.map.get("cave", false) and gs.has("lastOutside")

static func escape(_player: int) -> void:
	var o := ow()
	var gs: Dictionary = Game.gs
	var r: Dictionary = gs.lastOutside
	_warp(o, r.map, r.x, r.y, "down", false)

## Called before a warp. Remembers where you went into a cave, for Escape Rope and Dig.
## Returns true if a warp script took over (the Safari Zone gate, the Secret Base door).
static func before_warp(o: OverworldScene, warp: Dictionary) -> bool:
	var gs: Dictionary = Game.gs
	var dest: Dictionary = DB.MAPS[warp.map]
	if dest.get("cave", false) and not o.map.get("cave", false):
		gs.lastOutside = {"map": o.map.id, "x": o.player.x, "y": o.player.y + 1}
	match warp.get("script", ""):
		"safari":
			_safari_gate(o, warp)
			return true
		"safariExit":
			gs.safari = null
		"trickDone":
			Trick.solved(int(warp.level))
		"pyramidUp":
			Frontier.pyramid_next_floor(o)
			return true
		"baseExit":
			var b: Variant = gs.secretBase
			if b != null:
				_warp(o, b.map, int(b.x), int(b.y) + 1, "down", false)
				return true
	return false

# ---------- Safari Zone ----------
static func _safari_gate(o: OverworldScene, warp: Dictionary) -> void:
	var gs: Dictionary = Game.gs
	var back := func() -> void:
		o.player.y += 1
		o.player.dir = "down"
		gs.y = o.player.y
	Game.ask("Welcome to the Safari Zone! It's $500 to play. You get 30 Safari Orbs and 500 steps. Would you like to play?",
		["YES", "NO"], func(c: int) -> void:
			if c != 0:
				back.call()
				return
			if gs.money < 500:
				Game.say(["You don't have enough money."], back)
				return
			gs.money -= 500
			gs.safari = {"steps": 500, "balls": 30, "map": o.map.id, "x": o.player.x, "y": o.player.y + 1}
			Game.say(["Here are your 30 Safari Orbs. Good luck!"], func() -> void:
				_warp(o, warp.map, warp.x, warp.y, warp.dir, false)))

static func _end_safari(o: OverworldScene, text: String) -> void:
	var gs: Dictionary = Game.gs
	var back: Dictionary = gs.safari if gs.safari != null else {"map": "saltmarsh", "x": 5, "y": 5}
	gs.safari = null
	var go := func() -> void: _warp(o, back.map, int(back.x), int(back.y), "down", false)
	if text != "":
		Game.say([text], go)
	else:
		go.call()

# ---------- berries ----------
static func _berry_entry(o: OverworldScene, k: String) -> Dictionary:
	var gs: Dictionary = Game.gs
	var bm: Dictionary = gs.berries.get(o.map.id, {})
	if bm.has(k):
		return bm[k]
	# Berry trees placed on the map start out fully grown.
	var start: Variant = o.map.get("berries", {}).get(k, null)
	if start != null:
		return {"berry": start, "t": 0, "water": 2}
	return {}

static func _set_berry(o: OverworldScene, k: String, e: Dictionary) -> void:
	var gs: Dictionary = Game.gs
	if not gs.berries.has(o.map.id):
		gs.berries[o.map.id] = {}
	gs.berries[o.map.id][k] = e

## 0 (just planted) .. 4 (ready), from the real-time clock and the berry's growth time.
static func berry_stage(e: Dictionary) -> int:
	if e.is_empty() or e.get("berry", null) == null:
		return -1
	var hours: float = float(DB.item(e.berry).get("growHours", 4))
	var elapsed: float = float(Options.now() - int(e.t)) / 3600.0
	return clampi(int(elapsed / hours * 4.0), 0, 4)

static func berry_color(id: String) -> String:
	return BERRY_COLORS[absi(hash(id)) % BERRY_COLORS.size()]

static func _soil(o: OverworldScene, k: String) -> void:
	var gs: Dictionary = Game.gs
	var e := _berry_entry(o, k)
	var stage := berry_stage(e)
	if stage < 0:
		var have: Array = []
		for id in gs.bag:
			if gs.bag[id] > 0 and DB.ITEMS.has(id) and DB.item(id).effect.kind == "berry":
				have.append(id)
		if have.is_empty():
			Game.say(["It's soft, loamy soil."])
			return
		Game.ask("It's soft, loamy soil. Want to plant a berry?", ["YES", "NO"], func(c: int) -> void:
			if c != 0:
				return
			Menus.open_bag({"player": 0, "in_battle": false, "can_throw": false, "pocket": 2, "on_close": func() -> void: pass,
				"usable": func(id: String) -> bool: return DB.item(id).effect.kind == "berry",
				"on_pick": func(id: String, done: Callable) -> void:
					gs.bag[id] -= 1
					_set_berry(o, k, {"berry": id, "t": Options.now(), "water": 0})
					done.call()
					Game.say(["%s planted one %s in the soft soil." % [gs.players[0].name, DB.item(id).name]])}))
		return
	var name: String = DB.item(e.berry).name
	if stage < 4:
		var words: Array = ["One %s was planted here." % name, "%s has sprouted." % name, "This %s plant is growing taller." % name, "These %s flowers are blooming." % name]
		var lines: Array = [words[stage]]
		if gs.bag.get("wailmerPail", 0) > 0 and int(e.water) < 3:
			lines.append("Water it with the Watering Can from your BAG to grow more berries.")
		Game.say(lines)
		return
	var count: int = 2 + int(e.water) + Rng.global_rng.int_below(2)
	Game.ask("There are %d %s! Want to pick them?" % [count, name], ["YES", "NO"], func(c: int) -> void:
		if c != 0:
			return
		gs.bag[e.berry] = gs.bag.get(e.berry, 0) + count
		_set_berry(o, k, {"berry": null})
		Audio.sfx("item")
		Game.say(["%s picked the %d %s." % [gs.players[0].name, count, name], "The soil returned to its soft and loamy state."]))

static func water_berry(o: OverworldScene, k: String) -> bool:
	var e := _berry_entry(o, k)
	var stage := berry_stage(e)
	if stage < 0 or stage >= 4:
		return false
	e = e.duplicate()
	e.water = mini(3, int(e.water) + 1)
	_set_berry(o, k, e)
	Game.say(["%s watered the plant. The plant seemed delighted." % Game.gs.players[0].name])
	return true

# ---------- drawing ----------
## Ground layer, drawn after the tiles and before people: items, berry plants, legendaries, decorations, the surf blob.
static func draw_ground(o: OverworldScene, cam_x: int, cam_y: int) -> void:
	var gs: Dictionary = Game.gs
	for it in o.map.get("items", []):
		if not it.hidden and not gs.flags.get(it.id, false):
			Gfx.image(FieldTiles.item_orb(), it.x * 16 - cam_x, it.y * 16 - cam_y)
	var spots: Array = o.map.get("soil", []).duplicate()
	for k in o.map.get("berries", {}):
		if not spots.has(k):
			spots.append(k)
	for k in spots:
		if _mirage_hidden(o, k):
			continue
		var e := _berry_entry(o, k)
		var stage := berry_stage(e)
		if stage >= 0:
			var p: PackedStringArray = k.split(",")
			Gfx.image(FieldTiles.berry_plant(stage, berry_color(e.berry)), int(p[0]) * 16 - cam_x, int(p[1]) * 16 - cam_y)
	for s in _statics(o):
		var spr: Texture2D = CreatureArt.creature_sprite(s.species)
		var bob := sin(Game.time * 2) * 1.5
		Gfx.image(spr, s.x * 16 - cam_x - 8, s.y * 16 - cam_y - 16 + bob, {"scale": 32.0 / spr.get_width()})
	if o.map.has("shoal"):
		Shoal.draw(o, cam_x, cam_y)
	Legends.draw(o, cam_x, cam_y)
	if o.map.get("secretBase", false) and gs.secretBase != null:
		for d in gs.secretBase.decor:
			var dd: Dictionary = DB.DECORATIONS[d.id]
			Gfx.image(FieldTiles.decoration(d.id, dd.color), d.x * 16 - cam_x, d.y * 16 - cam_y)
	if surfing(o):
		var ap := OverworldScene.actor_pixel(o.player)
		var bob := sin(Game.time * 4) * 1.0
		Gfx.rect(ap.x - cam_x + 1, ap.y - cam_y + 8 + bob, 14, 7, "#305890")
		Gfx.rect(ap.x - cam_x + 2, ap.y - cam_y + 7 + bob, 12, 6, "#78a8e8")
		Gfx.rect(ap.x - cam_x + 4, ap.y - cam_y + 8 + bob, 3, 1, "#d8f0ff")

## Top layer, drawn after people: weather, the dark of a cave without Flash, the underwater tint.
static func draw_overlay(o: OverworldScene, cam_x: int, cam_y: int) -> void:
	var tm := Game.time
	match o.map.get("weather", ""):
		"rain":
			Gfx.rect(0, 0, Gfx.W, Gfx.H, Color(0.2, 0.25, 0.45, 0.18))
			for i in 50:
				Gfx.rect(fmod(i * 37 + tm * 90 - cam_x * 0.0, Gfx.W), fmod(i * 23 + tm * 320, Gfx.H), 1, 6, Color(0.7, 0.8, 1.0, 0.7))
		"sand":
			Gfx.rect(0, 0, Gfx.W, Gfx.H, Color(0.85, 0.7, 0.35, 0.25))
			for i in 40:
				Gfx.rect(fmod(i * 41 + tm * 220, Gfx.W), fmod(i * 29 + tm * 30, Gfx.H), 2, 1, Color(0.95, 0.85, 0.55, 0.8))
		"ash":
			for i in 40:
				Gfx.rect(fmod(i * 41 + sin(tm + i) * 6, Gfx.W), fmod(i * 29 + tm * 25, Gfx.H), 2, 2, Color(0.55, 0.55, 0.55, 0.8))
		"fog":
			Gfx.rect(0, 0, Gfx.W, Gfx.H, Color(0.9, 0.9, 0.95, 0.35))
			for i in 4:
				Gfx.rect(fmod(i * 90 + tm * 8, Gfx.W + 120) - 120, 20 + i * 36, 120, 18, Color(1, 1, 1, 0.18))
	if o.map.get("underwater", false):
		Gfx.rect(0, 0, Gfx.W, Gfx.H, Color(0.1, 0.25, 0.6, 0.35))
	if o.map.get("dark", false):
		var ap := OverworldScene.actor_pixel(o.player)
		var cx: float = ap.x - cam_x + 8
		var cy: float = ap.y - cam_y + 8
		var r := 80.0 if o.field.flash else 22.0
		_dark_around(cx, cy, r)

static func _dark_around(cx: float, cy: float, r: float) -> void:
	var dark := Color(0, 0, 0, 0.92)
	Gfx.rect(0, 0, Gfx.W, maxf(0, cy - r), dark)
	Gfx.rect(0, cy + r, Gfx.W, maxf(0, Gfx.H - cy - r), dark)
	# Rows of the circle, so the lit area is round.
	var step := 2.0
	var yy := cy - r
	while yy < cy + r:
		var dy := absf(yy + step / 2 - cy)
		var half := sqrt(maxf(0, r * r - dy * dy))
		Gfx.rect(0, yy, maxf(0, cx - half), step, dark)
		Gfx.rect(cx + half, yy, maxf(0, Gfx.W - cx - half), step, dark)
		yy += step
