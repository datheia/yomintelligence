extends "res://game.gd"



func _ready():
	if not is_ghost:
		add_child(preload("res://_AIOpponents/AIController.tscn").instance())
	._ready()
#

# Code for faster deep copy

var fast_copy_scene_cache = {}
var native_fast_copy_checked = false
var native_fast_copy = null
var native_fast_copy_warned = false
var native_fighter_runtime_warned = false
var native_state_history_warned = false
var ai_skip_show_state = false


func get_native_fast_copy():
	if native_fast_copy_checked:
		return native_fast_copy
	native_fast_copy_checked = true

	var library_path = OS.get_executable_path().get_base_dir().plus_file("libai_fast_copy.so")
	if OS.get_name() == "Windows":
		library_path = OS.get_executable_path().get_base_dir().plus_file("ai_fast_copy.dll")

	var file = File.new()
	if not file.file_exists(library_path):
		return null

	var script = load("res://_AIOpponents/native/AIFastCopy.gdns")
	if script == null:
		return null
	native_fast_copy = script.new()
	return native_fast_copy


func get_fast_copy_scene(filename:String):
	if not fast_copy_scene_cache.has(filename):
		fast_copy_scene_cache[filename] = load(filename)
	return fast_copy_scene_cache[filename]

func fast_copy_to(game:Game):
	if not game_started:
		return
	clean_objects()
	clear_fast_copy_transients(game)
	reset_fast_copy_registry(game)
	fighter_fast_copy(p1, game.p1)
	fighter_fast_copy(p2, game.p2)
	game.p1.hp = p1.hp
	game.p2.hp = p2.hp
	for object in objects:
		if is_instance_valid(object):
			if not object.disabled:
				copy_fast_prediction_object(object, game)
			else :
				game.objs_map[str(game.objs_map.size() + 1)] = null
	game.camera.limit_left = camera.limit_left
	game.camera.limit_right = camera.limit_right


func clear_fast_copy_transients(game:Game):
	if game.objects.size() > 0:
		var object_index = game.objects.size() - 1
		while object_index >= 0:
			var object = game.objects[object_index]
			if is_instance_valid(object):
				object.free()
			object_index -= 1
		game.objects.clear()
	if game.effects.size() > 0:
		var effect_index = game.effects.size() - 1
		while effect_index >= 0:
			var fx = game.effects[effect_index]
			if is_instance_valid(fx):
				fx.free()
			effect_index -= 1
		game.effects.clear()


func reset_fast_copy_registry(game:Game):
	game.objs_map = {
		"P1": game.p1,
		"P2": game.p2,
	}
	game.p1.objs_map = game.objs_map
	game.p2.objs_map = game.objs_map


func simulate_one_tick():
	tick()
	if !ai_skip_show_state:
		show_state()


func copy_fast_prediction_object(object, game:Game):
	var new_obj = get_fast_copy_scene(object.filename).instance()
	new_obj.obj_name = object.obj_name
	new_obj.name = object.obj_name
	new_obj.id = object.id
	new_obj.objs_map = game.objs_map
	game.objects.append(new_obj)
	game.objects_node.add_child(new_obj)
	new_obj.has_ceiling = game.has_ceiling
	new_obj.ceiling_height = game.ceiling_height
	new_obj.logic_rng = BetterRng.new()
	new_obj.logic_rng_static = BetterRng.new()
	var seed_ = hash(game.match_data.seed + int(object.obj_name))
	new_obj.logic_rng.seed = seed_
	new_obj.logic_rng_seed = seed_
	new_obj.logic_rng_static.seed = game.match_data.seed
	new_obj.logic_rng_static_seed = game.match_data.seed
	game.objs_map[object.obj_name] = new_obj
	new_obj.connect("tree_exited", game, "_on_obj_exit_tree", [new_obj])
	new_obj.connect("hitbox_refreshed", game, "on_hitbox_refreshed")
	new_obj.connect("global_hitlag", game, "on_global_hitlag")
	new_obj.gravity_enabled = game.gravity_enabled
	new_obj.set_gravity_modifier(game.global_gravity_modifier)
	new_obj.fighter_owner = game.get_player(object.id)
	for particle in new_obj.particles.get_children():
		game.effects.append(particle)
	game.connect_signals(new_obj)
	object.copy_to(new_obj)
	sync_fast_copy_state_history(object, new_obj)
	game.objs_map[object.obj_name] = new_obj
	new_obj.objs_map = game.objs_map


# Deep copy one fighter's values into a target Fighter object.
func fighter_fast_copy(copy_from:Fighter, copy_target:Fighter):
	reset_fast_copy_state_machine(copy_target)
	copy_fast_fighter_state(copy_from, copy_target)
	sync_fast_copy_state_history(copy_from, copy_target)


func copy_fast_fighter_state(copy_from:Fighter, copy_target:Fighter):
	if not copy_from.initialized:
		copy_from.init()
	var current_state = copy_from.current_state()
	copy_target.state_machine.starting_state = current_state.name
	copy_target.spawn_data = current_state.copy_data()
	copy_target.set_pos(copy_from.get_pos().x, copy_from.get_pos().y)
	if copy_from.creator_name and copy_target.objs_map.has(copy_from.creator_name):
		copy_target.creator = copy_target.objs_map[copy_from.creator_name]
	copy_target.init()
	copy_target.update_data()
	copy_fast_state_variables(copy_from, copy_target)
	copy_target.change_state(current_state.state_name, current_state.data)
	copy_relevant_state_nodes(copy_from, copy_target)
	copy_target.current_state().current_tick = current_state.current_tick
	copy_target.stage_width = copy_from.stage_width
	copy_target.chara.update_grounded()
	copy_target.update_data()
	copy_target.set_facing(copy_from.get_facing_int())
	copy_active_hitboxes(copy_from, copy_target)
	copy_from.hurtbox.copy_to(copy_target.hurtbox)
	copy_target.projectile_invulnerable = copy_from.projectile_invulnerable
	copy_target.invulnerable = copy_from.invulnerable
	copy_from.chara.copy_to(copy_target.chara)
	copy_target.set_facing(copy_from.get_facing_int())
	copy_logic_rng(copy_from, copy_target)
	if not copy_native_fighter_runtime(copy_from, copy_target, current_state):
		copy_base_fighter_fields(copy_from, copy_target, current_state)
		copy_character_specific_fighter_fields(copy_from, copy_target)
	copy_target.update_data()


func copy_fast_state_variables(copy_from:Fighter, copy_target:Fighter):
	var native = get_native_fast_copy()
	if native != null:
		var copied = native.copy_properties(copy_from, copy_target, copy_from.state_variables)
		if copied == copy_from.state_variables.size():
			return
		if not native_fast_copy_warned:
			native_fast_copy_warned = true
			print("[FAST_COPY_NATIVE] incomplete copy; falling back to GDScript")
	for variable in copy_from.state_variables:
		var value = copy_from.get(variable)
		if value is Array or value is Dictionary:
			copy_target.set(variable, value.duplicate(true))
		else:
			copy_target.set(variable, value)


func copy_native_fighter_runtime(copy_from:Fighter, copy_target:Fighter, current_state) -> bool:
	var native = get_native_fast_copy()
	if native == null or !native.has_method("copy_fighter_runtime"):
		return false
	var script = copy_from.get_script()
	var script_path = script.resource_path if script != null else ""
	var copied = native.copy_fighter_runtime(copy_from, copy_target, current_state, script_path)
	if copied:
		return true
	if not native_fighter_runtime_warned:
		native_fighter_runtime_warned = true
		print("[FAST_COPY_NATIVE] fighter runtime copy failed; falling back to GDScript")
	return false


func copy_relevant_state_nodes(copy_from, copy_target):
	var state_names = {}
	if copy_from.current_state() != null:
		state_names[copy_from.current_state().name] = true
	for state in copy_from.state_machine.states_stack:
		var state_name = state.name if state is Node else str(state)
		state_names[state_name] = true
	for state in copy_from.state_machine.queued_states:
		var queued_state_name = state.name if state is Node else str(state)
		state_names[queued_state_name] = true
	for state_name in state_names.keys():
		if copy_from.state_machine.states_map.has(state_name) and copy_target.state_machine.states_map.has(state_name):
			copy_from.state_machine.states_map[state_name].copy_to(copy_target.state_machine.states_map[state_name])
			copy_from.state_machine.states_map[state_name].copy_hurtbox_states(copy_target.state_machine.states_map[state_name])


func copy_active_hitboxes(copy_from, copy_target):
	var pos = copy_from.get_pos()
	for i in range(copy_target.hitboxes.size()):
		copy_target.hitboxes[i].deactivate()
	for i in range(copy_from.hitboxes.size()):
		copy_target.hitboxes[i].hit_objects = copy_from.hitboxes[i].hit_objects.duplicate()
		if copy_from.hitboxes[i].active:
			copy_target.hitboxes[i].activate()
			copy_target.hitboxes[i].tick = copy_from.hitboxes[i].tick
			copy_target.hitboxes[i].enabled = copy_from.hitboxes[i].enabled
			copy_from.hitboxes[i].copy_to(copy_target.hitboxes[i])
			copy_target.hitboxes[i].update_position(pos.x, pos.y)


func copy_logic_rng(copy_from, copy_target):
	if copy_target.logic_rng == null:
		copy_target.logic_rng = BetterRng.new()
	if copy_target.logic_rng_static == null:
		copy_target.logic_rng_static = BetterRng.new()
	copy_target.logic_rng.seed = copy_from.logic_rng_seed
	copy_target.logic_rng_static.seed = copy_from.logic_rng_static_seed
	copy_target.logic_rng.state = copy_from.logic_rng.state
	copy_target.logic_rng_static.state = copy_from.logic_rng_static.state


func copy_base_fighter_fields(copy_from:Fighter, copy_target:Fighter, current_state):
	copy_target.got_parried = copy_from.got_parried
	copy_target.colliding_with_opponent = copy_from.colliding_with_opponent
	copy_target.has_hyper_armor = copy_from.has_hyper_armor
	copy_target.has_projectile_armor = copy_from.has_projectile_armor
	copy_target.blockstun_ticks = copy_from.blockstun_ticks
	copy_target.blocked_hitbox_plus_frames = copy_from.blocked_hitbox_plus_frames
	copy_target.stance = copy_from.stance
	copy_target.current_state().interrupt_frames = current_state.interrupt_frames.duplicate(true)
	copy_target.set_facing(copy_from.get_facing_int(), true)


func copy_character_specific_fighter_fields(copy_from:Fighter, copy_target:Fighter):
	var script = copy_from.get_script()
	if script == null:
		return
	match script.resource_path:
		"res://characters/wizard/Wizard.gd":
			copy_target.boulder_projectile = copy_from.boulder_projectile
		"res://characters/swordandgun/SwordGuy.gd":
			copy_target.bullet_cancelling = copy_from.bullet_cancelling
		"res://characters/robo/Robot.gd":
			copy_target.armor_active = copy_from.armor_active
			copy_target.magnet_ticks_left = copy_from.magnet_ticks_left
			copy_target.flying_dir = copy_from.flying_dir.duplicate(true) if copy_from.flying_dir != null else null
			copy_target.flame_touching_opponent = copy_from.flame_touching_opponent
			copy_target.magnet_polygon.polygon = copy_from.magnet_polygon.polygon
			copy_target.magnet_polygon2.polygon = copy_from.magnet_polygon2.polygon
			copy_target.drive_cancel = copy_from.drive_cancel
			copy_target.buffer_drive_cancel = copy_from.buffer_drive_cancel
		"res://characters/mutant/Beast.gd":
			copy_target.juke_ticks = copy_from.juke_ticks
			copy_target.up_juke_ticks = copy_from.up_juke_ticks


func reset_fast_copy_state_machine(object):
	if object != null and object.state_machine != null:
		object.state_machine.states_stack.clear()
		object.state_machine.queued_states.clear()
		object.state_machine.queued_data.clear()


func sync_fast_copy_state_history(copy_from, copy_target):
	if copy_from == null or copy_target == null:
		return
	if copy_from.state_machine == null or copy_target.state_machine == null:
		return
	var native = get_native_fast_copy()
	if native != null and native.has_method("copy_state_history"):
		if native.copy_state_history(copy_from, copy_target):
			return
		if not native_state_history_warned:
			native_state_history_warned = true
			print("[FAST_COPY_NATIVE] state history copy failed; falling back to GDScript")
	copy_target.state_machine.states_stack.clear()
	for state in copy_from.state_machine.states_stack:
		var state_name = state.name if state is Node else str(state)
		if copy_target.state_machine.states_map.has(state_name):
			copy_target.state_machine.states_stack.append(copy_target.state_machine.states_map[state_name])
	if copy_target.state_machine.states_stack.empty() and copy_target.current_state() != null:
		copy_target.state_machine.states_stack.append(copy_target.current_state())
	copy_target.state_machine.queued_states.clear()
	copy_target.state_machine.queued_data.clear()
	for state in copy_from.state_machine.queued_states:
		var queued_state_name = state.name if state is Node else str(state)
		copy_target.state_machine.queued_states.append(queued_state_name)
	for datum in copy_from.state_machine.queued_data:
		copy_target.state_machine.queued_data.append(datum)



func fast_start_game(singleplayer:bool, match_data:Dictionary):
	self.match_data = match_data
	
	if match_data.has("spectating"):
		spectating = match_data.spectating
		if is_ghost:
			spectating = false
			
	# Problem: The game is freed each time and these with it, even if they're stored in the controller
	# The time is spent in .instance()
	if Global.name_paths.has(match_data.selected_characters[1]["name"]):
		p1 = load(Global.name_paths[match_data.selected_characters[1]["name"]]).instance()
	else :
		return false
	if Global.name_paths.has(match_data.selected_characters[2]["name"]):
		p2 = load(Global.name_paths[match_data.selected_characters[2]["name"]]).instance()
	else :
		return false
	
	
	
	p1.connect("parried", self, "on_parry")
	p2.connect("parried", self, "on_parry")
	p1.connect("clashed", self, "on_clash")
	p2.connect("clashed", self, "on_clash")


	p1.connect("predicted", self, "on_prediction", [p1])
	p2.connect("predicted", self, "on_prediction", [p2])
	stage_width = Utils.int_clamp(match_data.stage_width, 100, 50000)
	if match_data.has("game_length"):
		time = match_data["game_length"]
	if match_data.has("frame_by_frame"):
		frame_by_frame = match_data.frame_by_frame
	if match_data.has("char_distance"):
		char_distance = match_data["char_distance"]
	if match_data.has("clashing_enabled"):
		clashing_enabled = match_data["clashing_enabled"]
	if match_data.has("asymmetrical_clashing"):
		asymmetrical_clashing = match_data["asymmetrical_clashing"]
	if match_data.has("global_gravity_modifier"):
		global_gravity_modifier = match_data["global_gravity_modifier"]
	if match_data.has("has_ceiling"):
		has_ceiling = match_data["has_ceiling"]
	if match_data.has("ceiling_height"):
		ceiling_height = match_data["ceiling_height"]
	if match_data.has("prediction_enabled"):
		prediction_enabled = match_data["prediction_enabled"]
	p1.has_ceiling = has_ceiling
	p2.has_ceiling = has_ceiling
	p1.ceiling_height = ceiling_height
	p2.ceiling_height = ceiling_height




	p1.name = "P1"
	p2.name = "P2"
	p1.logic_rng = BetterRng.new()
	p2.logic_rng = BetterRng.new()
	p1.logic_rng_static = BetterRng.new()
	p2.logic_rng_static = BetterRng.new()
	p1.logic_rng.seed = hash(match_data.seed)
	p1.logic_rng_seed = hash(match_data.seed)
	p2.logic_rng.seed = hash(match_data.seed + 1)
	p2.logic_rng_seed = hash(match_data.seed + 1)
	p1.logic_rng_static.seed = hash(match_data.seed)
	p1.logic_rng_static_seed = hash(match_data.seed)
	p2.logic_rng_static.seed = hash(match_data.seed + 1)
	p2.logic_rng_static_seed = hash(match_data.seed + 1)

	p2.id = 2
	p1.is_ghost = is_ghost
	p2.is_ghost = is_ghost
	p1.set_gravity_modifier(global_gravity_modifier)
	p2.set_gravity_modifier(global_gravity_modifier)
	if not is_ghost:
		Global.current_game = self
	for value in match_data:
		for player in [p1, p2]:
			if player.get(value) != null:
				player.set(value, match_data[value])

	$Players.add_child(p1)
	$Players.add_child(p2)
	p1.set_color(Color("aca2ff"))
	p2.set_color(Color("ff7a81"))
	
	# Inefficiency comes from Node2D.init()
	p1.init()
	p2.init()
	
	

	if match_data.has("selected_styles"):
		var style1 = match_data.selected_styles[1]
		var style2 = match_data.selected_styles[2]

		if is_ghost or Custom.can_use_style(1, style1):
			p1.apply_style(style1)
		

		if is_ghost or Custom.can_use_style(2, style1):
			p2.apply_style(style2)

	if match_data.has("gravity_enabled"):
		gravity_enabled = match_data.gravity_enabled
		p1.gravity_enabled = match_data.gravity_enabled
		p2.gravity_enabled = match_data.gravity_enabled
	

	
	p1.connect("undo", self, "set", ["undoing", true])
	p2.connect("undo", self, "set", ["undoing", true])
	p1.connect("super_started", self, "_on_super_started", [p1])
	p2.connect("super_started", self, "_on_super_started", [p2])
	p1.connect("global_hitlag", self, "on_global_hitlag")
	p2.connect("global_hitlag", self, "on_global_hitlag")
	connect_signals(p1)
	connect_signals(p2)
	objs_map = {
		"P1":p1, 
		"P2":p2, 
	}
	p1.objs_map = objs_map
	p2.objs_map = objs_map
	snapping_camera = true
	self.singleplayer = singleplayer
	if singleplayer:
		if match_data["p2_dummy"]:
			p2.dummy = true
		pass
	elif not is_ghost:
		Network.game = self
	if not singleplayer:
		started_multiplayer = true
		if Network.multiplayer_active:
			p1_username = Network.pid_to_username(1)
			p2_username = Network.pid_to_username(2)

			my_id = Network.player_id
	current_tick = - 1
	if not is_ghost:
		if ReplayManager.playback:
			get_max_replay_tick()
		elif not match_data.has("replay"):
			ReplayManager.init()
		else :
			get_max_replay_tick()
			if ReplayManager.frames[1].size() > 0 or ReplayManager.frames[2].size() > 0:
				ReplayManager.playback = true

	var height = 0
	if match_data.has("char_height"):
		height = - match_data.char_height

	p1.set_pos( - char_distance, height)
	p2.set_pos(char_distance, height)

	
	p1.stage_width = stage_width
	p2.stage_width = stage_width
	if stage_width >= 320:
		camera.limit_left = - stage_width - CAMERA_PADDING
		camera.limit_right = stage_width + CAMERA_PADDING
	


	p1.opponent = p2
	p2.opponent = p1
	p2.set_facing( - 1)
	p1.update_data()
	p2.update_data()
	p1_data = p1.data
	p2_data = p2.data
	apply_hitboxes([p1, p2])
	if not ReplayManager.resimulating:
		show_state()
	if ReplayManager.playback and not ReplayManager.resimulating and not is_ghost:
		yield (get_tree().create_timer(0.5 if not ReplayManager.replaying_ingame else 0.25), "timeout")
	game_started = true
	if not is_ghost:
		if SteamLobby.is_fighting():
			SteamLobby.on_match_started()

	if match_data.has("starting_meter"):
		var meter_amount = p1.fixed.round(p1.fixed.mul(str(Fighter.MAX_SUPER_METER), match_data.starting_meter))
		p1.gain_super_meter(meter_amount)
		p2.gain_super_meter(meter_amount)
