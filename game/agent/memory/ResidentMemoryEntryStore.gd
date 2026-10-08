class_name AgentResidentMemoryEntryStore
extends RefCounted

const TEST_FILE_SYSTEM := preload("res://agent/AgentFileSystem.gd")


const AgentJsonScript := preload("res://agent/AgentJson.gd")
const STATE_VERSION := 1
const SOURCE_KINDS: Array[String] = ["firsthand", "hearsay", "implanted"]
const MEMORY_STATES: Array[String] = [
	"influencing",
	"past",
	"doubtful",
	"anomalous",
	"corrected",
]
const MAX_ENTRIES := 256
const MAX_SUBJECT_LENGTH := 480
const MAX_INTERPRETATION_LENGTH := 480

var _path: String
var _resident_id: String


func _init(path: String, resident_id: String) -> void:
	_path = path
	_resident_id = resident_id


func read() -> Dictionary:
	var recovery := _recover_backup()
	if not bool(recovery.get("ok", false)):
		return recovery
	if not FileAccess.file_exists(_path):
		return {"ok": true, "archive": empty_archive(), "exists": false}
	var result := _read_path(_path)
	if bool(result.get("ok", false)):
		result["exists"] = true
	return result


func initialize_empty() -> Dictionary:
	if FileAccess.file_exists(_path):
		return read()
	return replace(empty_archive())


func erase_storage() -> Dictionary:
	for path: String in [_path, "%s.tmp" % _path, "%s.bak" % _path]:
		if _remove_file(path) != OK:
			return _test_retention_failure()
	return {"ok": true}


func replace(value: Variant) -> Dictionary:
	var validation := validate(value)
	if not bool(validation.get("ok", false)):
		return validation
	var archive := validation["archive"] as Dictionary
	var directory_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(_path.get_base_dir()),
	)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return _failure("无法创建居民正式记忆目录：%s" % error_string(directory_error))
	var temporary_path := "%s.tmp" % _path
	var backup_path := "%s.bak" % _path
	if _remove_file(temporary_path) != OK:
		return _test_retention_failure()
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return _failure("无法写入居民正式记忆临时文件：%s" % temporary_path)
	file.store_string(JSON.stringify(archive, "  ", false))
	file.flush()
	var write_error := file.get_error()
	file = null
	if write_error != OK:
		if _remove_file(temporary_path) != OK:
			return _test_retention_failure()
		return _failure("无法写入居民正式记忆：%s" % error_string(write_error))
	var verification := _read_path(temporary_path)
	if not bool(verification.get("ok", false)):
		if _remove_file(temporary_path) != OK:
			return _test_retention_failure()
		return verification
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
			return _failure("无法准备居民正式记忆原子替换：%s" % error_string(backup_error))
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
		return _failure("无法提交居民正式记忆：%s" % error_string(replace_error))
	if _remove_file(backup_path) != OK:
		return _test_retention_failure()
	return {"ok": true, "archive": archive.duplicate(true)}


func validate(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return _failure("居民正式记忆档案必须是对象")
	var archive := value as Dictionary
	if not _has_exact_fields(
		archive,
		["state_version", "resident_id", "revision", "entries"],
	):
		return _failure("居民正式记忆档案字段不完整或包含未知字段")
	if (
		archive.get("state_version") != STATE_VERSION
		or archive.get("resident_id") != _resident_id
		or typeof(archive.get("revision")) != TYPE_INT
		or int(archive.get("revision")) < 0
		or typeof(archive.get("entries")) != TYPE_ARRAY
	):
		return _failure("居民正式记忆档案版本、归属或字段类型损坏")
	var source := archive["entries"] as Array
	if source.size() > MAX_ENTRIES:
		return _failure("居民正式记忆条目超过容量上限")
	var entries: Array[Dictionary] = []
	var ids := {}
	for index in range(source.size()):
		var item_result := _validate_entry(source[index], index)
		if not bool(item_result.get("ok", false)):
			return item_result
		var entry := item_result["entry"] as Dictionary
		var memory_id := String(entry["memory_id"])
		if ids.has(memory_id):
			return _failure("居民正式记忆 memory_id 重复：%s" % memory_id)
		ids[memory_id] = true
		entries.append(entry)
	return {
		"ok": true,
		"archive": {
			"state_version": STATE_VERSION,
			"resident_id": _resident_id,
			"revision": int(archive["revision"]),
			"entries": entries,
		},
	}


func empty_archive() -> Dictionary:
	return {
		"state_version": STATE_VERSION,
		"resident_id": _resident_id,
		"revision": 0,
		"entries": [],
	}


func _validate_entry(value: Variant, index: int) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return _failure("居民正式记忆第 %d 项必须是对象" % index)
	var entry := value as Dictionary
	var fields := [
		"memory_id", "resident_id", "subject", "interpretation", "people",
		"places", "topics", "world_time", "source_kind", "source_resident_id",
		"claim_root_id", "confidence", "state", "active_version_id",
		"evidence_refs", "created_revision", "updated_revision",
	]
	if not _has_exact_fields(entry, fields):
		return _failure("居民正式记忆第 %d 项字段损坏" % index)
	var memory_id := String(entry.get("memory_id", "")).strip_edges()
	var subject := String(entry.get("subject", "")).strip_edges()
	var interpretation := String(entry.get("interpretation", "")).strip_edges()
	var source_kind := String(entry.get("source_kind", ""))
	var source_resident_id := String(entry.get("source_resident_id", "")).strip_edges()
	var claim_root_id := String(entry.get("claim_root_id", "")).strip_edges()
	var active_version_id := String(entry.get("active_version_id", "")).strip_edges()
	if (
		memory_id.is_empty()
		or entry.get("resident_id") != _resident_id
		or subject.is_empty()
		or subject.length() > MAX_SUBJECT_LENGTH
		or interpretation.length() > MAX_INTERPRETATION_LENGTH
		or source_kind not in SOURCE_KINDS
		or claim_root_id.is_empty()
		or active_version_id.is_empty()
	):
		return _failure("居民正式记忆第 %d 项身份、正文或来源损坏" % index)
	if (
		(source_kind == "hearsay" and source_resident_id.is_empty())
		or (source_kind != "hearsay" and not source_resident_id.is_empty())
	):
		return _failure("居民正式记忆第 %d 项二手来源损坏" % index)
	if (
		typeof(entry.get("confidence")) != TYPE_INT
		or int(entry.get("confidence")) < 0
		or int(entry.get("confidence")) > 100
		or String(entry.get("state", "")) not in MEMORY_STATES
		or typeof(entry.get("created_revision")) != TYPE_INT
		or typeof(entry.get("updated_revision")) != TYPE_INT
		or int(entry.get("created_revision")) < 1
		or int(entry.get("updated_revision")) < int(entry.get("created_revision"))
	):
		return _failure("居民正式记忆第 %d 项确信或 revision 损坏" % index)
	var people := _validate_string_list(entry.get("people"), "人物", index)
	if not bool(people.get("ok", false)):
		return people
	var places := _validate_string_list(entry.get("places"), "地点", index)
	if not bool(places.get("ok", false)):
		return places
	var topics := _validate_string_list(entry.get("topics"), "主题", index)
	if not bool(topics.get("ok", false)):
		return topics
	var evidence := _validate_string_list(entry.get("evidence_refs"), "证据来源", index)
	if not bool(evidence.get("ok", false)):
		return evidence
	if not _valid_world_time(entry.get("world_time")):
		return _failure("居民正式记忆第 %d 项世界时间损坏" % index)
	return {
		"ok": true,
		"entry": {
			"memory_id": memory_id,
			"resident_id": _resident_id,
			"subject": subject,
			"interpretation": interpretation,
			"people": people["items"],
			"places": places["items"],
			"topics": topics["items"],
			"world_time": (entry["world_time"] as Dictionary).duplicate(true),
			"source_kind": source_kind,
			"source_resident_id": source_resident_id,
			"claim_root_id": claim_root_id,
			"confidence": int(entry["confidence"]),
			"state": String(entry["state"]),
			"active_version_id": active_version_id,
			"evidence_refs": evidence["items"],
			"created_revision": int(entry["created_revision"]),
			"updated_revision": int(entry["updated_revision"]),
		},
	}


func _validate_string_list(value: Variant, label: String, index: int) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return _failure("居民正式记忆第 %d 项%s必须是数组" % [index, label])
	var items: Array[String] = []
	for item_value: Variant in value as Array:
		if typeof(item_value) != TYPE_STRING:
			return _failure("居民正式记忆第 %d 项%s包含非法内容" % [index, label])
		var item := String(item_value).strip_edges()
		if item.is_empty() or items.has(item):
			return _failure("居民正式记忆第 %d 项%s为空或重复" % [index, label])
		items.append(item)
	return {"ok": true, "items": items}


func _valid_world_time(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false
	var time := value as Dictionary
	if not _has_exact_fields(time, ["day", "clock", "period"]):
		return false
	if typeof(time.get("day")) != TYPE_INT or int(time.get("day")) < 1:
		return false
	if typeof(time.get("clock")) != TYPE_STRING or typeof(time.get("period")) != TYPE_STRING:
		return false
	var parts := String(time["clock"]).split(":", false)
	if parts.size() != 2 or not String(parts[0]).is_valid_int() or not String(parts[1]).is_valid_int():
		return false
	var hour := int(parts[0])
	var minute := int(parts[1])
	return hour >= 0 and hour < 24 and minute >= 0 and minute < 60 and not String(time["period"]).strip_edges().is_empty()


func _read_path(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("无法读取居民正式记忆：%s" % path)
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	file = null
	if parse_error != OK:
		return _failure("居民正式记忆文件损坏：%s（%s）" % [path, parser.get_error_message()])
	return validate(AgentJsonScript.normalize_numbers(parser.data))


func _recover_backup() -> Dictionary:
	var backup_path := "%s.bak" % _path
	if _remove_file("%s.tmp" % _path) != OK:
		return _test_retention_failure()
	if not FileAccess.file_exists(backup_path):
		return {"ok": true}
	if FileAccess.file_exists(_path):
		if _remove_file(backup_path) != OK:
			return _test_retention_failure()
		return {"ok": true}
	var error := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(backup_path),
		ProjectSettings.globalize_path(_path),
	)
	return {"ok": true} if error == OK else _failure("无法恢复居民正式记忆备份：%s" % error_string(error))


func _has_exact_fields(value: Dictionary, fields: Array) -> bool:
	if value.size() != fields.size():
		return false
	for field_name: Variant in fields:
		if not value.has(field_name):
			return false
	return true


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
