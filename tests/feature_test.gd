extends SceneTree
## Checks the Emerald features outside battle: evolution methods, save migration, field moves, items on the
## ground, berries, Secret Bases, Surf, the Day Care and eggs, the Battle Tower copies, Treat Blocks, items from
## the bag, Repel, rematches and the Safari Zone engine. Dialogs are answered directly (no input).
## The checks live in feature_checks.gd, loaded once the autoloads exist.
## Run: timeout 600 godot --headless --path . -s res://tests/feature_test.gd

func _initialize() -> void:
	await process_frame
	var t = load("res://tests/feature_checks.gd").new()
	t.run()
	if t.failures:
		print("%d failure(s)" % t.failures)
		quit(1)
		return
	print("all feature tests passed")
	quit(0)
