class_name Contest
## Showcase contests (Lumenvale) in the style of Emerald's: five categories (Cool, Beauty, Cute, Smart, Tough)
## and four ranks. Round one judges the creature's condition (raised with Treat Blocks from the Berry Blender);
## round two is five appeals, one move per turn: moves of the contest's category score more, repeating a move
## bores the judge. Winning gives a ribbon and opens the next rank.

const CATS := ["cool", "beauty", "cute", "smart", "tough"]
const CAT_NAMES := {"cool": "COOL", "beauty": "BEAUTY", "cute": "CUTE", "smart": "SMART", "tough": "TOUGH"}
const RANKS := ["Normal", "Super", "Hyper", "Master"]
## Treat Block flavors, in berry flavor order, and the condition each raises.
const FLAVORS := ["Spicy", "Dry", "Sweet", "Bitter", "Sour"]
const FLAVOR_CAT := ["cool", "beauty", "cute", "smart", "tough"]
const FLAVOR_COLORS := ["#e04848", "#4878e0", "#f070b0", "#48a848", "#e8c830"]
## Gen 3 natures like the flavor of the stat they raise and dislike the one they lower (atk, def, spe, spa, spd).
const STAT_FLAVOR := [0, 4, 2, 1, 3]

static func start(player: int) -> void:
	var gs: Dictionary = Game.gs
	if gs.bag.get("contestPass", 0) <= 0:
		Game.say(["You'll need a Contest Pass to enter. Someone in town hands them out."])
		return
	var labels: Array = []
	for c in CATS:
		var rank: int = mini(3, int(gs.contest.get(c, 0)))
		labels.append("%s %s" % [CAT_NAMES[c], RANKS[rank].to_upper()])
	labels.append("CANCEL")
	var ref := {}
	var menu := ListMenu.new({
		"x": 110, "y": 8, "w": 126, "player": player, "title": "Which contest?", "items": labels,
		"on_cancel": func() -> void: Game.pop(ref.menu),
		"on_select": func(i: int) -> void:
			Game.pop(ref.menu)
			if i >= CATS.size():
				return
			Services.pick_creature("Which creature will enter?", func(_m: Dictionary) -> String: return "",
				func(m: Dictionary) -> void: Game.push(ContestScene.new(m, CATS[i], mini(3, int(gs.contest.get(CATS[i], 0)))))),
	})
	ref.menu = menu
	Game.push(menu)

# ---------- Berry Blender and Treat Blocks ----------
static func blender(player: int) -> void:
	var gs: Dictionary = Game.gs
	if gs.bag.get("blockCase", 0) <= 0:
		Game.say(["You'll need a Block Case to carry Treat Blocks."])
		return
	Menus.open_bag({"player": player, "in_battle": false, "can_throw": false, "pocket": 2, "on_close": func() -> void: pass,
		"usable": func(id: String) -> bool: return DB.item(id).effect.kind == "berry",
		"on_pick": func(id: String, done: Callable) -> void:
			done.call()
			gs.bag[id] -= 1
			var fl: Array = DB.item(id).get("flavor", [10, 10, 10, 10, 10])
			var block := {"flavor": fl.map(func(v: int) -> int: return v * 2 + Rng.global_rng.int_below(6)), "sheen": 10 + Rng.global_rng.int_below(15)}
			if not gs.has("blocks"):
				gs.blocks = []
			gs.blocks.append(block)
			Audio.sfx("confirm")
			Game.say(["Whirr... The berry was blended!", "You made a %s!" % block_name(block)])})

static func block_name(b: Dictionary) -> String:
	var best := 0
	for i in 5:
		if int(b.flavor[i]) > int(b.flavor[best]):
			best = i
	return "%s Treat Block" % FLAVORS[best]

static func open_block_case(player: int) -> void:
	var gs: Dictionary = Game.gs
	var blocks: Array = gs.get("blocks", [])
	if blocks.is_empty():
		Game.say(["The Block Case is empty. Blend berries at the Showcase Hall."], Callable(), player)
		return
	var items: Array = []
	for b in blocks:
		items.append({"label": block_name(b), "right": "Feel %d" % b.sheen})
	items.append({"label": "CLOSE"})
	var ref := {}
	var menu := ListMenu.new({
		"x": 70, "y": 8, "w": 166, "player": player, "title": "Feed which block?", "items": items, "max_visible": 7,
		"on_cancel": func() -> void: Game.pop(ref.menu),
		"on_select": func(i: int) -> void:
			Game.pop(ref.menu)
			if i >= blocks.size():
				return
			Services.pick_creature("Feed it to which creature?", func(m: Dictionary) -> String:
				return "" if int(m.condition.sheen) < 255 else "%s won't eat any more..." % Creatures.display_name(m),
			func(m: Dictionary) -> void:
				var msg := feed(m, blocks[i])
				blocks.remove_at(i)
				Game.say([msg])),
	})
	ref.menu = menu
	Game.push(menu)

static func feed(m: Dictionary, b: Dictionary) -> String:
	var nat := Creatures.nature_of(m)
	var liked: int = STAT_FLAVOR[nat / 5]
	var disliked: int = STAT_FLAVOR[nat % 5]
	var cond: Dictionary = m.condition
	for i in 5:
		var v: int = b.flavor[i]
		if nat / 5 != nat % 5:
			if i == liked:
				v = v * 11 / 10
			elif i == disliked:
				v = v * 9 / 10
		var k: String = FLAVOR_CAT[i]
		cond[k] = mini(255, int(cond.get(k, 0)) + v)
	cond.sheen = mini(255, int(cond.get("sheen", 0)) + int(b.sheen))
	var flavor_best := 0
	for i in 5:
		if int(b.flavor[i]) > int(b.flavor[flavor_best]):
			flavor_best = i
	var mood := "happily ate the block!" if flavor_best == liked and nat / 5 != nat % 5 else ("ate it, but didn't seem to like it much." if flavor_best == disliked and nat / 5 != nat % 5 else "ate the block.")
	return "%s %s" % [Creatures.display_name(m), mood]

## A contest in progress: intro, condition round, five appeal turns, results.
class ContestScene extends Scene:
	var _m: Dictionary
	var _cat: String
	var _rank: int
	## [{name, palette, species, primary, appeal, last, is_player}]
	var _rows: Array = []
	var _turn := 0
	var _stage := "intro"
	var _sel := 0
	var _msg := ""
	var _t := 0.0

	func _init(m: Dictionary, cat: String, rank: int) -> void:
		_m = m
		_cat = cat
		_rank = rank
		var gs: Dictionary = Game.gs
		_rows.append({"name": Creatures.display_name(m), "trainer": gs.players[0].name, "species": m.species,
			"primary": int(m.condition.get(cat, 0)) + int(m.condition.get("sheen", 0)) / 4, "appeal": 0, "last": "", "is_player": true})
		var rivals: Array = DB.CONTEST.rivals.duplicate()
		var pool: Array = DB.SPECIES.keys()
		for i in 3:
			var r: Array = rivals.pop_at(Rng.global_rng.int_below(rivals.size()))
			var sp: String = pool[Rng.global_rng.int_below(pool.size())]
			_rows.append({"name": DB.species(sp).name, "trainer": r[0], "species": sp,
				"primary": 20 + rank * 45 + Rng.global_rng.int_below(50), "appeal": 0, "last": "", "is_player": false})
		_msg = "%s Contest, %s Rank! Round 1: the judge looks over each creature's condition." % [CAT_NAMES[cat], RANKS[rank]]
		Audio.push_music("town")

	func _hearts(primary: int) -> int:
		return clampi(primary / 25, 0, 10)

	func update(dt: float) -> void:
		_t += dt
		var inp := Game.input.p(0)
		match _stage:
			"intro", "between", "results":
				if inp.pressed("a") or inp.pressed("b"):
					Audio.sfx("confirm")
					_advance()
			"choose":
				var n: int = _m.moves.size()
				if inp.pressed("up"):
					_sel = (_sel + n - 1) % n
					Audio.sfx("cursor")
				if inp.pressed("down"):
					_sel = (_sel + 1) % n
					Audio.sfx("cursor")
				if inp.pressed("a"):
					Audio.sfx("confirm")
					_appeal_turn(_m.moves[_sel].id)

	func _advance() -> void:
		if _stage == "intro":
			_stage = "between"
			_msg = "Round 2: five appeals! Pick a move each turn."
			return
		if _stage == "between":
			if _turn >= 5:
				_finish()
			else:
				_stage = "choose"
			return
		if _stage == "results":
			Audio.pop_music()
			Game.pop(self)

	func _score(id: String, row: Dictionary) -> int:
		var base: int = int(DB.CONTEST.moveAppeal.get(id, 2))
		var cat: String = DB.CONTEST.moveCategory.get(id, "cool")
		var s := base + (2 if cat == _cat else 0)
		if row.last == id:
			s -= 3
		return maxi(0, s)

	func _appeal_turn(id: String) -> void:
		var lines: Array = []
		for row in _rows:
			var mv: String = id
			if not row.is_player:
				var learn: Array = DB.species(row.species).learnset
				mv = learn[Rng.global_rng.int_below(learn.size())][1]
			var s := _score(mv, row)
			if not row.is_player:
				s = maxi(0, s + Rng.global_rng.int_below(3) - 1 + (_rank / 2))
			row.appeal += s
			if row.is_player:
				var note := ""
				if row.last == mv:
					note = " The judge looks bored..."
				elif DB.CONTEST.moveCategory.get(mv, "") == _cat:
					note = " It's a perfect fit for this contest!"
				lines.append("%s used %s! +%d%s" % [row.name, DB.move(mv).name, s, note])
			row.last = mv
		_turn += 1
		_msg = " ".join(lines)
		_stage = "between"

	func _total(row: Dictionary) -> int:
		return _hearts(row.primary) * 2 + int(row.appeal)

	func _finish() -> void:
		var gs: Dictionary = Game.gs
		var order: Array = _rows.duplicate()
		order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _total(a) > _total(b))
		var place: int = order.find(_rows[0]) + 1
		_stage = "results"
		if place == 1:
			var ribbon := "%s %s" % [CAT_NAMES[_cat], RANKS[_rank]]
			if not (_m.ribbons as Array).has(ribbon):
				_m.ribbons.append(ribbon)
			gs.contest[_cat] = maxi(int(gs.contest.get(_cat, 0)), _rank + 1)
			if _rank == RANKS.size() - 1:
				Museum.paint(gs, _cat, _m)
			Audio.sfx("badge")
			_msg = "%s won the contest! It received the %s Ribbon!" % [_rows[0].name, ribbon]
			if _rank == RANKS.size() - 1:
				_msg += " Its portrait will hang in the Lumenvale Art Museum!"
		else:
			_msg = "%s placed %s. Keep raising its condition with Treat Blocks!" % [_rows[0].name, ["", "1st", "2nd", "3rd", "4th"][place]]

	func draw() -> void:
		Gfx.screen("contest", "#f8e8d0", "#c05878")
		Gfx.text("%s CONTEST  %s RANK   Appeal %d/5" % [CAT_NAMES[_cat], RANKS[_rank].to_upper(), _turn], 6, 5, {"color": "#ffffff", "size": 5})
		for i in _rows.size():
			var row: Dictionary = _rows[i]
			var y := 20 + i * 26
			Gfx.panel(4, y, 232, 24)
			var spr: Texture2D = CreatureArt.creature_sprite(row.species)
			Gfx.image(spr, 8, y + 1, {"scale": 22.0 / spr.get_width()})
			Gfx.text(row.name, 34, y + 4, {"size": 6, "color": "#c03050" if row.is_player else "#303030"})
			Gfx.text(row.trainer, 34, y + 14, {"size": 5, "color": "#606870"})
			for h in _hearts(row.primary):
				Gfx.rect(110 + h * 6, y + 5, 4, 4, "#e05080")
			var ap: int = mini(int(row.appeal), 30)
			for h in ap:
				Gfx.rect(110 + (h % 15) * 6, y + 13 + (h / 15) * 5, 4, 3, "#f0a020")
		Gfx.panel(0, 126, Gfx.W, 34)
		var lines := Gfx.wrap(_msg, 220, 5)
		for i in mini(3, lines.size()):
			Gfx.text(lines[i], 8, 132 + i * 8, {"size": 5})
		if _stage == "choose":
			var n: int = _m.moves.size()
			Gfx.panel(130, 126 - n * 12 - 8, 106, n * 12 + 8)
			for i in n:
				var id: String = _m.moves[i].id
				var fit: bool = DB.CONTEST.moveCategory.get(id, "") == _cat
				Gfx.text(DB.move(id).name, 144, 126 - n * 12 - 3 + i * 12, {"size": 5, "color": "#c03050" if fit else "#303030"})
				if i == _sel:
					Gfx.cursor(134, 126 - n * 12 - 3 + i * 12)
