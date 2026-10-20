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
	Gfx.ci = self
	Game.draw()
	Net.draw_overlay()
	# A friend who joined over the network: draw their view for their computer, not this screen.
	if Net.guest_in_world():
		Game.in_view(1, func() -> void:
			Gfx.ci = Net.begin_frame()
			Game.draw()
			Net.draw_overlay()
			Net.end_frame())
		Gfx.ci = self
