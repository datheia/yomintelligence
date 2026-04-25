extends "res://game.gd"

const FAST_COPY_EXTRA_BY_SCRIPT = {
	"res://characters/wizard/Wizard.gd": ["boulder_projectile"],
	"res://characters/swordandgun/SwordGuy.gd": ["bullet_cancelling"],
}

const FAST_COPY_SAFE_FIGHTER_SCRIPTS = [
	"res://characters/stickman/Stickman.gd",
	"res://characters/wizard/Wizard.gd",
	"res://characters/swordandgun/SwordGuy.gd",
	"res://characters/robo/Robot.gd",
	"res://characters/mutant/Beast.gd",
]

var fast_copy_scene_cache = {}
var native_fast_copy_checked = false
var native_fast_copy = null
var native_fast_copy_warned = false
var native_state_history_warned = false


func copy_fast_variant(value):
	if value is Array or value is Dictionary:
		return value.duplicate(true)
	return value


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



func _ready():
	if !is_ghost:
		add_child(preload("res://_AIOpponents/AIController.tscn").instance())
	._ready()
#
# Code for faster deep copy

func fast_copy_to(game:Game):
	if not game_started:
		return

	var reusable_objects = game.objects.duplicate()
	game.objects.clear()
	for fx in game.effects.duplicate():
		if is_instance_valid(fx):
			fx.free()
	game.effects.clear()
	reset_fast_copy_objs_map(game)

	p1.chara.copy_to(game.p1.chara)
	p2.chara.copy_to(game.p2.chara)
	game.p1.update_data()
	game.p2.update_data()

	copy_fighter_for_prediction(p1, game.p1)
	copy_fighter_for_prediction(p2, game.p2)

	game.p1.hp = p1.hp
	game.p2.hp = p2.hp

	# Clean source game objects
	clean_objects()
	copy_transient_objects_for_prediction(game, reusable_objects)
	game.camera.limit_left = camera.limit_left
	game.camera.limit_right = camera.limit_right


func reset_fast_copy_objs_map(game:Game):
	game.objs_map = {
		"P1": game.p1,
		"P2": game.p2,
	}
	game.p1.objs_map = game.objs_map
	game.p2.objs_map = game.objs_map


func get_fast_copy_scene(filename:String):
	if not fast_copy_scene_cache.has(filename):
		fast_copy_scene_cache[filename] = load(filename)
	return fast_copy_scene_cache[filename]


func reset_hitboxes_for_fast_copy(object):
	for hitbox in object.hitboxes:
		hitbox.deactivate()


func copy_transient_objects_for_prediction(game:Game, reusable_objects:Array):
	for old_object in reusable_objects:
		if is_instance_valid(old_object):
			old_object.free()

	for object in objects:
		if not is_instance_valid(object):
			continue
		if object.disabled:
			game.objs_map[str(game.objs_map.size() + 1)] = null
			continue

		copy_fast_prediction_object(object, game)


func copy_fast_prediction_object(object, game:Game):
	var target = get_fast_copy_scene(object.filename).instance()
	target.obj_name = object.obj_name
	target.name = object.obj_name
	target.id = object.id
	target.objs_map = game.objs_map
	game.objects.append(target)
	game.objects_node.add_child(target)
	target.has_ceiling = game.has_ceiling
	target.ceiling_height = game.ceiling_height
	target.logic_rng = BetterRng.new()
	target.logic_rng_static = BetterRng.new()
	var seed_ = hash(game.match_data.seed + int(object.obj_name))
	target.logic_rng.seed = seed_
	target.logic_rng_seed = seed_
	target.logic_rng_static.seed = game.match_data.seed
	target.logic_rng_static_seed = game.match_data.seed
	game.objs_map[object.obj_name] = target
	target.connect("tree_exited", game, "_on_obj_exit_tree", [target])
	target.connect("hitbox_refreshed", game, "on_hitbox_refreshed")
	target.connect("global_hitlag", game, "on_global_hitlag")
	target.gravity_enabled = game.gravity_enabled
	target.set_gravity_modifier(game.global_gravity_modifier)
	target.fighter_owner = game.get_player(object.id)
	for particle in target.particles.get_children():
		game.effects.append(particle)
	game.connect_signals(target)
	object.copy_to(target)
	game.objs_map[object.obj_name] = target
	target.objs_map = game.objs_map



func copy_fighter_for_prediction(copy_from:Fighter, copy_target:Fighter):
	if fighter_supports_fast_copy(copy_from):
		fighter_fast_copy(copy_from, copy_target)
	else:
		copy_from.copy_to(copy_target)
		copy_state_history(copy_from, copy_target)


func fighter_supports_fast_copy(fighter:Fighter) -> bool:
	var script = fighter.get_script()
	return script != null and script.resource_path in FAST_COPY_SAFE_FIGHTER_SCRIPTS


# Deep copy one fighter's values into a target Fighter object.
func fighter_fast_copy(copy_from:Fighter, copy_target:Fighter):

	# BASE OBJECT COPY, WITH CHANGES

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


	#Initial here takes 0.001s

	copy_target.change_state(current_state.state_name, copy_fast_variant(current_state.data))

	copy_live_state_data(copy_from, copy_target)

	copy_state_history(copy_from, copy_target)





	copy_target.stage_width = copy_from.stage_width




	copy_target.chara.update_grounded()


	copy_target.update_data()
	copy_target.sprite.rotation = copy_from.sprite.rotation
	copy_target.set_facing(copy_from.get_facing_int())
	var pos = copy_from.get_pos()
	reset_hitboxes_for_fast_copy(copy_target)
	for i in range(copy_from.hitboxes.size()):
		copy_target.hitboxes[i].hit_objects = copy_from.hitboxes[i].hit_objects.duplicate()
		if copy_from.hitboxes[i].active:
			copy_target.hitboxes[i].activate()
			copy_target.hitboxes[i].tick = copy_from.hitboxes[i].tick
			copy_target.hitboxes[i].enabled = copy_from.hitboxes[i].enabled
			copy_from.hitboxes[i].copy_to(copy_target.hitboxes[i])
			copy_target.hitboxes[i].update_position(pos.x, pos.y)
	copy_from.hurtbox.copy_to(copy_target.hurtbox)
	copy_target.projectile_invulnerable = copy_from.projectile_invulnerable
	copy_target.invulnerable = copy_from.invulnerable

	copy_from.chara.copy_to(copy_target.chara)
	copy_target.set_facing(copy_from.get_facing_int())

	for state in copy_target.state_machine.states_map:
		copy_from.state_machine.states_map[state].copy_hurtbox_states(copy_target.state_machine.states_map[state])




	# Reuse existing RNG objects to reduce allocations
	if copy_target.logic_rng == null:
		copy_target.logic_rng = BetterRng.new()
	if copy_target.logic_rng_static == null:
		copy_target.logic_rng_static = BetterRng.new()

	copy_target.logic_rng.seed = copy_from.logic_rng_seed
	copy_target.logic_rng_static.seed = copy_from.logic_rng_static_seed

	copy_target.logic_rng.state = copy_from.logic_rng.state
	copy_target.logic_rng_static.state = copy_from.logic_rng_static.state



	# BASE FIGHTER COPY

	copy_target.got_parried = copy_from.got_parried
	copy_target.colliding_with_opponent = copy_from.colliding_with_opponent
	copy_target.has_hyper_armor = copy_from.has_hyper_armor
	copy_target.has_projectile_armor = copy_from.has_hyper_armor
	copy_target.has_projectile_armor = copy_from.has_projectile_armor
	copy_target.blockstun_ticks = copy_from.blockstun_ticks
	copy_target.blocked_hitbox_plus_frames = copy_from.blocked_hitbox_plus_frames
	copy_target.stance = copy_from.stance
	copy_target.current_state().interrupt_frames = current_state.interrupt_frames.duplicate(true)
	copy_target.update_data()

	var facing = copy_from.get_facing_int()
	copy_target.set_facing(facing, true)

	fighter_fast_copy_character_specific(copy_from, copy_target)

	copy_target.update_data()


func copy_fast_state_variables(copy_from:Fighter, copy_target:Fighter):
	var native = get_native_fast_copy()
	if native != null and native.has_method("copy_properties"):
		var copied = native.copy_properties(copy_from, copy_target, copy_from.state_variables)
		if copied == copy_from.state_variables.size():
			return
		if not native_fast_copy_warned:
			native_fast_copy_warned = true
			print("[FAST_COPY_NATIVE] copied " + str(copied) + "/" + str(copy_from.state_variables.size()) + " state variables; falling back to GDScript")

	for variable in copy_from.state_variables:
		var v = copy_from.get(variable)
		if v is Array or v is Dictionary:
			copy_target.set(variable, v.duplicate(true))
		else:
			copy_target.set(variable, v)


func fighter_fast_copy_character_specific(copy_from:Fighter, copy_target:Fighter):
	var script = copy_from.get_script()
	if script != null and FAST_COPY_EXTRA_BY_SCRIPT.has(script.resource_path):
		for variable in FAST_COPY_EXTRA_BY_SCRIPT[script.resource_path]:
			var value = copy_from.get(variable)
			if value is Array or value is Dictionary:
				copy_target.set(variable, value.duplicate(true))
			else:
				copy_target.set(variable, value)

	# Robot's ordinary gameplay fields are covered by extra_state_variables, but
	# its copy_to override also preserves these visual/area polygons.
	if script != null and script.resource_path == "res://characters/robo/Robot.gd":
		copy_target.magnet_polygon.polygon = copy_from.magnet_polygon.polygon
		copy_target.magnet_polygon2.polygon = copy_from.magnet_polygon2.polygon


func copy_live_state_data(copy_from:Fighter, copy_target:Fighter):
	var state_names = {}
	if copy_from.current_state():
		state_names[copy_from.current_state().name] = true
	for state in copy_from.state_machine.states_stack:
		state_names[state.name] = true
	for queued_state in copy_from.state_machine.queued_states:
		var state_name = queued_state.name if queued_state is Node else str(queued_state)
		state_names[state_name] = true

	for state_name in state_names.keys():
		if copy_from.state_machine.states_map.has(state_name) and copy_target.state_machine.states_map.has(state_name):
			copy_from.state_machine.states_map[state_name].copy_to(copy_target.state_machine.states_map[state_name])


func copy_state_history(copy_from:Fighter, copy_target:Fighter):
	var native = get_native_fast_copy()
	if native != null and native.has_method("copy_state_history"):
		if native.copy_state_history(copy_from, copy_target):
			return
		if not native_state_history_warned:
			native_state_history_warned = true
			print("[FAST_COPY_NATIVE] state history copy failed; falling back to GDScript")

	copy_target.state_machine.states_stack.clear()
	for state in copy_from.state_machine.states_stack:
		if copy_target.state_machine.states_map.has(state.name):
			copy_target.state_machine.states_stack.append(copy_target.state_machine.states_map[state.name])

	copy_target.state_machine.queued_states.clear()
	copy_target.state_machine.queued_data.clear()
	for state in copy_from.state_machine.queued_states:
		var state_name = state.name if state is Node else str(state)
		if copy_target.state_machine.states_map.has(state_name):
			copy_target.state_machine.queued_states.append(state_name)
	for datum in copy_from.state_machine.queued_data:
		copy_target.state_machine.queued_data.append(copy_fast_variant(datum))



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
	else:
		return false
	if Global.name_paths.has(match_data.selected_characters[2]["name"]):
		p2 = load(Global.name_paths[match_data.selected_characters[2]["name"]]).instance()
	else:
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
		else:
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
		yield(get_tree().create_timer(0.5 if not ReplayManager.replaying_ingame else 0.25), "timeout")
	game_started = true
	if not is_ghost:
		if SteamLobby.is_fighting():
			SteamLobby.on_match_started()

	if match_data.has("starting_meter"):
		var meter_amount = p1.fixed.round(p1.fixed.mul(str(Fighter.MAX_SUPER_METER), match_data.starting_meter))
		p1.gain_super_meter(meter_amount)
		p2.gain_super_meter(meter_amount)
