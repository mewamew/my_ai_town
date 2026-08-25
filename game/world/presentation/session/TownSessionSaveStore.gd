class_name TownSessionSaveStore
extends RefCounted


const RESULT_SHAPES := preload(
	"res://world/contract/TownWorldResultShapes.gd"
)
const MANIFEST := preload(
	"res://world/presentation/session/TownSessionSaveManifest.gd"
)
const DEFAULT_ROOT := "user://town_session_saves"
const TEST_ROOT := "user://tests/town_session_saves"
const MAX_SAFE_INTEGER := 9007199254740991
const MAX_SAFE_INTEGER_PADDED := "00009007199254740991"
const CREATE_CLAIM_RETRY_LIMIT := 10000
const CREATE_CLAIM_RETRY_DELAY_USEC := 1000
const EPHEMERAL_CLAIM_LIVENESS_GRACE_MSEC := 250
const CLAIM_PATH_TOKEN_LENGTH := 24
const EPHEMERAL_CLAIM_KEY_LENGTH := 24
const EPHEMERAL_CLAIM_ROOT := "_claims"
const WORLD_LOG_SEGMENT_RECORD_LIMIT := 256
const SLOT_LEASE_ROOT := "slot_leases"
const SLOT_ARCHIVE_CLAIM := "archive.claim"
const SLOT_ARCHIVE_PENDING := "archive.pending"
const SLOT_TRANSACTION_ROOT := "transactions"
const EPHEMERAL_CLAIM_OWNER_V1_FIELDS: Array[String] = [
	"schema",
	"schema_version",
	"claim_path_sha256",
	"owner_pid",
	"owner_token",
	"created_unix_msec",
]
const EPHEMERAL_CLAIM_OWNER_FIELDS: Array[String] = [
	"schema",
	"schema_version",
	"claim_path_sha256",
	"owner_pid",
	"process_start_sha256",
	"owner_token",
	"created_unix_msec",
]
const REVISION_ALLOCATION_FIELDS: Array[String] = [
	"schema",
	"schema_version",
	"context",
]
const ALLOCATION_FIELDS: Array[String] = [
	"schema",
	"schema_version",
	"kind",
	"intent_id",
	"context",
]
const RECORD_FIELDS: Array[String] = [
	"schema",
	"schema_version",
	"kind",
	"intent_id",
	"state",
	"order",
	"context",
	"payload",
]
const SAVE_STAGES: Array[String] = TownSaveJournalStates.SAVE_STAGES
const RESTORE_STAGES: Array[String] = TownSaveJournalStates.RESTORE_STAGES
const STAGE_ORDER = TownSaveJournalStates.STAGE_ORDER
const SAVE_TRANSITIONS = TownSaveJournalStates.SAVE_TRANSITIONS
const RESTORE_TRANSITIONS = TownSaveJournalStates.RESTORE_TRANSITIONS
const SAVE_TRANSACTION_FAILED_STAGES: Array[String] = TownSaveJournalStates.SAVE_TRANSACTION_FAILED_STAGES
const RESTORE_TRANSACTION_FAILED_STAGES: Array[String] = TownSaveJournalStates.RESTORE_TRANSACTION_FAILED_STAGES

var _root := DEFAULT_ROOT
var _owned_slot_transactions: Dictionary = {}
var _owned_slot_archives: Dictionary = {}
static var _current_process_start_sha256 := ""


func configure_test_root(path_value: Variant) -> Dictionary:
	if _root != DEFAULT_ROOT:
		return _failure("SESSION_SAVE_STORE_ALREADY_CONFIGURED", false)
	if not path_value is String:
		return _failure("SESSION_SAVE_STORE_PATH_INVALID", false)
	var path := path_value as String
	if (
		path.is_empty()
		or path != path.strip_edges()
		or path.ends_with("/")
		or not path.begins_with("%s/" % TEST_ROOT)
		or path.contains("..")
		or path.contains("\\")
		or path.trim_prefix("%s/" % TEST_ROOT).contains("//")
	):
		return _failure("SESSION_SAVE_STORE_PATH_INVALID", false)
	_root = path
	return _success()


func create_isolated_peer() -> RefCounted:
	var peer: RefCounted = TownSessionSaveStore.new()
	peer.set("_root", _root)
	return peer


func cleanup_test_root() -> Dictionary:
	if not _root.begins_with("%s/" % TEST_ROOT):
		return _failure("SESSION_SAVE_STORE_PATH_INVALID", false)
	var error := _remove_tree(_root)
	return (
		_success()
		if error == OK
		else _failure("SESSION_SAVE_STORE_CLEANUP_FAILED", true)
	)


func begin_slot_transaction(slot_id_value: Variant) -> Dictionary:
	var slot_check := _validated_slot_id(slot_id_value)
	if slot_check.get("ok") != true:
		return slot_check
	var slot_id := String(slot_check.get("slotId", ""))
	var legacy_state := check_legacy_slot_ephemeral_state(slot_id)
	if legacy_state.get("ok") != true:
		return legacy_state
	var archive_claim_path := _slot_archive_claim_path(slot_id)
	var archive_claim_state := _recoverable_claim_activity(archive_claim_path)
	archive_claim_state = _recover_unpublished_archive_claim_if_safe(
		slot_id,
		archive_claim_path,
		archive_claim_state,
	)
	if archive_claim_state.get("ok") != true:
		return archive_claim_state
	if (
		archive_claim_state.get("active") == true
		or DirAccess.dir_exists_absolute(
			_absolute(_slot_archive_pending_path(slot_id)),
		)
	):
		return _failure("SESSION_SAVE_SLOT_BUSY", true)
	var transaction_root := _slot_transaction_root(slot_id)
	var create_error := DirAccess.make_dir_recursive_absolute(
		_absolute(transaction_root),
	)
	if create_error != OK:
		return _failure("SESSION_SAVE_STORE_WRITE_FAILED", true)
	var lease_seed := _new_ephemeral_claim_owner(archive_claim_path)
	var lease_token := String(lease_seed.get("owner_token", ""))
	var claim_path := _join(
		transaction_root,
		"%s.claim" % lease_token.left(CLAIM_PATH_TOKEN_LENGTH),
	)
	var acquired := _acquire_recoverable_directory_claim(claim_path)
	if acquired.get("ok") != true:
		return acquired
	var claim_owner := (
		acquired.get("claimOwner", {}) as Dictionary
	).duplicate(true)
	archive_claim_state = _recoverable_claim_activity(archive_claim_path)
	archive_claim_state = _recover_unpublished_archive_claim_if_safe(
		slot_id,
		archive_claim_path,
		archive_claim_state,
	)
	if (
		archive_claim_state.get("ok") != true
		or archive_claim_state.get("active") == true
		or DirAccess.dir_exists_absolute(
			_absolute(_slot_archive_pending_path(slot_id)),
		)
	):
		var released := _release_owned_directory_claim(
			claim_path,
			claim_owner,
		)
		if released.get("ok") != true:
			return released
		if archive_claim_state.get("ok") != true:
			return archive_claim_state
		return _failure("SESSION_SAVE_SLOT_BUSY", true)
	_owned_slot_transactions[lease_token] = {
		"slotId": slot_id,
		"claimPath": claim_path,
		"claimOwner": claim_owner,
	}
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"slotId": slot_id,
		"leaseToken": lease_token,
	}


func end_slot_transaction(lease_token_value: Variant) -> Dictionary:
	return _release_slot_lease(
		lease_token_value,
		_owned_slot_transactions,
	)


func begin_slot_archive(slot_id_value: Variant) -> Dictionary:
	var slot_check := _validated_slot_id(slot_id_value)
	if slot_check.get("ok") != true:
		return slot_check
	var slot_id := String(slot_check.get("slotId", ""))
	var legacy_state := check_legacy_slot_ephemeral_state(slot_id)
	if legacy_state.get("ok") != true:
		return legacy_state
	var claim_path := _slot_archive_claim_path(slot_id)
	var create_error := DirAccess.make_dir_recursive_absolute(
		_absolute(_slot_lease_root(slot_id)),
	)
	if create_error != OK:
		return _failure("SESSION_SAVE_STORE_WRITE_FAILED", true)
	var archive_claim_state := _recoverable_claim_activity(claim_path)
	archive_claim_state = _recover_unpublished_archive_claim_if_safe(
		slot_id,
		claim_path,
		archive_claim_state,
	)
	if archive_claim_state.get("ok") != true:
		return archive_claim_state
	if archive_claim_state.get("active") == true:
		return _failure("SESSION_SAVE_SLOT_BUSY", true)
	var acquired := _acquire_recoverable_directory_claim(
		claim_path,
		"",
		{},
		1,
	)
	if acquired.get("ok") != true:
		archive_claim_state = _recoverable_claim_activity(claim_path)
		if archive_claim_state.get("ok") != true:
			return archive_claim_state
		if archive_claim_state.get("active") == true:
			return _failure("SESSION_SAVE_SLOT_BUSY", true)
		return acquired
	var claim_owner := (
		acquired.get("claimOwner", {}) as Dictionary
	).duplicate(true)
	var transaction_root := _slot_transaction_root(slot_id)
	var active_transaction := false
	var transaction_root_exists := DirAccess.dir_exists_absolute(
		_absolute(transaction_root),
	)
	var directory := _open_slot_transaction_directory(transaction_root)
	if transaction_root_exists and directory == null:
		var read_failure_release := _release_owned_directory_claim(
			claim_path,
			claim_owner,
		)
		return (
			_failure("SESSION_SAVE_STORE_READ_FAILED", true)
			if read_failure_release.get("ok") == true
			else read_failure_release
		)
	if directory != null:
		for directory_name: String in directory.get_directories():
			if not directory_name.ends_with(".claim"):
				continue
			var transaction_claim_state := _recoverable_claim_activity(
				_join(transaction_root, directory_name),
			)
			if transaction_claim_state.get("ok") != true:
				var failed_scan_release := _release_owned_directory_claim(
					claim_path,
					claim_owner,
				)
				return (
					transaction_claim_state
					if failed_scan_release.get("ok") == true
					else failed_scan_release
				)
			if transaction_claim_state.get("active") == true:
				active_transaction = true
				break
	if active_transaction:
		var released := _release_owned_directory_claim(
			claim_path,
			claim_owner,
		)
		return (
			_failure("SESSION_SAVE_SLOT_BUSY", true)
			if released.get("ok") == true
			else released
		)
	var lease_token := String(claim_owner.get("owner_token", ""))
	_owned_slot_archives[lease_token] = {
		"slotId": slot_id,
		"claimPath": claim_path,
		"claimOwner": claim_owner,
	}
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"slotId": slot_id,
		"leaseToken": lease_token,
	}


func end_slot_archive(lease_token_value: Variant) -> Dictionary:
	return _release_slot_lease(
		lease_token_value,
		_owned_slot_archives,
	)


func recover_unpublished_slot_lease_residue(slot_id_value: Variant) -> Dictionary:
	var slot_check := _validated_slot_id(slot_id_value)
	if slot_check.get("ok") != true:
		return slot_check
	var slot_id := String(slot_check.get("slotId", ""))
	var published := list_published(slot_id)
	if published.get("ok") != true:
		return published
	var manifests_value: Variant = published.get("manifests", [])
	if not manifests_value is Array:
		return _failure("SESSION_SAVE_STORE_READ_FAILED", true)
	if not (manifests_value as Array).is_empty():
		return _failure("SESSION_SAVE_PUBLISHED_STATE_PRESENT", false)
	var lease_root := _slot_lease_root(slot_id)
	var pending_path := _slot_archive_pending_path(slot_id)
	if DirAccess.dir_exists_absolute(_absolute(pending_path)):
		return _failure("SESSION_SAVE_SLOT_BUSY", true)
	if not DirAccess.dir_exists_absolute(_absolute(lease_root)):
		return _success()
	var claim_path := _slot_archive_claim_path(slot_id)
	if DirAccess.dir_exists_absolute(_absolute(claim_path)):
		var owner := _read_owned_claim_owner(claim_path)
		if owner.get("ok") == true and _ephemeral_claim_owner_is_alive(
			owner.get("claimOwner", {}) as Dictionary,
		):
			return _failure("SESSION_SAVE_SLOT_BUSY", true)
		var remove_error := _remove_tree(claim_path)
		if remove_error != OK:
			return _failure("SESSION_SAVE_STORE_WRITE_FAILED", true)
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"changed": true,
	}


func _recover_unpublished_archive_claim_if_safe(
	slot_id: String,
	claim_path: String,
	claim_state: Dictionary,
) -> Dictionary:
	if claim_state.get("ok") == true:
		return claim_state
	# A transient owner.json read is the gap between two atomic claim
	# generations. Retrying is safe; deleting it would be able to race a live
	# transaction. Only a structurally invalid owner record can use the guarded
	# no-published-revision cleanup below.
	if claim_state.get("claimReadTransient") == true:
		return claim_state
	if claim_state.get("errorCode") != "SESSION_SAVE_STORE_JSON_INVALID":
		return claim_state
	var residue := recover_unpublished_slot_lease_residue(slot_id)
	if residue.get("ok") != true:
		return claim_state
	return _recoverable_claim_activity(claim_path)


func mark_slot_archive_pending(lease_token_value: Variant) -> Dictionary:
	var owned := _owned_archive_lease(lease_token_value)
	if owned.get("ok") != true:
		return owned
	var pending_path := _slot_archive_pending_path(
		String(owned.get("slotId", "")),
	)
	if DirAccess.dir_exists_absolute(_absolute(pending_path)):
		return _success()
	var create_error := DirAccess.make_dir_absolute(_absolute(pending_path))
	return (
		_success()
		if create_error == OK
		else _failure("SESSION_SAVE_STORE_WRITE_FAILED", true)
	)


func clear_slot_archive_pending(lease_token_value: Variant) -> Dictionary:
	var owned := _owned_archive_lease(lease_token_value)
	if owned.get("ok") != true:
		return owned
	var pending_path := _slot_archive_pending_path(
		String(owned.get("slotId", "")),
	)
	if not DirAccess.dir_exists_absolute(_absolute(pending_path)):
		return _success()
	var remove_error := DirAccess.remove_absolute(_absolute(pending_path))
	return (
		_success()
		if remove_error == OK
		else _failure("SESSION_SAVE_STORE_WRITE_FAILED", true)
	)


func reserve_revision(
	slot_id_value: Variant,
	session_id_value: Variant,
) -> Dictionary:
	var context_check := MANIFEST.validate_context({
		"slot_id": slot_id_value,
		"session_id": session_id_value,
		"save_revision": 0,
	}) as Dictionary
	if context_check.get("ok") != true:
		return context_check
	var normalized := context_check.get("context", {}) as Dictionary
	var legacy_state := check_legacy_slot_ephemeral_state(
		String(normalized.get("slot_id", "")),
	)
	if legacy_state.get("ok") != true:
		return legacy_state
	var allocation_root := _join(
		_slot_root(String(normalized.get("slot_id", ""))),
		"allocations",
	)
	var create_error := DirAccess.make_dir_recursive_absolute(_absolute(allocation_root))
	if create_error != OK:
		return _failure("SESSION_SAVE_STORE_WRITE_FAILED", true)
	var next_revision := _next_revision_candidate(allocation_root)
	if next_revision < 0:
		return _failure("SESSION_SAVE_REVISION_EXHAUSTED", false)
	while next_revision <= MAX_SAFE_INTEGER:
		var claim_path := _join(
			allocation_root,
			"%020d.claim" % next_revision,
		)
		var claim_error := DirAccess.make_dir_absolute(_absolute(claim_path))
		if claim_error != OK:
			var refreshed_revision := _next_revision_candidate(allocation_root)
			if refreshed_revision < 0:
				return _failure("SESSION_SAVE_REVISION_EXHAUSTED", false)
			if refreshed_revision > next_revision:
				next_revision = refreshed_revision
				continue
			if claim_error == ERR_ALREADY_EXISTS:
				OS.delay_usec(1000)
				continue
			return _failure("SESSION_SAVE_STORE_WRITE_FAILED", true)
		var context := {
			"slot_id": String(normalized.get("slot_id", "")),
			"session_id": String(normalized.get("session_id", "")),
			"save_revision": next_revision,
		}
		var allocation_path := _join(
			allocation_root,
			"%020d.json" % next_revision,
		)
		if FileAccess.file_exists(allocation_path):
			DirAccess.remove_absolute(_absolute(claim_path))
			next_revision = _next_revision_candidate(allocation_root)
			if next_revision < 0:
				return _failure("SESSION_SAVE_REVISION_EXHAUSTED", false)
			continue
		var written := _atomic_create_json(allocation_path, {
			"schema": "town-session-save-allocation",
			"schema_version": 1,
			"context": context,
		})
		if written.get("ok") != true:
			return written
		DirAccess.remove_absolute(_absolute(claim_path))
		return {
			"ok": true,
			"errorCode": "",
			"retryable": false,
			"context": context,
		}
	return _failure("SESSION_SAVE_REVISION_EXHAUSTED", false)


func discard_unpublished_revision(context_value: Variant) -> Dictionary:
	var checked := MANIFEST.validate_context(context_value)
	if checked.get("ok") != true:
		return checked
	var context := (
		checked.get("context", {}) as Dictionary
	).duplicate(true)
	if FileAccess.file_exists(_manifest_path(context)):
		return _failure("SESSION_SAVE_REVISION_ALREADY_PUBLISHED", false)
	var allocation_path := _join(
		_slot_root(String(context.get("slot_id", ""))),
		"allocations/%020d.json" % int(context.get("save_revision", 0)),
	)
	if (
		FileAccess.file_exists(allocation_path)
		and not _revision_allocation_matches(context)
	):
		return _failure("SESSION_SAVE_REVISION_ALLOCATION_MISMATCH", false)
	var revision_root := _revision_root(context)
	if DirAccess.dir_exists_absolute(_absolute(revision_root)):
		var remove_error := _remove_tree(revision_root)
		if remove_error != OK:
			return _failure("SESSION_SAVE_STORE_WRITE_FAILED", true)
	if FileAccess.file_exists(allocation_path):
		var allocation_error := DirAccess.remove_absolute(
			_absolute(allocation_path),
		)
		if allocation_error != OK:
			return _failure("SESSION_SAVE_STORE_WRITE_FAILED", true)
	return _success()


func check_legacy_slot_ephemeral_state(slot_id_value: Variant) -> Dictionary:
	var slot_check := _validated_slot_id(slot_id_value)
	if slot_check.get("ok") != true:
		return slot_check
	var slot_id := String(slot_check.get("slotId", ""))
	var legacy_root := _legacy_slot_lease_root(slot_id)
	if legacy_root == _slot_lease_root(slot_id):
		return _success()
	if not DirAccess.dir_exists_absolute(_absolute(legacy_root)):
		var absent := _success()
		absent["legacyState"] = "absent"
		return absent

	var archive_claim := _check_legacy_claim_activity(
		legacy_root,
		SLOT_ARCHIVE_CLAIM,
	)
	if archive_claim.get("ok") != true:
		return archive_claim
	if archive_claim.get("active") == true:
		return _failure("SESSION_SAVE_SLOT_BUSY", true)

	var transaction_root := _join(legacy_root, SLOT_TRANSACTION_ROOT)
	if DirAccess.dir_exists_absolute(_absolute(transaction_root)):
		var transactions := DirAccess.open(transaction_root)
		if transactions == null:
			return _failure("SESSION_SAVE_STORE_READ_FAILED", true)
		transactions.include_hidden = true
		var transaction_directories := transactions.get_directories()
		transactions = null
		var transaction_claims: Array[String] = []
		for directory_name: String in transaction_directories:
			var claim_name := directory_name
			if directory_name.contains(".claim.candidate-"):
				claim_name = directory_name.get_slice(".candidate-", 0)
			if not claim_name.ends_with(".claim"):
				continue
			if not transaction_claims.has(claim_name):
				transaction_claims.append(claim_name)
		for claim_name: String in transaction_claims:
			var claim_result := _check_legacy_claim_activity(
				transaction_root,
				claim_name,
			)
			if claim_result.get("ok") != true:
				return claim_result
			if claim_result.get("active") == true:
				return _failure("SESSION_SAVE_SLOT_BUSY", true)
	var checked := _success()
	checked["legacyState"] = "observed"
	return checked


func write_world_candidate(
	context_value: Variant,
	snapshot_value: Variant,
	session_config_value: Variant,
	world_log_snapshot_value: Variant = null,
) -> Dictionary:
	var checked := MANIFEST.validate_context(context_value)
	if checked.get("ok") != true:
		return checked
	if not snapshot_value is Dictionary or not session_config_value is Dictionary:
		return _failure("SESSION_SAVE_CANDIDATE_INVALID", false)
	var snapshot := snapshot_value as Dictionary
	var session_config := session_config_value as Dictionary
	var has_world_log := world_log_snapshot_value is Dictionary
	var world_log_snapshot := (
		world_log_snapshot_value as Dictionary
		if has_world_log
		else {}
	)
	if (
		not _json_safe(snapshot)
		or not _json_safe(session_config)
		or (has_world_log and not _json_safe(world_log_snapshot))
	):
		return _failure("SESSION_SAVE_CANDIDATE_INVALID", false)
	var normalized := checked.get("context", {}) as Dictionary
	if not _revision_allocation_matches(normalized):
		return _failure("SESSION_SAVE_CANDIDATE_INVALID", false)
	var revision_root := _revision_root(normalized)
	var create_error := DirAccess.make_dir_recursive_absolute(_absolute(revision_root))
	if create_error != OK:
		return _failure("SESSION_SAVE_STORE_WRITE_FAILED", true)
	var snapshot_ref := _reference(
		_join(revision_root, "world_snapshot.json"),
	)
	var config_ref := _reference(
		_join(revision_root, "session_config.json"),
	)
	var snapshot_written := _atomic_create_json(
		_resolve_reference(snapshot_ref),
		snapshot,
	)
	if snapshot_written.get("ok") != true:
		return snapshot_written
	var config_written := _atomic_create_json(
		_resolve_reference(config_ref),
		session_config,
	)
	if config_written.get("ok") != true:
		return config_written
	var result := {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"snapshotRef": snapshot_ref,
		"snapshotSha256": String(snapshot_written.get("sha256", "")),
		"sessionConfigRef": config_ref,
		"sessionConfigSha256": String(config_written.get("sha256", "")),
	}
	if has_world_log:
		var world_log_written := _write_world_log_candidate(
			revision_root,
			world_log_snapshot,
		)
		if world_log_written.get("ok") != true:
			return world_log_written
		result["worldLogSnapshotRef"] = String(
			world_log_written.get("snapshotRef", ""),
		)
		result["worldLogSnapshotSha256"] = String(
			world_log_written.get("snapshotSha256", ""),
		)
	return result


func _write_world_log_candidate(
	revision_root: String,
	snapshot: Dictionary,
) -> Dictionary:
	var records_value: Variant = snapshot.get("records")
	if (
		String(snapshot.get("schema", "")) != "town-world-log-snapshot"
		or int(snapshot.get("schemaVersion", 0)) != 1
		or not records_value is Array
		or not snapshot.get("readState", {}) is Dictionary
	):
		return _failure("SESSION_SAVE_CANDIDATE_INVALID", false)
	var records := records_value as Array
	if int(snapshot.get("maxSequence", -1)) != records.size():
		return _failure("SESSION_SAVE_CANDIDATE_INVALID", false)
	var storage_snapshot := snapshot.duplicate(true)
	storage_snapshot.erase("records")
	storage_snapshot["storageSchemaVersion"] = 1
	storage_snapshot["segments"] = []
	var segment_descriptors := storage_snapshot["segments"] as Array
	var expected_sequence := 1
	for start_index in range(
		0,
		records.size(),
		WORLD_LOG_SEGMENT_RECORD_LIMIT,
	):
		var segment_records: Array = []
		var end_index := mini(
			records.size(),
			start_index + WORLD_LOG_SEGMENT_RECORD_LIMIT,
		)
		for index in range(start_index, end_index):
			var record_value: Variant = records[index]
			if (
				not record_value is Dictionary
				or int((record_value as Dictionary).get("sequence", 0))
				!= expected_sequence
			):
				return _failure("SESSION_SAVE_CANDIDATE_INVALID", false)
			segment_records.append((record_value as Dictionary).duplicate(true))
			expected_sequence += 1
		var segment := {
			"schema": "town-world-log-segment",
			"schemaVersion": 1,
			"timelineId": String(snapshot.get("timelineId", "")),
			"startSequence": start_index + 1,
			"endSequence": end_index,
			"records": segment_records,
		}
		var segment_sha256 := JSON.stringify(segment, "\t").sha256_text()
		var segment_ref := "world_log_segments/%s.json" % segment_sha256
		var segment_written := _atomic_create_json(
			_resolve_reference(segment_ref),
			segment,
		)
		if (
			segment_written.get("ok") != true
			or String(segment_written.get("sha256", "")) != segment_sha256
		):
			return _failure("SESSION_SAVE_STORE_WRITE_FAILED", true)
		segment_descriptors.append({
			"segmentRef": segment_ref,
			"segmentSha256": segment_sha256,
			"startSequence": start_index + 1,
			"endSequence": end_index,
			"recordCount": segment_records.size(),
		})
	var snapshot_ref := _reference(
		_join(revision_root, "world_log_snapshot.json"),
	)
	var snapshot_written := _atomic_create_json(
		_resolve_reference(snapshot_ref),
		storage_snapshot,
	)
	if snapshot_written.get("ok") != true:
		return snapshot_written
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"snapshotRef": snapshot_ref,
		"snapshotSha256": String(snapshot_written.get("sha256", "")),
		"segmentCount": segment_descriptors.size(),
	}


func begin_intent(context_value: Variant, kind_value: Variant) -> Dictionary:
	var checked := MANIFEST.validate_context(context_value)
	if checked.get("ok") != true:
		return checked
	if not kind_value is String:
		return _failure("SESSION_SAVE_JOURNAL_STATE_INVALID", false)
	var kind := kind_value as String
	if not ["save", "restore"].has(kind):
		return _failure("SESSION_SAVE_JOURNAL_STATE_INVALID", false)
	var normalized := checked.get("context", {}) as Dictionary
	if not _revision_allocation_matches(normalized):
		return _failure("SESSION_SAVE_JOURNAL_STATE_INVALID", false)
	var revision_root := _intent_revision_root(normalized, kind)
	var create_error := DirAccess.make_dir_recursive_absolute(
		_absolute(revision_root),
	)
	if create_error != OK:
		return _failure("SESSION_SAVE_STORE_WRITE_FAILED", true)
	var intent_id := "save"
	if kind == "save":
		var save_root := _intent_attempt_root(normalized, kind, intent_id)
		var save_allocation := _atomic_create_json(
			_join(save_root, "000_allocation.json"),
			_intent_allocation(normalized, kind, intent_id),
		)
		if save_allocation.get("ok") != true:
			return save_allocation
		return _intent_allocation_success(intent_id)
	var claim_root := _restore_intent_claim_root(normalized)
	var claim_root_error := DirAccess.make_dir_recursive_absolute(
		_absolute(claim_root),
	)
	if claim_root_error != OK:
		return _failure("SESSION_SAVE_STORE_WRITE_FAILED", true)
	var candidate := _next_restore_attempt_candidate(normalized)
	if candidate.get("ok") != true:
		return candidate
	var next_attempt := int(candidate.get("attempt", 0))
	while next_attempt <= MAX_SAFE_INTEGER:
		intent_id = "attempt-%020d" % next_attempt
		var claim_path := _join(claim_root, "%s.claim" % intent_id)
		var claim_error := DirAccess.make_dir_absolute(_absolute(claim_path))
		if claim_error != OK:
			var refreshed := _next_restore_attempt_candidate(normalized)
			if refreshed.get("ok") != true:
				return refreshed
			var refreshed_attempt := int(refreshed.get("attempt", 0))
			if refreshed_attempt > next_attempt:
				next_attempt = refreshed_attempt
				continue
			if claim_error == ERR_ALREADY_EXISTS:
				OS.delay_usec(1000)
				continue
			return _failure("SESSION_SAVE_STORE_WRITE_FAILED", true)
		var intent_root := _intent_attempt_root(
			normalized,
			kind,
			intent_id,
		)
		if DirAccess.dir_exists_absolute(_absolute(intent_root)):
			DirAccess.remove_absolute(_absolute(claim_path))
			var existing_refreshed := _next_restore_attempt_candidate(
				normalized,
			)
			if existing_refreshed.get("ok") != true:
				return existing_refreshed
			next_attempt = int(existing_refreshed.get("attempt", 0))
			continue
		var allocated := _atomic_create_json(
			_join(claim_path, "000_allocation.json"),
			_intent_allocation(normalized, kind, intent_id),
		)
		if allocated.get("ok") != true:
			return allocated
		var publish_error := DirAccess.rename_absolute(
			_absolute(claim_path),
			_absolute(intent_root),
		)
		if publish_error != OK:
			return _failure("SESSION_SAVE_STORE_WRITE_FAILED", true)
		return _intent_allocation_success(intent_id)
	return _failure("SESSION_SAVE_JOURNAL_STATE_INVALID", false)


func write_intent_stage(
	context_value: Variant,
	kind_value: Variant,
	intent_id_value: Variant,
	stage_value: Variant,
	payload_value: Variant = {},
) -> Dictionary:
	var checked := MANIFEST.validate_context(context_value)
	if checked.get("ok") != true:
		return checked
	if (
		not kind_value is String
		or not intent_id_value is String
		or not stage_value is String
		or not payload_value is Dictionary
	):
		return _failure("SESSION_SAVE_JOURNAL_STATE_INVALID", false)
	var kind := kind_value as String
	var intent_id := intent_id_value as String
	var stage := stage_value as String
	var payload := payload_value as Dictionary
	if (
		not ["save", "restore"].has(kind)
		or not _valid_stage_for_kind(kind, stage)
		or not _valid_intent_id(kind, intent_id)
	):
		return _failure("SESSION_SAVE_JOURNAL_STATE_INVALID", false)
	if not _json_safe(payload):
		return _failure("SESSION_SAVE_JOURNAL_STATE_INVALID", false)
	if not _valid_payload_for_stage(kind, stage, payload):
		return _failure("SESSION_SAVE_JOURNAL_STATE_INVALID", false)
	var normalized := checked.get("context", {}) as Dictionary
	var intent_root := _intent_attempt_root(
		normalized,
		kind,
		intent_id,
	)
	if not FileAccess.file_exists(_join(intent_root, "000_allocation.json")):
		return _failure("SESSION_SAVE_JOURNAL_NOT_FOUND", false)
	var create_error := DirAccess.make_dir_recursive_absolute(_absolute(intent_root))
	if create_error != OK:
		return _failure("SESSION_SAVE_STORE_WRITE_FAILED", true)
	var transition_claim_path := _ephemeral_claim_path(
		"transition",
		intent_root,
	)
	var transition_claim := _acquire_recoverable_directory_claim(
		transition_claim_path,
	)
	if transition_claim.get("ok") != true:
		return transition_claim
	var result := _write_intent_stage_claimed(
		normalized,
		kind,
		intent_id,
		stage,
		payload,
		intent_root,
	)
	return _release_owned_claim_and_return(
		transition_claim_path,
		transition_claim.get("claimOwner", {}) as Dictionary,
		result,
	)


func _write_intent_stage_claimed(
	context: Dictionary,
	kind: String,
	intent_id: String,
	stage: String,
	payload: Dictionary,
	intent_root: String,
) -> Dictionary:
	var current := read_latest_intent(context, kind, intent_id)
	if (
		current.get("ok") != true
		and current.get("errorCode") != "SESSION_SAVE_JOURNAL_NOT_FOUND"
	):
		return current
	if (
		current.get("ok") != true
		and stage != _initial_stage(kind)
	):
		return _failure("SESSION_SAVE_JOURNAL_STATE_INVALID", false)
	if (
		current.get("ok") == true
		and not _transition_is_valid(
			kind,
			String(current.get("state", "")),
			stage,
		)
	):
		return _failure("SESSION_SAVE_JOURNAL_STATE_INVALID", false)
	var record := {
		"schema": "town-session-save-intent",
		"schema_version": 1,
		"kind": kind,
		"intent_id": intent_id,
		"state": stage,
		"order": int(STAGE_ORDER.get(stage, 0)),
		"context": context.duplicate(true),
		"payload": payload.duplicate(true),
	}
	var path := _join(
		intent_root,
		"%03d_%s.json" % [int(STAGE_ORDER.get(stage, 0)), stage],
	)
	var written := _atomic_create_json(path, record)
	if written.get("ok") != true:
		return written
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"record": record,
	}


func read_latest_intent(
	context_value: Variant,
	kind_value: Variant,
	intent_id_value: Variant = "",
) -> Dictionary:
	var checked := MANIFEST.validate_context(context_value)
	if checked.get("ok") != true:
		return checked
	if not kind_value is String or not intent_id_value is String:
		return _failure("SESSION_SAVE_JOURNAL_STATE_INVALID", false)
	var kind := kind_value as String
	var intent_id := intent_id_value as String
	if not ["save", "restore"].has(kind):
		return _failure("SESSION_SAVE_JOURNAL_STATE_INVALID", false)
	var normalized := checked.get("context", {}) as Dictionary
	var normalized_intent_id := intent_id
	if normalized_intent_id.is_empty():
		var revision_root := _intent_revision_root(normalized, kind)
		var revision_directory := DirAccess.open(revision_root)
		if revision_directory == null:
			return _failure("SESSION_SAVE_JOURNAL_NOT_FOUND", false)
		var attempts := revision_directory.get_directories()
		for candidate in attempts:
			if not _valid_intent_id(kind, candidate):
				return _failure("SESSION_SAVE_JOURNAL_STATE_INVALID", false)
		attempts.sort()
		if attempts.is_empty():
			return _failure("SESSION_SAVE_JOURNAL_NOT_FOUND", false)
		normalized_intent_id = attempts[-1]
	if not _valid_intent_id(kind, normalized_intent_id):
		return _failure("SESSION_SAVE_JOURNAL_STATE_INVALID", false)
	var intent_root := _intent_attempt_root(
		normalized,
		kind,
		normalized_intent_id,
	)
	var allocation := _read_json(_join(intent_root, "000_allocation.json"))
	if allocation.get("ok") != true:
		return allocation
	if not _valid_allocation_record(
		allocation.get("value"),
		normalized,
		kind,
		normalized_intent_id,
	):
		return _failure("SESSION_SAVE_JOURNAL_STATE_INVALID", false)
	var directory := DirAccess.open(intent_root)
	if directory == null:
		return _failure("SESSION_SAVE_JOURNAL_NOT_FOUND", false)
	var paths: Array[String] = []
	for file_name in directory.get_files():
		if file_name.ends_with(".json") and not file_name == "000_allocation.json":
			paths.append(_join(intent_root, file_name))
	paths.sort()
	if paths.is_empty():
		return _failure("SESSION_SAVE_JOURNAL_NOT_FOUND", false)
	var record: Dictionary = {}
	var previous_state := ""
	for index in paths.size():
		var path := paths[index]
		var loaded := _read_json(path)
		if loaded.get("ok") != true:
			return loaded
		var record_value: Variant = loaded.get("value")
		if not _valid_intent_record(
			record_value,
			normalized,
			kind,
			normalized_intent_id,
			path.get_file(),
		):
			return _failure("SESSION_SAVE_JOURNAL_STATE_INVALID", false)
		record = (record_value as Dictionary).duplicate(true)
		var state := String(record.get("state", ""))
		if index == 0:
			if state != _initial_stage(kind):
				return _failure("SESSION_SAVE_JOURNAL_STATE_INVALID", false)
		elif not _transition_is_valid(kind, previous_state, state):
			return _failure("SESSION_SAVE_JOURNAL_STATE_INVALID", false)
		previous_state = state
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"record": record,
		"state": String(record.get("state", "")),
		"order": int(record.get("order", -1)),
	}


func publish_manifest(manifest_value: Variant) -> Dictionary:
	var validation := MANIFEST.validate(manifest_value)
	if validation.get("ok") != true:
		return validation
	var manifest := manifest_value as Dictionary
	var allocation_context := {
		"slot_id": manifest.get("slot_id"),
		"session_id": manifest.get("session_id"),
		"save_revision": manifest.get("save_revision"),
	}
	if not _revision_allocation_matches(allocation_context):
		return _failure("SESSION_SAVE_MANIFEST_PUBLISH_FAILED", false)
	var components := manifest.get("components", {}) as Dictionary
	var world := components.get("world", {}) as Dictionary
	var snapshot := read_reference(
		world.get("snapshot_ref"),
		world.get("snapshot_sha256"),
	)
	var session_config := read_reference(
		manifest.get("session_config_ref"),
		manifest.get("session_config_sha256"),
	)
	var world_log := {"ok": true}
	if int(manifest.get("schema_version", 0)) >= 3:
		var world_log_component := components.get("world_log", {}) as Dictionary
		world_log = read_world_log_snapshot(
			world_log_component.get("snapshot_ref"),
			world_log_component.get("snapshot_sha256"),
		)
	if (
		snapshot.get("ok") != true
		or session_config.get("ok") != true
		or world_log.get("ok") != true
	):
		return _failure("SESSION_SAVE_MANIFEST_PUBLISH_FAILED", false)
	var path := _manifest_path({
		"slot_id": manifest.get("slot_id"),
		"session_id": manifest.get("session_id"),
		"save_revision": manifest.get("save_revision"),
	})
	var written := _atomic_create_json(path, manifest)
	if written.get("ok") != true:
		return _failure(
			"SESSION_SAVE_MANIFEST_PUBLISH_FAILED",
			bool(written.get("retryable", true)),
		)
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"manifest": manifest.duplicate(true),
	}


func list_published(slot_id_value: Variant) -> Dictionary:
	var slot_check := MANIFEST.validate_slot_id(slot_id_value)
	if slot_check.get("ok") != true:
		return slot_check
	var slot_id := String(slot_check.get("slotId", ""))
	var manifest_root := _join(_slot_root(slot_id), "manifests")
	var directory := DirAccess.open(manifest_root)
	if directory == null:
		return {
			"ok": true,
			"errorCode": "",
			"retryable": false,
			"manifests": [],
			"readOnly": [],
			"invalid": [],
		}
	var manifests: Array[Dictionary] = []
	var read_only: Array[Dictionary] = []
	var invalid: Array[String] = []
	for file_name in directory.get_files():
		if not file_name.ends_with(".json"):
			continue
		var loaded := _read_json(_join(manifest_root, file_name))
		if loaded.get("ok") != true:
			invalid.append(file_name)
			continue
		var manifest := loaded.get("value", {}) as Dictionary
		var revision := _canonical_revision_from_file(file_name)
		var unsupported_versions := MANIFEST.unsupported_version_evidence(manifest)
		if (
			revision >= 1
			and not unsupported_versions.is_empty()
			and String(manifest.get("slot_id", "")) == slot_id
			and int(manifest.get("save_revision", -1)) == revision
		):
			read_only.append({
				"manifest": manifest.duplicate(true),
				"versions": unsupported_versions.duplicate(true),
			})
			continue
		if (
			revision < 1
			or MANIFEST.validate(manifest).get("ok") != true
			or String(manifest.get("slot_id", "")) != slot_id
			or int(manifest.get("save_revision", -1)) != revision
		):
			invalid.append(file_name)
			continue
		manifests.append(manifest.duplicate(true))
	manifests.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left.get("save_revision", 0)) > int(
			right.get("save_revision", 0),
		)
	)
	read_only.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(
			(left.get("manifest", {}) as Dictionary).get("save_revision", 0),
		) > int(
			(right.get("manifest", {}) as Dictionary).get("save_revision", 0),
		)
	)
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"manifests": manifests,
		"readOnly": read_only,
		"invalid": invalid,
	}


func read_reference(
	reference_value: Variant,
	expected_sha256_value: Variant = "",
) -> Dictionary:
	if not reference_value is String or not expected_sha256_value is String:
		return _failure("SESSION_SAVE_REFERENCE_INVALID", false)
	var reference := reference_value as String
	var expected_sha256 := expected_sha256_value as String
	if (
		reference.is_empty()
		or reference != reference.strip_edges()
		or not _valid_reference_shape(reference)
		or expected_sha256 != expected_sha256.strip_edges()
		or (
			not expected_sha256.is_empty()
			and not _is_sha256(expected_sha256)
		)
	):
		return _failure("SESSION_SAVE_REFERENCE_INVALID", false)
	var path := _resolve_reference(reference)
	if path.is_empty():
		return _failure("SESSION_SAVE_REFERENCE_INVALID", false)
	var loaded := _read_json(path)
	if loaded.get("ok") != true:
		return loaded
	var actual_sha256 := _sha256_file(path)
	if (
		not expected_sha256.is_empty()
		and actual_sha256 != expected_sha256
	):
		return _failure("SESSION_SAVE_REFERENCE_HASH_MISMATCH", false)
	loaded["sha256"] = actual_sha256
	return loaded


func read_world_log_snapshot(
	reference_value: Variant,
	expected_sha256_value: Variant = "",
) -> Dictionary:
	var loaded := read_reference(reference_value, expected_sha256_value)
	if loaded.get("ok") != true:
		return loaded
	var value: Variant = loaded.get("value")
	if not value is Dictionary:
		return _failure("SESSION_SAVE_REFERENCE_INVALID", false)
	var storage_snapshot := value as Dictionary
	if not storage_snapshot.has("segments"):
		if not storage_snapshot.get("records") is Array:
			return _failure("SESSION_SAVE_REFERENCE_INVALID", false)
		return loaded
	if (
		String(storage_snapshot.get("schema", ""))
		!= "town-world-log-snapshot"
		or int(storage_snapshot.get("schemaVersion", 0)) != 1
		or int(storage_snapshot.get("storageSchemaVersion", 0)) != 1
		or not storage_snapshot.get("segments") is Array
		or not storage_snapshot.get("readState", {}) is Dictionary
	):
		return _failure("SESSION_SAVE_REFERENCE_INVALID", false)
	var records: Array = []
	var expected_sequence := 1
	for descriptor_value: Variant in storage_snapshot.get("segments", []) as Array:
		if not descriptor_value is Dictionary:
			return _failure("SESSION_SAVE_REFERENCE_INVALID", false)
		var descriptor := descriptor_value as Dictionary
		var segment_ref := String(descriptor.get("segmentRef", ""))
		var segment_sha256 := String(descriptor.get("segmentSha256", ""))
		if (
			int(descriptor.get("startSequence", 0)) != expected_sequence
			or int(descriptor.get("recordCount", -1)) < 1
			or int(descriptor.get("endSequence", 0))
			!= expected_sequence + int(descriptor.get("recordCount", 0)) - 1
		):
			return _failure("SESSION_SAVE_REFERENCE_INVALID", false)
		var segment_loaded := read_reference(segment_ref, segment_sha256)
		if segment_loaded.get("ok") != true:
			return segment_loaded
		var segment_value: Variant = segment_loaded.get("value")
		if not segment_value is Dictionary:
			return _failure("SESSION_SAVE_REFERENCE_INVALID", false)
		var segment := segment_value as Dictionary
		var segment_records_value: Variant = segment.get("records")
		if (
			String(segment.get("schema", "")) != "town-world-log-segment"
			or int(segment.get("schemaVersion", 0)) != 1
			or String(segment.get("timelineId", ""))
			!= String(storage_snapshot.get("timelineId", ""))
			or int(segment.get("startSequence", 0))
			!= int(descriptor.get("startSequence", 0))
			or int(segment.get("endSequence", 0))
			!= int(descriptor.get("endSequence", 0))
			or not segment_records_value is Array
			or (segment_records_value as Array).size()
			!= int(descriptor.get("recordCount", 0))
		):
			return _failure("SESSION_SAVE_REFERENCE_INVALID", false)
		for record_value: Variant in segment_records_value as Array:
			if (
				not record_value is Dictionary
				or int((record_value as Dictionary).get("sequence", 0))
				!= expected_sequence
			):
				return _failure("SESSION_SAVE_REFERENCE_INVALID", false)
			records.append((record_value as Dictionary).duplicate(true))
			expected_sequence += 1
	if int(storage_snapshot.get("maxSequence", -1)) != records.size():
		return _failure("SESSION_SAVE_REFERENCE_INVALID", false)
	var hydrated := storage_snapshot.duplicate(true)
	hydrated.erase("storageSchemaVersion")
	hydrated.erase("segments")
	hydrated["records"] = records
	loaded["value"] = hydrated
	return loaded


func list_incomplete(slot_id_value: Variant) -> Dictionary:
	var slot_check := MANIFEST.validate_slot_id(slot_id_value)
	if slot_check.get("ok") != true:
		return slot_check
	var slot_id := String(slot_check.get("slotId", ""))
	var intent_parent := _join(_slot_root(slot_id), "intents")
	var directory := DirAccess.open(intent_parent)
	var records: Array[Dictionary] = []
	if directory == null:
		return {
			"ok": true,
			"errorCode": "",
			"retryable": false,
			"records": records,
		}
	for kind in directory.get_directories():
		if not ["save", "restore"].has(kind):
			return _failure("SESSION_SAVE_JOURNAL_STATE_INVALID", false)
		var kind_root := _join(intent_parent, kind)
		var kind_directory := DirAccess.open(kind_root)
		if kind_directory == null:
			continue
		for session_id in kind_directory.get_directories():
			if (
				MANIFEST.validate_context({
					"slot_id": slot_id,
					"session_id": session_id,
					"save_revision": 1,
				}).get("ok") != true
			):
				return _failure("SESSION_SAVE_JOURNAL_STATE_INVALID", false)
			var session_root := _join(kind_root, session_id)
			var session_directory := DirAccess.open(session_root)
			if session_directory == null:
				continue
			for revision_text in session_directory.get_directories():
				var revision := _canonical_revision_from_directory(
					revision_text,
				)
				if revision < 1:
					return _failure(
						"SESSION_SAVE_JOURNAL_STATE_INVALID",
						false,
					)
				var context := {
					"slot_id": slot_id,
					"session_id": session_id,
					"save_revision": revision,
				}
				if MANIFEST.validate_context(context).get("ok") != true:
					continue
				if (
					kind == "save"
					and FileAccess.file_exists(_manifest_path(context))
				):
					continue
				var revision_root := _intent_revision_root(context, kind)
				var revision_directory := DirAccess.open(revision_root)
				if revision_directory == null:
					continue
				for intent_id in revision_directory.get_directories():
					if not _valid_intent_id(kind, intent_id):
						return _failure(
							"SESSION_SAVE_JOURNAL_STATE_INVALID",
							false,
						)
					var latest := read_latest_intent(
						context,
						kind,
						intent_id,
					)
					if latest.get("ok") != true:
						return latest
					if (
						kind == "restore"
						and latest.get("state") in [
							"restore_completed",
							"restore_reconciled",
						]
					):
						continue
					if kind == "save" and latest.get("state") == "save_reconciled":
						continue
					records.append(
						(latest.get("record", {}) as Dictionary).duplicate(true),
					)
	records.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_context := left.get("context", {}) as Dictionary
		var right_context := right.get("context", {}) as Dictionary
		return int(left_context.get("save_revision", 0)) < int(
			right_context.get("save_revision", 0),
		)
	)
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"records": records,
	}


func _slot_root(slot_id: String) -> String:
	return _join(_root, "slots/%s" % slot_id)


func _slot_lease_root(slot_id: String) -> String:
	return _join(
		_root,
		"%s/%s" % [
			SLOT_LEASE_ROOT,
			slot_id.sha256_text().left(EPHEMERAL_CLAIM_KEY_LENGTH),
		],
	)


func _legacy_slot_lease_root(slot_id: String) -> String:
	# beta.2 之前直接把 slot_id 放进锁目录。只访问由校验过的 slot_id
	# 拼出的这一个目录，不会递归扫存档根，也不会触碰 slots 下的正式数据。
	return _join(_root, "%s/%s" % [SLOT_LEASE_ROOT, slot_id])


func _slot_archive_claim_path(slot_id: String) -> String:
	return _join(_slot_lease_root(slot_id), SLOT_ARCHIVE_CLAIM)


func _slot_archive_pending_path(slot_id: String) -> String:
	return _join(_slot_lease_root(slot_id), SLOT_ARCHIVE_PENDING)


func _slot_transaction_root(slot_id: String) -> String:
	return _join(_slot_lease_root(slot_id), SLOT_TRANSACTION_ROOT)


func _check_legacy_claim_activity(
	parent_path: String,
	claim_name: String,
) -> Dictionary:
	var claim_path := _join(parent_path, claim_name)
	var active := false
	if DirAccess.dir_exists_absolute(_absolute(claim_path)):
		var loaded := _read_owned_claim_owner(claim_path)
		if loaded.get("ok") == true:
			active = _ephemeral_claim_owner_is_alive(
				loaded.get("claimOwner", {}) as Dictionary,
			)

	var parent := DirAccess.open(parent_path)
	if parent == null:
		var absent := _success()
		absent["active"] = active
		return absent
	parent.include_hidden = true
	var candidate_prefix := "%s.candidate-" % claim_name
	var candidate_directories := parent.get_directories()
	parent = null
	for directory_name: String in candidate_directories:
		if not directory_name.begins_with(candidate_prefix):
			continue
		var candidate_path := _join(parent_path, directory_name)
		var candidate_owner := _read_owned_claim_owner(
			candidate_path,
			claim_path,
		)
		if candidate_owner.get("ok") == true and _ephemeral_claim_owner_is_alive(
			candidate_owner.get("claimOwner", {}) as Dictionary,
		):
			active = true
	var checked := _success()
	checked["active"] = active
	return checked


func _revision_root(context: Dictionary) -> String:
	return _join(_root, TownSaveContext.revision_directory(context))


func _intent_revision_root(context: Dictionary, kind: String) -> String:
	return _join(
		_slot_root(String(context.get("slot_id", ""))),
		"intents/%s/%s/%020d" % [
			kind,
			String(context.get("session_id", "")),
			int(context.get("save_revision", 0)),
		],
	)


func _intent_attempt_root(
	context: Dictionary,
	kind: String,
	intent_id: String,
) -> String:
	return _join(_intent_revision_root(context, kind), intent_id)


func _restore_intent_claim_root(context: Dictionary) -> String:
	return _join(
		_slot_root(String(context.get("slot_id", ""))),
		"intent_claims/restore/%s/%020d" % [
			String(context.get("session_id", "")),
			int(context.get("save_revision", 0)),
		],
	)


func _intent_allocation(
	context: Dictionary,
	kind: String,
	intent_id: String,
) -> Dictionary:
	return {
		"schema": "town-session-save-intent-allocation",
		"schema_version": 1,
		"kind": kind,
		"intent_id": intent_id,
		"context": context.duplicate(true),
	}


func _intent_allocation_success(intent_id: String) -> Dictionary:
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"intentId": intent_id,
	}


func _valid_intent_id(kind: String, intent_id: String) -> bool:
	if kind == "save":
		return intent_id == "save"
	if (
		kind != "restore"
		or intent_id.length() != 28
		or not intent_id.begins_with("attempt-")
	):
		return false
	var attempt_text := intent_id.trim_prefix("attempt-")
	return (
		attempt_text.is_valid_int()
		and attempt_text > "00000000000000000000"
		and attempt_text <= MAX_SAFE_INTEGER_PADDED
	)


func _next_restore_attempt_candidate(context: Dictionary) -> Dictionary:
	var next_attempt := 1
	var revision_directory := DirAccess.open(
		_intent_revision_root(context, "restore"),
	)
	if revision_directory != null:
		for intent_id: String in revision_directory.get_directories():
			if not _valid_intent_id("restore", intent_id):
				return _failure("SESSION_SAVE_JOURNAL_STATE_INVALID", false)
			var attempt := int(intent_id.trim_prefix("attempt-"))
			if attempt >= MAX_SAFE_INTEGER:
				return _failure("SESSION_SAVE_JOURNAL_STATE_INVALID", false)
			next_attempt = maxi(next_attempt, attempt + 1)
	var claim_directory := DirAccess.open(_restore_intent_claim_root(context))
	if claim_directory != null:
		for claim_name: String in claim_directory.get_directories():
			var claimed_attempt := _canonical_restore_attempt_from_claim(
				claim_name,
			)
			if claimed_attempt < 1 or claimed_attempt >= MAX_SAFE_INTEGER:
				return _failure("SESSION_SAVE_JOURNAL_STATE_INVALID", false)
			next_attempt = maxi(next_attempt, claimed_attempt + 1)
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"attempt": next_attempt,
	}


func _canonical_restore_attempt_from_claim(claim_name: String) -> int:
	if not claim_name.ends_with(".claim"):
		return -1
	var intent_id := claim_name.trim_suffix(".claim")
	if not _valid_intent_id("restore", intent_id):
		return -1
	return int(intent_id.trim_prefix("attempt-"))


func _valid_stage_for_kind(kind: String, stage: String) -> bool:
	if kind == "save":
		return stage in SAVE_STAGES
	if kind == "restore":
		return stage in RESTORE_STAGES
	return false


func _initial_stage(kind: String) -> String:
	return "save_started" if kind == "save" else "restore_started"


func _transition_is_valid(
	kind: String,
	current_state: String,
	next_state: String,
) -> bool:
	if current_state == next_state:
		return true
	var transitions: Dictionary = (
		SAVE_TRANSITIONS
		if kind == "save"
		else RESTORE_TRANSITIONS
		if kind == "restore"
		else {}
	)
	var allowed_value: Variant = transitions.get(current_state)
	return allowed_value is Array and next_state in (allowed_value as Array)


func _valid_payload_for_stage(
	kind: String,
	stage: String,
	payload: Dictionary,
) -> bool:
	if stage != "transaction_failed":
		return true
	if (
		not payload.has("stage")
		or not payload.get("stage") is String
	):
		return false
	var failed_stage := payload.get("stage") as String
	var known_stage := (
		failed_stage in SAVE_TRANSACTION_FAILED_STAGES
		if kind == "save"
		else failed_stage in RESTORE_TRANSACTION_FAILED_STAGES
		if kind == "restore"
		else false
	)
	if not known_stage:
		return false
	var allowed_fields: Array[String] = ["stage"]
	if failed_stage == "world_prepare":
		allowed_fields.append_array(["errorCode", "errors"])
	for key: Variant in payload:
		if not key is String or key not in allowed_fields:
			return false
	if (
		payload.has("errorCode")
		and not payload.get("errorCode") is String
	):
		return false
	if payload.has("errors") and not payload.get("errors") is Array:
		return false
	return true


func _valid_allocation_record(
	value: Variant,
	expected_context: Dictionary,
	expected_kind: String,
	expected_intent_id: String,
) -> bool:
	if not value is Dictionary:
		return false
	var allocation := value as Dictionary
	return (
		_has_exact_fields(allocation, ALLOCATION_FIELDS)
		and allocation.get("schema") == "town-session-save-intent-allocation"
		and allocation.get("schema_version") == 1
		and allocation.get("kind") == expected_kind
		and allocation.get("intent_id") == expected_intent_id
		and allocation.get("context") == expected_context
	)


func _valid_intent_record(
	value: Variant,
	expected_context: Dictionary,
	expected_kind: String,
	expected_intent_id: String,
	file_name: String,
) -> bool:
	if not value is Dictionary:
		return false
	var record := value as Dictionary
	var state_value: Variant = record.get("state")
	var order_value: Variant = record.get("order")
	if (
		not _has_exact_fields(record, RECORD_FIELDS)
		or record.get("schema") != "town-session-save-intent"
		or record.get("schema_version") != 1
		or record.get("kind") != expected_kind
		or record.get("intent_id") != expected_intent_id
		or not state_value is String
		or not order_value is int
		or not record.get("context") is Dictionary
		or not record.get("payload") is Dictionary
	):
		return false
	var state := state_value as String
	var order := order_value as int
	return (
		_valid_stage_for_kind(expected_kind, state)
		and order == int(STAGE_ORDER.get(state, -1))
		and file_name == "%03d_%s.json" % [order, state]
		and record.get("context") == expected_context
		and _json_safe(record.get("payload"))
		and _valid_payload_for_stage(
			expected_kind,
			state,
			record.get("payload") as Dictionary,
		)
	)


func _has_exact_fields(value: Dictionary, fields: Array[String]) -> bool:
	if value.size() != fields.size():
		return false
	for field in fields:
		if not value.has(field):
			return false
	return true


func _manifest_path(context: Dictionary) -> String:
	return _join(
		_slot_root(String(context.get("slot_id", ""))),
		"manifests/%020d.json" % int(context.get("save_revision", 0)),
	)


func _canonical_revision_from_file(file_name: String) -> int:
	if not file_name.ends_with(".json"):
		return -1
	return _canonical_revision_from_directory(file_name.trim_suffix(".json"))


func _revision_allocation_matches(context: Dictionary) -> bool:
	var allocation_path := _join(
		_join(
			_slot_root(String(context.get("slot_id", ""))),
			"allocations",
		),
		"%020d.json" % int(context.get("save_revision", 0)),
	)
	var loaded := _read_json(allocation_path)
	if loaded.get("ok") != true:
		return false
	var value: Variant = loaded.get("value")
	if not value is Dictionary:
		return false
	var allocation := value as Dictionary
	return (
		_has_exact_fields(allocation, REVISION_ALLOCATION_FIELDS)
		and allocation.get("schema") == "town-session-save-allocation"
		and allocation.get("schema_version") == 1
		and allocation.get("context") is Dictionary
		and allocation.get("context") == context
	)


func _canonical_revision_from_claim(directory_name: String) -> int:
	if not directory_name.ends_with(".claim"):
		return -1
	return _canonical_revision_from_directory(
		directory_name.trim_suffix(".claim")
	)


func _next_revision_candidate(allocation_root: String) -> int:
	var next_revision := 1
	var directory := DirAccess.open(allocation_root)
	if directory == null:
		return next_revision
	for file_name: String in directory.get_files():
		var existing_revision := _canonical_revision_from_file(file_name)
		if existing_revision < 0:
			continue
		if existing_revision >= MAX_SAFE_INTEGER:
			return -1
		next_revision = maxi(next_revision, existing_revision + 1)
	for directory_name: String in directory.get_directories():
		var claimed_revision := _canonical_revision_from_claim(directory_name)
		if claimed_revision < 0:
			continue
		if claimed_revision >= MAX_SAFE_INTEGER:
			return -1
		next_revision = maxi(next_revision, claimed_revision + 1)
	return next_revision


func _canonical_revision_from_directory(revision_text: String) -> int:
	if (
		revision_text.length() != 20
		or not TownSaveScalars.ascii_digits(revision_text)
		or revision_text > MAX_SAFE_INTEGER_PADDED
	):
		return -1
	var revision := int(revision_text)
	return revision if "%020d" % revision == revision_text else -1


func _reference(path: String) -> String:
	var prefix := "%s/" % _root.trim_suffix("/")
	return path.trim_prefix(prefix)


func _resolve_reference(reference: String) -> String:
	if (
		reference.is_empty()
		or reference != reference.strip_edges()
		or reference.begins_with("/")
		or reference.ends_with("/")
		or reference.contains("..")
		or reference.contains("\\")
		or reference.contains("//")
	):
		return ""
	return _join(_root, reference)


func _valid_reference_shape(reference: String) -> bool:
	var parts := reference.split("/", false)
	if (
		parts.size() == 2
		and parts[0] == "world_log_segments"
		and parts[1].ends_with(".json")
	):
		var segment_sha256 := parts[1].trim_suffix(".json")
		return _is_sha256(segment_sha256)
	var parsed := TownSaveContext.parse_revision_reference(reference)
	if (
		parsed.get("ok") != true
		or not String(parsed.get("file_name", "")) in [
			"world_snapshot.json",
			"session_config.json",
			"world_log_snapshot.json",
		]
	):
		return false
	var revision := _canonical_revision_from_directory(
		String(parsed.get("revision_text", "")),
	)
	return (
		revision >= 1
		and MANIFEST.validate_context({
			"slot_id": parsed.get("slot_id", ""),
			"session_id": parsed.get("session_id", ""),
			"save_revision": revision,
		}).get("ok") == true
	)


func _atomic_create_json(path: String, value: Dictionary) -> Dictionary:
	if not _json_safe(value):
		return _failure("SESSION_SAVE_STORE_JSON_INVALID", false)
	var encoded := JSON.stringify(value, "\t")
	var expected_parsed: Variant = JSON.parse_string(encoded)
	if not expected_parsed is Dictionary:
		return _failure("SESSION_SAVE_STORE_JSON_INVALID", false)
	var expected := _normalize_numbers(expected_parsed) as Dictionary
	if FileAccess.file_exists(path):
		return _compare_existing_json(path, expected)
	var parent_error := DirAccess.make_dir_recursive_absolute(
		_absolute(path.get_base_dir()),
	)
	if parent_error != OK:
		return _failure("SESSION_SAVE_STORE_WRITE_FAILED", true)
	var claim_path := _ephemeral_claim_path("create", path)
	var claim := _acquire_recoverable_directory_claim(
		claim_path,
		path,
		expected,
	)
	if claim.get("existing") == true:
		return claim
	if claim.get("ok") != true:
		return claim
	var claim_owner := claim.get("claimOwner", {}) as Dictionary
	if FileAccess.file_exists(path):
		var existing := _compare_existing_json(path, expected)
		return _release_owned_claim_and_return(
			claim_path,
			claim_owner,
			existing,
		)
	# The per-target claim serializes writers, so a fixed adjacent temporary name
	# is sufficient and avoids another long Windows-only suffix.
	var temporary := "%s.tmp" % path
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return _release_owned_claim_and_return(
			claim_path,
			claim_owner,
			_failure("SESSION_SAVE_STORE_WRITE_FAILED", true),
		)
	file.store_string(encoded)
	file.flush()
	var write_error := file.get_error()
	file = null
	if write_error != OK:
		DirAccess.remove_absolute(_absolute(temporary))
		return _release_owned_claim_and_return(
			claim_path,
			claim_owner,
			_failure("SESSION_SAVE_STORE_WRITE_FAILED", true),
		)
	var verified := _read_json(temporary)
	if (
		verified.get("ok") != true
		or not _json_values_equal_exact(verified.get("value"), expected)
	):
		DirAccess.remove_absolute(_absolute(temporary))
		return _release_owned_claim_and_return(
			claim_path,
			claim_owner,
			_failure("SESSION_SAVE_STORE_WRITE_FAILED", true),
		)
	var temporary_sha256 := _sha256_file(temporary)
	if temporary_sha256.is_empty():
		DirAccess.remove_absolute(_absolute(temporary))
		return _release_owned_claim_and_return(
			claim_path,
			claim_owner,
			_failure("SESSION_SAVE_STORE_WRITE_FAILED", true),
		)
	var rename_error := DirAccess.rename_absolute(
		_absolute(temporary),
		_absolute(path),
	)
	if rename_error != OK:
		DirAccess.remove_absolute(_absolute(temporary))
		return _release_owned_claim_and_return(
			claim_path,
			claim_owner,
			_failure("SESSION_SAVE_STORE_WRITE_FAILED", true),
		)
	return _release_owned_claim_and_return(claim_path, claim_owner, {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"sha256": temporary_sha256,
		"existing": false,
	})


func _validated_slot_id(slot_id_value: Variant) -> Dictionary:
	return MANIFEST.validate_slot_id(slot_id_value)


func _recoverable_claim_activity(claim_path: String) -> Dictionary:
	if not DirAccess.dir_exists_absolute(_absolute(claim_path)):
		var absent := _success()
		absent["active"] = false
		return absent
	var loaded := _read_owned_claim_owner(claim_path)
	if loaded.get("ok") != true:
		return loaded
	var owner := loaded.get("claimOwner", {}) as Dictionary
	if _ephemeral_claim_owner_is_alive(owner):
		var active := _success()
		active["active"] = true
		return active
	var recovered := _acquire_recoverable_directory_claim(
		claim_path,
		"",
		{},
		2,
	)
	if recovered.get("ok") != true:
		var current := _read_owned_claim_owner(claim_path)
		if (
			current.get("ok") == true
			and _ephemeral_claim_owner_is_alive(
				current.get("claimOwner", {}) as Dictionary,
			)
		):
			var occupied := _success()
			occupied["active"] = true
			return occupied
		return current if current.get("ok") != true else recovered
	var released := _release_owned_directory_claim(
		claim_path,
		recovered.get("claimOwner", {}) as Dictionary,
	)
	if released.get("ok") != true:
		return released
	var inactive := _success()
	inactive["active"] = false
	return inactive


func _owned_archive_lease(lease_token_value: Variant) -> Dictionary:
	if (
		not lease_token_value is String
		or (lease_token_value as String).is_empty()
	):
		return _failure("SESSION_SAVE_SLOT_LEASE_INVALID", false)
	var lease_value: Variant = _owned_slot_archives.get(
		lease_token_value as String,
	)
	if not lease_value is Dictionary:
		return _failure("SESSION_SAVE_SLOT_LEASE_INVALID", false)
	var lease := lease_value as Dictionary
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"slotId": String(lease.get("slotId", "")),
	}


func _open_slot_transaction_directory(path: String) -> DirAccess:
	return DirAccess.open(path)


func _release_slot_lease(
	lease_token_value: Variant,
	owned_leases: Dictionary,
) -> Dictionary:
	if (
		not lease_token_value is String
		or (lease_token_value as String).is_empty()
	):
		return _failure("SESSION_SAVE_SLOT_LEASE_INVALID", false)
	var lease_token := lease_token_value as String
	var lease_value: Variant = owned_leases.get(lease_token)
	if not lease_value is Dictionary:
		return _failure("SESSION_SAVE_SLOT_LEASE_INVALID", false)
	var lease := lease_value as Dictionary
	var released := _release_owned_directory_claim(
		String(lease.get("claimPath", "")),
		lease.get("claimOwner", {}) as Dictionary,
	)
	if released.get("ok") == true:
		owned_leases.erase(lease_token)
	return released


func _acquire_recoverable_directory_claim(
	claim_path: String,
	existing_path: String = "",
	expected: Dictionary = {},
	retry_limit: int = CREATE_CLAIM_RETRY_LIMIT,
) -> Dictionary:
	var resolved_retry_limit := maxi(retry_limit, 1)
	var claim_parent_error := DirAccess.make_dir_recursive_absolute(
		_absolute(claim_path.get_base_dir()),
	)
	if claim_parent_error not in [OK, ERR_ALREADY_EXISTS]:
		return _failure("SESSION_SAVE_STORE_WRITE_FAILED", true)
	var owner := _new_ephemeral_claim_owner(claim_path)
	var candidate_path := "%s.candidate-%s" % [
		claim_path,
		_claim_path_token(owner),
	]
	var candidate_error := DirAccess.make_dir_absolute(_absolute(candidate_path))
	if candidate_error != OK:
		return _failure("SESSION_SAVE_STORE_WRITE_FAILED", true)
	var owner_write := _write_owned_claim_record(
		candidate_path,
		claim_path,
		owner,
	)
	if owner_write.get("ok") != true:
		_remove_tree(candidate_path)
		return owner_write
	for retry in range(resolved_retry_limit):
		if not existing_path.is_empty() and FileAccess.file_exists(existing_path):
			var existing := _compare_existing_json(existing_path, expected)
			_remove_tree(candidate_path)
			return existing
		if not DirAccess.dir_exists_absolute(_absolute(claim_path)):
			var publish_error := DirAccess.rename_absolute(
				_absolute(candidate_path),
				_absolute(claim_path),
			)
			if publish_error == OK:
				var acquired := _success()
				acquired["claimOwner"] = owner.duplicate(true)
				return acquired
		var current_owner := _read_owned_claim_owner(claim_path)
		if current_owner.get("claimReadTransient") == true:
			if retry + 1 < resolved_retry_limit:
				OS.delay_usec(CREATE_CLAIM_RETRY_DELAY_USEC)
			continue
		if (
			current_owner.get("ok") != true
			and not DirAccess.dir_exists_absolute(_absolute(claim_path))
		):
			continue
		if current_owner.get("ok") != true:
			_remove_tree(candidate_path)
			return current_owner
		var current_owner_record := (
			current_owner.get("claimOwner", {}) as Dictionary
		)
		if not _ephemeral_claim_owner_is_alive(current_owner_record):
			var confirmed_owner := _read_owned_claim_owner(claim_path)
			if confirmed_owner.get("claimReadTransient") == true:
				continue
			if confirmed_owner.get("ok") != true:
				_remove_tree(candidate_path)
				return confirmed_owner
			if not _json_values_equal_exact(
				confirmed_owner.get("claimOwner"),
				current_owner_record,
			):
				continue
			var recovered_path := "%s.recovered-%s" % [
				claim_path,
				_claim_path_token(current_owner_record),
			]
			var recover_error := DirAccess.rename_absolute(
				_absolute(claim_path),
				_absolute(recovered_path),
			)
			if recover_error == OK:
				var recovered_owner := _read_owned_claim_owner(
					recovered_path,
					claim_path,
				)
				if (
					recovered_owner.get("ok") != true
					or not _json_values_equal_exact(
						recovered_owner.get("claimOwner"),
						current_owner_record,
					)
				):
					_remove_tree(candidate_path)
					return _failure(
						"SESSION_SAVE_STORE_WRITE_FAILED",
						false,
					)
				# Keep the retired generation as a tombstone. A contender that
				# observed this dead owner before the rename must not be able
				# to rename and delete a newer owner published at claim_path.
				continue
		if retry + 1 >= resolved_retry_limit:
			break
		OS.delay_usec(CREATE_CLAIM_RETRY_DELAY_USEC)
	_remove_tree(candidate_path)
	return _failure("SESSION_SAVE_STORE_WRITE_FAILED", true)


func _ephemeral_claim_owner_is_alive(owner: Dictionary) -> bool:
	var owner_pid := int(String(owner.get("owner_pid", "")))
	if owner_pid == OS.get_process_id():
		if owner.get("schema_version") == "1":
			# This binary never creates v1 owners. A v1 claim with our PID is
			# therefore residue from an earlier process that reused the PID.
			return false
		return (
			owner.get("process_start_sha256")
			== _current_process_identity_sha256()
		)
	var created_unix_msec := int(
		String(owner.get("created_unix_msec", "")),
	)
	var now_unix_msec := int(Time.get_unix_time_from_system() * 1000.0)
	if (
		now_unix_msec >= created_unix_msec
		and now_unix_msec - created_unix_msec
			< EPHEMERAL_CLAIM_LIVENESS_GRACE_MSEC
	):
		return true
	var output: Array = []
	match OS.get_name():
		"macOS", "Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD":
			if not FileAccess.file_exists("/bin/kill"):
				return true
			var exit_code := OS.execute(
				"/bin/kill",
				PackedStringArray(["-0", str(owner_pid)]),
				output,
				true,
			)
			# kill -0 uses 0 for a visible live process and 1 for a missing PID.
			# Any other launcher error fails closed.
			if exit_code == 1:
				return false
			if owner.get("schema_version") == "1":
				# v1 has no cross-process identity field. A foreign live PID
				# must therefore remain occupied until that process exits.
				return true
			var observed_identity := _observed_process_identity_sha256(
				owner_pid,
			)
			return (
				true
				if observed_identity.is_empty()
				else observed_identity
					== owner.get("process_start_sha256")
			)
		"Windows":
			var exit_code := OS.execute(
				"tasklist",
				PackedStringArray([
					"/FI",
					"PID eq %d" % owner_pid,
					"/FO",
					"CSV",
					"/NH",
				]),
				output,
				true,
			)
			if exit_code != 0:
				return true
			var process_present := (
				not output.is_empty()
				and String(output[0]).contains("\"%d\"" % owner_pid)
			)
			if not process_present:
				return false
			if owner.get("schema_version") == "1":
				return true
			var observed_identity := _observed_process_identity_sha256(
				owner_pid,
			)
			return (
				true
				if observed_identity.is_empty()
				else observed_identity
					== owner.get("process_start_sha256")
			)
	# Unknown platforms fail closed instead of reclaiming a possibly live owner.
	return true


func _new_ephemeral_claim_owner(claim_path: String) -> Dictionary:
	var owner_pid := OS.get_process_id()
	var process_start_sha256 := _current_process_identity_sha256()
	var entropy := "%d:%d:%f:%d" % [
		owner_pid,
		Time.get_ticks_usec(),
		Time.get_unix_time_from_system(),
		randi(),
	]
	return {
		"schema": "town-session-save-ephemeral-claim",
		"schema_version": "2",
		"claim_path_sha256": claim_path.sha256_text(),
		"owner_pid": str(owner_pid),
		"process_start_sha256": process_start_sha256,
		"owner_token": entropy.sha256_text(),
		"created_unix_msec": str(
			int(Time.get_unix_time_from_system() * 1000.0),
		),
	}


func _current_process_identity_sha256() -> String:
	if _current_process_start_sha256.is_empty():
		_current_process_start_sha256 = _observed_process_identity_sha256(
			OS.get_process_id(),
		)
		if _current_process_start_sha256.is_empty():
			var fallback := "%d:%f:%d:%d" % [
				OS.get_process_id(),
				Time.get_unix_time_from_system(),
				Time.get_ticks_usec(),
				randi(),
			]
			_current_process_start_sha256 = fallback.sha256_text()
	return _current_process_start_sha256


func _observed_process_identity_sha256(process_id: int) -> String:
	var output: Array = []
	var exit_code := -1
	match OS.get_name():
		"macOS", "Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD":
			if not FileAccess.file_exists("/bin/ps"):
				return ""
			exit_code = OS.execute(
				"/bin/ps",
				PackedStringArray([
					"-p",
					str(process_id),
					"-ww",
					"-o",
					"lstart=",
					"-o",
					"ppid=",
					"-o",
					"pgid=",
					"-o",
					"sess=",
					"-o",
					"uid=",
					"-o",
					"comm=",
				]),
				output,
				true,
			)
		"Windows":
			exit_code = OS.execute(
				"powershell.exe",
				PackedStringArray([
					"-NoProfile",
					"-NonInteractive",
					"-Command",
					(
						"$p=Get-Process -Id %d -ErrorAction Stop;"
						+ "('{0}|{1}' -f "
						+ "$p.StartTime.ToUniversalTime().Ticks,$p.Path)"
					) % process_id,
				]),
				output,
				true,
			)
		_:
			return ""
	if exit_code != 0:
		return ""
	var identity := "\n".join(output).strip_edges()
	return "" if identity.is_empty() else identity.sha256_text()


func _write_owned_claim_record(
	claim_directory: String,
	claim_path: String,
	owner: Dictionary,
) -> Dictionary:
	if not _valid_ephemeral_claim_owner(owner, claim_path):
		return _failure("SESSION_SAVE_STORE_WRITE_FAILED", false)
	var owner_path := _join(claim_directory, "owner.json")
	var file := FileAccess.open(owner_path, FileAccess.WRITE)
	if file == null:
		return _failure("SESSION_SAVE_STORE_WRITE_FAILED", true)
	file.store_string(JSON.stringify(owner, "\t"))
	file.flush()
	var write_error := file.get_error()
	file = null
	if write_error != OK:
		return _failure("SESSION_SAVE_STORE_WRITE_FAILED", true)
	var raw_text := FileAccess.get_file_as_string(owner_path)
	var loaded: Variant = JSON.parse_string(raw_text)
	if (
		not loaded is Dictionary
		or not _json_values_equal_exact(loaded, owner)
		or raw_text != JSON.stringify(loaded, "\t")
	):
		return _failure("SESSION_SAVE_STORE_WRITE_FAILED", true)
	return _success()


func _read_owned_claim_owner(
	claim_path: String,
	owner_claim_path: String = "",
) -> Dictionary:
	var validated_claim_path := (
		claim_path
		if owner_claim_path.is_empty()
		else owner_claim_path
	)
	var owner_path := _join(claim_path, "owner.json")
	var file := FileAccess.open(owner_path, FileAccess.READ)
	if file == null:
		# The claim directory is published and released atomically, so a failed
		# open can be the gap between generations rather than malformed JSON.
		# Never apply that observation to a claim that may already be a newer
		# generation at the same path; the acquisition loop must read again.
		var transient := _failure("SESSION_SAVE_STORE_WRITE_FAILED", true)
		transient["claimReadTransient"] = true
		return transient
	var raw_text := file.get_as_text()
	var read_error := file.get_error()
	file = null
	if read_error != OK:
		return _failure("SESSION_SAVE_STORE_JSON_INVALID", false)
	var loaded: Variant = JSON.parse_string(raw_text)
	if (
		not loaded is Dictionary
		or not _valid_ephemeral_claim_owner(loaded, validated_claim_path)
		or raw_text != JSON.stringify(loaded, "\t")
	):
		return _failure("SESSION_SAVE_STORE_JSON_INVALID", false)
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"claimOwner": (
			loaded as Dictionary
		).duplicate(true),
	}


func _valid_ephemeral_claim_owner(
	value: Variant,
	claim_path: String,
) -> bool:
	if not value is Dictionary:
		return false
	var owner := value as Dictionary
	var owner_pid_value: Variant = owner.get("owner_pid")
	var created_value: Variant = owner.get("created_unix_msec")
	var schema_version_value: Variant = owner.get("schema_version")
	if (
		not schema_version_value is String
		or not schema_version_value in ["1", "2"]
	):
		return false
	var expected_fields := (
		EPHEMERAL_CLAIM_OWNER_V1_FIELDS
		if schema_version_value == "1"
		else EPHEMERAL_CLAIM_OWNER_FIELDS
	)
	return (
		_has_exact_fields(owner, expected_fields)
		and owner.get("schema") == "town-session-save-ephemeral-claim"
		and owner.get("claim_path_sha256") == claim_path.sha256_text()
		and owner_pid_value is String
		and _canonical_positive_integer_text(owner_pid_value as String)
		and (
			schema_version_value == "1"
			or (
				owner.get("process_start_sha256") is String
				and _is_sha256(
					owner.get("process_start_sha256") as String,
				)
			)
		)
		and owner.get("owner_token") is String
		and _is_sha256(owner.get("owner_token") as String)
		and created_value is String
		and _canonical_positive_integer_text(created_value as String)
	)


func _canonical_positive_integer_text(value: String) -> bool:
	if (
		value.is_empty()
		or not TownSaveScalars.ascii_digits(value)
		or value.length() > str(MAX_SAFE_INTEGER).length()
	):
		return false
	var parsed := int(value)
	return (
		parsed > 0
		and parsed <= MAX_SAFE_INTEGER
		and str(parsed) == value
	)


func _release_owned_directory_claim(
	claim_path: String,
	expected_owner: Dictionary,
) -> Dictionary:
	var loaded := _read_owned_claim_owner(claim_path)
	if (
		loaded.get("ok") != true
		or not _json_values_equal_exact(
			loaded.get("claimOwner"),
			expected_owner,
		)
	):
		return _failure("SESSION_SAVE_STORE_WRITE_FAILED", true)
	var released_path := "%s.released-%s" % [
		claim_path,
		_claim_path_token(expected_owner),
	]
	var release_error := DirAccess.rename_absolute(
		_absolute(claim_path),
		_absolute(released_path),
	)
	if release_error != OK:
		return _failure("SESSION_SAVE_STORE_WRITE_FAILED", true)
	var cleanup_error := _remove_tree(released_path)
	return (
		_success()
		if cleanup_error == OK
		else _failure("SESSION_SAVE_STORE_CLEANUP_FAILED", true)
	)


func _release_owned_claim_and_return(
	claim_path: String,
	expected_owner: Dictionary,
	result: Dictionary,
) -> Dictionary:
	var released := _release_owned_directory_claim(
		claim_path,
		expected_owner,
	)
	return result if released.get("ok") == true else released


func _compare_existing_json(path: String, expected: Dictionary) -> Dictionary:
	var existing := _read_json(path)
	if (
		existing.get("ok") == true
		and _json_values_equal_exact(existing.get("value"), expected)
	):
		return {
			"ok": true,
			"errorCode": "",
			"retryable": false,
			"sha256": _sha256_file(path),
			"existing": true,
		}
	return _failure("SESSION_SAVE_STORE_IMMUTABLE_CONFLICT", false)


func _claim_path_token(owner: Dictionary) -> String:
	# The complete token remains in owner.json. Only the filesystem generation
	# suffix is shortened so deep user:// save paths stay below legacy Windows
	# path limits while retaining 96 bits of collision resistance.
	return String(owner.get("owner_token", "")).left(CLAIM_PATH_TOKEN_LENGTH)


func _ephemeral_claim_path(kind: String, identity: String) -> String:
	# Claims are recoverable coordination state, not save identity. Keeping them
	# under one shallow hashed root prevents a deep restore journal path from
	# crossing the legacy Windows MAX_PATH boundary before owner.json is written.
	var key := "%s:%s" % [kind, identity]
	return _join(
		_root,
		"%s/%s-%s" % [
			EPHEMERAL_CLAIM_ROOT,
			kind,
			key.sha256_text().left(EPHEMERAL_CLAIM_KEY_LENGTH),
		],
	)


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("SESSION_SAVE_REFERENCE_NOT_FOUND", false)
	var text := file.get_as_text()
	var read_error := file.get_error()
	file = null
	if read_error != OK:
		return _failure("SESSION_SAVE_STORE_READ_FAILED", true)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return _failure("SESSION_SAVE_STORE_JSON_INVALID", false)
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"value": (_normalize_numbers(parsed) as Dictionary).duplicate(true),
	}


func _normalize_numbers(value: Variant) -> Variant:
	if typeof(value) == TYPE_FLOAT:
		var number := float(value)
		if (
			not is_nan(number)
			and not is_inf(number)
			and absf(number) <= float(MAX_SAFE_INTEGER)
			and number == floorf(number)
		):
			return int(number)
	if value is Array:
		var normalized_array: Array = []
		for item: Variant in value as Array:
			normalized_array.append(_normalize_numbers(item))
		return normalized_array
	if value is Dictionary:
		var normalized_dictionary := {}
		for key: Variant in value as Dictionary:
			normalized_dictionary[key] = _normalize_numbers(
				(value as Dictionary)[key],
			)
		return normalized_dictionary
	return value


func _json_safe(value: Variant, depth := 0) -> bool:
	if depth > 64:
		return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_STRING:
			return true
		TYPE_INT:
			var integer := int(value)
			return (
				integer >= -MAX_SAFE_INTEGER
				and integer <= MAX_SAFE_INTEGER
			)
		TYPE_FLOAT:
			var number := float(value)
			return (
				not is_nan(number)
				and not is_inf(number)
				and absf(number) <= float(MAX_SAFE_INTEGER)
			)
		TYPE_ARRAY:
			for item: Variant in value as Array:
				if not _json_safe(item, depth + 1):
					return false
			return true
		TYPE_DICTIONARY:
			for key: Variant in value as Dictionary:
				if (
					not key is String
					or not _json_safe(
						(value as Dictionary)[key],
						depth + 1,
					)
				):
					return false
			return true
	return false


func _json_values_equal_exact(left: Variant, right: Variant) -> bool:
	if typeof(left) != typeof(right):
		return false
	match typeof(left):
		TYPE_ARRAY:
			var left_array := left as Array
			var right_array := right as Array
			if left_array.size() != right_array.size():
				return false
			for index in left_array.size():
				if not _json_values_equal_exact(
					left_array[index],
					right_array[index],
				):
					return false
			return true
		TYPE_DICTIONARY:
			var left_dictionary := left as Dictionary
			var right_dictionary := right as Dictionary
			if left_dictionary.size() != right_dictionary.size():
				return false
			for key: Variant in left_dictionary:
				if (
					not right_dictionary.has(key)
					or not _json_values_equal_exact(
						left_dictionary[key],
						right_dictionary[key],
					)
				):
					return false
			return true
	return left == right


func _is_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	for index in value.length():
		var code := value.unicode_at(index)
		if not (
			code >= "0".unicode_at(0) and code <= "9".unicode_at(0)
			or code >= "a".unicode_at(0) and code <= "f".unicode_at(0)
		):
			return false
	return true


func _sha256_file(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var bytes := file.get_buffer(file.get_length())
	file = null
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK:
		return ""
	hashing.update(bytes)
	return hashing.finish().hex_encode()


func _remove_tree(path: String) -> Error:
	var absolute := _absolute(path)
	if not DirAccess.dir_exists_absolute(absolute):
		return OK
	# Godot's Windows backend adds the native long-path prefix for absolute paths.
	# Stay in that path form for enumeration and every recursive child operation.
	var directory := DirAccess.open(absolute)
	if directory == null:
		return DirAccess.get_open_error()
	directory.include_hidden = true
	for file_name in directory.get_files():
		var error := DirAccess.remove_absolute(
			_absolute(_join(path, file_name)),
		)
		if error != OK:
			return error
	for directory_name in directory.get_directories():
		var child_error := _remove_tree(_join(path, directory_name))
		if child_error != OK:
			return child_error
	# Windows keeps the directory locked while this iterator owns its handle.
	directory = null
	return DirAccess.remove_absolute(absolute)


func _absolute(path: String) -> String:
	return ProjectSettings.globalize_path(path)


func _join(base: String, child: String) -> String:
	return TownSaveContext.join_path(base, child)


func _success() -> Dictionary:
	return {"ok": true, "errorCode": "", "retryable": false}


func _failure(error_code: String, retryable: bool) -> Dictionary:
	return RESULT_SHAPES.failure_retryable(error_code, retryable)
