class_name PartyScreen
extends Scene
## Party list (TS PartyScreen in menus.ts).
## o keys: player (int), party (Array of Creature dicts), prompt (String), on_select (Callable(int)),
## on_cancel (Callable(), optional), marked (int index highlighted as "being moved", optional), start (int, optional).

var sel := 0
var o: Dictionary

func _init(opts: Dictionary) -> void:
	o = opts
	sel = o.get("start", 0)

func update(_dt: float) -> void:
	var inp := Game.input.p(o.player)
	var party: Array = o.party
	var n := party.size() + 1 # + Cancel
	if inp.pressed("up"):
		sel = (sel + n - 1) % n
		Audio.sfx("cursor")
	if inp.pressed("down"):
		sel = (sel + 1) % n
		Audio.sfx("cursor")
	if inp.pressed("a"):
		if sel == party.size():
			Audio.sfx("cancel")
			_cancel()
		else:
			Audio.sfx("confirm")
			(o.on_select as Callable).call(sel)
	elif inp.pressed("b"):
		Audio.sfx("cancel")
		_cancel()

func _cancel() -> void:
	var cb: Callable = o.get("on_cancel", Callable())
	if cb.is_valid():
		cb.call()

func draw() -> void:
	Gfx.rect(0, 0, Gfx.W, Gfx.H, "#5880b8")
	for i in 12:
		Gfx.rect(0, i * 14, Gfx.W, 7, "#6890c8")
	var party: Array = o.party
	for i in party.size():
		var m: Dictionary = party[i]
		var y := 4 + i * 19
		var selected := sel == i
		var fainted: bool = m.hp <= 0
		Gfx.rect(6, y, 228, 17, "#283850")
		Gfx.rect(7, y + 1, 226, 15, "#f8d070" if selected else ("#e0a0a0" if fainted else "#a8d0f0"))
		if o.get("marked", -1) == i:
			Gfx.rect(7, y + 1, 4, 15, "#e05050")
		Menus.draw_mini(m, 10, y - 4, 22, (int(Game.time * 4) % 2) if selected else 0)
		Gfx.text(Creatures.display_name(m), 36, y + 5, {"size": 6})
		var g: Variant = Creatures.gender_of(m)
		if g != null:
			Gfx.text("♂" if g == "M" else "♀", 104, y + 4, {"size": 7, "color": "#3870e0" if g == "M" else "#e04870", "shadow": null})
		Gfx.text("Lv%d" % m.level, 116, y + 5, {"size": 6})
		var mx: int = Creatures.max_hp(m)
		var frac := float(m.hp) / mx
		Gfx.bar(150, y + 4, 48, frac, Gfx.hp_color(frac), 3)
		Gfx.text("%d/%d" % [m.hp, mx], 228, y + 9, {"size": 5, "align": "right"})
		Gfx.status_badge(null if fainted else m.status, 150, y + 9)
		if fainted:
			Gfx.text("FNT", 150, y + 9, {"size": 5, "color": "#c03030"})
	var cy := 4 + party.size() * 19
	Gfx.rect(170, cy, 64, 14, "#283850")
	Gfx.rect(171, cy + 1, 62, 12, "#f8d070" if sel == party.size() else "#d0d8e8")
	Gfx.text("CANCEL", 202, cy + 4, {"size": 6, "align": "center"})
	Gfx.panel(2, 128, 160, 30)
	Gfx.text(o.prompt, 10, 138, {"size": 6})
	Game.player_tag(o.player, 140, 131)
