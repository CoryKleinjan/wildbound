extends SceneTree
## Port of tests/engine.test.ts. Run:
## timeout 600 godot --headless --path . -s res://tests/engine_test.gd

var failures := 0
## Engine scripts are loaded at runtime (not referenced by class_name) so they compile after the DB autoload exists.
var RngS: GDScript
var Cr: GDScript
var BattleS: GDScript

func check(name: String, cond: bool, extra: String = "") -> void:
	if not cond:
		failures += 1
		print("FAIL %s %s" % [name, extra])
	else:
		print("ok   %s" % name)

func _initialize() -> void:
	await process_frame
	RngS = load("res://scripts/engine/rng.gd")
	Cr = load("res://scripts/engine/creature.gd")
	BattleS = load("res://scripts/engine/battle.gd")
	_run()
	if failures:
		print("%d failure(s)" % failures)
		quit(1)
		return
	print("all tests passed")
	quit(0)

func _all31() -> Dictionary:
	return {"hp": 31, "atk": 31, "def": 31, "spa": 31, "spd": 31, "spe": 31}

func _all0() -> Dictionary:
	return {"hp": 0, "atk": 0, "def": 0, "spa": 0, "spd": 0, "spe": 0}

func _run() -> void:
	# Rng sanity: mulberry32 reference values for seed 1 (from the TS implementation).
	var r0 = RngS.new(1)
	var firsts: Array = []
	for i in 3:
		firsts.push_back(r0.next_float())
	check("mulberry32 seed 1", absf(firsts[0] - 0.6270739405881613) < 1e-12 and absf(firsts[1] - 0.002735721180215478) < 1e-12 and absf(firsts[2] - 0.5274470399599522) < 1e-12, str(firsts))

	# Stat formula (Gen 3): a level 50 Sproutle with 31 IVs, 0 EVs, Hardy nature.
	var c = Cr.create_creature("sproutle", 50, {"personality": 0, "ivs": _all31()})
	var s = Cr.calc_stats(c)
	# HP = floor((2*45+31)*50/100)+50+10 = 60+60 = 120; Atk = floor((2*49+31)*50/100)+5 = 64+5 = 69
	check("hp formula", s.hp == 120, str(s.hp))
	check("atk formula", s.atk == 69, str(s.atk))
	# Modest (15): +SpA -Atk. SpA = floor((floor((130+31)*0.5)+5)*1.1) = floor(85*1.1) = 93; Atk = floor(69*0.9) = 62
	var m = Cr.create_creature("sproutle", 50, {"personality": 15, "ivs": _all31()})
	var ms = Cr.calc_stats(m)
	check("nature boost", ms.spa == 93, str(ms.spa))
	check("nature drop", ms.atk == 62, str(ms.atk))

	# Growth curves.
	check("medium slow L5", Cr.exp_for_level("mediumSlow", 5) == 135)
	check("medium fast L10", Cr.exp_for_level("mediumFast", 10) == 1000)
	check("erratic L100", Cr.exp_for_level("erratic", 100) == 600000)
	check("fluctuating L100", Cr.exp_for_level("fluctuating", 100) == 1640000)

	# Level up raises HP by the max HP difference.
	var lc = Cr.create_creature("nibbit", 5)
	lc.hp -= 3
	var before: int = Cr.calc_stats(lc).hp
	Cr.gain_exp(lc, Cr.exp_for_level("mediumFast", 6) - int(lc.exp))
	check("level up hp", lc.hp == Cr.calc_stats(lc).hp - 3 and lc.level == 6, "%d/%d before %d" % [lc.hp, Cr.calc_stats(lc).hp, before])

	_damage_test()
	_fuzz_test()

# Damage formula: compare one Tackle against a hand calculation with min/max rolls.
func _damage_test() -> void:
	var a = Cr.create_creature("nibbit", 10, {"personality": 0, "ivs": _all0()})
	var d = Cr.create_creature("nibbit", 10, {"personality": 0, "ivs": _all0()})
	var sa = Cr.calc_stats(a)
	var sd = Cr.calc_stats(d)
	# base = floor(floor(atk*35*floor(2*10/5+2)/def)/50)+2, then STAB 1.5, random 85..100
	var base: int = ((int(sa.atk) * 35 * 6) / int(sd.def)) / 50 + 2
	var stab: int = (base * 15) / 10
	var lo: int = (stab * 85) / 100
	var hi: int = stab
	var seen := {}
	for i in 300:
		var A: Dictionary = a.duplicate()
		A.hp = Cr.calc_stats(a).hp
		A.moves = [{"id": "tackle", "pp": 35, "maxPp": 35}]
		var D: Dictionary = d.duplicate()
		D.hp = 999
		var b = BattleS.new({"kind": "trainer", "double": false, "rng": RngS.new(i), "sides": [
			[{"name": "A", "party": [A], "controller": "human", "slots": [0], "player": 0}],
			[{"name": "D", "party": [D], "controller": "human", "slots": [0]}],
		]})
		b.start()
		# Make the defender harmless: give it a status move.
		D.moves = [{"id": "growl", "pp": 40, "maxPp": 40}]
		var ev = b.submit({"0:0": {"kind": "move", "moveIdx": 0}})
		var hp_ev: Variant = null
		var crit := false
		var miss := false
		for e in ev:
			if hp_ev == null and e.t == "hp" and e.side == 1:
				hp_ev = e
			if e.t == "msg" and e.text == "A critical hit!":
				crit = true
			if e.t == "msg" and e.text.contains("missed"):
				miss = true
		if hp_ev != null and not crit and not miss:
			seen[999 - int(hp_ev.hp)] = true
	var vals: Array = seen.keys()
	vals.sort()
	var ok := vals.size() > 1
	for v in vals:
		if v < lo or v > hi:
			ok = false
	check("damage roll range", ok, "%d-%d saw %s" % [lo, hi, str(vals)])

# Fuzz: random battles must always terminate without throwing.
func _fuzz_test() -> void:
	var db = root.get_node("DB")
	var ids: Array = db.SPECIES.keys()
	var all_moves: Array = db.MOVES.keys().filter(func(k: String) -> bool: return k != "struggle")
	var held: Array = db.ITEMS.keys().filter(func(k: String) -> bool:
		return db.ITEMS[k].effect.kind in ["held", "berry"])
	var rng = RngS.new(1234)
	var done := 0
	var total_turns := 0
	for n in 400:
		var double := n % 2 == 0
		var wild := n % 3 == 0
		var mk := func(cnt: int, owner: int) -> Array:
			var out: Array = []
			for i in cnt:
				var c: Dictionary = Cr.create_creature(rng.pick(ids), 5 + rng.int_below(40), {"rng": rng, "owner": owner})
				# The second half uses random moves from the whole list and random held items.
				if n >= 200:
					c.moves = []
					for j in 4:
						c.moves.push_back(Cr.move_slot(rng.pick(all_moves)))
					c.item = rng.pick(held) if rng.int_below(4) != 0 else null
				out.push_back(c)
			return out
		var side0: Array
		if double:
			side0 = [
				{"name": "P1", "party": mk.call(3, 0), "controller": "human", "slots": [0], "player": 0},
				{"name": "P2", "party": mk.call(3, 1), "controller": "human", "slots": [1], "player": 1},
			]
		else:
			side0 = [{"name": "P1", "party": mk.call(6, 0), "controller": "human", "slots": [0], "player": 0}]
		var side1: Array
		if wild:
			side1 = [{"name": "wild", "party": mk.call(2 if double else 1, 9), "controller": "wild", "slots": [0, 1] if double else [0]}]
		else:
			side1 = [{"name": "Rival", "party": mk.call(3, 9), "controller": "ai", "slots": [0, 1] if double else [0]}]
		var b = BattleS.new({"kind": ("safari" if n % 7 == 0 and not double else "wild") if wild else "trainer", "double": double, "sides": [side0, side1], "rng": RngS.new(n)})
		b.start()
		var turns := 0
		while b.phase != "over" and turns < 500:
			var reqs = b.requests()
			var chosen := {}
			for r in reqs:
				var key := "%d:%d" % [r.ref.side, r.ref.slot]
				var bench = b.bench_for(r.trainer)
				if r.kind == "replace":
					chosen[key] = {"kind": "switch", "partyIdx": bench[0]}
					continue
				var mon: Dictionary = b.at(r.ref).mon
				var roll = rng.int_below(10)
				if roll == 0 and not bench.is_empty():
					chosen[key] = {"kind": "switch", "partyIdx": rng.pick(bench)}
				elif roll == 2 and b.kind == "safari":
					chosen[key] = {"kind": rng.pick(["bait", "rock"])}
				elif roll == 1 and wild:
					chosen[key] = {"kind": "item", "itemId": "orb", "target": {"side": 1, "slot": rng.int_below(2 if double else 1)}}
				else:
					var usable: Array = []
					for i in mon.moves.size():
						if b.move_selectable(b.at(r.ref), i) == "":
							usable.push_back(i)
					chosen[key] = {"kind": "move", "moveIdx": rng.pick(usable) if not usable.is_empty() else -1, "target": {"side": 1, "slot": rng.int_below(2 if double else 1)}}
			b.submit(chosen)
			turns += 1
		total_turns += turns
		if b.phase == "over":
			done += 1
	print("fuzz: %d battles, %d turns" % [done, total_turns])
	check("fuzz battles finish", done == 400, "%d/400" % done)
