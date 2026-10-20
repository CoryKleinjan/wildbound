class_name TownMapScene
extends Scene
## The region map (Navi Gear MAP, and Fly). Routes are drawn as paths, towns as squares, and a marker shows
## where you are. The cursor jumps between places with the arrow keys; in Fly mode A picks a town you've visited.

var _player: int
var _fly: bool
var _on_pick: Callable
var _on_close: Callable
var _points: Array = []
var _sel := 0
var _t := 0.0
var _scale := 0.5
var _ox := 0.0
var _oy := 0.0
var _here := ""
var _maxx := 1.0
var _maxy := 1.0
var _painted_fits := false

## Where you are on the region map: the map itself, or the outdoor map a building or cave belongs to.
static func region_id(map_id: String) -> String:
	var id := map_id
	for i in 4:
		if DB.REGION_MAP.has(id):
			return id
		id = DB.MAP_PARENT.get(id, "")
		if id == "":
			break
	return ""

## fly: only visited towns can be picked; on_pick(town_id) runs then.
func _init(player: int, fly: bool, on_pick: Callable, on_close: Callable) -> void:
	_player = player
	_fly = fly
	_on_pick = on_pick
	_on_close = on_close
	var gs: Dictionary = Game.gs
	_here = region_id(gs.map)
	var maxx := 1.0
	var maxy := 1.0
	for id in DB.REGION_MAP:
		var r: Dictionary = DB.REGION_MAP[id]
		maxx = maxf(maxx, r.x + r.w)
		maxy = maxf(maxy, r.y + r.h)
	_maxx = maxx
	_maxy = maxy
	_painted_fits = _painting_fits()
	_scale = minf((Gfx.W - 24) / maxx, (Gfx.H - 46) / maxy)
	_ox = (Gfx.W - maxx * _scale) / 2.0
	_oy = 22 + (Gfx.H - 46 - maxy * _scale) / 2.0
	for id in DB.REGION_MAP:
		var r: Dictionary = DB.REGION_MAP[id]
		if _fly and not (DB.FLY_POINTS.has(id) and gs.fly.has(id)):
			continue
		if id == "battlefrontier" and not gs.flags.get("champion", false):
			continue
		_points.append(id)
	_points.sort_custom(func(a: String, b: String) -> bool: return _center(a).x < _center(b).x)
	_sel = maxi(0, _points.find(_here))

## The painting only fits the region layout it was made for (assets/screens/townmap.json, written by
## tools/artgen/townmap.py); after routes are added the map is drawn from the layout until it is repainted.
func _painting_fits() -> bool:
	var f := FileAccess.open("res://assets/screens/townmap.json", FileAccess.READ)
	if f == null:
		return false
	var fit: Variant = JSON.parse_string(f.get_as_text())
	return fit is Dictionary and is_equal_approx(float(fit.get("w", 0)), _maxx) and is_equal_approx(float(fit.get("h", 0)), _maxy)

func _center(id: String) -> Vector2:
	var r: Dictionary = DB.REGION_MAP[id]
	return Vector2(_ox + (r.x + r.w / 2.0) * _scale, _oy + (r.y + r.h / 2.0) * _scale)

func update(dt: float) -> void:
	_t += dt
	var inp := Game.input.p(_player)
	for d in ["up", "down", "left", "right"]:
		if inp.pressed(d):
			_move(d)
	if inp.pressed("a") and _fly and not _points.is_empty():
		Audio.sfx("confirm")
		_on_pick.call(_points[_sel])
	elif inp.pressed("b"):
		Audio.sfx("cancel")
		_on_close.call()

## Moves the cursor to the nearest place in that direction.
func _move(d: String) -> void:
	if _points.is_empty():
		return
	var dir: Vector2 = {"up": Vector2(0, -1), "down": Vector2(0, 1), "left": Vector2(-1, 0), "right": Vector2(1, 0)}[d]
	var from := _center(_points[_sel])
	var best := -1
	var best_score := INF
	for i in _points.size():
		var v := _center(_points[i]) - from
		var along := v.dot(dir)
		if i == _sel or along <= 0.5:
			continue
		var score := along + absf(v.dot(Vector2(dir.y, dir.x))) * 2.0
		if score < best_score:
			best_score = score
			best = i
	if best >= 0:
		_sel = best
		Audio.sfx("cursor")

func draw() -> void:
	var gs: Dictionary = Game.gs
	# The painted region map (assets/screens/townmap.png, from tools/artgen/townmap.py) has the land and routes;
	# the Battle Frontier isn't on it, since it only appears after the League.
	var painted := ArtAssets.texture("screens/townmap") if _painted_fits else null
	if painted != null:
		Gfx.image(painted, 0, 0)
	else:
		Gfx.rect(0, 0, Gfx.W, Gfx.H, "#3870b8")
		for i in 40:
			Gfx.rect(fposmod(i * 47.3 + _t * 3, Gfx.W), fposmod(i * 29.1, Gfx.H), 3, 1, Color(1, 1, 1, 0.15))
	# Land under every route and town, then the routes and towns on top.
	for id in DB.REGION_MAP:
		var r: Dictionary = DB.REGION_MAP[id]
		if id == "battlefrontier" and not gs.flags.get("champion", false):
			continue
		if painted != null and id != "battlefrontier":
			continue
		var x: float = _ox + r.x * _scale
		var y: float = _oy + r.y * _scale
		if not r.get("sea", false):
			Gfx.rect(x - 2, y - 2, r.w * _scale + 4, r.h * _scale + 4, "#78b858")
	for id in DB.REGION_MAP:
		var r: Dictionary = DB.REGION_MAP[id]
		if id == "battlefrontier" and not gs.flags.get("champion", false):
			continue
		if painted != null and id != "battlefrontier":
			continue
		var c := _center(id)
		if r.town:
			continue
		var w: float = r.w * _scale
		var h: float = r.h * _scale
		if r.get("sea", false) and w > h:
			Gfx.rect(c.x - w / 2, c.y - 1, w, 2, "#a8d0f8")
		elif r.get("sea", false):
			Gfx.rect(c.x - 1, c.y - h / 2, 2, h, "#a8d0f8")
		elif w > h:
			Gfx.rect(c.x - w / 2, c.y - 2, w, 4, "#e8d098")
		else:
			Gfx.rect(c.x - 2, c.y - h / 2, 4, h, "#e8d098")
	for id in DB.REGION_MAP:
		var r: Dictionary = DB.REGION_MAP[id]
		if not r.town or (id == "battlefrontier" and not gs.flags.get("champion", false)):
			continue
		var c := _center(id)
		var visited: bool = gs.fly.has(id)
		Gfx.rect(c.x - 5, c.y - 5, 10, 10, "#f8f8f8")
		Gfx.rect(c.x - 4, c.y - 4, 8, 8, "#e05040" if visited else "#a08070")
	# You are here.
	if _here != "" and DB.REGION_MAP.has(_here):
		var c := _center(_here)
		if fmod(_t, 0.8) < 0.55:
			Gfx.ellipse(c.x, c.y, 4, 4, "#f8f8f8")
			Gfx.ellipse(c.x, c.y, 3, 3, "#3060e0")
	# The cursor.
	if not _points.is_empty():
		var c := _center(_points[_sel])
		var k := 2.0 + sin(_t * 6) * 1.0
		Gfx.rect(c.x - 7 - k, c.y - 7 - k, 4, 2, "#f8e040")
		Gfx.rect(c.x - 7 - k, c.y - 7 - k, 2, 4, "#f8e040")
		Gfx.rect(c.x + 3 + k, c.y - 7 - k, 4, 2, "#f8e040")
		Gfx.rect(c.x + 5 + k, c.y - 7 - k, 2, 4, "#f8e040")
		Gfx.rect(c.x - 7 - k, c.y + 5 + k, 4, 2, "#f8e040")
		Gfx.rect(c.x - 7 - k, c.y + 3 + k, 2, 4, "#f8e040")
		Gfx.rect(c.x + 3 + k, c.y + 5 + k, 4, 2, "#f8e040")
		Gfx.rect(c.x + 5 + k, c.y + 3 + k, 2, 4, "#f8e040")
	Gfx.rect(0, 0, Gfx.W, 18, "#284878")
	Gfx.text("FLY: where to?" if _fly else "REGION MAP", 8, 6, {"color": "#ffffff", "size": 6})
	if _here != "":
		Gfx.text("You: %s" % DB.REGION_MAP[_here].name, Gfx.W - 8, 6, {"color": "#d0e0ff", "size": 6, "align": "right"})
	Gfx.panel(4, Gfx.H - 22, Gfx.W - 8, 20)
	if _points.is_empty():
		Gfx.text("There's nowhere to fly to yet.", 12, Gfx.H - 15, {"size": 6})
	else:
		var id: String = _points[_sel]
		Gfx.text(DB.REGION_MAP[id].name, 12, Gfx.H - 15, {"size": 6})
		Gfx.text("A: fly  B: cancel" if _fly else "B: close", Gfx.W - 12, Gfx.H - 15, {"size": 5, "align": "right", "color": "#606060"})
