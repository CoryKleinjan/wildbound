class_name RecordMix
## Record Mixing: when a friend joins over the LAN, each of you gets the other's records. They show up on the TV,
## a newer trendy phrase spreads to both worlds, and a friend's team can appear in the Battle Tower.

const KEEP := 5

## A trainer's record card.
static func card(gs: Dictionary) -> Dictionary:
	var party: Array = []
	for m in gs.players[0].party:
		if not m.get("egg", false) and party.size() < 3:
			party.append(m.species)
	return {"name": gs.players[0].name, "otId": int(gs.players[0].otId), "tower": int(gs.tower.get("best", 0)),
		"lead": party[0] if party.size() else "", "party": party, "trendy": String(gs.get("trendy", "")), "day": Options.today()}

## Only well-formed cards from a friend's save are kept.
static func valid(c: Variant) -> bool:
	if not c is Dictionary:
		return false
	if not (c.get("name") is String and c.get("party") is Array and c.get("tower") is int and c.get("otId") is int):
		return false
	for sp in c.party:
		if not sp is String or not DB.SPECIES.has(sp):
			return false
	return (c.name as String).length() <= 12 and c.party.size() <= 3

static func _add(gs: Dictionary, c: Dictionary) -> void:
	var list: Array = gs.get("mixed", []).filter(func(r: Dictionary) -> bool: return int(r.otId) != int(c.otId))
	list.push_front(c)
	gs.mixed = list.slice(0, KEEP)

## Mixes the host's and the friend's records. friend_save: the friend's own save, as they sent it.
static func mix(host_gs: Dictionary, guest_gs: Dictionary, friend_save: Variant) -> void:
	var theirs := card(guest_gs)
	if friend_save is Dictionary:
		var tw: Variant = friend_save.get("tower")
		if tw is Dictionary and tw.get("best") is int:
			theirs.tower = clampi(tw.best, 0, 9999)
		var tr: Variant = friend_save.get("trendy")
		if tr is String and tr != "":
			theirs.trendy = (tr as String).substr(0, 24)
	_add(host_gs, theirs)
	_add(guest_gs, card(host_gs))
	# One of the two trendy phrases (a coin flip) catches on in both worlds.
	if theirs.trendy != "" and theirs.trendy != host_gs.trendy and Rng.global_rng.int_below(2) == 0:
		host_gs.trendy = theirs.trendy
	guest_gs.trendy = host_gs.trendy

## A friend's team for the Battle Tower, sometimes: {trainer, party} or {}.
static func tower_opponent(gs: Dictionary, level: int) -> Dictionary:
	var list: Array = gs.get("mixed", []).filter(func(r: Dictionary) -> bool: return r.party.size() == 3)
	if list.is_empty() or Rng.global_rng.int_below(4) != 0:
		return {}
	var r: Dictionary = list[Rng.global_rng.int_below(list.size())]
	var party: Array = []
	for sp in r.party:
		party.append(Creatures.create_creature(sp, level, {"owner": 9}))
	return {"trainer": {"id": "tower", "name": r.name, "palette": "ace", "pay": 0,
		"intro": "Remember me? I've been training since we mixed records!", "defeat": "You're as strong as ever!"}, "party": party}
