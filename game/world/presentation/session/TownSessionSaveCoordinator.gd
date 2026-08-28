class_name TownSessionSaveCoordinator
extends RefCounted


const MANIFEST := preload(
	"res://world/presentation/session/TownSessionSaveManifest.gd"
)
const COMPATIBILITY := preload(
	"res://world/presentation/session/TownSaveCompatibilityRegistry.gd"
)
const STORE_METHODS: Array[String] = [
	"begin_slot_transaction",
	"end_slot_transaction",
	"reserve_revision",
	"write_world_candidate",
	"begin_intent",
	"write_intent_stage",
	"publish_manifest",
	"list_published",
	"read_reference",
	"list_incomplete",
]
const WORLD_METHODS: Array[String] = [
	"prepare_save_candidate",
	"validate_save_candidate",
	"commit_save_candidate",
	"abort_save_candidate",
	"cleanup_save_candidate",
	"prepare_restore_candidate",
	"validate_restore_candidate",
	"commit_restore_candidate",
	"abort_restore_candidate",
	"cleanup_restore_candidate",
]
const AGENT_METHODS: Array[String] = [
	"save_game",
	"restore_game",
	"finish_restore",
	"cancel_restore",
	"get_save_context",
	"get_active_resident_ids",
]
const GATE_METHODS: Array[String] = [
	"begin_session_transaction",
	"validate_session_transaction",
	"end_session_transaction",
]
const HYDRATOR_METHOD := "hydrate_agent_restore"
const SAVE_JOURNAL_STATES: Array[String] = TownSaveJournalStates.SAVE_STAGES
const RESTORE_JOURNAL_STATES: Array[String] = TownSaveJournalStates.RESTORE_STAGES
const SAVE_FAILURE_STAGES: Array[String] = TownSaveJournalStates.SAVE_TRANSACTION_FAILED_STAGES
const RESTORE_FAILURE_STAGES: Array[String] = TownSaveJournalStates.RESTORE_TRANSACTION_FAILED_STAGES
const SESSION_CONFIG_FIELDS: Array[String] = [
	"mode",
	"sessionId",
	"saveRelease",
	"openingConfig",
	"residentIdentities",
	"residentBindings",
	"connectedResidents",
	"worldStartMode",
	"useLiveModel",
	"enablePlayerAvatar",
	"enableTestUi",
]

var _store: Object
var _world: Object
var _agent: Object
var _gate: Object
var _busy := false
var _generation := 1
var _active_intent_id := ""
var _active_slot_lease: Dictionary = {}
var _allow_development_world := false


func configure(
	store: Object,
	world: Object,
	agent: Object,
	transaction_gate: Object,
	options: Dictionary = {},
) -> Dictionary:
	if _busy:
		return _failure("SESSION_SAVE_BUSY", true)
	var errors: Array[Dictionary] = []
	errors.append_array(_contract_errors("store", store, STORE_METHODS))
	errors.append_array(_contract_errors("world", world, WORLD_METHODS))
	errors.append_array(_contract_errors("agent", agent, AGENT_METHODS))
	errors.append_array(_contract_errors(
		"transactionGate",
		transaction_gate,
		GATE_METHODS,
	))
	if not errors.is_empty():
		return _failure("SESSION_SAVE_CONTRACT_INVALID", false, errors)
	_store = store
	_world = world
	_agent = agent
	_gate = transaction_gate
	_allow_development_world = bool(
		options.get("allowDevelopmentWorld", false),
	)
	return _success()


func get_generation() -> int:
	return _generation


func accepts_generation(value: int) -> bool:
	return value == _generation


func save(request: Dictionary) -> Dictionary:
	if _busy:
		return _failure("SESSION_SAVE_BUSY", true)
	var configured := _require_configured()
	if configured.get("ok") != true:
		return configured
	var base := _base_request(request)
	if base.get("ok") != true:
		return base
	_busy = true
	var slot_lease := _begin_slot_transaction(
		String(base.get("slotId", "")),
	)
	if slot_lease.get("ok") != true:
		return _finish(slot_lease)
	var active_context := _call_dictionary(
		_agent,
		"get_save_context",
	)
	if (
		MANIFEST.validate_context(active_context).get("ok") != true
		or
		String(active_context.get("slot_id", "")) != String(base.get("slotId", ""))
		or String(active_context.get("session_id", "")) != String(base.get("sessionId", ""))
	):
		return _finish(
			_failure("SESSION_SAVE_AGENT_CONTEXT_MISMATCH", false),
		)
	var active_residents := _call_dictionary(
		_agent,
		"get_active_resident_ids",
	)
	if active_residents.get("ok") != true:
		return _finish(_participant_failure(
			"SESSION_SAVE_AGENT_IDENTITY_MISMATCH",
			active_residents,
			false,
		))
	var agent_resident_validation := _validate_resident_ids(
		active_residents.get("resident_ids"),
		base.get("residentIds", []) as Array,
		"SESSION_SAVE_AGENT_IDENTITY_MISMATCH",
	)
	if agent_resident_validation.get("ok") != true:
		return _finish(agent_resident_validation)
	var reconciliation := inspect_incomplete(String(base.get("slotId", "")))
	if reconciliation.get("ok") != true:
		return _finish(reconciliation)
	var blockers: Array[Dictionary] = []
	for item_value: Variant in reconciliation.get("items", []) as Array:
		var item := item_value as Dictionary
		if String(item.get("classification", "")) in [
			"agent_commit_uncertain",
			"agent_orphan_isolated",
		]:
			blockers.append({
				"context": (
					item.get("context", {}) as Dictionary
				).duplicate(true),
				"errorCode": String(item.get("errorCode", "")),
			})
	if not blockers.is_empty():
		return _finish(_failure(
			"SESSION_SAVE_RECONCILE_REQUIRED",
			false,
			[],
			{"blockers": blockers},
		))
	var reserved := _call_dictionary(_store, "reserve_revision", [
		String(base.get("slotId", "")),
		String(base.get("sessionId", "")),
	])
	if reserved.get("ok") != true:
		return _finish(_normalize_store_failure(reserved))
	var reserved_context_value: Variant = reserved.get("context")
	if not reserved_context_value is Dictionary:
		return _finish(
			_failure("SESSION_SAVE_STORE_RESPONSE_INVALID", false),
		)
	var context := reserved_context_value as Dictionary
	var context_check := MANIFEST.validate_context(context)
	if (
		context_check.get("ok") != true
		or String(context.get("slot_id", ""))
		!= String(base.get("slotId", ""))
		or String(context.get("session_id", ""))
		!= String(base.get("sessionId", ""))
		or int(context.get("save_revision", 0)) <= 0
	):
		return _finish(
			_failure("SESSION_SAVE_STORE_RESPONSE_INVALID", false),
		)
	var intent := _call_dictionary(_store, "begin_intent", [
		context.duplicate(true),
		"save",
	])
	if intent.get("ok") != true:
		return _finish(_normalize_store_failure(intent))
	var intent_id_value: Variant = intent.get("intentId")
	if not intent_id_value is String:
		return _finish(_failure("SESSION_SAVE_STORE_RESPONSE_INVALID", false))
	_active_intent_id = intent_id_value as String
	if _active_intent_id.is_empty():
		return _finish(_failure("SESSION_SAVE_STORE_RESPONSE_INVALID", false))
	var started_journal := _journal(
		context,
		"save",
		"save_started",
		{"sourceGeneration": _generation},
	)
	if started_journal.get("ok") != true:
		return _finish(started_journal)
	var gate_result := _call_dictionary(
		_gate,
		"begin_session_transaction",
		["save", context.duplicate(true)],
	)
	if gate_result.get("ok") != true:
		_journal(context, "save", "transaction_failed", {
			"stage": "gate_begin",
		})
		return _finish(_participant_failure(
			"SESSION_SAVE_GATE_FAILED",
			gate_result,
			false,
		))
	var gate_token_value: Variant = gate_result.get("token")
	if not gate_token_value is String or (gate_token_value as String).is_empty():
		return _finish(_failure(
			"SESSION_SAVE_GATE_FAILED",
			false,
			[],
			{"releaseImpossible": true},
		))
	var gate_token := gate_token_value as String

	var prepared := _call_dictionary(
		_world,
		"prepare_save_candidate",
	)
	if prepared.get("ok") != true:
		_journal(context, "save", "transaction_failed", {
			"stage": "world_prepare",
			"errorCode": String(prepared.get("errorCode", "")),
			"errors": _array_copy(prepared.get("errors")),
		})
		return _finish_with_gate(
			_participant_failure(
				"SESSION_SAVE_WORLD_PREPARE_FAILED",
				prepared,
				bool(prepared.get("retryable", false)),
			),
			gate_token,
		)
	var candidate_value: Variant = prepared.get("candidate")
	var snapshot_value: Variant = prepared.get("snapshot")
	var world_log_snapshot_value: Variant = prepared.get("worldLogSnapshot")
	var has_world_log := (
		world_log_snapshot_value is Dictionary
		and not (world_log_snapshot_value as Dictionary).is_empty()
	)
	if (
		has_world_log
		and not _method_accepts_argument_count(
			_store,
			"write_world_candidate",
			4,
		)
	):
		has_world_log = false
	if (
		not candidate_value is Dictionary
		or not snapshot_value is Dictionary
	):
		if candidate_value is Dictionary:
			var malformed_token_value: Variant = (
				candidate_value as Dictionary
			).get("token")
			if malformed_token_value is String:
				_abort_world_save(malformed_token_value as String)
		return _finish_with_gate(
			_failure("SESSION_SAVE_WORLD_PREPARE_FAILED", false),
			gate_token,
		)
	var world_candidate := candidate_value as Dictionary
	var world_token_value: Variant = world_candidate.get("token")
	var world_revision_value: Variant = world_candidate.get("worldRevision")
	var world_token := (
		world_token_value as String
		if world_token_value is String
		else ""
	)
	if (
		world_token.is_empty()
		or not _is_positive_integer_number(world_revision_value)
	):
		_abort_world_save(world_token)
		return _finish_with_gate(
			_failure("SESSION_SAVE_WORLD_PREPARE_FAILED", false),
			gate_token,
		)
	var world_resident_validation := _validate_world_resident_ids(
		world_candidate.get("residentIds"),
		base.get("residentIds", []) as Array,
	)
	if world_resident_validation.get("ok") != true:
		_abort_world_save(world_token)
		return _finish_with_gate(world_resident_validation, gate_token)
	var store_arguments: Array = [
		context.duplicate(true),
		(snapshot_value as Dictionary).duplicate(true),
		(base.get("sessionConfig", {}) as Dictionary).duplicate(true),
	]
	if has_world_log:
		store_arguments.append(
			(world_log_snapshot_value as Dictionary).duplicate(true),
		)
	var stored := _call_dictionary(
		_store,
		"write_world_candidate",
		store_arguments,
	)
	if stored.get("ok") != true:
		_journal(context, "save", "transaction_failed", {
			"stage": "world_candidate_write",
		})
		_abort_world_save(world_token)
		return _finish_with_gate(_normalize_store_failure(stored), gate_token)
	var stored_validation := _validate_stored_candidate(
		context,
		stored,
		has_world_log,
	)
	if stored_validation.get("ok") != true:
		_journal(context, "save", "transaction_failed", {
			"stage": "world_candidate_write",
		})
		_abort_world_save(world_token)
		return _finish_with_gate(stored_validation, gate_token)
	var snapshot_ref := String(stored.get("snapshotRef", ""))
	var candidate_payload := {
		"sourceGeneration": _generation,
		"gateToken": gate_token,
		"worldToken": world_token,
		"worldRevision": int(world_revision_value),
		"snapshotRef": snapshot_ref,
		"snapshotSha256": String(stored.get("snapshotSha256", "")),
		"worldLogSnapshotRef": String(
			stored.get("worldLogSnapshotRef", ""),
		),
		"worldLogSnapshotSha256": String(
			stored.get("worldLogSnapshotSha256", ""),
		),
		"sessionConfigRef": String(stored.get("sessionConfigRef", "")),
		"sessionConfigSha256": String(stored.get("sessionConfigSha256", "")),
	}
	var candidate_journal := _journal(
		context,
		"save",
		"world_candidate_written",
		candidate_payload,
	)
	if candidate_journal.get("ok") != true:
		_abort_world_save(world_token)
		return _finish_with_gate(candidate_journal, gate_token)
	var world_validation := _call_dictionary(
		_world,
		"validate_save_candidate",
		[world_token],
	)
	if world_validation.get("ok") != true:
		_journal(context, "save", "transaction_failed", {
			"stage": "world_validate",
		})
		_abort_world_save(world_token)
		return _finish_with_gate(
			_participant_failure(
				"SESSION_SAVE_WORLD_PREPARE_FAILED",
				world_validation,
				bool(world_validation.get("retryable", false)),
			),
			gate_token,
		)
	var gate_validation := _call_dictionary(
		_gate,
		"validate_session_transaction",
		[gate_token],
	)
	if gate_validation.get("ok") != true:
		_journal(context, "save", "transaction_failed", {
			"stage": "gate_validate",
		})
		_abort_world_save(world_token)
		return _finish_with_gate(
			_participant_failure(
				"SESSION_SAVE_GATE_FAILED",
				gate_validation,
				false,
			),
			gate_token,
		)
	var before_agent := _journal(
		context,
		"save",
		"agent_commit_started",
		candidate_payload,
	)
	if before_agent.get("ok") != true:
		_abort_world_save(world_token)
		return _finish_with_gate(before_agent, gate_token)

	var agent_result := _call_dictionary(
		_agent,
		"save_game",
		[context.duplicate(true)],
	)
	var agent_save_ok_value: Variant = agent_result.get("ok")
	var agent_save_context_value: Variant = agent_result.get("context")
	var observed_agent_context := _call_dictionary(
		_agent,
		"get_save_context",
	)
	var observed_agent_commit := observed_agent_context == context
	var response_context_invalid := (
		agent_result.has("context")
		and (
			not agent_save_context_value is Dictionary
			or (agent_save_context_value as Dictionary) != context
		)
	)
	var agent_save_uncertain: bool = (
		String(agent_result.get("errorCode", ""))
		== "SESSION_SAVE_PARTICIPANT_RESPONSE_INVALID"
		or not agent_save_ok_value is bool
		or response_context_invalid
		or (agent_save_ok_value == true and not observed_agent_commit)
		or (agent_save_ok_value == false and observed_agent_commit)
	)
	if agent_save_uncertain:
		_journal(context, "save", "agent_commit_uncertain", {
			"worldToken": world_token,
		})
		_abort_world_save(world_token)
		return _finish_with_gate(
			_failure("SESSION_SAVE_AGENT_COMMIT_UNCERTAIN", false),
			gate_token,
		)
	if agent_save_ok_value != true:
		_journal(context, "save", "agent_commit_failed", {
			"worldToken": world_token,
		})
		_abort_world_save(world_token)
		return _finish_with_gate(
			_failure("SESSION_SAVE_AGENT_COMMIT_FAILED", false),
			gate_token,
		)
	var agent_journal := _journal(
		context,
		"save",
		"agent_committed",
		candidate_payload,
	)
	if agent_journal.get("ok") != true:
		return _save_orphan_failure(
			context,
			world_token,
			gate_token,
			"journal_agent_committed",
		)
	var world_commit_arguments: Array = [world_token, snapshot_ref]
	if has_world_log:
		world_commit_arguments.append(
			String(stored.get("worldLogSnapshotRef", "")),
		)
	var world_commit := _call_dictionary(
		_world,
		"commit_save_candidate",
		world_commit_arguments,
	)
	if world_commit.get("ok") != true:
		return _save_orphan_failure(
			context,
			world_token,
			gate_token,
			"world_commit",
		)
	var world_component_value: Variant = world_commit.get("worldComponent")
	if not world_component_value is Dictionary:
		return _save_orphan_failure(
			context,
			world_token,
			gate_token,
			"world_commit_response",
		)
	var world_component := world_component_value as Dictionary
	var world_log_component: Dictionary = {}
	var world_log_component_value: Variant = world_commit.get("worldLogComponent")
	if has_world_log and not world_log_component_value is Dictionary:
		return _save_orphan_failure(
			context,
			world_token,
			gate_token,
			"world_log_commit_response",
		)
	if has_world_log:
		world_log_component = (
			world_log_component_value as Dictionary
		).duplicate(true)
		world_log_component["snapshotSha256"] = String(
			stored.get("worldLogSnapshotSha256", ""),
		)
	var world_journal := _journal(
		context,
		"save",
		"world_committed",
		candidate_payload,
	)
	if world_journal.get("ok") != true:
		return _save_orphan_failure(
			context,
			world_token,
			gate_token,
			"journal_world_committed",
		)
	var manifest := MANIFEST.build(
		context,
		String(base.get("savedAt", "")),
		String(stored.get("sessionConfigRef", "")),
		String(stored.get("sessionConfigSha256", "")),
		base.get("residentIds", []) as Array,
		world_component,
		String(stored.get("snapshotSha256", "")),
		base.get("residentMessages", []) as Array,
		world_log_component,
	) as Dictionary
	if manifest.is_empty():
		return _save_orphan_failure(
			context,
			world_token,
			gate_token,
			"manifest_build",
		)
	var published := _call_dictionary(
		_store,
		"publish_manifest",
		[manifest],
	)
	if published.get("ok") != true:
		return _save_orphan_failure(
			context,
			world_token,
			gate_token,
			"manifest_publish",
		)
	var published_journal := _journal(context, "save", "manifest_published", {
		"worldToken": world_token,
	})
	var cleanup_result := _call_dictionary(
		_world,
		"cleanup_save_candidate",
		[world_token],
	)
	var completed := {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"context": context.duplicate(true),
		"manifest": manifest.duplicate(true),
		"summary": MANIFEST.summary(manifest),
		"generation": _generation,
	}
	if published_journal.get("ok") != true:
		completed = _failure(
			"SESSION_SAVE_JOURNAL_INCOMPLETE",
			false,
			[],
			{"published": true},
		)
	elif cleanup_result.get("ok") != true:
		completed = _failure(
			"SESSION_SAVE_WORLD_CLEANUP_FAILED",
			false,
			[],
			{"published": true},
		)
	return _finish_with_gate(completed, gate_token)


func discover_latest(slot_id: String) -> Dictionary:
	var configured := _require_configured()
	if configured.get("ok") != true:
		return configured
	var listed := _call_dictionary(
		_store,
		"list_published",
		[slot_id],
	)
	if listed.get("ok") != true:
		return _normalize_store_failure(listed)
	var manifests_value: Variant = listed.get("manifests")
	if not manifests_value is Array:
		return _failure("SESSION_SAVE_PARTICIPANT_RESPONSE_INVALID", false)
	var manifests := manifests_value as Array
	if manifests.is_empty():
		return _failure("SESSION_SAVE_NO_PUBLISHED_REVISION", false)
	if not manifests[0] is Dictionary:
		return _failure("SESSION_SAVE_PARTICIPANT_RESPONSE_INVALID", false)
	var manifest := manifests[0] as Dictionary
	if MANIFEST.validate(manifest).get("ok") != true:
		return _failure("SESSION_SAVE_MANIFEST_INVALID", false)
	var invalid_value: Variant = listed.get("invalid", [])
	if not invalid_value is Array:
		return _failure("SESSION_SAVE_PARTICIPANT_RESPONSE_INVALID", false)
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"manifest": manifest.duplicate(true),
		"summary": MANIFEST.summary(manifest),
		"invalid": (invalid_value as Array).duplicate(true),
	}


func discover_revision(
	slot_id: String,
	session_id: String,
	save_revision: int,
) -> Dictionary:
	var configured := _require_configured()
	if configured.get("ok") != true:
		return configured
	var context_check := MANIFEST.validate_context({
		"slot_id": slot_id,
		"session_id": session_id,
		"save_revision": save_revision,
	}) as Dictionary
	if context_check.get("ok") != true or save_revision <= 0:
		return _failure("SESSION_SAVE_CONTEXT_INVALID", false)
	var listed := _call_dictionary(
		_store,
		"list_published",
		[slot_id],
	)
	if listed.get("ok") != true:
		return _normalize_store_failure(listed)
	var manifests_value: Variant = listed.get("manifests")
	var invalid_value: Variant = listed.get("invalid", [])
	if not manifests_value is Array or not invalid_value is Array:
		return _failure("SESSION_SAVE_PARTICIPANT_RESPONSE_INVALID", false)
	for manifest_value: Variant in manifests_value as Array:
		if not manifest_value is Dictionary:
			return _failure("SESSION_SAVE_PARTICIPANT_RESPONSE_INVALID", false)
		var manifest := manifest_value as Dictionary
		if MANIFEST.validate(manifest).get("ok") != true:
			continue
		if (
			String(manifest.get("session_id", "")) == session_id
			and int(manifest.get("save_revision", 0)) == save_revision
		):
			return {
				"ok": true,
				"errorCode": "",
				"retryable": false,
				"manifest": manifest.duplicate(true),
				"summary": MANIFEST.summary(manifest),
				"invalid": (invalid_value as Array).duplicate(true),
			}
	return _failure("SESSION_SAVE_REVISION_NOT_FOUND", false)


func restore_latest(
	slot_id: String,
	world_data: Dictionary,
	resident_identities: Array,
	agent_hydrator: Object,
) -> Dictionary:
	return _restore_selected(
		slot_id,
		world_data,
		resident_identities,
		agent_hydrator,
		"",
		-1,
	)


func restore_revision(
	slot_id: String,
	session_id: String,
	save_revision: int,
	world_data: Dictionary,
	resident_identities: Array,
	agent_hydrator: Object,
) -> Dictionary:
	return _restore_selected(
		slot_id,
		world_data,
		resident_identities,
		agent_hydrator,
		session_id,
		save_revision,
	)


func _restore_selected(
	slot_id: String,
	world_data: Dictionary,
	resident_identities: Array,
	agent_hydrator: Object,
	requested_session_id: String,
	requested_revision: int,
) -> Dictionary:
	if _busy:
		return _failure("SESSION_SAVE_BUSY", true)
	var configured := _require_configured()
	if configured.get("ok") != true:
		return configured
	if (
		agent_hydrator == null
		or not agent_hydrator.has_method(HYDRATOR_METHOD)
	):
		return _failure("SESSION_CONTINUE_HYDRATOR_MISSING", false)
	_busy = true
	var slot_lease := _begin_slot_transaction(slot_id)
	if slot_lease.get("ok") != true:
		return _finish(slot_lease)
	var discovered := (
		discover_latest(slot_id)
		if requested_revision <= 0
		else discover_revision(
			slot_id,
			requested_session_id,
			requested_revision,
		)
	)
	if discovered.get("ok") != true:
		return _finish(discovered)
	var manifest := discovered.get("manifest", {}) as Dictionary
	var context := {
		"slot_id": manifest.get("slot_id"),
		"session_id": manifest.get("session_id"),
		"save_revision": int(manifest.get("save_revision", 0)),
	}
	var incomplete_state := inspect_incomplete(slot_id)
	if incomplete_state.get("ok") != true:
		return _finish(incomplete_state)
	var restore_blockers: Array[Dictionary] = []
	for item_value: Variant in incomplete_state.get("items", []) as Array:
		var item := item_value as Dictionary
		var item_context := item.get("context", {}) as Dictionary
		if (
			String(item.get("kind", "")) == "restore"
			and item_context == context
			and String(item.get("classification", "")) in [
				"restore_agent_uncertain",
				"restore_partial_commit",
			]
		):
			restore_blockers.append({
				"context": item_context.duplicate(true),
				"errorCode": String(item.get("errorCode", "")),
			})
	if not restore_blockers.is_empty():
		return _finish(_failure(
			"SESSION_CONTINUE_RECONCILE_REQUIRED",
			false,
			[],
			{"blockers": restore_blockers},
		))
	var resident_result := MANIFEST.resident_ids(resident_identities)
	if (
		resident_result.get("ok") != true
		or (resident_result.get("residentIds", []) as Array)
		!= (manifest.get("resident_ids", []) as Array)
	):
		return _finish(
			_failure("SESSION_CONTINUE_IDENTITY_MISMATCH", false),
		)
	var components := manifest.get("components", {}) as Dictionary
	var world_component := components.get("world", {}) as Dictionary
	var snapshot_loaded := _call_dictionary(_store, "read_reference", [
		String(world_component.get("snapshot_ref", "")),
		String(world_component.get("snapshot_sha256", "")),
	])
	if snapshot_loaded.get("ok") != true:
		return _finish(_normalize_store_failure(snapshot_loaded))
	var world_log_snapshot: Dictionary = {}
	var world_log_component_value: Variant = components.get("world_log")
	if world_log_component_value is Dictionary:
		var world_log_component := world_log_component_value as Dictionary
		var world_log_read_method := (
			"read_world_log_snapshot"
			if _store.has_method("read_world_log_snapshot")
			else "read_reference"
		)
		var world_log_loaded := _call_dictionary(_store, world_log_read_method, [
			String(world_log_component.get("snapshot_ref", "")),
			String(world_log_component.get("snapshot_sha256", "")),
		])
		if world_log_loaded.get("ok") != true:
			return _finish(_normalize_store_failure(world_log_loaded))
		var loaded_world_log_value: Variant = world_log_loaded.get("value")
		if not loaded_world_log_value is Dictionary:
			return _finish(
				_failure("SESSION_SAVE_PARTICIPANT_RESPONSE_INVALID", false),
			)
		world_log_snapshot = (
			loaded_world_log_value as Dictionary
		).duplicate(true)
	var config_loaded := _call_dictionary(_store, "read_reference", [
		String(manifest.get("session_config_ref", "")),
		String(manifest.get("session_config_sha256", "")),
	])
	if config_loaded.get("ok") != true:
		return _finish(_normalize_store_failure(config_loaded))
	var session_config_value: Variant = config_loaded.get("value")
	if not session_config_value is Dictionary:
		return _finish(
			_failure("SESSION_SAVE_PARTICIPANT_RESPONSE_INVALID", false),
		)
	var session_config_validation := _validate_session_config(
		session_config_value as Dictionary,
		String(context.get("session_id", "")),
		manifest.get("resident_ids", []) as Array,
	)
	if session_config_validation.get("ok") != true:
		return _finish(_failure(
			"SESSION_SAVE_MANIFEST_INVALID",
			false,
			_array_copy(session_config_validation.get("errors")),
		))
	var session_config := (
		session_config_validation.get("sessionConfig", {}) as Dictionary
	)
	var opening_config := session_config.get("openingConfig", {}) as Dictionary
	var restored_identity_contract := _restore_identity_contract(
		session_config.get("residentIdentities", []),
		resident_identities,
		manifest.get("resident_ids", []) as Array,
	)
	if restored_identity_contract.get("ok") != true:
		return _finish(restored_identity_contract)
	var intent := _call_dictionary(_store, "begin_intent", [
		context.duplicate(true),
		"restore",
	])
	if intent.get("ok") != true:
		return _finish(_normalize_store_failure(intent))
	var intent_id_value: Variant = intent.get("intentId")
	if not intent_id_value is String:
		return _finish(_failure("SESSION_SAVE_STORE_RESPONSE_INVALID", false))
	_active_intent_id = intent_id_value as String
	if _active_intent_id.is_empty():
		return _finish(_failure("SESSION_SAVE_STORE_RESPONSE_INVALID", false))
	var restore_started := _journal(context, "restore", "restore_started", {
		"sourceGeneration": _generation,
	})
	if restore_started.get("ok") != true:
		return _finish(restore_started)
	var gate_result := _call_dictionary(
		_gate,
		"begin_session_transaction",
		["restore", context.duplicate(true)],
	)
	if gate_result.get("ok") != true:
		return _finish(_participant_failure(
			"SESSION_CONTINUE_GATE_FAILED",
			gate_result,
			false,
		))
	var gate_token_value: Variant = gate_result.get("token")
	if not gate_token_value is String or (gate_token_value as String).is_empty():
		return _finish(_failure(
			"SESSION_CONTINUE_GATE_FAILED",
			false,
			[],
			{"releaseImpossible": true},
		))
	var gate_token := gate_token_value as String
	var snapshot_value: Variant = snapshot_loaded.get("value")
	if not snapshot_value is Dictionary:
		return _finish_with_gate(
			_failure("SESSION_SAVE_PARTICIPANT_RESPONSE_INVALID", false),
			gate_token,
		)
	var world_prepare_arguments: Array = [
		world_data,
		opening_config,
		snapshot_value as Dictionary,
		resident_identities.duplicate(true),
		true,
	]
	if not world_log_snapshot.is_empty():
		world_prepare_arguments.append(world_log_snapshot)
	var world_prepare := _call_dictionary(
		_world,
		"prepare_restore_candidate",
		world_prepare_arguments,
	)
	if world_prepare.get("ok") != true:
		_journal(context, "restore", "transaction_failed", {
			"stage": "world_prepare",
			"errorCode": String(world_prepare.get("errorCode", "")),
			"errors": _array_copy(world_prepare.get("errors")),
		})
		return _finish_with_gate(
			_participant_failure(
				"SESSION_CONTINUE_WORLD_PREPARE_FAILED",
				world_prepare,
				bool(world_prepare.get("retryable", false)),
			),
			gate_token,
		)
	var restore_candidate_value: Variant = world_prepare.get("candidate")
	if not restore_candidate_value is Dictionary:
		return _finish_with_gate(
			_failure("SESSION_CONTINUE_WORLD_PREPARE_FAILED", false),
			gate_token,
		)
	var world_token_value: Variant = (
		restore_candidate_value as Dictionary
	).get("token")
	var world_token := (
		world_token_value as String
		if world_token_value is String
		else ""
	)
	if world_token.is_empty():
		return _finish_with_gate(
			_failure("SESSION_CONTINUE_WORLD_PREPARE_FAILED", false),
			gate_token,
		)
	var world_prepared_journal := _journal(
		context,
		"restore",
		"restore_world_prepared",
		{
			"worldToken": world_token,
		},
	)
	if world_prepared_journal.get("ok") != true:
		_abort_world_restore(world_token)
		return _finish_with_gate(world_prepared_journal, gate_token)
	var agent_context_before_prepare := _call_dictionary(
		_agent,
		"get_save_context",
	)
	if not _valid_agent_context_observation(agent_context_before_prepare):
		_journal(context, "restore", "transaction_failed", {
			"stage": "agent_prepare",
		})
		_abort_world_restore(world_token)
		return _finish_with_gate(
			_failure("SESSION_CONTINUE_AGENT_PREPARE_FAILED", false),
			gate_token,
		)
	var agent_started_journal := _journal(
		context,
		"restore",
		"restore_agent_started",
		{"worldToken": world_token},
	)
	if agent_started_journal.get("ok") != true:
		_abort_world_restore(world_token)
		return _finish_with_gate(agent_started_journal, gate_token)
	var agent_prepare := _call_dictionary(
		_agent,
		"restore_game",
		[context.duplicate(true)],
	)
	var agent_prepare_ok_value: Variant = agent_prepare.get("ok")
	var agent_prepare_context_value: Variant = agent_prepare.get("context")
	var agent_prepare_status_value: Variant = agent_prepare.get("status")
	var observed_agent_prepare_context := _call_dictionary(
		_agent,
		"get_save_context",
	)
	var observed_prepare_transition := (
		not _valid_agent_context_observation(
			observed_agent_prepare_context,
		)
		or observed_agent_prepare_context != agent_context_before_prepare
	)
	var agent_prepare_uncertain: bool = (
		String(agent_prepare.get("errorCode", ""))
		== "SESSION_SAVE_PARTICIPANT_RESPONSE_INVALID"
		or not agent_prepare_ok_value is bool
		or (
			agent_prepare_ok_value == true
			and (
				not agent_prepare_status_value is String
				or agent_prepare_status_value != "pending_hydration"
			)
		)
		or observed_prepare_transition
	)
	if agent_prepare_uncertain:
		_journal(context, "restore", "transaction_failed", {
			"stage": "agent_commit",
		})
		_agent.call("cancel_restore")
		_abort_world_restore(world_token)
		return _finish_with_gate(
			_failure("SESSION_CONTINUE_AGENT_COMMIT_UNCERTAIN", false),
			gate_token,
		)
	if (
		agent_prepare_ok_value != true
		or not agent_prepare_context_value is Dictionary
		or (agent_prepare_context_value as Dictionary) != context
	):
		_journal(context, "restore", "transaction_failed", {
			"stage": "agent_prepare",
		})
		_agent.call("cancel_restore")
		_abort_world_restore(world_token)
		return _finish_with_gate(
			_failure("SESSION_CONTINUE_AGENT_PREPARE_FAILED", false),
			gate_token,
		)
	var resident_ids_value: Variant = agent_prepare.get("resident_ids")
	if not resident_ids_value is Array:
		_journal(context, "restore", "transaction_failed", {
			"stage": "agent_resident_set",
		})
		_agent.call("cancel_restore")
		_abort_world_restore(world_token)
		return _finish_with_gate(
			_failure("SESSION_CONTINUE_IDENTITY_MISMATCH", false),
			gate_token,
		)
	var resident_ids := resident_ids_value as Array
	var agent_migration_receipt := {}
	var agent_migration_receipt_value: Variant = agent_prepare.get(
		"migration_receipt",
	)
	if agent_migration_receipt_value is Dictionary:
		var candidate_receipt := agent_migration_receipt_value as Dictionary
		if (
			String(candidate_receipt.get("module", "")) == "resident_payload"
			and candidate_receipt.get("migrationVersion") is int
			and candidate_receipt.get("applied") is Array
		):
			agent_migration_receipt = candidate_receipt.duplicate(true)
	var normalized_agent_ids: Array[String] = []
	for resident_id_value: Variant in resident_ids:
		if not resident_id_value is String:
			_journal(context, "restore", "transaction_failed", {
				"stage": "agent_resident_set",
			})
			_agent.call("cancel_restore")
			_abort_world_restore(world_token)
			return _finish_with_gate(
				_failure("SESSION_CONTINUE_IDENTITY_MISMATCH", false),
				gate_token,
			)
		var resident_id := resident_id_value as String
		if (
			resident_id.is_empty()
			or resident_id != resident_id.strip_edges()
			or normalized_agent_ids.has(resident_id)
		):
			_journal(context, "restore", "transaction_failed", {
				"stage": "agent_resident_set",
			})
			_agent.call("cancel_restore")
			_abort_world_restore(world_token)
			return _finish_with_gate(
				_failure("SESSION_CONTINUE_IDENTITY_MISMATCH", false),
				gate_token,
			)
		normalized_agent_ids.append(resident_id)
	normalized_agent_ids.sort()
	if normalized_agent_ids != (
		restored_identity_contract.get("residentIds", []) as Array
	):
		_journal(context, "restore", "transaction_failed", {
			"stage": "agent_resident_set",
		})
		_agent.call("cancel_restore")
		_abort_world_restore(world_token)
		return _finish_with_gate(
			_failure("SESSION_CONTINUE_IDENTITY_MISMATCH", false),
			gate_token,
		)
	var hydrated := _call_dictionary(
		agent_hydrator,
		HYDRATOR_METHOD,
		[
			_agent,
			session_config.duplicate(true),
			normalized_agent_ids.duplicate(),
		],
	)
	if hydrated.get("ok") != true:
		_journal(context, "restore", "transaction_failed", {
			"stage": "agent_hydrate",
			"errorCode": String(hydrated.get("errorCode", "")),
		})
		_agent.call("cancel_restore")
		_abort_world_restore(world_token)
		return _finish_with_gate(
			_participant_failure(
				"SESSION_CONTINUE_AGENT_PREPARE_FAILED",
				hydrated,
				bool(hydrated.get("retryable", false)),
			),
			gate_token,
		)
	var hydrated_journal := _journal(
		context,
		"restore",
		"restore_agent_hydrated",
		{
			"worldToken": world_token,
			"residentCount": resident_ids.size(),
		},
	)
	if hydrated_journal.get("ok") != true:
		_agent.call("cancel_restore")
		_abort_world_restore(world_token)
		return _finish_with_gate(hydrated_journal, gate_token)
	var world_validation := _call_dictionary(
		_world,
		"validate_restore_candidate",
		[world_token],
	)
	var gate_validation := _call_dictionary(
		_gate,
		"validate_session_transaction",
		[gate_token],
	)
	if (
		world_validation.get("ok") != true
		or gate_validation.get("ok") != true
	):
		_journal(context, "restore", "transaction_failed", {
			"stage": (
				"world_validate"
				if world_validation.get("ok") != true
				else "gate_validate"
			),
		})
		_agent.call("cancel_restore")
		_abort_world_restore(world_token)
		return _finish_with_gate(
			_failure("SESSION_CONTINUE_WORLD_PREPARE_FAILED", false),
			gate_token,
		)
	var validated_journal := _journal(
		context,
		"restore",
		"restore_world_validated",
		{
			"worldToken": world_token,
		},
	)
	if validated_journal.get("ok") != true:
		_agent.call("cancel_restore")
		_abort_world_restore(world_token)
		return _finish_with_gate(validated_journal, gate_token)
	var agent_commit_started := _journal(
		context,
		"restore",
		"restore_agent_commit_started",
		{"worldToken": world_token},
	)
	if agent_commit_started.get("ok") != true:
		_agent.call("cancel_restore")
		_abort_world_restore(world_token)
		return _finish_with_gate(agent_commit_started, gate_token)
	var agent_commit := _call_dictionary(
		_agent,
		"finish_restore",
	)
	var agent_commit_ok_value: Variant = agent_commit.get("ok")
	var agent_commit_context_value: Variant = agent_commit.get("context")
	var observed_agent_context := _call_dictionary(
		_agent,
		"get_save_context",
	)
	var observed_agent_commit := observed_agent_context == context
	var agent_commit_uncertain: bool = (
		String(agent_commit.get("errorCode", ""))
		== "SESSION_SAVE_PARTICIPANT_RESPONSE_INVALID"
		or not agent_commit_ok_value is bool
		or (
			agent_commit_ok_value == true
			and (
				not agent_commit_context_value is Dictionary
				or (agent_commit_context_value as Dictionary) != context
			)
		)
		or (agent_commit_ok_value == true and not observed_agent_commit)
		or (agent_commit_ok_value == false and observed_agent_commit)
	)
	if agent_commit_uncertain:
		_journal(context, "restore", "transaction_failed", {
			"stage": "agent_commit",
		})
		_agent.call("cancel_restore")
		_abort_world_restore(world_token)
		return _finish_with_gate(
			_failure("SESSION_CONTINUE_AGENT_COMMIT_UNCERTAIN", false),
			gate_token,
		)
	if agent_commit_ok_value != true:
		_journal(context, "restore", "transaction_failed", {
			"stage": "agent_commit",
		})
		_agent.call("cancel_restore")
		_abort_world_restore(world_token)
		return _finish_with_gate(
			_failure("SESSION_CONTINUE_AGENT_COMMIT_FAILED", false),
			gate_token,
		)
	var agent_committed_journal := _journal(
		context,
		"restore",
		"restore_agent_committed",
		{
		"worldToken": world_token,
		},
	)
	if agent_committed_journal.get("ok") != true:
		_abort_world_restore(world_token)
		return _finish_with_gate(
			_failure("SESSION_CONTINUE_PARTIAL_COMMIT", false),
			gate_token,
		)
	var world_commit_method := (
		"commit_restore_candidate_for_observer"
		if _world.has_method("commit_restore_candidate_for_observer")
		else "commit_restore_candidate"
	)
	var world_commit := _call_dictionary(
		_world,
		world_commit_method,
		[world_token],
	)
	if world_commit.get("ok") != true:
		_journal(context, "restore", "transaction_failed", {
			"stage": "world_commit_after_agent",
		})
		_abort_world_restore(world_token)
		return _finish_with_gate(
			_failure("SESSION_CONTINUE_PARTIAL_COMMIT", false),
			gate_token,
		)
	var receipt_value: Variant = world_commit.get("commitReceipt")
	if not receipt_value is Dictionary:
		_journal(context, "restore", "transaction_failed", {
			"stage": "post_commit_validation",
		})
		_world.cleanup_restore_candidate(world_token)
		return _finish_with_gate(
			_failure("SESSION_CONTINUE_PARTIAL_COMMIT", false),
			gate_token,
		)
	var receipt := receipt_value as Dictionary
	var world_migration_receipt := (
		receipt.get("migrationReceipt", {}) as Dictionary
	).duplicate(true)
	var applied_migrations := (
		world_migration_receipt.get("applied", []) as Array
	).duplicate()
	for migration_id_value: Variant in agent_migration_receipt.get(
		"applied",
		[],
	) as Array:
		var migration_id := String(migration_id_value)
		if not migration_id.is_empty() and not applied_migrations.has(migration_id):
			applied_migrations.append(migration_id)
	var migration_receipt := world_migration_receipt.duplicate(true)
	migration_receipt["module"] = "restore"
	migration_receipt.erase("migrationVersion")
	migration_receipt["applied"] = applied_migrations
	migration_receipt["moduleReceipts"] = {
		"world_snapshot": world_migration_receipt,
		"resident_payload": agent_migration_receipt,
	}
	receipt["migrationReceipt"] = migration_receipt
	var identity_snapshot_value: Variant = receipt.get("identitySnapshot")
	var receipt_world_revision: Variant = receipt.get("worldRevision")
	var receipt_runtime_generation: Variant = receipt.get(
		"runtimeGeneration",
	)
	if (
		not identity_snapshot_value is Dictionary
		or not _restored_identity_matches(
			identity_snapshot_value as Dictionary,
			manifest.get("resident_ids", []) as Array,
		)
		or _call_dictionary(_agent, "get_save_context") != context
		or not _is_positive_integer_number(receipt_world_revision)
		or int(receipt_world_revision)
		< int(world_component.get("world_revision", 0))
		or not _is_positive_integer_number(receipt_runtime_generation)
	):
		_journal(context, "restore", "transaction_failed", {
			"stage": "post_commit_validation",
		})
		_world.cleanup_restore_candidate(world_token)
		return _finish_with_gate(
			_failure("SESSION_CONTINUE_PARTIAL_COMMIT", false),
			gate_token,
		)
	var world_committed_journal := _journal(
		context,
		"restore",
		"restore_world_committed",
		{
			"worldToken": world_token,
			"runtimeGeneration": int(receipt_runtime_generation),
		},
	)
	if world_committed_journal.get("ok") != true:
		_world.cleanup_restore_candidate(world_token)
		return _finish_with_gate(
			_failure("SESSION_CONTINUE_PARTIAL_COMMIT", false),
			gate_token,
		)
	_generation += 1
	var completed_journal := _journal(
		context,
		"restore",
		"restore_completed",
		{
			"generation": _generation,
		},
	)
	var cleanup_result := _call_dictionary(
		_world,
		"cleanup_restore_candidate",
		[world_token],
	)
	if completed_journal.get("ok") != true:
		return _finish_with_gate(
			_failure(
				"SESSION_CONTINUE_JOURNAL_INCOMPLETE",
				false,
			),
			gate_token,
		)
	if cleanup_result.get("ok") != true:
		return _finish_with_gate(
			_failure(
				"SESSION_CONTINUE_WORLD_CLEANUP_FAILED",
				false,
				[],
				{"committed": true},
			),
			gate_token,
		)
	return _finish_with_gate({
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"context": context.duplicate(true),
		"manifest": manifest.duplicate(true),
		"summary": MANIFEST.summary(manifest),
		"generation": _generation,
		"commitReceipt": receipt.duplicate(true),
	}, gate_token)


func inspect_incomplete(slot_id: String) -> Dictionary:
	var listed := _call_dictionary(
		_store,
		"list_incomplete",
		[slot_id],
	)
	if listed.get("ok") != true:
		return _normalize_store_failure(listed)
	var items: Array[Dictionary] = []
	var records_value: Variant = listed.get("records")
	if not records_value is Array:
		return _failure("SESSION_SAVE_PARTICIPANT_RESPONSE_INVALID", false)
	for record_value: Variant in records_value as Array:
		if not (record_value is Dictionary):
			return _failure(
				"SESSION_SAVE_JOURNAL_STATE_INVALID",
				false,
			)
		var record := record_value as Dictionary
		var context_value: Variant = record.get("context")
		var payload_value: Variant = record.get("payload")
		if (
			not context_value is Dictionary
			or MANIFEST.validate_context(context_value).get("ok") != true
			or not payload_value is Dictionary
		):
			return _failure(
				"SESSION_SAVE_JOURNAL_STATE_INVALID",
				false,
			)
		var state_value: Variant = record.get("state")
		var kind_value: Variant = record.get("kind")
		if not state_value is String or not kind_value is String:
			return _failure(
				"SESSION_SAVE_JOURNAL_STATE_INVALID",
				false,
			)
		var state := state_value as String
		var kind := kind_value as String
		var allowed_states: Array[String] = []
		if kind == "save":
			allowed_states = SAVE_JOURNAL_STATES
		elif kind == "restore":
			allowed_states = RESTORE_JOURNAL_STATES
		if state not in allowed_states:
			return _failure(
				"SESSION_SAVE_JOURNAL_STATE_INVALID",
				false,
			)
		if state == "transaction_failed":
			var failure_stage_value: Variant = (
				payload_value as Dictionary
			).get("stage")
			if not failure_stage_value is String:
				return _failure(
					"SESSION_SAVE_JOURNAL_STATE_INVALID",
					false,
				)
			var failure_stage := failure_stage_value as String
			var allowed_failure_stages := (
				SAVE_FAILURE_STAGES
				if kind == "save"
				else RESTORE_FAILURE_STAGES
			)
			if failure_stage not in allowed_failure_stages:
				return _failure(
					"SESSION_SAVE_JOURNAL_STATE_INVALID",
					false,
				)
		var classified := TownSaveJournalStates.classify_incomplete(
			kind,
			state,
			payload_value as Dictionary,
		)
		items.append({
			"context": (
				context_value as Dictionary
			).duplicate(true),
			"kind": kind,
			"state": state,
			"classification": String(classified.get("classification", "")),
			"errorCode": String(classified.get("errorCode", "")),
			"retryable": false,
		})
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"items": items,
	}


func _base_request(request: Dictionary) -> Dictionary:
	var slot_id_value: Variant = request.get("slotId")
	var session_id_value: Variant = request.get("sessionId")
	if not slot_id_value is String or not session_id_value is String:
		return _failure("SESSION_SAVE_CONTEXT_INVALID", false)
	var slot_id := slot_id_value as String
	var session_id := session_id_value as String
	if slot_id != slot_id.strip_edges() or session_id != session_id.strip_edges():
		return _failure("SESSION_SAVE_CONTEXT_INVALID", false)
	var context_check := MANIFEST.validate_slot_session(slot_id, session_id)
	var resident_result := MANIFEST.resident_ids(
		request.get("residentIdentities", []),
	)
	if (
		context_check.get("ok") != true
		or resident_result.get("ok") != true
		or not (request.get("sessionConfig") is Dictionary)
	):
		return _failure("SESSION_SAVE_CONTEXT_INVALID", false)
	var session_config_result := _validate_session_config(
		request.get("sessionConfig", {}) as Dictionary,
		session_id,
		resident_result.get("residentIds", []) as Array,
	)
	if session_config_result.get("ok") != true:
		return session_config_result
	var resident_messages_result := MANIFEST.validate_resident_messages(
		request.get("residentMessages", []),
		resident_result.get("residentIds", []) as Array,
	)
	if resident_messages_result.get("ok") != true:
		return _failure("SESSION_SAVE_RESIDENT_MESSAGES_INVALID", false)
	var saved_at_value: Variant = request.get(
		"savedAt",
		Time.get_datetime_string_from_system(false, false),
	)
	if not saved_at_value is String:
		return _failure("SESSION_SAVE_CONTEXT_INVALID", false)
	var saved_at := saved_at_value as String
	if not TownSaveScalars.is_saved_at(saved_at):
		return _failure("SESSION_SAVE_CONTEXT_INVALID", false)
	return {
		"ok": true,
		"slotId": slot_id,
		"sessionId": session_id,
		"savedAt": saved_at,
		"residentIds": (
			resident_result.get("residentIds", []) as Array
		).duplicate(),
		"residentMessages": (
			resident_messages_result.get("residentMessages", []) as Array
		).duplicate(true),
		"sessionConfig": (
			session_config_result.get("sessionConfig", {}) as Dictionary
		).duplicate(true),
	}


func _validate_session_config(
	value: Dictionary,
	session_id: String,
	expected_resident_ids: Array,
) -> Dictionary:
	var required_fields: Array[String] = [
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
	for key_value: Variant in value:
		if (
			not key_value is String
			or not SESSION_CONFIG_FIELDS.has(key_value as String)
		):
			return _failure("SESSION_SAVE_SESSION_CONFIG_INVALID", false, [{
				"path": "sessionConfig.%s" % String(key_value),
				"code": "SESSION_SAVE_PRIVATE_PAYLOAD_FORBIDDEN",
			}])
	for field_name in required_fields:
		if not value.has(field_name):
			return _failure("SESSION_SAVE_SESSION_CONFIG_INVALID", false)
	if not (value.get("openingConfig") is Dictionary):
		return _failure("SESSION_SAVE_SESSION_CONFIG_INVALID", false)
	if (value.get("openingConfig", {}) as Dictionary).is_empty():
		return _failure("SESSION_SAVE_SESSION_CONFIG_INVALID", false)
	if (
		not value.get("mode") is String
		or value.get("mode") not in ["new_game", "continue"]
		or not value.get("sessionId") is String
		or value.get("sessionId") != session_id
	):
		return _failure("SESSION_SAVE_SESSION_CONFIG_INVALID", false)
	if (
		value.has("saveRelease")
		and (
			not value.get("saveRelease") is String
			or not COMPATIBILITY.is_valid_release_marker(
				String(value.get("saveRelease", "")),
			)
		)
	):
		return _failure("SESSION_SAVE_SESSION_CONFIG_INVALID", false)
	if (
		not value.get("worldStartMode") is String
		or (
			value.get("worldStartMode") != "formal"
			and not (
				_allow_development_world
				and value.get("worldStartMode") == "development"
			)
		)
	):
		return _failure("SESSION_SAVE_SESSION_CONFIG_INVALID", false)
	for bool_field in [
		"useLiveModel",
		"enablePlayerAvatar",
		"enableTestUi",
	]:
		if not value.get(bool_field) is bool:
			return _failure("SESSION_SAVE_SESSION_CONFIG_INVALID", false)
	var identities := MANIFEST.resident_ids(
		value.get("residentIdentities", []),
	)
	if (
		identities.get("ok") != true
		or (identities.get("residentIds", []) as Array)
		!= expected_resident_ids
	):
		return _failure("SESSION_SAVE_SESSION_CONFIG_INVALID", false)
	var connected_values: Variant = value.get("connectedResidents")
	if not connected_values is Array:
		return _failure("SESSION_SAVE_SESSION_CONFIG_INVALID", false)
	var connected_names: Array[String] = []
	for name_value: Variant in connected_values as Array:
		if not name_value is String:
			return _failure("SESSION_SAVE_SESSION_CONFIG_INVALID", false)
		var resident_name := name_value as String
		if (
			resident_name.is_empty()
			or resident_name != resident_name.strip_edges()
			or connected_names.has(resident_name)
		):
			return _failure("SESSION_SAVE_SESSION_CONFIG_INVALID", false)
		connected_names.append(resident_name)
	var binding_validation := _validate_saved_resident_bindings(
		value.get("residentBindings"),
		expected_resident_ids,
	)
	if binding_validation.get("ok") != true:
		return binding_validation
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"sessionConfig": value.duplicate(true),
	}


func _validate_saved_resident_bindings(
	value: Variant,
	expected_resident_ids: Array,
) -> Dictionary:
	if not value is Array:
		return _failure("SESSION_SAVE_SESSION_CONFIG_INVALID", false)
	var resident_ids: Array[String] = []
	for binding_value: Variant in value as Array:
		if not binding_value is Dictionary:
			return _failure("SESSION_SAVE_SESSION_CONFIG_INVALID", false)
		var binding := binding_value as Dictionary
		for key: Variant in binding:
			if (
				not key is String
				or (key as String) not in ["residentId", "llmBinding"]
			):
				return _failure("SESSION_SAVE_PRIVATE_PAYLOAD_FORBIDDEN", false)
		if not binding.get("residentId") is String:
			return _failure("SESSION_SAVE_SESSION_CONFIG_INVALID", false)
		var resident_id := binding.get("residentId") as String
		var llm_value: Variant = binding.get("llmBinding")
		if (
			resident_id.is_empty()
			or resident_id != resident_id.strip_edges()
			or resident_ids.has(resident_id)
			or not llm_value is Dictionary
		):
			return _failure("SESSION_SAVE_SESSION_CONFIG_INVALID", false)
		var llm := llm_value as Dictionary
		for key: Variant in llm:
			if (
				not key is String
				or (key as String) not in ["mode", "providerId", "modelId"]
			):
				return _failure("SESSION_SAVE_PRIVATE_PAYLOAD_FORBIDDEN", false)
		if (
			llm.size() != 3
			or not llm.get("mode") is String
			or llm.get("mode") != "model"
			or not llm.get("providerId") is String
			or not llm.get("modelId") is String
			or (llm.get("providerId") as String).is_empty()
			or (llm.get("providerId") as String)
			!= (llm.get("providerId") as String).strip_edges()
			or (llm.get("modelId") as String).is_empty()
			or (llm.get("modelId") as String)
			!= (llm.get("modelId") as String).strip_edges()
		):
			return _failure("SESSION_SAVE_SESSION_CONFIG_INVALID", false)
		resident_ids.append(resident_id)
	resident_ids.sort()
	if resident_ids != expected_resident_ids:
		return _failure("SESSION_SAVE_SESSION_CONFIG_INVALID", false)
	return {"ok": true, "errorCode": "", "retryable": false}


func _restore_identity_contract(
	stored_values: Variant,
	requested_values: Variant,
	expected_ids: Array,
) -> Dictionary:
	var stored := _identity_map(stored_values)
	var requested := _identity_map(requested_values)
	if (
		stored.get("ok") != true
		or requested.get("ok") != true
		or (stored.get("residentIds", []) as Array) != expected_ids
		or stored.get("residents") != requested.get("residents")
	):
		return _failure("SESSION_CONTINUE_IDENTITY_MISMATCH", false)
	return stored


func _identity_map(values: Variant) -> Dictionary:
	if not (values is Array):
		return _failure("SESSION_CONTINUE_IDENTITY_MISMATCH", false)
	var residents: Array[Dictionary] = []
	var ids: Array[String] = []
	var names: Array[String] = []
	for value: Variant in values as Array:
		if not (value is Dictionary):
			return _failure("SESSION_CONTINUE_IDENTITY_MISMATCH", false)
		var identity := value as Dictionary
		var resident_id := String(identity.get("residentId", "")).strip_edges()
		var resident_name := String(
			identity.get("residentName", ""),
		).strip_edges()
		if (
			resident_id.is_empty()
			or resident_name.is_empty()
			or ids.has(resident_id)
			or names.has(resident_name)
		):
			return _failure("SESSION_CONTINUE_IDENTITY_MISMATCH", false)
		ids.append(resident_id)
		names.append(resident_name)
		residents.append({
			"residentId": resident_id,
			"residentName": resident_name,
		})
	ids.sort()
	names.sort()
	residents.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left.get("residentId", "")) < String(
			right.get("residentId", ""),
		)
	)
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"residentIds": ids,
		"residentNames": names,
		"residents": residents,
	}


func _save_orphan_failure(
	context: Dictionary,
	world_token: String,
	gate_token: String,
	stage: String,
) -> Dictionary:
	_journal(context, "save", "agent_orphan_isolated", {
		"stage": stage,
		"worldToken": world_token,
	})
	_abort_world_save(world_token)
	return _finish_with_gate(
		_failure(
			"SESSION_SAVE_AGENT_ORPHAN_ISOLATED",
			false,
			[],
			{
				"stage": stage,
				"participantBlocker": (
					"AGENT_SINGLE_REVISION_CLEANUP_MISSING"
				),
			},
		),
		gate_token,
	)


func _abort_world_save(token: String) -> void:
	if token.is_empty():
		return
	_world.abort_save_candidate(token)
	_world.cleanup_save_candidate(token)


func _abort_world_restore(token: String) -> void:
	if token.is_empty():
		return
	_world.abort_restore_candidate(token)
	_world.cleanup_restore_candidate(token)


func _restored_identity_matches(
	snapshot: Dictionary,
	expected_ids: Array,
) -> bool:
	var status_value: Variant = snapshot.get("status")
	if not status_value is String or status_value != "confirmed":
		return false
	var residents_value: Variant = snapshot.get("residents")
	if not residents_value is Array:
		return false
	var ids: Array[String] = []
	for value: Variant in residents_value as Array:
		if not (value is Dictionary):
			return false
		var resident_id_value: Variant = (
			value as Dictionary
		).get("residentId")
		if not resident_id_value is String:
			return false
		var resident_id := resident_id_value as String
		if (
			resident_id.is_empty()
			or resident_id != resident_id.strip_edges()
			or ids.has(resident_id)
		):
			return false
		ids.append(resident_id)
	ids.sort()
	return ids == expected_ids


func _journal(
	context: Dictionary,
	kind: String,
	stage: String,
	payload: Dictionary,
) -> Dictionary:
	var result := _call_dictionary(_store, "write_intent_stage", [
		context.duplicate(true),
		kind,
		_active_intent_id,
		stage,
		payload.duplicate(true),
	])
	return (
		_success()
		if result.get("ok") == true
		else _normalize_store_failure(result)
	)


func _validate_stored_candidate(
	context: Dictionary,
	stored: Dictionary,
	require_world_log := false,
) -> Dictionary:
	var snapshot_ref_value: Variant = stored.get("snapshotRef")
	var snapshot_sha256_value: Variant = stored.get("snapshotSha256")
	var session_config_ref_value: Variant = stored.get("sessionConfigRef")
	var session_config_sha256_value: Variant = stored.get("sessionConfigSha256")
	var world_log_ref_value: Variant = stored.get("worldLogSnapshotRef", "")
	var world_log_sha256_value: Variant = stored.get(
		"worldLogSnapshotSha256",
		"",
	)
	if (
		not snapshot_ref_value is String
		or not snapshot_sha256_value is String
		or not session_config_ref_value is String
		or not session_config_sha256_value is String
		or (require_world_log and not world_log_ref_value is String)
		or (require_world_log and not world_log_sha256_value is String)
	):
		return _failure("SESSION_SAVE_STORE_RESPONSE_INVALID", false)
	var revision_root := TownSaveContext.revision_directory(context)
	if (
		(snapshot_ref_value as String)
		!= revision_root + "/world_snapshot.json"
		or (session_config_ref_value as String)
		!= revision_root + "/session_config.json"
		or (
			require_world_log
			and (world_log_ref_value as String)
			!= revision_root + "/world_log_snapshot.json"
		)
		or not _is_sha256(snapshot_sha256_value as String)
		or not _is_sha256(session_config_sha256_value as String)
		or (
			require_world_log
			and not _is_sha256(world_log_sha256_value as String)
		)
	):
		return _failure("SESSION_SAVE_STORE_RESPONSE_INVALID", false)
	return _success()


func _validate_world_resident_ids(
	value: Variant,
	expected_ids: Array,
) -> Dictionary:
	return _validate_resident_ids(
		value,
		expected_ids,
		"SESSION_SAVE_WORLD_IDENTITY_MISMATCH",
	)


func _validate_resident_ids(
	value: Variant,
	expected_ids: Array,
	error_code: String,
) -> Dictionary:
	if not value is Array:
		return _failure(error_code, false)
	var resident_ids: Array[String] = []
	for resident_id_value: Variant in value as Array:
		if not resident_id_value is String:
			return _failure(error_code, false)
		var resident_id := resident_id_value as String
		if (
			resident_id.is_empty()
			or resident_id != resident_id.strip_edges()
			or resident_ids.has(resident_id)
		):
			return _failure(error_code, false)
		resident_ids.append(resident_id)
	resident_ids.sort()
	if resident_ids != expected_ids:
		return _failure(error_code, false)
	return _success()


func _is_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	for character in value:
		var code := character.unicode_at(0)
		if not (
			(code >= 48 and code <= 57)
			or (code >= 97 and code <= 102)
		):
			return false
	return true


func _is_positive_integer_number(value: Variant) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var number := float(value)
	return (
		is_finite(number)
		and number == floorf(number)
		and number >= 1.0
		and number <= 9007199254740991.0
	)


func _end_gate(token: String) -> Dictionary:
	if token.is_empty():
		return _failure("SESSION_SAVE_GATE_RELEASE_FAILED", false)
	var ended_value: Variant = _gate.call(
		"end_session_transaction",
		token,
	)
	if not ended_value is Dictionary:
		return _failure("SESSION_SAVE_GATE_RELEASE_FAILED", false)
	var ended := ended_value as Dictionary
	if ended.get("ok") != true:
		return _failure(
			"SESSION_SAVE_GATE_RELEASE_FAILED",
			false,
			[],
			{
				"participantErrorCode": String(
					ended.get("errorCode", ""),
				),
			},
		)
	return _success()


func _finish_with_gate(
	result: Dictionary,
	gate_token: String,
) -> Dictionary:
	var released := _end_gate(gate_token)
	if released.get("ok") != true:
		var meta := (
			released.get("meta", {}) as Dictionary
		).duplicate(true)
		meta["operationOk"] = result.get("ok") == true
		meta["operationErrorCode"] = String(
			result.get("errorCode", ""),
		)
		return _finish(_failure(
			String(released.get(
				"errorCode",
				"SESSION_SAVE_GATE_RELEASE_FAILED",
			)),
			false,
			[],
			meta,
		))
	return _finish(result)


func _finish(result: Dictionary) -> Dictionary:
	var final_result := result
	if not _active_slot_lease.is_empty():
		var token := String(_active_slot_lease.get("leaseToken", ""))
		var released := _call_dictionary(
			_store,
			"end_slot_transaction",
			[token],
		)
		if released.get("ok") != true:
			final_result = _failure(
				"SESSION_SAVE_SLOT_LEASE_RELEASE_FAILED",
				false,
				[],
				{
					"operationOk": result.get("ok") == true,
					"operationErrorCode": String(
						result.get("errorCode", ""),
					),
					"participantErrorCode": String(
						released.get("errorCode", ""),
					),
				},
			)
		_active_slot_lease.clear()
	_busy = false
	_active_intent_id = ""
	return final_result


func _begin_slot_transaction(slot_id: String) -> Dictionary:
	var lease := _call_dictionary(
		_store,
		"begin_slot_transaction",
		[slot_id],
	)
	if lease.get("ok") != true:
		return _normalize_store_failure(lease)
	var token_value: Variant = lease.get("leaseToken")
	if (
		not token_value is String
		or (token_value as String).is_empty()
		or lease.get("slotId") != slot_id
	):
		if token_value is String and not (token_value as String).is_empty():
			var released := _call_dictionary(
				_store,
				"end_slot_transaction",
				[token_value],
			)
			if released.get("ok") != true:
				return _failure(
					"SESSION_SAVE_SLOT_LEASE_RELEASE_FAILED",
					false,
					[],
					{
						"operationOk": false,
						"operationErrorCode": (
							"SESSION_SAVE_STORE_RESPONSE_INVALID"
						),
						"participantErrorCode": String(
							released.get("errorCode", ""),
						),
					},
				)
		return _failure("SESSION_SAVE_STORE_RESPONSE_INVALID", false)
	_active_slot_lease = {
		"slotId": slot_id,
		"leaseToken": token_value as String,
	}
	return _success()


func _require_configured() -> Dictionary:
	if (
		_store == null
		or _world == null
		or _agent == null
		or _gate == null
		or not is_instance_valid(_store)
		or not is_instance_valid(_world)
		or not is_instance_valid(_agent)
		or not is_instance_valid(_gate)
	):
		return _failure("SESSION_SAVE_CONTRACT_INVALID", false)
	return _success()


func _call_dictionary(
	target: Object,
	method_name: String,
	arguments: Array = [],
) -> Dictionary:
	if (
		target == null
		or not is_instance_valid(target)
		or not target.has_method(method_name)
	):
		return _failure(
			"SESSION_SAVE_PARTICIPANT_RESPONSE_INVALID",
			false,
			[],
			{"method": method_name},
		)
	var value: Variant = target.callv(method_name, arguments)
	if not value is Dictionary:
		return _failure(
			"SESSION_SAVE_PARTICIPANT_RESPONSE_INVALID",
			false,
			[],
			{"method": method_name},
		)
	return (value as Dictionary).duplicate(true)


func _method_accepts_argument_count(
	target: Object,
	method_name: String,
	argument_count: int,
) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	for method_value: Variant in target.get_method_list():
		if not method_value is Dictionary:
			continue
		var method := method_value as Dictionary
		if String(method.get("name", "")) != method_name:
			continue
		var arguments_value: Variant = method.get("args", [])
		return (
			arguments_value is Array
			and (arguments_value as Array).size() >= argument_count
		)
	return false


func _valid_agent_context_observation(value: Dictionary) -> bool:
	return (
		value.is_empty()
		or MANIFEST.validate_context(value).get("ok") == true
	)


func _array_copy(value: Variant) -> Array:
	return (value as Array).duplicate(true) if value is Array else []


func _contract_errors(
	scope: String,
	target: Object,
	methods: Array[String],
) -> Array[Dictionary]:
	var errors: Array[Dictionary] = []
	if target == null or not is_instance_valid(target):
		return [{"path": scope, "code": "SESSION_SAVE_CONTRACT_INVALID"}]
	for method_name in methods:
		if not target.has_method(method_name):
			errors.append({
				"path": "%s.%s" % [scope, method_name],
				"code": "SESSION_SAVE_CONTRACT_INVALID",
			})
	return errors


func _participant_failure(
	error_code: String,
	result: Dictionary,
	retryable: bool,
) -> Dictionary:
	var participant_errors: Array = []
	if result.get("errors") is Array:
		participant_errors = (
			result.get("errors", []) as Array
		).duplicate(true)
	return _failure(error_code, retryable, participant_errors, {
		"participantErrorCode": String(result.get("errorCode", "")),
	})


func _normalize_store_failure(result: Dictionary) -> Dictionary:
	return _failure(
		String(result.get("errorCode", "SESSION_SAVE_STORE_FAILED")),
		bool(result.get("retryable", false)),
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
