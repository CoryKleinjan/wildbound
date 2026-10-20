class_name Mail
## Mail: give a Mail item to a creature and write a short letter with Easy Chat words. The creature carries it
## (through trades too). Taking it off sends the letter to the PC mailbox. A creature's mail is {item, text, from}.

const WORDS := [
	"HELLO", "THANKS", "GOOD LUCK", "LET'S", "TRADE", "BATTLE", "TOGETHER", "AGAIN", "SOON", "TODAY", "TOMORROW",
	"FRIEND", "RIVAL", "CHAMPION", "CREATURE", "BERRY", "CONTEST", "TOWER", "ADVENTURE", "JOURNEY", "TOWN", "ROUTE",
	"I", "YOU", "WE", "MY", "YOUR", "IS", "ARE", "WILL", "WIN", "LOSE", "LOVE", "LIKE", "TRAIN", "TRAINER", "STRONG",
	"COOL", "CUTE", "AWESOME", "GREAT", "FUN", "BEST", "HAPPY", "WOW", "OK", "YES", "NO", "PLEASE", "!", "?", "...",
]
const MAX_WORDS := 6
const DESIGNS := {
	"orangeMail": ["#f8b060", "#f8e0c0"], "harborMail": ["#5888c8", "#d8e8f8"], "glitterMail": ["#c8a0e8", "#f8f0ff"],
	"mechMail": ["#8890a0", "#e0e4e8"], "woodMail": ["#a87848", "#f0e0c8"], "waveMail": ["#48a8c8", "#d8f4f8"],
}

static func is_mail(id: Variant) -> bool:
	return id != null and DB.ITEMS.has(id) and DB.item(id).effect.kind == "mail"

## Writes a letter; on_done(text) with "" when cancelled.
static func compose(player: int, on_done: Callable, words: Array = []) -> void:
	var items: Array = WORDS.duplicate()
	items.append_array(["DELETE", "DONE", "CANCEL"])
	var ref := {}
	var preview := " ".join(words) if not words.is_empty() else "(pick up to %d words)" % MAX_WORDS
	var menu := ListMenu.new({
		"x": 120, "y": 4, "w": 116, "player": player, "items": items, "max_visible": 8,
		"title": "%d/%d words" % [words.size(), MAX_WORDS],
		"footer": func(_i: int) -> String: return preview,
		"on_cancel": func() -> void:
			Game.pop(ref.menu)
			on_done.call(""),
		"on_select": func(i: int) -> void:
			Game.pop(ref.menu)
			var label: String = items[i]
			if label == "CANCEL":
				on_done.call("")
			elif label == "DONE":
				on_done.call(" ".join(words))
			elif label == "DELETE":
				compose(player, on_done, words.slice(0, maxi(0, words.size() - 1)))
			elif words.size() >= MAX_WORDS:
				Game.say(["The letter is full. Choose DONE."], func() -> void: compose(player, on_done, words), player)
			else:
				compose(player, on_done, words + [label]),
	})
	ref.menu = menu
	Game.push(menu)

## Gives a Mail item to a creature after writing the letter.
static func give(m: Dictionary, id: String, player: int, done: Callable) -> void:
	var gs: Dictionary = Game.gs
	compose(player, func(text: String) -> void:
		if text == "":
			done.call()
			return
		gs.bag[id] -= 1
		var old: Variant = m.get("item", null)
		if old != null:
			gs.bag[old] = gs.bag.get(old, 0) + 1
		m.item = id
		m.mail = {"item": id, "text": text, "from": gs.players[player].name}
		Game.say(["%s was given the %s to hold." % [Creatures.display_name(m), DB.item(id).name]], done, player))

## Takes the letter off a creature and files it in the PC mailbox.
static func take(m: Dictionary, player: int) -> void:
	var gs: Dictionary = Game.gs
	Game.ask("Send the letter to your PC mailbox?", ["YES", "NO"], func(c: int) -> void:
		if c != 0:
			return
		if gs.mailbox.size() >= 16:
			Game.say(["The mailbox is full."], Callable(), player)
			return
		var mail: Variant = m.get("mail", null)
		if mail == null:
			mail = {"item": m.item, "text": "", "from": gs.players[player].name}
		gs.mailbox.append(mail)
		m.item = null
		m.mail = null
		Game.say(["The letter was sent to the PC mailbox."], Callable(), player), player)

static func read(mail: Dictionary, on_close: Callable) -> void:
	var ref := {}
	var s := MailScene.new(mail, func() -> void:
		Game.pop(ref.s)
		on_close.call())
	ref.s = s
	Game.push(s)

class MailScene extends Scene:
	var _mail: Dictionary
	var _on_close: Callable
	func _init(mail: Dictionary, on_close: Callable) -> void:
		_mail = mail
		_on_close = on_close
	func update(_dt: float) -> void:
		if Game.input.any("a") or Game.input.any("b"):
			Audio.sfx("cancel")
			_on_close.call()
	func draw() -> void:
		var paper := ArtAssets.texture("screens/mail_" + str(_mail.item))
		if paper != null:
			Gfx.image(paper, 0, 0)
		else:
			var d: Array = DESIGNS.get(_mail.item, ["#c0c0c0", "#f8f8f8"])
			Gfx.rect(0, 0, Gfx.W, Gfx.H, d[0])
			for i in 12:
				Gfx.ellipse(fposmod(i * 47.0, Gfx.W), fposmod(i * 31.0, Gfx.H), 6, 6, Gfx.shade(d[0], 1.15))
			Gfx.rect(20, 20, Gfx.W - 40, Gfx.H - 40, d[1])
		Gfx.text(DB.item(_mail.item).name if DB.ITEMS.has(_mail.item) else "Mail", 28, 26, {"size": 5, "color": "#808080"})
		var lines := Gfx.wrap(str(_mail.text) if str(_mail.text) != "" else "(blank)", Gfx.W - 64, 7)
		for i in lines.size():
			Gfx.text(lines[i], 32, 46 + i * 14, {"size": 7})
		Gfx.text("From %s" % _mail.get("from", "?"), Gfx.W - 30, Gfx.H - 34, {"size": 6, "align": "right"})
