class_name EndingScene
extends Scene
## Hall of Fame and credits after becoming Champion. A skips ahead; on_done runs at the end.

const CREDITS := [
	["WILDBOUND", ""],
	["THE HALL OF FAME", ""],
	["STARRING", "%s"],
	["AND", "%s"],
	["PROF. ALDER", "Creature Professor"],
	["KAI", "Rival, and friend"],
	["THE GYM LEADERS", "Garna  Torvin  Wynn  Sola\nHollis  Aeryn  Ilsa & Oren  Marisol"],
	["THE ELITE", "Vesna  Brannoc  Champion Rowan"],
	["THE HOLLOW ORDER", "Magister Vane  Sable  Corvin"],
	["THE WARDENS", "Orrerion  Thalassor  Terrasolis\nZenithar  Solvara  Velunox  Starchime"],
	["200 CREATURES", "Gen 3 battle rules"],
	["MADE WITH", "Godot Engine"],
	["THANK YOU FOR PLAYING!", ""],
	["THE END", ""],
]
const CARD_TIME := 3.2

var _on_done: Callable
var _t := 0.0
var _card := 0
var _mons: Array = []
var _cards: Array = []

func _init(on_done: Callable) -> void:
	_on_done = on_done
	Audio.play_music("ending")
	var gs: Dictionary = Game.gs
	_mons = GameState.all_party_mons(gs)
	var names: Array = []
	for p in gs.players:
		names.append(p.name)
	var mon_names: Array = []
	for m in _mons:
		mon_names.append(Creatures.display_name(m))
	for c in CREDITS:
		if c[0] == "STARRING":
			_cards.append([c[0], " and ".join(names)])
		elif c[0] == "AND":
			_cards.append([c[0], "  ".join(mon_names)])
		else:
			_cards.append(c)

func update(dt: float) -> void:
	_t += dt
	if Game.input.any("a"):
		_t = maxf(_t, (_card + 1) * CARD_TIME - 0.4)
	_card = floori(_t / CARD_TIME)
	if _card >= _cards.size():
		Game.pop(self)
		_on_done.call()

func draw() -> void:
	Gfx.rect(0, 0, Gfx.W, Gfx.H, "#0c1028")
	# Drifting stars.
	for i in 48:
		var sx := fposmod(i * 53.7 + _t * (4 + i % 5), Gfx.W)
		var sy := fposmod(i * 37.3, 112.0)
		var tw := 0.5 + 0.5 * sin(_t * 2 + i)
		Gfx.rect(sx, sy, 1, 1, Color(1, 1, 0.85, 0.3 + 0.7 * tw))
	# The Starchime's glow.
	var glow := 0.5 + 0.5 * sin(_t * 1.5)
	Gfx.ellipse(120, 26, 18 + glow * 4, 18 + glow * 4, Color(1, 0.9, 0.5, 0.15))
	Gfx.ellipse(120, 26, 9, 10, Color("#f8e8a0"))
	Gfx.rect(119, 12, 2, 6, "#c8b070")
	# The party parades along the bottom.
	var n := _mons.size()
	for i in n:
		var x := fposmod(i * (Gfx.W / maxf(1, n)) + _t * 12, Gfx.W + 40) - 40
		Gfx.image(CreatureArt.creature_sprite(_mons[i].species, Creatures.is_shiny(_mons[i])), x, 112 + sin(_t * 4 + i) * 2, {"scale": 0.6})
	var k := clampf(_card, 0, _cards.size() - 1)
	var c: Array = _cards[int(k)]
	var local := _t - _card * CARD_TIME
	var alpha := clampf(minf(local * 2.5, (CARD_TIME - local) * 2.5), 0, 1)
	Gfx.text(c[0], Gfx.W / 2.0, 58, {"size": 9 if c[1] == "" else 8, "align": "center", "color": Color(0.97, 0.91, 0.63, alpha), "shadow": null})
	var row := 0
	for para in (c[1] as String).split("\n"):
		for l in Gfx.wrap(para, 220, 6):
			Gfx.text(l, Gfx.W / 2.0, 76 + row * 11, {"size": 6, "align": "center", "color": Color(1, 1, 1, alpha), "shadow": null})
			row += 1
