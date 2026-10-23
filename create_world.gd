extends Control

func _ready():
	print("Create world scene loaded")
	
	# Connect back button
	var back_button = $BackButton
	if back_button:
		print("Found BackButton, connecting...")
		back_button.connect("pressed", Callable(self, "_on_back_button_pressed"))
		print("Back button connected successfully")
	
	# Connect create button
	var create_button = $CreateButton
	if create_button:
		print("Found CreateButton, connecting...")
		create_button.connect("pressed", Callable(self, "_on_create_button_pressed"))
		print("Create button connected successfully")
	
	# Get the world slot number from meta
	var world_slot = get_tree().get_meta("world_creation_slot", 1)
	print("Creating world for slot: " + str(world_slot))

func _on_back_button_pressed():
	print("Back button pressed - changing scene")
	get_tree().change_scene_to_file("res://world_selection.tscn")

func _on_create_button_pressed():
	print("Create world button pressed")
	
	# Get input values
	var name_input = $WorldNameContainer/WorldNameInput
	
	var world_name = ""
	
	if name_input:
		world_name = name_input.text
		
	print("Creating world: Name='" + world_name + "'")
	
	# Save world data to local storage (similar to character data)
	if not world_name.is_empty():
		var world_data = {
			"name": world_name,
			"last_played": "Never"
		}
		
		# Save to local storage
		save_world_to_local_storage(world_name, world_data)
	
	# Navigate back to world selection
	get_tree().change_scene_to_file("res://world_selection.tscn")

func save_world_to_local_storage(world_name, world_data):
	# Use the project's save directory for storing world data
	var save_dir = "user://save_data"
	
	# Create the directory if it doesn't exist
	if not DirAccess.dir_exists_absolute(save_dir):
		DirAccess.make_dir_recursive_absolute(save_dir)
	
	# Save the world data to a file named after the world
	var file_path = save_dir + "/world_" + world_name.replace(" ", "_") + ".json"
	
	# Convert to JSON and save
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file != null:
		var json_string = JSON.stringify(world_data)
		file.store_string(json_string)
		file.close()
		print("Saved world data: " + world_name)
	else:
		print("Failed to save world data for: " + world_name)
