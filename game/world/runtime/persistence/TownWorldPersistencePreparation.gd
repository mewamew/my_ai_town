class_name TownWorldPersistencePreparation
extends RefCounted


const OPENING_CONFIG := preload(
	"res://world/runtime/TownWorldOpeningConfig.gd"
)
const SAVE_CODEC := preload(
	"res://world/runtime/persistence/TownWorldSaveCodec.gd"
)
const SAVE_CANDIDATE_RUNTIME := preload(
	"res://world/runtime/persistence/TownWorldSaveCandidateRuntime.gd"
)
const RESTORE_STATE := preload(
	"res://world/runtime/persistence/TownWorldRestoreState.gd"
)
const WORLD_LOG_STORE := preload(
	"res://world/runtime/log/TownWorldLogStore.gd"
)


static func prepare_save_candidate(
	world,
	event_journal,
	world_log_store,
	world_data: Dictionary,
	opening_config: Dictionary,
	identity_status: String,
	resident_order: Array[String],
	resident_names: Dictionary,
	save_candidate_runtime,
	runtime_generation: int,
	world_revision: int,
) -> Dictionary:
	if not event_journal.consistency_error().is_empty():
		return _failure(
			"WORLD_LOG_CONSISTENCY_ERROR",
			[event_journal.consistency_error()],
		)
	var snapshot_result := world.create_save_snapshot() as Dictionary
	if snapshot_result.get("ok") != true:
		return snapshot_result
	var snapshot := (
		snapshot_result.get("snapshot", {}) as Dictionary
	).duplicate(true)
	var world_log_snapshot := world_log_store.create_save_snapshot(
		world_revision,
	) as Dictionary
	if world_log_snapshot.is_empty():
		return _failure(
			"WORLD_LOG_SNAPSHOT_INVALID",
			["世界日志无法生成保存快照"],
		)
	var restore_compatibility := prepare_snapshot_state_for_restore(
		world,
		world_data,
		opening_config,
		snapshot,
	)
	if restore_compatibility.get("ok") != true:
		return _failure(
			"WORLD_SAVE_RESTORE_VALIDATION_FAILED",
			restore_compatibility.get(
				"errors",
				["当前 World 状态无法生成可恢复存档"],
			) as Array,
		)
	var identity_snapshot: Variant = world.get_resident_identity_snapshot()
	var resident_ids_result := SAVE_CANDIDATE_RUNTIME.resident_ids_from_identity_snapshot(
		identity_snapshot,
		identity_status,
		resident_order,
		resident_names,
	) as Dictionary
	if resident_ids_result.get("ok") != true:
		return _failure(
			"WORLD_SAVE_IDENTITY_INVALID",
			resident_ids_result.get(
				"errors",
				["当前居民身份无法生成 World 保存候选"],
			) as Array,
		)
	return save_candidate_runtime.prepare(
		runtime_generation,
		world_revision,
		snapshot,
		world_log_snapshot,
		identity_snapshot as Dictionary,
		resident_ids_result.get("residentIds", []) as Array,
	) as Dictionary


static func prepare_restore_candidate(
	world,
	world_data: Dictionary,
	opening_config: Dictionary,
	snapshot: Dictionary,
	resident_identities: Variant,
	require_world_ready: bool,
	world_log_snapshot: Dictionary,
	world_running: bool,
	identity_status: String,
	restore_candidate_runtime,
	runtime_generation: int,
	world_revision: int,
) -> Dictionary:
	var prepared_identities := OPENING_CONFIG.prepare_resident_identities(
		opening_config,
		resident_identities,
		require_world_ready,
	) as Dictionary
	if world_running and identity_status == "confirmed":
		var requested_identity_snapshot := {
			"status": String(prepared_identities.get("status", "")),
			"residents": (
				prepared_identities.get("residents", []) as Array
			).duplicate(true),
		}
		if (
			prepared_identities.get("ok") != true
			or requested_identity_snapshot != world.get_resident_identity_snapshot()
		):
			return _failure(
				"WORLD_RESTORE_IDENTITY_DRIFT",
				["恢复身份集合与当前 World 权威身份集合不一致"],
			)
	var startup_validation := world.validate_startup(
		world_data,
		opening_config,
		require_world_ready,
		resident_identities,
	) as Dictionary
	if startup_validation.get("ok") != true:
		return startup_validation
	var restore_compatibility := prepare_snapshot_state_for_restore(
		world,
		world_data,
		opening_config,
		snapshot,
	)
	if restore_compatibility.get("ok") != true:
		return _failure(
			"SAVE_SNAPSHOT_INVALID",
			restore_compatibility.get(
				"errors",
				["世界存档无法恢复"],
			) as Array,
		)
	var prepared := restore_compatibility.get("preparedState", {}) as Dictionary
	var prepared_world_log: RefCounted = WORLD_LOG_STORE.new()
	var world_log_restore := prepared_world_log.restore_save_snapshot(
		world_log_snapshot.duplicate(true),
		prepared,
	) as Dictionary
	if world_log_restore.get("ok") != true:
		return _failure(
			"WORLD_LOG_SNAPSHOT_INVALID",
			["世界日志存档无法恢复"],
		)
	return restore_candidate_runtime.prepare(
		runtime_generation,
		world_revision,
		require_world_ready,
		world_data,
		opening_config,
		prepared_identities,
		prepared,
		prepared_world_log,
		int(snapshot.get("schemaVersion", 0)),
		restore_compatibility.get("migrationReceipt", {}) as Dictionary,
	) as Dictionary


static func prepare_snapshot_state_for_restore(
	world,
	world_data: Dictionary,
	opening_config: Dictionary,
	snapshot: Dictionary,
) -> Dictionary:
	var errors := SAVE_CODEC.validate_envelope(
		snapshot,
		world_data,
		opening_config,
	) as Array[String]
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	var decoded := SAVE_CODEC.decode_checked(snapshot.get("state", {})) as Dictionary
	if decoded.get("ok") != true:
		return {
			"ok": false,
			"errors": (
				decoded.get("errors", ["世界存档反序列化失败"]) as Array
			).duplicate(true),
		}
	return RESTORE_STATE.prepare_full(
		world,
		world_data,
		opening_config,
		decoded.get("value", {}) as Dictionary,
	)


static func _failure(error_code: String, errors: Array) -> Dictionary:
	return {
		"ok": false,
		"errorCode": error_code,
		"errors": errors.duplicate(true),
		"retryable": false,
	}
