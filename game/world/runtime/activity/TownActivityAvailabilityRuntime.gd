class_name TownActivityAvailabilityRuntime
extends RefCounted


const ACTIVITY_SCALARS := preload(
	"res://world/runtime/activity/TownActivityScalars.gd"
)
const DINING_SERVICE := preload(
	"res://world/runtime/work/TownDiningServiceRuntime.gd"
)
const CLINIC_CONTINUITY := preload(
	"res://world/runtime/condition/TownClinicContinuityRuntime.gd"
)
const PUBLIC_PLACE_CONTINUITY := preload(
	"res://world/runtime/work/TownPublicPlaceContinuityRuntime.gd"
)
const OCCUPATION_SERVICE_ACTIVITY_POLICY := preload(
	"res://world/runtime/work/TownOccupationServiceActivityPolicy.gd"
)
const SOCIAL_JUDGMENTS := preload(
	"res://world/runtime/social/TownSocialJudgments.gd"
)


static func resident_sleep_needed(resident: Dictionary) -> bool:
	return ACTIVITY_SCALARS.resident_sleep_needed(resident)


static func apply_sleep(resident: Dictionary, option: Dictionary) -> void:
	ACTIVITY_SCALARS.apply_sleep_activity_availability(resident, option)


static func apply_occupation_service(
	host,
	resident_id: String,
	option: Dictionary,
) -> void:
	if (
		not bool(option.get("available", false))
		or String(option.get("role", "")) != "visitor"
	):
		return
	var activity_id := String(option.get("activityId", ""))
	var request_spec: Dictionary = host.PLACE_SERVICE_COMMAND_RUNTIME.visitor_occupation_service_spec(
		host,
		resident_id,
		activity_id,
	)
	OCCUPATION_SERVICE_ACTIVITY_POLICY.apply_visitor_availability(
		option,
		(
			DINING_SERVICE.collect_disabled_reason(
				host,
				resident_id,
				int(host._environment.get_absolute_minute()),
			)
			if activity_id == "activity_dining_collect_meal"
			else ""
		),
		CLINIC_CONTINUITY.visitor_service_is_staffed(
			host,
			activity_id,
			request_spec,
		),
	)


static func apply_communal_simple_meal(
	host,
	resident: Dictionary,
	option: Dictionary,
) -> void:
	if String(option.get("activityId", "")) != DINING_SERVICE.SIMPLE_MEAL_ACTIVITY_ID:
		return
	var absolute_minute := int(host._environment.get_absolute_minute())
	var available := DINING_SERVICE.communal_simple_meal_available(
		host,
		resident,
		absolute_minute,
	)
	option["available"] = available
	option["disabledReason"] = (
		""
		if available
		else DINING_SERVICE.communal_simple_meal_disabled_reason(
			host,
			resident,
			absolute_minute,
		)
	)


static func apply_dining_meal_state(
	host,
	option: Dictionary,
) -> void:
	if String(option.get("activityId", "")) not in [
		"activity_dining_eat_meal",
		"activity_dining_return_dishes",
	]:
		return
	if host.work_domain.meal_period_is_prepared(
		int(host._environment.get_absolute_minute()),
	):
		return
	option["available"] = false
	option["disabledReason"] = "DINING_MEAL_NOT_READY"


static func apply_clinic_continuity(
	host,
	resident: Dictionary,
	option: Dictionary,
) -> void:
	CLINIC_CONTINUITY.apply_activity_availability(
		host,
		resident,
		option,
	)


static func apply_public_place_continuity(
	host,
	option: Dictionary,
) -> void:
	PUBLIC_PLACE_CONTINUITY.apply_activity_availability(
		host,
		option,
	)


static func apply_work_task(
	host,
	resident_id: String,
	resident: Dictionary,
	option: Dictionary,
) -> void:
	if (
		not bool(option.get("available", false))
		or String(option.get("role", "")) != "worker"
	):
		return
	var activity_id := String(option.get("activityId", ""))
	if work_task_available(host, resident_id, resident, activity_id, "worker"):
		return
	option["available"] = false
	option["disabledReason"] = "WORK_TASK_REQUIRED"


static func work_task_available(
	host,
	resident_id: String,
	resident: Dictionary,
	activity_id: String,
	role: String,
) -> bool:
	if role != "worker":
		return true
	var capabilities: Array = host._work.tasks.capabilities_for_activity(activity_id)
	if capabilities.is_empty():
		return true
	var occupation_id: String = host.OCCUPATION_RESIDENT_CONTEXT_RUNTIME.id_for_activity(host,
		resident_id,
		activity_id,
	)
	var tasks := host._work.tasks.tasks_for_activity(
		occupation_id,
		activity_id,
		resident_id,
	) as Array
	tasks = host._work.available_work_tasks(tasks, host.resident_registry.records)
	if tasks.is_empty():
		return false
	var candidates := host._activity_runtime.query_preflight_candidates(
		host.OCCUPATION_RESIDENT_CONTEXT_RUNTIME.activity_social_state(host, resident_id, activity_id),
		String(resident.get("currentPlace", "")),
		activity_id,
	) as Array
	return not host.ACTIVITY_SCALARS.matching_work_tasks_for_targets(
		tasks,
		host.ACTIVITY_SCALARS.activity_candidate_physical_targets(candidates),
	).is_empty()


static func apply_bulletin(
	host,
	resident_id: String,
	option: Dictionary,
) -> void:
	if not bool(option.get("available", false)):
		return
	var activity_id := String(option.get("activityId", ""))
	var available := bulletin_available(host, resident_id, activity_id)
	var disabled_reason := ""
	if activity_id == SOCIAL_JUDGMENTS.BULLETIN_READ_ACTIVITY_ID:
		if not available:
			disabled_reason = "BULLETIN_NOTHING_UNREAD"
	elif activity_id == SOCIAL_JUDGMENTS.BULLETIN_PUBLISH_ACTIVITY_ID:
		if not available:
			disabled_reason = "BULLETIN_NO_CONFIRMED_POST"
	else:
		return
	option["available"] = available
	option["disabledReason"] = disabled_reason


static func bulletin_available(
	host,
	resident_id: String,
	activity_id: String,
) -> bool:
	if activity_id == SOCIAL_JUDGMENTS.BULLETIN_READ_ACTIVITY_ID:
		return (
			host.announcement_unread_count(resident_id) > 0
			or host.SOCIAL_GOAL_MATCHING_RUNTIME.has_active_capability(host, resident_id, "bulletin.read")
		)
	if activity_id == SOCIAL_JUDGMENTS.BULLETIN_PUBLISH_ACTIVITY_ID:
		return (
			host.SOCIAL_GOAL_MATCHING_RUNTIME.has_active_capability(host, resident_id, "bulletin.publish")
			or not host.WORK_TASK_PUBLIC_RUNTIME.natural_bulletin_task_for_resident(host, resident_id).is_empty()
		)
	return true


static func interrupt_unsafe_weather(host) -> void:
	if host._activity_runtime == null:
		return
	var resident_ids: Array[String] = []
	for resident_id_value: Variant in host.resident_registry.order:
		resident_ids.append(String(resident_id_value))
	for resident_id in resident_ids:
		if not host.resident_registry.records.has(resident_id):
			continue
		var resident := host.resident_registry.records[resident_id] as Dictionary
		var action := resident.get("currentAction", {}) as Dictionary
		if action.is_empty():
			continue
		var execution := host._activity_runtime.execution_for_action(
			resident_id,
			String(action.get("action_id", "")),
		) as Dictionary
		if execution.is_empty():
			continue
		var availability := host._activity_runtime.activity_weather_availability(
			String(execution.get("activityId", "")),
			String(execution.get("placeId", "")),
			String(execution.get("role", "")),
			host.get_weather(),
		) as Dictionary
		if bool(availability.get("available", true)):
			continue
		var reason := String(
			availability.get("reason", "当前天气不适合继续这项活动。"),
		).strip_edges()
		if reason.is_empty():
			reason = "当前天气不适合继续这项活动。"
		host.ACTION_SETTLEMENT_RUNTIME.interrupt(host, resident_id, reason)
