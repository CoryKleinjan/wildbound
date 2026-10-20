class_name MatchCall
## Match Call on the Navi Gear: trainers you beat register with you, call now and then to chat, and call when
## they want a rematch. You can call them back from the Navi Gear too.

const CHATTER := [
	"I've been training every day since our battle. My creatures are getting tougher!",
	"I saw a creature I'd never seen before in the tall grass today. I wonder what it was...",
	"Have you tried growing berries? Mine grew huge after I watered them!",
	"Did you know creatures get friendlier if you walk with them a lot?",
	"I lost to a Swimmer yesterday. Water types are no joke!",
	"I heard there's an island that only appears on certain days. Have you seen it?",
	"My creature learned a new move! I can't wait to show you.",
	"Someone told me the Game Corner's slot machines pay out big sometimes...",
]

static var _index: Dictionary = {}

## {trainer, map} for a trainer id.
static func lookup(id: String) -> Variant:
	if _index.is_empty():
		for mid in DB.MAPS:
			for t in DB.MAPS[mid].get("trainers", []):
				_index[t.id] = {"trainer": t, "map": mid}
	return _index.get(id, null)

## Trainers who can register: the same ones who ask for rematches.
static func can_register(t: Dictionary) -> bool:
	var id := str(t.id)
	return not (t.get("champion", false) or t.get("leaveAfter", false) or id.begins_with("elite") or id.begins_with("order_")
		or id.contains("rival") or id.begins_with("pyr_") or t.get("badge"))

## After beating a trainer: with a Navi Gear, they register you (about half of them ask).
static func after_win(gs: Dictionary, t: Dictionary, msgs: Array) -> void:
	if gs.bag.get("naviGear", 0) <= 0 or gs.matchCall.has(t.id) or not can_register(t) or lookup(t.id) == null:
		return
	if absi(hash(t.id)) % 2 == 1:
		return
	gs.matchCall.append(t.id)
	msgs.append("%s registered you in their Match Call!" % t.name)

static func queue_ready(gs: Dictionary, id: String) -> void:
	if gs.matchCall.has(id) and not gs.calls.has(id):
		gs.calls.append(id)

## Called after each step. True if a call started.
static func on_step(gs: Dictionary) -> bool:
	if gs.bag.get("naviGear", 0) <= 0 or gs.matchCall.is_empty():
		return false
	if gs.calls.is_empty() and gs.steps % 500 == 250 and Rng.global_rng.int_below(3) == 0:
		gs.calls.append("chat:" + str(gs.matchCall[Rng.global_rng.int_below(gs.matchCall.size())]))
	if gs.calls.is_empty() or gs.steps % 16 != 0:
		return false
	var c: String = gs.calls.pop_front()
	var chat := c.begins_with("chat:")
	var id := c.substr(5) if chat else c
	var info: Variant = lookup(id)
	if info == null:
		return false
	Audio.sfx("spotted")
	Game.say(["Beep beep! Incoming Match Call from %s!" % info.trainer.name] + _lines(gs, info, chat))
	return true

static func _lines(gs: Dictionary, info: Dictionary, chat: bool) -> Array:
	var t: Dictionary = info.trainer
	var where: String = DB.MAPS[info.map].name
	if not chat and Field.rematch_ready(gs, t):
		return ["%s: Hey, it's me! I've been training hard. Come find me on %s for a rematch!" % [t.name, where]]
	var line: String = CHATTER[absi(hash(t.id + str(Options.today()))) % CHATTER.size()]
	return ["%s: %s" % [t.name, line]]

static func open(player: int, on_close: Callable) -> void:
	var gs: Dictionary = Game.gs
	if gs.matchCall.is_empty():
		Game.say(["Nobody is registered yet. Some trainers register you after a battle."], on_close, player)
		return
	var ids: Array = gs.matchCall.filter(func(id: String) -> bool: return lookup(id) != null)
	var items: Array = []
	for id in ids:
		var info: Dictionary = lookup(id)
		items.append({"label": info.trainer.name, "right": "!" if Field.rematch_ready(gs, info.trainer) else ""})
	items.append({"label": "CANCEL"})
	var ref := {}
	var menu := ListMenu.new({
		"x": 76, "y": 4, "w": 160, "player": player, "title": "Match Call", "items": items, "max_visible": 7,
		"footer": func(i: int) -> String: return DB.MAPS[lookup(ids[i]).map].name if i < ids.size() else "",
		"on_cancel": func() -> void:
			Game.pop(ref.menu)
			on_close.call(),
		"on_select": func(i: int) -> void:
			if i >= ids.size():
				Game.pop(ref.menu)
				on_close.call()
				return
			var info: Dictionary = lookup(ids[i])
			Game.say(["Calling %s..." % info.trainer.name] + _lines(gs, info, false), Callable(), player),
	})
	ref.menu = menu
	Game.push(menu)
