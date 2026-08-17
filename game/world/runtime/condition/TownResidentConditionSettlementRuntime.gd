class_name TownResidentConditionSettlementRuntime
extends RefCounted


const ACTIVITY_ATTENDANCE_RUNTIME := preload(
	"res://world/runtime/activity/TownActivityAttendanceRuntime.gd"
)


const SLEEP_ACTIVITY_ID := "activity_home_sleep"


static func settle_activity(
	host,
	resident_id: String,
	resident: Dictionary,
	action: Dictionary,
	execution: Dictionary,
	status: String,
	reason: String,
) -> void:
	if execution.is_empty() or host._environment == null:
		return
	var action_id := String(action.get("action_id", "")).strip_edges()
	if action_id.is_empty():
		return
	var occurred_at := int(host._environment.get_absolute_minute())
	var activity_id := String(execution.get("activityId", ""))
	var condition_result: Dictionary = {}
	if activity_id == SLEEP_ACTIVITY_ID:
		ACTIVITY_ATTENDANCE_RUNTIME.clear_sleep_leave(host, resident)
		var active_sleep := host._resident_sleep.get_active_sleep(resident_id) as Dictionary
		if active_sleep.is_empty():
			return
		var sleep_finish := host._resident_sleep.finish_sleep(
			resident_id,
			action_id,
			occurred_at,
			status != "completed",
			reason if not reason.strip_edges().is_empty() else status,
		) as Dictionary
		if sleep_finish.get("ok") != true:
			return
		condition_result = host._resident_conditions.submit_sleep_result(
			resident_id,
			sleep_finish.get("sleepResult", {}) as Dictionary,
			host.CLINIC_CONDITION_SETTLEMENT_RUNTIME.life_state(host, resident),
		) as Dictionary
	else:
		var performing_started_at: int = int(action.get("startedAbsoluteMinute", occurred_at)) + host.ACTION_SUPPORT.prop_approach_duration_minutes(host, action)
		performing_started_at = mini(performing_started_at, occurred_at)
		condition_result = host._resident_conditions.submit_activity_execution_result(
			resident_id,
			{
				"resultId": "activity:%s:%s" % [action_id, status],
				"activityId": activity_id,
				"actionId": action_id,
				"startedAtMinute": performing_started_at,
				"occurredAtMinute": occurred_at,
				"status": status,
				"placeId": String(execution.get("placeId", "")),
				"weather": host.get_weather(),
				"outdoors": String(resident.get("spaceId", "")) == "town_outdoor",
			},
			host.CLINIC_CONDITION_SETTLEMENT_RUNTIME.life_state(host, resident),
		) as Dictionary
	host.CLINIC_CONDITION_SETTLEMENT_RUNTIME.record_condition_result(host, resident_id, condition_result)


static func settle_route(
	host,
	resident_id: String,
	resident: Dictionary,
	action: Dictionary,
	status: String,
) -> void:
	if host._environment == null or String(action.get("type", "")) != "去":
		return
	var action_id := String(action.get("action_id", "")).strip_edges()
	if action_id.is_empty():
		return
	var started_at := int(action.get("startedAbsoluteMinute", 0))
	var occurred_at := int(host._environment.get_absolute_minute())
	var actual_duration := clampi(
		occurred_at - started_at,
		0,
		maxi(0, int(action.get("durationMinutes", 0))),
	)
	if actual_duration < 20:
		return
	var route := action.get("route", {}) as Dictionary
	var was_outdoors := false
	for sample_value: Variant in route.get("minutePositions", []) as Array:
		if sample_value is Dictionary and String((sample_value as Dictionary).get("spaceId", "")) == "town_outdoor":
			was_outdoors = true
			break
	var result := host._resident_conditions.submit_world_action_result(
		resident_id,
		{
			"resultId": "route:%s:%s" % [action_id, status],
			"sourceKind": "route",
			"sourceRef": action_id,
			"startedAtMinute": started_at,
			"occurredAtMinute": occurred_at,
			"status": status,
			"riskTags": ["physical_exertion"],
			"reliefTags": [],
			"context": {
				"fromPlaceId": String(route.get("fromPlaceName", "")),
				"toPlaceId": String(action.get("place", "")),
				"weather": host.get_weather(),
				"outdoors": was_outdoors,
			},
		},
		host.CLINIC_CONDITION_SETTLEMENT_RUNTIME.life_state(host, resident),
	) as Dictionary
	host.CLINIC_CONDITION_SETTLEMENT_RUNTIME.record_condition_result(host, resident_id, result)
