class_name GameState
## The save state (a plain Dictionary with the TS GameState keys) and its save file.
## GameState: {version, mode ("solo" | "coop"), players: [{name, party, otId}], box, bag, money, map, x, y, dir,
## respawn: {map, x, y}, flags, seen, caught, playTime}

const SAVE_PATH := "user://wildbound-save.json"

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
	if not gs.caught.has(mon.species):
		gs.caught.append(mon.species)
	if p.party.size() < party_cap(gs):
		p.party.append(mon)
		return "party"
	gs.box.append(mon)
	return "box"

static func save(gs: Dictionary) -> bool:
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
	# Saves from before the story existed already have their starters.
	if not gs.flags.has("starter") and not all_party_mons(gs).is_empty():
		gs.flags.starter = true
	var max_uid := 0
	for m in all_party_mons(gs) + gs.box:
		max_uid = maxi(max_uid, m.uid)
	Creatures.set_next_uid(max_uid + 1)
	return gs
