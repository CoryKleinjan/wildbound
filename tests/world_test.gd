extends SceneTree
## Checks that every map in DB.MAPS is well formed and fully connected (port of tests/world.test.ts).
## Run: godot --headless --path . -s res://tests/world_test.gd

const DX := {"up": Vector2i(0, -1), "down": Vector2i(0, 1), "left": Vector2i(-1, 0), "right": Vector2i(1, 0)}
const OPP := {"up": "down", "down": "up", "left": "right", "right": "left"}
## Tiles crossed with field moves (see Field): water, deep water, waterfalls, cut trees, rocks, boulders.
const FIELD := "~DWTRO"

func _initialize() -> void:
	await process_frame
	var db = root.get_node("DB")
	# Loaded after the autoloads exist (Maps uses the DB autoload).
	var Maps = load("res://scripts/game/maps.gd")
	var maps: Dictionary = db.MAPS
	var errs: Array = []
	errs.append_array(Maps.validate_maps())
	for m: Dictionary in maps.values():
		var h: int = m.tiles.size()
		var w: int = (m.tiles[0] as String).length()
		var blocked := {}
		for a in m.get("npcs", []) + m.get("trainers", []):
			# Story bosses that leave once beaten only block until then.
			if not a.get("leaveAfter", false):
				blocked["%d,%d" % [a.x, a.y]] = true
		# Field moves (Surf, Cut, Rock Smash, Strength, Waterfall) open up their tiles.
		var ok := func(x: int, y: int) -> bool:
			var t: String = Maps.tile_at(m, x, y)
			return (Maps.WALKABLE.has(t) or FIELD.contains(t)) and not blocked.has("%d,%d" % [x, y])
		# Entry points: each connection edge gap and each warp landing.
		var starts: Array = []
		for side: String in m.connections.keys():
			var c: Dictionary = m.connections[side]
			if not maps.has(c.map):
				errs.append("%s: connection to missing %s" % [m.id, c.map])
				continue
			for i in maxi(w, h):
				var p: Vector2i
				match side:
					"up": p = Vector2i(i, 0)
					"down": p = Vector2i(i, h - 1)
					"left": p = Vector2i(0, i)
					_: p = Vector2i(w - 1, i)
				if p.x < w and p.y < h and ok.call(p.x, p.y):
					starts.append([p.x, p.y, "edge " + side])
					break
			var back: Variant = maps[c.map].connections.get(OPP[side])
			if back == null or back.map != m.id:
				errs.append("%s: %s connection not mirrored" % [m.id, side])
		for other: Dictionary in maps.values():
			for wp in other.get("warps", {}).values():
				if wp.map == m.id and wp.get("script", "") != "baseExit":
					starts.append([wp.x, wp.y, "warp"])
		# Ferry stops (the Battle Frontier, the event islands) are entered next to the ferry.
		for n in m.get("npcs", []):
			if n.get("service", "") == "ferry":
				for d: Vector2i in DX.values():
					if ok.call(n.x + d.x, n.y + d.y):
						starts.append([n.x + d.x, n.y + d.y, "ferry"])
						break
				break
		# Trick House puzzle rooms are entered at their bottom door, after finding the Trick Master.
		if m.has("trickLevel"):
			starts.append([7, 11, "trick master"])
		if starts.is_empty():
			if m.id != "fernhollow" and not m.get("secretBase", false) and not m.get("underwater", false):
				errs.append("%s: unreachable (no entries)" % m.id)
			continue
		# BFS from the first entry; ledges can be jumped downwards.
		var seen := {}
		var q: Array = [Vector2i(starts[0][0], starts[0][1])]
		seen["%d,%d" % [q[0].x, q[0].y]] = true
		while q.size():
			var cur: Vector2i = q.pop_front()
			for d: Vector2i in DX.values():
				var nx := cur.x + d.x
				var ny := cur.y + d.y
				if Maps.tile_at(m, nx, ny) == "v" and d.y == 1:
					ny += 1
				var key := "%d,%d" % [nx, ny]
				if seen.has(key) or not ok.call(nx, ny):
					continue
				seen[key] = true
				q.append(Vector2i(nx, ny))
		for s in starts:
			if not seen.has("%d,%d" % [s[0], s[1]]):
				errs.append("%s: %s at %d,%d not reachable from first entry" % [m.id, s[2], s[0], s[1]])
		for k in m.get("doors", {}).keys() + m.get("warps", {}).keys():
			if not seen.has(k):
				errs.append("%s: door/warp %s unreachable" % [m.id, k])
		for t in m.get("trainers", []):
			var adj := false
			for d: Vector2i in DX.values():
				if seen.has("%d,%d" % [t.x + d.x, t.y + d.y]):
					adj = true
			if not adj:
				errs.append("%s: trainer %s can't be reached" % [m.id, t.id])
			for e in t.party:
				if not db.SPECIES.has(e[0]):
					errs.append("%s: trainer %s has unknown %s" % [m.id, t.id, e[0]])
		# Every NPC can be talked to: from a reachable neighbour tile, or across a counter.
		for n in m.get("npcs", []):
			var talk := false
			for d: Vector2i in DX.values():
				if seen.has("%d,%d" % [n.x + d.x, n.y + d.y]):
					talk = true
				if Maps.tile_at(m, n.x + d.x, n.y + d.y) == "c" and seen.has("%d,%d" % [n.x + d.x * 2, n.y + d.y * 2]):
					talk = true
			if not talk:
				errs.append("%s: npc at %d,%d can't be talked to" % [m.id, n.x, n.y])
		if m.get("route") and m.get("encounters", []).is_empty() and m.get("waterEncounters", []).is_empty():
			errs.append("%s: no wild encounters" % m.id)
		for e in m.get("encounters", []):
			if not db.SPECIES.has(e.species):
				errs.append("%s: unknown wild %s" % [m.id, e.species])
	# Every map's connections land on walkable tiles (what OverworldScene._on_step computes when crossing an edge).
	for m: Dictionary in maps.values():
		var h: int = m.tiles.size()
		var w: int = (m.tiles[0] as String).length()
		for side: String in m.connections.keys():
			var c: Dictionary = m.connections[side]
			if not maps.has(c.map):
				continue
			var next: Dictionary = maps[c.map]
			var nh: int = next.tiles.size()
			var nw: int = (next.tiles[0] as String).length()
			var vertical := side == "up" or side == "down"
			for i in (w if vertical else h):
				# Leaving from edge tile i.
				var ex: int = i if vertical else (0 if side == "left" else w - 1)
				var ey: int = (0 if side == "up" else h - 1) if vertical else i
				if not Maps.WALKABLE.has(Maps.tile_at(m, ex, ey)):
					continue
				var nx: int
				var ny: int
				if vertical:
					nx = ex + c.offset
					ny = nh - 1 if side == "up" else 0
				else:
					nx = nw - 1 if side == "left" else 0
					ny = ey + c.offset
				if not Maps.WALKABLE.has(Maps.tile_at(next, nx, ny)):
					errs.append("%s: leaving %s at %d,%d lands on '%s' at %s %d,%d" % [m.id, side, ex, ey, Maps.tile_at(next, nx, ny), c.map, nx, ny])
	# Warps land on walkable tiles of existing maps.
	for m: Dictionary in maps.values():
		for k in m.get("warps", {}).keys():
			var wp: Dictionary = m.warps[k]
			if not maps.has(wp.map):
				errs.append("%s: warp %s to missing %s" % [m.id, k, wp.map])
			elif wp.get("script", "") == "baseExit":
				continue
			elif not Maps.WALKABLE.has(Maps.tile_at(maps[wp.map], wp.x, wp.y)):
				errs.append("%s: warp %s lands on a wall in %s" % [m.id, k, wp.map])
	# Whole-world reachability from Fernhollow through connections and warps (doors lead back outside).
	var reach := {"fernhollow": true}
	var mq: Array = ["fernhollow"]
	while mq.size():
		var id: String = mq.pop_front()
		var nexts: Array = []
		for c in maps[id].connections.values():
			nexts.append(c.map)
		for wp in maps[id].get("warps", {}).values():
			nexts.append(wp.map)
		# Dive, and the Secret Base behind a secret-spot tree.
		if maps[id].has("diveTo"):
			nexts.append(maps[id].diveTo)
		if not maps[id].get("secretSpots", []).is_empty():
			nexts.append("secretbase")
		# The ferry, and the Trick Master's puzzle rooms.
		for n in maps[id].get("npcs", []):
			if n.get("service", "") == "ferry":
				nexts.append(n.to)
				nexts.append_array(n.get("islands", []))
		if maps[id].get("trickHouse", false):
			for i in range(1, 4):
				nexts.append("trickpuzzle%d" % i)
		for n in nexts:
			if maps.has(n) and not reach.has(n):
				reach[n] = true
				mq.append(n)
	for id in maps.keys():
		if not reach.has(id):
			errs.append("%s: not reachable from fernhollow" % id)
	var gates := 0
	for m: Dictionary in maps.values():
		if m.has("exitGate"):
			gates += 1
			if not m.connections.has(m.exitGate.side):
				errs.append("%s: exitGate on side %s without a connection" % [m.id, m.exitGate.side])
		if m.has("leagueGate"):
			gates += 1
			var has_u := false
			for row: String in m.tiles:
				if row.contains("u"):
					has_u = true
			if not has_u:
				errs.append("%s: leagueGate but no league door" % m.id)

	var routes := 0
	var towns := 0
	for m: Dictionary in maps.values():
		if m.get("route"):
			routes += 1
		if m.get("town", false) or m.id == "fernhollow":
			towns += 1
	print("maps %d, towns %d, routes %d, gyms %d, reachable %d, gates %d" % [maps.size(), towns, routes, db.GYMS.size(), reach.size(), gates])
	for m: Dictionary in maps.values():
		if m.get("route"):
			print("  %s: %d wild species, %d trainers" % [m.name, m.encounters.size(), m.get("trainers", []).size()])
	for g in db.GYMS:
		var leader: Dictionary = {}
		for t in maps["gym%d" % g.badge].trainers:
			if t.get("badge"):
				leader = t
		var mons: Array = []
		for e in leader.party:
			mons.append("%s %d" % [e[0], e[1]])
		print("  %s (%s): %s" % [g.leader, g.type, ", ".join(mons)])
	# Every trainer and NPC faces a real direction, and every walking sheet has had each frame's facing checked
	# (tools/artgen/walkers.py records the sheet's md5 once its rows face down, up and left).
	for m: Dictionary in maps.values():
		for who in m.get("trainers", []) + m.get("npcs", []):
			if not ["down", "up", "left", "right"].has(who.get("dir", "down")):
				errs.append("%s: %s faces %s" % [m.id, who.get("id", who.get("name", "?")), who.dir])
	var facing: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/trainers/walk_facing.json"))
	for f in DirAccess.get_files_at("res://assets/trainers"):
		if f.ends_with("_walk.png") and not f.contains("_bike") and not f.contains("_surf"):
			var md5 := FileAccess.get_md5("res://assets/trainers/" + f)
			if facing.get(f.get_basename(), "") != md5:
				errs.append("%s: facing not checked (run tools/artgen/walkers.py audit)" % f)
	if errs.size():
		print("\n".join(errs))
		quit(1)
		return
	print("world ok")
	quit(0)
