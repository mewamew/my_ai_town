class_name TownWorldRestoreCandidateRuntime
extends RefCounted


var _sequence := 0
var _candidates: Dictionary = {}


func prepare(
	base_generation: int,
	base_world_revision: int,
	require_world_ready: bool,
	world_data: Dictionary,
	opening_config: Dictionary,
	prepared_identities: Dictionary,
	prepared_state: Dictionary,
	prepared_world_log: RefCounted,
	snapshot_schema_version: int,
	migration_receipt: Dictionary,
) -> Dictionary:
	_sequence += 1
	var token := "world-restore-g%d-c%d" % [base_generation, _sequence]
	var candidate := {
		"token": token,
		"state": "prepared",
		"baseGeneration": base_generation,
		"baseWorldRevision": base_world_revision,
		"requireWorldReady": require_world_ready,
		"worldData": world_data.duplicate(true),
		"openingConfig": opening_config.duplicate(true),
		"preparedIdentities": prepared_identities,
		"preparedState": prepared_state,
		"preparedWorldLog": prepared_world_log,
		"snapshotSchemaVersion": snapshot_schema_version,
		"migrationReceipt": migration_receipt.duplicate(true),
		"savedWorldRevision": int(
			(prepared_state.get("sequences", {}) as Dictionary).get(
				"worldRevision",
				0,
			),
		),
	}
	_candidates[token] = candidate
	return {"ok": true, "candidate": projection(candidate)}


func validate(
	token: String,
	runtime_generation: int,
	world_revision: int,
) -> Dictionary:
	var normalized := token.strip_edges()
	if not _candidates.has(normalized):
		return _failure(
			"WORLD_RESTORE_CANDIDATE_NOT_FOUND",
			["World 恢复候选不存在：%s" % normalized],
		)
	var candidate := _candidates[normalized] as Dictionary
	var state := String(candidate.get("state", ""))
	if state != "prepared":
		return _failure(
			"WORLD_RESTORE_CANDIDATE_STATE_INVALID",
			["World 恢复候选当前状态不能校验：%s" % state],
			{"candidate": projection(candidate)},
		)
	if (
		int(candidate.get("baseGeneration", -1)) != runtime_generation
		or int(candidate.get("baseWorldRevision", -1)) != world_revision
	):
		return _failure(
			"WORLD_RESTORE_CANDIDATE_STALE",
			["World 在恢复准备后已经发生变化，必须重新 prepare"],
			{"candidate": projection(candidate)},
			true,
		)
	return {"ok": true, "candidate": projection(candidate)}


func begin_commit(
	token: String,
	runtime_generation: int,
	world_revision: int,
) -> Dictionary:
	var normalized := token.strip_edges()
	if not _candidates.has(normalized):
		return _failure(
			"WORLD_RESTORE_CANDIDATE_NOT_FOUND",
			["World 恢复候选不存在：%s" % normalized],
		)
	var candidate := _candidates[normalized] as Dictionary
	if String(candidate.get("state", "")) == "committed":
		return {
			"ok": true,
			"alreadyCommitted": true,
			"candidate": projection(candidate),
			"summary": (
				candidate.get("commitSummary", {}) as Dictionary
			).duplicate(true),
			"commitReceipt": (
				candidate.get("commitReceipt", {}) as Dictionary
			).duplicate(true),
		}
	var validation := validate(normalized, runtime_generation, world_revision)
	if validation.get("ok") != true:
		return validation
	return {
		"ok": true,
		"alreadyCommitted": false,
		"candidateState": candidate,
	}


func complete_commit(
	token: String,
	commit_generation: int,
	commit_world_revision: int,
	summary: Dictionary,
	receipt: Dictionary,
) -> Dictionary:
	var normalized := token.strip_edges()
	if not _candidates.has(normalized):
		return _failure(
			"WORLD_RESTORE_CANDIDATE_NOT_FOUND",
			["World 恢复候选不存在：%s" % normalized],
		)
	var candidate := _candidates[normalized] as Dictionary
	candidate["state"] = "committed"
	candidate["commitGeneration"] = commit_generation
	candidate["commitWorldRevision"] = commit_world_revision
	candidate["commitSummary"] = summary.duplicate(true)
	candidate["commitReceipt"] = receipt.duplicate(true)
	_release_payload(candidate)
	_candidates[normalized] = candidate
	return {
		"ok": true,
		"candidate": projection(candidate),
		"summary": summary,
		"commitReceipt": receipt,
	}


func abort(token: String) -> Dictionary:
	var normalized := token.strip_edges()
	if not _candidates.has(normalized):
		return _failure(
			"WORLD_RESTORE_CANDIDATE_NOT_FOUND",
			["World 恢复候选不存在：%s" % normalized],
		)
	var candidate := _candidates[normalized] as Dictionary
	var state := String(candidate.get("state", ""))
	if state == "aborted":
		return {"ok": true, "candidate": projection(candidate)}
	if state != "prepared":
		return _failure(
			"WORLD_RESTORE_CANDIDATE_STATE_INVALID",
			["World 恢复候选只能在 prepared 状态中止"],
			{"candidate": projection(candidate)},
		)
	candidate["state"] = "aborted"
	_release_payload(candidate)
	_candidates[normalized] = candidate
	return {"ok": true, "candidate": projection(candidate)}


func cleanup(token: String) -> Dictionary:
	var normalized := token.strip_edges()
	if not _candidates.has(normalized):
		return _failure(
			"WORLD_RESTORE_CANDIDATE_NOT_FOUND",
			["World 恢复候选不存在：%s" % normalized],
		)
	var candidate := _candidates[normalized] as Dictionary
	if String(candidate.get("state", "")) not in ["committed", "aborted"]:
		return _failure(
			"WORLD_RESTORE_CANDIDATE_STATE_INVALID",
			["World 恢复候选必须先提交或中止才能清理"],
			{"candidate": projection(candidate)},
		)
	var candidate_projection := projection(candidate)
	_candidates.erase(normalized)
	return {"ok": true, "candidate": candidate_projection}


static func projection(candidate: Dictionary) -> Dictionary:
	var prepared_identities := candidate.get("preparedIdentities", {}) as Dictionary
	var result := {
		"token": String(candidate.get("token", "")),
		"state": String(candidate.get("state", "")),
		"baseGeneration": int(candidate.get("baseGeneration", -1)),
		"baseWorldRevision": int(candidate.get("baseWorldRevision", 0)),
		"requireWorldReady": bool(candidate.get("requireWorldReady", true)),
		"snapshotSchemaVersion": int(candidate.get("snapshotSchemaVersion", 0)),
		"savedWorldRevision": int(candidate.get("savedWorldRevision", 0)),
		"migrationReceipt": (
			candidate.get("migrationReceipt", {}) as Dictionary
		).duplicate(true),
		"identitySnapshot": {
			"status": String(prepared_identities.get("status", "")),
			"residents": (
				prepared_identities.get("residents", []) as Array
			).duplicate(true),
		},
	}
	if candidate.has("commitGeneration"):
		result["commitGeneration"] = int(candidate.get("commitGeneration", -1))
		result["commitWorldRevision"] = int(candidate.get("commitWorldRevision", 0))
	return result


static func _release_payload(candidate: Dictionary) -> void:
	# 提交或中止后只保留投影和幂等提交所需的轻量字段，释放约 3MB 重载荷。
	candidate.erase("worldData")
	candidate.erase("openingConfig")
	candidate.erase("preparedState")
	candidate.erase("preparedWorldLog")


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
