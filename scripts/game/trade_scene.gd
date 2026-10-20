class_name TradeScene
extends Scene
## Trade animation: the outgoing creature goes into its orb, which flies off the top of the screen; the incoming orb
## drops in and opens on the new creature. The trade dialog plays on top; when it closes the scene pops itself.

var _from: String
var _to: String
var _t := 0.0

func _init(from_species: String, to_species: String) -> void:
	_from = from_species
	_to = to_species

func update(dt: float) -> void:
	_t += dt

func draw() -> void:
	var bg := ArtAssets.texture("screens/evolution")
	if bg != null:
		Gfx.image(bg, 0, 0)
	else:
		Gfx.rect(0, 0, Gfx.W, Gfx.H, "#182838")
	var cx := Gfx.W / 2.0
	var cy := 60.0
	var orb := ArtAssets.texture("fx/trade_orb")
	var sp := _from if _t < 1.6 else _to
	var spr: Texture2D = CreatureArt.creature_sprite(sp)
	# 0-0.8 outgoing creature shown, 0.8-1.6 its orb rises; 1.6-2.4 the new orb falls, then the creature appears.
	if _t < 0.8 or _t > 2.4:
		var k := clampf((_t - 2.4) / 0.3, 0, 1) if _t > 2.4 else 1.0 - clampf((_t - 0.5) / 0.3, 0, 1)
		Gfx.image(spr, cx - spr.get_width() * k / 2, cy - spr.get_height() * k / 2, {"scale": maxf(k, 0.01)})
	if _t >= 0.6 and _t < 2.7:
		var y := cy
		if _t < 1.6:
			y = cy - maxf(0, _t - 0.8) / 0.8 * 120
		elif _t < 2.4:
			y = cy - 120 + (_t - 1.6) / 0.8 * 120
		if orb != null:
			Gfx.image(orb, cx - orb.get_width(), y - orb.get_height(), {"scale": 2.0})
		else:
			Gfx.ellipse(cx, y, 8, 8, "#60e0f0")
	var sparkle := ArtAssets.texture("fx/sparkle")
	if sparkle != null:
		for i in 6:
			var a := Game.time * 2 + i * TAU / 6
			Gfx.image(sparkle, cx + cos(a) * 60 - 8, cy + sin(a) * 34 - 9, {"modulate": Color(1, 1, 1, 0.5 + 0.5 * sin(Game.time * 5 + i))})
