extends Node
## An actual ENet peer controlled by the integration runner through local files.

var _role := "client"
var _name := "Tester"
var _port := 17000
var _report_path := ""
var _command_path := ""
var _last_command := -1
var _direction := Vector2.ZERO
var _send_movement := false
var _elapsed := 0.0
var _pulses: Array[Dictionary] = []
var _error := ""


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		var parts := argument.split("=", true, 1)
		if parts.size() != 2:
			continue
		match parts[0]:
			"--role": _role = parts[1]
			"--name": _name = parts[1]
			"--port": _port = int(parts[1])
			"--report": _report_path = parts[1]
			"--commands": _command_path = parts[1]
	NetworkManager.pulse_received.connect(_on_pulse)
	NetworkManager.session_ended.connect(func(reason: String) -> void: _error = reason)
	_start()


func _start() -> void:
	if _role == "server":
		var error := NetworkManager.start_server(_port)
		if error != OK:
			_error = NetworkManager.status_message
	else:
		NetworkManager.connect_to_server("127.0.0.1", _port, _name)


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < 1.0 / 30.0:
		return
	_elapsed = 0.0
	_read_command()
	if _send_movement:
		NetworkManager.send_input(_direction)
	_write_report()


func _read_command() -> void:
	if not FileAccess.file_exists(_command_path):
		return
	var file := FileAccess.open(_command_path, FileAccess.READ)
	if file == null:
		return
	var command: Variant = JSON.parse_string(file.get_as_text())
	if not command is Dictionary or int(command.get("sequence", -1)) <= _last_command:
		return
	_last_command = int(command.sequence)
	match command.action:
		"move":
			_direction = Vector2(command.direction[0], command.direction[1])
			_send_movement = true
		"silence":
			_send_movement = false
		"invalid_input":
			_send_movement = false
			NetworkManager.send_input(Vector2(NAN, INF))
		"pulse":
			NetworkManager.request_pulse()
		"pulse_twice":
			NetworkManager.request_pulse()
			NetworkManager.request_pulse()
		"disconnect":
			_send_movement = false
			NetworkManager.cleanup()
		"reconnect":
			_send_movement = false
			_error = ""
			NetworkManager.connect_to_server("127.0.0.1", _port, _name)
		"view_pulse":
			var scene := get_tree().current_scene
			if scene != null and scene.name == "MainGame":
				if scene._pulses.is_empty():
					_error = "No pulse animation in field view."
			else:
				_error = "Field scene did not load."
		"quit":
			NetworkManager.cleanup()
			get_tree().quit()


func _on_pulse(player_id: int, origin: Vector2, _tint: Color) -> void:
	_pulses.append({"player_id": player_id, "origin": [origin.x, origin.y]})


func _write_report() -> void:
	var state := {}
	for player_id in NetworkManager.players:
		var player: Dictionary = NetworkManager.players[player_id]
		var position: Vector2 = player.position
		state[str(player_id)] = {"name": player.name, "position": [position.x, position.y]}
	var file := FileAccess.open(_report_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({
			"active": NetworkManager.is_active, "connecting": NetworkManager.is_connecting,
			"id": NetworkManager.my_player_id, "players": state, "pulses": _pulses,
			"error": _error, "command": _last_command,
		}))
