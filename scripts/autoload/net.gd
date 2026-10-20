extends Node
## LAN co-op. The host's computer runs the whole game. Player 2's computer joins over the local
## network, sends its button presses, and shows the host's screen (replayed draw calls) and sound.
## Hosts announce themselves with a UDP broadcast so the join screen can list them.

const PORT := 47777
const DISCOVERY_PORT := 47778
const M_FRAME := 1
const M_TEX := 2
const M_SFX := 3
const M_MUSIC := 4
const M_INPUT := 5
const CH_RELIABLE := 0
const CH_FRAMES := 1
## An unchanged screen is still re-sent this often (ms), in case a frame packet was lost.
const RESEND_MS := 500

enum Role { NONE, HOST, CLIENT }
var role := Role.NONE
var _peer: ENetMultiplayerPeer

# Host
## The joined player's peer id, 0 while nobody is connected.
var client_id := 0
var recorder := DrawRecorder.new()
var game_name := ""
var _recording := false
var _last_frame := PackedByteArray()
var _last_sent_ms := 0
var _beacon: PacketPeerUDP
var _beacon_t := 0.0

# Client
var connected := false
## Set when the connection to the host failed or dropped.
var lost := false
## The host's latest screen (DrawRecorder format) and the textures it uses.
var frame: Array = []
var textures := {}
var _sent_mask := -1
var _browse: PacketPeerUDP
## Games found on the network: ip -> {name, seen (msec)}.
var found := {}

var _toast := ""
var _toast_until := 0

## Starts listening for player 2. name is shown in the join list.
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

func join(ip: String) -> Error:
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
	return OK

func stop() -> void:
	if _peer:
		_peer.close()
		_peer = null
	if _beacon:
		_beacon.close()
		_beacon = null
	role = Role.NONE
	client_id = 0
	connected = false
	Game.input.set_remote(false)

func is_hosting_with_player() -> bool:
	return role == Role.HOST and client_id != 0

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

func toast(msg: String, seconds := 4.0) -> void:
	_toast = msg
	_toast_until = Time.get_ticks_msec() + int(seconds * 1000)

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
			_beacon.put_packet(JSON.stringify({"game": "wildbound", "v": 1, "name": game_name, "open": client_id == 0}).to_utf8_buffer())
	while _peer != null and _peer.get_available_packet_count() > 0:
		var data: Variant = bytes_to_var(_peer.get_packet())
		if data is Array and data.size() > 0:
			_handle(data)
	if role == Role.CLIENT and _peer != null:
		match _peer.get_connection_status():
			MultiplayerPeer.CONNECTION_CONNECTED:
				connected = true
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
		if d is Dictionary and d.get("game") == "wildbound" and d.get("open", true):
			found[ip] = {"name": str(d.get("name", "")).substr(0, 24), "seen": Time.get_ticks_msec()}
		elif d is Dictionary and d.get("game") == "wildbound":
			found.erase(ip)
	for ip in found.keys():
		if Time.get_ticks_msec() - found[ip].seen > 4000:
			found.erase(ip)

func _on_joined(id: int) -> void:
	if client_id != 0:
		_peer.disconnect_peer(id)
		return
	client_id = id
	recorder.reset()
	_last_frame = PackedByteArray()
	Game.input.set_remote(true)
	if Audio.current_track() != "":
		_send([M_MUSIC, Audio.current_track()])
	Audio.sfx("confirm")
	toast("Player 2 joined!")

func _on_left(id: int) -> void:
	if id != client_id:
		return
	client_id = 0
	Game.input.set_remote(false)
	if Game.input.coop:
		toast("Player 2 left. They can rejoin with JOIN CO-OP, or play on this keyboard (arrows + Enter).", 6.0)

func _handle(data: Array) -> void:
	match int(data[0]):
		M_INPUT:
			if role == Role.HOST:
				var held := {}
				for i in GameInput.BUTTONS.size():
					if int(data[1]) & (1 << i):
						held[GameInput.BUTTONS[i]] = true
				Game.input.set_remote_buttons(held)
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

func _send(data: Array, reliable := true) -> void:
	if _peer == null:
		return
	_peer.transfer_channel = CH_RELIABLE if reliable else CH_FRAMES
	_peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE if reliable else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
	_peer.put_packet(var_to_bytes(data))

# ---------------------------------------------------------------- host: screen and sound
## Called by main.gd before drawing; returns what Gfx should draw on.
func begin_frame(canvas: CanvasItem) -> Variant:
	_recording = is_hosting_with_player()
	if not _recording:
		return canvas
	recorder.begin(canvas)
	return recorder

## Called by main.gd after drawing: sends the frame to player 2 if it changed.
func end_frame() -> void:
	if not _recording:
		return
	_recording = false
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
## Sends player 2's held buttons to the host whenever they change.
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

## Toasts (player 2 joined or left) on top of the game, on both screens.
func draw_overlay() -> void:
	if _toast == "" or Time.get_ticks_msec() > _toast_until:
		return
	var lines := Gfx.wrap(_toast, 208, 6)
	var h := 8 + lines.size() * 9
	Gfx.panel(8, 4, 224, h, "dark")
	for i in lines.size():
		Gfx.text(lines[i], 16, 8 + i * 9, {"size": 6, "color": "#ffffff", "shadow": null})
