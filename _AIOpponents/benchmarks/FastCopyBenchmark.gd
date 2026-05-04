extends SceneTree

const GAME_SCENE = "res://Game.tscn"
const GAME_SCENE_ALT = "res://game.tscn"


func _init():
	call_deferred("_run")


func _run():
	var game_scene = _load_game_scene()
	var game_script = load(get_script().resource_path.get_base_dir().get_base_dir().plus_file("game.gd"))
	if game_scene == null or game_script == null:
		_fail("Could not load the game scene or AI game extension.")
		return

	var source = _new_game(game_scene, game_script, false)
	var target = _new_game(game_scene, game_script, true)
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
	var gdscript_usec = _time_copies(source, target, false, warmup, iterations)
	var native_usec = _time_copies(source, target, true, warmup, iterations)

	print("[FAST_COPY_BENCH] iterations=", iterations)
	print("[FAST_COPY_BENCH] gdscript_usec_per_copy=", gdscript_usec)
	print("[FAST_COPY_BENCH] native_usec_per_copy=", native_usec)
	if native_usec > 0.0:
		print("[FAST_COPY_BENCH] speedup=", gdscript_usec / native_usec)

	quit(0)


func _load_game_scene():
	var path = GAME_SCENE if ResourceLoader.exists(GAME_SCENE) else GAME_SCENE_ALT
	return load(path) if ResourceLoader.exists(path) else null


func _new_game(game_scene, game_script, ghost:bool):
	var game = game_scene.instance()
	game.set_script(game_script)
	game.is_ghost = ghost
	root.add_child(game)
	return game


func _time_copies(source, target, use_native:bool, warmup:int, iterations:int) -> float:
	_set_native(source, use_native)
	for _i in range(max(0, warmup)):
		source.fast_copy_to(target)

	var count = max(1, iterations)
	var started = OS.get_ticks_usec()
	for _i in range(count):
		source.fast_copy_to(target)
	return float(OS.get_ticks_usec() - started) / float(count)


func _set_native(game, enabled:bool) -> void:
	game.native_fast_copy_warned = false
	game.native_state_history_warned = false
	if enabled:
		game.native_fast_copy_checked = false
		game.native_fast_copy = null
	else:
		game.native_fast_copy_checked = true
		game.native_fast_copy = null


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
