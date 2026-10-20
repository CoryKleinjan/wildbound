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
	if m.get("egg", false):
		draw_egg(x + size / 2, y + size / 2 + bob, size / 24.0)
		return
	# The two-frame party icon (assets/creatures/icons/<id>.png, from tools/artgen/partyicons.py); a bob shows frame 2.
	var icon := ArtAssets.texture("creatures/icons/" + str(m.species))
	if icon != null and not Creatures.is_shiny(m):
		var k := size / 22.0
		var c := 32.0 * k
		Gfx.ci.draw_texture_rect_region(icon, Rect2(x + size / 2 - c / 2, y + size - c + 2 * k, c, c), Rect2(32 if bob > 0 else 0, 0, 32, 32))
		return
	var spr: Texture2D = CreatureArt.creature_sprite(m.species, Creatures.is_shiny(m))
	Gfx.image(spr, x, y + bob, {"scale": size / spr.get_width()})

## An Egg: cream with green spots.
static func draw_egg(cx: float, cy: float, k: float = 1.0) -> void:
	var tex := ArtAssets.texture("icons/egg")
	if tex != null:
		Gfx.image(tex, cx - 12 * k, cy - 12 * k, {"scale": k})
		return
	Gfx.rect(cx - 6 * k, cy - 7 * k, 12 * k, 15 * k, "#506040")
	Gfx.rect(cx - 5 * k, cy - 8 * k, 10 * k, 17 * k, "#506040")
	Gfx.rect(cx - 5 * k, cy - 6 * k, 10 * k, 13 * k, "#f8f0d0")
	Gfx.rect(cx - 4 * k, cy - 7 * k, 8 * k, 15 * k, "#f8f0d0")
	Gfx.rect(cx - 3 * k, cy - 3 * k, 3 * k, 3 * k, "#78b850")
	Gfx.rect(cx + 1 * k, cy + 2 * k, 3 * k, 3 * k, "#78b850")
	Gfx.rect(cx - 2 * k, cy - 6 * k, 2 * k, 2 * k, "#ffffff")

## Draws an item's 24x24 icon (assets/icons/<id>.png) at (x, y); TMs and HMs share one disc tinted with the move's type.
## Draws nothing when there is no icon.
static func draw_item_icon(id: String, x: float, y: float) -> void:
	var it: Dictionary = DB.item(id)
	if it.get("effect", {}).get("kind", "") == "tm":
		var tex := ArtAssets.texture("icons/tm")
		if tex == null:
			return
		var mv: Dictionary = DB.MOVES.get(it.effect.get("move", ""), {})
		var tint: Color = Gfx.col(DB.TYPE_COLORS.get(mv.get("type", ""), "#ffffff")).lightened(0.25)
		Gfx.image(tex, x, y, {"modulate": tint})
		return
	var icon := ArtAssets.texture("icons/" + id)
	if icon != null:
		Gfx.image(icon, x, y)

# ---------- overworld party flow ----------
## Field moves usable from the party menu, in the order they're listed.
const FIELD_MOVES := ["cut", "fly", "surf", "strength", "flash", "rockSmash", "waterfall", "dive", "teleport", "dig",
	"secretPower", "sweetScent", "softBoiled", "milkDrink"]

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
		var m: Dictionary = party[i]
		var labels: Array = ["SUMMARY"]
		var field: Array = []
		if not m.get("egg", false):
			for id in FIELD_MOVES:
				if Creatures.knows(m, id):
					field.append(id)
					labels.append(DB.move(id).name.to_upper())
		labels.append("SWITCH")
		if not m.get("egg", false):
			labels.append("ITEM")
		labels.append("CANCEL")
		var ref := {}
		var menu := ListMenu.new({
			"x": 150, "y": 20, "w": 86, "player": player, "items": labels,
			"on_cancel": func() -> void: Game.pop(ref.menu),
			"on_select": func(k: int) -> void:
				Game.pop(ref.menu)
				var label: String = labels[k]
				if label == "SUMMARY":
					var sref := {}
					var s := SummaryScreen.new(m, player, func() -> void: Game.pop(sref.s))
					sref.s = s
					Game.push(s)
				elif label == "SWITCH":
					st.swap_from = i
					screen.o.marked = i
					screen.o.prompt = "Move to where?"
				elif label == "ITEM":
					_item_menu(m, player)
				elif k >= 1 and k <= field.size():
					Field.use_field_move(player, m, field[k - 1], func() -> void:
						Game.pop(screen)
						on_close.call()),
		})
		ref.menu = menu
		Game.push(menu)
	Game.push(screen)

## GIVE / TAKE a held item from the party menu (READ and TAKE for a letter).
static func _item_menu(m: Dictionary, player: int) -> void:
	var gs: Dictionary = Game.gs
	var held: Variant = m.get("item", null)
	if Mail.is_mail(held):
		Game.ask("%s is holding a letter." % Creatures.display_name(m), ["READ", "TAKE", "CANCEL"], func(c: int) -> void:
			if c == 0:
				var mail: Variant = m.get("mail", null)
				Mail.read(mail if mail != null else {"item": held, "text": "", "from": "?"}, func() -> void: pass)
			elif c == 1:
				Mail.take(m, player), player)
		return
	Game.ask("%s is holding %s." % [Creatures.display_name(m), DB.item(held).name] if held != null else "%s isn't holding anything." % Creatures.display_name(m),
		["GIVE", "TAKE", "CANCEL"], func(c: int) -> void:
			if c == 0:
				open_bag({"player": player, "in_battle": false, "can_throw": false, "on_close": func() -> void: pass,
					"usable": func(id: String) -> bool: return can_hold(id),
					"on_pick": func(id: String, done: Callable) -> void:
						if Mail.is_mail(id):
							done.call()
							Mail.give(m, id, player, func() -> void: pass)
							return
						give_item(m, id, player)
						done.call()})
			elif c == 1:
				if held == null:
					Game.say(["%s isn't holding anything." % Creatures.display_name(m)], Callable(), player)
					return
				gs.bag[held] = gs.bag.get(held, 0) + 1
				m.item = null
				Game.say(["Received the %s from %s." % [DB.item(held).name, Creatures.display_name(m)]], Callable(), player), player)

## Whether an item can be held (anything but key items, TMs/HMs and decorations).
static func can_hold(id: String) -> bool:
	var k: String = DB.item(id).effect.kind
	return not (k in ["key", "tm", "deco"])

static func give_item(m: Dictionary, id: String, player: int) -> void:
	var gs: Dictionary = Game.gs
	var old: Variant = m.get("item", null)
	gs.bag[id] -= 1
	if old != null:
		gs.bag[old] = gs.bag.get(old, 0) + 1
	m.item = id
	var msg := "%s was given the %s to hold." % [Creatures.display_name(m), DB.item(id).name]
	if old != null:
		msg = "The %s was swapped for the %s." % [DB.item(old).name, DB.item(id).name]
	Game.say([msg], Callable(), player)

## Asks for one of a creature's moves. on_pick(index) is not called on cancel.
static func pick_move(m: Dictionary, player: int, title: String, on_pick: Callable) -> void:
	var items: Array = []
	for ms in m.moves:
		items.append({"label": DB.move(ms.id).name, "right": "%d/%d" % [ms.pp, ms.maxPp]})
	var ref := {}
	var menu := ListMenu.new({
		"x": 100, "y": 30, "w": 136, "player": player, "title": title, "items": items,
		"on_cancel": func() -> void: Game.pop(ref.menu),
		"on_select": func(i: int) -> void:
			Game.pop(ref.menu)
			on_pick.call(i),
	})
	ref.menu = menu
	Game.push(menu)

# ---------- bag ----------
const POCKETS := ["items", "balls", "berries", "tms", "key"]
const POCKET_NAMES := {"items": "ITEMS", "balls": "CAPTURE ORBS", "berries": "BERRIES", "tms": "TMs & HMs", "key": "KEY ITEMS"}
## Item kinds that can be used during a battle.
const BATTLE_KINDS := ["heal", "fullRestore", "revive", "cure", "pp", "xStat", "ball", "berry"]

static func pocket_of(id: String) -> String:
	var it: Dictionary = DB.item(id)
	if it.has("pocket"):
		return it.pocket
	match it.effect.kind:
		"ball": return "balls"
		"berry": return "berries"
		"tm": return "tms"
		"key": return "key"
	return "items"

## o keys: player (int), in_battle (bool), can_throw (bool), on_pick (Callable(item_id: String, done: Callable)), on_close (Callable()),
## usable (optional Callable(item_id) -> bool: items it returns false for are greyed out).
## The bag has pockets (LEFT/RIGHT switches between them), like Emerald's.
static func open_bag(o: Dictionary) -> void:
	var gs: Dictionary = Game.gs
	var st := {"pocket": o.get("pocket", 0)}
	var on_close: Callable = o.on_close
	var ids_in := func(pocket: String) -> Array:
		var out: Array = []
		for id in DB.ITEMS:
			if gs.bag.get(id, 0) > 0 and pocket_of(id) == pocket and DB.ITEMS[id].effect.kind != "deco":
				out.append(id)
		return out
	var ref := {}
	var bg := FnScene.new(func() -> void:
		Gfx.screen("bag", "#e8c878", "#a87838")
		Gfx.text("◀ %s ▶" % POCKET_NAMES[POCKETS[st.pocket]], 8, 5, {"color": "#ffffff", "size": 6})
		Gfx.text("$%d" % gs.money, Gfx.W - 8, 5, {"color": "#ffffff", "size": 6, "align": "right"})
		for k in POCKETS.size():
			Gfx.rect(10 + k * 9, 24, 6, 6, "#f8f0d0" if k == st.pocket else "#b89050")
		# The selected item's icon, in a little frame on the left like the handheld bag.
		if ref.has("menu") and st.has("ids") and ref.menu.sel < st.ids.size():
			Gfx.panel(14, 122, 32, 32)
			draw_item_icon(st.ids[ref.menu.sel], 18, 126)
		Game.player_tag(o.player, 100, 4))
	# Takes the bag's own scenes (list, pocket switcher, background) off the stack.
	var pop_bag := func() -> void:
		if ref.has("menu"):
			Game.pop(ref.menu)
			ref.erase("menu")
		if ref.has("sw"):
			Game.pop(ref.sw)
		Game.pop(bg)
	var close := func() -> void:
		pop_bag.call()
		on_close.call()
	var build := func(self_ref: Callable) -> void:
		var ids: Array = ids_in.call(POCKETS[st.pocket])
		st.ids = ids
		var items: Array = []
		for id in ids:
			var it: Dictionary = DB.item(id)
			var ok: bool = not (it.effect.kind == "ball" and not o.can_throw)
			if o.has("usable"):
				ok = ok and (o.usable as Callable).call(id)
			var right: String = "" if it.effect.kind == "tm" and it.effect.get("hm", false) else "x%d" % gs.bag[id]
			items.append({"label": it.name, "right": right, "disabled": not ok})
		items.append({"label": "CLOSE BAG"})
		var menu := ListMenu.new({
			"x": 60, "y": 20, "w": 176, "player": o.player, "max_visible": 7,
			"items": items,
			"footer": func(i: int) -> String: return DB.item(ids[i]).desc if i < ids.size() else "",
			"on_cancel": func() -> void: close.call(),
			"on_select": func(i: int) -> void:
				if i == ids.size():
					close.call()
					return
				(o.on_pick as Callable).call(ids[i], pop_bag),
		})
		ref.menu = menu
		Game.push(menu)
	# LEFT/RIGHT switch pockets: a tiny scene above the list that rebuilds it.
	var switcher := PocketSwitch.new(o.player, func(d: int) -> void:
		st.pocket = (st.pocket + d + POCKETS.size()) % POCKETS.size()
		Game.pop(ref.menu)
		Game.pop(ref.sw)
		build.call(build)
		Game.push(ref.sw))
	ref.sw = switcher
	Game.push(bg)
	build.call(build)
	Game.push(switcher)

## Watches LEFT/RIGHT over the bag's list (it passes every other button through to the list below it).
class PocketSwitch extends Scene:
	var _player: int
	var _cb: Callable
	func _init(player: int, cb: Callable) -> void:
		_player = player
		_cb = cb
		overlay = true
	func update(dt: float) -> void:
		var inp := Game.input.p(_player)
		if inp.pressed("left"):
			Audio.sfx("cursor")
			_cb.call(-1)
			return
		if inp.pressed("right"):
			Audio.sfx("cursor")
			_cb.call(1)
			return
		# Let the list under this scene handle everything else.
		var i := Game.stack.rfind(self)
		if i > 0 and Game.stack[i - 1] is ListMenu:
			Game.stack[i - 1].update(dt)
	func draw() -> void:
		pass

## Applies a healing/cure item outside battle. Returns a message or null if it had no effect.
static func use_item_on(gs: Dictionary, item_id: String, m: Dictionary) -> Variant:
	var it: Dictionary = DB.item(item_id)
	var eff: Dictionary = it.effect
	if m.get("egg", false):
		return null
	if eff.kind == "berry":
		var hold: Dictionary = eff.get("hold", {})
		if hold.get("kind", "") == "heal":
			eff = {"kind": "heal", "amount": hold.amount}
		elif hold.get("kind", "") == "flavorHeal":
			eff = {"kind": "heal", "amount": Creatures.max_hp(m) / 8}
		elif hold.get("kind", "") == "cure":
			eff = {"kind": "cure", "statuses": hold.statuses}
	if eff.kind == "heal" or eff.kind == "fullRestore":
		var mx: int = Creatures.max_hp(m)
		if m.hp <= 0 or (m.hp >= mx and (eff.kind == "heal" or m.status == null)):
			return null
		var before: int = m.hp
		m.hp = mini(mx, m.hp + int(eff.get("amount", 9999)))
		if eff.kind == "fullRestore":
			m.status = null
			m.sleepTurns = 0
		gs.bag[item_id] -= 1
		return "%s's HP was restored by %d point(s)." % [Creatures.display_name(m), m.hp - before]
	if eff.kind == "revive":
		if m.hp > 0:
			return null
		m.hp = Creatures.max_hp(m) if eff.get("full", false) else Creatures.max_hp(m) / 2
		gs.bag[item_id] -= 1
		return "%s was revived!" % Creatures.display_name(m)
	if eff.kind == "cure":
		if m.status == null or not (eff.statuses as Array).has(m.status) or m.hp <= 0:
			return null
		m.status = null
		m.sleepTurns = 0
		gs.bag[item_id] -= 1
		return "%s was cured!" % Creatures.display_name(m)
	if eff.kind == "vitamin":
		var k: String = eff.stat
		var total := 0
		for kk in DB.STAT_KEYS:
			total += int(m.evs[kk])
		if int(m.evs[k]) >= 100 or total >= Creatures.EV_TOTAL_CAP:
			return null
		var before_hp := Creatures.max_hp(m)
		m.evs[k] = mini(100, int(m.evs[k]) + 10)
		if k == "hp" and m.hp > 0:
			m.hp += Creatures.max_hp(m) - before_hp
		Creatures.add_friendship(m, 5 if int(m.friendship) < 100 else (3 if int(m.friendship) < 200 else 2))
		gs.bag[item_id] -= 1
		return "%s's %s rose." % [Creatures.display_name(m), {"hp": "HP", "atk": "Attack", "def": "Defense", "spa": "Sp. Atk", "spd": "Sp. Def", "spe": "Speed"}[k]]
	return null

## Uses a PP item on one move (or all, for Elixirs) or a PP Up. Returns a message or null.
static func use_pp_item(gs: Dictionary, item_id: String, m: Dictionary, idx: int) -> Variant:
	var eff: Dictionary = DB.item(item_id).effect
	if eff.kind == "ppUp":
		var ms: Dictionary = m.moves[idx]
		var base: int = DB.move(ms.id).pp
		var ups: int = ms.get("ups", 0)
		if ups >= 3 or base < 5:
			return null
		ms.ups = ups + 1
		ms.maxPp = base + (base / 5) * ms.ups
		ms.pp += base / 5
		gs.bag[item_id] -= 1
		return "%s's PP increased." % DB.move(ms.id).name
	var targets: Array = range(m.moves.size()) if eff.get("all", false) else [idx]
	var any := false
	for i in targets:
		var ms: Dictionary = m.moves[i]
		if ms.pp < ms.maxPp:
			any = true
			ms.pp = mini(int(ms.maxPp), int(ms.pp) + int(eff.amount))
	if not any:
		return null
	gs.bag[item_id] -= 1
	return "PP was restored."

static func open_bag_overworld(player: int, on_close: Callable) -> void:
	var gs: Dictionary = Game.gs
	open_bag({
		"player": player, "in_battle": false, "can_throw": false, "on_close": on_close,
		"on_pick": func(id: String, done: Callable) -> void:
			var it: Dictionary = DB.item(id)
			var kind: String = it.effect.kind
			var opts: Array = []
			if kind in ["heal", "fullRestore", "revive", "cure", "pp", "ppUp", "rareCandy", "vitamin", "evoStone", "tm", "repel",
					"escapeRope", "key", "berry"]:
				opts.append("USE")
			if can_hold(id):
				opts.append("GIVE")
			opts.append("TOSS" if kind not in ["key", "tm"] else "CANCEL")
			if opts[-1] != "CANCEL":
				opts.append("CANCEL")
			Game.ask("%s is selected." % it.name, opts, func(c: int) -> void:
				var pick: String = opts[c]
				if pick == "USE":
						use_from_bag(player, id, done, on_close)
				elif pick == "GIVE":
						var ps := PartyScreen.new({"player": player, "party": gs.players[player].party, "prompt": "Give to which creature?"})
						ps.o.on_cancel = func() -> void: Game.pop(ps)
						ps.o.on_select = func(i: int) -> void:
							var m: Dictionary = gs.players[player].party[i]
							if m.get("egg", false):
								Game.say(["An Egg can't hold items."], Callable(), player)
								return
							Game.pop(ps)
							give_item(m, id, player)
						Game.push(ps)
				elif pick == "TOSS":
						Game.ask("Throw away one %s?" % it.name, ["YES", "NO"], func(k: int) -> void:
							if k == 0:
								gs.bag[id] -= 1
								Game.say(["Threw away the %s." % it.name], Callable(), player), player), player),
	})

## USE from the field bag.
static func use_from_bag(player: int, id: String, done: Callable, on_close: Callable) -> void:
	var gs: Dictionary = Game.gs
	var it: Dictionary = DB.item(id)
	var eff: Dictionary = it.effect
	var close_all := func() -> void:
		done.call()
		on_close.call()
	match eff.kind:
		"repel":
			if gs.repel > 0:
				Game.say(["But the effects of a Repel lingered from earlier."], Callable(), player)
				return
			gs.bag[id] -= 1
			gs.repel = eff.steps
			Audio.sfx("confirm")
			Game.say(["%s used the %s." % [gs.players[player].name, it.name]], close_all, player)
			return
		"escapeRope":
			if not Field.can_escape(gs):
				Game.say(["%s! This isn't the time to use that!" % gs.players[player].name], Callable(), player)
				return
			gs.bag[id] -= 1
			close_all.call()
			Field.escape(player)
			return
		"key":
			Field.use_key_item(player, id, close_all)
			return
	# Everything else is used on a creature.
	var party: Array = gs.players[player].party
	var ps := PartyScreen.new({"player": player, "party": party, "prompt": "Use %s on?" % it.name})
	ps.o.on_cancel = func() -> void: Game.pop(ps)
	var finish := func(r: Variant) -> void:
		Audio.sfx("recover" if r != null else "error")
		Game.say([r if r != null else "It won't have any effect."], func() -> void:
			Game.pop(ps)
			if r != null:
				close_all.call(), player)
	ps.o.on_select = func(i: int) -> void:
		var m: Dictionary = party[i]
		match eff.kind:
			"pp", "ppUp":
				if eff.get("all", false):
					finish.call(use_pp_item(gs, id, m, 0))
				else:
					pick_move(m, player, "Which move?", func(k: int) -> void: finish.call(use_pp_item(gs, id, m, k)))
			"rareCandy":
				if m.level >= 100 or m.get("egg", false):
					finish.call(null)
					return
				gs.bag[id] -= 1
				Game.pop(ps)
				close_all.call()
				level_up_flow(m, player)
			"evoStone":
				var into: Variant = Creatures.pending_evolution(m, id)
				if into == null:
					finish.call(null)
					return
				gs.bag[id] -= 1
				Game.pop(ps)
				close_all.call()
				EvolutionScene.new(m, into, player, func() -> void: pass)
			"tm":
				var mv_id: String = eff.move
				if m.get("egg", false) or not Creatures.can_learn_tm(m, id):
					Game.say(["%s can't learn %s." % [Creatures.display_name(m), DB.move(mv_id).name]], Callable(), player)
					return
				if Creatures.knows(m, mv_id):
					Game.say(["%s already knows %s." % [Creatures.display_name(m), DB.move(mv_id).name]], Callable(), player)
					return
				Game.pop(ps)
				learn_move_flow(m, mv_id, player, func() -> void:
					# TMs are used up (HMs are not), as in Gen 3.
					if Creatures.knows(m, mv_id) and not eff.get("hm", false):
						gs.bag[id] -= 1
					close_all.call())
			_:
				finish.call(use_item_on(gs, id, m))
	Game.push(ps)

## Rare Candy: one level, with the usual messages, new moves and evolution.
static func level_up_flow(m: Dictionary, player: int, done: Callable = Callable()) -> void:
	var need: int = Creatures.exp_for_level(DB.species(m.species).growth, m.level + 1) - int(m.exp)
	var ups: Array = Creatures.gain_exp(m, maxi(1, need))
	var msgs: Array = ["%s grew to Lv. %d!" % [Creatures.display_name(m), m.level]]
	var pending: Array = []
	for up in ups:
		for mv in up.learned:
			msgs.append("%s learned %s!" % [Creatures.display_name(m), DB.move(mv).name])
		pending.append_array(up.pending)
	Audio.sfx("level_up")
	var after_learn := func() -> void:
		var into: Variant = Creatures.pending_evolution(m)
		if into != null:
			EvolutionScene.new(m, into, player, func() -> void:
				if done.is_valid():
					done.call())
		elif done.is_valid():
			done.call()
	var learn_next := func(self_ref: Callable) -> void:
		if pending.is_empty():
			after_learn.call()
			return
		learn_move_flow(m, pending.pop_front(), player, func() -> void: self_ref.call(self_ref))
	Game.say(msgs, func() -> void: learn_next.call(learn_next), player)

# ---------- shop ----------
static func badge_count(gs: Dictionary) -> int:
	var re := RegEx.create_from_string("^badge\\d$")
	var n := 0
	for f in gs.flags:
		if re.search(f) != null:
			n += 1
	return n

## Trail Mart stock: grows with badges.
static func mart_stock(badges: int) -> Array:
	var stock: Array = ["orb"]
	if badges >= 1: stock.append("greatOrb")
	if badges >= 3: stock.append("ultraOrb")
	stock.append("potion")
	if badges >= 1: stock.append("superPotion")
	if badges >= 4: stock.append("hyperPotion")
	if badges >= 2: stock.append("revive")
	stock.append_array(["antidote", "parlyzHeal", "awakening", "burnHeal"])
	if badges >= 3: stock.append("fullHeal")
	# Emerald's extra stock (Repels, Escape Ropes, special orbs...) by badge count, from data/features.json.
	for tier in DB.SHOPS.get("mart", {}):
		if int(tier) <= badges:
			for id in DB.SHOPS.mart[tier]:
				if not stock.has(id):
					stock.append(id)
	return stock

## fixed_stock: item ids for a counter with its own list (department store); empty = the Trail Mart's badge-based stock.
## BUY or SELL first, like the handheld games. Decorations go to the Secret Base collection instead of the bag.
static func open_shop(player: int, on_close: Callable, fixed_stock: Array = []) -> void:
	Game.ask("How may I serve you?", ["BUY", "SELL", "SEE YA!"], func(c: int) -> void:
		if c == 0:
			_buy_menu(player, func() -> void: open_shop(player, on_close, fixed_stock), fixed_stock)
		elif c == 1:
			_sell_menu(player, func() -> void: open_shop(player, on_close, fixed_stock))
		else:
			on_close.call(), player)

static func _buy_menu(player: int, on_close: Callable, fixed_stock: Array) -> void:
	var gs: Dictionary = Game.gs
	var stock: Array = fixed_stock if not fixed_stock.is_empty() else mart_stock(badge_count(gs))
	var header := FnScene.new(func() -> void:
		Gfx.panel(4, 4, 90, 22)
		Gfx.text("$%d" % gs.money, 12, 12, {"size": 6}), true)
	var items: Array = []
	for id in stock:
		var owned_deco: bool = DB.item(id).effect.kind == "deco" and gs.decor.has(id)
		items.append({"label": DB.item(id).name, "right": "OWNED" if owned_deco else "$%d" % DB.item(id).price, "disabled": owned_deco})
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
				Audio.sfx("error")
				Game.say(["You don't have enough money."], Callable(), player)
				return
			var deco: bool = it.effect.kind == "deco"
			var max_n: int = 1 if deco or it.effect.kind == "tm" and it.effect.get("hm", false) else mini(99, gs.money / maxi(1, it.price))
			_ask_count(player, "%s? How many?" % it.name, max_n, it.price, func(n: int) -> void:
				Game.ask("That will be $%d for %d. OK?" % [it.price * n, n], ["YES", "NO"], func(k: int) -> void:
					if k != 0:
						return
					gs.money -= it.price * n
					if deco:
						gs.decor.append(it.id)
						Game.pop(ref.menu)
						Game.pop(header)
						_buy_menu(player, on_close, fixed_stock)
					else:
						gs.bag[it.id] = gs.bag.get(it.id, 0) + n
						# Emerald's bonus: a Premier Orb with every 10 Capture Orbs.
						if it.id == "orb" and n >= 10 and DB.ITEMS.has("premierOrb"):
							gs.bag.premierOrb = gs.bag.get("premierOrb", 0) + 1
							Game.say(["Here you go! Thank you.", "I'll throw in a Premier Orb, too."], Callable(), player)
							Audio.sfx("buy")
							return
					Audio.sfx("buy")
					Game.say(["Here you go! Thank you."], Callable(), player), player)),
	})
	ref.menu = menu
	Game.push(header)
	Game.push(menu)

## Picks a quantity 1..max_n with UP/DOWN (LEFT/RIGHT by 10).
static func _ask_count(player: int, title: String, max_n: int, price: int, on_pick: Callable) -> void:
	if max_n <= 1:
		on_pick.call(1)
		return
	var st := {"n": 1}
	var sc := CountScene.new(player, max_n, func(n: int) -> void:
		if n > 0:
			on_pick.call(n), func() -> String: return "%s  x%02d  $%d" % [title, sc_n(st), price * sc_n(st)], st)
	Game.push(sc)

static func sc_n(st: Dictionary) -> int:
	return st.n

class CountScene extends Scene:
	var _player: int
	var _max: int
	var _cb: Callable
	var _label: Callable
	var _st: Dictionary
	func _init(player: int, max_n: int, cb: Callable, label: Callable, st: Dictionary) -> void:
		overlay = true
		_player = player
		_max = max_n
		_cb = cb
		_label = label
		_st = st
	func update(_dt: float) -> void:
		var inp := Game.input.p(_player)
		var n: int = _st.n
		if inp.pressed("up"): n += 1
		if inp.pressed("down"): n -= 1
		if inp.pressed("right"): n += 10
		if inp.pressed("left"): n -= 10
		n = clampi(n, 1, _max) if n >= 1 else (_max if inp.pressed("down") else 1)
		if n != _st.n:
			Audio.sfx("cursor")
		_st.n = n
		if inp.pressed("a"):
			Audio.sfx("confirm")
			Game.pop(self)
			_cb.call(n)
		elif inp.pressed("b"):
			Audio.sfx("cancel")
			Game.pop(self)
			_cb.call(0)
	func draw() -> void:
		Gfx.panel(2, 128, Gfx.W - 4, 30)
		Gfx.text(_label.call(), 10, 136, {"size": 6})
		Gfx.text("▲▼ amount   A: OK   B: back", 10, 147, {"size": 5, "color": "#606870"})

static func _sell_menu(player: int, on_close: Callable) -> void:
	var gs: Dictionary = Game.gs
	open_bag({"player": player, "in_battle": false, "can_throw": true, "on_close": on_close,
		"usable": func(id: String) -> bool: return DB.item(id).price > 0 and DB.item(id).effect.kind not in ["key", "tm"] or (DB.item(id).effect.kind == "tm" and not DB.item(id).effect.get("hm", false)),
		"on_pick": func(id: String, done: Callable) -> void:
			var it: Dictionary = DB.item(id)
			var each: int = it.price / 2
			_ask_count(player, "Sell %s?" % it.name, gs.bag[id], each, func(n: int) -> void:
				Game.ask("I can pay $%d. Would that be OK?" % (each * n), ["YES", "NO"], func(k: int) -> void:
					if k != 0:
						return
					gs.bag[id] -= n
					gs.money += each * n
					Audio.sfx("buy")
					Game.say(["Turned over the %s and received $%d." % [it.name, each * n]], func() -> void:
						done.call()
						_sell_menu(player, on_close), player), player))})

## Battle Point exchange (Battle Tower): items priced in BP.
static func open_bp_shop(player: int, on_close: Callable) -> void:
	var gs: Dictionary = Game.gs
	var stock: Array = DB.SHOPS.get("bp", [])
	var items: Array = []
	for row in stock:
		items.append({"label": DB.item(row[0]).name, "right": "%d BP" % row[1]})
	items.append({"label": "DONE"})
	var header := FnScene.new(func() -> void:
		Gfx.panel(4, 4, 90, 22)
		Gfx.text("%d BP" % gs.bp, 12, 12, {"size": 6}), true)
	var ref := {}
	var menu := ListMenu.new({
		"x": 100, "y": 4, "w": 136, "player": player, "max_visible": 7, "items": items,
		"footer": func(i: int) -> String: return DB.item(stock[i][0]).desc if i < stock.size() else "",
		"on_cancel": func() -> void:
			Game.pop(ref.menu)
			Game.pop(header)
			on_close.call(),
		"on_select": func(i: int) -> void:
			if i == stock.size():
				Game.pop(ref.menu)
				Game.pop(header)
				on_close.call()
				return
			var row: Array = stock[i]
			if gs.bp < int(row[1]):
				Audio.sfx("error")
				Game.say(["You don't have enough Battle Points."], Callable(), player)
				return
			gs.bp -= int(row[1])
			gs.bag[row[0]] = gs.bag.get(row[0], 0) + 1
			Audio.sfx("buy")
			Game.say(["Here's your %s!" % DB.item(row[0]).name], Callable(), player),
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
