class_name TitleScene
extends Scene
## Title screen with the CONTINUE / NEW GAME menu.

var _t := 0.0
var _menu_open := false

func update(dt: float) -> void:
	_t += dt
	if _menu_open:
		return
	if Game.input.any("a") or Game.input.any("start"):
		_open_menu()

func _open_menu() -> void:
	_menu_open = true
	var items: Array = []
	if GameState.has_save():
		items.append("CONTINUE")
	items.append_array(["NEW GAME - SOLO", "NEW GAME - CO-OP", "CONTROLS"])
	var ref: Array = []
	var menu := ListMenu.new({
		"x": 40, "y": 92, "w": 160, "items": items,
		"on_cancel": func() -> void:
			Game.pop(ref[0])
			_menu_open = false,
		"on_select": func(i: int) -> void: _on_pick(items[i]),
	})
	ref.append(menu)
	Game.push(menu)

func _on_pick(pick: String) -> void:
	if pick == "CONTINUE":
		var gs: Variant = GameState.load_game()
		if gs == null:
			Game.say(["The save file could not be read."])
			return
		Game.gs = gs
		Game.input.coop = gs.mode == "coop"
		Game.transition(func() -> void: Game.replace(OverworldScene.new()))
	elif pick == "CONTROLS":
		Game.say(OverworldScene.controls_text(false) + OverworldScene.controls_text(true))
	else:
		var coop := pick.contains("CO-OP")
		Game.input.coop = coop
		Game.transition(func() -> void: Game.replace(StarterScene.new(coop)))

func draw() -> void:
	# Sky gradient.
	var top := Color("#78b8f0")
	var bottom := Color("#c8f0b0")
	Gfx.ci.draw_polygon(
		PackedVector2Array([Vector2(0, 0), Vector2(Gfx.W, 0), Vector2(Gfx.W, Gfx.H), Vector2(0, Gfx.H)]),
		PackedColorArray([top, top, bottom, bottom]))
	Gfx.rect(0, 120, Gfx.W, 40, "#78c060")
	var bob := sin(_t * 2) * 2
	var s := 56.0 / 64.0
	Gfx.image(CreatureArt.creature_sprite("cindercub"), 20, 64 + bob, {"scale": s})
	Gfx.image(CreatureArt.creature_sprite("sproutle"), 92, 68 - bob, {"scale": s})
	Gfx.image(CreatureArt.creature_sprite("ripplet"), 164, 64 + bob, {"scale": s})
	Gfx.text("WILDBOUND", Gfx.W / 2.0, 18, {"size": 16, "align": "center", "color": "#f8f8f8", "shadow": "#384878"})
	Gfx.text("a co-op creature adventure", Gfx.W / 2.0, 42, {"size": 6, "align": "center", "color": "#283860", "shadow": null})
	if not _menu_open and floori(_t * 2) % 2 == 0:
		Gfx.text("PRESS A / ENTER", Gfx.W / 2.0, 140, {"size": 7, "align": "center", "color": "#f8f8f8", "shadow": "#305020"})
