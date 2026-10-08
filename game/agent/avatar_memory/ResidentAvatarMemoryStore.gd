class_name AgentResidentAvatarMemoryStore
extends RefCounted

const TEST_FILE_SYSTEM := preload("res://agent/AgentFileSystem.gd")


const AgentJsonScript := preload("res://agent/AgentJson.gd")
const LEGACY_STATE_VERSION := 1
const STATE_VERSION := 2
const SOURCE_TYPES: Array[String] = [
	"direct_dialogue",
	"direct_observation",
	"hearsay",
	"inference",
]
const MEMORY_STATUSES: Array[String] = [
	"active",
	"resolved",
	"superseded",
	"disputed",
]
const MESSAGE_STATUSES: Array[String] = [
	"unconfirmed",
	"acknowledged",
	"resolved",
]
const SUMMARY_TARGET := 1200
const SUMMARY_LIMIT := 1600
const MEMORY_TARGET_COUNT := 24
const MEMORY_LIMIT_COUNT := 32
const MEMORY_TARGET_TOTAL := 2000
const MEMORY_LIMIT_TOTAL := 2400
const MEMORY_ITEM_TARGET := 160
const MEMORY_ITEM_LIMIT := 240
const OPEN_LOOP_TARGET_COUNT := 8
const OPEN_LOOP_LIMIT_COUNT := 12
const OPEN_LOOP_TARGET_TOTAL := 800
const OPEN_LOOP_LIMIT_TOTAL := 1000
const OPEN_LOOP_ITEM_TARGET := 160
const OPEN_LOOP_ITEM_LIMIT := 240
const MESSAGE_LIMIT_COUNT := 8
const MESSAGE_TARGET_LENGTH := 80
const MESSAGE_LIMIT_LENGTH := 96

var _path: String
var _resident_id: String
var _avatar_person_id: String


func _init(path: String, resident_id: String, avatar_person_id: String) -> void:
	_path = path
	_resident_id = resident_id
	_avatar_person_id = avatar_person_id


func read() -> Dictionary:
	var recovery := _recover_backup()
	if not bool(recovery.get("ok", false)):
		return recovery
	if not FileAccess.file_exists(_path):
		return {"ok": true, "memory": empty_memory(), "exists": false}
	var read_result := _read_path(_path)
	if bool(read_result.get("ok", false)):
		read_result["exists"] = true
	return read_result


func replace(value: Variant) -> Dictionary:
	var validation := validate(value)
	if not bool(validation.get("ok", false)):
		return validation
	var memory := validation["memory"] as Dictionary
	var directory_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(_path.get_base_dir()),
	)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return _failure(
			"无法创建居民化身记忆目录：%s" % error_string(directory_error),
		)
	var temporary_path := "%s.tmp" % _path
	var backup_path := "%s.bak" % _path
	if _remove_file(temporary_path) != OK:
		return _test_retention_failure()
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return _failure("无法写入居民化身记忆临时文件：%s" % temporary_path)
	# 写入内容刚通过 validate，不再读回验证；原子性由临时文件 + rename 保证。
	file.store_string(JSON.stringify(memory, "  ", false))
	file.flush()
	var write_error := file.get_error()
	file = null
	if write_error != OK:
		if _remove_file(temporary_path) != OK:
			return _test_retention_failure()
		return _failure("无法写入居民化身记忆：%s" % error_string(write_error))
	if _remove_file(backup_path) != OK:
		return _test_retention_failure()
	if FileAccess.file_exists(_path):
		var backup_error := DirAccess.rename_absolute(
			ProjectSettings.globalize_path(_path),
			ProjectSettings.globalize_path(backup_path),
		)
		if backup_error != OK:
			if _remove_file(temporary_path) != OK:
				return _test_retention_failure()
			return _failure(
				"无法准备居民化身记忆原子替换：%s"
				% error_string(backup_error),
			)
	var replace_error := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temporary_path),
		ProjectSettings.globalize_path(_path),
	)
	if replace_error != OK:
		if FileAccess.file_exists(backup_path):
			DirAccess.rename_absolute(
				ProjectSettings.globalize_path(backup_path),
				ProjectSettings.globalize_path(_path),
			)
		if _remove_file(temporary_path) != OK:
			return _test_retention_failure()
		return _failure(
			"无法提交居民化身记忆：%s" % error_string(replace_error),
		)
	if _remove_file(backup_path) != OK:
		return _test_retention_failure()
	return {"ok": true, "memory": memory.duplicate(true)}


func validate(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return _failure("居民化身记忆必须是对象")
	var memory := value as Dictionary
	var fields := [
		"state_version",
		"resident_id",
		"avatar_person_id",
		"summary",
		"memories",
		"open_loops",
		"sent_messages",
		"revision",
	]
	var state_version := int(memory.get("state_version", -1))
	var legacy_state := state_version == LEGACY_STATE_VERSION
	var current_fields := fields.duplicate()
	current_fields.append("departure_screening")
	if (
		not (
			legacy_state
			and _has_exact_fields(memory, fields)
		)
		and not (
			state_version == STATE_VERSION
			and _has_exact_fields(memory, current_fields)
		)
	):
		return _failure("居民化身记忆字段不完整或包含未知字段")
	if state_version not in [LEGACY_STATE_VERSION, STATE_VERSION]:
		return _failure("居民化身记忆版本不受支持")
	if memory.get("resident_id") != _resident_id:
		return _failure("居民化身记忆归属与运行时不一致")
	if memory.get("avatar_person_id") != _avatar_person_id:
		return _failure("居民化身记忆中的化身身份不一致")
	if (
		typeof(memory.get("summary")) != TYPE_STRING
		or typeof(memory.get("memories")) != TYPE_ARRAY
		or typeof(memory.get("open_loops")) != TYPE_ARRAY
		or typeof(memory.get("sent_messages")) != TYPE_ARRAY
		or typeof(memory.get("revision")) != TYPE_INT
		or int(memory.get("revision")) < 0
	):
		return _failure("居民化身记忆字段类型损坏")
	var summary := String(memory["summary"]).strip_edges()
	if summary.length() > SUMMARY_LIMIT:
		return _overflow(["summary"])
	var memories_result := _validate_memories(memory["memories"])
	if not bool(memories_result.get("ok", false)):
		return memories_result
	var loops_result := _validate_open_loops(memory["open_loops"])
	if not bool(loops_result.get("ok", false)):
		return loops_result
	var messages_result := _validate_messages(memory["sent_messages"])
	if not bool(messages_result.get("ok", false)):
		return messages_result
	var screening_result := _validate_departure_screening(
		memory.get("departure_screening", _empty_departure_screening()),
	)
	if not bool(screening_result.get("ok", false)):
		return screening_result
	return {
		"ok": true,
		"memory": {
			"state_version": STATE_VERSION,
			"resident_id": _resident_id,
			"avatar_person_id": _avatar_person_id,
			"summary": summary,
			"memories": memories_result["items"],
			"open_loops": loops_result["items"],
			"sent_messages": messages_result["items"],
			"revision": int(memory["revision"]),
			"departure_screening": screening_result["screening"],
		},
	}


func empty_memory() -> Dictionary:
	return {
		"state_version": STATE_VERSION,
		"resident_id": _resident_id,
		"avatar_person_id": _avatar_person_id,
		"summary": "",
		"memories": [],
		"open_loops": [],
		"sent_messages": [],
		"revision": 0,
		"departure_screening": _empty_departure_screening(),
	}


func capacity() -> Dictionary:
	return {
		"summary": {"target": SUMMARY_TARGET, "limit": SUMMARY_LIMIT},
		"memories": {
			"target_count": MEMORY_TARGET_COUNT,
			"limit_count": MEMORY_LIMIT_COUNT,
			"target_total": MEMORY_TARGET_TOTAL,
			"limit_total": MEMORY_LIMIT_TOTAL,
			"item_target": MEMORY_ITEM_TARGET,
			"item_limit": MEMORY_ITEM_LIMIT,
		},
		"open_loops": {
			"target_count": OPEN_LOOP_TARGET_COUNT,
			"limit_count": OPEN_LOOP_LIMIT_COUNT,
			"target_total": OPEN_LOOP_TARGET_TOTAL,
			"limit_total": OPEN_LOOP_LIMIT_TOTAL,
			"item_target": OPEN_LOOP_ITEM_TARGET,
			"item_limit": OPEN_LOOP_ITEM_LIMIT,
		},
		"sent_messages": {
			"limit_count": MESSAGE_LIMIT_COUNT,
			"target_length": MESSAGE_TARGET_LENGTH,
			"limit_length": MESSAGE_LIMIT_LENGTH,
		},
	}


func erase_storage() -> Dictionary:
	if _remove_file(_path) != OK:
		return _test_retention_failure()
	if _remove_file("%s.tmp" % _path) != OK:
		return _test_retention_failure()
	if _remove_file("%s.bak" % _path) != OK:
		return _test_retention_failure()
	return {"ok": true}


func _validate_memories(value: Array) -> Dictionary:
	if value.size() > MEMORY_LIMIT_COUNT:
		return _overflow(["memories.count"])
	var ids := {}
	var normalized: Array[Dictionary] = []
	var total := 0
	for index in value.size():
		var result := _validate_memory_item(value[index], index)
		if not bool(result.get("ok", false)):
			return result
		var item := result["item"] as Dictionary
		var memory_id := String(item["memory_id"])
		if ids.has(memory_id):
			return _failure("居民化身记忆 memory_id 重复：%s" % memory_id)
		ids[memory_id] = true
		total += String(item["content"]).length()
		normalized.append(item)
	if total > MEMORY_LIMIT_TOTAL:
		return _overflow(["memories.total"])
	return {"ok": true, "items": normalized}


func _validate_memory_item(value: Variant, index: int) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return _failure("居民化身具体记忆第 %d 项必须是对象" % index)
	var item := value as Dictionary
	var fields := [
		"memory_id",
		"content",
		"world_time",
		"source_type",
		"source_person_id",
		"source_refs",
		"status",
		"salience",
	]
	if not _has_exact_fields(item, fields):
		return _failure("居民化身具体记忆第 %d 项字段损坏" % index)
	var memory_id := String(item.get("memory_id", "")).strip_edges()
	var content := String(item.get("content", "")).strip_edges()
	if not _safe_id(memory_id) or content.is_empty():
		return _failure("居民化身具体记忆第 %d 项编号或正文无效" % index)
	if content.length() > MEMORY_ITEM_LIMIT:
		return _overflow(["memories[%d].content" % index])
	var common := _validate_sourced_item(item, index, "具体记忆")
	if not bool(common.get("ok", false)):
		return common
	var normalized := common["item"] as Dictionary
	normalized["memory_id"] = memory_id
	normalized["content"] = content
	return {"ok": true, "item": normalized}


func _validate_open_loops(value: Array) -> Dictionary:
	if value.size() > OPEN_LOOP_LIMIT_COUNT:
		return _overflow(["open_loops.count"])
	var ids := {}
	var normalized: Array[Dictionary] = []
	var total := 0
	for index in value.size():
		var result := _validate_open_loop(value[index], index)
		if not bool(result.get("ok", false)):
			return result
		var item := result["item"] as Dictionary
		var loop_id := String(item["loop_id"])
		if ids.has(loop_id):
			return _failure("居民化身未解决事项 loop_id 重复：%s" % loop_id)
		ids[loop_id] = true
		total += String(item["content"]).length()
		normalized.append(item)
	if total > OPEN_LOOP_LIMIT_TOTAL:
		return _overflow(["open_loops.total"])
	return {"ok": true, "items": normalized}


func _validate_open_loop(value: Variant, index: int) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return _failure("居民化身未解决事项第 %d 项必须是对象" % index)
	var item := value as Dictionary
	var fields := [
		"loop_id",
		"content",
		"world_time",
		"source_type",
		"source_person_id",
		"source_refs",
		"status",
		"salience",
		"people",
		"progress",
	]
	if not _has_exact_fields(item, fields):
		return _failure("居民化身未解决事项第 %d 项字段损坏" % index)
	var loop_id := String(item.get("loop_id", "")).strip_edges()
	var content := String(item.get("content", "")).strip_edges()
	var progress := String(item.get("progress", "")).strip_edges()
	if not _safe_id(loop_id) or content.is_empty():
		return _failure("居民化身未解决事项第 %d 项编号或正文无效" % index)
	if content.length() > OPEN_LOOP_ITEM_LIMIT or progress.length() > OPEN_LOOP_ITEM_LIMIT:
		return _overflow(["open_loops[%d].content" % index])
	var people_result := _string_array(item.get("people"), true)
	if not bool(people_result.get("ok", false)):
		return _failure("居民化身未解决事项第 %d 项涉及人物损坏" % index)
	var common := _validate_sourced_item(item, index, "未解决事项")
	if not bool(common.get("ok", false)):
		return common
	var normalized := common["item"] as Dictionary
	normalized["loop_id"] = loop_id
	normalized["content"] = content
	normalized["people"] = people_result["items"]
	normalized["progress"] = progress
	return {"ok": true, "item": normalized}


func _validate_sourced_item(
	item: Dictionary,
	index: int,
	label: String,
) -> Dictionary:
	var world_time_result := _world_time(item.get("world_time"))
	if not bool(world_time_result.get("ok", false)):
		return _failure("居民化身%s第 %d 项时间损坏" % [label, index])
	var source_type := String(item.get("source_type", ""))
	var source_person_id := String(item.get("source_person_id", "")).strip_edges()
	var refs_result := _string_array(item.get("source_refs"), false)
	var status := String(item.get("status", ""))
	var salience_value: Variant = item.get("salience")
	if (
		not SOURCE_TYPES.has(source_type)
		or not _safe_id(source_person_id)
		or not bool(refs_result.get("ok", false))
		or not MEMORY_STATUSES.has(status)
		or typeof(salience_value) != TYPE_INT
		or int(salience_value) < 1
		or int(salience_value) > 5
	):
		return _failure("居民化身%s第 %d 项来源或状态损坏" % [label, index])
	return {
		"ok": true,
		"item": {
			"world_time": world_time_result["time"],
			"source_type": source_type,
			"source_person_id": source_person_id,
			"source_refs": refs_result["items"],
			"status": status,
			"salience": int(salience_value),
		},
	}


func _validate_messages(value: Array) -> Dictionary:
	if value.size() > MESSAGE_LIMIT_COUNT:
		return _overflow(["sent_messages.count"])
	var ids := {}
	var departures := {}
	var normalized: Array[Dictionary] = []
	for index in value.size():
		if typeof(value[index]) != TYPE_DICTIONARY:
			return _failure("居民留言第 %d 项必须是对象" % index)
		var item := value[index] as Dictionary
		if not _has_exact_fields(
			item,
			["message_id", "content", "world_time", "departure_id", "status"],
		):
			return _failure("居民留言第 %d 项字段损坏" % index)
		var message_id := String(item.get("message_id", "")).strip_edges()
		var departure_id := String(item.get("departure_id", "")).strip_edges()
		var content := String(item.get("content", "")).strip_edges()
		var status := String(item.get("status", ""))
		var world_time_result := _world_time(item.get("world_time"))
		if (
			not _safe_id(message_id)
			or not _safe_id(departure_id)
			or content.is_empty()
			or content.length() > MESSAGE_LIMIT_LENGTH
			or not MESSAGE_STATUSES.has(status)
			or not bool(world_time_result.get("ok", false))
			or ids.has(message_id)
			or departures.has(departure_id)
		):
			return _failure("居民留言第 %d 项内容损坏" % index)
		ids[message_id] = true
		departures[departure_id] = true
		normalized.append({
			"message_id": message_id,
			"content": content,
			"world_time": world_time_result["time"],
			"departure_id": departure_id,
			"status": status,
		})
	return {"ok": true, "items": normalized}


func _validate_departure_screening(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return _failure("居民留言筛查游标必须是对象")
	var screening := value as Dictionary
	if not _has_exact_fields(
		screening,
		["source_refs", "summary_sha256", "departure_id"],
	):
		return _failure("居民留言筛查游标字段损坏")
	if (
		typeof(screening.get("source_refs")) != TYPE_ARRAY
		or typeof(screening.get("summary_sha256")) != TYPE_STRING
		or typeof(screening.get("departure_id")) != TYPE_STRING
	):
		return _failure("居民留言筛查游标类型损坏")
	var source_refs: Array[String] = []
	for source_ref_value: Variant in screening.get("source_refs", []) as Array:
		if typeof(source_ref_value) != TYPE_STRING:
			return _failure("居民留言筛查来源编号损坏")
		var source_ref := String(source_ref_value).strip_edges()
		if (
			source_ref.is_empty()
			or source_ref.length() > 256
			or source_refs.has(source_ref)
		):
			return _failure("居民留言筛查来源编号损坏")
		source_refs.append(source_ref)
	if source_refs.size() > 256:
		return _failure("居民留言筛查来源超过容量")
	source_refs.sort()
	var summary_sha256 := String(screening.get("summary_sha256", ""))
	var departure_id := String(screening.get("departure_id", "")).strip_edges()
	if (
		not summary_sha256.is_empty()
		and summary_sha256.length() != 64
	):
		return _failure("居民留言筛查摘要指纹损坏")
	if departure_id.length() > 128:
		return _failure("居民留言筛查退出标识损坏")
	return {
		"ok": true,
		"screening": {
			"source_refs": source_refs,
			"summary_sha256": summary_sha256,
			"departure_id": departure_id,
		},
	}


func _empty_departure_screening() -> Dictionary:
	return {
		"source_refs": [],
		"summary_sha256": "",
		"departure_id": "",
	}


func _world_time(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {"ok": false}
	var time := value as Dictionary
	if not _has_exact_fields(time, ["day", "clock", "period"]):
		return {"ok": false}
	if (
		typeof(time.get("day")) != TYPE_INT
		or int(time.get("day")) < 0
		or typeof(time.get("clock")) != TYPE_STRING
		or String(time.get("clock")).strip_edges().is_empty()
		or typeof(time.get("period")) != TYPE_STRING
		or String(time.get("period")).strip_edges().is_empty()
	):
		return {"ok": false}
	return {
		"ok": true,
		"time": {
			"day": int(time["day"]),
			"clock": String(time["clock"]).strip_edges(),
			"period": String(time["period"]).strip_edges(),
		},
	}


func _string_array(value: Variant, allow_empty: bool) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return {"ok": false}
	var items: Array[String] = []
	for item_value: Variant in value as Array:
		if typeof(item_value) != TYPE_STRING:
			return {"ok": false}
		var item := String(item_value).strip_edges()
		if item.is_empty() or items.has(item):
			return {"ok": false}
		items.append(item)
	if items.is_empty() and not allow_empty:
		return {"ok": false}
	items.sort()
	return {"ok": true, "items": items}


func _read_path(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("无法读取居民化身记忆：%s" % path)
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	file = null
	if parse_error != OK:
		return _failure(
			"居民化身记忆文件损坏：%s（%s）"
			% [path, parser.get_error_message()],
		)
	var validation := validate(AgentJsonScript.normalize_numbers(parser.data))
	if not bool(validation.get("ok", false)):
		var result := validation.duplicate(true)
		var errors: Array = result.get("errors", []).duplicate()
		errors.append("居民化身记忆文件损坏：%s" % path)
		result["errors"] = errors
		return result
	return {
		"ok": true,
		"memory": (validation["memory"] as Dictionary).duplicate(true),
	}


func _recover_backup() -> Dictionary:
	var backup_path := "%s.bak" % _path
	var temporary_path := "%s.tmp" % _path
	if _remove_file(temporary_path) != OK:
		return _test_retention_failure()
	if not FileAccess.file_exists(backup_path):
		return {"ok": true}
	if FileAccess.file_exists(_path):
		if _remove_file(backup_path) != OK:
			return _test_retention_failure()
		return {"ok": true}
	var restore_error := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(backup_path),
		ProjectSettings.globalize_path(_path),
	)
	if restore_error != OK:
		return _failure(
			"无法恢复居民化身记忆备份：%s" % error_string(restore_error),
		)
	return {"ok": true}


func _safe_id(value: String) -> bool:
	if value.is_empty() or value.length() > 128:
		return false
	const ALLOWED := (
		"abcdefghijklmnopqrstuvwxyz"
		+ "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
		+ "0123456789_-.:"
	)
	for character in value:
		if not ALLOWED.contains(character):
			return false
	return true


func _has_exact_fields(value: Dictionary, fields: Array) -> bool:
	if value.size() != fields.size():
		return false
	for field_name: Variant in fields:
		if not value.has(field_name):
			return false
	return true


func _overflow(fields: Array[String]) -> Dictionary:
	return {
		"ok": false,
		"errors": ["居民化身记忆超过代码容量上限：%s" % ", ".join(fields)],
		"retryable": true,
		"overflow_fields": fields,
		"limits": capacity(),
	}


func _remove_file(path: String) -> Error:
	if TEST_FILE_SYSTEM.test_retention_enabled():
		return TEST_FILE_SYSTEM.retain_for_test(path)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return OK


func _test_retention_failure() -> Dictionary:
	return {"ok": false, "errorCode": "AGENT_TEST_RETENTION_FAILED", "retryable": false,
		"errors": ["测试记忆文件保留失败"]}


func _failure(message: String) -> Dictionary:
	return {"ok": false, "errors": [message]}
