class_name Maps
## Tile helpers for the maps in DB.MAPS (the world itself is generated data, see data/maps.json).

# Tile legend:
# . grass   , tall grass   = path   F flowers   ~ water   # tree   v ledge (jump down)
# r/p/b roof (house/lodge/mart)   w wall   h/l/m door (house/lodge/mart)   S sign
# k/n roof (gym/league)   j/u door (gym/league)   indoor: _ floor  | wall  o statue  e exit mat
# c counter (talk across it)  t table  K bookshelf  B bed  P potted plant  q mart shelf  M storage machine

const WALKABLE := {
	".": true, ",": true, "=": true, "F": true, "h": true, "l": true, "m": true,
	":": true, "j": true, "u": true, "_": true, "e": true,
}

static func tile_at(m: Dictionary, x: int, y: int) -> String:
	var tiles: Array = m.tiles
	if y < 0 or y >= tiles.size() or x < 0 or x >= (tiles[0] as String).length():
		return "#"
	var row: String = tiles[y]
	if x >= row.length():
		return "#"
	return row[x]

static func validate_maps() -> Array[String]:
	var errs: Array[String] = []
	for m: Dictionary in DB.MAPS.values():
		var w: int = (m.tiles[0] as String).length()
		for i in m.tiles.size():
			var row: String = m.tiles[i]
			if row.length() != w:
				errs.append("%s row %d has %d != %d" % [m.id, i, row.length(), w])
		for t in m.get("trainers", []):
			if not WALKABLE.has(tile_at(m, t.x, t.y)):
				errs.append("%s trainer %s on %s" % [m.id, t.id, tile_at(m, t.x, t.y)])
		for n in m.get("npcs", []):
			if not WALKABLE.has(tile_at(m, n.x, n.y)):
				errs.append("%s npc at %d,%d" % [m.id, n.x, n.y])
		for k: String in m.get("doors", {}).keys():
			var p := k.split(",")
			var ch := tile_at(m, int(p[0]), int(p[1]))
			if not "hlm".contains(ch):
				errs.append("%s door %s is %s" % [m.id, k, ch])
			if not m.get("warps", {}).has(k):
				errs.append("%s door %s has no room behind it" % [m.id, k])
		for k: String in m.get("signs", {}).keys():
			var p := k.split(",")
			var ch := tile_at(m, int(p[0]), int(p[1]))
			if ch != "S":
				errs.append("%s sign %s is %s" % [m.id, k, ch])
	return errs
