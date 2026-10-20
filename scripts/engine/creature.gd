class_name Creatures
extends RefCounted
## Port of src/engine/creature.ts. A Creature is a Dictionary with the TS keys:
## uid, species, nickname (optional), level, exp, personality, otId, ivs, evs, moves: [{id, pp, maxPp}],
## hp, status (null or "brn"/"par"/"psn"/"tox"/"slp"/"frz"), sleepTurns, toxicCount, owner.
## Emerald additions: item (held item id or null), friendship (0-255), ball, metLevel, ppUps [per move slot],
## egg (bool) + eggSteps, ribbons [], condition {cool, beauty, cute, smart, tough, sheen}, pokerus-free.
## Older saves lack these; migrate() fills them in.

const EV_STAT_CAP := 255
const EV_TOTAL_CAP := 510

static var next_uid: int = 1

static func set_next_uid(n: int) -> void:
	next_uid = maxi(next_uid, n)

static func display_name(c: Dictionary) -> String:
	if c.get("egg", false):
		return "Egg"
	var nick: Variant = c.get("nickname", null)
	if nick != null and str(nick) != "":
		return str(nick)
	return DB.species(c.species).name

static func nature_of(c: Dictionary) -> int:
	return int(c.personality) % 25

static func ability_of(c: Dictionary) -> String:
	var a: Array = DB.species(c.species).abilities
	return a[1] if a.size() == 2 and (int(c.personality) & 1) else a[0]

## "M", "F" or null.
static func gender_of(c: Dictionary) -> Variant:
	var r: int = DB.species(c.species).genderRatio
	if r < 0:
		return null
	if r == 0:
		return "M"
	if r >= 254:
		return "F"
	return "F" if (int(c.personality) & 0xff) < r else "M"

static func is_shiny(c: Dictionary) -> bool:
	var p: int = int(c.personality) & 0xFFFFFFFF
	var t: int = int(c.otId) & 0xFFFFFFFF
	return ((t >> 16) ^ (t & 0xffff) ^ (p >> 16) ^ (p & 0xffff)) < 8

## Gen 3 stat formulas, including the nature multiplier applied with floor.
static func calc_stats(c: Dictionary) -> Dictionary:
	var b: Dictionary = DB.species(c.species).base
	var n := nature_of(c)
	var lvl: int = c.level
	var out := {}
	for k in DB.STAT_KEYS:
		var core: int = ((2 * int(b[k]) + int(c.ivs[k]) + int(c.evs[k]) / 4) * lvl) / 100
		if k == "hp":
			out.hp = core + lvl + 10
		else:
			out[k] = ((core + 5) * DB.nature_mod(n, k)) / 100
	return out

static func max_hp(c: Dictionary) -> int:
	return calc_stats(c).hp

static func exp_for_level(rate: String, n: int) -> int:
	if n <= 1:
		return 0
	var n3 := n * n * n
	match rate:
		"fast":
			return (4 * n3) / 5
		"mediumFast":
			return n3
		"mediumSlow":
			return (6 * n3) / 5 - 15 * n * n + 100 * n - 140
		"slow":
			return (5 * n3) / 4
		"erratic":
			if n <= 50:
				return (n3 * (100 - n)) / 50
			if n <= 68:
				return (n3 * (150 - n)) / 100
			if n <= 98:
				return (n3 * ((1911 - 10 * n) / 3)) / 500
			return (n3 * (160 - n)) / 100
		"fluctuating":
			if n <= 15:
				return (n3 * ((n + 1) / 3 + 24)) / 50
			if n <= 36:
				return (n3 * (n + 14)) / 50
			return (n3 * (n / 2 + 32)) / 50
	return 0

static func move_slot(id: String) -> Dictionary:
	var m: Dictionary = DB.move(id)
	return {"id": id, "pp": m.pp, "maxPp": m.pp}

## opts keys (TS CreateOpts): owner, otId, rng (Rng), ivs (partial Stats6), personality.
static func create_creature(species_id: String, level: int, opts: Dictionary = {}) -> Dictionary:
	var rng: Rng = opts.get("rng", null)
	if rng == null:
		rng = Rng.global_rng
	var sp: Dictionary = DB.species(species_id)
	var ivs := {}
	for k in DB.STAT_KEYS:
		ivs[k] = rng.int_below(32)
	var given_ivs: Dictionary = opts.get("ivs", {})
	for k in given_ivs:
		ivs[k] = given_ivs[k]
	# Gen 3: a new creature knows the last four moves it would have learned by its level.
	var known: Array = []
	for entry in sp.learnset:
		if int(entry[0]) > level:
			break
		var id: String = entry[1]
		if known.has(id):
			continue
		known.push_back(id)
		if known.size() > 4:
			known.pop_front()
	var moves: Array = []
	for id in known:
		moves.push_back(move_slot(id))
	var personality: int = opts.personality if opts.get("personality", null) != null else rng.u32()
	var ot_id: int = opts.otId if opts.get("otId", null) != null else rng.u32()
	var c := {
		"uid": next_uid,
		"species": species_id,
		"level": level,
		"exp": exp_for_level(sp.growth, level),
		"personality": personality,
		"otId": ot_id,
		"ivs": ivs,
		"evs": {"hp": 0, "atk": 0, "def": 0, "spa": 0, "spd": 0, "spe": 0},
		"moves": moves,
		"hp": 0,
		"status": null,
		"sleepTurns": 0,
		"toxicCount": 0,
		"owner": opts.get("owner", 0),
		"item": opts.get("item", null),
		"friendship": int(sp.get("friendship", 70)),
		"ball": "orb",
		"metLevel": level,
		"egg": false,
		"eggSteps": 0,
		"ribbons": [],
		"condition": {"cool": 0, "beauty": 0, "cute": 0, "smart": 0, "tough": 0, "sheen": 0},
	}
	next_uid += 1
	c.hp = max_hp(c)
	return c

static func heal_fully(c: Dictionary) -> void:
	c.hp = max_hp(c)
	c.status = null
	c.sleepTurns = 0
	c.toxicCount = 0
	for m in c.moves:
		m.pp = m.maxPp

static func add_evs(c: Dictionary, gain: Dictionary) -> void:
	for k in DB.STAT_KEYS:
		var want: int = gain.get(k, 0)
		if not want:
			continue
		var total := 0
		for kk in DB.STAT_KEYS:
			total += int(c.evs[kk])
		var room: int = mini(EV_STAT_CAP - int(c.evs[k]), EV_TOTAL_CAP - total)
		c.evs[k] += maxi(0, mini(want, room))

## Adds experience and applies level-ups. HP rises by the max-HP gain, as in Gen 3.
## Returns LevelUpResult dicts: {level, learned, pending, oldStats, newStats}.
static func gain_exp(c: Dictionary, amount: int) -> Array:
	var sp: Dictionary = DB.species(c.species)
	var results: Array = []
	c.exp = mini(int(c.exp) + amount, exp_for_level(sp.growth, 100))
	while c.level < 100 and c.exp >= exp_for_level(sp.growth, c.level + 1):
		var old_stats := calc_stats(c)
		c.level += 1
		if c.has("friendship"):
			var f: int = c.friendship
			add_friendship(c, 5 if f < 100 else (3 if f < 200 else 2))
		var new_stats := calc_stats(c)
		if c.hp > 0:
			c.hp += new_stats.hp - old_stats.hp
		var learned: Array = []
		var pending: Array = []
		for entry in sp.learnset:
			var id: String = entry[1]
			if int(entry[0]) != c.level:
				continue
			var knows := false
			for m in c.moves:
				if m.id == id:
					knows = true
					break
			if knows:
				continue
			if c.moves.size() < 4:
				c.moves.push_back(move_slot(id))
				learned.push_back(id)
			else:
				pending.push_back(id)
		results.push_back({"level": c.level, "learned": learned, "pending": pending, "oldStats": old_stats, "newStats": new_stats})
	return results

## {into, span}
static func exp_to_next(c: Dictionary) -> Dictionary:
	var g: String = DB.species(c.species).growth
	if c.level >= 100:
		return {"into": 1, "span": 1}
	var lo := exp_for_level(g, c.level)
	var hi := exp_for_level(g, c.level + 1)
	return {"into": int(c.exp) - lo, "span": hi - lo}

## Evolves in place, keeping HP damage. Returns the old species id.
static func evolve(c: Dictionary, into: String) -> String:
	var old: String = c.species
	var before := max_hp(c)
	c.species = into
	var after := max_hp(c)
	if c.hp > 0:
		c.hp += after - before
	return old

## Adds the Emerald fields to a creature from an older save.
static func migrate(c: Dictionary) -> void:
	if not c.has("item"):
		c.item = null
	if not c.has("friendship"):
		c.friendship = int(DB.species(c.species).get("friendship", 70))
	if not c.has("ball"):
		c.ball = "orb"
	if not c.has("metLevel"):
		c.metLevel = c.level
	if not c.has("egg"):
		c.egg = false
		c.eggSteps = 0
	if not c.has("ribbons"):
		c.ribbons = []
	if not c.has("condition"):
		c.condition = {"cool": 0, "beauty": 0, "cute": 0, "smart": 0, "tough": 0, "sheen": 0}
	# A Knock Off from the last battle hands the item back.
	if c.has("knockedOff"):
		if c.item == null:
			c.item = c.knockedOff
		c.erase("knockedOff")

## Gen 3 friendship change; Soothe Bell boosts gains by half and Luxury Orbs add one.
static func add_friendship(c: Dictionary, amount: int) -> void:
	if not c.has("friendship"):
		return
	var a := amount
	if a > 0:
		if c.get("item", null) == "sootheBell":
			a = (a * 150) / 100
		if c.get("luxury", false):
			a += 1
		# Gains shrink as friendship grows, as in Gen 3.
		if int(c.friendship) >= 200:
			a = maxi(1, a / 2)
	c.friendship = clampi(int(c.friendship) + a, 0, 255)

## Teaches a move into a free slot, or returns false when all four are full.
static func learn(c: Dictionary, id: String) -> bool:
	for m in c.moves:
		if m.id == id:
			return true
	if c.moves.size() >= 4:
		return false
	c.moves.push_back(move_slot(id))
	return true

static func knows(c: Dictionary, id: String) -> bool:
	for m in c.moves:
		if m.id == id:
			return true
	return false

## Species id or null. `trigger` is "level" (after battle), "trade", or an evolution stone item id.
## Everstone stops level, friendship and trade evolutions, as in Gen 3.
static func pending_evolution(c: Dictionary, trigger: String = "level") -> Variant:
	var e: Variant = DB.species(c.species).get("evolves", null)
	if not e or c.hp <= 0 or c.get("egg", false):
		return null
	var method: String = e.get("method", "level")
	if trigger == "level":
		if c.get("item", null) == "everstone":
			return null
		if method == "level" and c.level >= int(e.level):
			return e.into
		if method == "friendship" and int(c.get("friendship", 0)) >= 220:
			return e.into
		return null
	if trigger == "trade":
		if method == "trade" and c.get("item", null) != "everstone":
			return e.into
		return null
	if method == "stone" and e.get("item", "") == trigger:
		return e.into
	return null

## Moves this species could relearn at its level that it doesn't already know.
static func relearnable(c: Dictionary) -> Array:
	var out: Array = []
	for entry in DB.species(c.species).learnset:
		if int(entry[0]) <= int(c.level) and not knows(c, entry[1]) and not out.has(entry[1]):
			out.push_back(entry[1])
	return out

## Whether the species can learn a TM/HM (by item id, e.g. "tm26").
static func can_learn_tm(c: Dictionary, tm_id: String) -> bool:
	return (DB.species(c.species).get("tms", []) as Array).has(tm_id)

static func can_learn_tutor(c: Dictionary, move_id: String) -> bool:
	return (DB.species(c.species).get("tutor", []) as Array).has(move_id)
