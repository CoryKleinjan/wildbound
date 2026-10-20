class_name NameEntryScene
extends Scene
## On-screen keyboard for naming a player. A types, B deletes, MENU (or OK) finishes.

const MAX_LEN := 8
const UPPER := ["ABCDEFGHI", "JKLMNOPQR", "STUVWXYZ-"]
const LOWER := ["abcdefghi", "jklmnopqr", "stuvwxyz."]
const ACTIONS := ["aA", "DEL", "OK"]

var _player: int
var _title: String
var _palette: String
var _default: String
var _on_done: Callable
var _name := ""
var _lower := false
var _cx := 0
var _cy := 0

func _init(player: int, title: String, palette: String, default_name: String, on_done: Callable) -> void:
	_player = player
	_title = title
	_palette = palette
	_default = default_name
	_on_done = on_done

func _rows() -> Array:
	return LOWER if _lower else UPPER

func update(_dt: float) -> void:
	var inp := Game.input.p(_player)
	var rows := _rows().size() + 1
	if inp.pressed("up"):
		_cy = (_cy + rows - 1) % rows
	if inp.pressed("down"):
		_cy = (_cy + 1) % rows
	var cols := ACTIONS.size() if _cy == rows - 1 else (_rows()[0] as String).length()
	if inp.pressed("left"):
		_cx = (_cx + cols - 1) % cols
	if inp.pressed("right"):
		_cx = (_cx + 1) % cols
	_cx = mini(_cx, cols - 1)
	if inp.pressed("b"):
		_name = _name.substr(0, maxi(0, _name.length() - 1))
	elif inp.pressed("start"):
		_finish()
	elif inp.pressed("a"):
		if _cy == rows - 1:
			match ACTIONS[_cx]:
				"aA":
					_lower = not _lower
				"DEL":
					_name = _name.substr(0, maxi(0, _name.length() - 1))
				"OK":
					_finish()
		elif _name.length() < MAX_LEN:
			_name += (_rows()[_cy] as String)[_cx]
			# Like the handhelds: after the first capital, switch to lower case.
			if _name.length() == 1 and not _lower:
				_lower = true
			if _name.length() == MAX_LEN:
				_cy = rows - 1
				_cx = ACTIONS.find("OK")

func _finish() -> void:
	var n := _name.strip_edges()
	Game.pop(self)
	_on_done.call(n if n != "" else _default)

func draw() -> void:
	Gfx.screen("naming", "#e8e0c8", "#5868a8", 20)
	Gfx.text(_title, Gfx.W / 2.0, 7, {"size": 6, "align": "center", "color": "#ffffff"})
	TrainerArt.draw_char(20, 30, "down", 0, DB.PALETTES[_palette], _palette)
	Gfx.panel(44, 26, 150, 24)
	for i in MAX_LEN:
		var x := 56 + i * 16
		if i < _name.length():
			Gfx.text(_name[i], x, 33, {"size": 8})
		Gfx.rect(x, 44, 10, 1, "#e05050" if i == _name.length() else "#9098a8")
	Gfx.panel(16, 56, 208, 98)
	var rows := _rows()
	for r in rows.size():
		var line: String = rows[r]
		for c in line.length():
			var x := 34 + c * 20
			var y := 66 + r * 18
			if r == _cy and c == _cx:
				Gfx.rect(x - 4, y - 3, 16, 14, "#f8e0a0")
			Gfx.text(line[c], x, y, {"size": 7})
	for i in ACTIONS.size():
		var x := 34 + i * 64
		var y := 128
		if _cy == rows.size() and _cx == i:
			Gfx.rect(x - 4, y - 3, 44, 14, "#f8e0a0")
		Gfx.text(ACTIONS[i], x, y, {"size": 7, "color": "#3858a8"})
	Gfx.text("A: type  B: delete  MENU: done", Gfx.W / 2.0, 144, {"size": 4, "align": "center", "color": "#707880", "shadow": null})
