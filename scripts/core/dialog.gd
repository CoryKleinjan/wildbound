class_name Dialog
extends Scene
## Typewriter text box. opts: player (int or "any"), choices (Array[String]),
## on_choice (Callable(int)), on_done (Callable()), auto (seconds before auto-advance, battle style).

var _o: Dictionary
var _idx := 0
var _shown := 0.0
var _lines: Array = []
var _choice := 0
var _wait := 0.0

func _init(msgs: Array, opts: Dictionary = {}) -> void:
	overlay = true
	_o = opts
	for m in msgs:
		var wrapped := Gfx.wrap(m, 212)
		for i in range(0, wrapped.size(), 2):
			_lines.append(wrapped.slice(i, i + 2))
	if _lines.is_empty():
		_lines.append([""])

func _pressed(b: String) -> bool:
	var p: Variant = _o.get("player", "any")
	if p == null or (p is String and p == "any"):
		return Game.input.any(b)
	return Game.input.p(p).pressed(b)

func _page_len() -> int:
	return "".join(_lines[_idx]).length()

func update(dt: float) -> void:
	var total := _page_len()
	if _shown < total:
		_shown += dt * 90
		if _pressed("a") or _pressed("b"):
			_shown = total
		return
	var last := _idx == _lines.size() - 1
	var choices: Array = _o.get("choices", [])
	if last and choices.size():
		if _pressed("up"):
			_choice = (_choice + choices.size() - 1) % choices.size()
			Audio.sfx("cursor")
		if _pressed("down"):
			_choice = (_choice + 1) % choices.size()
			Audio.sfx("cursor")
		if _pressed("a"):
			Audio.sfx("confirm")
			Game.pop(self)
			_call("on_choice", [_choice])
		elif _pressed("b"):
			Audio.sfx("cancel")
			Game.pop(self)
			_call("on_choice", [choices.size() - 1])
		return
	_wait += dt
	if _pressed("a") or _pressed("b") or (_o.has("auto") and _wait > _o.auto):
		if _pressed("a") or _pressed("b"):
			Audio.sfx("text")
		_wait = 0
		if last:
			Game.pop(self)
			_call("on_done", [])
		else:
			_idx += 1
			_shown = 0

func _call(key: String, args: Array) -> void:
	var cb: Callable = _o.get(key, Callable())
	if cb.is_valid():
		cb.callv(args)

func draw() -> void:
	Gfx.panel(2, 114, Gfx.W - 4, 44)
	var page: Array = _lines[_idx]
	var left := int(_shown)
	for i in page.size():
		var ln: String = page[i]
		Gfx.text(ln.substr(0, maxi(0, left)), 12, 124 + i * 15)
		left -= ln.length()
	var done := _shown >= _page_len()
	var choices: Array = _o.get("choices", [])
	var asking := _idx == _lines.size() - 1 and choices.size() > 0
	if done and not asking and int(Game.time * 3) % 2 == 0:
		Gfx.rect(Gfx.W - 16, 148, 6, 2, "#e05050")
		Gfx.rect(Gfx.W - 15, 150, 4, 1, "#e05050")
	if done and asking:
		var w := 64
		var h := choices.size() * 14 + 8
		Gfx.panel(Gfx.W - w - 4, 112 - h, w, h)
		for i in choices.size():
			Gfx.text(choices[i], Gfx.W - w + 10, 112 - h + 6 + i * 14)
		Gfx.cursor(Gfx.W - w + 2, 112 - h + 6 + _choice * 14)
