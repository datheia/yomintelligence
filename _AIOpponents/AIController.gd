extends Node2D

var target_player = null
var id = 0

var queued_action = null
var queued_data = null
var queued_extra = null
var ai_vs_ai = false
var ai_vs_ai_deciding = false
var ai_vs_ai_ready = false

var ghost_game = null
var main = null
var ghost_viewport = null
var game = null
var search_ui_host = null

var gg_scene = null
var ghost_match_signature = ""
var ghost_setup_created = 0
var ghost_setup_reused = 0
var ghost_base = null
var ghost_eval = null
var search_snapshots = []
var search_start_hp = {}
var search_start_distance = 0.0

# Search tree tracking for debugging
var search_tree = {
	"depth": 0,
	"node_id": "root_0",
	"moves": [],
	"total_nodes": 0,
	"best_move": null
}
var search_warnings = []
var search_ghost_simulations = 0
var search_moves_evaluated = 0
var search_moves_pruned = 0
var search_profile = {}

# To check UIElements against to see if they have the same script as the 3 default ones
var checkable_menu = preload("res://_AIOpponents/AICheckableUIData.tscn").instance()

var configured_search_depth = 2
var read_strength = 55.0
var experimental_speedup = true

export var _c_AI_variables = 0
# Frames simulated when evaluating a move. Slow supers and long recovery states
# need more than the old 35 frame window to score correctly.
export var FRAMES_TO_SIMULATE = 35
# Search depth - how many decision plies to think ahead.
export var SEARCH_DEPTH = 2
export var REAL_SEARCH_DEPTH_CAP = 3
export(float, 0.2, 0.6) var PRUNE_PERCENT = 0.8 # Higher keeps more candidate moves during search; lower prunes harder and makes choices narrower/faster.
export var ROOT_BRANCH_CAP = 7 # Max number of our candidate moves explored at the root decision.
export var OPPONENT_BRANCH_CAP = 4 # Max number of opponent reply moves considered for each of our root moves.
export var FOLLOWUP_BRANCH_CAP = 5 # Max number of our non-root followup moves explored in deeper search plies.
export(float, 0.0, 1.0) var WORST_REPLY_WEIGHT = 0.2 # Safety floor when the opponent read is confident: higher = less exploitative, lower = more willing to hard-read.
export(float, 0.0, 1.0) var UNCERTAIN_REPLY_WEIGHT = 0.25 # Safety floor when the opponent read is uncertain: higher = more anti-exploit/defensive under ambiguity.
export var OPPONENT_REPLY_TEMPERATURE = 300.0 # Softmax temperature for opponent reply prediction: lower = sharper/more committed read, higher = flatter/more cautious read.
export var SEARCH_PROFILE_LOGGING = true
export var SEARCH_TREE_EXPORT_ENABLED = false
export var SEARCH_TREE_PRINT_JSON = false
export var SEARCH_TREE_OUTPUT_PATH = "user://ai_search_tree_latest.json"
# States to not simulate
export var states_to_ignore = ["Taunt"] 
# Stop eval immediately if a move causes hp to drop below 0
export var prevent_self_destruction = true 
# Amount to multiply the damage a move does by at evaluation
export var DAMAGE_MODIFIER = 24
# Amount to penalize damage taken.
export var DAMAGE_TAKEN_PENALTY = 150
# Amount by which to multiply the frame advantage a move causes at evaluation
export var FRAME_ADVANTAGE_MODIFIER = 25

# Combo/hurt catastrophe scoring - large swing when either side is already in a decisive hurt/combo state.
export var COMBOED_PENALTY = 10000
export var COMBOED_COUNT_PENALTY = 1000
export var HURT_STATE_PENALTY = 3000
export var VULNERABLE_FRAME_PENALTY = 80
export var COMBO_REWARD = 4500
export var COMBO_COUNT_REWARD = 450

enum LogLevel { ERROR, WARN, INFO, DEBUG, TRACE }
export(int) var log_level = LogLevel.INFO

var quick_data_lookup = {
	"SuperJump":["homing"],
	"Grab":{"Dash":[true, false], "Direction":[{"x":1, "y":0}, {"x":-1, "y":0}], "Jump":[false]},
	#"DashForward":{"AutoCorrect":[true], "Distance":[{"x":0}, {"x":100}, {"x":50}]},
	"ParryHigh":["Parry"],
	"Jump":[{"x":0, "y":-100}, {"x":-87, "y":-50}, {"x":87, "y":-50}, #Largest jump in directions
		{"x":45, "y":-89}, {"x":-54, "y":-84}, #Diagonal
		{"x":0, "y":-69}, {"x":-60, "y":-35}, {"x":60, "y":-35}], #Short hops
}

var hidden_ai_actions = {
	"InstantCancel": true,
	"WhiffInstantCancel": true,
}

class SearchActionButtonsStub:
	var current_button = null
	var opponent_action_buttons = null


var multihustle = false


func _ready():
	game = get_parent()
	if game != null and game.is_ghost:
		self.queue_free()
		return

	search_ui_host = Control.new()
	search_ui_host.name = "AISearchUIHost"
	search_ui_host.visible = false
	search_ui_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(search_ui_host)

	if main == null:
		main = find_parent("Main")
	if !multihustle and main.has_method("MultiHustle_AddData"):
		print("AI: Multihustle detected!")
		multihustle = true

	# Load AI options
	var ModOptions = main.get_node("ModOptions")
	if ModOptions != null and ModOptions.has_method("get_setting"):
		id = _normalize_target_player_setting(int(ModOptions.get_setting("_AIOptions", "target_player")))
		configured_search_depth = int(ModOptions.get_setting("_AIOptions", "search_depth"))
		read_strength = float(ModOptions.get_setting("_AIOptions", "read_strength"))
		ai_vs_ai = false
		experimental_speedup = ModOptions.get_setting("_AIOptions", "experimental_speedup")
	elif ModOptions != null:
		if ModOptions.has("settings"):
			var ai_settings = ModOptions.settings.get("_AIOptions", {})
			id = _normalize_target_player_setting(int(ai_settings.get("target_player", 2)))
			configured_search_depth = int(ai_settings.get("search_depth", configured_search_depth))
			read_strength = float(ai_settings.get("read_strength", read_strength))
			ai_vs_ai = false
			experimental_speedup = bool(ai_settings.get("experimental_speedup", true))
		else:
			id = 2
	else:
		id = 2
	apply_saved_ai_options()
	id = _normalize_target_player_setting(id)
	ai_vs_ai = false
	apply_read_strength()
	if Network.multiplayer_active:
		id = 0
		ai_vs_ai = false
	print("AI: Options loaded. target=" + str(id) + ", depth=" + str(configured_search_depth) + ", reads=" + str(int(round(read_strength))))
	
	game.connect("player_actionable", self, "_start_decision_thread")


func _exit_tree():
	release_ghost_game()
	release_search_ghosts()


func debug_print(message):
	log_debug(message)


func _log(level:int, prefix:String, message) -> void:
	if level <= log_level:
		print("[AI][" + prefix + "] " + str(message))


func log_error(message) -> void:
	_log(LogLevel.ERROR, "ERROR", message)


func log_warn(message) -> void:
	_log(LogLevel.WARN, "WARN", message)


func log_info(message) -> void:
	_log(LogLevel.INFO, "INFO", message)


func log_debug(message) -> void:
	_log(LogLevel.DEBUG, "DEBUG", message)


func log_trace(message) -> void:
	_log(LogLevel.TRACE, "TRACE", message)


func _profile_reset() -> void:
	search_profile = {}


func _search_tree_output_enabled() -> bool:
	return SEARCH_TREE_EXPORT_ENABLED or SEARCH_TREE_PRINT_JSON


func _profile_now() -> int:
	return OS.get_ticks_usec()


func _profile_add(name:String, started_usec:int) -> void:
	if !SEARCH_PROFILE_LOGGING:
		return
	var elapsed = OS.get_ticks_usec() - started_usec
	if !search_profile.has(name):
		search_profile[name] = {"us":0, "count":0}
	search_profile[name].us += elapsed
	search_profile[name].count += 1


func _profile_count(name:String, amount:int=1) -> void:
	if !SEARCH_PROFILE_LOGGING:
		return
	if !search_profile.has(name):
		search_profile[name] = {"us":0, "count":0}
	search_profile[name].count += amount


func _profile_print_summary() -> void:
	if !SEARCH_PROFILE_LOGGING:
		return
	var keys = search_profile.keys()
	keys.sort()
	var parts = []
	for key in keys:
		var item = search_profile[key]
		var ms = float(item.us) / 1000.0
		parts.append(key + "=" + str(ms) + "ms/" + str(item.count))
	log_info("[PROFILE] " + " ".join(parts))


func apply_saved_ai_options():
	var file = File.new()
	if not file.file_exists("user://modoptions/_AIOptions.json"):
		return
	if file.open("user://modoptions/_AIOptions.json", File.READ) != OK:
		return
	var saved_settings = parse_json(file.get_as_text())
	file.close()
	if !(saved_settings is Dictionary):
		return
	if saved_settings.has("target_player"):
		id = _normalize_target_player_setting(int(saved_settings.get("target_player")))
		ai_vs_ai = false
	if saved_settings.has("search_depth"):
		configured_search_depth = int(saved_settings.get("search_depth"))
	elif saved_settings.has("difficulty"):
		configured_search_depth = _legacy_difficulty_to_depth(int(saved_settings.get("difficulty")))
	if saved_settings.has("read_strength"):
		read_strength = float(saved_settings.get("read_strength"))
	if saved_settings.has("experimental_speedup"):
		experimental_speedup = bool(saved_settings.get("experimental_speedup"))


func _normalize_target_player_setting(value:int) -> int:
	if value < 0 or value > 2:
		return 0
	return value


func _legacy_difficulty_to_depth(old_difficulty:int) -> int:
	match old_difficulty + 1:
		1:
			return 0
		2, 3:
			return 1
		4, 5:
			return 2
		_:
			return 3


func apply_read_strength() -> void:
	read_strength = clamp(read_strength, 0.0, 100.0)
	var normalized = read_strength / 100.0
	WORST_REPLY_WEIGHT = lerp(0.45, 0.08, normalized)
	UNCERTAIN_REPLY_WEIGHT = lerp(0.85, 0.20, normalized)
	OPPONENT_REPLY_TEMPERATURE = lerp(1150.0, 180.0, normalized)


func _start_decision_thread():
	if ai_vs_ai:
		make_ai_vs_ai_moves()
		return
	if id <= 0:
		print("AI: Disabled")
		get_parent().disconnect("player_actionable", self, "_start_decision_thread")
		self.queue_free()
		return
	if !target_player:
		target_player = get_parent().get_player(id)
		if target_player:
			target_player.connect("action_selected", self, "_edit_queue")
			print("AI: Controller ready!")
		else:
			print("AI: Disabled")
			get_parent().disconnect("player_actionable", self, "_start_decision_thread")
			self.queue_free()
			return
	if !_fighter_can_prompt(target_player):
		log_debug("[TURN_SKIP] target P" + str(id) + " is not actionable; state=" + _state_display_name(target_player.current_state()) + " state_interruptable=" + str(target_player.state_interruptable) + " busy_interrupt=" + str(target_player.busy_interrupt))
		return
	if target_player.queued_action != null:
		log_debug("[TURN_SKIP] target P" + str(id) + " already has queued_action=" + str(target_player.queued_action))
		return
	make_move()

func _edit_queue(_action, _data, _extra):
	target_player.queued_action = queued_action
	target_player.queued_data = queued_data
	target_player.queued_extra = queued_extra

# Decicion making code. Calls ActionSelected
func make_ai_vs_ai_moves():
	if ai_vs_ai_deciding:
		return
	if game == null:
		game = get_parent()
	if game == null:
		return
	var p1 = game.get_player(1)
	var p2 = game.get_player(2)
	if p1 == null or p2 == null:
		print("AI vs AI: Disabled")
		return

	ai_vs_ai_deciding = true
	if !ai_vs_ai_ready:
		print("AI vs AI: Controller ready!")
		ai_vs_ai_ready = true

	var p1_choice = null
	var p2_choice = null
	if _fighter_can_prompt(p1) and p1.queued_action == null:
		p1_choice = make_move_for_player(1)
	if _fighter_can_prompt(p2) and p2.queued_action == null:
		p2_choice = make_move_for_player(2)

	if p1_choice != null:
		submit_ai_choice(1, p1_choice)
	if p2_choice != null:
		submit_ai_choice(2, p2_choice)

	if (p1_choice != null or p2_choice != null) and main != null and main.has_method("_start_ghost"):
		main.call_deferred("_start_ghost")

	ai_vs_ai_deciding = false


func make_move_for_player(player_id:int, forced_opponent_action=null, forced_opponent_data=null) -> Dictionary:
	id = player_id
	target_player = get_parent().get_player(id)
	if target_player == null:
		return {"action":"Continue", "data":null, "extra":null, "eval":0, "feint":false}
	return make_move(forced_opponent_action, forced_opponent_data, false)


func submit_ai_choice(player_id:int, choice:Dictionary):
	var player = game.get_player(player_id)
	if player == null:
		return
	if main != null:
		if player_id == 1:
			main.p1_ghost_action = choice.action
			main.p1_ghost_data = choice.data
			main.p1_ghost_extra = choice.extra
		else:
			main.p2_ghost_action = choice.action
			main.p2_ghost_data = choice.data
			main.p2_ghost_extra = choice.extra
	player.on_action_selected(choice.action, choice.data, choice.extra)


func make_move(forced_opponent_action=null, forced_opponent_data=null, submit_choice:bool=true) -> Dictionary:
	
	ReplayManager.resimulating = true # Not strictly necessary but stops Godot errors
	
	debug_print("============================================================")
	var decision_started_ms = OS.get_ticks_msec()
	search_warnings.clear()
	search_ghost_simulations = 0
	search_moves_evaluated = 0
	search_moves_pruned = 0
	_profile_reset()
	var tree_output_enabled = _search_tree_output_enabled()
	
	# Initialize search tree for this turn
	search_tree = {
		"depth": 0,
		"node_id": "root_0",
		"game_state_snapshot": _game_state_snapshot(game) if tree_output_enabled else {},
		"moves": [],
		"total_nodes": 0,
		"best_move": null,
		"turn_info": {
			"game_tick": game.get_ticks_left() if game else 0,
			"p1_hp": game.p1.hp if game else 0,
			"p2_hp": game.p2.hp if game else 0,
			"configured_depth": configured_search_depth,
			"read_strength": read_strength
		}
	}
	
	# Prepare variables for prediction setup
	if game == null:
		game = get_parent()
	if ghost_viewport == null:
		ghost_viewport = main.find_node("GhostViewport")
	if tree_output_enabled:
		search_tree["game_state_snapshot"] = _game_state_snapshot(game)
	
	if multihustle:
		var closest_dist = 999999
		var closest_opponent = target_player.opponent
		for player in game.players.values():
			if player != target_player:
				var opponent_dist = sqrt(pow(player.get_pos().x - target_player.get_pos().x, 2) + pow(player.get_pos().y - target_player.get_pos().y, 2))
				if opponent_dist < closest_dist:
					closest_opponent = player
					closest_dist = opponent_dist
		target_player.opponent = closest_opponent
		debug_print("AI of ID " + str(id) + " chooses to target player ID " + str(target_player.opponent.id))
	
	# Do DI
	var ai_pos = target_player.get_pos()
	var opponent_pos = target_player.opponent.get_pos()
	var di = di_as_percentage_int_vec(Vector2(ai_pos.x - opponent_pos.x, ai_pos.y - opponent_pos.y).normalized())
	var temp_extra = {"DI":di, "feint":false, "prediction":-1, "reverse":false}

	if !_has_visible_non_continue_actions(target_player, temp_extra):
		log_info("[NO_UI_ACTIONS] P" + str(id) + " has no visible actions; auto-continuing.")
		var continue_choice = _continue_move()
		target_player.queued_action = continue_choice.action
		target_player.queued_data = continue_choice.data
		ReplayManager.resimulating = false
		queued_action = continue_choice.action
		queued_data = continue_choice.data
		queued_extra = {"DI":di, "feint":false, "prediction":-1, "reverse":false}
		if submit_choice:
			submit_ai_choice(id, {"action":queued_action, "data":queued_data, "extra":queued_extra})
		if main != null and main.has_method("_start_ghost"):
			main.call_deferred("_start_ghost")
		export_search_tree(decision_started_ms, 0, continue_choice)
		return {"action":queued_action, "data":queued_data, "extra":queued_extra, "eval":0, "feint":false}
	
	var search_depth = min(get_adjusted_search_depth(), REAL_SEARCH_DEPTH_CAP)
	
	var choice = {"action":"Continue", "data":null}
	var opponent_action = choice.action
	var opponent_data = choice.data

	# Initial opponent prediction
	if forced_opponent_action != null:
		opponent_action = forced_opponent_action
		opponent_data = forced_opponent_data
		if tree_output_enabled:
			search_tree["opponent_prediction"] = {"action": opponent_action, "score": 0}
	elif target_player.bursts_available > 0 or target_player.opponent.combo_count <= 0:
		choice = get_best_move(temp_extra, target_player.opponent.id, 0.2, true, false, "Continue", null, 0, null)
		opponent_action = choice.action
		opponent_data = choice.data
		if tree_output_enabled:
			search_tree["opponent_prediction"] = {"action": opponent_action, "score": choice.eval if choice.has("eval") else 0}

	
	debug_print("Choosing " +opponent_action+" with data " + str(opponent_data))
	debug_print("++++++++++++++++++++++++++++++++++++++++++++++++++++")
	
	if search_depth > 0:
		debug_print("[REAL_SEARCH] depth=" + str(search_depth) + " prune=" + str(PRUNE_PERCENT))
		var profile_prepare = _profile_now()
		prepare_real_search(id, search_depth)
		_profile_add("decision.prepare_real_search", profile_prepare)
		var predicted_reply = null
		if opponent_action != "Continue":
			predicted_reply = {"action":opponent_action, "data":opponent_data, "eval":0, "feint":false}
		var profile_search = _profile_now()
		choice = real_search_root(temp_extra, id, search_depth, predicted_reply)
		_profile_add("decision.real_search", profile_search)
	else:
		choice = get_best_move(temp_extra, id, 0.01, true, true, opponent_action, opponent_data, 1, null)
	if _is_ai_locked_cancel_state(target_player) and choice.action != "Continue":
		log_warn("[LEGALITY] replacing " + str(choice.action) + " with Continue because P" + str(id) + " is in " + _state_display_name(target_player.current_state()))
		choice = _continue_move()
	if tree_output_enabled:
		search_tree["my_move"] = {"action": choice.action, "score": choice.eval if choice.has("eval") else 0}
		var decision_reason = "highest_minimax_score_after_depth_" + str(search_depth) + "_search"
		if search_depth == 1:
			decision_reason = "highest_root_score_at_depth_1_no_opponent_model"
		search_tree["best_move"] = {
			"action": choice.action,
			"data": choice.data if choice.has("data") else null,
			"final_score": choice.eval if choice.has("eval") else 0,
			"depth": search_depth,
			"reason": decision_reason
		}
	target_player.queued_action = choice.action
	target_player.queued_data = choice.data
	
	ReplayManager.resimulating = false
	
	queued_action = choice.action
	queued_data = choice.data
	queued_extra = {"DI":di, "feint":choice.feint if target_player.feints > 0 else false, "prediction":-1, "reverse":false}
	debug_print("Extra is " + str(queued_extra))

	if submit_choice:
		submit_ai_choice(id, {"action":queued_action, "data":queued_data, "extra":queued_extra})

	if main != null and main.has_method("_start_ghost"):
		main.call_deferred("_start_ghost")

	export_search_tree(decision_started_ms, search_depth, choice)

	return {"action":queued_action, "data":queued_data, "extra":queued_extra, "eval":choice.eval if choice.has("eval") else 0, "feint":choice.feint if choice.has("feint") else false}


# Function that evaluates a move made by character of an id.
# Returns an array of 2 values - the evaluation number and a bool of whether the move should be free cancelled.
func eval_move(action, data, extra, id, opponent_action="Continue", opponent_data=null):
	# Always create fresh ghost for accurate state - optimization is in cached scene load
	setup_ghost_game()
	
	var evaluee = ghost_game.get_player(id)
	
	var opponent = ghost_game.get_player(evaluee.opponent.id) 
	var validity = check_move_validity(action, evaluee)
	if !validity.valid:
		_record_search_warning(validity.warning_type, action, validity.reason)
		return {
			"eval": -999999,
			"feint": false,
			"valid": false,
			"invalid_reason": validity.reason
		}
	
	# Setup specifics
	opponent.is_ghost = true
	opponent.queued_action = opponent_action
	opponent.queued_data = opponent_data
	opponent.queued_extra = null
	
	evaluee.is_ghost = true
	evaluee.queued_action = action
	evaluee.queued_data = data
	evaluee.queued_extra = extra
	
	var opponent_start_hp = opponent.hp
	var evaluee_start_hp = evaluee.hp
	
	var evaluee_ready_tick = null
	var opponent_ready_tick = null
	var frames_simulated = 0
	
	
	if multihustle: # Makes sure that the evalation plays out as expected in MultiHustle
		evaluee.opponent = opponent
		evaluee.opponent.opponent = evaluee
	
	for current_frame in range(1, FRAMES_TO_SIMULATE+1):
		frames_simulated = current_frame
		search_ghost_simulations += 1
		ghost_game.simulate_one_tick()
		
		if evaluee.hp <= 0 and prevent_self_destruction and evaluee_ready_tick == null:
			return {"eval":-999999, "feint":false}
		
		var evaluee_tick = current_frame + (evaluee.hitlag_ticks if not opponent_ready_tick else 0)
		if (evaluee.state_interruptable or evaluee.dummy_interruptable or evaluee.state_hit_cancellable) and evaluee_ready_tick == null:
			evaluee_ready_tick = evaluee_tick
			# ghost_p1_actionable is evaluee_actionable != null
			# Ready if true, inturrupt if false:
			# opponent.current_state().anim_length == opponent.current_state().current_tick + 1 or opponent.current_state().iasa_at == opponent.current_state().current_tick
			if (opponent.current_state().interruptible_on_opponent_turn or opponent.feinting or ghost_game.negative_on_hit(opponent)) and opponent_ready_tick == null:
				opponent_ready_tick = current_frame
				break
		var opponent_tick = current_frame + (opponent.hitlag_ticks if not evaluee_ready_tick else 0)
		if (opponent.state_interruptable or opponent.dummy_interruptable or opponent.state_hit_cancellable) and opponent_ready_tick == null:
			opponent_ready_tick = opponent_tick
			
			# Ready if true, inturrupt if false:
			# evaluee.current_state().anim_length == evaluee.current_state().current_tick + 1 or evaluee.current_state().iasa_at == evaluee.current_state().current_tick
			if (evaluee.current_state().interruptible_on_opponent_turn or evaluee.feinting or ghost_game.negative_on_hit(evaluee)) and evaluee_ready_tick == null:
				evaluee_ready_tick = current_frame
		if opponent_ready_tick != null and evaluee_ready_tick != null:
			break

	if evaluee_ready_tick == null:
		evaluee_ready_tick = FRAMES_TO_SIMULATE
	if opponent_ready_tick == null:
		opponent_ready_tick = FRAMES_TO_SIMULATE
	
	var frame_advantage = opponent_ready_tick - evaluee_ready_tick
	# Adjust for busy_interrupt states - busy characters are effectively slower
	if evaluee.busy_interrupt and not opponent.busy_interrupt:
		frame_advantage -= 8
	elif opponent.busy_interrupt and not evaluee.busy_interrupt:
		frame_advantage += 8
	var damage_dealt = opponent_start_hp - opponent.hp
	var damage_taken = evaluee_start_hp - evaluee.hp
	
	
	var evaluee_state = evaluee.state_machine.get_state(action)
	var feint = false
	if evaluee_state:
		
		if evaluee.feints > 0 and evaluee_state.can_feint() and frame_advantage < 0:
			feint = true
			if damage_dealt > damage_taken:
				frame_advantage = 0
	
	var eval = (
		(frame_advantage * FRAME_ADVANTAGE_MODIFIER) +
		(damage_dealt * DAMAGE_MODIFIER) -
		(damage_taken * DAMAGE_TAKEN_PENALTY)
	)

	eval += _combo_state_score(evaluee, opponent, evaluee_ready_tick, opponent_ready_tick)

	return {
		"eval":eval,
		"feint":feint,
		"frame_advantage":frame_advantage,
		"damage_dealt":damage_dealt,
		"damage_taken":damage_taken,
		"combo_state":evaluee.combo_count > 0,
		"was_blocked":false,
		"was_parried":evaluee.got_parried,
		"whiff_cancel_used":evaluee.current_state() != null and evaluee.current_state().state_name == "WhiffInstantCancel",
		"resources_after":_fighter_resources_snapshot(evaluee),
		"valid":true,
		"frames_simulated":frames_simulated
	}
		

# Returns the frame at which you should block to parry a given move.
# ID is of the blocking player.
func get_block_data(opponent_action, opponent_data, id):
	setup_ghost_game()
	
	var evaluee = ghost_game.get_player(id)
	var opponent = evaluee.opponent

	opponent.is_ghost = true
	opponent.queued_action = opponent_action
	opponent.queued_data = opponent_data
	opponent.queued_extra = null
	
	evaluee.queued_action = "ParryHigh"
	evaluee.queued_data = {"Block Height":{"y":0}, "Melee Parry Timing":{"count":19}}
	evaluee.queued_extra = null
	evaluee.is_ghost = true
	
	var tick = 0
	# If the move doesn't hit, only go for 20 frames then return a default of 4
	while evaluee.ghost_blocked_melee_attack == -1 and tick < 20: 
		ghost_game.simulate_one_tick()
		tick += 1
	
	return {"Block Height":{"y":1 if evaluee.ghost_wrong_block == "Low" else 0}, "Melee Parry Timing":{"count":evaluee.ghost_blocked_melee_attack if evaluee.ghost_blocked_melee_attack != -1 else 4}}

func _combo_state_score(player, opponent, player_ready_tick, opponent_ready_tick) -> float:
	var score = 0.0
	var player_is_hurt = _is_hurt_state(player)
	if opponent.combo_count > 0:
		score -= COMBOED_PENALTY + (opponent.combo_count * COMBOED_COUNT_PENALTY)
		if opponent.get("combo_damage") != null:
			score -= opponent.combo_damage * 2
	if player_is_hurt:
		score -= HURT_STATE_PENALTY
	if player_is_hurt or opponent.combo_count > 0:
		var player_ready = player_ready_tick if player_ready_tick != null else FRAMES_TO_SIMULATE
		var opponent_ready = opponent_ready_tick if opponent_ready_tick != null else FRAMES_TO_SIMULATE
		score -= max(player_ready - opponent_ready, 0) * VULNERABLE_FRAME_PENALTY
	if player.combo_count > 0:
		score += COMBO_REWARD + (player.combo_count * COMBO_COUNT_REWARD)
		if player.get("combo_damage") != null:
			score += player.combo_damage
	return score

func _is_hurt_state(fighter) -> bool:
	var state = fighter.current_state()
	if state == null:
		return false
	if state.get("is_hurt_state") != null and state.get("is_hurt_state"):
		return true
	var state_name = state.get("state_name") if state.get("state_name") != null else ""
	return "Hurt" in state_name


func _is_hurt_or_grabbed_state(fighter) -> bool:
	if fighter == null:
		return false
	if _is_hurt_state(fighter):
		return true
	var state = fighter.current_state()
	if state == null:
		return false
	var state_name = state.get("state_name") if state.get("state_name") != null else ""
	return "Grabbed" in state_name


func _is_ai_locked_cancel_state(fighter) -> bool:
	if fighter == null:
		return false
	var state = fighter.current_state()
	if state == null:
		return false
	var state_name = state.get("state_name") if state.get("state_name") != null else ""
	return state_name == "WhiffInstantCancel" or state_name == "InstantCancel"


func _state_commitment_frames(fighter) -> int:
	if fighter.state_interruptable:
		return 0
	var state = fighter.current_state()
	if state == null:
		return 0
	var current_tick = state.get("current_tick") if state.get("current_tick") != null else 0
	var remaining = 0
	if state.get("iasa_at") != null and state.get("iasa_at") > current_tick:
		remaining = max(remaining, state.get("iasa_at") - current_tick)
	if state.get("anim_length") != null and state.get("anim_length") > current_tick:
		remaining = max(remaining, state.get("anim_length") - current_tick)
	return remaining

func _state_is_attack_threat(fighter) -> bool:
	var state = fighter.current_state()
	if state == null:
		return false
	if state.get("type") != null:
		var state_type = state.get("type")
		if state_type == 1 or state_type == 2:
			return true
	if state.get("hit_yet") != null and state.get("hit_yet"):
		return true
	if state.get("earliest_hitbox") != null:
		return true
	return false

func _state_should_penalize_commitment(fighter) -> bool:
	var state = fighter.current_state()
	if state == null:
		return false
	if state.get("interruptible_on_opponent_turn") != null and state.get("interruptible_on_opponent_turn"):
		return false
	if state.get("type") == null:
		return _state_is_attack_threat(fighter)
	var state_type = state.get("type")
	return state_type == 3 or state_type == 1 or state_type == 2


func get_adjusted_search_depth() -> int:
	return int(max(0, configured_search_depth))


func _continue_move() -> Dictionary:
	return {"action":"Continue", "data":null, "eval":0, "feint":false}


func _sort_by_eval_desc(a, b):
	return a.eval > b.eval


func _sort_by_order_desc(a, b):
	var a_score = a.order_score if a.has("order_score") else a.eval
	var b_score = b.order_score if b.has("order_score") else b.eval
	if a_score == b_score:
		return a.eval > b.eval
	return a_score > b_score


func _is_cancel_action_name(action_name:String) -> bool:
	return action_name == "WhiffInstantCancel" or action_name == "InstantCancel" or action_name == "Cancel" or action_name.find("Cancel") != -1


func _candidate_style_score(action_name:String, candidate_state, branch_label:String="") -> float:
	# Style bias intentionally disabled: move choice should come from simulated outcomes only.
	return 0.0


func _move_key(move:Dictionary) -> String:
	return str(move.action) + "|" + str(move.data)


func _same_move(a:Dictionary, b:Dictionary) -> bool:
	return _move_key(a) == _move_key(b)


func _append_unique_move(result:Array, move:Dictionary) -> void:
	for existing in result:
		if _same_move(existing, move):
			return
	result.append(move)


func _without_continue_moves(moves:Array) -> Array:
	var result = []
	for move in moves:
		if move.action != "Continue":
			result.append(move)
	return result


func _ensure_move_list(moves:Array) -> Array:
	var active_moves = _without_continue_moves(moves)
	if !active_moves.empty():
		return active_moves
	if moves.empty():
		return [_continue_move()]
	return moves


func prepare_real_search(my_id:int, depth:int) -> void:
	ensure_search_ghosts(depth)
	copy_game_state(game, ghost_base)
	search_start_hp.clear()
	var player = ghost_base.get_player(my_id)
	var opponent = ghost_base.get_player(player.opponent.id)
	search_start_hp[player.id] = player.hp
	search_start_hp[opponent.id] = opponent.hp
	search_start_distance = sqrt(pow(opponent.get_pos().x - player.get_pos().x, 2) + pow(opponent.get_pos().y - player.get_pos().y, 2))


func ensure_search_ghosts(depth:int) -> void:
	if ghost_base == null or not is_instance_valid(ghost_base):
		ghost_base = make_search_ghost()
	if ghost_eval == null or not is_instance_valid(ghost_eval):
		ghost_eval = make_search_ghost()
	while search_snapshots.size() <= depth:
		search_snapshots.append(make_search_ghost())
	for index in range(search_snapshots.size()):
		if search_snapshots[index] == null or not is_instance_valid(search_snapshots[index]):
			search_snapshots[index] = make_search_ghost()


func make_search_ghost():
	if gg_scene == null:
		gg_scene = load("res://Game.tscn")
	if ghost_viewport == null:
		ghost_viewport = main.find_node("GhostViewport")
	var search_game = gg_scene.instance()
	if multihustle:
		search_game.set_script(Global.current_game.get_script())
		search_game.multiHustle_CharManager = Global.current_game.multiHustle_CharManager
	search_game.is_ghost = true
	search_game.visible = false
	ghost_viewport.add_child(search_game)
	search_game.start_game(true, main.match_data)
	search_game.ghost_speed = 100
	search_game.ghost_freeze = false
	if search_game.get("ai_skip_show_state") != null:
		search_game.ai_skip_show_state = true
	return search_game


func copy_game_state(source, target) -> void:
	reset_search_game_runtime(target)
	if experimental_speedup and source.has_method("fast_copy_to"):
		source.fast_copy_to(target)
	else:
		source.copy_to(target)


func reset_search_game_runtime(search_game) -> void:
	if search_game == null or not is_instance_valid(search_game):
		return
	search_game.visible = false
	search_game.is_ghost = true
	search_game.is_afterimage = false
	search_game.ghost_hidden = false
	search_game.ghost_speed = 100
	search_game.ghost_tick = 0
	search_game.ghost_freeze = false
	if search_game.get("ai_skip_show_state") != null:
		search_game.ai_skip_show_state = true
	search_game.ghost_simulated_ticks = 0
	search_game.ghost_actionable_freeze_ticks = 0
	search_game.ghost_p1_actionable = false
	search_game.ghost_p2_actionable = false
	search_game.p1_ghost_ready_tick = null
	search_game.p2_ghost_ready_tick = null
	search_game.current_tick = -1
	search_game.real_tick = 0
	search_game.max_replay_tick = 0
	search_game.game_end_tick = 0
	search_game.frame_passed = false
	search_game.game_finished = false
	search_game.parry_freeze = false
	search_game.game_paused = false
	search_game.buffer_playback = false
	search_game.buffer_edit = false
	search_game.forfeit = false
	search_game.forfeit_player = null
	search_game.quitter_focus = false
	search_game.quitter_focus_ticks = 0
	search_game.advance_frame_input = false
	search_game.network_simulate_ready = true
	search_game.simulated_once = false
	search_game.super_freeze_ticks = 0
	search_game.super_active = false
	search_game.prediction_effect = false
	search_game.p1_super = false
	search_game.p2_super = false
	search_game.hit_freeze = false
	search_game.player_actionable = false
	search_game.p1_turn = false
	search_game.p2_turn = false
	search_game.made_afterimage = false
	if search_game.p1 != null and search_game.p2 != null:
		reset_ghost_player_runtime(search_game.p1, search_game.p2)
		reset_ghost_player_runtime(search_game.p2, search_game.p1)


func snapshot_base(depth:int) -> void:
	copy_game_state(ghost_base, search_snapshots[depth])


func restore_base(depth:int) -> void:
	copy_game_state(search_snapshots[depth], ghost_base)


func _make_extra_for_player(game_state, player_id:int, base_extra:Dictionary) -> Dictionary:
	var player = game_state.get_player(player_id)
	var opponent = game_state.get_player(player.opponent.id)
	var player_pos = player.get_pos()
	var opponent_pos = opponent.get_pos()
	var di = di_as_percentage_int_vec(Vector2(player_pos.x - opponent_pos.x, player_pos.y - opponent_pos.y).normalized())
	return {
		"DI": di,
		"feint": base_extra.feint if base_extra.has("feint") else false,
		"prediction": base_extra.prediction if base_extra.has("prediction") else -1,
		"reverse": base_extra.reverse if base_extra.has("reverse") else false,
	}


func _queue_search_action(fighter, action, data, extra) -> void:
	fighter.is_ghost = true
	fighter.queued_action = action
	fighter.queued_data = data
	fighter.queued_extra = extra
	fighter.state_interruptable = false
	fighter.dummy_interruptable = false
	fighter.state_hit_cancellable = false
	fighter.busy_interrupt = false


func _prepare_search_rollout(search_game) -> void:
	search_game.p1_turn = false
	search_game.p2_turn = false
	search_game.game_paused = false
	search_game.player_actionable = false


func _fighter_can_prompt(fighter) -> bool:
	return fighter.state_interruptable or fighter.dummy_interruptable or fighter.state_hit_cancellable


func _fighter_waiting_for_turn(fighter) -> bool:
	return fighter.state_interruptable or fighter.dummy_interruptable


func _apply_ghost_waiting_turn_rules(search_game) -> void:
	var p1 = search_game.p1
	var p2 = search_game.p2
	if p1.state_interruptable and !search_game.p1_turn:
		p2.busy_interrupt = (!p2.state_interruptable and !(p2.current_state().interruptible_on_opponent_turn or p2.feinting or search_game.negative_on_hit(p2)))
		if !p2.busy_interrupt:
			p2.current_state().on_interrupt()
		p2.state_interruptable = true
		search_game.p1_turn = true
	elif p2.state_interruptable and !search_game.p2_turn:
		p1.busy_interrupt = (!p1.state_interruptable and !(p1.current_state().interruptible_on_opponent_turn or p1.feinting or search_game.negative_on_hit(p1)))
		if !p1.busy_interrupt:
			p1.current_state().on_interrupt()
		p1.state_interruptable = true
		search_game.p2_turn = true


func _simulate_until_search_decision(search_game, perspective_id:int) -> Dictionary:
	var ready_ticks = {}
	var ticks = 0
	while ticks < FRAMES_TO_SIMULATE:
		search_ghost_simulations += 1
		search_game.simulate_one_tick()
		ticks += 1
		for player_id in [1, 2]:
			var player = search_game.get_player(player_id)
			if _fighter_can_prompt(player) and !ready_ticks.has(player_id):
				ready_ticks[player_id] = ticks + (player.hitlag_ticks if !ready_ticks.has(player.opponent.id) else 0)
		if search_game.should_game_end():
			break
		if _fighter_waiting_for_turn(search_game.p1) or _fighter_waiting_for_turn(search_game.p2):
			_apply_ghost_waiting_turn_rules(search_game)
			for player_id in [1, 2]:
				var player = search_game.get_player(player_id)
				if _fighter_can_prompt(player) and !ready_ticks.has(player_id):
					ready_ticks[player_id] = ticks + (player.hitlag_ticks if !ready_ticks.has(player.opponent.id) else 0)
			if _fighter_waiting_for_turn(search_game.p1) and _fighter_waiting_for_turn(search_game.p2):
				break
	if !ready_ticks.has(perspective_id):
		ready_ticks[perspective_id] = FRAMES_TO_SIMULATE
	var perspective = search_game.get_player(perspective_id)
	if !ready_ticks.has(perspective.opponent.id):
		ready_ticks[perspective.opponent.id] = FRAMES_TO_SIMULATE
	return {"ticks":ticks, "ready_ticks":ready_ticks}


func _evaluate_game_state(search_game, my_id:int, rollout:Dictionary = {}) -> float:
	var player = search_game.get_player(my_id)
	var opponent = search_game.get_player(player.opponent.id)
	var player_start_hp = search_start_hp[player.id] if search_start_hp.has(player.id) else player.hp
	var opponent_start_hp = search_start_hp[opponent.id] if search_start_hp.has(opponent.id) else opponent.hp
	var damage_dealt = opponent_start_hp - opponent.hp
	var damage_taken = player_start_hp - player.hp
	var player_ready = FRAMES_TO_SIMULATE
	var opponent_ready = FRAMES_TO_SIMULATE
	if rollout.has("ready_ticks"):
		var ready_ticks = rollout.ready_ticks
		player_ready = ready_ticks[player.id] if ready_ticks.has(player.id) else FRAMES_TO_SIMULATE
		opponent_ready = ready_ticks[opponent.id] if ready_ticks.has(opponent.id) else FRAMES_TO_SIMULATE
	var frame_advantage = opponent_ready - player_ready
	if player.busy_interrupt and !opponent.busy_interrupt:
		frame_advantage -= 8
	elif opponent.busy_interrupt and !player.busy_interrupt:
		frame_advantage += 8
	return (
		(frame_advantage * FRAME_ADVANTAGE_MODIFIER) +
		(damage_dealt * DAMAGE_MODIFIER) -
		(damage_taken * DAMAGE_TAKEN_PENALTY) +
		_combo_state_score(player, opponent, player_ready, opponent_ready)
	)


func _evaluate_search_state(my_id:int, rollout:Dictionary = {}) -> float:
	return _evaluate_game_state(ghost_base, my_id, rollout)


func _fighter_resources_snapshot(fighter) -> Dictionary:
	if fighter == null:
		return {}
	return {
		"burst_meter": fighter.burst_meter if fighter.get("burst_meter") != null else 0,
		"bursts_available": fighter.bursts_available if fighter.get("bursts_available") != null else 0,
		"super_meter": fighter.super_meter if fighter.get("super_meter") != null else 0,
		"supers_available": fighter.supers_available if fighter.get("supers_available") != null else 0,
		"total_super_meter": fighter.get_total_super_meter() if fighter.has_method("get_total_super_meter") else (fighter.super_meter if fighter.get("super_meter") != null else 0),
		"air_movements": fighter.air_movements_left if fighter.get("air_movements_left") != null else 0
	}


func _state_stack_names(fighter) -> Array:
	var result = []
	if fighter == null or fighter.state_machine == null:
		return result
	for state in fighter.state_machine.states_stack:
		result.append(_state_display_name(state))
	return result


func _fighter_state_snapshot(fighter) -> Dictionary:
	if fighter == null:
		return {}
	var pos = fighter.get_pos()
	var previous = _previous_state_for_fighter(fighter)
	return {
		"id": fighter.id if fighter.get("id") != null else 0,
		"hp": fighter.hp if fighter.get("hp") != null else 0,
		"position": {"x": pos.x, "y": pos.y},
		"facing": fighter.get_facing_int() if fighter.has_method("get_facing_int") else 0,
		"current_state": _state_display_name(fighter.current_state()),
		"previous_state": _state_display_name(previous),
		"states_stack": _state_stack_names(fighter),
		"combo_count": fighter.combo_count if fighter.get("combo_count") != null else 0,
		"burst_meter": fighter.burst_meter if fighter.get("burst_meter") != null else 0,
		"bursts_available": fighter.bursts_available if fighter.get("bursts_available") != null else 0,
		"super_meter": fighter.super_meter if fighter.get("super_meter") != null else 0,
		"air_movements_left": fighter.air_movements_left if fighter.get("air_movements_left") != null else 0,
		"hitlag_ticks": fighter.hitlag_ticks if fighter.get("hitlag_ticks") != null else 0,
		"blockstun_ticks": fighter.blockstun_ticks if fighter.get("blockstun_ticks") != null else 0,
		"busy_interrupt": fighter.busy_interrupt if fighter.get("busy_interrupt") != null else false,
		"state_interruptable": fighter.state_interruptable if fighter.get("state_interruptable") != null else false,
		"initiative": fighter.initiative if fighter.get("initiative") != null else false,
		"got_parried": fighter.got_parried if fighter.get("got_parried") != null else false,
		"got_blocked": fighter.got_blocked if fighter.get("got_blocked") != null else false
	}


func whose_turn(player, opponent) -> int:
	if player == null or opponent == null:
		return 0
	if player.combo_count > 0:
		return player.id
	if opponent.combo_count > 0:
		return opponent.id
	if player.busy_interrupt and !opponent.busy_interrupt:
		return opponent.id
	if opponent.busy_interrupt and !player.busy_interrupt:
		return player.id
	var player_tick = player.lowest_tick if player.get("lowest_tick") != null and player.lowest_tick != null else 999999
	var opponent_tick = opponent.lowest_tick if opponent.get("lowest_tick") != null and opponent.lowest_tick != null else 999999
	return player.id if player_tick <= opponent_tick else opponent.id


func _game_state_snapshot(game_state) -> Dictionary:
	if game_state == null:
		return {}
	var p1 = game_state.get_player(1) if game_state.has_method("get_player") else game_state.p1
	var p2 = game_state.get_player(2) if game_state.has_method("get_player") else game_state.p2
	if p1 == null or p2 == null:
		return {}
	return {
		"p1_hp": p1.hp,
		"p2_hp": p2.hp,
		"p1_burst": p1.burst_meter,
		"p2_burst": p2.burst_meter,
		"p1_super": p1.super_meter,
		"p2_super": p2.super_meter,
		"p1_combo": p1.combo_count,
		"p2_combo": p2.combo_count,
		"tick": game_state.current_tick if game_state.get("current_tick") != null else 0,
		"turn_ownership": whose_turn(p1, p2),
		"players": [_fighter_state_snapshot(p1), _fighter_state_snapshot(p2)]
	}


func _json_safe(value):
	if value is Vector2:
		return {"x": value.x, "y": value.y}
	if value is Dictionary:
		var result = {}
		for key in value.keys():
			result[str(key)] = _json_safe(value[key])
		return result
	if value is Array:
		var result_array = []
		for item in value:
			result_array.append(_json_safe(item))
		return result_array
	if value is Object:
		return str(value)
	return value


func _read_strength_name() -> String:
	if read_strength <= 20:
		return "Very Safe"
	if read_strength <= 40:
		return "Cautious"
	if read_strength <= 60:
		return "Balanced"
	if read_strength <= 80:
		return "Read Heavy"
	return "Hard Read"


func _count_tree_nodes(node) -> int:
	if !(node is Dictionary):
		return 0
	var total = 1
	if node.has("moves"):
		for move in node.moves:
			total += _count_tree_nodes(move)
	if node.has("children"):
		for child in node.children:
			total += _count_tree_nodes(child)
	return total


func export_search_tree(decision_started_ms:int, search_depth:int, choice:Dictionary) -> void:
	var profile_export_total = _profile_now()
	var decision_ms = OS.get_ticks_msec() - decision_started_ms
	log_info("Decision " + str(choice.action) + " score=" + str(choice.eval if choice.has("eval") else 0) + " ms=" + str(decision_ms) + " evaluated=" + str(search_moves_evaluated) + " pruned=" + str(search_moves_pruned))
	if !_search_tree_output_enabled():
		_profile_add("export.total", profile_export_total)
		_profile_print_summary()
		return
	var profile_count_tree = _profile_now()
	search_tree["total_nodes"] = _count_tree_nodes(search_tree)
	_profile_add("export.count_tree_nodes", profile_count_tree)
	var profile_build_output = _profile_now()
	var output = {
		"version": 1,
		"turn": game.current_tick if game != null and game.get("current_tick") != null else 0,
		"tick": game.get_ticks_left() if game != null and game.has_method("get_ticks_left") else 0,
		"player_id": id,
		"decision_ms": decision_ms,
		"configured_depth": configured_search_depth,
		"read_strength": read_strength,
		"read_profile": _read_strength_name(),
		"search_depth": search_depth,
		"prune_percent_root": PRUNE_PERCENT,
		"game_state": _game_state_snapshot(game),
		"moves_evaluated": search_moves_evaluated,
		"moves_pruned": search_moves_pruned,
		"prune_reason": _search_move_prune_reason(),
		"tree": search_tree,
		"warnings": search_warnings,
		"metadata": {
			"ghost_simulations": search_ghost_simulations,
			"frame_time_ms": float(decision_ms) / max(search_ghost_simulations, 1),
			"engine": "godot3",
			"profile": search_profile
		}
	}
	_profile_add("export.build_output", profile_build_output)
	if SEARCH_TREE_EXPORT_ENABLED:
		var file = File.new()
		var profile_file = _profile_now()
		var err = file.open(SEARCH_TREE_OUTPUT_PATH, File.WRITE)
		if err == OK:
			file.store_string(JSON.print(_json_safe(output), "\t"))
			file.close()
		else:
			log_warn("could not write search tree to " + SEARCH_TREE_OUTPUT_PATH + " error=" + str(err))
		_profile_add("export.write_file", profile_file)
	if SEARCH_TREE_PRINT_JSON:
		var profile_print = _profile_now()
		print(JSON.print(_json_safe(output)))
		_profile_add("export.print_json", profile_print)
	_profile_add("export.total", profile_export_total)
	_profile_print_summary()


func _simulate_pair_on_eval(player_id:int, our_move:Dictionary, opponent_move:Dictionary, extra:Dictionary) -> Dictionary:
	_prepare_search_rollout(ghost_eval)
	var us = ghost_eval.get_player(player_id)
	var opponent = ghost_eval.get_player(us.opponent.id)
	_queue_search_action(us, our_move.action, our_move.data, _make_extra_for_player(ghost_eval, us.id, extra))
	_queue_search_action(opponent, opponent_move.action, opponent_move.data, _make_extra_for_player(ghost_eval, opponent.id, extra))
	return _simulate_until_search_decision(ghost_eval, player_id)


func _advance_pair_on_base(my_id:int, our_move:Dictionary, opponent_move:Dictionary, extra:Dictionary) -> Dictionary:
	copy_game_state(ghost_base, ghost_eval)
	var rollout = _simulate_pair_on_eval(my_id, our_move, opponent_move, extra)
	copy_game_state(ghost_eval, ghost_base)
	return rollout


func _is_combo_breaker_action(action_name:String) -> bool:
	return "Burst" in action_name or action_name == "CounterAttack"


func _is_ignored_action(action_name:String) -> bool:
	if _is_combo_breaker_action(action_name):
		return false
	return action_name in states_to_ignore or "StrikeAPose" in action_name or "StrikeA_Pose" in action_name


func _state_display_name(state) -> String:
	if state == null:
		return ""
	if state is Node:
		if state.get("state_name") != null:
			return str(state.state_name)
		return state.name
	return str(state)


func _previous_state_for_fighter(fighter):
	if fighter == null:
		return null
	if fighter.has_method("previous_state"):
		var previous = fighter.previous_state()
		if previous != null:
			return previous
	if fighter.state_machine != null and fighter.state_machine.states_stack.size() > 1:
		return fighter.state_machine.states_stack[-2]
	return null


func can_use_whiff_cancel(fighter) -> Dictionary:
	if fighter.got_parried or fighter.got_blocked:
		return {
			"valid": false,
			"warning_type": "invalid_whiff_cancel_contact",
			"reason": "fighter was parried or blocked"
		}
	var max_burst = fighter.MAX_BURST_METER if fighter.get("MAX_BURST_METER") != null else 1500
	var has_meter = fighter.bursts_available > 0 or fighter.burst_meter >= int(max_burst * 0.75)
	if !has_meter:
		return {
			"valid": false,
			"warning_type": "invalid_whiff_cancel_meter",
			"reason": "burst meter below 75 percent and no burst available"
		}
	return {"valid": true, "warning_type": "", "reason": ""}


func check_move_validity(action_name:String, fighter) -> Dictionary:
	if action_name == "WhiffInstantCancel":
		return can_use_whiff_cancel(fighter)
	return {"valid": true, "warning_type": "", "reason": ""}


func _record_search_warning(warning_type:String, action_name:String, reason:String) -> void:
	var warning = {
		"type": warning_type,
		"action": action_name,
		"reason": reason
	}
	for existing in search_warnings:
		if existing.type == warning.type and existing.action == warning.action and existing.reason == warning.reason:
			return
	search_warnings.append(warning)
	log_warn(action_name + ": " + reason)


func _search_force_grounded(extra) -> bool:
	if extra != null and extra is Dictionary and extra.has("input_grounded"):
		return extra.input_grounded
	return false


func _search_force_aerial(extra) -> bool:
	if extra != null and extra is Dictionary and extra.has("input_aerial"):
		return extra.input_aerial
	return false


func _search_update_cancel_category_air_type(categories:Array, force_grounded:bool, force_aerial:bool) -> void:
	for i in range(categories.size()):
		if force_grounded:
			categories[i] = categories[i].replace("Aerial", "Grounded")
		if force_aerial:
			categories[i] = categories[i].replace("Grounded", "Aerial")


func _can_fighter_cancel_to_state(fighter, candidate, extra=null) -> bool:
	if candidate != null and candidate.state_name == "WhiffInstantCancel":
		var validity = can_use_whiff_cancel(fighter)
		if !validity.valid:
			_record_search_warning(validity.warning_type, "WhiffInstantCancel", validity.reason)
			return false
	var state = fighter.current_state()
	if state == null:
		return false
	var cancel_into = _search_cancel_categories(fighter, extra)
	var force_aerial = _search_force_aerial(extra)
	var force_grounded = _search_force_grounded(extra)
	for category in cancel_into:
		if !fighter.action_cancels.has(category):
			continue
		for cancel_state in fighter.action_cancels[category]:
			if cancel_state.state_name != candidate.state_name:
				continue
			if !cancel_state.is_usable_with_grounded_check(force_aerial, force_grounded) or !cancel_state.allowed_in_stance():
				continue
			if cancel_state.state_name == state.state_name:
				if fighter.state_hit_cancellable and !state.self_hit_cancellable and !fighter.turbo_mode:
					continue
				elif !fighter.state_hit_cancellable and !state.self_interruptable and !fighter.turbo_mode:
					continue
			if fighter.state_hit_cancellable and cancel_state.state_name in state.hit_cancel_exceptions:
				continue
			elif fighter.state_interruptable and cancel_state.state_name in state.interrupt_exceptions:
				continue
			var excepted = false
			if fighter.state_hit_cancellable:
				for c in state.hit_cancel_exceptions:
					if c in cancel_state.interrupt_from:
						excepted = true
			if !excepted and fighter.state_interruptable:
				for c in state.interrupt_exceptions:
					if c in cancel_state.interrupt_from:
						excepted = true
			if excepted:
				continue
			return true
	return false


func _search_cancel_categories(fighter, extra=null) -> Array:
	var state = fighter.current_state()
	if state == null:
		return []
	var cancel_into = []
	if !fighter.busy_interrupt:
		cancel_into = (state.interrupt_into if !fighter.state_hit_cancellable else state.hit_cancel_into).duplicate(true)
		if fighter.turbo_mode and fighter.opponent.current_state().state_name != "Grabbed":
			cancel_into.append("Grounded" if fighter.is_grounded() else "Aerial")
		if fighter.feinting and fighter.should_free_cancel_allow_grounded_and_aerial_states() and fighter.opponent.current_state().busy_interrupt_type != CharacterState.BusyInterrupt.Hurt:
			cancel_into.append("Grounded")
			cancel_into.append("Aerial")
	else:
		cancel_into = state.busy_interrupt_into.duplicate(true)
	_search_update_cancel_category_air_type(cancel_into, _search_force_grounded(extra), _search_force_aerial(extra))
	return cancel_into


func _search_cancel_state_is_legal(fighter, state, cancel_state, extra=null) -> bool:
	if cancel_state == null:
		return false
	if cancel_state.state_name == "WhiffInstantCancel":
		var validity = can_use_whiff_cancel(fighter)
		if !validity.valid:
			_record_search_warning(validity.warning_type, "WhiffInstantCancel", validity.reason)
			return false
	if !cancel_state.is_usable_with_grounded_check(_search_force_aerial(extra), _search_force_grounded(extra)) or !cancel_state.allowed_in_stance():
		return false
	if cancel_state.state_name == state.state_name:
		if fighter.state_hit_cancellable and !state.self_hit_cancellable and !fighter.turbo_mode:
			return false
		elif !fighter.state_hit_cancellable and !state.self_interruptable and !fighter.turbo_mode:
			return false
	if fighter.state_hit_cancellable and cancel_state.state_name in state.hit_cancel_exceptions:
		return false
	elif fighter.state_interruptable and cancel_state.state_name in state.interrupt_exceptions:
		return false
	var excepted = false
	if fighter.state_hit_cancellable:
		for c in state.hit_cancel_exceptions:
			if c in cancel_state.interrupt_from:
				excepted = true
	if !excepted and fighter.state_interruptable:
		for c in state.interrupt_exceptions:
			if c in cancel_state.interrupt_from:
				excepted = true
	return !excepted


func _is_state_candidate_for_search(candidate) -> bool:
	if candidate == null:
		return false
	if candidate.get("state_name") == null:
		return false
	if hidden_ai_actions.has(candidate.state_name):
		return false
	if candidate.get("show_in_menu") != null and !candidate.show_in_menu:
		return false
	if candidate.get("selectable") != null and !candidate.selectable:
		return false
	if _is_ignored_action(candidate.state_name):
		return false
	return true


func _candidate_allowed_while_hurt_or_grabbed(evaluee, candidate) -> bool:
	if !_is_hurt_or_grabbed_state(evaluee):
		return true
	return _is_combo_breaker_action(candidate.state_name)


func _candidate_allowed_from_current_ai_state(evaluee, candidate) -> bool:
	if _is_ai_locked_cancel_state(evaluee):
		return false
	return _candidate_allowed_while_hurt_or_grabbed(evaluee, candidate)


func _search_candidate_key(candidate:Dictionary) -> String:
	return str(candidate.action_name)


func _append_unique_search_candidate(candidates:Array, candidate:Dictionary) -> void:
	var key = _search_candidate_key(candidate)
	for existing in candidates:
		if _search_candidate_key(existing) == key:
			return
	candidates.append(candidate)


func _has_visible_non_continue_actions(fighter, extra=null) -> bool:
	if fighter == null:
		return false
	for candidate in get_search_candidates(fighter, extra):
		if candidate.action_name != "Continue":
			return true
	return false


func get_search_candidates(evaluee, extra=null) -> Array:
	var candidates = [{"action_name":"Continue", "state":null}]
	if evaluee == null or evaluee.state_machine == null:
		return candidates
	var state = evaluee.current_state()
	if state == null:
		return candidates
	var cancel_categories = _search_cancel_categories(evaluee, extra)
	var scanned = 0
	# Mirror the live action UI: only consider states that are currently reachable
	# through the fighter's active cancel categories. Falling back to states_map lets
	# the AI discover internal/non-visible states such as hidden cancel actions.
	for category in cancel_categories:
		if !evaluee.action_cancels.has(category):
			continue
		for candidate in evaluee.action_cancels[category]:
			scanned += 1
			if !_is_state_candidate_for_search(candidate):
				continue
			if !_candidate_allowed_from_current_ai_state(evaluee, candidate):
				continue
			if !_search_cancel_state_is_legal(evaluee, state, candidate, extra):
				continue
			_append_unique_search_candidate(candidates, {"action_name":candidate.state_name, "state":candidate})
	if candidates.size() <= 1:
		log_warn("[SEARCH_MOVES] p" + str(evaluee.id) + " only has UI-visible Continue from state=" + _state_display_name(state) + " categories=[" + ", ".join(cancel_categories) + "] action_cancel_scan=" + str(scanned) + " action_cancel_keys=" + str(evaluee.action_cancels.keys()))
	return candidates


func _normalize_search_data(action_name:String, data):
	if data is String and data == "Parry":
		return {"Block Height":{"y":0}, "Melee Parry Timing":{"count":4}}
	return data


func _direction_sign(value:float) -> int:
	if value > 0:
		return 1
	if value < 0:
		return -1
	return 0


func _append_directional_x_values(value, result:Array) -> void:
	if value is Vector2:
		result.append(value.x)
	elif value is Dictionary:
		if value.has("x") and (typeof(value.x) == TYPE_INT or typeof(value.x) == TYPE_REAL):
			result.append(float(value.x))
		for key in value.keys():
			var nested = value[key]
			if nested is Dictionary or nested is Array or nested is Vector2:
				_append_directional_x_values(nested, result)
	elif value is Array:
		for item in value:
			if item is Dictionary or item is Array or item is Vector2:
				_append_directional_x_values(item, result)


func _candidate_uses_attack_vector_filter(action_name:String, candidate_state) -> bool:
	if candidate_state == null:
		return false
	if _is_combo_breaker_action(action_name):
		return false
	if candidate_state.get("type") == null:
		return false
	return candidate_state.type == 1 or candidate_state.type == 2 or candidate_state.type == 3


func _filter_attack_vectors_facing_opponent(action_name:String, candidate_state, temp_data:Array, fighter) -> Array:
	if !_candidate_uses_attack_vector_filter(action_name, candidate_state):
		return temp_data
	var has_positive = false
	var has_negative = false
	for data in temp_data:
		var xs = []
		_append_directional_x_values(data, xs)
		for x in xs:
			var dir_sign = _direction_sign(float(x))
			has_positive = has_positive or dir_sign > 0
			has_negative = has_negative or dir_sign < 0
	if !has_positive or !has_negative:
		return temp_data
	var opponent_dir = fighter.get_opponent_dir() if fighter.has_method("get_opponent_dir") else fighter.get_facing_int()
	var filtered = []
	for data in temp_data:
		var xs = []
		_append_directional_x_values(data, xs)
		var keep = true
		for x in xs:
			var dir_sign = _direction_sign(float(x))
			if dir_sign != 0 and dir_sign != opponent_dir:
				keep = false
				break
		if keep:
			filtered.append(data)
	return filtered if !filtered.empty() else temp_data


func _keep_count_for_move_count(move_count:int, prune_percent:float) -> int:
	if move_count <= 0:
		return 0
	return int(clamp(ceil(move_count * prune_percent), 1, move_count))


func _apply_branch_cap(keep_count:int, move_count:int, branch_cap:int) -> int:
	if move_count <= 0:
		return 0
	if branch_cap <= 0:
		return keep_count
	return int(clamp(min(keep_count, branch_cap), 1, move_count))


func _search_move_prune_reason() -> String:
	return "bottom_" + str(int(round((1.0 - PRUNE_PERCENT) * 100.0))) + "_percent_by_score"


func _frame_advantage_from_rollout(search_game, perspective_id:int, rollout:Dictionary) -> int:
	var perspective = search_game.get_player(perspective_id)
	var opponent = search_game.get_player(perspective.opponent.id)
	var ready_ticks = rollout.ready_ticks if rollout.has("ready_ticks") else {}
	var player_ready = ready_ticks[perspective.id] if ready_ticks.has(perspective.id) else FRAMES_TO_SIMULATE
	var opponent_ready = ready_ticks[opponent.id] if ready_ticks.has(opponent.id) else FRAMES_TO_SIMULATE
	var frame_advantage = opponent_ready - player_ready
	if perspective.busy_interrupt and !opponent.busy_interrupt:
		frame_advantage -= 8
	elif opponent.busy_interrupt and !perspective.busy_interrupt:
		frame_advantage += 8
	return frame_advantage


func _move_order_score(search_game, perspective_id:int, move:Dictionary, rollout:Dictionary, reply_to_move=null) -> float:
	var perspective = search_game.get_player(perspective_id)
	var opponent = search_game.get_player(perspective.opponent.id)
	var perspective_start_hp = search_start_hp[perspective.id] if search_start_hp.has(perspective.id) else perspective.hp
	var opponent_start_hp = search_start_hp[opponent.id] if search_start_hp.has(opponent.id) else opponent.hp
	var damage_dealt = opponent_start_hp - opponent.hp
	var damage_taken = perspective_start_hp - perspective.hp
	var frame_advantage = move.frame_advantage if move.has("frame_advantage") else _frame_advantage_from_rollout(search_game, perspective_id, rollout)
	var score = float(move.eval)
	var replying_to_attack = false
	if reply_to_move is Dictionary:
		replying_to_attack = reply_to_move.get("action", "Continue") != "Continue"
	
	if damage_dealt > 0:
		score += 1500.0 + (damage_dealt * 10.0)
	if perspective.combo_count > 0:
		score += 1600.0 + (perspective.combo_count * 180.0)
	if _is_hurt_or_grabbed_state(opponent):
		score += 1200.0
	if opponent.blockstun_ticks > 0 or perspective.got_blocked:
		score += 700.0 + (min(opponent.blockstun_ticks, FRAMES_TO_SIMULATE) * 30.0)
	
	if replying_to_attack:
		if damage_taken <= 0:
			score += 900.0
		if frame_advantage >= 0:
			score += 500.0
	if damage_taken > 0:
		score -= 1800.0 + (damage_taken * 24.0)
	if _is_hurt_or_grabbed_state(perspective):
		score -= 1600.0
	
	score += frame_advantage * 18.0
	return score


func _best_eval_move(moves:Array) -> Dictionary:
	if moves.empty():
		return _continue_move()
	var best = moves[0]
	for move in moves:
		if move.eval > best.eval:
			best = move
	return best


func _move_order_metric(move:Dictionary) -> float:
	return float(move.order_score if move.has("order_score") else move.eval)


func _reply_belief_profile(opponent_moves:Array, reply_scores:Array) -> Dictionary:
	if reply_scores.empty():
		return {"belief_score":0.0, "confidence":0.0}
	if opponent_moves.empty() or opponent_moves.size() != reply_scores.size():
		var uniform_total = 0.0
		for score in reply_scores:
			uniform_total += score
		return {"belief_score":uniform_total / reply_scores.size(), "confidence":0.0}
	var max_logit = -999999999.0
	for move in opponent_moves:
		max_logit = max(max_logit, _move_order_metric(move))
	var total_weight = 0.0
	var weighted_total = 0.0
	var strongest_weight = 0.0
	var temperature = max(OPPONENT_REPLY_TEMPERATURE, 1.0)
	for index in range(opponent_moves.size()):
		var weight = exp((_move_order_metric(opponent_moves[index]) - max_logit) / temperature)
		total_weight += weight
		weighted_total += reply_scores[index] * weight
		strongest_weight = max(strongest_weight, weight)
	if total_weight <= 0.0:
		var fallback_total = 0.0
		for score in reply_scores:
			fallback_total += score
		return {"belief_score":fallback_total / reply_scores.size(), "confidence":0.0}
	var max_probability = strongest_weight / total_weight
	var baseline_probability = 1.0 / max(float(opponent_moves.size()), 1.0)
	var confidence = 0.0
	if baseline_probability < 1.0:
		confidence = clamp((max_probability - baseline_probability) / (1.0 - baseline_probability), 0.0, 1.0)
	return {"belief_score":weighted_total / total_weight, "confidence":confidence}


func _find_ranked_move(ranked_moves:Array, target_move:Dictionary):
	for move in ranked_moves:
		if _same_move(move, target_move):
			return move
	return null


func _risk_adjusted_reply_score(opponent_moves:Array, reply_scores:Array, worst_score:float) -> float:
	if reply_scores.empty():
		return worst_score
	var belief = _reply_belief_profile(opponent_moves, reply_scores)
	var safety_weight = lerp(UNCERTAIN_REPLY_WEIGHT, WORST_REPLY_WEIGHT, belief.confidence)
	return (worst_score * safety_weight) + (belief.belief_score * (1.0 - safety_weight))


func get_search_moves(extra:Dictionary, player_id:int, prune_percent:float=-1.0, reply_to_move=null, branch_cap:int=0, branch_label:String="") -> Dictionary:
	var profile_total = _profile_now()
	if prune_percent <= 0.0:
		prune_percent = PRUNE_PERCENT
	var moves = []
	var evaluee = ghost_base.get_player(player_id)
	var profile_candidates = _profile_now()
	var candidates = get_search_candidates(evaluee, extra)
	_profile_add("search.candidates", profile_candidates)
	_profile_count("search.candidates.count", candidates.size())
	var candidate_names = []
	for candidate_info in candidates:
		if candidate_names.size() >= 24:
			break
		candidate_names.append(str(candidate_info.action_name))
	log_info("[SEARCH_MOVES] p" + str(player_id) + " state=" + _state_display_name(evaluee.current_state()) + " candidates=" + str(candidates.size()) + " [" + ", ".join(candidate_names) + "] depth_prune=" + str(prune_percent) + " branch_cap=" + str(branch_cap) + " role=" + str(branch_label))
	for candidate_info in candidates:
		var action_name = candidate_info.action_name
		var candidate_state = candidate_info.state
		var data_ui_scene = candidate_state.data_ui_scene if candidate_state != null else null
		var profile_data = _profile_now()
		var temp_data = [null] if action_name == "Continue" else get_option_data(action_name, extra, data_ui_scene, evaluee, candidate_state)
		temp_data = _filter_attack_vectors_facing_opponent(action_name, candidate_state, temp_data, evaluee)
		_profile_add("search.option_data", profile_data)
		_profile_count("search.option_data.outputs", temp_data.size())
		for data in temp_data:
			data = _normalize_search_data(action_name, data)
			var move = {"action":action_name, "data":data, "eval":0, "feint":false}
			var opponent_move = reply_to_move if reply_to_move is Dictionary else _continue_move()
			var profile_copy = _profile_now()
			copy_game_state(ghost_base, ghost_eval)
			_profile_add("search.copy_base_to_eval", profile_copy)
			var profile_rollout = _profile_now()
			var rollout = _simulate_pair_on_eval(player_id, move, opponent_move, extra)
			_profile_add("search.simulate_rollout", profile_rollout)
			var profile_eval = _profile_now()
			move.eval = _evaluate_game_state(ghost_eval, player_id, rollout)
			move.frame_advantage = _frame_advantage_from_rollout(ghost_eval, player_id, rollout)
			move.style_score = 0.0
			move.order_score = _move_order_score(ghost_eval, player_id, move, rollout, reply_to_move)
			move.resources_after = _fighter_resources_snapshot(ghost_eval.get_player(player_id))
			if _search_tree_output_enabled():
				move.game_state_snapshot = _game_state_snapshot(ghost_eval)
			move.valid = true
			_profile_add("search.evaluate_snapshot", profile_eval)
			moves.append(move)
			_profile_count("search.moves.simulated")
	var profile_sort = _profile_now()
	moves.sort_custom(self, "_sort_by_eval_desc")
	moves = _ensure_move_list(moves)
	_profile_add("search.sort_and_ensure", profile_sort)
	search_moves_evaluated += moves.size()
	var percentile_keep_count = _keep_count_for_move_count(moves.size(), prune_percent)
	var keep_count = _apply_branch_cap(percentile_keep_count, moves.size(), branch_cap)
	var kept = []
	var pruned = []
	var threshold = moves[keep_count - 1].eval if keep_count > 0 and moves.size() > 0 else 0
	for index in range(moves.size()):
		var move = moves[index]
		move.pruned = index >= keep_count
		if move.pruned:
			move.prune_reason = "branch_cap_" + str(branch_cap) + "_" + str(branch_label) if branch_cap > 0 and index >= branch_cap else "score_in_bottom_" + str(int(round((1.0 - prune_percent) * 100.0))) + "_percent"
			move.prune_score_threshold = threshold
			pruned.append(move)
		else:
			kept.append(move)
	var profile_order = _profile_now()
	kept.sort_custom(self, "_sort_by_order_desc")
	_profile_add("search.order_kept_moves", profile_order)
	search_moves_pruned += pruned.size()
	var first_order_action = "none"
	var first_order_score = 0
	if kept.size() > 0:
		first_order_action = str(kept[0].action)
		first_order_score = kept[0].order_score if kept[0].has("order_score") else kept[0].eval
	log_info("[SEARCH_MOVES] p" + str(player_id) + " evaluated=" + str(moves.size()) + " kept=" + str(kept.size()) + " pruned=" + str(pruned.size()) + " percentile_keep=" + str(percentile_keep_count) + " best=" + str(moves[0].action if moves.size() > 0 else "none") + ":" + str(moves[0].eval if moves.size() > 0 else 0) + " search_first=" + first_order_action + ":" + str(first_order_score))
	_profile_add("search.get_search_moves.total", profile_total)
	return {"all":moves, "kept":kept, "pruned":pruned.size(), "threshold":threshold}


func _attach_ranked_moves_to_tree(parent_node:Dictionary, ranked:Dictionary, node_prefix:String, ply_depth:int, opponent_label:bool=false) -> void:
	var key = "children" if opponent_label else "moves"
	if !parent_node.has(key):
		parent_node[key] = []
	for index in range(ranked.all.size()):
		var move = ranked.all[index]
		var node_id = node_prefix + "_" + ("r" if opponent_label else "a") + str(index)
		var entry = {
			"node_id": node_id,
			"quick_score": move.eval,
			"style_score": move.style_score if move.has("style_score") else 0,
			"order_score": move.order_score if move.has("order_score") else move.eval,
			"simulated_score": move.eval,
			"depth_remaining": ply_depth,
			"frame_advantage": move.frame_advantage if move.has("frame_advantage") else 0,
			"resources_after": move.resources_after if move.has("resources_after") else {},
			"game_state_snapshot": move.game_state_snapshot if move.has("game_state_snapshot") else {},
			"pruned": move.pruned if move.has("pruned") else false
		}
		if opponent_label:
			entry["opponent_action"] = move.action
			entry["opponent_data"] = _json_safe(move.data)
		else:
			entry["action"] = move.action
			entry["data"] = _json_safe(move.data)
		if entry.pruned:
			entry["prune_reason"] = move.prune_reason if move.has("prune_reason") else _search_move_prune_reason()
			entry["prune_score_threshold"] = move.prune_score_threshold if move.has("prune_score_threshold") else ranked.threshold
		move.node_id = node_id
		move.tree_entry = entry
		parent_node[key].append(entry)


func real_search_root(extra:Dictionary, my_id:int, depth:int, predicted_reply=null) -> Dictionary:
	var tree_node = search_tree if _search_tree_output_enabled() else null
	return real_search_value(extra, my_id, depth, true, predicted_reply, tree_node, "root_0", 0)


func real_search_value(extra:Dictionary, my_id:int, depth:int, root:bool=false, predicted_reply=null, tree_node=null, node_prefix:String="node", ply_depth:int=0, alpha:float=-999999999.0, beta:float=999999999.0) -> Dictionary:
	var profile_total = _profile_now()
	if depth <= 0 or ghost_base.should_game_end():
		var leaf = _continue_move()
		leaf.eval = _evaluate_search_state(my_id)
		_profile_add("real_search.leaf", profile_total)
		return leaf
	var opponent_id = ghost_base.get_player(my_id).opponent.id
	var profile_our_moves = _profile_now()
	var our_branch_cap = ROOT_BRANCH_CAP if root else FOLLOWUP_BRANCH_CAP
	var our_branch_label = "root" if root else "followup"
	var our_ranked = get_search_moves(extra, my_id, PRUNE_PERCENT, null, our_branch_cap, our_branch_label)
	_profile_add("real_search.our_moves", profile_our_moves)
	if tree_node is Dictionary:
		var profile_attach_our = _profile_now()
		_attach_ranked_moves_to_tree(tree_node, our_ranked, node_prefix, ply_depth, false)
		_profile_add("real_search.attach_our_tree", profile_attach_our)
	var our_moves = our_ranked.kept
	if depth == 1:
		var shallow_best = _best_eval_move(our_moves).duplicate(true) if our_moves.size() > 0 else _continue_move()
		if shallow_best.has("tree_entry"):
			shallow_best.tree_entry["minimax_score"] = shallow_best.eval
		if tree_node is Dictionary:
			tree_node["best_move"] = {
				"action": shallow_best.action,
				"data": _json_safe(shallow_best.data if shallow_best.has("data") else null),
				"final_score": shallow_best.eval,
				"depth": depth,
				"reason": "highest_root_score_at_depth_1_no_opponent_model"
			}
		debug_print("[REAL_SEARCH] depth=1 root=" + str(root) + " chose=" + str(shallow_best.action) + " eval=" + str(int(shallow_best.eval)) + " no_opponent_model=true")
		_profile_add("real_search.total.depth_" + str(depth), profile_total)
		return shallow_best
	var best_move = _continue_move()
	best_move.eval = -999999999.0
	var best_score = alpha
	var profile_snapshot = _profile_now()
	snapshot_base(depth)
	_profile_add("real_search.snapshot_base", profile_snapshot)
	for our_move in our_moves:
		var worst_score = 999999999.0
		var worst_reply = "Continue"
		var profile_restore_for_opp = _profile_now()
		restore_base(depth)
		_profile_add("real_search.restore_before_opponent_moves", profile_restore_for_opp)
		var profile_opp_moves = _profile_now()
		var opponent_ranked = get_search_moves(extra, opponent_id, PRUNE_PERCENT, our_move, OPPONENT_BRANCH_CAP, "opponent")
		_profile_add("real_search.opponent_moves", profile_opp_moves)
		if root and predicted_reply is Dictionary:
			var predicted_ranked_move = _find_ranked_move(opponent_ranked.all, predicted_reply)
			if predicted_ranked_move == null:
				predicted_ranked_move = predicted_reply.duplicate(true)
				predicted_ranked_move.eval = opponent_ranked.threshold if opponent_ranked.has("threshold") else 0
				predicted_ranked_move.order_score = _move_order_metric(predicted_ranked_move)
			predicted_ranked_move.pruned = false
			_append_unique_move(opponent_ranked.kept, predicted_ranked_move)
			_append_unique_move(opponent_ranked.all, predicted_ranked_move)
			opponent_ranked.kept.sort_custom(self, "_sort_by_order_desc")
		if our_move.has("tree_entry"):
			var profile_attach_opp = _profile_now()
			_attach_ranked_moves_to_tree(our_move.tree_entry, opponent_ranked, our_move.node_id, ply_depth + 1, true)
			_profile_add("real_search.attach_opp_tree", profile_attach_opp)
		var opponent_moves = opponent_ranked.kept
		var reply_scores = []
		for opponent_move in opponent_moves:
			var profile_restore = _profile_now()
			restore_base(depth)
			_profile_add("real_search.restore_base", profile_restore)
			var profile_advance = _profile_now()
			var rollout = _advance_pair_on_base(my_id, our_move, opponent_move, extra)
			_profile_add("real_search.advance_pair", profile_advance)
			var profile_eval = _profile_now()
			var score = _evaluate_search_state(my_id, rollout)
			_profile_add("real_search.evaluate_pair", profile_eval)
			if depth > 1 and !ghost_base.should_game_end():
				var child_node = opponent_move.tree_entry if opponent_move.has("tree_entry") else null
				var child_beta = min(beta, worst_score)
				var profile_recurse = _profile_now()
				var future = real_search_value(extra, my_id, depth - 1, false, null, child_node, opponent_move.node_id if opponent_move.has("node_id") else node_prefix, ply_depth + 2, best_score, child_beta)
				_profile_add("real_search.recursive_call", profile_recurse)
				score = min(score, future.eval)
			reply_scores.append(score)
			if score < worst_score:
				worst_score = score
				worst_reply = str(opponent_move.action)
			if opponent_move.has("tree_entry"):
				opponent_move.tree_entry["simulated_score"] = score
				opponent_move.tree_entry["game_state_snapshot"] = _game_state_snapshot(ghost_base)
		var evaluated_move = our_move.duplicate(true)
		var risk_adjusted_score = _risk_adjusted_reply_score(opponent_moves, reply_scores, worst_score)
		evaluated_move.eval = risk_adjusted_score
		evaluated_move.worst_reply = worst_reply
		evaluated_move.worst_score = worst_score
		if our_move.has("tree_entry"):
			our_move.tree_entry["minimax_score"] = risk_adjusted_score
			our_move.tree_entry["worst_score"] = worst_score
			our_move.tree_entry["worst_reply"] = worst_reply
		if evaluated_move.eval > best_move.eval:
			best_move = evaluated_move
		best_score = max(best_score, best_move.eval)
		if best_score >= beta:
			_profile_count("real_search.beta_cutoff")
			if our_move.has("tree_entry"):
				our_move.tree_entry["beta_cutoff"] = true
				our_move.tree_entry["beta_cutoff_score"] = best_score
				our_move.tree_entry["beta_cutoff_against"] = beta
			break
	var profile_restore_final = _profile_now()
	restore_base(depth)
	_profile_add("real_search.restore_final", profile_restore_final)
	if tree_node is Dictionary:
		tree_node["best_move"] = {
			"action": best_move.action,
			"data": _json_safe(best_move.data if best_move.has("data") else null),
			"final_score": best_move.eval,
			"depth": depth,
			"reason": "highest_minimax_score_after_depth_" + str(depth) + "_search"
		}
	debug_print("[REAL_SEARCH] depth=" + str(depth) + " root=" + str(root) + " chose=" + str(best_move.action) + " eval=" + str(int(best_move.eval)) + " worst_reply=" + str(best_move.worst_reply if best_move.has("worst_reply") else ""))
	_profile_add("real_search.total.depth_" + str(depth), profile_total)
	return best_move


# Takes a potential data node as input (ActionUIData or XYPlot/Slider etc.)
# Recursively generates a dictionary of arrays of possible inputs to an ActionUIData.
func get_data_structure(control_node, fighter=null, state=null):
	# Account for unused code, halves time to process Grab
	if !control_node.visible and control_node.get_name() == "Jump" and get_children_names(control_node.get_parent()) == ["Direction", "Dash", "Jump"]:
		return {control_node.get_name():[false]}
	
	var script = control_node.get_script()
	if script != null:
		for UIElement in checkable_menu.get_children():
			if script == UIElement.get_script():
				# If it's a custom UIElement, we do nothing. Will be fixed eventally
				match UIElement.get_name():
					"XYPlot":
						return {control_node.get_name():get_possible_xyplot_outputs(control_node, fighter)}
					"8Way":
						var possible_dirs = []
						for dir in control_node.DIRS:
							if control_node.get(dir):
								possible_dirs.append(control_node.get_value(dir))
						return {control_node.get_name():possible_dirs}
					"Slider":
						return {control_node.get_name():make_unique([{"x":control_node.min_value}, {"x":control_node.max_value}, {"x":(control_node.min_value+control_node.max_value)/2}])}
					"CountOption":
						return {control_node.get_name():{"count":make_unique([control_node.min_value, control_node.max_value, (control_node.min_value+control_node.max_value)/2])}}
					"OptionButton":
						return {control_node.get_name():get_enabled_options(control_node)}
					"CheckButton":
						return {control_node.get_name():[true, false]}

	if control_node is Container:
		activate_action_ui_data(control_node, fighter, state)
		var test_data = {}
		var datum = null
		for child in control_node.get_children():
			datum = get_data_structure(child, fighter, state)
			if datum is int:
				return null
			elif datum != null and not datum is Array:
				test_data[datum.keys()[0]] = datum.values()[0]
		
		
		if test_data.keys().size() > 1:
			return verify_data_structure(control_node, test_data)
		elif datum is Array:
			return verify_data_structure(control_node, datum)
		elif datum != null:
			return verify_data_structure(control_node, datum.values()[0] )
		else:
			return [null]

# Turns the pile of spaghetti made in the above function into an an array of data
func split_potential_data(data):
	debug_print(data)
	var result = [{}]
	
	for key in data.keys():
		var new_result = []
		var value = data[key]
		
		if value is Array:
			for item in value:
				for existing_dict in result:
					var new_dict = existing_dict.duplicate()
					new_dict[key] = item
					new_result.append(new_dict)
		elif value is Dictionary:
			var sub_permutations = split_potential_data(value)
			for sub_perm in sub_permutations:
				for existing_dict in result:
					var new_dict = existing_dict.duplicate()
					new_dict[key] = sub_perm
					new_result.append(new_dict)
		else:
			for existing_dict in result:
				existing_dict[key] = value
			new_result = result
		
		result = new_result
	
	return result
	
	
func get_enabled_options(option_button: OptionButton) -> Array:
	var enabled_options = []
	var items = option_button.get_item_count()
	for option in range(items):
		if not option_button.is_item_disabled(option):
			enabled_options.append({
				id = option, 
				name = option_button.items[option]
			})

	return enabled_options
	
# An AI generated bit to get possible XYPlot values (that I've manually fixed)
# It gets up, down, left and right if applicable, then the extremities of the limited area if it is limited
func create_output(x: float, y: float, xy_plot, panel_radius) -> Dictionary:
	return xy_plot.as_percentage_int_vec(Vector2(x, y) * panel_radius)

func get_possible_xyplot_outputs(xy_plot: XYPlot, fighter) -> Array:
	var outputs = []
	var panel_radius = xy_plot.panel_radius
	var facing = xy_plot.facing * fighter.get_facing_int()
	var limit_angle = xy_plot.limit_angle
	var limit_center = xy_plot.get_limit_center()
	var limit_range = xy_plot.get_limit_range()

	# Add (1, 0) and (-1, 0) if within allowed angle
	if not limit_angle or abs(Utils.angle_diff(0, limit_center)) <= limit_range / 2:
		outputs.append(create_output(facing, 0, xy_plot, panel_radius))
	if not limit_angle or abs(Utils.angle_diff(PI, limit_center)) <= limit_range / 2:
		outputs.append(create_output(-facing, 0, xy_plot, panel_radius))

	# Add (0, 1) and (0, -1) if within allowed angle
	if not limit_angle or abs(Utils.angle_diff(-PI/2, limit_center)) <= limit_range / 2:
		outputs.append(create_output(0, -1, xy_plot, panel_radius))
	if not limit_angle or abs(Utils.angle_diff(PI/2, limit_center)) <= limit_range / 2:
		outputs.append(create_output(0, 1, xy_plot, panel_radius))

	# If angle is limited, add extremities
	if limit_angle:
		var left_extremity = Utils.ang2vec(limit_center - limit_range / 2)
		var right_extremity = Utils.ang2vec(limit_center + limit_range / 2)
		outputs.append(create_output(left_extremity.x * facing, left_extremity.y, xy_plot, panel_radius))
		outputs.append(create_output(right_extremity.x * facing, right_extremity.y, xy_plot, panel_radius))

	return outputs

# From the actual DI code
func di_as_percentage_int_vec(vec2:Vector2):
	return {
		"x":int(round(vec2.x * 100)), 
		"y":int(round(vec2.y * 100)), 
	}

#Stole this from Reddit u/Dizzy_Caterpillar777
func make_unique(arr: Array) -> Array:
	var dict := {}
	for a in arr:
		dict[a] = 1
	return dict.keys()
	
func get_children_names(node):
	var children_names = []
	for child in node.get_children():
		children_names.append(child.get_name())
	return children_names


func suppress_search_ui_runtime(node):
	node.set_block_signals(true)
	node.set_process(false)
	node.set_physics_process(false)
	node.set_process_input(false)
	node.set_process_unhandled_input(false)
	node.set_process_unhandled_key_input(false)
	for child in node.get_children():
		suppress_search_ui_runtime(child)


func _search_facing_sign(fighter) -> int:
	if fighter != null and fighter.has_method("get_facing_int"):
		return fighter.get_facing_int()
	return 1


func _search_percent_vec(x:float, y:float, fighter=null) -> Dictionary:
	return {
		"x": int(round(x * 100.0)) * _search_facing_sign(fighter),
		"y": int(round(y * 100.0)),
	}


func _search_slider_values(min_value:=0, max_value:=100) -> Array:
	return make_unique([
		{"x": min_value},
		{"x": max_value},
		{"x": (min_value + max_value) / 2},
	])


func _search_8way_vec(x:int, y:int, fighter=null) -> Dictionary:
	return {
		"x": x * _search_facing_sign(fighter),
		"y": y,
	}


func _search_xy_cardinals(fighter) -> Array:
	return [
		_search_percent_vec(1, 0, fighter),
		_search_percent_vec(-1, 0, fighter),
		_search_percent_vec(0, -1, fighter),
		_search_percent_vec(0, 1, fighter),
	]


func get_special_option_data(option:String, fighter):
	match option:
		"Geyser":
			var max_charge = 1
			if fighter != null and fighter.get("geyser_charge") != null:
				max_charge = max(int(fighter.geyser_charge), 1)
			return {
				"Charge": {
					"count": make_unique([1, max_charge, (1 + max_charge) / 2.0])
				},
				"Direction": [
					{"x": -100, "y": 0},
					{"x": 0, "y": -100},
					{"x": 0, "y": 100},
					{"x": 71, "y": -71},
					{"x": 71, "y": 71},
				]
			}
		"DriveJump":
			return _search_slider_values()
		"CommandGrab":
			return [true, false]
		"ClapJump":
			return {
				"Auto": [true, false],
				"Direction": [
					_search_8way_vec(1, 0, fighter),
					_search_8way_vec(-1, 0, fighter),
				]
			}
		"LOIC":
			return {
				"Self": [true, false],
				"Delay": _search_slider_values(),
			}
		"Grenade":
			var edge_angle = deg2rad(80.0)
			return [
				_search_percent_vec(0, -1, fighter),
				_search_percent_vec(-sin(edge_angle), -cos(edge_angle), fighter),
				_search_percent_vec(sin(edge_angle), -cos(edge_angle), fighter),
			]
		_:
			return null

func get_option_data(option: String, extra: Dictionary, data_ui_scene, fighter, state=null) -> Array:
	var temp_data = [null]
	debug_print("--------------")
	debug_print("checking " + option)
	if data_ui_scene != null:
		var possible_data = []
		var special_data = get_special_option_data(option, fighter)
		if option in quick_data_lookup:
			possible_data = quick_data_lookup[option]
		elif special_data != null:
			possible_data = special_data
			log_info("[SEARCH_UI_FASTPATH] action=" + str(option) + " state=" + _state_display_name(state) + " data=" + str(possible_data))
		else:
			log_info("[SEARCH_UI] action=" + str(option) + " state=" + _state_display_name(state) + " scene=" + str(data_ui_scene.resource_path))
			var data_scene_instance = data_ui_scene.instance()
			log_info("[SEARCH_UI_INSTANCE] action=" + str(option) + " root=" + str(data_scene_instance.name) + " children=" + str(get_children_names(data_scene_instance)))
			possible_data = get_data_structure(data_scene_instance, fighter, state)
			log_info("[SEARCH_UI_DATA] action=" + str(option) + " data=" + str(possible_data))
			if data_scene_instance.get_parent() != null:
				data_scene_instance.get_parent().remove_child(data_scene_instance)
			data_scene_instance.free()
		temp_data = split_potential_data(possible_data) if possible_data is Dictionary else possible_data
		debug_print(temp_data)
	return temp_data

func setup_ghost_game():
	# Use cached scene for faster instantiation (still faster than loading each time)
	if gg_scene == null:
		gg_scene = load("res://Game.tscn")

	if ghost_viewport == null:
		ghost_viewport = main.find_node("GhostViewport")

	var match_signature = get_ghost_match_signature()
	var can_reuse = experimental_speedup
	var must_create = ghost_game == null or not is_instance_valid(ghost_game) or ghost_match_signature != match_signature or not can_reuse

	if must_create:
		release_ghost_game()
		ghost_game = gg_scene.instance()
		ghost_setup_created += 1

		if multihustle:
			ghost_game.set_script(Global.current_game.get_script())
			ghost_game.multiHustle_CharManager = Global.current_game.multiHustle_CharManager

		ghost_game.is_ghost = true
		ghost_game.visible = false
		ghost_viewport.add_child(ghost_game)

		ghost_game.start_game(true, main.match_data)
		ghost_game.ghost_speed = 100
		ghost_game.ghost_freeze = false
		if ghost_game.get("ai_skip_show_state") != null:
			ghost_game.ai_skip_show_state = true
		ghost_match_signature = match_signature
	else:
		ghost_setup_reused += 1

	reset_ghost_runtime_state()

	if experimental_speedup:
		game.fast_copy_to(ghost_game)
	else:
		game.copy_to(ghost_game)


func get_ghost_match_signature() -> String:
	if main == null or main.match_data == null:
		return ""
	var selected = main.match_data.selected_characters if main.match_data.has("selected_characters") else {}
	var styles = main.match_data.selected_styles if main.match_data.has("selected_styles") else {}
	var seed_value = main.match_data.seed if main.match_data.has("seed") else 0
	return JSON.print({
		"selected": selected,
		"styles": styles,
		"seed": seed_value,
		"stage_width": main.match_data.stage_width if main.match_data.has("stage_width") else 0,
		"game_length": main.match_data.game_length if main.match_data.has("game_length") else 0,
		"char_distance": main.match_data.char_distance if main.match_data.has("char_distance") else 0,
	})


func release_ghost_game():
	if ghost_game and is_instance_valid(ghost_game):
		ghost_game.free()
	ghost_game = null
	ghost_match_signature = ""


func release_search_ghosts():
	if ghost_base and is_instance_valid(ghost_base):
		ghost_base.free()
	if ghost_eval and is_instance_valid(ghost_eval):
		ghost_eval.free()
	for search_game in search_snapshots:
		if search_game and is_instance_valid(search_game):
			search_game.free()
	ghost_base = null
	ghost_eval = null
	search_snapshots.clear()


func reset_ghost_runtime_state():
	if ghost_game == null or not is_instance_valid(ghost_game):
		return
	ghost_game.visible = false
	ghost_game.is_ghost = true
	ghost_game.is_afterimage = false
	ghost_game.ghost_hidden = false
	ghost_game.ghost_speed = 100
	ghost_game.ghost_tick = 0
	ghost_game.ghost_freeze = false
	if ghost_game.get("ai_skip_show_state") != null:
		ghost_game.ai_skip_show_state = true
	ghost_game.ghost_simulated_ticks = 0
	ghost_game.ghost_actionable_freeze_ticks = 0
	ghost_game.ghost_p1_actionable = false
	ghost_game.ghost_p2_actionable = false
	ghost_game.p1_ghost_ready_tick = null
	ghost_game.p2_ghost_ready_tick = null
	ghost_game.current_tick = -1
	ghost_game.real_tick = 0
	ghost_game.max_replay_tick = 0
	ghost_game.game_end_tick = 0
	ghost_game.frame_passed = false
	ghost_game.game_finished = false
	ghost_game.parry_freeze = false
	ghost_game.game_paused = false
	ghost_game.buffer_playback = false
	ghost_game.buffer_edit = false
	ghost_game.forfeit = false
	ghost_game.forfeit_player = null
	ghost_game.quitter_focus = false
	ghost_game.quitter_focus_ticks = 0
	ghost_game.advance_frame_input = false
	ghost_game.network_simulate_ready = true
	ghost_game.simulated_once = false
	ghost_game.super_freeze_ticks = 0
	ghost_game.super_active = false
	ghost_game.prediction_effect = false
	ghost_game.p1_super = false
	ghost_game.p2_super = false
	ghost_game.hit_freeze = false
	ghost_game.player_actionable = true
	ghost_game.p1_turn = false
	ghost_game.p2_turn = false
	ghost_game.made_afterimage = false
	if ghost_game.p1 != null and ghost_game.p2 != null:
		reset_ghost_player_runtime(ghost_game.p1, ghost_game.p2)
		reset_ghost_player_runtime(ghost_game.p2, ghost_game.p1)


func reset_ghost_player_runtime(player, opponent):
	player.is_ghost = true
	player.opponent = opponent
	player.queued_action = null
	player.queued_data = null
	player.queued_extra = null
	return


func get_best_move(extra:Dictionary, id:int, leeway_percentage:float, allow_leeway:bool, randomise_burst:bool, opponent_action="Continue", opponent_data=null, tree_depth:int=0, parent_node=null) -> Dictionary:
	var moves = []
	var best_score = -999999
	var record_tree = _search_tree_output_enabled() or parent_node != null
	var current_node = {}
	if record_tree:
		current_node = {
			"depth": tree_depth,
			"player": "P" + str(id),
			"opponent_action": opponent_action,
			"evaluations": [],
			"chosen": null
		}
	
	var evaluee = game.get_player(id)
	var opponent = game.get_player(evaluee.opponent.id) 
	
	var dist = sqrt(pow(opponent.get_pos().x - evaluee.get_pos().x, 2) + pow(opponent.get_pos().y - evaluee.get_pos().y, 2))
	
	var candidates = get_search_candidates(evaluee, extra)
	for candidate_info in candidates:
		var action_name = candidate_info.action_name
		var button_state = candidate_info.state
		var too_far_for_melee = dist > 200 and button_state != null and button_state.type == 1
		if too_far_for_melee:
			continue
		var evaluation = evaluate_candidate(action_name, button_state, extra, id, opponent_action, opponent_data)
		if record_tree:
			current_node["evaluations"].append({
				"action": action_name,
				"score": evaluation.eval,
				"data": str(evaluation.data).left(50) if evaluation.data else null
			})
		if best_score < evaluation.eval:
			if !allow_leeway or abs(best_score - evaluation.eval) >= best_score*leeway_percentage:
				moves = [evaluation]
			best_score = evaluation.eval

		elif allow_leeway and abs(best_score - evaluation.eval) <= best_score*leeway_percentage:
			moves.append(evaluation)

	# Choose a move that's one of the "best" options to pick
	debug_print("Options were: " + str(make_options_readable(moves)))
	
	# Burst randomisation and failsafe if no moves are returned
	# Only randomize Burst when there are other moves available
	if moves.empty():
		moves.append({"action":"Continue", "eval":0, "data":null, "feint":false})
	elif randomise_burst and moves[0].action == "Burst" and moves.size() > 1:
		# Only add Continue as alternative when Burst isn't the only option
		moves.append({"action":"Continue", "eval":0, "data":null, "feint":false})
	
	var chosen_move = moves[target_player.randi_range(0, moves.size()-1)].duplicate() if !moves.empty() else {"action":"Continue", "eval":-999999, "data":null, "feint":false}
	
	if record_tree:
		current_node["chosen"] = {
			"action": chosen_move.action,
			"score": chosen_move.eval,
			"data": str(chosen_move.data).left(50) if chosen_move.data else null
		}
		if parent_node != null:
			if not parent_node.has("children"):
				parent_node["children"] = []
			parent_node["children"].append(current_node)
		elif tree_depth == 0:
			search_tree["moves"].append(current_node)
			search_tree["total_nodes"] += 1
	
	debug_print("Picking " + chosen_move.action + " with eval of " + str(chosen_move.eval) + " and data " + str(chosen_move.data))
	debug_print("Assuming opponent chooses " + opponent_action + " with data " + str(opponent_data))
	return chosen_move


func evaluate_candidate(action_name:String, candidate_state, extra, id, opponent_action, opponent_data):
	var temp_data = get_option_data(action_name, extra, candidate_state.data_ui_scene if candidate_state != null else null, game.get_player(id), candidate_state)
	temp_data = _filter_attack_vectors_facing_opponent(action_name, candidate_state, temp_data, game.get_player(id))
	var best_score = -999999
	var best_data = null
	var feint = false
	
	for example_data in temp_data:
		if example_data is String and example_data == "Parry":
			example_data = get_block_data(opponent_action, opponent_data, id)
			if example_data["Melee Parry Timing"].count == 0:
				example_data["Melee Parry Timing"].count = 1 #Not possible to block @f0
		debug_print(example_data)
		var prediction = eval_move(action_name, example_data, extra, id, opponent_action, opponent_data)
		debug_print(prediction.eval)
		if prediction.eval > best_score:# If the move has the best score, we'll assume they'll pick it
			best_score = prediction.eval
			best_data = example_data
			feint = prediction.feint
	return {"action":action_name, "eval":best_score, "data":best_data, "feint":feint, "style_score":0.0}


func evaluate_button(button, extra, id, opponent_action, opponent_data):
	return evaluate_candidate(button.action_name, button.state, extra, id, opponent_action, opponent_data)


func _make_search_action_buttons_stub():
	var action_buttons = SearchActionButtonsStub.new()
	var opponent_action_buttons = SearchActionButtonsStub.new()
	action_buttons.opponent_action_buttons = opponent_action_buttons
	return action_buttons


func activate_action_ui_data(control_node, fighter, state=null):
	if control_node is ActionUIData:
		var script = control_node.get_script()
		log_info("[SEARCH_UI_ACTIVATE] node=" + str(control_node.name) + " script=" + str(script.resource_path if script != null else "") + " state=" + _state_display_name(state))
		suppress_search_ui_runtime(control_node)
		control_node.fighter = fighter
		control_node.state = state
		if control_node.action_buttons == null:
			control_node.action_buttons = _make_search_action_buttons_stub()
		if search_ui_host != null and is_instance_valid(search_ui_host):
			search_ui_host.add_child(control_node)
		else:
			self.add_child(control_node)
		log_info("[SEARCH_UI_INIT] node=" + str(control_node.name) + " state=" + _state_display_name(state))
		control_node.init()
		log_info("[SEARCH_UI_INIT_DONE] node=" + str(control_node.name) + " state=" + _state_display_name(state))
		log_info("[SEARCH_UI_FIGHTER_UPDATE] node=" + str(control_node.name) + " state=" + _state_display_name(state))
		control_node.fighter_update()
		log_info("[SEARCH_UI_FIGHTER_UPDATE_DONE] node=" + str(control_node.name) + " state=" + _state_display_name(state))


func verify_data_structure(control_node, unverified_data):
	if control_node is ActionUIData:
		var default_data = control_node.get_data()
		var test_data
		if unverified_data is Array:
			test_data = unverified_data[0]
		else:
			test_data = unverified_data
		if default_data is Dictionary and test_data is Dictionary and default_data.keys() != test_data.keys():
			debug_print("Mismatch: " + str(test_data.keys()) + " vs " + str(default_data.keys()))
			return [default_data]
		if test_data is Dictionary and not default_data is Dictionary or not test_data is Dictionary and default_data is Dictionary:
			debug_print("Mismatch: " + str(test_data) + " vs " + str(default_data))
			return [default_data]
	return unverified_data


func make_options_readable(options):
	var output = ""
	for option in options:
		output += option.action + ", "
	return output.left(output.length() - 2)
	
