class_name GameInput
## Two-player keyboard + gamepad input. In solo mode both key sets drive player 1.
## In LAN co-op (remote) player 2's buttons come from their own computer, and every local key
## and gamepad drives player 1.

const BUTTONS := ["up", "down", "left", "right", "a", "b", "start"]
const KEYMAP := [
	{KEY_W: "up", KEY_S: "down", KEY_A: "left", KEY_D: "right", KEY_F: "a", KEY_G: "b", KEY_R: "start"},
	{KEY_UP: "up", KEY_DOWN: "down", KEY_LEFT: "left", KEY_RIGHT: "right", KEY_ENTER: "a", KEY_KP_ENTER: "a", KEY_SLASH: "a", KEY_PERIOD: "b", KEY_BACKSPACE: "start"},
]
## Extra keys that only count for player 1 in solo mode.
const SOLO_EXTRA := {
	KEY_UP: "up", KEY_DOWN: "down", KEY_LEFT: "left", KEY_RIGHT: "right", KEY_Z: "a", KEY_ENTER: "a", KEY_SPACE: "a",
	KEY_X: "b", KEY_SHIFT: "b", KEY_BACKSPACE: "b", KEY_ESCAPE: "start", KEY_C: "start",
}

class PlayerInput:
	var held := {}
	var _prev := {}
	var _pressed := {}
	var _repeat := {}
	func pressed(b: String) -> bool:
		return _pressed.has(b)
	func is_held(b: String) -> bool:
		return held.has(b)
	func end_frame(now: Dictionary, dt: float) -> void:
		_pressed.clear()
		for b in BUTTONS:
			if now.has(b) and not _prev.has(b):
				_pressed[b] = true
				_repeat[b] = 0.35
			elif now.has(b) and b in ["up", "down", "left", "right"]:
				# Menu auto-repeat for held directions.
				_repeat[b] = _repeat.get(b, 0.0) - dt
				if _repeat[b] <= 0:
					_pressed[b] = true
					_repeat[b] = 0.09
		held = now.duplicate()
		_prev = now.duplicate()

var coop := false
var players: Array[PlayerInput] = [PlayerInput.new(), PlayerInput.new()]
## Physical keycodes currently down.
var keys := {}
## Right Shift is P2's B button in co-op; Godot reports both shifts as KEY_SHIFT, so track it by location.
var right_shift := false
## LAN co-op: player 2 is on another computer (see Net).
var remote := false
var _remote_held := {}
## Buttons player 2 pressed since the last frame, so a quick tap isn't lost between frames.
var _remote_taps := {}

func set_remote(on: bool) -> void:
	remote = on
	_remote_held = {}
	_remote_taps = {}

func set_remote_buttons(held: Dictionary) -> void:
	for b in held:
		if not _remote_held.has(b):
			_remote_taps[b] = true
	_remote_held = held

func handle_event(e: InputEvent) -> void:
	if e is InputEventKey and not e.echo:
		var k: int = e.physical_keycode
		if k == KEY_SHIFT and e.location == KEY_LOCATION_RIGHT:
			right_shift = e.pressed
		if e.pressed:
			keys[k] = true
		else:
			keys.erase(k)

func update(dt: float) -> void:
	var now := [{}, {}]
	# Split the keyboard between two players only when both share this computer.
	var split := coop and not remote
	for k in keys:
		if split:
			if KEYMAP[0].has(k):
				now[0][KEYMAP[0][k]] = true
			if KEYMAP[1].has(k):
				now[1][KEYMAP[1][k]] = true
		else:
			var b: String = KEYMAP[0].get(k, KEYMAP[1].get(k, SOLO_EXTRA.get(k, "")))
			if b != "":
				now[0][b] = true
	if split and right_shift:
		now[1]["b"] = true
	var pi := 0
	for pad in Input.get_connected_joypads():
		if pi > 1:
			break
		var target: int = pi if split else 0
		var ax := Input.get_joy_axis(pad, JOY_AXIS_LEFT_X)
		var ay := Input.get_joy_axis(pad, JOY_AXIS_LEFT_Y)
		if ay < -0.5 or Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_UP): now[target]["up"] = true
		if ay > 0.5 or Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_DOWN): now[target]["down"] = true
		if ax < -0.5 or Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_LEFT): now[target]["left"] = true
		if ax > 0.5 or Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_RIGHT): now[target]["right"] = true
		if Input.is_joy_button_pressed(pad, JOY_BUTTON_A): now[target]["a"] = true
		if Input.is_joy_button_pressed(pad, JOY_BUTTON_B): now[target]["b"] = true
		if Input.is_joy_button_pressed(pad, JOY_BUTTON_START) or Input.is_joy_button_pressed(pad, JOY_BUTTON_Y): now[target]["start"] = true
		pi += 1
	if coop and remote:
		now[1] = _remote_held.duplicate()
		now[1].merge(_remote_taps)
		_remote_taps = {}
	players[0].end_frame(now[0], dt)
	players[1].end_frame(now[1], dt)

func p(i: int) -> PlayerInput:
	return players[i if coop else 0]

## Either player pressed (used for shared prompts like dialogue).
func any(b: String) -> bool:
	return players[0].pressed(b) or (coop and players[1].pressed(b))
