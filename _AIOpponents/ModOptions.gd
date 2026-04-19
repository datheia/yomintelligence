extends "res://SoupModOptions/ModOptions.gd"

func _ready():
	var my_menu = generate_menu("_AIOptions", "AI Opponent Options")
	my_menu.add_label("lbl1", "AI Opponent Options Menu")
	
	var player_dropdown = my_menu.add_dropdown_menu("target_player", "AI Player")
	player_dropdown.add_item("Off")
	player_dropdown.add_item("Player 1")
	player_dropdown.add_item("Player 2")
	player_dropdown.add_item("Both Players (AI vs AI)")
	my_menu.add_label("lbl_ai_vs_ai", "AI vs AI runs Player 1 thinking first, then Player 2.")

	var dropdown = my_menu.add_dropdown_menu("difficulty", "Difficulty")
	dropdown.add_item("Easy")
	dropdown.add_item("Medium")
	dropdown.add_item("Hard")
	dropdown.add_item("Very Hard")
	dropdown.add_item("Expert")
	dropdown.add_item("Insane")
	dropdown.add_item("Extreme")
	dropdown.add_item("Impossible")
	dropdown.add_item("Godlike")
	
	my_menu.add_label("lbl3", "The harder the setting, the longer an AI will take to think, but the more possibilities it will consider. Insane+ modes take VERY long!")
	
	var experimental_button = my_menu.add_bool("experimental_speedup", "Experimental Performance Increase", true)
	my_menu.add_label("lbl4", "By deleting a line of YOMI's code, you can double decision speed! It may cause mod incompatibilities...")

	var talk_button = my_menu.add_bool("trash_talk", "Trash Talk", true)
	var generate_button = my_menu.add_bool("generate_messages", "Generate Messages", true)
	my_menu.add_label("lbl4", "Happy April Fool's Day! If you ask it to 'generate' messages, it sometimes randomly generates its own phrases, some better than others.")

	add_menu(my_menu)
	
export var min_value = 0
export var max_value = 100
