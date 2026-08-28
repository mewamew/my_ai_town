class_name TownHistoricalSaveUpgrader
extends RefCounted
## 把已登记的旧修订恢复到当前运行时，再以新的成对修订原子发布。原修订保持只读。


const COMPATIBILITY := preload(
	"res://world/presentation/session/TownSaveCompatibilityRegistry.gd"
)
const MANIFEST := preload(
	"res://world/presentation/session/TownSessionSaveManifest.gd"
)

const ERROR_NOT_CONFIGURED := "SAVE_UPGRADER_NOT_CONFIGURED"
const ERROR_REQUEST_INVALID := "SAVE_UPGRADE_REQUEST_INVALID"
const ERROR_MIGRATION_INCOMPLETE := "SAVE_UPGRADE_MIGRATION_INCOMPLETE"
const ERROR_VERIFICATION_FAILED := "SAVE_UPGRADE_VERIFICATION_FAILED"

var _coordinator: Object
var _runtime: Node
var _catalog: Object


func configure(coordinator: Object, runtime: Node, catalog: Object) -> Dictionary:
	if (
		coordinator == null
		or runtime == null
		or catalog == null
		or not is_instance_valid(runtime)
		or not coordinator.has_method("restore_revision")
		or not coordinator.has_method("save")
		or not runtime.has_method("complete_restored_session")
		or not runtime.has_method("record_published_save")
		or not catalog.has_method("get_catalog")
	):
		return _failure(ERROR_NOT_CONFIGURED)
	_coordinator = coordinator
	_runtime = runtime
	_catalog = catalog
	return _success()


func upgrade(source: Dictionary, publication: Dictionary) -> Dictionary:
	if _coordinator == null or _runtime == null or _catalog == null:
		return _failure(ERROR_NOT_CONFIGURED)
	var request := _validate_request(source, publication)
	if request.get("ok") != true:
		return request
	var context := source.get("context", {}) as Dictionary
	var session_config := source.get("sessionConfig", {}) as Dictionary
	var evidence := (
		source.get("releaseEvidence", {}) as Dictionary
	).duplicate(true)
	var recorded_release := String(
		session_config.get("saveRelease", "")
	).strip_edges()
	if not recorded_release.is_empty():
		evidence["recordedRelease"] = recorded_release
	var detected := COMPATIBILITY.detect_release(evidence)
	if detected.get("ok") != true:
		return detected
	var migration_start := String(detected.get("migrationStartRelease", ""))
	var path := COMPATIBILITY.migration_path(migration_start)
	if path.get("ok") != true:
		return path
	if (
		String(detected.get("release", "")) == COMPATIBILITY.current_release()
		and bool(detected.get("exact", false))
		and recorded_release == COMPATIBILITY.current_release()
	):
		var current_verification := _verify_publication(
			String(context.get("slot_id", "")),
			int(context.get("save_revision", -1)),
			publication.get("slotDefinitions", []) as Array,
		)
		if current_verification.get("ok") != true:
			return current_verification
		return {
			"ok": true,
			"errorCode": "",
			"retryable": false,
			"changed": false,
			"detection": detected.duplicate(true),
			"migrationPath": path.duplicate(true),
			"context": context.duplicate(true),
			"verification": (
				current_verification.get("verification", {}) as Dictionary
			).duplicate(true),
		}

	var restored := _coordinator.restore_revision(
		String(context.get("slot_id", "")),
		String(context.get("session_id", "")),
		int(context.get("save_revision", -1)),
		(source.get("worldData", {}) as Dictionary).duplicate(true),
		(source.get("residentIdentities", []) as Array).duplicate(true),
		source.get("agentHydrator"),
	) as Dictionary
	if restored.get("ok") != true:
		return restored
	var completed := _runtime.complete_restored_session(
		restored.get("context", {}) as Dictionary,
	) as Dictionary
	if completed.get("ok") != true:
		return completed
	var migration_receipt := (
		(restored.get("commitReceipt", {}) as Dictionary)
		.get("migrationReceipt", {}) as Dictionary
	).duplicate(true)
	if not _contains_required_migrations(path, migration_receipt):
		return _failure(ERROR_MIGRATION_INCOMPLETE)

	var target_config := session_config.duplicate(true)
	target_config["mode"] = "continue"
	target_config["saveRelease"] = COMPATIBILITY.current_release()
	var saved := _coordinator.save({
		"slotId": context.get("slot_id"),
		"sessionId": context.get("session_id"),
		"residentIdentities": (
			source.get("residentIdentities", []) as Array
		).duplicate(true),
		"sessionConfig": target_config,
			"residentMessages": (
				publication.get("residentMessages", []) as Array
		).duplicate(true),
	}) as Dictionary
	if saved.get("ok") != true:
		return saved
	var published_context := saved.get("context", {}) as Dictionary
	var runtime_update := _runtime.record_published_save(
		published_context,
	) as Dictionary
	if runtime_update.get("ok") != true:
		return runtime_update
	var verification := _verify_publication(
		String(context.get("slot_id", "")),
		int(published_context.get("save_revision", -1)),
		publication.get("slotDefinitions", []) as Array,
	)
	if verification.get("ok") != true:
		return verification
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"changed": true,
		"detection": detected.duplicate(true),
		"migrationPath": path.duplicate(true),
		"migrationReceipt": migration_receipt,
		"restoredContext": (
			restored.get("context", {}) as Dictionary
		).duplicate(true),
		"context": published_context.duplicate(true),
		"manifest": (saved.get("manifest", {}) as Dictionary).duplicate(true),
		"verification": verification.get("verification", {}).duplicate(true),
	}


func _validate_request(source: Dictionary, publication: Dictionary) -> Dictionary:
	var context_value: Variant = source.get("context")
	if (
		not context_value is Dictionary
		or MANIFEST.validate_context(context_value).get("ok") != true
		or int((context_value as Dictionary).get("save_revision", 0)) < 1
		or not source.get("releaseEvidence") is Dictionary
		or not source.get("sessionConfig") is Dictionary
		or not source.get("worldData") is Dictionary
		or not source.get("residentIdentities") is Array
		or (source.get("residentIdentities", []) as Array).is_empty()
		or source.get("agentHydrator") == null
		or not publication.get("slotDefinitions") is Array
		or (publication.get("slotDefinitions", []) as Array).is_empty()
		or not publication.get("residentMessages", []) is Array
	):
		return _failure(ERROR_REQUEST_INVALID)
	return _success()


func _contains_required_migrations(
	path: Dictionary,
	receipt: Dictionary,
) -> bool:
	var applied_value: Variant = receipt.get("applied")
	if not applied_value is Array:
		return false
	var applied := applied_value as Array
	for edge_value: Variant in path.get("edges", []) as Array:
		if not edge_value is Dictionary:
			return false
		for migration_id: Variant in (
			(edge_value as Dictionary).get("migrationIds", []) as Array
		):
			if not applied.has(migration_id):
				return false
	return true


func _verify_publication(
	slot_id: String,
	published_revision: int,
	slot_definitions: Array,
) -> Dictionary:
	var inspected := _catalog.get_catalog(
		slot_definitions.duplicate(true),
	) as Dictionary
	if inspected.get("ok") != true:
		return _failure(ERROR_VERIFICATION_FAILED)
	for slot_value: Variant in inspected.get("slots", []) as Array:
		if not slot_value is Dictionary:
			continue
		var slot := slot_value as Dictionary
		var summary := slot.get("summary", {}) as Dictionary
		if String(summary.get("slotId", "")) != slot_id:
			continue
		if (
			String(slot.get("state", "")) != "healthy"
			or int(summary.get("saveRevision", -1)) != published_revision
		):
			return _failure(ERROR_VERIFICATION_FAILED)
		return {
			"ok": true,
			"verification": {
				"state": "healthy",
				"saveRevision": published_revision,
				"agentIntegrity": String(slot.get("agentIntegrity", "")),
			},
		}
	return _failure(ERROR_VERIFICATION_FAILED)


func _success() -> Dictionary:
	return {"ok": true, "errorCode": "", "retryable": false}


func _failure(error_code: String) -> Dictionary:
	return {"ok": false, "errorCode": error_code, "retryable": false}
