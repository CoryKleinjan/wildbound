class_name SecretBase
## Secret Bases: a creature that knows Secret Power opens a hidden room in certain trees (z tiles listed in a
## map's secretSpots). You have one base at a time; moving it keeps your decorations. Decorations are bought
## at the Dept. Store and placed from the PC inside the base.

## Spots in the base room where decorations go, in order.
const SLOTS := [[2, 2], [8, 2], [3, 4], [7, 4], [2, 6], [8, 6], [4, 2], [6, 2], [4, 6], [6, 6]]
const ENTRY := Vector2i(5, 7)

static func interact_tree(o: OverworldScene, tx: int, ty: int) -> void:
	var gs: Dictionary = Game.gs
	var b: Variant = gs.secretBase
	if b != null and b.map == o.map.id and int(b.x) == tx and int(b.y) == ty:
		Game.ask("It's your Secret Base. Go inside?", ["YES", "NO"], func(c: int) -> void:
			if c == 0:
				_enter(o))
		return
	if not o.map.get("secretSpots", []).has("%d,%d" % [tx, ty]):
		Game.say(["It's a tree with a small hollow."])
		return
	var m: Variant = Field.knower("secretPower")
	if m == null:
		Game.say(["There's a small indent in the tree. A creature's move might open it up."])
		return
	var ask := "There's a small indent in the tree. Use Secret Power?"
	Game.ask(ask, ["YES", "NO"], func(c: int) -> void:
		if c != 0:
			return
		var make := func() -> void:
			var decor: Array = b.decor if b != null else []
			gs.secretBase = {"map": o.map.id, "x": tx, "y": ty, "decor": decor}
			Game.say(["%s used Secret Power!" % Creatures.display_name(m), "Discovered a small cavern! It'll make a fine Secret Base."], func() -> void: _enter(o))
		if b != null:
			Game.ask("You already have a Secret Base in %s. Move it here? Your decorations come along." % DB.MAPS[b.map].name, ["YES", "NO"], func(k: int) -> void:
				if k == 0:
					make.call())
		else:
			make.call())

static func _enter(o: OverworldScene) -> void:
	Field._warp(o, "secretbase", ENTRY.x, ENTRY.y, "up", false)

static func open_pc(o: OverworldScene) -> void:
	var gs: Dictionary = Game.gs
	if gs.secretBase == null:
		return
	Game.ask("It's your base's PC. What would you like to do?", ["DECORATE", "PUT AWAY", "TURN OFF"], func(c: int) -> void:
		if c == 0:
			_decorate()
		elif c == 1:
			gs.secretBase.decor = []
			Game.say(["All the decorations were put away."]))

static func _decorate() -> void:
	var gs: Dictionary = Game.gs
	var placed: Array = gs.secretBase.decor.map(func(d: Dictionary) -> String: return d.id)
	var free: Array = gs.decor.filter(func(id: String) -> bool: return not placed.has(id))
	if free.is_empty():
		Game.say(["There are no decorations to place.", "The Dept. Store in Lumenvale sells them."] if gs.decor.is_empty() else ["Every decoration you own is already out."])
		return
	if gs.secretBase.decor.size() >= SLOTS.size():
		Game.say(["There's no more room for decorations."])
		return
	var items: Array = []
	for id in free:
		items.append(DB.DECORATIONS[id].name)
	items.append("CANCEL")
	var ref := {}
	var menu := ListMenu.new({
		"x": 100, "y": 8, "w": 136, "player": 0, "title": "Place which?", "items": items, "max_visible": 8,
		"on_cancel": func() -> void: Game.pop(ref.menu),
		"on_select": func(i: int) -> void:
			Game.pop(ref.menu)
			if i >= free.size():
				return
			var slot: Array = SLOTS[gs.secretBase.decor.size()]
			gs.secretBase.decor.append({"id": free[i], "x": slot[0], "y": slot[1]})
			Audio.sfx("confirm")
			Game.say(["Placed the %s." % DB.DECORATIONS[free[i]].name]),
	})
	ref.menu = menu
	Game.push(menu)

static func interact_decoration(o: OverworldScene, tx: int, ty: int) -> bool:
	var gs: Dictionary = Game.gs
	if gs.secretBase == null:
		return false
	for d in gs.secretBase.decor:
		if int(d.x) == tx and int(d.y) == ty:
			Game.say(["It's a %s." % DB.DECORATIONS[d.id].name])
			return true
	return false
