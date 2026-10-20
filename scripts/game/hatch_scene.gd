class_name HatchScene
extends Scene
## Egg hatching: the Egg wobbles, cracks and bursts in a flash, then the creature appears. The hatch dialog plays on
## top; when it closes the scene pops itself.

var _mon: Dictionary
var _t := 0.0

func _init(mon: Dictionary) -> void:
	_mon = mon

func update(dt: float) -> void:
	_t += dt

func draw() -> void:
	var bg := ArtAssets.texture("screens/evolution")
	if bg != null:
		Gfx.image(bg, 0, 0)
	else:
		Gfx.rect(0, 0, Gfx.W, Gfx.H, "#202838")
	var cx := Gfx.W / 2.0
	var cy := 60.0
	if _t < 2.6:
		var name := "icons/egg" if _t < 1.2 else ("fx/egg_crack1" if _t < 1.9 else "fx/egg_crack2")
		var tex := ArtAssets.texture(name)
		var wob := sin(_t * (6.0 + _t * 6.0)) * minf(_t, 2.0) * 2.0
		if tex != null:
			Gfx.image(tex, cx - tex.get_width() + wob, cy - tex.get_height(), {"scale": 2.0})
		else:
			Gfx.ellipse(cx + wob, cy - 4, 14, 18, "#f0e8c8")
		return
	var spr: Texture2D = CreatureArt.creature_sprite(_mon.species, Creatures.is_shiny(_mon))
	Gfx.image(spr, cx - spr.get_width() / 2.0, cy - spr.get_height() / 2.0 - 4)
	var k := (_t - 2.6) / 0.5
	if k < 1.0:
		var burst := ArtAssets.texture("fx/egg_burst")
		if burst != null:
			var s := 2.0 + k * 2.0
			Gfx.image(burst, cx - burst.get_width() * s / 2, cy - burst.get_height() * s / 2, {"scale": s, "modulate": Color(1, 1, 1, 1 - k)})
		Gfx.rect(0, 0, Gfx.W, Gfx.H, Color(1, 1, 1, 1 - k))
