extends "res://SoupModOptions/ModOptions.gd"

func _ready():
	var my_menu = generate_menu("_AIOptions", "AI Opponent Options")
	my_menu.add_label("lbl1", "AI Opponent Options Menu")
	
	var player_dropdown = my_menu.add_dropdown_menu("target_player", "AI Player")
	player_dropdown.add_item("Off")
	player_dropdown.add_item("Player 1")
	player_dropdown.add_item("Player 2")

	my_menu.add_number_spinbox("search_depth", "Depth", 2, {
		min_value = 0,
		max_value = 3,
		step = 1,
		rounded = true,
	})
	my_menu.add_label("lbl_depth", "Exact search depth. Higher values look further ahead but take much longer.")

	my_menu.add_number_slider("read_strength", "Reads", 55, {
		min_value = 0,
		max_value = 100,
		step = 1,
		rounded = true,
	})
	my_menu.add_label("lbl_reads", "0 = safest and hardest to exploit. 100 = most willing to commit to an opponent read.")
	
	my_menu.add_bool("experimental_speedup", "Experimental Performance Increase", true)
	my_menu.add_label("lbl_speedup", "By deleting a line of YOMI's code, you can double decision speed! It may cause mod incompatibilities...")

	my_menu.add_bool("trash_talk", "Trash Talk", true)
	my_menu.add_bool("generate_messages", "Generate Messages", true)
	my_menu.add_label("lbl_messages", "Happy April Fool's Day! If you ask it to 'generate' messages, it sometimes randomly generates its own phrases, some better than others.")

	add_menu(my_menu)
	
export var min_value = 0
export var max_value = 100
