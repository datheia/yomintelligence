extends SceneTree

const GAME_SCENE = "res://Game.tscn"
const GAME_SCENE_ALT = "res://game.tscn"


func _init():
	call_deferred("_run")


func _run():
	var game_scene = _load_game_scene()
	if game_scene == null:
		_fail("Could not load the game scene.")
		return

	var source = _new_game(game_scene, false)
	var target = _new_game(game_scene, true)
	var reference = _new_game(game_scene, true)
	if source == null or target == null or reference == null:
		_fail("Could not create benchmark games.")
		return

	if source.fast_start_game(true, _match_data()) == false:
		_fail("Could not start source game.")
		return
	if target.fast_start_game(true, _match_data()) == false:
		_fail("Could not start target game.")
		return
	if reference.fast_start_game(true, _match_data()) == false:
		_fail("Could not start reference game.")
		return

	for _i in range(_arg_int("--ticks", 20)):
		source.tick()

	var warmup = _arg_int("--warmup", 50)
	var iterations = _arg_int("--iterations", 1000)
	var native = _load_native(source)

	print("[FAST_COPY_BENCH] iterations=", iterations, " warmup=", warmup)
	print("[FAST_COPY_BENCH] native_loaded=", native != null)
	_print_state_shape("p1_current_state", source.p1.current_state())
	_print_accuracy(source, target, reference)
	_print_changed_state_variables(source.p1, target.p1)
	_print_state_accuracy_cases(source, target)
	if native != null:
		print("[FAST_COPY_BENCH] native_methods copy_properties=", native.has_method("copy_properties"), " copy_state_history=", native.has_method("copy_state_history"))

	_print_timing("copy_to_vs_fast_copy_to", _time_copy_to(source, target, warmup, iterations), _time_full_copy(source, target, true, warmup, iterations))
	_print_timing("state_variables_p1", _time_state_variables(source, target, false, warmup, iterations), _time_state_variables(source, target, true, warmup, iterations))
	_print_timing("state_history_p1", _time_state_history(source, target, false, warmup, iterations), _time_state_history(source, target, true, warmup, iterations))
	_print_timing("fast_copy_gdscript_vs_native", _time_full_copy(source, target, false, warmup, iterations), _time_full_copy(source, target, true, warmup, iterations))
	_print_single_timing("fighter_fast_copy_p1", _time_fighter_copy(source, target, warmup, iterations))
	_print_single_timing("fighter_fast_copy_p2", _time_fighter_copy_p2(source, target, warmup, iterations))
	_print_single_timing("chara_copy_pair", _time_chara_copy_pair(source, target, warmup, iterations))
	_print_single_timing("transient_objects", _time_transient_objects(source, target, warmup, iterations))
	_print_single_timing("fighter_change_state_p1", _time_change_state(source, target, warmup, iterations))
	_print_single_timing("fighter_live_state_data_p1", _time_live_state_data(source, target, warmup, iterations))
	_print_single_timing("fighter_hitboxes_p1", _time_hitboxes(source, target, warmup, iterations))
	_print_single_timing("fighter_hurtbox_states_p1", _time_hurtbox_states(source, target, warmup, iterations))
	_print_single_timing("fighter_update_data_p1", _time_update_data(source, target, warmup, iterations))

	quit(0)


func _load_game_scene():
	var path = GAME_SCENE if ResourceLoader.exists(GAME_SCENE) else GAME_SCENE_ALT
	return load(path) if ResourceLoader.exists(path) else null


func _new_game(game_scene, ghost:bool):
	var game = game_scene.instance()
	if not game.has_method("fast_copy_to"):
		var game_script = load(get_script().resource_path.get_base_dir().get_base_dir().plus_file("game.gd"))
		if game_script == null:
			return null
		game.set_script(game_script)
	game.is_ghost = ghost
	root.add_child(game)
	return game


func _time_full_copy(source, target, use_native:bool, warmup:int, iterations:int) -> float:
	_set_native(source, use_native)
	for _i in range(max(0, warmup)):
		source.fast_copy_to(target)

	var count = max(1, iterations)
	var started = OS.get_ticks_usec()
	for _i in range(count):
		source.fast_copy_to(target)
	return float(OS.get_ticks_usec() - started) / float(count)


func _time_copy_to(source, target, warmup:int, iterations:int) -> float:
	for _i in range(max(0, warmup)):
		source.copy_to(target)

	var count = max(1, iterations)
	var started = OS.get_ticks_usec()
	for _i in range(count):
		source.copy_to(target)
	return float(OS.get_ticks_usec() - started) / float(count)


func _time_state_variables(source, target, use_native:bool, warmup:int, iterations:int) -> float:
	_set_native(source, use_native)
	for _i in range(max(0, warmup)):
		source.copy_fast_state_variables(source.p1, target.p1)

	var count = max(1, iterations)
	var started = OS.get_ticks_usec()
	for _i in range(count):
		source.copy_fast_state_variables(source.p1, target.p1)
	return float(OS.get_ticks_usec() - started) / float(count)


func _time_state_history(source, target, use_native:bool, warmup:int, iterations:int) -> float:
	_set_native(source, use_native)
	for _i in range(max(0, warmup)):
		source.copy_state_history(source.p1, target.p1)

	var count = max(1, iterations)
	var started = OS.get_ticks_usec()
	for _i in range(count):
		source.copy_state_history(source.p1, target.p1)
	return float(OS.get_ticks_usec() - started) / float(count)


func _time_fighter_copy(source, target, warmup:int, iterations:int) -> float:
	_set_native(source, true)
	for _i in range(max(0, warmup)):
		source.copy_fighter_for_prediction(source.p1, target.p1)

	var count = max(1, iterations)
	var started = OS.get_ticks_usec()
	for _i in range(count):
		source.copy_fighter_for_prediction(source.p1, target.p1)
	return float(OS.get_ticks_usec() - started) / float(count)


func _time_fighter_copy_p2(source, target, warmup:int, iterations:int) -> float:
	_set_native(source, true)
	for _i in range(max(0, warmup)):
		source.copy_fighter_for_prediction(source.p2, target.p2)

	var count = max(1, iterations)
	var started = OS.get_ticks_usec()
	for _i in range(count):
		source.copy_fighter_for_prediction(source.p2, target.p2)
	return float(OS.get_ticks_usec() - started) / float(count)


func _time_chara_copy_pair(source, target, warmup:int, iterations:int) -> float:
	for _i in range(max(0, warmup)):
		source.p1.chara.copy_to(target.p1.chara)
		source.p2.chara.copy_to(target.p2.chara)

	var count = max(1, iterations)
	var started = OS.get_ticks_usec()
	for _i in range(count):
		source.p1.chara.copy_to(target.p1.chara)
		source.p2.chara.copy_to(target.p2.chara)
	return float(OS.get_ticks_usec() - started) / float(count)


func _time_transient_objects(source, target, warmup:int, iterations:int) -> float:
	for _i in range(max(0, warmup)):
		source.copy_transient_objects_for_prediction(target, [])

	var count = max(1, iterations)
	var started = OS.get_ticks_usec()
	for _i in range(count):
		source.copy_transient_objects_for_prediction(target, [])
	return float(OS.get_ticks_usec() - started) / float(count)


func _time_change_state(source, target, warmup:int, iterations:int) -> float:
	var current_state = source.p1.current_state()
	for _i in range(max(0, warmup)):
		target.p1.change_state(current_state.state_name, source.copy_fast_variant(current_state.data))

	var count = max(1, iterations)
	var started = OS.get_ticks_usec()
	for _i in range(count):
		target.p1.change_state(current_state.state_name, source.copy_fast_variant(current_state.data))
	return float(OS.get_ticks_usec() - started) / float(count)


func _time_live_state_data(source, target, warmup:int, iterations:int) -> float:
	for _i in range(max(0, warmup)):
		source.copy_live_state_data(source.p1, target.p1)

	var count = max(1, iterations)
	var started = OS.get_ticks_usec()
	for _i in range(count):
		source.copy_live_state_data(source.p1, target.p1)
	return float(OS.get_ticks_usec() - started) / float(count)


func _time_hitboxes(source, target, warmup:int, iterations:int) -> float:
	for _i in range(max(0, warmup)):
		_copy_hitboxes(source.p1, target.p1)

	var count = max(1, iterations)
	var started = OS.get_ticks_usec()
	for _i in range(count):
		_copy_hitboxes(source.p1, target.p1)
	return float(OS.get_ticks_usec() - started) / float(count)


func _copy_hitboxes(copy_from, copy_target) -> void:
	var pos = copy_from.get_pos()
	for hitbox in copy_target.hitboxes:
		if hitbox.active:
			hitbox.deactivate()
	for i in range(copy_from.hitboxes.size()):
		copy_target.hitboxes[i].hit_objects = copy_from.hitboxes[i].hit_objects.duplicate()
		if copy_from.hitboxes[i].active:
			copy_target.hitboxes[i].activate()
			copy_target.hitboxes[i].tick = copy_from.hitboxes[i].tick
			copy_target.hitboxes[i].enabled = copy_from.hitboxes[i].enabled
			copy_from.hitboxes[i].copy_to(copy_target.hitboxes[i])
			copy_target.hitboxes[i].update_position(pos.x, pos.y)

func _time_hurtbox_states(source, target, warmup:int, iterations:int) -> float:
	for _i in range(max(0, warmup)):
		_copy_hurtbox_states(source.p1, target.p1)

	var count = max(1, iterations)
	var started = OS.get_ticks_usec()
	for _i in range(count):
		_copy_hurtbox_states(source.p1, target.p1)
	return float(OS.get_ticks_usec() - started) / float(count)


func _copy_hurtbox_states(copy_from, copy_target) -> void:
	_copy_live_hurtbox_states(copy_from, copy_target)


func _copy_live_hurtbox_states(copy_from, copy_target) -> void:
	var state_names = {}
	var current_state = copy_from.current_state()
	if current_state:
		state_names[current_state.name] = true
	for state in copy_from.state_machine.states_stack:
		state_names[state.name] = true
	for queued_state in copy_from.state_machine.queued_states:
		var state_name = queued_state.name if queued_state is Node else str(queued_state)
		state_names[state_name] = true
	for state_name in state_names.keys():
		if copy_from.state_machine.states_map.has(state_name) and copy_target.state_machine.states_map.has(state_name):
			copy_from.state_machine.states_map[state_name].copy_hurtbox_states(copy_target.state_machine.states_map[state_name])


func _time_update_data(source, target, warmup:int, iterations:int) -> float:
	for _i in range(max(0, warmup)):
		target.p1.update_data()

	var count = max(1, iterations)
	var started = OS.get_ticks_usec()
	for _i in range(count):
		target.p1.update_data()
	return float(OS.get_ticks_usec() - started) / float(count)


func _load_native(game):
	_set_native(game, true)
	return game.get_native_fast_copy()


func _set_native(game, enabled:bool) -> void:
	game.native_fast_copy_warned = false
	game.native_state_history_warned = false
	if enabled:
		game.native_fast_copy_checked = false
		game.native_fast_copy = null
	else:
		game.native_fast_copy_checked = true
		game.native_fast_copy = null


func _print_timing(label:String, gdscript_usec:float, native_usec:float) -> void:
	print("[FAST_COPY_BENCH] ", label, "_gdscript_usec=", gdscript_usec)
	print("[FAST_COPY_BENCH] ", label, "_native_usec=", native_usec)
	if native_usec > 0.0:
		print("[FAST_COPY_BENCH] ", label, "_speedup=", gdscript_usec / native_usec)


func _print_single_timing(label:String, usec:float) -> void:
	print("[FAST_COPY_BENCH] ", label, "_usec=", usec)


func _print_state_shape(label:String, state) -> void:
	var hitboxes = 0
	var hurtboxes = 0
	for child in state.get_children():
		var script = child.get_script()
		var script_path = script.resource_path if script != null else ""
		if script_path.ends_with("Hitbox.gd") or script_path.ends_with("Hitbox.gdc"):
			hitboxes += 1
		elif script_path.ends_with("HurtboxState.gd") or script_path.ends_with("HurtboxState.gdc"):
			hurtboxes += 1
	print("[FAST_COPY_BENCH] ", label, "_name=", state.name, " property_count=", state.property_list.size(), " child_count=", state.get_child_count(), " hitboxes=", hitboxes, " hurtboxes=", hurtboxes)


func _print_accuracy(source, fast_target, copy_target) -> void:
	source.copy_to(copy_target)
	source.fast_copy_to(fast_target)
	var mismatches = []
	_compare_fighter("p1", source.p1, fast_target.p1, mismatches)
	_compare_fighter("p2", source.p2, fast_target.p2, mismatches)
	print("[FAST_COPY_BENCH] accuracy_ok=", mismatches.empty(), " mismatch_count=", mismatches.size())
	for i in range(min(10, mismatches.size())):
		print("[FAST_COPY_BENCH] accuracy_mismatch=", mismatches[i])


func _print_changed_state_variables(source_fighter, target_fighter) -> void:
	var changed = []
	for variable in source_fighter.state_variables:
		if var2str(source_fighter.get(variable)) != var2str(target_fighter.get(variable)):
			changed.append(variable)
	print("[FAST_COPY_BENCH] changed_state_variables_count=", changed.size(), " names=", changed)


func _print_state_accuracy_cases(source, fast_target) -> void:
	var states = _arg_string("--states", "Wait,Fall,DashForward,Jump,Grab").split(",", false)
	for state_name in states:
		if not source.p1.state_machine.states_map.has(state_name):
			print("[FAST_COPY_BENCH] state_accuracy state=", state_name, " skipped=true")
			continue
		source.p1.change_state(state_name)
		source.fast_copy_to(fast_target)
		var mismatches = []
		_compare_fighter("p1", source.p1, fast_target.p1, mismatches)
		print("[FAST_COPY_BENCH] state_accuracy state=", state_name, " ok=", mismatches.empty(), " mismatch_count=", mismatches.size())
		for i in range(min(3, mismatches.size())):
			print("[FAST_COPY_BENCH] state_accuracy_mismatch=", mismatches[i])
	source.p1.change_state("Wait")
	source.p1.state_machine.states_stack.clear()
	source.p1.state_machine.states_stack.append(source.p1.current_state())


func _compare_fighter(label:String, source_fighter, fast_fighter, mismatches:Array) -> void:
	_compare_value(label + ".hp", fast_fighter.hp, source_fighter.hp, mismatches)
	_compare_value(label + ".pos", fast_fighter.get_pos(), source_fighter.get_pos(), mismatches)
	_compare_value(label + ".current_state", fast_fighter.current_state().name, source_fighter.current_state().name, mismatches)
	_compare_value(label + ".current_tick", fast_fighter.current_state().current_tick, source_fighter.current_state().current_tick, mismatches)
	_compare_value(label + ".state_stack", _state_names(fast_fighter.state_machine.states_stack), _state_names(source_fighter.state_machine.states_stack), mismatches)
	_compare_value(label + ".queued_states", _queued_state_names(fast_fighter.state_machine.queued_states), _queued_state_names(source_fighter.state_machine.queued_states), mismatches)
	for variable in source_fighter.state_variables:
		_compare_value(label + "." + variable, fast_fighter.get(variable), source_fighter.get(variable), mismatches)


func _compare_value(label:String, fast_value, copy_value, mismatches:Array) -> void:
	if var2str(fast_value) != var2str(copy_value):
		mismatches.append(label + " fast=" + str(fast_value) + " copy=" + str(copy_value))


func _state_names(stack:Array) -> Array:
	var names = []
	for state in stack:
		names.append(state.name)
	return names


func _queued_state_names(stack:Array) -> Array:
	var names = []
	for state in stack:
		names.append(state.name if state is Node else str(state))
	return names


func _match_data() -> Dictionary:
	return {
		"seed": 1234567,
		"selected_characters": {
			1: {"name": "Ninja"},
			2: {"name": "Ninja"},
		},
		"selected_styles": {
			1: null,
			2: null,
		},
		"stage_width": 1000,
		"game_length": 30,
		"char_distance": 60,
		"char_height": 0,
		"clashing_enabled": true,
		"asymmetrical_clashing": false,
		"global_gravity_modifier": "1.0",
		"gravity_enabled": true,
		"has_ceiling": false,
		"ceiling_height": -1000,
		"prediction_enabled": true,
		"frame_by_frame": false,
		"p2_dummy": true,
	}


func _arg_int(name:String, default_value:int) -> int:
	var args = OS.get_cmdline_args()
	for i in range(args.size()):
		if args[i] == name and i + 1 < args.size():
			return int(args[i + 1])
	return default_value


func _arg_string(name:String, default_value:String) -> String:
	var args = OS.get_cmdline_args()
	for i in range(args.size()):
		if args[i] == name and i + 1 < args.size():
			return args[i + 1]
	return default_value


func _fail(message:String) -> void:
	print("[FAST_COPY_BENCH] ", message)
	quit(1)
