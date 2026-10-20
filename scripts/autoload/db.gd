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
## From data/features.json (tools/build_features.py): TMs, HMs, tutors, shops and the postgame/contest tables.
var TMS: Array = []
var HMS: Array = []
var HM_BADGES: Dictionary = {}
var TUTORS: Array = []
var FLY_POINTS: Dictionary = {}
var DECORATIONS: Dictionary = {}
var SHOPS: Dictionary = {}
var CONTEST: Dictionary = {}
var TOWER: Dictionary = {}
var ROAMERS: Array = []
var GYM_TMS: Dictionary = {}
## Game Corner prizes {items: [[id, coins]], creatures: [[species, level, coins]]}, Trick House {badges, prizes},
## Battle Frontier data, the region map {map id: {x, y, w, h, town, name}} and indoor map -> outdoor map.
var PRIZES: Dictionary = {}
var TRICK: Dictionary = {}
var FRONTIER: Dictionary = {}
var REGION_MAP: Dictionary = {}
var MAP_PARENT: Dictionary = {}
## The last of the Emerald extras: glass flutes, rare fishing, outbreaks, quiz and fan prizes, Battle Tents.
var EMERALD: Dictionary = {}
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
	_apply_styles(_load("town_styles"))
	_apply_features(_fix_ints(_load("features")))
	if FileAccess.file_exists("res://data/map_fit.json") and OS.get_environment("MAP_FIT") != "off":
		_apply_map_fit(_load("map_fit"))

## Applies data/map_fit.json ({map_id: {"x,y": tile}}, from tools/artgen/mapfit.py): the walkable grid fitted to
## each map's painting, so it only applies while that painting (assets/maps/<id>.png) is there.
func _apply_map_fit(fit: Dictionary) -> void:
	for map_id in fit:
		if not MAPS.has(map_id) or not ResourceLoader.exists("res://assets/maps/%s.png" % map_id):
			continue
		var rows: Array = MAPS[map_id].tiles.duplicate()
		for k in fit[map_id]:
			var xy: PackedStringArray = k.split(",")
			var x := int(xy[0])
			var y := int(xy[1])
			if y < rows.size() and x < rows[y].length():
				rows[y] = rows[y].substr(0, x) + fit[map_id][k] + rows[y].substr(x + 1)
		MAPS[map_id].tiles = rows

## Attaches each town's look (data/town_styles.json, see TownStyle) to the town and the rooms inside it.
func _apply_styles(styles: Dictionary) -> void:
	for m in MAPS.values():
		var sid: String = m.get("townId", m.id)
		if not styles.has(sid):
			continue
		var style: Dictionary = styles[sid].duplicate()
		style.id = sid
		m.style = style
		if m.get("interior", false) and style.has("floor"):
			m.theme = style.floor

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

const _APPEND_KEYS := ["npcs", "trainers", "items", "statics", "secretSpots", "soil"]

## Merges data/features.json: new moves, abilities, items and maps, plus patches to species and existing maps.
func _apply_features(f: Dictionary) -> void:
	for id in f.moves:
		MOVES[id] = f.moves[id]
	for id in f.movePatches:
		MOVES[id].merge(f.movePatches[id], true)
	for id in f.abilities:
		ABILITIES[id] = f.abilities[id]
	for id in f.items:
		if ITEMS.has(id):
			ITEMS[id].merge(f.items[id], true)
		else:
			ITEMS[id] = f.items[id]
	for id in f.species:
		if SPECIES.has(id):
			SPECIES[id].merge(f.species[id], true)
		else:
			SPECIES[id] = f.species[id]
	for id in f.maps:
		MAPS[id] = f.maps[id]
	for id in f.mapPatches:
		var m: Dictionary = MAPS[id]
		var patch: Dictionary = f.mapPatches[id]
		for k in patch:
			if _APPEND_KEYS.has(k):
				m[k] = m.get(k, []) + patch[k]
			elif patch[k] is Dictionary and m.get(k, null) is Dictionary:
				m[k].merge(patch[k], true)
			else:
				m[k] = patch[k]
	TMS = f.tms
	HMS = f.hms
	HM_BADGES = f.hmBadges
	TUTORS = f.tutors
	FLY_POINTS = f.flyPoints
	DECORATIONS = f.decorations
	SHOPS = f.shops
	CONTEST = f.contest
	TOWER = f.tower
	ROAMERS = f.roamers
	GYM_TMS = f.gymTms
	PRIZES = f.get("prizes", {})
	TRICK = f.get("trick", {})
	FRONTIER = f.get("frontier", {})
	REGION_MAP = f.get("regionMap", {})
	MAP_PARENT = f.get("mapParent", {})
	EMERALD = f.get("emerald", {})

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
