class_name LanScenes
## Screens for joining a friend's game over the network: finding a game, typing a host's address,
## and the joined player's screen (drawn by the host's computer).

static func _backdrop(title: String) -> void:
	Gfx.rect(0, 0, Gfx.W, Gfx.H, "#e8e0c8")
	Gfx.rect(0, 0, Gfx.W, 20, "#5868a8")
	Gfx.text(title, Gfx.W / 2.0, 7, {"size": 6, "align": "center", "color": "#ffffff"})

static func _lines(lines: Array, y: float) -> float:
	for l in lines:
		for w in Gfx.wrap(l, 208, 6):
			Gfx.text(w, 16, y, {"size": 6})
			y += 10
		y += 3
	return y

## Client side: lists games announced on the network, or connects to a typed address.
class Join extends Scene:
	var _sel := 0
	var _connecting := ""
	var _since := 0.0
	var _message := ""
	var _name := ""

	func _init() -> void:
		Net.browse()

	func _set_name(n: String, ip: String) -> void:
		_name = n
		_connect(ip)

	func _items() -> Array:
		var out: Array = []
		for ip in Net.found:
			out.append({"label": "%s  (%s)" % [Net.found[ip].name, ip], "ip": ip})
		out.append({"label": "ENTER ADDRESS"})
		out.append({"label": "BACK"})
		return out

	func update(dt: float) -> void:
		if _connecting != "":
			_since += dt
			if Net.connected:
				Net.stop_browse()
				Game.transition(func() -> void: Game.replace(LanScenes.RemoteScreen.new()))
				_connecting = ""
			elif Net.lost or _since > 6.0:
				Net.stop()
				_message = "Couldn't reach a game at %s." % _connecting
				_connecting = ""
			return
		var inp := Game.input.p(0)
		var items := _items()
		_sel = mini(_sel, items.size() - 1)
		if inp.pressed("up"):
			_sel = (_sel + items.size() - 1) % items.size()
			Audio.sfx("cursor")
		if inp.pressed("down"):
			_sel = (_sel + 1) % items.size()
			Audio.sfx("cursor")
		if inp.pressed("b"):
			_back()
		elif inp.pressed("a"):
			Audio.sfx("confirm")
			var it: Dictionary = items[_sel]
			if it.has("ip"):
				_connect(it.ip)
			elif it.label == "BACK":
				_back()
			else:
				Game.push(LanScenes.AddressEntry.new(_on_address))

	func _on_address(ip: String) -> void:
		if ip != "":
			_connect(ip)

	func _connect(ip: String) -> void:
		_message = ""
		# Without a save, ask for a name first; creatures come from PROF. ALDER once they arrive.
		var save: Variant = GameState.load_game()
		if save == null and _name == "":
			Game.push(NameEntryScene.new(0, "YOUR NAME?", "p2", "Juno", func(n: String) -> void: _set_name(n, ip)))
			return
		if Net.join(ip, _name) != OK:
			_message = "Couldn't connect to %s." % ip
			return
		_connecting = ip
		_since = 0.0

	func _back() -> void:
		Audio.sfx("cancel")
		Net.stop_browse()
		Net.stop()
		Game.transition(func() -> void: Game.replace(TitleScene.new()))

	func draw() -> void:
		LanScenes._backdrop("JOIN A GAME")
		if _connecting != "":
			LanScenes._lines(["Connecting to %s..." % _connecting], 70)
			return
		var items := _items()
		var hint := "Looking for games on your network..." if items.size() == 2 else "Pick a game to join:"
		Gfx.text(hint, 16, 28, {"size": 6})
		Gfx.panel(12, 40, 216, 96)
		for i in mini(items.size(), 8):
			var y := 47 + i * 11
			if i == _sel:
				Gfx.cursor(18, y)
			Gfx.text(items[i].label, 26, y, {"size": 6})
		if _message != "":
			Gfx.text(_message, Gfx.W / 2.0, 142, {"size": 5, "align": "center", "color": "#c03030", "shadow": null})
		else:
			Gfx.text("Your friend needs to be playing (past the title screen).", Gfx.W / 2.0, 142, {"size": 5, "align": "center", "color": "#707880", "shadow": null})

## Typing an IP address with the number keys. Enter connects, Esc cancels.
class AddressEntry extends Scene:
	const DIGITS := {
		KEY_0: "0", KEY_1: "1", KEY_2: "2", KEY_3: "3", KEY_4: "4", KEY_5: "5", KEY_6: "6", KEY_7: "7", KEY_8: "8", KEY_9: "9",
		KEY_KP_0: "0", KEY_KP_1: "1", KEY_KP_2: "2", KEY_KP_3: "3", KEY_KP_4: "4", KEY_KP_5: "5", KEY_KP_6: "6", KEY_KP_7: "7", KEY_KP_8: "8", KEY_KP_9: "9",
		KEY_PERIOD: ".", KEY_KP_PERIOD: ".",
	}
	var _on_done: Callable
	var _text := ""
	var _prev := {}

	func _init(on_done: Callable) -> void:
		overlay = true
		_on_done = on_done
		# Most home networks share the first three numbers, so start from this computer's.
		var mine := Net.local_addresses()
		if not mine.is_empty():
			var parts: PackedStringArray = (mine[0] as String).split(".")
			_text = ".".join(parts.slice(0, 3)) + "."
		_prev = Game.input.keys.duplicate()

	func update(_dt: float) -> void:
		var keys: Dictionary = Game.input.keys
		for k in keys:
			if _prev.has(k):
				continue
			if DIGITS.has(k) and _text.length() < 15:
				_text += DIGITS[k]
				Audio.sfx("cursor")
			elif k == KEY_BACKSPACE or k == KEY_DELETE:
				_text = _text.substr(0, maxi(0, _text.length() - 1))
			elif k == KEY_ENTER or k == KEY_KP_ENTER:
				_finish(_text if _text.is_valid_ip_address() else "")
				return
			elif k == KEY_ESCAPE:
				_finish("")
				return
		_prev = keys.duplicate()

	func _finish(ip: String) -> void:
		Game.pop(self)
		_on_done.call(ip)

	func draw() -> void:
		Gfx.panel(24, 50, 192, 60)
		Gfx.text("HOST'S ADDRESS", Gfx.W / 2.0, 58, {"size": 6, "align": "center"})
		var shown := _text + ("_" if floori(Game.time * 2) % 2 == 0 else " ")
		Gfx.text(shown, Gfx.W / 2.0, 74, {"size": 8, "align": "center", "color": "#3858a8"})
		Gfx.text("Number keys and . to type", Gfx.W / 2.0, 90, {"size": 5, "align": "center", "color": "#707880", "shadow": null})
		Gfx.text("Enter: join   Esc: cancel", Gfx.W / 2.0, 99, {"size": 5, "align": "center", "color": "#707880", "shadow": null})

## The joined player's computer: shows the frames the host draws for them and sends this
## computer's buttons.
class RemoteScreen extends Scene:
	func _init() -> void:
		Audio.stop_music()
		if DisplayServer.get_name() != "headless":
			DisplayServer.window_set_title("Wildbound - joined game")

	func update(_dt: float) -> void:
		if Net.lost or Net.role != Net.Role.CLIENT:
			Net.stop()
			Audio.stop_music()
			Game.replace(TitleScene.new())
			Game.say(["The connection to your friend's game was lost. Your progress there was saved on this computer."])
			return
		Net.send_buttons(Game.input.p(0).held)

	func draw() -> void:
		if Net.frame.is_empty():
			LanScenes._backdrop("JOIN A GAME")
			LanScenes._lines(["Connected! Waiting for your friend's game..."], 70)
			return
		DrawRecorder.replay(Net.frame, Gfx.ci, Net.textures)
