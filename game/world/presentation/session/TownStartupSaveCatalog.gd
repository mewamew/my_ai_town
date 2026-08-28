class_name TownStartupSaveCatalog
extends RefCounted


const SESSION_SAVE_MANIFEST := preload(
	"res://world/presentation/session/TownSessionSaveManifest.gd"
)
const RECOVERY_PLANNER := preload(
	"res://world/presentation/session/TownSaveRecoveryPlanner.gd"
)
const RECONCILIATION_SERVICE := preload(
	"res://world/presentation/session/TownSaveReconciliationService.gd"
)
const COMPATIBILITY := preload(
	"res://world/presentation/session/TownSaveCompatibilityRegistry.gd"
)
const DEFAULT_PROFILE_PATH := "user://town_startup_profile.json"
const TEST_PROFILE_ROOT := "user://tests/town_startup_profile"
const PROFILE_SCHEMA := "town-startup-profile"
const PROFILE_SCHEMA_VERSION := TownSaveSchemaRegistry.PROFILE_SCHEMA_VERSION
const LEGACY_PROFILE_SCHEMA_VERSION := TownSaveSchemaRegistry.PROFILE_LEGACY_SCHEMA_VERSION
const MAX_SAFE_INTEGER := 9007199254740991.0
const MAX_SAFE_INTEGER_TEXT := "9007199254740991"
const STORE_METHODS: Array[String] = [
	"list_published",
	"read_reference",
	"list_incomplete",
]
const SAVE_STATES: Array[String] = [
	"save_started",
	"world_candidate_written",
	"agent_commit_started",
	"agent_committed",
	"world_committed",
	"manifest_published",
	"agent_commit_failed",
	"agent_commit_uncertain",
	"agent_orphan_isolated",
	"transaction_failed",
]
const RESTORE_STATES: Array[String] = [
	"restore_started",
	"restore_world_prepared",
	"restore_agent_started",
	"restore_agent_hydrated",
	"restore_world_validated",
	"restore_agent_commit_started",
	"restore_agent_committed",
	"restore_world_committed",
	"transaction_failed",
]
const SAVE_TRANSACTION_FAILED_STAGES: Array[String] = [
	"gate_begin",
	"world_prepare",
	"world_candidate_write",
	"world_validate",
	"gate_validate",
]
const RESTORE_TRANSACTION_FAILED_STAGES: Array[String] = [
	"world_prepare",
	"agent_prepare",
	"agent_resident_set",
	"agent_hydrate",
	"world_validate",
	"gate_validate",
	"agent_commit",
	"world_commit_after_agent",
	"post_commit_validation",
]
const SAVE_UNCERTAIN_STATES: Array[String] = [
	"agent_commit_started",
	"agent_commit_uncertain",
]
const SAVE_ORPHAN_STATES: Array[String] = [
	"agent_committed",
	"world_committed",
	"agent_orphan_isolated",
]
const RESTORE_UNCERTAIN_STATES: Array[String] = [
	"restore_agent_started",
	"restore_agent_commit_started",
]
const RESTORE_PARTIAL_STATES: Array[String] = [
	"restore_agent_committed",
	"restore_world_committed",
]

var _store: Object
var _agent_store: Object
var _profile_path := DEFAULT_PROFILE_PATH


func configure(
	store_value: Variant,
	profile_path_value: Variant = DEFAULT_PROFILE_PATH,
	agent_store_value: Variant = null,
) -> Dictionary:
	if _store != null:
		return _failure("STARTUP_SAVE_CATALOG_ALREADY_CONFIGURED", false)
	if (
		not store_value is Object
		or not is_instance_valid(store_value)
	):
		return _failure("STARTUP_SAVE_CATALOG_CONTRACT_INVALID", false)
	if not profile_path_value is String:
		return _failure("STARTUP_SAVE_PROFILE_PATH_INVALID", false)
	var store := store_value as Object
	for method_name in STORE_METHODS:
		if not store.has_method(method_name):
			return _failure("STARTUP_SAVE_CATALOG_CONTRACT_INVALID", false, {
				"missingMethod": method_name,
			})
	if agent_store_value != null:
		if (
			not agent_store_value is Object
			or not is_instance_valid(agent_store_value)
			or not (agent_store_value as Object).has_method("load_snapshot")
			or not (agent_store_value as Object).has_method(
				"inspect_snapshot_versions",
			)
		):
			return _failure("STARTUP_SAVE_AGENT_STORE_CONTRACT_INVALID", false)
		_agent_store = agent_store_value as Object
	var normalized_path := (profile_path_value as String).strip_edges()
	if (
		normalized_path.is_empty()
		or normalized_path != profile_path_value
		or normalized_path.contains("..")
	):
		return _failure("STARTUP_SAVE_PROFILE_PATH_INVALID", false)
	if (
		normalized_path != DEFAULT_PROFILE_PATH
		and not normalized_path.begins_with("%s/" % TEST_PROFILE_ROOT)
	):
		return _failure("STARTUP_SAVE_PROFILE_PATH_INVALID", false)
	_store = store
	_profile_path = normalized_path
	return _success()


func get_catalog(slot_definitions_value: Variant) -> Dictionary:
	if _store == null:
		return _failure("STARTUP_SAVE_CATALOG_CONTRACT_INVALID", false)
	var definitions := _normalize_slot_definitions(slot_definitions_value)
	if definitions.get("ok") != true:
		return definitions
	var profile := _load_profile()
	if profile.get("ok") != true:
		return profile
	var profile_version := int(
		profile.get("schemaVersion", PROFILE_SCHEMA_VERSION),
	)
	var slots: Array[Dictionary] = []
	var slots_by_id := {}
	for definition_value: Variant in definitions.get("slots", []) as Array:
		var definition := definition_value as Dictionary
		var inspected := _inspect_slot(definition, profile_version)
		if inspected.get("ok") != true:
			return inspected
		var slot := inspected.get("slot", {}) as Dictionary
		slots.append(slot)
		slots_by_id[String(slot.get("slotId", ""))] = slot

	var shown_messages := (
		profile.get("shownResidentMessages", {}) as Dictionary
	)
	for slot_index in slots.size():
		var slot := slots[slot_index]
		var slot_id := String(slot.get("slotId", ""))
		var shown_ids: Dictionary = {}
		for shown_id_value: Variant in shown_messages.get(slot_id, []) as Array:
			shown_ids[String(shown_id_value)] = true
		var unshown: Array[Dictionary] = []
		for message_value: Variant in slot.get("residentMessages", []) as Array:
			if not message_value is Dictionary:
				continue
			var message := message_value as Dictionary
			if not shown_ids.has(String(message.get("message_id", ""))):
				unshown.append(message.duplicate(true))
		slot["residentMessages"] = unshown
		slots[slot_index] = slot
		slots_by_id[slot_id] = slot
	var last_played_slot_id := String(profile.get("lastPlayedSlotId", ""))
	var source := "profile"
	var profiled_slot := slots_by_id.get(last_played_slot_id, {}) as Dictionary
	if (
		profiled_slot.is_empty()
		or not bool(profiled_slot.get("continueAvailable", false))
	):
		last_played_slot_id = _infer_last_played_slot(slots)
		source = "inferred" if not last_played_slot_id.is_empty() else "none"
	var continue_slot := slots_by_id.get(last_played_slot_id, {}) as Dictionary
	var continue_available := (
		not continue_slot.is_empty()
		and bool(continue_slot.get("continueAvailable", false))
	)
	var first_empty_slot_id := ""
	for slot in slots:
		if String(slot.get("state", "")) == "empty":
			first_empty_slot_id = String(slot.get("slotId", ""))
			break
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"slots": slots,
		"lastPlayedSlotId": last_played_slot_id,
		"lastPlayedSource": source,
		"continueAvailable": continue_available,
		"continueSlot": continue_slot.duplicate(true),
		"residentMessages": (
			(continue_slot.get("residentMessages", []) as Array).duplicate(true)
			if continue_available
			else []
		),
		"firstEmptySlotId": first_empty_slot_id,
		"slotsFull": first_empty_slot_id.is_empty(),
	}


func record_last_played(
	slot_id_value: Variant,
	allowed_slot_ids_value: Variant,
) -> Dictionary:
	if _store == null:
		return _failure("STARTUP_SAVE_CATALOG_CONTRACT_INVALID", false)
	if (
		not slot_id_value is String
		or not allowed_slot_ids_value is Array
	):
		return _failure("STARTUP_SAVE_SLOT_ID_INVALID", false)
	var normalized := (slot_id_value as String).strip_edges()
	if normalized != slot_id_value:
		return _failure("STARTUP_SAVE_SLOT_ID_INVALID", false)
	var allowed: Array[String] = []
	for value: Variant in allowed_slot_ids_value as Array:
		if not value is String:
			return _failure("STARTUP_SAVE_SLOT_ID_INVALID", false)
		var candidate := (value as String).strip_edges()
		if (
			candidate.is_empty()
			or candidate != value
			or allowed.has(candidate)
		):
			return _failure("STARTUP_SAVE_SLOT_ID_INVALID", false)
		allowed.append(candidate)
	if normalized.is_empty() or not allowed.has(normalized):
		return _failure("STARTUP_SAVE_SLOT_ID_INVALID", false)
	var current_profile := _load_profile()
	if current_profile.get("ok") != true:
		return current_profile
	var profile := {
		"schema": PROFILE_SCHEMA,
		"schemaVersion": PROFILE_SCHEMA_VERSION,
		"lastPlayedSlotId": normalized,
		"shownResidentMessages": (
			current_profile.get("shownResidentMessages", {}) as Dictionary
		).duplicate(true),
	}
	var written := _write_profile(profile)
	if written.get("ok") != true:
		return written
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"lastPlayedSlotId": normalized,
	}


func record_resident_messages_shown(
	slot_id_value: Variant,
	message_ids_value: Variant,
	allowed_slot_ids_value: Variant,
) -> Dictionary:
	if (
		_store == null
		or not slot_id_value is String
		or not message_ids_value is Array
		or not allowed_slot_ids_value is Array
	):
		return _failure("STARTUP_SAVE_MESSAGE_RECEIPT_INVALID", false)
	var slot_id := (slot_id_value as String).strip_edges()
	var allowed_slot_ids: Array[String] = []
	for allowed_value: Variant in allowed_slot_ids_value as Array:
		if not allowed_value is String:
			return _failure("STARTUP_SAVE_MESSAGE_RECEIPT_INVALID", false)
		var allowed_id := (allowed_value as String).strip_edges()
		if allowed_id.is_empty() or allowed_slot_ids.has(allowed_id):
			return _failure("STARTUP_SAVE_MESSAGE_RECEIPT_INVALID", false)
		allowed_slot_ids.append(allowed_id)
	if slot_id.is_empty() or not allowed_slot_ids.has(slot_id):
		return _failure("STARTUP_SAVE_MESSAGE_RECEIPT_INVALID", false)
	var message_ids: Array[String] = []
	for message_value: Variant in message_ids_value as Array:
		if not message_value is String:
			return _failure("STARTUP_SAVE_MESSAGE_RECEIPT_INVALID", false)
		var message_id := (message_value as String).strip_edges()
		if (
			message_id.is_empty()
			or message_ids.has(message_id)
			or not _safe_identifier(message_id)
		):
			return _failure("STARTUP_SAVE_MESSAGE_RECEIPT_INVALID", false)
		message_ids.append(message_id)
	if message_ids.is_empty():
		return _failure("STARTUP_SAVE_MESSAGE_RECEIPT_INVALID", false)
	var current_profile := _load_profile()
	if current_profile.get("ok") != true:
		return current_profile
	var shown := (
		current_profile.get("shownResidentMessages", {}) as Dictionary
	).duplicate(true)
	var existing: Array = (
		(shown.get(slot_id, []) as Array).duplicate()
		if shown.get(slot_id, []) is Array
		else []
	)
	for message_id: String in message_ids:
		if not existing.has(message_id):
			existing.append(message_id)
	shown[slot_id] = existing
	var next_profile := {
		"schema": PROFILE_SCHEMA,
		"schemaVersion": PROFILE_SCHEMA_VERSION,
		"lastPlayedSlotId": String(
			current_profile.get("lastPlayedSlotId", "")
		),
		"shownResidentMessages": shown,
	}
	var written := _write_profile(next_profile)
	if written.get("ok") != true:
		return written
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"slotId": slot_id,
		"messageIds": message_ids,
	}


func clear_slot_profile(
	slot_id_value: Variant,
	allowed_slot_ids_value: Variant,
) -> Dictionary:
	if not slot_id_value is String or not allowed_slot_ids_value is Array:
		return _failure("STARTUP_SAVE_SLOT_ID_INVALID", false)
	var slot_id := (slot_id_value as String).strip_edges()
	var allowed_slot_ids: Array[String] = []
	for value: Variant in allowed_slot_ids_value as Array:
		if not value is String:
			return _failure("STARTUP_SAVE_SLOT_ID_INVALID", false)
		var candidate := (value as String).strip_edges()
		if candidate.is_empty() or allowed_slot_ids.has(candidate):
			return _failure("STARTUP_SAVE_SLOT_ID_INVALID", false)
		allowed_slot_ids.append(candidate)
	if slot_id.is_empty() or not allowed_slot_ids.has(slot_id):
		return _failure("STARTUP_SAVE_SLOT_ID_INVALID", false)
	var current_profile := _load_profile()
	if current_profile.get("ok") != true:
		return current_profile
	var shown := (
		current_profile.get("shownResidentMessages", {}) as Dictionary
	).duplicate(true)
	shown.erase(slot_id)
	var last_played := String(current_profile.get("lastPlayedSlotId", ""))
	if last_played == slot_id:
		last_played = ""
	return _write_profile({
		"schema": PROFILE_SCHEMA,
		"schemaVersion": PROFILE_SCHEMA_VERSION,
		"lastPlayedSlotId": last_played,
		"shownResidentMessages": shown,
	})


func _write_profile(profile: Dictionary) -> Dictionary:
	var parent_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(_profile_path.get_base_dir()),
	)
	if parent_error != OK:
		return _failure("STARTUP_SAVE_PROFILE_WRITE_FAILED", true)
	var operation_id := Time.get_ticks_usec()
	var temporary := "%s.tmp-%d" % [_profile_path, operation_id]
	var backup := "%s.bak-%d" % [_profile_path, operation_id]
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return _failure("STARTUP_SAVE_PROFILE_WRITE_FAILED", true)
	file.store_string(JSON.stringify(profile, "\t"))
	file.flush()
	var write_error := file.get_error()
	file = null
	if write_error != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		return _failure("STARTUP_SAVE_PROFILE_WRITE_FAILED", true)
	var absolute_profile := ProjectSettings.globalize_path(_profile_path)
	var absolute_temporary := ProjectSettings.globalize_path(temporary)
	var absolute_backup := ProjectSettings.globalize_path(backup)
	var previous_moved := false
	if FileAccess.file_exists(_profile_path):
		var backup_error := DirAccess.rename_absolute(
			absolute_profile,
			absolute_backup,
		)
		if backup_error != OK:
			DirAccess.remove_absolute(absolute_temporary)
			return _failure("STARTUP_SAVE_PROFILE_WRITE_FAILED", true)
		previous_moved = true
	var rename_error := DirAccess.rename_absolute(
		absolute_temporary,
		absolute_profile,
	)
	if rename_error != OK:
		DirAccess.remove_absolute(absolute_temporary)
		if previous_moved:
			DirAccess.rename_absolute(absolute_backup, absolute_profile)
		return _failure("STARTUP_SAVE_PROFILE_WRITE_FAILED", true)
	if previous_moved:
		DirAccess.remove_absolute(absolute_backup)
	return _success()


func _inspect_slot(definition: Dictionary, profile_version: int) -> Dictionary:
	var slot_id := String(definition.get("slotId", ""))
	var listed_value: Variant = _store.call("list_published", slot_id)
	if not listed_value is Dictionary:
		return _failure("STARTUP_SAVE_STORE_RESPONSE_INVALID", false)
	var listed := listed_value as Dictionary
	if listed.get("ok") != true:
		return _store_failure(listed)
	var incomplete_value: Variant = _store.call("list_incomplete", slot_id)
	if not incomplete_value is Dictionary:
		return _failure("STARTUP_SAVE_STORE_RESPONSE_INVALID", false)
	var incomplete := incomplete_value as Dictionary
	if incomplete.get("ok") != true:
		return _store_failure(incomplete)
	var manifest_values: Variant = listed.get("manifests")
	var read_only_values: Variant = listed.get("readOnly", [])
	var invalid_values: Variant = listed.get("invalid")
	var record_values: Variant = incomplete.get("records")
	if (
		not manifest_values is Array
		or not read_only_values is Array
		or not invalid_values is Array
		or not record_values is Array
	):
		return _failure("STARTUP_SAVE_STORE_RESPONSE_INVALID", false)

	var complete_revisions: Array[Dictionary] = []
	var corrupt_revisions: Array[Dictionary] = []
	var seen_manifest_revisions: Dictionary = {}
	var latest_evidence_revision := -1
	for manifest_value: Variant in manifest_values as Array:
		if not manifest_value is Dictionary:
			return _failure("STARTUP_SAVE_STORE_RESPONSE_INVALID", false)
		var manifest := manifest_value as Dictionary
		var inspected := _inspect_manifest(manifest, slot_id, profile_version)
		var revision := _integer_or(
			manifest.get("save_revision"),
			-1,
		)
		if revision < 1 or seen_manifest_revisions.has(revision):
			return _failure("STARTUP_SAVE_STORE_RESPONSE_INVALID", false)
		seen_manifest_revisions[revision] = true
		latest_evidence_revision = maxi(latest_evidence_revision, revision)
		if inspected.get("ok") == true:
			complete_revisions.append(inspected)
		else:
			var inspection_code := _string_or(
				inspected.get("errorCode"),
				"STARTUP_SAVE_STORE_RESPONSE_INVALID",
			)
			if (
				bool(inspected.get("retryable", false))
				or inspection_code.begins_with("STARTUP_SAVE_")
				or not _is_corrupt_reference_failure(inspection_code)
				and bool(
					(inspected.get("meta", {}) as Dictionary).get(
						"storeFailure",
						false,
					),
				)
			):
				return inspected
			corrupt_revisions.append(
				_corrupt_revision_details(manifest, inspected),
			)
	for read_only_value: Variant in read_only_values as Array:
		if not read_only_value is Dictionary:
			return _failure("STARTUP_SAVE_STORE_RESPONSE_INVALID", false)
		var inspected := _inspect_read_only_manifest(
			read_only_value as Dictionary,
			slot_id,
		)
		if inspected.get("ok") != true:
			return inspected
		var revision := int(inspected.get("saveRevision", -1))
		if revision < 1 or seen_manifest_revisions.has(revision):
			return _failure("STARTUP_SAVE_STORE_RESPONSE_INVALID", false)
		seen_manifest_revisions[revision] = true
		latest_evidence_revision = maxi(latest_evidence_revision, revision)
		complete_revisions.append(inspected)
	for invalid_value: Variant in invalid_values as Array:
		if not invalid_value is String:
			return _failure("STARTUP_SAVE_STORE_RESPONSE_INVALID", false)
		var revision := _revision_from_file_name(invalid_value as String)
		var evidence_revision := maxi(revision, 0)
		latest_evidence_revision = maxi(
			latest_evidence_revision,
			evidence_revision,
		)
		corrupt_revisions.append({
			"saveRevision": evidence_revision,
			"sessionId": "",
			"savedAt": "",
			"worldRevision": -1,
			"residentCount": 0,
			"errorCode": "SESSION_SAVE_MANIFEST_INVALID",
			"detailsAvailable": false,
		})
	complete_revisions.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left.get("saveRevision", -1)) > int(right.get("saveRevision", -1))
	)
	corrupt_revisions.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left.get("saveRevision", -1)) > int(right.get("saveRevision", -1))
	)

	var latest_incomplete_revision := -1
	var save_blockers: Array[Dictionary] = []
	var restore_blockers: Array[Dictionary] = []
	for record_value: Variant in record_values as Array:
		if not record_value is Dictionary:
			return _failure("STARTUP_SAVE_STORE_RESPONSE_INVALID", false)
		var record := record_value as Dictionary
		var context_value: Variant = record.get("context")
		var kind_value: Variant = record.get("kind")
		var state_value: Variant = record.get("state")
		if (
			not context_value is Dictionary
			or not kind_value is String
			or not state_value is String
		):
			return _failure("STARTUP_SAVE_STORE_RESPONSE_INVALID", false)
		var context := context_value as Dictionary
		if not _has_exact_fields(
			context,
			["slot_id", "session_id", "save_revision"],
		):
			return _failure("STARTUP_SAVE_STORE_RESPONSE_INVALID", false)
		var context_slot_id := _required_string(context.get("slot_id"))
		var context_session_id := _required_string(context.get("session_id"))
		var revision := _integer_or(context.get("save_revision"), -1)
		if (
			context_slot_id != slot_id
			or context_session_id.is_empty()
			or revision < 1
		):
			return _failure("STARTUP_SAVE_STORE_RESPONSE_INVALID", false)
		var kind := kind_value as String
		if kind == "save":
			var save_state := state_value as String
			if save_state not in SAVE_STATES:
				return _failure(
					"STARTUP_SAVE_STORE_RESPONSE_INVALID",
					false,
				)
			if save_state == "transaction_failed":
				var failure_stage := _transaction_failure_stage(record)
				if failure_stage not in SAVE_TRANSACTION_FAILED_STAGES:
					return _failure(
						"STARTUP_SAVE_STORE_RESPONSE_INVALID",
						false,
					)
			latest_incomplete_revision = maxi(latest_incomplete_revision, revision)
			latest_evidence_revision = maxi(latest_evidence_revision, revision)
			if save_state in SAVE_UNCERTAIN_STATES:
				save_blockers.append({
					"saveRevision": revision,
					"state": save_state,
					"errorCode": "SESSION_SAVE_AGENT_COMMIT_UNCERTAIN",
				})
			elif save_state in SAVE_ORPHAN_STATES:
				save_blockers.append({
					"saveRevision": revision,
					"state": save_state,
					"errorCode": "SESSION_SAVE_AGENT_ORPHAN_ISOLATED",
				})
		elif kind == "restore":
			var state := state_value as String
			if state not in RESTORE_STATES:
				return _failure(
					"STARTUP_SAVE_STORE_RESPONSE_INVALID",
					false,
				)
			var blocker_code := ""
			if state in RESTORE_UNCERTAIN_STATES:
				blocker_code = "SESSION_CONTINUE_AGENT_COMMIT_UNCERTAIN"
			elif state in RESTORE_PARTIAL_STATES:
				blocker_code = "SESSION_CONTINUE_PARTIAL_COMMIT"
			elif state == "transaction_failed":
				var failure_stage := _transaction_failure_stage(record)
				if failure_stage not in RESTORE_TRANSACTION_FAILED_STAGES:
					return _failure(
						"STARTUP_SAVE_STORE_RESPONSE_INVALID",
						false,
					)
				if failure_stage == "agent_commit":
					blocker_code = (
						"SESSION_CONTINUE_AGENT_COMMIT_UNCERTAIN"
					)
				elif failure_stage in [
					"world_commit_after_agent",
					"post_commit_validation",
				]:
					blocker_code = "SESSION_CONTINUE_PARTIAL_COMMIT"
			if not blocker_code.is_empty():
				restore_blockers.append({
					"saveRevision": revision,
					"state": state,
					"errorCode": blocker_code,
				})
		else:
			return _failure("STARTUP_SAVE_STORE_RESPONSE_INVALID", false)
	var blocker_sort := func(left: Dictionary, right: Dictionary) -> bool:
		var left_revision := int(left.get("saveRevision", -1))
		var right_revision := int(right.get("saveRevision", -1))
		if left_revision != right_revision:
			return left_revision > right_revision
		return String(left.get("state", "")) < String(right.get("state", ""))
	save_blockers.sort_custom(blocker_sort)
	restore_blockers.sort_custom(blocker_sort)
	var reconciliation_plan: Dictionary = {}
	if _agent_store != null and not (record_values as Array).is_empty():
		var reconciliation := RECONCILIATION_SERVICE.new()
		var reconciliation_configured := reconciliation.configure(
			_store,
			_agent_store,
		) as Dictionary
		if reconciliation_configured.get("ok") != true:
			return reconciliation_configured
		var reconciliation_inspection := reconciliation.inspect(slot_id) as Dictionary
		if reconciliation_inspection.get("ok") != true:
			return reconciliation_inspection
		reconciliation_plan = reconciliation_inspection.duplicate(true)

	var latest_complete := (
		complete_revisions[0].duplicate(true)
		if not complete_revisions.is_empty()
		else {}
	)
	var latest_complete_revision := int(latest_complete.get("saveRevision", -1))
	var latest_corrupt_revision := (
		int(corrupt_revisions[0].get("saveRevision", -1))
		if not corrupt_revisions.is_empty()
		else -1
	)
	var state := "empty"
	var recovery_state := "none"
	var continue_available := false
	var requires_confirmation := false
	var recovery_progress_rollback := false
	var error_code := ""
	if not save_blockers.is_empty():
		state = "corrupt"
		recovery_state = "save_reconciliation_required"
		error_code = String(save_blockers[0].get("errorCode", ""))
	elif not restore_blockers.is_empty():
		state = "corrupt"
		recovery_state = "restore_reconciliation_required"
		error_code = "SESSION_CONTINUE_RECONCILE_REQUIRED"
	elif latest_evidence_revision < 0:
		state = "empty"
	elif latest_complete.is_empty():
		if latest_incomplete_revision >= latest_corrupt_revision:
			state = "incomplete"
			recovery_state = "no_published_revision"
			error_code = "SESSION_SAVE_INCOMPLETE_CANDIDATE"
		else:
			state = "corrupt"
			recovery_state = "no_complete_revision"
			error_code = (
				String(corrupt_revisions[0].get("errorCode", ""))
				if not corrupt_revisions.is_empty()
				else "SESSION_SAVE_MANIFEST_INVALID"
			)
	elif (
		latest_complete.get("compatibility", {}) is Dictionary
		and (latest_complete.get("compatibility", {}) as Dictionary).get("ok")
		!= true
	):
		var blocked_compatibility := (
			latest_complete.get("compatibility", {}) as Dictionary
		)
		state = "read_only"
		recovery_state = "version_not_supported"
		continue_available = false
		error_code = String(
			(blocked_compatibility.get("error", {}) as Dictionary).get(
				"code",
				"SAVE_VERSION_COMBINATION_UNKNOWN",
			),
		)
	elif (
		latest_corrupt_revision > latest_complete_revision
		and latest_corrupt_revision >= latest_incomplete_revision
	):
		state = "recoverable"
		recovery_state = "older_complete_revision_available"
		continue_available = true
		var latest_corrupt := corrupt_revisions[0]
		var latest_complete_summary := latest_complete.get("summary", {}) as Dictionary
		recovery_progress_rollback = (
			int(latest_corrupt.get("worldRevision", -1))
			> int(latest_complete_summary.get("worldRevision", -1))
		)
		# A damaged latest revision must always be explained before the player
		# chooses an older complete World + Agent pair. Progress rollback only
		# changes the warning copy; it no longer skips the recovery page.
		requires_confirmation = true
		error_code = String(corrupt_revisions[0].get("errorCode", ""))
	elif latest_incomplete_revision > latest_complete_revision:
		state = "incomplete"
		recovery_state = "latest_complete_revision_available"
		continue_available = true
	else:
		state = "healthy"
		recovery_state = "current"
		continue_available = true
	if not reconciliation_plan.is_empty():
		if bool(reconciliation_plan.get("repairable", false)) and not latest_complete.is_empty():
			state = "recoverable"
			continue_available = true
			requires_confirmation = true
		else:
			state = "corrupt"
			continue_available = false
			requires_confirmation = false
		if String(recovery_state) == "none":
			recovery_state = "transaction_reconciliation_required"

	var summary := {}
	var manifest := {}
	var session_config := {}
	var compatibility_evidence := {}
	var compatibility := {}
	if not latest_complete.is_empty():
		summary = (latest_complete.get("summary", {}) as Dictionary).duplicate(true)
		summary["slotName"] = String(definition.get("displayName", ""))
		manifest = (latest_complete.get("manifest", {}) as Dictionary).duplicate(true)
		session_config = (
			latest_complete.get("sessionConfig", {}) as Dictionary
		).duplicate(true)
		compatibility_evidence = (
			latest_complete.get("compatibilityEvidence", {}) as Dictionary
		).duplicate(true)
		compatibility = (
			latest_complete.get("compatibility", {}) as Dictionary
		).duplicate(true)
	var resident_messages := (
		SESSION_SAVE_MANIFEST.resident_messages(manifest)
		if not manifest.is_empty()
		else []
	)
	var slot := {
		"slotId": slot_id,
		"displayName": String(definition.get("displayName", "")),
		"state": state,
		"recoveryState": recovery_state,
		"continueAvailable": continue_available,
		"requiresRecoveryConfirmation": requires_confirmation,
		"recoveryProgressRollback": recovery_progress_rollback,
		"errorCode": error_code,
		"latestEvidenceRevision": latest_evidence_revision,
		"latestCompleteRevision": latest_complete_revision,
		"latestIncompleteRevision": latest_incomplete_revision,
		"summary": summary,
		"manifest": manifest,
		"sessionConfig": session_config,
		"compatibilityEvidence": compatibility_evidence,
		"compatibility": compatibility,
		"residentMessages": resident_messages,
		"corruptRevisions": corrupt_revisions,
		"damageDetails": (
			_build_damage_details(
				corrupt_revisions[0],
				latest_complete,
				recovery_progress_rollback,
			)
			if state == "recoverable" and not corrupt_revisions.is_empty()
			else {}
		),
		"continueNotice": (
			{
				"noticeId": "latest_save_incomplete_fallback",
				"message": "上次保存未完成，已使用最近完整存档",
				"surface": "toast",
				"blocking": false,
			}
			if (
				state == "incomplete"
				and not latest_complete.is_empty()
				and latest_incomplete_revision > latest_complete_revision
			)
			else {}
		),
		"saveBlockers": save_blockers,
		"restoreBlockers": restore_blockers,
		"reconciliationPlan": reconciliation_plan,
		"diagnosticAvailable": (
			String(reconciliation_plan.get("action", ""))
			== RECONCILIATION_SERVICE.EXPORT_ACTION
		),
		"agentIntegrity": (
			"version_only_read_only"
			if (
				not latest_complete.is_empty()
				and (latest_complete.get("compatibility", {}) as Dictionary).get(
					"ok",
				) != true
			)
			else "agent_snapshot_verified"
			if _agent_store != null and not latest_complete.is_empty()
			else "manifest_committed_unverified"
			if not latest_complete.is_empty()
			else "not_applicable"
		),
	}
	var inspection_report := RECOVERY_PLANNER.inspection_report(slot)
	slot["inspectionReport"] = inspection_report
	var recovery_plan := RECOVERY_PLANNER.recovery_plan(
		slot,
		inspection_report,
	)
	slot["recoveryPlan"] = recovery_plan
	slot["diagnosticAvailable"] = (
		String(recovery_plan.get("action", ""))
		== RECONCILIATION_SERVICE.EXPORT_ACTION
		or (
			not bool(slot.get("continueAvailable", false))
			and not recovery_plan.is_empty()
		)
	)
	return {
		"ok": true,
		"slot": slot,
	}


func _inspect_read_only_manifest(record: Dictionary, slot_id: String) -> Dictionary:
	var manifest_value: Variant = record.get("manifest")
	var versions_value: Variant = record.get("versions")
	if not manifest_value is Dictionary or not versions_value is Dictionary:
		return _failure("STARTUP_SAVE_STORE_RESPONSE_INVALID", false)
	var manifest := manifest_value as Dictionary
	var revision := _integer_or(manifest.get("save_revision"), -1)
	if (
		revision < 1
		or _required_string(manifest.get("slot_id")) != slot_id
		or _required_string(manifest.get("session_id")).is_empty()
	):
		return _failure("STARTUP_SAVE_STORE_RESPONSE_INVALID", false)
	var evidence := {"versions": (versions_value as Dictionary).duplicate(true)}
	var compatibility := COMPATIBILITY.detect_release(evidence)
	if compatibility.get("ok") == true:
		return _failure("STARTUP_SAVE_STORE_RESPONSE_INVALID", false)
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"saveRevision": revision,
		"manifest": manifest.duplicate(true),
		"sessionConfig": {},
		"summary": {
			"slotId": slot_id,
			"sessionId": String(manifest.get("session_id", "")),
			"saveRevision": revision,
			"savedAt": String(manifest.get("saved_at", "")),
			"residentCount": 0,
			"worldRevision": -1,
			"day": 0,
		},
		"compatibilityEvidence": evidence,
		"compatibility": compatibility,
	}


func _corrupt_revision_details(
	manifest: Dictionary,
	inspection: Dictionary,
) -> Dictionary:
	var components_value: Variant = manifest.get("components")
	var components := (
		components_value as Dictionary
		if components_value is Dictionary
		else {}
	)
	var world_value: Variant = components.get("world")
	var world := (
		world_value as Dictionary
		if world_value is Dictionary
		else {}
	)
	var resident_ids_value: Variant = manifest.get("resident_ids")
	return {
		"saveRevision": _integer_or(manifest.get("save_revision"), -1),
		"sessionId": _string_or_empty(manifest.get("session_id")),
		"savedAt": _string_or_empty(manifest.get("saved_at")),
		"worldRevision": _integer_or(world.get("world_revision"), -1),
		"residentCount": (
			(resident_ids_value as Array).size()
			if resident_ids_value is Array
			else 0
		),
		"errorCode": _string_or(
			inspection.get("errorCode"),
			"SESSION_SAVE_MANIFEST_INVALID",
		),
		"detailsAvailable": true,
	}


func _build_damage_details(
	corrupt: Dictionary,
	latest_complete: Dictionary,
	progress_rollback: bool,
) -> Dictionary:
	var fallback_summary := latest_complete.get("summary", {}) as Dictionary
	return {
		"damagedSaveRevision": int(corrupt.get("saveRevision", -1)),
		"damagedSavedAt": String(corrupt.get("savedAt", "")),
		"damagedWorldRevision": int(corrupt.get("worldRevision", -1)),
		"damagedResidentCount": int(corrupt.get("residentCount", 0)),
		"damageCode": String(corrupt.get("errorCode", "SESSION_SAVE_MANIFEST_INVALID")),
		"detailsAvailable": bool(corrupt.get("detailsAvailable", false)),
		"fallbackSaveRevision": int(fallback_summary.get("saveRevision", -1)),
		"fallbackSavedAt": String(fallback_summary.get("savedAt", "")),
		"fallbackWorldRevision": int(fallback_summary.get("worldRevision", -1)),
		"fallbackDay": int(fallback_summary.get("day", 0)),
		"progressRollback": progress_rollback,
	}


func _inspect_manifest(
	manifest: Dictionary,
	expected_slot_id: String,
	profile_version: int,
) -> Dictionary:
	var revision := _integer_or(manifest.get("save_revision"), -1)
	var slot_id := _required_string(manifest.get("slot_id"))
	var session_id := _required_string(manifest.get("session_id"))
	var saved_at := _required_string(manifest.get("saved_at"))
	var config_ref := _required_string(manifest.get("session_config_ref"))
	var config_sha256 := _required_string(
		manifest.get("session_config_sha256"),
	)
	var resident_ids_value: Variant = manifest.get("resident_ids")
	var components_value: Variant = manifest.get("components")
	if not slot_id.is_empty() and slot_id != expected_slot_id:
		return _failure("STARTUP_SAVE_STORE_RESPONSE_INVALID", false)
	if (
		revision < 1
		or slot_id.is_empty()
		or session_id.is_empty()
		or not TownSaveScalars.is_saved_at(saved_at)
		or config_ref.is_empty()
		or config_sha256.is_empty()
		or not resident_ids_value is Array
		or not components_value is Dictionary
	):
		return _failure("SESSION_SAVE_MANIFEST_INVALID", false)
	var resident_ids := resident_ids_value as Array
	var normalized_resident_ids := _normalized_unique_strings(resident_ids)
	if (
		normalized_resident_ids.get("ok") != true
		or (normalized_resident_ids.get("values", []) as Array).is_empty()
	):
		return _failure("SESSION_SAVE_MANIFEST_INVALID", false)
	var components := components_value as Dictionary
	var world_value: Variant = components.get("world")
	if not world_value is Dictionary:
		return _failure("SESSION_SAVE_MANIFEST_INVALID", false)
	var world := world_value as Dictionary
	var snapshot_ref := _required_string(world.get("snapshot_ref"))
	var snapshot_sha256 := _required_string(world.get("snapshot_sha256"))
	var world_revision := _integer_or(world.get("world_revision"), -1)
	if (
		snapshot_ref.is_empty()
		or snapshot_sha256.is_empty()
		or world_revision < 0
	):
		return _failure("SESSION_SAVE_MANIFEST_INVALID", false)
	var snapshot_loaded_value: Variant = _store.call(
		"read_reference",
		snapshot_ref,
		snapshot_sha256,
	)
	if not snapshot_loaded_value is Dictionary:
		return _failure("STARTUP_SAVE_STORE_RESPONSE_INVALID", false)
	var snapshot_loaded := snapshot_loaded_value as Dictionary
	if snapshot_loaded.get("ok") != true:
		return _store_failure(snapshot_loaded)
	var world_log_value: Variant = components.get("world_log")
	if world_log_value is Dictionary:
		var world_log := world_log_value as Dictionary
		var world_log_loaded_value: Variant = _store.call(
			"read_reference",
			_required_string(world_log.get("snapshot_ref")),
			_required_string(world_log.get("snapshot_sha256")),
		)
		if not world_log_loaded_value is Dictionary:
			return _failure("STARTUP_SAVE_STORE_RESPONSE_INVALID", false)
		var world_log_loaded := world_log_loaded_value as Dictionary
		if world_log_loaded.get("ok") != true:
			return _store_failure(world_log_loaded)
		if not world_log_loaded.get("value") is Dictionary:
			return _failure("SESSION_SAVE_WORLD_LOG_INVALID", false)
	elif int(manifest.get("schema_version", 0)) >= 3:
		return _failure("SESSION_SAVE_MANIFEST_INVALID", false)
	var config_loaded_value: Variant = _store.call(
		"read_reference",
		config_ref,
		config_sha256,
	)
	if not config_loaded_value is Dictionary:
		return _failure("STARTUP_SAVE_STORE_RESPONSE_INVALID", false)
	var config_loaded := config_loaded_value as Dictionary
	if config_loaded.get("ok") != true:
		return _store_failure(config_loaded)
	var snapshot_value: Variant = snapshot_loaded.get("value")
	var config_value: Variant = config_loaded.get("value")
	if not snapshot_value is Dictionary or not config_value is Dictionary:
		return _failure("STARTUP_SAVE_STORE_RESPONSE_INVALID", false)
	var snapshot := snapshot_value as Dictionary
	var state_value: Variant = snapshot.get("state")
	if not state_value is Dictionary:
		return _failure("SESSION_SAVE_WORLD_SUMMARY_INVALID", false)
	var state := state_value as Dictionary
	var environment_value: Variant = state.get("environment")
	if not environment_value is Dictionary:
		return _failure("SESSION_SAVE_WORLD_SUMMARY_INVALID", false)
	var environment := environment_value as Dictionary
	var day := _integer_or(environment.get("day"), 0)
	if day <= 0:
		return _failure("SESSION_SAVE_WORLD_SUMMARY_INVALID", false)
	var session_config := config_value as Dictionary
	var binding_check := _validate_saved_bindings(
		session_config.get("residentBindings"),
		resident_ids,
	)
	if binding_check.get("ok") != true:
		return binding_check
	var context := {
		"slot_id": slot_id,
		"session_id": session_id,
		"save_revision": revision,
	}
	var agent_versions := _inspect_agent_versions(context)
	if agent_versions.get("ok") != true:
		return agent_versions
	var module_versions := (
		agent_versions.get("versions", {}) as Dictionary
	).duplicate(true)
	module_versions["profile"] = profile_version
	var compatibility_evidence := COMPATIBILITY.evidence_from_save(
		manifest,
		snapshot,
		session_config,
		"",
		module_versions,
	)
	var compatibility := COMPATIBILITY.detect_release(compatibility_evidence)
	if compatibility.get("ok") == true:
		var agent_check := _inspect_agent_snapshot(
			slot_id,
			session_id,
			revision,
			normalized_resident_ids.get("values", []) as Array[String],
		)
		if agent_check.get("ok") != true:
			return agent_check
	var summary := {
		"slotId": slot_id,
		"sessionId": session_id,
		"saveRevision": revision,
		"savedAt": saved_at,
		"residentCount": resident_ids.size(),
		"worldRevision": world_revision,
		"day": day,
	}
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"saveRevision": revision,
		"manifest": manifest.duplicate(true),
		"sessionConfig": session_config.duplicate(true),
		"summary": summary,
		"compatibilityEvidence": compatibility_evidence,
		"compatibility": compatibility,
	}


func _inspect_agent_versions(context: Dictionary) -> Dictionary:
	if _agent_store == null:
		return {"ok": true, "versions": {
			"agent": 3,
			"residentPayload": 2,
			"residentRuntime": 6,
			"residentMemory": 6,
		}}
	var inspected_value: Variant = _agent_store.inspect_snapshot_versions(
		context.duplicate(true),
	)
	if not inspected_value is Dictionary:
		return _failure("SESSION_SAVE_AGENT_SNAPSHOT_INVALID", false)
	var inspected := inspected_value as Dictionary
	if inspected.get("ok") != true:
		return _failure(
			"SESSION_SAVE_AGENT_SNAPSHOT_INVALID",
			false,
			{"meta": {"agentStoreErrors": inspected.get("errors", [])}},
		)
	return inspected


func _inspect_agent_snapshot(
	slot_id: String,
	session_id: String,
	save_revision: int,
	expected_resident_ids: Array[String],
) -> Dictionary:
	# Unit-level catalog consumers may omit an Agent store. Production always
	# supplies one so "complete" means an actually readable World+Agent pair.
	if _agent_store == null:
		return _success()
	var loaded_value: Variant = _agent_store.call("load_snapshot", {
		"slot_id": slot_id,
		"session_id": session_id,
		"save_revision": save_revision,
	})
	if not loaded_value is Dictionary:
		return _failure(
			"SESSION_SAVE_AGENT_SNAPSHOT_INVALID",
			false,
			{"meta": {"responseType": typeof(loaded_value)}},
		)
	var loaded := loaded_value as Dictionary
	if loaded.get("ok") != true:
		return _failure(
			"SESSION_SAVE_AGENT_SNAPSHOT_INVALID",
			false,
			{"meta": {
				"agentStoreErrors": loaded.get("errors", loaded.get("error", [])),
				"payloadType": typeof(loaded.get("resident_payloads")),
			}},
		)
	var payloads_value: Variant = loaded.get("resident_payloads")
	if not payloads_value is Dictionary:
		return _failure(
			"SESSION_SAVE_AGENT_SNAPSHOT_INVALID",
			false,
			{"meta": {"payloadType": typeof(payloads_value)}},
		)
	var actual_ids: Array[String] = []
	for resident_id_value: Variant in (payloads_value as Dictionary).keys():
		if not resident_id_value is String:
			return _failure("SESSION_SAVE_AGENT_SNAPSHOT_INVALID", false)
		actual_ids.append(resident_id_value as String)
	actual_ids.sort()
	var sorted_expected := expected_resident_ids.duplicate()
	sorted_expected.sort()
	if actual_ids != sorted_expected:
		return _failure("SESSION_SAVE_AGENT_RESIDENT_SET_MISMATCH", false)
	return _success()


func _validate_saved_bindings(value: Variant, expected_ids: Array) -> Dictionary:
	if not value is Array:
		return _failure("SESSION_SAVE_RESIDENT_BINDINGS_MISSING", false)
	var expected_result := _normalized_unique_strings(expected_ids)
	if expected_result.get("ok") != true:
		return _failure("SESSION_SAVE_RESIDENT_BINDINGS_INVALID", false)
	var ids: Array[String] = []
	for binding_value: Variant in value as Array:
		if not binding_value is Dictionary:
			return _failure("SESSION_SAVE_RESIDENT_BINDINGS_INVALID", false)
		var binding := binding_value as Dictionary
		if not _has_exact_fields(binding, ["residentId", "llmBinding"]):
			return _failure("SESSION_SAVE_RESIDENT_BINDINGS_INVALID", false)
		var resident_id := _required_string(binding.get("residentId"))
		var llm_value: Variant = binding.get("llmBinding")
		if (
			resident_id.is_empty()
			or ids.has(resident_id)
			or not llm_value is Dictionary
		):
			return _failure("SESSION_SAVE_RESIDENT_BINDINGS_INVALID", false)
		var llm := llm_value as Dictionary
		if (
			not _has_exact_fields(
				llm,
				["mode", "providerId", "modelId"],
			)
			or _required_string(llm.get("mode")) != "model"
			or _required_string(llm.get("providerId")).is_empty()
			or _required_string(llm.get("modelId")).is_empty()
		):
			return _failure("SESSION_SAVE_RESIDENT_BINDINGS_INVALID", false)
		ids.append(resident_id)
	ids.sort()
	var normalized_expected := (
		expected_result.get("values", []) as Array[String]
	)
	if ids != normalized_expected:
		return _failure("SESSION_SAVE_RESIDENT_BINDINGS_INVALID", false)
	return _success()


func _load_profile() -> Dictionary:
	if not FileAccess.file_exists(_profile_path):
		return {
			"ok": true,
			"errorCode": "",
			"retryable": false,
			"schemaVersion": PROFILE_SCHEMA_VERSION,
			"lastPlayedSlotId": "",
			"shownResidentMessages": {},
		}
	var file := FileAccess.open(_profile_path, FileAccess.READ)
	if file == null:
		return _failure("STARTUP_SAVE_PROFILE_READ_FAILED", true)
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return _failure("STARTUP_SAVE_PROFILE_INVALID", false)
	var parsed: Variant = parser.data
	if not parsed is Dictionary:
		return _failure("STARTUP_SAVE_PROFILE_INVALID", false)
	var profile := parsed as Dictionary
	var schema_version := _integer_or(profile.get("schemaVersion"), 0)
	if (
		profile.has("schemaVersion")
		and _is_integer_number(profile.get("schemaVersion"))
		and schema_version not in [
			LEGACY_PROFILE_SCHEMA_VERSION,
			PROFILE_SCHEMA_VERSION,
		]
	):
		return COMPATIBILITY.restore_gate(COMPATIBILITY.detect_release({
			"versions": {"profile": schema_version},
		}))
	var allowed_fields := (
		["schema", "schemaVersion", "lastPlayedSlotId"]
		if schema_version == LEGACY_PROFILE_SCHEMA_VERSION
		else [
			"schema",
			"schemaVersion",
			"lastPlayedSlotId",
			"shownResidentMessages",
		]
	)
	var last_played_value: Variant = profile.get("lastPlayedSlotId")
	var last_played_slot_id := _string_or_empty(last_played_value)
	if (
		not _has_exact_fields(profile, allowed_fields)
		or _required_string(profile.get("schema")) != PROFILE_SCHEMA
		or schema_version not in [
			LEGACY_PROFILE_SCHEMA_VERSION,
			PROFILE_SCHEMA_VERSION,
		]
		or not last_played_value is String
		or last_played_slot_id != last_played_slot_id.strip_edges()
		or (
			not last_played_slot_id.is_empty()
			and not _safe_identifier(last_played_slot_id)
		)
	):
		return _failure("STARTUP_SAVE_PROFILE_INVALID", false)
	var shown_result := _validate_shown_messages(
		profile.get("shownResidentMessages", {})
		if schema_version == PROFILE_SCHEMA_VERSION
		else {}
	)
	if shown_result.get("ok") != true:
		return shown_result
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"schemaVersion": schema_version,
		"lastPlayedSlotId": last_played_slot_id,
		"shownResidentMessages": (
			shown_result.get("shownResidentMessages", {}) as Dictionary
		).duplicate(true),
	}


func _validate_shown_messages(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return _failure("STARTUP_SAVE_PROFILE_INVALID", false)
	var normalized: Dictionary = {}
	for slot_value: Variant in value:
		if not slot_value is String:
			return _failure("STARTUP_SAVE_PROFILE_INVALID", false)
		var slot_id := (slot_value as String).strip_edges()
		var ids_value: Variant = (value as Dictionary).get(slot_value)
		if (
			slot_id.is_empty()
			or slot_id != slot_value
			or not _safe_identifier(slot_id)
			or not ids_value is Array
		):
			return _failure("STARTUP_SAVE_PROFILE_INVALID", false)
		var ids: Array[String] = []
		for id_value: Variant in ids_value as Array:
			if not id_value is String:
				return _failure("STARTUP_SAVE_PROFILE_INVALID", false)
			var message_id := (id_value as String).strip_edges()
			if (
				message_id.is_empty()
				or ids.has(message_id)
				or not _safe_identifier(message_id)
			):
				return _failure("STARTUP_SAVE_PROFILE_INVALID", false)
			ids.append(message_id)
		normalized[slot_id] = ids
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"shownResidentMessages": normalized,
	}


func _infer_last_played_slot(slots: Array[Dictionary]) -> String:
	var selected_slot_id := ""
	var selected_saved_at := -INF
	for slot in slots:
		if not bool(slot.get("continueAvailable", false)):
			continue
		var summary := slot.get("summary", {}) as Dictionary
		var saved_at := String(summary.get("savedAt", ""))
		var saved_at_value := _saved_at_sort_value(saved_at)
		if (
			selected_slot_id.is_empty()
			or saved_at_value > selected_saved_at
		):
			selected_slot_id = String(slot.get("slotId", ""))
			selected_saved_at = saved_at_value
	return selected_slot_id


func _normalize_slot_definitions(values_value: Variant) -> Dictionary:
	if not values_value is Array:
		return _failure("STARTUP_SAVE_SLOT_DEFINITIONS_INVALID", false)
	var values := values_value as Array
	var slots: Array[Dictionary] = []
	var ids: Array[String] = []
	for value: Variant in values:
		if not value is Dictionary:
			return _failure("STARTUP_SAVE_SLOT_DEFINITIONS_INVALID", false)
		var definition := value as Dictionary
		if not _has_exact_fields(definition, ["slotId", "displayName"]):
			return _failure("STARTUP_SAVE_SLOT_DEFINITIONS_INVALID", false)
		var slot_id := _required_string(definition.get("slotId"))
		var display_name := _required_string(definition.get("displayName"))
		if (
			slot_id.is_empty()
			or display_name.is_empty()
			or ids.has(slot_id)
		):
			return _failure("STARTUP_SAVE_SLOT_DEFINITIONS_INVALID", false)
		ids.append(slot_id)
		slots.append({"slotId": slot_id, "displayName": display_name})
	if slots.size() < 2:
		return _failure("STARTUP_SAVE_SLOT_DEFINITIONS_INVALID", false)
	return {"ok": true, "slots": slots}


func _revision_from_file_name(file_name: String) -> int:
	var text := file_name.trim_suffix(".json")
	if not file_name.ends_with(".json") or not text.is_valid_int():
		return -1
	var significant := text
	while significant.begins_with("0"):
		significant = significant.trim_prefix("0")
	if significant.is_empty():
		return -1
	if (
		significant.length() > MAX_SAFE_INTEGER_TEXT.length()
		or (
			significant.length() == MAX_SAFE_INTEGER_TEXT.length()
			and significant.naturalnocasecmp_to(MAX_SAFE_INTEGER_TEXT) > 0
		)
	):
		return -1
	var revision := int(text)
	return revision if revision > 0 else -1


func _normalized_unique_strings(values: Array) -> Dictionary:
	var normalized: Array[String] = []
	for value: Variant in values:
		if not value is String:
			return {"ok": false, "values": []}
		var text := (value as String).strip_edges()
		if (
			text.is_empty()
			or text != value
			or normalized.has(text)
		):
			return {"ok": false, "values": []}
		normalized.append(text)
	normalized.sort()
	return {"ok": true, "values": normalized}


func _has_exact_fields(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size():
		return false
	for field_value: Variant in expected:
		if not field_value is String or not value.has(field_value):
			return false
	return true


func _safe_identifier(value: String) -> bool:
	if value.is_empty() or value == "." or value == "..":
		return false
	for character in value:
		var code := character.unicode_at(0)
		if not (
			(code >= 48 and code <= 57)
			or (code >= 65 and code <= 90)
			or (code >= 97 and code <= 122)
			or character == "_"
			or character == "-"
		):
			return false
	return true


func _transaction_failure_stage(record: Dictionary) -> String:
	var payload_value: Variant = record.get("payload")
	if not payload_value is Dictionary:
		return ""
	var payload := payload_value as Dictionary
	# The save journal keeps player-safe diagnostics beside the stage. Catalog
	# discovery only needs the stage classification and must not reject a valid
	# failed attempt because errorCode/errors are also present.
	if not payload.has("stage"):
		return ""
	return _required_string(payload.get("stage"))


func _integer_or(value: Variant, fallback: int) -> int:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return fallback
	var number := float(value)
	if (
		not is_finite(number)
		or number != floor(number)
		or number < -MAX_SAFE_INTEGER
		or number > MAX_SAFE_INTEGER
	):
		return fallback
	return int(number)


func _is_integer_number(value: Variant) -> bool:
	return (
		typeof(value) in [TYPE_INT, TYPE_FLOAT]
		and is_finite(float(value))
		and float(value) == floor(float(value))
	)


func _required_string(value: Variant) -> String:
	if not value is String:
		return ""
	var text := value as String
	return text if text == text.strip_edges() else ""


func _saved_at_sort_value(text: String) -> float:
	if not TownSaveScalars.is_saved_at(text):
		return -INF
	var result := float(
		Time.get_unix_time_from_datetime_string(text.substr(0, 19)),
	)
	if text.length() != 25:
		return result
	var offset_seconds := (
		int(text.substr(20, 2)) * 3600
		+ int(text.substr(23, 2)) * 60
	)
	return result - offset_seconds if text[19] == "+" else result + offset_seconds


func _string_or_empty(value: Variant) -> String:
	return value as String if value is String else ""


func _string_or(value: Variant, fallback: String) -> String:
	return value as String if value is String else fallback


func _store_failure(result: Dictionary) -> Dictionary:
	var error_code := _string_or(
		result.get("errorCode"),
		"SESSION_SAVE_STORE_FAILED",
	)
	if error_code.is_empty():
		error_code = "SESSION_SAVE_STORE_FAILED"
	var retryable_value: Variant = result.get("retryable")
	return _failure(
		error_code,
		retryable_value as bool if retryable_value is bool else false,
		{"storeFailure": true},
	)


func _is_corrupt_reference_failure(error_code: String) -> bool:
	return error_code in [
		"SESSION_SAVE_REFERENCE_INVALID",
		"SESSION_SAVE_REFERENCE_NOT_FOUND",
		"SESSION_SAVE_REFERENCE_HASH_MISMATCH",
		"SESSION_SAVE_STORE_JSON_INVALID",
	]


func _success() -> Dictionary:
	return {"ok": true, "errorCode": "", "retryable": false}


func _failure(
	error_code: String,
	retryable: bool,
	meta: Dictionary = {},
) -> Dictionary:
	return {
		"ok": false,
		"errorCode": error_code,
		"retryable": retryable,
		"meta": meta.duplicate(true),
	}
