class_name AgentResidentStateCodec
extends RefCounted


const FORMAT_VERSION := 2


func encode(resident_id: String, resident_name: String, resident_state: Variant) -> Dictionary:
	if resident_id.is_empty():
		return {"ok": false, "errors": ["居民状态 codec 需要非空 resident_id"]}
	if resident_name.is_empty():
		return {"ok": false, "errors": ["居民状态 codec 需要非空居民显示名"]}
	if typeof(resident_state) != TYPE_DICTIONARY:
		return {"ok": false, "errors": ["居民 %s 的持久状态必须是对象" % resident_id]}
	var envelope := {
		"format_version": FORMAT_VERSION,
		"resident_id": resident_id,
		"resident_name": resident_name,
		"resident_state": (resident_state as Dictionary).duplicate(true),
	}
	return {"ok": true, "payload": var_to_bytes(envelope)}


func decode(
	expected_resident_id: String,
	expected_resident_name: String,
	payload: Variant,
) -> Dictionary:
	if expected_resident_id.is_empty():
		return {"ok": false, "errors": ["居民状态 codec 需要非空目标 resident_id"]}
	if typeof(payload) != TYPE_PACKED_BYTE_ARRAY:
		return {"ok": false, "errors": ["居民 %s 的持久载荷必须是 PackedByteArray" % expected_resident_id]}
	var decoded: Variant = bytes_to_var(payload as PackedByteArray)
	if typeof(decoded) != TYPE_DICTIONARY:
		return {"ok": false, "errors": ["居民 %s 的持久载荷不是对象" % expected_resident_id]}
	var envelope := decoded as Dictionary
	if envelope.get("format_version") != FORMAT_VERSION:
		return {"ok": false, "errors": ["居民 %s 的状态 codec 版本不受支持" % expected_resident_id]}
	var payload_resident_id := String(envelope.get("resident_id", ""))
	var payload_resident_name := String(envelope.get("resident_name", ""))
	if (
		payload_resident_id != expected_resident_id
		or payload_resident_name != expected_resident_name
	):
		return {
			"ok": false,
			"errors": [
				"居民载荷身份串用：清单为 %s（%s），载荷为 %s（%s）"
					% [
						expected_resident_id,
						expected_resident_name,
						payload_resident_id,
						payload_resident_name,
					],
			],
		}
	if typeof(envelope.get("resident_state")) != TYPE_DICTIONARY:
		return {"ok": false, "errors": ["居民 %s 的持久状态损坏" % expected_resident_id]}
	return {
		"ok": true,
		"resident_id": payload_resident_id,
		"resident_name": payload_resident_name,
		"resident_state": (envelope["resident_state"] as Dictionary).duplicate(true),
	}


func equivalent_initialization(left: Variant, right: Variant) -> bool:
	if typeof(left) != TYPE_DICTIONARY or typeof(right) != TYPE_DICTIONARY:
		return false
	return equivalent(
		_initialization_without_display_names(left as Dictionary),
		_initialization_without_display_names(right as Dictionary),
	)


func initialization_difference_paths(
	left: Variant,
	right: Variant,
	limit := 24,
) -> Array[String]:
	if typeof(left) != TYPE_DICTIONARY or typeof(right) != TYPE_DICTIONARY:
		return ["initialization"]
	var differences: Array[String] = []
	_collect_difference_paths(
		_initialization_without_display_names(left as Dictionary),
		_initialization_without_display_names(right as Dictionary),
		"initialization",
		differences,
		maxi(limit, 1),
	)
	return differences


func _collect_difference_paths(
	left: Variant,
	right: Variant,
	path: String,
	differences: Array[String],
	limit: int,
) -> void:
	if differences.size() >= limit:
		return
	if typeof(left) != typeof(right):
		differences.append(path)
		return
	if left is Dictionary:
		var left_dictionary := left as Dictionary
		var right_dictionary := right as Dictionary
		var keys: Array = left_dictionary.keys()
		for key: Variant in right_dictionary:
			if not keys.has(key):
				keys.append(key)
		keys.sort_custom(func(a: Variant, b: Variant) -> bool:
			return String(a) < String(b)
		)
		for key: Variant in keys:
			if differences.size() >= limit:
				return
			var child_path := "%s.%s" % [path, String(key)]
			if (
				not left_dictionary.has(key)
				or not right_dictionary.has(key)
			):
				differences.append(child_path)
				continue
			_collect_difference_paths(
				left_dictionary[key],
				right_dictionary[key],
				child_path,
				differences,
				limit,
			)
		return
	if left is Array:
		var left_array := left as Array
		var right_array := right as Array
		if left_array.size() != right_array.size():
			differences.append("%s.size" % path)
		for index in mini(left_array.size(), right_array.size()):
			if differences.size() >= limit:
				return
			_collect_difference_paths(
				left_array[index],
				right_array[index],
				"%s[%d]" % [path, index],
				differences,
				limit,
			)
		return
	if left != right:
		differences.append(path)


func _initialization_without_display_names(initialization: Dictionary) -> Dictionary:
	var normalized := initialization.duplicate(true)
	var me_value: Variant = normalized.get("me")
	if typeof(me_value) == TYPE_DICTIONARY:
		var attributes_value: Variant = (me_value as Dictionary).get("attributes")
		if typeof(attributes_value) == TYPE_DICTIONARY:
			(attributes_value as Dictionary).erase("name")
		# 金钱/声望是运行时动态数值,不属于居民存档身份,不应参与
		# 恢复时的初始化等价比较(旧档无这些字段,新档有,直接比较会误判)。
		var me_social: Variant = (me_value as Dictionary).get("social_state")
		if typeof(me_social) == TYPE_DICTIONARY:
			(me_social as Dictionary).erase("money")
			(me_social as Dictionary).erase("reputation")
	var residents_value: Variant = normalized.get("residents")
	if typeof(residents_value) == TYPE_ARRAY:
		for resident_value: Variant in residents_value as Array:
			if typeof(resident_value) != TYPE_DICTIONARY:
				continue
			var resident := resident_value as Dictionary
			resident.erase("name")
			# 其他居民的财富/声望同为运行时动态数值,不参与身份等价比较。
			resident.erase("money")
			resident.erase("reputation")
	var places_value: Variant = normalized.get("places")
	if typeof(places_value) == TYPE_ARRAY:
		for place_value: Variant in places_value as Array:
			if typeof(place_value) != TYPE_DICTIONARY:
				continue
			var place := place_value as Dictionary
			# 地点简介和可见物件来自当前 World 内容，不属于居民存档身份。
			# 正式内容补充这些展示事实时应继续恢复原有记忆，并让恢复后的
			# ResidentRuntime 使用当前初始化，而不是把旧内容写回 World。
			place.erase("summary")
			place.erase("features")
			if place.has("owner_resident_id"):
				place.erase("owner")
	return normalized


func equivalent(left: Variant, right: Variant) -> bool:
	if (typeof(left) == TYPE_INT or typeof(left) == TYPE_FLOAT) \
		and (typeof(right) == TYPE_INT or typeof(right) == TYPE_FLOAT):
		return float(left) == float(right)
	if typeof(left) != typeof(right):
		return false
	if typeof(left) == TYPE_DICTIONARY:
		var left_dictionary := left as Dictionary
		var right_dictionary := right as Dictionary
		if left_dictionary.size() != right_dictionary.size():
			return false
		for key: Variant in left_dictionary:
			if not right_dictionary.has(key) \
				or not equivalent(left_dictionary[key], right_dictionary[key]):
				return false
		return true
	if typeof(left) == TYPE_ARRAY:
		var left_array := left as Array
		var right_array := right as Array
		if left_array.size() != right_array.size():
			return false
		for index in left_array.size():
			if not equivalent(left_array[index], right_array[index]):
				return false
		return true
	return left == right
