class_name Battle
extends RefCounted
## Battle engine following Generation 3 (Ruby/Sapphire/Emerald) rules.
## The engine resolves a whole turn at once and returns a list of events for the UI to play back.
##
## Plain data stays in Dictionaries with the TS keys:
##   TrainerInit {name, party, controller ("human"/"ai"/"wild"), slots, player?, otId?}; BTrainer = TrainerInit + side.
##   BattleInit {kind ("wild"/"trainer"/"safari"), double, sides: [[TrainerInit...], [TrainerInit...]], rng?, weather?, noExp?,
##     location? ("water"/"underwater"/"cave"), caughtSpecies? (Array, for Repeat Orbs)}
##   Ref {side, slot}
##   Action {kind: "move", moveIdx, target?} | {kind: "switch", partyIdx} | {kind: "item", itemId, partyIdx?, target?, moveIdx?}
##     | {kind: "run"} | {kind: "bait"} | {kind: "rock"} (Safari Zone)
##   MonView {uid, species, name, level, hp, maxHp, status, gender, shiny, expFrac}
##   BEvent {t: "msg", text} | {t: "switchIn", side, slot, mon} | {t: "switchOut", side, slot} | {t: "update", side, slot, mon}
##     | {t: "hp", side, slot, hp, maxHp} | {t: "status", side, slot, status} | {t: "faint", side, slot}
##     | {t: "anim", kind ("hit"/"stat-up"/"stat-down"/"status"/"heal"/"move"), side, slot, type?}
##     | {t: "ball", side, slot, shakes, caught} | {t: "exp", side, slot, uid, expFrac, level}
##     | {t: "levelUp", uid, name, level, old: Stats6, now: Stats6} | {t: "learnPrompt", uid, moveId, player}
##     | {t: "weather", weather} | {t: "semi", side, slot, hidden}
##   Request {ref, player, kind ("action"/"replace"), trainer}
## Creatures are compared by identity (is_same), like the TS object comparisons.
## Held items live in creature.item (an item id or null); consumed berries and herbs are used up for good, as in Gen 3.

static func _fresh_volatile() -> Dictionary:
	return {
		"confusion": 0, "flinch": false, "protect": false, "protectStreak": 0, "protectedThisTurn": false,
		"leechSeed": null, "focusEnergy": false, "recharge": false, "charging": null, "helpingHand": false, "flashFire": false,
		"substitute": 0, "trap": null, "cantEscape": false, "encore": null, "taunt": 0, "disable": null, "torment": false,
		"lastMove": -9, "attract": null, "destinyBond": false, "perish": 0, "lockOn": 0, "yawn": 0, "endure": false,
		"hitBy": null, "dmgPhys": 0, "dmgSpec": 0, "rampage": null, "semi": null, "ingrain": false, "choice": -1,
		"truant": false, "curse": false, "turnsOut": 0, "type": null, "abilityOverride": null, "critBoost": 0,
		"followMe": false, "mist": false, "moved": false,
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
	## Ability id or null (Skill Swap and Trace override it for the battle).
	var ability: Variant:
		get:
			if mon == null:
				return null
			return vol.abilityOverride if vol.abilityOverride != null else Creatures.ability_of(mon)
	## Held item id or null.
	var item: Variant:
		get: return mon.get("item", null) if mon != null else null
	var types: Array:
		get:
			if mon == null:
				return []
			return vol.type if vol.type != null else DB.species(mon.species).types

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
## Gen 3 Hidden Power type order.
const HP_TYPES := ["Fighting", "Flying", "Poison", "Ground", "Rock", "Bug", "Ghost", "Steel", "Fire", "Water", "Grass",
	"Electric", "Psychic", "Ice", "Dragon", "Dark"]
const TRAP_ABILITIES := ["shadowTag", "arenaTrap", "magnetPull"]
## Moves Metronome and Sleep Talk can't call.
const NO_CALL := ["metronome", "sleepTalk", "struggle", "counter", "mirrorCoat", "protect", "detect", "endure", "focusPunch",
	"thief", "covet", "trick", "followMe", "helpingHand", "destinyBond"]

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

## Gen 3 Hidden Power: {type, power} from the IVs.
static func hidden_power(c: Dictionary) -> Dictionary:
	var iv: Dictionary = c.ivs
	var order := ["hp", "atk", "def", "spe", "spa", "spd"]
	var t := 0
	var p := 0
	for i in 6:
		t += (int(iv[order[i]]) & 1) << i
		p += ((int(iv[order[i]]) >> 1) & 1) << i
	return {"type": HP_TYPES[(t * 15) / 63], "power": (p * 40) / 63 + 30}

var kind: String
var double: bool
var rng: Rng
## BTrainer[][] (each a copy of the TrainerInit with `side` added; party arrays are shared).
var trainers: Array = []
## Battler[][]
var battlers: Array = []
var side_state: Array = [_fresh_side(), _fresh_side()]
## null or "rain"/"sun"/"sand"/"hail".
var weather: Variant = null
## Turns left, or -1 for weather summoned by an ability (lasts until replaced, as in Gen 3).
var weather_turns: int = 0
## "choose" | "replace" | "over"
var phase: String = "choose"
## null | "win" | "lose" | "ran"
var result: Variant = null
var run_attempts: int = 0
var turn: int = 0
## Wild creatures caught this battle with the player index that caught them: [{mon, player}].
var caught: Array = []
## Money scattered by Pay Day.
var pay_day: int = 0
var no_exp := false
## "land" | "water" | "underwater" | "cave"
var location := "land"
var caught_species: Array = []
## Battle style SHIFT: after a foe trainer sends out a new creature, the player may switch too.
var shift_style := false
var _shift_offer: Array = []
## Safari Zone: catch and flee modifiers (x10).
var safari := {"catch": 10, "flee": 10}
var _events: Array = []
var _moved_this_turn: Array = []
var _fainted: Array = []
## PendingAction dicts {battler, mon, action, trainer}.
var _actions_this_turn: Array = []

static func _fresh_side() -> Dictionary:
	return {"reflect": 0, "lightScreen": 0, "mist": 0, "safeguard": 0, "spikes": 0, "wish": [null, null]}

func _init(init: Dictionary) -> void:
	kind = init.kind
	double = init.double
	var r: Variant = init.get("rng", null)
	rng = r if r != null else Rng.new()
	no_exp = init.get("noExp", false)
	location = init.get("location", "land")
	caught_species = init.get("caughtSpecies", [])
	shift_style = init.get("shift", false)
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
	var w: Variant = init.get("weather", null)
	if w != null:
		weather = w
		weather_turns = -1

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
	return "Wild %s" % n if kind != "trainer" else "Foe %s" % n

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

## Weather as it affects battle (Cloud Nine and Air Lock suppress it).
func eff_weather() -> Variant:
	if weather == null:
		return null
	for b in all_battlers():
		if b.alive and (b.ability == "cloudNine" or b.ability == "airLock"):
			return null
	return weather

func _item_name(id: String) -> String:
	return DB.item(id).name

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

## Eggs never battle.
static func can_battle(m: Dictionary) -> bool:
	return int(m.hp) > 0 and not m.get("egg", false)

func bench_for(t: Dictionary) -> Array:
	var active := _active_mons(t)
	var out: Array = []
	for i in t.party.size():
		var m: Dictionary = t.party[i]
		if can_battle(m) and not _has_same(active, m):
			out.push_back(i)
	return out

func _has_usable(t: Dictionary) -> bool:
	for m in t.party:
		if can_battle(m):
			return true
	return false

func _side_defeated(side: int) -> bool:
	if side == 1 and kind != "trainer":
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
func _send_out(b: Battler, mon: Dictionary, announce: bool, pass_from: Variant = null) -> void:
	b.mon = mon
	b.stats = Creatures.calc_stats(mon)
	b.stages = _fresh_stages()
	b.vol = _fresh_volatile()
	mon.toxicCount = 0
	if pass_from != null:
		# Baton Pass keeps stat stages and most volatile effects.
		b.stages = pass_from.stages
		for k in ["confusion", "focusEnergy", "leechSeed", "substitute", "curse", "perish", "cantEscape", "ingrain", "lockOn"]:
			b.vol[k] = pass_from.vol[k]
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
	# Spikes.
	var layers: int = side_state[b.side].spikes
	if layers > 0 and not b.types.has("Flying") and b.ability != "levitate":
		var dmg: int = maxi(1, int(b.stats.hp) / [8, 6, 4][layers - 1])
		_apply_damage(b, dmg)
		_msg("%s is hurt by spikes!" % name(b))
		_check_faint(b)

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
	# Anything trapped or infatuated by the leaving battler is freed.
	for o in all_battlers():
		if o.vol.trap != null and o.vol.trap.by == b.mon.uid:
			o.vol.trap = null
		if o.vol.attract == b.mon.uid:
			o.vol.attract = null
		if o.vol.cantEscape is int and o.vol.cantEscape == b.mon.uid:
			o.vol.cantEscape = false
	_emit({"t": "switchOut", "side": b.side, "slot": b.slot})
	b.mon = null

func _switch_in_abilities(list: Array) -> void:
	for b in _speed_order(list):
		if not b.alive:
			continue
		var ab: Variant = b.ability
		if ab == "intimidate":
			for f in foes_of(b):
				if f.ability == "clearBody" or f.ability == "whiteSmoke" or f.ability == "hyperCutter":
					_msg("%s's %s prevents stat loss!" % [name(f), DB.ABILITIES[f.ability].name])
					continue
				if f.vol.substitute > 0 or side_state[f.side].mist > 0:
					continue
				if f.stages.atk <= -6:
					continue
				f.stages.atk -= 1
				_emit({"t": "anim", "kind": "stat-down", "side": f.side, "slot": f.slot})
				_msg("%s's Intimidate cuts %s's Attack!" % [name(b), name(f)])
				_white_herb(f)
		elif ab == "drizzle" or ab == "drought" or ab == "sandStream":
			var w: String = {"drizzle": "rain", "drought": "sun", "sandStream": "sand"}[ab]
			if weather != w:
				weather = w
				weather_turns = -1
				_emit({"t": "weather", "weather": w})
				_msg("%s's %s %s" % [name(b), DB.ABILITIES[ab].name, {"rain": "made it rain!", "sun": "intensified the sun's rays!", "sand": "whipped up a sandstorm!"}[w]])
		elif ab == "trace":
			var foes := foes_of(b)
			if not foes.is_empty():
				var f: Battler = foes[rng.int_below(foes.size())]
				if f.ability != null and f.ability != "trace":
					b.vol.abilityOverride = f.ability
					_msg("%s traced %s's %s!" % [name(b), name(f), DB.ABILITIES[f.ability].name])
		elif ab == "cloudNine" or ab == "airLock":
			if weather != null:
				_msg("The effects of weather disappeared.")
		_forecast(b)

## Forecast changes the user's type with the weather.
func _forecast(b: Battler) -> void:
	if not b.alive or b.ability != "forecast":
		return
	var w: Variant = eff_weather()
	var t: Variant = {"rain": ["Water"], "sun": ["Fire"], "hail": ["Ice"]}.get(w if w != null else "", null)
	if t == null:
		t = DB.species(b.mon.species).types
	if b.types != t:
		b.vol.type = t
		_msg("%s transformed into the %s type!" % [name(b), t[0]])

## Sends out lead creatures. Call once before the first request.
func start() -> Array:
	_events = []
	if kind != "trainer":
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
	if weather != null:
		_emit({"t": "weather", "weather": weather})
		_msg({"rain": "It is raining.", "sun": "The sunlight is strong.", "sand": "A sandstorm is raging.", "hail": "Hail is falling."}[weather])
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
			elif b.alive and _shift_offer.has(b) and not bench_for(t).is_empty():
				out.push_back({"ref": b.ref, "player": t.get("player", 0), "kind": "shift", "trainer": t})
		elif b.alive and not _locked_in(b):
			out.push_back({"ref": b.ref, "player": t.get("player", 0), "kind": "action", "trainer": t})
	return out

## The battler acts without a choice this turn (recharging, charging, rampaging).
func _locked_in(b: Battler) -> bool:
	return b.vol.recharge or b.vol.charging != null or b.vol.rampage != null

## Whether a creature has any usable move (otherwise it must Struggle).
func has_usable_move(mon: Dictionary) -> bool:
	for m in mon.moves:
		if m.pp > 0:
			return true
	return false

## Whether a move slot can be picked right now (PP, Disable, Taunt, Torment, Encore, Choice Band).
func move_selectable(b: Battler, idx: int) -> String:
	var ms: Dictionary = b.mon.moves[idx]
	if ms.pp <= 0:
		return "There's no PP left for this move!"
	var mv: Dictionary = DB.move(ms.id)
	if b.vol.disable != null and b.vol.disable.moveIdx == idx:
		return "%s is disabled!" % mv.name
	if b.vol.taunt > 0 and mv.power == 0:
		return "%s can't use %s after the taunt!" % [Creatures.display_name(b.mon), mv.name]
	if b.vol.torment and b.vol.lastMove == idx:
		return "%s can't use the same move twice in a row due to the torment!" % Creatures.display_name(b.mon)
	if b.vol.encore != null and b.vol.encore.moveIdx != idx:
		return "%s must use %s!" % [Creatures.display_name(b.mon), DB.move(b.mon.moves[b.vol.encore.moveIdx].id).name]
	if b.vol.choice >= 0 and b.vol.choice != idx and b.item == "choiceBand":
		return "The Choice Band only allows one move!"
	return ""

## Whether the battler can switch out or flee (Mean Look, binding moves, trapping abilities, Ingrain).
func trapped(b: Battler) -> String:
	if b.item == "smokeBall" and kind != "trainer":
		return ""
	if b.vol.cantEscape or b.vol.trap != null:
		return "%s can't escape!" % name(b)
	if b.vol.ingrain:
		return "%s anchored itself with its roots!" % name(b)
	for f in foes_of(b):
		var ab: Variant = f.ability
		if ab == "shadowTag" or (ab == "arenaTrap" and not b.types.has("Flying") and b.ability != "levitate") \
				or (ab == "magnetPull" and b.types.has("Steel")):
			return "%s prevents escape with %s!" % [name(f), DB.ABILITIES[ab].name]
	return ""

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
			if r.kind == "shift":
				_withdraw(b)
			_send_out(b, r.trainer.party[a.partyIdx], true)
			ins.push_back(b)
		_shift_offer.clear()
		_switch_in_abilities(ins)
		phase = "choose"
		return _take_events()

	turn += 1
	var pending: Array = []
	for b in all_battlers():
		b.vol.moved = false
		b.vol.hitBy = null
		b.vol.dmgPhys = 0
		b.vol.dmgSpec = 0
		if not b.alive or b.trainer == null:
			continue
		var action: Variant = null
		if b.vol.recharge:
			action = {"kind": "move", "moveIdx": -2}
		elif b.vol.charging:
			action = {"kind": "move", "moveIdx": b.vol.charging.moveIdx, "target": b.vol.charging.target}
		elif b.vol.rampage != null:
			action = {"kind": "move", "moveIdx": b.vol.rampage.moveIdx, "target": b.vol.rampage.target}
		elif b.trainer.controller == "human":
			action = chosen.get("%d:%d" % [b.side, b.slot], null)
		elif kind == "safari":
			action = {"kind": "safariWatch"}
		else:
			action = _choose_ai(b)
		if action != null:
			if action.kind == "move" and b.vol.encore != null and action.moveIdx >= 0:
				action = action.duplicate()
				action.moveIdx = b.vol.encore.moveIdx
			pending.push_back({"battler": b, "mon": b.mon, "action": action, "trainer": b.trainer})

	var ordered := _order_actions(pending)
	_actions_this_turn = ordered
	_moved_this_turn.clear()
	# Focus Punch tightens its focus before anything moves.
	for p in ordered:
		if p.action.kind == "move" and _move_id_of(p.battler, p.action.moveIdx) == "focusPunch":
			_msg("%s is tightening its focus!" % name(p.battler))
	for p in ordered:
		if result != null:
			break
		if not is_same(p.battler.mon, p.mon) or not p.battler.alive:
			continue
		_execute(p)
		p.battler.vol.moved = true
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
	if shift_style and not ins.is_empty() and kind == "trainer" and not double:
		for b in battlers[0]:
			if b.alive and b.trainer != null and b.trainer.controller == "human" and not bench_for(b.trainer).is_empty():
				_shift_offer.push_back(b)
	if not _requests_for_replace().is_empty() or not _shift_offer.is_empty():
		phase = "replace"

func _requests_for_replace() -> Array:
	return battlers[0].filter(func(b: Battler) -> bool:
		return not b.alive and b.trainer != null and b.trainer.controller == "human" and not bench_for(b.trainer).is_empty())

func effective_speed(b: Battler) -> int:
	var s := _stat_mod(b.stats.spe, b.stages.spe)
	var w: Variant = eff_weather()
	if b.ability == "swiftSwim" and w == "rain":
		s *= 2
	if b.ability == "chlorophyll" and w == "sun":
		s *= 2
	if b.item == "machoBrace":
		s = s / 2
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
		# Quick Claw: a 20% chance to move first within its priority bracket.
		var claw := 1 if p.battler.item == "quickClaw" and rng.int_below(5) == 0 else 0
		keyed.push_back({"p": p, "k1": k1, "k2": k2, "c": claw, "s": effective_speed(p.battler), "r": rng.next_float()})
	keyed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.k1 != b.k1:
			return a.k1 > b.k1
		if a.k2 != b.k2:
			return a.k2 > b.k2
		if a.c != b.c:
			return a.c > b.c
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
			if not can_battle(mon):
				return
			_withdraw(b)
			_send_out(b, mon, true)
			_switch_in_abilities([b])
		"item":
			_do_item(p, action)
		"move":
			_do_move(b, action.moveIdx, action.get("target", null))
		"bait", "rock":
			_safari_action(b, action.kind)
		"safariWatch":
			_safari_watch(b)

# ---------- Safari Zone ----------
func _safari_action(b: Battler, what: String) -> void:
	var player_name: String = b.trainer.name
	var foes := foes_of(b)
	if foes.is_empty():
		return
	var f: Battler = foes[0]
	if what == "bait":
		_msg("%s threw some bait!" % player_name)
		_msg("%s is eating!" % name(f))
		safari.catch = maxi(3, safari.catch / 2)
		safari.flee = maxi(3, safari.flee / 2)
	else:
		_msg("%s threw a rock!" % player_name)
		_msg("%s is angry!" % name(f))
		safari.catch = mini(40, safari.catch * 2)
		safari.flee = mini(40, safari.flee * 2)

func _safari_watch(b: Battler) -> void:
	if not b.alive:
		return
	# Faster creatures flee more easily; rocks make them angry, bait calms them.
	var odds: int = (int(DB.species(b.mon.species).base.spe) * safari.flee) / 40 + 2
	if rng.int_below(100) < mini(60, odds):
		_msg("%s fled!" % name(b))
		_emit({"t": "switchOut", "side": b.side, "slot": b.slot})
		b.mon.hp = 0
		b.mon = null
		result = "ran"
		phase = "over"
	else:
		_msg("%s is watching carefully." % name(b))

func _do_run(b: Battler) -> void:
	if kind == "trainer":
		_msg("No! There's no running from a trainer battle!")
		return
	if b.item == "smokeBall":
		_msg("%s fled using its Smoke Ball!" % name(b))
		result = "ran"
		phase = "over"
		return
	var why := trapped(b)
	if why != "" and b.ability != "runAway":
		_msg("Can't escape!")
		return
	var foe_speed := 1
	for f in foes_of(b):
		foe_speed = maxi(foe_speed, f.stats.spe)
	var escaped := false
	if b.ability == "runAway" or kind == "safari":
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
		if target == null or not target.alive or kind == "trainer":
			_msg("It missed!")
			return
		_try_catch(target, _ball_mult10(it, target), p.trainer.get("player", 0), a.itemId)
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
	match eff.kind:
		"heal", "fullRestore":
			var mx := Creatures.max_hp(mon)
			var before: int = mon.hp
			mon.hp = mini(mx, int(mon.hp) + int(eff.get("amount", 9999)))
			if eff.kind == "fullRestore":
				mon.status = null
				mon.sleepTurns = 0
				if active != null:
					active.vol.confusion = 0
					_status_event(active)
			if active != null:
				_hp_event(active)
			_msg("%s's HP was restored by %d point(s)." % [Creatures.display_name(mon), mon.hp - before])
		"revive":
			if mon.hp > 0:
				_msg("But it had no effect.")
			else:
				mon.hp = Creatures.max_hp(mon) if eff.get("full", false) else Creatures.max_hp(mon) / 2
				mon.status = null
				for i in range(_fainted.size() - 1, -1, -1):
					if is_same(_fainted[i], mon):
						_fainted.remove_at(i)
				_msg("%s was revived!" % Creatures.display_name(mon))
		"cure":
			if mon.status and eff.statuses.has(mon.status):
				mon.status = null
				mon.sleepTurns = 0
				if active != null:
					_status_event(active)
				_msg("%s was cured!" % Creatures.display_name(mon))
			else:
				_msg("But it had no effect.")
		"pp":
			var idxs: Array = range(mon.moves.size()) if eff.get("all", false) else [int(a.get("moveIdx", 0))]
			for i in idxs:
				var ms: Dictionary = mon.moves[i]
				ms.pp = mini(int(ms.maxPp), int(ms.pp) + int(eff.amount))
			_msg("PP was restored.")
		"xStat":
			if active == null:
				_msg("But it had no effect.")
				return
			if eff.stat == "crit":
				active.vol.focusEnergy = true
				_msg("%s is getting pumped!" % name(active))
			elif eff.stat == "mist":
				side_state[active.side].mist = 5
				_msg("Your team became shrouded in mist!")
			else:
				_apply_stat_changes(active, active, {eff.stat: 1}, true)

## Ball multiplier x10, including the special Gen 3 orbs.
func _ball_mult10(it: Dictionary, target: Battler) -> int:
	var eff: Dictionary = it.effect
	var m: int = eff.mult10
	match eff.get("special", ""):
		"net":
			if target.types.has("Water") or target.types.has("Bug"):
				m = 30
		"dive":
			if location == "underwater" or location == "water":
				m = 35
		"nest":
			m = maxi(10, 40 - int(target.mon.level))
		"repeat":
			if caught_species.has(target.mon.species):
				m = 30
		"timer":
			m = mini(40, 10 + turn)
	if eff.get("safari", false):
		m = (m * safari.catch) / 10
	return m

## Gen 3 catch formula with four shake checks.
func _try_catch(b: Battler, ball_mult10: int, player: int, ball_id: String = "orb") -> void:
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
	_emit({"t": "ball", "side": b.side, "slot": b.slot, "shakes": 3 if is_caught else mini(shakes, 3), "caught": is_caught, "item": ball_id})
	if is_caught:
		_msg("Gotcha! %s was caught!" % Creatures.display_name(mon))
		mon.owner = player
		mon.ball = ball_id
		if ball_id == "luxuryOrb":
			mon.luxury = true
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
func _do_move(user: Battler, move_idx: int, chosen_target: Variant, called: Variant = null) -> void:
	var mon: Dictionary = user.mon
	# Recharge turn (Hyper Beam).
	if move_idx == -2:
		_msg("%s must recharge!" % name(user))
		user.vol.recharge = false
		return
	var move_id: Variant = called if called != null else _move_id_of(user, move_idx)
	if move_id == null:
		return
	var mv: Dictionary = DB.move(move_id)
	var effect: Dictionary = mv.effect
	var continuing_charge: bool = user.vol.charging != null and called == null
	var continuing_rampage: bool = user.vol.rampage != null and called == null

	if called == null:
		# Truant loafs around every other turn.
		if user.ability == "truant":
			user.vol.truant = not user.vol.truant
			if not user.vol.truant:
				_msg("%s is loafing around!" % name(user))
				return
		# Status checks, in the Gen 3 "attack canceler" order.
		if mon.status == "slp":
			mon.sleepTurns -= 2 if user.ability == "earlyBird" else 1
			if mon.sleepTurns > 0:
				_msg("%s is fast asleep." % name(user))
				user.vol.charging = null
				user.vol.rampage = null
				if effect.kind != "sleepTalk" and effect.kind != "snore":
					return
			else:
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
		if (effect.kind == "sleepTalk" or effect.kind == "snore") and mon.status != "slp":
			_msg("%s used %s!" % [name(user), mv.name])
			_msg("But it failed!")
			return
		if user.vol.flinch:
			_msg("%s flinched!" % name(user))
			user.vol.charging = null
			user.vol.rampage = null
			return
		if user.vol.disable != null and user.vol.disable.moveIdx == move_idx:
			_msg("%s's %s is disabled!" % [name(user), mv.name])
			return
		if user.vol.taunt > 0 and mv.power == 0 and called == null:
			_msg("%s can't use %s after the taunt!" % [name(user), mv.name])
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
					user.vol.rampage = null
					_check_faint(user)
					return
		if user.vol.attract != null:
			var lover: Variant = null
			for f in foes_of(user):
				if f.mon.uid == user.vol.attract:
					lover = f
			if lover == null:
				user.vol.attract = null
			else:
				_msg("%s is in love with %s!" % [name(user), name(lover)])
				if rng.int_below(2) == 0:
					_msg("%s is immobilized by love!" % name(user))
					return
		if mon.status == "par" and rng.int_below(4) == 0:
			_msg("%s is paralyzed! It can't move!" % name(user))
			user.vol.charging = null
			user.vol.rampage = null
			return
		if effect.kind == "focusPunch" and (user.vol.dmgPhys > 0 or user.vol.dmgSpec > 0):
			_msg("%s lost its focus and couldn't move!" % name(user))
			return

	# Targets.
	var targets := _resolve_targets(user, mv, chosen_target)

	# PP (Pressure costs one extra per Pressure foe targeted).
	if called == null and not continuing_charge and not continuing_rampage and move_idx >= 0:
		var slot: Dictionary = mon.moves[move_idx]
		var cost := 1
		for t in targets:
			if t.side != user.side and t.ability == "pressure":
				cost += 1
		slot.pp = maxi(0, int(slot.pp) - cost)
		user.vol.lastMove = move_idx
		if user.item == "choiceBand":
			user.vol.choice = move_idx
		if slot.pp == 0:
			_leppa(user, move_idx)

	if move_id == "struggle":
		_msg("%s has no moves left!" % name(user))
	if not continuing_charge or effect.kind != "twoTurn":
		_msg("%s used %s!" % [name(user), mv.name])
	_emit({"t": "anim", "kind": "move", "side": user.side, "slot": user.slot, "type": mv.type})

	# Two-turn moves.
	if effect.kind == "charge" and not continuing_charge and eff_weather() != "sun":
		_msg("%s took in sunlight!" % name(user))
		user.vol.charging = {"moveIdx": move_idx, "target": chosen_target}
		return
	if effect.kind == "twoTurn":
		if not continuing_charge:
			_msg("%s %s" % [name(user), effect.get("text", "is charging!")])
			user.vol.charging = {"moveIdx": move_idx, "target": chosen_target}
			if effect.has("semi"):
				user.vol.semi = effect.semi
				_emit({"t": "semi", "side": user.side, "slot": user.slot, "hidden": true})
			if effect.has("chargeStat"):
				_apply_stat_changes(user, user, effect.chargeStat, false)
			return
		_msg("%s used %s!" % [name(user), mv.name])
		if user.vol.semi != null:
			user.vol.semi = null
			_emit({"t": "semi", "side": user.side, "slot": user.slot, "hidden": false})
	user.vol.charging = null

	# Rampage moves (Thrash, Outrage, Petal Dance) lock in for 2-3 turns, then confuse.
	if effect.kind == "rampage":
		if user.vol.rampage == null:
			user.vol.rampage = {"moveIdx": move_idx, "target": chosen_target, "turns": 1 + rng.int_below(2)}
		else:
			user.vol.rampage.turns -= 1
			if user.vol.rampage.turns <= 0:
				user.vol.rampage = null
				_confuse(user, false, true)

	if _field_move(user, mv, effect, targets):
		return

	if mv.target == "self":
		if effect.kind == "stat":
			_apply_stat_changes(user, user, effect.stages, true)
		return

	if targets.is_empty():
		_msg("But there was no target...")
		return

	if (effect.kind == "explode") and _damp_blocks(user):
		return

	var alive_on_foe_side := 0
	for x in battlers[1 - user.side]:
		if x.alive:
			alive_on_foe_side += 1
	var spread_half: bool = (mv.target == "both" or mv.target == "foesAndAlly") and double and targets.size() > 1
	var any_hit := false
	var explode_done := false

	for target in targets:
		if not target.alive:
			continue
		if target.vol.protect and mv.protectable and target != user:
			_msg("%s protected itself!" % name(target))
			continue
		if not _semi_hits(mv, target):
			_msg("%s's attack missed!" % name(user))
			continue
		if mv.get("sound", false) and target.ability == "soundproof" and target != user:
			_msg("%s's Soundproof blocks %s!" % [name(target), mv.name])
			continue
		# Ability-based immunities.
		var mtype := _move_type(user, mv)
		if mtype == "Ground" and mv.power > 0 and target.ability == "levitate":
			_msg("%s makes Ground moves miss with Levitate!" % name(target))
			continue
		if mv.power > 0 and ((mtype == "Electric" and target.ability == "voltAbsorb") or (mtype == "Water" and target.ability == "waterAbsorb")):
			var ab_name: String = DB.ABILITIES[target.ability].name
			if target.mon.hp >= target.stats.hp:
				_msg("%s's %s made %s useless!" % [name(target), ab_name, mv.name])
			else:
				_heal(target, target.stats.hp / 4)
				_msg("%s restored HP using its %s!" % [name(target), ab_name])
			continue
		if mtype == "Fire" and target.ability == "flashFire" and target.mon.status != "frz" and (mv.power > 0 or effect.kind == "status"):
			target.vol.flashFire = true
			_msg("%s's Flash Fire raised its Fire power!" % name(target))
			continue
		# Accuracy.
		if effect.kind == "ohko":
			if target.ability == "sturdy":
				_msg("%s was protected by Sturdy!" % name(target))
				continue
			if int(target.mon.level) > int(mon.level) or (rng.int_below(100) >= int(mon.level) - int(target.mon.level) + 30 and user.vol.lockOn <= 0):
				_msg("%s's attack missed!" % name(user))
				continue
		elif not _accuracy_check(user, target, mv):
			_msg("%s's attack missed!" % name(user))
			if effect.kind == "crash":
				var would: int = mini(int(target.mon.hp), base_damage(user, target, mv.power, mtype, false, false)) / 2
				if would > 0:
					_msg("%s kept going and crashed!" % name(user))
					_apply_damage(user, maxi(1, would))
					_check_faint(user)
			continue
		if mv.power > 0:
			if _damaging_hit(user, target, mv, spread_half):
				any_hit = true
		else:
			_status_move(user, target, mv)
			any_hit = true
		if effect.kind == "explode" and not explode_done:
			explode_done = true

	if effect.kind == "explode" and user.alive:
		_apply_damage(user, int(user.mon.hp))
		_check_faint(user)
	if any_hit and effect.kind == "recharge":
		user.vol.recharge = true
	user.vol.helpingHand = false
	if user.vol.lockOn > 0 and mv.power > 0:
		user.vol.lockOn = 0

## Type of a move for this user (Hidden Power and Weather Ball change it).
func _move_type(user: Battler, mv: Dictionary) -> String:
	var k: String = mv.effect.kind
	if k == "hiddenPower" and user.mon != null:
		return hidden_power(user.mon).type
	if k == "weatherBall":
		var w: Variant = eff_weather()
		if w != null:
			return {"rain": "Water", "sun": "Fire", "hail": "Ice", "sand": "Rock"}[w]
	return mv.type

## Semi-invulnerable targets (Fly, Dig, Dive) can only be hit by a few moves.
func _semi_hits(mv: Dictionary, target: Battler) -> bool:
	var semi: Variant = target.vol.semi
	if semi == null:
		return true
	match semi:
		"fly":
			return mv.id in ["gust", "twister", "thunder", "skyUppercut"]
		"dig":
			return mv.id in ["earthquake", "magnitude", "fissure"]
		"dive":
			return mv.id in ["surf", "whirlpool"]
	return true

func _damp_blocks(user: Battler) -> bool:
	for b in all_battlers():
		if b.alive and b.ability == "damp":
			_msg("%s's Damp prevents %s from using it!" % [name(b), name(user)])
			return true
	return false

## Moves that don't hit a battler. Returns true when the move was fully handled.
func _field_move(user: Battler, mv: Dictionary, effect: Dictionary, _targets: Array) -> bool:
	var mon: Dictionary = user.mon
	match effect.kind:
		"weather":
			_set_weather(effect.weather)
		"screen":
			var s: Dictionary = side_state[user.side]
			var key: String = effect.screen
			if s[key] > 0:
				_msg("But it failed!")
				return true
			s[key] = 5
			var team := "your team's" if user.side == 0 else "the foe team's"
			_msg("Reflect raised %s Defense!" % team if key == "reflect" else "Light Screen raised %s Sp. Def!" % team)
		"mist":
			var s: Dictionary = side_state[user.side]
			if s.mist > 0:
				_msg("But it failed!")
				return true
			s.mist = 5
			_msg("%s's team became shrouded in mist!" % name(user))
		"safeguard":
			var s: Dictionary = side_state[user.side]
			if s.safeguard > 0:
				_msg("But it failed!")
				return true
			s.safeguard = 5
			_msg("%s's team became cloaked in a mystical veil!" % name(user))
		"spikes":
			var s: Dictionary = side_state[1 - user.side]
			if s.spikes >= 3:
				_msg("But it failed!")
				return true
			s.spikes += 1
			_msg("Spikes were scattered all around the opposing team's feet!")
		"haze":
			for b in all_battlers():
				b.stages = _fresh_stages()
			_msg("All stat changes were eliminated!")
		"perishSong":
			for b in all_battlers():
				if b.alive and b.vol.perish == 0 and b.ability != "soundproof":
					b.vol.perish = 4
			_msg("All creatures hearing the song will faint in three turns!")
		"healBell":
			for m in user.trainer.party if user.trainer != null else [mon]:
				m.status = null
				m.sleepTurns = 0
			for b in battlers[user.side]:
				_status_event(b)
			_msg("A bell chimed!" if mv.id == "healBell" else "A soothing aroma wafted through the area!")
		"protect", "endure":
			var others := 0
			for p in _actions_this_turn:
				if not _moved_this_turn.has(p.battler) and p.battler != user:
					others += 1
			var is_last := others == 0
			var rate: int = PROTECT_RATES[mini(user.vol.protectStreak, 3)]
			if not is_last and rng.random16() <= rate:
				user.vol.protectedThisTurn = true
				user.vol.protectStreak += 1
				if effect.kind == "protect":
					user.vol.protect = true
					_msg("%s protected itself!" % name(user))
				else:
					user.vol.endure = true
					_msg("%s braced itself!" % name(user))
			else:
				user.vol.protectStreak = 0
				_msg("But it failed!")
		"helpingHand":
			var ally := ally_of(user)
			if ally == null or _moved_this_turn.has(ally):
				_msg("But it failed!")
				return true
			ally.vol.helpingHand = true
			_msg("%s is ready to help %s!" % [name(user), name(ally)])
		"followMe":
			if not double:
				_msg("But it failed!")
				return true
			user.vol.followMe = true
			_msg("%s became the center of attention!" % name(user))
		"focusEnergy":
			if user.vol.focusEnergy:
				_msg("But it failed!")
				return true
			user.vol.focusEnergy = true
			_msg("%s is getting pumped!" % name(user))
		"rest":
			if mon.hp >= user.stats.hp or user.ability == "insomnia" or user.ability == "vitalSpirit":
				_msg("But it failed!")
				return true
			mon.status = "slp"
			mon.sleepTurns = 3
			mon.hp = user.stats.hp
			_status_event(user)
			_hp_event(user)
			_msg("%s slept and became healthy!" % name(user))
		"heal":
			if mon.hp >= user.stats.hp:
				_msg("%s's HP is full!" % name(user))
				return true
			var amt: int = user.stats.hp / 2
			var w: Variant = eff_weather()
			if effect.get("weatherScaled", false) and w == "sun":
				amt = (int(user.stats.hp) * 20) / 30
			elif effect.get("weatherScaled", false) and w != null:
				amt = user.stats.hp / 4
			_heal(user, amt)
			_msg("%s regained health!" % name(user))
		"substitute":
			if user.vol.substitute > 0:
				_msg("%s already has a substitute!" % name(user))
				return true
			var cost: int = int(user.stats.hp) / 4
			if int(mon.hp) <= cost or cost == 0:
				_msg("It was too weak to make a substitute!")
				return true
			_apply_damage(user, cost)
			user.vol.substitute = cost
			_msg("%s made a substitute!" % name(user))
		"bellyDrum":
			var cost: int = int(user.stats.hp) / 2
			if int(mon.hp) <= cost or user.stages.atk >= 6:
				_msg("But it failed!")
				return true
			_apply_damage(user, cost)
			user.stages.atk = 6
			_emit({"t": "anim", "kind": "stat-up", "side": user.side, "slot": user.slot})
			_msg("%s cut its own HP and maximized Attack!" % name(user))
		"curse":
			if user.types.has("Ghost"):
				var foes := foes_of(user)
				if foes.is_empty() or foes[0].vol.curse:
					_msg("But it failed!")
					return true
				var f: Battler = _targets[0] if not _targets.is_empty() and _targets[0].side != user.side else foes[0]
				_apply_damage(user, maxi(1, int(user.stats.hp) / 2))
				f.vol.curse = true
				_msg("%s cut its own HP and laid a curse on %s!" % [name(user), name(f)])
				_check_faint(user)
			else:
				_apply_stat_changes(user, user, {"spe": -1, "atk": 1, "def": 1}, true)
		"batonPass":
			if user.trainer == null or bench_for(user.trainer).is_empty():
				_msg("But it failed!")
				return true
			var bench := bench_for(user.trainer)
			var pick: int = bench[0]
			if user.trainer.controller == "human":
				# The UI asks for the replacement afterwards; pick the first healthy one here.
				pick = bench[0]
			var old := Battler.new(user.side, user.slot, user.trainer)
			old.stages = user.stages.duplicate()
			old.vol = user.vol.duplicate()
			_withdraw(user)
			_send_out(user, user.trainer.party[pick], true, old)
			_switch_in_abilities([user])
		"teleport":
			if kind == "trainer":
				_msg("But it failed!")
				return true
			_msg("%s fled from battle!" % name(user))
			result = "ran"
			phase = "over"
		"wish":
			var s: Dictionary = side_state[user.side]
			if s.wish[user.slot] != null:
				_msg("But it failed!")
				return true
			s.wish[user.slot] = {"turns": 2, "hp": int(user.stats.hp) / 2, "from": name(user)}
		"ingrain":
			if user.vol.ingrain:
				_msg("But it failed!")
				return true
			user.vol.ingrain = true
			_msg("%s planted its roots!" % name(user))
		"refresh":
			if mon.status in ["psn", "tox", "par", "brn"]:
				mon.status = null
				_status_event(user)
				_msg("%s's status returned to normal!" % name(user))
			else:
				_msg("But it failed!")
		"splash":
			_msg("But nothing happened!")
		"metronome":
			var pool: Array = DB.MOVES.keys().filter(func(k: String) -> bool: return not NO_CALL.has(k))
			var pick: String = pool[rng.int_below(pool.size())]
			_msg("Waggling a finger let it use %s!" % DB.move(pick).name)
			_do_move(user, -3, null, pick)
		"sleepTalk":
			var opts: Array = []
			for ms in mon.moves:
				if not NO_CALL.has(ms.id) and DB.move(ms.id).effect.kind not in ["twoTurn", "charge"]:
					opts.push_back(ms.id)
			if opts.is_empty():
				_msg("But it failed!")
				return true
			_do_move(user, -3, null, opts[rng.int_below(opts.size())])
		"destinyBond":
			user.vol.destinyBond = true
			_msg("%s is trying to take its foe down with it!" % name(user))
		_:
			return false
	return true

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
			# Follow Me and Lightning Rod draw single-target moves in doubles.
			if double and chosen != null and chosen.side != user.side:
				for f in foes:
					if f.vol.followMe:
						return [f]
				if _move_type(user, mv) == "Electric":
					for f in foes:
						if f.ability == "lightningRod":
							return [f]
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
	if user.vol.lockOn > 0:
		return true
	var acc: int = mv.acc
	var w: Variant = eff_weather()
	if mv.id == "thunder":
		if w == "rain":
			return true
		if w == "sun":
			acc = 50
	var stage: int = clampi(user.stages.acc - target.stages.eva, -6, 6)
	var r: Array = ACC_RATIOS[stage + 6]
	var calc: int = (int(r[0]) * acc) / int(r[1])
	if user.ability == "compoundEyes":
		calc = (calc * 130) / 100
	if target.ability == "sandVeil" and w == "sand":
		calc = (calc * 80) / 100
	if user.ability == "hustle" and DB.is_physical_type(mv.type):
		calc = (calc * 80) / 100
	if target.item == "brightPowder":
		calc = (calc * 90) / 100
	return rng.int_below(100) + 1 <= calc

## Type effectiveness x10 (can be fractional, e.g. 2.5, like the TS).
func _type_effect10(mv: Dictionary, target: Battler, mtype: String = "") -> float:
	var t0: String = mtype if mtype != "" else mv.type
	if t0 == "Mystery":
		return 10.0
	var m := 10.0
	var seen: Array = []
	for t in target.types:
		if seen.has(t):
			continue
		seen.push_back(t)
		m = (m * DB.type_multiplier10(t0, t)) / 10.0
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
	if physical and (ab == "hugePower" or ab == "purePower"):
		attack *= 2
	# Held items that boost a stat or a type (10% in Gen 3).
	var it: Variant = att.item
	if it != null and type != "Mystery":
		var boost: Variant = DB.item(it).effect.get("boost", null)
		if boost == type:
			attack = (attack * 110) / 100
		if it == "choiceBand" and physical:
			attack = (attack * 150) / 100
	if ab == "hustle" and physical:
		attack = (attack * 150) / 100
	if not physical and (ab == "plus" or ab == "minus"):
		var ally := ally_of(att)
		if ally != null and ally.ability == ("minus" if ab == "plus" else "plus"):
			attack = (attack * 150) / 100
	if def.ability == "thickFat" and (type == "Fire" or type == "Ice"):
		attack = attack / 2
	if ab == "guts" and amon.status and physical:
		attack = (attack * 150) / 100
	if physical and def.ability == "marvelScale" and def.mon.status:
		defense = (defense * 150) / 100
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
	var w: Variant = eff_weather()
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
		if w == "rain":
			if type == "Fire":
				damage = damage / 2
			if type == "Water":
				damage = (15 * damage) / 10
		if w == "sun":
			if type == "Fire":
				damage = (15 * damage) / 10
			if type == "Water":
				damage = damage / 2
		if type == "Fire" and att.vol.flashFire:
			damage = (15 * damage) / 10
	return damage + 2

func _crit_check(user: Battler, target: Battler, mv: Dictionary) -> bool:
	if target.ability == "battleArmor" or target.ability == "shellArmor":
		return false
	var stage := (2 if user.vol.focusEnergy else 0) + (1 if mv.get("highCrit", false) else 0)
	if user.item == "scopeLens":
		stage += 1
	return rng.random16() % int(CRIT_CHANCE[mini(4, stage)]) == 0

## Base power for moves whose power depends on the situation.
func _power_of(user: Battler, target: Battler, mv: Dictionary) -> int:
	var p: int = mv.power
	var e: Dictionary = mv.effect
	var mon: Dictionary = user.mon
	match e.kind:
		"hiddenPower":
			p = hidden_power(mon).power
		"weatherBall":
			if eff_weather() != null:
				p = 100
		"return":
			p = maxi(1, (int(mon.get("friendship", 70)) * 10) / 25)
		"frustration":
			p = maxi(1, ((255 - int(mon.get("friendship", 70))) * 10) / 25)
		"reversal":
			var n: int = (48 * int(mon.hp)) / maxi(1, int(user.stats.hp))
			p = 200 if n <= 1 else (150 if n <= 4 else (100 if n <= 9 else (80 if n <= 16 else (40 if n <= 32 else 20))))
		"eruption":
			p = maxi(1, (150 * int(mon.hp)) / maxi(1, int(user.stats.hp)))
		"facade":
			if mon.status in ["brn", "par", "psn", "tox"]:
				p *= 2
		"smellingSalt":
			if target.mon.status == "par":
				p *= 2
		"revenge":
			if user.vol.hitBy != null:
				p *= 2
		"magnitude":
			var r := rng.int_below(100)
			var table := [[5, 4, 10], [15, 5, 30], [35, 6, 50], [65, 7, 70], [85, 8, 90], [95, 9, 110], [100, 10, 150]]
			for row in table:
				if r < row[0]:
					p = row[2]
					_msg("Magnitude %d!" % row[1])
					break
	if target.vol.semi == "dig" and mv.id in ["earthquake", "magnitude"]:
		p *= 2
	if target.vol.semi == "dive" and mv.id in ["surf", "whirlpool"]:
		p *= 2
	if target.vol.semi == "fly" and mv.id in ["gust", "twister"]:
		p *= 2
	return p

## Full damage pipeline for one target. Returns true if the move connected.
func _damaging_hit(user: Battler, target: Battler, mv: Dictionary, spread_half: bool) -> bool:
	var effect: Dictionary = mv.effect
	var mtype := _move_type(user, mv)
	var eff := _type_effect10(mv, target, mtype)
	if effect.kind == "dreamEater" or (effect.kind == "drain" and effect.get("sleeping", false)):
		if target.mon.status != "slp" or target.vol.substitute > 0:
			_msg("%s wasn't affected!" % name(target))
			return false
	if effect.kind == "fakeOut" and user.vol.turnsOut > 0:
		_msg("But it failed!")
		return false
	if eff == 0.0:
		_msg("It doesn't affect %s..." % name(target))
		return false
	if target.ability == "wonderGuard" and eff <= 10.0 and mtype != "Mystery" and effect.kind != "fixed":
		_msg("%s avoided damage with Wonder Guard!" % name(target))
		return false
	if effect.kind == "brickBreak":
		var s: Dictionary = side_state[target.side]
		if s.reflect or s.lightScreen:
			s.reflect = 0
			s.lightScreen = 0
			_msg("It shattered the barrier!")

	var hits := 1
	if effect.kind == "multihit":
		if effect.has("hits"):
			hits = int(effect.hits)
		else:
			var r := rng.random16() & 3
			hits = (rng.random16() & 3) + 2 if r > 1 else r + 2

	var total_dealt := 0
	var landed := 0
	var h := 0
	var subbed := false
	while h < hits and target.alive and user.alive:
		h += 1
		var dmg: int
		var crit := false
		match effect.kind:
			"fixed":
				dmg = user.mon.level if typeof(effect.amount) == TYPE_STRING and effect.amount == "level" else int(effect.amount)
			"superFang":
				dmg = maxi(1, int(target.mon.hp) / 2)
			"endeavor":
				dmg = maxi(0, int(target.mon.hp) - int(user.mon.hp))
				if dmg == 0:
					_msg("But it failed!")
					return false
			"ohko":
				dmg = int(target.mon.hp)
			"counter":
				var got: int = user.vol.dmgPhys if effect.physical else user.vol.dmgSpec
				if got <= 0 or user.vol.hitBy == null or user.vol.hitBy.side == user.side:
					_msg("But it failed!")
					return false
				dmg = got * 2
			_:
				crit = _crit_check(user, target, mv)
				var power: int = _power_of(user, target, mv)
				if mv.id == "solarBeam" and eff_weather() != null and eff_weather() != "sun":
					power = power / 2
				dmg = base_damage(user, target, power, mtype, crit, spread_half)
				dmg *= 2 if crit else 1
				if user.vol.helpingHand:
					dmg = (dmg * 15) / 10
				if user.types.has(mtype):
					dmg = (dmg * 15) / 10
				for t in _unique(target.types):
					dmg = (dmg * DB.type_multiplier10(mtype, t)) / 10
				var rand_pct := 100 - (rng.random16() % 16)
				dmg = (dmg * rand_pct) / 100
				if dmg == 0:
					dmg = 1
		if effect.kind == "falseSwipe" and dmg >= target.mon.hp:
			dmg = target.mon.hp - 1
		_emit({"t": "anim", "kind": "hit", "side": target.side, "slot": target.slot, "type": mtype})
		# A substitute takes the hit instead.
		if target.vol.substitute > 0 and effect.kind != "fixed" or (target.vol.substitute > 0 and effect.kind == "fixed"):
			if target.vol.substitute > 0 and target != user:
				var taken: int = mini(dmg, int(target.vol.substitute))
				target.vol.substitute -= taken
				total_dealt += taken
				landed += 1
				subbed = true
				_msg("The substitute took damage for %s!" % name(target))
				if target.vol.substitute <= 0:
					target.vol.substitute = 0
					_msg("%s's substitute faded!" % name(target))
				if crit:
					_msg("A critical hit!")
				continue
		# Endure, Focus Band and Sturdy-free survival.
		if dmg >= int(target.mon.hp):
			if target.vol.endure:
				dmg = int(target.mon.hp) - 1
				_msg("%s endured the hit!" % name(target))
			elif target.item == "focusBand" and rng.int_below(10) == 0:
				dmg = int(target.mon.hp) - 1
				_msg("%s hung on using its Focus Band!" % name(target))
		var dealt := _apply_damage(target, dmg)
		total_dealt += dealt
		landed += 1
		target.vol.hitBy = user.ref
		if DB.is_physical_type(mtype) or mtype == "Mystery":
			target.vol.dmgPhys += dealt
		else:
			target.vol.dmgSpec += dealt
		if target.vol.rampage == null and target.vol.charging == null:
			pass
		if crit:
			_msg("A critical hit!")
		# Contact abilities.
		if mv.contact and dealt > 0:
			_contact_ability(user, target)
		# Thaw a frozen target with a Fire move.
		if mtype == "Fire" and target.mon != null and target.mon.status == "frz" and target.alive:
			target.mon.status = null
			_status_event(target)
			_msg("%s was defrosted!" % name(target))
		# Color Change.
		if target.alive and target.ability == "colorChange" and not target.types.has(mtype) and mtype != "Mystery":
			target.vol.type = [mtype]
			_msg("%s's Color Change made it the %s type!" % [name(target), mtype])
		_hp_berry(target)
	if effect.kind not in ["fixed", "superFang", "endeavor", "counter", "ohko"]:
		if eff > 10.0:
			_msg("It's super effective!")
		elif eff < 10.0:
			_msg("It's not very effective...")
	if effect.kind == "ohko" and not target.alive:
		_msg("It's a one-hit KO!")
	if hits > 1:
		_msg("Hit %d time(s)!" % landed)

	# Drain / recoil.
	if (effect.kind == "drain" or effect.kind == "dreamEater") and user.alive and total_dealt > 0:
		var amt := maxi(1, total_dealt / 2)
		if target.ability == "liquidOoze":
			_apply_damage(user, amt)
			_msg("%s sucked up the liquid ooze!" % name(user))
			_check_faint(user)
		else:
			_heal(user, amt)
			_msg("%s had its energy drained!" % name(target))
	if (effect.kind == "recoil" or effect.kind == "struggle") and user.alive and user.ability != "rockHead":
		var div: int = effect.div if effect.kind == "recoil" else 4
		_apply_damage(user, maxi(1, total_dealt / div))
		_msg("%s is hit with recoil!" % name(user))
	# Shell Bell.
	if user.alive and user.item == "shellBell" and total_dealt > 0 and user.mon.hp < user.stats.hp:
		_heal(user, maxi(1, total_dealt / 8))
		_msg("%s restored a little HP using its Shell Bell!" % name(user))

	if total_dealt > 0 and not subbed:
		_after_hit_effects(user, target, mv, effect)

	# Secondary effects.
	if mv.get("chance", 0) and total_dealt > 0 and not subbed:
		_secondary(user, target, mv)
	elif mv.get("chance", 0) and total_dealt > 0 and subbed:
		var se: Dictionary = mv.get("secondary", mv.effect)
		if se.kind == "stat" and se.get("who", "") == "self":
			_secondary(user, target, mv)
	# King's Rock adds a 10% flinch to moves without one.
	if user.item == "kingsRock" and total_dealt > 0 and target.alive and not subbed:
		var fk: String = mv.get("secondary", mv.effect).kind
		if fk != "flinch" and rng.int_below(10) == 0 and not _moved_this_turn.has(target) and target.ability != "innerFocus":
			target.vol.flinch = true
	if effect.kind == "fakeOut" and target.alive and not subbed and target.ability != "innerFocus":
		target.vol.flinch = true
	if effect.kind == "payDay" and user.side == 0:
		pay_day += int(user.mon.level) * 5
		_msg("Coins scattered everywhere!")

	_check_faint(target)
	_check_faint(user)
	if not target.alive and target.vol.destinyBond and user.alive and user.side != target.side:
		_msg("%s took its attacker down with it!" % name(target))
		_apply_damage(user, int(user.mon.hp))
		_check_faint(user)
	return true

## Effects of damaging moves that happen after the hit: binding, stealing, rapid spin...
func _after_hit_effects(user: Battler, target: Battler, mv: Dictionary, effect: Dictionary) -> void:
	match effect.kind:
		"trap":
			if target.alive and target.vol.trap == null:
				target.vol.trap = {"turns": 2 + rng.int_below(4), "by": user.mon.uid, "move": mv.name}
				_msg("%s %s %s!" % [name(target), effect.get("text", "was trapped by"), name(user)])
		"thief":
			if user.item == null and target.item != null and target.ability != "stickyHold" and target.alive and target.side != user.side:
				if user.side == 0 or kind == "trainer":
					user.mon.item = target.item
					target.mon.item = null
					_msg("%s stole %s's %s!" % [name(user), name(target), _item_name(user.item)])
		"knockOff":
			if target.item != null and target.ability != "stickyHold":
				_msg("%s knocked off %s's %s!" % [name(user), name(target), _item_name(target.item)])
				# Gen 3: the item is only lost for the battle; it comes back afterwards.
				target.mon.knockedOff = target.item
				target.mon.item = null
		"rapidSpin":
			if user.alive:
				if user.vol.trap != null:
					_msg("%s was freed from %s!" % [name(user), user.vol.trap.move])
					user.vol.trap = null
				user.vol.leechSeed = null
				if side_state[user.side].spikes > 0:
					side_state[user.side].spikes = 0
					_msg("%s blew away Spikes!" % name(user))
		"smellingSalt":
			if target.alive and target.mon.status == "par":
				target.mon.status = null
				_status_event(target)
				_msg("%s was cured of paralysis." % name(target))
		"triAttack":
			pass

func _secondary(user: Battler, target: Battler, mv: Dictionary) -> void:
	var e: Dictionary = mv.get("secondary", mv.effect)
	var self_effect: bool = e.kind == "stat" and e.get("who", "") == "self"
	if not self_effect and (not target.alive or target.ability == "shieldDust"):
		return
	var chance: int = int(mv.get("chance", 0))
	if user.ability == "sereneGrace":
		chance *= 2
	if rng.int_below(100) >= chance:
		return
	match e.kind:
		"status":
			_inflict(target, e.status, user, false)
		"triAttack":
			_inflict(target, ["brn", "frz", "par"][rng.int_below(3)], user, false)
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
	var foe: bool = target.side != user.side
	# A substitute blocks most status moves aimed at it.
	if target.vol.substitute > 0 and foe and e.kind not in ["roar", "perishSong", "haze", "spikes", "attract", "encore", "taunt", "disable", "torment", "spite", "psychUp", "skillSwap", "lockOn"]:
		_msg("But it failed!")
		return
	match e.kind:
		"status":
			if side_state[target.side].safeguard > 0 and foe:
				_msg("%s is protected by Safeguard!" % name(target))
				return
			_inflict(target, e.status, user, true)
		"confuse":
			if side_state[target.side].safeguard > 0 and foe:
				_msg("%s is protected by Safeguard!" % name(target))
				return
			_confuse(target, true)
		"stat":
			_apply_stat_changes(user, user if e.who == "self" else target, e.stages, true)
		"leechSeed":
			if target.types.has("Grass") or target.vol.leechSeed != null:
				_msg("%s evaded the attack!" % name(target))
			else:
				target.vol.leechSeed = user.ref
				_msg("%s was seeded!" % name(target))
		"roar":
			if target.ability == "suctionCups" or target.vol.ingrain:
				_msg("%s anchors itself!" % name(target))
				return
			if kind != "trainer":
				_msg("%s fled in fear!" % name(target) if target.side == 1 else "%s was blown away!" % name(target))
				if target.side == 1:
					result = "ran"
					phase = "over"
				return
			var t: Variant = target.trainer
			if t == null or bench_for(t).is_empty():
				_msg("But it failed!")
				return
			var bench := bench_for(t)
			var pick: int = bench[rng.int_below(bench.size())]
			_emit({"t": "switchOut", "side": target.side, "slot": target.slot})
			target.mon = null
			_send_out(target, t.party[pick], false)
			_msg("%s was dragged out!" % name(target))
			_switch_in_abilities([target])
		"disable":
			var idx: int = target.vol.lastMove
			if idx < 0 or target.vol.disable != null or idx >= target.mon.moves.size() or target.mon.moves[idx].pp <= 0:
				_msg("But it failed!")
				return
			target.vol.disable = {"moveIdx": idx, "turns": 2 + rng.int_below(4)}
			_msg("%s's %s was disabled!" % [name(target), DB.move(target.mon.moves[idx].id).name])
		"encore":
			var idx: int = target.vol.lastMove
			if idx < 0 or target.vol.encore != null or idx >= target.mon.moves.size() or DB.move(target.mon.moves[idx].id).id in ["encore", "mimic", "struggle"]:
				_msg("But it failed!")
				return
			target.vol.encore = {"moveIdx": idx, "turns": 2 + rng.int_below(5)}
			_msg("%s got an encore!" % name(target))
		"taunt":
			if target.vol.taunt > 0:
				_msg("But it failed!")
				return
			target.vol.taunt = 2
			_msg("%s fell for the taunt!" % name(target))
		"torment":
			if target.vol.torment:
				_msg("But it failed!")
				return
			target.vol.torment = true
			_msg("%s was subjected to torment!" % name(target))
		"spite":
			var idx: int = target.vol.lastMove
			if idx < 0 or idx >= target.mon.moves.size() or target.mon.moves[idx].pp <= 0:
				_msg("But it failed!")
				return
			var cut: int = mini(int(target.mon.moves[idx].pp), 2 + rng.int_below(4))
			target.mon.moves[idx].pp -= cut
			_msg("It reduced the PP of %s's %s by %d!" % [name(target), DB.move(target.mon.moves[idx].id).name, cut])
		"meanLook":
			if target.vol.cantEscape:
				_msg("But it failed!")
				return
			target.vol.cantEscape = user.mon.uid
			_msg("%s can't escape now!" % name(target))
		"attract":
			var g1: Variant = Creatures.gender_of(user.mon)
			var g2: Variant = Creatures.gender_of(target.mon)
			if g1 == null or g2 == null or g1 == g2 or target.vol.attract != null:
				_msg("But it failed!")
				return
			if target.ability == "oblivious":
				_msg("%s's Oblivious prevents romance!" % name(target))
				return
			target.vol.attract = user.mon.uid
			_msg("%s fell in love!" % name(target))
			_mental_herb(target)
		"swagger":
			var st: String = e.get("stat", "atk")
			_apply_stat_changes(user, target, {st: int(e.get("stages", 2))}, true)
			_confuse(target, true)
		"painSplit":
			var avg: int = (int(user.mon.hp) + int(target.mon.hp)) / 2
			user.mon.hp = mini(int(user.stats.hp), avg)
			target.mon.hp = mini(int(target.stats.hp), avg)
			_hp_event(user)
			_hp_event(target)
			_msg("The battlers shared their pain!")
		"psychUp":
			user.stages = target.stages.duplicate()
			_msg("%s copied %s's stat changes!" % [name(user), name(target)])
		"lockOn":
			user.vol.lockOn = 2
			_msg("%s took aim at %s!" % [name(user), name(target)])
		"yawn":
			if target.mon.status or target.vol.yawn > 0 or _can_have_status(target, "slp") != null:
				_msg("But it failed!")
				return
			target.vol.yawn = 2
			_msg("%s made %s drowsy!" % [name(user), name(target)])
		"memento":
			_apply_stat_changes(user, target, {"atk": -2, "spa": -2}, true)
			_apply_damage(user, int(user.mon.hp))
			_check_faint(user)
		"trick":
			if target.ability == "stickyHold" or (user.item == null and target.item == null) or kind != "trainer" and user.side == 1:
				_msg("But it failed!")
				return
			var a: Variant = user.item
			user.mon.item = target.item
			target.mon.item = a
			_msg("%s switched items with its target!" % name(user))
		"skillSwap":
			var a: Variant = user.ability
			var b: Variant = target.ability
			if a == "wonderGuard" or b == "wonderGuard":
				_msg("But it failed!")
				return
			user.vol.abilityOverride = b
			target.vol.abilityOverride = a
			_msg("%s swapped abilities with its target!" % name(user))
		_:
			_msg("But it failed!")

func _contact_ability(user: Battler, target: Battler) -> void:
	var umon: Variant = user.mon
	if umon == null or umon.hp <= 0:
		return
	var ab: Variant = target.ability
	if ab == "roughSkin":
		_apply_damage(user, maxi(1, int(user.stats.hp) / 16))
		_msg("%s was hurt by %s's Rough Skin!" % [name(user), name(target)])
		_check_faint(user)
		return
	if ab == "cuteCharm" and rng.int_below(3) == 0 and user.vol.attract == null and user.ability != "oblivious":
		var g1: Variant = Creatures.gender_of(user.mon)
		var g2: Variant = Creatures.gender_of(target.mon)
		if g1 != null and g2 != null and g1 != g2:
			user.vol.attract = target.mon.uid
			_msg("%s's Cute Charm infatuated %s!" % [name(target), name(user)])
			_mental_herb(user)
		return
	if umon.status:
		return
	if ab == "static" and rng.int_below(3) == 0:
		_inflict(user, "par", target, false, "%s's Static" % name(target))
	elif ab == "poisonPoint" and rng.int_below(3) == 0:
		_inflict(user, "psn", target, false, "%s's Poison Point" % name(target))
	elif ab == "flameBody" and rng.int_below(3) == 0:
		_inflict(user, "brn", target, false, "%s's Flame Body" % name(target))
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
	if s == "frz" and (types.has("Ice") or eff_weather() == "sun"):
		return "type"
	if s == "slp" and ab == "insomnia":
		return "Insomnia"
	if s == "slp" and ab == "vitalSpirit":
		return "Vital Spirit"
	if s == "par" and ab == "limber":
		return "Limber"
	if (s == "psn" or s == "tox") and ab == "immunity":
		return "Immunity"
	if s == "brn" and ab == "waterVeil":
		return "Water Veil"
	if s == "frz" and ab == "magmaArmor":
		return "Magma Armor"
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
	if source != null and source.side != target.side and side_state[target.side].safeguard > 0:
		if primary:
			_msg("%s is protected by Safeguard!" % name(target))
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
	_status_berry(target)
	return true

func _confuse(target: Battler, primary: bool, from_rampage: bool = false) -> void:
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
	_msg("%s became confused due to fatigue!" % name(target) if from_rampage else "%s became confused!" % name(target))
	_status_berry(target)

func _apply_stat_changes(user: Battler, target: Battler, stages: Dictionary, primary: bool) -> void:
	if not target.alive:
		return
	var dropped := false
	for k in stages:
		var delta: int = stages[k]
		var by_foe := target != user and delta < 0
		if by_foe and (target.ability == "clearBody" or target.ability == "whiteSmoke"):
			if primary:
				_msg("%s's %s prevents stat loss!" % [name(target), DB.ABILITIES[target.ability].name])
			continue
		if by_foe and side_state[target.side].mist > 0:
			if primary:
				_msg("%s is protected by Mist!" % name(target))
			continue
		if by_foe and target.vol.substitute > 0:
			if primary:
				_msg("But it failed!")
			continue
		if by_foe and k == "acc" and target.ability == "keenEye":
			if primary:
				_msg("%s's Keen Eye prevents accuracy loss!" % name(target))
			continue
		if by_foe and k == "atk" and target.ability == "hyperCutter":
			if primary:
				_msg("%s's Hyper Cutter prevents Attack loss!" % name(target))
			continue
		var cur: int = target.stages[k]
		var nxt := clampi(cur + delta, -6, 6)
		if nxt == cur:
			if primary:
				_msg("%s's %s won't go %s!" % [name(target), STAT_NAMES[k], "higher" if delta > 0 else "lower"])
			continue
		target.stages[k] = nxt
		if delta < 0:
			dropped = true
		_emit({"t": "anim", "kind": "stat-up" if delta > 0 else "stat-down", "side": target.side, "slot": target.slot})
		var word: String
		if delta > 0:
			word = "sharply rose" if delta > 1 else "rose"
		else:
			word = "harshly fell" if delta < -1 else "fell"
		_msg("%s's %s %s!" % [name(target), STAT_NAMES[k], word])
	if dropped:
		_white_herb(target)

func _set_weather(w: String) -> void:
	if weather == w:
		_msg("But it failed!")
		return
	weather = w
	weather_turns = 5
	_emit({"t": "weather", "weather": w})
	_msg({"rain": "It started to rain!", "sun": "The sunlight got bright!", "sand": "A sandstorm brewed!", "hail": "It started to hail!"}[w])
	for b in all_battlers():
		_forecast(b)

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
	if b.vol.semi != null:
		_emit({"t": "semi", "side": b.side, "slot": b.slot, "hidden": false})
	b.vol = _fresh_volatile()
	# Fainting lowers friendship a little.
	if b.side == 0 and b.mon.has("friendship"):
		b.mon.friendship = maxi(0, int(b.mon.friendship) - 1)
	_emit({"t": "faint", "side": b.side, "slot": b.slot})
	_msg("%s fainted!" % name(b))
	if b.side == 1:
		_award_exp(b)

# ---------- held item triggers ----------
func _consume(b: Battler) -> void:
	b.mon.item = null

func _hp_berry(b: Battler) -> void:
	if not b.alive or b.item == null:
		return
	var it: Dictionary = DB.item(b.item)
	var hold: Dictionary = it.effect.get("hold", {})
	var hp: int = b.mon.hp
	var mx: int = b.stats.hp
	match hold.get("kind", ""):
		"heal":
			if hp <= mx / 2:
				_consume(b)
				_heal(b, int(hold.amount))
				_msg("%s's %s restored health!" % [name(b), it.name])
		"flavorHeal":
			if hp <= mx / 2:
				_consume(b)
				_heal(b, mx / 8)
				_msg("%s's %s restored health!" % [name(b), it.name])
				# A creature whose nature dislikes the flavor gets confused.
				var down: int = Creatures.nature_of(b.mon) % 5
				var flavor_stat: Array = [0, 4, 2, 1, 3] # spicy=atk, dry=spa, sweet=spe, bitter=spd, sour=def in nature order
				if flavor_stat[int(hold.flavor)] == down and Creatures.nature_of(b.mon) / 5 != down:
					_confuse(b, false)
		"pinchStat":
			if hp <= mx / 4:
				_consume(b)
				_msg("%s's %s raised its stat!" % [name(b), it.name])
				_apply_stat_changes(b, b, {hold.stat: 1}, false)

func _status_berry(b: Battler) -> void:
	if not b.alive or b.item == null:
		return
	var it: Dictionary = DB.item(b.item)
	var hold: Dictionary = it.effect.get("hold", {})
	var kind_: String = hold.get("kind", "")
	if kind_ == "cure" and b.mon.status != null and (hold.statuses as Array).has(b.mon.status):
		_consume(b)
		b.mon.status = null
		b.mon.sleepTurns = 0
		_status_event(b)
		_msg("%s's %s cured its status!" % [name(b), it.name])
	elif (kind_ == "cureConfusion" or (kind_ == "cure" and hold.get("confusion", false))) and b.vol.confusion > 0:
		_consume(b)
		b.vol.confusion = 0
		_msg("%s's %s snapped it out of confusion!" % [name(b), it.name])
	if b.item == "mentalHerb" and b.vol.attract != null:
		_mental_herb(b)

func _leppa(b: Battler, idx: int) -> void:
	if b.item != "leppaBerry":
		return
	_consume(b)
	var ms: Dictionary = b.mon.moves[idx]
	ms.pp = mini(int(ms.maxPp), 10)
	_msg("%s's Leppa Berry restored %s's PP!" % [name(b), DB.move(ms.id).name])

func _white_herb(b: Battler) -> void:
	if b.item != "whiteHerb" or not b.alive:
		return
	var any := false
	for k in b.stages:
		if b.stages[k] < 0:
			b.stages[k] = 0
			any = true
	if any:
		_consume(b)
		_msg("%s's White Herb restored its stats!" % name(b))

func _mental_herb(b: Battler) -> void:
	if b.item != "mentalHerb" or b.vol.attract == null:
		return
	_consume(b)
	b.vol.attract = null
	_msg("%s's Mental Herb cured its infatuation!" % name(b))

## Gen 3 EXP: floor(baseExp * level / 7), split between participants, x1.5 in trainer battles.
## Exp. Share holders take half; Lucky Eggs and traded creatures get x1.5.
func _award_exp(fainted: Battler) -> void:
	var foe: Dictionary = fainted.mon
	var sp: Dictionary = DB.species(foe.species)
	if no_exp:
		return
	var parts: Array = []
	var sharers: Array = []
	for t in trainers[0]:
		for m in t.party:
			if not can_battle(m):
				continue
			if fainted.participants.has(m.uid):
				parts.push_back(m)
			if m.get("item", null) == "expShare":
				sharers.push_back(m)
	if parts.is_empty():
		return
	var total: int = (int(sp.baseExp) * int(foe.level)) / 7
	var gains := {}
	if sharers.is_empty():
		for m in parts:
			gains[m.uid] = maxi(1, total / parts.size())
	else:
		for m in parts:
			gains[m.uid] = maxi(1, (total / 2) / parts.size())
		for m in sharers:
			gains[m.uid] = gains.get(m.uid, 0) + maxi(1, (total / 2) / sharers.size())
	var order: Array = parts.duplicate()
	for m in sharers:
		if not _has_same(order, m):
			order.push_back(m)
	for m in order:
		var gain: int = gains[m.uid]
		var owner: Variant = null
		for t in trainers[0]:
			if _has_same(t.party, m):
				owner = t
				break
		if kind == "trainer":
			gain = (gain * 150) / 100
		var traded: bool = owner != null and owner.has("otId") and int(m.otId) != int(owner.otId)
		if traded:
			gain = (gain * 150) / 100
		if m.get("item", null) == "luckyEgg":
			gain = (gain * 150) / 100
		var evs: Dictionary = sp.evYield
		if m.get("item", null) == "machoBrace":
			evs = evs.duplicate()
			for k in evs:
				evs[k] = int(evs[k]) * 2
		Creatures.add_evs(m, evs)
		if m.level >= 100:
			continue
		_msg("%s gained %s%d EXP. Points!" % [Creatures.display_name(m), "a boosted " if traded or m.get("item", null) == "luckyEgg" else "", gain])
		var ups := Creatures.gain_exp(m, gain)
		var active: Battler = null
		for b in battlers[0]:
			if is_same(b.mon, m):
				active = b
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
		if s.mist > 0:
			s.mist -= 1
			if s.mist == 0:
				_msg("%s Mist wore off!" % who)
		if s.safeguard > 0:
			s.safeguard -= 1
			if s.safeguard == 0:
				_msg("%s Safeguard wore off!" % who)
		for slot in s.wish.size():
			var wsh: Variant = s.wish[slot]
			if wsh == null:
				continue
			wsh.turns -= 1
			if wsh.turns <= 0:
				s.wish[slot] = null
				if slot < battlers[i].size():
					var b: Battler = battlers[i][slot]
					if b.alive and b.mon.hp < b.stats.hp:
						_heal(b, wsh.hp)
						_msg("%s's wish came true!" % wsh.from)
	var w: Variant = eff_weather()
	if weather != null:
		if weather_turns > 0:
			weather_turns -= 1
		if weather_turns == 0:
			_msg({"rain": "The rain stopped.", "sun": "The sunlight faded.", "sand": "The sandstorm subsided.", "hail": "The hail stopped."}[weather])
			weather = null
			_emit({"t": "weather", "weather": null})
			for b in all_battlers():
				_forecast(b)
		else:
			_msg({"rain": "Rain continues to fall.", "sun": "The sunlight is strong.", "sand": "The sandstorm rages.", "hail": "Hail continues to fall."}[weather])
			if w == "sand" or w == "hail":
				for b in _speed_order(all_battlers().filter(func(x: Battler) -> bool: return x.alive)):
					var immune: bool
					if w == "sand":
						immune = b.types.has("Rock") or b.types.has("Ground") or b.types.has("Steel") or b.ability == "sandVeil"
					else:
						immune = b.types.has("Ice")
					if immune or b.vol.semi == "dig" or b.vol.semi == "dive":
						continue
					_apply_damage(b, maxi(1, int(b.stats.hp) / 16))
					_msg("%s is buffeted by the %s!" % [name(b), "sandstorm" if w == "sand" else "hail"])
					_check_faint(b)
	for b in _speed_order(all_battlers().filter(func(x: Battler) -> bool: return x.alive)):
		var mon: Dictionary = b.mon
		if b.ability == "rainDish" and w == "rain" and mon.hp < b.stats.hp:
			_heal(b, int(b.stats.hp) / 16)
			_msg("%s's Rain Dish restored its HP a little!" % name(b))
		if b.vol.ingrain and mon.hp < b.stats.hp:
			_heal(b, int(b.stats.hp) / 16)
			_msg("%s absorbed nutrients with its roots!" % name(b))
		if b.item == "leftovers" and mon.hp < b.stats.hp:
			_heal(b, int(b.stats.hp) / 16)
			_msg("%s restored a little HP using its Leftovers!" % name(b))
		if b.ability == "shedSkin" and mon.status and rng.int_below(3) == 0:
			mon.status = null
			_status_event(b)
			_msg("%s's Shed Skin cured its status!" % name(b))
		if b.vol.leechSeed != null and b.alive:
			var seeder := at(b.vol.leechSeed)
			var dmg := _apply_damage(b, maxi(1, int(b.stats.hp) / 8))
			if seeder.alive:
				if b.ability == "liquidOoze":
					_apply_damage(seeder, dmg)
					_check_faint(seeder)
				else:
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
		if not b.alive:
			continue
		if b.vol.curse:
			_apply_damage(b, maxi(1, int(b.stats.hp) / 4))
			_msg("%s is afflicted by the curse!" % name(b))
			_check_faint(b)
		if b.alive and b.vol.trap != null:
			b.vol.trap.turns -= 1
			if b.vol.trap.turns <= 0:
				_msg("%s was freed from %s!" % [name(b), b.vol.trap.move])
				b.vol.trap = null
			else:
				_apply_damage(b, maxi(1, int(b.stats.hp) / 16))
				_msg("%s is hurt by %s!" % [name(b), b.vol.trap.move])
				_check_faint(b)
		if b.alive and b.vol.yawn > 0:
			b.vol.yawn -= 1
			if b.vol.yawn == 0 and not b.mon.status and _can_have_status(b, "slp") == null and side_state[b.side].safeguard == 0:
				_inflict(b, "slp", null, false)
		if b.alive and b.vol.perish > 0:
			b.vol.perish -= 1
			_msg("%s's perish count fell to %d!" % [name(b), b.vol.perish])
			if b.vol.perish == 0:
				_apply_damage(b, int(b.mon.hp))
				_check_faint(b)
		if b.alive and b.vol.encore != null:
			b.vol.encore.turns -= 1
			if b.vol.encore.turns <= 0 or b.mon.moves[b.vol.encore.moveIdx].pp <= 0:
				b.vol.encore = null
				_msg("%s's encore ended!" % name(b))
		if b.alive and b.vol.disable != null:
			b.vol.disable.turns -= 1
			if b.vol.disable.turns <= 0:
				b.vol.disable = null
				_msg("%s is no longer disabled!" % name(b))
		if b.alive and b.vol.taunt > 0:
			b.vol.taunt -= 1
		if b.alive and b.ability == "speedBoost" and b.vol.turnsOut > 0 and b.stages.spe < 6:
			b.stages.spe += 1
			_emit({"t": "anim", "kind": "stat-up", "side": b.side, "slot": b.slot})
			_msg("%s's Speed Boost raised its Speed!" % name(b))
		if b.alive:
			_hp_berry(b)
			_status_berry(b)
	for b in all_battlers():
		b.vol.flinch = false
		b.vol.protect = false
		b.vol.endure = false
		b.vol.followMe = false
		b.vol.helpingHand = false
		b.vol.destinyBond = b.vol.destinyBond and not b.vol.moved
		if b.vol.lockOn > 0:
			b.vol.lockOn -= 1
		if not b.vol.protectedThisTurn:
			b.vol.protectStreak = 0
		b.vol.protectedThisTurn = false
		if b.alive:
			b.vol.turnsOut += 1

# ---------- AI ----------
func _choose_ai(b: Battler) -> Dictionary:
	var mon: Dictionary = b.mon
	var usable: Array = []
	for i in mon.moves.size():
		if move_selectable(b, i) == "":
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
			var mtype := _move_type(b, mv)
			if mv.power > 0:
				var eff := _type_effect10(mv, t, mtype)
				if eff == 0.0 or (mtype == "Ground" and t.ability == "levitate") or (t.ability == "wonderGuard" and eff <= 10.0):
					score = 0.0
				else:
					var est: float
					match mv.effect.kind:
						"fixed":
							est = float(mon.level if typeof(mv.effect.amount) == TYPE_STRING and mv.effect.amount == "level" else int(mv.effect.amount))
						"ohko":
							est = float(t.mon.hp) * 0.3 if int(t.mon.level) <= int(mon.level) else 0.0
						"superFang", "endeavor", "counter":
							est = float(t.mon.hp) * 0.4
						_:
							est = (float(base_damage(b, t, maxi(1, _power_of_est(b, mv)), mtype, false, false)) * (1.5 if b.types.has(mtype) else 1.0) * eff) / 10.0 * 0.92
					var acc: float = 1.0 if mv.acc == 0 else float(mv.acc) / 100.0
					var thp: float = float(t.mon.hp)
					score = minf(est, thp) / maxf(1.0, thp) * 100.0 * acc
					if est >= thp:
						score += 40.0
					if (mv.target == "both" or mv.target == "foesAndAlly") and foes.size() > 1:
						score *= 1.3
					if mv.effect.kind in ["recharge", "explode", "twoTurn", "rampage", "focusPunch"]:
						score *= 0.7
					if mv.effect.kind == "explode" and float(mon.hp) > float(b.stats.hp) / 3.0:
						score *= 0.3
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
				if e.kind in ["substitute", "bellyDrum"] and float(b.mon.hp) < float(b.stats.hp) / 2.0:
					score = 0.0
				if e.kind in ["perishSong", "destinyBond", "memento", "metronome", "splash", "teleport", "batonPass"]:
					score = 3.0
				if e.kind == "spikes" and side_state[t.side].spikes >= 3:
					score = 0.0
				if e.kind == "sleepTalk" and mon.status != "slp":
					score = 0.0
			score += rng.int_below(20)
			if score > best.score:
				best = {"score": score, "idx": u.i, "target": t.ref}
	return {"kind": "move", "moveIdx": best.idx, "target": best.target}

## Rough power for AI estimates (no side effects like the Magnitude roll).
func _power_of_est(b: Battler, mv: Dictionary) -> int:
	match mv.effect.kind:
		"hiddenPower":
			return hidden_power(b.mon).power
		"return", "frustration":
			return 70
		"reversal":
			return 40
		"eruption":
			return maxi(1, (150 * int(b.mon.hp)) / maxi(1, int(b.stats.hp)))
		"magnitude":
			return 70
	return mv.power
