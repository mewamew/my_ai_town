class_name TownWorldOpeningConfig
extends RefCounted


const WORLD_SCALARS := preload("res://world/data/town/TownWorldScalars.gd")
const INTERESTS := preload(
	"res://world/data/town/TownInterestCatalog.gd"
)
const SOUL_PROFILE := preload("res://agent/soul/AgentSoulProfile.gd")
const BODY_VALUES := {
	"困": ["不困", "有点困", "很困"],
	"饿": ["不饿", "有点饿", "很饿"],
	"累": ["不累", "有点累", "很累"],
}
const WEATHER_VALUES := ["晴天", "阴天", "小雨", "中雨", "大雨", "雷暴", "下雪"]
const MAX_SAFE_INTEGER := 9007199254740991.0
const MAX_SAFE_DAY := 6254999482459
const MAX_CANVAS_COMPONENT := 1_000_000.0


static func load_config(path: String, world_data: Dictionary) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {"ok": false, "errors": ["世界开局配置不存在：%s" % path]}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "errors": ["世界开局配置必须是 JSON 对象"]}
	var config := _normalize_numbers(parsed) as Dictionary
	var errors := validate(config, world_data)
	return {"ok": errors.is_empty(), "config": config.duplicate(true), "errors": errors}


static func validate(config: Dictionary, world_data: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	_validate_exact_keys(
		config,
		["schemaVersion", "worldId", "environment", "ownerAssignments", "residents", "agentSoulProfiles", "playerAvatar"],
		"世界开局配置",
		errors,
	)
	if not _is_exact_integer(config.get("schemaVersion"), 1):
		errors.append("世界开局配置 schemaVersion 必须为 1")
	if not _is_nonempty_string(config.get("worldId")):
		errors.append("世界开局配置 worldId 必须是非空文本")
	elif config.get("worldId") != world_data.get("worldId"):
		errors.append("世界开局配置 worldId 与世界数据不一致")
	var environment_value: Variant = config.get("environment")
	if not environment_value is Dictionary:
		errors.append("世界开局配置 environment 必须是对象")
	else:
		_validate_environment(environment_value as Dictionary, errors)
	var places := _place_index(world_data)
	var residents_value: Variant = config.get("residents")
	if not residents_value is Array:
		errors.append("世界开局配置 residents 必须是数组")
	var residents := residents_value as Array if residents_value is Array else []
	var resident_ids := {}
	var resident_names: Array[String] = []
	var homes_by_resident_id := {}
	var residents_by_home := {}
	for index in residents.size():
		if typeof(residents[index]) != TYPE_DICTIONARY:
			errors.append("residents[%d] 必须是对象" % index)
			continue
		var resident := residents[index] as Dictionary
		_validate_exact_keys(
			resident,
			["residentId", "attributes", "socialState", "worldState"],
			"residents[%d]" % index,
			errors,
		)
		var resident_id_value: Variant = resident.get("residentId")
		var resident_id := (
			(resident_id_value as String).strip_edges()
			if resident_id_value is String
			else ""
		)
		if (
			resident_id.is_empty()
			or resident_id_value != resident_id
			or not _resident_id_is_safe(resident_id)
		):
			errors.append("residents[%d].residentId 无效" % index)
		elif resident_ids.has(resident_id):
			errors.append("residentId 重复：%s" % resident_id)
		else:
			resident_ids[resident_id] = true
		var attributes_value: Variant = resident.get("attributes")
		if not attributes_value is Dictionary:
			errors.append("residents[%d].attributes 必须是对象" % index)
		var attributes := attributes_value as Dictionary if attributes_value is Dictionary else {}
		var name := String(attributes.get("name", "")).strip_edges() if attributes.get("name") is String else ""
		if name.is_empty():
			errors.append("居民名字缺失")
		else:
			resident_names.append(name)
		_validate_attributes(name, attributes, errors)
		var social_value: Variant = resident.get("socialState")
		if not social_value is Dictionary:
			errors.append("residents[%d].socialState 必须是对象" % index)
		var social_state := social_value as Dictionary if social_value is Dictionary else {}
		_validate_social_state(name, social_state, places, errors)
		var home := String(social_state.get("home", "")).strip_edges() if social_state.get("home") is String else ""
		if not resident_id.is_empty() and not home.is_empty():
			homes_by_resident_id[resident_id] = home
			if residents_by_home.has(home):
				errors.append("住家被多个居民占用：%s" % home)
			else:
				residents_by_home[home] = resident_id
		var world_state_value: Variant = resident.get("worldState")
		if not world_state_value is Dictionary:
			errors.append("residents[%d].worldState 必须是对象" % index)
		else:
			_validate_world_state(name, world_state_value as Dictionary, world_data, errors)
	var home_count := 0
	for place_value: Variant in world_data.get("places", []) as Array:
		if String((place_value as Dictionary).get("type", "")) == "住家":
			home_count += 1
	if residents.size() != home_count:
		errors.append("居民数量必须等于住家槽位数量 %d，实际为 %d" % [home_count, residents.size()])
	if config.has("agentSoulProfiles"):
		_validate_soul_profiles(
			config.get("agentSoulProfiles"),
			resident_ids,
			errors,
		)
	for place_name_value: Variant in places:
		var place_name := String(place_name_value)
		if String((places[place_name] as Dictionary).get("type", "")) == "住家" and not residents_by_home.has(place_name):
			errors.append("住家没有对应居民：%s" % place_name)
	var owners_value: Variant = config.get("ownerAssignments")
	if not owners_value is Dictionary:
		errors.append("世界开局配置 ownerAssignments 必须是对象")
	_validate_owners(
		owners_value as Dictionary if owners_value is Dictionary else {},
		places,
		resident_ids,
		homes_by_resident_id,
		errors,
	)
	var avatar_value: Variant = config.get("playerAvatar")
	if not avatar_value is Dictionary:
		errors.append("世界开局配置 playerAvatar 必须是对象")
	var avatar := avatar_value as Dictionary if avatar_value is Dictionary else {}
	_validate_exact_keys(avatar, ["residentId", "name", "worldState"], "playerAvatar", errors)
	var avatar_id_value: Variant = avatar.get("residentId")
	var avatar_id := (
		(avatar_id_value as String).strip_edges()
		if avatar_id_value is String
		else ""
	)
	if (
		avatar_id.is_empty()
		or avatar_id_value != avatar_id
		or not _resident_id_is_safe(avatar_id)
		or resident_ids.has(avatar_id)
	):
		errors.append("玩家化身必须有不与居民重复的合法 residentId")
	var avatar_name := String(avatar.get("name", "")).strip_edges() if avatar.get("name") is String else ""
	if avatar_name.is_empty():
		errors.append("玩家化身必须有世界内名字")
	var avatar_world_state_value: Variant = avatar.get("worldState")
	if not avatar_world_state_value is Dictionary:
		errors.append("playerAvatar.worldState 必须是对象")
	else:
		_validate_world_state(avatar_name, avatar_world_state_value as Dictionary, world_data, errors, false)
	return errors


static func resident_names(config: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in config.get("residents", []) as Array:
		result.append(String((value as Dictionary).get("attributes", {}).get("name", "")))
	return result


static func resident_ids(config: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in config.get("residents", []) as Array:
		var resident_id := String((value as Dictionary).get("residentId", "")).strip_edges()
		if not resident_id.is_empty():
			result.append(resident_id)
	result.sort()
	return result


static func resident_record(config: Dictionary, resident_ref: String) -> Dictionary:
	var matching_name_records: Array[Dictionary] = []
	for value: Variant in config.get("residents", []) as Array:
		var resident := value as Dictionary
		if String(resident.get("residentId", "")) == resident_ref:
			return resident.duplicate(true)
		if String(resident.get("attributes", {}).get("name", "")) == resident_ref:
			matching_name_records.append(resident)
	if matching_name_records.size() == 1:
		return matching_name_records[0].duplicate(true)
	return {}


static func prepare_resident_identities(
	config: Dictionary,
	identity_values: Variant,
	require_confirmed: bool,
) -> Dictionary:
	var opening_identities: Array[Dictionary] = []
	var opening_ids := {}
	for value: Variant in config.get("residents", []) as Array:
		var resident := value as Dictionary
		var resident_id := String(resident.get("residentId", "")).strip_edges()
		var resident_name := String(resident.get("attributes", {}).get("name", "")).strip_edges()
		if not resident_id.is_empty():
			opening_identities.append({"residentId": resident_id, "residentName": resident_name})
			opening_ids[resident_id] = resident_name
	opening_identities.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("residentId", "")) < String(b.get("residentId", ""))
	)
	if not (identity_values is Array):
		return _identity_failure(
			"WORLD_RESIDENT_IDENTITIES_INVALID",
			"居民身份集合必须是数组",
		)
	var values := identity_values as Array
	if values.is_empty():
		if not opening_identities.is_empty():
			return {
				"ok": true,
				"errorCode": "",
				"retryable": false,
				"status": "confirmed",
				"residents": opening_identities,
			}
		var opening_names := resident_names(config)
		opening_names.sort()
		if require_confirmed and not opening_names.is_empty():
			return _identity_failure(
				"WORLD_RESIDENT_IDENTITIES_REQUIRED",
				"正式世界启动必须提供稳定居民 ID 与显示名称集合",
			)
		var compatibility_residents: Array[Dictionary] = []
		for resident_name in opening_names:
			compatibility_residents.append({
				"residentId": resident_name,
				"residentName": resident_name,
			})
		return {
			"ok": true,
			"errorCode": "",
			"retryable": false,
			"status": "compatibility",
			"residents": compatibility_residents,
		}
	var id_to_name := {}
	var errors: Array[String] = []
	for index in values.size():
		var value: Variant = values[index]
		if not (value is Dictionary):
			errors.append("residentIdentities[%d] 必须是对象" % index)
			continue
		var identity := value as Dictionary
		_validate_exact_keys(
			identity,
			["residentId", "residentName"],
			"residentIdentities[%d]" % index,
			errors,
		)
		var resident_id_value: Variant = identity.get("residentId")
		var resident_id := (
			(resident_id_value as String).strip_edges()
			if resident_id_value is String
			else ""
		)
		var resident_name_value: Variant = identity.get("residentName")
		var resident_name := (
			(resident_name_value as String).strip_edges()
			if resident_name_value is String
			else ""
		)
		if resident_id.is_empty() or resident_id_value != resident_id:
			errors.append("residentIdentities[%d].residentId 不能为空" % index)
		elif not _resident_id_is_safe(resident_id):
			errors.append(
				"residentIdentities[%d].residentId 只能包含最多 128 个 ASCII 小写字母、数字、下划线和连字符"
				% index,
			)
		elif id_to_name.has(resident_id):
			errors.append("residentId 重复：%s" % resident_id)
		if resident_name.is_empty() or resident_name_value != resident_name:
			errors.append("residentIdentities[%d].residentName 不能为空" % index)
		if (
			not resident_id.is_empty()
			and not resident_name.is_empty()
			and not id_to_name.has(resident_id)
		):
			id_to_name[resident_id] = resident_name
	if not errors.is_empty():
		return _identity_failure(
			"WORLD_RESIDENT_IDENTITIES_INVALID",
			"; ".join(errors),
		)
	if not opening_ids.is_empty():
		if id_to_name != opening_ids:
			return _identity_failure(
				"WORLD_RESIDENT_IDENTITY_SET_MISMATCH",
				"居民身份集合必须与 opening 中的 residentId 与显示名称完全一致",
			)
	else:
		var identity_names: Array[String] = []
		for resident_name_value: Variant in id_to_name.values():
			identity_names.append(String(resident_name_value))
		identity_names.sort()
		var opening_names := resident_names(config)
		opening_names.sort()
		if identity_names != opening_names:
			return _identity_failure(
				"WORLD_RESIDENT_IDENTITY_SET_MISMATCH",
				"居民身份集合必须与 opening 居民集合一一对应",
			)
	var resident_ids: Array[String] = []
	for resident_id_value: Variant in id_to_name:
		resident_ids.append(String(resident_id_value))
	resident_ids.sort()
	var residents: Array[Dictionary] = []
	for resident_id in resident_ids:
		residents.append({
			"residentId": resident_id,
			"residentName": String(id_to_name[resident_id]),
		})
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"status": "confirmed",
		"residents": residents,
	}


static func _identity_failure(error_code: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"errorCode": error_code,
		"retryable": false,
		"status": "invalid",
		"residents": [],
		"errors": [message],
	}


static func _resident_id_is_safe(resident_id: String) -> bool:
	return WORLD_SCALARS.resident_id_is_safe(resident_id)


static func _validate_environment(environment: Dictionary, errors: Array[String]) -> void:
	_validate_exact_keys(environment, ["day", "clock", "weather", "randomSeed"], "environment", errors)
	if not _is_valid_day(environment.get("day")):
		errors.append("开局天数必须为不溢出绝对分钟的正整数")
	var clock := String(environment.get("clock", "")) if environment.get("clock") is String else ""
	if not _is_valid_clock(clock):
		errors.append("开局时钟必须是合法 HH:MM")
	if not environment.get("weather") is String or not WEATHER_VALUES.has(environment.get("weather")):
		errors.append("开局天气不是合法值")
	if typeof(environment.get("randomSeed")) != TYPE_INT:
		errors.append("开局天气随机种子必须是整数")


static func _validate_attributes(name: String, attributes: Dictionary, errors: Array[String]) -> void:
	var normalized := INTERESTS.migrate_attributes(attributes)
	_validate_exact_keys(
		normalized,
		[
			"name",
			"gender",
			"age",
			"appearance",
			"desire",
			"personality",
			"speech",
			"interests",
			"customInterests",
		],
		"居民 %s 的 attributes" % name,
		errors,
	)
	if not _is_nonempty_string(normalized.get("name")):
		errors.append("居民名字必须是非空文本")
	if not normalized.get("gender") is String or not ["男", "女"].has(normalized.get("gender")):
		errors.append("居民 %s 的性别无效" % name)
	if (
		not _is_positive_integer(normalized.get("age"))
		or int(normalized.get("age", 0)) > 120
	):
		errors.append("居民 %s 的年龄必须是 1..120 的整数" % name)
	if normalized.has("appearance") and not _is_nonempty_string(normalized.get("appearance")):
		errors.append("居民 %s 的外观标识必须是非空文本" % name)
	for key in ["desire", "personality", "speech"]:
		if not _is_nonempty_string(normalized.get(key)):
			errors.append("居民 %s 缺少属性 %s" % [name, key])
	var interest_error := INTERESTS.profile_validation_error(
		normalized.get("interests", []),
		normalized.get("customInterests", []),
	)
	if not interest_error.is_empty():
		errors.append("居民 %s 的兴趣无效：%s" % [name, interest_error])


static func _validate_soul_profiles(
	value: Variant,
	resident_ids: Dictionary,
	errors: Array[String],
) -> void:
	# 老存档没有该可选域时按空资料兼容；新游戏编译器会始终写入它。
	if value == null:
		return
	if not value is Dictionary:
		errors.append("世界开局配置 agentSoulProfiles 必须是对象")
		return
	var profiles := value as Dictionary
	for resident_id_value: Variant in profiles:
		var resident_id := String(resident_id_value)
		if not resident_ids.has(resident_id):
			errors.append("agentSoulProfiles 包含未知居民：%s" % resident_id)
			continue
		var profile_errors := SOUL_PROFILE.validate(profiles[resident_id_value])
		for profile_error in profile_errors:
			errors.append("agentSoulProfiles.%s：%s" % [resident_id, profile_error])
	for resident_id: Variant in resident_ids:
		if not profiles.has(resident_id):
			errors.append("agentSoulProfiles 缺少居民：%s" % String(resident_id))


static func _validate_social_state(name: String, state: Dictionary, places: Dictionary, errors: Array[String]) -> void:
	_validate_exact_keys(state, ["home", "job", "workplace"], "居民 %s 的 socialState" % name, errors)
	for key in ["home", "workplace"]:
		var place_value: Variant = state.get(key)
		var place_name := (
			(place_value as String).strip_edges()
			if place_value is String
			else ""
		)
		if place_name.is_empty() or place_value != place_name:
			errors.append("居民 %s 的 %s 不能为空" % [name, key])
		elif not places.has(place_name):
			errors.append("居民 %s 的 %s 不是已知地点" % [name, key])
	if not _is_nonempty_string(state.get("job")):
		errors.append("居民 %s 缺少职业" % name)


static func _validate_world_state(
	name: String,
	state: Dictionary,
	world_data: Dictionary,
	errors: Array[String],
	validate_body := true,
) -> void:
	var allowed_fields: Array[String] = ["place", "spaceId", "regionId", "position", "doing"]
	if validate_body:
		allowed_fields.append("body")
	_validate_exact_keys(
		state,
		allowed_fields,
		"人物 %s 的 worldState" % name,
		errors,
	)
	for key in ["place", "spaceId", "regionId", "doing"]:
		if not _is_nonempty_string(state.get(key)):
			errors.append("人物 %s 的 %s 必须是非空文本" % [name, key])
	if not _is_pair(state.get("position")):
		errors.append("人物 %s 的开局位置无效" % name)
		return
	var membership := _membership_for_state(state, world_data)
	if membership.is_empty():
		errors.append("人物 %s 的位置不属于声明的空间与区域" % name)
	elif String(membership.get("placeName", "")) != String(state.get("place", "")):
		errors.append("人物 %s 的开局地点与位置归属不一致" % name)
	if not validate_body:
		return
	var body_state_value: Variant = state.get("body")
	if not body_state_value is Dictionary:
		errors.append("人物 %s 的 body 必须是对象" % name)
		return
	if validate_body:
		var body := body_state_value as Dictionary
		for body_name_value: Variant in body:
			if not body_name_value is String or not BODY_VALUES.has(body_name_value as String):
				errors.append("居民 %s 包含未知身体状态：%s" % [name, str(body_name_value)])
		for body_name: String in BODY_VALUES:
			var body_value := String(body.get(body_name, "")).strip_edges()
			if body_value.is_empty() or not (BODY_VALUES[body_name] as Array).has(body_value):
				errors.append("居民 %s 的身体状态无效：%s" % [name, body_name])


static func _validate_owners(
	owners: Dictionary,
	places: Dictionary,
	resident_ids: Dictionary,
	homes_by_resident_id: Dictionary,
	errors: Array[String],
) -> void:
	for place_name_value: Variant in owners:
		if not place_name_value is String or not owners[place_name_value] is String:
			errors.append("归属配置的地点和居民 ID 必须是文本")
	for place_name_value: Variant in places:
		var place_name := String(place_name_value)
		var place := places[place_name] as Dictionary
		var place_type := String(place.get("type", ""))
		if place_type == "公共地点":
			if owners.has(place_name):
				errors.append("公共地点不能分配归属人：%s" % place_name)
			continue
		if place_type == "住家" and (
			not owners.has(place_name)
			or not resident_ids.has(String(owners.get(place_name, "")))
		):
			errors.append("住家缺少合法居民归属：%s" % place_name)
		elif (
			place_type == "铺面"
			and owners.has(place_name)
			and not resident_ids.has(String(owners.get(place_name, "")))
		):
			errors.append("铺面归属引用非法居民：%s" % place_name)
	for place_name_value: Variant in owners:
		if not places.has(String(place_name_value)):
			errors.append("归属配置引用未知地点：%s" % place_name_value)
	for resident_id_value: Variant in homes_by_resident_id:
		var resident_id := String(resident_id_value)
		var home_name := String(homes_by_resident_id[resident_id])
		if owners.get(home_name) != resident_id:
			errors.append("居民 %s 必须归属自己的住家 %s" % [resident_id, home_name])


static func _membership_for_state(state: Dictionary, world_data: Dictionary) -> Dictionary:
	var pair := state.get("position", []) as Array
	var position := Vector2(float(pair[0]), float(pair[1]))
	var expected_space := String(state.get("spaceId", ""))
	var expected_region := String(state.get("regionId", ""))
	for value: Variant in world_data.get("perceptionRegions", []) as Array:
		var region := value as Dictionary
		if String(region.get("id", "")) != expected_region or String(region.get("spaceId", "")) != expected_space:
			continue
		if _position_in_shape(position, region.get("shape", {}) as Dictionary):
			return {"regionId": expected_region, "spaceId": expected_space, "placeName": String(region.get("placeName", ""))}
	return {}


static func _position_in_shape(position: Vector2, shape: Dictionary) -> bool:
	if String(shape.get("type", "")) == "grid_cells":
		var cell_size := int(shape.get("cellSize", 0))
		if cell_size <= 0:
			return false
		var expected := Vector2i(floori(position.x / float(cell_size)), floori(position.y / float(cell_size)))
		for value: Variant in shape.get("cells", []) as Array:
			var pair := value as Array
			if Vector2i(int(pair[0]), int(pair[1])) == expected:
				return true
		return false
	if String(shape.get("type", "")) == "rect":
		return Rect2(float(shape.get("x", 0.0)), float(shape.get("y", 0.0)), float(shape.get("width", 0.0)), float(shape.get("height", 0.0))).has_point(position)
	return false


static func _place_index(world_data: Dictionary) -> Dictionary:
	var result := {}
	for value: Variant in world_data.get("places", []) as Array:
		var place := value as Dictionary
		result[String(place.get("name", ""))] = place
	return result


static func _is_pair(value: Variant) -> bool:
	return (
		value is Array
		and (value as Array).size() == 2
		and _is_finite_number((value as Array)[0])
		and _is_finite_number((value as Array)[1])
		and absf(float((value as Array)[0])) <= MAX_CANVAS_COMPONENT
		and absf(float((value as Array)[1])) <= MAX_CANVAS_COMPONENT
	)


static func _is_valid_clock(clock: String) -> bool:
	if (
		clock.length() != 5
		or clock.substr(2, 1) != ":"
		or not _is_ascii_digit(clock.substr(0, 1))
		or not _is_ascii_digit(clock.substr(1, 1))
		or not _is_ascii_digit(clock.substr(3, 1))
		or not _is_ascii_digit(clock.substr(4, 1))
	):
		return false
	var parts := clock.split(":")
	return int(parts[0]) in range(24) and int(parts[1]) in range(60)


static func _is_ascii_digit(character: String) -> bool:
	return WORLD_SCALARS.is_ascii_digit(character)


static func _is_finite_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


static func _is_positive_integer(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and int(value) > 0


static func _is_valid_day(value: Variant) -> bool:
	return _is_positive_integer(value) and int(value) <= MAX_SAFE_DAY


static func _is_nonempty_string(value: Variant) -> bool:
	return (
		value is String
		and not (value as String).is_empty()
		and value == (value as String).strip_edges()
	)


static func _is_exact_integer(value: Variant, expected: int) -> bool:
	return typeof(value) == TYPE_INT and int(value) == expected


static func _validate_exact_keys(
	value: Dictionary,
	allowed: Array[String],
	label: String,
	errors: Array[String],
) -> void:
	for key_value: Variant in value:
		if not key_value is String or not allowed.has(key_value as String):
			errors.append("%s 包含未知字段：%s" % [label, str(key_value)])


static func _normalize_numbers(value: Variant) -> Variant:
	if typeof(value) == TYPE_FLOAT:
		var number := float(value)
		if (
			is_finite(number)
			and number == floorf(number)
			and absf(number) <= MAX_SAFE_INTEGER
		):
			return int(number)
		return number
	if typeof(value) == TYPE_ARRAY:
		var result: Array = []
		for item: Variant in value:
			result.append(_normalize_numbers(item))
		return result
	if typeof(value) == TYPE_DICTIONARY:
		var result := {}
		for key: Variant in value:
			result[key] = _normalize_numbers(value[key])
		return result
	return value
