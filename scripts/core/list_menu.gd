class_name ListMenu
extends Scene
## Vertical menu. opts: x, y, w, items (Strings or {label, disabled, right}), player, title,
## on_select (Callable(int)), on_cancel (Callable()), on_move (Callable(int)),
## footer (Callable(int) -> String, "" for none), max_visible, start.

var sel := 0
var items: Array = []
var _scroll := 0
var _o: Dictionary

func _init(opts: Dictionary) -> void:
	overlay = true
	_o = opts
	for it in opts.items:
		items.append({"label": it} if it is String else it)
	sel = opts.get("start", 0)

func update(_dt: float) -> void:
	var inp := Game.input.p(_o.get("player", 0))
	var n := items.size()
	if inp.pressed("up"):
		sel = (sel + n - 1) % n
		_emit("on_move", [sel])
	if inp.pressed("down"):
		sel = (sel + 1) % n
		_emit("on_move", [sel])
	if inp.pressed("a") and not items[sel].get("disabled", false):
		_emit("on_select", [sel])
	elif inp.pressed("b") and _o.has("on_cancel"):
		_emit("on_cancel", [])
	var vis: int = _o.get("max_visible", 99)
	if sel < _scroll:
		_scroll = sel
	if sel >= _scroll + vis:
		_scroll = sel - vis + 1

func _emit(key: String, args: Array) -> void:
	var cb: Callable = _o.get(key, Callable())
	if cb.is_valid():
		cb.callv(args)

func draw() -> void:
	var vis: int = mini(_o.get("max_visible", 99), items.size())
	var top := 14 if _o.has("title") else 0
	var h := vis * 14 + 10 + top
	var x: float = _o.x
	var y: float = _o.y
	var w: float = _o.w
	Gfx.panel(x, y, w, h)
	if _o.has("title"):
		Gfx.text(_o.title, x + 8, y + 6, {"color": "#6070a0", "size": 6})
	for i in vis:
		var it: Dictionary = items[i + _scroll]
		var iy := y + 6 + top + i * 14
		Gfx.text(it.label, x + 14, iy, {"color": "#a0a0a8" if it.get("disabled", false) else "#303030"})
		if it.get("right", "") != "":
			Gfx.text(it.right, x + w - 8, iy, {"align": "right", "color": "#505868"})
	Gfx.cursor(x + 5, y + 6 + top + (sel - _scroll) * 14 + 0.5, "#3878e0" if _o.get("player", 0) == 1 else "#303030")
	if _o.has("footer"):
		var f: String = _o.footer.call(sel)
		if f != "":
			Gfx.panel(2, 128, Gfx.W - 4, 30)
			var lines := Gfx.wrap(f, 220, 6)
			for i in mini(2, lines.size()):
				Gfx.text(lines[i], 10, 136 + i * 10, {"size": 6})
