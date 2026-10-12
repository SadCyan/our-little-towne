extends Node
## The server simulates the field. Clients send input and render its snapshots.
## RPCs live on this autoload so joining never depends on scene load timing.

signal session_started
signal session_ended(reason: String)
signal world_updated
signal pulse_received(player_id: int, origin: Vector2, tint: Color)

const DEFAULT_PORT := 7000
const MAX_PLAYERS := 8
const PROTOCOL_VERSION := 1
const FIELD := Rect2(64, 120, 1152, 520)
const PLAYER_RADIUS := 16.0
const MOVE_SPEED := 240.0
const SNAPSHOT_INTERVAL := 1.0 / 20.0
const INPUT_TIMEOUT := 0.5
const CONNECTION_TIMEOUT := 8.0
const SERVER_TIMEOUT := 3.0
const PULSE_COOLDOWN := 0.75
const PLAYER_COLORS := [
	Color("ffd166"), Color("7bdff2"), Color("cdb4db"), Color("ff9b85"),
	Color("b8f2b0"), Color("f7aef8"), Color("a0c4ff"), Color("fdffb6"),
]

var is_server := false
var is_connecting := false
var is_active := false
var my_player_id := 0
var server_port := DEFAULT_PORT
var server_address := "127.0.0.1"
var display_name := "Player"
var status_message := "Start a server or join one on your local network."
var players: Dictionary = {}

var _peer: ENetMultiplayerPeer
var _inputs: Dictionary = {}
var _input_times: Dictionary = {}
var _pulse_times: Dictionary = {}
var _spawn_slots: Dictionary = {}
var _snapshot_elapsed := 0.0
var _snapshot_sequence := 0
var _last_snapshot_sequence := -1
var _session_generation := 0
var _last_snapshot_time := 0


func _ready() -> void:
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	# Clients cannot relay RPCs to other clients.
	(multiplayer as SceneMultiplayer).server_relay = false


func start_server(port: int = DEFAULT_PORT) -> Error:
	cleanup()
	if port < 1 or port > 65535:
		status_message = "Port must be between 1 and 65535."
		return ERR_INVALID_PARAMETER
	var candidate := ENetMultiplayerPeer.new()
	var error := candidate.create_server(port, MAX_PLAYERS, 3)
	if error != OK:
		candidate.close()
		status_message = "Cannot listen on UDP port %d: %s" % [port, error_string(error)]
		return error
	_peer = candidate
	multiplayer.multiplayer_peer = _peer
	server_port = port
	is_server = true
	is_active = true
	status_message = "Server listening on UDP port %d." % port
	print(status_message)
	session_started.emit()
	return OK


func connect_to_server(address: String, port: int = DEFAULT_PORT, player_name: String = "Player") -> Error:
	cleanup()
	address = address.strip_edges()
	if address.is_empty() or port < 1 or port > 65535:
		status_message = "Enter a server address and a port between 1 and 65535."
		return ERR_INVALID_PARAMETER
	var candidate := ENetMultiplayerPeer.new()
	var error := candidate.create_client(address, port, 3)
	if error != OK:
		candidate.close()
		status_message = "Cannot connect: %s" % error_string(error)
		return error
	_peer = candidate
	multiplayer.multiplayer_peer = _peer
	server_address = address
	server_port = port
	display_name = _clean_name(player_name)
	is_connecting = true
	status_message = "Connecting to %s:%d..." % [address, port]
	_wait_for_connection(_session_generation)
	return OK


func _wait_for_connection(generation: int) -> void:
	await get_tree().create_timer(CONNECTION_TIMEOUT).timeout
	if generation == _session_generation and is_connecting:
		_end_session("Connection timed out. Check the address, UDP port, firewall, and server capacity.")


func _on_connected_to_server() -> void:
	if not is_connecting:
		return
	my_player_id = multiplayer.get_unique_id()
	_join_game.rpc_id(1, PROTOCOL_VERSION, display_name)


@rpc("any_peer", "call_remote", "reliable", 0)
func _join_game(version: int, player_name: String) -> void:
	if not is_server:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 1 or not multiplayer.get_peers().has(sender) or players.has(sender):
		return
	if version != PROTOCOL_VERSION or players.size() >= MAX_PLAYERS:
		_peer.disconnect_peer(sender)
		return
	var slot := 0
	while _spawn_slots.values().has(slot):
		slot += 1
	_spawn_slots[sender] = slot
	players[sender] = {
		"name": _clean_name(player_name),
		"position": FIELD.get_center() + Vector2((slot % 4 - 1.5) * 96.0, (floori(slot / 4.0) - 0.5) * 96.0),
		"color": PLAYER_COLORS[slot],
	}
	_inputs[sender] = Vector2.ZERO
	_input_times[sender] = Time.get_ticks_msec()
	_pulse_times[sender] = -10000
	print("Player joined: %s (%d)" % [players[sender].name, sender])
	_publish_world(true)


func send_input(direction: Vector2) -> void:
	if is_active and not is_server:
		_submit_input.rpc_id(1, direction)


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _submit_input(direction: Vector2) -> void:
	if not is_server or not direction.is_finite():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not players.has(sender):
		return
	# Input is tied to its sender; clients never set positions or player IDs.
	_inputs[sender] = direction.limit_length(1.0)
	_input_times[sender] = Time.get_ticks_msec()


func request_pulse() -> void:
	if is_active and not is_server:
		_submit_pulse.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable", 0)
func _submit_pulse() -> void:
	if not is_server:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not players.has(sender):
		return
	var now := Time.get_ticks_msec()
	if now - int(_pulse_times[sender]) < PULSE_COOLDOWN * 1000.0:
		return
	_pulse_times[sender] = now
	var origin: Vector2 = players[sender].position
	var tint: Color = players[sender].color
	pulse_received.emit(sender, origin, tint)
	for player_id in players:
		_receive_pulse.rpc_id(player_id, sender, origin, tint)


@rpc("authority", "call_remote", "reliable", 0)
func _receive_pulse(player_id: int, origin: Vector2, tint: Color) -> void:
	if is_active and not is_server:
		pulse_received.emit(player_id, origin, tint)


func _physics_process(delta: float) -> void:
	if not is_active:
		return
	var now := Time.get_ticks_msec()
	if not is_server:
		if now - _last_snapshot_time > SERVER_TIMEOUT * 1000.0:
			_end_session("The server stopped responding. Check the network and reconnect.")
		return
	for player_id in players:
		var direction: Vector2 = _inputs[player_id]
		if now - int(_input_times[player_id]) > INPUT_TIMEOUT * 1000.0:
			direction = Vector2.ZERO
		var next_position: Vector2 = players[player_id].position + direction * MOVE_SPEED * delta
		next_position.x = clampf(next_position.x, FIELD.position.x + PLAYER_RADIUS, FIELD.end.x - PLAYER_RADIUS)
		next_position.y = clampf(next_position.y, FIELD.position.y + PLAYER_RADIUS, FIELD.end.y - PLAYER_RADIUS)
		players[player_id].position = next_position
	_snapshot_elapsed += delta
	if _snapshot_elapsed >= SNAPSHOT_INTERVAL:
		_snapshot_elapsed = fmod(_snapshot_elapsed, SNAPSHOT_INTERVAL)
		_publish_world(false)


func _publish_world(reliable: bool) -> void:
	_snapshot_sequence += 1
	for player_id in players:
		if reliable:
			_receive_roster.rpc_id(player_id, players, _snapshot_sequence)
		else:
			_receive_snapshot.rpc_id(player_id, players, _snapshot_sequence)
	world_updated.emit()


@rpc("authority", "call_remote", "reliable", 0)
func _receive_roster(snapshot: Dictionary, sequence: int) -> void:
	_accept_snapshot(snapshot, sequence)


@rpc("authority", "call_remote", "unreliable_ordered", 2)
func _receive_snapshot(snapshot: Dictionary, sequence: int) -> void:
	_accept_snapshot(snapshot, sequence)


func _accept_snapshot(snapshot: Dictionary, sequence: int) -> void:
	if is_server or sequence <= _last_snapshot_sequence or not snapshot.has(my_player_id):
		return
	# Roster and movement updates travel on separate channels. Ignore old packets
	# so they cannot resurrect departed players or rewind newer positions.
	_last_snapshot_sequence = sequence
	_last_snapshot_time = Time.get_ticks_msec()
	players = snapshot
	if is_connecting:
		is_connecting = false
		is_active = true
		status_message = "Connected to %s:%d." % [server_address, server_port]
		session_started.emit()
	world_updated.emit()


func _on_peer_disconnected(player_id: int) -> void:
	if not is_server or not players.has(player_id):
		return
	players.erase(player_id)
	_inputs.erase(player_id)
	_input_times.erase(player_id)
	_pulse_times.erase(player_id)
	_spawn_slots.erase(player_id)
	print("Player left: %d" % player_id)
	_publish_world(true)


func _on_connection_failed() -> void:
	if is_connecting:
		_end_session("Could not connect. Check the server address, UDP port, and available player slots.")


func _on_server_disconnected() -> void:
	if is_active or is_connecting:
		_end_session("The server disconnected. You can reconnect when it is available.")


func _end_session(reason: String) -> void:
	cleanup()
	status_message = reason
	session_ended.emit(reason)


func cleanup() -> void:
	_session_generation += 1
	is_server = false
	is_active = false
	is_connecting = false
	my_player_id = 0
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if _peer != null:
		_peer.close()
		_peer = null
	players.clear()
	_inputs.clear()
	_input_times.clear()
	_pulse_times.clear()
	_spawn_slots.clear()
	_snapshot_elapsed = 0.0
	_snapshot_sequence = 0
	_last_snapshot_sequence = -1
	_last_snapshot_time = 0


func _clean_name(player_name: String) -> String:
	var result := ""
	for character in player_name.strip_edges():
		if character.unicode_at(0) >= 32 and character.unicode_at(0) != 127:
			result += character
		if result.length() == 24:
			break
	return "Player" if result.is_empty() else result
