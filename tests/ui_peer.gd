extends "res://tests/network_peer.gd"
## Exercise the real join form, scene transition, avatars, and disconnect UI.

var _checked_field := false


func _start() -> void:
	# Keep the driver on the root while the actual application changes scenes.
	get_tree().current_scene = null
	get_tree().change_scene_to_file.call_deferred("res://main_menu.tscn")
	await get_tree().process_frame
	await get_tree().process_frame
	var menu := get_tree().current_scene
	if menu == null:
		_error = "UI failure: menu did not load."
		return
	menu.get_node("%Address").text = "127.0.0.1"
	menu.get_node("%PlayerName").text = _name
	menu.get_node("%Port").value = _port
	menu.get_node("%JoinButton").pressed.emit()


func _process(delta: float) -> void:
	super._process(delta)
	var scene := get_tree().current_scene
	if scene == null:
		return
	if scene.name == "MainGame" and NetworkManager.is_active:
		_checked_field = true
		var avatars := scene.get_node("Players")
		if avatars.get_child_count() != NetworkManager.players.size():
			_error = "UI failure: missing avatars."
		var local_avatar := avatars.get_node_or_null("Player_%d" % NetworkManager.my_player_id)
		if local_avatar == null or not local_avatar.get_node("NameLabel").text.ends_with("(you)"):
			_error = "UI failure: local player is not identified."
	elif _checked_field and not NetworkManager.is_active and scene.name == "MainMenu":
		if scene.get_node("%JoinButton").disabled:
			_error = "UI failure: reconnect button is disabled."
