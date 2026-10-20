extends Node
## Scene stack, input, the current save state and screen fades.

var stack: Array[Scene] = []
var input := GameInput.new()
## The current GameState dictionary (see GameState.new_game), or null on the title screen.
var gs: Variant = null
var time := 0.0
## 0..1 black overlay.
var fade := 0.0
var _fade_target := 0
var _fade_cb := Callable()

func start() -> void:
	replace(TitleScene.new())

func _input(e: InputEvent) -> void:
	input.handle_event(e)

func push(s: Scene) -> void:
	stack.append(s)

func pop(s: Scene = null) -> void:
	if s:
		var i := stack.rfind(s)
		if i >= 0:
			stack.remove_at(i)
	elif stack.size():
		stack.pop_back()

func replace(s: Scene) -> void:
	stack = [s]

var top: Scene:
	get:
		return stack.back() if stack.size() else null

## Fades to black, runs cb, fades back in.
func transition(cb: Callable) -> void:
	_fade_target = 1
	_fade_cb = cb

func update(dt: float) -> void:
	time += dt
	input.update(dt)
	if gs != null:
		gs.playTime += dt
	if _fade_target == 1:
		fade = minf(1, fade + dt * 4)
		if fade >= 1:
			var cb := _fade_cb
			_fade_cb = Callable()
			_fade_target = 0
			if cb.is_valid():
				cb.call()
		return
	if fade > 0:
		fade = maxf(0, fade - dt * 4)
	if top:
		top.update(dt)

func draw() -> void:
	var start_i := stack.size() - 1
	while start_i > 0 and stack[start_i].overlay:
		start_i -= 1
	for i in range(maxi(0, start_i), stack.size()):
		stack[i].draw()
	if fade > 0:
		Gfx.rect(0, 0, Gfx.W, Gfx.H, Color(0, 0, 0, fade))

func say(msgs: Array, on_done: Callable = Callable(), player: Variant = "any") -> void:
	push(Dialog.new(msgs, {"on_done": on_done, "player": player}))

func ask(msg: String, choices: Array, on_choice: Callable, player: Variant = "any") -> void:
	push(Dialog.new([msg], {"choices": choices, "on_choice": on_choice, "player": player}))

func player_tag(player: int, x: float, y: float) -> void:
	if gs == null or gs.mode != "coop":
		return
	Gfx.rect(x, y, 18, 9, "#e04848" if player == 0 else "#3878e0")
	Gfx.text("P%d" % (player + 1), x + 3, y + 2, {"color": "#ffffff", "size": 5, "shadow": null})
