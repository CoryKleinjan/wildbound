class_name GameState
## The save state (a plain Dictionary with the TS GameState keys) and its save file.
## GameState: {version, mode ("solo" | "coop"), players: [{name, party, otId}], box, bag, money, map, x, y, dir,
## respawn: {map, x, y}, flags, seen, caught, playTime,
## Emerald additions (see _extra): daycare {mons, steps, egg}, berries {map: {"x,y": {berry, planted, watered}}},
## repel (steps left), bike (riding), safari (null or {steps, balls}), secretBase (null or {map, x, y, decor}),
## decor (owned decoration ids), bp (Battle Points), tower {streak, best}, roamers {species: {map, level, hp}},
## steps, rematch {trainer id: times beaten again}, fly (unlocked towns), pcItems {item: count}, mailbox [mail],
## hallOfFame [{date, team}], coins, frontier {facility: {streak, best}}, pyramid (null or the run in progress),
## trick {level, spot}, matchCall (registered trainer ids), calls (queued Match Call messages), lastDay, trades}

static var SAVE_PATH := "user://wildbound-save.json"

## A new game before the starter event: players have names but no creatures yet.
static func new_game(mode: String, names: Array = []) -> Dictionary:
	var players: Array = []
	for i in (2 if mode == "coop" else 1):
		var default_name: String = ["Wren", "Juno"][i]
		players.append({
			"name": names[i] if i < names.size() and names[i] != "" else default_name,
			"otId": Rng.global_rng.u32(),
			"party": [],
		})
	return {
		"version": 1,
		"mode": mode,
		"players": players,
		"box": [],
		"bag": {"potion": 4},
		"money": 3000,
		"map": "fernhollow_home",
		"x": 6,
		"y": 4,
		"dir": "down",
		"respawn": {"map": "fernhollow_lodge", "x": 6, "y": 4},
		"flags": {},
		"seen": [],
		"caught": [],
		"playTime": 0.0,
	}.merged(_extra())

static func _extra() -> Dictionary:
	return {
		"daycare": {"mons": [], "steps": 0, "egg": false},
		"berries": {},
		"repel": 0,
		"bike": false,
		"safari": null,
		"secretBase": null,
		"decor": [],
		"bp": 0,
		"tower": {"streak": 0, "best": 0},
		"roamers": {},
		"steps": 0,
		"rematch": {},
		"fly": ["fernhollow"],
		"contest": {},
		"pcItems": {"potion": 1},
		"mailbox": [],
		"hallOfFame": [],
		"coins": 0,
		"frontier": {},
		"pyramid": null,
		"trick": {"level": 0, "spot": ""},
		"matchCall": [],
		"calls": [],
		"lastDay": 0,
		"trades": 0,
	}

## Gives a player their first creature (from PROF. ALDER's bag).
static func give_starter(gs: Dictionary, player: int, sp: String) -> void:
	var p: Dictionary = gs.players[player]
	p.party.append(Creatures.create_creature(sp, 5, {"owner": player, "otId": p.otId}))
	for list in [gs.seen, gs.caught]:
		if not list.has(sp):
			list.append(sp)

static func party_cap(gs: Dictionary) -> int:
	return 3 if gs.mode == "coop" else 6

static func all_party_mons(gs: Dictionary) -> Array:
	var out: Array = []
	for p in gs.players:
		out.append_array(p.party)
	return out

## Puts a newly caught creature in its catcher's party, or in storage when the party is full.
static func receive_creature(gs: Dictionary, mon: Dictionary, player: int) -> String:
	var p: Dictionary = gs.players[mini(player, gs.players.size() - 1)]
	Creatures.migrate(mon)
	if not gs.caught.has(mon.species):
		gs.caught.append(mon.species)
	if p.party.size() < party_cap(gs):
		p.party.append(mon)
		return "party"
	gs.box.append(mon)
	return "box"

static func save(gs: Dictionary) -> bool:
	# A joined friend's progress is saved on their own computer.
	if Game.cur == 1:
		Net.sync_guest()
		return true
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(gs))
	f.close()
	return true

static func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

static func load_game() -> Variant:
	if not FileAccess.file_exists(SAVE_PATH):
		return null
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return null
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not parsed is Dictionary or not parsed.has("players"):
		return null
	var gs: Dictionary = DB._fix_ints(parsed)
	gs.playTime = float(gs.get("playTime", 0.0))
	# Old shared-keyboard co-op saves: player 2's creatures go to storage.
	if gs.mode == "coop":
		for p in gs.players.slice(1):
			gs.box.append_array(p.party)
		gs.players = [gs.players[0]]
		gs.mode = "solo"
		for m in gs.players[0].party + gs.box:
			m.owner = 0
	# Saves from before the story existed already have their starters.
	if not gs.flags.has("starter") and not all_party_mons(gs).is_empty():
		gs.flags.starter = true
	# Saves from before the Emerald features get the new fields.
	var extra := _extra()
	for k in extra:
		if not gs.has(k):
			gs[k] = extra[k]
	for m in all_party_mons(gs) + gs.box + gs.daycare.mons:
		Creatures.migrate(m)
	var max_uid := 0
	for m in all_party_mons(gs) + gs.box + gs.daycare.mons:
		max_uid = maxi(max_uid, m.uid)
	Creatures.set_next_uid(max_uid + 1)
	# A save made inside the Battle Pyramid: the run is over, and the real team and bag come back.
	Frontier.restore_after_load(gs)
	return gs

# ---------------------------------------------------------------- drop-in co-op
## The save state for a friend joining host_gs's world (see Net). Their trainer, creatures, items
## and money come from their own save (checked, since it arrives over the network); position and
## story/trainer flags are the host's. flags is the host's own dictionary, so the world is shared.
static func guest_state(save: Variant, name: String, host_gs: Dictionary) -> Dictionary:
	var gs := new_game("solo", [name if name != "" else "Juno"])
	if save is Dictionary:
		var s: Dictionary = save
		var pl: Variant = s.get("players", [])
		if pl is Array and pl.size() > 0 and pl[0] is Dictionary:
			var p: Dictionary = pl[0]
			if p.get("name") is String and p.name != "":
				gs.players[0].name = (p.name as String).substr(0, 8)
			if p.get("otId") is int:
				gs.players[0].otId = p.otId
			gs.players[0].party = _valid_mons(p.get("party"), 6)
		gs.box = _valid_mons(s.get("box"), 600)
		var bag: Variant = s.get("bag")
		if bag is Dictionary:
			gs.bag = {}
			for k in bag:
				if k is String and DB.ITEMS.has(k) and bag[k] is int and bag[k] > 0:
					gs.bag[k] = mini(bag[k], 999)
		if s.get("money") is int:
			gs.money = clampi(s.money, 0, 999999)
		for key in ["seen", "caught"]:
			var list: Variant = s.get(key)
			if list is Array:
				gs[key] = list.filter(func(sp: Variant) -> bool: return sp is String and DB.SPECIES.has(sp))
		if s.get("playTime") is float or s.get("playTime") is int:
			gs.playTime = float(s.playTime)
		if s.get("bp") is int:
			gs.bp = clampi(s.bp, 0, 9999)
		var decor: Variant = s.get("decor")
		if decor is Array:
			gs.decor = decor.filter(func(d: Variant) -> bool: return d is String and DB.DECORATIONS.has(d))
		if s.get("coins") is int:
			gs.coins = clampi(s.coins, 0, 9999)
		var pc: Variant = s.get("pcItems")
		if pc is Dictionary:
			gs.pcItems = {}
			for k in pc:
				if k is String and DB.ITEMS.has(k) and pc[k] is int and pc[k] > 0:
					gs.pcItems[k] = mini(pc[k], 999)
	# Fresh ids, so they can't clash with the host's creatures.
	for m in gs.players[0].party + gs.box:
		Creatures.migrate(m)
		m.uid = Creatures.next_uid
		Creatures.next_uid += 1
		m.owner = 0
	gs.map = host_gs.map
	gs.x = host_gs.x
	gs.y = host_gs.y
	gs.dir = host_gs.dir
	gs.respawn = host_gs.respawn.duplicate()
	gs.flags = host_gs.flags
	return gs

const _MON_KEYS := {
	"uid": TYPE_INT, "species": TYPE_STRING, "level": TYPE_INT, "exp": TYPE_INT, "personality": TYPE_INT,
	"otId": TYPE_INT, "ivs": TYPE_DICTIONARY, "evs": TYPE_DICTIONARY, "moves": TYPE_ARRAY, "hp": TYPE_INT,
	"sleepTurns": TYPE_INT, "toxicCount": TYPE_INT,
}

static func _valid_mons(list: Variant, cap: int) -> Array:
	var out: Array = []
	if not list is Array:
		return out
	for m in list:
		if out.size() < cap and _valid_mon(m):
			out.append((m as Dictionary).duplicate(true))
	return out

static func _valid_mon(m: Variant) -> bool:
	if not m is Dictionary:
		return false
	for k in _MON_KEYS:
		if typeof(m.get(k)) != _MON_KEYS[k]:
			return false
	if not DB.SPECIES.has(m.species) or m.level < 1 or m.level > 100 or m.hp < 0:
		return false
	for k in DB.STAT_KEYS:
		if not m.ivs.get(k) is int or not m.evs.get(k) is int:
			return false
	if m.moves.is_empty() or m.moves.size() > 4:
		return false
	for mv in m.moves:
		if not mv is Dictionary or not DB.MOVES.has(mv.get("id")) or not mv.get("pp") is int or not mv.get("maxPp") is int:
			return false
	var st: Variant = m.get("status")
	if st != null and not (st is String and (st == "" or Gfx.STATUS_LABEL.has(st))):
		return false
	var nick: Variant = m.get("nickname")
	if nick != null and not nick is String:
		return false
	var item: Variant = m.get("item")
	if item != null and not (item is String and DB.ITEMS.has(item)):
		return false
	for k in ["friendship", "eggSteps", "metLevel"]:
		if m.has(k) and not m[k] is int:
			return false
	if m.has("egg") and not m.egg is bool:
		return false
	if m.has("ribbons") and not m.ribbons is Array:
		return false
	if m.has("condition") and not m.condition is Dictionary:
		return false
	var pk: Variant = m.get("pkrs")
	if pk != null and not (pk is Dictionary and pk.get("strain") is int and pk.get("days") is int):
		return false
	var mail: Variant = m.get("mail")
	if mail != null and not (mail is Dictionary and mail.get("text") is String and (mail.text as String).length() <= 120
			and mail.get("from") is String and mail.get("item") is String and DB.ITEMS.has(mail.item)):
		return false
	return true

## On a friend's computer: saves the progress the host sent (own: OWN_KEYS of their state in the
## host's world) into this computer's save, keeping this computer's own map, position and flags.
static func save_progress_from_host(own: Dictionary, name: String) -> void:
	var gs: Variant = load_game()
	if gs == null:
		gs = new_game("solo", [name])
		# They have their creatures already, so skip the starter event at home.
		gs.flags.starter = true
		gs.flags.intro_mom = true
	var incoming := guest_state(own, name, gs)
	for k in Net.OWN_KEYS:
		gs[k] = incoming[k]
	if not gs.players[0].party.is_empty():
		gs.flags.starter = true
	save(gs)
