class_name JointBattle
## Double battles fought together: when a friend has joined (see Net) and both players are on the
## same screen, a wild encounter or a trainer battle for either of them pulls the other in. Each
## player sends out their own creatures and picks their own moves.
##
## The battle runs in the host's view (view 0) with a combined co-op state (both players' trainers,
## the host's world), using the battle code's co-op mode: players[i] picks for side slot i, through
## that player's own input (GameInput.joint). The friend's view shows it through a LinkScene.

## How far apart (in tiles) the players can be and still count as on the same screen.
const SCREEN_TILES := Vector2i(7, 5)

## Live joint battle state, or null.
static var _live: Variant = null

## True if the player in the current view can pull the other player into a battle right now.
static func partner_ready(ow: OverworldScene) -> bool:
	if not Net.guest_in_world() or _live != null:
		return false
	var other := Game.other_overworld()
	var v := Game.views[1 - Game.cur]
	if other == null or other.map.id != ow.map.id or v.stack.back() != other or v.fade_target != 0:
		return false
	if other.is_busy():
		return false
	if absi(other.player.x - ow.player.x) > SCREEN_TILES.x or absi(other.player.y - ow.player.y) > SCREEN_TILES.y:
		return false
	for g in [Game.views[0].gs, Game.views[1].gs]:
		if not _has_usable(g.players[0].party):
			return false
	return true

static func _has_usable(party: Array) -> bool:
	for m in party:
		if m.hp > 0:
			return true
	return false

static func is_live() -> bool:
	return _live != null

## Starts a joint battle. setup is a BattleScene setup (kind, wild or trainer + trainerParty);
## it is made a double battle. Called from the view whose player started it.
static func start(setup: Dictionary, trainer: Variant) -> void:
	var host_gs: Dictionary = Game.views[0].gs
	var guest_gs: Dictionary = Game.views[1].gs
	var starter := Game.cur
	var cg := host_gs.duplicate()
	cg.mode = "coop"
	cg.players = [host_gs.players[0], guest_gs.players[0]]
	for m in guest_gs.players[0].party:
		m.owner = 1
	setup.double = true
	# Each player uses their own items in battle (see BattleScene._open_bag_for).
	setup.bags = [host_gs.bag, guest_gs.bag]
	_live = {"setup": setup, "trainer": trainer, "host_gs": host_gs, "guest_gs": guest_gs, "cg": cg,
		"money": [host_gs.money, guest_gs.money], "scene": null, "link": null}
	setup.onEnd = _on_end
	Game.input.joint = true
	Game.views[0].gs = cg
	Game.in_view(0, _push_battle)
	Game.in_view(1, _push_link)
	var name: String = (host_gs if starter == 0 else guest_gs).players[0].name
	Net.toast("You joined %s's battle!" % name, 1 - starter, 2.5)

static func _push_battle() -> void:
	# The host's own screen may still be mid-step or mid-fade from the overworld.
	Game.views[0].fade_target = 0
	var scene := BattleScene.new(_live.setup)
	_live.scene = scene
	Game.push(scene)

static func _push_link() -> void:
	Game.views[1].fade_target = 0
	var link := LinkScene.new()
	_live.link = link
	Game.push(link)

## Battle over (or the friend left mid-battle): give each player their results back in their own view.
static func _on_end(result: String, battle) -> void:
	var st: Dictionary = _live
	_live = null
	Game.input.joint = false
	var host_gs: Dictionary = st.host_gs
	var guest_gs: Dictionary = st.guest_gs
	var cg: Dictionary = st.cg
	Game.views[0].gs = host_gs
	for m in guest_gs.players[0].party:
		m.owner = 0
	# Both players get the prize, or both drop half their money.
	var delta: int = cg.money - st.money[0]
	host_gs.money = maxi(0, st.money[0] + delta) if result != "lose" else st.money[0] - st.money[0] / 2
	guest_gs.money = maxi(0, st.money[1] + delta) if result != "lose" else st.money[1] - st.money[1] / 2
	var guest_here: bool = Game.views[1].gs == guest_gs
	var per_view := [{"gs": host_gs, "msgs": [], "evolve": []}, {"gs": guest_gs, "msgs": [], "evolve": []}]
	for c in battle.caught:
		var v: Dictionary = per_view[c.player]
		c.mon.owner = 0
		if GameState.receive_creature(v.gs, c.mon, 0) == "box":
			v.msgs.append("%s was sent to storage (party full: %d max)." % [Creatures.display_name(c.mon), GameState.party_cap(v.gs)])
	if battle.kind == "wild":
		for m in st.setup.wild:
			if not guest_gs.seen.has(m.species):
				guest_gs.seen.append(m.species)
	var trainer: Variant = st.trainer
	if trainer != null and result == "win":
		# Flags are shared, so this marks the trainer beaten for both players.
		host_gs.flags[trainer.id] = true
		if trainer.get("badge"):
			host_gs.flags["badge%d" % trainer.badge] = true
			var gym: Dictionary = {}
			for gy in DB.GYMS:
				if gy.badge == trainer.badge:
					gym = gy
			for v in per_view:
				v.msgs.append("You received the %s! (%d/8 badges)" % [gym.badgeName, OverworldScene.badge_count(host_gs)])
	for i in 2:
		var v: Dictionary = per_view[i]
		for uid in st.scene.leveled:
			for m in v.gs.players[0].party:
				if m.uid == uid and Creatures.pending_evolution(m) != null:
					v.evolve.append(m)
	# Anything the battle left above itself (a dialog, when the friend left mid-battle) goes too.
	_cut(Game.views[0], st.scene)
	if guest_here:
		_cut(Game.views[1], st.link)
	for i in (2 if guest_here else 1):
		Game.in_view(i, _back_to_world.bind(result, trainer, per_view[i]))

static func _cut(v, scene: Scene) -> void:
	var i: int = v.stack.find(scene)
	if i >= 0:
		v.stack.resize(i)

## In one player's view: back on the map, with their messages and evolutions.
static func _back_to_world(result: String, trainer: Variant, v: Dictionary) -> void:
	var ow: OverworldScene = Game.stack[0]
	# The friend heard the battle through the host's view, so their own music starts over.
	if Game.cur == 1:
		Audio.reset_view(1)
	Audio.play_music(OverworldScene.map_track(ow.map))
	if result == "lose":
		for m in v.gs.players[0].party:
			Creatures.heal_fully(m)
		var r: Dictionary = v.gs.respawn
		ow.load_map(r.map, r.x, r.y, "down")
		v.gs.x = r.x
		v.gs.y = r.y
		Game.say(["You're both out of usable creatures!", "You hurried back to the Rest Lodge!"])
		return
	if trainer != null and result == "win" and trainer.get("leaveAfter", false):
		ow.remove_trainer(trainer.id)
	var queue: Array = v.evolve
	var next := func(self_ref: Callable) -> void:
		if queue.is_empty():
			return
		var m: Dictionary = queue.pop_front()
		EvolutionScene.new(m, Creatures.pending_evolution(m), 0, func() -> void: self_ref.call(self_ref))
	if v.msgs.size():
		Game.say(v.msgs, func() -> void: next.call(next))
	else:
		next.call(next)

## The friend left in the middle of a joint battle: end it for the host.
static func abort() -> void:
	if _live == null:
		return
	var st: Dictionary = _live
	st.scene.battle.caught = []
	_on_end("ran", st.scene.battle)

## On the friend's screen while the battle runs in the host's view: shows that battle.
class LinkScene extends Scene:
	func draw() -> void:
		Game.in_view(0, Game.draw)
