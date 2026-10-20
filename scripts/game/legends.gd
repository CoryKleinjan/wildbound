class_name Legends
## The legendary side quests: the Braille walls of the Sealed Chamber and the three golem tombs, the triangle on
## Birth Island, the Eon creature on Southern Island, and the tickets and ferry trips to the event islands.

const BRAILLE := {
	"A": [1], "B": [1, 2], "C": [1, 4], "D": [1, 4, 5], "E": [1, 5], "F": [1, 2, 4], "G": [1, 2, 4, 5], "H": [1, 2, 5],
	"I": [2, 4], "J": [2, 4, 5], "K": [1, 3], "L": [1, 2, 3], "M": [1, 3, 4], "N": [1, 3, 4, 5], "O": [1, 3, 5],
	"P": [1, 2, 3, 4], "Q": [1, 2, 3, 4, 5], "R": [1, 2, 3, 5], "S": [2, 3, 4], "T": [2, 3, 4, 5], "U": [1, 3, 6],
	"V": [1, 2, 3, 6], "W": [2, 4, 5, 6], "X": [1, 3, 4, 6], "Y": [1, 3, 4, 5, 6], "Z": [1, 3, 5, 6], ".": [2, 5, 6],
	",": [2],
}
const WAIT_SECONDS := 120.0

# ---------- Braille walls and tombs ----------
## A pressed facing (tx, ty). True if a Braille wall answered.
static func interact(o: OverworldScene, tx: int, ty: int) -> bool:
	var k := "%d,%d" % [tx, ty]
	var text: Variant = o.map.get("braille", {}).get(k)
	if text == null:
		return false
	var after := func() -> void:
		if o.map.get("chamber", "") == k:
			_chamber(o)
		elif o.map.has("tomb") and o.map.tomb.wall == k:
			_tomb(o)
	var ref := {}
	var s := BrailleScene.new(text, func() -> void:
		Game.pop(ref.s)
		after.call())
	ref.s = s
	Game.push(s)
	return true

## The Sealed Chamber: a creature of the sea first, one of stone last, then Dig.
static func _chamber(o: OverworldScene) -> void:
	var gs: Dictionary = Game.gs
	if gs.flags.get("golems_awake", false):
		return
	var party: Array = Field.party().filter(func(m: Dictionary) -> bool: return not m.get("egg", false))
	if party.size() < 2:
		return
	var first: Dictionary = party[0]
	var last: Dictionary = party[party.size() - 1]
	if not DB.species(first.species).types.has("Water") or not DB.species(last.species).types.has("Rock"):
		return
	var digger: Variant = Field.knower("dig")
	if digger == null:
		return
	Game.ask("Would you like to use Dig here?", ["YES", "NO"], func(c: int) -> void:
		if c != 0:
			return
		gs.flags.golems_awake = true
		Audio.sfx("bump")
		Game.say(["%s used Dig!" % Creatures.display_name(digger), "... ... ...", "Rumble... Rumble...",
			"It sounded as if a door opened somewhere far away..."]))

## A golem tomb: once the golems are awake, the field move written on the wall opens it.
static func _tomb(o: OverworldScene) -> void:
	var gs: Dictionary = Game.gs
	var t: Dictionary = o.map.tomb
	if gs.flags.get(t.flag, false) or not gs.flags.get("golems_awake", false):
		return
	var open := func() -> void:
		gs.flags[t.flag] = true
		Audio.sfx("bump")
		Game.say(["Rumble... Rumble...", "The wall shook, and something in the middle of the room began to move!"])
	if t.move == "wait":
		var w: Variant = o.field.get("wait")
		if w != null and w.x == o.player.x and w.y == o.player.y and Game.time - float(w.t) >= WAIT_SECONDS:
			open.call()
			return
		o.field.wait = {"x": o.player.x, "y": o.player.y, "t": Game.time}
		Game.say(["%s stood still in the freezing air..." % gs.players[0].name])
		return
	var m: Variant = Field.knower(t.move)
	if m == null:
		return
	Game.ask("Would you like to use %s here?" % DB.move(t.move).name, ["YES", "NO"], func(c: int) -> void:
		if c == 0:
			Game.say(["%s used %s!" % [Creatures.display_name(m), DB.move(t.move).name]], open))

## Walking away resets the wait in the Frost Tomb.
static func on_step(o: OverworldScene) -> void:
	if o.field.has("wait"):
		o.field.erase("wait")

# ---------- Birth Island's triangle ----------
static func triangle_pos(o: OverworldScene) -> Variant:
	var tri: Array = o.map.get("triangle", [])
	var gs: Dictionary = Game.gs
	if tri.is_empty() or gs.flags.get("birth_puzzle", false):
		return null
	var p: Array = tri[int(gs.flags.get("birth_step", 0)) % tri.size()]
	return Vector2i(int(p[0]), int(p[1]))

static func triangle_interact(o: OverworldScene, tx: int, ty: int) -> bool:
	var p: Variant = triangle_pos(o)
	if p == null or p != Vector2i(tx, ty):
		return false
	var gs: Dictionary = Game.gs
	var step := int(gs.flags.get("birth_step", 0)) + 1
	gs.flags.birth_step = step
	Audio.sfx("cursor")
	if step >= (o.map.triangle as Array).size():
		gs.flags.birth_puzzle = true
		Audio.sfx("spotted")
		Game.say(["The triangle shone brightly... and split open!"])
	else:
		Game.say(["The triangle vanished... and appeared somewhere else!"])
	return true

## The triangle blocks its tile.
static func blocked(o: OverworldScene, x: int, y: int) -> bool:
	var p: Variant = triangle_pos(o)
	return p != null and p == Vector2i(x, y)

static func draw(o: OverworldScene, cam_x: int, cam_y: int) -> void:
	var p: Variant = triangle_pos(o)
	if p == null:
		return
	var px: int = p.x * 16 - cam_x
	var py: int = p.y * 16 - cam_y
	var glow := 0.5 + 0.5 * sin(Game.time * 3)
	for r in 7:
		Gfx.rect(px + 8 - r - 1, py + 3 + r * 2, (r + 1) * 2, 2, "#d04040")
	Gfx.rect(px + 6, py + 9, 4, 2, Color(1, 0.9, 0.5, glow))

# ---------- Southern Island ----------
## Only the first Eon creature still roaming waits on the island.
static func eon_here(gs: Dictionary, s: Dictionary) -> bool:
	if not s.get("eon", false):
		return true
	for sp in DB.ROAMERS:
		if gs.roamers.has(sp):
			return sp == s.species
	return false

# ---------- tickets and the ferry ----------
static func ticket(npc: Dictionary, text: Array) -> void:
	var gs: Dictionary = Game.gs
	var id: String = npc.ticket
	if gs.bag.get(id, 0) > 0:
		Game.say(["Take the ferry from Saltmarsh, and show them your %s." % DB.item(id).name])
		return
	var ok := false
	match npc.need:
		"eon":
			ok = gs.flags.get("champion", false) and (not gs.mixed.is_empty() or TownLife.fame(gs) >= 10)
		"frontier":
			for fid in gs.frontier:
				if int(gs.frontier[fid].get("best", 0)) >= 7:
					ok = true
		"dex":
			ok = gs.caught.size() >= 120
		"hof":
			ok = gs.hallOfFame.size() >= 2
	if not ok:
		Game.say(text)
		return
	gs.bag[id] = 1
	Audio.sfx("badge")
	Game.say(["You've earned this. Take it!", "%s received the %s!" % [gs.players[0].name, DB.item(id).name],
		"Show it at the Saltmarsh ferry."])

## Places the ferry can take you from here: the npc's own destination plus islands you have tickets for.
static func ferry_stops(npc: Dictionary) -> Array:
	var gs: Dictionary = Game.gs
	var out: Array = []
	if npc.to != "battlefrontier" or gs.flags.get("champion", false):
		out.append(npc.to)
	var tickets: Dictionary = DB.EMERALD.get("islands", {})
	for id in npc.get("islands", []):
		if gs.bag.get(tickets.get(id, ""), 0) > 0 and DB.MAPS.has(id):
			out.append(id)
	return out

# ---------- Braille reader ----------
class BrailleScene extends Scene:
	var _text: String
	var _on_close: Callable
	var _read := false

	func _init(text: String, on_close: Callable) -> void:
		_text = text
		_on_close = on_close

	func update(_dt: float) -> void:
		var inp := Game.input.p(0)
		if inp.pressed("a") and not _read:
			_read = true
			Audio.sfx("cursor")
		elif inp.pressed("a") or inp.pressed("b"):
			Audio.sfx("cancel")
			_on_close.call()

	func draw() -> void:
		Gfx.rect(0, 0, Gfx.W, Gfx.H, "#3a2c20")
		Gfx.rect(8, 8, Gfx.W - 16, Gfx.H - 60, "#8a7050")
		Gfx.rect(10, 10, Gfx.W - 20, Gfx.H - 64, "#a88a62")
		# Six-dot cells, wrapped to the panel.
		var x := 16.0
		var y := 16.0
		for ch in _text:
			if ch == " ":
				x += 8
			else:
				var dots: Array = Legends.BRAILLE.get(ch, [])
				for d in dots:
					var col: int = 0 if d <= 3 else 1
					var row: int = (int(d) - 1) % 3
					Gfx.rect(x + col * 4, y + row * 4, 3, 3, "#f0e0c0")
				x += 10
			if x > Gfx.W - 26:
				x = 16
				y += 16
		Gfx.panel(4, Gfx.H - 48, Gfx.W - 8, 44)
		if _read:
			var re := RegEx.create_from_string(".{1,40}(\\s|$)")
			var lines := re.search_all(_text)
			for i in mini(3, lines.size()):
				Gfx.text(lines[i].get_string().strip_edges(), 12, Gfx.H - 41 + i * 11, {"size": 5})
		else:
			Gfx.text("Dots are carved into the wall.", 12, Gfx.H - 41, {"size": 5})
			Gfx.text("A: read them", 12, Gfx.H - 25, {"size": 5, "color": "#606060"})
