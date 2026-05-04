extends SceneTree

const GAME_SCENE = "res://Game.tscn"
const GAME_SCENE_ALT = "res://game.tscn"

var _bench = null


func _init():
	call_deferred("_run")


func _run():
	var script_dir = get_script().resource_path.get_base_dir()
	var benchmark_script = load(script_dir.plus_file("FastCopyBenchmark.gd"))
	var patched_game_script = load("res://game.gd")
	if benchmark_script == null or patched_game_script == null:
		print("[FAST_COPY_BENCH] failed to load benchmark or patched game script from ", script_dir)
		quit(1)
		return

	var scene_path = GAME_SCENE if ResourceLoader.exists(GAME_SCENE) else GAME_SCENE_ALT
	if not ResourceLoader.exists(scene_path):
		print("[FAST_COPY_BENCH] missing game scene: ", GAME_SCENE, " or ", GAME_SCENE_ALT)
		quit(1)
		return

	var game_scene = load(scene_path)
	var source = _create_game(game_scene, patched_game_script)
	var baseline_target = _create_game(game_scene, patched_game_script)
	var native_target = _create_game(game_scene, patched_game_script)
	if source == null or baseline_target == null or native_target == null:
		quit(1)
		return

	var match_data = _match_data()
	for game in [source, baseline_target, native_target]:
		var ok = game.start_game(true, match_data)
		if ok == false:
			print("[FAST_COPY_BENCH] start_game failed")
			quit(1)
			return

	for _i in range(10):
		source.tick()

	_bench = benchmark_script.new()
	root.add_child(_bench)
	var result = _bench.run(source, baseline_target, native_target, _arg_int("--iterations", 250), _arg_int("--warmup", 25))
	quit(0 if result["ok"] else 2)


func _create_game(game_scene, mod_game_script):
	var game = game_scene.instance()
	if not game.has_method("fast_copy_to"):
		game.set_script(mod_game_script)
	root.add_child(game)
	return game


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
