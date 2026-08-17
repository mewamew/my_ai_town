class_name TownFormalSlotArchiveService
extends RefCounted


const RESULT_SHAPES := preload(
	"res://world/contract/TownWorldResultShapes.gd"
)
const SAVE_MANIFEST := preload(
	"res://world/presentation/session/TownSessionSaveManifest.gd"
)
const SAVE_STORE := preload(
	"res://world/presentation/session/TownSessionSaveStore.gd"
)
const AGENT_FILE_SYSTEM := preload("res://agent/AgentFileSystem.gd")
const DEFAULT_WORLD_SLOTS_ROOT := "user://town_session_saves/slots"
const DEFAULT_AGENT_SLOTS_ROOT := "user://agent_saves"
const DEFAULT_PHOTO_SLOTS_ROOT := "user://town_conversation_photos"
const DEFAULT_BACKUP_ROOT := "user://formal_slot_backups"
const TEST_ROOT := "user://tests/town_session_saves/formal_slot_archive"
const UNVERIFIED_DELETE_STATES := ["incomplete", "corrupt"]
const TRANSACTION_FILE := "archive.transaction.json"
const COMPLETION_RECEIPT_FILE := "archive.receipt.json"
const ARCHIVE_METADATA_FILE := "archive.json"
const TRANSACTION_SCHEMA := "ai-town-formal-slot-archive-transaction"
const PHOTO_WRITE_BLOCK_SCHEMA := "ai-town-conversation-photo-archive-block"
const AGENT_SAVE_FORMAT_VERSION := TownSaveSchemaRegistry.AGENT_SAVE_FORMAT_VERSION
const INTERRUPTED_WORLD_DIRECTORY := "interrupted_new_game_world"
const INTERRUPTED_AGENT_DIRECTORY := "interrupted_new_game_agent"
const INTERRUPTED_PHOTO_DIRECTORY := "interrupted_new_game_photos"

var _world_slots_root := DEFAULT_WORLD_SLOTS_ROOT
var _agent_slots_root := DEFAULT_AGENT_SLOTS_ROOT
var _photo_slots_root := DEFAULT_PHOTO_SLOTS_ROOT
var _backup_root := DEFAULT_BACKUP_ROOT
var _save_store: TownSessionSaveStore = SAVE_STORE.new()


func configure_test_roots(
	world_slots_root: String,
	agent_slots_root: String,
	backup_root: String,
	photo_slots_root: String = "",
) -> Dictionary:
	if (
		_world_slots_root != DEFAULT_WORLD_SLOTS_ROOT
		or _agent_slots_root != DEFAULT_AGENT_SLOTS_ROOT
		or _photo_slots_root != DEFAULT_PHOTO_SLOTS_ROOT
		or _backup_root != DEFAULT_BACKUP_ROOT
	):
		return _failure("FORMAL_SLOT_ARCHIVE_ALREADY_CONFIGURED", false)
	var resolved_photo_root := (
		photo_slots_root
		if not photo_slots_root.strip_edges().is_empty()
		else "%s/photos" % backup_root.trim_suffix("/")
	)
	var roots: Array[String] = [
		world_slots_root.trim_suffix("/"),
		agent_slots_root.trim_suffix("/"),
		backup_root.trim_suffix("/"),
		resolved_photo_root.trim_suffix("/"),
	]
	for root: String in roots:
		if not _is_test_path(root):
			return _failure("FORMAL_SLOT_ARCHIVE_TEST_PATH_INVALID", false)
	if roots[0].get_file() != "slots":
		return _failure("FORMAL_SLOT_ARCHIVE_TEST_PATH_INVALID", false)
	var store_configuration := _save_store.configure_test_root(roots[0].get_base_dir(),) as Dictionary
	if store_configuration.get("ok") != true:
		return _failure("FORMAL_SLOT_ARCHIVE_TEST_PATH_INVALID", false)
	_world_slots_root = roots[0]
	_agent_slots_root = roots[1]
	_backup_root = roots[2]
	_photo_slots_root = roots[3]
	return _success(false)


func archive_for_new_game(request: Dictionary) -> Dictionary:
	var lease := _begin_archive_lease(request.get("slotId"))
	if lease.get("ok") != true:
		return lease
	var recovered := _recover_pending_archives(
		String(request.get("slotId", "")),
	)
	if recovered.get("ok") != true:
		return _finish_archive_lease(lease, recovered)
	var completed := _completed_archive_result_for_request(
		request,
		"new_game_overwrite",
	)
	if completed.get("found") == true:
		return _finish_archive_lease(
			lease,
			_with_recovery_change(completed, recovered),
		)
	return _finish_archive_lease(
		lease,
		_with_recovery_change(
			_archive_complete_pair(request, "new_game_overwrite"),
			recovered,
		),
	)


func restore_completed_new_game_archive(request: Dictionary) -> Dictionary:
	var slot_id_value: Variant = request.get("slotId")
	var session_id_value: Variant = request.get("sessionId")
	var save_revision_value: Variant = request.get("saveRevision")
	var archive_path_value: Variant = request.get("archivePath")
	if (
		not slot_id_value is String
		or not session_id_value is String
		or not _is_positive_integer_number(save_revision_value)
		or not archive_path_value is String
	):
		return _failure("FORMAL_SLOT_ARCHIVE_RESTORE_CONTEXT_INVALID", false)
	var slot_id := slot_id_value as String
	var session_id := session_id_value as String
	var archive_path := archive_path_value as String
	if (
		slot_id != slot_id.strip_edges()
		or session_id != session_id.strip_edges()
		or archive_path != archive_path.strip_edges()
		or not _valid_slot_id(slot_id)
		or not _valid_slot_id(session_id)
		or not _archive_root_matches_slot(archive_path, slot_id)
	):
		return _failure("FORMAL_SLOT_ARCHIVE_RESTORE_CONTEXT_INVALID", false)
	var lease := _begin_archive_lease(slot_id)
	if lease.get("ok") != true:
		return lease
	return _finish_archive_lease(
		lease,
		_restore_completed_new_game_archive({
			"slotId": slot_id,
			"sessionId": session_id,
			"saveRevision": int(save_revision_value),
			"archivePath": archive_path,
		}),
	)


func recover_interrupted_new_game_overwrite(slot_id: String) -> Dictionary:
	var normalized_slot_id := slot_id.strip_edges()
	if (
		slot_id != normalized_slot_id
		or not _valid_slot_id(normalized_slot_id)
	):
		return _failure("FORMAL_SLOT_ARCHIVE_SLOT_ID_INVALID", false)
	# Startup discovery runs before a first Web save directory exists.  A fresh
	# profile has nothing to recover, so do not acquire a write lock just to
	# inspect an empty slot; Web storage can reject that directory creation
	# before its persistent filesystem has been mounted.
	if not _slot_has_archive_recovery_evidence(normalized_slot_id):
		return _success(false)
	var lease := _begin_archive_lease(normalized_slot_id)
	if lease.get("ok") != true:
		return lease
	var recovered := _recover_pending_archives(normalized_slot_id)
	if recovered.get("ok") != true:
		return _finish_archive_lease(lease, recovered)
	return _finish_archive_lease(
		lease,
		_with_recovery_change(
			_recover_interrupted_new_game_overwrite(normalized_slot_id),
			recovered,
		),
	)


func _slot_has_archive_recovery_evidence(slot_id: String) -> bool:
	return (
		DirAccess.dir_exists_absolute(_absolute(_join(_world_slots_root, slot_id)))
		or DirAccess.dir_exists_absolute(_absolute(_join(_agent_slots_root, slot_id)))
		or DirAccess.dir_exists_absolute(_absolute(_join(_photo_slots_root, slot_id)))
		or DirAccess.dir_exists_absolute(_absolute(_slot_backup_root(slot_id)))
	)


func finalize_completed_new_game_archive(request: Dictionary) -> Dictionary:
	var slot_id_value: Variant = request.get("slotId")
	var session_id_value: Variant = request.get("sessionId")
	var save_revision_value: Variant = request.get("saveRevision")
	var archive_path_value: Variant = request.get("archivePath")
	if (
		not slot_id_value is String
		or not session_id_value is String
		or not _is_positive_integer_number(save_revision_value)
		or not archive_path_value is String
	):
		return _failure("FORMAL_SLOT_ARCHIVE_FINALIZE_CONTEXT_INVALID", false)
	var slot_id := slot_id_value as String
	var session_id := session_id_value as String
	var archive_path := archive_path_value as String
	if (
		slot_id != slot_id.strip_edges()
		or session_id != session_id.strip_edges()
		or archive_path != archive_path.strip_edges()
		or not _valid_slot_id(slot_id)
		or not _valid_slot_id(session_id)
		or not _archive_root_matches_slot(archive_path, slot_id)
	):
		return _failure("FORMAL_SLOT_ARCHIVE_FINALIZE_CONTEXT_INVALID", false)
	var lease := _begin_archive_lease(slot_id)
	if lease.get("ok") != true:
		return lease
	var recovered := _recover_pending_archives(slot_id)
	if recovered.get("ok") != true:
		return _finish_archive_lease(lease, recovered)
	return _finish_archive_lease(
		lease,
		_with_recovery_change(
			_finalize_completed_new_game_archive({
				"slotId": slot_id,
				"sessionId": session_id,
				"saveRevision": int(save_revision_value),
				"archivePath": archive_path,
			}),
			recovered,
		),
	)


func archive_for_player_delete(request: Dictionary) -> Dictionary:
	var slot_id_value: Variant = request.get("slotId")
	if not slot_id_value is String:
		return _failure("FORMAL_SLOT_DELETE_SLOT_ID_INVALID", false)
	var slot_id := slot_id_value as String
	if slot_id != slot_id.strip_edges() or not _valid_slot_id(slot_id):
		return _failure("FORMAL_SLOT_DELETE_SLOT_ID_INVALID", false)
	var session_id_value: Variant = request.get("sessionId")
	var save_revision_value: Variant = request.get("saveRevision")
	var expected_state_value: Variant = request.get("expectedState")
	if (
		not session_id_value is String
		or not _is_non_negative_integer_number(save_revision_value)
		or not expected_state_value is String
	):
		return _failure("FORMAL_SLOT_DELETE_CONTEXT_INVALID", false)
	var session_id := session_id_value as String
	var save_revision := int(save_revision_value)
	var expected_state := expected_state_value as String
	if (
		session_id != session_id.strip_edges()
		or expected_state != expected_state.strip_edges()
		or expected_state.is_empty()
	):
		return _failure("FORMAL_SLOT_DELETE_CONTEXT_INVALID", false)
	if not session_id.is_empty():
		if save_revision < 1:
			return _failure("FORMAL_SLOT_DELETE_CONTEXT_INVALID", false)
		var complete_lease := _begin_archive_lease(slot_id)
		if complete_lease.get("ok") != true:
			return complete_lease
		var recovered := _recover_pending_archives(slot_id)
		if recovered.get("ok") != true:
			return _finish_archive_lease(complete_lease, recovered)
		var completed := _completed_archive_result_for_request(
			request,
			"player_delete",
		)
		if completed.get("found") == true:
			return _finish_archive_lease(
				complete_lease,
				_with_recovery_change(completed, recovered),
			)
		return _finish_archive_lease(
			complete_lease,
			_with_recovery_change(
				_archive_complete_pair(request, "player_delete"),
				recovered,
			),
		)
	if save_revision != 0:
		return _failure("FORMAL_SLOT_DELETE_CONTEXT_INVALID", false)
	if not UNVERIFIED_DELETE_STATES.has(expected_state):
		return _failure("FORMAL_SLOT_DELETE_CONTEXT_INVALID", false)
	var lease := _begin_archive_lease(slot_id)
	if lease.get("ok") != true:
		return lease
	var recovered := _recover_pending_archives(slot_id)
	if recovered.get("ok") != true:
		return _finish_archive_lease(lease, recovered)
	var completed := _completed_archive_result_for_request(
		request,
		"player_delete",
	)
	if completed.get("found") == true:
		return _finish_archive_lease(
			lease,
			_with_recovery_change(completed, recovered),
		)
	return _finish_archive_lease(
		lease,
		_with_recovery_change(
			_archive_unverified_slot_for_player_delete(
				slot_id,
				expected_state,
			),
			recovered,
		),
	)


func _archive_complete_pair(request: Dictionary, reason: String) -> Dictionary:
	var context_result := SAVE_MANIFEST.validate_context(
		TownSaveContext.camel_to_snake(request),
	) as Dictionary
	if not bool(context_result.get("ok", false)):
		return _failure("FORMAL_SLOT_ARCHIVE_CONTEXT_INVALID", false)
	var context := context_result.get("context", {}) as Dictionary
	var slot_id := String(context.get("slot_id", ""))
	var session_id := String(context.get("session_id", ""))
	var save_revision := int(context.get("save_revision", 0))
	var world_slot := _join(_world_slots_root, slot_id)
	var agent_slot := _join(_agent_slots_root, slot_id)
	var photo_slot := _join(_photo_slots_root, slot_id)
	var photo_exists := DirAccess.dir_exists_absolute(_absolute(photo_slot))
	var manifest_path := _join(
		world_slot,
		"manifests/%020d.json" % save_revision,
	)
	var agent_revision := _join(
		agent_slot,
		"sessions/%s/revisions/%d" % [session_id, save_revision],
	)
	if not DirAccess.dir_exists_absolute(_absolute(world_slot)):
		return _failure("FORMAL_SLOT_ARCHIVE_WORLD_SLOT_MISSING", false)
	if not DirAccess.dir_exists_absolute(_absolute(agent_slot)):
		return _failure("FORMAL_SLOT_ARCHIVE_AGENT_SLOT_MISSING", false)
	if not DirAccess.dir_exists_absolute(_absolute(agent_revision)):
		return _failure("FORMAL_SLOT_ARCHIVE_AGENT_REVISION_MISSING", false)
	var loaded_manifest := _read_json(manifest_path)
	if not bool(loaded_manifest.get("ok", false)):
		return _failure("FORMAL_SLOT_ARCHIVE_MANIFEST_UNREADABLE", false)
	var manifest := loaded_manifest.get("value", {}) as Dictionary
	if not bool(SAVE_MANIFEST.validate(manifest).get("ok", false)):
		return _failure("FORMAL_SLOT_ARCHIVE_MANIFEST_INVALID", false)
	if (
		String(manifest.get("slot_id", "")) != slot_id
		or String(manifest.get("session_id", "")) != session_id
		or int(manifest.get("save_revision", -1)) != save_revision
	):
		return _failure("FORMAL_SLOT_ARCHIVE_SAVE_CHANGED", false)
	var latest_manifest := _latest_published_context(
		world_slot,
		agent_slot,
		slot_id,
	)
	if not bool(latest_manifest.get("ok", false)):
		return latest_manifest
	if (
		(latest_manifest.get("context", {}) as Dictionary)
		!= context
	):
		return _failure("FORMAL_SLOT_ARCHIVE_SAVE_CHANGED", false)

	var backup_parent_error := DirAccess.make_dir_recursive_absolute(
		_absolute(_backup_root),
	)
	if backup_parent_error != OK:
		return _failure("FORMAL_SLOT_ARCHIVE_BACKUP_ROOT_FAILED", true)
	var archive_root := _next_archive_root(slot_id, save_revision)
	var create_error := DirAccess.make_dir_recursive_absolute(_absolute(archive_root))
	if create_error != OK:
		return _failure("FORMAL_SLOT_ARCHIVE_BACKUP_CREATE_FAILED", true)
	if not _begin_archive_transaction(
		archive_root,
		slot_id,
		true,
		true,
		photo_exists,
	):
		_remove_failed_archive_root(archive_root)
		return _failure(
			"FORMAL_SLOT_ARCHIVE_TRANSACTION_WRITE_FAILED",
			true,
		)
	if not _participant_layout_matches(
		archive_root,
		slot_id,
		true,
		true,
		photo_exists,
		false,
	):
		_remove_failed_archive_root(archive_root)
		return _failure(
			"FORMAL_SLOT_ARCHIVE_PARTICIPANT_CHANGED",
			true,
		)
	var archived_world_slot := _join(archive_root, "world_slot")
	var archived_agent_slot := _join(archive_root, "agent_slot")
	var archived_photo_slot := _join(archive_root, "conversation_photos")
	var world_move_error := _rename_absolute(
		_absolute(world_slot),
		_absolute(archived_world_slot),
	)
	if world_move_error != OK:
		_remove_failed_archive_root(archive_root)
		return _failure("FORMAL_SLOT_ARCHIVE_WORLD_MOVE_FAILED", true)
	var moved_latest_manifest := _latest_published_context(
		archived_world_slot,
		agent_slot,
		slot_id,
	)
	if (
		not bool(moved_latest_manifest.get("ok", false))
		or (
			(moved_latest_manifest.get("context", {}) as Dictionary)
			!= context
		)
	):
		var rollback_error := _rename_absolute(
			_absolute(archived_world_slot),
			_absolute(world_slot),
		)
		if rollback_error != OK:
			return _failure("FORMAL_SLOT_ARCHIVE_ROLLBACK_FAILED", false, {
				"archivePath": archive_root,
			}, true)
		_remove_failed_archive_root(archive_root)
		if not bool(moved_latest_manifest.get("ok", false)):
			return moved_latest_manifest
		return _failure("FORMAL_SLOT_ARCHIVE_SAVE_CHANGED", false)
	var agent_move_error := _rename_absolute(
		_absolute(agent_slot),
		_absolute(archived_agent_slot),
	)
	if agent_move_error != OK:
		var rollback_error := _rename_absolute(
			_absolute(archived_world_slot),
			_absolute(world_slot),
		)
		if rollback_error != OK:
			return _failure("FORMAL_SLOT_ARCHIVE_ROLLBACK_FAILED", false, {
				"archivePath": archive_root,
			}, true)
		_remove_failed_archive_root(archive_root)
		return _failure("FORMAL_SLOT_ARCHIVE_AGENT_MOVE_FAILED", true)
	if photo_exists:
		var photo_move_error := _rename_absolute(
			_absolute(photo_slot),
			_absolute(archived_photo_slot),
		)
		if photo_move_error != OK:
			var agent_rollback_error := _rename_absolute(
				_absolute(archived_agent_slot),
				_absolute(agent_slot),
			)
			var world_rollback_error := _rename_absolute(
				_absolute(archived_world_slot),
				_absolute(world_slot),
			)
			if (
				agent_rollback_error != OK
				or world_rollback_error != OK
			):
				return _failure(
					"FORMAL_SLOT_ARCHIVE_ROLLBACK_FAILED",
					false,
					{"archivePath": archive_root},
					true,
				)
			_remove_failed_archive_root(archive_root)
			return _failure(
				"FORMAL_SLOT_ARCHIVE_PHOTO_MOVE_FAILED",
				true,
			)
	if not _ensure_photo_write_blocker(slot_id):
		if not _rollback_archive_participants(
			archive_root,
			slot_id,
			true,
			true,
			photo_exists,
		):
			return _failure(
				"FORMAL_SLOT_ARCHIVE_ROLLBACK_FAILED",
				false,
				{"archivePath": archive_root},
				true,
			)
		_remove_failed_archive_root(archive_root)
		return _failure(
			"FORMAL_SLOT_ARCHIVE_PARTICIPANT_CHANGED",
			true,
		)
	if not _participant_layout_matches(
		archive_root,
		slot_id,
		true,
		true,
		photo_exists,
		true,
	):
		if not _rollback_archive_participants(
			archive_root,
			slot_id,
			true,
			true,
			photo_exists,
		):
			return _failure(
				"FORMAL_SLOT_ARCHIVE_ROLLBACK_FAILED",
				false,
				{"archivePath": archive_root},
				true,
			)
		_remove_failed_archive_root(archive_root)
		return _failure(
			"FORMAL_SLOT_ARCHIVE_PARTICIPANT_CHANGED",
			true,
		)

	var metadata_written := _write_json(_join(archive_root, "archive.json"), {
		"schema": "ai-town-formal-slot-archive",
		"schema_version": 1,
		"reason": reason,
		"archived_at": Time.get_datetime_string_from_system(false, true),
		"slot_id": slot_id,
		"session_id": session_id,
		"save_revision": save_revision,
		"conversation_photos_present": photo_exists,
	})
	if not metadata_written:
		if not _remove_photo_write_blocker(slot_id):
			return _failure(
				"FORMAL_SLOT_ARCHIVE_ROLLBACK_FAILED",
				false,
				{"archivePath": archive_root},
				true,
			)
		var photo_rollback_error := OK
		if photo_exists:
			photo_rollback_error = _rename_absolute(
				_absolute(archived_photo_slot),
				_absolute(photo_slot),
			)
		var agent_rollback_error := _rename_absolute(
			_absolute(archived_agent_slot),
			_absolute(agent_slot),
		)
		var world_rollback_error := _rename_absolute(
			_absolute(archived_world_slot),
			_absolute(world_slot),
		)
		if (
			photo_rollback_error != OK
			or agent_rollback_error != OK
			or world_rollback_error != OK
		):
			return _failure(
				(
					"FORMAL_SLOT_DELETE_ROLLBACK_FAILED"
					if reason == "player_delete"
					else "FORMAL_SLOT_ARCHIVE_ROLLBACK_FAILED"
				),
				false,
				{"archivePath": archive_root},
				true,
			)
		_remove_failed_archive_root(archive_root)
		return _failure(
			(
				"FORMAL_SLOT_DELETE_METADATA_WRITE_FAILED"
				if reason == "player_delete"
				else "FORMAL_SLOT_ARCHIVE_METADATA_WRITE_FAILED"
			),
			true,
		)
	if not _completed_archive_state_is_valid(archive_root, slot_id):
		return _failure(
			"FORMAL_SLOT_ARCHIVE_COMPLETION_INVALID",
			false,
			{"archivePath": archive_root},
			true,
		)
	if not _commit_archive_transaction(archive_root):
		return _failure(
			"FORMAL_SLOT_ARCHIVE_RECOVERY_PENDING",
			true,
			{"archivePath": archive_root},
			true,
		)
	if not _completed_archive_receipt_is_valid(archive_root, slot_id):
		var reopened := _reopen_archive_transaction(archive_root)
		var invalid := _failure(
			"FORMAL_SLOT_ARCHIVE_COMPLETION_INVALID",
			false,
			{"archivePath": archive_root},
			true,
		)
		invalid["preservePending"] = not reopened
		return invalid
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"changed": true,
		"archivePath": archive_root,
		"metadataWritten": metadata_written,
		"transactionCleanupPending": false,
		"context": context.duplicate(true),
	}


func _archive_unverified_slot_for_player_delete(
	slot_id: String,
	expected_state: String,
	archive_reason := "player_delete",
) -> Dictionary:
	var world_slot := _join(_world_slots_root, slot_id)
	var agent_slot := _join(_agent_slots_root, slot_id)
	var photo_slot := _join(_photo_slots_root, slot_id)
	var world_exists := DirAccess.dir_exists_absolute(_absolute(world_slot))
	var agent_exists := DirAccess.dir_exists_absolute(_absolute(agent_slot))
	var photo_exists := DirAccess.dir_exists_absolute(_absolute(photo_slot))
	if not world_exists and not agent_exists and not photo_exists:
		return _failure("FORMAL_SLOT_DELETE_SLOT_MISSING", false)
	if (
		world_exists
		and _has_complete_published_pair(
			world_slot,
			agent_slot,
			slot_id,
		)
	):
		return _failure("FORMAL_SLOT_DELETE_CONTEXT_INVALID", false)
	var backup_parent_error := DirAccess.make_dir_recursive_absolute(
		_absolute(_backup_root),
	)
	if backup_parent_error != OK:
		return _failure("FORMAL_SLOT_DELETE_BACKUP_ROOT_FAILED", true)
	var archive_root := _next_archive_root(slot_id, 0)
	var create_error := DirAccess.make_dir_recursive_absolute(_absolute(archive_root))
	if create_error != OK:
		return _failure("FORMAL_SLOT_DELETE_BACKUP_CREATE_FAILED", true)
	if not _begin_archive_transaction(
		archive_root,
		slot_id,
		world_exists,
		agent_exists,
		photo_exists,
	):
		_remove_failed_archive_root(archive_root)
		return _failure(
			"FORMAL_SLOT_DELETE_TRANSACTION_WRITE_FAILED",
			true,
		)
	if not _participant_layout_matches(
		archive_root,
		slot_id,
		world_exists,
		agent_exists,
		photo_exists,
		false,
	):
		_remove_failed_archive_root(archive_root)
		return _failure(
			"FORMAL_SLOT_DELETE_PARTICIPANT_CHANGED",
			true,
		)
	var archived_world_slot := _join(archive_root, "world_slot")
	var archived_agent_slot := _join(archive_root, "agent_slot")
	var archived_photo_slot := _join(archive_root, "conversation_photos")
	if world_exists:
		var world_move_error := _rename_absolute(
			_absolute(world_slot),
			_absolute(archived_world_slot),
		)
		if world_move_error != OK:
			_remove_failed_archive_root(archive_root)
			return _failure("FORMAL_SLOT_DELETE_WORLD_MOVE_FAILED", true)
	if agent_exists:
		var agent_move_error := _rename_absolute(
			_absolute(agent_slot),
			_absolute(archived_agent_slot),
		)
		if agent_move_error != OK:
			if world_exists:
				var rollback_error := _rename_absolute(
					_absolute(archived_world_slot),
					_absolute(world_slot),
				)
				if rollback_error != OK:
					return _failure(
						"FORMAL_SLOT_DELETE_ROLLBACK_FAILED",
						false,
						{"archivePath": archive_root},
						true,
					)
			_remove_failed_archive_root(archive_root)
			return _failure("FORMAL_SLOT_DELETE_AGENT_MOVE_FAILED", true)
	if photo_exists:
		var photo_move_error := _rename_absolute(
			_absolute(photo_slot),
			_absolute(archived_photo_slot),
		)
		if photo_move_error != OK:
			var agent_rollback_error := OK
			if agent_exists:
				agent_rollback_error = _rename_absolute(
					_absolute(archived_agent_slot),
					_absolute(agent_slot),
				)
			var world_rollback_error := OK
			if world_exists:
				world_rollback_error = _rename_absolute(
					_absolute(archived_world_slot),
					_absolute(world_slot),
				)
			if (
				agent_rollback_error != OK
				or world_rollback_error != OK
			):
				return _failure(
					"FORMAL_SLOT_DELETE_ROLLBACK_FAILED",
					false,
					{"archivePath": archive_root},
					true,
				)
			_remove_failed_archive_root(archive_root)
			return _failure("FORMAL_SLOT_DELETE_PHOTO_MOVE_FAILED", true)
	if not _ensure_photo_write_blocker(slot_id):
		if not _rollback_archive_participants(
			archive_root,
			slot_id,
			world_exists,
			agent_exists,
			photo_exists,
		):
			return _failure(
				"FORMAL_SLOT_DELETE_ROLLBACK_FAILED",
				false,
				{"archivePath": archive_root},
				true,
			)
		_remove_failed_archive_root(archive_root)
		return _failure(
			"FORMAL_SLOT_DELETE_PARTICIPANT_CHANGED",
			true,
		)
	if not _participant_layout_matches(
		archive_root,
		slot_id,
		world_exists,
		agent_exists,
		photo_exists,
		true,
	):
		if not _rollback_archive_participants(
			archive_root,
			slot_id,
			world_exists,
			agent_exists,
			photo_exists,
		):
			return _failure(
				"FORMAL_SLOT_DELETE_ROLLBACK_FAILED",
				false,
				{"archivePath": archive_root},
				true,
			)
		_remove_failed_archive_root(archive_root)
		return _failure(
			"FORMAL_SLOT_DELETE_PARTICIPANT_CHANGED",
			true,
		)
	var metadata_written := _write_json(
		_join(archive_root, ARCHIVE_METADATA_FILE),
		{
			"schema": "ai-town-formal-slot-archive",
			"schema_version": 1,
			"reason": archive_reason,
			"archived_at": Time.get_datetime_string_from_system(false, true),
			"slot_id": slot_id,
			"session_id": "",
			"save_revision": 0,
			"expected_state": expected_state,
			"world_participant_present": world_exists,
			"agent_participant_present": agent_exists,
			"conversation_photos_present": photo_exists,
		},
	)
	if not metadata_written:
		if not _remove_photo_write_blocker(slot_id):
			return _failure(
				"FORMAL_SLOT_DELETE_ROLLBACK_FAILED",
				false,
				{"archivePath": archive_root},
				true,
			)
		var photo_rollback_error := OK
		if photo_exists:
			photo_rollback_error = _rename_absolute(
				_absolute(archived_photo_slot),
				_absolute(photo_slot),
			)
		var agent_rollback_error := OK
		if agent_exists:
			agent_rollback_error = _rename_absolute(
				_absolute(archived_agent_slot),
				_absolute(agent_slot),
			)
		var world_rollback_error := OK
		if world_exists:
			world_rollback_error = _rename_absolute(
				_absolute(archived_world_slot),
				_absolute(world_slot),
			)
		if (
			photo_rollback_error != OK
			or agent_rollback_error != OK
			or world_rollback_error != OK
		):
			return _failure(
				"FORMAL_SLOT_DELETE_ROLLBACK_FAILED",
				false,
				{"archivePath": archive_root},
				true,
			)
		_remove_failed_archive_root(archive_root)
		return _failure("FORMAL_SLOT_DELETE_METADATA_WRITE_FAILED", true)
	if not _completed_archive_state_is_valid(archive_root, slot_id):
		return _failure(
			"FORMAL_SLOT_DELETE_COMPLETION_INVALID",
			false,
			{"archivePath": archive_root},
			true,
		)
	if not _commit_archive_transaction(archive_root):
		return _failure(
			"FORMAL_SLOT_ARCHIVE_RECOVERY_PENDING",
			true,
			{"archivePath": archive_root},
			true,
		)
	if not _completed_archive_receipt_is_valid(archive_root, slot_id):
		var reopened := _reopen_archive_transaction(archive_root)
		var invalid := _failure(
			"FORMAL_SLOT_ARCHIVE_COMPLETION_INVALID",
			false,
			{"archivePath": archive_root},
			true,
		)
		invalid["preservePending"] = not reopened
		return invalid
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"changed": true,
		"archivePath": archive_root,
		"metadataWritten": true,
		"transactionCleanupPending": false,
		"context": {
			"slot_id": slot_id,
			"session_id": "",
			"save_revision": 0,
		},
	}


func archive_unpaired_agent_slot_for_new_game(slot_id: String) -> Dictionary:
	var normalized_slot_id := slot_id.strip_edges()
	if slot_id != normalized_slot_id or not _valid_slot_id(normalized_slot_id):
		return _failure("FORMAL_SLOT_ARCHIVE_SLOT_ID_INVALID", false)
	var lease := _begin_archive_lease(normalized_slot_id)
	if (
		lease.get("ok") != true
		and OS.get_name() == "Web"
		and lease.get("errorCode") == "FORMAL_SLOT_ARCHIVE_STORE_FAILED"
	):
		# A previous interrupted Web startup can leave a malformed archive claim
		# before any World revision is published.  It is not a player-loadable
		# save, so repair only that claim and retry the normal archive lease.  A
		# published revision or a live owner remains fail-closed in the store.
		var residue := _save_store.recover_unpublished_slot_lease_residue(
			normalized_slot_id,
		)
		if residue.get("ok") == true:
			# Web's persistent filesystem can reject a second directory-claim
			# rename even after the malformed residue is removed.  There is no
			# published World revision in this branch, so finish the isolated
			# Agent/photo quarantine directly; a concurrent published save is
			# still protected by the no-published-revision check above.
			var recovered := _recover_pending_archives(normalized_slot_id)
			if recovered.get("ok") != true:
				return recovered
			return _with_recovery_change(
				_archive_unpaired_agent_slot_for_new_game(normalized_slot_id),
				recovered,
			)
	if lease.get("ok") != true:
		return lease
	var recovered := _recover_pending_archives(normalized_slot_id)
	if recovered.get("ok") != true:
		return _finish_archive_lease(lease, recovered)
	var result := _archive_unpaired_agent_slot_for_new_game(
		normalized_slot_id,
	)
	return _finish_archive_lease(
		lease,
		_with_recovery_change(result, recovered),
	)


func _archive_unpaired_agent_slot_for_new_game(
	normalized_slot_id: String,
) -> Dictionary:
	var world_slot := _join(_world_slots_root, normalized_slot_id)
	var agent_slot := _join(_agent_slots_root, normalized_slot_id)
	var photo_slot := _join(_photo_slots_root, normalized_slot_id)
	var agent_exists := DirAccess.dir_exists_absolute(_absolute(agent_slot))
	var photo_exists := DirAccess.dir_exists_absolute(_absolute(photo_slot))
	if DirAccess.dir_exists_absolute(_absolute(world_slot)):
		if _has_complete_published_pair(world_slot, agent_slot, normalized_slot_id):
			return _failure("FORMAL_SLOT_RECOVERY_WORLD_STATE_PRESENT", false)
		return _archive_unverified_slot_for_player_delete(
			normalized_slot_id,
			"unpaired_world_slot_recovery",
			"unpaired_world_slot_recovery",
		)
	if not agent_exists and not photo_exists:
		return _success(false)
	var backup_parent_error := DirAccess.make_dir_recursive_absolute(
		_absolute(_backup_root),
	)
	if backup_parent_error != OK:
		return _failure("FORMAL_SLOT_ARCHIVE_BACKUP_ROOT_FAILED", true)
	var archive_root := _next_archive_root(normalized_slot_id, 0)
	var create_error := DirAccess.make_dir_recursive_absolute(_absolute(archive_root))
	if create_error != OK:
		return _failure("FORMAL_SLOT_ARCHIVE_BACKUP_CREATE_FAILED", true)
	if not _begin_archive_transaction(
		archive_root,
		normalized_slot_id,
		false,
		agent_exists,
		photo_exists,
	):
		_remove_failed_archive_root(archive_root)
		return _failure(
			"FORMAL_SLOT_ARCHIVE_TRANSACTION_WRITE_FAILED",
			true,
		)
	if not _participant_layout_matches(
		archive_root,
		normalized_slot_id,
		false,
		agent_exists,
		photo_exists,
		false,
	):
		_remove_failed_archive_root(archive_root)
		return _failure(
			"FORMAL_SLOT_ARCHIVE_PARTICIPANT_CHANGED",
			true,
		)
	var archived_agent_slot := _join(archive_root, "agent_slot")
	var archived_photo_slot := _join(archive_root, "conversation_photos")
	if agent_exists:
		var move_error := _rename_absolute(
			_absolute(agent_slot),
			_absolute(archived_agent_slot),
		)
		if move_error != OK:
			_remove_failed_archive_root(archive_root)
			return _failure("FORMAL_SLOT_ARCHIVE_AGENT_MOVE_FAILED", true)
	if photo_exists:
		var photo_move_error := _rename_absolute(
			_absolute(photo_slot),
			_absolute(archived_photo_slot),
		)
		if photo_move_error != OK:
			var rollback_error := OK
			if agent_exists:
				rollback_error = _rename_absolute(
					_absolute(archived_agent_slot),
					_absolute(agent_slot),
				)
			if rollback_error != OK:
				return _failure(
					"FORMAL_SLOT_ARCHIVE_ROLLBACK_FAILED",
					false,
					{"archivePath": archive_root},
					true,
				)
			_remove_failed_archive_root(archive_root)
			return _failure(
				"FORMAL_SLOT_ARCHIVE_PHOTO_MOVE_FAILED",
				true,
			)
	if not _ensure_photo_write_blocker(normalized_slot_id):
		if not _rollback_archive_participants(
			archive_root,
			normalized_slot_id,
			false,
			agent_exists,
			photo_exists,
		):
			return _failure(
				"FORMAL_SLOT_ARCHIVE_ROLLBACK_FAILED",
				false,
				{"archivePath": archive_root},
				true,
			)
		_remove_failed_archive_root(archive_root)
		return _failure(
			"FORMAL_SLOT_ARCHIVE_PARTICIPANT_CHANGED",
			true,
		)
	if not _participant_layout_matches(
		archive_root,
		normalized_slot_id,
		false,
		agent_exists,
		photo_exists,
		true,
	):
		if not _rollback_archive_participants(
			archive_root,
			normalized_slot_id,
			false,
			agent_exists,
			photo_exists,
		):
			return _failure(
				"FORMAL_SLOT_ARCHIVE_ROLLBACK_FAILED",
				false,
				{"archivePath": archive_root},
				true,
			)
		_remove_failed_archive_root(archive_root)
		return _failure(
			"FORMAL_SLOT_ARCHIVE_PARTICIPANT_CHANGED",
			true,
		)
	var metadata_written := _write_json(_join(archive_root, "archive.json"), {
		"schema": "ai-town-formal-slot-archive",
		"schema_version": 1,
		"reason": "unpaired_agent_slot_recovery",
		"archived_at": Time.get_datetime_string_from_system(false, true),
		"slot_id": normalized_slot_id,
		"save_revision": 0,
		"agent_slot_present": agent_exists,
		"conversation_photos_present": photo_exists,
	})
	if not metadata_written:
		if not _remove_photo_write_blocker(normalized_slot_id):
			return _failure(
				"FORMAL_SLOT_ARCHIVE_ROLLBACK_FAILED",
				false,
				{"archivePath": archive_root},
				true,
			)
		var photo_rollback_error := OK
		if photo_exists:
			photo_rollback_error = _rename_absolute(
				_absolute(archived_photo_slot),
				_absolute(photo_slot),
			)
		var agent_rollback_error := OK
		if agent_exists:
			agent_rollback_error = _rename_absolute(
				_absolute(archived_agent_slot),
				_absolute(agent_slot),
			)
		if photo_rollback_error != OK or agent_rollback_error != OK:
			return _failure(
				"FORMAL_SLOT_ARCHIVE_ROLLBACK_FAILED",
				false,
				{"archivePath": archive_root},
				true,
			)
		_remove_failed_archive_root(archive_root)
		return _failure("FORMAL_SLOT_ARCHIVE_METADATA_WRITE_FAILED", true)
	if not _completed_archive_state_is_valid(
		archive_root,
		normalized_slot_id,
	):
		return _failure(
			"FORMAL_SLOT_ARCHIVE_COMPLETION_INVALID",
			false,
			{"archivePath": archive_root},
			true,
		)
	if not _commit_archive_transaction(archive_root):
		return _failure(
			"FORMAL_SLOT_ARCHIVE_RECOVERY_PENDING",
			true,
			{"archivePath": archive_root},
			true,
		)
	if not _completed_archive_receipt_is_valid(
		archive_root,
		normalized_slot_id,
	):
		var reopened := _reopen_archive_transaction(archive_root)
		var invalid := _failure(
			"FORMAL_SLOT_ARCHIVE_COMPLETION_INVALID",
			false,
			{"archivePath": archive_root},
			true,
		)
		invalid["preservePending"] = not reopened
		return invalid
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"changed": true,
		"archivePath": archive_root,
		"metadataWritten": metadata_written,
		"transactionCleanupPending": false,
	}


func _begin_archive_transaction(
	archive_root: String,
	slot_id: String,
	world_present: bool,
	agent_present: bool,
	photo_present: bool,
) -> bool:
	return _write_transaction_json(
		_join(archive_root, TRANSACTION_FILE),
		{
			"schema": TRANSACTION_SCHEMA,
			"schema_version": 1,
			"slot_id": slot_id,
			"world_present": world_present,
			"agent_present": agent_present,
			"photo_present": photo_present,
		},
	)


func _participant_layout_matches(
	archive_root: String,
	slot_id: String,
	world_present: bool,
	agent_present: bool,
	photo_present: bool,
	archived: bool,
) -> bool:
	var participants: Array[Dictionary] = [
		{
			"present": world_present,
			"source": _join(_world_slots_root, slot_id),
			"target": _join(archive_root, "world_slot"),
		},
		{
			"present": agent_present,
			"source": _join(_agent_slots_root, slot_id),
			"target": _join(archive_root, "agent_slot"),
		},
		{
			"present": photo_present,
			"source": _join(_photo_slots_root, slot_id),
			"target": _join(archive_root, "conversation_photos"),
		},
	]
	for participant: Dictionary in participants:
		var source_exists := DirAccess.dir_exists_absolute(
			_absolute(String(participant.get("source", ""))),
		)
		var target_exists := DirAccess.dir_exists_absolute(
			_absolute(String(participant.get("target", ""))),
		)
		if participant.get("present") == true:
			if archived:
				if source_exists or not target_exists:
					return false
			elif not source_exists or target_exists:
				return false
		elif source_exists or target_exists:
			return false
	return true


func _rollback_archive_participants(
	archive_root: String,
	slot_id: String,
	world_present: bool,
	agent_present: bool,
	photo_present: bool,
) -> bool:
	if not _remove_photo_write_blocker(slot_id):
		return false
	var participants: Array[Dictionary] = [
		{
			"present": photo_present,
			"source": _join(_photo_slots_root, slot_id),
			"target": _join(archive_root, "conversation_photos"),
		},
		{
			"present": agent_present,
			"source": _join(_agent_slots_root, slot_id),
			"target": _join(archive_root, "agent_slot"),
		},
		{
			"present": world_present,
			"source": _join(_world_slots_root, slot_id),
			"target": _join(archive_root, "world_slot"),
		},
	]
	for participant: Dictionary in participants:
		if participant.get("present") != true:
			continue
		var source := String(participant.get("source", ""))
		var target := String(participant.get("target", ""))
		var source_exists := DirAccess.dir_exists_absolute(_absolute(source))
		var target_exists := DirAccess.dir_exists_absolute(_absolute(target))
		if source_exists and not target_exists:
			continue
		if source_exists or not target_exists:
			return false
		if _rename_absolute(_absolute(target), _absolute(source)) != OK:
			return false
	return true


func _recover_interrupted_new_game_overwrite(slot_id: String) -> Dictionary:
	var candidate := _latest_completed_new_game_restore_request(slot_id)
	if candidate.get("ok") != true:
		return candidate
	if candidate.get("found") != true:
		return _success(false)
	var world_slot := _join(_world_slots_root, slot_id)
	var agent_slot := _join(_agent_slots_root, slot_id)
	var active_context := _latest_published_context(
		world_slot,
		agent_slot,
		slot_id,
	)
	if active_context.get("ok") == true:
		return _finalize_completed_new_game_archive(
			candidate.get("request", {}) as Dictionary,
		)
	var active_state := _validate_interrupted_active_state(slot_id)
	if active_state.get("ok") != true:
		return active_state
	var restore_request := (
		candidate.get("request", {}) as Dictionary
	).duplicate(true)
	var archive_root := String(restore_request.get("archivePath", ""))
	var quarantined := _quarantine_interrupted_active_state(
		slot_id,
		archive_root,
		active_state,
	)
	if quarantined.get("ok") != true:
		return quarantined
	if not _ensure_photo_write_blocker(slot_id):
		var blocker_rollback := _restore_quarantined_interrupted_state(
			slot_id,
			archive_root,
			quarantined,
		)
		if blocker_rollback.get("ok") != true:
			return _interrupted_restore_rollback_failure(
				"FORMAL_SLOT_ARCHIVE_INTERRUPTED_BLOCKER_FAILED",
				archive_root,
				blocker_rollback,
			)
		return _failure(
			"FORMAL_SLOT_ARCHIVE_INTERRUPTED_BLOCKER_FAILED",
			true,
			{"archivePath": archive_root},
		)
	var restored := _restore_completed_new_game_archive(restore_request)
	if restored.get("ok") != true:
		var state_rollback := _restore_quarantined_interrupted_state(
			slot_id,
			archive_root,
			quarantined,
		)
		if state_rollback.get("ok") != true:
			return _interrupted_restore_rollback_failure(
				String(restored.get(
					"errorCode",
					"FORMAL_SLOT_ARCHIVE_RESTORE_FAILED",
				)),
				archive_root,
				state_rollback,
			)
		return restored
	var cleanup_complete := _remove_interrupted_quarantine(
		archive_root,
		quarantined,
	)
	_remove_empty_archive_root(archive_root)
	var recovered := restored.duplicate(true)
	recovered["recoveredInterruptedOverwrite"] = true
	recovered["interruptedStateCleared"] = cleanup_complete
	if not cleanup_complete:
		recovered["cleanupPending"] = true
		recovered["archivePath"] = archive_root
	return recovered


func _finalize_completed_new_game_archive(
	request: Dictionary,
) -> Dictionary:
	var slot_id := String(request.get("slotId", ""))
	var archive_root := String(request.get("archivePath", ""))
	var metadata_result := _read_json(
		_join(archive_root, ARCHIVE_METADATA_FILE),
	)
	if (
		metadata_result.get("ok") != true
		or not metadata_result.get("value") is Dictionary
		or not _completed_new_game_archive_bundle_is_valid(
			archive_root,
			slot_id,
			metadata_result.get("value") as Dictionary,
			request,
		)
	):
		return _failure(
			"FORMAL_SLOT_ARCHIVE_FINALIZE_ARCHIVE_INVALID",
			false,
			{"archivePath": archive_root},
		)
	var active_context := _latest_published_context(
		_join(_world_slots_root, slot_id),
		_join(_agent_slots_root, slot_id),
		slot_id,
	)
	if active_context.get("ok") != true:
		return _failure(
			"FORMAL_SLOT_ARCHIVE_FINALIZE_ACTIVE_PAIR_MISSING",
			true,
			{"archivePath": archive_root},
		)
	var replacement := active_context.get("context", {}) as Dictionary
	if (
		replacement.get("session_id") == request.get("sessionId")
		and replacement.get("save_revision") == request.get("saveRevision")
	):
		return _failure(
			"FORMAL_SLOT_ARCHIVE_FINALIZE_REPLACEMENT_INVALID",
			false,
			{"archivePath": archive_root},
		)
	var receipt_path := _join(archive_root, COMPLETION_RECEIPT_FILE)
	if (
		not FileAccess.file_exists(receipt_path)
		or _remove_absolute(_absolute(receipt_path)) != OK
	):
		return _failure(
			"FORMAL_SLOT_ARCHIVE_FINALIZE_RECEIPT_FAILED",
			true,
			{"archivePath": archive_root},
		)
	var cleanup_complete := _remove_tree(archive_root)
	var result := _success(true)
	result["found"] = true
	result["activePairPreserved"] = true
	result["archiveFinalized"] = true
	result["context"] = replacement.duplicate(true)
	if not cleanup_complete:
		result["cleanupPending"] = true
		result["archivePath"] = archive_root
	return result


func _latest_completed_new_game_restore_request(
	slot_id: String,
) -> Dictionary:
	var slot_backup_root := _slot_backup_root(slot_id)
	if not DirAccess.dir_exists_absolute(_absolute(slot_backup_root)):
		return {"ok": true, "found": false}
	var directory := DirAccess.open(slot_backup_root)
	if directory == null:
		return _failure("FORMAL_SLOT_ARCHIVE_RECOVERY_READ_FAILED", true)
	var completed_records: Array[Dictionary] = []
	for archive_name: String in directory.get_directories():
		var archive_root := _join(slot_backup_root, archive_name)
		if not FileAccess.file_exists(
			_join(archive_root, COMPLETION_RECEIPT_FILE),
		):
			continue
		var loaded_metadata := _read_json(
			_join(archive_root, ARCHIVE_METADATA_FILE),
		)
		if (
			loaded_metadata.get("ok") != true
			or not loaded_metadata.get("value") is Dictionary
		):
			return _failure(
				"FORMAL_SLOT_ARCHIVE_RECOVERY_METADATA_INVALID",
				false,
				{"archivePath": archive_root},
			)
		var metadata := loaded_metadata.get("value") as Dictionary
		if not _valid_archive_timestamp(metadata.get("archived_at")):
			return _failure(
				"FORMAL_SLOT_ARCHIVE_RECOVERY_METADATA_INVALID",
				false,
				{"archivePath": archive_root},
			)
		completed_records.append({
			"archiveName": archive_name,
			"archivePath": archive_root,
			"metadata": metadata,
		})
	completed_records.sort_custom(
		_completed_archive_record_is_newer,
	)
	for record: Dictionary in completed_records:
		var archive_root := String(record.get("archivePath", ""))
		var metadata := record.get("metadata", {}) as Dictionary
		var reason := String(metadata.get("reason", ""))
		if reason == "player_delete":
			if not _completed_archive_history_receipt_is_valid(
				archive_root,
				slot_id,
			):
				return _failure(
					"FORMAL_SLOT_ARCHIVE_RECOVERY_METADATA_INVALID",
					false,
					{"archivePath": archive_root},
				)
			return {
				"ok": true,
				"found": false,
				"suppressedByPlayerDelete": true,
			}
		if reason != "new_game_overwrite":
			continue
		var request := {
			"slotId": slot_id,
			"sessionId": String(metadata.get("session_id", "")),
			"saveRevision": int(metadata.get("save_revision", 0)),
			"archivePath": archive_root,
		}
		if not _completed_new_game_archive_bundle_is_valid(
			archive_root,
			slot_id,
			metadata,
			request,
		):
			return _failure(
				"FORMAL_SLOT_ARCHIVE_RESTORE_ARCHIVE_INVALID",
				false,
				{"archivePath": archive_root},
			)
		return {
			"ok": true,
			"found": true,
			"request": request,
		}
	return {"ok": true, "found": false}


func _completed_archive_record_is_newer(
	left: Dictionary,
	right: Dictionary,
) -> bool:
	var left_metadata := left.get("metadata", {}) as Dictionary
	var right_metadata := right.get("metadata", {}) as Dictionary
	var left_timestamp := String(left_metadata.get("archived_at", ""))
	var right_timestamp := String(right_metadata.get("archived_at", ""))
	if left_timestamp != right_timestamp:
		return left_timestamp > right_timestamp
	var left_name := String(left.get("archiveName", ""))
	var right_name := String(right.get("archiveName", ""))
	var left_format := _archive_name_format(left_name)
	var right_format := _archive_name_format(right_name)
	if left_format != right_format:
		# A current-format record can only have been created after upgrading
		# from the legacy wall-clock name format. Prefer it when both metadata
		# timestamps fall in the same one-second bucket.
		return left_format > right_format
	if left_format == 2:
		var left_sequence := int(left_name.substr(0, 16))
		var right_sequence := int(right_name.substr(0, 16))
		if left_sequence != right_sequence:
			return left_sequence > right_sequence
	return left_name > right_name


func _archive_name_format(archive_name: String) -> int:
	if (
		archive_name.length() > 18
		and archive_name[16] == "-"
		and archive_name[17] == "r"
		and TownSaveScalars.ascii_digits(archive_name.substr(0, 16))
	):
		return 2
	if (
		archive_name.length() > 18
		and archive_name[8] == "-"
		and archive_name[15] == "-"
		and archive_name[16] == "r"
		and TownSaveScalars.ascii_digits(
			archive_name.substr(0, 8) + archive_name.substr(9, 6),
		)
	):
		return 1
	return 0


func _completed_new_game_archive_bundle_is_valid(
	archive_root: String,
	slot_id: String,
	metadata: Dictionary,
	request: Dictionary,
) -> bool:
	if (
		not _archive_root_matches_slot(archive_root, slot_id)
		or FileAccess.file_exists(_join(archive_root, TRANSACTION_FILE))
		or not _has_exact_fields(metadata, [
			"schema",
			"schema_version",
			"reason",
			"archived_at",
			"slot_id",
			"session_id",
			"save_revision",
			"conversation_photos_present",
		])
		or metadata.get("schema") != "ai-town-formal-slot-archive"
		or metadata.get("schema_version") != 1
		or not _valid_archive_timestamp(metadata.get("archived_at"))
		or not _valid_slot_id(String(metadata.get("session_id", "")))
		or not _is_positive_integer_number(metadata.get("save_revision"))
		or not metadata.get("conversation_photos_present") is bool
		or not _archive_metadata_matches_request(
			metadata,
			request,
			"new_game_overwrite",
		)
	):
		return false
	var receipt := _read_json(
		_join(archive_root, COMPLETION_RECEIPT_FILE),
	)
	if (
		receipt.get("ok") != true
		or not receipt.get("value") is Dictionary
	):
		return false
	var transaction := receipt.get("value") as Dictionary
	var photo_present := bool(
		metadata.get("conversation_photos_present", false),
	)
	if (
		not _valid_archive_transaction(transaction, slot_id)
		or transaction.get("world_present") != true
		or transaction.get("agent_present") != true
		or transaction.get("photo_present") != photo_present
		or not DirAccess.dir_exists_absolute(
			_absolute(_join(archive_root, "world_slot")),
		)
		or not DirAccess.dir_exists_absolute(
			_absolute(_join(archive_root, "agent_slot")),
		)
		or (
			DirAccess.dir_exists_absolute(
				_absolute(_join(archive_root, "conversation_photos")),
			)
			!= photo_present
		)
	):
		return false
	var archived_context := _latest_published_context(
		_join(archive_root, "world_slot"),
		_join(archive_root, "agent_slot"),
		slot_id,
	)
	if archived_context.get("ok") != true:
		return false
	var context := archived_context.get("context", {}) as Dictionary
	return (
		context.get("session_id") == request.get("sessionId")
		and context.get("save_revision") == request.get("saveRevision")
	)


func _validate_interrupted_active_state(slot_id: String) -> Dictionary:
	var world_slot := _join(_world_slots_root, slot_id)
	var agent_slot := _join(_agent_slots_root, slot_id)
	var photo_slot := _join(_photo_slots_root, slot_id)
	if (
		FileAccess.file_exists(world_slot)
		or FileAccess.file_exists(agent_slot)
		or (
			FileAccess.file_exists(photo_slot)
			and not _valid_photo_write_blocker(photo_slot, slot_id)
		)
	):
		return _failure(
			"FORMAL_SLOT_ARCHIVE_INTERRUPTED_STATE_AMBIGUOUS",
			false,
			{"slotId": slot_id},
		)
	var world_present := DirAccess.dir_exists_absolute(_absolute(world_slot))
	var agent_present := DirAccess.dir_exists_absolute(_absolute(agent_slot))
	var photo_present := DirAccess.dir_exists_absolute(_absolute(photo_slot))
	var agent_session_id := ""
	if agent_present:
		var agent_state := _interrupted_agent_context(
			agent_slot,
			slot_id,
		)
		if agent_state.get("ok") != true:
			return agent_state
		agent_session_id = String(agent_state.get("sessionId", ""))
	if world_present:
		if not agent_present or not _interrupted_world_state_is_safe(
			world_slot,
			slot_id,
		):
			return _interrupted_state_ambiguous(slot_id, "world")
	if photo_present:
		var photo_state := _interrupted_photo_context(
			photo_slot,
			agent_session_id,
		)
		if photo_state.get("ok") != true:
			return photo_state
		if agent_session_id.is_empty():
			agent_session_id = String(photo_state.get("sessionId", ""))
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"worldPresent": world_present,
		"agentPresent": agent_present,
		"photoPresent": photo_present,
		"sessionId": agent_session_id,
	}


func _interrupted_world_state_is_safe(
	world_slot: String,
	slot_id: String,
) -> bool:
	var manifests_root := _join(world_slot, "manifests")
	if FileAccess.file_exists(manifests_root):
		return false
	if DirAccess.dir_exists_absolute(_absolute(manifests_root)):
		var manifests := DirAccess.open(manifests_root)
		if manifests == null or (
			not manifests.get_files().is_empty()
			or not manifests.get_directories().is_empty()
		):
			return false
	var published := _save_store.list_published(slot_id) as Dictionary
	return (
		published.get("ok") == true
		and published.get("manifests") is Array
		and (published.get("manifests") as Array).is_empty()
		and published.get("invalid") is Array
		and (published.get("invalid") as Array).is_empty()
	)


func _interrupted_agent_context(
	agent_slot: String,
	slot_id: String,
) -> Dictionary:
	var slot_directory := DirAccess.open(agent_slot)
	if slot_directory == null:
		return _interrupted_state_ambiguous(slot_id, "agent")
	var slot_files := slot_directory.get_files()
	var slot_directories := slot_directory.get_directories()
	slot_files.sort()
	slot_directories.sort()
	if slot_files != PackedStringArray(["slot.json"]) or (
		slot_directories != PackedStringArray(["sessions"])
	):
		return _interrupted_state_ambiguous(slot_id, "agent")
	var slot_manifest := _read_json(_join(agent_slot, "slot.json"))
	if (
		slot_manifest.get("ok") != true
		or not slot_manifest.get("value") is Dictionary
	):
		return _interrupted_state_ambiguous(slot_id, "agent")
	var slot_value := slot_manifest.get("value") as Dictionary
	if (
		not _has_exact_fields(slot_value, ["format_version", "slot_id"])
		or slot_value.get("format_version") != AGENT_SAVE_FORMAT_VERSION
		or slot_value.get("slot_id") != slot_id
	):
		return _interrupted_state_ambiguous(slot_id, "agent")
	var sessions_root := _join(agent_slot, "sessions")
	var sessions := DirAccess.open(sessions_root)
	if sessions == null or not sessions.get_files().is_empty():
		return _interrupted_state_ambiguous(slot_id, "agent")
	var session_directories := sessions.get_directories()
	session_directories.sort()
	if session_directories.size() != 1:
		return _interrupted_state_ambiguous(slot_id, "agent")
	var session_id := String(session_directories[0])
	if not _valid_slot_id(session_id):
		return _interrupted_state_ambiguous(slot_id, "agent")
	var session_root := _join(sessions_root, session_id)
	var session_directory := DirAccess.open(session_root)
	if session_directory == null or not session_directory.get_files().is_empty():
		return _interrupted_state_ambiguous(slot_id, "agent")
	var session_children := session_directory.get_directories()
	session_children.sort()
	if session_children != PackedStringArray(["revisions"]):
		return _interrupted_state_ambiguous(slot_id, "agent")
	var revisions_root := _join(session_root, "revisions")
	var revisions := DirAccess.open(revisions_root)
	if revisions == null or not revisions.get_files().is_empty():
		return _interrupted_state_ambiguous(slot_id, "agent")
	var revision_directories := revisions.get_directories()
	if revision_directories.is_empty():
		return _interrupted_state_ambiguous(slot_id, "agent")
	var revision_numbers: Array[int] = []
	for revision_name: String in revision_directories:
		if not TownSaveScalars.ascii_digits(revision_name):
			return _interrupted_state_ambiguous(slot_id, "agent")
		var revision := int(revision_name)
		if str(revision) != revision_name or revision_numbers.has(revision):
			return _interrupted_state_ambiguous(slot_id, "agent")
		revision_numbers.append(revision)
	revision_numbers.sort()
	if revision_numbers[0] != 0:
		return _interrupted_state_ambiguous(slot_id, "agent")
	for index: int in revision_numbers.size():
		if revision_numbers[index] != index:
			return _interrupted_state_ambiguous(slot_id, "agent")
		var revision := revision_numbers[index]
		var revision_root := _join(revisions_root, str(revision))
		var revision_directory := DirAccess.open(revision_root)
		if revision_directory == null:
			return _interrupted_state_ambiguous(slot_id, "agent")
		var revision_files := revision_directory.get_files()
		var revision_children := revision_directory.get_directories()
		revision_files.sort()
		revision_children.sort()
		if not revision_children.is_empty():
			return _interrupted_state_ambiguous(slot_id, "agent")
		var snapshot := _read_json(_join(revision_root, "snapshot.json"))
		if (
			snapshot.get("ok") != true
			or not snapshot.get("value") is Dictionary
		):
			return _interrupted_state_ambiguous(slot_id, "agent")
		var snapshot_value := snapshot.get("value") as Dictionary
		if (
			snapshot_value.get("format_version") != AGENT_SAVE_FORMAT_VERSION
			or snapshot_value.get("slot_id") != slot_id
			or snapshot_value.get("session_id") != session_id
			or snapshot_value.get("save_revision") != revision
		):
			return _interrupted_state_ambiguous(slot_id, "agent")
		var resident_set := _read_json(_join(revision_root, "resident_set.json"))
		if (
			resident_set.get("ok") != true
			or not resident_set.get("value") is Dictionary
		):
			return _interrupted_state_ambiguous(slot_id, "agent")
		if not _valid_interrupted_agent_snapshot(
			revision_root,
			revision_files,
			snapshot_value,
			resident_set.get("value") as Dictionary,
		):
			return _interrupted_state_ambiguous(slot_id, "agent")
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"sessionId": session_id,
		"latestRevision": revision_numbers.back(),
	}


func _valid_interrupted_agent_snapshot(
	revision_root: String,
	revision_files: PackedStringArray,
	snapshot: Dictionary,
	resident_set: Dictionary,
) -> bool:
	if (
		not _has_exact_fields(snapshot, [
			"format_version",
			"slot_id",
			"session_id",
			"save_revision",
			"resident_count",
			"resident_set_sha256",
			"residents",
		])
		or not _has_exact_fields(
			resident_set,
			["resident_ids", "resident_set_sha256"],
		)
		or not snapshot.get("residents") is Array
		or not resident_set.get("resident_ids") is Array
	):
		return false
	var entries := snapshot.get("residents") as Array
	var resident_ids := resident_set.get("resident_ids") as Array
	if (
		not _is_non_negative_integer_number(
			snapshot.get("resident_count"),
		)
		or int(snapshot.get("resident_count", -1)) != entries.size()
		or resident_ids.size() != entries.size()
	):
		return false
	var normalized_ids: Array[String] = []
	for resident_id_value: Variant in resident_ids:
		if not resident_id_value is String:
			return false
		var resident_id := resident_id_value as String
		if (
			not AGENT_FILE_SYSTEM.is_safe_path_segment(resident_id)
			or resident_id != resident_id.to_lower()
			or normalized_ids.has(resident_id)
		):
			return false
		normalized_ids.append(resident_id)
	var sorted_ids := normalized_ids.duplicate()
	sorted_ids.sort()
	if sorted_ids != normalized_ids:
		return false
	var resident_set_digest := _sha256_bytes(
		JSON.stringify(normalized_ids).to_utf8_buffer(),
	)
	if (
		resident_set_digest.is_empty()
		or resident_set.get("resident_set_sha256") != resident_set_digest
		or snapshot.get("resident_set_sha256") != resident_set_digest
	):
		return false
	var expected_files := PackedStringArray([
		"resident_set.json",
		"snapshot.json",
	])
	for index: int in entries.size():
		var entry_value: Variant = entries[index]
		if not entry_value is Dictionary:
			return false
		var entry := entry_value as Dictionary
		if not _has_exact_fields(entry, [
			"resident_id",
			"resident_name",
			"file",
			"byte_length",
			"sha256",
		]):
			return false
		var expected_file := "resident_%04d.bin" % index
		var payload_path := _join(revision_root, expected_file)
		var payload := FileAccess.open(payload_path, FileAccess.READ)
		if (
			entry.get("resident_id") != normalized_ids[index]
			or not entry.get("resident_name") is String
			or String(entry.get("resident_name", "")).strip_edges().is_empty()
			or entry.get("file") != expected_file
			or not _is_non_negative_integer_number(entry.get("byte_length"))
			or payload == null
		):
			return false
		var payload_length := payload.get_length()
		payload = null
		var payload_digest := FileAccess.get_sha256(payload_path)
		if (
			int(entry.get("byte_length", -1)) != payload_length
			or payload_digest.is_empty()
			or entry.get("sha256") != payload_digest
		):
			return false
		expected_files.append(expected_file)
	expected_files.sort()
	return revision_files == expected_files


func _sha256_bytes(value: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if hashing.update(value) != OK:
		return ""
	return hashing.finish().hex_encode()


func _interrupted_photo_context(
	photo_slot: String,
	expected_session_id: String,
) -> Dictionary:
	var slot_directory := DirAccess.open(photo_slot)
	if slot_directory == null or not slot_directory.get_files().is_empty():
		return _interrupted_state_ambiguous(
			photo_slot.get_file(),
			"photo",
		)
	var session_directories := slot_directory.get_directories()
	session_directories.sort()
	if session_directories.size() != 1:
		return _interrupted_state_ambiguous(
			photo_slot.get_file(),
			"photo",
		)
	var session_id := String(session_directories[0])
	if (
		not _valid_slot_id(session_id)
		or (
			not expected_session_id.is_empty()
			and session_id != expected_session_id
		)
	):
		return _interrupted_state_ambiguous(
			photo_slot.get_file(),
			"photo",
		)
	var session_directory := DirAccess.open(_join(photo_slot, session_id))
	if session_directory == null or (
		not session_directory.get_directories().is_empty()
	):
		return _interrupted_state_ambiguous(
			photo_slot.get_file(),
			"photo",
		)
	for file_name: String in session_directory.get_files():
		if not _valid_interrupted_photo_file(file_name):
			return _interrupted_state_ambiguous(
				photo_slot.get_file(),
				"photo",
			)
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"sessionId": session_id,
	}


func _valid_interrupted_photo_file(file_name: String) -> bool:
	if (
		not file_name.begins_with("chat-photo-sha256-")
		or not file_name.ends_with(".bin")
	):
		return false
	var digest := (
		file_name
		.trim_prefix("chat-photo-sha256-")
		.trim_suffix(".bin")
	)
	if digest.length() != 64:
		return false
	for character: String in digest:
		var code := character.unicode_at(0)
		if not (
			code >= 48 and code <= 57
			or code >= 97 and code <= 102
		):
			return false
	return true


func _interrupted_state_ambiguous(
	slot_id: String,
	participant: String,
) -> Dictionary:
	return _failure(
		"FORMAL_SLOT_ARCHIVE_INTERRUPTED_STATE_AMBIGUOUS",
		false,
		{"slotId": slot_id, "participant": participant},
	)


func _quarantine_interrupted_active_state(
	slot_id: String,
	archive_root: String,
	active_state: Dictionary,
) -> Dictionary:
	var world_present := bool(active_state.get("worldPresent", false))
	var agent_present := bool(active_state.get("agentPresent", false))
	var photo_present := bool(active_state.get("photoPresent", false))
	var active_world := _join(_world_slots_root, slot_id)
	var active_agent := _join(_agent_slots_root, slot_id)
	var active_photos := _join(_photo_slots_root, slot_id)
	var quarantined_world := _join(
		archive_root,
		INTERRUPTED_WORLD_DIRECTORY,
	)
	var quarantined_agent := _join(
		archive_root,
		INTERRUPTED_AGENT_DIRECTORY,
	)
	var quarantined_photos := _join(
		archive_root,
		INTERRUPTED_PHOTO_DIRECTORY,
	)
	var participants: Array[Dictionary] = [
		{
			"name": "world",
			"present": world_present,
			"source": active_world,
			"target": quarantined_world,
		},
		{
			"name": "agent",
			"present": agent_present,
			"source": active_agent,
			"target": quarantined_agent,
		},
		{
			"name": "photo",
			"present": photo_present,
			"source": active_photos,
			"target": quarantined_photos,
		},
	]
	for participant: Dictionary in participants:
		if participant.get("present") != true:
			continue
		var target := String(participant.get("target", ""))
		if (
			DirAccess.dir_exists_absolute(_absolute(target))
			or FileAccess.file_exists(target)
		):
			return _interrupted_state_ambiguous(slot_id, "quarantine")
	var moved: Array[Dictionary] = []
	for participant: Dictionary in participants:
		if participant.get("present") != true:
			continue
		var source := String(participant.get("source", ""))
		var target := String(participant.get("target", ""))
		if _rename_absolute(_absolute(source), _absolute(target)) == OK:
			moved.append(participant)
			continue
		var rollback_ok := true
		for index: int in range(moved.size() - 1, -1, -1):
			var prior := moved[index]
			if _rename_absolute(
				_absolute(String(prior.get("target", ""))),
				_absolute(String(prior.get("source", ""))),
			) != OK:
				rollback_ok = false
		return _failure(
			(
				"FORMAL_SLOT_ARCHIVE_INTERRUPTED_QUARANTINE_FAILED"
				if rollback_ok
				else "FORMAL_SLOT_ARCHIVE_INTERRUPTED_STATE_ROLLBACK_FAILED"
			),
			rollback_ok,
			{
				"archivePath": archive_root,
				"participant": String(participant.get("name", "")),
			},
			not rollback_ok,
		)
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"worldPresent": world_present,
		"agentPresent": agent_present,
		"photoPresent": photo_present,
		"worldPath": quarantined_world,
		"agentPath": quarantined_agent,
		"photoPath": quarantined_photos,
	}


func _restore_quarantined_interrupted_state(
	slot_id: String,
	archive_root: String,
	quarantined: Dictionary,
) -> Dictionary:
	var active_world := _join(_world_slots_root, slot_id)
	var active_agent := _join(_agent_slots_root, slot_id)
	var active_photos := _join(_photo_slots_root, slot_id)
	var world_present := bool(quarantined.get("worldPresent", false))
	var photo_present := bool(quarantined.get("photoPresent", false))
	var agent_present := bool(quarantined.get("agentPresent", false))
	var quarantined_world := String(quarantined.get("worldPath", ""))
	var quarantined_photos := String(quarantined.get("photoPath", ""))
	var quarantined_agent := String(quarantined.get("agentPath", ""))
	if photo_present and not _remove_photo_write_blocker(slot_id):
		return _failure(
			"FORMAL_SLOT_ARCHIVE_INTERRUPTED_STATE_ROLLBACK_FAILED",
			false,
			{"archivePath": archive_root, "participant": "photo"},
		)
	var participants: Array[Dictionary] = [
		{
			"name": "world",
			"present": world_present,
			"source": active_world,
			"target": quarantined_world,
		},
		{
			"name": "agent",
			"present": agent_present,
			"source": active_agent,
			"target": quarantined_agent,
		},
		{
			"name": "photo",
			"present": photo_present,
			"source": active_photos,
			"target": quarantined_photos,
		},
	]
	for participant: Dictionary in participants:
		if participant.get("present") != true:
			continue
		var source := String(participant.get("source", ""))
		var target := String(participant.get("target", ""))
		if (
			DirAccess.dir_exists_absolute(_absolute(source))
			or FileAccess.file_exists(source)
			or not DirAccess.dir_exists_absolute(_absolute(target))
		):
			if photo_present:
				_ensure_photo_write_blocker(slot_id)
			return _failure(
				"FORMAL_SLOT_ARCHIVE_INTERRUPTED_STATE_ROLLBACK_FAILED",
				false,
				{
					"archivePath": archive_root,
					"participant": String(participant.get("name", "")),
				},
			)
	var restored: Array[Dictionary] = []
	for participant: Dictionary in participants:
		if participant.get("present") != true:
			continue
		var source := String(participant.get("source", ""))
		var target := String(participant.get("target", ""))
		if _rename_absolute(_absolute(target), _absolute(source)) == OK:
			restored.append(participant)
			continue
		for index: int in range(restored.size() - 1, -1, -1):
			var prior := restored[index]
			_rename_absolute(
				_absolute(String(prior.get("source", ""))),
				_absolute(String(prior.get("target", ""))),
			)
		if photo_present:
			_ensure_photo_write_blocker(slot_id)
		return _failure(
			"FORMAL_SLOT_ARCHIVE_INTERRUPTED_STATE_ROLLBACK_FAILED",
			false,
			{
				"archivePath": archive_root,
				"participant": String(participant.get("name", "")),
			},
		)
	return _success(world_present or agent_present or photo_present)


func _interrupted_restore_rollback_failure(
	restore_error_code: String,
	archive_root: String,
	rollback: Dictionary,
) -> Dictionary:
	return _failure(
		"FORMAL_SLOT_ARCHIVE_INTERRUPTED_STATE_ROLLBACK_FAILED",
		false,
		{
			"archivePath": archive_root,
			"restoreErrorCode": restore_error_code,
			"rollbackErrorCode": String(rollback.get("errorCode", "")),
		},
		true,
	)


func _remove_interrupted_quarantine(
	archive_root: String,
	quarantined: Dictionary,
) -> bool:
	var removed := true
	for key: String in ["worldPath", "agentPath", "photoPath"]:
		var path := String(quarantined.get(key, ""))
		if (
			not path.is_empty()
			and DirAccess.dir_exists_absolute(_absolute(path))
			and not _remove_tree(path)
		):
			removed = false
	if removed:
		_remove_empty_archive_root(archive_root)
	return removed


func _remove_tree(path: String) -> bool:
	var absolute_path := _absolute(path)
	if not DirAccess.dir_exists_absolute(absolute_path):
		return not FileAccess.file_exists(path)
	var directory := DirAccess.open(absolute_path)
	if directory == null:
		return false
	for file_name: String in directory.get_files():
		if (
			_remove_absolute(
				_absolute(_join(path, file_name)),
			)
			!= OK
		):
			return false
	for directory_name: String in directory.get_directories():
		if not _remove_tree(_join(path, directory_name)):
			return false
	# Windows keeps the directory locked while this iterator owns its handle.
	directory = null
	return _remove_absolute(absolute_path) == OK


func _restore_completed_new_game_archive(request: Dictionary) -> Dictionary:
	var slot_id := String(request.get("slotId", ""))
	var session_id := String(request.get("sessionId", ""))
	var save_revision := int(request.get("saveRevision", 0))
	var archive_root := String(request.get("archivePath", ""))
	if not DirAccess.dir_exists_absolute(_absolute(archive_root)):
		return _failure("FORMAL_SLOT_ARCHIVE_RESTORE_ARCHIVE_MISSING", false)
	var metadata_result := _read_json(
		_join(archive_root, ARCHIVE_METADATA_FILE),
	)
	if (
		metadata_result.get("ok") != true
		or not metadata_result.get("value") is Dictionary
		or not _archive_metadata_matches_request(
			metadata_result.get("value") as Dictionary,
			request,
			"new_game_overwrite",
		)
		or not _completed_archive_receipt_is_valid(archive_root, slot_id)
	):
		return _failure(
			"FORMAL_SLOT_ARCHIVE_RESTORE_ARCHIVE_INVALID",
			false,
			{"archivePath": archive_root},
		)
	var metadata := metadata_result.get("value") as Dictionary
	var photo_present := bool(
		metadata.get("conversation_photos_present", false),
	)
	if not _reopen_archive_transaction(archive_root):
		return _failure(
			"FORMAL_SLOT_ARCHIVE_RESTORE_TRANSACTION_FAILED",
			true,
			{"archivePath": archive_root},
		)
	if not _rollback_archive_participants(
		archive_root,
		slot_id,
		true,
		true,
		photo_present,
	):
		return _finish_completed_archive_restore_failure(
			archive_root,
			slot_id,
			photo_present,
			"FORMAL_SLOT_ARCHIVE_RESTORE_MOVE_FAILED",
		)
	var restored_context := _latest_published_context(
		_join(_world_slots_root, slot_id),
		_join(_agent_slots_root, slot_id),
		slot_id,
	)
	if (
		restored_context.get("ok") != true
		or String(
			(restored_context.get("context", {}) as Dictionary).get(
				"session_id",
				"",
			),
		) != session_id
		or int(
			(restored_context.get("context", {}) as Dictionary).get(
				"save_revision",
				0,
			),
		) != save_revision
	):
		return _finish_completed_archive_restore_failure(
			archive_root,
			slot_id,
			photo_present,
			"FORMAL_SLOT_ARCHIVE_RESTORE_CONTEXT_MISMATCH",
		)
	var transaction_path := _join(archive_root, TRANSACTION_FILE)
	if (
		not FileAccess.file_exists(transaction_path)
		or _remove_absolute(_absolute(transaction_path)) != OK
	):
		return _finish_completed_archive_restore_failure(
			archive_root,
			slot_id,
			photo_present,
			"FORMAL_SLOT_ARCHIVE_RESTORE_TRANSACTION_CLEANUP_FAILED",
		)
	var metadata_path := _join(archive_root, ARCHIVE_METADATA_FILE)
	var metadata_cleanup_pending := false
	if (
		not FileAccess.file_exists(metadata_path)
		or _remove_absolute(_absolute(metadata_path)) != OK
	):
		# The participants and their exact published context are already back in
		# the active roots, and the transaction record is gone. A stale,
		# non-secret archive.json must not turn a successful restore into an
		# unretryable compensation failure or keep the slot write-blocked.
		metadata_cleanup_pending = true
	else:
		_remove_empty_archive_root(archive_root)
	var result := {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"changed": true,
		"restored": true,
		"context": {
			"slot_id": slot_id,
			"session_id": session_id,
			"save_revision": save_revision,
		},
	}
	if metadata_cleanup_pending:
		result["cleanupPending"] = true
		result["archivePath"] = archive_root
	return result


func _finish_completed_archive_restore_failure(
	archive_root: String,
	slot_id: String,
	photo_present: bool,
	error_code: String,
) -> Dictionary:
	if not _rearchive_restored_participants(
		archive_root,
		slot_id,
		true,
		true,
		photo_present,
	):
		var rollback_failed := _failure(
			"FORMAL_SLOT_ARCHIVE_RESTORE_ROLLBACK_FAILED",
			false,
			{
				"archivePath": archive_root,
				"restoreErrorCode": error_code,
			},
			true,
		)
		rollback_failed["preservePending"] = true
		return rollback_failed
	if (
		not _commit_archive_transaction(archive_root)
		or not _completed_archive_receipt_is_valid(archive_root, slot_id)
	):
		var recovery_pending := _failure(
			"FORMAL_SLOT_ARCHIVE_RESTORE_ROLLBACK_PENDING",
			true,
			{
				"archivePath": archive_root,
				"restoreErrorCode": error_code,
			},
			true,
		)
		recovery_pending["preservePending"] = true
		return recovery_pending
	return _failure(
		error_code,
		true,
		{"archivePath": archive_root},
	)


func _rearchive_restored_participants(
	archive_root: String,
	slot_id: String,
	world_present: bool,
	agent_present: bool,
	photo_present: bool,
) -> bool:
	var participants: Array[Dictionary] = [
		{
			"present": world_present,
			"source": _join(_world_slots_root, slot_id),
			"target": _join(archive_root, "world_slot"),
		},
		{
			"present": agent_present,
			"source": _join(_agent_slots_root, slot_id),
			"target": _join(archive_root, "agent_slot"),
		},
		{
			"present": photo_present,
			"source": _join(_photo_slots_root, slot_id),
			"target": _join(archive_root, "conversation_photos"),
		},
	]
	for participant: Dictionary in participants:
		if participant.get("present") != true:
			continue
		var source := String(participant.get("source", ""))
		var target := String(participant.get("target", ""))
		var source_exists := DirAccess.dir_exists_absolute(_absolute(source))
		var target_exists := DirAccess.dir_exists_absolute(_absolute(target))
		if target_exists and not source_exists:
			continue
		if not source_exists or target_exists:
			return false
		if _rename_absolute(_absolute(source), _absolute(target)) != OK:
			return false
	if not _ensure_photo_write_blocker(slot_id):
		return false
	return _participant_layout_matches(
		archive_root,
		slot_id,
		world_present,
		agent_present,
		photo_present,
		true,
	)


func _ensure_photo_write_blocker(slot_id: String) -> bool:
	var photo_slot := _join(_photo_slots_root, slot_id)
	if DirAccess.dir_exists_absolute(_absolute(photo_slot)):
		return false
	if FileAccess.file_exists(photo_slot):
		return _valid_photo_write_blocker(photo_slot, slot_id)
	var parent_error := DirAccess.make_dir_recursive_absolute(
		_absolute(_photo_slots_root),
	)
	if parent_error != OK:
		return false
	if not _write_json_atomic(photo_slot, {
		"schema": PHOTO_WRITE_BLOCK_SCHEMA,
		"schema_version": 1,
		"slot_id": slot_id,
	}):
		return false
	return _valid_photo_write_blocker(photo_slot, slot_id)


func _remove_photo_write_blocker(slot_id: String) -> bool:
	var photo_slot := _join(_photo_slots_root, slot_id)
	if DirAccess.dir_exists_absolute(_absolute(photo_slot)):
		return true
	if not FileAccess.file_exists(photo_slot):
		return true
	if not _valid_photo_write_blocker(photo_slot, slot_id):
		return false
	return DirAccess.remove_absolute(_absolute(photo_slot)) == OK


func _valid_photo_write_blocker(path: String, slot_id: String) -> bool:
	var loaded := _read_json(path)
	if loaded.get("ok") != true or not loaded.get("value") is Dictionary:
		return false
	var value := loaded.get("value") as Dictionary
	return (
		_has_exact_fields(value, ["schema", "schema_version", "slot_id"])
		and value.get("schema") == PHOTO_WRITE_BLOCK_SCHEMA
		and value.get("schema_version") == 1
		and value.get("slot_id") == slot_id
	)


func _completed_archive_state_is_valid(
	archive_root: String,
	slot_id: String,
) -> bool:
	return _completed_archive_record_is_valid(
		archive_root,
		slot_id,
		TRANSACTION_FILE,
	)


func _completed_archive_receipt_is_valid(
	archive_root: String,
	slot_id: String,
) -> bool:
	return _completed_archive_record_is_valid(
		archive_root,
		slot_id,
		COMPLETION_RECEIPT_FILE,
	)


func _completed_archive_history_receipt_is_valid(
	archive_root: String,
	slot_id: String,
) -> bool:
	var transaction := _read_json(
		_join(archive_root, COMPLETION_RECEIPT_FILE),
	)
	var metadata := _read_json(_join(archive_root, ARCHIVE_METADATA_FILE))
	return (
		transaction.get("ok") == true
		and metadata.get("ok") == true
		and transaction.get("value") is Dictionary
		and _valid_archive_transaction(
			transaction.get("value") as Dictionary,
			slot_id,
		)
		and _completed_archive_is_valid(
			archive_root,
			slot_id,
			transaction.get("value") as Dictionary,
			metadata.get("value"),
			false,
		)
	)


func _completed_archive_record_is_valid(
	archive_root: String,
	slot_id: String,
	record_file: String,
) -> bool:
	var transaction := _read_json(_join(archive_root, record_file))
	var metadata := _read_json(_join(archive_root, ARCHIVE_METADATA_FILE))
	return (
		transaction.get("ok") == true
		and metadata.get("ok") == true
		and transaction.get("value") is Dictionary
		and _valid_archive_transaction(
			transaction.get("value") as Dictionary,
			slot_id,
		)
		and _completed_archive_is_valid(
			archive_root,
			slot_id,
			transaction.get("value") as Dictionary,
			metadata.get("value"),
		)
	)


func _commit_archive_transaction(archive_root: String) -> bool:
	var transaction_path := _join(archive_root, TRANSACTION_FILE)
	var receipt_path := _join(archive_root, COMPLETION_RECEIPT_FILE)
	if FileAccess.file_exists(receipt_path):
		return not FileAccess.file_exists(transaction_path)
	if not FileAccess.file_exists(transaction_path):
		return false
	return _rename_absolute(
		_absolute(transaction_path),
		_absolute(receipt_path),
	) == OK


func _reopen_archive_transaction(archive_root: String) -> bool:
	var transaction_path := _join(archive_root, TRANSACTION_FILE)
	var receipt_path := _join(archive_root, COMPLETION_RECEIPT_FILE)
	if FileAccess.file_exists(transaction_path):
		return not FileAccess.file_exists(receipt_path)
	if not FileAccess.file_exists(receipt_path):
		return false
	return _rename_absolute(
		_absolute(receipt_path),
		_absolute(transaction_path),
	) == OK


func _recover_pending_archives(slot_id: String) -> Dictionary:
	var slot_backup_root := _slot_backup_root(slot_id)
	if not DirAccess.dir_exists_absolute(_absolute(slot_backup_root)):
		return _success(false)
	var backup_directory := DirAccess.open(slot_backup_root)
	if backup_directory == null:
		return _failure("FORMAL_SLOT_ARCHIVE_RECOVERY_READ_FAILED", true)
	var recovered_any := false
	var archive_names := backup_directory.get_directories()
	archive_names.sort()
	for archive_name: String in archive_names:
		var archive_root := _join(slot_backup_root, archive_name)
		var transaction_path := _join(archive_root, TRANSACTION_FILE)
		if not FileAccess.file_exists(transaction_path):
			continue
		var loaded := _read_json(transaction_path)
		if loaded.get("ok") != true:
			return _failure(
				"FORMAL_SLOT_ARCHIVE_RECOVERY_RECORD_INVALID",
				false,
				{"archivePath": archive_root},
				true,
			)
		var transaction_value: Variant = loaded.get("value")
		if not transaction_value is Dictionary:
			return _failure(
				"FORMAL_SLOT_ARCHIVE_RECOVERY_RECORD_INVALID",
				false,
				{"archivePath": archive_root},
				true,
			)
		var transaction := transaction_value as Dictionary
		var transaction_slot_value: Variant = transaction.get("slot_id")
		if (
			not transaction_slot_value is String
			or not _valid_archive_transaction(
				transaction,
				slot_id,
			)
		):
			return _failure(
				"FORMAL_SLOT_ARCHIVE_RECOVERY_RECORD_INVALID",
				false,
				{"archivePath": archive_root},
				true,
			)
		var recovered := _recover_pending_archive(
			archive_root,
			slot_id,
			transaction,
		)
		if recovered.get("ok") != true:
			return recovered
		recovered_any = true
	return _success(recovered_any)


func _recover_pending_archive(
	archive_root: String,
	slot_id: String,
	transaction: Dictionary,
) -> Dictionary:
	var metadata_path := _join(archive_root, ARCHIVE_METADATA_FILE)
	if FileAccess.file_exists(metadata_path):
		var loaded_metadata := _read_json(metadata_path)
		if (
			loaded_metadata.get("ok") != true
			or not _completed_archive_is_valid(
				archive_root,
				slot_id,
				transaction,
				loaded_metadata.get("value"),
			)
		):
			return _failure(
				"FORMAL_SLOT_ARCHIVE_RECOVERY_METADATA_INVALID",
				false,
				{"archivePath": archive_root},
				true,
			)
		if not _commit_archive_transaction(archive_root):
			return _failure(
				"FORMAL_SLOT_ARCHIVE_RECOVERY_CLEANUP_FAILED",
				true,
				{"archivePath": archive_root},
				true,
			)
		if not _completed_archive_receipt_is_valid(archive_root, slot_id):
			var reopened := _reopen_archive_transaction(archive_root)
			var invalid := _failure(
				"FORMAL_SLOT_ARCHIVE_RECOVERY_METADATA_INVALID",
				false,
				{"archivePath": archive_root},
				true,
			)
			invalid["preservePending"] = not reopened
			return invalid
		return _success(true)
	var participants: Array[Dictionary] = [
		{
			"present": transaction.get("photo_present"),
			"source": _join(_photo_slots_root, slot_id),
			"target": _join(archive_root, "conversation_photos"),
		},
		{
			"present": transaction.get("agent_present"),
			"source": _join(_agent_slots_root, slot_id),
			"target": _join(archive_root, "agent_slot"),
		},
		{
			"present": transaction.get("world_present"),
			"source": _join(_world_slots_root, slot_id),
			"target": _join(archive_root, "world_slot"),
		},
	]
	for participant: Dictionary in participants:
		var source := String(participant.get("source", ""))
		var target := String(participant.get("target", ""))
		var source_exists := DirAccess.dir_exists_absolute(_absolute(source))
		var target_exists := DirAccess.dir_exists_absolute(_absolute(target))
		if participant.get("present") != true:
			if source_exists or target_exists:
				return _failure(
					"FORMAL_SLOT_ARCHIVE_RECOVERY_AMBIGUOUS",
					false,
					{"archivePath": archive_root},
					false,
				)
			continue
		if source_exists and target_exists:
			return _failure(
				"FORMAL_SLOT_ARCHIVE_RECOVERY_AMBIGUOUS",
				false,
				{"archivePath": archive_root},
				false,
			)
		if not source_exists and not target_exists:
			return _failure(
				"FORMAL_SLOT_ARCHIVE_RECOVERY_PARTICIPANT_MISSING",
				false,
				{"archivePath": archive_root},
				false,
			)
	var photo_blocker_path := _join(_photo_slots_root, slot_id)
	var blocker_existed := FileAccess.file_exists(photo_blocker_path)
	if not _remove_photo_write_blocker(slot_id):
		return _failure(
			"FORMAL_SLOT_ARCHIVE_ROLLBACK_FAILED",
			false,
			{"archivePath": archive_root},
			false,
		)
	var changed := blocker_existed
	for participant: Dictionary in participants:
		var source := String(participant.get("source", ""))
		var target := String(participant.get("target", ""))
		var source_exists := DirAccess.dir_exists_absolute(_absolute(source))
		var target_exists := DirAccess.dir_exists_absolute(_absolute(target))
		if participant.get("present") != true:
			continue
		if not source_exists:
			var rollback_error := _rename_absolute(
				_absolute(target),
				_absolute(source),
			)
			if rollback_error != OK:
				return _failure(
					"FORMAL_SLOT_ARCHIVE_ROLLBACK_FAILED",
					false,
					{"archivePath": archive_root},
					changed,
				)
			changed = true
	var transaction_path := _join(archive_root, TRANSACTION_FILE)
	if (
		FileAccess.file_exists(transaction_path)
		and DirAccess.remove_absolute(_absolute(transaction_path)) != OK
	):
		return _failure(
			"FORMAL_SLOT_ARCHIVE_RECOVERY_CLEANUP_FAILED",
			true,
			{"archivePath": archive_root},
			changed,
		)
	_remove_empty_archive_root(archive_root)
	return _success(changed)


func _completed_archive_is_valid(
	archive_root: String,
	slot_id: String,
	transaction: Dictionary,
	metadata_value: Variant,
	require_active_sources_absent: bool = true,
) -> bool:
	if not metadata_value is Dictionary:
		return false
	var metadata := metadata_value as Dictionary
	var world_present: bool = transaction.get("world_present") == true
	var agent_present: bool = transaction.get("agent_present") == true
	var photo_present: bool = transaction.get("photo_present") == true
	if (
		metadata.get("schema") != "ai-town-formal-slot-archive"
		or metadata.get("schema_version") != 1
		or metadata.get("slot_id") != slot_id
		or not _valid_archive_timestamp(metadata.get("archived_at"))
	):
		return false
	var reason_value: Variant = metadata.get("reason")
	if not reason_value is String:
		return false
	var reason := reason_value as String
	var metadata_matches := false
	var complete_pair_metadata := false
	if reason in ["new_game_overwrite", "player_delete"] and (
		world_present
		and agent_present
		and _has_exact_fields(metadata, [
			"schema",
			"schema_version",
			"reason",
			"archived_at",
			"slot_id",
			"session_id",
			"save_revision",
			"conversation_photos_present",
		])
		and metadata.get("session_id") is String
		and _valid_slot_id(metadata.get("session_id") as String)
		and _is_positive_integer_number(metadata.get("save_revision"))
		and _boolean_field_matches(
			metadata,
			"conversation_photos_present",
			photo_present,
		)
	):
		metadata_matches = true
		complete_pair_metadata = true
	elif (
		reason in ["player_delete", "unpaired_world_slot_recovery"]
		and _has_exact_fields(metadata, [
			"schema",
			"schema_version",
			"reason",
			"archived_at",
			"slot_id",
			"session_id",
			"save_revision",
			"expected_state",
			"world_participant_present",
			"agent_participant_present",
			"conversation_photos_present",
		])
		and metadata.get("session_id") == ""
		and metadata.get("save_revision") == 0
		and (
			metadata.get("expected_state") in UNVERIFIED_DELETE_STATES
			or (
				reason == "unpaired_world_slot_recovery"
				and metadata.get("expected_state") == "unpaired_world_slot_recovery"
			)
		)
		and _boolean_field_matches(
			metadata,
			"world_participant_present",
			world_present,
		)
		and _boolean_field_matches(
			metadata,
			"agent_participant_present",
			agent_present,
		)
		and _boolean_field_matches(
			metadata,
			"conversation_photos_present",
			photo_present,
		)
	):
		metadata_matches = true
	elif (
		reason == "unpaired_agent_slot_recovery"
		and not world_present
		and _has_exact_fields(metadata, [
			"schema",
			"schema_version",
			"reason",
			"archived_at",
			"slot_id",
			"save_revision",
			"agent_slot_present",
			"conversation_photos_present",
		])
		and metadata.get("save_revision") == 0
		and _boolean_field_matches(
			metadata,
			"agent_slot_present",
			agent_present,
		)
		and _boolean_field_matches(
			metadata,
			"conversation_photos_present",
			photo_present,
		)
	):
		metadata_matches = true
	if not metadata_matches:
		return false
	var participants: Array[Dictionary] = [
		{
			"present": world_present,
			"source": _join(_world_slots_root, slot_id),
			"target": _join(archive_root, "world_slot"),
		},
		{
			"present": agent_present,
			"source": _join(_agent_slots_root, slot_id),
			"target": _join(archive_root, "agent_slot"),
		},
		{
			"present": photo_present,
			"source": _join(_photo_slots_root, slot_id),
			"target": _join(archive_root, "conversation_photos"),
		},
	]
	for participant: Dictionary in participants:
		var source_exists := DirAccess.dir_exists_absolute(
			_absolute(String(participant.get("source", ""))),
		)
		var target_exists := DirAccess.dir_exists_absolute(
			_absolute(String(participant.get("target", ""))),
		)
		if participant.get("present") == true:
			if (
				(require_active_sources_absent and source_exists)
				or not target_exists
			):
				return false
		elif (
			(require_active_sources_absent and source_exists)
			or target_exists
		):
			return false
	if require_active_sources_absent and not _valid_photo_write_blocker(
		_join(_photo_slots_root, slot_id),
		slot_id,
	):
		return false
	if complete_pair_metadata:
		var archived_context := _latest_published_context(
			_join(archive_root, "world_slot"),
			_join(archive_root, "agent_slot"),
			slot_id,
		)
		if archived_context.get("ok") != true:
			return false
		var context := archived_context.get("context", {}) as Dictionary
		if (
			context.get("session_id") != metadata.get("session_id")
			or context.get("save_revision") != metadata.get("save_revision")
		):
			return false
	return true


func _valid_archive_transaction(
	transaction: Dictionary,
	slot_id: String,
) -> bool:
	var expected_fields: Array[String] = [
		"schema",
		"schema_version",
		"slot_id",
		"world_present",
		"agent_present",
		"photo_present",
	]
	if transaction.size() != expected_fields.size():
		return false
	for field_name: String in expected_fields:
		if not transaction.has(field_name):
			return false
	return (
		transaction.get("schema") is String
		and transaction.get("schema") == TRANSACTION_SCHEMA
		and _is_non_negative_integer_number(
			transaction.get("schema_version"),
		)
		and int(transaction.get("schema_version")) == 1
		and transaction.get("slot_id") is String
		and transaction.get("slot_id") == slot_id
		and transaction.get("world_present") is bool
		and transaction.get("agent_present") is bool
		and transaction.get("photo_present") is bool
	)


func _write_transaction_json(path: String, value: Dictionary) -> bool:
	return _write_json_atomic(path, value)


func _completed_archive_result_for_request(
	request: Dictionary,
	reason: String,
) -> Dictionary:
	var slot_id := String(request.get("slotId", ""))
	var slot_backup_root := _slot_backup_root(slot_id)
	if not DirAccess.dir_exists_absolute(_absolute(slot_backup_root)):
		return {"found": false}
	var directory := DirAccess.open(slot_backup_root)
	if directory == null:
		var read_failure := _failure(
			"FORMAL_SLOT_ARCHIVE_RECOVERY_READ_FAILED",
			true,
		)
		read_failure["found"] = true
		return read_failure
	var archive_names := directory.get_directories()
	archive_names.sort()
	archive_names.reverse()
	for archive_name: String in archive_names:
		var archive_root := _join(slot_backup_root, archive_name)
		var receipt_path := _join(archive_root, COMPLETION_RECEIPT_FILE)
		if not FileAccess.file_exists(receipt_path):
			continue
		var active_world := DirAccess.dir_exists_absolute(
			_absolute(_join(_world_slots_root, slot_id)),
		)
		var active_agent := DirAccess.dir_exists_absolute(
			_absolute(_join(_agent_slots_root, slot_id)),
		)
		var active_photos := DirAccess.dir_exists_absolute(
			_absolute(_join(_photo_slots_root, slot_id)),
		)
		var loaded_metadata := _read_json(
			_join(archive_root, ARCHIVE_METADATA_FILE),
		)
		if (
			loaded_metadata.get("ok") != true
			or not loaded_metadata.get("value") is Dictionary
		):
			if active_world or active_agent or active_photos:
				continue
			var reopened_unreadable := _reopen_archive_transaction(
				archive_root,
			)
			var unreadable := _failure(
				"FORMAL_SLOT_ARCHIVE_RECOVERY_METADATA_INVALID",
				false,
				{"archivePath": archive_root},
				true,
			)
			unreadable["found"] = true
			unreadable["preservePending"] = not reopened_unreadable
			return unreadable
		var metadata := loaded_metadata.get("value") as Dictionary
		if not _archive_metadata_matches_request(metadata, request, reason):
			continue
		if _completed_archive_receipt_is_valid(archive_root, slot_id):
			return {
				"ok": true,
				"errorCode": "",
				"retryable": false,
				"changed": true,
				"found": true,
				"archivePath": archive_root,
				"metadataWritten": true,
				"transactionCleanupPending": false,
				"context": {
					"slot_id": slot_id,
					"session_id": String(request.get("sessionId", "")),
					"save_revision": int(request.get("saveRevision", 0)),
				},
			}
		if active_world or active_agent or active_photos:
			continue
		var reopened := _reopen_archive_transaction(archive_root)
		var invalid := _failure(
			"FORMAL_SLOT_ARCHIVE_COMPLETION_INVALID",
			false,
			{"archivePath": archive_root},
			true,
		)
		invalid["found"] = true
		invalid["preservePending"] = not reopened
		return invalid
	return {"found": false}


func _archive_metadata_matches_request(
	metadata: Dictionary,
	request: Dictionary,
	reason: String,
) -> bool:
	if (
		metadata.get("reason") != reason
		or metadata.get("slot_id") != request.get("slotId")
		or metadata.get("session_id") != request.get("sessionId")
		or metadata.get("save_revision") != request.get("saveRevision")
	):
		return false
	if reason == "player_delete" and String(request.get("sessionId", "")).is_empty():
		return metadata.get("expected_state") == request.get("expectedState")
	return true


func _with_recovery_change(
	result: Dictionary,
	recovery: Dictionary,
) -> Dictionary:
	var combined := result.duplicate(true)
	if recovery.get("changed") == true:
		combined["changed"] = true
	return combined


func _begin_archive_lease(slot_id_value: Variant) -> Dictionary:
	var lease := _save_store.begin_slot_archive(slot_id_value,) as Dictionary
	if lease.get("ok") != true:
		var participant_error := String(lease.get("errorCode", ""))
		var error_code := "FORMAL_SLOT_ARCHIVE_STORE_FAILED"
		if participant_error == "SESSION_SAVE_SLOT_BUSY":
			error_code = "FORMAL_SLOT_ARCHIVE_BUSY"
		elif participant_error == "SESSION_SAVE_CONTEXT_INVALID":
			error_code = "FORMAL_SLOT_ARCHIVE_CONTEXT_INVALID"
		return _failure(
			error_code,
			bool(lease.get("retryable", true)),
			{
				"participantErrorCode": participant_error,
			},
		)
	var token_value: Variant = lease.get("leaseToken")
	if (
		not token_value is String
		or (token_value as String).is_empty()
		or not lease.get("slotId") is String
		or lease.get("slotId") != slot_id_value
	):
		if token_value is String and not (token_value as String).is_empty():
			var released := _save_store.end_slot_archive(token_value,) as Dictionary
			if released.get("ok") != true:
				return _failure(
					"FORMAL_SLOT_ARCHIVE_LEASE_RELEASE_FAILED",
					false,
					{
						"operationOk": false,
						"operationErrorCode": (
							"FORMAL_SLOT_ARCHIVE_LEASE_INVALID"
						),
						"participantErrorCode": String(
							released.get("errorCode", ""),
						),
					},
				)
		return _failure("FORMAL_SLOT_ARCHIVE_LEASE_INVALID", false)
	var pending_marked := _save_store.mark_slot_archive_pending(token_value,) as Dictionary
	if pending_marked.get("ok") != true:
		var mark_release := _save_store.end_slot_archive(token_value,) as Dictionary
		return _failure(
			"FORMAL_SLOT_ARCHIVE_PENDING_MARK_FAILED",
			bool(pending_marked.get("retryable", true)),
			{
				"participantErrorCode": String(
					pending_marked.get("errorCode", ""),
				),
				"leaseReleaseOk": mark_release.get("ok") == true,
			},
		)
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"leaseToken": token_value as String,
		"slotId": slot_id_value as String,
	}


func _finish_archive_lease(
	lease: Dictionary,
	result: Dictionary,
) -> Dictionary:
	var final_result := result
	var preserve_pending: bool = result.get("preservePending") == true
	var pending_state := (
		{"ok": true, "pending": true}
		if preserve_pending
		else _pending_archive_transaction_state(
			String(lease.get("slotId", "")),
		)
	)
	if pending_state.get("ok") != true:
		final_result = _failure(
			"FORMAL_SLOT_ARCHIVE_PENDING_CHECK_FAILED",
			true,
			{
				"operationOk": result.get("ok") == true,
				"operationErrorCode": String(result.get("errorCode", "")),
				"participantErrorCode": String(
					pending_state.get("errorCode", ""),
				),
			},
			bool(result.get("changed", false)),
		)
	elif pending_state.get("pending") != true:
		var cleared := _save_store.clear_slot_archive_pending(lease.get("leaseToken"),) as Dictionary
		if cleared.get("ok") != true:
			final_result = _failure(
				"FORMAL_SLOT_ARCHIVE_PENDING_CLEAR_FAILED",
				true,
				{
					"operationOk": result.get("ok") == true,
					"operationErrorCode": String(
						result.get("errorCode", ""),
					),
					"participantErrorCode": String(
						cleared.get("errorCode", ""),
					),
				},
				bool(result.get("changed", false)),
			)
		else:
			_remove_empty_archive_root(
				_slot_backup_root(String(lease.get("slotId", ""))),
			)
	elif result.get("ok") == true:
		final_result = _failure(
			"FORMAL_SLOT_ARCHIVE_RECOVERY_PENDING",
			true,
			{
				"operationErrorCode": "",
				"archivePath": String(result.get("archivePath", "")),
			},
			bool(result.get("changed", false)),
		)
	elif preserve_pending:
		final_result = result
	var released := _save_store.end_slot_archive(lease.get("leaseToken"),) as Dictionary
	if released.get("ok") == true:
		return final_result
	return _failure(
		"FORMAL_SLOT_ARCHIVE_LEASE_RELEASE_FAILED",
		false,
		{
			"operationOk": final_result.get("ok") == true,
			"operationErrorCode": String(
				final_result.get("errorCode", ""),
			),
			"participantErrorCode": String(
				released.get("errorCode", ""),
			),
		},
		bool(final_result.get("changed", false)),
	)


func _pending_archive_transaction_state(slot_id: String) -> Dictionary:
	var slot_backup_root := _slot_backup_root(slot_id)
	if not DirAccess.dir_exists_absolute(_absolute(slot_backup_root)):
		return {"ok": true, "pending": false}
	var backup_directory := DirAccess.open(slot_backup_root)
	if backup_directory == null:
		return _failure("FORMAL_SLOT_ARCHIVE_RECOVERY_READ_FAILED", true)
	for archive_name: String in backup_directory.get_directories():
		var transaction_path := _join(
			_join(slot_backup_root, archive_name),
			TRANSACTION_FILE,
		)
		if not FileAccess.file_exists(transaction_path):
			continue
		var loaded := _read_json(transaction_path)
		if loaded.get("ok") != true:
			return _failure(
				"FORMAL_SLOT_ARCHIVE_RECOVERY_RECORD_INVALID",
				false,
			)
		var transaction_value: Variant = loaded.get("value")
		if not transaction_value is Dictionary:
			return _failure(
				"FORMAL_SLOT_ARCHIVE_RECOVERY_RECORD_INVALID",
				false,
			)
		var transaction := transaction_value as Dictionary
		var transaction_slot_value: Variant = transaction.get("slot_id")
		if (
			not transaction_slot_value is String
			or not _valid_archive_transaction(
				transaction,
				slot_id,
			)
		):
			return _failure(
				"FORMAL_SLOT_ARCHIVE_RECOVERY_RECORD_INVALID",
				false,
			)
		return {"ok": true, "pending": true}
	return {"ok": true, "pending": false}


func _rename_absolute(from_path: String, to_path: String) -> Error:
	return DirAccess.rename_absolute(from_path, to_path)


func _remove_absolute(path: String) -> Error:
	return DirAccess.remove_absolute(path)


func _next_archive_root(slot_id: String, save_revision: int) -> String:
	var archive_order := "%016d" % int(
		Time.get_unix_time_from_system() * 1000000.0
	)
	var stem := "%s-r%d" % [archive_order, save_revision]
	var slot_backup_root := _slot_backup_root(slot_id)
	var candidate := _join(slot_backup_root, stem)
	var suffix := 1
	while DirAccess.dir_exists_absolute(_absolute(candidate)):
		candidate = _join(slot_backup_root, "%s-%d" % [stem, suffix])
		suffix += 1
	return candidate


func _slot_backup_root(slot_id: String) -> String:
	return _join(_backup_root, slot_id)


func _archive_root_matches_slot(archive_root: String, slot_id: String) -> bool:
	var normalized := archive_root.trim_suffix("/")
	return (
		not normalized.is_empty()
		and normalized == archive_root
		and not normalized.contains("..")
		and not normalized.contains("\\")
		and normalized.get_base_dir() == _slot_backup_root(slot_id)
		and _valid_slot_id(normalized.get_file())
	)


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("FORMAL_SLOT_ARCHIVE_READ_FAILED", false)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return _failure("FORMAL_SLOT_ARCHIVE_JSON_INVALID", false)
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"value": (parsed as Dictionary).duplicate(true),
	}


func _latest_published_context(
	world_slot: String,
	agent_slot: String,
	expected_slot_id: String,
) -> Dictionary:
	var manifest_root := _join(world_slot, "manifests")
	var directory := DirAccess.open(manifest_root)
	if directory == null:
		return _failure("FORMAL_SLOT_ARCHIVE_MANIFEST_UNREADABLE", false)
	var latest_revision := -1
	var latest_context: Dictionary = {}
	for file_name: String in directory.get_files():
		if not file_name.ends_with(".json"):
			continue
		var revision := _canonical_manifest_revision(file_name)
		if revision < 1:
			continue
		var loaded := _read_json(_join(manifest_root, file_name))
		if not bool(loaded.get("ok", false)):
			continue
		var manifest := loaded.get("value", {}) as Dictionary
		if (
			not bool(SAVE_MANIFEST.validate(manifest).get("ok", false))
			or String(manifest.get("slot_id", "")) != expected_slot_id
			or int(manifest.get("save_revision", -1)) != revision
		):
			continue
		var session_id := String(manifest.get("session_id", ""))
		var agent_revision := _join(
			agent_slot,
			"sessions/%s/revisions/%d" % [session_id, revision],
		)
		if not DirAccess.dir_exists_absolute(_absolute(agent_revision)):
			continue
		if revision > latest_revision:
			latest_revision = revision
			latest_context = {
				"slot_id": expected_slot_id,
				"session_id": session_id,
				"save_revision": revision,
			}
	if latest_revision < 1:
		return _failure("FORMAL_SLOT_ARCHIVE_MANIFEST_UNREADABLE", false)
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"context": latest_context,
	}


func _has_complete_published_pair(
	world_slot: String,
	agent_slot: String,
	expected_slot_id: String,
) -> bool:
	return bool(_latest_published_context(
		world_slot,
		agent_slot,
		expected_slot_id,
	).get("ok", false))


func _canonical_manifest_revision(file_name: String) -> int:
	if not file_name.ends_with(".json"):
		return -1
	var revision_text := file_name.trim_suffix(".json")
	if revision_text.length() != 20:
		return -1
	if not TownSaveScalars.ascii_digits(revision_text):
		return -1
	var revision := int(revision_text)
	if revision < 1 or "%020d" % revision != revision_text:
		return -1
	return revision


func _write_json(path: String, value: Dictionary) -> bool:
	return _write_json_atomic(path, value)


func _write_json_atomic(path: String, value: Dictionary) -> bool:
	var staging_path := _temporary_json_path(path)
	var staging_parent_error := DirAccess.make_dir_recursive_absolute(
		_absolute(staging_path.get_base_dir()),
	)
	if staging_parent_error not in [OK, ERR_ALREADY_EXISTS]:
		return false
	var file := FileAccess.open(staging_path, FileAccess.WRITE)
	if file == null:
		return false
	# 紧凑输出：存档快照可达数 MB，带缩进会显著放大写盘体积与耗时。
	file.store_string(JSON.stringify(value))
	file.flush()
	var write_error := file.get_error()
	file = null
	if write_error != OK:
		DirAccess.remove_absolute(_absolute(staging_path))
		return false
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(_absolute(staging_path))
		return false
	var rename_error := DirAccess.rename_absolute(
		_absolute(staging_path),
		_absolute(path),
	)
	if rename_error != OK:
		DirAccess.remove_absolute(_absolute(staging_path))
		return false
	return true


func _temporary_json_path(path: String) -> String:
	return _join(
		_backup_root,
		"_tmp/json-%s.tmp" % path.sha256_text().left(24),
	)


func _remove_empty_archive_root(archive_root: String) -> void:
	if not DirAccess.dir_exists_absolute(_absolute(archive_root)):
		return
	var directory := DirAccess.open(_absolute(archive_root))
	if directory == null:
		return
	var is_empty := (
		directory.get_files().is_empty()
		and directory.get_directories().is_empty()
	)
	directory = null
	if is_empty:
		DirAccess.remove_absolute(_absolute(archive_root))


func _remove_failed_archive_root(archive_root: String) -> void:
	var metadata_path := _join(archive_root, ARCHIVE_METADATA_FILE)
	if FileAccess.file_exists(metadata_path):
		DirAccess.remove_absolute(_absolute(metadata_path))
	var transaction_path := _join(archive_root, TRANSACTION_FILE)
	if FileAccess.file_exists(transaction_path):
		DirAccess.remove_absolute(_absolute(transaction_path))
	_remove_empty_archive_root(archive_root)


func _valid_slot_id(slot_id: String) -> bool:
	return SAVE_MANIFEST.validate_slot_id(slot_id).get("ok") == true


func _is_non_negative_integer_number(value: Variant) -> bool:
	if value is int:
		return int(value) >= 0
	if value is float:
		var number := float(value)
		return (
			is_finite(number)
			and number >= 0.0
			and number <= 9007199254740991.0
			and number == floor(number)
		)
	return false


func _is_positive_integer_number(value: Variant) -> bool:
	return _is_non_negative_integer_number(value) and int(value) > 0


func _boolean_field_matches(
	value: Dictionary,
	field_name: String,
	expected: bool,
) -> bool:
	return value.get(field_name) is bool and value.get(field_name) == expected


func _valid_archive_timestamp(value: Variant) -> bool:
	if not value is String:
		return false
	var text := value as String
	if (
		text.length() != 19
		or text[4] != "-"
		or text[7] != "-"
		or text[10] != " "
		or text[13] != ":"
		or text[16] != ":"
	):
		return false
	var digits := (
		text.substr(0, 4)
		+ text.substr(5, 2)
		+ text.substr(8, 2)
		+ text.substr(11, 2)
		+ text.substr(14, 2)
		+ text.substr(17, 2)
	)
	if not TownSaveScalars.ascii_digits(digits):
		return false
	var month := int(text.substr(5, 2))
	var day := int(text.substr(8, 2))
	var year := int(text.substr(0, 4))
	var hour := int(text.substr(11, 2))
	var minute := int(text.substr(14, 2))
	var second := int(text.substr(17, 2))
	return (
		year >= 1
		and month >= 1
		and month <= 12
		and day >= 1
		and day <= TownSaveScalars.days_in_month(month, year)
		and hour <= 23
		and minute <= 59
		and second <= 59
	)


func _has_exact_fields(value: Dictionary, expected_fields: Array) -> bool:
	if value.size() != expected_fields.size():
		return false
	for key: Variant in value:
		if not key is String or key not in expected_fields:
			return false
	return true


func _is_test_path(path: String) -> bool:
	return (
		path.begins_with("%s/" % TEST_ROOT)
		and not path.contains("..")
		and not path.contains("\\")
	)


func _join(left: String, right: String) -> String:
	return TownSaveContext.join_path(left, right)


func _absolute(path: String) -> String:
	return ProjectSettings.globalize_path(path)


func _success(changed: bool) -> Dictionary:
	return RESULT_SHAPES.success_changed(changed)


func _failure(
	error_code: String,
	retryable: bool,
	meta: Dictionary = {},
	changed: bool = false,
) -> Dictionary:
	return {
		"ok": false,
		"errorCode": error_code,
		"retryable": retryable,
		"changed": changed,
		"meta": meta.duplicate(true),
	}
