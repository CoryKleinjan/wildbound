class_name DayCare
## The Day Care in Harrowfield and eggs. Two creatures left there gain 1 EXP per step; if they share an egg
## group and are of opposite genders, the Day Care Man may find an Egg (checked every 256 steps, Gen 3 odds).
## The baby is the first form of the mother's line, with three IVs passed down, egg moves from the father,
## and the mother's nature half the time when she holds an Everstone.

const PRICE_BASE := 100

static func on_step(gs: Dictionary) -> void:
	var dc: Dictionary = gs.daycare
	if dc.mons.is_empty():
		return
	dc.steps = int(dc.steps) + 1
	for m in dc.mons:
		if m.level < 100:
			# Level-ups at the Day Care learn new moves by pushing out the oldest one, as in Gen 3.
			for up in Creatures.gain_exp(m, 1):
				for id in up.pending:
					m.moves.pop_front()
					m.moves.append(Creatures.move_slot(id))
	if dc.mons.size() == 2 and not dc.egg and int(dc.steps) % 256 == 0:
		var chance := compatibility(dc.mons[0], dc.mons[1])
		if chance > 0 and Rng.global_rng.int_below(100) < chance:
			dc.egg = true

## Percent chance per check of an egg: 0 if they can't breed.
static func compatibility(a: Dictionary, b: Dictionary) -> int:
	var sa: Dictionary = DB.species(a.species)
	var sb: Dictionary = DB.species(b.species)
	if sa.get("rarity", "") == "legendary" or sb.get("rarity", "") == "legendary":
		return 0
	var ga: Variant = Creatures.gender_of(a)
	var gb: Variant = Creatures.gender_of(b)
	if ga == null or gb == null or ga == gb:
		return 0
	var shared := false
	for g in sa.get("eggGroups", []):
		if (sb.get("eggGroups", []) as Array).has(g) and g != "Undiscovered":
			shared = true
	if not shared:
		return 0
	var same_ot: bool = int(a.otId) == int(b.otId)
	if a.species == b.species:
		return 50 if same_ot else 70
	return 20 if same_ot else 50

## The first form of a species' evolution line.
static func base_form(sp: String) -> String:
	var cur := sp
	for i in 4:
		var found := ""
		for id in DB.SPECIES:
			var e: Variant = DB.SPECIES[id].get("evolves", null)
			if e and e.into == cur:
				found = id
				break
		if found == "":
			break
		cur = found
	return cur

static func make_egg(gs: Dictionary) -> Dictionary:
	var a: Dictionary = gs.daycare.mons[0]
	var b: Dictionary = gs.daycare.mons[1]
	var mother: Dictionary = a if Creatures.gender_of(a) == "F" else b
	var father: Dictionary = b if is_same(mother, a) else a
	var sp := base_form(mother.species)
	var rng := Rng.global_rng
	var opts := {"owner": 0, "otId": gs.players[0].otId}
	var egg := Creatures.create_creature(sp, 5, opts)
	# Three stats inherit an IV from a random parent.
	var stats: Array = DB.STAT_KEYS.duplicate()
	for i in 3:
		var k: String = stats.pop_at(rng.int_below(stats.size()))
		egg.ivs[k] = (mother if rng.int_below(2) == 0 else father).ivs[k]
	if mother.get("item", null) == "everstone" and rng.int_below(2) == 0:
		var p: int = int(egg.personality) & 0x7FFFFFFF
		egg.personality = p - (p % 25) + Creatures.nature_of(mother)
	# Egg moves the father knows replace the newest default moves.
	for id in DB.species(sp).get("eggMoves", []):
		if Creatures.knows(father, id) and not Creatures.knows(egg, id):
			if egg.moves.size() >= 4:
				egg.moves.pop_back()
			egg.moves.append(Creatures.move_slot(id))
	egg.hp = Creatures.max_hp(egg)
	egg.egg = true
	egg.eggSteps = int(DB.species(sp).get("eggCycles", 20)) * 256
	egg.friendship = 120
	egg.metLevel = 0
	return egg

# ---------- the Day Care Lady (inside) ----------
static func lady() -> void:
	var gs: Dictionary = Game.gs
	var dc: Dictionary = gs.daycare
	var opts: Array = []
	if dc.mons.size() < 2:
		opts.append("LEAVE ONE")
	if not dc.mons.is_empty():
		opts.append("TAKE BACK")
	opts.append("CANCEL")
	var lines := "Would you like us to raise one of your creatures?"
	if not dc.mons.is_empty():
		var names: PackedStringArray = []
		for m in dc.mons:
			names.append("%s (Lv%d)" % [Creatures.display_name(m), m.level])
		lines = "We're raising %s for you. What would you like to do?" % " and ".join(names)
	Game.ask(lines, opts, func(c: int) -> void:
		if opts[c] == "LEAVE ONE":
			_deposit()
		elif opts[c] == "TAKE BACK":
			_withdraw())

static func _deposit() -> void:
	var gs: Dictionary = Game.gs
	var party: Array = gs.players[0].party
	Services.pick_creature("Leave which creature?", func(m: Dictionary) -> String:
		var others := 0
		for x in party:
			if not is_same(x, m) and Battle.can_battle(x):
				others += 1
		return "" if others > 0 else "If you leave that one, you won't have any creatures to battle with!",
	func(m: Dictionary) -> void:
		party.erase(m)
		m.dcLevel = m.level
		Creatures.heal_fully(m)
		gs.daycare.mons.append(m)
		Game.say(["Fine, we'll raise your %s for a while." % Creatures.display_name(m), "Come back for it later."]))

static func _withdraw() -> void:
	var gs: Dictionary = Game.gs
	var dc: Dictionary = gs.daycare
	var party: Array = gs.players[0].party
	if party.size() >= GameState.party_cap(gs):
		Game.say(["Your party is full. Come back when you have room."])
		return
	var items: Array = []
	for m in dc.mons:
		var gained: int = int(m.level) - int(m.get("dcLevel", m.level))
		items.append({"label": Creatures.display_name(m), "right": "$%d" % (PRICE_BASE + PRICE_BASE * gained)})
	items.append({"label": "CANCEL"})
	var ref := {}
	var menu := ListMenu.new({
		"x": 100, "y": 20, "w": 136, "player": 0, "title": "Take back which?", "items": items,
		"on_cancel": func() -> void: Game.pop(ref.menu),
		"on_select": func(i: int) -> void:
			Game.pop(ref.menu)
			if i >= dc.mons.size():
				return
			var m: Dictionary = dc.mons[i]
			var gained: int = int(m.level) - int(m.get("dcLevel", m.level))
			var price: int = PRICE_BASE + PRICE_BASE * gained
			if gs.money < price:
				Game.say(["You don't have enough money."])
				return
			gs.money -= price
			dc.mons.remove_at(i)
			m.erase("dcLevel")
			Creatures.heal_fully(m)
			party.append(m)
			var lines: Array = ["%s took back %s for $%d." % [gs.players[0].name, Creatures.display_name(m), price]]
			if gained > 0:
				lines.insert(0, "Your %s has grown %d level(s)!" % [Creatures.display_name(m), gained])
			Game.say(lines),
	})
	ref.menu = menu
	Game.push(menu)

# ---------- the Day Care Man (outside) ----------
static func man(text: Array) -> void:
	var gs: Dictionary = Game.gs
	var dc: Dictionary = gs.daycare
	if dc.egg:
		Game.ask("Ah, it's you! We were raising your creatures, and my word, we found an Egg! Do you want it?", ["YES", "NO"], func(c: int) -> void:
			if c != 0:
				Game.ask("Are you sure? I'll keep it for you, then.", ["OK"], func(_k: int) -> void: pass)
				return
			if gs.players[0].party.size() >= GameState.party_cap(gs):
				Game.say(["You have no room for it... Come back when you've made room."])
				return
			dc.egg = false
			gs.players[0].party.append(make_egg(gs))
			Audio.sfx("item")
			Game.say(["%s received the Egg from the Day Care Man!" % gs.players[0].name, "Take good care of it."]))
		return
	var lines: Array = text.duplicate()
	if dc.mons.size() == 2:
		var c := compatibility(dc.mons[0], dc.mons[1])
		lines.append(["The two prefer to play with other creatures than each other.", "The two don't really seem to like each other.",
			"The two seem to get along.", "The two seem to get along very well!"][0 if c == 0 else (1 if c <= 20 else (2 if c <= 50 else 3))])
	elif dc.mons.size() == 1:
		lines.append("Your %s is doing just fine." % Creatures.display_name(dc.mons[0]))
	else:
		lines.append("My wife runs the Day Care inside. Leave two creatures with her and they might find an Egg!")
	Game.say(lines)
