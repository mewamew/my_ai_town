class_name AgentSaveStore
extends RefCounted


const AgentFileSystemScript := preload("res://agent/AgentFileSystem.gd")
const RESIDENT_STATE_CODEC := preload(
	"res://agent/lifecycle/ResidentStateCodec.gd"
)
const RESIDENT_RUNTIME := preload("res://agent/ResidentRuntime.gd")
const FORMAT_VERSION := 3
const DEFAULT_STORE_ROOT := "user://agent_saves"
const TEST_STORE_ROOT := "user://agent_save_tests"
const DEBUG_STORE_ROOT := "user://agent_debug/saves"
const DEBUG_TEST_ROOT := "user://agent_debug/tests"
const SLOT_MANIFEST_FILE := "slot.json"
const SNAPSHOT_MANIFEST_FILE := "snapshot.json"
const RESIDENT_SET_FILE := "resident_set.json"
const CONTEXT_FIELDS := ["slot_id", "session_id", "save_revision"]
const STAGING_DIRECTORY := "_staging"
const STAGING_KEY_LENGTH := 24

var _store_root := DEFAULT_STORE_ROOT


func configure_debug_root(debug_root: String = DEBUG_STORE_ROOT) -> Dictionary:
	if _store_root != DEFAULT_STORE_ROOT:
		return {"ok": false, "errors": ["Agent 调试存储根目录只能配置一次"]}
	var normalized := debug_root.trim_suffix("/")
	var allowed := (
		normalized == DEBUG_STORE_ROOT
		or normalized.begins_with("%s/" % DEBUG_TEST_ROOT)
	)
	if not allowed or normalized.contains(".."):
		return {
			"ok": false,
			"errors": ["Agent 调试存储根目录必须位于 DEBUG 专属命名空间"],
		}
	_store_root = normalized
	return {"ok": true}


func configure_test_root(test_root: String) -> Dictionary:
	if _store_root != DEFAULT_STORE_ROOT:
		return {"ok": false, "errors": ["Agent 测试存储根目录只能配置一次"]}
	var normalized := test_root.trim_suffix("/")
	if not normalized.begins_with("%s/" % TEST_STORE_ROOT) or normalized.contains(".."):
		return {"ok": false, "errors": ["Agent 测试存储根目录必须位于 %s 下" % TEST_STORE_ROOT]}
	_store_root = normalized
	return {"ok": true}


func create_isolated_peer() -> RefCounted:
	var peer: RefCounted = AgentSaveStore.new()
	peer.set("_store_root", _store_root)
	return peer


func cleanup_test_root() -> Dictionary:
	if not _store_root.begins_with("%s/" % TEST_STORE_ROOT):
		return {"ok": false, "errors": ["当前 Agent Store 未配置测试根目录"]}
	var remove_error := AgentFileSystemScript.remove_tree(_store_root)
	if remove_error != OK:
		return {"ok": false, "errors": ["清理 Agent 测试根目录失败：%s" % error_string(remove_error)]}
	DirAccess.remove_absolute(_absolute(TEST_STORE_ROOT))
	return {"ok": true}


func validate_new_game(context: Variant) -> Dictionary:
	var errors := _validate_context(context)
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	var context_data := (context as Dictionary).duplicate(true)
	var final_root := _slot_root(context_data)
	if DirAccess.dir_exists_absolute(_absolute(final_root)) or FileAccess.file_exists(final_root):
		return {"ok": false, "errors": ["slot_id 对应的 Agent 存档已存在；开始新游戏前必须先删除原存档"]}
	return {"ok": true, "context": context_data}


func create_new_game(context: Variant, resident_payloads: Variant) -> Dictionary:
	var validation := validate_new_game(context)
	if not bool(validation.get("ok", false)):
		return validation
	var payload_errors := _validate_payloads(resident_payloads)
	if not payload_errors.is_empty():
		return {"ok": false, "errors": payload_errors}
	var context_data := validation["context"] as Dictionary
	var final_root := _slot_root(context_data)
	var staging_root := _new_staging_root("slot", final_root)
	var create_error := DirAccess.make_dir_recursive_absolute(_absolute(staging_root))
	if create_error != OK:
		return {"ok": false, "errors": ["无法创建 Agent 存档临时目录：%s" % error_string(create_error)]}
	var slot_result := _write_json(
		_join(staging_root, SLOT_MANIFEST_FILE),
		{"format_version": FORMAT_VERSION, "slot_id": context_data["slot_id"]},
	)
	if not bool(slot_result.get("ok", false)):
		AgentFileSystemScript.remove_tree(staging_root)
		return slot_result
	var snapshot_result := _write_snapshot(context_data, resident_payloads as Dictionary, staging_root)
	if not bool(snapshot_result.get("ok", false)):
		AgentFileSystemScript.remove_tree(staging_root)
		return snapshot_result
	var parent_error := DirAccess.make_dir_recursive_absolute(_absolute(_store_root))
	if parent_error != OK:
		AgentFileSystemScript.remove_tree(staging_root)
		return {"ok": false, "errors": ["无法创建 Agent 存档目录：%s" % error_string(parent_error)]}
	var rename_error := DirAccess.rename_absolute(_absolute(staging_root), _absolute(final_root))
	if rename_error != OK:
		AgentFileSystemScript.remove_tree(staging_root)
		return {"ok": false, "errors": ["无法原子提交 Agent 新游戏存档：%s" % error_string(rename_error)]}
	return {"ok": true, "context": context_data}


func save_snapshot(context: Variant, resident_payloads: Variant) -> Dictionary:
	var errors := _validate_context(context)
	errors.append_array(_validate_payloads(resident_payloads))
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	var context_data := (context as Dictionary).duplicate(true)
	var slot_result := _read_and_validate_slot(context_data)
	if not bool(slot_result.get("ok", false)):
		return slot_result
	var result := _write_snapshot(context_data, resident_payloads as Dictionary)
	if not bool(result.get("ok", false)):
		return result
	return {"ok": true, "context": context_data}


func load_snapshot(context: Variant) -> Dictionary:
	var errors := _validate_context(context)
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	var context_data := (context as Dictionary).duplicate(true)
	var slot_result := _read_and_validate_slot(context_data)
	if not bool(slot_result.get("ok", false)):
		return slot_result

	var session_root := _session_root(context_data)
	if not DirAccess.dir_exists_absolute(_absolute(session_root)):
		return {"ok": false, "errors": ["session_id 对应的 Agent 存档不存在"]}
	var snapshot_root := _snapshot_root(context_data)
	if not DirAccess.dir_exists_absolute(_absolute(snapshot_root)):
		return {"ok": false, "errors": ["save_revision 对应的 Agent 快照不存在"]}
	var manifest_result := _read_json(_join(snapshot_root, SNAPSHOT_MANIFEST_FILE))
	if not bool(manifest_result.get("ok", false)):
		return manifest_result
	var manifest := manifest_result["value"] as Dictionary
	var identity_errors := _snapshot_identity_errors(manifest, context_data)
	if not identity_errors.is_empty():
		return {"ok": false, "errors": identity_errors}
	if typeof(manifest.get("residents")) != TYPE_ARRAY:
		return {"ok": false, "errors": ["Agent 快照 residents 损坏"]}
	var resident_set_result := _read_resident_set(snapshot_root)
	if not bool(resident_set_result.get("ok", false)):
		return resident_set_result
	var stored_resident_ids := resident_set_result["resident_ids"] as Array
	var resident_entries := manifest["residents"] as Array
	var resident_count: Variant = manifest.get("resident_count")
	if not _is_non_negative_integer_number(resident_count) \
		or int(resident_count) != resident_entries.size():
		return {"ok": false, "errors": ["Agent 快照居民集合数量不一致"]}
	var expected_resident_set_sha256: Variant = manifest.get("resident_set_sha256")
	if typeof(expected_resident_set_sha256) != TYPE_STRING \
		or String(expected_resident_set_sha256).length() != 64:
		return {"ok": false, "errors": ["Agent 快照居民集合摘要无效"]}

	var resident_payloads := {}
	var used_files := {}
	var loaded_resident_ids: Array = []
	for value: Variant in resident_entries:
		if typeof(value) != TYPE_DICTIONARY:
			return {"ok": false, "errors": ["Agent 快照居民条目损坏"]}
		var entry := value as Dictionary
		var resident_id := String(entry.get("resident_id", ""))
		var resident_name := String(entry.get("resident_name", ""))
		if (
			not _is_safe_resident_id(resident_id)
			or resident_name.is_empty()
			or resident_payloads.has(resident_id)
		):
			return {"ok": false, "errors": ["Agent 快照居民身份损坏或重复"]}
		loaded_resident_ids.append(resident_id)
		var payload_result := _read_checked_resident_payload(snapshot_root, entry)
		if payload_result.get("ok") != true:
			return payload_result
		var file_name := String(payload_result.get("fileName", ""))
		if used_files.has(file_name):
			return {"ok": false, "errors": ["Agent 快照居民文件引用重复"]}
		used_files[file_name] = true
		var payload := payload_result.get("payload") as PackedByteArray
		resident_payloads[resident_id] = {
			"resident_name": resident_name,
			"payload": payload,
		}
	loaded_resident_ids.sort()
	if loaded_resident_ids != stored_resident_ids:
		return {"ok": false, "errors": ["Agent 快照居民集合与独立集合记录不一致"]}
	if _resident_set_sha256(loaded_resident_ids) != String(expected_resident_set_sha256):
		return {"ok": false, "errors": ["Agent 快照居民集合摘要不一致"]}
	return {
		"ok": true,
		"context": context_data,
		"resident_payloads": resident_payloads,
	}


func inspect_snapshot_versions(context: Variant) -> Dictionary:
	var errors := _validate_context(context)
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	var context_data := (context as Dictionary).duplicate(true)
	var slot_result := _read_json(
		_join(_slot_root(context_data), SLOT_MANIFEST_FILE),
	)
	var snapshot_root := _snapshot_root(context_data)
	var snapshot_result := _read_json(
		_join(snapshot_root, SNAPSHOT_MANIFEST_FILE),
	)
	if slot_result.get("ok") != true:
		return slot_result
	if snapshot_result.get("ok") != true:
		return snapshot_result
	var slot_manifest := slot_result.get("value", {}) as Dictionary
	var snapshot_manifest := snapshot_result.get("value", {}) as Dictionary
	var slot_version: Variant = slot_manifest.get("format_version")
	var snapshot_version: Variant = snapshot_manifest.get("format_version")
	if (
		not _is_non_negative_integer_number(slot_version)
		or not _is_non_negative_integer_number(snapshot_version)
	):
		return {"ok": false, "errors": ["Agent 存档版本字段损坏"]}
	var agent_version := maxi(int(slot_version), int(snapshot_version))
	var versions := {"agent": agent_version}
	if agent_version != FORMAT_VERSION:
		return {"ok": true, "versions": versions}
	var entries_value: Variant = snapshot_manifest.get("residents")
	if not entries_value is Array or (entries_value as Array).is_empty():
		return {"ok": false, "errors": ["Agent 快照居民版本证据缺失"]}
	var observed := {
		"residentPayload": {},
		"residentRuntime": {},
		"residentMemory": {},
	}
	for entry_value: Variant in entries_value as Array:
		if not entry_value is Dictionary:
			return {"ok": false, "errors": ["Agent 快照居民条目损坏"]}
		var entry := entry_value as Dictionary
		var payload_result := _read_checked_resident_payload(snapshot_root, entry)
		if payload_result.get("ok") != true:
			return payload_result
		var payload := payload_result.get("payload") as PackedByteArray
		if payload.size() < 4:
			return {"ok": false, "errors": ["居民状态版本证据损坏"]}
		var decoded: Variant = bytes_to_var(payload)
		if not decoded is Dictionary:
			return {"ok": false, "errors": ["居民状态版本证据损坏"]}
		var envelope := decoded as Dictionary
		var payload_version := _integer_version(envelope.get("format_version"))
		if payload_version < 0:
			return {"ok": false, "errors": ["居民载荷版本字段损坏"]}
		(observed["residentPayload"] as Dictionary)[payload_version] = true
		if payload_version != RESIDENT_STATE_CODEC.FORMAT_VERSION:
			versions["residentPayload"] = payload_version
			return {"ok": true, "versions": versions}
		var state_value: Variant = envelope.get("resident_state")
		if not state_value is Dictionary:
			return {"ok": false, "errors": ["居民运行时版本证据损坏"]}
		var state := state_value as Dictionary
		var runtime_version := _integer_version(
			state.get("runtime_state_version"),
		)
		if runtime_version < 0:
			return {"ok": false, "errors": ["居民运行时版本字段损坏"]}
		(observed["residentRuntime"] as Dictionary)[runtime_version] = true
		if runtime_version not in [
			RESIDENT_RUNTIME.LEGACY_PERSISTENT_STATE_VERSION,
			RESIDENT_RUNTIME.PERSISTENT_STATE_VERSION,
		]:
			versions["residentPayload"] = payload_version
			versions["residentRuntime"] = runtime_version
			return {"ok": true, "versions": versions}
		var memory_value: Variant = state.get("memory_system")
		if not memory_value is Dictionary:
			return {"ok": false, "errors": ["居民记忆版本证据损坏"]}
		var memory_version := _integer_version(
			(memory_value as Dictionary).get("memory_state_version"),
		)
		if memory_version < 0:
			return {"ok": false, "errors": ["居民记忆版本字段损坏"]}
		(observed["residentMemory"] as Dictionary)[memory_version] = true
	for key_value: Variant in observed:
		var key := String(key_value)
		var found := (observed.get(key, {}) as Dictionary).keys()
		if found.size() != 1:
			return {"ok": false, "errors": ["Agent 居民版本组合不一致"]}
		versions[key] = int(found[0])
	return {"ok": true, "versions": versions}


func delete_slot(context: Variant) -> Dictionary:
	var errors := _validate_context(context)
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	var context_data := (context as Dictionary).duplicate(true)
	var slot_result := _read_and_validate_slot(context_data)
	if not bool(slot_result.get("ok", false)):
		return slot_result
	var snapshot_result := load_snapshot(context_data)
	if not bool(snapshot_result.get("ok", false)):
		return snapshot_result
	var remove_error := AgentFileSystemScript.remove_tree(_slot_root(context_data))
	if remove_error != OK:
		return {"ok": false, "errors": ["删除 Agent 存档失败：%s" % error_string(remove_error)]}
	return {"ok": true}


func _write_snapshot(
	context: Dictionary,
	resident_payloads: Dictionary,
	slot_root_override := "",
) -> Dictionary:
	var final_root := _snapshot_root(context, slot_root_override)
	if DirAccess.dir_exists_absolute(_absolute(final_root)):
		return {"ok": false, "errors": ["save_revision 已存在，Agent 快照不可覆盖"]}
	var staging_root := _new_staging_root("snapshot", final_root)
	var create_error := DirAccess.make_dir_recursive_absolute(_absolute(staging_root))
	if create_error != OK:
		return {"ok": false, "errors": ["无法创建 Agent 快照临时目录：%s" % error_string(create_error)]}

	var resident_ids: Array = resident_payloads.keys()
	resident_ids.sort()
	var entries: Array[Dictionary] = []
	for index in resident_ids.size():
		var resident_id := String(resident_ids[index])
		var payload_record := resident_payloads[resident_id] as Dictionary
		var resident_name := String(payload_record["resident_name"])
		var file_name := "resident_%04d.bin" % index
		var payload_file := FileAccess.open(_join(staging_root, file_name), FileAccess.WRITE)
		if payload_file == null:
			AgentFileSystemScript.remove_tree(staging_root)
			return {"ok": false, "errors": ["无法写入居民 %s 的 Agent 载荷" % resident_id]}
		var payload := payload_record["payload"] as PackedByteArray
		payload_file.store_buffer(payload)
		payload_file.flush()
		var write_error := payload_file.get_error()
		payload_file = null
		if write_error != OK:
			AgentFileSystemScript.remove_tree(staging_root)
			return {
				"ok": false,
				"errors": ["写入居民 %s 的 Agent 载荷失败：%s" % [resident_id, error_string(write_error)]],
			}
		var digest := _sha256(payload)
		if digest.length() != 64:
			AgentFileSystemScript.remove_tree(staging_root)
			return {"ok": false, "errors": ["计算居民 %s 的 SHA-256 失败" % resident_id]}
		entries.append({
			"resident_id": resident_id,
			"resident_name": resident_name,
			"file": file_name,
			"byte_length": payload.size(),
			"sha256": digest,
		})

	var resident_set_result := _write_json(
		_join(staging_root, RESIDENT_SET_FILE),
		{
			"resident_ids": resident_ids,
			"resident_set_sha256": _resident_set_sha256(resident_ids),
		},
	)
	if not bool(resident_set_result.get("ok", false)):
		AgentFileSystemScript.remove_tree(staging_root)
		return resident_set_result
	var manifest_result := _write_json(
		_join(staging_root, SNAPSHOT_MANIFEST_FILE),
		{
			"format_version": FORMAT_VERSION,
			"slot_id": context["slot_id"],
			"session_id": context["session_id"],
			"save_revision": context["save_revision"],
			"resident_count": resident_ids.size(),
			"resident_set_sha256": _resident_set_sha256(resident_ids),
			"residents": entries,
		},
	)
	if not bool(manifest_result.get("ok", false)):
		AgentFileSystemScript.remove_tree(staging_root)
		return manifest_result
	var parent_error := DirAccess.make_dir_recursive_absolute(_absolute(final_root.get_base_dir()))
	if parent_error != OK:
		AgentFileSystemScript.remove_tree(staging_root)
		return {"ok": false, "errors": ["无法创建 Agent revision 目录：%s" % error_string(parent_error)]}
	var rename_error := DirAccess.rename_absolute(_absolute(staging_root), _absolute(final_root))
	if rename_error != OK:
		AgentFileSystemScript.remove_tree(staging_root)
		return {"ok": false, "errors": ["无法原子提交 Agent 快照：%s" % error_string(rename_error)]}
	return {"ok": true}


func _read_and_validate_slot(context: Dictionary) -> Dictionary:
	if not DirAccess.dir_exists_absolute(_absolute(_slot_root(context))):
		return {"ok": false, "errors": ["slot_id 对应的 Agent 存档不存在"]}
	var manifest_result := _read_json(_join(_slot_root(context), SLOT_MANIFEST_FILE))
	if not bool(manifest_result.get("ok", false)):
		return manifest_result
	var manifest := manifest_result["value"] as Dictionary
	var errors: Array[String] = []
	if manifest.get("format_version") != FORMAT_VERSION:
		errors.append("Agent 存档 format_version 不受支持")
	if String(manifest.get("slot_id", "")) != String(context["slot_id"]):
		errors.append("Agent 存档 slot_id 与上下文不一致")
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	return {"ok": true}


func _snapshot_identity_errors(manifest: Dictionary, context: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if manifest.get("format_version") != FORMAT_VERSION:
		errors.append("Agent 快照 format_version 不受支持")
	if String(manifest.get("slot_id", "")) != String(context["slot_id"]):
		errors.append("Agent 快照 slot_id 与上下文不一致")
	if String(manifest.get("session_id", "")) != String(context["session_id"]):
		errors.append("Agent 快照 session_id 与上下文不一致")
	if manifest.get("save_revision") != context["save_revision"]:
		errors.append("Agent 快照 save_revision 与上下文不一致")
	return errors


func _validate_context(context: Variant) -> Array[String]:
	var errors: Array[String] = []
	if typeof(context) != TYPE_DICTIONARY:
		return ["存档上下文必须是对象"]
	var value := context as Dictionary
	for key: Variant in value:
		if not CONTEXT_FIELDS.has(String(key)):
			errors.append("存档上下文 %s 不是允许字段" % String(key))
	for field_name in ["slot_id", "session_id"]:
		if typeof(value.get(field_name)) != TYPE_STRING or String(value.get(field_name)).is_empty():
			errors.append("存档上下文 %s 必须是非空字符串" % field_name)
	if typeof(value.get("save_revision")) != TYPE_INT or int(value.get("save_revision", -1)) < 0:
		errors.append("存档上下文 save_revision 必须是非负整数")
	if errors.is_empty():
		if not _is_safe_identifier(String(value["slot_id"])):
			errors.append("存档上下文 slot_id 包含非法字符")
		if not _is_safe_identifier(String(value["session_id"])):
			errors.append("存档上下文 session_id 包含非法字符")
	return errors


func _integer_version(value: Variant) -> int:
	return int(value) if _is_non_negative_integer_number(value) else -1


func _read_checked_resident_payload(
	snapshot_root: String,
	entry: Dictionary,
) -> Dictionary:
	var file_name := String(entry.get("file", ""))
	if file_name.is_empty() or file_name.get_file() != file_name:
		return {"ok": false, "errors": ["Agent 快照居民文件引用无效"]}
	var expected_length: Variant = entry.get("byte_length")
	var expected_sha256: Variant = entry.get("sha256")
	if (
		not _is_non_negative_integer_number(expected_length)
		or typeof(expected_sha256) != TYPE_STRING
		or String(expected_sha256).length() != 64
	):
		return {"ok": false, "errors": ["Agent 快照居民载荷清单损坏"]}
	var file := FileAccess.open(_join(snapshot_root, file_name), FileAccess.READ)
	if file == null:
		return {"ok": false, "errors": ["Agent 快照居民载荷缺失"]}
	var payload := file.get_buffer(file.get_length())
	file = null
	if payload.size() != int(expected_length):
		return {"ok": false, "errors": ["Agent 快照居民 byte_length 不一致"]}
	if _sha256(payload) != String(expected_sha256):
		return {"ok": false, "errors": ["Agent 快照居民 SHA-256 不一致"]}
	return {"ok": true, "fileName": file_name, "payload": payload}


func _validate_payloads(resident_payloads: Variant) -> Array[String]:
	var errors: Array[String] = []
	if typeof(resident_payloads) != TYPE_DICTIONARY:
		return ["resident_payloads 必须是对象"]
	for key: Variant in (resident_payloads as Dictionary).keys():
		if (
			typeof(key) != TYPE_STRING
			or not _is_safe_resident_id(String(key))
		):
			errors.append("居民载荷键必须是合法 resident_id")
			continue
		var record: Variant = (resident_payloads as Dictionary)[key]
		if typeof(record) != TYPE_DICTIONARY:
			errors.append("居民 %s 的 Agent 载荷记录必须是对象" % key)
			continue
		var payload_record := record as Dictionary
		if payload_record.size() != 2:
			errors.append("居民 %s 的 Agent 载荷记录字段不完整" % key)
		if (
			typeof(payload_record.get("resident_name")) != TYPE_STRING
			or String(payload_record.get("resident_name")).strip_edges().is_empty()
		):
			errors.append("居民 %s 的显示名必须是非空文本" % key)
		if typeof(payload_record.get("payload")) != TYPE_PACKED_BYTE_ARRAY:
			errors.append("居民 %s 的 Agent 状态必须是 PackedByteArray 不透明载荷" % key)
	return errors


func _is_safe_identifier(value: String) -> bool:
	return AgentFileSystemScript.is_safe_path_segment(value)


func _is_safe_resident_id(value: String) -> bool:
	return _is_safe_identifier(value) and value == value.to_lower()


func _is_non_negative_integer_number(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var number := float(value)
	return number >= 0.0 and number == floor(number)


func _write_json(path: String, value: Dictionary) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "errors": ["无法写入 Agent 存档文件：%s" % path]}
	file.store_string(JSON.stringify(value, "\t"))
	file.flush()
	var write_error := file.get_error()
	file = null
	if write_error != OK:
		return {
			"ok": false,
			"errors": ["写入 Agent 存档文件失败：%s" % error_string(write_error)],
		}
	return {"ok": true}


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "errors": ["Agent 存档文件不存在：%s" % path]}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK:
		return {"ok": false, "errors": ["Agent 存档文件损坏：%s" % path]}
	var parsed: Variant = parser.data
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "errors": ["Agent 存档文件损坏：%s" % path]}
	return {"ok": true, "value": parsed}


func _read_resident_set(snapshot_root: String) -> Dictionary:
	var result := _read_json(_join(snapshot_root, RESIDENT_SET_FILE))
	if not bool(result.get("ok", false)):
		return result
	var value := result["value"] as Dictionary
	if typeof(value.get("resident_ids")) != TYPE_ARRAY:
		return {"ok": false, "errors": ["Agent 快照独立居民集合损坏"]}
	var resident_ids := value["resident_ids"] as Array
	var normalized_ids: Array = []
	var used_ids := {}
	for resident_id: Variant in resident_ids:
		if typeof(resident_id) != TYPE_STRING or not _is_safe_resident_id(String(resident_id)):
			return {"ok": false, "errors": ["Agent 快照独立居民集合包含无效身份"]}
		if used_ids.has(resident_id):
			return {"ok": false, "errors": ["Agent 快照独立居民集合包含重复身份"]}
		used_ids[resident_id] = true
		normalized_ids.append(resident_id)
	normalized_ids.sort()
	if normalized_ids != resident_ids:
		return {"ok": false, "errors": ["Agent 快照独立居民集合顺序损坏"]}
	var expected_sha256: Variant = value.get("resident_set_sha256")
	if typeof(expected_sha256) != TYPE_STRING \
		or String(expected_sha256) != _resident_set_sha256(normalized_ids):
		return {"ok": false, "errors": ["Agent 快照独立居民集合摘要不一致"]}
	return {"ok": true, "resident_ids": normalized_ids}


func _slot_root(context: Dictionary) -> String:
	return _join(_store_root, String(context["slot_id"]))


func _session_root(context: Dictionary, slot_root_override := "") -> String:
	var root := slot_root_override if not slot_root_override.is_empty() else _slot_root(context)
	return _join(root, "sessions/%s" % context["session_id"])


func _snapshot_root(context: Dictionary, slot_root_override := "") -> String:
	return _join(
		_session_root(context, slot_root_override),
		"revisions/%d" % int(context["save_revision"]),
	)


func _new_staging_root(kind: String, identity: String) -> String:
	var entropy := "%s:%s:%d:%d:%d" % [
		kind,
		identity,
		OS.get_process_id(),
		Time.get_ticks_usec(),
		randi(),
	]
	return _join(
		_store_root,
		"%s/%s-%s" % [
			STAGING_DIRECTORY,
			kind,
			entropy.sha256_text().left(STAGING_KEY_LENGTH),
		],
	)


func _absolute(path: String) -> String:
	return ProjectSettings.globalize_path(path)


func _sha256(payload: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK:
		return ""
	hashing.update(payload)
	return hashing.finish().hex_encode()


func _resident_set_sha256(resident_ids: Array) -> String:
	return _sha256(JSON.stringify(resident_ids).to_utf8_buffer())


func _join(base: String, child: String) -> String:
	return "%s/%s" % [base.trim_suffix("/"), child.trim_prefix("/")]
