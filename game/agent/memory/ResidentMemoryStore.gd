class_name AgentResidentMemoryStore
extends RefCounted


const FIELDS := [
	"important_memories",
	"relationships",
	"current_thoughts",
	"long_term_goals",
	"short_term_goals",
]
const TARGET_LIMITS := {
	"important_memories": 2000,
	"relationships": 1300,
	"current_thoughts": 600,
	"long_term_goals": 600,
	"short_term_goals": 1000,
}
const HARD_LIMITS := {
	"important_memories": 2400,
	"relationships": 1560,
	"current_thoughts": 720,
	"long_term_goals": 720,
	"short_term_goals": 1200,
}
const TARGET_TOTAL := 5000
const HARD_TOTAL := 6000

var _path: String
var _directory_ready := false


func _init(path: String) -> void:
	_path = path


func read() -> Dictionary:
	var recovery := _recover_backup()
	if not bool(recovery.get("ok", false)):
		return recovery
	if not FileAccess.file_exists(_path):
		return {"ok": true, "memory": empty_memory()}
	return _read_path(_path)


func replace(value: Variant) -> Dictionary:
	var validation := validate(value)
	if not bool(validation.get("ok", false)):
		return validation
	var memory := validation["memory"] as Dictionary
	var directory_error := OK
	if not _directory_ready:
		directory_error = DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(_path.get_base_dir()),
		)
		if directory_error == OK or directory_error == ERR_ALREADY_EXISTS:
			_directory_ready = true
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return _failure("无法创建居民记忆目录：%s" % error_string(directory_error))

	var temporary_path := "%s.tmp" % _path
	var backup_path := "%s.bak" % _path
	_remove_file(temporary_path)
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null and _directory_ready:
		_directory_ready = false
		directory_error = DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(_path.get_base_dir()),
		)
		if directory_error == OK or directory_error == ERR_ALREADY_EXISTS:
			_directory_ready = true
			file = FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return _failure("无法写入居民记忆临时文件：%s" % temporary_path)
	# 写入内容刚通过 validate，不再读回验证；原子性由临时文件 + rename 保证。
	file.store_string(JSON.stringify(memory, "  ", false))
	file.flush()
	var write_error := file.get_error()
	file = null
	if write_error != OK:
		_remove_file(temporary_path)
		return _failure("无法写入居民记忆：%s" % error_string(write_error))

	var used_backup_fallback := false
	var replace_error := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temporary_path),
		ProjectSettings.globalize_path(_path),
	)
	if replace_error != OK and FileAccess.file_exists(_path):
		_remove_file(backup_path)
		used_backup_fallback = true
		var backup_error := DirAccess.rename_absolute(
			ProjectSettings.globalize_path(_path),
			ProjectSettings.globalize_path(backup_path),
		)
		if backup_error != OK:
			_remove_file(temporary_path)
			return _failure("无法准备居民记忆原子替换：%s" % error_string(backup_error))
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
		return _failure("无法提交居民记忆：%s" % error_string(replace_error))
	if used_backup_fallback:
		_remove_file(backup_path)
	return {"ok": true, "memory": memory.duplicate(true)}


func validate(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return _failure("居民记忆必须是 JSON 对象")
	var memory := value as Dictionary
	if not _has_exact_fields(memory, FIELDS):
		return _failure("居民记忆必须精确包含五个字符串字段")
	var overflow_fields: Array[String] = []
	var total := 0
	for field_name: String in FIELDS:
		var field_value: Variant = memory.get(field_name)
		if typeof(field_value) != TYPE_STRING:
			return _failure("居民记忆 %s 必须是字符串" % field_name)
		var length := String(field_value).length()
		total += length
		if length > int(HARD_LIMITS[field_name]):
			overflow_fields.append(field_name)
	if total > HARD_TOTAL:
		overflow_fields.append("total")
	if not overflow_fields.is_empty():
		return {
			"ok": false,
			"errors": ["居民记忆超过代码容量上限：%s" % ", ".join(overflow_fields)],
			"retryable": true,
			"overflow_fields": overflow_fields,
			"limits": capacity(),
		}
	return {"ok": true, "memory": memory.duplicate(true)}


func empty_memory() -> Dictionary:
	return {
		"important_memories": "",
		"relationships": "",
		"current_thoughts": "",
		"long_term_goals": "",
		"short_term_goals": "",
	}


func capacity() -> Dictionary:
	return {
		"target_fields": TARGET_LIMITS.duplicate(true),
		"hard_fields": HARD_LIMITS.duplicate(true),
		"target_total": TARGET_TOTAL,
		"hard_total": HARD_TOTAL,
	}


func _read_path(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("无法读取居民记忆：%s" % path)
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	file = null
	if parse_error != OK:
		return _failure(
			"居民记忆文件损坏：%s（%s）"
			% [path, parser.get_error_message()],
		)
	var parsed: Variant = parser.data
	var validation := validate(parsed)
	if not bool(validation.get("ok", false)):
		var result := validation.duplicate(true)
		var errors: Array = result.get("errors", []).duplicate()
		errors.append("居民记忆文件损坏：%s" % path)
		result["errors"] = errors
		return result
	return {"ok": true, "memory": (validation["memory"] as Dictionary).duplicate(true)}


func _recover_backup() -> Dictionary:
	var backup_path := "%s.bak" % _path
	var temporary_path := "%s.tmp" % _path
	_remove_file(temporary_path)
	if not FileAccess.file_exists(backup_path):
		return {"ok": true}
	if FileAccess.file_exists(_path):
		_remove_file(backup_path)
		return {"ok": true}
	var restore_error := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(backup_path),
		ProjectSettings.globalize_path(_path),
	)
	if restore_error != OK:
		return _failure("无法恢复居民记忆备份：%s" % error_string(restore_error))
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
