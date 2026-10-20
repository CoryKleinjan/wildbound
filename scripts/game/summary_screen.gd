class_name SummaryScreen
extends Scene
## Two-page creature summary (TS SummaryScreen in menus.ts).

var page := 0
var _mon: Dictionary
var _player: int
var _on_close: Callable

func _init(mon: Dictionary, player: int, on_close: Callable) -> void:
	_mon = mon
	_player = player
	_on_close = on_close

func update(_dt: float) -> void:
	var inp := Game.input.p(_player)
	if inp.pressed("left") or inp.pressed("right"):
		page = 1 - page
		Audio.sfx("cursor")
	if inp.pressed("b") or inp.pressed("a"):
		Audio.sfx("cancel")
		_on_close.call()

func draw() -> void:
	var m := _mon
	if m.get("egg", false):
		Gfx.screen("summary", "#f0f0e8", "#486088")
		Gfx.text("EGG", 6, 5, {"color": "#ffffff", "size": 6})
		Gfx.rect(4, 20, 76, 76, "#c8e0f0")
		Menus.draw_egg(42, 58, 2.2)
		Gfx.panel(86, 20, 150, 76)
		var lines := Gfx.wrap(Eggs.hatch_text(m), 136, 6)
		for i in lines.size():
			Gfx.text(lines[i], 94, 30 + i * 11, {"size": 6})
		return
	var sp: Dictionary = DB.species(m.species)
	Gfx.screen("summary", "#f0f0e8", "#486088")
	Gfx.text("INFO & STATS" if page == 0 else "MOVES", 6, 5, {"color": "#ffffff", "size": 6})
	Gfx.text("◀▶ page   B: back", Gfx.W - 6, 5, {"color": "#c8d8f0", "size": 5, "align": "right"})
	# Left column: sprite and identity.
	Gfx.rect(4, 20, 76, 76, "#c8e0f0")
	Gfx.image(CreatureArt.creature_sprite(m.species, Creatures.is_shiny(m)), 10, 22)
	Gfx.text(Creatures.display_name(m), 6, 100, {"size": 6})
	Gfx.text("Lv%d" % m.level, 6, 110, {"size": 6})
	var g: Variant = Creatures.gender_of(m)
	if g != null:
		Gfx.text("♂" if g == "M" else "♀", 50, 109, {"color": "#3870e0" if g == "M" else "#e04870", "shadow": null})
	if Creatures.is_shiny(m):
		Gfx.text("★", 66, 109, {"color": "#e0b020", "shadow": null})
	var types: Array = sp.types
	for i in types.size():
		Gfx.type_badge(types[i], 4 + i * 36, 122)
	Gfx.text("No.%03d %s" % [sp.dex, sp.name], 6, 136, {"size": 5})
	Gfx.status_badge(m.status, 4, 146)
	var held: Variant = m.get("item", null)
	Gfx.text("Held: %s" % (DB.item(held).name if held != null else "-"), 28 if m.status else 6, 148, {"size": 5, "color": "#405070"})
	if page == 0:
		var st: Dictionary = Creatures.calc_stats(m)
		var nat: int = Creatures.nature_of(m)
		var ab: String = Creatures.ability_of(m)
		Gfx.text("%s nature" % DB.NATURE_NAMES[nat], 88, 22, {"size": 6})
		Gfx.text("Ability: %s" % DB.ABILITIES[ab].name, 88, 32, {"size": 6})
		Gfx.text(DB.ABILITIES[ab].desc, 88, 41, {"size": 5, "color": "#606870"})
		var rows := [["HP", "hp"], ["Attack", "atk"], ["Defense", "def"], ["Sp. Atk", "spa"], ["Sp. Def", "spd"], ["Speed", "spe"]]
		Gfx.text("STAT", 88, 54, {"size": 5, "color": "#808890"})
		Gfx.text("IV", 190, 54, {"size": 5, "color": "#808890", "align": "right"})
		Gfx.text("EV", 222, 54, {"size": 5, "color": "#808890", "align": "right"})
		var nat_up := nat / 5
		var nat_down := nat % 5
		var order := ["atk", "def", "spe", "spa", "spd"]
		for i in rows.size():
			var label: String = rows[i][0]
			var k: String = rows[i][1]
			var y := 63 + i * 10
			var color := "#303030"
			if nat_up != nat_down and order[nat_up] == k:
				color = "#d04040"
			if nat_up != nat_down and order[nat_down] == k:
				color = "#3060c0"
			Gfx.text(label, 88, y, {"size": 6, "color": color})
			Gfx.text(("%d/%d" % [m.hp, st.hp]) if k == "hp" else str(st[k]), 166, y, {"size": 6, "align": "right"})
			Gfx.text(str(m.ivs[k]), 190, y, {"size": 6, "align": "right", "color": "#606870"})
			Gfx.text(str(m.evs[k]), 222, y, {"size": 6, "align": "right", "color": "#606870"})
		var e: Dictionary = Creatures.exp_to_next(m)
		Gfx.text("EXP %d" % m.exp, 88, 128, {"size": 5})
		if not m.get("ribbons", []).is_empty():
			Gfx.text("Ribbons %d" % m.ribbons.size(), 222, 128, {"size": 5, "align": "right", "color": "#c05878"})
		Gfx.text("To next Lv: %d" % maxi(0, e.span - e.into), 88, 137, {"size": 5})
		Gfx.bar(88, 147, 120, (float(e.into) / e.span) if e.span else 0.0, "#40a0f0", 2)
	else:
		var moves: Array = m.moves
		for i in moves.size():
			var ms: Dictionary = moves[i]
			var mv: Dictionary = DB.move(ms.id)
			var y := 22 + i * 32
			Gfx.panel(86, y, 150, 30)
			Gfx.type_badge(mv.type, 92, y + 5)
			Gfx.text(mv.name, 128, y + 6, {"size": 6})
			Gfx.text("PP %d/%d" % [ms.pp, ms.maxPp], 228, y + 17, {"size": 5, "align": "right"})
			var cat := "Status" if mv.power == 0 else ("Special" if mv.type in ["Fire", "Water", "Grass", "Electric", "Psychic", "Ice", "Dragon", "Dark"] else "Physical")
			var pow_s: String = str(mv.power) if mv.power > 1 else "--"
			var acc_s: String = str(mv.acc) if mv.acc else "--"
			Gfx.text("%s  Pow %s  Acc %s" % [cat, pow_s, acc_s], 92, y + 17, {"size": 5, "color": "#606870"})
