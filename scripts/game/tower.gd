class_name Tower
## The Battle Tower (postgame, Summit Crown): pick three creatures, which fight as level-50 copies, then win
## seven single battles in a row against trainers with fully evolved creatures. The seventh is the Tower Tycoon.
## Each set won pays Battle Points (more for long streaks), spent at the counter next door.

const NAMES := ["Ace Rowan", "Ace Mira", "Veteran Hale", "Psychic Iris", "Gentleman Ode", "Beauty Lark", "Hiker Bram",
	"Swimmer Coral", "Ace Tobin", "Veteran Faye", "Psychic Noor", "Beauty Sage"]
const PALETTES := ["ace", "ace", "old", "psychic", "gentleman", "beauty", "hiker", "swimmer", "ace", "old", "psychic", "beauty"]
const HELD := ["leftovers", "quickClaw", "scopeLens", "brightPowder", "focusBand", "shellBell", "kingsRock", "whiteHerb",
	"lumBerry", "sitrusBerry", "choiceBand"]

static func start(o: OverworldScene) -> void:
	var gs: Dictionary = Game.gs
	if not gs.flags.get("champion", false):
		Game.say(["The Battle Tower is open to League Champions only. Come back once you've beaten the Champion!"])
		return
	Game.ask("Your streak is %d (best %d). Take on the Battle Tower? Bring three creatures; they'll fight at level 50." % [gs.tower.streak, gs.tower.best],
		["YES", "NO"], func(c: int) -> void:
			if c == 0:
				_pick_team(o, []))

static func _pick_team(o: OverworldScene, picked: Array) -> void:
	var gs: Dictionary = Game.gs
	if picked.size() == 3:
		_run(o, picked.map(func(m: Dictionary) -> Dictionary: return _copy(m)), 0)
		return
	Services.pick_creature("Choose creature %d of 3." % (picked.size() + 1), func(m: Dictionary) -> String:
		if picked.has(m):
			return "That one's already chosen."
		for p in picked:
			if p.species == m.species:
				return "You can't enter two of the same species."
		return "" if DB.species(m.species).get("rarity", "") != "legendary" else "Legendary creatures can't enter the Tower.",
	func(m: Dictionary) -> void:
		picked.append(m)
		_pick_team(o, picked),
	func() -> void: Game.say(["Come back anytime."]))

## A level-50 copy for the Tower: the original keeps its own level and EXP.
static func _copy(m: Dictionary) -> Dictionary:
	var c: Dictionary = m.duplicate(true)
	c.level = 50
	c.exp = Creatures.exp_for_level(DB.species(c.species).growth, 50)
	Creatures.heal_fully(c)
	return c

static func _opponent(n: int) -> Dictionary:
	var rng := Rng.global_rng
	var tycoon := n == 6
	if not tycoon:
		var friend := RecordMix.tower_opponent(Game.gs, 50)
		if not friend.is_empty():
			return friend
	var i := rng.int_below(NAMES.size())
	var t := {
		"id": "tower", "name": "Tower Tycoon Vale" if tycoon else NAMES[i], "palette": "prof" if tycoon else PALETTES[i], "pay": 0,
		"intro": "So you've made it this far. Show me everything!" if tycoon else "Battle %d of 7. Let's go!" % (n + 1),
		"defeat": "Magnificent! That's what a true champion looks like." if tycoon else "You're strong!",
	}
	var pool: Array = DB.TOWER.pool.duplicate()
	var party: Array = []
	for k in 3:
		var sp: String = pool.pop_at(rng.int_below(pool.size()))
		var ivs := {}
		for s in DB.STAT_KEYS:
			ivs[s] = 31 if tycoon else 12 + rng.int_below(12)
		var mon := Creatures.create_creature(sp, 50, {"owner": 9, "ivs": ivs})
		mon.item = HELD[rng.int_below(HELD.size())] if DB.ITEMS.has(HELD[0]) else null
		if mon.item != null and not DB.ITEMS.has(mon.item):
			mon.item = null
		party.append(mon)
	return {"trainer": t, "party": party}

static func _run(o: OverworldScene, team: Array, n: int) -> void:
	var gs: Dictionary = Game.gs
	var opp := _opponent(n)
	var t: Dictionary = opp.trainer
	Game.say([t.intro], func() -> void:
		var ref := {}
		var setup := {"kind": "trainer", "double": false, "trainer": t, "trainerParty": opp.party, "party": team,
			"noExp": true, "noPrize": true}
		setup.onEnd = func(result: String, _battle) -> void:
			Game.transition(func() -> void:
				Game.pop(ref.scene)
				Audio.play_music(OverworldScene.map_track(o.map))
				if result != "win":
					gs.tower.streak = 0
					Game.say(["Your streak ended at battle %d. Better luck next time!" % (n + 1)])
					return
				gs.tower.streak += 1
				gs.tower.best = maxi(gs.tower.best, gs.tower.streak)
				for m in team:
					Creatures.heal_fully(m)
				if n == 6:
					var bp: int = 3 + mini(7, gs.tower.streak / 7 - 1) * 2
					gs.bp += bp
					Audio.sfx("badge")
					Game.say(["Congratulations! You beat all seven trainers! Your streak is %d." % gs.tower.streak, "You earned %d Battle Points!" % bp])
					return
				Game.ask("You've won %d in a row. Your creatures were healed. Keep going?" % (n + 1), ["YES", "REST"], func(c: int) -> void:
					if c == 0:
						_run(o, team, n + 1)
					else:
						# Leaving mid-set forfeits the set's wins.
						gs.tower.streak = maxi(0, gs.tower.streak - (n + 1))
						Game.say(["You left before finishing the set, so this set's wins don't count. Come back anytime!"])))
		o._flash_then(func() -> void:
			var scene := BattleScene.new(setup)
			ref.scene = scene
			Game.push(scene)))
