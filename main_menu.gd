extends Control

var _opening_game := false

@onready var address_input: LineEdit = %Address
@onready var port_input: SpinBox = %Port
@onready var name_input: LineEdit = %PlayerName
@onready var host_button: Button = %HostButton
@onready var join_button: Button = %JoinButton
@onready var cancel_button: Button = %CancelButton
@onready var status_label: Label = %Status


func _ready() -> void:
	NetworkManager.session_started.connect(_on_session_started)
	NetworkManager.session_ended.connect(_on_session_ended)
	host_button.pressed.connect(_host)
	join_button.pressed.connect(_join)
	cancel_button.pressed.connect(_cancel)
	address_input.text_submitted.connect(func(_text: String) -> void: _join())
	name_input.text_submitted.connect(func(_text: String) -> void: _join())
	address_input.text = NetworkManager.server_address
	port_input.value = NetworkManager.server_port
	name_input.text = NetworkManager.display_name
	status_label.text = NetworkManager.status_message
	var addresses: PackedStringArray = []
	for address in IP.get_local_addresses():
		if address.is_valid_ip_address() and not address.contains(":") and not address.begins_with("127."):
			addresses.append(address)
	%LocalAddresses.text = "This computer's network addresses: %s" % (", ".join(addresses) if not addresses.is_empty() else "none detected")
	# Consume command-line options once so disconnecting returns to the menu.
	if not get_tree().has_meta("launch_options_consumed"):
		get_tree().set_meta("launch_options_consumed", true)
		_apply_launch_options()


func _apply_launch_options() -> void:
	var start_as_server := OS.has_feature("dedicated_server")
	var connect_address := ""
	for argument in OS.get_cmdline_user_args():
		if argument == "--server":
			start_as_server = true
		elif argument.begins_with("--connect="):
			connect_address = argument.trim_prefix("--connect=")
		elif argument.begins_with("--port="):
			var port_text := argument.trim_prefix("--port=")
			if not port_text.is_valid_int() or int(port_text) < 1 or int(port_text) > 65535:
				_launch_error("Port must be an integer between 1 and 65535.")
				return
			port_input.value = int(port_text)
		elif argument.begins_with("--name="):
			name_input.text = argument.trim_prefix("--name=")
	if start_as_server and not connect_address.is_empty():
		_launch_error("Choose --server or --connect, not both.")
	elif start_as_server:
		_host()
	elif not connect_address.is_empty():
		address_input.text = connect_address
		_join()


func _launch_error(message: String) -> void:
	status_label.text = message
	if DisplayServer.get_name() == "headless":
		printerr(message)
		get_tree().quit(2)


func _host() -> void:
	if NetworkManager.is_connecting or _opening_game:
		return
	var error := NetworkManager.start_server(int(port_input.value))
	status_label.text = NetworkManager.status_message
	if error != OK and DisplayServer.get_name() == "headless":
		printerr(NetworkManager.status_message)
		get_tree().quit(1)


func _join() -> void:
	if NetworkManager.is_connecting or _opening_game:
		return
	var error := NetworkManager.connect_to_server(address_input.text, int(port_input.value), name_input.text)
	status_label.text = NetworkManager.status_message
	_set_connecting(error == OK)


func _cancel() -> void:
	NetworkManager.cleanup()
	NetworkManager.status_message = "Connection cancelled."
	status_label.text = NetworkManager.status_message
	_set_connecting(false)


func _set_connecting(connecting: bool) -> void:
	host_button.disabled = connecting
	join_button.disabled = connecting
	address_input.editable = not connecting
	name_input.editable = not connecting
	port_input.editable = not connecting
	cancel_button.visible = connecting


func _on_session_started() -> void:
	if NetworkManager.is_server and DisplayServer.get_name() == "headless":
		_set_connecting(true)
		cancel_button.visible = false
		return
	_opening_game = true
	get_tree().change_scene_to_file.call_deferred("res://main_game.tscn")


func _on_session_ended(reason: String) -> void:
	_opening_game = false
	_set_connecting(false)
	status_label.text = reason
