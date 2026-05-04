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
	if source == null or target == null:
		_fail("Could not create benchmark games.")
		return

	if source.fast_start_game(true, _match_data()) == false:
		_fail("Could not start source game.")
		return
	if target.fast_start_game(true, _match_data()) == false:
		_fail("Could not start target game.")
		return

	for _i in range(_arg_int("--ticks", 20)):
		source.tick()

	var warmup = _arg_int("--warmup", 50)
	var iterations = _arg_int("--iterations", 1000)
	var native = _load_native(source)

	print("[FAST_COPY_BENCH] iterations=", iterations, " warmup=", warmup)
	print("[FAST_COPY_BENCH] native_loaded=", native != null)
	if native != null:
		print("[FAST_COPY_BENCH] native_methods copy_properties=", native.has_method("copy_properties"), " copy_state_history=", native.has_method("copy_state_history"))

	_print_timing("copy_to_vs_fast_copy_to", _time_copy_to(source, target, warmup, iterations), _time_full_copy(source, target, true, warmup, iterations))
	_print_timing("state_variables_p1", _time_state_variables(source, target, false, warmup, iterations), _time_state_variables(source, target, true, warmup, iterations))
	_print_timing("state_history_p1", _time_state_history(source, target, false, warmup, iterations), _time_state_history(source, target, true, warmup, iterations))
	_print_timing("fast_copy_gdscript_vs_native", _time_full_copy(source, target, false, warmup, iterations), _time_full_copy(source, target, true, warmup, iterations))

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


func _fail(message:String) -> void:
	print("[FAST_COPY_BENCH] ", message)
	quit(1)
