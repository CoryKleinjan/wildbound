class_name TrainerCardScene
extends Scene
## The Trainer Card (from the START menu): name, ID No., money, Dex, play time and badges on the front; records on
## the back. A flips the card, B closes it. The card's color gets better with each star earned, as in Emerald.

const COLORS := ["#d8d8e0", "#78b0f0", "#70c070", "#f0a8c8", "#e8c040", "#b890f0"]

var _player: int
var _on_close: Callable
var _back := false

## The card's stars: Champion, completed Dex, Battle Frontier streak of 50+ (or Tower), every contest won at Master.
static func stars(gs: Dictionary) -> Array:
	var out: Array = []
	if gs.flags.get("champion", false):
		out.append("Became the Champion")
	if gs.caught.size() >= DB.SPECIES.size() - DB.ROAMERS.size() - 5:
		out.append("Completed the Dex")
	var best := int(gs.tower.best)
	for f in gs.frontier.values():
		best = maxi(best, int(f.get("best", 0)))
	if best >= 50:
		out.append("Won 50 battles in a row")
	var master := 0
	for c in gs.contest.values():
		if int(c) >= 4:
			master += 1
	if master >= 5:
		out.append("Won every Master contest")
	return out

static func id_no(gs: Dictionary, pl: int = 0) -> String:
	return "%05d" % (int(gs.players[pl].otId) % 65536)

static func play_time(gs: Dictionary) -> String:
	var s := int(gs.playTime)
	return "%d:%02d" % [s / 3600, (s / 60) % 60]

func _init(player: int, on_close: Callable) -> void:
	_player = player
	_on_close = on_close

func update(_dt: float) -> void:
	var inp := Game.input.p(_player)
	if inp.pressed("a"):
		_back = not _back
		Audio.sfx("cursor")
	elif inp.pressed("b"):
		Audio.sfx("cancel")
		_on_close.call()

func draw() -> void:
	var gs: Dictionary = Game.gs
	var st := stars(gs)
	var color: String = COLORS[mini(st.size(), COLORS.size() - 1)]
	Gfx.rect(0, 0, Gfx.W, Gfx.H, "#404858")
	Gfx.rect(10, 10, Gfx.W - 20, Gfx.H - 20, Gfx.shade(color, 0.7))
	Gfx.rect(12, 12, Gfx.W - 24, Gfx.H - 24, color)
	Gfx.rect(12, 12, Gfx.W - 24, 18, Gfx.shade(color, 0.8))
	Gfx.text("TRAINER CARD", 20, 18, {"color": "#ffffff", "size": 7})
	Gfx.text("IDNo. %s" % id_no(gs, _player), Gfx.W - 20, 18, {"color": "#ffffff", "size": 6, "align": "right"})
	var p: Dictionary = gs.players[_player]
	if not _back:
		Gfx.text("NAME: %s" % p.name, 20, 38, {"size": 7})
		var rows := [["MONEY", "$%d" % gs.money], ["DEX", "%d" % gs.caught.size()], ["TIME", play_time(gs)]]
		for i in rows.size():
			Gfx.text(rows[i][0], 20, 56 + i * 13, {"size": 6})
			Gfx.text(rows[i][1], 128, 56 + i * 13, {"size": 6, "align": "right"})
		# The player's portrait.
		Gfx.rect(160, 36, 56, 64, Gfx.shade(color, 1.15))
		var pal: Dictionary = DB.PALETTES.get("p1" if _player == 0 else "p2", DB.PALETTES.get("boy", {}))
		TrainerArt.draw_char(180, 56, "down", 0, pal, "p1" if _player == 0 else "p2")
		# Badges.
		Gfx.text("BADGES", 20, 106, {"size": 6})
		for i in 8:
			var bx := 22 + i * 26
			var gym: Dictionary = DB.GYMS[i] if i < DB.GYMS.size() else {}
			if gs.flags.get("badge%d" % (i + 1), false):
				var c: Color = Gfx.col(DB.TYPE_COLORS.get(gym.get("type", "Normal"), "#c0c0c0"))
				Gfx.ellipse(bx + 8, 124, 8, 8, Gfx.shade(c, 0.6))
				Gfx.ellipse(bx + 8, 124, 6, 6, c)
				Gfx.rect(bx + 5, 120, 3, 2, Color(1, 1, 1, 0.7))
			else:
				Gfx.ellipse(bx + 8, 124, 7, 7, Color(0, 0, 0, 0.15))
		for i in st.size():
			Gfx.text("★", Gfx.W - 22 - i * 10, 38, {"size": 7, "color": "#f8e060", "align": "right"})
		Gfx.text("A: flip   B: close", Gfx.W / 2.0, Gfx.H - 18, {"size": 5, "align": "center", "color": "#404040"})
		return
	var hof: Array = gs.hallOfFame
	var best_frontier := 0
	for f in gs.frontier.values():
		best_frontier = maxi(best_frontier, int(f.get("best", 0)))
	var contests := 0
	for c in gs.contest.values():
		contests += int(c)
	var rows := [
		["HALL OF FAME", hof[0].date if not hof.is_empty() else "--"],
		["BATTLE TOWER BEST", "%d" % int(gs.tower.best)],
		["FRONTIER BEST", "%d" % best_frontier],
		["BATTLE POINTS", "%d" % int(gs.bp)],
		["CONTEST RIBBONS", "%d" % contests],
		["TRADES", "%d" % int(gs.get("trades", 0))],
		["COINS", "%d" % int(gs.get("coins", 0))],
	]
	for i in rows.size():
		Gfx.text(rows[i][0], 20, 38 + i * 12, {"size": 6})
		Gfx.text(rows[i][1], Gfx.W - 20, 38 + i * 12, {"size": 6, "align": "right"})
	if not st.is_empty():
		Gfx.text("★ " + st[st.size() - 1], 20, 124, {"size": 5, "color": "#605020"})
	Gfx.text("A: flip   B: close", Gfx.W / 2.0, Gfx.H - 18, {"size": 5, "align": "center", "color": "#404040"})
