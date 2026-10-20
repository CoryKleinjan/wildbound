class_name Trade
## Trading: in-game trades with townsfolk, and trades with a friend who has joined your world (both on the same
## map). Creatures that evolve by trade evolve when they arrive, unless they hold an Everstone.

static func npc_trade(npc: Dictionary) -> void:
	var gs: Dictionary = Game.gs
	if gs.flags.get(npc.flag, false):
		Game.say(["How's my old %s doing? I love the %s you gave me!" % [npc.nickname, DB.species(npc.want).name]])
		return
	var want: String = npc.want
	var give: String = npc.give
	Game.ask("I'm looking for a %s. Would you trade it for my %s?" % [DB.species(want).name, DB.species(give).name], ["YES", "NO"], func(c: int) -> void:
		if c != 0:
			Game.say(["Oh, well. Let me know if you change your mind."])
			return
		Services.pick_creature("Trade which creature?", func(m: Dictionary) -> String:
			return "" if m.species == want else "That's not a %s." % DB.species(want).name,
		func(m: Dictionary) -> void:
			var party: Array = gs.players[0].party
			var got := Creatures.create_creature(give, m.level, {"owner": 0})
			got.nickname = npc.nickname
			if m.get("item", null) != null:
				gs.bag[m.item] = gs.bag.get(m.item, 0) + 1
			party[party.find(m)] = got
			gs.flags[npc.flag] = true
			for list in [gs.seen, gs.caught]:
				if not list.has(give):
					list.append(give)
			Audio.sfx("item")
			var scene := TradeScene.new(m.species, give)
			Game.push(scene)
			Game.say(["%s traded %s for %s!" % [gs.players[0].name, Creatures.display_name(m), npc.nickname], "Take good care of it!"], func() -> void:
				Game.pop(scene)
				_trade_evolve(got, 0))))

static func _trade_evolve(m: Dictionary, player: int) -> void:
	var into: Variant = Creatures.pending_evolution(m, "trade")
	if into != null:
		EvolutionScene.new(m, into, player, func() -> void: pass)

## From the CO-OP menu: offer a trade to the friend in your world when you're on the same map.
static func offer_coop(o: OverworldScene) -> void:
	if not Net.guest_in_world():
		return
	var other := Game.other_overworld()
	if other == null or other.map.id != o.map.id:
		return
	var me := Game.cur
	var them := 1 - me
	var my_gs: Dictionary = Game.views[me].gs
	var their_gs: Dictionary = Game.views[them].gs
	var their_name: String = their_gs.players[0].name
	var my_name: String = my_gs.players[0].name
	Game.ask("Trade creatures with %s?" % their_name, ["YES", "NO"], func(c: int) -> void:
		if c != 0:
			return
		var mine_party: Array = my_gs.players[0].party
		var ps := PartyScreen.new({"player": 0, "party": mine_party, "prompt": "Offer which creature?"})
		ps.o.on_cancel = func() -> void: Game.pop(ps)
		ps.o.on_select = func(i: int) -> void:
			var mine: Dictionary = mine_party[i]
			if _last_battler(mine_party, mine):
				Game.say(["That's your last creature that can battle!"])
				return
			Game.pop(ps)
			Game.say(["Waiting for %s..." % their_name])
			# Ask the friend on their own screen.
			Game.in_view(them, func() -> void:
				Game.ask("%s wants to trade %s (Lv%d). Trade one of yours for it?" % [my_name, Creatures.display_name(mine), mine.level], ["YES", "NO"], func(k: int) -> void:
					if k != 0:
						Game.in_view(me, func() -> void: Game.say(["%s declined the trade." % their_name]))
						return
					var their_party: Array = their_gs.players[0].party
					var ps2 := PartyScreen.new({"player": 0, "party": their_party, "prompt": "Trade which creature?"})
					ps2.o.on_cancel = func() -> void:
						Game.pop(ps2)
						Game.in_view(me, func() -> void: Game.say(["%s declined the trade." % their_name]))
					ps2.o.on_select = func(j: int) -> void:
						var theirs: Dictionary = their_party[j]
						if _last_battler(their_party, theirs):
							Game.say(["That's your last creature that can battle!"])
							return
						Game.pop(ps2)
						_swap(me, mine, them, theirs)
					Game.push(ps2)))
		Game.push(ps))

static func _last_battler(party: Array, m: Dictionary) -> bool:
	for x in party:
		if not is_same(x, m) and Battle.can_battle(x):
			return false
	return true

static func _swap(va: int, a: Dictionary, vb: int, b: Dictionary) -> void:
	var gsa: Dictionary = Game.views[va].gs
	var gsb: Dictionary = Game.views[vb].gs
	var pa: Array = gsa.players[0].party
	var pb: Array = gsb.players[0].party
	pa[pa.find(a)] = b
	pb[pb.find(b)] = a
	a.owner = 0
	b.owner = 0
	gsa.trades = int(gsa.get("trades", 0)) + 1
	gsb.trades = int(gsb.get("trades", 0)) + 1
	for pair in [[gsa, b], [gsb, a]]:
		for list in [pair[0].seen, pair[0].caught]:
			if not list.has(pair[1].species):
				list.append(pair[1].species)
	for pair in [[va, b, a], [vb, a, b]]:
		Game.in_view(pair[0], func() -> void:
			Audio.sfx("item")
			Game.say(["You traded %s for %s!" % [Creatures.display_name(pair[2]), Creatures.display_name(pair[1])], "Take good care of it!"], func() -> void:
				GameState.save(Game.gs)
				_trade_evolve(pair[1], 0)))
