extends SceneTree
## Renders every map whole, the way the overworld draws it (painting, field objects, NPCs), with the player,
## weather and cave darkness left out. The overworld's own draw() runs once per screen-sized window and the windows are stitched.
## xvfb-run -a godot --path . --rendering-driver opengl3 -s res://tests/map_gallery.gd -- <out_dir> [map_id ...]

var _ow
var _canvas: Node2D
var _cams: Array = []

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 3:
		await process_frame
	var game = root.get_node("Game")
	var db = root.get_node("DB")
	var ids: Array = args.slice(1) if args.size() > 1 else db.MAPS.keys()
	game.gs = load("res://scripts/game/game_state.gd").new_game("solo", ["cindercub"])
	var sub := SubViewport.new()
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub.transparent_bg = false
	root.add_child(sub)
	_canvas = Node2D.new()
	_canvas.draw.connect(_draw_map)
	sub.add_child(_canvas)
	var index := []
	for id in ids:
		var m: Dictionary = db.MAPS[id]
		game.gs.map = id
		game.gs.x = 0
		game.gs.y = 0
		_ow = _hidden_player_overworld().new()
		game.replace(_ow)
		_ow._banner.t = 0.0
		# Dark caves are drawn lit; in game they're black past a small circle until Flash is used.
		var dark: bool = m.get("dark", false)
		m.dark = false
		# Weather tints and particles are per screen, so they're left out of the stitched image.
		var weather: String = m.get("weather", "")
		m.erase("weather")
		var w: int = _ow._map_w()
		var h: int = _ow._map_h()
		sub.size = Vector2i(w * 16, h * 16)
		_cams = []
		for cy in range(0, h * 16, Gfx.H):
			for cx in range(0, w * 16, Gfx.W):
				_cams.append(Vector2i(cx, cy))
		_canvas.queue_redraw()
		for k in 3:
			await process_frame
		var img: Image = sub.get_texture().get_image()
		img.save_png(out.path_join("%s.png" % id))
		m.dark = dark
		if weather != "":
			m.weather = weather
		index.append({"id": id, "name": m.name, "w": w, "h": h, "painted": ResourceLoader.exists("res://assets/maps/%s.png" % id),
			"interior": m.get("interior", false), "indoor": m.get("indoor", false), "townId": m.get("townId", ""), "town": m.get("town", false), "dark": dark, "weather": weather})
		print("saved ", id)
	var f := FileAccess.open(out.path_join("index.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(index))
	f.close()
	quit()

## Each window puts the player where the overworld camera lands on it, so draw() renders exactly that window.
func _draw_map() -> void:
	if _ow == null:
		return
	Gfx.ci = _canvas
	for c in _cams:
		# Rooms that fit on screen are centered by draw() itself; shift the window to match.
		var cam: Vector2i = c
		if _ow.map.get("interior", false):
			if _ow._map_w() * 16 <= Gfx.W:
				cam.x = roundi((_ow._map_w() * 16 - Gfx.W) / 2.0)
			if _ow._map_h() * 16 <= Gfx.H:
				cam.y = roundi((_ow._map_h() * 16 - Gfx.H) / 2.0)
		# Camera = player pixel + 8 - half the screen; a fractional move puts the player at any pixel.
		var px: float = c.x - 8 + Gfx.W / 2.0
		var py: float = c.y - 8 + Gfx.H / 2.0
		_ow.player.x = 0
		_ow.player.y = 0
		_ow.player.move = {"fx": px / 16.0, "fy": py / 16.0, "t": 0.0, "dur": 1.0, "jump": false}
		_canvas.draw_set_transform(Vector2(cam), 0, Vector2.ONE)
		_ow.draw()
	_canvas.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

var _patched: GDScript

## The overworld with its draw() copied unchanged except that the player isn't added to the actors.
func _hidden_player_overworld() -> GDScript:
	if _patched != null:
		return _patched
	var src: String = FileAccess.get_file_as_string("res://scripts/game/overworld.gd")
	var start := src.find("func draw() -> void:")
	var end := src.find("\nstatic func ", start)
	var body := src.substr(start, end - start)
	body = body.replace("\tactors.append(player)\n", "")
	body = body.replace("var actors: Array[Actor] = []", "var actors: Array = []")
	body = body.replace("func(a: Actor, b: Actor) -> bool:", "func(a, b) -> bool:")
	_patched = GDScript.new()
	_patched.source_code = "extends OverworldScene\n\nfunc update(_dt: float) -> void:\n\tpass\n\n" + body
	_patched.reload()
	return _patched
