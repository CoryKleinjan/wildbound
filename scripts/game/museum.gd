class_name Museum
## The Lumenvale Art Museum: winning a Master Rank contest gets your creature painted, and the painting hangs in
## that category's frame (tile G). Fill all five frames and the curator gives you a Glass Ornament.

const CATS := ["cool", "beauty", "cute", "smart", "tough"]

## Called when a creature wins a Master Rank contest.
static func paint(gs: Dictionary, cat: String, m: Dictionary) -> void:
	gs.paintings[cat] = {"species": m.species, "name": Creatures.display_name(m), "trainer": gs.players[0].name,
		"shiny": Creatures.is_shiny(m)}

## The curator.
static func curator(text: Array) -> void:
	var gs: Dictionary = Game.gs
	var n: int = gs.paintings.size()
	if n >= CATS.size() and not gs.flags.get("museum_prize", false):
		gs.flags.museum_prize = true
		if not gs.decor.has("decoOrnament"):
			gs.decor.append("decoOrnament")
		Audio.sfx("badge")
		Game.say(text + ["Every frame is filled! What a collection!", "Please take this Glass Ornament for your Secret Base."])
		return
	Game.say(text + ["%d of our %d frames have paintings. Win a Master Rank contest to fill another!" % [n, CATS.size()]])

## Looking at the frame at (x, y): the paintings hang left to right in CATS order.
static func view(o: OverworldScene, x: int) -> void:
	var gs: Dictionary = Game.gs
	var frames: Array = []
	var row: String = o.map.tiles[1]
	for i in row.length():
		if row[i] == "G":
			frames.append(i)
	var idx := frames.find(x)
	if idx < 0 or idx >= CATS.size():
		Game.say(["An empty frame."])
		return
	var cat: String = CATS[idx]
	var p: Variant = gs.paintings.get(cat)
	if p == null:
		Game.say(["An empty frame. A sign reads: %s CONTEST, MASTER RANK." % cat.to_upper()])
		return
	var ref := {}
	var s := PaintingScene.new(cat, p, func() -> void: Game.pop(ref.s))
	ref.s = s
	Game.push(s)

class PaintingScene extends Scene:
	var _cat: String
	var _p: Dictionary
	var _on_close: Callable

	func _init(cat: String, p: Dictionary, on_close: Callable) -> void:
		_cat = cat
		_p = p
		_on_close = on_close

	func update(_dt: float) -> void:
		var inp := Game.input.p(0)
		if inp.pressed("a") or inp.pressed("b"):
			Audio.sfx("cancel")
			_on_close.call()

	func draw() -> void:
		var bg: String = {"cool": "#e86040", "beauty": "#4888e0", "cute": "#f088b8", "smart": "#48b060", "tough": "#e0c040"}[_cat]
		Gfx.rect(0, 0, Gfx.W, Gfx.H, "#302828")
		var fx := Gfx.W / 2 - 56
		Gfx.rect(fx - 8, 10, 128, 120, "#b08830")
		Gfx.rect(fx - 5, 13, 122, 114, "#e0b850")
		Gfx.rect(fx, 18, 112, 104, bg)
		for i in 12:
			Gfx.rect(fx + (i * 37) % 104, 22 + (i * 23) % 92, 6, 3, Color(1, 1, 1, 0.25))
		var spr: Texture2D = CreatureArt.creature_sprite(_p.species, _p.get("shiny", false))
		Gfx.image(spr, fx + 56 - 48, 22, {"scale": 96.0 / spr.get_width()})
		Gfx.panel(8, Gfx.H - 40, Gfx.W - 16, 34)
		Gfx.text("%s CONTEST MASTER RANK WINNER" % _cat.to_upper(), Gfx.W / 2, Gfx.H - 33, {"align": "center", "size": 5, "color": "#806040"})
		Gfx.text("%s  (Trainer: %s)" % [_p.name, _p.trainer], Gfx.W / 2, Gfx.H - 21, {"align": "center", "size": 6})
