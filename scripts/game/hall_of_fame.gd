class_name HallOfFameScene
extends Scene
## The Hall of Fame record on the PC: every team that beat the Champion, newest first. LEFT/RIGHT pages through
## the entries, B closes. HallOfFameScene.record() adds the current team (called when the ending starts).

var _entries: Array
var _page := 0
var _on_close: Callable
var _t := 0.0

static func record(gs: Dictionary) -> void:
	var team: Array = []
	for m in gs.players[0].party:
		if m.get("egg", false):
			continue
		team.append({"species": m.species, "name": Creatures.display_name(m), "level": m.level, "shiny": Creatures.is_shiny(m),
			"gender": m.get("gender", null)})
	var d := Time.get_date_dict_from_system()
	gs.hallOfFame.append({"date": "%04d-%02d-%02d" % [d.year, d.month, d.day], "player": gs.players[0].name, "team": team})

func _init(entries: Array, on_close: Callable) -> void:
	_entries = entries
	_on_close = on_close

func update(dt: float) -> void:
	_t += dt
	var inp := Game.input.p(0)
	var n := _entries.size()
	if inp.pressed("left") or inp.pressed("up"):
		_page = (_page + 1) % n
		Audio.sfx("cursor")
	elif inp.pressed("right") or inp.pressed("down"):
		_page = (_page + n - 1) % n
		Audio.sfx("cursor")
	elif inp.pressed("b") or inp.pressed("a"):
		Audio.sfx("cancel")
		_on_close.call()

func draw() -> void:
	Gfx.rect(0, 0, Gfx.W, Gfx.H, "#181830")
	for i in 30:
		var tw := 0.5 + 0.5 * sin(_t * 2 + i)
		Gfx.rect(fposmod(i * 53.7, Gfx.W), fposmod(i * 37.3, Gfx.H), 1, 1, Color(1, 1, 0.8, 0.3 + 0.6 * tw))
	var idx := _entries.size() - 1 - _page
	var e: Dictionary = _entries[idx]
	Gfx.rect(0, 0, Gfx.W, 18, "#c09830")
	Gfx.text("HALL OF FAME  No. %d" % (idx + 1), 8, 6, {"color": "#ffffff", "size": 6})
	Gfx.text(e.date, Gfx.W - 8, 6, {"color": "#ffffff", "size": 6, "align": "right"})
	var team: Array = e.team
	for i in team.size():
		var m: Dictionary = team[i]
		var col := i % 3
		var row := i / 3
		var x := 14 + col * 76
		var y := 24 + row * 62
		Gfx.ellipse(x + 24, y + 40, 22, 6, Color(1, 0.9, 0.5, 0.18))
		var spr: Texture2D = CreatureArt.creature_sprite(m.species, m.get("shiny", false))
		Gfx.image(spr, x + 4, y + sin(_t * 3 + i) * 1.5, {"scale": 40.0 / spr.get_width()})
		Gfx.text(m.name, x + 24, y + 44, {"color": "#ffffff", "size": 6, "align": "center"})
		Gfx.text("Lv%d" % m.level, x + 24, y + 53, {"color": "#f8e070", "size": 6, "align": "center"})
	Gfx.text("Champion %s" % e.get("player", ""), 8, Gfx.H - 10, {"color": "#d8d8f0", "size": 6})
	if _entries.size() > 1:
		Gfx.text("◀▶ %d/%d" % [_page + 1, _entries.size()], Gfx.W - 8, Gfx.H - 10, {"color": "#d8d8f0", "size": 6, "align": "right"})
