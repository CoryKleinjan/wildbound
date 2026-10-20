class_name EvolutionScene
extends Scene
## Evolution animation (TS EvolutionScene in menus.ts). Pushes itself on construction.

var t := 0.0
## "intro" | "morph" | "done"
var stage := "intro"
var cancelled := false
var _mon: Dictionary
var _into: String
var _player: int
var _on_done: Callable
var _from: String

func _init(mon: Dictionary, into: String, player: int, on_done: Callable) -> void:
	_mon = mon
	_into = into
	_player = player
	_on_done = on_done
	_from = mon.species
	Game.push(self)
	Game.say(["What? %s is evolving!" % Creatures.display_name(mon)], func() -> void: stage = "morph", player)

func update(dt: float) -> void:
	if stage != "morph":
		return
	t += dt
	if Game.input.p(_player).pressed("b") and t < 3.5:
		stage = "done"
		Game.say(["Huh? %s stopped evolving!" % Creatures.display_name(_mon)], _finish, _player)
		return
	if t > 4:
		stage = "done"
		var old_name := Creatures.display_name(_mon)
		Creatures.evolve(_mon, _into)
		var gs: Dictionary = Game.gs
		if not gs.caught.has(_into):
			gs.caught.append(_into)
		Game.say(["Congratulations! Your %s evolved into %s!" % [old_name, DB.species(_into).name]], _learn_new_moves, _player)

func _learn_new_moves() -> void:
	var learn: Array = []
	for entry in DB.species(_into).learnset:
		if entry[0] == _mon.level:
			learn.append(entry[1])
	_learn_next(learn)

func _learn_next(learn: Array) -> void:
	if learn.is_empty():
		_finish()
		return
	var id: String = learn.pop_front()
	Menus.learn_move_flow(_mon, id, _player, func() -> void: _learn_next(learn))

func _finish() -> void:
	Game.pop(self)
	_on_done.call()

func draw() -> void:
	Gfx.rect(0, 0, Gfx.W, Gfx.H, "#202838")
	for i in 16:
		var a := Game.time * 0.8 + i
		Gfx.rect(120 + cos(a) * (40 + i * 4), 60 + sin(a) * (30 + i * 2), 2, 2, "#8098c8")
	var sp: String = _mon.species if stage == "done" else _from
	var white := false
	if stage == "morph":
		var speed := 2 + t * 3
		var flip := sin(t * speed) > 0
		sp = _into if flip else _from
		white = true
	var spr: Texture2D = CreatureArt.creature_sprite(sp, Creatures.is_shiny(_mon))
	if white:
		spr = CreatureArt.silhouette(spr, "#f8f8f8")
	Gfx.image(spr, 88, 24)
