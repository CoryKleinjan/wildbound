extends SceneTree
## Headless audio test: synthesizes every SFX, checks length and peak level, exercises the music API
## (with missing files) and exports a few SFX as .wav for listening.
## Usage: godot --headless --path . -s res://tests/audio_test.gd [-- out_dir]

const OUT_DEFAULT := "/tmp/claude-0/sfx"
const EXPORT := ["confirm", "encounter", "hit_super", "catch", "level_up", "heal", "badge", "evolve_done", "spotted", "ledge"]

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var audio: Node = root.get_node("Audio")
	var fails := 0
	audio.generate_all()
	var t0 := Time.get_ticks_msec()
	# Fresh generation timing (the autoload already built everything in _ready).
	for n in audio.SFX_NAMES:
		audio.build(n)
	print("Generated %d SFX in %d ms" % [audio.SFX_NAMES.size(), Time.get_ticks_msec() - t0])
	var total := 0.0
	for n in audio.SFX_NAMES:
		var s: AudioStreamWAV = audio.streams.get(n)
		if s == null:
			print("FAIL %s: missing stream" % n)
			fails += 1
			continue
		var data := s.data
		var count := data.size() / 2
		var peak := 0
		var sumsq := 0.0
		for i in count:
			var v := absi(data.decode_s16(i * 2))
			peak = maxi(peak, v)
			sumsq += float(v) * v
		var len_s := float(count) / s.mix_rate
		var rms := sqrt(sumsq / maxi(1, count)) / 32767.0
		var pk := peak / 32767.0
		total += len_s
		var ok := s.format == AudioStreamWAV.FORMAT_16_BITS and s.mix_rate == 22050 and not s.stereo
		ok = ok and len_s > 0.02 and len_s < 3.0 and pk > 0.05 and pk <= 0.95
		# Last samples should be near-silent (no click at the end).
		var tail := absi(data.decode_s16((count - 1) * 2)) / 32767.0
		ok = ok and tail < 0.05
		print("%s %-13s %5.2fs  peak %.2f  rms %.3f" % ["ok  " if ok else "FAIL", n, len_s, pk, rms])
		if not ok:
			fails += 1
	print("Total SFX audio: %.1fs" % total)
	# Distinctness: no two SFX have identical data.
	var seen := {}
	for n in audio.SFX_NAMES:
		var h: int = hash(audio.streams[n].data)
		if seen.has(h):
			print("FAIL %s identical to %s" % [n, seen[h]])
			fails += 1
		seen[h] = n
	# Playback API must not crash with the dummy driver.
	for n in audio.SFX_NAMES:
		audio.sfx(n)
	audio.sfx("no_such_sound")
	audio.play_music("battle_wild")
	audio.play_music("battle_wild")
	if audio.current_track() != "battle_wild":
		print("FAIL current_track")
		fails += 1
	audio.stop_music()
	audio.play_music("route")
	audio.push_music("battle_trainer")
	audio.play_music("victory_trainer")
	if audio.previous_track() != "route":
		print("FAIL previous_track = %s" % audio.previous_track())
		fails += 1
	audio.pop_music()
	if audio.current_track() != "route" or audio.previous_track() != "":
		print("FAIL pop_music")
		fails += 1
	for i in 10:
		await process_frame
	audio.stop_sfx()
	# Export a few for listening.
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() else OUT_DEFAULT
	DirAccess.make_dir_recursive_absolute(out)
	for n in EXPORT:
		var err: int = audio.streams[n].save_to_wav(out.path_join(n + ".wav"))
		if err != OK:
			print("FAIL export %s: %d" % [n, err])
			fails += 1
	print("Exported %d wavs to %s" % [EXPORT.size(), out])
	print("AUDIO TEST %s (%d failures)" % ["PASSED" if fails == 0 else "FAILED", fails])
	quit(1 if fails else 0)
