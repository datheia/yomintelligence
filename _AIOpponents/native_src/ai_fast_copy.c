#include <stdint.h>
#include <string.h>

#include <gdnative_api_struct.gen.h>

const godot_gdnative_core_api_struct *_gdnative_wrapper_api_struct = 0;
const godot_gdnative_ext_nativescript_api_struct *_gdnative_wrapper_nativescript_api_struct = 0;
const godot_gdnative_ext_pluginscript_api_struct *_gdnative_wrapper_pluginscript_api_struct = 0;
const godot_gdnative_ext_android_api_struct *_gdnative_wrapper_android_api_struct = 0;
const godot_gdnative_ext_arvr_api_struct *_gdnative_wrapper_arvr_api_struct = 0;
const godot_gdnative_ext_videodecoder_api_struct *_gdnative_wrapper_videodecoder_api_struct = 0;
const godot_gdnative_ext_net_api_struct *_gdnative_wrapper_net_api_struct = 0;

static const godot_gdnative_core_1_1_api_struct *core_1_1 = 0;
static const godot_gdnative_core_1_2_api_struct *core_1_2 = 0;
static godot_method_bind *object_get_bind = 0;
static godot_method_bind *object_set_bind = 0;

static void *aifastcopy_create(godot_object *instance, void *method_data) {
	(void)instance;
	(void)method_data;
	return _gdnative_wrapper_api_struct->godot_alloc(1);
}

static void aifastcopy_destroy(godot_object *instance, void *method_data, void *user_data) {
	(void)instance;
	(void)method_data;
	if (user_data) {
		_gdnative_wrapper_api_struct->godot_free(user_data);
	}
}

static godot_variant int_variant(int64_t value) {
	godot_variant ret;
	_gdnative_wrapper_api_struct->godot_variant_new_int(&ret, value);
	return ret;
}

static godot_variant bool_variant(godot_bool value) {
	godot_variant ret;
	_gdnative_wrapper_api_struct->godot_variant_new_bool(&ret, value);
	return ret;
}

static godot_variant string_variant(const char *value) {
	godot_string string_value = _gdnative_wrapper_api_struct->godot_string_chars_to_utf8(value);
	godot_variant ret;
	_gdnative_wrapper_api_struct->godot_variant_new_string(&ret, &string_value);
	_gdnative_wrapper_api_struct->godot_string_destroy(&string_value);
	return ret;
}

static godot_bool variant_string_equals(godot_variant *variant, const char *value) {
	if (_gdnative_wrapper_api_struct->godot_variant_get_type(variant) != GODOT_VARIANT_TYPE_STRING) {
		return GODOT_FALSE;
	}
	godot_string string_value = _gdnative_wrapper_api_struct->godot_variant_as_string(variant);
	godot_char_string utf8 = _gdnative_wrapper_api_struct->godot_string_utf8(&string_value);
	const char *data = _gdnative_wrapper_api_struct->godot_char_string_get_data(&utf8);
	const godot_bool equals = data && strcmp(data, value) == 0 ? GODOT_TRUE : GODOT_FALSE;
	_gdnative_wrapper_api_struct->godot_char_string_destroy(&utf8);
	_gdnative_wrapper_api_struct->godot_string_destroy(&string_value);
	return equals;
}

static int make_deep_container_variant(godot_variant *src, godot_variant *dst) {
	const godot_variant_type type = _gdnative_wrapper_api_struct->godot_variant_get_type(src);

	if (type == GODOT_VARIANT_TYPE_ARRAY) {
		if (!core_1_1) {
			return -1;
		}
		godot_array array_value = _gdnative_wrapper_api_struct->godot_variant_as_array(src);
		godot_array duplicate = core_1_1->godot_array_duplicate(&array_value, GODOT_TRUE);
		_gdnative_wrapper_api_struct->godot_variant_new_array(dst, &duplicate);
		_gdnative_wrapper_api_struct->godot_array_destroy(&duplicate);
		_gdnative_wrapper_api_struct->godot_array_destroy(&array_value);
		return 1;
	}

	if (type == GODOT_VARIANT_TYPE_DICTIONARY) {
		if (!core_1_2) {
			return -1;
		}
		godot_dictionary dict_value = _gdnative_wrapper_api_struct->godot_variant_as_dictionary(src);
		godot_dictionary duplicate = core_1_2->godot_dictionary_duplicate(&dict_value, GODOT_TRUE);
		_gdnative_wrapper_api_struct->godot_variant_new_dictionary(dst, &duplicate);
		_gdnative_wrapper_api_struct->godot_dictionary_destroy(&duplicate);
		_gdnative_wrapper_api_struct->godot_dictionary_destroy(&dict_value);
		return 1;
	}

	return 0;
}

static godot_variant object_get_property(godot_object *object, const char *property_name, godot_bool *ok) {
	*ok = GODOT_FALSE;
	godot_variant property = string_variant(property_name);
	godot_variant_call_error error = { 0, 0, GODOT_VARIANT_TYPE_NIL };
	const godot_variant *args[1] = { &property };
	godot_variant value = _gdnative_wrapper_api_struct->godot_method_bind_call(
		object_get_bind,
		object,
		args,
		1,
		&error
	);
	_gdnative_wrapper_api_struct->godot_variant_destroy(&property);
	if (error.error == GODOT_CALL_ERROR_CALL_OK) {
		*ok = GODOT_TRUE;
	}
	return value;
}

static godot_bool object_set_property_variant(godot_object *object, const char *property_name, godot_variant *value) {
	godot_variant property = string_variant(property_name);
	godot_variant_call_error error = { 0, 0, GODOT_VARIANT_TYPE_NIL };
	const godot_variant *args[2] = { &property, value };
	godot_variant result = _gdnative_wrapper_api_struct->godot_method_bind_call(
		object_set_bind,
		object,
		args,
		2,
		&error
	);
	_gdnative_wrapper_api_struct->godot_variant_destroy(&result);
	_gdnative_wrapper_api_struct->godot_variant_destroy(&property);
	return error.error == GODOT_CALL_ERROR_CALL_OK ? GODOT_TRUE : GODOT_FALSE;
}

static godot_object *object_get_object_property(godot_object *object, const char *property_name) {
	godot_bool ok = GODOT_FALSE;
	godot_variant value = object_get_property(object, property_name, &ok);
	godot_object *result = 0;
	if (ok && _gdnative_wrapper_api_struct->godot_variant_get_type(&value) == GODOT_VARIANT_TYPE_OBJECT) {
		result = _gdnative_wrapper_api_struct->godot_variant_as_object(&value);
	}
	_gdnative_wrapper_api_struct->godot_variant_destroy(&value);
	return result;
}

static godot_bool copy_named_property(godot_object *copy_from, godot_object *copy_target, const char *property_name, godot_bool deep) {
	godot_bool get_ok = GODOT_FALSE;
	godot_variant value = object_get_property(copy_from, property_name, &get_ok);
	if (!get_ok) {
		_gdnative_wrapper_api_struct->godot_variant_destroy(&value);
		return GODOT_FALSE;
	}

	godot_variant deep_value;
	godot_variant *set_value = &value;
	int deep_status = 0;
	if (deep) {
		deep_status = make_deep_container_variant(&value, &deep_value);
		if (deep_status < 0) {
			_gdnative_wrapper_api_struct->godot_variant_destroy(&value);
			return GODOT_FALSE;
		}
		if (deep_status > 0) {
			set_value = &deep_value;
		}
	}

	const godot_bool set_ok = object_set_property_variant(copy_target, property_name, set_value);
	if (deep && deep_status > 0) {
		_gdnative_wrapper_api_struct->godot_variant_destroy(&deep_value);
	}
	_gdnative_wrapper_api_struct->godot_variant_destroy(&value);
	return set_ok;
}

static godot_int copy_property_list(godot_object *copy_from, godot_object *copy_target, const char **properties, godot_int count, godot_bool deep) {
	godot_int copied = 0;
	for (godot_int i = 0; i < count; i++) {
		if (copy_named_property(copy_from, copy_target, properties[i], deep)) {
			copied++;
		}
	}
	return copied;
}

static void load_core_version_apis(void) {
	const godot_gdnative_api_struct *api = _gdnative_wrapper_api_struct->next;
	while (api) {
		if (api->type == GDNATIVE_CORE) {
			if (api->version.major == 1 && api->version.minor == 1) {
				core_1_1 = (const godot_gdnative_core_1_1_api_struct *)api;
			} else if (api->version.major == 1 && api->version.minor == 2) {
				core_1_2 = (const godot_gdnative_core_1_2_api_struct *)api;
			}
		}
		api = api->next;
	}
}

static godot_variant copy_properties(
	godot_object *instance,
	void *method_data,
	void *user_data,
	int arg_count,
	godot_variant **args
) {
	(void)instance;
	(void)method_data;
	(void)user_data;

	if (arg_count < 3 || !object_get_bind || !object_set_bind) {
		return int_variant(0);
	}

	if (_gdnative_wrapper_api_struct->godot_variant_get_type(args[0]) != GODOT_VARIANT_TYPE_OBJECT ||
		_gdnative_wrapper_api_struct->godot_variant_get_type(args[1]) != GODOT_VARIANT_TYPE_OBJECT ||
		_gdnative_wrapper_api_struct->godot_variant_get_type(args[2]) != GODOT_VARIANT_TYPE_ARRAY) {
		return int_variant(0);
	}

	godot_object *copy_from = _gdnative_wrapper_api_struct->godot_variant_as_object(args[0]);
	godot_object *copy_target = _gdnative_wrapper_api_struct->godot_variant_as_object(args[1]);
	if (!copy_from || !copy_target) {
		return int_variant(0);
	}

	godot_array property_names = _gdnative_wrapper_api_struct->godot_variant_as_array(args[2]);
	const godot_int property_count = _gdnative_wrapper_api_struct->godot_array_size(&property_names);
	godot_int copied = 0;

	for (godot_int i = 0; i < property_count; i++) {
		godot_variant property_name = _gdnative_wrapper_api_struct->godot_array_get(&property_names, i);
		if (_gdnative_wrapper_api_struct->godot_variant_get_type(&property_name) != GODOT_VARIANT_TYPE_STRING) {
			_gdnative_wrapper_api_struct->godot_variant_destroy(&property_name);
			continue;
		}

		godot_variant_call_error get_error = { 0, 0, GODOT_VARIANT_TYPE_NIL };
		const godot_variant *get_args[1] = { &property_name };
		godot_variant value = _gdnative_wrapper_api_struct->godot_method_bind_call(
			object_get_bind,
			copy_from,
			get_args,
			1,
			&get_error
		);

		if (get_error.error == GODOT_CALL_ERROR_CALL_OK) {
			godot_variant deep_value;
			godot_variant *set_value = &value;
			const int deep_status = make_deep_container_variant(&value, &deep_value);
			if (deep_status < 0) {
				_gdnative_wrapper_api_struct->godot_variant_destroy(&value);
				_gdnative_wrapper_api_struct->godot_variant_destroy(&property_name);
				continue;
			}
			if (deep_status > 0) {
				set_value = &deep_value;
			}

			godot_variant_call_error set_error = { 0, 0, GODOT_VARIANT_TYPE_NIL };
			const godot_variant *set_args[2] = { &property_name, set_value };
			godot_variant set_result = _gdnative_wrapper_api_struct->godot_method_bind_call(
				object_set_bind,
				copy_target,
				set_args,
				2,
				&set_error
			);
			_gdnative_wrapper_api_struct->godot_variant_destroy(&set_result);

			if (deep_status > 0) {
				_gdnative_wrapper_api_struct->godot_variant_destroy(&deep_value);
			}
			if (set_error.error == GODOT_CALL_ERROR_CALL_OK) {
				copied++;
			}
		}

		_gdnative_wrapper_api_struct->godot_variant_destroy(&value);
		_gdnative_wrapper_api_struct->godot_variant_destroy(&property_name);
	}

	_gdnative_wrapper_api_struct->godot_array_destroy(&property_names);
	return int_variant(copied);
}

static godot_variant copy_fighter_runtime(
	godot_object *instance,
	void *method_data,
	void *user_data,
	int arg_count,
	godot_variant **args
) {
	(void)instance;
	(void)method_data;
	(void)user_data;

	if (arg_count < 4 || !object_get_bind || !object_set_bind) {
		return bool_variant(GODOT_FALSE);
	}
	if (_gdnative_wrapper_api_struct->godot_variant_get_type(args[0]) != GODOT_VARIANT_TYPE_OBJECT ||
		_gdnative_wrapper_api_struct->godot_variant_get_type(args[1]) != GODOT_VARIANT_TYPE_OBJECT ||
		_gdnative_wrapper_api_struct->godot_variant_get_type(args[2]) != GODOT_VARIANT_TYPE_OBJECT ||
		_gdnative_wrapper_api_struct->godot_variant_get_type(args[3]) != GODOT_VARIANT_TYPE_STRING) {
		return bool_variant(GODOT_FALSE);
	}

	godot_object *copy_from = _gdnative_wrapper_api_struct->godot_variant_as_object(args[0]);
	godot_object *copy_target = _gdnative_wrapper_api_struct->godot_variant_as_object(args[1]);
	godot_object *current_state = _gdnative_wrapper_api_struct->godot_variant_as_object(args[2]);
	if (!copy_from || !copy_target || !current_state) {
		return bool_variant(GODOT_FALSE);
	}

	static const char *base_properties[] = {
		"got_parried",
		"colliding_with_opponent",
		"has_hyper_armor",
		"has_projectile_armor",
		"blockstun_ticks",
		"blocked_hitbox_plus_frames",
		"stance",
		"projectile_invulnerable",
		"invulnerable"
	};
	const godot_int base_count = (godot_int)(sizeof(base_properties) / sizeof(base_properties[0]));
	godot_int copied = copy_property_list(copy_from, copy_target, base_properties, base_count, GODOT_FALSE);
	godot_int required = base_count;

	godot_object *target_state_machine = object_get_object_property(copy_target, "state_machine");
	godot_object *target_current_state = target_state_machine ? object_get_object_property(target_state_machine, "state") : 0;
	if (target_current_state && copy_named_property(current_state, target_current_state, "interrupt_frames", GODOT_TRUE)) {
		copied++;
	}

	if (variant_string_equals(args[3], "res://characters/wizard/Wizard.gd")) {
		static const char *wizard_properties[] = { "boulder_projectile" };
		required += 1;
		copied += copy_property_list(copy_from, copy_target, wizard_properties, 1, GODOT_FALSE);
	} else if (variant_string_equals(args[3], "res://characters/swordandgun/SwordGuy.gd")) {
		static const char *sword_properties[] = { "bullet_cancelling" };
		required += 1;
		copied += copy_property_list(copy_from, copy_target, sword_properties, 1, GODOT_FALSE);
	} else if (variant_string_equals(args[3], "res://characters/robo/Robot.gd")) {
		static const char *robo_properties[] = {
			"armor_active",
			"magnet_ticks_left",
			"flame_touching_opponent",
			"drive_cancel",
			"buffer_drive_cancel"
		};
		required += 8;
		copied += copy_property_list(copy_from, copy_target, robo_properties, 5, GODOT_FALSE);
		if (copy_named_property(copy_from, copy_target, "flying_dir", GODOT_TRUE)) {
			copied++;
		}
		godot_object *from_magnet = object_get_object_property(copy_from, "magnet_polygon");
		godot_object *target_magnet = object_get_object_property(copy_target, "magnet_polygon");
		if (from_magnet && target_magnet && copy_named_property(from_magnet, target_magnet, "polygon", GODOT_FALSE)) {
			copied++;
		}
		godot_object *from_magnet2 = object_get_object_property(copy_from, "magnet_polygon2");
		godot_object *target_magnet2 = object_get_object_property(copy_target, "magnet_polygon2");
		if (from_magnet2 && target_magnet2 && copy_named_property(from_magnet2, target_magnet2, "polygon", GODOT_FALSE)) {
			copied++;
		}
	} else if (variant_string_equals(args[3], "res://characters/mutant/Beast.gd")) {
		static const char *mutant_properties[] = { "juke_ticks", "up_juke_ticks" };
		required += 2;
		copied += copy_property_list(copy_from, copy_target, mutant_properties, 2, GODOT_FALSE);
	}

	return bool_variant(copied >= required ? GODOT_TRUE : GODOT_FALSE);
}

static godot_bool append_state_name_or_value(godot_array *target_array, godot_variant *source_value) {
	if (_gdnative_wrapper_api_struct->godot_variant_get_type(source_value) == GODOT_VARIANT_TYPE_OBJECT) {
		godot_object *state_object = _gdnative_wrapper_api_struct->godot_variant_as_object(source_value);
		if (state_object) {
			godot_bool name_ok = GODOT_FALSE;
			godot_variant name_value = object_get_property(state_object, "name", &name_ok);
			if (name_ok) {
				_gdnative_wrapper_api_struct->godot_array_append(target_array, &name_value);
				_gdnative_wrapper_api_struct->godot_variant_destroy(&name_value);
				return GODOT_TRUE;
			}
			_gdnative_wrapper_api_struct->godot_variant_destroy(&name_value);
		}
	}
	_gdnative_wrapper_api_struct->godot_array_append(target_array, source_value);
	return GODOT_TRUE;
}

static godot_variant copy_state_history(
	godot_object *instance,
	void *method_data,
	void *user_data,
	int arg_count,
	godot_variant **args
) {
	(void)instance;
	(void)method_data;
	(void)user_data;

	if (arg_count < 2 || !object_get_bind || !object_set_bind) {
		return bool_variant(GODOT_FALSE);
	}
	if (_gdnative_wrapper_api_struct->godot_variant_get_type(args[0]) != GODOT_VARIANT_TYPE_OBJECT ||
		_gdnative_wrapper_api_struct->godot_variant_get_type(args[1]) != GODOT_VARIANT_TYPE_OBJECT) {
		return bool_variant(GODOT_FALSE);
	}

	godot_object *copy_from = _gdnative_wrapper_api_struct->godot_variant_as_object(args[0]);
	godot_object *copy_target = _gdnative_wrapper_api_struct->godot_variant_as_object(args[1]);
	godot_object *from_sm = copy_from ? object_get_object_property(copy_from, "state_machine") : 0;
	godot_object *target_sm = copy_target ? object_get_object_property(copy_target, "state_machine") : 0;
	if (!from_sm || !target_sm) {
		return bool_variant(GODOT_FALSE);
	}

	godot_bool stack_ok = GODOT_FALSE;
	godot_bool map_ok = GODOT_FALSE;
	godot_variant source_stack_value = object_get_property(from_sm, "states_stack", &stack_ok);
	godot_variant target_map_value = object_get_property(target_sm, "states_map", &map_ok);
	if (!stack_ok || !map_ok ||
		_gdnative_wrapper_api_struct->godot_variant_get_type(&source_stack_value) != GODOT_VARIANT_TYPE_ARRAY ||
		_gdnative_wrapper_api_struct->godot_variant_get_type(&target_map_value) != GODOT_VARIANT_TYPE_DICTIONARY) {
		_gdnative_wrapper_api_struct->godot_variant_destroy(&source_stack_value);
		_gdnative_wrapper_api_struct->godot_variant_destroy(&target_map_value);
		return bool_variant(GODOT_FALSE);
	}

	godot_array source_stack = _gdnative_wrapper_api_struct->godot_variant_as_array(&source_stack_value);
	godot_dictionary target_map = _gdnative_wrapper_api_struct->godot_variant_as_dictionary(&target_map_value);
	godot_array target_stack;
	_gdnative_wrapper_api_struct->godot_array_new(&target_stack);
	const godot_int stack_size = _gdnative_wrapper_api_struct->godot_array_size(&source_stack);
	for (godot_int i = 0; i < stack_size; i++) {
		godot_variant source_state = _gdnative_wrapper_api_struct->godot_array_get(&source_stack, i);
		if (_gdnative_wrapper_api_struct->godot_variant_get_type(&source_state) == GODOT_VARIANT_TYPE_OBJECT) {
			godot_object *state_object = _gdnative_wrapper_api_struct->godot_variant_as_object(&source_state);
			if (state_object) {
				godot_bool name_ok = GODOT_FALSE;
				godot_variant state_name = object_get_property(state_object, "name", &name_ok);
				if (name_ok && _gdnative_wrapper_api_struct->godot_dictionary_has(&target_map, &state_name)) {
					godot_variant target_state = _gdnative_wrapper_api_struct->godot_dictionary_get(&target_map, &state_name);
					_gdnative_wrapper_api_struct->godot_array_append(&target_stack, &target_state);
					_gdnative_wrapper_api_struct->godot_variant_destroy(&target_state);
				}
				_gdnative_wrapper_api_struct->godot_variant_destroy(&state_name);
			}
		}
		_gdnative_wrapper_api_struct->godot_variant_destroy(&source_state);
	}
	if (_gdnative_wrapper_api_struct->godot_array_size(&target_stack) == 0) {
		godot_object *target_state = object_get_object_property(target_sm, "state");
		if (target_state) {
			godot_variant target_state_value;
			_gdnative_wrapper_api_struct->godot_variant_new_object(&target_state_value, target_state);
			_gdnative_wrapper_api_struct->godot_array_append(&target_stack, &target_state_value);
			_gdnative_wrapper_api_struct->godot_variant_destroy(&target_state_value);
		}
	}
	godot_variant target_stack_variant;
	_gdnative_wrapper_api_struct->godot_variant_new_array(&target_stack_variant, &target_stack);
	const godot_bool set_stack_ok = object_set_property_variant(target_sm, "states_stack", &target_stack_variant);
	_gdnative_wrapper_api_struct->godot_variant_destroy(&target_stack_variant);
	_gdnative_wrapper_api_struct->godot_array_destroy(&target_stack);
	_gdnative_wrapper_api_struct->godot_array_destroy(&source_stack);
	_gdnative_wrapper_api_struct->godot_dictionary_destroy(&target_map);
	_gdnative_wrapper_api_struct->godot_variant_destroy(&source_stack_value);
	_gdnative_wrapper_api_struct->godot_variant_destroy(&target_map_value);

	godot_bool queued_ok = GODOT_FALSE;
	godot_variant source_queued_value = object_get_property(from_sm, "queued_states", &queued_ok);
	if (queued_ok && _gdnative_wrapper_api_struct->godot_variant_get_type(&source_queued_value) == GODOT_VARIANT_TYPE_ARRAY) {
		godot_array source_queued = _gdnative_wrapper_api_struct->godot_variant_as_array(&source_queued_value);
		godot_array target_queued;
		_gdnative_wrapper_api_struct->godot_array_new(&target_queued);
		const godot_int queued_size = _gdnative_wrapper_api_struct->godot_array_size(&source_queued);
		for (godot_int i = 0; i < queued_size; i++) {
			godot_variant item = _gdnative_wrapper_api_struct->godot_array_get(&source_queued, i);
			append_state_name_or_value(&target_queued, &item);
			_gdnative_wrapper_api_struct->godot_variant_destroy(&item);
		}
		godot_variant target_queued_variant;
		_gdnative_wrapper_api_struct->godot_variant_new_array(&target_queued_variant, &target_queued);
		object_set_property_variant(target_sm, "queued_states", &target_queued_variant);
		_gdnative_wrapper_api_struct->godot_variant_destroy(&target_queued_variant);
		_gdnative_wrapper_api_struct->godot_array_destroy(&target_queued);
		_gdnative_wrapper_api_struct->godot_array_destroy(&source_queued);
	}
	_gdnative_wrapper_api_struct->godot_variant_destroy(&source_queued_value);

	godot_bool queued_data_ok = GODOT_FALSE;
	godot_variant source_queued_data_value = object_get_property(from_sm, "queued_data", &queued_data_ok);
	if (queued_data_ok && _gdnative_wrapper_api_struct->godot_variant_get_type(&source_queued_data_value) == GODOT_VARIANT_TYPE_ARRAY) {
		godot_array source_queued_data = _gdnative_wrapper_api_struct->godot_variant_as_array(&source_queued_data_value);
		godot_array target_queued_data;
		_gdnative_wrapper_api_struct->godot_array_new_copy(&target_queued_data, &source_queued_data);
		godot_variant target_queued_data_variant;
		_gdnative_wrapper_api_struct->godot_variant_new_array(&target_queued_data_variant, &target_queued_data);
		object_set_property_variant(target_sm, "queued_data", &target_queued_data_variant);
		_gdnative_wrapper_api_struct->godot_variant_destroy(&target_queued_data_variant);
		_gdnative_wrapper_api_struct->godot_array_destroy(&target_queued_data);
		_gdnative_wrapper_api_struct->godot_array_destroy(&source_queued_data);
	}
	_gdnative_wrapper_api_struct->godot_variant_destroy(&source_queued_data_value);

	return bool_variant(set_stack_ok);
}

void GDN_EXPORT godot_gdnative_init(godot_gdnative_init_options *options) {
	GDNATIVE_API_INIT(options);
	load_core_version_apis();
	object_get_bind = _gdnative_wrapper_api_struct->godot_method_bind_get_method("Object", "get");
	object_set_bind = _gdnative_wrapper_api_struct->godot_method_bind_get_method("Object", "set");
}

void GDN_EXPORT godot_gdnative_terminate(godot_gdnative_terminate_options *options) {
	(void)options;
}

void GDN_EXPORT godot_nativescript_init(void *handle) {
	godot_instance_create_func create = { aifastcopy_create, 0, 0 };
	godot_instance_destroy_func destroy = { aifastcopy_destroy, 0, 0 };
	_gdnative_wrapper_nativescript_api_struct->godot_nativescript_register_class(
		handle,
		"AIFastCopy",
		"Reference",
		create,
		destroy
	);

	godot_method_attributes attrs = { GODOT_METHOD_RPC_MODE_DISABLED };
	godot_instance_method method = { copy_properties, 0, 0 };
	_gdnative_wrapper_nativescript_api_struct->godot_nativescript_register_method(
		handle,
		"AIFastCopy",
		"copy_properties",
		attrs,
		method
	);

	godot_instance_method runtime_method = { copy_fighter_runtime, 0, 0 };
	_gdnative_wrapper_nativescript_api_struct->godot_nativescript_register_method(
		handle,
		"AIFastCopy",
		"copy_fighter_runtime",
		attrs,
		runtime_method
	);

	godot_instance_method history_method = { copy_state_history, 0, 0 };
	_gdnative_wrapper_nativescript_api_struct->godot_nativescript_register_method(
		handle,
		"AIFastCopy",
		"copy_state_history",
		attrs,
		history_method
	);
}
