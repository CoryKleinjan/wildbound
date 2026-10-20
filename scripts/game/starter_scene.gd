class_name StarterScene
extends Scene
## Choosing a creature from PROF. ALDER's bag (one pick per player in co-op).
## Pushed over the overworld during the Route 1 event; on_done receives the picked species ids.

var _coop: bool
var _on_done: Callable
var _picker := 0
var _sel := 1
var _picks: Array = []
var _busy := false
var _started := false

var _lines: Array

## lines replaces PROF. ALDER's opening lines.
func _init(coop: bool, on_done: Callable, lines: Array = []) -> void:
	_coop = coop
	_on_done = on_done
	_lines = lines

func _intro() -> void:
	_busy = true
	var lines := _lines if not _lines.is_empty() else [
		"PROF. ALDER: My bag! There are three Capture Orbs inside!",
		"Each of you, grab one and send it out!" if _coop else "Grab one and send it out, quick!",
	]
	Game.say(lines, func() -> void: _busy = false)

func update(_dt: float) -> void:
	if not _started:
		_started = true
		_intro()
		return
	if _busy:
		return
	var inp := Game.input.p(_picker)
	if inp.pressed("left"):
		_sel = (_sel + 2) % 3
	if inp.pressed("right"):
		_sel = (_sel + 1) % 3
	if inp.pressed("a"):
		var sp: String = DB.STARTERS[_sel]
		if _picks.has(sp):
			return
		var s := DB.species(sp)
		_busy = true
		Game.push(ListMenu.new({
			"x": 150, "y": 70, "w": 86, "player": _picker, "title": "%s?" % s.name, "items": ["YES", "NO"],
			"on_cancel": func() -> void:
				Game.pop()
				_busy = false,
			"on_select": func(i: int) -> void:
				Game.pop()
				_on_choose(i, sp),
		}))

func _on_choose(i: int, sp: String) -> void:
	if i != 0:
		_busy = false
		return
	var s := DB.species(sp)
	_picks.append(sp)
	if _coop and _picks.size() == 1:
		_picker = 1
		for k in DB.STARTERS.size():
			if not _picks.has(DB.STARTERS[k]):
				_sel = k
				break
		Game.say(["%s chose %s!" % [Game.gs.players[0].name, s.name], "%s, your turn! (Arrow keys, Enter = A)" % Game.gs.players[1].name], func() -> void: _busy = false, 1)
		return
	var names: Array = []
	for p in _picks:
		names.append(DB.species(p).name)
	Game.say(["%s, I choose you!" % " and ".join(names)], func() -> void:
		Game.pop(self)
		_on_done.call(_picks))

func draw() -> void:
	Gfx.rect(0, 0, Gfx.W, Gfx.H, "#f0e8d0")
	Gfx.rect(0, 0, Gfx.W, 20, "#b07850")
	Gfx.text("%s: CHOOSE A CREATURE" % Game.gs.players[_picker].name.to_upper() if _coop else "PROF. ALDER'S BAG", Gfx.W / 2.0, 7, {"size": 6, "align": "center", "color": "#ffffff"})
	TrainerArt.draw_char(112, 26, "down", 0, DB.PALETTES.prof, "prof")
	for i in DB.STARTERS.size():
		var sp: String = DB.STARTERS[i]
		var x := 12 + i * 76
		var taken := _picks.has(sp)
		Gfx.panel(x, 46, 68, 64)
		if taken:
			Gfx.rect(x + 3, 49, 62, 58, "#d0d0d0")
		var bob := (Time.get_ticks_msec() / 250) % 2 if i == _sel else 0
		Gfx.image(CreatureArt.creature_sprite(sp), x + 6, 46 + bob, {"scale": 56.0 / 64.0, "modulate": Color(1, 1, 1, 0.35 if taken else 1.0)})
		if i == _sel and not _busy:
			Gfx.cursor(x - 6, 74, "#3878e0" if _picker == 1 else "#e04848")
	var s := DB.species(DB.STARTERS[_sel])
	Gfx.panel(4, 112, Gfx.W - 8, 44)
	Gfx.text(s.name, 12, 120, {"size": 7})
	for i in s.types.size():
		Gfx.type_badge(s.types[i], 100 + i * 36, 119)
	var lines := Gfx.wrap(s.dexText, 216, 5)
	for i in mini(2, lines.size()):
		Gfx.text(lines[i], 12, 133 + i * 9, {"size": 5})
	var names: Array = []
	for a in s.abilities:
		names.append(DB.ABILITIES[a].name)
	Gfx.text("Ability: %s - %s" % [" / ".join(names), DB.ABILITIES[s.abilities[0]].desc], 12, 148, {"size": 4, "color": "#707880"})
