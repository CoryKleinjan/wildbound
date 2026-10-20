extends Node
## Game data loaded from data/*.json. Dictionaries keep the JSON's camelCase keys.

var SPECIES: Dictionary = {}
var MOVES: Dictionary = {}
var ITEMS: Dictionary = {}
var ABILITIES: Dictionary = {}
var MAPS: Dictionary = {}
var STARTERS: Array = []
var NATURE_NAMES: Array = []
## Gen 3 nature order: raised stat = floor(n / 5), lowered = n % 5, over these stats.
var NATURE_STATS: Array = []
var TYPE_COLORS: Dictionary = {}
var SPECIAL_TYPES: Array = []
var TYPE_CHART: Dictionary = {}
var GYMS: Array = []
var ROUTE_LEVELS: Array = []
var PALETTES: Dictionary = {}
const STAT_KEYS := ["hp", "atk", "def", "spa", "spd", "spe"]

func _init() -> void:
	SPECIES = _load("species")
	MOVES = _load("moves")
	ITEMS = _load("items")
	ABILITIES = _load("abilities")
	MAPS = _load("maps")
	var misc: Dictionary = _load("misc")
	STARTERS = misc.starters
	NATURE_NAMES = misc.natureNames
	NATURE_STATS = misc.natureStats
	TYPE_COLORS = misc.typeColors
	SPECIAL_TYPES = misc.specialTypes
	TYPE_CHART = misc.typeChart
	GYMS = misc.gyms
	ROUTE_LEVELS = misc.routeLevels
	PALETTES = misc.palettes
	_fix_ints(SPECIES)
	_fix_ints(MOVES)
	_fix_ints(ITEMS)
	_fix_ints(MAPS)
	_fix_ints(GYMS)
	_fix_ints(ROUTE_LEVELS)
	_fix_ints(TYPE_CHART)
	_apply_interiors(_fix_ints(_load("interiors")))
	_apply_story(_fix_ints(_load("story")))

## Merges data/interiors.json (the rooms behind town doors, built by tools/build_interiors.py) into MAPS
## and turns each door into a warp to its room.
func _apply_interiors(interiors: Dictionary) -> void:
	MAPS.merge(interiors.maps)
	for map_id in interiors.warps:
		var warps: Dictionary = MAPS[map_id].get("warps", {})
		warps.merge(interiors.warps[map_id])
		MAPS[map_id].warps = warps

## Merges data/story.json (story NPCs, Hollow Order trainers, rival lines) into MAPS.
func _apply_story(story: Dictionary) -> void:
	for map_id in story.npcs:
		MAPS[map_id].npcs = MAPS[map_id].get("npcs", []) + story.npcs[map_id]
	for map_id in story.trainers:
		MAPS[map_id].trainers = MAPS[map_id].get("trainers", []) + story.trainers[map_id]
	for m in MAPS.values():
		for t in m.get("trainers", []):
			if story.trainerPatches.has(t.id):
				t.merge(story.trainerPatches[t.id], true)

func _load(name: String) -> Variant:
	var f := FileAccess.open("res://data/%s.json" % name, FileAccess.READ)
	return JSON.parse_string(f.get_as_text())

## JSON numbers arrive as floats; whole numbers become ints so integer math matches Gen 3.
static func _fix_ints(v: Variant) -> Variant:
	if v is Dictionary:
		for k in v.keys():
			v[k] = _fix_ints(v[k])
	elif v is Array:
		for i in v.size():
			v[i] = _fix_ints(v[i])
	elif v is float and v == floorf(v):
		return int(v)
	return v

func species(id: String) -> Dictionary:
	assert(SPECIES.has(id), "Unknown species %s" % id)
	return SPECIES[id]

func move(id: String) -> Dictionary:
	assert(MOVES.has(id), "Unknown move %s" % id)
	return MOVES[id]

func item(id: String) -> Dictionary:
	assert(ITEMS.has(id), "Unknown item %s" % id)
	return ITEMS[id]

## Effectiveness of one attacking type against one defending type, x10.
func type_multiplier10(atk: String, def: String) -> int:
	if not TYPE_CHART.has(atk):
		return 10
	return TYPE_CHART[atk].get(def, 10)

## In Gen 3 a move's category (physical/special) is decided by its type.
func is_physical_type(t: String) -> bool:
	return t != "Mystery" and not SPECIAL_TYPES.has(t)

## Nature modifier for a stat as a percentage: 110, 90 or 100.
func nature_mod(nature: int, stat: String) -> int:
	var up: String = NATURE_STATS[nature / 5]
	var down: String = NATURE_STATS[nature % 5]
	if up == down:
		return 100
	if stat == up:
		return 110
	if stat == down:
		return 90
	return 100

func type_color(t: String) -> Color:
	return Color(TYPE_COLORS[t])
