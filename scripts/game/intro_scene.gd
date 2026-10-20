class_name IntroScene
extends Scene
## PROF. ALDER's opening speech: the region's legend, naming the players, meeting Kai.

var _coop: bool
var _names: Array = []
## Who is on stage ("prof", "creature", "player", "partner", "kai") and when they appeared (Game.time).
## Animations are driven by time because update() doesn't run while a dialog is on top.
var _show := {"prof": 0.0}
var _shrink_at := -1.0
var _t := 0.0
var _started := false

func _init(coop: bool) -> void:
	_coop = coop

func _say(lines: Array, next: Callable) -> void:
	Game.say(lines, next)

func update(dt: float) -> void:
	_t += dt
	if not _started:
		_show.prof = Game.time
		Audio.play_music("title")
		_started = true
		_say([
			"Hello there! Welcome to the world of creatures!",
			"My name is Alder. Folks around here call me the Creature Professor.",
		], _part_creature)

func _part_creature() -> void:
	_show.creature = Game.time
	_say([
		"This world is home to creatures of every shape and size.",
		"Some people keep them as friends. Others battle alongside them. As for me, I study them.",
		"Here in the Wildbound region, legend says seven Wardens watch over the land and its seasons...",
		"...and that atop Summit Crown sleeps the Starchime, which rings once in a thousand years to grant a single wish.",
	], _part_name)

func _part_name() -> void:
	_show.erase("creature")
	_show.player = Game.time
	_say(["But enough about legends. Tell me about yourself!"], func() -> void:
		Game.push(NameEntryScene.new(0, "YOUR NAME?", "p1", "Wren", _on_name)))

func _on_name(n: String) -> void:
	_names.append(n)
	if _coop:
		_show.partner = Game.time
		_say(["And who's this standing beside you? Player 2, tell me your name!"], func() -> void:
			Game.push(NameEntryScene.new(1, "PLAYER 2'S NAME?", "p2", "Juno", _on_partner_name)))
	else:
		_say(["So your name is %s!" % n], _part_kai)

func _on_partner_name(n: String) -> void:
	_names.append(n)
	_say(["%s and %s! What a fine pair." % _names], _part_kai)

func _part_kai() -> void:
	_show.erase("player")
	_show.erase("partner")
	_show.kai = Game.time
	_say([
		"This is my grandson, Kai.",
		"You've been rivals since you could both walk. He's already out exploring, I expect.",
	], _part_end)

func _part_end() -> void:
	_show.erase("kai")
	_show.player = Game.time
	if _coop:
		_show.partner = Game.time
	var who := " and ".join(_names)
	_say([
		"%s! Your very own creature legend is about to unfold!" % who,
		"A world of dreams and adventures awaits. Let's go!",
	], func() -> void:
		_shrink_at = Game.time
		# Let the shrink play, then start the game in Fernhollow.
		Game.push(_Wait.new(1.0, _start_game)))

func _start_game() -> void:
	Game.gs = GameState.new_game("coop" if _coop else "solo", _names)
	Game.transition(func() -> void: Game.replace(OverworldScene.new()))

class _Wait extends Scene:
	var _left: float
	var _cb: Callable
	func _init(seconds: float, cb: Callable) -> void:
		overlay = true
		_left = seconds
		_cb = cb
	func update(dt: float) -> void:
		_left -= dt
		if _left <= 0:
			Game.pop(self)
			_cb.call()

func draw() -> void:
	var top := Color("#203048")
	var bottom := Color("#5878b0")
	Gfx.ci.draw_polygon(
		PackedVector2Array([Vector2(0, 0), Vector2(Gfx.W, 0), Vector2(Gfx.W, Gfx.H), Vector2(0, Gfx.H)]),
		PackedColorArray([top, top, bottom, bottom]))
	# A soft spotlight on the stage.
	Gfx.ellipse(120, 100, 84, 12, Color(1, 1, 1, 0.12))
	if _show.has("prof"):
		_figure("prof", DB.PALETTES.prof, 96, false)
	if _show.has("creature"):
		var k := _appear("creature")
		var s := 0.25 + 0.6 * k
		var tex := CreatureArt.creature_sprite("chirpling")
		Gfx.image(tex, 168 - 32 * s, 100 - 64 * s + sin(Game.time * 3) * 1.5, {"scale": s, "modulate": Color(1, 1, 1, k)})
	if _show.has("kai"):
		_figure("kai", DB.PALETTES.rival, 150, false)
	var scale := 1.0 if _shrink_at < 0 else maxf(0.0, 1.0 - (Game.time - _shrink_at) * 1.2)
	if _show.has("player"):
		_figure("player", DB.PALETTES.p1, 40 if _show.has("partner") else 150, false, scale)
	if _show.has("partner"):
		_figure("partner", DB.PALETTES.p2, 150, false, scale)

func _appear(key: String) -> float:
	return clampf((Game.time - _show[key]) * 2.5, 0.0, 1.0)

func _figure(key: String, pal: Dictionary, x: float, back: bool, scale := 1.0) -> void:
	var k := _appear(key)
	if scale <= 0.02:
		return
	# Slide in from the side and fade in.
	var dx := (1.0 - k) * (30.0 if x > 100 else -30.0)
	Gfx.ci.draw_set_transform(Vector2(x + 24 + dx, 100), 0, Vector2(scale, scale))
	TrainerArt.draw_trainer_big(-24, -52, pal, back)
	Gfx.ci.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
