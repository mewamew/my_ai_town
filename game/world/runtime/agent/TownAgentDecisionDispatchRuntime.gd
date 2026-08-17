class_name TownAgentDecisionDispatchRuntime
extends RefCounted


const WAKE_STATE_RUNTIME := preload(
	"res://world/runtime/TownAgentWakeStateRuntime.gd"
)
const WAKE_CONTEXT_RUNTIME := preload(
	"res://world/runtime/agent/TownAgentWakeContextRuntime.gd"
)
const DECISION_ENVELOPE_RUNTIME := preload(
	"res://world/runtime/agent/TownAgentDecisionEnvelopeRuntime.gd"
)
const GO_ACTION_PREFETCH_RUNTIME := preload(
	"res://world/runtime/movement/TownGoActionPrefetchRuntime.gd"
)


static func take(
	host,
	resident_filter: Array = [],
	materialize_snapshots: bool = true,
) -> Array[Dictionary]:
	if not host._running or host.is_paused():
		return []
	host.telemetry.ensure_frame_probe()
	var allowed := {}
	for value: Variant in resident_filter:
		var resident_id: String = host._resident_key(String(value))
		if not resident_id.is_empty():
			allowed[resident_id] = true
	var result: Array[Dictionary] = []
	var pending_count := 0
	for resident_id: String in host.resident_registry.order:
		if not allowed.is_empty() and not allowed.has(resident_id):
			continue
		var resident := host.resident_registry.records[resident_id] as Dictionary
		if (
			not host.resident_is_present(resident)
			or not bool(resident.get("wakeDispatchQueued", false))
		):
			continue
		pending_count += 1
		var lap_usec := Time.get_ticks_usec() if host.telemetry.frame_probe != null else 0
		if materialize_snapshots and WAKE_STATE_RUNTIME.needs_refresh(resident, 0, ""):
			refresh_snapshot(host, resident_id, resident)
			WAKE_STATE_RUNTIME.mark_built(
				resident,
				int(host._environment.get_absolute_minute()),
				host.get_weather(),
			)
			lap_usec = probe_lap(host, "agentTakeRefreshUsec", lap_usec)
		# 轻量模式先由 Gateway 按容量选中，真正派发前再冻结完整快照。
		resident["wakeDispatchQueued"] = false
		result.append({
			"residentId": resident_id,
			"residentName": String(host.resident_registry.name_by_id.get(resident_id, "")),
			"wakePacket": (
				resident.get("pendingWake", {}) as Dictionary
			).duplicate(true),
		})
		if host.telemetry.frame_probe != null:
			probe_lap(host, "agentTakePacketCopyUsec", lap_usec)
			host.telemetry.frame_probe.record(
				Engine.get_process_frames(),
				"agentTakeResidentCount",
				1,
			)
	host.telemetry.update_pending_queue_peak(pending_count)
	return result


static func probe_lap(host, key: String, lap_started_usec: int) -> int:
	if host.telemetry.frame_probe == null:
		return lap_started_usec
	var now_usec := Time.get_ticks_usec()
	host.telemetry.frame_probe.record(
		Engine.get_process_frames(),
		key,
		now_usec - lap_started_usec,
	)
	return now_usec


static func refresh_snapshot(
	host,
	resident_id: String,
	resident: Dictionary,
	frame_budgeted := false,
) -> void:
	var pending := resident.get("pendingWake", {}) as Dictionary
	if pending.is_empty():
		return
	host.telemetry.count_agent_request_metric("wakeRefresh", 1)
	var preserved_social_results: Variant = (
		WAKE_STATE_RUNTIME.preserved_social_results(pending)
	)
	resident["pendingWake"] = WAKE_CONTEXT_RUNTIME.wake_packet(
		host,
		resident_id,
		resident,
		String(resident.get("validDecisionId", "")),
		(pending.get("events", []) as Array).duplicate(true),
		(pending.get("action_results", []) as Array).duplicate(true),
		preserved_social_results,
		bool(resident.get("decisionPrefetch", false))
		and GO_ACTION_PREFETCH_RUNTIME.can_prefetch(
			resident.get("currentAction", {}) as Dictionary,
		),
		frame_budgeted,
	)


static func take_by_ids(
	host,
	resident_ids: Array,
	materialize_snapshots: bool = true,
) -> Array[Dictionary]:
	if resident_ids.is_empty():
		return []
	var normalized_ids: Array[String] = WAKE_STATE_RUNTIME.normalized_resident_ids(
		resident_ids,
		host.resident_registry.records,
		host.resident_registry.id_by_name,
	)
	return [] if normalized_ids.is_empty() else take(
		host,
		normalized_ids,
		materialize_snapshots,
	)


static func refresh_by_id(
	host,
	resident_ref: String,
	decision_id: String,
) -> Dictionary:
	var resident_id: String = host._resident_key(resident_ref)
	if resident_id.is_empty() or not host._running or not host.resident_registry.records.has(resident_id):
		return {"ok": false, "stale": true}
	var resident := host.resident_registry.records[resident_id] as Dictionary
	if (
		not host.resident_is_present(resident)
		or not bool(resident.get("decisionPending", false))
		or String(resident.get("validDecisionId", "")) != decision_id
	):
		return {"ok": false, "stale": true}
	var current_minute := int(host._environment.get_absolute_minute())
	var current_weather: String = host.get_weather()
	var refresh_started_usec := (
		Time.get_ticks_usec() if host.telemetry.frame_probe != null else 0
	)
	if WAKE_STATE_RUNTIME.needs_refresh(resident, 0, ""):
		refresh_snapshot(host, resident_id, resident, true)
		WAKE_STATE_RUNTIME.mark_built(resident, current_minute, current_weather)
		probe_lap(host, "agentDispatchRefreshUsec", refresh_started_usec)
	return {
		"ok": true,
		"stale": false,
		"residentId": resident_id,
		"decisionId": decision_id,
		"wakePacket": (
			resident.get("pendingWake", {}) as Dictionary
		).duplicate(true),
	}


static func redispatch(
	host,
	resident_ref: String,
	decision_id: String,
) -> bool:
	var resident_id: String = host._resident_key(resident_ref)
	if resident_id.is_empty():
		return false
	var resident := host.resident_registry.records[resident_id] as Dictionary
	if (
		not bool(resident.get("decisionPending", false))
		or String(resident.get("validDecisionId", "")) != decision_id
	):
		return false
	WAKE_STATE_RUNTIME.mark_dirty(resident)
	resident["wakeDispatchQueued"] = true
	return true


static func submit_by_id(
	host,
	resident_id: String,
	decision: Dictionary,
) -> Dictionary:
	var normalized := resident_id.strip_edges()
	var resident_name := String(host.resident_registry.name_by_id.get(normalized, ""))
	var entry_error := DECISION_ENVELOPE_RUNTIME.by_id_entry_error(
		host._running,
		normalized,
		resident_name,
		host.resident_registry.records.has(normalized),
		host._running
		and host.resident_registry.records.has(normalized)
		and host._resident_is_alive(normalized),
		host._world_revision,
	)
	if not entry_error.is_empty():
		return entry_error
	var result: Dictionary = host.submit_agent_decision(normalized, decision)
	result["residentId"] = normalized
	result["residentName"] = resident_name
	result["errorCode"] = String(result.get("errorCode", ""))
	result["retryable"] = bool(result.get("retryable", false))
	result["worldRevision"] = host._world_revision
	return result
