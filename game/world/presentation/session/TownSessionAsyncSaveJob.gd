class_name TownSessionAsyncSaveJob
extends RefCounted


const COORDINATOR := preload(
	"res://world/presentation/session/TownSessionSaveCoordinator.gd"
)
const WORLD_CANDIDATE_RUNTIME := preload(
	"res://world/runtime/persistence/TownWorldSaveCandidateRuntime.gd"
)

var _thread: Thread
var _started := false
var _finished := false
var _result: Dictionary = {}
var _started_usec := 0


class PreparedWorldParticipant:
	extends RefCounted
	var _capture: Dictionary
	var _candidate_runtime: TownWorldSaveCandidateRuntime
	var _source_generation := 0
	var _world_revision := 0

	func _init(capture: Dictionary) -> void:
		# The UI service passes a detached, immutable capture. Keeping the same
		# reference avoids another full snapshot copy on the worker's first frame.
		_capture = capture
		_candidate_runtime = WORLD_CANDIDATE_RUNTIME.new()
		var candidate := _capture.get("candidate", {}) as Dictionary
		_source_generation = int(candidate.get("sourceGeneration", 0))
		_world_revision = int(candidate.get("worldRevision", 0))

	func prepare_save_candidate() -> Dictionary:
		var candidate := _capture.get("candidate", {}) as Dictionary
		return _candidate_runtime.prepare(
			_source_generation,
			_world_revision,
			(_capture.get("snapshot", {}) as Dictionary).duplicate(true),
			(_capture.get("worldLogSnapshot", {}) as Dictionary).duplicate(true),
			(candidate.get("identitySnapshot", {}) as Dictionary).duplicate(true),
			(candidate.get("residentIds", []) as Array).duplicate(),
		) as Dictionary

	func validate_save_candidate(token: String) -> Dictionary:
		return _candidate_runtime.validate(
			token, true, _source_generation, _world_revision,
		) as Dictionary

	func commit_save_candidate(
		token: String,
		snapshot_ref: String,
		world_log_snapshot_ref := "",
	) -> Dictionary:
		return _candidate_runtime.commit(
			token,
			snapshot_ref,
			String(world_log_snapshot_ref),
			true,
			_source_generation,
			_world_revision,
		) as Dictionary

	func abort_save_candidate(token: String) -> Dictionary:
		return _candidate_runtime.abort(token) as Dictionary

	func cleanup_save_candidate(token: String) -> Dictionary:
		return _candidate_runtime.cleanup(token) as Dictionary

	func prepare_restore_candidate(
		_world_data: Dictionary = {},
		_opening_config: Dictionary = {},
		_snapshot: Dictionary = {},
		_resident_identities: Variant = [],
		_require_world_ready := true,
		_world_log_snapshot: Dictionary = {},
	) -> Dictionary:
		return _unsupported()

	func validate_restore_candidate(_token: String) -> Dictionary:
		return _unsupported()

	func commit_restore_candidate(_token: String) -> Dictionary:
		return _unsupported()

	func abort_restore_candidate(_token: String) -> Dictionary:
		return _unsupported()

	func cleanup_restore_candidate(_token: String) -> Dictionary:
		return _unsupported()

	func _unsupported() -> Dictionary:
		return {
			"ok": false,
			"errorCode": "SESSION_ASYNC_SAVE_RESTORE_UNSUPPORTED",
			"retryable": false,
		}


class PreparedAgentParticipant:
	extends RefCounted
	var _context: Dictionary
	var _resident_ids: Array
	var _resident_payloads: Dictionary
	var _store: RefCounted

	func _init(capture: Dictionary, store: RefCounted) -> void:
		# AgentSystem has already encoded each resident into detached payload data.
		# These structures are read-only during the worker transaction.
		_context = capture.get("context", {}) as Dictionary
		_resident_ids = capture.get("residentIds", []) as Array
		_resident_payloads = capture.get("residentPayloads", {}) as Dictionary
		_store = store

	func save_game(next_context: Variant) -> Dictionary:
		var result := _store.save_snapshot(
			next_context,
			_resident_payloads,
		) as Dictionary
		if not bool(result.get("ok", false)):
			return result
		_context = (next_context as Dictionary).duplicate(true)
		return {"ok": true, "context": _context.duplicate(true)}

	func get_save_context() -> Dictionary:
		return _context.duplicate(true)

	func get_active_resident_ids() -> Dictionary:
		return {
			"ok": true,
			"resident_ids": _resident_ids.duplicate(),
		}

	func restore_game(_context: Variant) -> Dictionary:
		return _unsupported()

	func finish_restore() -> Dictionary:
		return _unsupported()

	func cancel_restore() -> Dictionary:
		return _unsupported()

	func _unsupported() -> Dictionary:
		return {
			"ok": false,
			"errorCode": "SESSION_ASYNC_SAVE_RESTORE_UNSUPPORTED",
			"retryable": false,
		}


class PreparedGate:
	extends RefCounted
	var _sequence := 0
	var _active_token := ""

	func begin_session_transaction(
		kind_value: Variant,
		_context_value: Variant,
	) -> Dictionary:
		if not _active_token.is_empty() or kind_value != "save":
			return _failure("SESSION_SAVE_BUSY", true)
		_sequence += 1
		_active_token = "async-save-%d" % _sequence
		return {
			"ok": true,
			"errorCode": "",
			"retryable": false,
			"token": _active_token,
		}

	func validate_session_transaction(token_value: Variant) -> Dictionary:
		if token_value != _active_token or _active_token.is_empty():
			return _failure("SESSION_SAVE_GATE_STALE", false)
		return {"ok": true, "errorCode": "", "retryable": false}

	func end_session_transaction(token_value: Variant) -> Dictionary:
		if token_value != _active_token or _active_token.is_empty():
			return _failure("SESSION_SAVE_GATE_STALE", false)
		_active_token = ""
		return {"ok": true, "errorCode": "", "retryable": false}

	func _failure(error_code: String, retryable: bool) -> Dictionary:
		return {
			"ok": false,
			"errorCode": error_code,
			"retryable": retryable,
		}


func start(
	store: RefCounted,
	world_capture: Dictionary,
	agent_capture: Dictionary,
	agent_store: RefCounted,
	request: Dictionary,
	options: Dictionary = {},
) -> Dictionary:
	if _started:
		return _failure("SESSION_ASYNC_SAVE_ALREADY_STARTED", false)
	if store == null or agent_store == null:
		return _failure("SESSION_ASYNC_SAVE_STORE_MISSING", false)
	_thread = Thread.new()
	_started_usec = Time.get_ticks_usec()
	var start_error := _thread.start(_run.bind(
		store,
		# Captures are detached before start and are never mutated by the caller
		# afterwards. Do not deep-copy them on the main thread or at thread start.
		world_capture,
		agent_capture,
		agent_store,
		request.duplicate(true),
		options.duplicate(true),
	))
	if start_error != OK:
		_thread = null
		_started_usec = 0
		return _failure("SESSION_ASYNC_SAVE_THREAD_START_FAILED", true)
	_started = true
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"pending": true,
	}


func poll() -> Dictionary:
	if not _started:
		return _failure("SESSION_ASYNC_SAVE_NOT_STARTED", false)
	if _finished:
		return _result.duplicate(true)
	if _thread.is_alive():
		return {"ok": true, "pending": true}
	return _collect_result()


func finish() -> Dictionary:
	if not _started:
		return _failure("SESSION_ASYNC_SAVE_NOT_STARTED", false)
	if _finished:
		return _result.duplicate(true)
	return _collect_result()


func _collect_result() -> Dictionary:
	var value: Variant = _thread.wait_to_finish()
	_finished = true
	if value is Dictionary:
		_result = (value as Dictionary).duplicate(true)
	else:
		_result = _failure("SESSION_ASYNC_SAVE_RESULT_INVALID", false)
	var timing := (_result.get("timing", {}) as Dictionary).duplicate(true)
	timing["totalMsec"] = (
		float(Time.get_ticks_usec() - _started_usec) / 1000.0
	)
	_result["timing"] = timing
	_result["pending"] = false
	return _result.duplicate(true)


func _run(
	store: RefCounted,
	world_capture: Dictionary,
	agent_capture: Dictionary,
	agent_store: RefCounted,
	request: Dictionary,
	options: Dictionary,
) -> Dictionary:
	var worker_started_usec := Time.get_ticks_usec()
	var delay_msec := maxi(0, int(options.get("workerDelayMsec", 0)))
	if delay_msec > 0:
		OS.delay_msec(delay_msec)
	var world := PreparedWorldParticipant.new(world_capture)
	var agent := PreparedAgentParticipant.new(agent_capture, agent_store)
	var gate := PreparedGate.new()
	var coordinator: TownSessionSaveCoordinator = COORDINATOR.new()
	var configured := coordinator.configure(
		store, world, agent, gate,
	) as Dictionary
	var result: Dictionary
	if not bool(configured.get("ok", false)):
		result = configured
	else:
		result = coordinator.save(request) as Dictionary
	result["timing"] = {
		"workerMsec": (
			float(Time.get_ticks_usec() - worker_started_usec) / 1000.0
		),
	}
	return result


func _failure(error_code: String, retryable: bool) -> Dictionary:
	return {
		"ok": false,
		"errorCode": error_code,
		"retryable": retryable,
		"pending": false,
	}
