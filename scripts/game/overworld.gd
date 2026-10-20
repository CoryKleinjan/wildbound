class_name OverworldScene
extends Scene
## Tile-based overworld: movement, map connections, warps and doors, NPCs, trainers, wild encounters.

const DX := {"up": Vector2i(0, -1), "down": Vector2i(0, 1), "left": Vector2i(-1, 0), "right": Vector2i(1, 0)}
const OPP := {"up": "down", "down": "up", "left": "right", "right": "left"}
const WALK := 0.24
const RUN := 0.12

class Actor:
	var x: int
	var y: int
	var dir: String
	## null or {fx, fy, t, dur, jump}
	var move: Variant = null
	var step_count := 0
	var palette: String
	## Map NPC definition (MapNpc.npc) or trainer definition (MapNpc.trainer), when this actor is one.
	var npc: Variant = null
	var trainer: Variant = null
	func _init(x_: int, y_: int, dir_: String, palette_: String) -> void:
		x = x_
		y = y_
		dir = dir_
		palette = palette_

static func actor_pixel(a: Actor) -> Dictionary:
	if a.move == null:
		return {"x": a.x * 16.0, "y": a.y * 16.0, "hop": 0.0}
	var k := minf(1.0, a.move.t / a.move.dur)
	return {
		"x": (a.move.fx + (a.x - a.move.fx) * k) * 16.0,
		"y": (a.move.fy + (a.y - a.move.fy) * k) * 16.0,
		"hop": sin(k * PI) * 8.0 if a.move.jump else 0.0,
	}

var map: Dictionary
var player: Actor
var follower: Actor = null
var npcs: Array[Actor] = []
var _hold_time := 0.0
## Callable(dt) -> bool (true when finished), or an invalid Callable.
var _script := Callable()
var _banner := {"text": "", "t": 0.0}
## null or {a: Actor, t}
var _exclaim: Variant = null
var _frame := 0.0
var _flash_t := 0.0
## Story hooks run on the first update after a map loads (dialogs pushed earlier would be lost by Game.replace).
var _map_fresh := false
var _bump_t := 0.0
## This visit's field state (cut trees, pushed boulders, Flash, Strength): see Field.
var field: Dictionary = Field.fresh_state()

func _init() -> void:
	var gs: Dictionary = Game.gs
	load_map(gs.map, gs.x, gs.y, gs.dir)
	# Whoever is playing hosts, so a friend can drop in at any time.
	if Game.cur == 0 and Net.role == Net.Role.NONE:
		Net.host("%s's game" % gs.players[0].name)

var gs: Dictionary:
	get:
		return Game.gs

func load_map(id: String, x: int, y: int, dir: String) -> void:
	map = DB.MAPS[id]
	gs.map = id
	# The friend who joined (view 1) looks like player 2.
	player = Actor.new(x, y, dir, "p1" if Game.cur == 0 else "p2")
	if gs.mode == "coop":
		var d: Vector2i = DX[OPP[dir]]
		var fx := x + d.x
		var fy := y + d.y
		var ok := _walkable(fx, fy, true)
		follower = Actor.new(fx if ok else x, fy if ok else y, dir, "p2")
	else:
		follower = null
	npcs = []
	for n in map.get("npcs", []):
		# showIf / hideIf: story flags that make an NPC appear or leave.
		if n.has("showIf") and not gs.flags.get(n.showIf, false):
			continue
		if n.has("hideIf") and gs.flags.get(n.hideIf, false):
			continue
		var a := Actor.new(n.x, n.y, n.dir, n.palette)
		a.npc = n
		npcs.append(a)
	for t in map.get("trainers", []):
		if t.get("leaveAfter", false) and gs.flags.get(t.id, false):
			continue
		var a := Actor.new(t.x, t.y, t.dir, t.palette)
		a.trainer = t
		npcs.append(a)
	_banner = {"text": map.name, "t": 0.0 if map.get("interior", false) else 2.2}
	_map_fresh = true
	Field.on_map_loaded(self)
	Audio.play_music(map_track(map))

## Music for a map: gym, league, town or route (rooms inside buildings name theirs).
static func map_track(m: Dictionary) -> String:
	if m.has("music"):
		return m.music
	var id: String = m.id
	if id.begins_with("gym"):
		return "gym"
	if id == "league":
		return "league"
	if m.get("town", false):
		return "town"
	return "route"

## Adds a temporary actor for a story scene (not saved).
func add_actor(x: int, y: int, dir: String, palette: String) -> Actor:
	var a := Actor.new(x, y, dir, palette)
	npcs.append(a)
	return a

func remove_actor(a: Actor) -> void:
	npcs.erase(a)

## Shows the "!" bubble over an actor.
func exclaim(a: Actor) -> void:
	_exclaim = {"a": a, "t": 0.8}

func run_battle(setup: Dictionary, trainer: Variant = null) -> void:
	_flash_then(func() -> void: _run_battle(setup, trainer))

func _map_h() -> int:
	return map.tiles.size()

func _map_w() -> int:
	return (map.tiles[0] as String).length()

func _npc_at(x: int, y: int, except: Actor = null) -> Actor:
	for n in npcs:
		if n != except and n.x == x and n.y == y:
			return n
	return null

func _walkable(x: int, y: int, ignore_actors := false) -> bool:
	var t := Field.tile(self, x, y)
	var outside := y < 0 or x < 0 or y >= _map_h() or x >= _map_w()
	if outside:
		return false
	if not Maps.WALKABLE.has(t) and not Field.passable(self, t):
		return false
	if not ignore_actors and (_npc_at(x, y) != null or Field.blocked(self, x, y)):
		return false
	return true

func _can_leave(x: int, y: int, dir: String) -> bool:
	var h := _map_h()
	var w := _map_w()
	var conns: Dictionary = map.connections
	if dir == "up" and y < 0:
		return conns.has("up")
	if dir == "down" and y >= h:
		return conns.has("down")
	if dir == "left" and x < 0:
		return conns.has("left")
	if dir == "right" and x >= w:
		return conns.has("right")
	return false

func update(dt: float) -> void:
	_frame += dt
	_bump_t -= dt
	if _banner.t > 0:
		_banner.t -= dt
	if _exclaim != null:
		_exclaim.t -= dt
		if _exclaim.t <= 0:
			_exclaim = null
	for n in npcs:
		_advance(n, dt)
	if _map_fresh:
		_map_fresh = false
		Story.on_map_loaded(self)
		if Game.top != self:
			return
	if _script.is_valid():
		if _script.call(dt):
			_script = Callable()
		return
	var inp := Game.input
	var p1 := inp.p(0)
	if player.move != null or (follower != null and follower.move != null):
		var done := _advance(player, dt)
		if follower != null:
			_advance(follower, dt)
		if done:
			_on_step()
		return
	for pl in ([0, 1] if gs.mode == "coop" else [0]):
		if inp.p(pl).pressed("start"):
			_open_start_menu(pl)
			return
	if p1.pressed("a") or (gs.mode == "coop" and inp.p(1).pressed("a")):
		_interact()
		return
	var held := ""
	for d in ["up", "down", "left", "right"]:
		if p1.is_held(d):
			held = d
			break
	if held == "":
		_hold_time = 0
		return
	if held != player.dir and _hold_time == 0:
		player.dir = held
		_hold_time = 0.001
		return
	_hold_time += dt
	player.dir = held
	if _hold_time < 0.07:
		return
	_try_move(held, Field.step_time(self, RUN if p1.is_held("b") else WALK))

func _bump() -> void:
	if _bump_t <= 0:
		_bump_t = 0.35
		Audio.sfx("bump")

func _advance(a: Actor, dt: float) -> bool:
	if a.move == null:
		return false
	a.move.t += dt
	if a.move.t >= a.move.dur:
		a.move = null
		a.step_count += 1
		return true
	return false

func _try_move(dir: String, dur: float) -> void:
	var d: Vector2i = DX[dir]
	var p := player
	var tx := p.x + d.x
	var ty := p.y + d.y
	var jump := false
	var t := Maps.tile_at(map, tx, ty)
	if t == "v":
		if dir != "down" or not _walkable(tx, ty + 1):
			_bump()
			return
		ty += 1
		jump = true
		Audio.sfx("ledge")
	elif not _walkable(tx, ty) and not _can_leave(tx, ty, dir):
		if not Field.on_bump(self, dir, tx, ty):
			_bump()
		return
	if Story.intercept_move(self, dir, tx, ty):
		_hold_time = 0
		return
	var gate: Variant = map.get("exitGate")
	if gate != null and gate.side == dir and _can_leave(tx, ty, dir) and not gs.flags.get(gate.flag, false):
		_hold_time = 0
		Game.say(gate.text)
		return
	var league: Variant = map.get("leagueGate")
	if t == "u" and league != null and not gs.flags.get(league.flag, false):
		_hold_time = 0
		Game.say(league.text)
		return
	if follower != null:
		var f := follower
		if not (f.x == tx and f.y == ty):
			f.move = {"fx": f.x, "fy": f.y, "t": 0.0, "dur": dur * 2 if jump else dur, "jump": absi(f.x - p.x) + absi(f.y - p.y) > 1}
			if f.x < p.x:
				f.dir = "right"
			elif f.x > p.x:
				f.dir = "left"
			elif f.y < p.y:
				f.dir = "down"
			elif f.y > p.y:
				f.dir = "up"
			else:
				f.dir = dir
			f.x = p.x
			f.y = p.y
		else:
			# Walking back into the follower: swap places.
			f.move = {"fx": f.x, "fy": f.y, "t": 0.0, "dur": dur, "jump": false}
			f.dir = OPP[dir]
			f.x = p.x
			f.y = p.y
	p.move = {"fx": p.x, "fy": p.y, "t": 0.0, "dur": dur * 2 if jump else dur, "jump": jump}
	p.x = tx
	p.y = ty

func _on_step() -> void:
	var p := player
	gs.x = p.x
	gs.y = p.y
	gs.dir = p.dir
	# Map connections.
	var h := _map_h()
	var w := _map_w()
	if p.y < 0 or p.y >= h or p.x < 0 or p.x >= w:
		var conn: Dictionary = map.connections[p.dir]
		var next: Dictionary = DB.MAPS[conn.map]
		var nh: int = next.tiles.size()
		var nw: int = (next.tiles[0] as String).length()
		var vertical := p.dir == "up" or p.dir == "down"
		var nx: int
		var ny: int
		if vertical:
			nx = p.x + conn.offset
			ny = nh - 1 if p.dir == "up" else 0
		else:
			nx = nw - 1 if p.dir == "left" else 0
			ny = p.y + conn.offset
		load_map(conn.map, nx, ny, p.dir)
		gs.x = nx
		gs.y = ny
		return
	var t := Maps.tile_at(map, p.x, p.y)
	var warp: Variant = map.get("warps", {}).get("%d,%d" % [p.x, p.y])
	if warp != null and Field.before_warp(self, warp):
		return
	if warp != null:
		Audio.sfx("door")
		Game.transition(func() -> void:
			load_map(warp.map, warp.x, warp.y, warp.dir)
			gs.x = warp.x
			gs.y = warp.y
			gs.dir = warp.dir)
		return
	if Field.on_step(self):
		return
	if _check_trainers():
		return
	Field.encounter(self, t)

# ---------- buildings ----------
## What looking at a piece of furniture says (A while facing it).
const FURNITURE_TEXT := {
	"K": ["It's crammed with books about creatures."],
	"B": ["A soft, cozy bed. It looks freshly made."],
	"P": ["A potted plant. Someone waters it every day."],
	"q": ["The shelves are stocked with Potions and Capture Orbs.", "Pay at the counter."],
}

const DRINKS := ["freshWater", "sodaPop", "lemonade"]

## Runs a building NPC's job after (or instead of) their lines: the Rest Lodge nurse, the Mart clerk,
## or a resident who lets your creatures rest.
func _npc_action(npc: Dictionary, text: Array) -> void:
	if npc.has("service"):
		Services.run(self, npc, text)
		return
	match npc.get("action", ""):
		"lodge":
			Game.say(["Welcome to the Rest Lodge!"], _lodge_menu)
		"mart":
			Game.say([npc.get("greeting", "Welcome to the Trail Mart! What do you need?")], func() -> void:
				Menus.open_shop(0, func() -> void: Game.say(["Please come again!"]), npc.get("stock", [])))
		"heal":
			Game.say(text, func() -> void:
				for m in GameState.all_party_mons(gs):
					Creatures.heal_fully(m)
				if not GameState.all_party_mons(gs).is_empty():
					Audio.sfx("heal")
					Game.say(["You took a short rest. Your creatures look well rested!"]))
		_:
			Game.say(text)

func _lodge_menu(heal := true) -> void:
	var players: int = gs.players.size()
	var items: Array = ["HEAL"] if heal else []
	var first := 1 if heal else 0
	items.append_array(["STORAGE P1", "STORAGE P2"] if players > 1 else ["STORAGE"])
	items.append_array(Pc.MENU)
	items.append("LEAVE")
	var ref: Array = []
	var menu := ListMenu.new({
		"x": 128, "y": 24, "w": 108, "items": items,
		"on_cancel": func() -> void: Game.pop(ref[0]),
		"on_select": func(i: int) -> void:
			Game.pop(ref[0])
			if heal and i == 0:
				for m in GameState.all_party_mons(gs):
					Creatures.heal_fully(m)
				gs.respawn = {"map": map.id, "x": player.x, "y": player.y}
				Audio.sfx("heal")
				Game.say(["Let me take your creatures for a moment...", "... ... ..."] + Pokerus.nurse_lines(gs) + ["They're fully healed! We hope to see you again!"], _lodge_menu)
			elif Pc.MENU.has(items[i]):
				Pc.open(items[i], func() -> void: _lodge_menu(heal))
			elif i - first < players:
				var pl := i - first
				var sref: Array = []
				var s = StorageScreen.new(pl, func() -> void:
					Game.pop(sref[0])
					_lodge_menu(heal))
				sref.append(s)
				Game.push(s),
	})
	ref.append(menu)
	Game.push(menu)

# ---------- interaction ----------
func _interact() -> void:
	if Field.interact_here(self):
		return
	var p := player
	var d: Vector2i = DX[p.dir]
	var tx := p.x + d.x
	var ty := p.y + d.y
	var n := _npc_at(tx, ty)
	# Shopkeepers and nurses are talked to across their counter.
	if n == null and Maps.tile_at(map, tx, ty) == "c":
		n = _npc_at(tx + d.x, ty + d.y)
	if n != null:
		n.dir = OPP[p.dir]
		if n.npc != null:
			var text: Array = n.npc.text
			for v in n.npc.get("variants", []):
				if gs.flags.get(v.if, false):
					text = v.text
					break
			_npc_action(n.npc, text)
			return
		if n.trainer != null:
			if gs.flags.get(n.trainer.id, false):
				if Field.offer_rematch(self, n):
					return
				Game.say([n.trainer.after])
				return
			_trainer_battle(n)
			return
	var sign: Variant = map.get("signs", {}).get("%d,%d" % [tx, ty])
	if sign != null:
		Game.say(sign)
		return
	if Field.interact(self, tx, ty):
		return
	var tile := Maps.tile_at(map, tx, ty)
	if tile == "V":
		Game.say(["A drink machine! What will you buy?"], func() -> void:
			Menus.open_shop(0, func() -> void: pass, DRINKS))
	elif tile == "M":
		Game.say(["It's a storage machine for creatures."], func() -> void: _lodge_menu(false))
	elif FURNITURE_TEXT.has(tile) and map.get("interior", false):
		Game.say(FURNITURE_TEXT[tile])

func _open_start_menu(pl: int) -> void:
	var ref: Array = []
	var labels: Array = ["DEX", "PARTY", "BAG", gs.players[pl].name.to_upper(), "SAVE", "CO-OP", "OPTIONS", "CONTROLS", "EXIT"]
	var opts := {
		"x": 158, "y": 4, "w": 78, "player": pl, "items": labels,
		"on_cancel": func() -> void: Game.pop(ref[0]),
		"on_select": func(i: int) -> void:
			if i == 0:
				var dref: Array = []
				var d := DexScreen.new(pl, func() -> void: Game.pop(dref[0]))
				dref.append(d)
				Game.push(d)
			elif (i == 1 or i == 2) and gs.players[pl].party.is_empty():
				Game.say(["You don't have any creatures yet."], Callable(), pl)
			elif i == 1:
				Menus.open_party_menu(pl, func() -> void: pass)
			elif i == 2:
				Menus.open_bag_overworld(pl, func() -> void: pass)
			elif i == 3:
				var cref: Array = []
				var card := TrainerCardScene.new(pl, func() -> void: Game.pop(cref[0]))
				cref.append(card)
				Game.push(card)
			elif i == 4:
				Game.ask("Save your progress?", ["YES", "NO"], func(c: int) -> void:
					if c == 0:
						Audio.sfx("save")
						Game.say(["Your progress was saved!" if GameState.save(gs) else "Saving failed (the save file could not be written)."], Callable(), pl), pl)
			elif i == 5:
				Game.say(OverworldScene.coop_text(), func() -> void: Trade.offer_coop(self), pl)
			elif i == 6:
				Options.open_menu(pl, func() -> void: pass)
			elif i == 7:
				Game.say(OverworldScene.controls_text(false), Callable(), pl)
			else:
				Game.pop(ref[0]),
	}
	if gs.mode == "coop":
		opts.title = "PLAYER %d" % (pl + 1)
	var menu := ListMenu.new(opts)
	ref.append(menu)
	Game.push(menu)

# ---------- trainers ----------
func _check_trainers() -> bool:
	var p := player
	for n in npcs:
		var t: Variant = n.trainer
		if t == null or gs.flags.get(t.id, false):
			continue
		var d: Vector2i = DX[n.dir]
		for i in range(1, t.sight + 1):
			var x := n.x + d.x * i
			var y := n.y + d.y * i
			if x == p.x and y == p.y:
				_spotted(n, i - 1)
				return true
			if not _walkable(x, y, true) or _npc_at(x, y, n) != null:
				break
	return false

func _spotted(n: Actor, steps: int) -> void:
	_exclaim = {"a": n, "t": 0.8}
	Audio.sfx("spotted")
	# Lambdas capture locals by value, so the mutable script state lives in a Dictionary.
	var st := {"wait": 0.8, "left": steps}
	_script = func(dt: float) -> bool:
		if st.wait > 0:
			st.wait -= dt
			return false
		if n.move != null:
			return false
		if st.left > 0:
			var d: Vector2i = DX[n.dir]
			n.move = {"fx": n.x, "fy": n.y, "t": 0.0, "dur": WALK, "jump": false}
			n.x += d.x
			n.y += d.y
			st.left -= 1
			return false
		player.dir = OPP[n.dir]
		_trainer_battle(n)
		return true

func _trainer_battle(n: Actor) -> void:
	var t: Dictionary = n.trainer
	Game.say([t.intro], func() -> void:
		var party: Array = []
		for e in t.party:
			party.append(Creatures.create_creature(e[0], e[1], {"owner": 9}))
		_flash_then(func() -> void:
			var setup := {"kind": "trainer", "double": t.get("double", false) or gs.mode == "coop", "trainer": t, "trainerParty": party}
			Field.prepare_battle(self, setup)
			# The champion battle leads into the ending, so it stays one player's.
			if not t.get("champion", false) and JointBattle.partner_ready(self):
				JointBattle.start(setup, t)
			else:
				_run_battle(setup, t)))

## Removes a beaten trainer who leaves (leaveAfter) from this map.
func remove_trainer(id: String) -> void:
	for n in npcs:
		if n.trainer != null and n.trainer.id == id:
			npcs.erase(n)
			return

## True while a scripted sequence (a trainer walking up, a battle flash) is running.
func is_busy() -> bool:
	return _script.is_valid()

# ---------- wild ----------
## table: the encounter list to roll on (the map's grass list by default). extra: more battle setup
## (kind "safari", location...). Returns false when Repel kept the creature away.
func _start_wild(table: Array = [], extra: Dictionary = {}) -> bool:
	if table.is_empty():
		table = map.encounters
	var pick := func() -> Dictionary:
		var total := 0
		for e in table:
			total += e.weight
		var r: int = Rng.global_rng.int_below(total)
		var found: Dictionary = table[0]
		for e in table:
			r -= e.weight
			if r < 0:
				found = e
				break
		return Creatures.create_creature(found.species, found.min + Rng.global_rng.int_below(found.max - found.min + 1), {"owner": 9})
	# With the other player on screen, two wild creatures appear and both players fight.
	var solo: bool = extra.get("kind", "wild") == "safari"
	var count := 2 if not solo and (gs.mode == "coop" or JointBattle.partner_ready(self)) else 1
	var wild: Array = []
	for i in count:
		wild.append(pick.call())
	if not extra.get("fishing", false) and Field.repelled(wild[0].level):
		return false
	Audio.sfx("encounter")
	var setup := {"kind": "wild", "double": count > 1, "wild": wild}
	setup.merge(extra, true)
	Field.prepare_battle(self, setup)
	_flash_then(func() -> void:
		if count > 1 and JointBattle.partner_ready(self):
			JointBattle.start(setup, null)
		else:
			_run_battle(setup))
	return true

func _flash_then(cb: Callable) -> void:
	var st := {"t": 0.0}
	_script = func(dt: float) -> bool:
		st.t += dt
		if st.t > 0.6:
			Game.transition(cb)
			return true
		return false
	_flash_t = 0.6

func _run_battle(setup: Dictionary, trainer: Variant = null) -> void:
	var g := gs
	var ref: Array = []
	Field.prepare_battle(self, setup)
	setup.onEnd = func(result: String, battle) -> void:
		Game.transition(func() -> void:
			var scene = ref[0]
			Game.pop(scene)
			Audio.play_music(map_track(map))
			var msgs: Array = []
			if setup.has("storyEnd"):
				for c in battle.caught:
					GameState.receive_creature(g, c.mon, c.player)
				if result == "lose":
					for m in GameState.all_party_mons(g):
						Creatures.heal_fully(m)
				setup.storyEnd.call(result)
				return
			for c in battle.caught:
				var where := GameState.receive_creature(g, c.mon, c.player)
				if where == "box":
					msgs.append("%s was sent to storage (party full: %d max)." % [Creatures.display_name(c.mon), GameState.party_cap(g)])
			Field.after_battle(self, setup, result, battle, trainer, msgs)
			if result == "lose":
				if Field.on_whiteout(self):
					return
				for m in GameState.all_party_mons(g):
					Creatures.heal_fully(m)
				var r: Dictionary = g.respawn
				load_map(r.map, r.x, r.y, "down")
				g.x = r.x
				g.y = r.y
				return
			var champion := false
			if trainer != null and result == "win":
				g.flags[trainer.id] = true
				if trainer.get("leaveAfter", false):
					remove_trainer(trainer.id)
				if trainer.get("badge"):
					g.flags["badge%d" % trainer.badge] = true
					var gym: Dictionary = {}
					for gy in DB.GYMS:
						if gy.badge == trainer.badge:
							gym = gy
					Audio.sfx("badge")
					msgs.append("You received the %s! (%d/8 badges)" % [gym.badgeName, OverworldScene.badge_count(g)])
				champion = trainer.get("champion", false)
			msgs.append_array(setup.get("lateMsgs", []))
			var evolve_queue: Array = []
			for uid in scene.leveled:
				for m in GameState.all_party_mons(g):
					if m.uid == uid and Creatures.pending_evolution(m) != null:
						evolve_queue.append(m)
						break
			var run_evos := func(self_ref: Callable) -> void:
				if evolve_queue.is_empty():
					if champion:
						Story.ending(self)
					return
				var m: Dictionary = evolve_queue.pop_front()
				EvolutionScene.new(m, Creatures.pending_evolution(m), 1 if m.owner == 1 and g.mode == "coop" else 0, func() -> void: self_ref.call(self_ref))
			var start_evos := func() -> void: run_evos.call(run_evos)
			if msgs.size():
				Game.say(msgs, start_evos)
			else:
				start_evos.call())
	setup.bg = BattleScene.backdrop_for(map)
	var scene = BattleScene.new(setup)
	ref.append(scene)
	Game.push(scene)

static func badge_count(g: Dictionary) -> int:
	var re := RegEx.create_from_string("^badge\\d$")
	var n := 0
	for f in g.flags.keys():
		if re.search(f) != null:
			n += 1
	return n

# ---------- drawing ----------
## The player's sprite sheet name while riding the Bicycle or Surfing (or diving), when that art exists.
func _ride_look(look: String) -> String:
	var ride := ""
	if Field.surfing(self) or map.get("underwater", false):
		ride = "surf"
	elif Game.gs.get("bike", false) and not map.get("indoor", false):
		ride = "bike"
	if ride != "" and ArtAssets.texture("trainers/%s_%s_walk" % [look, ride]) != null:
		return "%s_%s" % [look, ride]
	return look

## Field objects that can be cleared or pushed, so a painted map leaves them out and they are drawn on top.
const DYNAMIC := "TRO"

func draw() -> void:
	var p := actor_pixel(player)
	var cam_x: int = roundi(p.x + 8 - Gfx.W / 2.0)
	var cam_y: int = roundi(p.y + 8 - Gfx.H / 2.0)
	# Rooms that fit on screen stay still and centered, like the handheld games.
	if map.get("interior", false):
		if _map_w() * 16 <= Gfx.W:
			cam_x = roundi((_map_w() * 16 - Gfx.W) / 2.0)
		if _map_h() * 16 <= Gfx.H:
			cam_y = roundi((_map_h() * 16 - Gfx.H) / 2.0)
	var x0: int = floori(cam_x / 16.0) - 1
	var y0: int = floori(cam_y / 16.0) - 1
	var anim: int = floori(_frame * 2)
	var theme: String = map.get("theme", "#d8d0c0")
	var indoor: bool = map.get("indoor", false)
	var style: Dictionary = map.get("style", {})
	var gen_trees := Tiles.tree_sprite(0, 0) != null and not style.has("treeShape")
	var cave: bool = map.get("cave", false)
	var h := _map_h()
	var w := _map_w()
	# A painted whole-map image (assets/maps/<id>.png) replaces the tiles inside the map; tiles still fill the border.
	var painted := ArtAssets.texture("maps/" + str(map.get("id", "")))
	var inside := func(tx: int, ty: int) -> bool: return tx >= 0 and ty >= 0 and tx < w and ty < h
	Gfx.rect(0, 0, Gfx.W, Gfx.H, "#000000")
	if painted != null:
		Gfx.image(painted, -cam_x, -cam_y)
	for ty in range(y0, y0 + Gfx.H / 16 + 3):
		for tx in range(x0, x0 + Gfx.W / 16 + 3):
			if indoor and (tx < 0 or ty < 0 or ty >= h or tx >= w):
				continue
			var raw := Maps.tile_at(map, tx, ty)
			var ch := Field.tile(self, tx, ty)
			# Inside a painted map only the things that can change (Cut trees, rocks, boulders) are drawn.
			if painted != null and inside.call(tx, ty) and not DYNAMIC.contains(ch):
				continue
			if ch == "#" and cave:
				ch = "x"
			var tex: Texture2D
			if FieldTiles.handles(ch):
				tex = FieldTiles.texture(ch, tx, ty, anim, Maps.tile_at(map, tx, ty - 1), theme)
			elif ch == raw:
				# Generated trees are drawn as sprites below, so their tile is just (town-styled) grass.
				var tch := "." if ch == "#" and gen_trees else ch
				tex = TownStyle.apply(Tiles.map_tile(map, tx, ty, anim, theme), tch, style)
			else:
				tex = TownStyle.apply(Tiles.tile_texture(ch, tx, ty, anim, Maps.tile_at(map, tx, ty - 1), Maps.tile_at(map, tx, ty + 1), theme), ch, style)
			Gfx.image(tex, tx * 16 - cam_x, ty * 16 - cam_y)
	# Generated trees: one 32x32 sprite per '#' tile, row by row so lower trees overlap the ones behind.
	if gen_trees and not cave:
		for ty in range(y0, y0 + Gfx.H / 16 + 4):
			for tx in range(x0 - 1, x0 + Gfx.W / 16 + 4):
				if painted != null and inside.call(tx, ty):
					continue
				if Field.tile(self, tx, ty) == "#" and not (indoor and (tx < 0 or ty < 0 or ty >= h or tx >= w)):
					Gfx.image(TownStyle.apply(Tiles.tree_sprite(tx, ty), "#", style), tx * 16 - cam_x - 8, ty * 16 - cam_y - 16)
	# Generated whole-building sprites (when present) over their footprint, doors on top.
	for b in ([] if painted != null else Tiles.buildings(map)):
		var r: Rect2i = b.rect
		var btex := ArtAssets.texture("buildings/%s_%dx%d" % [b.kind, r.size.x, r.size.y])
		if btex == null:
			btex = ArtAssets.texture("buildings/" + b.kind)
		if btex == null or r.position.x * 16 - cam_x > Gfx.W or r.end.x * 16 - cam_x < 0 or r.position.y * 16 - cam_y > Gfx.H or r.end.y * 16 - cam_y < 0:
			continue
		btex = TownStyle.apply(btex, b.roof, style)
		Gfx.ci.draw_texture_rect(btex, Rect2(r.position.x * 16 - cam_x, r.position.y * 16 - cam_y, r.size.x * 16, r.size.y * 16), false)
		for d in b.doors:
			Gfx.image(TownStyle.apply(Tiles.tile_texture(d[2], d[0], d[1], anim), d[2], style), d[0] * 16 - cam_x, d[1] * 16 - cam_y)
	Field.draw_ground(self, cam_x, cam_y)
	var actors: Array[Actor] = []
	actors.append_array(npcs)
	actors.append(player)
	if follower != null:
		actors.append(follower)
	# The other player, when they're on this map. They walk through people rather than block them.
	var other := Game.other_overworld()
	if other != null and other.map.id == map.id:
		actors.append(other.player)
	actors.sort_custom(func(a: Actor, b: Actor) -> bool: return actor_pixel(a).y < actor_pixel(b).y)
	for a in actors:
		var ap := actor_pixel(a)
		var walking: bool = a.move != null and not a.move.jump
		var step := 0
		if walking and a.move.t / a.move.dur < 0.5:
			step = (a.step_count % 2) + 1
		var sx: float = ap.x - cam_x
		var sy: float = ap.y - cam_y - 4 - ap.hop
		var look: String = a.palette if DB.PALETTES.has(a.palette) else "boy"
		if a == player:
			look = _ride_look(look)
			if look.ends_with("_surf"):
				step = floori(Game.time * 3) % 3  # the surf ride paddles even when still
		TrainerArt.draw_char(sx, sy, a.dir, step, DB.PALETTES.get(a.palette, DB.PALETTES.boy), look)
		# Tall grass covers the feet.
		if a.move == null and Maps.tile_at(map, a.x, a.y) == "," and painted != null:
			Gfx.ci.draw_texture_rect_region(painted, Rect2(ap.x - cam_x, ap.y - cam_y + 9, 16, 7), Rect2(a.x * 16, a.y * 16 + 9, 16, 7))
		elif a.move == null and Maps.tile_at(map, a.x, a.y) == ",":
			var gt: Texture2D = TownStyle.apply(Tiles.tile_texture(",", a.x, a.y, anim), ",", style)
			Gfx.ci.draw_texture_rect_region(gt, Rect2(ap.x - cam_x, ap.y - cam_y + 9, 16, 7), Rect2(0, 9, 16, 7))
		if _exclaim != null and _exclaim.a == a:
			Gfx.rect(sx + 4, sy - 14, 9, 11, "#303030")
			Gfx.rect(sx + 5, sy - 13, 7, 9, "#f8f8f8")
			Gfx.rect(sx + 8, sy - 12, 2, 5, "#e03030")
			Gfx.rect(sx + 8, sy - 6, 2, 1, "#e03030")
	Field.draw_overlay(self, cam_x, cam_y)
	if _banner.t > 0:
		var slide := minf(1.0, minf(_banner.t * 3, (2.2 - _banner.t) * 4))
		Gfx.panel(4, -28 + 32 * slide, 110, 24)
		Gfx.text(_banner.text, 59, -20 + 32 * slide, {"align": "center"})
	if _flash_t > 0:
		_flash_t -= 1.0 / 60
		if posmod(floori(_flash_t * 10), 2) == 0:
			Gfx.rect(0, 0, Gfx.W, Gfx.H, Color(1, 1, 1, 0.7))

## What the CO-OP menu item says: how a friend joins, or whose world the friend is in.
static func coop_text() -> Array:
	if Game.cur == 1:
		var host: Dictionary = Game.views[0].gs.players[0]
		return [
			"You're in %s's world. Go anywhere you like: you don't have to stay together." % host.name,
			"Your creatures, items and money are saved on your own computer as you play. Close the game to leave.",
		]
	if Net.role != Net.Role.HOST:
		return ["Co-op isn't available right now: this computer couldn't open network port %d." % Net.PORT]
	var lines: Array = []
	if Net.guest_in_world():
		lines.append("%s is playing in your world." % Game.views[1].gs.players[0].name)
	else:
		lines.append("A friend can join any time from their own computer on this network: they pick JOIN A GAME on the title screen and bring their own creatures.")
	var addr := Net.local_addresses()
	if not addr.is_empty():
		lines.append("If your game isn't listed for them, they can type this address: %s" % ", ".join(addr))
	return lines

static func controls_text(_coop := false) -> Array:
	return ["CONTROLS: Arrows or WASD to move. Z, Enter, Space or F = A (confirm).", "X, Shift or G = B (back; hold to run). Esc, C or R = Menu. Gamepads work too."]

class DexScreen extends Scene:
	var sel := 0
	var _player: int
	var _on_close: Callable
	var _list: Array = []

	func _init(player: int, on_close: Callable) -> void:
		_player = player
		_on_close = on_close
		_list = DB.SPECIES.values()
		_list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.dex < b.dex)

	func update(_dt: float) -> void:
		var inp := Game.input.p(_player)
		if inp.pressed("up"):
			sel = (sel + _list.size() - 1) % _list.size()
		if inp.pressed("down"):
			sel = (sel + 1) % _list.size()
		if inp.pressed("b") or inp.pressed("a"):
			_on_close.call()

	func draw() -> void:
		var gs: Dictionary = Game.gs
		Gfx.rect(0, 0, Gfx.W, Gfx.H, "#d84848")
		Gfx.rect(0, 0, Gfx.W, 16, "#a83030")
		Gfx.text("CREATUREDEX   Seen %d  Caught %d" % [gs.seen.size(), gs.caught.size()], 6, 5, {"color": "#ffffff", "size": 5})
		Gfx.panel(118, 20, 118, 136)
		var start := maxi(0, mini(sel - 4, _list.size() - 9))
		var shown := _list.slice(start, start + 9)
		for k in shown.size():
			var sp: Dictionary = shown[k]
			var i := start + k
			var seen: bool = gs.seen.has(sp.id)
			var caught: bool = gs.caught.has(sp.id)
			var y := 28 + k * 14
			if i == sel:
				Gfx.rect(120, y - 3, 114, 13, "#f8e0a0")
			if caught:
				Gfx.rect(124, y + 1, 4, 4, "#e04040")
			Gfx.text("%03d %s" % [sp.dex, sp.name if seen else "-----"], 132, y, {"size": 5})
		var sp: Dictionary = _list[sel]
		Gfx.panel(4, 20, 110, 136)
		if gs.seen.has(sp.id):
			Gfx.image(CreatureArt.creature_sprite(sp.id), 27, 24)
			Gfx.text(sp.name, 59, 92, {"align": "center", "size": 6})
			Gfx.text("/".join(sp.types), 59, 102, {"align": "center", "size": 5, "color": "#606870"})
			if gs.caught.has(sp.id):
				var re := RegEx.create_from_string(".{1,22}(\\s|$)")
				var lines := re.search_all(sp.dexText)
				for i in mini(4, lines.size()):
					Gfx.text(lines[i].get_string().strip_edges(), 10, 114 + i * 9, {"size": 5})
			else:
				Gfx.text("Not caught yet.", 59, 118, {"align": "center", "size": 5, "color": "#808890"})
		else:
			Gfx.text("???", 59, 80, {"align": "center"})
