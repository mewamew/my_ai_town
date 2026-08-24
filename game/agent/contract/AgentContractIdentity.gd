class_name AgentContractIdentity
extends RefCounted
## AgentContract 拆分模块(批次C之4,纯搬运+跨模块调用改类前缀)。


const WORLD_SCALARS := preload("res://world/data/town/TownWorldScalars.gd")
const SOUL_PROFILE := preload("res://agent/soul/AgentSoulProfile.gd")
static func _validate_me(me: Dictionary, errors: Array[String]) -> void:
	_validate_allowed_fields(me, ["resident_id", "attributes", "social_state", "soul_profile"], "me", errors)
	_validate_resident_id(me, "resident_id", "me.resident_id", errors)
	var attributes := AgentContract._require_dictionary(me, "attributes", "me.attributes", errors)
	if not attributes.is_empty():
		_validate_allowed_fields(
			attributes,
			[
				"name",
				"gender",
				"age",
				"desire",
				"personality",
				"speech",
				"interests",
				"customInterests",
			],
			"me.attributes",
			errors,
		)
		AgentContract._require_non_empty_string(attributes, "name", "me.attributes.name", errors)
		_validate_gender(attributes, "gender", "me.attributes.gender", errors)
		_validate_age(attributes, "age", "me.attributes.age", errors)
		AgentContract._require_non_empty_string(attributes, "desire", "me.attributes.desire", errors)
		AgentContract._require_non_empty_string(attributes, "personality", "me.attributes.personality", errors)
		AgentContract._require_non_empty_string(attributes, "speech", "me.attributes.speech", errors)
		var interest_error := AgentContract.INTERESTS.profile_validation_error(
			attributes.get("interests", []),
			attributes.get("customInterests", []),
		)
		if not interest_error.is_empty():
			errors.append("me.attributes.interests 无效：%s" % interest_error)

	var social_state := AgentContract._require_dictionary(me, "social_state", "me.social_state", errors)
	if not social_state.is_empty():
		_validate_allowed_fields(
			social_state,
			["home", "job", "workplace"],
			"me.social_state",
			errors,
		)
		AgentContract._require_non_empty_string(social_state, "home", "me.social_state.home", errors)
		AgentContract._require_non_empty_string(social_state, "job", "me.social_state.job", errors)
		AgentContract._require_non_empty_string(social_state, "workplace", "me.social_state.workplace", errors)
	if me.has("soul_profile"):
		errors.append_array(SOUL_PROFILE.validate(me.get("soul_profile")))


static func _validate_residents(
	residents: Array,
	me: Dictionary,
	errors: Array[String],
) -> void:
	var resident_ids := {}
	var me_resident_id := String(me.get("resident_id", ""))
	if not me_resident_id.is_empty():
		resident_ids[me_resident_id] = true

	for index in residents.size():
		var path := "residents[%d]" % index
		var value: Variant = residents[index]
		if typeof(value) != TYPE_DICTIONARY:
			errors.append("%s 必须是对象" % path)
			continue
		var resident := value as Dictionary
		_validate_allowed_fields(
			resident,
			[
				"resident_id", "name", "gender", "age", "job", "home",
				"workplace", "lifecycle_status",
			],
			path,
			errors,
		)
		if (
			resident.has("lifecycle_status")
			and String(resident.get("lifecycle_status", ""))
				not in ["alive", "dead"]
		):
			errors.append("%s.lifecycle_status 不是合法生命状态" % path)
		var resident_id := _validate_resident_id(
			resident,
			"resident_id",
			"%s.resident_id" % path,
			errors,
		)
		AgentContract._require_non_empty_string(resident, "name", "%s.name" % path, errors)
		_validate_gender(resident, "gender", "%s.gender" % path, errors)
		_validate_age(resident, "age", "%s.age" % path, errors)
		AgentContract._require_non_empty_string(resident, "job", "%s.job" % path, errors)
		AgentContract._require_non_empty_string(resident, "home", "%s.home" % path, errors)
		AgentContract._require_non_empty_string(resident, "workplace", "%s.workplace" % path, errors)
		if resident_id.is_empty():
			continue
		if resident_ids.has(resident_id):
			errors.append("%s.resident_id 必须在本局居民中唯一" % path)
		resident_ids[resident_id] = true


static func _validate_places(places: Array, errors: Array[String]) -> void:
	var names := {}
	for index in places.size():
		var path := "places[%d]" % index
		var value: Variant = places[index]
		if typeof(value) != TYPE_DICTIONARY:
			errors.append("%s 必须是对象" % path)
			continue
		var place := value as Dictionary
		_validate_allowed_fields(
			place,
			[
				"name",
				"type",
				"summary",
				"features",
				"owner",
				"owner_resident_id",
			],
			path,
			errors,
		)
		var name := AgentContract._require_non_empty_string(place, "name", "%s.name" % path, errors)
		var place_type := AgentContract._require_non_empty_string(place, "type", "%s.type" % path, errors)
		AgentContract._require_non_empty_string(place, "summary", "%s.summary" % path, errors)
		if place.has("features"):
			var features := AgentContract._require_array(
				place,
				"features",
				"%s.features" % path,
				errors,
			)
			var seen_features := {}
			for feature_index in features.size():
				if (
					typeof(features[feature_index]) != TYPE_STRING
					or String(features[feature_index]).strip_edges().is_empty()
				):
					errors.append(
						"%s.features[%d] 必须是非空文本"
						% [path, feature_index]
					)
					continue
				var feature := String(features[feature_index]).strip_edges()
				if seen_features.has(feature):
					errors.append("%s.features 不能重复：%s" % [path, feature])
				seen_features[feature] = true
		if not place_type.is_empty() and not AgentContract.PLACE_TYPES.has(place_type):
			errors.append("%s.type 必须是公共地点、住家或铺面" % path)
		if not place.has("owner"):
			errors.append("%s.owner 缺失" % path)
		elif place_type in ["公共地点", "铺面"] and place["owner"] != null:
			errors.append("%s.owner 在公共地点或铺面必须为 null" % path)
		elif place_type == "住家":
			AgentContract._require_non_empty_string(place, "owner", "%s.owner" % path, errors)
		if not place.has("owner_resident_id"):
			errors.append("%s.owner_resident_id 缺失" % path)
		elif place_type in ["公共地点", "铺面"] and place["owner_resident_id"] != null:
			errors.append("%s.owner_resident_id 在公共地点或铺面必须为 null" % path)
		elif place_type == "住家":
			_validate_resident_id(
				place,
				"owner_resident_id",
				"%s.owner_resident_id" % path,
				errors,
			)
		if not name.is_empty() and names.has(name):
			errors.append("%s.name 必须在本局地点中唯一" % path)
		names[name] = true


static func _validate_gender(
	data: Dictionary,
	key: String,
	path: String,
	errors: Array[String],
) -> void:
	var gender := AgentContract._require_non_empty_string(data, key, path, errors)
	if not gender.is_empty() and gender not in ["男", "女"]:
		errors.append("%s 必须是男或女" % path)


static func _validate_age(
	data: Dictionary,
	key: String,
	path: String,
	errors: Array[String],
) -> void:
	if not data.has(key):
		errors.append("%s 缺失" % path)
		return
	if typeof(data[key]) != TYPE_INT or int(data[key]) <= 0:
		errors.append("%s 必须是正整数" % path)


static func _validate_allowed_fields(
	data: Dictionary,
	allowed_fields: Array,
	path: String,
	errors: Array[String],
) -> void:
	for key: Variant in data:
		if not allowed_fields.has(String(key)):
			errors.append("%s.%s 不是允许字段" % [path, key])


static func _validate_resident_id(
	data: Dictionary,
	key: String,
	path: String,
	errors: Array[String],
) -> String:
	var resident_id := AgentContract._require_non_empty_string(data, key, path, errors)
	if resident_id.is_empty():
		return ""
	if not _resident_id_is_safe(resident_id):
		errors.append("%s 只能包含最多 128 个 ASCII 小写字母、数字、下划线和连字符" % path)
	return resident_id


static func _resident_id_is_safe(resident_id: String) -> bool:
	return WORLD_SCALARS.resident_id_is_safe(resident_id)
