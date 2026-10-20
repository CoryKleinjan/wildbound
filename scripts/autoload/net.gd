extends Node
## Drop-in co-op over the local network. Whoever is playing hosts: their computer runs the world.
## A friend can join at any time from their own computer with the creatures, items and money from
## their own save. They get their own view of the world (Game view 1): they walk around on their
## own, on any map, while their computer sends its buttons and shows the frames (replayed draw
## calls) and sound the host makes for them. Their progress is sent back and saved on their
## computer. Hosts announce themselves with a UDP broadcast so the join screen can list them.

const PORT := 47777
const DISCOVERY_PORT := 47778
const M_FRAME := 1
const M_TEX := 2
const M_SFX := 3
const M_MUSIC := 4
const M_INPUT := 5
## Friend -> host: [M_HELLO, their save (or null), their name].
const M_HELLO := 6
## Host -> friend: [M_SAVE, their progress] to save on their computer.
const M_SAVE := 7
const CH_RELIABLE := 0
const CH_FRAMES := 1
## An unchanged frame is still re-sent this often (ms).
const RESEND_MS := 1000
## How often the friend's progress is checked for changes and sent home (ms).
const SYNC_MS := 3000
## The parts of a save that belong to the player rather than the world they're in.
const OWN_KEYS := ["players", "box", "bag", "money", "seen", "caught", "playTime", "bp", "decor", "coins", "pcItems", "mixed", "trendy"]

enum Role { NONE, HOST, CLIENT }
var role := Role.NONE
var _peer: ENetMultiplayerPeer

# Host
## The friend's peer id, 0 while nobody is connected.
var client_id := 0
var recorder := DrawRecorder.new()
var game_name := ""
var _last_frame := PackedByteArray()
var _last_sent_ms := 0
var _last_sync := PackedByteArray()
var _sync_ms := 0
var _beacon: PacketPeerUDP
var _beacon_t := 0.0

# Client
var connected := false
## Set when the connection to the host failed or dropped.
var lost := false
## The host's latest frame for us (DrawRecorder format) and the textures it uses.
var frame: Array = []
var textures := {}
var _sent_mask := -1
var _hello_sent := false
var _my_name := ""
var _browse: PacketPeerUDP
## Games found on the network: ip -> {name, seen (msec)}.
var found := {}

## One toast per view (shown on top of that view's screen).
var _toasts := [{"text": "", "until": 0}, {"text": "", "until": 0}]

## Starts accepting a friend. name is shown in their join list.
func host(name: String) -> Error:
	stop()
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_server(PORT, 1, 2)
	if err != OK:
		_peer = null
		return err
	_peer.peer_connected.connect(_on_joined)
	_peer.peer_disconnected.connect(_on_left)
	role = Role.HOST
	game_name = name
	_beacon = PacketPeerUDP.new()
	_beacon.set_broadcast_enabled(true)
	_beacon.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	_beacon_t = 0.0
	return OK

## Joins the game at ip as name (used when this computer has no save yet).
func join(ip: String, name: String) -> Error:
	stop()
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(ip, PORT, 2)
	if err != OK:
		_peer = null
		return err
	role = Role.CLIENT
	connected = false
	lost = false
	frame = []
	textures = {}
	_sent_mask = -1
	_hello_sent = false
	_my_name = name
	return OK

func stop() -> void:
	if _peer:
		_peer.close()
		_peer = null
	if _beacon:
		_beacon.close()
		_beacon = null
	if role == Role.HOST and client_id != 0:
		_drop_guest()
	role = Role.NONE
	client_id = 0
	connected = false

func is_hosting_with_player() -> bool:
	return role == Role.HOST and client_id != 0

## True once the friend is in the world (their view is running).
func guest_in_world() -> bool:
	return is_hosting_with_player() and Game.views[1].gs != null

## Starts listening for host announcements; results land in found.
func browse() -> void:
	stop_browse()
	found = {}
	_browse = PacketPeerUDP.new()
	_browse.bind(DISCOVERY_PORT)

func stop_browse() -> void:
	if _browse:
		_browse.close()
		_browse = null

## This computer's LAN addresses, for players to type in when discovery doesn't work.
static func local_addresses() -> Array:
	var out: Array = []
	for a in IP.get_local_addresses():
		if a.contains(".") and not a.begins_with("127.") and not a.begins_with("169.254."):
			out.append(a)
	return out

## Shows msg on top of view v's screen for a few seconds.
func toast(msg: String, v := 0, seconds := 4.0) -> void:
	_toasts[v] = {"text": msg, "until": Time.get_ticks_msec() + int(seconds * 1000)}

func _process(dt: float) -> void:
	if _browse:
		_poll_browse()
	if _peer == null:
		return
	_peer.poll()
	if _peer == null:
		return
	if role == Role.HOST:
		_beacon_t -= dt
		if _beacon_t <= 0:
			_beacon_t = 1.0
			_beacon.put_packet(JSON.stringify({"game": "wildbound", "v": 2, "name": game_name, "open": client_id == 0}).to_utf8_buffer())
		if guest_in_world() and Time.get_ticks_msec() - _sync_ms > SYNC_MS:
			sync_guest()
	while _peer != null and _peer.get_available_packet_count() > 0:
		var data: Variant = bytes_to_var(_peer.get_packet())
		if data is Array and data.size() > 0:
			_handle(data)
	if role == Role.CLIENT and _peer != null:
		match _peer.get_connection_status():
			MultiplayerPeer.CONNECTION_CONNECTED:
				connected = true
				if not _hello_sent:
					_hello_sent = true
					_send([M_HELLO, GameState.load_game(), _my_name])
			MultiplayerPeer.CONNECTION_DISCONNECTED:
				lost = true
				connected = false
				_peer.close()
				_peer = null

func _poll_browse() -> void:
	while _browse.get_available_packet_count() > 0:
		var pkt := _browse.get_packet()
		var ip := _browse.get_packet_ip()
		var d: Variant = JSON.parse_string(pkt.get_string_from_utf8())
		if not d is Dictionary or d.get("game") != "wildbound":
			continue
		if d.get("open", true):
			found[ip] = {"name": str(d.get("name", "")).substr(0, 24), "seen": Time.get_ticks_msec()}
		else:
			found.erase(ip)
	for ip in found.keys():
		if Time.get_ticks_msec() - found[ip].seen > 4000:
			found.erase(ip)

# ---------------------------------------------------------------- host: the friend's view
func _on_joined(id: int) -> void:
	if client_id != 0:
		_peer.disconnect_peer(id)
		return
	client_id = id
	recorder.reset()
	_last_frame = PackedByteArray()
	_last_sync = PackedByteArray()
	Game.input.clear_remote()
	Audio.reset_view(1)

func _on_left(id: int) -> void:
	if id != client_id:
		return
	var name := _guest_name()
	client_id = 0
	_drop_guest()
	if name != "":
		Audio.sfx("cancel")
		toast("%s left. Their progress was saved on their computer." % name)

func _guest_name() -> String:
	var g: Variant = Game.views[1].gs
	return g.players[0].name if g != null else ""

func _drop_guest() -> void:
	JointBattle.abort()
	Game.clear_guest()
	Game.input.clear_remote()
	Audio.reset_view(1)

## The friend arrives next to the host, with their own trainer, creatures, items and money, but in
## the host's world: story and trainer flags are shared (the same dictionary).
func _welcome(save: Variant, name: String) -> void:
	var host_gs: Variant = Game.views[0].gs
	if host_gs == null:
		_peer.disconnect_peer(client_id)
		return
	var gs := GameState.guest_state(save, name, host_gs)
	RecordMix.mix(host_gs, gs, save)
	# Arrive next to the host rather than on top of them.
	var host_ow: Variant = Game.views[0].stack[0] if Game.views[0].stack.size() else null
	if host_ow is OverworldScene and host_ow.map.id == gs.map:
		for d in [Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1)]:
			if host_ow._walkable(host_ow.player.x + d.x, host_ow.player.y + d.y):
				gs.x = host_ow.player.x + d.x
				gs.y = host_ow.player.y + d.y
				break
	Game.views[1].gs = gs
	Game.in_view(1, _start_guest_view.bind(host_gs.players[0].name))
	Audio.sfx("confirm")
	toast("%s joined your game!" % gs.players[0].name)
	sync_guest()

func _start_guest_view(host_name: String) -> void:
	Game.replace(OverworldScene.new())
	if Game.gs.players[0].party.is_empty():
		Story.gift_starter(host_name)
	else:
		Game.say(["Welcome to %s's world!" % host_name])

## Sends the friend's progress home if it changed.
func sync_guest() -> void:
	_sync_ms = Time.get_ticks_msec()
	var gs: Variant = Game.views[1].gs
	if gs == null:
		return
	var own := {}
	for k in OWN_KEYS:
		own[k] = gs[k]
	var bytes := var_to_bytes(own)
	# playTime always changes; compare without it so an idle friend isn't re-sent every few seconds.
	var cmp := var_to_bytes([own.players, own.box, own.bag, own.money, own.seen, own.caught])
	if cmp == _last_sync:
		return
	_last_sync = cmp
	_send([M_SAVE, bytes])

func _handle(data: Array) -> void:
	match int(data[0]):
		M_INPUT:
			if role == Role.HOST:
				var held := {}
				for i in GameInput.BUTTONS.size():
					if int(data[1]) & (1 << i):
						held[GameInput.BUTTONS[i]] = true
				Game.input.set_remote_buttons(held)
		M_HELLO:
			if role == Role.HOST and Game.views[1].gs == null and data.size() >= 3:
				_welcome(data[1], str(data[2]).substr(0, 8))
		M_FRAME:
			if role == Role.CLIENT:
				var raw: PackedByteArray = (data[1] as PackedByteArray).decompress(int(data[2]), FileAccess.COMPRESSION_ZSTD)
				var f: Variant = bytes_to_var(raw)
				if f is Array:
					frame = f
		M_TEX:
			if role == Role.CLIENT:
				var img := Image.new()
				if img.load_png_from_buffer(data[2]) == OK:
					textures[int(data[1])] = ImageTexture.create_from_image(img)
		M_SFX:
			if role == Role.CLIENT:
				Audio.sfx(str(data[1]))
		M_MUSIC:
			if role == Role.CLIENT:
				if str(data[1]) == "":
					Audio.stop_music()
				else:
					Audio.play_music(str(data[1]))
		M_SAVE:
			if role == Role.CLIENT:
				var own: Variant = bytes_to_var(data[1])
				if own is Dictionary:
					GameState.save_progress_from_host(own, _my_name)

func _send(data: Array, reliable := true) -> void:
	if _peer == null:
		return
	# Frames are bigger than one network packet, and unreliable packets that need splitting are
	# often lost, so they're sent reliably too, on their own channel so they don't hold up input.
	_peer.transfer_channel = CH_RELIABLE if reliable else CH_FRAMES
	_peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
	_peer.put_packet(var_to_bytes(data))

# ---------------------------------------------------------------- host: the friend's screen and sound
## Called by main.gd before drawing the friend's view; Gfx draws on the returned recorder, which
## records without touching this computer's screen.
func begin_frame() -> DrawRecorder:
	recorder.begin(null)
	return recorder

## Called by main.gd after drawing the friend's view: sends the frame if it changed.
func end_frame() -> void:
	for t in recorder.take_new_textures():
		_send([M_TEX, t[0], (t[1] as Texture2D).get_image().save_png_to_buffer()])
	var raw := var_to_bytes(recorder.cmds)
	var packed := raw.compress(FileAccess.COMPRESSION_ZSTD)
	var now := Time.get_ticks_msec()
	if packed == _last_frame and now - _last_sent_ms < RESEND_MS:
		return
	_last_frame = packed
	_last_sent_ms = now
	_send([M_FRAME, packed, raw.size()], false)

func relay_sfx(sfx_name: String) -> void:
	if is_hosting_with_player():
		_send([M_SFX, sfx_name])

func relay_music(track: String) -> void:
	if is_hosting_with_player():
		_send([M_MUSIC, track])

# ---------------------------------------------------------------- client: buttons
## Sends this computer's held buttons to the host whenever they change.
func send_buttons(held: Dictionary) -> void:
	if role != Role.CLIENT or not connected:
		return
	var mask := 0
	for i in GameInput.BUTTONS.size():
		if held.has(GameInput.BUTTONS[i]):
			mask |= 1 << i
	if mask != _sent_mask:
		_sent_mask = mask
		_send([M_INPUT, mask])

## The current view's toast (a friend joined or left).
func draw_overlay() -> void:
	var t: Dictionary = _toasts[Game.cur]
	if t.text == "" or Time.get_ticks_msec() > t.until:
		return
	var lines := Gfx.wrap(t.text, 208, 6)
	var h := 8 + lines.size() * 9
	Gfx.panel(8, 4, 224, h, "dark")
	for i in lines.size():
		Gfx.text(lines[i], 16, 8 + i * 9, {"size": 6, "color": "#ffffff", "shadow": null})
