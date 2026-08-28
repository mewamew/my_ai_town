class_name TownSessionUiService
extends RefCounted


const RESULT_SHAPES := preload(
	"res://world/contract/TownWorldResultShapes.gd"
)
const STORE := preload(
	"res://world/presentation/session/TownSessionSaveStore.gd"
)
const RUNTIME_GATE := preload(
	"res://world/presentation/session/TownSessionRuntimeGate.gd"
)
const COORDINATOR := preload(
	"res://world/presentation/session/TownSessionSaveCoordinator.gd"
)
const ASYNC_SAVE_JOB := preload(
	"res://world/presentation/session/TownSessionAsyncSaveJob.gd"
)
const MANIFEST := preload(
	"res://world/presentation/session/TownSessionSaveManifest.gd"
)
const RECOVERY_PLANNER := preload(
	"res://world/presentation/session/TownSaveRecoveryPlanner.gd"
)
const COMPATIBILITY := preload(
	"res://world/presentation/session/TownSaveCompatibilityRegistry.gd"
)
const HISTORICAL_UPGRADER := preload(
	"res://world/presentation/session/TownHistoricalSaveUpgrader.gd"
)
const RECONCILIATION_SERVICE := preload(
	"res://world/presentation/session/TownSaveReconciliationService.gd"
)
const AGENT_STORE := preload("res://agent/lifecycle/AgentSaveStore.gd")

const FORMAL_WORLD_REQUIRED := "SESSION_SAVE_FORMAL_WORLD_REQUIRED"
const SERVICE_NOT_CONFIGURED := "SESSION_SAVE_SERVICE_NOT_CONFIGURED"
const ASYNC_SAVE_RESIDENTS_PER_FRAME := 1

var _runtime: Node
var _world: Object
var _agent: Object
var _session_config: Dictionary = {}
var _store: RefCounted
var _gate: RefCounted
var _coordinator: RefCounted
var _configuration_error: Dictionary = {}
var _last_result: Dictionary = {}
var _test_store_root := ""
var _async_save_job: RefCounted
var _async_save_previous_agent_context: Dictionary = {}
var _async_save_completion: Dictionary = {}
var _async_save_capture_msec := 0.0
var _async_save_capture: Dictionary = {}


func configure_test_store_root(path: String) -> Dictionary:
	if _coordinator != null or _store != null:
		return _failure("SESSION_SAVE_SERVICE_ALREADY_CONFIGURED", false)
	var candidate: RefCounted = STORE.new()
	var configured := candidate.call("configure_test_root", path) as Dictionary
	if configured.get("ok") != true:
		return configured
	_test_store_root = path.trim_suffix("/")
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
	}


func configure(
	runtime: Node,
	world: Object,
	agent: Object,
	session_config: Dictionary,
) -> Dictionary:
	if _async_save_job != null or not _async_save_capture.is_empty():
		return _failure("SESSION_SAVE_BUSY", true)
	_runtime = runtime
	_world = world
	_agent = agent
	_session_config = session_config.duplicate(true)
	_configuration_error.clear()
	_last_result.clear()
	_async_save_previous_agent_context.clear()
	_async_save_completion.clear()
	_async_save_capture_msec = 0.0
	_async_save_capture.clear()
	if (
		runtime == null
		or world == null
		or agent == null
		or not is_instance_valid(runtime)
		or not is_instance_valid(world)
		or not is_instance_valid(agent)
	):
		return _remember_configuration_failure(
			"SESSION_SAVE_RUNTIME_DEPENDENCY_MISSING",
		)
	if not agent.has_method("get_save_context"):
		return _remember_configuration_failure(
			"SESSION_SAVE_AGENT_PARTICIPANT_MISSING",
		)
	if not runtime.has_method("get_resident_identity_snapshot"):
		return _remember_configuration_failure(
			"SESSION_SAVE_RUNTIME_DEPENDENCY_MISSING",
		)
	_store = STORE.new()
	if not _test_store_root.is_empty():
		var store_configuration := _store.call(
			"configure_test_root",
			_test_store_root,
		) as Dictionary
		if store_configuration.get("ok") != true:
			return _remember_configuration_result(store_configuration)
	_gate = RUNTIME_GATE.new()
	var gate_result := _gate.call("configure", runtime) as Dictionary
	if gate_result.get("ok") != true:
		return _remember_configuration_result(gate_result)
	_coordinator = COORDINATOR.new()
	var configured := _coordinator.call(
		"configure",
		_store,
		world,
		agent,
		_gate,
	) as Dictionary
	if configured.get("ok") != true:
		return _remember_configuration_result(configured)
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
	}


func get_save_snapshot() -> Dictionary:
	var blocker := _save_blocker()
	var slots: Array[Dictionary] = []
	var selected_save_id := ""
	var slot_id := _session_slot_id()
	if blocker.is_empty() and _coordinator != null and not slot_id.is_empty():
		var discovered := _coordinator.call("discover_latest", slot_id) as Dictionary
		if discovered.get("ok") == true:
			var summary := (
				discovered.get("summary", {}) as Dictionary
			).duplicate(true)
			selected_save_id = "%s:%d" % [
				String(summary.get("slotId", slot_id)),
				int(summary.get("saveRevision", 0)),
			]
			summary["saveId"] = selected_save_id
			slots.append(summary)
		elif String(discovered.get("errorCode", "")) != (
			"SESSION_SAVE_NO_PUBLISHED_REVISION"
		):
			blocker = String(
				discovered.get(
					"errorCode",
					"SESSION_SAVE_STORE_FAILED",
				),
			)
	var can_save := blocker.is_empty()
	var can_continue := can_save and not slots.is_empty()
	return {
		"configured": _coordinator != null and _configuration_error.is_empty(),
		"canSave": can_save,
		"canContinue": can_continue,
		"disabledReason": blocker,
		"continueDisabledReason": (
			"" if can_continue else (
				"SESSION_SAVE_NO_PUBLISHED_REVISION" if can_save else blocker
			)
		),
		"slots": slots,
		"selectedSaveId": selected_save_id,
		"saveInProgress": (
			_async_save_job != null or not _async_save_capture.is_empty()
		),
		"source": String(_session_config.get("source", "runtime")),
		"capabilityMode": String(
			_session_config.get("capabilityMode", "development"),
		),
		"formalReady": bool(_session_config.get("formalReady", false)),
		"lastResult": _last_result.duplicate(true),
	}


func update_resident_bindings(bindings_value: Variant) -> Dictionary:
	if not bindings_value is Array:
		return _failure("SESSION_LLM_BINDINGS_INVALID", false)
	var identities_value: Variant = _session_config.get("residentIdentities", [])
	if not identities_value is Array:
		return _failure("SESSION_RESIDENT_IDENTITIES_INVALID", false)
	var expected_ids: Dictionary = {}
	for identity_value: Variant in identities_value as Array:
		if not identity_value is Dictionary:
			return _failure("SESSION_RESIDENT_IDENTITIES_INVALID", false)
		var resident_id := String(
			(identity_value as Dictionary).get("residentId", "")
		).strip_edges()
		if resident_id.is_empty() or expected_ids.has(resident_id):
			return _failure("SESSION_RESIDENT_IDENTITIES_INVALID", false)
		expected_ids[resident_id] = true
	var seen_ids: Dictionary = {}
	var normalized: Array[Dictionary] = []
	for binding_value: Variant in bindings_value as Array:
		if not binding_value is Dictionary:
			return _failure("SESSION_LLM_BINDINGS_INVALID", false)
		var binding := binding_value as Dictionary
		var resident_id := String(binding.get("residentId", "")).strip_edges()
		if (
			resident_id.is_empty()
			or not expected_ids.has(resident_id)
			or seen_ids.has(resident_id)
			or not binding.get("llmBinding", {}) is Dictionary
		):
			return _failure("SESSION_LLM_BINDINGS_INVALID", false)
		seen_ids[resident_id] = true
		normalized.append({
			"residentId": resident_id,
			"llmBinding": (
				binding.get("llmBinding", {}) as Dictionary
			).duplicate(true),
		})
	if seen_ids.size() != expected_ids.size():
		return _failure("SESSION_LLM_BINDINGS_INVALID", false)
	normalized.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("residentId", "")) < String(b.get("residentId", ""))
	)
	var previous := (
		_session_config.get("residentBindings", []) as Array
	).duplicate(true)
	_session_config["residentBindings"] = normalized.duplicate(true)
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"changed": normalized != previous,
		"previousBindings": previous,
		"residentBindings": normalized,
	}


func update_resident_roster(
	identities_value: Variant,
	bindings_value: Variant,
	opening_config_value: Variant,
) -> Dictionary:
	if (
		not identities_value is Array
		or not bindings_value is Array
		or not opening_config_value is Dictionary
	):
		return _failure("SESSION_RESIDENT_ROSTER_INVALID", false)
	var identities := (identities_value as Array).duplicate(true)
	var bindings := (bindings_value as Array).duplicate(true)
	if identities.is_empty() or identities.size() != bindings.size():
		return _failure("SESSION_RESIDENT_ROSTER_INVALID", false)
	_session_config["residentIdentities"] = identities
	_session_config["residentBindings"] = bindings
	_session_config["openingConfig"] = (
		opening_config_value as Dictionary
	).duplicate(true)
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"changed": true,
		"residentCount": identities.size(),
	}


func create_save(payload: Dictionary = {}) -> Dictionary:
	if _async_save_job != null or not _async_save_capture.is_empty():
		var background_result := finish_create_save_async()
		if (
			not bool(background_result.get("ok", false))
			and bool(
				(background_result.get("meta", {}) as Dictionary).get(
					"published",
					false,
				)
			)
		):
			return background_result
	var blocker := _save_blocker()
	if not blocker.is_empty():
		_last_result = _failure(blocker, false)
		return _last_result.duplicate(true)
	var result := _coordinator.save(_save_request(payload)) as Dictionary
	_last_result = result.duplicate(true)
	return result


func execute_recovery_plan(
	plan: Dictionary,
	confirmation: Dictionary,
	payload: Dictionary = {},
) -> Dictionary:
	var active_context := (
		_agent.get_save_context() as Dictionary
		if _agent != null and _agent.has_method("get_save_context")
		else {}
	)
	var source_revision := int(plan.get("sourceSaveRevision", -1))
	var damaged_revision := int(plan.get("damagedSaveRevision", -1))
	var slot_id := String(plan.get("slotId", ""))
	var session_id := String(plan.get("sourceSessionId", ""))
	var expected_plan_id := RECOVERY_PLANNER.plan_id(
		slot_id,
		source_revision,
		damaged_revision,
	)
	if (
		int(plan.get("version", 0)) != RECOVERY_PLANNER.PLAN_VERSION
		or String(plan.get("planId", "")) != expected_plan_id
		or String(plan.get("action", ""))
		!= RECOVERY_PLANNER.REPUBLISH_ACTION
		or not bool(plan.get("confirmationRequired", false))
		or confirmation != {
			"confirmed": true,
			"planId": expected_plan_id,
		}
		or slot_id != _session_slot_id()
		or session_id != _session_id()
		or source_revision < 1
		or damaged_revision <= source_revision
		or String(active_context.get("slot_id", "")) != slot_id
		or String(active_context.get("session_id", "")) != session_id
		or int(active_context.get("save_revision", -1)) != source_revision
	):
		_last_result = _failure("SESSION_SAVE_RECOVERY_PLAN_INVALID", false)
		return _last_result.duplicate(true)
	var published := create_save(payload)
	if not bool(published.get("ok", false)):
		return published
	var published_context := published.get("context", {}) as Dictionary
	var published_revision := int(
		published_context.get("save_revision", -1),
	)
	if (
		String(published_context.get("slot_id", "")) != slot_id
		or String(published_context.get("session_id", "")) != session_id
		or published_revision <= damaged_revision
	):
		_last_result = _failure(
			"SESSION_SAVE_RECOVERY_PUBLICATION_INVALID",
			false,
		)
		return _last_result.duplicate(true)
	_session_config["saveRevision"] = published_revision
	var result := published.duplicate(true)
	result["repairReceipt"] = {
		"planId": String(plan.get("planId", "")),
		"action": String(plan.get("action", "")),
		"sourceSaveRevision": source_revision,
		"damagedSaveRevision": damaged_revision,
		"publishedSaveRevision": published_revision,
		"rebuiltDerivedData": [
			"manifest_index",
			"session_config_projection",
			"startup_summary",
		],
	}
	_last_result = result.duplicate(true)
	return result


func execute_reconciliation_plan(
	plan: Dictionary,
	confirmation: Dictionary,
) -> Dictionary:
	if _store == null:
		return _failure(SERVICE_NOT_CONFIGURED, false)
	var service := RECONCILIATION_SERVICE.new()
	var configured := service.configure(_store, AGENT_STORE.new()) as Dictionary
	if configured.get("ok") != true:
		return configured
	var result := service.execute(plan, confirmation) as Dictionary
	_last_result = result.duplicate(true)
	return result


func upgrade_revision(
	source: Dictionary,
	publication: Dictionary,
	catalog: Object,
) -> Dictionary:
	if not _configuration_error.is_empty() or _coordinator == null:
		return _failure(SERVICE_NOT_CONFIGURED, false)
	var upgrader := HISTORICAL_UPGRADER.new()
	var configured := upgrader.configure(
		_coordinator,
		_runtime,
		catalog,
	) as Dictionary
	if configured.get("ok") != true:
		return configured
	var upgraded := upgrader.upgrade(
		source.duplicate(true),
		publication.duplicate(true),
	) as Dictionary
	_last_result = upgraded.duplicate(true)
	return upgraded


func restore_discovered_revision(
	discovery: Dictionary,
	world_data: Dictionary,
	resident_identities: Array,
	agent_hydrator: Object,
	publication: Dictionary,
	catalog: Object,
) -> Dictionary:
	var compatibility_value: Variant = discovery.get("compatibility")
	if not compatibility_value is Dictionary:
		return _failure("SAVE_COMPATIBILITY_EVIDENCE_INVALID", false)
	var compatibility := compatibility_value as Dictionary
	var restore_gate := COMPATIBILITY.restore_gate(compatibility)
	if restore_gate.get("ok") != true:
		return restore_gate
	var manifest := discovery.get("manifest", {}) as Dictionary
	var session_config := discovery.get("sessionConfig", {}) as Dictionary
	if (
		manifest.is_empty()
		or session_config.is_empty()
		or not discovery.get("compatibilityEvidence") is Dictionary
	):
		return _failure("SAVE_COMPATIBILITY_EVIDENCE_INVALID", false)
	if String(compatibility.get("supportStatus", "")) == COMPATIBILITY.STATUS_SUPPORTED:
		var upgraded := upgrade_revision({
			"context": {
				"slot_id": String(manifest.get("slot_id", "")),
				"session_id": String(manifest.get("session_id", "")),
				"save_revision": int(manifest.get("save_revision", 0)),
			},
			"releaseEvidence": (
				discovery.get("compatibilityEvidence", {}) as Dictionary
			).duplicate(true),
			"sessionConfig": session_config.duplicate(true),
			"worldData": world_data.duplicate(true),
			"residentIdentities": resident_identities.duplicate(true),
			"agentHydrator": agent_hydrator,
		}, publication, catalog)
		upgraded["completedByUpgrade"] = bool(upgraded.get("ok", false))
		return upgraded
	if String(compatibility.get("supportStatus", "")) != COMPATIBILITY.STATUS_CURRENT:
		return _failure("SAVE_VERSION_COMBINATION_UNKNOWN", false)
	return continue_revision(
		String(manifest.get("session_id", "")),
		int(manifest.get("save_revision", 0)),
		world_data,
		resident_identities,
		agent_hydrator,
	)


func begin_create_save_async(payload: Dictionary = {}) -> Dictionary:
	var capture_started_usec := Time.get_ticks_usec()
	var blocker := _save_blocker()
	if not blocker.is_empty():
		return _remember_async_result(_failure(blocker, false))
	if _async_save_job != null or not _async_save_capture.is_empty():
		return _failure("SESSION_SAVE_BUSY", true)
	if (
		_world == null
		or not _world.has_method("prepare_save_candidate")
		or _agent == null
		or (
			not _agent.has_method("prepare_save_candidate")
			and not (
				_agent.has_method("begin_save_capture")
				and _agent.has_method("continue_save_capture")
			)
		)
		or not _agent.has_method("create_save_store_peer")
		or not _agent.has_method("accept_published_save_context")
		or _store == null
		or not _store.has_method("create_isolated_peer")
	):
		return _remember_async_result(
			_failure("SESSION_ASYNC_SAVE_CONTRACT_INVALID", false),
		)
	var prepared := _world.prepare_save_candidate() as Dictionary
	if not bool(prepared.get("ok", false)):
		prepared["pending"] = false
		return _remember_async_result(prepared)
	var world_capture := {
		# World preparation already returns detached save data. The async job
		# treats this capture as immutable, so copying it here would only add a
		# full main-thread pause before the worker can start.
		"candidate": prepared.get("candidate", {}) as Dictionary,
		"snapshot": prepared.get("snapshot", {}) as Dictionary,
		"worldLogSnapshot": prepared.get("worldLogSnapshot", {}) as Dictionary,
	}
	var supports_incremental_capture := (
		_agent.has_method("begin_save_capture")
		and _agent.has_method("continue_save_capture")
	)
	if supports_incremental_capture:
		var capture_result := _agent.begin_save_capture() as Dictionary
		if not bool(capture_result.get("ok", false)):
			_release_live_world_candidate(prepared)
			return _remember_async_result(capture_result)
		var agent_capture := capture_result.get("capture", {}) as Dictionary
		if agent_capture.is_empty():
			_release_live_world_candidate(prepared)
			return _remember_async_result(_failure(
				"SESSION_SAVE_AGENT_CAPTURE_FAILED",
				true,
			))
		_async_save_capture = {
			"prepared": prepared,
			"worldCapture": world_capture,
			"agentCapture": agent_capture,
			"payload": payload.duplicate(true),
			"startedUsec": capture_started_usec,
		}
		return {
			"ok": true,
			"errorCode": "",
			"retryable": false,
			"pending": true,
			"capturePending": true,
		}
	var agent_capture := _agent.prepare_save_candidate() as Dictionary
	return _start_async_save_job(
		prepared,
		world_capture,
		agent_capture,
		payload,
		capture_started_usec,
	)


func poll_create_save_async() -> Dictionary:
	if not _async_save_capture.is_empty():
		return _poll_async_save_capture(false)
	if _async_save_job == null:
		if not _async_save_completion.is_empty():
			var completed := _async_save_completion.duplicate(true)
			_async_save_completion.clear()
			return completed
		return {"ok": true, "pending": false, "idle": true}
	var result := _complete_async_save_job(false)
	if not bool(result.get("pending", false)):
		_async_save_completion.clear()
	return result


func finish_create_save_async() -> Dictionary:
	if not _async_save_capture.is_empty():
		var captured := _poll_async_save_capture(true)
		if not bool(captured.get("pending", false)):
			return captured
	if _async_save_job == null:
		return poll_create_save_async()
	return _complete_async_save_job(true)


func has_active_create_save_async() -> bool:
	return _async_save_job != null or not _async_save_capture.is_empty()


func continue_latest(
	world_data: Dictionary,
	resident_identities: Array,
	agent_hydrator: Object,
) -> Dictionary:
	if not _configuration_error.is_empty() or _coordinator == null:
		_last_result = _failure(SERVICE_NOT_CONFIGURED, false)
		return _last_result.duplicate(true)
	if not _formal_world_ready():
		_last_result = _failure(FORMAL_WORLD_REQUIRED, false)
		return _last_result.duplicate(true)
	var slot_id := _session_slot_id()
	if slot_id.is_empty():
		_last_result = _failure("SESSION_SAVE_CONTEXT_INVALID", false)
		return _last_result.duplicate(true)
	var result := _coordinator.call(
		"restore_latest",
		slot_id,
		world_data.duplicate(true),
		resident_identities.duplicate(true),
		agent_hydrator,
	) as Dictionary
	_last_result = result.duplicate(true)
	return result


func continue_revision(
	session_id: String,
	save_revision: int,
	world_data: Dictionary,
	resident_identities: Array,
	agent_hydrator: Object,
) -> Dictionary:
	if not _configuration_error.is_empty() or _coordinator == null:
		_last_result = _failure(SERVICE_NOT_CONFIGURED, false)
		return _last_result.duplicate(true)
	if not _formal_world_ready():
		_last_result = _failure(FORMAL_WORLD_REQUIRED, false)
		return _last_result.duplicate(true)
	var slot_id := _session_slot_id()
	var normalized_session_id := session_id.strip_edges()
	if (
		slot_id.is_empty()
		or normalized_session_id.is_empty()
		or normalized_session_id != session_id
		or save_revision <= 0
	):
		_last_result = _failure("SESSION_SAVE_CONTEXT_INVALID", false)
		return _last_result.duplicate(true)
	var result := _coordinator.call(
		"restore_revision",
		slot_id,
		normalized_session_id,
		save_revision,
		world_data.duplicate(true),
		resident_identities.duplicate(true),
		agent_hydrator,
	) as Dictionary
	_last_result = result.duplicate(true)
	return result


func _save_request(payload: Dictionary) -> Dictionary:
	var identities_value: Variant = _session_config.get("residentIdentities")
	var identities: Array = (
		(identities_value as Array).duplicate(true)
		if identities_value is Array
		else []
	)
	return {
		"slotId": _session_config.get("slotId"),
		"sessionId": _session_config.get("sessionId"),
		"residentIdentities": identities,
		"sessionConfig": _manifest_session_config(),
		"savedAt": Time.get_datetime_string_from_system(false, false),
		"residentMessages": (
			(payload.get("residentMessages", []) as Array).duplicate(true)
			if payload.get("residentMessages", []) is Array
			else payload.get("residentMessages")
		),
	}


func _poll_async_save_capture(wait_for_completion: bool) -> Dictionary:
	if _async_save_capture.is_empty():
		return {"ok": true, "pending": false, "idle": true}
	var capture_state := _async_save_capture
	var agent_capture := capture_state.get("agentCapture", {}) as Dictionary
	var resident_limit := ASYNC_SAVE_RESIDENTS_PER_FRAME
	if wait_for_completion:
		resident_limit = maxi(
			1,
			(agent_capture.get("residentIds", []) as Array).size(),
		)
	var step := _agent.continue_save_capture(
		agent_capture,
		resident_limit,
	) as Dictionary
	if not bool(step.get("ok", false)):
		var prepared_for_release := capture_state.get(
			"prepared",
			{},
		) as Dictionary
		_async_save_capture.clear()
		var released := _release_live_world_candidate(
			prepared_for_release,
		)
		var failure := step
		if not bool(released.get("ok", false)):
			failure = released
		return _remember_async_result(failure)
	var next_agent_capture := step.get("capture", {}) as Dictionary
	if bool(step.get("pending", false)):
		capture_state["agentCapture"] = next_agent_capture
		_async_save_capture = capture_state
		return {
			"ok": true,
			"errorCode": "",
			"retryable": false,
			"pending": true,
			"capturePending": true,
			"residentCaptureIndex": int(
				next_agent_capture.get("nextIndex", 0),
			),
			"residentCaptureTotal": (
				(next_agent_capture.get("residentIds", []) as Array).size()
			),
		}
	var prepared := capture_state.get("prepared", {}) as Dictionary
	var world_capture := capture_state.get("worldCapture", {}) as Dictionary
	var payload := capture_state.get("payload", {}) as Dictionary
	var started_usec := int(
		capture_state.get("startedUsec", Time.get_ticks_usec())
	)
	_async_save_capture.clear()
	var completed_agent_capture := {
		"ok": true,
		"context": next_agent_capture.get("context", {}) as Dictionary,
		"residentIds": next_agent_capture.get("residentIds", []) as Array,
		"residentPayloads": next_agent_capture.get(
			"residentPayloads",
			{},
		) as Dictionary,
	}
	return _start_async_save_job(
		prepared,
		world_capture,
		completed_agent_capture,
		payload,
		started_usec,
	)


func _start_async_save_job(
	prepared: Dictionary,
	world_capture: Dictionary,
	agent_capture: Dictionary,
	payload: Dictionary,
	capture_started_usec: int,
) -> Dictionary:
	var release_result := _release_live_world_candidate(prepared)
	if not bool(release_result.get("ok", false)):
		return _remember_async_result(release_result)
	if not bool(agent_capture.get("ok", false)):
		return _remember_async_result(_failure(
			"SESSION_SAVE_AGENT_CAPTURE_FAILED",
			true,
		))
	var store_peer := _store.create_isolated_peer() as RefCounted
	var agent_store_peer := _agent.create_save_store_peer() as RefCounted
	if store_peer == null or agent_store_peer == null:
		return _remember_async_result(
			_failure("SESSION_ASYNC_SAVE_STORE_MISSING", false),
		)
	var job: RefCounted = ASYNC_SAVE_JOB.new()
	_async_save_previous_agent_context = (
		agent_capture.get("context", {}) as Dictionary
	).duplicate(true)
	var started := job.start(
		store_peer,
		world_capture,
		agent_capture,
		agent_store_peer,
		_save_request(payload),
	) as Dictionary
	if not bool(started.get("ok", false)):
		_async_save_previous_agent_context.clear()
		return _remember_async_result(started)
	_async_save_capture_msec = (
		float(Time.get_ticks_usec() - capture_started_usec) / 1000.0
	)
	_async_save_job = job
	return started


func _release_live_world_candidate(prepared: Dictionary) -> Dictionary:
	var token := String(
		(prepared.get("candidate", {}) as Dictionary).get("token", ""),
	)
	if token.is_empty():
		return _failure("SESSION_SAVE_WORLD_PREPARE_FAILED", false)
	var aborted := _world.abort_save_candidate(token) as Dictionary
	if not bool(aborted.get("ok", false)):
		return _failure("SESSION_SAVE_WORLD_CLEANUP_FAILED", false)
	var cleaned := _world.cleanup_save_candidate(token) as Dictionary
	if not bool(cleaned.get("ok", false)):
		return _failure("SESSION_SAVE_WORLD_CLEANUP_FAILED", false)
	return {"ok": true, "errorCode": "", "retryable": false}


func _complete_async_save_job(wait_for_completion: bool) -> Dictionary:
	if _async_save_job == null:
		return {"ok": true, "pending": false, "idle": true}
	var result := (
		_async_save_job.finish()
		if wait_for_completion
		else _async_save_job.poll()
	) as Dictionary
	if bool(result.get("pending", false)):
		return result
	_async_save_job = null
	if bool(result.get("ok", false)):
		var accepted := _agent.accept_published_save_context(
			result.get("context", {}),
			_async_save_previous_agent_context,
		) as Dictionary
		if not bool(accepted.get("ok", false)):
			var context_failure := _failure(
				"SESSION_SAVE_AGENT_CONTEXT_COMMIT_FAILED",
				false,
			)
			context_failure["meta"] = {
				"published": true,
				"publishedContext": (
					result.get("context", {}) as Dictionary
				).duplicate(true),
			}
			result = context_failure
	_async_save_previous_agent_context.clear()
	var timing := (result.get("timing", {}) as Dictionary).duplicate(true)
	timing["captureMsec"] = _async_save_capture_msec
	result["timing"] = timing
	_async_save_capture_msec = 0.0
	result["pending"] = false
	_async_save_completion = result.duplicate(true)
	_last_result = result.duplicate(true)
	return result


func _remember_async_result(result: Dictionary) -> Dictionary:
	var remembered := result.duplicate(true)
	remembered["pending"] = false
	_last_result = remembered.duplicate(true)
	return remembered


func _save_blocker() -> String:
	if not _configuration_error.is_empty():
		return String(
			_configuration_error.get("errorCode", SERVICE_NOT_CONFIGURED),
		)
	if _coordinator == null:
		return SERVICE_NOT_CONFIGURED
	if not _formal_world_ready():
		return FORMAL_WORLD_REQUIRED
	if _session_slot_id().is_empty() or _session_id().is_empty():
		return "SESSION_SAVE_CONTEXT_INVALID"
	if (
		_runtime == null
		or not is_instance_valid(_runtime)
		or not _runtime.has_method("get_resident_identity_snapshot")
	):
		return "SESSION_SAVE_IDENTITY_NOT_CONFIRMED"
	var snapshot_value: Variant = _runtime.call(
		"get_resident_identity_snapshot",
	)
	var snapshot_status_value: Variant = (
		(snapshot_value as Dictionary).get("status")
		if snapshot_value is Dictionary
		else null
	)
	if (
		not snapshot_value is Dictionary
		or not snapshot_status_value is String
		or snapshot_status_value != "confirmed"
		or not _identity_snapshot_matches(
			snapshot_value as Dictionary,
			_session_config.get("residentIdentities"),
		)
	):
		return "SESSION_SAVE_IDENTITY_NOT_CONFIRMED"
	if _agent == null or not is_instance_valid(_agent):
		return "SESSION_SAVE_AGENT_CONTEXT_MISMATCH"
	var context_value: Variant = _agent.call("get_save_context")
	if not context_value is Dictionary:
		return "SESSION_SAVE_AGENT_CONTEXT_MISMATCH"
	var context := context_value as Dictionary
	if MANIFEST.validate_context(context).get("ok") != true:
		return "SESSION_SAVE_AGENT_CONTEXT_MISMATCH"
	if (
		context.get("slot_id") != _session_config.get("slotId")
		or context.get("session_id") != _session_config.get("sessionId")
	):
		return "SESSION_SAVE_AGENT_CONTEXT_MISMATCH"
	return ""


func _manifest_session_config() -> Dictionary:
	var filtered := {
		"saveRelease": COMPATIBILITY.current_release(),
	}
	for field_name in [
		"mode",
		"sessionId",
		"openingConfig",
		"residentIdentities",
		"connectedResidents",
		"worldStartMode",
		"useLiveModel",
		"enablePlayerAvatar",
		"enableTestUi",
	]:
		if _session_config.has(field_name):
			filtered[field_name] = _duplicate_value(
				_session_config.get(field_name),
			)
	if _session_config.has("residentBindings"):
		# The runtime binding also carries presentation-only residentName. A save
		# only needs the stable Agent routing identity; rebuild the allow-listed
		# shape here so no future runtime/provider metadata can leak into a
		# published session config.
		var bindings_value: Variant = _session_config.get("residentBindings")
		if not bindings_value is Array:
			filtered["residentBindings"] = _duplicate_value(bindings_value)
		else:
			var saved_bindings: Array = []
			for value: Variant in bindings_value as Array:
				if not value is Dictionary:
					saved_bindings.append(_duplicate_value(value))
					continue
				var binding := value as Dictionary
				var llm_value: Variant = binding.get("llmBinding")
				var saved_binding := {
					"residentId": binding.get("residentId"),
					"llmBinding": _duplicate_value(llm_value),
				}
				if llm_value is Dictionary:
					var llm := llm_value as Dictionary
					saved_binding["llmBinding"] = {
						"mode": llm.get("mode"),
						"providerId": llm.get("providerId"),
						"modelId": llm.get("modelId"),
					}
				saved_bindings.append(saved_binding)
			filtered["residentBindings"] = saved_bindings
	return filtered


func _formal_world_ready() -> bool:
	return (
		_session_config.get("worldStartMode") is String
		and _session_config.get("worldStartMode") == "formal"
		and _session_config.get("capabilityMode") is String
		and _session_config.get("capabilityMode") == "formal"
		and _session_config.get("formalReady") is bool
		and _session_config.get("formalReady") == true
	)


func _session_slot_id() -> String:
	var value: Variant = _session_config.get("slotId")
	if not value is String:
		return ""
	var slot_id := value as String
	return slot_id if slot_id == slot_id.strip_edges() else ""


func _session_id() -> String:
	var value: Variant = _session_config.get("sessionId")
	if not value is String:
		return ""
	var session_id := value as String
	return session_id if session_id == session_id.strip_edges() else ""


func _duplicate_value(value: Variant) -> Variant:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	if value is Array:
		return (value as Array).duplicate(true)
	return value


func _identity_snapshot_matches(
	snapshot: Dictionary,
	expected_identities: Variant,
) -> bool:
	var expected_result := MANIFEST.resident_ids(expected_identities)
	if expected_result.get("ok") != true:
		return false
	var residents_value: Variant = snapshot.get("residents")
	if not residents_value is Array:
		return false
	var actual_ids: Array[String] = []
	for resident_value: Variant in residents_value as Array:
		if not resident_value is Dictionary:
			return false
		var resident_id_value: Variant = (
			resident_value as Dictionary
		).get("residentId")
		if not resident_id_value is String:
			return false
		var resident_id := resident_id_value as String
		if (
			resident_id.is_empty()
			or resident_id != resident_id.strip_edges()
			or actual_ids.has(resident_id)
		):
			return false
		actual_ids.append(resident_id)
	actual_ids.sort()
	return actual_ids == (
		expected_result.get("residentIds", []) as Array
	)


func _remember_configuration_failure(error_code: String) -> Dictionary:
	return _remember_configuration_result(_failure(error_code, false))


func _remember_configuration_result(result: Dictionary) -> Dictionary:
	_configuration_error = result.duplicate(true)
	_last_result = result.duplicate(true)
	return result


func _failure(error_code: String, retryable: bool) -> Dictionary:
	return RESULT_SHAPES.failure_retryable(error_code, retryable)
