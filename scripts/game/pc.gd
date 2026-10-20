class_name Pc
## The rest of the Rest Lodge PC, beside creature storage: item storage (deposit and withdraw), the mailbox
## (letters taken off creatures) and the Hall of Fame record.

const MENU := ["ITEM STORAGE", "MAILBOX", "HALL OF FAME"]

static func open(label: String, on_close: Callable) -> void:
	match label:
		"ITEM STORAGE":
			_items(on_close)
		"MAILBOX":
			_mailbox(on_close)
		"HALL OF FAME":
			var gs: Dictionary = Game.gs
			if gs.hallOfFame.is_empty():
				Game.say(["There's no Hall of Fame record yet. Become the Champion to make one!"], on_close)
				return
			var ref := {}
			var s := HallOfFameScene.new(gs.hallOfFame, func() -> void:
				Game.pop(ref.s)
				on_close.call())
			ref.s = s
			Game.push(s)

# ---------- items ----------
static func _items(on_close: Callable) -> void:
	Game.ask("What would you like to do?", ["WITHDRAW", "DEPOSIT", "TOSS", "CANCEL"], func(c: int) -> void:
		if c == 0:
			_withdraw(on_close, false)
		elif c == 1:
			_deposit(on_close)
		elif c == 2:
			_withdraw(on_close, true)
		else:
			on_close.call())

static func _withdraw(on_close: Callable, toss: bool) -> void:
	var gs: Dictionary = Game.gs
	var ids: Array = []
	for id in gs.pcItems:
		if int(gs.pcItems[id]) > 0 and DB.ITEMS.has(id):
			ids.append(id)
	if ids.is_empty():
		Game.say(["There are no items stored in the PC."], func() -> void: _items(on_close))
		return
	var items: Array = []
	for id in ids:
		items.append({"label": DB.item(id).name, "right": "x%d" % gs.pcItems[id]})
	items.append({"label": "CANCEL"})
	var ref := {}
	var menu := ListMenu.new({
		"x": 92, "y": 4, "w": 144, "player": 0, "title": "Toss which?" if toss else "Withdraw which?", "items": items,
		"max_visible": 7,
		"footer": func(i: int) -> String: return DB.item(ids[i]).desc if i < ids.size() else "",
		"on_cancel": func() -> void:
			Game.pop(ref.menu)
			_items(on_close),
		"on_select": func(i: int) -> void:
			if i >= ids.size():
				Game.pop(ref.menu)
				_items(on_close)
				return
			var id: String = ids[i]
			Menus._ask_count(0, DB.item(id).name, int(gs.pcItems[id]), 0, func(n: int) -> void:
				Game.pop(ref.menu)
				gs.pcItems[id] -= n
				if int(gs.pcItems[id]) <= 0:
					gs.pcItems.erase(id)
				var line := "Threw away %d %s." % [n, DB.item(id).name]
				if not toss:
					gs.bag[id] = gs.bag.get(id, 0) + n
					line = "Withdrew %d %s." % [n, DB.item(id).name]
				Audio.sfx("confirm")
				Game.say([line], func() -> void: _withdraw(on_close, toss))),
	})
	ref.menu = menu
	Game.push(menu)

static func _deposit(on_close: Callable) -> void:
	var gs: Dictionary = Game.gs
	Menus.open_bag({"player": 0, "in_battle": false, "can_throw": false,
		"on_close": func() -> void: _items(on_close),
		"usable": func(id: String) -> bool: return DB.item(id).effect.kind != "key",
		"on_pick": func(id: String, done: Callable) -> void:
			Menus._ask_count(0, DB.item(id).name, int(gs.bag.get(id, 0)), 0, func(n: int) -> void:
				gs.bag[id] -= n
				gs.pcItems[id] = int(gs.pcItems.get(id, 0)) + n
				Audio.sfx("confirm")
				done.call()
				Game.say(["Stored %d %s in the PC." % [n, DB.item(id).name]], func() -> void: _deposit(on_close)))})

# ---------- mailbox ----------
static func _mailbox(on_close: Callable) -> void:
	var gs: Dictionary = Game.gs
	if gs.mailbox.is_empty():
		Game.say(["There's no mail here."], on_close)
		return
	var items: Array = []
	for m in gs.mailbox:
		items.append({"label": "%s's %s" % [m.get("from", "?"), DB.item(m.item).name if DB.ITEMS.has(m.item) else "Mail"]})
	items.append({"label": "CANCEL"})
	var ref := {}
	var menu := ListMenu.new({
		"x": 64, "y": 4, "w": 172, "player": 0, "title": "Mailbox", "items": items, "max_visible": 7,
		"on_cancel": func() -> void:
			Game.pop(ref.menu)
			on_close.call(),
		"on_select": func(i: int) -> void:
			Game.pop(ref.menu)
			if i >= gs.mailbox.size():
				on_close.call()
				return
			var mail: Dictionary = gs.mailbox[i]
			Game.ask("What would you like to do with this letter?", ["READ", "MOVE TO BAG", "DELETE", "CANCEL"], func(c: int) -> void:
				if c == 0:
					Mail.read(mail, func() -> void: _mailbox(on_close))
				elif c == 1:
					gs.mailbox.erase(mail)
					gs.bag[mail.item] = gs.bag.get(mail.item, 0) + 1
					Game.say(["The letter was erased and the %s went back in the BAG." % DB.item(mail.item).name], func() -> void: _mailbox(on_close))
				elif c == 2:
					gs.mailbox.erase(mail)
					Game.say(["The letter was deleted."], func() -> void: _mailbox(on_close))
				else:
					_mailbox(on_close)),
	})
	ref.menu = menu
	Game.push(menu)
