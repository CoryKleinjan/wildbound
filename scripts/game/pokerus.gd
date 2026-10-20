class_name Pokerus
## Pokérus, as in Gen 3: a rare, harmless virus (3 in 65536 per battle) that doubles the effort points a creature
## earns. It spreads to the creatures next to an infected one in the party after battles, and wears off after 1-4
## days in the party (creatures in storage keep it). Once cured, a creature keeps the doubled effort points and
## can't catch it again. A creature's pkrs is null, or {strain, days}.

static func infected(m: Dictionary) -> bool:
	var p: Variant = m.get("pkrs", null)
	return p != null and int(p.days) > 0

static func ever_had(m: Dictionary) -> bool:
	return m.get("pkrs", null) != null

static func infect(m: Dictionary, strain: int) -> void:
	m.pkrs = {"strain": strain, "days": strain % 4 + 1}

## After a battle: maybe a new infection, then spreading to neighbours in the party.
static func after_battle(_gs: Dictionary, party: Array, _msgs: Array) -> void:
	var mons: Array = party.filter(func(m: Dictionary) -> bool: return not m.get("egg", false))
	if mons.is_empty():
		return
	if Rng.global_rng.int_below(65536) < 3:
		var m: Dictionary = mons[Rng.global_rng.int_below(mons.size())]
		if not ever_had(m):
			infect(m, 1 + Rng.global_rng.int_below(15))
	for i in party.size():
		var m: Dictionary = party[i]
		if not infected(m) or Rng.global_rng.int_below(3) != 0:
			continue
		for j in [i - 1, i + 1]:
			if j >= 0 and j < party.size() and not ever_had(party[j]) and not party[j].get("egg", false):
				party[j].pkrs = m.pkrs.duplicate()

## Counts days down for the creatures in the party.
static func on_step(gs: Dictionary) -> void:
	var today := Options.today()
	var last := int(gs.get("lastDay", 0))
	if last == today:
		return
	gs.lastDay = today
	if last == 0 or today < last:
		return
	for m in gs.players[0].party:
		if infected(m):
			m.pkrs.days = maxi(0, int(m.pkrs.days) - (today - last))

## What the Rest Lodge nurse says the first time she notices it.
static func nurse_lines(gs: Dictionary) -> Array:
	if gs.flags.get("pkrs_told", false):
		return []
	for m in gs.players[0].party:
		if infected(m):
			gs.flags.pkrs_told = true
			return ["Your %s appears to be infected with Pokérus." % Creatures.display_name(m),
				"Little is known about it, except that it's a microscopic life-form that attaches to creatures.",
				"While infected, creatures are said to grow exceptionally well."]
	return []
