class_name AgentResidentAvatarEvidenceQueue
extends RefCounted

const TEST_FILE_SYSTEM := preload("res://agent/AgentFileSystem.gd")


const AgentJsonScript := preload("res://agent/AgentJson.gd")
const STATE_VERSION := 1
const MAX_ITEMS := 16
const SOURCE_TYPES: Array[String] = [
	"direct_dialogue",
	"direct_observation",
	"hearsay",
]

var _path: String
var _resident_id: String
var _avatar_person_id: String
var _avatar_name: String
var _items: Array[Dictionary] = []
var _known_source_hashes: Dictionary = {}
var _new_items_since_organization := 0
var _loaded := false
var _file_expected := false


func _init(
	path: String,
	resident_id: String,
	avatar_person_id: String,
	avatar_name := "旅行者",
) -> void:
	_path = path
	_resident_id = resident_id
	_avatar_person_id = avatar_person_id
	_avatar_name = String(avatar_name).strip_edges()


func read() -> Dictionary:
	var load_result := _ensure_loaded()
	if not bool(load_result.get("ok", false)):
		return load_result
	return {
		"ok": true,
		"items": _items.duplicate(true),
		"new_items_since_organization": _new_items_since_organization,
	}


func initialize_empty() -> Dictionary:
	if FileAccess.file_exists(_path):
		return _ensure_loaded()
	var write_result := _replace_file([], {}, 0)
	if not bool(write_result.get("ok", false)):
		return write_result
	_items = []
	_known_source_hashes = {}
	_new_items_since_organization = 0
	_loaded = true
	_file_expected = true
	return {"ok": true}


func append_wake(wake_packet: Dictionary) -> Dictionary:
	var load_result := _ensure_loaded()
	if not bool(load_result.get("ok", false)):
		return load_result
	var extracted := _extract_evidence(wake_packet)
	if not bool(extracted.get("ok", false)):
		return extracted
	var staged_hashes := _known_source_hashes.duplicate(true)
	var added_items: Array[Dictionary] = []
	for item_value: Variant in extracted.get("items", []) as Array:
		var item := item_value as Dictionary
		var source_ref := String(item.get("source_ref", ""))
		var digest := AgentJsonScript.content_sha256(item)
		if staged_hashes.has(source_ref):
			var existing_item := _find_staged_item(
				source_ref,
				added_items,
			)
			if (
				not existing_item.is_empty()
				and String(existing_item.get("evidence_id", ""))
				!= String(item.get("evidence_id", ""))
			):
				return _failure(
					"化身证据来源编号对应了不同内容：%s" % source_ref,
				)
			continue
		staged_hashes[source_ref] = digest
		added_items.append(item.duplicate(true))
	if added_items.is_empty():
		return {
			"ok": true,
			"added": false,
			"added_items": [],
			"items": _items.duplicate(true),
			"new_items_since_organization": _new_items_since_organization,
			"direct_avatar_conversation_ended": false,
		}
	var candidate := _items.duplicate(true)
	candidate.append_array(added_items)
	var new_count := _new_items_since_organization + added_items.size()
	var organized_count := maxi(0, candidate.size() - new_count)
	while candidate.size() > MAX_ITEMS and organized_count > 0:
		candidate.pop_front()
		organized_count -= 1
	while candidate.size() > MAX_ITEMS:
		candidate.pop_front()
		new_count -= 1
	var write_result := _replace_file(candidate, staged_hashes, new_count)
	if not bool(write_result.get("ok", false)):
		return write_result
	_items = candidate
	_known_source_hashes = _hashes_for_items(candidate)
	_new_items_since_organization = maxi(0, new_count)
	_file_expected = true
	return {
		"ok": true,
		"added": true,
		"added_items": added_items.duplicate(true),
		"items": _items.duplicate(true),
		"new_items_since_organization": _new_items_since_organization,
		"direct_avatar_conversation_ended": bool(
			extracted.get("direct_avatar_conversation_ended", false)
		),
	}


func _find_staged_item(
	source_ref: String,
	added_items: Array[Dictionary],
) -> Dictionary:
	for item in added_items:
		if String(item.get("source_ref", "")) == source_ref:
			return item
	for item in _items:
		if String(item.get("source_ref", "")) == source_ref:
			return item
	return {}


func mark_organized() -> Dictionary:
	var load_result := _ensure_loaded()
	if not bool(load_result.get("ok", false)):
		return load_result
	var write_result := _replace_file(_items, _known_source_hashes, 0)
	if not bool(write_result.get("ok", false)):
		return write_result
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
			"resident_id": _resident_id,
			"avatar_person_id": _avatar_person_id,
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
		return _failure("居民化身证据队列恢复目标不是空状态")
	var validation := validate_state(value)
	if not bool(validation.get("ok", false)):
		return validation
	var state := validation["queue_state"] as Dictionary
	var items: Array[Dictionary] = []
	items.assign(state["items"])
	var write_result := _replace_file(
		items,
		state["known_source_hashes"] as Dictionary,
		int(state["new_items_since_organization"]),
	)
	if not bool(write_result.get("ok", false)):
		return write_result
	_items = items
	_known_source_hashes = (
		state["known_source_hashes"] as Dictionary
	).duplicate(true)
	_new_items_since_organization = int(
		state["new_items_since_organization"],
	)
	_loaded = true
	_file_expected = true
	return {"ok": true}


func validate_state(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return _failure("居民化身证据队列持久状态必须是对象")
	var state := value as Dictionary
	if not _has_exact_fields(
		state,
		[
			"queue_state_version",
			"resident_id",
			"avatar_person_id",
			"items",
			"known_source_hashes",
			"new_items_since_organization",
		],
	):
		return _failure("居民化身证据队列持久状态字段损坏")
	if (
		state.get("queue_state_version") != STATE_VERSION
		or state.get("resident_id") != _resident_id
		or state.get("avatar_person_id") != _avatar_person_id
		or typeof(state.get("items")) != TYPE_ARRAY
		or typeof(state.get("known_source_hashes")) != TYPE_DICTIONARY
		or typeof(state.get("new_items_since_organization")) != TYPE_INT
	):
		return _failure("居民化身证据队列持久状态类型或归属损坏")
	var items_result := _validate_items(state["items"])
	if not bool(items_result.get("ok", false)):
		return items_result
	var hashes := state["known_source_hashes"] as Dictionary
	for source_ref_value: Variant in hashes:
		if (
			typeof(source_ref_value) != TYPE_STRING
			or String(source_ref_value).strip_edges().is_empty()
			or typeof(hashes[source_ref_value]) != TYPE_STRING
			or String(hashes[source_ref_value]).length() != 64
		):
			return _failure("居民化身证据来源去重索引损坏")
	var expected_hashes := {}
	for item_value: Variant in items_result["items"]:
		var item := item_value as Dictionary
		expected_hashes[String(item["source_ref"])] = (
			AgentJsonScript.content_sha256(item)
		)
	for source_ref: Variant in expected_hashes:
		if hashes.get(source_ref) != expected_hashes[source_ref]:
			return _failure("居民化身证据来源去重索引与内容不一致")
	var new_count := int(state["new_items_since_organization"])
	if new_count < 0 or new_count > (items_result["items"] as Array).size():
		return _failure("居民化身证据新增计数损坏")
	return {
		"ok": true,
		"queue_state": {
			"queue_state_version": STATE_VERSION,
			"resident_id": _resident_id,
			"avatar_person_id": _avatar_person_id,
				"items": (items_result["items"] as Array).duplicate(true),
				"known_source_hashes": expected_hashes.duplicate(true),
				"new_items_since_organization": new_count,
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


func _extract_evidence(wake: Dictionary) -> Dictionary:
	var result: Array[Dictionary] = []
	var direct_avatar_conversation_ended := false
	var snapshot := wake.get("snapshot", {}) as Dictionary
	var snapshot_time := snapshot.get("time", {}) as Dictionary
	var conversation_value: Variant = snapshot.get("conversation")
	if typeof(conversation_value) == TYPE_DICTIONARY:
		var conversation := conversation_value as Dictionary
		var turns := conversation.get("turns", []) as Array
		var direct := (
			String(conversation.get("with_resident_id", ""))
			== _avatar_person_id
			or _turns_include_avatar(turns)
		)
		if direct or _turns_mention_avatar(turns):
			_append_turns(
				result,
				String(conversation.get("conversation_id", "")),
				turns,
				snapshot_time,
				direct,
			)
	for event_value: Variant in wake.get("events", []) as Array:
		if typeof(event_value) != TYPE_DICTIONARY:
			continue
		var event := event_value as Dictionary
		var event_type := String(event.get("type", ""))
		var event_time := event.get("time", snapshot_time) as Dictionary
		if event_type == "对话结束":
			var turns := event.get("turns", []) as Array
			var direct := _turns_include_avatar(turns)
			if direct or _turns_mention_avatar(turns):
				_append_turns(
					result,
					String(event.get("conversation_id", "")),
					turns,
					event_time,
					direct,
				)
			direct_avatar_conversation_ended = (
				direct_avatar_conversation_ended or direct
			)
		elif ["搭话", "对方答话", "旁听"].has(event_type):
			var turn_value: Variant = event.get("turn")
			if typeof(turn_value) != TYPE_DICTIONARY:
				continue
			var turn := turn_value as Dictionary
			var direct := _contains_avatar_id(event)
			for speaker_id_value: Variant in (
				event.get("speaker_resident_ids", []) as Array
			):
				if String(speaker_id_value) == _avatar_person_id:
					direct = true
			if direct or _turn_mentions_avatar(turn):
				_append_turns(
					result,
					String(event.get("conversation_id", "")),
					[turn],
					event_time,
					direct,
				)
		elif (
			["有人来了", "有人走了"].has(event_type)
			and String(event.get("who_resident_id", "")) == _avatar_person_id
		):
			_append_event(result, event, "direct_observation")
		elif _contains_avatar_id(event):
			_append_event(result, event, "direct_observation")
	return {
		"ok": true,
		"items": result,
		"direct_avatar_conversation_ended": direct_avatar_conversation_ended,
	}


func _append_turns(
	target: Array[Dictionary],
	conversation_id: String,
	turns: Array,
	fallback_time: Dictionary,
	direct_conversation: bool,
) -> void:
	if conversation_id.strip_edges().is_empty():
		return
	for index in turns.size():
		if typeof(turns[index]) != TYPE_DICTIONARY:
			continue
		var turn := turns[index] as Dictionary
		var turn_id := int(turn.get("turn_id", index + 1))
		var speaker_id := String(
			turn.get("speaker_resident_id", ""),
		).strip_edges()
		if speaker_id.is_empty():
			continue
		var say := String(turn.get("say", "")).strip_edges()
		var narration := String(turn.get("narration", "")).strip_edges()
		# A resident's own scene action belongs to the conversation presentation,
		# not to what they know about the avatar. Keep narration only when it
		# describes an action performed by the avatar itself.
		if speaker_id != _avatar_person_id:
			narration = ""
		if say.is_empty() and narration.is_empty():
			continue
		var source_ref := "conversation:%s:turn:%d" % [
			conversation_id,
			turn_id,
		]
		var direct := direct_conversation or speaker_id == _avatar_person_id
		var payload := {
			"conversation_id": conversation_id,
			"turn_id": turn_id,
			"speaker_resident_id": speaker_id,
			"speaker": String(turn.get("speaker", "")),
			"say": say,
			"narration": narration,
			# 图片只允许在转文字阶段短暂存在；化身记忆只接收文字。
			"photos": [],
		}
		target.append(_evidence_item(
			source_ref,
			fallback_time,
			"direct_dialogue" if direct else "hearsay",
			speaker_id,
			direct,
			payload,
		))


func _append_event(
	target: Array[Dictionary],
	event: Dictionary,
	source_type: String,
) -> void:
	var event_id := String(event.get("event_id", "")).strip_edges()
	if event_id.is_empty():
		return
	target.append(_evidence_item(
		"event:%s" % event_id,
		event.get("time", {}) as Dictionary,
		source_type,
		String(event.get("who_resident_id", _avatar_person_id)),
		true,
		event,
	))


func _evidence_item(
	source_ref: String,
	world_time: Dictionary,
	source_type: String,
	source_person_id: String,
	direct_avatar: bool,
	payload: Dictionary,
) -> Dictionary:
	var digest := AgentJsonScript.content_sha256({
		"source_ref": source_ref,
		"payload": payload,
	})
	return {
		"evidence_id": "avatar-evidence-%s" % digest.left(20),
		"source_ref": source_ref,
		"world_time": _normalized_time(world_time),
		"source_type": source_type,
		"source_person_id": source_person_id,
		"direct_avatar": direct_avatar,
		"payload": payload.duplicate(true),
	}


func _turns_include_avatar(turns: Array) -> bool:
	for turn_value: Variant in turns:
		if (
			typeof(turn_value) == TYPE_DICTIONARY
			and String(
				(turn_value as Dictionary).get("speaker_resident_id", ""),
			) == _avatar_person_id
		):
			return true
	return false


func _turns_mention_avatar(turns: Array) -> bool:
	for turn_value: Variant in turns:
		if (
			typeof(turn_value) == TYPE_DICTIONARY
			and _turn_mentions_avatar(turn_value as Dictionary)
		):
			return true
	return false


func _turn_mentions_avatar(turn: Dictionary) -> bool:
	if _contains_avatar_id(turn):
		return true
	if _avatar_name.is_empty():
		return false
	var text := "%s\n%s" % [
		String(turn.get("say", "")),
		String(turn.get("narration", "")),
	]
	return text.contains(_avatar_name)


func _contains_avatar_id(value: Variant) -> bool:
	match typeof(value):
		TYPE_DICTIONARY:
			for nested: Variant in (value as Dictionary).values():
				if _contains_avatar_id(nested):
					return true
		TYPE_ARRAY:
			for nested: Variant in value as Array:
				if _contains_avatar_id(nested):
					return true
		TYPE_STRING:
			return String(value) == _avatar_person_id
	return false


func _validate_items(value: Array) -> Dictionary:
	if value.size() > MAX_ITEMS:
		return _failure("居民化身证据队列超过容量")
	var ids := {}
	var refs := {}
	var normalized: Array[Dictionary] = []
	for index in value.size():
		if typeof(value[index]) != TYPE_DICTIONARY:
			return _failure("居民化身证据第 %d 项必须是对象" % index)
		var item := value[index] as Dictionary
		if not _has_exact_fields(
			item,
			[
				"evidence_id",
				"source_ref",
				"world_time",
				"source_type",
				"source_person_id",
				"direct_avatar",
				"payload",
			],
		):
			return _failure("居民化身证据第 %d 项字段损坏" % index)
		var evidence_id := String(item.get("evidence_id", "")).strip_edges()
		var source_ref := String(item.get("source_ref", "")).strip_edges()
		var source_person_id := String(
			item.get("source_person_id", ""),
		).strip_edges()
		if (
			evidence_id.is_empty()
			or source_ref.is_empty()
			or source_person_id.is_empty()
			or ids.has(evidence_id)
			or refs.has(source_ref)
			or not SOURCE_TYPES.has(String(item.get("source_type", "")))
			or typeof(item.get("direct_avatar")) != TYPE_BOOL
			or typeof(item.get("payload")) != TYPE_DICTIONARY
			or not _valid_time(item.get("world_time"))
		):
			return _failure("居民化身证据第 %d 项内容损坏" % index)
		ids[evidence_id] = true
		refs[source_ref] = true
		normalized.append(item.duplicate(true))
	return {"ok": true, "items": normalized}


func _ensure_loaded() -> Dictionary:
	if _loaded:
		return {"ok": true}
	var recovery := _recover_backup()
	if not bool(recovery.get("ok", false)):
		return recovery
	if not FileAccess.file_exists(_path):
		if _file_expected:
			return _failure("居民化身证据文件缺失：%s" % _path)
		_items = []
		_known_source_hashes = {}
		_new_items_since_organization = 0
		_loaded = true
		return {"ok": true}
	var file := FileAccess.open(_path, FileAccess.READ)
	if file == null:
		return _failure("无法读取居民化身证据：%s" % _path)
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	file = null
	if parse_error != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return _failure("居民化身证据文件损坏：%s" % _path)
	var validation := validate_state(
		AgentJsonScript.normalize_numbers(parser.data),
	)
	if not bool(validation.get("ok", false)):
		return validation
	var state := validation["queue_state"] as Dictionary
	_items.assign(state["items"])
	_known_source_hashes = (
		state["known_source_hashes"] as Dictionary
	).duplicate(true)
	_new_items_since_organization = int(
		state["new_items_since_organization"],
	)
	_loaded = true
	_file_expected = true
	return {"ok": true}


func _replace_file(
	items: Array,
	_known_hashes: Dictionary,
	new_item_count: int,
) -> Dictionary:
	var state := {
		"queue_state_version": STATE_VERSION,
		"resident_id": _resident_id,
		"avatar_person_id": _avatar_person_id,
		"items": items.duplicate(true),
		"known_source_hashes": _hashes_for_items(items),
		"new_items_since_organization": new_item_count,
	}
	var directory_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(_path.get_base_dir()),
	)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return _failure(
			"无法创建居民化身证据目录：%s" % error_string(directory_error),
		)
	var temporary_path := "%s.tmp" % _path
	var backup_path := "%s.bak" % _path
	if _remove_file(temporary_path) != OK:
		return _test_retention_failure()
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return _failure("无法写入居民化身证据临时文件：%s" % temporary_path)
	file.store_string(JSON.stringify(state))
	file.flush()
	var write_error := file.get_error()
	file = null
	if write_error != OK:
		if _remove_file(temporary_path) != OK:
			return _test_retention_failure()
		return _failure("无法写入居民化身证据：%s" % error_string(write_error))
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
			return _failure("无法准备居民化身证据原子替换")
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
		return _failure("无法提交居民化身证据：%s" % error_string(replace_error))
	if _remove_file(backup_path) != OK:
		return _test_retention_failure()
	return {"ok": true}


func _hashes_for_items(items: Array) -> Dictionary:
	var hashes := {}
	for item_value: Variant in items:
		if typeof(item_value) != TYPE_DICTIONARY:
			continue
		var item := item_value as Dictionary
		var source_ref := String(item.get("source_ref", "")).strip_edges()
		if not source_ref.is_empty():
			hashes[source_ref] = AgentJsonScript.content_sha256(item)
	return hashes


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
			"无法恢复居民化身证据备份：%s" % error_string(restore_error),
		)
	return {"ok": true}


func _normalized_time(value: Dictionary) -> Dictionary:
	var day := int(value.get("day", 0))
	var clock := String(value.get("clock", "00:00")).strip_edges()
	var period := String(value.get("period", "未知")).strip_edges()
	return {
		"day": maxi(0, day),
		"clock": "00:00" if clock.is_empty() else clock,
		"period": "未知" if period.is_empty() else period,
	}


func _valid_time(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false
	var time := value as Dictionary
	return (
		_has_exact_fields(time, ["day", "clock", "period"])
		and typeof(time.get("day")) == TYPE_INT
		and int(time.get("day")) >= 0
		and typeof(time.get("clock")) == TYPE_STRING
		and not String(time.get("clock")).strip_edges().is_empty()
		and typeof(time.get("period")) == TYPE_STRING
		and not String(time.get("period")).strip_edges().is_empty()
	)


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
