extends Node
## Audio autoload: procedurally synthesized chiptune sound effects plus streamed background music.
##
##   Audio.sfx("confirm")              play a sound effect (names in SFX_NAMES; unknown names are ignored)
##   Audio.play_music("route")         loop res://assets/music/route.ogg (.mp3/.wav), crossfading; no-op if the
##                                     file is missing (the current track then fades out). Same track = no restart.
##   Audio.stop_music()                fade the music out.
##   Audio.push_music("battle_wild")   remember the current (field) track, then play another (battles use this).
##   Audio.pop_music()                 resume the remembered track (overworld calls this after a battle ends).
##   Audio.previous_track()            the remembered track ("" if none).
##   Audio.current_track()             the track name last asked for ("" if none).
##   Audio.music_volume / sfx_volume   linear 0..1.
##
## All SFX are built once at startup as 16-bit mono 22050 Hz AudioStreamWAVs (GBA-ish square/pulse,
## triangle and LFSR noise channels with ADSR envelopes, pitch sweeps and arpeggios). Works with the
## dummy audio driver (headless): players simply produce no sound.

const RATE := 22050
const MUSIC_DIR := "res://assets/music/"
const MUSIC_EXTS := ["ogg", "mp3", "wav"]
const POOL_SIZE := 6
const CROSSFADE := 0.6

const SFX_NAMES := [
	"cursor", "confirm", "cancel", "error", "bump", "door", "encounter", "hit", "hit_super", "hit_weak",
	"faint", "stat_up", "stat_down", "status", "recover", "send_out", "orb_throw", "orb_shake", "catch",
	"breakout", "level_up", "exp", "heal", "evolve_start", "evolve_done", "run", "low_hp", "save",
	"badge", "buy", "spotted", "ledge", "text",
]
## Jingles pause (duck) the music while they play, like the GBA did.
const JINGLES := ["catch", "level_up", "heal", "evolve_done", "badge", "save"]

var music_volume := 0.7:
	set(v):
		music_volume = clampf(v, 0, 1)
var sfx_volume := 0.8:
	set(v):
		sfx_volume = clampf(v, 0, 1)

var streams := {} # name -> AudioStreamWAV
var _pool: Array[AudioStreamPlayer] = []
var _pool_name: Array[String] = []
var _pool_started: Array[float] = []
var _last_play := {} # name -> clock
var _clock := 0.0
## The last 64 SFX/music requests ("sfx:hit", "music:battle_wild"), for tests and debugging.
var history: Array[String] = []
var _duck_until := 0.0
var _duck := 1.0

# Music: two players for crossfades. _mvol[i] is each player's fade level (0..1), _mtarget its goal.
var _music: Array[AudioStreamPlayer] = []
var _mvol := [0.0, 0.0]
var _mtarget := [0.0, 0.0]
var _active := 0
## Music state per view (Game.cur). View 1's sound plays on the friend's computer (see Net).
var _tracks := ["", ""]
var _saved_tracks := ["", ""]
var _current: String:
	get:
		return _tracks[Game.cur]
	set(v):
		_tracks[Game.cur] = v
var _saved: String:
	get:
		return _saved_tracks[Game.cur]
	set(v):
		_saved_tracks[Game.cur] = v
var _music_cache := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
		_pool_name.append("")
		_pool_started.append(-1.0)
	for i in 2:
		var m := AudioStreamPlayer.new()
		m.volume_db = -80
		add_child(m)
		_music.append(m)
	# Synthesis takes a few hundred ms in GDScript, so it runs on a worker thread; a sound requested
	# before the worker finishes is built on the spot.
	_task = WorkerThreadPool.add_task(_generate_async)

var _task := -1

func _generate_async() -> void:
	var out := {}
	for n in SFX_NAMES:
		out[n] = make_stream(build(n))
	_receive.call_deferred(out)

func _receive(out: Dictionary) -> void:
	for n in out:
		if not streams.has(n):
			streams[n] = out[n]
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1

## Builds every SFX now (synchronously). Tests call this; the game doesn't need to.
func generate_all() -> void:
	for n in SFX_NAMES:
		if not streams.has(n):
			streams[n] = make_stream(build(n))

func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1

# ---------------------------------------------------------------- playback
func sfx(sfx_name: String) -> void:
	if Game.cur == 1:
		Net.relay_sfx(sfx_name)
		return
	if _pool.is_empty() or not sfx_name in SFX_NAMES:
		return
	var s: AudioStreamWAV = streams.get(sfx_name)
	if s == null:
		s = make_stream(build(sfx_name))
		streams[sfx_name] = s
	# Don't stack the same sound within a couple of frames (menu spam, double events).
	if _clock - float(_last_play.get(sfx_name, -1.0)) < 0.035:
		return
	_last_play[sfx_name] = _clock
	_log("sfx:" + sfx_name)
	var idx := -1
	# Short UI blips reuse their own player so they cut themselves off instead of piling up.
	if sfx_name in ["cursor", "text", "exp"]:
		idx = _pool_name.find(sfx_name)
	if idx < 0:
		for i in _pool.size():
			if not _pool[i].playing:
				idx = i
				break
	if idx < 0:
		var oldest := INF
		for i in _pool.size():
			if _pool_started[i] < oldest:
				oldest = _pool_started[i]
				idx = i
	var p := _pool[idx]
	p.stream = s
	p.volume_db = linear_to_db(maxf(sfx_volume, 0.0001))
	p.play()
	_pool_name[idx] = sfx_name
	_pool_started[idx] = _clock
	if sfx_name in JINGLES:
		_duck_until = maxf(_duck_until, _clock + s.get_length() + 0.1)

func _log(entry: String) -> void:
	history.append(entry)
	if history.size() > 64:
		history.remove_at(0)

func stop_sfx() -> void:
	for p in _pool:
		p.stop()

func sfx_length(sfx_name: String) -> float:
	var s: AudioStreamWAV = streams.get(sfx_name)
	return s.get_length() if s else 0.0

func current_track() -> String:
	return _current

func previous_track() -> String:
	return _saved

## Remembers the current (field) track and plays another. Battle/victory/evolution tracks are never
## remembered, so a push while one of those plays keeps the earlier field track.
func push_music(track: String) -> void:
	if not _is_event_track(_current):
		_saved = _current
	play_music(track)

static func _is_event_track(t: String) -> bool:
	return t.begins_with("battle_") or t.begins_with("victory_") or t == "evolution"

## Plays the track remembered by push_music (if any) and forgets it.
func pop_music() -> void:
	var t := _saved
	_saved = ""
	if t != "":
		play_music(t)
	else:
		stop_music()

func play_music(track: String) -> void:
	if track == _current:
		return
	_current = track
	if Game.cur == 1:
		Net.relay_music(track)
		return
	_log("music:" + track)
	var stream := _load_music(track)
	# Fade whatever is playing out.
	_mtarget[_active] = 0.0
	if stream == null:
		return
	_active = 1 - _active
	var m := _music[_active]
	m.stream = stream
	_mvol[_active] = 0.0
	_mtarget[_active] = 1.0
	m.volume_db = -80
	m.play()

func stop_music() -> void:
	if Game.cur == 1:
		if _current != "":
			Net.relay_music("")
		_current = ""
		return
	_current = ""
	_mtarget[0] = 0.0
	_mtarget[1] = 0.0

## Forgets view v's music (a friend joined or left).
func reset_view(v: int) -> void:
	_tracks[v] = ""
	_saved_tracks[v] = ""

func has_music(track: String) -> bool:
	return _music_path(track) != ""

func _music_path(track: String) -> String:
	if track == "":
		return ""
	for ext in MUSIC_EXTS:
		var p: String = MUSIC_DIR + track + "." + ext
		if ResourceLoader.exists(p) or FileAccess.file_exists(p):
			return p
	return ""

func _load_music(track: String) -> AudioStream:
	if _music_cache.has(track):
		return _music_cache[track]
	var path := _music_path(track)
	var s: AudioStream = null
	if path != "":
		if ResourceLoader.exists(path):
			s = load(path) as AudioStream
		if s == null:
			# Not imported (e.g. dropped in while running from source): read the raw file.
			if path.ends_with(".ogg"):
				s = AudioStreamOggVorbis.load_from_file(path)
			elif path.ends_with(".mp3"):
				var mp3 := AudioStreamMP3.new()
				mp3.data = FileAccess.get_file_as_bytes(path)
				s = mp3
			elif path.ends_with(".wav"):
				s = AudioStreamWAV.load_from_file(path)
		if s is AudioStreamOggVorbis:
			(s as AudioStreamOggVorbis).loop = true
		elif s is AudioStreamMP3:
			(s as AudioStreamMP3).loop = true
		elif s is AudioStreamWAV:
			var w := s as AudioStreamWAV
			if w.loop_mode == AudioStreamWAV.LOOP_DISABLED:
				w.loop_mode = AudioStreamWAV.LOOP_FORWARD
				w.loop_begin = 0
				var bytes_per := (2 if w.format == AudioStreamWAV.FORMAT_16_BITS else 1) * (2 if w.stereo else 1)
				w.loop_end = w.data.size() / bytes_per
	_music_cache[track] = s
	return s

func _process(dt: float) -> void:
	_clock += dt
	var duck_goal := 0.15 if _clock < _duck_until else 1.0
	_duck = move_toward(_duck, duck_goal, dt * (6.0 if duck_goal < _duck else 1.5))
	for i in 2:
		_mvol[i] = move_toward(_mvol[i], _mtarget[i], dt / CROSSFADE)
		var m := _music[i]
		var v: float = _mvol[i] * music_volume * _duck
		m.volume_db = linear_to_db(maxf(v, 0.0001))
		if _mvol[i] <= 0.0 and _mtarget[i] <= 0.0 and m.playing:
			m.stop()

# ---------------------------------------------------------------- synthesis
## Turns float samples (-1..1) into a 16-bit mono AudioStreamWAV.
static func make_stream(buf: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in buf.size():
		bytes.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32767.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = bytes
	return s

static func midi(n: float) -> float:
	return 440.0 * pow(2.0, (n - 69.0) / 12.0)

## A mixing buffer that grows as voices are added.
class Buf:
	var d := PackedFloat32Array()

	func ensure(n: int) -> void:
		var old := d.size()
		if n > old:
			d.resize(n)
			for i in range(old, n):
				d[i] = 0.0

	## One voice. o keys: wave ("sq" | "tri" | "saw" | "sine" | "noise"), f (Hz), f1 (end Hz, sweep),
	## curve ("exp" | "lin"), duty (0..1), duty1 (end duty), vol, a, d, s, r (ADSR seconds / sustain level),
	## vib (semitones), vib_rate (Hz), arp (Array of semitone offsets), arp_rate (Hz), short (metallic noise).
	func tone(t0: float, dur: float, o: Dictionary) -> void:
		var start := int(t0 * RATE)
		var n := int(dur * RATE)
		if n <= 0:
			return
		ensure(start + n)
		var wave: String = o.get("wave", "sq")
		var f0: float = o.get("f", 440.0)
		var f1: float = o.get("f1", f0)
		var lin: bool = o.get("curve", "exp") == "lin"
		var duty0: float = o.get("duty", 0.5)
		var duty1: float = o.get("duty1", duty0)
		var vol: float = o.get("vol", 0.5)
		var a: float = o.get("a", 0.003)
		var dd: float = o.get("d", 0.0)
		var sl: float = o.get("s", 1.0)
		var r: float = minf(o.get("r", 0.012), dur)
		var vib: float = o.get("vib", 0.0)
		var vib_rate: float = o.get("vib_rate", 6.0)
		var arp: Array = o.get("arp", [])
		var arp_rate: float = o.get("arp_rate", 30.0)
		var short_noise: bool = o.get("short", false)
		var ratio := pow(f1 / f0, 1.0 / n) if f0 > 0 and f1 > 0 else 1.0
		var f := f0
		var phase := 0.0
		var lfsr := 0x7FFF
		var nval := 1.0
		for i in n:
			var t := float(i) / RATE
			# Frequency for this sample.
			if lin:
				f = f0 + (f1 - f0) * (float(i) / n)
			elif i > 0:
				f *= ratio
			var ff := f
			if arp.size():
				ff *= pow(2.0, float(arp[int(t * arp_rate) % arp.size()]) / 12.0)
			if vib != 0.0:
				ff *= pow(2.0, vib * sin(TAU * vib_rate * t) / 12.0)
			# Oscillator.
			var smp := 0.0
			if wave == "noise":
				phase += ff / RATE
				while phase >= 1.0:
					phase -= 1.0
					var bit := (lfsr ^ (lfsr >> 1)) & 1
					lfsr = (lfsr >> 1) | (bit << 14)
					if short_noise:
						lfsr = (lfsr & ~0x40) | (bit << 6)
					nval = 1.0 if (lfsr & 1) else -1.0
				smp = nval
			else:
				phase += ff / RATE
				phase -= floorf(phase)
				match wave:
					"sq":
						var duty := duty0 + (duty1 - duty0) * (float(i) / n)
						smp = 1.0 if phase < duty else -1.0
					"tri":
						smp = 4.0 * absf(phase - 0.5) - 1.0
					"saw":
						smp = 2.0 * phase - 1.0
					_:
						smp = sin(TAU * phase)
			# ADSR envelope.
			var env := 1.0
			if t < a:
				env = t / a
			elif t < a + dd:
				env = 1.0 - (1.0 - sl) * ((t - a) / dd)
			else:
				env = sl
			var rem := dur - t
			if rem < r:
				env *= rem / r
			d[start + i] += smp * env * vol

	## Plays a note list [[midi (0 = rest), steps], ...] with one voice. Returns the end time.
	func seq(t0: float, step: float, notes: Array, o: Dictionary) -> float:
		var t := t0
		var gate: float = o.get("gate", 0.92)
		for nt in notes:
			var len_s: float = nt[1] * step
			if nt[0] > 0:
				var oo := o.duplicate()
				oo.f = 440.0 * pow(2.0, (float(nt[0]) - 69.0) / 12.0)
				tone(t, len_s * gate, oo)
			t += len_s
		return t

	## Final pass: gentle low-pass, short fade-out, peak limit to 0.9.
	func finish(tail: float = 0.02) -> PackedFloat32Array:
		ensure(d.size() + int(tail * RATE))
		var y := 0.0
		var k := 0.82
		var peak := 0.0
		for i in d.size():
			y += k * (d[i] - y)
			d[i] = y
			peak = maxf(peak, absf(y))
		if peak > 0.9:
			var g := 0.9 / peak
			for i in d.size():
				d[i] *= g
		return d

## Builds one SFX's samples by name.
func build(sfx_name: String) -> PackedFloat32Array:
	var b := Buf.new()
	match sfx_name:
		"cursor":
			b.tone(0, 0.035, {"f": 1568, "duty": 0.25, "vol": 0.28, "r": 0.02})
		"text":
			b.tone(0, 0.025, {"f": 1175, "duty": 0.5, "vol": 0.12, "r": 0.015})
		"confirm":
			b.tone(0, 0.045, {"f": 988, "duty": 0.5, "vol": 0.3})
			b.tone(0.045, 0.08, {"f": 1319, "duty": 0.5, "vol": 0.3, "r": 0.05})
		"cancel":
			b.tone(0, 0.04, {"f": 784, "duty": 0.25, "vol": 0.3})
			b.tone(0.04, 0.08, {"f": 523, "f1": 440, "duty": 0.25, "vol": 0.3, "r": 0.05})
		"error":
			b.tone(0, 0.09, {"f": 196, "duty": 0.5, "vol": 0.3})
			b.tone(0.11, 0.12, {"f": 185, "duty": 0.5, "vol": 0.3, "r": 0.05})
		"bump":
			b.tone(0, 0.09, {"f": 110, "f1": 55, "duty": 0.5, "vol": 0.45, "r": 0.05})
			b.tone(0, 0.05, {"wave": "noise", "f": 1200, "f1": 400, "vol": 0.18, "r": 0.04})
		"door":
			b.tone(0, 0.03, {"wave": "noise", "f": 6000, "vol": 0.25, "r": 0.02})
			b.tone(0.03, 0.28, {"wave": "noise", "f": 900, "f1": 3500, "vol": 0.22, "a": 0.08, "r": 0.15})
			b.tone(0.05, 0.22, {"f": 220, "f1": 330, "duty": 0.125, "vol": 0.12, "a": 0.05, "r": 0.12})
		"encounter":
			# Fluttering rising arpeggio, then a falling swirl.
			var notes: Array = []
			for i in 14:
				notes.append([60 + i * 2 + (12 if i % 2 else 0), 1])
			b.seq(0, 0.03, notes, {"duty": 0.25, "vol": 0.26, "gate": 1.0, "r": 0.004})
			b.tone(0.42, 0.4, {"f": 1760, "f1": 220, "duty": 0.5, "vol": 0.24, "vib": 0.8, "vib_rate": 18, "r": 0.15})
			b.tone(0.0, 0.82, {"wave": "tri", "f": 110, "f1": 55, "vol": 0.3, "r": 0.2})
		"hit":
			b.tone(0, 0.13, {"wave": "noise", "f": 4000, "f1": 1200, "vol": 0.45, "d": 0.1, "s": 0.2, "r": 0.03})
			b.tone(0, 0.1, {"f": 260, "f1": 70, "duty": 0.5, "vol": 0.3, "r": 0.04})
		"hit_super":
			b.tone(0, 0.08, {"wave": "noise", "f": 6000, "f1": 2500, "vol": 0.55})
			b.tone(0.07, 0.22, {"wave": "noise", "f": 2500, "f1": 500, "vol": 0.5, "d": 0.15, "s": 0.3, "r": 0.06})
			b.tone(0, 0.26, {"f": 520, "f1": 45, "duty": 0.5, "vol": 0.38, "r": 0.08})
		"hit_weak":
			b.tone(0, 0.07, {"wave": "noise", "f": 7000, "f1": 3500, "vol": 0.25, "r": 0.04})
			b.tone(0, 0.05, {"f": 330, "f1": 200, "duty": 0.25, "vol": 0.12, "r": 0.03})
		"faint":
			b.tone(0, 0.65, {"f": 880, "f1": 90, "duty": 0.5, "duty1": 0.125, "vol": 0.32, "vib": 0.5, "vib_rate": 9, "r": 0.2})
			b.tone(0.55, 0.16, {"wave": "noise", "f": 800, "f1": 200, "vol": 0.3, "r": 0.1})
		"stat_up":
			for i in 3:
				b.tone(i * 0.11, 0.13, {"f": 392 * pow(1.26, i), "f1": 1568 * pow(1.26, i), "duty": 0.25, "vol": 0.24, "r": 0.03})
			b.tone(0, 0.36, {"wave": "tri", "f": 196, "f1": 392, "vol": 0.25, "r": 0.08})
		"stat_down":
			for i in 3:
				b.tone(i * 0.11, 0.13, {"f": 1568 / pow(1.26, i), "f1": 392 / pow(1.26, i), "duty": 0.25, "vol": 0.24, "r": 0.03})
			b.tone(0, 0.36, {"wave": "tri", "f": 392, "f1": 147, "vol": 0.25, "r": 0.08})
		"status":
			b.tone(0, 0.38, {"f": 466, "f1": 392, "duty": 0.5, "vol": 0.26, "vib": 2.0, "vib_rate": 22, "r": 0.1})
			b.tone(0, 0.38, {"wave": "noise", "f": 1500, "vol": 0.1, "short": true, "a": 0.05, "r": 0.15})
		"recover":
			b.tone(0, 0.42, {"f": 523, "duty": 0.125, "vol": 0.22, "arp": [0, 4, 7, 12], "arp_rate": 28, "vib": 0.2, "r": 0.15})
			b.tone(0, 0.42, {"wave": "tri", "f": 262, "f1": 523, "vol": 0.22, "r": 0.15})
		"send_out":
			b.tone(0, 0.05, {"wave": "noise", "f": 5000, "vol": 0.3, "r": 0.03})
			b.tone(0.03, 0.16, {"f": 330, "f1": 1320, "duty": 0.5, "vol": 0.26, "r": 0.06})
			b.tone(0.12, 0.12, {"wave": "noise", "f": 3000, "f1": 1000, "vol": 0.18, "r": 0.08})
		"orb_throw":
			b.tone(0, 0.32, {"wave": "noise", "f": 1500, "f1": 5000, "vol": 0.22, "a": 0.1, "r": 0.15})
			b.tone(0, 0.18, {"f": 330, "f1": 990, "duty": 0.125, "vol": 0.18, "r": 0.05})
			b.tone(0.18, 0.14, {"f": 990, "f1": 495, "duty": 0.125, "vol": 0.16, "r": 0.06})
		"orb_shake":
			b.tone(0, 0.04, {"wave": "noise", "f": 3000, "vol": 0.3, "r": 0.02})
			b.tone(0, 0.06, {"f": 247, "duty": 0.5, "vol": 0.28})
			b.tone(0.08, 0.04, {"wave": "noise", "f": 2500, "vol": 0.25, "r": 0.02})
			b.tone(0.08, 0.07, {"f": 196, "duty": 0.5, "vol": 0.26, "r": 0.04})
		"breakout":
			b.tone(0, 0.08, {"wave": "noise", "f": 7000, "f1": 2000, "vol": 0.45, "r": 0.04})
			b.tone(0.02, 0.2, {"f": 196, "f1": 1175, "duty": 0.5, "vol": 0.3, "r": 0.08})
			b.tone(0.06, 0.16, {"f": 294, "f1": 1760, "duty": 0.25, "vol": 0.18, "r": 0.08})
		"catch":
			var st := 0.09
			b.seq(0, st, [[79, 1], [78, 1], [79, 1], [83, 1], [86, 2], [0, 1], [84, 1], [86, 6]], {"duty": 0.5, "vol": 0.24, "r": 0.03})
			b.seq(0, st, [[71, 1], [69, 1], [71, 1], [74, 1], [78, 2], [0, 1], [76, 1], [78, 6]], {"duty": 0.25, "vol": 0.14, "r": 0.03})
			b.seq(0, st, [[43, 2], [50, 2], [55, 2], [0, 1], [48, 1], [55, 6]], {"wave": "tri", "vol": 0.35, "r": 0.04})
		"level_up":
			var st := 0.07
			b.seq(0, st, [[72, 1], [76, 1], [79, 1], [84, 1], [0, 1], [83, 1], [84, 5]], {"duty": 0.5, "vol": 0.24, "r": 0.03})
			b.seq(0, st, [[64, 1], [67, 1], [72, 1], [76, 1], [0, 1], [79, 1], [79, 5]], {"duty": 0.25, "vol": 0.15, "r": 0.03})
			b.seq(0, st, [[48, 4], [0, 1], [43, 1], [48, 5]], {"wave": "tri", "vol": 0.35, "r": 0.04})
		"exp":
			b.tone(0, 0.5, {"f": 520, "f1": 1560, "duty": 0.125, "vol": 0.14, "arp": [0, 12], "arp_rate": 40, "r": 0.05})
		"heal":
			# Rest Lodge jingle.
			var st := 0.1
			b.seq(0, st, [[76, 1], [79, 1], [84, 2], [83, 1], [79, 1], [81, 2], [77, 1], [81, 1], [84, 1], [86, 1], [88, 4]], {"duty": 0.5, "vol": 0.22, "r": 0.03})
			b.seq(0, st, [[72, 1], [76, 1], [79, 2], [79, 1], [76, 1], [77, 2], [74, 1], [77, 1], [81, 1], [83, 1], [84, 4]], {"duty": 0.25, "vol": 0.12, "r": 0.03})
			b.seq(0, st, [[48, 4], [53, 4], [55, 4], [48, 4]], {"wave": "tri", "vol": 0.35, "r": 0.04})
		"evolve_start":
			b.tone(0, 1.4, {"f": 262, "f1": 1047, "duty": 0.125, "vol": 0.2, "arp": [0, 4, 7, 12], "arp_rate": 24, "vib": 0.3, "a": 0.5, "r": 0.4})
			b.tone(0, 1.4, {"wave": "tri", "f": 65, "f1": 131, "vol": 0.3, "a": 0.4, "r": 0.4})
			b.tone(0.3, 1.1, {"wave": "noise", "f": 2000, "f1": 8000, "vol": 0.06, "a": 0.6, "r": 0.4})
		"evolve_done":
			var st := 0.1
			b.seq(0, st, [[72, 2], [72, 1], [74, 1], [76, 2], [79, 2], [77, 2], [76, 1], [74, 1], [76, 2], [84, 6]], {"duty": 0.5, "vol": 0.22, "r": 0.03})
			b.seq(0, st, [[64, 2], [64, 1], [65, 1], [67, 2], [71, 2], [69, 2], [67, 1], [65, 1], [67, 2], [76, 6]], {"duty": 0.25, "vol": 0.13, "r": 0.03})
			b.seq(0, st, [[48, 4], [53, 4], [55, 4], [48, 8]], {"wave": "tri", "vol": 0.35, "r": 0.05})
		"run":
			for i in 3:
				b.tone(i * 0.08, 0.05, {"wave": "noise", "f": 2500 - i * 500, "vol": 0.28, "r": 0.03})
			b.tone(0.05, 0.3, {"f": 880, "f1": 220, "duty": 0.25, "vol": 0.18, "r": 0.1})
		"low_hp":
			for i in 2:
				b.tone(i * 0.16, 0.09, {"f": 988, "duty": 0.5, "vol": 0.18, "r": 0.02})
		"save":
			var st := 0.06
			b.seq(0, st, [[72, 1], [79, 1], [76, 1], [84, 4]], {"duty": 0.25, "vol": 0.24, "r": 0.06})
			b.seq(st * 0.5, st, [[72, 1], [79, 1], [76, 1], [84, 4]], {"duty": 0.125, "vol": 0.08, "r": 0.06})
		"badge":
			var st := 0.09
			b.seq(0, st, [[67, 1], [67, 1], [67, 1], [72, 3], [0, 1], [71, 1], [72, 1], [74, 1], [76, 3], [0, 1], [79, 2], [77, 1], [76, 1], [77, 1], [79, 6]], {"duty": 0.5, "vol": 0.22, "r": 0.03})
			b.seq(0, st, [[64, 1], [64, 1], [64, 1], [67, 3], [0, 1], [67, 1], [69, 1], [71, 1], [72, 3], [0, 1], [76, 2], [74, 1], [72, 1], [74, 1], [76, 6]], {"duty": 0.25, "vol": 0.13, "r": 0.03})
			b.seq(0, st, [[48, 3], [48, 3], [0, 1], [43, 1], [45, 1], [47, 1], [48, 3], [0, 1], [52, 2], [53, 3], [55, 6]], {"wave": "tri", "vol": 0.35, "r": 0.04})
			for i in [0, 3, 6, 10, 13, 16, 19]:
				b.tone(i * st, 0.05, {"wave": "noise", "f": 5000, "vol": 0.12, "r": 0.03})
		"buy":
			b.tone(0, 0.02, {"wave": "noise", "f": 8000, "vol": 0.2})
			b.tone(0.0, 0.06, {"f": 1568, "duty": 0.5, "vol": 0.24})
			b.tone(0.06, 0.3, {"f": 2093, "duty": 0.5, "vol": 0.24, "d": 0.25, "s": 0.0, "r": 0.02})
			b.tone(0.06, 0.3, {"wave": "tri", "f": 1047, "vol": 0.2, "d": 0.25, "s": 0.0, "r": 0.02})
		"spotted":
			b.tone(0, 0.06, {"f": 600, "f1": 1800, "duty": 0.25, "vol": 0.26})
			b.tone(0, 0.05, {"wave": "noise", "f": 6000, "vol": 0.18, "r": 0.03})
			b.seq(0.08, 0.05, [[81, 2], [0, 1], [81, 4]], {"duty": 0.25, "vol": 0.24, "r": 0.04})
			b.seq(0.08, 0.05, [[69, 2], [0, 1], [70, 4]], {"wave": "tri", "vol": 0.3, "r": 0.04})
		"ledge":
			b.tone(0, 0.13, {"f": 300, "f1": 900, "duty": 0.25, "vol": 0.22, "r": 0.03})
			b.tone(0.2, 0.07, {"f": 120, "f1": 60, "duty": 0.5, "vol": 0.3, "r": 0.04})
			b.tone(0.2, 0.05, {"wave": "noise", "f": 1500, "vol": 0.16, "r": 0.03})
		_:
			return PackedFloat32Array()
	return b.finish()
