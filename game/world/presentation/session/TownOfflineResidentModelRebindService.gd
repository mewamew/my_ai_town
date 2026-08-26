class_name TownOfflineResidentModelRebindService
extends RefCounted


const MANIFEST := preload(
	"res://world/presentation/session/TownSessionSaveManifest.gd"
)
const ASSIGNMENT_PROJECTION := preload(
	"res://world/presentation/session/TownResidentModelAssignmentProjection.gd"
)
const SAVE_METHODS: Array[String] = [
	"begin_slot_transaction",
	"end_slot_transaction",
	"list_published",
	"list_incomplete",
	"read_reference",
	"read_world_log_snapshot",
	"reserve_revision",
	"write_world_candidate",
	"publish_manifest",
	"discard_unpublished_revision",
]
const AGENT_METHODS: Array[String] = [
	"load_snapshot",
	"save_snapshot",
	"discard_snapshot",
]


var _store: TownSessionSaveStore
var _agent_store: AgentSaveStore
var _binding_validator: Object
var _target: Dictionary = {}


func configure(
	store: TownSessionSaveStore,
	agent_store: AgentSaveStore,
	binding_validator: Object,
) -> Dictionary:
	if _store != null or _agent_store != null or _binding_validator != null:
		return _failure("OFFLINE_RESIDENT_MODEL_REBIND_ALREADY_CONFIGURED", false)
	if store == null or agent_store == null or binding_validator == null:
		return _failure("OFFLINE_RESIDENT_MODEL_REBIND_DEPENDENCY_MISSING", false)
	for method in SAVE_METHODS:
		if not store.has_method(method):
			return _failure(
				"OFFLINE_RESIDENT_MODEL_REBIND_SAVE_STORE_INVALID",
				false,
			)
	for method in AGENT_METHODS:
		if not agent_store.has_method(method):
			return _failure(
				"OFFLINE_RESIDENT_MODEL_REBIND_AGENT_STORE_INVALID",
				false,
			)
	if not binding_validator.has_method("validate_resident_bindings"):
		return _failure(
			"OFFLINE_RESIDENT_MODEL_REBIND_BINDING_VALIDATOR_INVALID",
			false,
		)
	_store = store
	_agent_store = agent_store
	_binding_validator = binding_validator
	return _success()


func prepare(slot_value: Variant, base_catalog_value: Variant) -> Dictionary:
	_target.clear()
	if _store == null or _agent_store == null:
		return _failure("OFFLINE_RESIDENT_MODEL_REBIND_NOT_CONFIGURED", false)
	if not slot_value is Dictionary or not base_catalog_value is Dictionary:
		return _failure("OFFLINE_RESIDENT_MODEL_REBIND_TARGET_INVALID", false)
	var slot := slot_value as Dictionary
	var summary_value: Variant = slot.get("summary")
	var manifest_value: Variant = slot.get("manifest")
	var config_value: Variant = slot.get("sessionConfig")
	if (
		not summary_value is Dictionary
		or not manifest_value is Dictionary
		or not config_value is Dictionary
		or not slot.get("saveBlockers", []) is Array
		or not slot.get("restoreBlockers", []) is Array
	):
		return _failure("OFFLINE_RESIDENT_MODEL_REBIND_TARGET_UNAVAILABLE", false)
	var save_blockers := slot.get("saveBlockers", []) as Array
	var restore_blockers := slot.get("restoreBlockers", []) as Array
	if not save_blockers.is_empty() or not restore_blockers.is_empty():
		var reconciliation := slot.get("reconciliationPlan", {}) as Dictionary
		return _failure(
			"OFFLINE_RESIDENT_MODEL_REBIND_RECOVERY_REQUIRED"
			if bool(reconciliation.get("repairable", false))
			else "OFFLINE_RESIDENT_MODEL_REBIND_TARGET_UNAVAILABLE",
			false,
			[],
			{"reconciliationPlan": reconciliation.duplicate(true)},
		)
	var summary := summary_value as Dictionary
	var manifest := manifest_value as Dictionary
	var session_config := config_value as Dictionary
	if MANIFEST.validate(manifest).get("ok") != true:
		return _failure("OFFLINE_RESIDENT_MODEL_REBIND_TARGET_INVALID", false)
	var slot_id := String(slot.get("slotId", "")).strip_edges()
	var session_id := String(summary.get("sessionId", "")).strip_edges()
	var save_revision := int(summary.get("saveRevision", -1))
	if (
		slot_id.is_empty()
		or session_id.is_empty()
		or save_revision < 1
		or String(manifest.get("slot_id", "")) != slot_id
		or String(manifest.get("session_id", "")) != session_id
		or int(manifest.get("save_revision", -1)) != save_revision
	):
		return _failure("OFFLINE_RESIDENT_MODEL_REBIND_TARGET_INVALID", false)
	var assignment := _build_assignment_inputs(
		session_config,
		base_catalog_value as Dictionary,
	)
	if assignment.get("ok") != true:
		return assignment
	_target = {
		"slotId": slot_id,
		"sessionId": session_id,
		"saveRevision": save_revision,
		"latestEvidenceRevision": int(
			slot.get("latestEvidenceRevision", save_revision),
		),
		"manifest": manifest.duplicate(true),
		"sessionConfig": session_config.duplicate(true),
	}
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"target": _target.duplicate(true),
		"residentCatalog": (
			assignment.get("residentCatalog", {}) as Dictionary
		).duplicate(true),
		"draft": (
			assignment.get("draft", {}) as Dictionary
		).duplicate(true),
	}


func apply_bindings(bindings_value: Variant) -> Dictionary:
	if _target.is_empty():
		return _failure("OFFLINE_RESIDENT_MODEL_REBIND_TARGET_MISSING", false)
	var normalized := ASSIGNMENT_PROJECTION.normalize_bindings(
		bindings_value,
		(_target.get("manifest", {}) as Dictionary).get("resident_ids", []),
	)
	if normalized.get("ok") != true:
		return normalized
	var bindings := normalized.get("bindings", []) as Array[Dictionary]
	var provider_validation := _binding_validator.call(
		"validate_resident_bindings",
		bindings,
	) as Dictionary
	if provider_validation.get("ok") != true:
		return _failure(
			String(provider_validation.get(
				"errorCode",
				"SESSION_LLM_BINDINGS_INVALID",
			)),
			bool(provider_validation.get("retryable", false)),
			provider_validation.get("errors", []) as Array,
		)
	var current_bindings := (
		(_target.get("sessionConfig", {}) as Dictionary).get(
			"residentBindings",
			[],
		) as Array
	).duplicate(true)
	if bindings == current_bindings:
		return {
			"ok": true,
			"errorCode": "",
			"retryable": false,
			"changed": false,
			"context": _snake_context(_target),
		}
	var lease := _store.begin_slot_transaction(_target.get("slotId"))
	if lease.get("ok") != true:
		return _store_failure(lease)
	var lease_token := String(lease.get("leaseToken", ""))
	if lease_token.is_empty():
		return _failure("OFFLINE_RESIDENT_MODEL_REBIND_SAVE_STORE_INVALID", false)
	var result := _apply_locked(bindings)
	var released := _store.end_slot_transaction(lease_token)
	if released.get("ok") != true:
		return _failure(
			"OFFLINE_RESIDENT_MODEL_REBIND_LEASE_RELEASE_FAILED",
			false,
			[],
			{"operation": result.duplicate(true)},
		)
	if result.get("ok") == true:
		_target.clear()
	return result


func _apply_locked(bindings: Array[Dictionary]) -> Dictionary:
	var evidence := _current_evidence(String(_target.get("slotId", "")))
	if evidence.get("ok") != true:
		return evidence
	var source_manifest := _target.get("manifest", {}) as Dictionary
	var current_source := {}
	for value: Variant in evidence.get("manifests", []) as Array:
		if (
			value is Dictionary
			and int((value as Dictionary).get("save_revision", -1))
			== int(_target.get("saveRevision", -1))
			and String((value as Dictionary).get("session_id", ""))
			== String(_target.get("sessionId", ""))
		):
			current_source = (value as Dictionary).duplicate(true)
			break
	if (
		int(evidence.get("latestEvidenceRevision", -1))
		!= int(_target.get("latestEvidenceRevision", -1))
		or current_source != source_manifest
	):
		return _failure("OFFLINE_RESIDENT_MODEL_REBIND_TARGET_STALE", false)
	var source := _read_source_revision(source_manifest)
	if source.get("ok") != true:
		return source
	var source_config := source.get("sessionConfig", {}) as Dictionary
	if source_config != (_target.get("sessionConfig", {}) as Dictionary):
		return _failure("OFFLINE_RESIDENT_MODEL_REBIND_TARGET_STALE", false)
	var next_config := source_config.duplicate(true)
	next_config["residentBindings"] = bindings.duplicate(true)
	var reserved := _store.reserve_revision(
		_target.get("slotId"),
		_target.get("sessionId"),
	)
	if reserved.get("ok") != true:
		return _store_failure(reserved)
	var context := (
		reserved.get("context", {}) as Dictionary
	).duplicate(true)
	var stored := _store.write_world_candidate(
		context,
		(source.get("worldSnapshot", {}) as Dictionary).duplicate(true),
		next_config,
		(
			(source.get("worldLogSnapshot", {}) as Dictionary).duplicate(true)
			if bool(source.get("hasWorldLog", false))
			else null
		),
	)
	if stored.get("ok") != true:
		return _cleanup_failed_candidate(context, _store_failure(stored))
	var source_agent := source.get("agent", {}) as Dictionary
	var saved_agent := _agent_store.save_snapshot(
		context,
		(source_agent.get("resident_payloads", {}) as Dictionary).duplicate(true),
	) as Dictionary
	if saved_agent.get("ok") != true:
		return _cleanup_failed_candidate(
			context,
			_failure(
				"OFFLINE_RESIDENT_MODEL_REBIND_AGENT_WRITE_FAILED",
				true,
				saved_agent.get("errors", []) as Array,
			),
		)
	var manifest := _build_manifest(context, source_manifest, stored)
	if manifest.is_empty():
		return _cleanup_failed_candidate(
			context,
			_failure("OFFLINE_RESIDENT_MODEL_REBIND_MANIFEST_INVALID", false),
		)
	var published := _store.publish_manifest(manifest)
	if published.get("ok") != true:
		return _cleanup_failed_candidate(context, _store_failure(published))
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"changed": true,
		"context": context,
		"manifest": manifest.duplicate(true),
		"summary": MANIFEST.summary(manifest),
	}


func _read_source_revision(manifest: Dictionary) -> Dictionary:
	var components := manifest.get("components", {}) as Dictionary
	var world := components.get("world", {}) as Dictionary
	var world_loaded := _store.read_reference(
		world.get("snapshot_ref"),
		world.get("snapshot_sha256"),
	)
	var config_loaded := _store.read_reference(
		manifest.get("session_config_ref"),
		manifest.get("session_config_sha256"),
	)
	if world_loaded.get("ok") != true or config_loaded.get("ok") != true:
		return _failure("OFFLINE_RESIDENT_MODEL_REBIND_SOURCE_READ_FAILED", false)
	if (
		not world_loaded.get("value") is Dictionary
		or not config_loaded.get("value") is Dictionary
	):
		return _failure("OFFLINE_RESIDENT_MODEL_REBIND_SOURCE_INVALID", false)
	var context := {
		"slot_id": manifest.get("slot_id"),
		"session_id": manifest.get("session_id"),
		"save_revision": manifest.get("save_revision"),
	}
	var agent := _agent_store.load_snapshot(context) as Dictionary
	if agent.get("ok") != true:
		return _failure(
			"OFFLINE_RESIDENT_MODEL_REBIND_SOURCE_AGENT_INVALID",
			false,
			agent.get("errors", []) as Array,
		)
	var has_world_log := int(manifest.get("schema_version", 0)) >= 3
	var world_log_snapshot: Dictionary = {}
	if has_world_log:
		var world_log := components.get("world_log", {}) as Dictionary
		var log_loaded := _store.read_world_log_snapshot(
			world_log.get("snapshot_ref"),
			world_log.get("snapshot_sha256"),
		)
		if log_loaded.get("ok") != true or not log_loaded.get("value") is Dictionary:
			return _failure("OFFLINE_RESIDENT_MODEL_REBIND_SOURCE_LOG_INVALID", false)
		world_log_snapshot = (
			log_loaded.get("value", {}) as Dictionary
		).duplicate(true)
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"worldSnapshot": (
			world_loaded.get("value", {}) as Dictionary
		).duplicate(true),
		"sessionConfig": (
			config_loaded.get("value", {}) as Dictionary
		).duplicate(true),
		"worldLogSnapshot": world_log_snapshot,
		"hasWorldLog": has_world_log,
		"agent": agent.duplicate(true),
	}


func _build_manifest(
	context: Dictionary,
	source_manifest: Dictionary,
	stored: Dictionary,
) -> Dictionary:
	var components := source_manifest.get("components", {}) as Dictionary
	var source_world := components.get("world", {}) as Dictionary
	var world_component := {
		"snapshotRef": String(stored.get("snapshotRef", "")),
		"worldRevision": int(source_world.get("world_revision", 0)),
		"schema": String(source_world.get("schema", "")),
		"schemaVersion": int(source_world.get("schema_version", 0)),
		"worldDataVersion": int(source_world.get("world_data_version", 0)),
	}
	if source_world.has("day"):
		world_component["day"] = int(source_world.get("day", 0))
	var world_log_component: Dictionary = {}
	if int(source_manifest.get("schema_version", 0)) >= 3:
		var source_log := components.get("world_log", {}) as Dictionary
		world_log_component = {
			"snapshotRef": String(stored.get("worldLogSnapshotRef", "")),
			"snapshotSha256": String(
				stored.get("worldLogSnapshotSha256", ""),
			),
			"schema": String(source_log.get("schema", "")),
			"schemaVersion": int(source_log.get("schema_version", 0)),
			"timelineId": String(source_log.get("timeline_id", "")),
			"maxSequence": int(source_log.get("max_sequence", 0)),
			"worldRevision": int(source_log.get("world_revision", 0)),
		}
	return MANIFEST.build(
		context,
		Time.get_datetime_string_from_system(false, false),
		String(stored.get("sessionConfigRef", "")),
		String(stored.get("sessionConfigSha256", "")),
		(source_manifest.get("resident_ids", []) as Array).duplicate(),
		world_component,
		String(stored.get("snapshotSha256", "")),
		MANIFEST.resident_messages(source_manifest),
		world_log_component,
	) as Dictionary


func _current_evidence(slot_id: String) -> Dictionary:
	var listed := _store.list_published(slot_id)
	var incomplete := _store.list_incomplete(slot_id)
	if listed.get("ok") != true:
		return _store_failure(listed)
	if incomplete.get("ok") != true:
		return _store_failure(incomplete)
	var latest := -1
	for value: Variant in listed.get("manifests", []) as Array:
		if value is Dictionary:
			latest = maxi(latest, int((value as Dictionary).get("save_revision", -1)))
	for value: Variant in listed.get("invalid", []) as Array:
		if value is String:
			latest = maxi(latest, (value as String).get_basename().to_int())
	for value: Variant in incomplete.get("records", []) as Array:
		if value is Dictionary:
			var context := (value as Dictionary).get("context", {}) as Dictionary
			latest = maxi(latest, int(context.get("save_revision", -1)))
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"latestEvidenceRevision": latest,
		"manifests": (
			listed.get("manifests", []) as Array
		).duplicate(true),
	}


func _build_assignment_inputs(
	session_config: Dictionary,
	base_catalog: Dictionary,
) -> Dictionary:
	var projected := ASSIGNMENT_PROJECTION.build(session_config, base_catalog)
	if projected.get("ok") == true:
		return projected
	var error_code := String(projected.get("errorCode", ""))
	return _failure(
		"OFFLINE_RESIDENT_MODEL_REBIND_SESSION_CONFIG_INVALID"
		if error_code == "SESSION_RESIDENT_ASSIGNMENT_PROJECTION_INVALID"
		else error_code,
		false,
		projected.get("errors", []) as Array,
	)


func _cleanup_failed_candidate(
	context: Dictionary,
	operation: Dictionary,
) -> Dictionary:
	# Agent 快照会拒绝覆盖同一修订。因此必须先删 Agent：
	# 若这一步失败，保留 World 候选与 allocation，下次将分配更大修订号。
	var agent_cleanup := _agent_store.discard_snapshot(context) as Dictionary
	if agent_cleanup.get("ok") != true:
		return _failure(
			"OFFLINE_RESIDENT_MODEL_REBIND_CLEANUP_FAILED",
			true,
			agent_cleanup.get("errors", []) as Array,
			{
				"context": context.duplicate(true),
				"operation": operation.duplicate(true),
				"agentCleanup": agent_cleanup.duplicate(true),
				"worldEvidencePreserved": true,
			},
		)
	var world_cleanup := _store.discard_unpublished_revision(context)
	if world_cleanup.get("ok") != true:
		return _failure(
			"OFFLINE_RESIDENT_MODEL_REBIND_CLEANUP_FAILED",
			true,
			[],
			{
				"context": context.duplicate(true),
				"operation": operation.duplicate(true),
				"agentCleanup": agent_cleanup.duplicate(true),
				"worldCleanup": world_cleanup.duplicate(true),
				"worldEvidencePreserved": true,
			},
		)
	return operation


func _snake_context(target: Dictionary) -> Dictionary:
	return {
		"slot_id": String(target.get("slotId", "")),
		"session_id": String(target.get("sessionId", "")),
		"save_revision": int(target.get("saveRevision", 0)),
	}


func _store_failure(result: Dictionary) -> Dictionary:
	return _failure(
		String(result.get(
			"errorCode",
			"OFFLINE_RESIDENT_MODEL_REBIND_STORE_FAILED",
		)),
		bool(result.get("retryable", true)),
		result.get("errors", []) as Array,
	)


func _success() -> Dictionary:
	return {"ok": true, "errorCode": "", "retryable": false}


func _failure(
	error_code: String,
	retryable: bool,
	errors: Array = [],
	meta: Dictionary = {},
) -> Dictionary:
	return {
		"ok": false,
		"errorCode": error_code,
		"retryable": retryable,
		"errors": errors.duplicate(true),
		"meta": meta.duplicate(true),
	}
