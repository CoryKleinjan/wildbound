extends Node
## Scene stacks, input, the current save state and screen fades.
## There are two views of one world: view 0 is the player at this computer and view 1 is a friend
## who joined over the network (see Net). Each view has its own scene stack, save state and fade.
## stack, gs, push, pop, say and the rest act on the view being updated or drawn (cur).

class View:
	var stack: Array[Scene] = []
	## The view's GameState dictionary (see GameState.new_game), or null on the title screen.
	var gs: Variant = null
	## 0..1 black overlay.
	var fade := 0.0
	var fade_target := 0
	var fade_cb := Callable()

var views: Array[View] = [View.new(), View.new()]
var cur := 0
var input := GameInput.new()
var time := 0.0

var stack: Array[Scene]:
	get:
		return views[cur].stack
	set(v):
		views[cur].stack = v

var gs: Variant:
	get:
		return views[cur].gs
	set(v):
		views[cur].gs = v

var fade: float:
	get:
		return views[cur].fade
	set(v):
		views[cur].fade = v

## Runs cb with view v as the current one (for code outside update and draw, like Net).
func in_view(v: int, cb: Callable) -> Variant:
	var was := cur
	cur = v
	input.view = v
	var r: Variant = cb.call()
	cur = was
	input.view = was
	return r

## The other view's overworld, when that view is in the world.
func other_overworld() -> OverworldScene:
	var v := views[1 - cur]
	if v.stack.size() and v.stack[0] is OverworldScene:
		return v.stack[0]
	return null

## Drops the friend's view (they left).
func clear_guest() -> void:
	views[1] = View.new()

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
	views[cur].fade_target = 1
	views[cur].fade_cb = cb

func update(dt: float) -> void:
	time += dt
	input.update(dt)
	for v in views.size():
		if views[v].stack.is_empty():
			continue
		cur = v
		input.view = v
		_update_view(dt)
	cur = 0
	input.view = 0

func _update_view(dt: float) -> void:
	var v := views[cur]
	if gs != null:
		gs.playTime += dt
	if v.fade_target == 1:
		v.fade = minf(1, v.fade + dt * 4)
		if v.fade >= 1:
			var cb := v.fade_cb
			v.fade_cb = Callable()
			v.fade_target = 0
			if cb.is_valid():
				cb.call()
		return
	if v.fade > 0:
		v.fade = maxf(0, v.fade - dt * 4)
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
