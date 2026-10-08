class_name AgentResidentMemoryInterventionStore
extends RefCounted

const TEST_FILE_SYSTEM := preload("res://agent/AgentFileSystem.gd")


const AgentJsonScript := preload("res://agent/AgentJson.gd")
const STATE_VERSION := 1
const KINDS: Array[String] = ["soften", "distort", "suppress", "implant"]
const OPERATIONS: Array[String] = ["edit", "delete", "write"]
const STATUSES: Array[String] = ["active", "discovered", "corrected", "superseded"]
const VERSION_FIELDS := [
	"subject", "interpretation", "confidence", "state", "active_version_id",
]
const MAX_INTERVENTIONS := 512

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
		return {"ok": true, "log": empty_log(), "exists": false}
	var result := _read_path(_path)
	if bool(result.get("ok", false)):
		result["exists"] = true
	return result


func initialize_empty() -> Dictionary:
	if FileAccess.file_exists(_path):
		return read()
	return replace(empty_log())


func erase_storage() -> Dictionary:
	for path: String in [_path, "%s.tmp" % _path, "%s.bak" % _path]:
		if _remove_file(path) != OK:
			return _test_retention_failure()
	return {"ok": true}


func replace(value: Variant) -> Dictionary:
	var validation := validate(value)
	if not bool(validation.get("ok", false)):
		return validation
	var log := validation["log"] as Dictionary
	var directory_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(_path.get_base_dir()),
	)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return _failure("无法创建居民记忆介入目录：%s" % error_string(directory_error))
	var temporary_path := "%s.tmp" % _path
	var backup_path := "%s.bak" % _path
	if _remove_file(temporary_path) != OK:
		return _test_retention_failure()
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return _failure("无法写入居民记忆介入临时文件：%s" % temporary_path)
	file.store_string(JSON.stringify(log, "  ", false))
	file.flush()
	var write_error := file.get_error()
	file = null
	if write_error != OK:
		if _remove_file(temporary_path) != OK:
			return _test_retention_failure()
		return _failure("无法写入居民记忆介入记录：%s" % error_string(write_error))
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
			return _failure("无法准备居民记忆介入原子替换：%s" % error_string(backup_error))
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
		return _failure("无法提交居民记忆介入记录：%s" % error_string(replace_error))
	if _remove_file(backup_path) != OK:
		return _test_retention_failure()
	return {"ok": true, "log": log.duplicate(true)}


func validate(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return _failure("居民记忆介入记录必须是对象")
	var log := value as Dictionary
	if not _has_exact_fields(log, ["state_version", "resident_id", "revision", "interventions"]):
		return _failure("居民记忆介入记录字段不完整或包含未知字段")
	if (
		log.get("state_version") != STATE_VERSION
		or log.get("resident_id") != _resident_id
		or typeof(log.get("revision")) != TYPE_INT
		or int(log.get("revision")) < 0
		or typeof(log.get("interventions")) != TYPE_ARRAY
	):
		return _failure("居民记忆介入记录版本、归属或字段类型损坏")
	var source := log["interventions"] as Array
	if source.size() > MAX_INTERVENTIONS:
		return _failure("居民记忆介入记录超过容量上限")
	var items: Array[Dictionary] = []
	var ids := {}
	for index in range(source.size()):
		var result := _validate_intervention(source[index], index)
		if not bool(result.get("ok", false)):
			return result
		var item := result["intervention"] as Dictionary
		if ids.has(item["intervention_id"]):
			return _failure("居民记忆 intervention_id 重复：%s" % item["intervention_id"])
		ids[item["intervention_id"]] = true
		items.append(item)
	return {
		"ok": true,
		"log": {
			"state_version": STATE_VERSION,
			"resident_id": _resident_id,
			"revision": int(log["revision"]),
			"interventions": items,
		},
	}


func empty_log() -> Dictionary:
	return {
		"state_version": STATE_VERSION,
		"resident_id": _resident_id,
		"revision": 0,
		"interventions": [],
	}


func _validate_intervention(value: Variant, index: int) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return _failure("居民记忆介入第 %d 项必须是对象" % index)
	var item := value as Dictionary
	var legacy_fields := [
		"intervention_id", "resident_id", "memory_id", "kind", "original_version",
		"active_version", "player_text", "created_world_time", "status",
	]
	var current_fields := legacy_fields.duplicate()
	current_fields.append("operation")
	if not _has_exact_fields(item, legacy_fields) and not _has_exact_fields(item, current_fields):
		return _failure("居民记忆介入第 %d 项字段损坏" % index)
	var intervention_id := String(item.get("intervention_id", "")).strip_edges()
	var memory_id := String(item.get("memory_id", "")).strip_edges()
	var kind := String(item.get("kind", ""))
	var operation := String(item.get("operation", _operation_for_kind(kind)))
	var status := String(item.get("status", ""))
	if (
		intervention_id.is_empty()
		or item.get("resident_id") != _resident_id
		or memory_id.is_empty()
		or kind not in KINDS
		or operation not in OPERATIONS
		or (item.has("operation") and operation != _operation_for_kind(kind))
		or status not in STATUSES
		or typeof(item.get("player_text")) != TYPE_STRING
		or String(item.get("player_text")).length() > 480
	):
		return _failure("居民记忆介入第 %d 项身份、类型或正文损坏" % index)
	var original := _validate_version(item.get("original_version"), index, "介入前版本")
	if not bool(original.get("ok", false)):
		return original
	var active := _validate_version(item.get("active_version"), index, "生效版本")
	if not bool(active.get("ok", false)):
		return active
	if not _valid_world_time(item.get("created_world_time")):
		return _failure("居民记忆介入第 %d 项世界时间损坏" % index)
	return {
		"ok": true,
		"intervention": {
			"intervention_id": intervention_id,
			"resident_id": _resident_id,
			"memory_id": memory_id,
			"kind": kind,
			"operation": operation,
			"original_version": original["version"],
			"active_version": active["version"],
			"player_text": String(item["player_text"]).strip_edges(),
			"created_world_time": (item["created_world_time"] as Dictionary).duplicate(true),
			"status": status,
		},
	}


func _operation_for_kind(kind: String) -> String:
	match kind:
		"distort":
			return "edit"
		"soften":
			return "edit"
		"suppress":
			return "delete"
		"implant":
			return "write"
	return ""


func _validate_version(value: Variant, index: int, label: String) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return _failure("居民记忆介入第 %d 项%s必须是对象" % [index, label])
	var version := value as Dictionary
	if not _has_exact_fields(version, VERSION_FIELDS):
		return _failure("居民记忆介入第 %d 项%s字段损坏" % [index, label])
	if (
		typeof(version.get("subject")) != TYPE_STRING
		or String(version.get("subject")).strip_edges().is_empty()
		or typeof(version.get("interpretation")) != TYPE_STRING
		or typeof(version.get("confidence")) != TYPE_INT
		or int(version.get("confidence")) < 0
		or int(version.get("confidence")) > 100
		or typeof(version.get("state")) != TYPE_STRING
		or typeof(version.get("active_version_id")) != TYPE_STRING
		or String(version.get("active_version_id")).strip_edges().is_empty()
	):
		return _failure("居民记忆介入第 %d 项%s内容损坏" % [index, label])
	return {"ok": true, "version": version.duplicate(true)}


func _valid_world_time(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false
	var time := value as Dictionary
	return (
		_has_exact_fields(time, ["day", "clock", "period"])
		and typeof(time.get("day")) == TYPE_INT
		and int(time.get("day")) >= 1
		and typeof(time.get("clock")) == TYPE_STRING
		and not String(time.get("clock")).strip_edges().is_empty()
		and typeof(time.get("period")) == TYPE_STRING
		and not String(time.get("period")).strip_edges().is_empty()
	)


func _read_path(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("无法读取居民记忆介入记录：%s" % path)
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	file = null
	if parse_error != OK:
		return _failure("居民记忆介入文件损坏：%s（%s）" % [path, parser.get_error_message()])
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
	return {"ok": true} if error == OK else _failure("无法恢复居民记忆介入备份：%s" % error_string(error))


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
