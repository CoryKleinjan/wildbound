extends SceneTree
## Debug: dumps the pre-pixelize alpha/color buffers of one species (for comparing coverage with Canvas2D).
func _initialize() -> void:
	await process_frame
	var id: String = OS.get_cmdline_user_args()[0]
	var spec: Dictionary = root.get_node("DB").species(id).sprite
	var r = CreatureArt._Raster.new(32, 61, 0.55 + float(spec.size) * 0.45)
	CreatureArt._draw_body(r, spec, false)
	var a: Array = []
	for i in 64 * 64:
		a.append(roundi(r.pa[i] * 255))
	FileAccess.open("/tmp/claude-0/shots/raw_gd.json", FileAccess.WRITE).store_string(JSON.stringify(a))
	quit()
