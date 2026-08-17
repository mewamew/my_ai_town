class_name TownResidentProfileEditor
extends RefCounted


const INTERESTS := preload("res://world/data/town/TownInterestCatalog.gd")


static func validate_profile(
	profile: Dictionary,
	place_detail: Callable,
) -> Dictionary:
	for key_value: Variant in profile:
		var key := String(key_value)
		if key not in ["home", "job", "workplace", "attributes"]:
			return _failure(
				"RESIDENT_PROFILE_FIELD_NOT_EDITABLE",
				"居民资料不允许修改字段：%s" % key,
			)
	var attributes_value: Variant = profile.get("attributes")
	if attributes_value is not Dictionary:
		return _failure(
			"RESIDENT_PROFILE_ATTRIBUTES_REQUIRED",
			"居民公开属性必须是对象",
		)
	var attributes := attributes_value as Dictionary
	for key_value: Variant in attributes:
		var key := String(key_value)
		if key not in [
			"gender",
			"age",
			"appearance",
			"desire",
			"personality",
			"speech",
			"interests",
			"customInterests",
		]:
			return _failure(
				"RESIDENT_PROFILE_FIELD_NOT_EDITABLE",
				"居民资料不允许修改字段：%s" % key,
			)
	var gender := String(attributes.get("gender", "")).strip_edges()
	if gender not in ["男", "女"]:
		return _failure(
			"RESIDENT_PROFILE_GENDER_INVALID",
			"居民性别仅支持男或女",
		)
	var age_value: Variant = attributes.get("age")
	if typeof(age_value) not in [TYPE_INT, TYPE_FLOAT]:
		return _failure(
			"RESIDENT_PROFILE_AGE_INVALID",
			"居民年龄必须是数字",
		)
	var age := int(age_value)
	if age < 1 or age > 120:
		return _failure(
			"RESIDENT_PROFILE_AGE_INVALID",
			"居民年龄需在 1 到 120 岁之间",
		)
	var normalized_attributes := {"gender": gender, "age": age}
	if attributes.has("appearance"):
		var appearance := String(attributes.get("appearance", "")).strip_edges()
		if appearance.is_empty() or not appearance.begins_with(
			"resident_wardrobe_v1:",
		):
			return _failure(
				"RESIDENT_PROFILE_APPEARANCE_INVALID",
				"居民外观必须来自正式衣柜",
			)
		normalized_attributes["appearance"] = appearance
	for key in ["desire", "personality", "speech"]:
		var text := String(attributes.get(key, "")).strip_edges()
		if text.is_empty() or text.length() > 1200:
			return _failure(
				"RESIDENT_PROFILE_TEXT_INVALID",
				"居民资料 %s 不能为空且不能超过 1200 字" % key,
			)
		normalized_attributes[key] = text
	var interest_values := INTERESTS.normalize(attributes.get("interests", []))
	var custom_interest_values := INTERESTS.normalize_custom(
		attributes.get("customInterests", []),
	)
	var interest_error := INTERESTS.profile_validation_error(
		interest_values,
		custom_interest_values,
	)
	if not interest_error.is_empty():
		return _failure(
			interest_error,
			"居民兴趣合计最多三项，自定义兴趣需为 1 到 20 个字且不能重复",
		)
	normalized_attributes["interests"] = interest_values
	normalized_attributes["customInterests"] = custom_interest_values
	var social_validation := validate_social_profile(
		{
			"home": profile.get("home", ""),
			"job": profile.get("job", ""),
			"workplace": profile.get("workplace", ""),
		},
		place_detail,
	)
	if social_validation.get("ok") != true:
		return social_validation
	return {
		"ok": true,
		"attributes": normalized_attributes,
		"profile": social_validation.get("profile", {}) as Dictionary,
	}


static func validate_social_profile(
	profile: Dictionary,
	place_detail: Callable,
) -> Dictionary:
	for key_value: Variant in profile:
		var key := String(key_value)
		if key not in ["home", "job", "workplace"]:
			return _failure(
				"RESIDENT_PROFILE_FIELD_NOT_EDITABLE",
				"居民总览不允许修改字段：%s" % key,
			)
	var home := String(profile.get("home", "")).strip_edges()
	var job := String(profile.get("job", "")).strip_edges()
	var workplace := String(profile.get("workplace", "")).strip_edges()
	if home.is_empty():
		return _failure("RESIDENT_PROFILE_HOME_REQUIRED", "居民住所不能为空")
	var home_detail := place_detail.call(home) as Dictionary
	if home_detail.is_empty() or String(home_detail.get("type", "")) != "住家":
		return _failure(
			"RESIDENT_PROFILE_HOME_UNKNOWN",
			"居民住所不是本局可用住宅：%s" % home,
		)
	if job.is_empty():
		return _failure("RESIDENT_PROFILE_JOB_REQUIRED", "居民职业不能为空")
	if workplace.is_empty() or (
		place_detail.call(workplace) as Dictionary
	).is_empty():
		return _failure(
			"RESIDENT_PROFILE_WORKPLACE_UNKNOWN",
			"居民工作地点不是本局可用地点：%s" % workplace,
		)
	return {
		"ok": true,
		"profile": {"home": home, "job": job, "workplace": workplace},
	}


static func apply(
	resident: Dictionary,
	profile_attributes: Dictionary,
	social_profile: Dictionary,
) -> Dictionary:
	var previous_social := (
		resident.get("socialState", {}) as Dictionary
	).duplicate(true)
	var next_social := social_profile.duplicate(true)
	var previous_attributes := (
		resident.get("attributes", {}) as Dictionary
	).duplicate(true)
	var next_attributes := previous_attributes.duplicate(true)
	for key_value: Variant in profile_attributes:
		next_attributes[String(key_value)] = profile_attributes[key_value]
	var changed := (
		previous_social != next_social
		or previous_attributes != next_attributes
	)
	if changed:
		resident["attributes"] = next_attributes
		resident["socialState"] = next_social
	return {
		"changed": changed,
		"profile": next_social,
		"attributes": saved_attributes(next_attributes),
	}


static func saved_attributes(attributes: Dictionary) -> Dictionary:
	return {
		"gender": String(attributes.get("gender", "")),
		"age": int(attributes.get("age", 0)),
		"appearance": String(attributes.get("appearance", "")),
		"desire": String(attributes.get("desire", "")),
		"personality": String(attributes.get("personality", "")),
		"speech": String(attributes.get("speech", "")),
		"interests": INTERESTS.normalize(attributes.get("interests", [])),
		"customInterests": INTERESTS.normalize_custom(
			attributes.get("customInterests", []),
		),
	}


static func _failure(error_code: String, error: String) -> Dictionary:
	return {"ok": false, "errorCode": error_code, "errors": [error]}
