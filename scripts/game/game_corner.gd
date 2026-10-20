class_name GameCorner
## The Game Corner in Cinder City: buy coins (you need the Coin Case), play the slot machines, and trade coins for
## prizes (TMs, held items and three creatures you can't find in the wild).

const MAX_COINS := 9999
const BET := 3

static func _has_case() -> bool:
	return Game.gs.bag.get("coinCase", 0) > 0

static func coins_counter(text: Array) -> void:
	var gs: Dictionary = Game.gs
	if not _has_case():
		Game.say(text + ["You don't have a Coin Case. Ask around the Game Corner!"])
		return
	Game.say(text, func() -> void:
		Game.ask("You have %d coins. How many would you like?" % gs.coins, ["50 for $1000", "500 for $10000", "NO THANKS"], func(c: int) -> void:
			if c > 1:
				return
			var n: int = [50, 500][c]
			var cost: int = [1000, 10000][c]
			if gs.money < cost:
				Game.say(["You don't have enough money."])
				return
			if gs.coins + n > MAX_COINS:
				Game.say(["Your Coin Case can't hold any more coins."])
				return
			gs.money -= cost
			gs.coins += n
			Audio.sfx("buy")
			Game.say(["Here are your %d coins!" % n])))

static func prizes(text: Array) -> void:
	var gs: Dictionary = Game.gs
	if not _has_case():
		Game.say(text + ["You need a Coin Case to trade for prizes."])
		return
	var rows: Array = []
	for r in DB.PRIZES.get("items", []):
		if DB.ITEMS.has(r[0]):
			rows.append({"item": r[0], "cost": int(r[1])})
	for r in DB.PRIZES.get("creatures", []):
		rows.append({"species": r[0], "level": int(r[1]), "cost": int(r[2])})
	var items: Array = []
	for r in rows:
		var label: String = DB.item(r.item).name if r.has("item") else "%s Lv%d" % [DB.species(r.species).name, r.level]
		items.append({"label": label, "right": "%d" % r.cost})
	items.append({"label": "DONE"})
	var header := Menus.FnScene.new(func() -> void:
		Gfx.panel(4, 4, 90, 22)
		Gfx.text("COINS %d" % gs.coins, 12, 12, {"size": 6}), true)
	var ref := {}
	var close := func() -> void:
		Game.pop(ref.menu)
		Game.pop(header)
	var menu := ListMenu.new({
		"x": 100, "y": 4, "w": 136, "player": 0, "max_visible": 8, "items": items,
		"footer": func(i: int) -> String:
			if i >= rows.size():
				return ""
			return DB.item(rows[i].item).desc if rows[i].has("item") else "A creature that doesn't live in the wild here.",
		"on_cancel": close,
		"on_select": func(i: int) -> void:
			if i >= rows.size():
				close.call()
				return
			var r: Dictionary = rows[i]
			if gs.coins < r.cost:
				Audio.sfx("error")
				Game.say(["You don't have enough coins."])
				return
			if r.has("species"):
				gs.coins -= r.cost
				var mon := Creatures.create_creature(r.species, r.level, {"owner": 0, "otId": gs.players[0].otId})
				var where := GameState.receive_creature(gs, mon, 0)
				if not gs.seen.has(r.species):
					gs.seen.append(r.species)
				Audio.sfx("item")
				Game.say(["You received %s!" % DB.species(r.species).name] + (["It was sent to storage."] if where == "box" else []))
				return
			gs.coins -= r.cost
			gs.bag[r.item] = gs.bag.get(r.item, 0) + 1
			Audio.sfx("buy")
			Game.say(["Here's your %s!" % DB.item(r.item).name]),
	})
	ref.menu = menu
	Game.push(header)
	Game.push(menu)

static func slots(_o: OverworldScene) -> void:
	var gs: Dictionary = Game.gs
	if not _has_case():
		Game.say(["It's a slot machine. You need a Coin Case to play."])
		return
	if gs.coins < BET:
		Game.say(["It's a slot machine. You need at least %d coins to play." % BET])
		return
	Game.ask("It's a slot machine. Play for %d coins a spin?" % BET, ["YES", "NO"], func(c: int) -> void:
		if c != 0:
			return
		var ref := {}
		var s := SlotsScene.new(func() -> void: Game.pop(ref.s))
		ref.s = s
		Game.push(s))

## The slot machine. A starts a spin and then stops the reels one at a time; B leaves between spins.
class SlotsScene extends Scene:
	const SYMBOLS := ["7", "BAR", "ORB", "LEAF", "BERRY"]
	## Each reel's strip of 21 symbols (indices into SYMBOLS).
	const REELS := [
		[0, 4, 2, 3, 4, 1, 2, 4, 3, 2, 4, 1, 3, 4, 2, 3, 4, 2, 3, 4, 1],
		[0, 2, 3, 4, 1, 3, 2, 4, 3, 1, 2, 3, 4, 2, 3, 0, 2, 4, 3, 2, 3],
		[0, 3, 2, 1, 3, 2, 4, 3, 2, 1, 3, 2, 3, 4, 2, 3, 2, 0, 3, 2, 3],
	]
	var _on_close: Callable
	var _pos := [0.0, 7.0, 14.0]
	var _spinning := [false, false, false]
	var _state := "ready"
	var _msg := "A: spin (3 coins)   B: quit"
	var _win := 0
	var _t := 0.0

	func _init(on_close: Callable) -> void:
		_on_close = on_close

	func update(dt: float) -> void:
		_t += dt
		var gs: Dictionary = Game.gs
		for i in 3:
			if _spinning[i]:
				_pos[i] = fposmod(_pos[i] + dt * 14.0, 21.0)
		var inp := Game.input.p(0)
		if _state == "ready":
			if inp.pressed("a"):
				if gs.coins < GameCorner.BET:
					_msg = "Not enough coins!"
					Audio.sfx("error")
					return
				gs.coins -= GameCorner.BET
				_spinning = [true, true, true]
				_state = "spin"
				_win = 0
				_msg = "A: stop a reel"
				Audio.sfx("confirm")
			elif inp.pressed("b"):
				Audio.sfx("cancel")
				_on_close.call()
		elif _state == "spin" and inp.pressed("a"):
			var i: int = _spinning.find(true)
			_spinning[i] = false
			_pos[i] = float(roundi(_pos[i]) % 21)
			Audio.sfx("bump")
			if not _spinning.has(true):
				_payout()

	func _symbol(reel: int, offset: int) -> int:
		return REELS[reel][(int(_pos[reel]) + offset + 21) % 21]

	func _payout() -> void:
		var gs: Dictionary = Game.gs
		var a := _symbol(0, 0)
		var b := _symbol(1, 0)
		var c := _symbol(2, 0)
		var win := 0
		if a == b and b == c:
			win = [300, 50, 15, 10, 8][a]
		elif a == 4 and b == 4:
			win = 6
		elif a == 4:
			win = 2
		win = mini(win, GameCorner.MAX_COINS - gs.coins)
		gs.coins += win
		_win = win
		_state = "ready"
		if win >= 50:
			Audio.sfx("badge")
		elif win > 0:
			Audio.sfx("item")
		_msg = ("You won %d coins!   " % win if win > 0 else "No luck...   ") + "A: spin  B: quit"

	func _draw_symbol(sym: int, cx: float, cy: float) -> void:
		match sym:
			0:
				Gfx.text("7", cx, cy - 7, {"size": 14, "color": "#e03030", "align": "center"})
			1:
				Gfx.rect(cx - 12, cy - 5, 24, 10, "#303030")
				Gfx.text("BAR", cx, cy - 3, {"size": 5, "color": "#f8e040", "align": "center", "shadow": null})
			2:
				Gfx.ellipse(cx, cy, 8, 8, "#303030")
				Gfx.ellipse(cx, cy, 7, 7, "#f8f8f8")
				Gfx.rect(cx - 7, cy - 7, 14, 7, "#e04848")
				Gfx.rect(cx - 7, cy - 1, 14, 2, "#303030")
				Gfx.ellipse(cx, cy, 2, 2, "#f8f8f8")
			3:
				Gfx.ellipse(cx, cy, 9, 5, "#48a848")
				Gfx.rect(cx - 8, cy, 16, 1, "#2c702c")
			4:
				Gfx.ellipse(cx - 3, cy + 1, 5, 5, "#8848c8")
				Gfx.ellipse(cx + 3, cy + 1, 5, 5, "#a060e0")
				Gfx.rect(cx - 1, cy - 8, 2, 5, "#48a848")

	func draw() -> void:
		var gs: Dictionary = Game.gs
		Gfx.rect(0, 0, Gfx.W, Gfx.H, "#601830")
		Gfx.rect(20, 10, 200, 114, "#c89030")
		Gfx.rect(24, 14, 192, 106, "#f0c848")
		Gfx.text("SLOTS", Gfx.W / 2.0, 18, {"size": 7, "align": "center", "color": "#a02020"})
		for r in 3:
			var x := 40 + r * 56
			Gfx.rect(x, 32, 48, 78, "#f8f8f0")
			var frac: float = _pos[r] - floorf(_pos[r])
			for k in range(-2, 3):
				var cy: float = 71 + (k - frac) * 24
				if cy < 34 or cy > 108:
					continue
				_draw_symbol(_symbol(r, k), x + 24, cy)
			Gfx.rect(x, 32, 48, 6, Color(0, 0, 0, 0.15))
			Gfx.rect(x, 104, 48, 6, Color(0, 0, 0, 0.15))
		Gfx.rect(36, 70, 168, 1, Color(0.9, 0.1, 0.1, 0.6))
		Gfx.panel(4, 128, Gfx.W - 8, 28)
		Gfx.text("COINS %d" % gs.coins, 12, 134, {"size": 6})
		Gfx.text(_msg, 12, 145, {"size": 5, "color": "#404040"})
		Gfx.text("777:300 BAR:50 ORB:15 LEAF:10", Gfx.W - 12, 134, {"size": 5, "align": "right", "color": "#806020"})
