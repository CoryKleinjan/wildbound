class_name Trick
## The Trick House on Route 7: the Trick Master hides behind a different piece of furniture each visit. Find him
## and he opens his next puzzle room (Cut, Rock Smash, then Strength), each needing more badges. Reaching the stairs
## at the end of a room leads to him and his prize.

static func on_enter(o: OverworldScene) -> void:
	var gs: Dictionary = Game.gs
	var spots: Array = o.map.get("hideSpots", [])
	o.field.trickSpot = spots[Rng.global_rng.int_below(spots.size())] if not spots.is_empty() else ""
	if int(gs.trick.level) == 0 and not gs.flags.get("trick_intro", false):
		gs.flags.trick_intro = true
		Game.say(["It's the Trick House! Somebody is watching you...", "Search the room to find where they're hiding!"])

## A pressed on a tile in the Trick House. True if it was his hiding place.
static func interact(o: OverworldScene, k: String) -> bool:
	if k != o.field.get("trickSpot", ""):
		return false
	var gs: Dictionary = Game.gs
	var level := int(gs.trick.level)
	var lines := ["Hah! You found me! I am the Trick Master!"]
	o.field.trickSpot = ""
	if level >= DB.TRICK.badges.size():
		Game.say(lines + ["You've beaten every one of my tricks... for now! I'll think up new ones someday."])
		return true
	var need: int = DB.TRICK.badges[level]
	if OverworldScene.badge_count(gs) < need:
		Game.say(lines + ["My next trick needs a trainer with at least %d badges. Come back when you have them!" % need])
		return true
	Game.say(lines, func() -> void:
		Game.ask("Behind that scroll is puzzle room %d. Are you ready to take it on?" % (level + 1), ["YES", "NO"], func(c: int) -> void:
			if c != 0:
				Game.say(["I'll be hiding when you come back!"])
				return
			Field._warp(o, "trickpuzzle%d" % (level + 1), 7, 11, "up", false)))
	return true

## Reached the stairs at the end of a puzzle room.
static func solved(level: int) -> void:
	var gs: Dictionary = Game.gs
	gs.trick.level = maxi(int(gs.trick.level), level)

## The Trick Master in the reward room.
static func prize(text: Array) -> void:
	var gs: Dictionary = Game.gs
	var level := int(gs.trick.level)
	var flag := "trickprize_%d" % level
	if level == 0 or gs.flags.get(flag, false):
		Game.say(["Come find me again in the Trick House!"])
		return
	gs.flags[flag] = true
	var lines: Array = text.duplicate()
	for id in DB.TRICK.prizes[level - 1]:
		gs.bag[id] = gs.bag.get(id, 0) + 1
		lines.append("%s received %s!" % [gs.players[0].name, DB.item(id).name])
	Audio.sfx("item")
	Game.say(lines + ["I'll be back with a trickier trick. Watch out!"])
