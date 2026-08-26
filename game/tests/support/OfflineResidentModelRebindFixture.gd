class_name OfflineResidentModelRebindFixture
extends RefCounted


const SAVE_STORE := preload(
	"res://world/presentation/session/TownSessionSaveStore.gd"
)
const AGENT_STORE := preload("res://agent/lifecycle/AgentSaveStore.gd")
const SAVE_MANIFEST := preload(
	"res://world/presentation/session/TownSessionSaveManifest.gd"
)
const SAVE_CATALOG := preload(
	"res://world/presentation/session/TownStartupSaveCatalog.gd"
)
const CURRENT_SAVE_FIXTURE_ROOT := (
	"res://tests/fixtures/historical_saves/beta6/town_session_saves/slots/"
	+ "roundtrip-slot-beta6/sessions/roundtrip-session-beta6/revisions/"
	+ "00000000000000000001"
)
const CURRENT_AGENT_FIXTURE_ROOT := (
	"res://tests/fixtures/historical_saves/beta6/agent_saves/"
	+ "roundtrip-slot-beta6/sessions/roundtrip-session-beta6/revisions/1"
)


class AvailableProvider:
	extends RefCounted
	var available := true
	var unavailable_model_ids: Array[String] = []

	func set_available(value: bool) -> void:
		available = value

	func set_unavailable_models(model_ids: Array) -> void:
		unavailable_model_ids.clear()
		for model_id: Variant in model_ids:
			unavailable_model_ids.append(String(model_id))

	func get_health_snapshot() -> Dictionary:
		if not available:
			return {
				"ok": false,
				"errorCode": "PROVIDER_HEALTH_UNAVAILABLE",
				"retryable": false,
			}
		return {
			"ok": true,
			"formalReady": true,
			"capabilityMode": "formal",
			"source": "runtime",
			"providers": [{
				"providerId": "current-provider",
				"label": "当前服务",
				"status": "available",
			}],
		}

	func list_available_models() -> Array:
		var models: Array[Dictionary] = []
		if not available:
			return models
		for model_id in ["current-model", "current-model-2", "current-model-3"]:
			models.append({
				"providerId": "current-provider",
				"modelId": model_id,
				"label": model_id,
				"available": model_id not in unavailable_model_ids,
			})
		return models

	func validate_resident_bindings(bindings: Variant) -> Dictionary:
		if not bindings is Array:
			return _failure("SESSION_LLM_BINDINGS_INVALID")
		for value: Variant in bindings as Array:
			if not value is Dictionary:
				return _failure("SESSION_LLM_BINDINGS_INVALID")
			var binding := (value as Dictionary).get("llmBinding", {}) as Dictionary
			if (
				String(binding.get("providerId", "")) != "current-provider"
				or String(binding.get("modelId", ""))
				not in ["current-model", "current-model-2", "current-model-3"]
				or unavailable_model_ids.has(String(binding.get("modelId", "")))
			):
				return _failure("LLM_MODEL_UNAVAILABLE")
		return {"ok": true, "errorCode": "", "retryable": false}

	func _failure(error_code: String) -> Dictionary:
		return {"ok": false, "errorCode": error_code, "retryable": false}


var slot_id := ""
var session_id := ""
var save_root := ""
var agent_root := ""
var profile_path := ""
var save_store: RefCounted
var agent_store: RefCounted


func configure(identity: String, agent_override: RefCounted = null) -> Dictionary:
	slot_id = "town-main"
	session_id = "offline-model-session-%s-%s" % ["r".repeat(80), identity]
	save_root = "user://tests/town_session_saves/offline_model_%s" % identity
	agent_root = "user://agent_save_tests/offline_model_%s" % identity
	profile_path = "user://tests/town_startup_profile/offline_model_%s.json" % identity
	save_store = SAVE_STORE.new()
	agent_store = agent_override if agent_override != null else AGENT_STORE.new()
	var world_configured := save_store.call("configure_test_root", save_root) as Dictionary
	if world_configured.get("ok") != true:
		return world_configured
	return agent_store.call("configure_test_root", agent_root) as Dictionary


func provider() -> RefCounted:
	return AvailableProvider.new()


func create_source_revision() -> Dictionary:
	var payloads := {
		"resident-a": {
			"resident_name": "甲居民",
			"payload": FileAccess.get_file_as_bytes(
				"%s/resident_0000.bin" % CURRENT_AGENT_FIXTURE_ROOT,
			),
		},
		"resident-b": {
			"resident_name": "乙居民",
			"payload": FileAccess.get_file_as_bytes(
				"%s/resident_0001.bin" % CURRENT_AGENT_FIXTURE_ROOT,
			),
		},
	}
	var created := agent_store.call("create_new_game", {
		"slot_id": slot_id,
		"session_id": session_id,
		"save_revision": 0,
	}, payloads) as Dictionary
	if created.get("ok") != true:
		return created
	var reserved := save_store.call("reserve_revision", slot_id, session_id) as Dictionary
	if reserved.get("ok") != true:
		return reserved
	var context := reserved.get("context", {}) as Dictionary
	var agent_saved := agent_store.call("save_snapshot", context, payloads) as Dictionary
	if agent_saved.get("ok") != true:
		return agent_saved
	var stored := save_store.call(
		"write_world_candidate",
		context,
		world_snapshot(),
		session_config(),
		world_log_snapshot(),
	) as Dictionary
	if stored.get("ok") != true:
		return stored
	var manifest := SAVE_MANIFEST.build(
		context,
		Time.get_datetime_string_from_system(false, false),
		stored.get("sessionConfigRef"),
		stored.get("sessionConfigSha256"),
		["resident-a", "resident-b"],
		{
			"snapshotRef": stored.get("snapshotRef"),
			"worldRevision": 9,
			"schema": "town-world-save",
			"schemaVersion": 2,
			"worldDataVersion": 4,
			"day": 1,
		},
		stored.get("snapshotSha256"),
		[],
		{
			"snapshotRef": stored.get("worldLogSnapshotRef"),
			"snapshotSha256": stored.get("worldLogSnapshotSha256"),
			"schema": "town-world-log-snapshot",
			"schemaVersion": 1,
			"timelineId": "offline-model-timeline",
			"maxSequence": 0,
			"worldRevision": 9,
		},
	) as Dictionary
	var published := save_store.call("publish_manifest", manifest) as Dictionary
	if published.get("ok") != true:
		return published
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"context": context,
		"manifest": manifest,
	}


func catalog_slot() -> Dictionary:
	var catalog := SAVE_CATALOG.new() as RefCounted
	var configured := catalog.call(
		"configure",
		save_store,
		profile_path,
		agent_store,
	) as Dictionary
	if configured.get("ok") != true:
		return {"fixtureError": configured}
	var result := catalog.call("get_catalog", slot_definitions()) as Dictionary
	if result.get("ok") != true:
		return {"fixtureError": result}
	return ((result.get("slots", []) as Array)[0] as Dictionary).duplicate(true)


func create_recoverable_catalog_slot() -> Dictionary:
	var listed := save_store.call("list_published", slot_id) as Dictionary
	var manifests := listed.get("manifests", []) as Array
	if manifests.is_empty():
		return {"ok": false, "errorCode": "TEST_SOURCE_MANIFEST_MISSING"}
	var latest := manifests[0] as Dictionary
	var components := latest.get("components", {}) as Dictionary
	var world_component := components.get("world", {}) as Dictionary
	var log_component := components.get("world_log", {}) as Dictionary
	var world := save_store.call("read_reference", world_component.get("snapshot_ref"), world_component.get("snapshot_sha256")) as Dictionary
	var config := save_store.call("read_reference", latest.get("session_config_ref"), latest.get("session_config_sha256")) as Dictionary
	var world_log := save_store.call("read_world_log_snapshot", log_component.get("snapshot_ref"), log_component.get("snapshot_sha256")) as Dictionary
	var source_agent := agent_store.call("load_snapshot", {
		"slot_id": slot_id,
		"session_id": session_id,
		"save_revision": int(latest.get("save_revision", 0)),
	}) as Dictionary
	for result in [world, config, world_log, source_agent]:
		if not bool((result as Dictionary).get("ok", false)):
			return result as Dictionary
	var reserved := save_store.call("reserve_revision", slot_id, session_id) as Dictionary
	if reserved.get("ok") != true:
		return reserved
	var context := reserved.get("context", {}) as Dictionary
	var begun := save_store.call("begin_intent", context, "save") as Dictionary
	if begun.get("ok") != true:
		return begun
	var intent_id := String(begun.get("intentId", ""))
	for stage in ["save_started"]:
		var staged := save_store.call("write_intent_stage", context, "save", intent_id, stage, {}) as Dictionary
		if staged.get("ok") != true:
			return staged
	var stored := save_store.call("write_world_candidate", context, world.get("value", {}), config.get("value", {}), world_log.get("value", {})) as Dictionary
	if stored.get("ok") != true:
		return stored
	for stage in ["world_candidate_written", "agent_commit_started"]:
		var staged := save_store.call("write_intent_stage", context, "save", intent_id, stage, {}) as Dictionary
		if staged.get("ok") != true:
			return staged
	var agent_saved := agent_store.call("save_snapshot", context, source_agent.get("resident_payloads", {})) as Dictionary
	if agent_saved.get("ok") != true:
		return agent_saved
	var committed := save_store.call("write_intent_stage", context, "save", intent_id, "agent_committed", {}) as Dictionary
	if committed.get("ok") != true:
		return committed
	return {"ok": true, "context": context, "slot": catalog_slot()}


func slot_definitions() -> Array[Dictionary]:
	return [
		{"slotId": slot_id, "displayName": "离线模型小镇"},
		{"slotId": "empty-slot", "displayName": "空槽位"},
	]


func base_catalog() -> Dictionary:
	return {"residents": [
		{"residentId": "resident-a", "attributes": {"name": "甲居民"}, "presentation": {"portraitRef": "res://missing/portrait-a.png"}},
		{"residentId": "resident-b", "attributes": {"name": "乙居民"}, "presentation": {}},
	]}


func session_config() -> Dictionary:
	var fixture := _read_json("%s/session_config.json" % CURRENT_SAVE_FIXTURE_ROOT)
	return {
		"mode": "continue",
		"sessionId": session_id,
		"openingConfig": (fixture.get("openingConfig", {}) as Dictionary).duplicate(true),
		"residentIdentities": [
			{"residentId": "resident-a", "residentName": "甲居民"},
			{"residentId": "resident-b", "residentName": "乙居民"},
		],
		"residentBindings": bindings_for("retired-provider", "retired-model"),
		"connectedResidents": ["甲居民", "乙居民"],
		"worldStartMode": "formal",
		"useLiveModel": true,
		"enablePlayerAvatar": false,
		"enableTestUi": false,
	}


func bindings_for(provider_id: String, model_id: String) -> Array[Dictionary]:
	return [
		{"residentId": "resident-a", "llmBinding": {"mode": "model", "providerId": provider_id, "modelId": model_id}},
		{"residentId": "resident-b", "llmBinding": {"mode": "model", "providerId": provider_id, "modelId": model_id}},
	]


func world_snapshot() -> Dictionary:
	return _read_json("%s/world_snapshot.json" % CURRENT_SAVE_FIXTURE_ROOT)


func world_log_snapshot() -> Dictionary:
	return {
		"schema": "town-world-log-snapshot",
		"schemaVersion": 1,
		"timelineId": "offline-model-timeline",
		"worldRevision": 9,
		"maxSequence": 0,
		"records": [],
		"readState": {},
	}


func cleanup() -> void:
	if agent_store != null:
		agent_store.call("cleanup_test_root")
	if save_store != null:
		save_store.call("cleanup_test_root")
	if FileAccess.file_exists(profile_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(profile_path))


func _read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return (parsed as Dictionary).duplicate(true) if parsed is Dictionary else {}
