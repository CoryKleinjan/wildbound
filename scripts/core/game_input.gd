class_name GameInput
## Keyboard + gamepad input. Every local key and gamepad drives the player at this computer
## (view 0); a friend who joined over the network sends their buttons (view 1, see Net).
## p() and any() read the buttons of the view being updated (view, set by Game).

const BUTTONS := ["up", "down", "left", "right", "a", "b", "start"]
const KEYMAP := {
	KEY_W: "up", KEY_S: "down", KEY_A: "left", KEY_D: "right", KEY_F: "a", KEY_G: "b", KEY_R: "start",
	KEY_UP: "up", KEY_DOWN: "down", KEY_LEFT: "left", KEY_RIGHT: "right", KEY_ENTER: "a", KEY_KP_ENTER: "a", KEY_SLASH: "a",
	KEY_PERIOD: "b", KEY_BACKSPACE: "start", KEY_Z: "a", KEY_SPACE: "a", KEY_X: "b", KEY_SHIFT: "b", KEY_ESCAPE: "start", KEY_C: "start",
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

var players: Array[PlayerInput] = [PlayerInput.new(), PlayerInput.new()]
var view := 0
## During a joint battle (see JointBattle) p(i) reads player i, whichever view is updating.
var joint := false
## Physical keycodes currently down.
var keys := {}
var _remote_held := {}
## Buttons the friend pressed since the last frame, so a quick tap isn't lost between frames.
var _remote_taps := {}

func handle_event(e: InputEvent) -> void:
	if e is InputEventKey and not e.echo:
		var k: int = e.physical_keycode
		if e.pressed:
			keys[k] = true
		else:
			keys.erase(k)

## The friend's held buttons, from the network.
func set_remote_buttons(held: Dictionary) -> void:
	for b in held:
		if not _remote_held.has(b):
			_remote_taps[b] = true
	_remote_held = held

func clear_remote() -> void:
	_remote_held = {}
	_remote_taps = {}

func update(dt: float) -> void:
	var now := {}
	for k in keys:
		if KEYMAP.has(k):
			now[KEYMAP[k]] = true
	for pad in Input.get_connected_joypads():
		var ax := Input.get_joy_axis(pad, JOY_AXIS_LEFT_X)
		var ay := Input.get_joy_axis(pad, JOY_AXIS_LEFT_Y)
		if ay < -0.5 or Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_UP): now["up"] = true
		if ay > 0.5 or Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_DOWN): now["down"] = true
		if ax < -0.5 or Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_LEFT): now["left"] = true
		if ax > 0.5 or Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_RIGHT): now["right"] = true
		if Input.is_joy_button_pressed(pad, JOY_BUTTON_A): now["a"] = true
		if Input.is_joy_button_pressed(pad, JOY_BUTTON_B): now["b"] = true
		if Input.is_joy_button_pressed(pad, JOY_BUTTON_START) or Input.is_joy_button_pressed(pad, JOY_BUTTON_Y): now["start"] = true
	var remote: Dictionary = _remote_held.duplicate()
	remote.merge(_remote_taps)
	_remote_taps = {}
	players[0].end_frame(now, dt)
	players[1].end_frame(remote, dt)

## The buttons of the view being updated. The player index only counts in a joint battle, where
## player 0 is this computer and player 1 is the friend; otherwise each view has one player.
func p(i: int = 0) -> PlayerInput:
	if joint:
		return players[clampi(i, 0, 1)]
	return players[view]

func any(b: String) -> bool:
	if joint:
		return players[0].pressed(b) or players[1].pressed(b)
	return players[view].pressed(b)
