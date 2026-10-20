class_name Tv
## The TV in every house (tile N). Each time you watch, the next show comes on: the news (today's mass outbreak),
## the trendy phrase, your friends' records (from Record Mixing), Mirage Island sightings and your own exploits.

static func watch() -> void:
	var gs: Dictionary = Game.gs
	var shows: Array = []
	var ob := TownLife.outbreak(gs)
	if not ob.is_empty():
		shows.append(["BREAKING NEWS!", "A swarm of %s has been spotted on %s!" % [DB.species(ob.species).name, DB.MAPS[ob.map].name],
			"This is a rare chance to catch one. Trainers, head out today!"])
	shows.append(["TRENDY TALK: Everyone in Wildbound is saying \"%s\"!" % gs.trendy,
		"They say the rare creature on Route 11 bites at new spots whenever a new phrase catches on..."])
	for r in gs.get("mixed", []):
		var lines: Array = ["FRIEND REPORT: Trainer %s is making a name for themselves!" % r.get("name", "?")]
		if int(r.get("tower", 0)) > 0:
			lines.append("Their best Battle Tower streak is %d wins in a row!" % int(r.tower))
		if r.get("lead", "") != "" and DB.SPECIES.has(r.lead):
			lines.append("Their partner %s never leaves their side." % DB.species(r.lead).name)
		shows.append(lines)
	if Field.mirage_visible(gs):
		shows.append(["SEA REPORT: Sailors near Saltmarsh report an island where there's usually only water...",
			"Could it be the legendary Mirage Island?"])
	var mine: Array = ["TRAINER WATCH: Tonight we follow %s!" % gs.players[0].name]
	var badges := 0
	for i in 8:
		if gs.flags.get("badge%d" % (i + 1), false):
			badges += 1
	mine.append("%d badge%s, %d creatures caught, and still going strong!" % [badges, "" if badges == 1 else "s", gs.caught.size()])
	if gs.flags.get("champion", false):
		mine.append("The Champion of Wildbound, everyone!")
	shows.append(mine)
	var show: Array = shows[int(gs.tvSeen) % shows.size()]
	gs.tvSeen = int(gs.tvSeen) + 1
	Audio.sfx("confirm")
	Game.say(["%s turned on the TV." % gs.players[0].name] + show)
