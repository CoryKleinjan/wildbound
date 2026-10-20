class_name Menus
## Module functions of TS menus.ts: party flow, bag, items, shop and move learning.
## The scene classes live in party_screen.gd, summary_screen.gd, storage_screen.gd and evolution_scene.gd.

## A scene whose draw is a Callable (TS inline `{ update() {}, draw() {...} }` objects).
class FnScene extends Scene:
	var draw_fn: Callable
	func _init(fn: Callable, is_overlay: bool = false) -> void:
		draw_fn = fn
		overlay = is_overlay
	func draw() -> void:
		draw_fn.call()

static func draw_mini(m: Dictionary, x: float, y: float, size: float = 24, bob: float = 0) -> void:
	var spr: Texture2D = CreatureArt.creature_sprite(m.species, Creatures.is_shiny(m))
	Gfx.image(spr, x, y + bob, {"scale": size / spr.get_width()})

# ---------- overworld party flow ----------
static func open_party_menu(player: int, on_close: Callable) -> void:
	var gs: Dictionary = Game.gs
	var party: Array = gs.players[player].party
	var st := {"swap_from": -1}
	var screen := PartyScreen.new({"player": player, "party": party, "prompt": "Choose a creature."})
	screen.o.on_cancel = func() -> void:
		if st.swap_from >= 0:
			st.swap_from = -1
			screen.o.erase("marked")
			screen.o.prompt = "Choose a creature."
			return
		Game.pop(screen)
		on_close.call()
	screen.o.on_select = func(i: int) -> void:
		if st.swap_from >= 0:
			var tmp: Dictionary = party[st.swap_from]
			party[st.swap_from] = party[i]
			party[i] = tmp
			st.swap_from = -1
			screen.o.erase("marked")
			screen.o.prompt = "Choose a creature."
			return
		var ref := {}
		var menu := ListMenu.new({
			"x": 160, "y": 60, "w": 76, "player": player, "items": ["SUMMARY", "SWITCH", "CANCEL"],
			"on_cancel": func() -> void: Game.pop(ref.menu),
			"on_select": func(k: int) -> void:
				Game.pop(ref.menu)
				if k == 0:
					var sref := {}
					var s := SummaryScreen.new(party[i], player, func() -> void: Game.pop(sref.s))
					sref.s = s
					Game.push(s)
				elif k == 1:
					st.swap_from = i
					screen.o.marked = i
					screen.o.prompt = "Move to where?",
		})
		ref.menu = menu
		Game.push(menu)
	Game.push(screen)

# ---------- bag ----------
## o keys: player (int), in_battle (bool), can_throw (bool), on_pick (Callable(item_id: String, done: Callable)), on_close (Callable()).
static func open_bag(o: Dictionary) -> void:
	var gs: Dictionary = Game.gs
	var ids: Array = []
	for id in DB.ITEMS:
		if gs.bag.get(id, 0) > 0:
			ids.append(id)
	var bg := FnScene.new(func() -> void:
		Gfx.rect(0, 0, Gfx.W, Gfx.H, "#e8c878")
		Gfx.rect(0, 0, Gfx.W, 16, "#a87838")
		Gfx.text("BAG", 8, 5, {"color": "#ffffff", "size": 6})
		Gfx.text("$%d" % gs.money, Gfx.W - 8, 5, {"color": "#ffffff", "size": 6, "align": "right"})
		Game.player_tag(o.player, 40, 4))
	var on_close: Callable = o.on_close
	if ids.is_empty():
		Game.push(bg)
		Game.say(["The bag is empty."], func() -> void:
			Game.pop(bg)
			on_close.call(), o.player)
		return
	var items: Array = []
	for id in ids:
		var it: Dictionary = DB.item(id)
		items.append({"label": it.name, "right": "x%d" % gs.bag[id], "disabled": it.effect.kind == "ball" and not o.can_throw})
	items.append({"label": "CLOSE"})
	var ref := {}
	var menu := ListMenu.new({
		"x": 60, "y": 20, "w": 176, "player": o.player, "max_visible": 7,
		"items": items,
		"footer": func(i: int) -> String: return DB.item(ids[i]).desc if i < ids.size() else "",
		"on_cancel": func() -> void:
			Game.pop(ref.menu)
			Game.pop(bg)
			on_close.call(),
		"on_select": func(i: int) -> void:
			if i == ids.size():
				Game.pop(ref.menu)
				Game.pop(bg)
				on_close.call()
				return
			(o.on_pick as Callable).call(ids[i], func() -> void:
				Game.pop(ref.menu)
				Game.pop(bg)),
	})
	ref.menu = menu
	Game.push(bg)
	Game.push(menu)

## Applies a healing/cure item outside battle. Returns a message or null if it had no effect.
static func use_item_on(gs: Dictionary, item_id: String, m: Dictionary) -> Variant:
	var it: Dictionary = DB.item(item_id)
	var eff: Dictionary = it.effect
	if eff.kind == "heal":
		var mx: int = Creatures.max_hp(m)
		if m.hp <= 0 or m.hp >= mx:
			return null
		var before: int = m.hp
		m.hp = mini(mx, m.hp + eff.amount)
		gs.bag[item_id] -= 1
		return "%s's HP was restored by %d point(s)." % [Creatures.display_name(m), m.hp - before]
	if eff.kind == "revive":
		if m.hp > 0:
			return null
		m.hp = Creatures.max_hp(m) / 2
		gs.bag[item_id] -= 1
		return "%s was revived!" % Creatures.display_name(m)
	if eff.kind == "cure":
		if m.status == null or not (eff.statuses as Array).has(m.status) or m.hp <= 0:
			return null
		m.status = null
		m.sleepTurns = 0
		gs.bag[item_id] -= 1
		return "%s was cured!" % Creatures.display_name(m)
	return null

static func open_bag_overworld(player: int, on_close: Callable) -> void:
	var gs: Dictionary = Game.gs
	open_bag({
		"player": player, "in_battle": false, "can_throw": false, "on_close": on_close,
		"on_pick": func(id: String, done: Callable) -> void:
			var party: Array = gs.players[player].party
			var ps := PartyScreen.new({"player": player, "party": party, "prompt": "Use %s on?" % DB.item(id).name})
			ps.o.on_cancel = func() -> void: Game.pop(ps)
			ps.o.on_select = func(i: int) -> void:
				var r: Variant = use_item_on(gs, id, party[i])
				Game.say([r if r != null else "It won't have any effect."], func() -> void:
					Game.pop(ps)
					if r != null:
						done.call()
						on_close.call(), player)
			Game.push(ps),
	})

# ---------- shop ----------
static func badge_count(gs: Dictionary) -> int:
	var re := RegEx.create_from_string("^badge\\d$")
	var n := 0
	for f in gs.flags:
		if re.search(f) != null:
			n += 1
	return n

static func open_shop(player: int, on_close: Callable) -> void:
	var gs: Dictionary = Game.gs
	var badges := badge_count(gs)
	var stock: Array = ["orb"]
	if badges >= 1: stock.append("greatOrb")
	if badges >= 3: stock.append("ultraOrb")
	stock.append("potion")
	if badges >= 1: stock.append("superPotion")
	if badges >= 4: stock.append("hyperPotion")
	if badges >= 2: stock.append("revive")
	stock.append_array(["antidote", "parlyzHeal", "awakening", "burnHeal"])
	if badges >= 3: stock.append("fullHeal")
	var header := FnScene.new(func() -> void:
		Gfx.panel(4, 4, 90, 22)
		Gfx.text("$%d" % gs.money, 12, 12, {"size": 6}), true)
	var items: Array = []
	for id in stock:
		items.append({"label": DB.item(id).name, "right": "$%d" % DB.item(id).price})
	items.append({"label": "DONE"})
	var ref := {}
	var close := func() -> void:
		Game.pop(ref.menu)
		Game.pop(header)
		on_close.call()
	var menu := ListMenu.new({
		"x": 100, "y": 4, "w": 136, "player": player, "max_visible": 7,
		"items": items,
		"footer": func(i: int) -> String:
			return ("%s  (You have %d)" % [DB.item(stock[i]).desc, gs.bag.get(stock[i], 0)]) if i < stock.size() else "",
		"on_cancel": func() -> void: close.call(),
		"on_select": func(i: int) -> void:
			if i == stock.size():
				close.call()
				return
			var it: Dictionary = DB.item(stock[i])
			if gs.money < it.price:
				Game.say(["You don't have enough money."], Callable(), player)
				return
			Game.ask("Buy a %s for $%d?" % [it.name, it.price], ["YES", "NO"], func(c: int) -> void:
				if c != 0:
					return
				gs.money -= it.price
				gs.bag[it.id] = gs.bag.get(it.id, 0) + 1
				Game.say(["Here you go! Thank you."], Callable(), player), player),
	})
	ref.menu = menu
	Game.push(header)
	Game.push(menu)

# ---------- move learning ----------
static func learn_move_flow(mon: Dictionary, move_id: String, player: int, done: Callable) -> void:
	var name := Creatures.display_name(mon)
	var mv: Dictionary = DB.move(move_id)
	for m in mon.moves:
		if m.id == move_id:
			done.call()
			return
	if mon.moves.size() < 4:
		mon.moves.append(Creatures.move_slot(move_id))
		Game.say(["%s learned %s!" % [name, mv.name]], done, player)
		return
	var not_learned := ["%s did not learn %s." % [name, mv.name]]
	Game.ask("%s wants to learn %s. But it already knows four moves. Forget a move for %s?" % [name, mv.name, mv.name], ["YES", "NO"], func(c: int) -> void:
		if c != 0:
			Game.say(not_learned, done, player)
			return
		var items: Array = []
		for m in mon.moves:
			items.append({"label": DB.move(m.id).name, "right": "%d/%d" % [m.pp, m.maxPp]})
		items.append({"label": "Keep old moves"})
		var ref := {}
		var menu := ListMenu.new({
			"x": 60, "y": 20, "w": 176, "player": player, "title": "Forget which move? (new: %s)" % mv.name,
			"items": items,
			"footer": func(i: int) -> String:
				if i < 4:
					var om: Dictionary = DB.move(mon.moves[i].id)
					return "%s - %s" % [om.type, om.desc]
				return "%s %s - %s" % [mv.type, ("Pow %d" % mv.power) if mv.power else "", mv.desc],
			"on_cancel": func() -> void:
				Game.pop(ref.menu)
				Game.say(not_learned, done, player),
			"on_select": func(i: int) -> void:
				Game.pop(ref.menu)
				if i == 4:
					Game.say(not_learned, done, player)
					return
				var old: String = DB.move(mon.moves[i].id).name
				mon.moves[i] = Creatures.move_slot(move_id)
				Game.say(["1, 2, and... Poof!", "%s forgot %s. And... %s learned %s!" % [name, old, name, mv.name]], done, player),
		})
		ref.menu = menu
		Game.push(menu), player)
