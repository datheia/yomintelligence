extends Node

const DEFAULT_ITERATIONS = 250
const DEFAULT_WARMUP_ITERATIONS = 25


func run(source_game, baseline_target, native_target, iterations:int = DEFAULT_ITERATIONS, warmup_iterations:int = DEFAULT_WARMUP_ITERATIONS) -> Dictionary:
	var result = {
		"ok": false,
		"accuracy_ok": false,
		"baseline_usec_per_copy": 0.0,
		"native_usec_per_copy": 0.0,
		"speedup": 0.0,
		"differences": [],
		"iterations": iterations,
		"warmup_iterations": warmup_iterations,
	}

	var setup_error = _validate_games(source_game, baseline_target, native_target)
	if setup_error != "":
		result["differences"].append(setup_error)
		_print_result(result)
		return result

	iterations = max(1, iterations)
	warmup_iterations = max(0, warmup_iterations)
	result["iterations"] = iterations
	result["warmup_iterations"] = warmup_iterations

	_run_copies(source_game, baseline_target, false, warmup_iterations)
	_run_copies(source_game, native_target, true, warmup_iterations)

	result["native_available"] = _native_available(source_game)

	_copy_once(source_game, baseline_target, false)
	_copy_once(source_game, native_target, true)

	var baseline_snapshot = snapshot_game(baseline_target)
	var native_snapshot = snapshot_game(native_target)
	result["differences"] = diff_snapshots(baseline_snapshot, native_snapshot)
	result["accuracy_ok"] = result["differences"].empty()

	result["baseline_usec_per_copy"] = _time_copies(source_game, baseline_target, false, iterations)
	result["native_usec_per_copy"] = _time_copies(source_game, native_target, true, iterations)
	if result["native_usec_per_copy"] > 0.0:
		result["speedup"] = result["baseline_usec_per_copy"] / result["native_usec_per_copy"]
	result["ok"] = result["accuracy_ok"]

	_print_result(result)
	return result


func _validate_games(source_game, baseline_target, native_target) -> String:
	for entry in [
		["source_game", source_game],
		["baseline_target", baseline_target],
		["native_target", native_target],
	]:
		if entry[1] == null:
			return entry[0] + " is null"
		if not entry[1].has_method("fast_copy_to"):
			return entry[0] + " does not have fast_copy_to"
		if not entry[1].has_method("set_native_fast_copy_enabled"):
			return entry[0] + " does not have set_native_fast_copy_enabled"
	return ""


func _run_copies(source_game, target_game, use_native:bool, count:int) -> void:
	for _i in range(count):
		_copy_once(source_game, target_game, use_native)


func _time_copies(source_game, target_game, use_native:bool, count:int) -> float:
	var started = OS.get_ticks_usec()
	_run_copies(source_game, target_game, use_native, count)
	var elapsed = OS.get_ticks_usec() - started
	return float(elapsed) / float(count)


func _copy_once(source_game, target_game, use_native:bool) -> void:
	source_game.set_native_fast_copy_enabled(use_native)
	source_game.fast_copy_to(target_game)


func _native_available(source_game) -> Dictionary:
	source_game.set_native_fast_copy_enabled(true)
	var native = source_game.get_native_fast_copy()
	return {
		"loaded": native != null,
		"copy_properties": native != null and native.has_method("copy_properties"),
		"copy_state_history": native != null and native.has_method("copy_state_history"),
		"script": native.get_script().resource_path if native != null and native.get_script() != null else "",
	}


func snapshot_game(game) -> Dictionary:
	return {
		"current_tick": _get_value(game, "current_tick"),
		"game_started": _get_value(game, "game_started"),
		"gravity_enabled": _get_value(game, "gravity_enabled"),
		"global_gravity_modifier": _get_value(game, "global_gravity_modifier"),
		"camera": {
			"limit_left": _get_value(game.camera, "limit_left") if game.camera != null else null,
			"limit_right": _get_value(game.camera, "limit_right") if game.camera != null else null,
		},
		"p1": snapshot_fighter(game.p1),
		"p2": snapshot_fighter(game.p2),
		"objects": snapshot_objects(game.objects),
		"objs_map_keys": _sorted_keys(game.objs_map),
	}


func snapshot_fighter(fighter) -> Dictionary:
	if fighter == null:
		return {}

	var state = fighter.current_state() if fighter.has_method("current_state") else null
	var state_variables = {}
	for variable in _get_value(fighter, "state_variables", []):
		state_variables[variable] = _copy_snapshot_value(fighter.get(variable))

	return {
		"script": fighter.get_script().resource_path if fighter.get_script() != null else "",
		"state": state.name if state != null else null,
		"state_name": _get_value(state, "state_name") if state != null else null,
		"state_tick": _get_value(state, "current_tick") if state != null else null,
		"state_data": _copy_snapshot_value(_get_value(state, "data", null)) if state != null else null,
		"pos": _copy_snapshot_value(fighter.get_pos()) if fighter.has_method("get_pos") else null,
		"facing": fighter.get_facing_int() if fighter.has_method("get_facing_int") else null,
		"hp": _get_value(fighter, "hp"),
		"stance": _get_value(fighter, "stance"),
		"blockstun_ticks": _get_value(fighter, "blockstun_ticks"),
		"blocked_hitbox_plus_frames": _get_value(fighter, "blocked_hitbox_plus_frames"),
		"got_parried": _get_value(fighter, "got_parried"),
		"colliding_with_opponent": _get_value(fighter, "colliding_with_opponent"),
		"has_hyper_armor": _get_value(fighter, "has_hyper_armor"),
		"has_projectile_armor": _get_value(fighter, "has_projectile_armor"),
		"projectile_invulnerable": _get_value(fighter, "projectile_invulnerable"),
		"invulnerable": _get_value(fighter, "invulnerable"),
		"logic_rng_seed": _get_value(fighter, "logic_rng_seed"),
		"logic_rng_state": _get_value(fighter.logic_rng, "state") if fighter.logic_rng != null else null,
		"logic_rng_static_seed": _get_value(fighter, "logic_rng_static_seed"),
		"logic_rng_static_state": _get_value(fighter.logic_rng_static, "state") if fighter.logic_rng_static != null else null,
		"state_variables": state_variables,
		"state_history": snapshot_state_machine(fighter.state_machine),
		"hitboxes": snapshot_hitboxes(fighter.hitboxes),
	}


func snapshot_state_machine(state_machine) -> Dictionary:
	if state_machine == null:
		return {}
	var stack = []
	for state in state_machine.states_stack:
		stack.append(state.name if state is Node else str(state))
	var queued = []
	for state in state_machine.queued_states:
		queued.append(state.name if state is Node else str(state))
	return {
		"stack": stack,
		"queued_states": queued,
		"queued_data": _copy_snapshot_value(state_machine.queued_data),
	}


func snapshot_hitboxes(hitboxes:Array) -> Array:
	var snapshot = []
	for hitbox in hitboxes:
		snapshot.append({
			"active": _get_value(hitbox, "active"),
			"enabled": _get_value(hitbox, "enabled"),
			"tick": _get_value(hitbox, "tick"),
			"hit_objects": _copy_snapshot_value(_get_value(hitbox, "hit_objects", [])),
		})
	return snapshot


func snapshot_objects(objects:Array) -> Array:
	var snapshot = []
	for object in objects:
		if not is_instance_valid(object):
			continue
		snapshot.append({
			"filename": _get_value(object, "filename"),
			"obj_name": _get_value(object, "obj_name"),
			"id": _get_value(object, "id"),
			"disabled": _get_value(object, "disabled"),
			"state": object.current_state().name if object.has_method("current_state") and object.current_state() != null else null,
			"pos": _copy_snapshot_value(object.get_pos()) if object.has_method("get_pos") else null,
			"state_history": snapshot_state_machine(_get_value(object, "state_machine")),
		})
	return snapshot


func diff_snapshots(expected, actual, path:String = "") -> Array:
	var differences = []
	if typeof(expected) != typeof(actual):
		differences.append(_format_diff(path, expected, actual))
		return differences

	match typeof(expected):
		TYPE_DICTIONARY:
			var keys = {}
			for key in expected.keys():
				keys[key] = true
			for key in actual.keys():
				keys[key] = true
			for key in _sorted_keys(keys):
				var next_path = _join_path(path, str(key))
				if not expected.has(key):
					differences.append(_format_diff(next_path, "<missing>", actual[key]))
				elif not actual.has(key):
					differences.append(_format_diff(next_path, expected[key], "<missing>"))
				else:
					differences += diff_snapshots(expected[key], actual[key], next_path)
		TYPE_ARRAY:
			if expected.size() != actual.size():
				differences.append(_format_diff(path + ".size()", expected.size(), actual.size()))
				return differences
			for i in range(expected.size()):
				differences += diff_snapshots(expected[i], actual[i], path + "[" + str(i) + "]")
		_:
			if expected != actual:
				differences.append(_format_diff(path, expected, actual))
	return differences


func _copy_snapshot_value(value):
	if value is Array or value is Dictionary:
		return value.duplicate(true)
	return value


func _get_value(object, property:String, default_value = null):
	if object == null:
		return default_value
	var value = object.get(property)
	return default_value if value == null else value


func _sorted_keys(dictionary:Dictionary) -> Array:
	var keys = dictionary.keys()
	keys.sort()
	return keys


func _join_path(base:String, leaf:String) -> String:
	return leaf if base == "" else base + "." + leaf


func _format_diff(path:String, expected, actual) -> String:
	var label = path if path != "" else "<root>"
	return label + " expected=" + str(expected) + " actual=" + str(actual)


func _print_result(result:Dictionary) -> void:
	print("[FAST_COPY_BENCH] iterations=", result["iterations"], " warmup=", result["warmup_iterations"])
	if result.has("native_available"):
		print("[FAST_COPY_BENCH] native_available=", result["native_available"])
	print("[FAST_COPY_BENCH] accuracy_ok=", result["accuracy_ok"], " differences=", result["differences"].size())
	print("[FAST_COPY_BENCH] baseline_gdscript_usec_per_copy=", result["baseline_usec_per_copy"])
	print("[FAST_COPY_BENCH] native_c_usec_per_copy=", result["native_usec_per_copy"])
	print("[FAST_COPY_BENCH] speedup=", result["speedup"], "x")
	for i in range(min(20, result["differences"].size())):
		print("[FAST_COPY_BENCH][DIFF] ", result["differences"][i])
