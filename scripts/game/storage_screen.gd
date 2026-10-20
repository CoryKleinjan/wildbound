class_name StorageScreen
extends Scene
## Move creatures between a player's party and the shared box (TS StorageScreen in menus.ts).

var col := 0
var sel := 0
var msg := "Move creatures between your party and storage."
var _player: int
var _on_close: Callable

func _init(player: int, on_close: Callable) -> void:
	_player = player
	_on_close = on_close

var party: Array:
	get:
		return Game.gs.players[_player].party

var box: Array:
	get:
		return Game.gs.box

func update(_dt: float) -> void:
	var inp := Game.input.p(_player)
	var list: Array = party if col == 0 else box
	if inp.pressed("left") or inp.pressed("right"):
		col = 1 - col
		sel = 0
	if inp.pressed("up") and list.size():
		sel = (sel + list.size() - 1) % list.size()
	if inp.pressed("down") and list.size():
		sel = (sel + 1) % list.size()
	if inp.pressed("b"):
		_on_close.call()
		return
	if inp.pressed("a") and list.size():
		var gs: Dictionary = Game.gs
		if col == 0:
			if party.size() <= 1:
				msg = "That's your last creature!"
			else:
				var m: Dictionary = party.pop_at(sel)
				box.append(m)
				msg = "%s was stored." % Creatures.display_name(m)
		elif party.size() >= GameState.party_cap(gs):
			msg = "Your party is full (%d max)." % GameState.party_cap(gs)
		else:
			var m: Dictionary = box.pop_at(sel)
			m.hp = Creatures.max_hp(m)
			party.append(m)
			msg = "%s joined your party." % Creatures.display_name(m)
		sel = maxi(0, mini(sel, (party if col == 0 else box).size() - 1))

func _draw_col(title: String, list: Array, x: float, active: bool) -> void:
	Gfx.panel(x, 20, 112, 104)
	Gfx.text(title, x + 8, 26, {"size": 6, "color": "#6070a0"})
	var start := maxi(0, sel - 5)
	var from := start if active else 0
	var shown := list.slice(from, from + 6)
	for k in shown.size():
		var m: Dictionary = shown[k]
		var i := k + from
		var y := 38 + k * 14
		Menus.draw_mini(m, x + 6, y - 5, 14)
		Gfx.text(Creatures.display_name(m), x + 24, y, {"size": 5})
		Gfx.text("Lv%d" % m.level, x + 104, y, {"size": 5, "align": "right"})
		if active and i == sel:
			Gfx.cursor(x + 2, y - 1)
	if list.is_empty():
		Gfx.text("(empty)", x + 10, 40, {"size": 5, "color": "#909090"})

func draw() -> void:
	Gfx.rect(0, 0, Gfx.W, Gfx.H, "#90b0d8")
	Gfx.rect(0, 0, Gfx.W, 16, "#486088")
	Gfx.text("CREATURE STORAGE", 8, 5, {"color": "#ffffff", "size": 6})
	Game.player_tag(_player, 140, 4)
	_draw_col("PARTY %d/%d" % [party.size(), GameState.party_cap(Game.gs)], party, 4, col == 0)
	_draw_col("STORAGE (%d)" % box.size(), box, 124, col == 1)
	Gfx.panel(2, 128, Gfx.W - 4, 30)
	Gfx.text(msg, 10, 136, {"size": 6})
	Gfx.text("A: move  ◀▶: switch column  B: exit", 10, 147, {"size": 5, "color": "#606870"})
