class_name BattleScene
extends Scene
## The battle screen (TS battleScene.ts): plays back Battle events and collects each human player's actions.
## setup keys (TS BattleSetup): kind ("wild" | "trainer" | "safari"), double (bool), wild (Array of Creatures, wild battles),
## trainer (TrainerDef dict from DB.MAPS), trainerParty (Array of Creatures), onEnd (Callable(result: String, battle: Battle)).
## Optional: weather (the map's), location ("water"/"underwater"/"cave"), noExp (Battle Tower), noPrize, party (Array:
## the creatures to use instead of the player's party, for the Battle Tower). Battle Frontier rules: palace (creatures
## act on their own), arena (three-turn judged match-ups), noBag, noSwitch, noCatch.
## The snake_case spellings trainer_party / on_end are accepted too.

class Slot:
	var view: Variant = null # MonView dict
	var shown_hp := 0.0
	var shown_exp := 0.0
	var visible := false
	var appear := 0.0 # 0..1
	var faint := 0.0 # 0..1 drop
	var flash := 0.0
	var lunge := 0.0
	var tint: Variant = null # {color, t}
	var hidden := false # up in the sky, underground or underwater (Fly, Dig, Dive)
	var fx: Variant = null # {tex, t, dur}: a move's hit effect or a stat/status/heal effect over the creature

var battle: Battle
## uids of creatures that levelled up (they get an evolution check afterwards).
var leveled: Array = []
var _setup: Dictionary
var _slots: Array = [[], []]
var _queue: Array = []
var _message := ""
var _msg_shown := 0.0
var _msg_wait := 0.0
## {kind, t, dur, data, done}
var _anim: Variant = null
## "intro" | "events" | "choose" | "busy" | "end"
var _mode := "intro"
var _intro_t := 0.0
var _reqs: Array = []
var _req_idx := 0
## Array of {req, action, refund}
var _choices: Array = []
## "action" | "move" | "target"
var _menu := "action"
var _action_sel := 0
var _move_sel := 0
var _target_list: Array = []
var _target_sel := 0
var _pending_move := 0
var _weather: Variant = null
var _ball: Variant = null
var _level_panel: Variant = null
var _after_events := Callable()
var _victory_played := false

func _init(setup: Dictionary) -> void:
	_setup = setup
	var gs: Dictionary = Game.gs
	var coop: bool = gs.mode == "coop"
	var double: bool = setup.get("double", false) or coop
	var side0: Array = []
	if coop:
		for i in gs.players.size():
			var p: Dictionary = gs.players[i]
			side0.append({"name": p.name, "party": p.party, "controller": "human", "slots": [i], "player": i, "otId": p.otId})
	else:
		side0.append({"name": gs.players[0].name, "party": setup.get("party", gs.players[0].party),
			"controller": "palace" if setup.get("palace", false) else "human",
			"slots": [0, 1] if double else [0], "player": 0, "otId": gs.players[0].otId})
	var side1: Array = []
	if setup.kind != "trainer":
		side1.append({"name": "Wild", "party": setup.wild, "controller": "wild", "slots": [0, 1] if double else [0]})
	else:
		side1.append({"name": setup.trainer.name, "party": _trainer_party(), "controller": "ai", "slots": [0, 1] if double else [0]})
	battle = Battle.new({"kind": setup.kind, "double": double, "sides": [side0, side1], "weather": setup.get("weather", null),
		"location": setup.get("location", "land"), "noExp": setup.get("noExp", false), "caughtSpecies": gs.caught,
		"shift": Options.shift_style() and not setup.get("noSwitch", false), "palace": setup.get("palace", false),
		"arena": setup.get("arena", false)})
	var n := 2 if double else 1
	for side in [0, 1]:
		for i in n:
			_slots[side].append(Slot.new())
	for m in setup.get("wild", []):
		if not gs.seen.has(m.species):
			gs.seen.append(m.species)
	Audio.push_music(battle_music(setup))

## Music track for a battle setup: battle_wild / battle_trainer / battle_gym / battle_rival /
## battle_champion / battle_villain.
static func battle_music(setup: Dictionary) -> String:
	if setup.get("kind", "wild") != "trainer":
		return "battle_wild"
	var t: Dictionary = setup.get("trainer", {})
	var id: String = str(t.get("id", ""))
	if t.get("champion", false) or id == "champion" or id.begins_with("elite_") or id.contains("league"):
		return "battle_champion"
	if id.begins_with("order_"):
		return "battle_villain"
	if id.contains("rival"):
		return "battle_rival"
	if t.has("badge"):
		return "battle_gym"
	return "battle_trainer"

func _play_victory() -> void:
	if _victory_played:
		return
	_victory_played = true
	Audio.play_music("victory_trainer" if _setup.kind == "trainer" else "victory_wild")

## Looks ahead in the event queue (up to the next hit) for the effectiveness message of this hit.
func _hit_sfx() -> String:
	for e in _queue:
		if e.t == "anim" and (e.kind == "hit" or e.kind == "move"):
			break
		if e.t == "msg":
			if e.text == "It's super effective!":
				return "hit_super"
			if e.text == "It's not very effective...":
				return "hit_weak"
	return "hit"

func _foe_faint_pending() -> bool:
	for e in _queue:
		if e.t == "faint" and e.side == 1:
			return true
	return false

func _trainer_party() -> Array:
	return _setup.get("trainerParty", _setup.get("trainer_party", []))

var _gs: Dictionary:
	get:
		return Game.gs

# ---------- event playback ----------
func _play(events: Array, then: Callable) -> void:
	_queue.append_array(events)
	_mode = "events"
	_after_events = then

func _slot_of(e: Dictionary) -> Slot:
	return _slots[e.side][e.slot] if e.has("side") else null

func _next_event() -> void:
	if _queue.is_empty():
		_message = ""
		var cb := _after_events
		_after_events = Callable()
		if cb.is_valid():
			cb.call()
		return
	var e: Dictionary = _queue.pop_front()
	var sl := _slot_of(e)
	match e.t:
		"msg":
			_message = e.text
			if e.text == "Got away safely!":
				Audio.sfx("run")
			_msg_shown = 0
			_msg_wait = 0
			_anim = {"kind": "msg", "t": 0.0, "dur": INF}
			return
		"switchIn":
			sl.view = e.mon.duplicate()
			sl.shown_hp = e.mon.hp
			sl.shown_exp = e.mon.expFrac
			sl.visible = true
			sl.faint = 0
			sl.appear = 0
			if e.side == 0 or _setup.kind == "trainer":
				Audio.sfx("send_out")
			if e.side == 1 and not _gs.seen.has(e.mon.species):
				_gs.seen.append(e.mon.species)
			_anim = {"kind": "appear", "t": 0.0, "dur": 0.35, "data": sl}
			return
		"switchOut":
			_anim = {"kind": "disappear", "t": 0.0, "dur": 0.25, "data": sl, "done": func() -> void: sl.visible = false}
			return
		"update":
			sl.view = e.mon.duplicate()
			sl.shown_hp = e.mon.hp
			_next_event()
			return
		"hp":
			var from := sl.shown_hp
			if sl.view != null:
				sl.view.maxHp = e.maxHp
			var diff := absf(e.hp - from)
			var dur := minf(0.9, maxf(0.15, (diff / maxf(1, e.maxHp)) * 1.4))
			var low_from := from / maxf(1, e.maxHp) > 0.25
			_anim = {"kind": "hp", "t": 0.0, "dur": dur, "data": {"sl": sl, "from": from, "to": e.hp}, "done": func() -> void:
				if e.side == 0 and low_from and e.hp > 0 and float(e.hp) / maxf(1, e.maxHp) <= 0.25:
					Audio.sfx("low_hp")
				sl.shown_hp = e.hp
				if sl.view != null:
					sl.view.hp = e.hp}
			return
		"status":
			if sl.view != null:
				sl.view.status = e.status
			_next_event()
			return
		"faint":
			Audio.sfx("faint")
			var last_foe: bool = e.side == 1 and battle.result == "win" and not _foe_faint_pending()
			_anim = {"kind": "faint", "t": 0.0, "dur": 0.45, "data": sl, "done": func() -> void:
				sl.visible = false
				if last_foe:
					_play_victory()}
			return
		"semi":
			sl.hidden = e.hidden
			_next_event()
			return
		"anim":
			if not Options.battle_scene():
				if e.kind == "hit":
					Audio.sfx(_hit_sfx())
				_next_event()
				return
			if e.kind == "move":
				_anim = {"kind": "lunge", "t": 0.0, "dur": 0.25, "data": sl}
				return
			if e.kind == "hit":
				Audio.sfx(_hit_sfx())
				_set_fx(sl, "fx_" + str(e.get("type", "normal")).to_lower(), 0.45)
				_anim = {"kind": "flash", "t": 0.0, "dur": 0.45, "data": sl}
				return
			Audio.sfx({"stat-up": "stat_up", "stat-down": "stat_down", "heal": "recover"}.get(e.kind, "status"))
			var color := "#f08040" if e.kind == "stat-up" else ("#4080f0" if e.kind == "stat-down" else ("#60e070" if e.kind == "heal" else "#c060e0"))
			sl.tint = {"color": color, "t": 0.0}
			_set_fx(sl, "fx_" + str(e.kind).replace("-", "_"), 0.4)
			_anim = {"kind": "tint", "t": 0.0, "dur": 0.4, "data": sl, "done": func() -> void: sl.tint = null}
			return
		"ball":
			_ball = {"side": e.side, "slot": e.slot, "shakes": e.shakes, "caught": e.caught, "item": e.get("item", "orb"), "t": 0.0, "sounds": 0}
			Audio.sfx("orb_throw")
			_anim = {"kind": "ball", "t": 0.0, "dur": 0.6 + e.shakes * 0.5 + 0.4, "done": func() -> void:
				if e.caught:
					sl.visible = false
				_ball = null}
			return
		"exp":
			var from := sl.shown_exp
			if e.expFrac > from:
				Audio.sfx("exp")
			_anim = {"kind": "exp", "t": 0.0, "dur": 0.5, "data": {"sl": sl, "from": from, "to": e.expFrac}, "done": func() -> void: sl.shown_exp = e.expFrac}
			return
		"levelUp":
			if not leveled.has(e.uid):
				leveled.append(e.uid)
			_level_panel = {"name": e.name, "old": e.old, "now": e.now}
			Audio.sfx("level_up")
			_anim = {"kind": "levelPanel", "t": 0.0, "dur": INF}
			return
		"learnPrompt":
			var mon: Variant = null
			for p in _gs.players:
				for m in p.party:
					if m.uid == e.uid:
						mon = m
			if mon == null:
				_next_event()
				return
			_anim = {"kind": "wait", "t": 0.0, "dur": INF}
			Menus.learn_move_flow(mon, e.moveId, e.player, func() -> void:
				_anim = null
				_next_event())
			return
		"weather":
			_weather = e.weather
			_next_event()
			return
	_next_event()

func _update_anim(dt: float) -> void:
	var a: Dictionary = _anim
	a.t += dt
	var k := minf(1, a.t / a.dur)
	match a.kind:
		"msg":
			var full := _message.length()
			if _msg_shown < full:
				_msg_shown += dt * 80
				if Game.input.any("a"):
					_msg_shown = full
			else:
				_msg_wait += dt
				if _msg_wait > 1.1 or Game.input.any("a") or Game.input.any("b"):
					_anim = null
					_next_event()
			return
		"levelPanel":
			if a.t > 0.3 and (Game.input.any("a") or Game.input.any("b") or a.t > 3):
				_level_panel = null
				_anim = null
				_next_event()
			return
		"wait":
			return
		"appear": a.data.appear = k
		"disappear": a.data.appear = 1 - k
		"faint": a.data.faint = k
		"flash": a.data.flash = (1 - k) if k < 1 else 0.0
		"lunge": a.data.lunge = sin(k * PI)
		"tint":
			if a.data.tint != null:
				a.data.tint.t = k
		"hp":
			var d: Dictionary = a.data
			d.sl.shown_hp = roundf(d.from + (d.to - d.from) * k)
		"exp":
			var d: Dictionary = a.data
			d.sl.shown_exp = d.from + (d.to - d.from) * k
		"ball":
			if _ball != null:
				_ball.t = a.t
				# Sounds: land at 0.6s, a shake every 0.5s, then the result.
				var due := 0
				if a.t >= 0.6:
					due = 1 + mini(_ball.shakes, int((a.t - 0.6) / 0.5))
				while _ball.sounds < due:
					_ball.sounds += 1
					if _ball.sounds - 1 < _ball.shakes:
						Audio.sfx("orb_shake")
					else:
						Audio.sfx("catch" if _ball.caught else "breakout")
	if a.t >= a.dur:
		var done: Callable = a.get("done", Callable())
		if done.is_valid():
			done.call()
		if a.kind == "flash":
			a.data.flash = 0.0
		if a.kind == "lunge":
			a.data.lunge = 0.0
		_anim = null
		_next_event()

# ---------- flow ----------
func _begin_choices() -> void:
	if battle.kind == "safari" and battle.phase != "over" and _safari_balls() <= 0:
		battle.result = "ran"
		battle.phase = "over"
		_play([{"t": "msg", "text": "PA: Ding-dong! You're out of Safari Orbs!"}], _finish)
		return
	if battle.phase == "over":
		_finish()
		return
	_reqs = battle.requests()
	_choices = []
	_req_idx = 0
	if _reqs.is_empty():
		_submit()
		return
	_start_request()

func _start_request() -> void:
	var r: Dictionary = _reqs[_req_idx]
	_mode = "choose"
	_menu = "action"
	_action_sel = 0
	_move_sel = 0
	if r.kind == "replace":
		_choose_replacement(r)
	elif r.kind == "shift":
		_offer_shift(r)

func _taken(t: Dictionary, i: int) -> bool:
	for c in _choices:
		if c.action.kind == "switch" and c.action.partyIdx == i and is_same(c.req.trainer, t):
			return true
	return false

func _choose_replacement(r: Dictionary) -> void:
	_mode = "busy"
	var t: Dictionary = r.trainer
	var bench: Array = battle.bench_for(t)
	var ps := PartyScreen.new({"player": r.player, "party": t.party, "prompt": "Send out which creature?", "start": bench[0] if bench.size() else 0})
	ps.o.on_select = func(i: int) -> void:
		var m: Dictionary = t.party[i]
		var taken := _taken(t, i)
		var active := false
		for b in battle.battlers[0]:
			if is_same(b.mon, m) and b.alive:
				active = true
		if m.get("egg", false):
			Game.say(["An Egg can't battle!"], Callable(), r.player)
			return
		if m.hp <= 0:
			Game.say(["%s has no energy left to battle!" % Creatures.display_name(m)], Callable(), r.player)
			return
		if active or taken:
			Game.say(["%s is already in battle!" % Creatures.display_name(m)], Callable(), r.player)
			return
		Game.pop(ps)
		_push_choice({"kind": "switch", "partyIdx": i})
	Game.push(ps)

## Battle style SHIFT: the foe trainer sent out a new creature, so the player may switch too.
func _offer_shift(r: Dictionary) -> void:
	_mode = "busy"
	var foe: Variant = battle.battlers[1][0].mon
	var foe_name: String = Creatures.display_name(foe) if foe != null else "a new creature"
	Game.ask("%s is about to use %s. Will %s change creatures?" % [_setup.trainer.name, foe_name, _gs.players[r.player].name],
		["YES", "NO"], func(c: int) -> void:
			if c != 0:
				_push_choice({"kind": "stay"})
				return
			var t: Dictionary = r.trainer
			var ps := PartyScreen.new({"player": r.player, "party": t.party, "prompt": "Send out which creature?"})
			ps.o.on_cancel = func() -> void:
				Game.pop(ps)
				_push_choice({"kind": "stay"})
			ps.o.on_select = func(i: int) -> void:
				var m: Dictionary = t.party[i]
				if not battle.bench_for(t).has(i):
					Game.say(["%s can't battle now!" % Creatures.display_name(m)], Callable(), r.player)
					return
				Game.pop(ps)
				_push_choice({"kind": "switch", "partyIdx": i})
			Game.push(ps), r.player)

func _push_choice(action: Dictionary, refund: String = "") -> void:
	_choices.append({"req": _reqs[_req_idx], "action": action, "refund": refund})
	_req_idx += 1
	if _req_idx >= _reqs.size():
		_submit()
	else:
		_start_request()

func _undo_choice() -> void:
	if _req_idx == 0:
		return
	var c: Dictionary = _choices.pop_back()
	if c.refund != "":
		_gs.bag[c.refund] = _gs.bag.get(c.refund, 0) + 1
	_req_idx -= 1
	if _reqs[_req_idx].kind == "replace":
		_req_idx += 1
		_choices.append(c)
		return
	_start_request()

func _submit() -> void:
	var map := {}
	for c in _choices:
		map["%d:%d" % [c.req.ref.side, c.req.ref.slot]] = c.action
	_mode = "events"
	var events: Array = battle.submit(map)
	_play(events, _begin_choices)

func _safari_balls() -> int:
	var sf: Variant = _gs.get("safari", null)
	return int(sf.balls) if sf != null else 0

func _finish() -> void:
	_mode = "end"
	var b := battle
	var msgs: Array = []
	var gs := _gs
	var party_mons: Array = []
	for t in b.trainers[0]:
		party_mons.append_array(t.party)
	# Knock Off only takes an item for the battle.
	for m in party_mons:
		if m.has("knockedOff"):
			if m.get("item", null) == null:
				m.item = m.knockedOff
			m.erase("knockedOff")
	var coin := false
	for m in party_mons:
		if m.get("item", null) == "amuletCoin":
			coin = true
	if b.result == "win" and _setup.kind == "trainer" and not _setup.get("noPrize", false):
		var t: Dictionary = _setup.trainer
		var tp := _trainer_party()
		var last: Dictionary = tp[tp.size() - 1]
		var prize: int = t.pay * last.level * (2 if coin else 1)
		gs.money += prize
		msgs.append_array([t.defeat, "You got $%d for winning!" % prize])
	elif b.result == "win" and _setup.kind == "trainer":
		msgs.append(_setup.trainer.defeat)
	if b.pay_day > 0 and b.result != "lose":
		gs.money += b.pay_day * (2 if coin else 1)
		msgs.append("You picked up $%d!" % (b.pay_day * (2 if coin else 1)))
	if b.result == "win" and not _setup.has("party"):
		msgs.append_array(Field.pickup(gs, party_mons))
	if b.result == "win":
		_play_victory()
	if b.result == "lose":
		var lost: int = gs.money / 2
		gs.money -= lost
		msgs.append_array(["You're both out of usable creatures!" if gs.mode == "coop" else "You are out of usable creatures!", "You panicked and dropped $%d..." % lost, "... ... ... ...", "You hurried back to the Rest Lodge!"])
	var on_end: Callable = _setup.get("onEnd", _setup.get("on_end", Callable()))
	var done := func() -> void: on_end.call(b.result if b.result != null else "ran", b)
	if msgs.size():
		Game.say(msgs, done)
	else:
		done.call()

# ---------- input ----------
func update(dt: float) -> void:
	for side in _slots:
		for s in side:
			if s.tint != null and _anim == null:
				s.tint = null
	if _mode == "intro":
		_intro_t += dt
		if _intro_t > 0.7:
			_mode = "events"
			_play(battle.start(), _begin_choices)
		return
	if _mode == "events":
		if _anim != null:
			_update_anim(dt)
		else:
			_next_event()
		return
	if _mode != "choose":
		return
	var r: Dictionary = _reqs[_req_idx]
	var inp := Game.input.p(r.player)
	var b = battle.at(r.ref)
	var mon: Dictionary = b.mon
	if _menu == "action":
		if inp.pressed("left") or inp.pressed("right"):
			_action_sel ^= 1
			Audio.sfx("cursor")
		if inp.pressed("up") or inp.pressed("down"):
			_action_sel ^= 2
			Audio.sfx("cursor")
		if inp.pressed("b") and _req_idx > 0:
			Audio.sfx("cancel")
			_undo_choice()
		if inp.pressed("a"):
			Audio.sfx("confirm")
			if battle.kind == "safari":
				match _action_sel:
					0:
						gs_safari_throw(r)
					1:
						_push_choice({"kind": "bait"})
					2:
						_push_choice({"kind": "rock"})
					3:
						_push_choice({"kind": "run"})
				return
			if _action_sel == 0:
				var any_move := false
				for k in mon.moves.size():
					if battle.move_selectable(b, k) == "":
						any_move = true
				if not any_move:
					Game.say(["%s has no moves left!" % Creatures.display_name(mon)], func() -> void: _push_choice({"kind": "move", "moveIdx": -1}), r.player)
					_mode = "busy"
					return
				_menu = "move"
			elif _action_sel == 1:
				if _setup.get("noBag", false):
					_mode = "busy"
					Game.say(["Items can't be used here."], func() -> void: _mode = "choose", r.player)
				else:
					_open_bag_for(r)
			elif _action_sel == 2:
				if _setup.get("noSwitch", false):
					_mode = "busy"
					Game.say(["Switching isn't allowed here!"], func() -> void: _mode = "choose", r.player)
				else:
					_open_party_for(r)
			elif _action_sel == 3:
				var why: String = battle.trapped(b)
				if battle.kind != "trainer" and why != "" and b.ability != "runAway" and b.item != "smokeBall":
					_mode = "busy"
					Game.say([why], func() -> void: _mode = "choose", r.player)
				elif battle.kind == "trainer":
					_mode = "busy"
					Game.say(["No! There's no running from a trainer battle!"], func() -> void: _mode = "choose", r.player)
				else:
					_push_choice({"kind": "run"})
	elif _menu == "move":
		var n: int = mon.moves.size()
		var before_sel := _move_sel
		if inp.pressed("left") or inp.pressed("right"):
			_move_sel = mini(n - 1, _move_sel ^ 1)
		if inp.pressed("up") or inp.pressed("down"):
			_move_sel = mini(n - 1, _move_sel ^ 2)
		if _move_sel != before_sel:
			Audio.sfx("cursor")
		if inp.pressed("b"):
			Audio.sfx("cancel")
			_menu = "action"
		if inp.pressed("a"):
			var ms: Dictionary = mon.moves[_move_sel]
			var why: String = battle.move_selectable(b, _move_sel)
			Audio.sfx("error" if why != "" else "confirm")
			if why != "":
				_mode = "busy"
				Game.say([why], func() -> void: _mode = "choose", r.player)
				return
			var mv: Dictionary = DB.move(ms.id)
			if battle.double and mv.target == "normal":
				var opts: Array = []
				for f in battle.battlers[1]:
					if f.alive:
						opts.append(f.ref)
				var ally = battle.ally_of(b)
				if ally != null:
					opts.append(ally.ref)
				if opts.size() > 1:
					_target_list = opts
					_target_sel = 0
					_pending_move = _move_sel
					_menu = "target"
					return
				_push_choice({"kind": "move", "moveIdx": _move_sel, "target": opts[0]})
				return
			_push_choice({"kind": "move", "moveIdx": _move_sel})
	elif _menu == "target":
		var n := _target_list.size()
		if inp.pressed("left") or inp.pressed("up"):
			_target_sel = (_target_sel + n - 1) % n
			Audio.sfx("cursor")
		if inp.pressed("right") or inp.pressed("down"):
			_target_sel = (_target_sel + 1) % n
			Audio.sfx("cursor")
		if inp.pressed("b"):
			Audio.sfx("cancel")
			_menu = "move"
		if inp.pressed("a"):
			Audio.sfx("confirm")
			_push_choice({"kind": "move", "moveIdx": _pending_move, "target": _target_list[_target_sel]})

func gs_safari_throw(r: Dictionary) -> void:
	var sf: Dictionary = _gs.safari
	sf.balls -= 1
	_push_choice({"kind": "item", "itemId": "safariOrb", "target": {"side": 1, "slot": 0}})

func _open_party_for(r: Dictionary) -> void:
	_mode = "busy"
	var t: Dictionary = r.trainer
	var ps := PartyScreen.new({"player": r.player, "party": t.party, "prompt": "Choose a creature."})
	ps.o.on_cancel = func() -> void:
		Game.pop(ps)
		_mode = "choose"
	ps.o.on_select = func(i: int) -> void:
		var m: Dictionary = t.party[i]
		var ref := {}
		var menu := ListMenu.new({
			"x": 160, "y": 60, "w": 76, "player": r.player, "items": ["SHIFT", "SUMMARY", "CANCEL"],
			"on_cancel": func() -> void: Game.pop(ref.menu),
			"on_select": func(k: int) -> void:
				Game.pop(ref.menu)
				if k == 1:
					var sref := {}
					var s := SummaryScreen.new(m, r.player, func() -> void: Game.pop(sref.s))
					sref.s = s
					Game.push(s)
				elif k == 0:
					var active := false
					for b in battle.battlers[0]:
						if is_same(b.mon, m):
							active = true
					var taken := _taken(t, i)
					var why: String = battle.trapped(battle.at(r.ref))
					if m.get("egg", false):
						Game.say(["An Egg can't battle!"], Callable(), r.player)
						return
					if why != "" and not active:
						Game.say([why], Callable(), r.player)
						return
					if m.hp <= 0:
						Game.say(["%s has no energy left to battle!" % Creatures.display_name(m)], Callable(), r.player)
						return
					if active or taken:
						Game.say(["%s is already in battle!" % Creatures.display_name(m)], Callable(), r.player)
						return
					Game.pop(ps)
					_push_choice({"kind": "switch", "partyIdx": i}),
		})
		ref.menu = menu
		Game.push(menu)
	Game.push(ps)

func _open_bag_for(r: Dictionary) -> void:
	_mode = "busy"
	var gs := _gs
	# Joint battles: each player uses their own bag.
	if _setup.has("bags"):
		gs.bag = _setup.bags[r.player]
	Menus.open_bag({
		"player": r.player, "in_battle": true, "can_throw": battle.kind == "wild",
		"usable": func(id: String) -> bool: return Menus.BATTLE_KINDS.has(DB.item(id).effect.kind),
		"on_close": func() -> void: _mode = "choose",
		"on_pick": func(id: String, close_bag: Callable) -> void:
			var it: Dictionary = DB.item(id)
			if it.effect.kind == "ball":
				var foes: Array = []
				for f in battle.battlers[1]:
					if f.alive:
						foes.append(f)
				var throw_at := func(ref: Dictionary) -> void:
					gs.bag[id] -= 1
					close_bag.call()
					_push_choice({"kind": "item", "itemId": id, "target": ref}, id)
				if foes.size() <= 1:
					throw_at.call(foes[0].ref)
					return
				var names: Array = []
				for f in foes:
					names.append(Creatures.display_name(f.mon))
				var mref := {}
				var menu := ListMenu.new({
					"x": 120, "y": 40, "w": 116, "player": r.player, "title": "Throw at?",
					"items": names,
					"on_cancel": func() -> void: Game.pop(mref.menu),
					"on_select": func(k: int) -> void:
						Game.pop(mref.menu)
						throw_at.call(foes[k].ref),
				})
				mref.menu = menu
				Game.push(menu)
				return
			var party: Array = r.trainer.party
			# X items work on the creature that's out.
			if it.effect.kind == "xStat":
				var active_idx: int = party.find(battle.at(r.ref).mon)
				gs.bag[id] -= 1
				close_bag.call()
				_push_choice({"kind": "item", "itemId": id, "partyIdx": active_idx}, id)
				return
			var ps := PartyScreen.new({"player": r.player, "party": party, "prompt": "Use %s on?" % it.name})
			ps.o.on_cancel = func() -> void: Game.pop(ps)
			ps.o.on_select = func(i: int) -> void:
				var m: Dictionary = party[i]
				var eff: Dictionary = it.effect
				var useful := false
				if m.get("egg", false):
					useful = false
				elif eff.kind == "revive":
					useful = m.hp <= 0
				elif eff.kind == "heal":
					useful = m.hp > 0 and m.hp < Creatures.max_hp(m)
				elif eff.kind == "fullRestore":
					useful = m.hp > 0 and (m.hp < Creatures.max_hp(m) or m.status != null)
				elif eff.kind == "pp":
					useful = m.moves.any(func(ms: Dictionary) -> bool: return ms.pp < ms.maxPp)
				else:
					useful = eff.kind == "cure" and m.hp > 0 and m.status != null and (eff.statuses as Array).has(m.status)
				if not useful:
					Game.say(["It won't have any effect."], Callable(), r.player)
					return
				var use := func(move_idx: int) -> void:
					gs.bag[id] -= 1
					Game.pop(ps)
					close_bag.call()
					_push_choice({"kind": "item", "itemId": id, "partyIdx": i, "moveIdx": move_idx}, id)
				if eff.kind == "pp" and not eff.get("all", false):
					Menus.pick_move(m, r.player, "Restore which move?", func(k: int) -> void: use.call(k))
					return
				use.call(0)
			Game.push(ps),
	})

# ---------- drawing ----------
func _pos(side: int, slot: int) -> Dictionary:
	var d: bool = battle.double
	if side == 1:
		if d:
			return {"x": 150 if slot == 0 else 202, "y": 64 - (0 if slot == 0 else 5), "scale": 0.85}
		return {"x": 176, "y": 72, "scale": 1.0}
	if d:
		return {"x": 46 if slot == 0 else 100, "y": 114, "scale": 1.05}
	return {"x": 64, "y": 114, "scale": 1.25}

static func _ellipse(cx: float, cy: float, rx: float, ry: float, color: Variant) -> void:
	var pts := PackedVector2Array()
	for i in 48:
		var a := TAU * i / 48.0
		pts.append(Vector2(cx + cos(a) * rx, cy + sin(a) * ry))
	Gfx.ci.draw_colored_polygon(pts, Gfx.col(color))

static func _tex(tex: Texture2D, x: float, y: float, w: float, h: float, modulate: Color = Color.WHITE) -> void:
	Gfx.ci.draw_texture_rect(tex, Rect2(x, y, w, h), false, modulate)

## Platform colors (rim, inner) per battle backdrop.
const PLATFORMS := {
	"field": ["#a8d088", "#88b870"], "forest": ["#90c070", "#70a058"], "beach": ["#f0e0a8", "#d8c888"],
	"mountain": ["#c0b098", "#a09078"], "town": ["#d0c8b8", "#b0a898"], "gym": ["#e0d0b0", "#c0b090"],
	"league": ["#c8b8e8", "#a898d0"], "night": ["#6878a0", "#506088"],
}

## Which battle backdrop a map uses (assets/backdrops/<name>.png).
static func backdrop_for(m: Dictionary) -> String:
	var id: String = m.get("id", "")
	if id == "league":
		return "league"
	if id.begins_with("gym"):
		return "gym"
	if m.get("town", false) or not m.has("route"):
		return "town"
	return ["field", "forest", "field", "mountain", "forest", "beach", "field", "forest", "beach", "night", "field", "mountain"][(int(m.route) - 1) % 12]

func _plat(cx: float, cy: float, rx: float, ry: float) -> void:
	var c: Array = PLATFORMS.get(_setup.get("bg", "field"), PLATFORMS.field)
	_ellipse(cx, cy, rx, ry, c[0])
	_ellipse(cx, cy + 2, rx - 6, ry - 3, c[1])

func draw() -> void:
	# Background.
	var bg: String = _setup.get("bg", "field")
	var bg_tex := ArtAssets.texture("backdrops/" + bg)
	if bg_tex != null:
		Gfx.image(bg_tex, 0, 0)
	else:
		var top := Color("#f8f0d8")
		var bot := Color("#d8f0c0")
		Gfx.ci.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(Gfx.W, 0), Vector2(Gfx.W, 112), Vector2(0, 112)]),
			PackedColorArray([top, top, bot, bot]))
	var tm := Game.time
	if _weather == "rain":
		for i in 40:
			Gfx.rect(fmod(i * 37 + tm * 120, Gfx.W), fmod(i * 23 + tm * 300, 112), 1, 5, "#7090d0")
	if _weather == "sun":
		Gfx.rect(0, 0, Gfx.W, 112, Color(1, 200 / 255.0, 80 / 255.0, 0.15))
	if _weather == "hail":
		for i in 30:
			Gfx.rect(fmod(i * 41 + tm * 60, Gfx.W), fmod(i * 29 + tm * 200, 112), 2, 2, "#f0f8ff")
	if _weather == "sand":
		Gfx.rect(0, 0, Gfx.W, 112, Color(200 / 255.0, 160 / 255.0, 80 / 255.0, 0.2))
	var intro := (1 - minf(1, _intro_t / 0.7)) if _mode == "intro" else 0.0
	_plat(176 + intro * 140, 61 if battle.double else 70, 58 if battle.double else 48, 10)
	_plat(64 - intro * 140, 112, 60, 12)

	if _mode == "intro" and _setup.kind == "trainer":
		TrainerArt.draw_trainer_big(152 + intro * 140, 18, DB.PALETTES.get(_setup.trainer.palette, DB.PALETTES.boy), false, _setup.trainer.palette if DB.PALETTES.has(_setup.trainer.palette) else "boy")

	for side in [1, 0]:
		var slots: Array = _slots[side]
		for slot in slots.size():
			_draw_sprite(slots[slot], side, slot, intro)
	if _ball != null:
		_draw_ball()
	for side in [1, 0]:
		for slot in _slots[side].size():
			_draw_fx(_slots[side][slot], side, slot)

	# Target highlight.
	if _mode == "choose" and _menu == "target":
		var t: Dictionary = _target_list[_target_sel]
		var p := _pos(t.side, t.slot)
		var bob := int(Game.time * 4) % 2
		Gfx.cursor(p.x - 3, p.y - 44 * p.scale + bob, "#e04040")

	# Info boxes.
	var d: bool = battle.double
	for i in _slots[1].size():
		var s: Slot = _slots[1][i]
		if s.visible and s.view != null:
			_foe_box(s, 4 if d else 8, (4 + i * 26) if d else 10)
	for i in _slots[0].size():
		var s: Slot = _slots[0][i]
		if s.visible and s.view != null:
			_player_box(s, 126 if d else 124, (67 + i * 22) if d else 74, i)

	# Bottom box.
	_draw_bottom()
	if _level_panel != null:
		_draw_level_panel()

func _draw_sprite(s: Slot, side: int, slot: int, intro: float) -> void:
	if not s.visible or s.view == null or s.hidden:
		return
	var p := _pos(side, slot)
	var size: float = 64 * p.scale
	var spr: Texture2D = CreatureArt.creature_sprite(s.view.species, s.view.shiny, side == 0)
	var x: float = p.x - size / 2 + (intro * 140 if side == 1 else -intro * 140)
	var y: float = p.y - size + ((-6 + sin(Game.time * 2) * 2) if CreatureArt.is_floating(s.view.species) else 0.0)
	x += s.lunge * (8 if side == 0 else -8)
	var req_here := false
	if _mode == "choose" and _req_idx < _reqs.size():
		var rr: Dictionary = _reqs[_req_idx].ref
		req_here = rr.side == side and rr.slot == slot
	if req_here:
		y += int(Game.time * 4) % 2
	var scale_y := s.appear if s.appear < 1 else 1.0
	if s.faint > 0:
		# Sink below the platform line: only the part above p.y shows.
		var dy := y + s.faint * size
		var vis_h := clampf(p.y - dy, 0, size)
		if vis_h > 0:
			var src_h := vis_h / size * spr.get_height()
			Gfx.ci.draw_texture_rect_region(spr, Rect2(x, dy, size, vis_h), Rect2(0, 0, spr.get_width(), src_h))
		return
	if s.flash > 0 and int(s.flash * 8) % 2 == 1:
		return
	var h := size * scale_y
	if _ball != null and _ball.side == side and _ball.slot == slot and _ball.t > 0.5:
		return
	if scale_y < 1:
		_tex(CreatureArt.silhouette(spr, "#f8f8f8"), x, y + size - h, size, h)
	else:
		_tex(spr, x, y, size, size)
	if s.tint != null:
		var alpha := 0.5 * sin(s.tint.t * PI)
		_tex(CreatureArt.silhouette(spr, s.tint.color), x, y, size, size, Color(1, 1, 1, alpha))

## Shows a generated effect sprite (assets/fx/<name>.png) over a creature for dur seconds; Normal's for unknown types.
func _set_fx(sl: Slot, name: String, dur: float) -> void:
	var tex := ArtAssets.texture("fx/" + name)
	if tex == null and name.begins_with("fx_") and not name.begins_with("fx_stat") and name not in ["fx_heal", "fx_status"]:
		tex = ArtAssets.texture("fx/fx_normal")
	var rise := -10.0 if name in ["fx_stat_up", "fx_heal"] else (10.0 if name == "fx_stat_down" else 0.0)
	sl.fx = {"tex": tex, "t": 0.0, "dur": dur, "rise": rise} if tex != null else null

func _draw_fx(s: Slot, side: int, slot: int) -> void:
	if s.fx == null:
		return
	s.fx.t += 1.0 / 60
	var k: float = s.fx.t / s.fx.dur
	if k >= 1.0 or not s.visible:
		s.fx = null
		return
	var p := _pos(side, slot)
	var size: float = 48.0 * p.scale * (0.8 + 0.4 * k)
	var rise: float = s.fx.rise * k
	_tex(s.fx.tex, p.x - size / 2, p.y - 30 * p.scale - size / 2 + rise, size, size, Color(1, 1, 1, clampf(2.0 - 2.0 * k, 0, 1)))

func _gender_mark(g: Variant, x: float, y: float) -> void:
	if g != null:
		Gfx.text("♂" if g == "M" else "♀", x, y, {"size": 6, "color": "#3870e0" if g == "M" else "#e04870", "shadow": null})

func _foe_box(s: Slot, x: float, y: float) -> void:
	var v: Dictionary = s.view
	Gfx.panel(x, y, 104, 24, "battle")
	Gfx.status_badge(v.status, x + 64, y + 13)
	Gfx.text(v.name, x + 6, y + 4, {"size": 6})
	_gender_mark(v.gender, x + 72, y + 3)
	Gfx.text("Lv%d" % v.level, x + 98, y + 4, {"size": 6, "align": "right"})
	if battle.kind == "wild" and _gs.caught.has(v.species):
		Gfx.rect(x + 86, y + 14, 4, 4, "#e04040")
	Gfx.text("HP", x + 6, y + 14, {"size": 5, "color": "#e0a020"})
	var frac: float = s.shown_hp / v.maxHp
	Gfx.bar(x + 20, y + 15, 40, frac, Gfx.hp_color(frac), 3)

func _player_box(s: Slot, x: float, y: float, slot: int) -> void:
	var v: Dictionary = s.view
	var frac: float = s.shown_hp / v.maxHp
	if battle.double:
		Gfx.panel(x, y, 112, 21, "battle")
		Gfx.text(v.name, x + 5, y + 3, {"size": 5})
		Gfx.text("Lv%d" % v.level, x + 107, y + 3, {"size": 5, "align": "right"})
		Gfx.bar(x + 6, y + 12, 50, frac, Gfx.hp_color(frac), 3)
		Gfx.status_badge(v.status, x + 60, y + 10)
		Gfx.text("%d/%d" % [maxi(0, int(s.shown_hp)), v.maxHp], x + 107, y + 11, {"size": 5, "align": "right"})
		Gfx.rect(x + 6, y + 17, 50 * clampf(s.shown_exp, 0, 1), 1, "#40a0f0")
		if _gs.mode == "coop":
			Game.player_tag(slot, x - 20, y + 6)
		return
	Gfx.panel(x, y, 112, 34, "battle")
	Gfx.text(v.name, x + 6, y + 4, {"size": 6})
	_gender_mark(v.gender, x + 76, y + 3)
	Gfx.text("Lv%d" % v.level, x + 106, y + 4, {"size": 6, "align": "right"})
	Gfx.text("HP", x + 6, y + 14, {"size": 5, "color": "#e0a020"})
	Gfx.bar(x + 20, y + 15, 62, frac, Gfx.hp_color(frac), 3)
	Gfx.status_badge(v.status, x + 86, y + 13)
	Gfx.text("%d/%d" % [maxi(0, int(s.shown_hp)), v.maxHp], x + 106, y + 21, {"size": 5, "align": "right"})
	Gfx.bar(x + 6, y + 30, 100, s.shown_exp, "#40a0f0", 1)

func _draw_ball() -> void:
	var b: Dictionary = _ball
	var p := _pos(b.side, b.slot)
	var t: float = b.t
	var bx: float
	var by: float
	if t < 0.5:
		var k := t / 0.5
		bx = 40 + (p.x - 40) * k
		by = 110 + (p.y - 40 - 110) * k - sin(k * PI) * 40
	else:
		bx = p.x
		var shake_t := t - 0.6
		var shaking: bool = shake_t > 0 and shake_t < b.shakes * 0.5
		bx += sin(shake_t * PI * 4) * 3 if shaking else 0.0
		by = p.y - 8
	var orb := ArtAssets.texture("icons/" + str(b.get("item", "orb")))
	if orb == null:
		orb = ArtAssets.texture("icons/orb")
	if orb != null:
		Gfx.image(orb, bx - 8, by - 8, {"scale": 16.0 / orb.get_width()})
		if b.caught and t > 0.6 + b.shakes * 0.5:
			for i in 3:
				Gfx.rect(bx - 10 + i * 9, by - 12 - fmod(t * 10, 4), 2, 2, "#f8e040")
		return
	# Capture Orb: a round teal orb with a gold band.
	Gfx.rect(bx - 3, by - 5, 6, 10, "#205860")
	Gfx.rect(bx - 5, by - 3, 10, 6, "#205860")
	Gfx.rect(bx - 4, by - 4, 8, 8, "#38b8c0")
	Gfx.rect(bx - 3, by - 3, 3, 2, "#a8f0f0")
	Gfx.rect(bx - 5, by, 10, 1, "#f0c040")
	Gfx.rect(bx - 1, by - 1, 2, 3, "#f8e890")
	if b.caught and t > 0.6 + b.shakes * 0.5:
		for i in 3:
			Gfx.rect(bx - 10 + i * 9, by - 12 - fmod(t * 10, 4), 2, 2, "#f8e040")

func _draw_bottom() -> void:
	var choose_req: Variant = _reqs[_req_idx] if _mode == "choose" else null
	if choose_req != null and _menu != "action":
		var mon: Dictionary = battle.at(choose_req.ref).mon
		Gfx.panel(0, 112, 160, 48, "battle")
		Gfx.panel(160, 112, 80, 48, "battle")
		if _menu == "move" or _menu == "target":
			var moves: Array = mon.moves
			for i in moves.size():
				var mslot: Dictionary = moves[i]
				var x := 14 + (i % 2) * 74
				var y := 124 + (i / 2) * 16
				Gfx.text(DB.move(mslot.id).name, x, y, {"size": 6, "color": "#303030" if mslot.pp else "#a0a0a0"})
				if i == _move_sel:
					Gfx.cursor(x - 8, y)
			var ms: Dictionary = moves[_pending_move if _menu == "target" else _move_sel]
			var mv: Dictionary = DB.move(ms.id)
			Gfx.text("PP %d/%d" % [ms.pp, ms.maxPp], 168, 122, {"size": 6, "color": "#e04040" if float(ms.pp) / ms.maxPp <= 0.25 else "#303030"})
			Gfx.rect(168, 134, 64, 9, DB.TYPE_COLORS[mv.type])
			Gfx.text(mv.type.to_upper(), 200, 136, {"size": 5, "color": "#ffffff", "align": "center", "shadow": Color(0, 0, 0, 0.4)})
			var pow_s := ("POW %d" % mv.power) if mv.power > 1 else ("POW --" if mv.power == 1 else "STATUS")
			Gfx.text(pow_s, 168, 148, {"size": 5, "color": "#606870"})
			if _menu == "target":
				var t = battle.at(_target_list[_target_sel])
				Gfx.rect(0, 100, 160, 12, Color(40 / 255.0, 40 / 255.0, 60 / 255.0, 0.85))
				var tname: String = Creatures.display_name(t.mon) if t.mon != null else "?"
				Gfx.text("Target: %s%s" % [tname, " (ally)" if t.side == 0 else ""], 6, 103, {"size": 5, "color": "#ffffff", "shadow": null})
		Game.player_tag(choose_req.player, 136, 114)
		return
	Gfx.panel(0, 112, Gfx.W, 48, "dark")
	if choose_req != null:
		var mon: Dictionary = battle.at(choose_req.ref).mon
		var lines := Gfx.wrap("What will %s do?" % Creatures.display_name(mon), 108, 7)
		for i in lines.size():
			Gfx.text(lines[i], 10, 122 + i * 14, {"color": "#f8f8f8", "shadow": Color(0, 0, 0, 0.5)})
		Gfx.panel(122, 114, 116, 44, "battle")
		var labels := ["ORB x%d" % _safari_balls(), "BAIT", "ROCK", "RUN"] if battle.kind == "safari" else ["FIGHT", "BAG", "PARTY", "RUN"]
		for i in labels.size():
			var x := 136 + (i % 2) * 54
			var y := 124 + (i / 2) * 16
			Gfx.text(labels[i], x, y, {"size": 7})
			if i == _action_sel:
				Gfx.cursor(x - 9, y + 0.5, "#3878e0" if choose_req.player == 1 else "#e04848")
		Game.player_tag(choose_req.player, 100, 114)
		return
	if _message != "":
		var left := int(_msg_shown)
		var lines := Gfx.wrap(_message, 218, 7)
		for i in lines.size():
			var ln: String = lines[i]
			Gfx.text(ln.substr(0, maxi(0, left)), 10, 122 + i * 14, {"color": "#f8f8f8", "shadow": Color(0, 0, 0, 0.5)})
			left -= ln.length() + 1

func _draw_level_panel() -> void:
	var p: Dictionary = _level_panel
	Gfx.panel(130, 4, 106, 84)
	var rows := [["MAX HP", "hp"], ["ATTACK", "atk"], ["DEFENSE", "def"], ["SP. ATK", "spa"], ["SP. DEF", "spd"], ["SPEED", "spe"]]
	for i in rows.size():
		var k: String = rows[i][1]
		Gfx.text(rows[i][0], 138, 12 + i * 12, {"size": 5})
		Gfx.text(str(p.now[k]), 210, 12 + i * 12, {"size": 5, "align": "right"})
		Gfx.text("+%d" % (p.now[k] - p.old[k]), 230, 12 + i * 12, {"size": 5, "align": "right", "color": "#d04040"})
