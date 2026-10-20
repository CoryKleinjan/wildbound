class_name Battle
extends RefCounted
## Battle engine following Generation 3 (Ruby/Sapphire/Emerald) rules.
## The engine resolves a whole turn at once and returns a list of events for the UI to play back.
##
## Plain data stays in Dictionaries with the TS keys:
##   TrainerInit {name, party, controller ("human"/"ai"/"wild"), slots, player?}; BTrainer = TrainerInit + side.
##   BattleInit {kind ("wild"/"trainer"), double, sides: [[TrainerInit...], [TrainerInit...]], rng?}
##   Ref {side, slot}
##   Action {kind: "move", moveIdx, target?} | {kind: "switch", partyIdx} | {kind: "item", itemId, partyIdx?, target?} | {kind: "run"}
##   MonView {uid, species, name, level, hp, maxHp, status, gender, shiny, expFrac}
##   BEvent {t: "msg", text} | {t: "switchIn", side, slot, mon} | {t: "switchOut", side, slot} | {t: "update", side, slot, mon}
##     | {t: "hp", side, slot, hp, maxHp} | {t: "status", side, slot, status} | {t: "faint", side, slot}
##     | {t: "anim", kind ("hit"/"stat-up"/"stat-down"/"status"/"heal"/"move"), side, slot, type?}
##     | {t: "ball", side, slot, shakes, caught} | {t: "exp", side, slot, uid, expFrac, level}
##     | {t: "levelUp", uid, name, level, old: Stats6, now: Stats6} | {t: "learnPrompt", uid, moveId, player}
##     | {t: "weather", weather}
##   Request {ref, player, kind ("action"/"replace"), trainer}
## Creatures are compared by identity (is_same), like the TS object comparisons.

static func _fresh_volatile() -> Dictionary:
	return {
		"confusion": 0, "flinch": false, "protect": false, "protectStreak": 0, "protectedThisTurn": false,
		"leechSeed": null, "focusEnergy": false, "recharge": false, "charging": null, "helpingHand": false, "flashFire": false,
	}

static func _fresh_stages() -> Dictionary:
	return {"atk": 0, "def": 0, "spa": 0, "spd": 0, "spe": 0, "acc": 0, "eva": 0}

class Battler extends RefCounted:
	## Creature Dictionary or null.
	var mon: Variant = null
	var stats: Dictionary = {"hp": 1, "atk": 1, "def": 1, "spa": 1, "spd": 1, "spe": 1}
	var stages: Dictionary = Battle._fresh_stages()
	var vol: Dictionary = Battle._fresh_volatile()
	## uids of opposing creatures that fought this battler (for EXP), as a set {uid: true}.
	var participants: Dictionary = {}
	var side: int
	var slot: int
	## BTrainer Dictionary or null.
	var trainer: Variant

	var alive: bool:
		get: return mon != null and int(mon.hp) > 0
	var ref: Dictionary:
		get: return {"side": side, "slot": slot}
	## Ability id or null.
	var ability: Variant:
		get: return Creatures.ability_of(mon) if mon != null else null
	var types: Array:
		get: return DB.species(mon.species).types if mon != null else []

	func _init(p_side: int, p_slot: int, p_trainer: Variant) -> void:
		side = p_side
		slot = p_slot
		trainer = p_trainer

# Gen 3 stat stage ratios (index = stage + 6) and accuracy stage ratios.
const STAGE_RATIOS := [
	[10, 40], [10, 35], [10, 30], [10, 25], [10, 20], [10, 15], [10, 10], [15, 10], [20, 10], [25, 10], [30, 10], [35, 10], [40, 10],
]
const ACC_RATIOS := [
	[33, 100], [36, 100], [43, 100], [50, 100], [60, 100], [75, 100], [1, 1], [133, 100], [166, 100], [2, 1], [233, 100], [133, 50], [3, 1],
]
const CRIT_CHANCE := [16, 8, 4, 3, 2]
const PROTECT_RATES := [65535, 32767, 16383, 8191]

const STAT_NAMES := {
	"atk": "Attack", "def": "Defense", "spa": "Sp. Atk", "spd": "Sp. Def", "spe": "Speed", "acc": "accuracy", "eva": "evasiveness",
}

static func _stat_mod(value: int, stage: int) -> int:
	var r: Array = STAGE_RATIOS[stage + 6]
	return (value * int(r[0])) / int(r[1])

static func view(c: Dictionary) -> Dictionary:
	var e := Creatures.exp_to_next(c)
	return {
		"uid": c.uid, "species": c.species, "name": Creatures.display_name(c), "level": c.level, "hp": c.hp,
		"maxHp": Creatures.max_hp(c), "status": c.status, "gender": Creatures.gender_of(c), "shiny": Creatures.is_shiny(c),
		"expFrac": float(e.into) / float(e.span) if e.span else 0.0,
	}

static func _has_same(arr: Array, x: Variant) -> bool:
	for v in arr:
		if is_same(v, x):
			return true
	return false

var kind: String
var double: bool
var rng: Rng
## BTrainer[][] (each a copy of the TrainerInit with `side` added; party arrays are shared).
var trainers: Array = []
## Battler[][]
var battlers: Array = []
var side_state: Array = [{"reflect": 0, "lightScreen": 0}, {"reflect": 0, "lightScreen": 0}]
## null or "rain"/"sun"/"sand"/"hail".
var weather: Variant = null
var weather_turns: int = 0
## "choose" | "replace" | "over"
var phase: String = "choose"
## null | "win" | "lose" | "ran"
var result: Variant = null
var run_attempts: int = 0
var turn: int = 0
## Wild creatures caught this battle with the player index that caught them: [{mon, player}].
var caught: Array = []
var _events: Array = []
var _moved_this_turn: Array = []
var _fainted: Array = []
## PendingAction dicts {battler, mon, action, trainer}.
var _actions_this_turn: Array = []

func _init(init: Dictionary) -> void:
	kind = init.kind
	double = init.double
	var r: Variant = init.get("rng", null)
	rng = r if r != null else Rng.new()
	var n := 2 if double else 1
	for side in 2:
		var ts: Array = []
		for t in init.sides[side]:
			var bt: Dictionary = t.duplicate()
			bt.side = side
			ts.push_back(bt)
		trainers.push_back(ts)
	for side in 2:
		var row: Array = []
		for slot in n:
			var owner: Variant = null
			for t in trainers[side]:
				if t.slots.has(slot):
					owner = t
					break
			row.push_back(Battler.new(side, slot, owner))
		battlers.push_back(row)

# ---------- helpers ----------
func _emit(e: Dictionary) -> void:
	_events.push_back(e)

func _msg(text: String) -> void:
	_emit({"t": "msg", "text": text})

func name(b: Battler) -> String:
	if b.mon == null:
		return "???"
	var n := Creatures.display_name(b.mon)
	if b.side == 0:
		return n
	return "Wild %s" % n if kind == "wild" else "Foe %s" % n

func all_battlers() -> Array:
	return battlers[0] + battlers[1]

func foes_of(b: Battler) -> Array:
	return battlers[1 - b.side].filter(func(x: Battler) -> bool: return x.alive)

func ally_of(b: Battler) -> Battler:
	if not double:
		return null
	var a: Battler = battlers[b.side][1 - b.slot]
	return a if a.alive else null

func at(r: Dictionary) -> Battler:
	return battlers[r.side][r.slot]

func _hp_event(b: Battler) -> void:
	if b.mon != null:
		_emit({"t": "hp", "side": b.side, "slot": b.slot, "hp": b.mon.hp, "maxHp": b.stats.hp})

func _status_event(b: Battler) -> void:
	if b.mon != null:
		_emit({"t": "status", "side": b.side, "slot": b.slot, "status": b.mon.status})

func _active_mons(t: Dictionary) -> Array:
	var out: Array = []
	for b in battlers[t.side]:
		if b.mon != null:
			out.push_back(b.mon)
	return out

func bench_for(t: Dictionary) -> Array:
	var active := _active_mons(t)
	var out: Array = []
	for i in t.party.size():
		var m: Dictionary = t.party[i]
		if m.hp > 0 and not _has_same(active, m):
			out.push_back(i)
	return out

func _has_usable(t: Dictionary) -> bool:
	for m in t.party:
		if m.hp > 0:
			return true
	return false

func _side_defeated(side: int) -> bool:
	if side == 1 and kind == "wild":
		for b in battlers[1]:
			if b.alive:
				return false
		return true
	for t in trainers[side]:
		if _has_usable(t):
			return false
	return true

func _trainer_names(side: int) -> String:
	var names: PackedStringArray = []
	for t in trainers[side]:
		names.push_back(t.name)
	return " & ".join(names)

func _check_end() -> bool:
	if result != null:
		return true
	if _side_defeated(1):
		result = "win"
		phase = "over"
		if kind == "trainer":
			_msg("Player defeated %s!" % _trainer_names(1))
		return true
	if _side_defeated(0):
		result = "lose"
		phase = "over"
		return true
	return false

# ---------- switching ----------
func _send_out(b: Battler, mon: Dictionary, announce: bool) -> void:
	b.mon = mon
	b.stats = Creatures.calc_stats(mon)
	b.stages = _fresh_stages()
	b.vol = _fresh_volatile()
	mon.toxicCount = 0
	if announce:
		if b.side == 0:
			_msg("Go! %s!" % Creatures.display_name(mon))
		elif kind == "trainer":
			_msg("%s sent out %s!" % [b.trainer.name if b.trainer != null else "undefined", Creatures.display_name(mon)])
	_emit({"t": "switchIn", "side": b.side, "slot": b.slot, "mon": view(mon)})
	# EXP participation: a foe remembers every player creature that was out while it was.
	if b.side == 1:
		b.participants = {}
		for f in foes_of(b):
			b.participants[f.mon.uid] = true
	else:
		for foe in foes_of(b):
			foe.participants[mon.uid] = true

func _withdraw(b: Battler) -> void:
	if b.mon == null:
		return
	if b.ability == "naturalCure" and b.mon.status:
		b.mon.status = null
	if b.mon.status == "tox":
		b.mon.toxicCount = 0
	if b.side == 0:
		_msg("%s, come back!" % Creatures.display_name(b.mon))
	else:
		_msg("%s withdrew %s!" % [b.trainer.name if b.trainer != null else "undefined", Creatures.display_name(b.mon)])
	# Leech Seed planted by this position is kept by Gen 3 rules; seeds on the leaving battler go away.
	_emit({"t": "switchOut", "side": b.side, "slot": b.slot})
	b.mon = null

func _switch_in_abilities(list: Array) -> void:
	for b in _speed_order(list):
		if not b.alive:
			continue
		if b.ability == "intimidate":
			for f in foes_of(b):
				if f.ability == "clearBody":
					_msg("%s's Clear Body prevents stat loss!" % name(f))
					continue
				if f.stages.atk <= -6:
					continue
				f.stages.atk -= 1
				_emit({"t": "anim", "kind": "stat-down", "side": f.side, "slot": f.slot})
				_msg("%s's Intimidate cuts %s's Attack!" % [name(b), name(f)])

## Sends out lead creatures. Call once before the first request.
func start() -> Array:
	_events = []
	if kind == "wild":
		var wild: Dictionary = trainers[1][0]
		var names: PackedStringArray = []
		for m in wild.party:
			names.push_back(Creatures.display_name(m))
		for i in wild.party.size():
			if i < battlers[1].size():
				_send_out(battlers[1][i], wild.party[i], false)
		_msg("Wild %s appeared!" % " and ".join(names))
	else:
		_msg("%s %s to battle!" % [_trainer_names(1), "want" if trainers[1].size() > 1 else "wants"])
		for t in trainers[1]:
			_fill_slots(t, true)
	for t in trainers[0]:
		_fill_slots(t, true)
	_switch_in_abilities(all_battlers())
	return _take_events()

func _fill_slots(t: Dictionary, announce: bool) -> void:
	for slot in t.slots:
		var b: Battler = battlers[t.side][slot]
		if b.alive:
			continue
		var bench := bench_for(t)
		if bench.is_empty():
			b.mon = null
			continue
		_send_out(b, t.party[bench[0]], announce)

func _take_events() -> Array:
	var e := _events
	_events = []
	return e

# ---------- requests ----------
func requests() -> Array:
	if phase == "over":
		return []
	var out: Array = []
	for b in battlers[0]:
		var t: Variant = b.trainer
		if t == null or t.controller != "human":
			continue
		if phase == "replace":
			if not b.alive and not bench_for(t).is_empty():
				out.push_back({"ref": b.ref, "player": t.get("player", 0), "kind": "replace", "trainer": t})
		elif b.alive and not b.vol.recharge and not b.vol.charging:
			out.push_back({"ref": b.ref, "player": t.get("player", 0), "kind": "action", "trainer": t})
	return out

## Whether a creature has any usable move (otherwise it must Struggle).
func has_usable_move(mon: Dictionary) -> bool:
	for m in mon.moves:
		if m.pp > 0:
			return true
	return false

# ---------- turn resolution ----------
## chosen: Dictionary "side:slot" -> Action.
func submit(chosen: Dictionary) -> Array:
	_events = []
	if phase == "replace":
		var ins: Array = []
		for r in requests():
			var a: Variant = chosen.get("%d:%d" % [r.ref.side, r.ref.slot], null)
			if a == null or a.kind != "switch":
				continue
			var b := at(r.ref)
			_send_out(b, r.trainer.party[a.partyIdx], true)
			ins.push_back(b)
		_switch_in_abilities(ins)
		phase = "choose"
		return _take_events()

	turn += 1
	var pending: Array = []
	for b in all_battlers():
		if not b.alive or b.trainer == null:
			continue
		var action: Variant = null
		if b.vol.recharge:
			action = {"kind": "move", "moveIdx": -2}
		elif b.vol.charging:
			action = {"kind": "move", "moveIdx": b.vol.charging.moveIdx, "target": b.vol.charging.target}
		elif b.trainer.controller == "human":
			action = chosen.get("%d:%d" % [b.side, b.slot], null)
		else:
			action = _choose_ai(b)
		if action != null:
			pending.push_back({"battler": b, "mon": b.mon, "action": action, "trainer": b.trainer})

	var ordered := _order_actions(pending)
	_actions_this_turn = ordered
	_moved_this_turn.clear()
	for p in ordered:
		if result != null:
			break
		if not is_same(p.battler.mon, p.mon) or not p.battler.alive:
			continue
		_execute(p)
		_moved_this_turn.push_back(p.battler)
		if _check_end():
			break
	if result == null:
		_end_of_turn()
	if result == null:
		_check_end()
	if result == null:
		_after_turn_replacements()
	return _take_events()

func _after_turn_replacements() -> void:
	# AI and wild sides replace automatically.
	var ins: Array = []
	for t in trainers[1]:
		if t.controller == "wild":
			continue
		for slot in t.slots:
			var b: Battler = battlers[1][slot]
			if b.alive:
				continue
			var bench := bench_for(t)
			if not bench.is_empty():
				_send_out(b, t.party[bench[0]], true)
				ins.push_back(b)
			else:
				b.mon = null
	# Clear fainted player positions that have no replacement.
	for b in battlers[0]:
		if not b.alive and b.trainer != null and bench_for(b.trainer).is_empty():
			b.mon = null
	_switch_in_abilities(ins)
	if not _requests_for_replace().is_empty():
		phase = "replace"

func _requests_for_replace() -> Array:
	return battlers[0].filter(func(b: Battler) -> bool:
		return not b.alive and b.trainer != null and b.trainer.controller == "human" and not bench_for(b.trainer).is_empty())

func effective_speed(b: Battler) -> int:
	var s := _stat_mod(b.stats.spe, b.stages.spe)
	if b.ability == "swiftSwim" and weather == "rain":
		s *= 2
	if b.ability == "chlorophyll" and weather == "sun":
		s *= 2
	if b.mon != null and b.mon.status == "par":
		s = s / 4
	return s

func _speed_order(list: Array) -> Array:
	var keyed: Array = []
	for b in list:
		keyed.push_back({"b": b, "s": effective_speed(b), "r": rng.next_float()})
	keyed.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		if x.s != y.s:
			return x.s > y.s
		return x.r < y.r)
	return keyed.map(func(x: Dictionary) -> Battler: return x.b)

func _order_actions(list: Array) -> Array:
	var keyed: Array = []
	for p in list:
		var k1 := 0 if p.action.kind == "move" else 1
		var k2 := 0
		if p.action.kind == "move":
			var id: Variant = _move_id_of(p.battler, p.action.moveIdx)
			k2 = DB.move(id).priority if id != null else 0
		keyed.push_back({"p": p, "k1": k1, "k2": k2, "s": effective_speed(p.battler), "r": rng.next_float()})
	keyed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.k1 != b.k1:
			return a.k1 > b.k1
		if a.k2 != b.k2:
			return a.k2 > b.k2
		if a.s != b.s:
			return a.s > b.s
		return a.r < b.r)
	return keyed.map(func(x: Dictionary) -> Dictionary: return x.p)

## Move id or null.
func _move_id_of(b: Battler, idx: int) -> Variant:
	if idx == -1:
		return "struggle"
	if idx < 0:
		return null
	if b.mon == null or idx >= b.mon.moves.size():
		return null
	return b.mon.moves[idx].id

func _execute(p: Dictionary) -> void:
	var b: Battler = p.battler
	var action: Dictionary = p.action
	match action.kind:
		"run":
			_do_run(b)
		"switch":
			var t: Dictionary = p.trainer
			var idx: int = action.partyIdx
			if idx < 0 or idx >= t.party.size():
				return
			var mon: Dictionary = t.party[idx]
			if mon.hp <= 0:
				return
			_withdraw(b)
			_send_out(b, mon, true)
			_switch_in_abilities([b])
		"item":
			_do_item(p, action)
		"move":
			_do_move(b, action.moveIdx, action.get("target", null))

func _do_run(b: Battler) -> void:
	if kind != "wild":
		_msg("No! There's no running from a trainer battle!")
		return
	var foe_speed := 1
	for f in foes_of(b):
		foe_speed = maxi(foe_speed, f.stats.spe)
	var escaped := false
	if b.ability == "runAway":
		escaped = true
	elif b.stats.spe > foe_speed:
		escaped = true
	else:
		var odds: int = (int(b.stats.spe) * 128) / foe_speed + 30 * run_attempts
		escaped = odds > (rng.random16() & 0xff)
	run_attempts += 1
	if escaped:
		_msg("Got away safely!")
		result = "ran"
		phase = "over"
	else:
		_msg("Can't escape!")

func _do_item(p: Dictionary, a: Dictionary) -> void:
	var it: Dictionary = DB.item(a.itemId)
	var player_name: String = p.trainer.name
	var eff: Dictionary = it.effect
	if eff.kind == "ball":
		var target: Battler = null
		if a.get("target", null) != null:
			target = at(a.target)
		else:
			var foes := foes_of(p.battler)
			target = foes[0] if not foes.is_empty() else null
		var nm: String = it.name
		var article := "an" if nm.length() > 0 and "AEIOU".contains(nm[0]) else "a"
		_msg("%s threw %s %s!" % [player_name, article, nm])
		if target == null or not target.alive or kind != "wild":
			_msg("It missed!")
			return
		_try_catch(target, eff.mult10, p.trainer.get("player", 0))
		return
	var pidx: int = a.get("partyIdx", 0) if a.get("partyIdx", null) != null else 0
	if pidx < 0 or pidx >= p.trainer.party.size():
		return
	var mon: Dictionary = p.trainer.party[pidx]
	var active: Battler = null
	for x in all_battlers():
		if is_same(x.mon, mon):
			active = x
			break
	_msg("%s used %s!" % [player_name, it.name])
	if eff.kind == "heal":
		var mx := Creatures.max_hp(mon)
		var before: int = mon.hp
		mon.hp = mini(mx, int(mon.hp) + int(eff.amount))
		if active != null:
			_hp_event(active)
		_msg("%s's HP was restored by %d point(s)." % [Creatures.display_name(mon), mon.hp - before])
	elif eff.kind == "revive":
		if mon.hp > 0:
			_msg("But it had no effect.")
		else:
			mon.hp = Creatures.max_hp(mon) / 2
			mon.status = null
			for i in range(_fainted.size() - 1, -1, -1):
				if is_same(_fainted[i], mon):
					_fainted.remove_at(i)
			_msg("%s was revived!" % Creatures.display_name(mon))
	elif eff.kind == "cure":
		if mon.status and eff.statuses.has(mon.status):
			mon.status = null
			mon.sleepTurns = 0
			if active != null:
				_status_event(active)
			_msg("%s was cured!" % Creatures.display_name(mon))
		else:
			_msg("But it had no effect.")

## Gen 3 catch formula with four shake checks.
func _try_catch(b: Battler, ball_mult10: int, player: int) -> void:
	var mon: Dictionary = b.mon
	var rate: int = DB.species(mon.species).catchRate
	var mx: int = b.stats.hp
	var odds: int = (((rate * ball_mult10) / 10) * (mx * 3 - int(mon.hp) * 2)) / (3 * mx)
	if mon.status == "slp" or mon.status == "frz":
		odds *= 2
	elif mon.status:
		odds = (odds * 15) / 10
	var shakes := 0
	var is_caught := false
	if odds > 254:
		is_caught = true
	else:
		var b2: int = 1048560 / int(sqrt(float(int(sqrt(float(16711680 / maxi(1, odds)))))))
		while shakes < 4 and rng.random16() < b2:
			shakes += 1
		is_caught = shakes == 4
	_emit({"t": "ball", "side": b.side, "slot": b.slot, "shakes": 3 if is_caught else mini(shakes, 3), "caught": is_caught})
	if is_caught:
		_msg("Gotcha! %s was caught!" % Creatures.display_name(mon))
		mon.owner = player
		# keeps status like Gen 3
		caught.push_back({"mon": mon, "player": player})
		_emit({"t": "switchOut", "side": b.side, "slot": b.slot})
		b.mon = null
		var wild: Dictionary = trainers[1][0]
		wild.party = wild.party.filter(func(m: Dictionary) -> bool: return not is_same(m, mon))
	else:
		_msg([
			"Oh, no! It broke free!",
			"Aww! It appeared to be caught!",
			"Aargh! Almost had it!",
			"Shoot! It was so close, too!",
		][mini(shakes, 3)])

# ---------- moves ----------
func _do_move(user: Battler, move_idx: int, chosen_target: Variant) -> void:
	var mon: Dictionary = user.mon
	# Recharge turn (Hyper Beam).
	if move_idx == -2:
		_msg("%s must recharge!" % name(user))
		user.vol.recharge = false
		return
	var move_id: Variant = _move_id_of(user, move_idx)
	if move_id == null:
		return
	var mv: Dictionary = DB.move(move_id)
	var effect: Dictionary = mv.effect
	var continuing_charge: bool = user.vol.charging != null

	# Status checks, in the Gen 3 "attack canceler" order.
	if mon.status == "slp":
		mon.sleepTurns -= 2 if user.ability == "earlyBird" else 1
		if mon.sleepTurns > 0:
			_msg("%s is fast asleep." % name(user))
			user.vol.charging = null
			return
		mon.status = null
		mon.sleepTurns = 0
		_status_event(user)
		_msg("%s woke up!" % name(user))
	if mon.status == "frz":
		if mv.get("thawsUser", false) or rng.int_below(5) == 0:
			mon.status = null
			_status_event(user)
			_msg("%s was defrosted!" % name(user))
		else:
			_msg("%s is frozen solid!" % name(user))
			return
	if user.vol.flinch:
		_msg("%s flinched!" % name(user))
		user.vol.charging = null
		return
	if user.vol.confusion > 0:
		user.vol.confusion -= 1
		if user.vol.confusion == 0:
			_msg("%s snapped out of confusion!" % name(user))
		else:
			_msg("%s is confused!" % name(user))
			if rng.int_below(2) == 0:
				var dmg := base_damage(user, user, 40, "Mystery", true, false, false)
				_msg("It hurt itself in its confusion!")
				_apply_damage(user, dmg)
				user.vol.charging = null
				_check_faint(user)
				return
	if mon.status == "par" and rng.int_below(4) == 0:
		_msg("%s is paralyzed! It can't move!" % name(user))
		user.vol.charging = null
		return

	# Targets.
	var targets := _resolve_targets(user, mv, chosen_target)

	# PP (Pressure costs one extra per Pressure foe targeted).
	if not continuing_charge and move_idx >= 0:
		var slot: Dictionary = mon.moves[move_idx]
		var cost := 1
		for t in targets:
			if t.side != user.side and t.ability == "pressure":
				cost += 1
		slot.pp = maxi(0, int(slot.pp) - cost)

	if move_id == "struggle":
		_msg("%s has no moves left!" % name(user))
	_msg("%s used %s!" % [name(user), mv.name])
	_emit({"t": "anim", "kind": "move", "side": user.side, "slot": user.slot, "type": mv.type})

	# Two-turn moves.
	if effect.kind == "charge" and not continuing_charge and weather != "sun":
		_msg("%s took in sunlight!" % name(user))
		user.vol.charging = {"moveIdx": move_idx, "target": chosen_target}
		return
	user.vol.charging = null

	# Moves that don't target a battler.
	match effect.kind:
		"weather":
			_set_weather(effect.weather)
			return
		"screen":
			var s: Dictionary = side_state[user.side]
			var key: String = effect.screen
			if s[key] > 0:
				_msg("But it failed!")
				return
			s[key] = 5
			var team := "your team's" if user.side == 0 else "the foe team's"
			_msg("Reflect raised %s Defense!" % team if key == "reflect" else "Light Screen raised %s Sp. Def!" % team)
			return
		"protect":
			var others := 0
			for p in _actions_this_turn:
				if not _moved_this_turn.has(p.battler) and p.battler != user:
					others += 1
			var is_last := others == 0
			var rate: int = PROTECT_RATES[mini(user.vol.protectStreak, 3)]
			if not is_last and rng.random16() <= rate:
				user.vol.protect = true
				user.vol.protectedThisTurn = true
				user.vol.protectStreak += 1
				_msg("%s protected itself!" % name(user))
			else:
				user.vol.protectStreak = 0
				_msg("But it failed!")
			return
		"helpingHand":
			var ally := ally_of(user)
			if ally == null or _moved_this_turn.has(ally):
				_msg("But it failed!")
				return
			ally.vol.helpingHand = true
			_msg("%s is ready to help %s!" % [name(user), name(ally)])
			return
		"focusEnergy":
			if user.vol.focusEnergy:
				_msg("But it failed!")
				return
			user.vol.focusEnergy = true
			_msg("%s is getting pumped!" % name(user))
			return
		"rest":
			if mon.hp >= user.stats.hp or user.ability == "insomnia":
				_msg("But it failed!")
				return
			mon.status = "slp"
			mon.sleepTurns = 3
			mon.hp = user.stats.hp
			_status_event(user)
			_hp_event(user)
			_msg("%s slept and became healthy!" % name(user))
			return
		"heal":
			if mon.hp >= user.stats.hp:
				_msg("%s's HP is full!" % name(user))
				return
			var amt: int = user.stats.hp / 2
			if effect.get("weatherScaled", false) and weather == "sun":
				amt = (int(user.stats.hp) * 20) / 30
			elif effect.get("weatherScaled", false) and weather != null:
				amt = user.stats.hp / 4
			_heal(user, amt)
			_msg("%s regained health!" % name(user))
			return

	if mv.target == "self":
		if effect.kind == "stat":
			_apply_stat_changes(user, user, effect.stages, true)
		return

	if targets.is_empty():
		_msg("But there was no target...")
		return

	var alive_on_foe_side := 0
	for x in battlers[1 - user.side]:
		if x.alive:
			alive_on_foe_side += 1
	var spread_half: bool = mv.target == "both" and double and alive_on_foe_side == 2
	var any_hit := false

	for target in targets:
		if not target.alive:
			continue
		if target.vol.protect and mv.protectable and target != user:
			_msg("%s protected itself!" % name(target))
			continue
		# Ability-based immunities.
		if mv.type == "Ground" and mv.power > 0 and target.ability == "levitate":
			_msg("%s makes Ground moves miss with Levitate!" % name(target))
			continue
		if mv.power > 0 and ((mv.type == "Electric" and target.ability == "voltAbsorb") or (mv.type == "Water" and target.ability == "waterAbsorb")):
			var ab_name: String = DB.ABILITIES[target.ability].name
			if target.mon.hp >= target.stats.hp:
				_msg("%s's %s made %s useless!" % [name(target), ab_name, mv.name])
			else:
				_heal(target, target.stats.hp / 4)
				_msg("%s restored HP using its %s!" % [name(target), ab_name])
			continue
		if mv.type == "Fire" and target.ability == "flashFire" and target.mon.status != "frz":
			target.vol.flashFire = true
			_msg("%s's Flash Fire raised its Fire power!" % name(target))
			continue
		# Accuracy.
		if not _accuracy_check(user, target, mv):
			_msg("%s's attack missed!" % name(user))
			continue
		if mv.power > 0:
			if _damaging_hit(user, target, mv, spread_half):
				any_hit = true
		else:
			_status_move(user, target, mv)
			any_hit = true

	if any_hit and effect.kind == "recharge":
		user.vol.recharge = true
	user.vol.helpingHand = false

func _resolve_targets(user: Battler, mv: Dictionary, chosen: Variant) -> Array:
	var foes := foes_of(user)
	var ally := ally_of(user)
	match mv.target:
		"self":
			return [user]
		"ally":
			return [ally] if ally != null else []
		"userSide", "field":
			return []
		"both":
			return foes
		"foesAndAlly":
			var out := foes.duplicate()
			if ally != null:
				out.push_back(ally)
			return out
		"normal":
			if chosen != null:
				var t := at(chosen)
				if t.alive and t != user:
					return [t]
				if chosen.side == user.side:
					return []
			return [foes[rng.int_below(foes.size())]] if not foes.is_empty() else []
	return []

func _accuracy_check(user: Battler, target: Battler, mv: Dictionary) -> bool:
	if mv.acc == 0:
		return true
	if mv.target == "self" or mv.target == "ally":
		return true
	var acc: int = mv.acc
	if mv.id == "thunder":
		if weather == "rain":
			return true
		if weather == "sun":
			acc = 50
	var stage: int = clampi(user.stages.acc - target.stages.eva, -6, 6)
	var r: Array = ACC_RATIOS[stage + 6]
	var calc: int = (int(r[0]) * acc) / int(r[1])
	if user.ability == "compoundEyes":
		calc = (calc * 130) / 100
	if user.ability == "hustle" and DB.is_physical_type(mv.type):
		calc = (calc * 80) / 100
	return rng.int_below(100) + 1 <= calc

## Type effectiveness x10 (can be fractional, e.g. 2.5, like the TS).
func _type_effect10(mv: Dictionary, target: Battler) -> float:
	if mv.type == "Mystery":
		return 10.0
	var m := 10.0
	var seen: Array = []
	for t in target.types:
		if seen.has(t):
			continue
		seen.push_back(t)
		m = (m * DB.type_multiplier10(mv.type, t)) / 10.0
	return m

static func _unique(arr: Array) -> Array:
	var out: Array = []
	for x in arr:
		if not out.has(x):
			out.push_back(x)
	return out

const _PINCH := {"overgrow": "Grass", "blaze": "Fire", "torrent": "Water", "swarm": "Bug"}

## Gen 3 CalculateBaseDamage, including the +2.
func base_damage(att: Battler, def: Battler, power: int, type: String, crit: bool, spread_half: bool, apply_screens: bool = true) -> int:
	var physical := DB.is_physical_type(type) or type == "Mystery"
	var amon: Dictionary = att.mon
	var attack: int = att.stats.atk if physical else att.stats.spa
	var defense: int = def.stats.def if physical else def.stats.spd
	var ab: Variant = att.ability
	if ab == "hustle" and physical:
		attack = (attack * 150) / 100
	if def.ability == "thickFat" and (type == "Fire" or type == "Ice"):
		attack = attack / 2
	if ab == "guts" and amon.status and physical:
		attack = (attack * 150) / 100
	if ab != null and _PINCH.get(ab, "") == type and amon.hp <= int(att.stats.hp) / 3:
		power = (power * 150) / 100

	var atk_stage: int = att.stages.atk if physical else att.stages.spa
	var def_stage: int = def.stages.def if physical else def.stages.spd
	var damage: int = attack if crit and atk_stage <= 0 else _stat_mod(attack, atk_stage)
	damage = damage * power
	damage *= (2 * int(amon.level)) / 5 + 2
	var defense2: int = defense if crit and def_stage >= 0 else _stat_mod(defense, def_stage)
	defense = maxi(1, defense2)
	damage = damage / defense
	damage = damage / 50

	var ss: Dictionary = side_state[def.side]
	var alive_on_side := 0
	for x in battlers[def.side]:
		if x.alive:
			alive_on_side += 1
	var two_on_side := double and alive_on_side == 2
	if physical:
		if amon.status == "brn" and ab != "guts":
			damage = damage / 2
		if apply_screens and ss.reflect > 0 and not crit:
			damage = 2 * (damage / 3) if two_on_side else damage / 2
		if spread_half:
			damage = damage / 2
		if damage == 0:
			damage = 1
	else:
		if apply_screens and ss.lightScreen > 0 and not crit:
			damage = 2 * (damage / 3) if two_on_side else damage / 2
		if spread_half:
			damage = damage / 2
		if weather == "rain":
			if type == "Fire":
				damage = damage / 2
			if type == "Water":
				damage = (15 * damage) / 10
		if weather == "sun":
			if type == "Fire":
				damage = (15 * damage) / 10
			if type == "Water":
				damage = damage / 2
		if type == "Fire" and att.vol.flashFire:
			damage = (15 * damage) / 10
	return damage + 2

func _crit_check(user: Battler, target: Battler, mv: Dictionary) -> bool:
	if target.ability == "battleArmor":
		return false
	var stage := mini(4, (2 if user.vol.focusEnergy else 0) + (1 if mv.get("highCrit", false) else 0))
	return rng.random16() % int(CRIT_CHANCE[stage]) == 0

## Full damage pipeline for one target. Returns true if the move connected.
func _damaging_hit(user: Battler, target: Battler, mv: Dictionary, spread_half: bool) -> bool:
	var effect: Dictionary = mv.effect
	var eff := _type_effect10(mv, target)
	if eff == 0.0:
		_msg("It doesn't affect %s..." % name(target))
		return false
	if effect.kind == "brickBreak":
		var s: Dictionary = side_state[target.side]
		if s.reflect or s.lightScreen:
			s.reflect = 0
			s.lightScreen = 0
			_msg("It shattered the barrier!")

	var hits := 1
	if effect.kind == "multihit":
		var r := rng.random16() & 3
		hits = (rng.random16() & 3) + 2 if r > 1 else r + 2

	var total_dealt := 0
	var landed := 0
	var h := 0
	while h < hits and target.alive and user.alive:
		h += 1
		var dmg: int
		var crit := false
		if effect.kind == "fixed":
			dmg = user.mon.level if typeof(effect.amount) == TYPE_STRING and effect.amount == "level" else int(effect.amount)
		else:
			crit = _crit_check(user, target, mv)
			var power: int = mv.power
			if mv.id == "solarBeam" and weather != null and weather != "sun":
				power = power / 2
			dmg = base_damage(user, target, power, mv.type, crit, spread_half)
			dmg *= 2 if crit else 1
			if user.vol.helpingHand:
				dmg = (dmg * 15) / 10
			if user.types.has(mv.type):
				dmg = (dmg * 15) / 10
			for t in _unique(target.types):
				dmg = (dmg * DB.type_multiplier10(mv.type, t)) / 10
			var rand_pct := 100 - (rng.random16() % 16)
			dmg = (dmg * rand_pct) / 100
			if dmg == 0:
				dmg = 1
		if effect.kind == "falseSwipe" and dmg >= target.mon.hp:
			dmg = target.mon.hp - 1
		_emit({"t": "anim", "kind": "hit", "side": target.side, "slot": target.slot, "type": mv.type})
		var dealt := _apply_damage(target, dmg)
		total_dealt += dealt
		landed += 1
		if crit:
			_msg("A critical hit!")
		# Contact abilities.
		if mv.contact and dealt > 0:
			_contact_ability(user, target)
		# Thaw a frozen target with a Fire move.
		if mv.type == "Fire" and target.mon != null and target.mon.status == "frz" and target.alive:
			target.mon.status = null
			_status_event(target)
			_msg("%s was defrosted!" % name(target))
	if effect.kind != "fixed":
		if eff > 10.0:
			_msg("It's super effective!")
		elif eff < 10.0:
			_msg("It's not very effective...")
	if hits > 1:
		_msg("Hit %d time(s)!" % landed)

	# Drain / recoil.
	if effect.kind == "drain" and user.alive:
		var amt := maxi(1, total_dealt / 2)
		_heal(user, amt)
		_msg("%s had its energy drained!" % name(target))
	if (effect.kind == "recoil" or effect.kind == "struggle") and user.alive and user.ability != "rockHead":
		var div: int = effect.div if effect.kind == "recoil" else 4
		_apply_damage(user, maxi(1, total_dealt / div))
		_msg("%s is hit with recoil!" % name(user))

	# Secondary effects.
	if mv.get("chance", 0) and total_dealt > 0:
		_secondary(user, target, mv)

	_check_faint(target)
	_check_faint(user)
	return true

func _secondary(user: Battler, target: Battler, mv: Dictionary) -> void:
	var e: Dictionary = mv.effect
	var self_effect: bool = e.kind == "stat" and e.who == "self"
	if not self_effect and (not target.alive or target.ability == "shieldDust"):
		return
	if rng.int_below(100) >= int(mv.get("chance", 0)):
		return
	match e.kind:
		"status":
			_inflict(target, e.status, user, false)
		"confuse":
			_confuse(target, false)
		"flinch":
			if not _moved_this_turn.has(target) and target.ability != "innerFocus":
				target.vol.flinch = true
		"stat":
			_apply_stat_changes(user, user if e.who == "self" else target, e.stages, false)

func _status_move(user: Battler, target: Battler, mv: Dictionary) -> void:
	var e: Dictionary = mv.effect
	# Type immunity applies to status moves like Thunder Wave in Gen 3.
	if e.kind == "status" and mv.type == "Electric" and _type_effect10(mv, target) == 0.0:
		_msg("It doesn't affect %s..." % name(target))
		return
	match e.kind:
		"status":
			_inflict(target, e.status, user, true)
		"confuse":
			_confuse(target, true)
		"stat":
			_apply_stat_changes(user, user if e.who == "self" else target, e.stages, true)
		"leechSeed":
			if target.types.has("Grass") or target.vol.leechSeed != null:
				_msg("%s evaded the attack!" % name(target))
			else:
				target.vol.leechSeed = user.ref
				_msg("%s was seeded!" % name(target))
		_:
			_msg("But it failed!")

func _contact_ability(user: Battler, target: Battler) -> void:
	var umon: Variant = user.mon
	if umon == null or umon.hp <= 0 or umon.status:
		return
	var ab: Variant = target.ability
	if ab == "static" and rng.int_below(3) == 0:
		_inflict(user, "par", target, false, "%s's Static" % name(target))
	elif ab == "poisonPoint" and rng.int_below(3) == 0:
		_inflict(user, "psn", target, false, "%s's Poison Point" % name(target))
	elif ab == "effectSpore" and rng.int_below(10) == 0:
		var s: String = ["psn", "par", "slp"][rng.int_below(3)]
		_inflict(user, s, target, false, "%s's Effect Spore" % name(target))

## Reason string or null.
func _can_have_status(target: Battler, s: String) -> Variant:
	var types := target.types
	var ab: Variant = target.ability
	if s == "brn" and types.has("Fire"):
		return "type"
	if (s == "psn" or s == "tox") and (types.has("Poison") or types.has("Steel")):
		return "type"
	if s == "frz" and (types.has("Ice") or weather == "sun"):
		return "type"
	if s == "slp" and ab == "insomnia":
		return "Insomnia"
	if s == "par" and ab == "limber":
		return "Limber"
	return null

const _ALREADY := {"brn": "already burned", "par": "already paralyzed", "psn": "already poisoned", "tox": "already poisoned", "slp": "already asleep", "frz": "already frozen"}
const _STATUS_TEXT := {
	"brn": "was burned!", "par": "is paralyzed! It may be unable to move!", "psn": "was poisoned!",
	"tox": "is badly poisoned!", "slp": "fell asleep!", "frz": "was frozen solid!",
}
const _STATUS_VERB := {"brn": "burned", "par": "paralyzed", "psn": "poisoned", "tox": "badly poisoned", "slp": "put to sleep", "frz": "froze"}

## Tries to give a major status. `primary` = the move's main effect (failures are announced).
func _inflict(target: Battler, s: String, source: Battler, primary: bool, via: String = "") -> bool:
	var mon: Variant = target.mon
	if mon == null or mon.hp <= 0:
		return false
	if mon.status:
		if primary:
			_msg("%s is %s!" % [name(target), _ALREADY[s]] if mon.status == s or (s == "tox" and mon.status == "psn") else "But it failed!")
		return false
	var block: Variant = _can_have_status(target, s)
	if block != null:
		if primary:
			_msg("It doesn't affect %s..." % name(target) if block == "type" else "%s's %s prevents it!" % [name(target), block])
		return false
	mon.status = s
	if s == "slp":
		mon.sleepTurns = rng.int_below(4) + 2
	if s == "tox":
		mon.toxicCount = 0
	_status_event(target)
	_emit({"t": "anim", "kind": "status", "side": target.side, "slot": target.slot})
	_msg("%s %s %s!" % [via, _STATUS_VERB[s], name(target)] if via != "" else "%s %s" % [name(target), _STATUS_TEXT[s]])
	# Synchronize passes burn, paralysis and poison back.
	if source != null and source != target and target.ability == "synchronize" and (s == "brn" or s == "par" or s == "psn" or s == "tox"):
		if source.mon != null and not source.mon.status:
			_inflict(source, s, null, false, "%s's Synchronize" % name(target))
	return true

func _confuse(target: Battler, primary: bool) -> void:
	if not target.alive:
		return
	if target.vol.confusion > 0:
		if primary:
			_msg("%s is already confused!" % name(target))
		return
	if target.ability == "ownTempo":
		if primary:
			_msg("%s's Own Tempo prevents confusion!" % name(target))
		return
	target.vol.confusion = rng.int_below(4) + 2
	_emit({"t": "anim", "kind": "status", "side": target.side, "slot": target.slot})
	_msg("%s became confused!" % name(target))

func _apply_stat_changes(user: Battler, target: Battler, stages: Dictionary, primary: bool) -> void:
	if not target.alive:
		return
	for k in stages:
		var delta: int = stages[k]
		var by_foe := target != user and delta < 0
		if by_foe and target.ability == "clearBody":
			if primary:
				_msg("%s's Clear Body prevents stat loss!" % name(target))
			continue
		if by_foe and k == "acc" and target.ability == "keenEye":
			if primary:
				_msg("%s's Keen Eye prevents accuracy loss!" % name(target))
			continue
		var cur: int = target.stages[k]
		var nxt := clampi(cur + delta, -6, 6)
		if nxt == cur:
			if primary:
				_msg("%s's %s won't go %s!" % [name(target), STAT_NAMES[k], "higher" if delta > 0 else "lower"])
			continue
		target.stages[k] = nxt
		_emit({"t": "anim", "kind": "stat-up" if delta > 0 else "stat-down", "side": target.side, "slot": target.slot})
		var word: String
		if delta > 0:
			word = "sharply rose" if delta > 1 else "rose"
		else:
			word = "harshly fell" if delta < -1 else "fell"
		_msg("%s's %s %s!" % [name(target), STAT_NAMES[k], word])

func _set_weather(w: String) -> void:
	if weather == w:
		_msg("But it failed!")
		return
	weather = w
	weather_turns = 5
	_emit({"t": "weather", "weather": w})
	_msg({"rain": "It started to rain!", "sun": "The sunlight got bright!", "sand": "A sandstorm brewed!", "hail": "It started to hail!"}[w])

func _apply_damage(b: Battler, dmg: int) -> int:
	var mon: Dictionary = b.mon
	var dealt := mini(int(mon.hp), maxi(0, dmg))
	mon.hp -= dealt
	_hp_event(b)
	return dealt

func _heal(b: Battler, amt: int) -> void:
	var mon: Dictionary = b.mon
	mon.hp = mini(int(b.stats.hp), int(mon.hp) + maxi(1, amt))
	_emit({"t": "anim", "kind": "heal", "side": b.side, "slot": b.slot})
	_hp_event(b)

func _check_faint(b: Battler) -> void:
	if b.mon == null or b.mon.hp > 0:
		return
	if _has_same(_fainted, b.mon):
		return
	_fainted.push_back(b.mon)
	b.mon.status = null
	b.vol = _fresh_volatile()
	_emit({"t": "faint", "side": b.side, "slot": b.slot})
	_msg("%s fainted!" % name(b))
	if b.side == 1:
		_award_exp(b)

## Gen 3 EXP: floor(baseExp * level / 7), split between participants, x1.5 in trainer battles.
func _award_exp(fainted: Battler) -> void:
	var foe: Dictionary = fainted.mon
	var sp: Dictionary = DB.species(foe.species)
	var parts: Array = []
	for t in trainers[0]:
		for m in t.party:
			if fainted.participants.has(m.uid) and m.hp > 0:
				parts.push_back(m)
	if parts.is_empty():
		return
	var total: int = (int(sp.baseExp) * int(foe.level)) / 7
	for m in parts:
		var gain := maxi(1, total / parts.size())
		if kind == "trainer":
			gain = (gain * 150) / 100
		Creatures.add_evs(m, sp.evYield)
		if m.level >= 100:
			continue
		_msg("%s gained %d EXP. Points!" % [Creatures.display_name(m), gain])
		var ups := Creatures.gain_exp(m, gain)
		var active: Battler = null
		for b in battlers[0]:
			if is_same(b.mon, m):
				active = b
				break
		var owner: Variant = null
		for t in trainers[0]:
			if _has_same(t.party, m):
				owner = t
				break
		for up in ups:
			if active != null:
				active.stats = up.newStats
				_emit({"t": "exp", "side": 0, "slot": active.slot, "uid": m.uid, "expFrac": 1.0, "level": up.level - 1})
				var v := view(m)
				v.level = up.level
				v.expFrac = 0.0
				_emit({"t": "update", "side": 0, "slot": active.slot, "mon": v})
			_emit({"t": "levelUp", "uid": m.uid, "name": Creatures.display_name(m), "level": up.level, "old": up.oldStats, "now": up.newStats})
			_msg("%s grew to Lv. %d!" % [Creatures.display_name(m), up.level])
			for id in up.learned:
				_msg("%s learned %s!" % [Creatures.display_name(m), DB.move(id).name])
			for id in up.pending:
				_emit({"t": "learnPrompt", "uid": m.uid, "moveId": id, "player": owner.get("player", 0) if owner != null else 0})
		if active != null:
			_emit({"t": "exp", "side": 0, "slot": active.slot, "uid": m.uid, "expFrac": view(m).expFrac, "level": m.level})

# ---------- end of turn ----------
func _end_of_turn() -> void:
	for i in side_state.size():
		var s: Dictionary = side_state[i]
		var who := "Your team's" if i == 0 else "The foe team's"
		if s.reflect > 0:
			s.reflect -= 1
			if s.reflect == 0:
				_msg("%s Reflect wore off!" % who)
		if s.lightScreen > 0:
			s.lightScreen -= 1
			if s.lightScreen == 0:
				_msg("%s Light Screen wore off!" % who)
	if weather != null:
		weather_turns -= 1
		if weather_turns <= 0:
			_msg({"rain": "The rain stopped.", "sun": "The sunlight faded.", "sand": "The sandstorm subsided.", "hail": "The hail stopped."}[weather])
			weather = null
			_emit({"t": "weather", "weather": null})
		else:
			_msg({"rain": "Rain continues to fall.", "sun": "The sunlight is strong.", "sand": "The sandstorm rages.", "hail": "Hail continues to fall."}[weather])
			if weather == "sand" or weather == "hail":
				for b in _speed_order(all_battlers().filter(func(x: Battler) -> bool: return x.alive)):
					var immune: bool
					if weather == "sand":
						immune = b.types.has("Rock") or b.types.has("Ground") or b.types.has("Steel")
					else:
						immune = b.types.has("Ice")
					if immune:
						continue
					_apply_damage(b, maxi(1, int(b.stats.hp) / 16))
					_msg("%s is buffeted by the %s!" % [name(b), "sandstorm" if weather == "sand" else "hail"])
					_check_faint(b)
	for b in _speed_order(all_battlers().filter(func(x: Battler) -> bool: return x.alive)):
		var mon: Dictionary = b.mon
		if b.ability == "shedSkin" and mon.status and rng.int_below(3) == 0:
			mon.status = null
			_status_event(b)
			_msg("%s's Shed Skin cured its status!" % name(b))
		if b.vol.leechSeed != null and b.alive:
			var seeder := at(b.vol.leechSeed)
			var dmg := _apply_damage(b, maxi(1, int(b.stats.hp) / 8))
			if seeder.alive:
				_heal(seeder, dmg)
			_msg("%s's health is sapped by Leech Seed!" % name(b))
			_check_faint(b)
		if not b.alive:
			continue
		if mon.status == "psn":
			_apply_damage(b, maxi(1, int(b.stats.hp) / 8))
			_msg("%s is hurt by poison!" % name(b))
		elif mon.status == "tox":
			if mon.toxicCount < 15:
				mon.toxicCount += 1
			_apply_damage(b, maxi(1, int(b.stats.hp) / 16) * int(mon.toxicCount))
			_msg("%s is hurt by poison!" % name(b))
		elif mon.status == "brn":
			_apply_damage(b, maxi(1, int(b.stats.hp) / 8))
			_msg("%s is hurt by its burn!" % name(b))
		_check_faint(b)
	for b in all_battlers():
		b.vol.flinch = false
		b.vol.protect = false
		b.vol.helpingHand = false
		if not b.vol.protectedThisTurn:
			b.vol.protectStreak = 0
		b.vol.protectedThisTurn = false

# ---------- AI ----------
func _choose_ai(b: Battler) -> Dictionary:
	var mon: Dictionary = b.mon
	var usable: Array = []
	for i in mon.moves.size():
		if mon.moves[i].pp > 0:
			usable.push_back({"m": mon.moves[i], "i": i})
	if usable.is_empty():
		return {"kind": "move", "moveIdx": -1}
	var foes := foes_of(b)
	if (b.trainer != null and b.trainer.controller == "wild") or foes.is_empty():
		var pick: Dictionary = rng.pick(usable)
		var act := {"kind": "move", "moveIdx": pick.i}
		if not foes.is_empty():
			act.target = rng.pick(foes).ref
		return act
	# Trainer AI: estimate damage for each move/target, prefer KOs and super-effective hits.
	var best := {"score": -1.0, "idx": usable[0].i, "target": foes[0].ref}
	for u in usable:
		var mv: Dictionary = DB.move(u.m.id)
		var targets: Array = foes if mv.target == "normal" else [foes[0]]
		for t in targets:
			var score: float
			if mv.power > 0:
				var eff := _type_effect10(mv, t)
				if eff == 0.0 or (mv.type == "Ground" and t.ability == "levitate"):
					score = 0.0
				else:
					var est: float
					if mv.effect.kind == "fixed":
						est = float(mon.level if typeof(mv.effect.amount) == TYPE_STRING and mv.effect.amount == "level" else int(mv.effect.amount))
					else:
						est = (float(base_damage(b, t, mv.power, mv.type, false, false)) * (1.5 if b.types.has(mv.type) else 1.0) * eff) / 10.0 * 0.92
					var acc: float = 1.0 if mv.acc == 0 else float(mv.acc) / 100.0
					var thp: float = float(t.mon.hp)
					score = minf(est, thp) / maxf(1.0, thp) * 100.0 * acc
					if est >= thp:
						score += 40.0
					if mv.target == "both" and foes.size() > 1:
						score *= 1.3
					if mv.effect.kind == "recharge":
						score *= 0.7
			else:
				score = 15.0
				var e: Dictionary = mv.effect
				if e.kind == "status" and (t.mon.status or _can_have_status(t, e.status) != null):
					score = 0.0
				if e.kind == "status" and not t.mon.status:
					score = 35.0
				if e.kind == "stat" and e.who == "self":
					score = 20.0 if float(b.mon.hp) > float(b.stats.hp) / 2.0 else 2.0
				if e.kind == "confuse" and t.vol.confusion:
					score = 0.0
				if e.kind == "leechSeed" and (t.vol.leechSeed != null or t.types.has("Grass")):
					score = 0.0
				if e.kind == "heal" and float(b.mon.hp) < float(b.stats.hp) / 2.0:
					score = 50.0
				if e.kind == "weather" and weather != null:
					score = 0.0
			score += rng.int_below(20)
			if score > best.score:
				best = {"score": score, "idx": u.i, "target": t.ref}
	return {"kind": "move", "moveIdx": best.idx, "target": best.target}
