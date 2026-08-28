class_name TownSaveReconciliationService
extends RefCounted


const PLAN_VERSION := 1
const RECONCILE_ACTION := "reconcile_interrupted_transactions"
const EXPORT_ACTION := "export_save_diagnostic"
const DEFAULT_DIAGNOSTIC_ROOT := "user://save_diagnostics"
const TEST_DIAGNOSTIC_ROOT := "user://tests/save_diagnostics"
const MANIFEST := preload(
	"res://world/presentation/session/TownSessionSaveManifest.gd"
)
const WORLD_SAVE_CODEC := preload(
	"res://world/runtime/persistence/TownWorldSaveCodec.gd"
)
const WORLD_LOG_STORE := preload(
	"res://world/runtime/log/TownWorldLogStore.gd"
)
const STORE_METHODS: Array[String] = [
	"begin_slot_transaction",
	"end_slot_transaction",
	"list_incomplete",
	"list_published",
	"read_latest_intent",
	"read_reference",
	"read_world_log_snapshot",
	"write_intent_stage",
]

var _store: Object
var _agent_store: Object
var _diagnostic_root := DEFAULT_DIAGNOSTIC_ROOT


func configure(
	store: Object,
	agent_store: Object,
	diagnostic_root := DEFAULT_DIAGNOSTIC_ROOT,
) -> Dictionary:
	if _store != null:
		return _failure("SESSION_SAVE_RECONCILIATION_ALREADY_CONFIGURED")
	for method_name: String in STORE_METHODS:
		if store == null or not store.has_method(method_name):
			return _failure("SESSION_SAVE_RECONCILIATION_CONTRACT_INVALID")
	if agent_store == null or not agent_store.has_method("load_snapshot"):
		return _failure("SESSION_SAVE_RECONCILIATION_CONTRACT_INVALID")
	var normalized_root := String(diagnostic_root).trim_suffix("/")
	if (
		normalized_root != DEFAULT_DIAGNOSTIC_ROOT
		and not normalized_root.begins_with("%s/" % TEST_DIAGNOSTIC_ROOT)
	):
		return _failure("SESSION_SAVE_DIAGNOSTIC_PATH_INVALID")
	_store = store
	_agent_store = agent_store
	_diagnostic_root = normalized_root
	return _success()


func inspect(slot_id: String) -> Dictionary:
	if _store == null:
		return _failure("SESSION_SAVE_RECONCILIATION_CONTRACT_INVALID")
	var listed := _store.call("list_incomplete", slot_id) as Dictionary
	if listed.get("ok") != true:
		return listed
	var published := _store.call("list_published", slot_id) as Dictionary
	if published.get("ok") != true:
		return published
	var records_value: Variant = listed.get("records")
	var manifests_value: Variant = published.get("manifests")
	var read_only_value: Variant = published.get("readOnly", [])
	if (
		not records_value is Array
		or not manifests_value is Array
		or not read_only_value is Array
	):
		return _failure("SESSION_SAVE_RECONCILIATION_EVIDENCE_INVALID")
	var published_records := (manifests_value as Array).duplicate(true)
	for read_only_record: Variant in read_only_value as Array:
		if read_only_record is Dictionary:
			published_records.append(
				(read_only_record as Dictionary).get("manifest", {}),
			)
	var items: Array[Dictionary] = []
	for record_value: Variant in records_value as Array:
		if not record_value is Dictionary:
			return _failure("SESSION_SAVE_RECONCILIATION_EVIDENCE_INVALID")
		var record := record_value as Dictionary
		var context_value: Variant = record.get("context")
		if not context_value is Dictionary:
			return _failure("SESSION_SAVE_RECONCILIATION_EVIDENCE_INVALID")
		var context := context_value as Dictionary
		var kind := String(record.get("kind", ""))
		var state := String(record.get("state", ""))
		var payload := record.get("payload", {}) as Dictionary
		var classified := TownSaveJournalStates.classify_incomplete(
			kind,
			state,
			payload,
		)
		var classification := String(classified.get("classification", ""))
		var agent_snapshot_valid := false
		var published_pair_valid := false
		var agent_snapshot: Dictionary = {}
		if classification != "pre_agent_cleanup":
			agent_snapshot = _agent_store.call(
				"load_snapshot",
				context,
			) as Dictionary
			agent_snapshot_valid = bool(agent_snapshot.get("ok", false))
		if kind == "restore":
			published_pair_valid = _published_pair_is_complete(
				published_records,
				context,
				agent_snapshot,
			)
		var safe := classification == "pre_agent_cleanup"
		var resolution := "discard_pre_commit_candidate"
		if kind == "save" and classification != "pre_agent_cleanup":
			safe = agent_snapshot_valid
			resolution = "preserve_orphan_agent_snapshot"
		elif kind == "restore" and classification != "pre_agent_cleanup":
			safe = agent_snapshot_valid and published_pair_valid
			resolution = "discard_stale_runtime_restore"
		items.append({
			"context": context.duplicate(true),
			"kind": kind,
			"intentId": String(record.get("intent_id", "")),
			"state": state,
			"classification": classification,
			"safe": safe,
			"resolution": resolution,
			"agentSnapshotValid": agent_snapshot_valid,
			"publishedPairValid": published_pair_valid,
		})
	items.sort_custom(_sort_items)
	var diagnostic_id := _diagnostic_id(slot_id, items)
	var repairable := not items.is_empty()
	for item: Dictionary in items:
		if not bool(item.get("safe", false)):
			repairable = false
	var action := RECONCILE_ACTION if repairable else EXPORT_ACTION
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"version": PLAN_VERSION,
		"planId": diagnostic_id,
		"diagnosticId": diagnostic_id,
		"action": action,
		"slotId": slot_id,
		"repairable": repairable,
		"confirmationRequired": repairable,
		"items": items,
	}


func execute(plan: Dictionary, confirmation: Dictionary) -> Dictionary:
	if (
		int(plan.get("version", 0)) != PLAN_VERSION
		or String(plan.get("action", "")) != RECONCILE_ACTION
		or not bool(plan.get("repairable", false))
		or confirmation != {
			"confirmed": true,
			"planId": String(plan.get("planId", "")),
		}
	):
		return _failure("SESSION_SAVE_RECONCILIATION_PLAN_INVALID")
	var slot_id := String(plan.get("slotId", ""))
	var lease := _store.call("begin_slot_transaction", slot_id) as Dictionary
	if lease.get("ok") != true:
		return lease
	var lease_token := String(lease.get("leaseToken", ""))
	var fresh := inspect(slot_id)
	if fresh.get("ok") != true:
		return _release_and_return(lease_token, fresh)
	var planned_items := plan.get("items", []) as Array
	var fresh_items := fresh.get("items", []) as Array
	if planned_items.is_empty() or not _fresh_items_belong_to_plan(
		fresh_items,
		planned_items,
	):
		return _release_and_return(
			lease_token,
			_failure("SESSION_SAVE_RECONCILIATION_PLAN_STALE"),
		)
	var sealed := 0
	var already_sealed := 0
	for item_value: Variant in planned_items:
		if not item_value is Dictionary:
			return _release_and_return(
				lease_token,
				_failure("SESSION_SAVE_RECONCILIATION_PLAN_INVALID"),
			)
		var item := item_value as Dictionary
		var kind := String(item.get("kind", ""))
		var latest := _store.call(
			"read_latest_intent",
			item.get("context", {}) as Dictionary,
			kind,
			String(item.get("intentId", "")),
		) as Dictionary
		if latest.get("ok") != true:
			return _release_and_return(lease_token, latest)
		var latest_state := String(latest.get("state", ""))
		var terminal_state := (
			"save_reconciled" if kind == "save" else "restore_reconciled"
		)
		if latest_state == terminal_state:
			var terminal_payload := (
				(latest.get("record", {}) as Dictionary).get(
					"payload",
					{},
				) as Dictionary
			)
			if (
				String(terminal_payload.get("diagnosticId", ""))
				!= String(plan.get("diagnosticId", ""))
				or String(terminal_payload.get("resolution", ""))
				!= String(item.get("resolution", ""))
			):
				return _release_and_return(
					lease_token,
					_failure("SESSION_SAVE_RECONCILIATION_PLAN_STALE"),
				)
			already_sealed += 1
			continue
		if (
			latest_state != String(item.get("state", ""))
			or not _contains_matching_safe_item(fresh_items, item)
		):
			return _release_and_return(
				lease_token,
				_failure("SESSION_SAVE_RECONCILIATION_PLAN_STALE"),
			)
		var written := _store.call(
			"write_intent_stage",
			item.get("context", {}) as Dictionary,
			kind,
			String(item.get("intentId", "")),
			"save_reconciled" if kind == "save" else "restore_reconciled",
			{
				"diagnosticId": String(plan.get("diagnosticId", "")),
				"previousState": String(item.get("state", "")),
				"resolution": String(item.get("resolution", "")),
			},
		) as Dictionary
		if written.get("ok") != true:
			return _release_and_return(lease_token, written)
		sealed += 1
	return _release_and_return(lease_token, {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"diagnosticId": String(plan.get("diagnosticId", "")),
		"sealedIntentCount": sealed,
		"alreadySealedIntentCount": already_sealed,
		"changed": sealed > 0,
		"preservedEvidence": true,
	})


func export_diagnostic(plan: Dictionary) -> Dictionary:
	if (
		int(plan.get("version", 0)) != PLAN_VERSION
		or String(plan.get("action", "")) != EXPORT_ACTION
		or not _valid_diagnostic_id(String(plan.get("diagnosticId", "")))
	):
		return _failure("SESSION_SAVE_DIAGNOSTIC_PLAN_INVALID")
	var create_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(_diagnostic_root),
	)
	if create_error != OK:
		return _failure("SESSION_SAVE_DIAGNOSTIC_EXPORT_FAILED", true)
	var diagnostic_id := String(plan.get("diagnosticId", ""))
	var path := "%s/%s.json" % [_diagnostic_root, diagnostic_id]
	var payload := {
		"schema": "town-save-diagnostic",
		"schemaVersion": 1,
		"diagnosticId": diagnostic_id,
		"slotId": String(plan.get("slotId", "")),
		"classification": "manual_review_required",
		"sourceBasis": "git_release_history",
		"originalEvidencePreserved": true,
		"items": (plan.get("items", []) as Array).duplicate(true),
	}
	var serialized := JSON.stringify(payload, "\t", false) + "\n"
	if FileAccess.file_exists(path):
		var existing := FileAccess.get_file_as_string(path)
		if existing == serialized:
			return _export_success(path, diagnostic_id, false)
		return _failure("SESSION_SAVE_DIAGNOSTIC_EXPORT_CONFLICT")
	var temporary := "%s.tmp-%d" % [path, OS.get_process_id()]
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return _failure("SESSION_SAVE_DIAGNOSTIC_EXPORT_FAILED", true)
	file.store_string(serialized)
	file.flush()
	var write_error := file.get_error()
	file = null
	if write_error != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		return _failure("SESSION_SAVE_DIAGNOSTIC_EXPORT_FAILED", true)
	var rename_error := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temporary),
		ProjectSettings.globalize_path(path),
	)
	if rename_error != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		return _failure("SESSION_SAVE_DIAGNOSTIC_EXPORT_FAILED", true)
	return _export_success(path, diagnostic_id, true)


func _published_pair_is_complete(
	manifests: Array,
	context: Dictionary,
	agent_snapshot: Dictionary,
) -> bool:
	if agent_snapshot.get("ok") != true:
		return false
	for manifest_value: Variant in manifests:
		if not manifest_value is Dictionary:
			continue
		var manifest := manifest_value as Dictionary
		if MANIFEST.validate(manifest).get("ok") != true:
			continue
		if not (
			String(manifest.get("slot_id", "")) == String(context.get("slot_id", ""))
			and String(manifest.get("session_id", "")) == String(context.get("session_id", ""))
			and int(manifest.get("save_revision", 0)) == int(context.get("save_revision", -1))
		):
			continue
		var resident_ids := (manifest.get("resident_ids", []) as Array).duplicate()
		resident_ids.sort()
		var payloads := agent_snapshot.get("resident_payloads", {}) as Dictionary
		var agent_ids := payloads.keys()
		agent_ids.sort()
		if agent_ids != resident_ids:
			continue
		var components := manifest.get("components", {}) as Dictionary
		var world := components.get("world", {}) as Dictionary
		var world_snapshot := _read_reference_value(
			String(world.get("snapshot_ref", "")),
			String(world.get("snapshot_sha256", "")),
		)
		var session_config := _read_reference_value(
			String(manifest.get("session_config_ref", "")),
			String(manifest.get("session_config_sha256", "")),
		)
		if (
			world_snapshot.is_empty()
			or session_config.is_empty()
			or not _session_config_is_valid(
				session_config,
				context,
				resident_ids,
			)
			or not _world_snapshot_is_valid(world_snapshot, session_config)
		):
			continue
		var world_log_value: Variant = components.get("world_log")
		if world_log_value is Dictionary:
			var world_log := world_log_value as Dictionary
			var loaded_world_log := _store.call(
				"read_world_log_snapshot",
				String(world_log.get("snapshot_ref", "")),
				String(world_log.get("snapshot_sha256", "")),
			) as Dictionary
			if (
				loaded_world_log.get("ok") != true
				or not loaded_world_log.get("value") is Dictionary
				or (WORLD_LOG_STORE.new().restore_save_snapshot(
					loaded_world_log.get("value", {}) as Dictionary,
				) as Dictionary).get("ok") != true
			):
				continue
		return true
	return false


func _read_reference_value(reference: String, sha256: String) -> Dictionary:
	if reference.is_empty() or sha256.length() != 64:
		return {}
	var loaded := _store.call("read_reference", reference, sha256) as Dictionary
	return (
		(loaded.get("value", {}) as Dictionary).duplicate(true)
		if loaded.get("ok") == true and loaded.get("value") is Dictionary
		else {}
	)


func _world_snapshot_is_valid(
	snapshot: Dictionary,
	session_config: Dictionary,
) -> bool:
	var opening := session_config.get("openingConfig", {}) as Dictionary
	var world_data := {
		"worldId": snapshot.get("worldId"),
		"schemaVersion": snapshot.get("worldDataSchemaVersion"),
		"dataVersion": snapshot.get("worldDataVersion"),
	}
	return WORLD_SAVE_CODEC.validate_envelope(
		snapshot,
		world_data,
		opening,
	).is_empty()


func _session_config_is_valid(
	config: Dictionary,
	context: Dictionary,
	expected_resident_ids: Array,
) -> bool:
	var required := [
		"mode",
		"sessionId",
		"openingConfig",
		"residentIdentities",
		"residentBindings",
		"connectedResidents",
		"worldStartMode",
		"useLiveModel",
		"enablePlayerAvatar",
		"enableTestUi",
	]
	var allowed := required + ["saveRelease"]
	for key_value: Variant in config:
		if not key_value is String or key_value not in allowed:
			return false
	for field: String in required:
		if not config.has(field):
			return false
	if (
		config.get("mode") not in ["new_game", "continue"]
		or String(config.get("sessionId", ""))
		!= String(context.get("session_id", ""))
		or not config.get("openingConfig") is Dictionary
		or (config.get("openingConfig", {}) as Dictionary).is_empty()
		or config.get("worldStartMode") != "formal"
		or not config.get("useLiveModel") is bool
		or not config.get("enablePlayerAvatar") is bool
		or not config.get("enableTestUi") is bool
		or not config.get("connectedResidents") is Array
	):
		return false
	var identity_ids := _resident_ids_from_records(
		config.get("residentIdentities"),
		"residentId",
		"residentName",
	)
	var binding_ids := _resident_ids_from_records(
		config.get("residentBindings"),
		"residentId",
		"llmBinding",
	)
	var expected := expected_resident_ids.duplicate()
	expected.sort()
	var connected := config.get("connectedResidents", []) as Array
	if connected.size() != expected.size():
		return false
	for resident_name: Variant in connected:
		if not resident_name is String or String(resident_name).is_empty():
			return false
	return identity_ids == expected and binding_ids == expected


func _resident_ids_from_records(
	value: Variant,
	id_field: String,
	required_field: String,
) -> Array:
	if not value is Array:
		return []
	var ids: Array = []
	for record_value: Variant in value as Array:
		if not record_value is Dictionary:
			return []
		var record := record_value as Dictionary
		var resident_id := String(record.get(id_field, ""))
		if (
			resident_id.is_empty()
			or ids.has(resident_id)
			or not record.has(required_field)
			or (
				required_field == "residentName"
				and String(record.get(required_field, "")).is_empty()
			)
			or (
				required_field == "llmBinding"
				and not record.get(required_field) is Dictionary
			)
		):
			return []
		ids.append(resident_id)
	ids.sort()
	return ids


func _fresh_items_belong_to_plan(fresh: Array, planned: Array) -> bool:
	for fresh_value: Variant in fresh:
		if not fresh_value is Dictionary:
			return false
		var found := false
		for planned_value: Variant in planned:
			if planned_value is Dictionary and _same_item_identity(
				fresh_value as Dictionary,
				planned_value as Dictionary,
			):
				found = true
				break
		if not found:
			return false
	return true


func _contains_matching_safe_item(items: Array, expected: Dictionary) -> bool:
	for item_value: Variant in items:
		if (
			item_value is Dictionary
			and _same_item_identity(item_value as Dictionary, expected)
			and bool((item_value as Dictionary).get("safe", false))
			and String((item_value as Dictionary).get("resolution", ""))
			== String(expected.get("resolution", ""))
		):
			return true
	return false


func _same_item_identity(left: Dictionary, right: Dictionary) -> bool:
	return (
		left.get("context") == right.get("context")
		and String(left.get("kind", "")) == String(right.get("kind", ""))
		and String(left.get("intentId", "")) == String(right.get("intentId", ""))
		and String(left.get("state", "")) == String(right.get("state", ""))
	)


func _release_and_return(lease_token: String, result: Dictionary) -> Dictionary:
	var released := _store.call("end_slot_transaction", lease_token) as Dictionary
	if released.get("ok") == true:
		return result
	released = released.duplicate(true)
	released["operationResult"] = result.duplicate(true)
	return released


func _diagnostic_id(slot_id: String, items: Array[Dictionary]) -> String:
	var evidence: Array[Dictionary] = []
	for item: Dictionary in items:
		evidence.append({
			"context": (item.get("context", {}) as Dictionary).duplicate(true),
			"kind": String(item.get("kind", "")),
			"intentId": String(item.get("intentId", "")),
			"state": String(item.get("state", "")),
			"safe": bool(item.get("safe", false)),
		})
	return "SAVE-%s" % JSON.stringify({
		"slotId": slot_id,
		"items": evidence,
	}).sha256_text().left(16).to_upper()


func _valid_diagnostic_id(value: String) -> bool:
	if value.length() != 21 or not value.begins_with("SAVE-"):
		return false
	for character: String in value.trim_prefix("SAVE-"):
		if character not in "0123456789ABCDEF":
			return false
	return true


func _sort_items(left: Dictionary, right: Dictionary) -> bool:
	var left_context := left.get("context", {}) as Dictionary
	var right_context := right.get("context", {}) as Dictionary
	var left_key := "%s:%020d:%s:%s" % [
		String(left.get("kind", "")),
		int(left_context.get("save_revision", 0)),
		String(left_context.get("session_id", "")),
		String(left.get("intentId", "")),
	]
	var right_key := "%s:%020d:%s:%s" % [
		String(right.get("kind", "")),
		int(right_context.get("save_revision", 0)),
		String(right_context.get("session_id", "")),
		String(right.get("intentId", "")),
	]
	return left_key < right_key


func _export_success(path: String, diagnostic_id: String, changed: bool) -> Dictionary:
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"diagnosticId": diagnostic_id,
		"path": path,
		"absolutePath": ProjectSettings.globalize_path(path),
		"changed": changed,
		"originalEvidencePreserved": true,
	}


func _success() -> Dictionary:
	return {"ok": true, "errorCode": "", "retryable": false}


func _failure(code: String, retryable := false) -> Dictionary:
	return {"ok": false, "errorCode": code, "retryable": retryable}
