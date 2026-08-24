class_name TownWorldSaveCodec
extends RefCounted


const WORLD_SCALARS := preload("res://world/data/town/TownWorldScalars.gd")
const SCHEMA := "town-world-save"
const SCHEMA_VERSION := TownSaveSchemaRegistry.WORLD_SCHEMA_VERSION
const SUPPORTED_SCHEMA_VERSIONS := TownSaveSchemaRegistry.WORLD_SUPPORTED_SCHEMA_VERSIONS
const TYPE_TAG := "__townWorldType"
const VECTOR2_TAG := "Vector2"
const MAX_SAFE_INTEGER := 9007199254740991.0
const MAX_SAFE_DAY := 6254999482459
const PERIODS := ["清晨", "上午", "中午", "下午", "傍晚", "夜里"]
const ENVELOPE_KEYS := [
	"schema",
	"schemaVersion",
	"worldId",
	"worldDataSchemaVersion",
	"worldDataVersion",
	"savedAt",
	"state",
]
const STATE_KEYS := [
	"environment",
	"owners",
	"residents",
	"playerAvatar",
	"announcements",
	"conversations",
	"eventLog",
	"sequences",
	"indoorLayoutOverrides",
]
const OPTIONAL_STATE_KEYS := [
	"activityRuntime",
	"activityRoutines",
	"workTasks",
	"staffingState",
	"cargoInventory",
	"productionState",
	"occupationServices",
	"privateMessages",
	"activityWorkTaskBindings",
	"socialMatters",
	"communityBulletin",
	"animalFacts",
	"placeServiceStates",
	"residentConditions",
	"residentSleep",
	"conflictState",
	"residentLifecycle",
	"travelerRelations",
	"werewolfState",
]


static func encode_checked(value: Variant) -> Dictionary:
	return _encode_checked(value, "state")


static func _encode_checked(value: Variant, path: String) -> Dictionary:
	match typeof(value):
		TYPE_VECTOR2:
			var point := value as Vector2
			if not is_finite(point.x) or not is_finite(point.y):
				return _encoding_failure(path, "Vector2 包含非有限坐标")
			return {
				"ok": true,
				"value": {TYPE_TAG: VECTOR2_TAG, "x": point.x, "y": point.y},
			}
		TYPE_ARRAY:
			var encoded_array: Array = []
			for index in (value as Array).size():
				var encoded_item := _encode_checked(
					(value as Array)[index],
					"%s[%d]" % [path, index],
				)
				if encoded_item.get("ok") != true:
					return encoded_item
				encoded_array.append(encoded_item.get("value"))
			return {"ok": true, "value": encoded_array}
		TYPE_DICTIONARY:
			var encoded_dictionary := {}
			for key: Variant in value as Dictionary:
				if not key is String:
					return _encoding_failure(path, "字典键必须是字符串")
				if key == TYPE_TAG:
					return _encoding_failure(path, "普通字典不能使用保留类型标签")
				var encoded_value := _encode_checked(
					(value as Dictionary)[key],
					"%s.%s" % [path, key],
				)
				if encoded_value.get("ok") != true:
					return encoded_value
				encoded_dictionary[key] = encoded_value.get("value")
			return {"ok": true, "value": encoded_dictionary}
		TYPE_INT:
			if not _is_safe_integer(value):
				return _encoding_failure(path, "整数超出 JSON 安全范围")
			return {"ok": true, "value": value}
		TYPE_FLOAT:
			if not is_finite(float(value)):
				return _encoding_failure(path, "浮点数必须是有限值")
			return {"ok": true, "value": value}
		TYPE_NIL, TYPE_BOOL, TYPE_STRING:
			return {"ok": true, "value": value}
		_:
			return _encoding_failure(path, "包含不支持的运行时类型 %d" % typeof(value))


static func _encoding_failure(path: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"errorCode": "SAVE_SERIALIZATION_FAILED",
		"retryable": false,
		"errors": ["%s：%s" % [path, message]],
	}


static func decode_checked(value: Variant) -> Dictionary:
	return _decode_checked(value, "state")


static func _decode_checked(value: Variant, path: String) -> Dictionary:
	match typeof(value):
		TYPE_ARRAY:
			var decoded_array: Array = []
			for index in (value as Array).size():
				var decoded_item := _decode_checked(
					(value as Array)[index],
					"%s[%d]" % [path, index],
				)
				if decoded_item.get("ok") != true:
					return decoded_item
				decoded_array.append(decoded_item.get("value"))
			return {"ok": true, "value": decoded_array}
		TYPE_DICTIONARY:
			var source := value as Dictionary
			if source.has(TYPE_TAG):
				if not source.get(TYPE_TAG) is String or source.get(TYPE_TAG) != VECTOR2_TAG:
					return _decoding_failure(path, "包含未知类型标签")
				if not _has_exact_keys(source, [TYPE_TAG, "x", "y"]):
					return _decoding_failure(path, "Vector2 类型标签字段不完整或包含额外字段")
				for coordinate in ["x", "y"]:
					var coordinate_value: Variant = source.get(coordinate)
					if (
						typeof(coordinate_value) not in [TYPE_INT, TYPE_FLOAT]
						or not is_finite(float(coordinate_value))
					):
						return _decoding_failure(
							"%s.%s" % [path, coordinate],
							"Vector2 坐标必须是有限数字",
						)
				return {
					"ok": true,
					"value": Vector2(float(source["x"]), float(source["y"])),
				}
			var decoded_dictionary := {}
			for key: Variant in source:
				if not key is String:
					return _decoding_failure(path, "字典键必须是字符串")
				var decoded_value := _decode_checked(source[key], "%s.%s" % [path, key])
				if decoded_value.get("ok") != true:
					return decoded_value
				decoded_dictionary[key] = decoded_value.get("value")
			return {"ok": true, "value": decoded_dictionary}
		TYPE_INT:
			if not _is_safe_integer(value):
				return _decoding_failure(path, "整数超出 JSON 安全范围")
			return {"ok": true, "value": value}
		TYPE_FLOAT:
			var number := float(value)
			if not is_finite(number):
				return _decoding_failure(path, "浮点数必须是有限值")
			return {
				"ok": true,
				"value": int(number) if _is_safe_integer(number) else number,
			}
		TYPE_NIL, TYPE_BOOL, TYPE_STRING:
			return {"ok": true, "value": value}
		_:
			return _decoding_failure(path, "包含不支持的存档类型 %d" % typeof(value))


static func _decoding_failure(path: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"errorCode": "SAVE_DESERIALIZATION_FAILED",
		"retryable": false,
		"errors": ["%s：%s" % [path, message]],
	}


static func validate_envelope(
	snapshot: Dictionary,
	world_data: Dictionary,
	opening_config: Dictionary,
) -> Array[String]:
	var errors: Array[String] = []
	_validate_exact_keys(snapshot, ENVELOPE_KEYS, "世界存档", errors)
	if not snapshot.get("schema") is String or snapshot.get("schema") != SCHEMA:
		errors.append("世界存档 schema 必须为 %s" % SCHEMA)
	var schema_version := (
		int(snapshot.get("schemaVersion"))
		if _is_safe_integer(snapshot.get("schemaVersion"))
		else -1
	)
	if schema_version not in SUPPORTED_SCHEMA_VERSIONS:
		errors.append(
			"世界存档 schemaVersion 不受支持：%s"
			% [snapshot.get("schemaVersion")]
		)

	var world_id_value: Variant = world_data.get("worldId")
	var expected_world_id := world_id_value as String if world_id_value is String else ""
	if expected_world_id.is_empty():
		errors.append("当前世界数据缺少合法 worldId")
	if (
		not snapshot.get("worldId") is String
		or snapshot.get("worldId") != expected_world_id
	):
		errors.append("世界存档 worldId 与当前世界数据不一致")
	if (
		not opening_config.get("worldId") is String
		or opening_config.get("worldId") != expected_world_id
	):
		errors.append("恢复配置 worldId 与当前世界数据不一致")
	_validate_version_match(
		snapshot.get("worldDataSchemaVersion"),
		world_data.get("schemaVersion"),
		"世界存档使用了不兼容的数据 schemaVersion",
		errors,
	)
	_validate_version_match(
		snapshot.get("worldDataVersion"),
		world_data.get("dataVersion"),
		"世界存档使用了不兼容的世界数据版本",
		errors,
	)
	_validate_saved_at(snapshot.get("savedAt"), errors)
	_validate_state(snapshot.get("state"), schema_version, errors)
	_validate_saved_at_matches_environment(snapshot, errors)
	return errors


static func validate_time_snapshot(
	value: Variant,
	label := "世界时间",
) -> Array[String]:
	var errors: Array[String] = []
	_validate_time_snapshot(value, label, errors)
	return errors


static func _validate_version_match(
	actual: Variant,
	expected: Variant,
	message: String,
	errors: Array[String],
) -> void:
	if (
		not _is_positive_integer(actual)
		or not _is_positive_integer(expected)
		or int(actual) != int(expected)
	):
		errors.append(message)


static func _validate_saved_at(value: Variant, errors: Array[String]) -> void:
	_validate_time_snapshot(value, "世界存档 savedAt", errors)


static func _validate_time_snapshot(
	value: Variant,
	label: String,
	errors: Array[String],
) -> void:
	if not value is Dictionary:
		errors.append("%s 必须是对象" % label)
		return
	var time_snapshot := value as Dictionary
	_validate_exact_keys(
		time_snapshot,
		["day", "clock", "period"],
		label,
		errors,
	)
	if not _is_valid_day(time_snapshot.get("day")):
		errors.append("%s.day 必须为不溢出绝对分钟的正整数" % label)
	var clock_value: Variant = time_snapshot.get("clock")
	var clock := clock_value as String if clock_value is String else ""
	if not _is_valid_clock(clock):
		errors.append("%s.clock 必须是合法 HH:MM" % label)
	var period_value: Variant = time_snapshot.get("period")
	var period := period_value as String if period_value is String else ""
	if period not in PERIODS:
		errors.append("%s.period 不是合法时段" % label)
	elif not clock.is_empty() and _is_valid_clock(clock) and period != _period_for_clock(clock):
		errors.append(
			"%s.period 与 %s.clock 不一致"
			% [label, label.trim_prefix("世界存档 ")]
		)


static func _validate_state(
	value: Variant,
	schema_version: int,
	errors: Array[String],
) -> void:
	if not value is Dictionary:
		errors.append("世界存档缺少 state")
		return
	var state := value as Dictionary
	_validate_required_and_optional_keys(
		state,
		STATE_KEYS,
		OPTIONAL_STATE_KEYS,
		"世界存档 state",
		errors,
	)
	if schema_version >= 2:
		for key in ["socialMatters", "communityBulletin"]:
			if not state.has(key):
				errors.append(
					"世界存档 v2 state 缺少字段：%s" % key
				)
	for key in ["environment", "playerAvatar", "owners", "sequences"]:
		if not state.get(key) is Dictionary:
			errors.append("世界存档 state.%s 必须是对象" % key)
	for key in [
		"residents",
		"announcements",
		"conversations",
		"eventLog",
		"indoorLayoutOverrides",
	]:
		if not state.get(key) is Array:
			errors.append("世界存档 state.%s 必须是数组" % key)
	if (
		state.has("activityRuntime")
		and not state.get("activityRuntime") is Dictionary
	):
		errors.append("世界存档 state.activityRuntime 必须是对象")
	if (
		state.has("activityRoutines")
		and not state.get("activityRoutines") is Dictionary
	):
		errors.append("世界存档 state.activityRoutines 必须是对象")
	if (
		state.has("workTasks")
		and not state.get("workTasks") is Dictionary
	):
		errors.append("世界存档 state.workTasks 必须是对象")
	if (
		state.has("staffingState")
		and not state.get("staffingState") is Dictionary
	):
		errors.append("世界存档 state.staffingState 必须是对象")
	if (
		state.has("cargoInventory")
		and not state.get("cargoInventory") is Dictionary
	):
		errors.append("世界存档 state.cargoInventory 必须是对象")
	if (
		state.has("productionState")
		and not state.get("productionState") is Dictionary
	):
		errors.append("世界存档 state.productionState 必须是对象")
	if (
		state.has("occupationServices")
		and not state.get("occupationServices") is Dictionary
	):
		errors.append("世界存档 state.occupationServices 必须是对象")
	if (
		state.has("activityWorkTaskBindings")
		and not state.get("activityWorkTaskBindings") is Dictionary
	):
		errors.append(
			"世界存档 state.activityWorkTaskBindings 必须是对象"
		)
	if (
		state.has("socialMatters")
		and not state.get("socialMatters") is Dictionary
	):
		errors.append("世界存档 state.socialMatters 必须是对象")
	if (
		state.has("communityBulletin")
		and not state.get("communityBulletin") is Dictionary
	):
		errors.append("世界存档 state.communityBulletin 必须是对象")
	if (
		state.has("werewolfState")
		and not state.get("werewolfState") is Dictionary
	):
		errors.append("世界存档 state.werewolfState 必须是对象")
	if (
		state.has("animalFacts")
		and not state.get("animalFacts") is Dictionary
	):
		errors.append("世界存档 state.animalFacts 必须是对象")
	if (
		state.has("placeServiceStates")
		and not state.get("placeServiceStates") is Dictionary
	):
		errors.append(
			"世界存档 state.placeServiceStates 必须是对象"
		)
	if (
		state.has("residentConditions")
		and not state.get("residentConditions") is Dictionary
	):
		errors.append("世界存档 state.residentConditions 必须是对象")
	if (
		state.has("residentSleep")
		and not state.get("residentSleep") is Dictionary
	):
		errors.append("世界存档 state.residentSleep 必须是对象")


static func _validate_saved_at_matches_environment(
	snapshot: Dictionary,
	errors: Array[String],
) -> void:
	var saved_at_value: Variant = snapshot.get("savedAt")
	var state_value: Variant = snapshot.get("state")
	if not saved_at_value is Dictionary or not state_value is Dictionary:
		return
	var environment_value: Variant = (state_value as Dictionary).get(
		"environment",
	)
	if not environment_value is Dictionary:
		return
	var saved_at := saved_at_value as Dictionary
	var environment := environment_value as Dictionary
	var day_value: Variant = environment.get("day")
	var minute_value: Variant = environment.get("minuteOfDay")
	if (
		not _is_valid_day(saved_at.get("day"))
		or not _is_valid_clock(
			saved_at.get("clock") as String
			if saved_at.get("clock") is String
			else ""
		)
		or not _is_valid_day(day_value)
		or not _is_safe_integer(minute_value)
		or int(minute_value) < 0
		or int(minute_value) >= 24 * 60
	):
		return
	var environment_clock := "%02d:%02d" % [
		int(minute_value) / 60,
		int(minute_value) % 60,
	]
	if (
		int(saved_at.get("day")) != int(day_value)
		or saved_at.get("clock") != environment_clock
		or saved_at.get("period") != _period_for_clock(environment_clock)
	):
		errors.append("世界存档 savedAt 与 state.environment 世界时间不一致")


static func _validate_required_and_optional_keys(
	value: Dictionary,
	required: Array,
	optional: Array,
	label: String,
	errors: Array[String],
) -> void:
	var allowed := required.duplicate()
	allowed.append_array(optional)
	for key: Variant in value:
		if not key is String or key not in allowed:
			errors.append("%s 包含未知字段：%s" % [label, str(key)])
	for required_key: Variant in required:
		if not value.has(required_key):
			errors.append("%s 缺少字段：%s" % [label, required_key])


static func _validate_exact_keys(
	value: Dictionary,
	allowed: Array,
	label: String,
	errors: Array[String],
) -> void:
	for key: Variant in value:
		if not key is String or key not in allowed:
			errors.append("%s 包含未知字段：%s" % [label, str(key)])
	for required_key: Variant in allowed:
		if not value.has(required_key):
			errors.append("%s 缺少字段：%s" % [label, required_key])


static func _has_exact_keys(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size():
		return false
	for key: Variant in expected:
		if not value.has(key):
			return false
	return true


static func _is_positive_integer(value: Variant) -> bool:
	return _is_safe_integer(value) and int(value) > 0


static func _is_valid_day(value: Variant) -> bool:
	return _is_positive_integer(value) and int(value) <= MAX_SAFE_DAY


static func _is_safe_integer(value: Variant) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var number := float(value)
	return (
		is_finite(number)
		and number == roundf(number)
		and number >= -MAX_SAFE_INTEGER
		and number <= MAX_SAFE_INTEGER
	)


static func _is_valid_clock(clock: String) -> bool:
	return WORLD_SCALARS.is_valid_clock(clock)


static func _period_for_clock(clock: String) -> String:
	var minutes := int(clock.substr(0, 2)) * 60 + int(clock.substr(3, 2))
	if minutes >= 21 * 60 or minutes < 5 * 60:
		return "夜里"
	if minutes < 8 * 60:
		return "清晨"
	if minutes < 12 * 60:
		return "上午"
	if minutes < 14 * 60:
		return "中午"
	if minutes < 18 * 60:
		return "下午"
	return "傍晚"


static func has_exact_string_keys(
	value: Dictionary,
	expected: Array,
) -> bool:
	if value.size() != expected.size():
		return false
	for key_value: Variant in value:
		if not key_value is String or not expected.has(key_value as String):
			return false
	return true


static func sequence_from_prefixed_id(
	value: String,
	prefix: String,
) -> int:
	if not value.begins_with(prefix):
		return 0
	var suffix := value.trim_prefix(prefix)
	return int(suffix) if suffix.is_valid_int() else 0


# _prepare_*_restore 家族共享的前置校验入口：空值放行给域默认值,
# 非对象用域自己的文案报错,可选的 key/schemaVersion 严格校验合并在同一处。
static func unpack_optional_domain_snapshot(
	value: Variant,
	type_error: String,
	exact_keys: Array = [],
	schema_versions: Array = [],
	field_error: String = "",
) -> Dictionary:
	if value == null:
		return {"ok": true, "empty": true, "snapshot": {}}
	if not value is Dictionary:
		return {
			"ok": false,
			"empty": false,
			"errors": [type_error],
			"snapshot": {},
		}
	var snapshot := value as Dictionary
	if not exact_keys.is_empty():
		var valid := has_exact_string_keys(snapshot, exact_keys)
		if valid and not schema_versions.is_empty():
			valid = schema_versions.has(snapshot.get("schemaVersion"))
		if not valid:
			return {
				"ok": false,
				"empty": false,
				"errors": [
					field_error if not field_error.is_empty() else type_error
				],
				"snapshot": {},
			}
	return {"ok": true, "empty": false, "snapshot": snapshot}
