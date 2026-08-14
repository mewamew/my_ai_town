class_name AgentResidentEvidenceQueue
extends RefCounted


const AgentContractScript := preload("res://agent/AgentContract.gd")
const AgentJsonScript := preload("res://agent/AgentJson.gd")
const STATE_VERSION := 1
const MAX_ITEMS := 16

var _path: String
var _items: Array[Dictionary] = []
var _known_source_hashes: Dictionary = {}
var _new_items_since_organization := 0
var _loaded := false
var _file_expected := false
var _synced_file_sha256 := ""
var _directory_ready := false


func _init(path: String) -> void:
	_path = path


func read() -> Dictionary:
	var load_result := _ensure_loaded()
	if not bool(load_result.get("ok", false)):
		return load_result
	return {
		"ok": true,
		"items": _items.duplicate(true),
		"new_items_since_organization": _new_items_since_organization,
	}


func ensure_ready() -> Dictionary:
	# ResidentMemorySystem 只需要确认队列可读时，不必为了这个检查深拷贝
	# 整份证据历史。真正需要整理记忆时仍通过 read() 取得独占副本。
	return _ensure_loaded()


func initialize_empty() -> Dictionary:
	if FileAccess.file_exists(_path):
		return _ensure_loaded()
	var write_result := _replace_file([])
	if not bool(write_result.get("ok", false)):
		return write_result
	_items = []
	_known_source_hashes = {}
	_new_items_since_organization = 0
	_loaded = true
	_file_expected = true
	return {"ok": true}


func append_wake(
	wake_packet: Variant,
	matched_intents: Variant,
	include_items: bool = true,
	storage_already_verified: bool = false,
) -> Dictionary:
	if not storage_already_verified or not _loaded:
		var load_result := _ensure_loaded()
		if not bool(load_result.get("ok", false)):
			return load_result
	var wake_errors: Array[String] = AgentContractScript.validate_wake_packet(wake_packet)
	if not wake_errors.is_empty():
		return {"ok": false, "errors": wake_errors}
	if typeof(matched_intents) != TYPE_ARRAY:
		return _failure("居民证据的 matched_intents 必须是数组")

	var wake := (wake_packet as Dictionary).duplicate(true)
	var intent_by_action_id := {}
	for intent_value: Variant in matched_intents as Array:
		if typeof(intent_value) != TYPE_DICTIONARY:
			return _failure("居民证据包含非法动作意图")
		var intent := intent_value as Dictionary
		var action_id := String(intent.get("action_id", ""))
		if action_id.is_empty() or intent_by_action_id.has(action_id):
			return _failure("居民证据动作意图 action_id 为空或重复")
		intent_by_action_id[action_id] = intent.duplicate(true)

	var staged_hashes := _known_source_hashes.duplicate(true)
	var new_events: Array[Dictionary] = []
	for event_value: Variant in wake.get("events", []) as Array:
		var event := event_value as Dictionary
		var source_ref := "event:%s" % String(event.get("event_id", ""))
		var source_result := _stage_source(staged_hashes, source_ref, event)
		if not bool(source_result.get("ok", false)):
			return source_result
		if bool(source_result.get("new", false)):
			new_events.append(event.duplicate(true))

	var new_results: Array[Dictionary] = []
	var new_intents: Array[Dictionary] = []
	for result_value: Variant in wake.get("action_results", []) as Array:
		var result := result_value as Dictionary
		var action_id := String(result.get("action_id", ""))
		var source_ref := "action_result:%s" % action_id
		var source_result := _stage_source(staged_hashes, source_ref, result)
		if not bool(source_result.get("ok", false)):
			return source_result
		if not bool(source_result.get("new", false)):
			continue
		if not intent_by_action_id.has(action_id):
			return _failure("世界动作结果缺少匹配的居民原意图：%s" % action_id)
		new_results.append(result.duplicate(true))
		new_intents.append((intent_by_action_id[action_id] as Dictionary).duplicate(true))

	if new_events.is_empty() and new_results.is_empty():
		var unchanged := {
			"ok": true,
			"added": false,
			"new_items_since_organization": _new_items_since_organization,
		}
		if include_items:
			unchanged["items"] = _items.duplicate(true)
		return unchanged

	wake["events"] = new_events
	wake["action_results"] = new_results
	var item := {
		"wake_packet": wake,
		"matched_intents": new_intents,
	}
	# 队列内部持有每一项，并且对外始终返回深拷贝。这里只需要复制数组容器，
	# 无需在每次居民唤醒时再次深拷贝整份历史。
	var candidate := _items.duplicate()
	candidate.append(item)
	var new_count := _new_items_since_organization + 1
	var organized_count := maxi(0, candidate.size() - new_count)
	while candidate.size() > MAX_ITEMS and organized_count > 0:
		candidate.pop_front()
		organized_count -= 1
	var write_result := _replace_file(candidate)
	if not bool(write_result.get("ok", false)):
		return write_result
	_items = candidate
	_known_source_hashes = staged_hashes
	_new_items_since_organization = new_count
	_file_expected = true
	var appended := {
		"ok": true,
		"added": true,
		"new_items_since_organization": _new_items_since_organization,
	}
	if include_items:
		appended["items"] = _items.duplicate(true)
	return appended


func mark_organized() -> Dictionary:
	var load_result := _ensure_loaded()
	if not bool(load_result.get("ok", false)):
		return load_result
	var trimmed := _items.duplicate(true)
	while trimmed.size() > MAX_ITEMS:
		trimmed.pop_front()
	if trimmed.size() != _items.size():
		var write_result := _replace_file(trimmed)
		if not bool(write_result.get("ok", false)):
			return write_result
		_items = trimmed
	_new_items_since_organization = 0
	return {"ok": true}


func capture_state() -> Dictionary:
	var load_result := _ensure_loaded()
	if not bool(load_result.get("ok", false)):
		return load_result
	return {
		"ok": true,
		"queue_state": {
			"queue_state_version": STATE_VERSION,
			"items": _items.duplicate(true),
			"known_source_hashes": _known_source_hashes.duplicate(true),
			"new_items_since_organization": _new_items_since_organization,
		},
	}


func apply_state(value: Variant) -> Dictionary:
	if (
		FileAccess.file_exists(_path)
		or (
			_loaded
			and (
				not _items.is_empty()
				or not _known_source_hashes.is_empty()
				or _new_items_since_organization != 0
			)
		)
	):
		return _failure("居民证据队列恢复目标不是空状态")
	var validation := validate_state(value)
	if not bool(validation.get("ok", false)):
		return validation
	var state := validation["queue_state"] as Dictionary
	var items: Array[Dictionary] = []
	items.assign(state["items"])
	var write_result := _replace_file(items)
	if not bool(write_result.get("ok", false)):
		return write_result
	_items = items
	_known_source_hashes = (state["known_source_hashes"] as Dictionary).duplicate(true)
	_new_items_since_organization = int(state["new_items_since_organization"])
	_loaded = true
	_file_expected = true
	return {"ok": true}


func validate_state(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return _failure("居民证据队列持久状态必须是对象")
	var state := value as Dictionary
	if not _has_exact_fields(
		state,
		[
			"queue_state_version",
			"items",
			"known_source_hashes",
			"new_items_since_organization",
		],
	):
		return _failure("居民证据队列持久状态字段损坏")
	if state.get("queue_state_version") != STATE_VERSION:
		return _failure("居民证据队列状态版本不受支持")
	if (
		typeof(state.get("items")) != TYPE_ARRAY
		or typeof(state.get("known_source_hashes")) != TYPE_DICTIONARY
		or typeof(state.get("new_items_since_organization")) != TYPE_INT
	):
		return _failure("居民证据队列持久状态类型损坏")
	var item_validation := _validate_items(state["items"])
	if not bool(item_validation.get("ok", false)):
		return item_validation
	var hashes := state["known_source_hashes"] as Dictionary
	if not _valid_hashes(hashes):
		return _failure("居民证据来源去重索引损坏")
	var expected_hashes := {}
	for item_value: Variant in item_validation["items"]:
		_index_item_sources(item_value as Dictionary, expected_hashes)
	for source_ref: Variant in expected_hashes:
		if hashes.get(source_ref) != expected_hashes[source_ref]:
			return _failure("居民证据来源去重索引与队列内容不一致")
	var new_count := int(state["new_items_since_organization"])
	if new_count < 0 or new_count > (item_validation["items"] as Array).size():
		return _failure("居民证据新增计数损坏")
	return {
		"ok": true,
		"queue_state": {
			"queue_state_version": STATE_VERSION,
			"items": (item_validation["items"] as Array).duplicate(true),
			"known_source_hashes": hashes.duplicate(true),
			"new_items_since_organization": new_count,
		},
	}


func erase_storage() -> void:
	_remove_file(_path)
	_remove_file("%s.tmp" % _path)
	_remove_file("%s.bak" % _path)
	_file_expected = false
	_synced_file_sha256 = ""


func _ensure_loaded() -> Dictionary:
	if _loaded:
		return _verify_loaded_storage()
	var recovery := _recover_backup()
	if not bool(recovery.get("ok", false)):
		return recovery
	if not FileAccess.file_exists(_path):
		_items = []
		_known_source_hashes = {}
		_new_items_since_organization = 0
		_loaded = true
		_file_expected = false
		return {"ok": true}
	var file := FileAccess.open(_path, FileAccess.READ)
	if file == null:
		return _failure("无法读取居民证据队列：%s" % _path)
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	file = null
	if parse_error != OK:
		return _failure(
			"居民证据文件损坏：%s（%s）"
			% [_path, parser.get_error_message()],
		)
	var parsed: Variant = parser.data
	var validation := _validate_items(parsed)
	if not bool(validation.get("ok", false)):
		return validation
	_items.assign(validation["items"])
	_known_source_hashes = {}
	for item: Dictionary in _items:
		_index_item_sources(item, _known_source_hashes)
	_new_items_since_organization = _items.size()
	_loaded = true
	_file_expected = true
	_record_synced_file_stats()
	return {"ok": true}


# 外部改写检测保留（验收契约）：快路径只比整文件 SHA-256——任意字节的
# 外部改写都会被发现；只有哈希不一致时才重新解析并全量校验以给出具体错误。
# 相比原实现省掉的是每次读取的 JSON 解析 + 合约校验 + 结构序列化哈希。
func _verify_loaded_storage() -> Dictionary:
	if not FileAccess.file_exists(_path):
		if _file_expected:
			return _failure("居民证据文件缺失：%s" % _path)
		return {"ok": true}
	if (
		not _synced_file_sha256.is_empty()
		and FileAccess.get_sha256(_path) == _synced_file_sha256
	):
		return {"ok": true}
	var file := FileAccess.open(_path, FileAccess.READ)
	if file == null:
		return _failure("无法读取居民证据文件：%s" % _path)
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	file = null
	if parse_error != OK:
		return _failure(
			"居民证据文件损坏：%s（%s）"
			% [_path, parser.get_error_message()],
		)
	var verification := _validate_items(parser.data)
	if not bool(verification.get("ok", false)):
		return verification
	if _content_hash(verification["items"]) != _content_hash(_items):
		return _failure("居民证据文件在运行时被外部改写：%s" % _path)
	_file_expected = true
	_record_synced_file_stats()
	return {"ok": true}


func _record_synced_file_stats() -> void:
	_synced_file_sha256 = (
		FileAccess.get_sha256(_path)
		if FileAccess.file_exists(_path)
		else ""
	)


func _validate_items(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return _failure("居民证据文件必须是 JSON 数组")
	var values := value as Array
	var items: Array[Dictionary] = []
	var source_hashes := {}
	for item_value: Variant in values:
		if typeof(item_value) != TYPE_DICTIONARY:
			return _failure("居民证据队列项必须是对象")
		var item := AgentJsonScript.normalize_numbers(
			(item_value as Dictionary).duplicate(true),
		) as Dictionary
		if not _has_exact_fields(item, ["wake_packet", "matched_intents"]):
			return _failure("居民证据队列项字段损坏")
		var wake_errors: Array[String] = AgentContractScript.validate_wake_packet(
			item.get("wake_packet"),
		)
		if not wake_errors.is_empty():
			return {"ok": false, "errors": wake_errors}
		if typeof(item.get("matched_intents")) != TYPE_ARRAY:
			return _failure("居民证据 matched_intents 必须是数组")
		var result_ids := {}
		var wake := item["wake_packet"] as Dictionary
		var events := wake.get("events", []) as Array
		var action_results := wake.get("action_results", []) as Array
		if events.is_empty() and action_results.is_empty():
			return _failure("居民证据队列不能包含空唤醒项")
		for result_value: Variant in action_results:
			result_ids[String((result_value as Dictionary).get("action_id", ""))] = true
		var intent_ids := {}
		for intent_value: Variant in item["matched_intents"] as Array:
			if typeof(intent_value) != TYPE_DICTIONARY:
				return _failure("居民证据动作意图必须是对象")
			var intent := intent_value as Dictionary
			if not validate_intent_shape(intent):
				return _failure("居民证据动作意图结构损坏")
			var action_id := String(intent.get("action_id", ""))
			if action_id.is_empty() or intent_ids.has(action_id):
				return _failure("居民证据动作意图编号损坏")
			intent_ids[action_id] = true
		if result_ids != intent_ids:
			return _failure("居民证据动作结果与原意图不匹配")
		for event_value: Variant in events:
			var event := event_value as Dictionary
			var event_ref := "event:%s" % String(event.get("event_id", ""))
			var event_source := _stage_source(source_hashes, event_ref, event)
			if not bool(event_source.get("ok", false)):
				return event_source
			if not bool(event_source.get("new", false)):
				return _failure("居民证据队列包含重复来源：%s" % event_ref)
		for result_value: Variant in wake.get("action_results", []) as Array:
			var result := result_value as Dictionary
			var result_ref := (
				"action_result:%s" % String(result.get("action_id", ""))
			)
			var result_source := _stage_source(source_hashes, result_ref, result)
			if not bool(result_source.get("ok", false)):
				return result_source
			if not bool(result_source.get("new", false)):
				return _failure("居民证据队列包含重复来源：%s" % result_ref)
		items.append(item.duplicate(true))
	return {"ok": true, "items": items}


func _replace_file(items: Array[Dictionary]) -> Dictionary:
	var serialized := JSON.stringify(items)
	var serialized_sha256 := serialized.sha256_text()
	var directory_error := OK
	if not _directory_ready:
		directory_error = DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(_path.get_base_dir()),
		)
		if directory_error == OK or directory_error == ERR_ALREADY_EXISTS:
			_directory_ready = true
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return _failure("无法创建居民证据目录：%s" % error_string(directory_error))
	var temporary_path := "%s.tmp" % _path
	var backup_path := "%s.bak" % _path
	_remove_file(temporary_path)
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null and _directory_ready:
		# 运行期间若父目录被外部移除，恢复原先每次写入都会重建目录的行为。
		_directory_ready = false
		directory_error = DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(_path.get_base_dir()),
		)
		if directory_error == OK or directory_error == ERR_ALREADY_EXISTS:
			_directory_ready = true
			file = FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return _failure("无法写入居民证据临时文件")
	# 内容在入队时已校验过，紧凑输出并依赖临时文件 + rename 保证原子性，
	# 不再整包读回验证。
	file.store_string(serialized)
	file.flush()
	var write_error := file.get_error()
	file = null
	if write_error != OK:
		_remove_file(temporary_path)
		return _failure("无法写入居民证据：%s" % error_string(write_error))
	var used_backup_fallback := false
	var replace_error := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temporary_path),
		ProjectSettings.globalize_path(_path),
	)
	if replace_error != OK and FileAccess.file_exists(_path):
		# POSIX/Android 可以直接原子覆盖旧文件；不支持覆盖的平台继续使用
		# 原有的备份、替换和回滚流程，保留相同的恢复保证。
		_remove_file(backup_path)
		used_backup_fallback = true
		var backup_error := DirAccess.rename_absolute(
			ProjectSettings.globalize_path(_path),
			ProjectSettings.globalize_path(backup_path),
		)
		if backup_error != OK:
			_remove_file(temporary_path)
			return _failure("无法准备居民证据原子替换")
		replace_error = DirAccess.rename_absolute(
			ProjectSettings.globalize_path(temporary_path),
			ProjectSettings.globalize_path(_path),
		)
	if replace_error != OK:
		if FileAccess.file_exists(backup_path):
			DirAccess.rename_absolute(
				ProjectSettings.globalize_path(backup_path),
				ProjectSettings.globalize_path(_path),
			)
		_remove_file(temporary_path)
		return _failure("无法提交居民证据队列")
	if used_backup_fallback:
		_remove_file(backup_path)
	# serialized 正是刚刚提交的字节序列。直接保存其摘要，避免提交成功后
	# 立刻重新打开并扫描整份历史文件。
	_synced_file_sha256 = serialized_sha256
	return {"ok": true}


func _stage_source(
	hashes: Dictionary,
	source_ref: String,
	payload: Dictionary,
) -> Dictionary:
	var digest := _content_hash(payload)
	if hashes.has(source_ref):
		if hashes[source_ref] == digest:
			return {"ok": true, "new": false}
		return _failure("同一世界来源编号对应了不同内容：%s" % source_ref)
	hashes[source_ref] = digest
	return {"ok": true, "new": true}


func _index_item_sources(item: Dictionary, hashes: Dictionary) -> void:
	var wake := item["wake_packet"] as Dictionary
	for event_value: Variant in wake.get("events", []) as Array:
		var event := event_value as Dictionary
		hashes["event:%s" % String(event.get("event_id", ""))] = _content_hash(event)
	for result_value: Variant in wake.get("action_results", []) as Array:
		var result := result_value as Dictionary
		hashes["action_result:%s" % String(result.get("action_id", ""))] = _content_hash(result)


func _valid_hashes(value: Dictionary) -> bool:
	for source_ref: Variant in value:
		if (
			typeof(source_ref) != TYPE_STRING
			or String(source_ref).is_empty()
			or typeof(value[source_ref]) != TYPE_STRING
			or String(value[source_ref]).is_empty()
		):
			return false
	return true


func validate_intent_shape(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false
	var action := value as Dictionary
	var action_type := String(action.get("type", ""))
	if not AgentContractScript.ACTION_FIELDS.has(action_type):
		return false
	var required_fields := (
		AgentContractScript.ACTION_FIELDS[action_type] as Array
	).duplicate()
	# World 只有在本轮提供普通行动选项时才要求 option_id。没有选项的
	# 合法决定（以及由旧存档恢复的同类决定）不能在证据落盘时被误判损坏。
	if (
		action_type in ["去", "用道具", "做活动", "搭话", "待着"]
		and not action.has("option_id")
	):
		required_fields.erase("option_id")
	if action_type == "答话" and not action.has("medical_response"):
		required_fields.erase("medical_response")
	var exact_fields := required_fields.duplicate()
	for field_value: Variant in AgentContractScript.OPTIONAL_ACTION_FIELDS.get(action_type, []) as Array:
		var field := String(field_value)
		if action.has(field):
			exact_fields.append(field)
	if not _has_exact_fields(
		action,
		exact_fields,
	):
		return false
	for field_name: String in required_fields:
		if field_name == "photos":
			if not _valid_photos(action.get(field_name)):
				return false
		elif field_name in ["end", "open"]:
			if typeof(action.get(field_name)) != TYPE_BOOL:
				return false
		elif field_name == "medical_response":
			if not _valid_medical_response(action.get(field_name)):
				return false
		elif field_name in ["say", "narration"]:
			if typeof(action.get(field_name)) != TYPE_STRING:
				return false
		elif (
			typeof(action.get(field_name)) != TYPE_STRING
			or String(action.get(field_name)).strip_edges().is_empty()
		):
			return false
	if action_type == "答话" and action.has("traveler_affinity_delta"):
		var affinity_delta: Variant = action.get("traveler_affinity_delta")
		if (
			typeof(affinity_delta) != TYPE_INT
			or int(affinity_delta) < -5
			or int(affinity_delta) > 5
		):
			return false
	if action_type in ["搭话", "答话"]:
		if (
			action_type == "答话"
			and bool(action.get("end", false))
			and String(action.get("narration", "")).strip_edges().is_empty()
		):
			return false
		return (
			not String(action.get("say", "")).strip_edges().is_empty()
			or not String(action.get("narration", "")).strip_edges().is_empty()
		)
	return true


func _valid_medical_response(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false
	var response := value as Dictionary
	return (
		_has_exact_fields(response, ["request_id", "response_kind"])
		and typeof(response.get("request_id")) == TYPE_STRING
		and not String(response.get("request_id")).strip_edges().is_empty()
		and typeof(response.get("response_kind")) == TYPE_STRING
		and String(response.get("response_kind")) in ["describe", "decline"]
	)


func _valid_photos(value: Variant) -> bool:
	if typeof(value) != TYPE_ARRAY:
		return false
	for photo_value: Variant in value as Array:
		if typeof(photo_value) != TYPE_DICTIONARY:
			return false
		var photo := photo_value as Dictionary
		if (
			not _has_exact_fields(photo, ["ref", "mime_type"])
			or typeof(photo.get("ref")) != TYPE_STRING
			or String(photo.get("ref")).strip_edges().is_empty()
			or typeof(photo.get("mime_type")) != TYPE_STRING
			or String(photo.get("mime_type")).strip_edges().is_empty()
		):
			return false
	return true


func _content_hash(value: Variant) -> String:
	return AgentJsonScript.content_sha256(value)


func _recover_backup() -> Dictionary:
	var backup_path := "%s.bak" % _path
	_remove_file("%s.tmp" % _path)
	if not FileAccess.file_exists(backup_path):
		return {"ok": true}
	if FileAccess.file_exists(_path):
		_remove_file(backup_path)
		return {"ok": true}
	var error := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(backup_path),
		ProjectSettings.globalize_path(_path),
	)
	if error != OK:
		return _failure("无法恢复居民证据队列备份")
	return {"ok": true}


func _has_exact_fields(value: Dictionary, fields: Array) -> bool:
	if value.size() != fields.size():
		return false
	for field_name: Variant in fields:
		if not value.has(field_name):
			return false
	return true


func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _failure(message: String) -> Dictionary:
	return {"ok": false, "errors": [message]}
