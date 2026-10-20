class_name Shoal
## Shoal Cave: the tide rises and falls every six hours, as in Emerald (high 3-9 and 15-21). At high tide the J
## tiles are water; at low tide they're cave floor. Shoal Salt and Shoal Shells wash up again every day.

static func low_tide() -> bool:
	var h: int = Time.get_datetime_dict_from_system().hour
	return (h >= 9 and h < 15) or h >= 21 or h < 3

## What a J tile is right now.
static func tide_tile() -> String:
	return "g" if low_tide() else "~"

static func on_map_loaded(o: OverworldScene) -> void:
	if not o.map.get("tide", false):
		return
	o.field.low = low_tide()
	Game.say(["It's low tide. The water has gone out." if o.field.low else "It's high tide. The sea has flooded in."])

## Today's salt and shells: [x, y, item] entries not yet picked up (the ones on tide tiles only at low tide).
static func pickups(o: OverworldScene) -> Array:
	var gs: Dictionary = Game.gs
	var today := Options.today()
	var out: Array = []
	for s in o.map.get("shoal", []):
		if Maps.tile_at(o.map, int(s[0]), int(s[1])) == "J" and not o.field.get("low", false):
			continue
		if int(gs.flags.get("shoal_%d_%d" % [s[0], s[1]], -1)) != today:
			out.append(s)
	return out

static func interact(o: OverworldScene, tx: int, ty: int) -> bool:
	var gs: Dictionary = Game.gs
	for s in pickups(o):
		if int(s[0]) == tx and int(s[1]) == ty:
			gs.flags["shoal_%d_%d" % [tx, ty]] = Options.today()
			gs.bag[s[2]] = gs.bag.get(s[2], 0) + 1
			Audio.sfx("item")
			Game.say(["%s found a %s!" % [gs.players[0].name, DB.item(s[2]).name]])
			return true
	return false

static func blocked(o: OverworldScene, x: int, y: int) -> bool:
	for s in pickups(o):
		if int(s[0]) == x and int(s[1]) == y:
			return true
	return false

static func draw(o: OverworldScene, cam_x: int, cam_y: int) -> void:
	for s in pickups(o):
		Gfx.image(FieldTiles.item_orb(), int(s[0]) * 16 - cam_x, int(s[1]) * 16 - cam_y)
