class_name TownClinicConditionSettlementRuntime
extends RefCounted


const SERVICE_REQUEST_POLICY := preload(
	"res://world/runtime/work/TownClinicServiceRequestPolicy.gd"
)
const AGENT_WORLD_QUERY_RUNTIME := preload(
	"res://world/runtime/agent/TownAgentWorldQueryRuntime.gd"
)


static func life_state(host, resident: Dictionary) -> Dictionary:
	var state: Dictionary = resident.get(
		"activityState",
		host.ACTIVITY_SCALARS.empty_activity_state(),
	)
	var result: Dictionary = {}
	for field_value: Variant in host.ACTIVITY_STATE_KEYS:
		var field := String(field_value)
		result[field] = clampf(float(state.get(field, 50.0)), 0.0, 100.0)
	return result


static func record_condition_result(
	host,
	resident_id: String,
	result: Dictionary,
) -> void:
	if result.get("ok") != true:
		return
	for event_value: Variant in result.get("events", []) as Array:
		if not event_value is Dictionary:
			continue
		var event := (event_value as Dictionary).duplicate(true)
		var public_event_id: String = host.world_log_domain.journal.next_world_event_id()
		host.WORLD_LOG_COMMIT_RUNTIME.append_public(
			host,
			public_event_id,
			"world_event",
			resident_id,
			host.resident_display_name(resident_id),
			String(
				(host.resident_registry.records.get(resident_id, {}) as Dictionary).get(
					"currentPlace",
					"",
				),
			),
			event,
		)
		var agent_event := event.duplicate(true)
		agent_event["event_id"] = public_event_id
		agent_event["time"] = host.get_time()
		agent_event["type"] = "身体状况变化"
		host.WORLD_EVENT_DELIVERY_RUNTIME.enqueue(host, resident_id, agent_event)


static func settle(
	host,
	request: Dictionary,
	task: Dictionary,
	worker_resident_id: String,
	outcome: Dictionary,
	now: int,
	execution: Dictionary,
) -> void:
	var patient_id := String(request.get("requesterResidentId", ""))
	if not host.resident_registry.records.has(patient_id):
		return
	var request_context := request.get("context", {}) as Dictionary
	if bool(request_context.get("generatedFromConflictInjury", false)):
		return
	var condition_ids: Array = (
		request_context.get("conditionIds", []) as Array
	).duplicate()
	if condition_ids.is_empty():
		return
	var capability := String(task.get("capability", ""))
	var relief_tags := (
		["care_examine", "indoor_dry"]
		if capability == "care.consult"
		else ["basic_care"]
	)
	var care_started_at := maxi(
		0,
		now - int(execution.get("performedDurationMinutes", 1)),
	)
	care_started_at = clampi(care_started_at, 0, now)
	var result := host._resident_conditions.submit_world_action_result(
		patient_id,
		{
			"resultId": "clinic:%s:%s" % [
				String(request.get("requestId", "")),
				capability,
			],
			"sourceKind": "place_event",
			"sourceRef": String(request.get("requestId", "")),
			"startedAtMinute": care_started_at,
			"occurredAtMinute": now,
			"status": "completed",
			"riskTags": [],
			"reliefTags": relief_tags,
			"context": {
				"placeId": String(request.get("placeId", "")),
				"workerResidentId": worker_resident_id,
				"requestId": String(request.get("requestId", "")),
				"targetConditionIds": condition_ids,
				"careOutcome": outcome.duplicate(true),
			},
		},
		life_state(
			host,
			host.resident_registry.records.get(patient_id, {}) as Dictionary,
		),
	) as Dictionary
	record_condition_result(host, patient_id, result)


static func request_context(host, resident_id: String) -> Dictionary:
	var nearby_resident_ids: Array[String] = []
	return SERVICE_REQUEST_POLICY.build_condition_context(
		host._resident_conditions.get_conditions(resident_id) as Array,
		AGENT_WORLD_QUERY_RUNTIME.conflict_snapshot(
			host,
			resident_id,
			host.resident_registry.records.get(resident_id, {}) as Dictionary,
			nearby_resident_ids,
		),
	)
