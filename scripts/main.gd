extends Node2D
## Root node. Everything is drawn in immediate mode on this one canvas item,
## on a 240x160 logical screen (the GBA resolution) scaled up by the window.

func _ready() -> void:
	Gfx.ci = self
	Game.start()

func _process(dt: float) -> void:
	Game.update(minf(dt, 0.05))
	queue_redraw()

func _draw() -> void:
	Gfx.ci = Net.begin_frame(self)
	Game.draw()
	Net.draw_overlay()
	Net.end_frame()
	Gfx.ci = self
