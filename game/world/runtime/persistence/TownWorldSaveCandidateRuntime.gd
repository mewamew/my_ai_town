class_name TownWorldSaveCandidateRuntime
extends RefCounted


const SAVE_CODEC := preload(
	"res://world/runtime/persistence/TownWorldSaveCodec.gd"
)

var _sequence := 0
var _candidates: Dictionary = {}


func prepare(
	source_generation: int,
	world_revision: int,
	snapshot: Dictionary,
	world_log_snapshot: Dictionary,
	identity_snapshot: Dictionary,
	resident_ids: Array,
) -> Dictionary:
	_sequence += 1
	var token := "world-save-g%d-c%d" % [source_generation, _sequence]
	var candidate := {
		"token": token,
		"state": "prepared",
		"sourceGeneration": source_generation,
		"worldRevision": world_revision,
		"snapshot": snapshot,
		"worldLogSnapshot": world_log_snapshot,
		"snapshotRef": "",
		"worldLogSnapshotRef": "",
		"identitySnapshot": identity_snapshot.duplicate(true),
		"residentIds": resident_ids.duplicate(),
	}
	_candidates[token] = candidate
	return {
		"ok": true,
		"candidate": projection(candidate),
		"snapshot": snapshot.duplicate(true),
		"worldLogSnapshot": world_log_snapshot.duplicate(true),
	}


func validate(
	token: String,
	world_running: bool,
	runtime_generation: int,
	world_revision: int,
) -> Dictionary:
	var normalized := token.strip_edges()
	if not _candidates.has(normalized):
		return _failure(
			"WORLD_SAVE_CANDIDATE_NOT_FOUND",
			["World 保存候选不存在：%s" % normalized],
		)
	var candidate := _candidates[normalized] as Dictionary
	var state := String(candidate.get("state", ""))
	if state not in ["prepared", "committed"]:
		return _failure(
			"WORLD_SAVE_CANDIDATE_STATE_INVALID",
			["World 保存候选当前状态不能校验：%s" % state],
			{"candidate": projection(candidate)},
		)
	if state == "prepared" and (
		not world_running
		or int(candidate.get("sourceGeneration", -1)) != runtime_generation
		or int(candidate.get("worldRevision", -1)) != world_revision
	):
		return _failure(
			"WORLD_SAVE_CANDIDATE_STALE",
			["World 保存候选来自已经变化的运行世代或 revision"],
			{"candidate": projection(candidate)},
			true,
		)
	var snapshot := candidate.get("snapshot", {}) as Dictionary
	var world_log_snapshot := candidate.get("worldLogSnapshot", {}) as Dictionary
	if snapshot.is_empty():
		return _failure(
			"WORLD_SAVE_CANDIDATE_INVALID",
			["World 保存候选不再是合法 JSON 快照"],
			{"candidate": projection(candidate)},
		)
	if world_log_snapshot.is_empty():
		return _failure(
			"WORLD_LOG_SNAPSHOT_INVALID",
			["世界日志保存候选不再是合法 JSON 快照"],
			{"candidate": projection(candidate)},
		)
	return {
		"ok": true,
		"candidate": projection(candidate),
		"snapshot": snapshot.duplicate(true),
	}


func commit(
	token: String,
	snapshot_ref: String,
	world_log_snapshot_ref: String,
	world_running: bool,
	runtime_generation: int,
	world_revision: int,
) -> Dictionary:
	var normalized_token := token.strip_edges()
	var normalized_ref := snapshot_ref.strip_edges()
	var normalized_log_ref := world_log_snapshot_ref.strip_edges()
	if normalized_ref.is_empty():
		return _failure(
			"WORLD_SAVE_SNAPSHOT_REF_INVALID",
			["World snapshotRef 不能为空"],
		)
	if not _candidates.has(normalized_token):
		return _failure(
			"WORLD_SAVE_CANDIDATE_NOT_FOUND",
			["World 保存候选不存在：%s" % normalized_token],
		)
	var candidate := _candidates[normalized_token] as Dictionary
	var state := String(candidate.get("state", ""))
	if state == "committed":
		if String(candidate.get("snapshotRef", "")) != normalized_ref:
			return _failure(
				"WORLD_SAVE_CANDIDATE_STATE_INVALID",
				["已提交的 World 保存候选不能更换 snapshotRef"],
				{"candidate": projection(candidate)},
			)
		if String(candidate.get("worldLogSnapshotRef", "")) != normalized_log_ref:
			return _failure(
				"WORLD_SAVE_CANDIDATE_STATE_INVALID",
				["已提交的 World 保存候选不能更换世界日志 snapshotRef"],
				{"candidate": projection(candidate)},
			)
		return _committed_result(candidate)
	if state != "prepared":
		return _failure(
			"WORLD_SAVE_CANDIDATE_STATE_INVALID",
			["World 保存候选只能从 prepared 提交"],
			{"candidate": projection(candidate)},
		)
	var validation := validate(
		normalized_token,
		world_running,
		runtime_generation,
		world_revision,
	)
	if validation.get("ok") != true:
		return validation
	candidate["state"] = "committed"
	candidate["snapshotRef"] = normalized_ref
	candidate["worldLogSnapshotRef"] = normalized_log_ref
	_candidates[normalized_token] = candidate
	return _committed_result(candidate)


func abort(token: String) -> Dictionary:
	var normalized := token.strip_edges()
	if not _candidates.has(normalized):
		return _failure(
			"WORLD_SAVE_CANDIDATE_NOT_FOUND",
			["World 保存候选不存在：%s" % normalized],
		)
	var candidate := _candidates[normalized] as Dictionary
	var state := String(candidate.get("state", ""))
	if state == "aborted":
		return {
			"ok": true,
			"candidate": projection(candidate),
			"cleanupSnapshotRef": String(candidate.get("snapshotRef", "")),
		}
	if state not in ["prepared", "committed"]:
		return _failure(
			"WORLD_SAVE_CANDIDATE_STATE_INVALID",
			["World 保存候选当前状态不能中止：%s" % state],
			{"candidate": projection(candidate)},
		)
	candidate["state"] = "aborted"
	_candidates[normalized] = candidate
	return {
		"ok": true,
		"candidate": projection(candidate),
		"cleanupSnapshotRef": String(candidate.get("snapshotRef", "")),
	}


func cleanup(token: String) -> Dictionary:
	var normalized := token.strip_edges()
	if not _candidates.has(normalized):
		return _failure(
			"WORLD_SAVE_CANDIDATE_NOT_FOUND",
			["World 保存候选不存在：%s" % normalized],
		)
	var candidate := _candidates[normalized] as Dictionary
	if String(candidate.get("state", "")) not in ["committed", "aborted"]:
		return _failure(
			"WORLD_SAVE_CANDIDATE_STATE_INVALID",
			["World 保存候选必须先提交或中止才能清理"],
			{"candidate": projection(candidate)},
		)
	var candidate_projection := projection(candidate)
	_candidates.erase(normalized)
	return {
		"ok": true,
		"candidate": candidate_projection,
		"cleanupSnapshotRef": String(candidate.get("snapshotRef", "")),
	}


static func resident_ids_from_identity_snapshot(
	identity_snapshot: Variant,
	expected_identity_status: String,
	authoritative_resident_ids: Array[String],
	authoritative_names: Dictionary,
) -> Dictionary:
	var errors: Array[String] = []
	if identity_snapshot is not Dictionary:
		return {"ok": false, "errors": ["identitySnapshot 必须是对象"]}
	var identity := identity_snapshot as Dictionary
	if not SAVE_CODEC.has_exact_string_keys(identity, ["status", "residents"]):
		errors.append("identitySnapshot 字段必须严格为 status、residents")
	var status_value: Variant = identity.get("status")
	if not status_value is String or status_value != expected_identity_status:
		errors.append("identitySnapshot.status 必须保持当前居民身份状态")
	var residents_value: Variant = identity.get("residents")
	if residents_value is not Array:
		errors.append("identitySnapshot.residents 必须是数组")
		return {"ok": false, "errors": errors}
	var resident_ids: Array[String] = []
	var resident_names := {}
	for index in (residents_value as Array).size():
		var resident_value: Variant = (residents_value as Array)[index]
		if resident_value is not Dictionary:
			errors.append("identitySnapshot.residents[%d] 必须是对象" % index)
			continue
		var resident := resident_value as Dictionary
		if not SAVE_CODEC.has_exact_string_keys(resident, ["residentId", "residentName"]):
			errors.append(
				"identitySnapshot.residents[%d] 字段必须严格为 residentId、residentName"
				% index,
			)
			continue
		var resident_id_value: Variant = resident.get("residentId")
		var resident_name_value: Variant = resident.get("residentName")
		if (
			resident_id_value is not String
			or (resident_id_value as String).is_empty()
			or resident_id_value != (resident_id_value as String).strip_edges()
			or not _resident_id_is_safe(resident_id_value as String)
		):
			errors.append("identitySnapshot.residents[%d].residentId 无效" % index)
			continue
		var resident_id := resident_id_value as String
		if (
			resident_name_value is not String
			or (resident_name_value as String).is_empty()
			or resident_name_value != (resident_name_value as String).strip_edges()
		):
			errors.append("identitySnapshot.residents[%d].residentName 无效" % index)
			continue
		if resident_names.has(resident_id):
			errors.append("identitySnapshot residentId 重复：%s" % resident_id)
			continue
		resident_ids.append(resident_id)
		resident_names[resident_id] = resident_name_value as String
	resident_ids.sort()
	var authoritative_ids := authoritative_resident_ids.duplicate()
	authoritative_ids.sort()
	if resident_ids != authoritative_ids:
		errors.append("identitySnapshot 居民集合与当前 World 权威居民集合不一致")
	else:
		for resident_id in authoritative_ids:
			if String(resident_names.get(resident_id, "")) != String(
				authoritative_names.get(resident_id, ""),
			):
				errors.append(
					"identitySnapshot 居民显示名称与当前 World 权威身份不一致：%s"
					% resident_id,
				)
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	return {"ok": true, "errors": [], "residentIds": resident_ids}


static func projection(candidate: Dictionary) -> Dictionary:
	var snapshot := candidate.get("snapshot", {}) as Dictionary
	return {
		"token": String(candidate.get("token", "")),
		"state": String(candidate.get("state", "")),
		"sourceGeneration": int(candidate.get("sourceGeneration", -1)),
		"worldRevision": int(candidate.get("worldRevision", 0)),
		"schema": String(snapshot.get("schema", "")),
		"schemaVersion": int(snapshot.get("schemaVersion", 0)),
		"worldId": String(snapshot.get("worldId", "")),
		"worldDataSchemaVersion": int(snapshot.get("worldDataSchemaVersion", 0)),
		"worldDataVersion": int(snapshot.get("worldDataVersion", 0)),
		"identitySnapshot": (
			candidate.get("identitySnapshot", {}) as Dictionary
		).duplicate(true),
		"residentIds": (candidate.get("residentIds", []) as Array).duplicate(),
		"snapshotRef": String(candidate.get("snapshotRef", "")),
		"worldLogSnapshotRef": String(candidate.get("worldLogSnapshotRef", "")),
	}


static func _resident_id_is_safe(resident_id: String) -> bool:
	if resident_id.is_empty() or resident_id.length() > 128:
		return false
	for character in resident_id:
		var code := character.unicode_at(0)
		var is_ascii_letter := code >= 97 and code <= 122
		var is_digit := code >= 48 and code <= 57
		if not is_ascii_letter and not is_digit and character not in ["_", "-"]:
			return false
	return true


static func _world_component(candidate: Dictionary) -> Dictionary:
	var snapshot := candidate.get("snapshot", {}) as Dictionary
	return {
		"worldRevision": int(candidate.get("worldRevision", 0)),
		"snapshotRef": String(candidate.get("snapshotRef", "")),
		"schema": String(snapshot.get("schema", "")),
		"schemaVersion": int(snapshot.get("schemaVersion", 0)),
		"worldDataVersion": int(snapshot.get("worldDataVersion", 0)),
		"day": int((snapshot.get("savedAt", {}) as Dictionary).get("day", 0)),
	}


static func _world_log_component(candidate: Dictionary) -> Dictionary:
	var snapshot := candidate.get("worldLogSnapshot", {}) as Dictionary
	return {
		"snapshotRef": String(candidate.get("worldLogSnapshotRef", "")),
		"schema": String(snapshot.get("schema", "")),
		"schemaVersion": int(snapshot.get("schemaVersion", 0)),
		"timelineId": String(snapshot.get("timelineId", "")),
		"maxSequence": int(snapshot.get("maxSequence", 0)),
		"worldRevision": int(snapshot.get("worldRevision", 0)),
	}


static func _committed_result(candidate: Dictionary) -> Dictionary:
	return {
		"ok": true,
		"candidate": projection(candidate),
		"worldComponent": _world_component(candidate),
		"worldLogComponent": _world_log_component(candidate),
	}


static func _failure(
	error_code: String,
	errors: Array,
	extra: Dictionary = {},
	retryable := false,
) -> Dictionary:
	var result := {
		"ok": false,
		"errorCode": error_code,
		"errors": errors.duplicate(true),
		"retryable": retryable,
	}
	result.merge(extra, true)
	return result
