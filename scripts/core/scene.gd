class_name Scene
extends RefCounted
## A screen on Game's stack. Overlays draw on top of the scene below them.

var overlay := false

func update(_dt: float) -> void:
	pass

func draw() -> void:
	pass
