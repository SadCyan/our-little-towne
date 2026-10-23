# This script should be attached to the MainGame node in main_game.tscn
# It handles the experience display functionality

extends Node2D

func _ready() -> void:
	# Call parent ready function
	super._ready()
	
	# Add the experience display functionality
	if $HUD/Margin/Rows/ExperienceContainer == null:
		# Create the experience container if it doesn't exist
		var experience_container := VBoxContainer.new()
		experience_container.name = "ExperienceContainer"
		
		var experience_label := Label.new()
		experience_label.name = "ExperienceLabel"
		experience_label.text = "Experience Points:"
		experience_label.theme_override_font_sizes.font_size = 16
		
		var player_experience_list := VBoxContainer.new()
		player_experience_list.name = "PlayerExperienceList"
		
		experience_container.add_child(experience_label)
		experience_container.add_child(player_experience_list)
		
		$HUD/Margin/Rows.add_child(experience_container)

func _update_experience_display() -> void:
	# This function is called from main_game.gd to update experience display
	if $HUD/Margin/Rows/ExperienceContainer == null:
		return
		
	var player_experience_container := $HUD/Margin/Rows/ExperienceContainer/PlayerExperienceList
	
	# Clear existing experience labels
	for child in player_experience_container.get_children():
		child.queue_free()
	
	# Create new experience labels for each player
	for player_id in NetworkManager.players:
		var player_name := NetworkManager.players[player_id].name
		var experience := NetworkManager.player_experience.get(player_id, 0)
		var is_local := player_id == NetworkManager.my_player_id
		
		var label := Label.new()
		label.text = "%s: %d XP" % [player_name, experience]
		if is_local:
			label.theme_override_colors.font_color = Color("ffffff")
		else:
			label.theme_override_colors.font_color = Color("cccccc")
		label.horizontal_alignment = 0
		player_experience_container.add_child(label)