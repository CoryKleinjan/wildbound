class_name Eggs
## Eggs in the party count down one step at a time (twice as fast with Flame Body or Magma Armor in the party)
## and hatch where you stand.

## Called each step. True if an egg hatched (a dialog took over).
static func on_step(gs: Dictionary) -> bool:
	var party: Array = gs.players[0].party
	var speed := 1
	for m in party:
		if not m.get("egg", false) and (Creatures.ability_of(m) == "flameBody" or Creatures.ability_of(m) == "magmaArmor"):
			speed = 2
	for m in party:
		if not m.get("egg", false):
			continue
		m.eggSteps = int(m.get("eggSteps", 0)) - speed
		if m.eggSteps <= 0:
			hatch(gs, m)
			return true
	return false

static func hatch(gs: Dictionary, m: Dictionary) -> void:
	m.egg = false
	m.eggSteps = 0
	m.hp = Creatures.max_hp(m)
	m.metLevel = 5
	for list in [gs.seen, gs.caught]:
		if not list.has(m.species):
			list.append(m.species)
	Audio.sfx("evolve_start")
	var scene := HatchScene.new(m)
	Game.push(scene)
	Game.say(["Oh?", "... ... ...", "%s hatched from the Egg!" % Creatures.display_name(m)], func() -> void:
		Game.pop(scene)
		Audio.sfx("level_up"))

## How close an egg is to hatching, as the summary screen says it.
static func hatch_text(m: Dictionary) -> String:
	var steps: int = m.get("eggSteps", 0)
	if steps <= 256 * 2:
		return "Sounds can be heard coming from inside! It will hatch soon!"
	if steps <= 256 * 5:
		return "It moves around inside sometimes. It must be close to hatching."
	if steps <= 256 * 10:
		return "What will hatch from this? It doesn't seem close to hatching."
	return "It looks like this Egg will take a long time to hatch."
