extends Node2D

const PLAYER_SCENE := preload("res://player.tscn")
const PULSE_DURATION := 0.65
const INPUT_INTERVAL := 1.0 / 30.0

var _avatars: Dictionary = {}
var _pulses: Array[Dictionary] = []
var _input_elapsed := 0.0
var _previous_input := Vector2.ZERO
var _leaving := false

@onready var status_label: Label = $HUD/Margin/Rows/Header/Status
@onready var leave_button: Button = $HUD/Margin/Rows/Header/LeaveButton


func _ready() -> void:
	if not NetworkManager.is_active:
		get_tree().change_scene_to_file.call_deferred("res://main_menu.tscn")
		return
	NetworkManager.world_updated.connect(_refresh_world)
	NetworkManager.pulse_received.connect(_on_pulse)
	NetworkManager.session_ended.connect(_on_session_ended)
	leave_button.pressed.connect(_leave)
	leave_button.focus_mode = Control.FOCUS_NONE
	leave_button.text = "Stop server" if NetworkManager.is_server else "Disconnect"
	_refresh_world()
	queue_redraw()


func _physics_process(delta: float) -> void:
	if not NetworkManager.is_active or NetworkManager.is_server or _leaving:
		return
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	# Losing focus must not leave someone walking indefinitely.
	if not get_window().has_focus():
		direction = Vector2.ZERO
	_input_elapsed += delta
	if direction != _previous_input or _input_elapsed >= INPUT_INTERVAL:
		NetworkManager.send_input(direction)
		_previous_input = direction
		_input_elapsed = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pulse") and not event.is_echo() and get_window().has_focus():
		NetworkManager.request_pulse()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		_leave()


func _process(delta: float) -> void:
	for pulse in _pulses:
		pulse.age += delta
	_pulses = _pulses.filter(func(pulse: Dictionary) -> bool: return pulse.age < PULSE_DURATION)
	queue_redraw()


func _refresh_world() -> void:
	for player_id in _avatars.keys():
		if not NetworkManager.players.has(player_id):
			_avatars[player_id].queue_free()
			_avatars.erase(player_id)
	for player_id in NetworkManager.players:
		var state: Dictionary = NetworkManager.players[player_id]
		if not _avatars.has(player_id):
			var avatar := PLAYER_SCENE.instantiate()
			avatar.name = "Player_%d" % player_id
			avatar.configure(state, player_id == NetworkManager.my_player_id)
			$Players.add_child(avatar)
			_avatars[player_id] = avatar
		_avatars[player_id].update_state(state)
	var count := NetworkManager.players.size()
	if NetworkManager.is_server:
		status_label.text = "SERVER | UDP %d | %d/%d players" % [NetworkManager.server_port, count, NetworkManager.MAX_PLAYERS]
	else:
		status_label.text = "%s | %s:%d | %d players" % [NetworkManager.display_name, NetworkManager.server_address, NetworkManager.server_port, count]
	$HUD/Margin/Rows/Help.text = (
		"Server running. Open another instance and join to play. Esc: stop server."
		if NetworkManager.is_server else "WASD: move   |   Space: pulse   |   Esc: disconnect"
	)


func _on_pulse(_player_id: int, origin: Vector2, tint: Color) -> void:
	_pulses.append({"origin": origin, "tint": tint, "age": 0.0})


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color("132d26"))
	draw_rect(NetworkManager.FIELD, Color("3d7755"))
	for x in range(64, 1217, 48):
		draw_line(Vector2(x, 120), Vector2(x, 640), Color(1, 1, 1, 0.035))
	for y in range(120, 641, 48):
		draw_line(Vector2(64, y), Vector2(1216, y), Color(1, 1, 1, 0.035))
	draw_rect(NetworkManager.FIELD, Color("87b897"), false, 3)
	for pulse in _pulses:
		var progress: float = pulse.age / PULSE_DURATION
		var tint: Color = pulse.tint
		tint.a = 1.0 - progress
		draw_arc(pulse.origin, lerpf(20, 120, progress), 0, TAU, 64, tint, 4, true)


func _leave() -> void:
	if _leaving:
		return
	_leaving = true
	var was_server := NetworkManager.is_server
	NetworkManager.cleanup()
	NetworkManager.status_message = "Server stopped." if was_server else "Disconnected."
	get_tree().change_scene_to_file.call_deferred("res://main_menu.tscn")


func _on_session_ended(_reason: String) -> void:
	_leaving = true
	get_tree().change_scene_to_file.call_deferred("res://main_menu.tscn")
