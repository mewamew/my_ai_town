class_name TownDiningOrderCoordinationRuntime
extends RefCounted


const OCCUPATION_SERVICE_REQUEST_RUNTIME := preload(
	"res://world/runtime/work/TownOccupationServiceRequestRuntime.gd"
)
const PRODUCTION_TASK_COORDINATION_RUNTIME := preload(
	"res://world/runtime/work/TownProductionTaskCoordinationRuntime.gd"
)
const OCCUPATION_SERVICE_PRESENCE_ADVANCEMENT_RUNTIME := preload(
	"res://world/runtime/work/TownOccupationServicePresenceAdvancementRuntime.gd"
)


static func reuse_existing(
	host,
	requester_id: String,
	request_now: int,
) -> Dictionary:
	var existing_meal_order: Dictionary = (
		host._work.dining_order_for_resident_meal_period(
			requester_id,
			request_now,
			["pending", "waiting", "in_progress"],
		)
	)
	if existing_meal_order.is_empty():
		return {}
	var existing_request_id := String(existing_meal_order.get("requestId", ""))
	if String(existing_meal_order.get("state", "")) in [
		"pending",
		"waiting",
		"in_progress",
	]:
		host.CUSTOMER_SERVICE_WAIT_RUNTIME.begin(host,
			requester_id,
			existing_request_id,
			String(existing_meal_order.get("placeId", "")),
			existing_meal_order.get("context", {}) as Dictionary,
		)
		OCCUPATION_SERVICE_PRESENCE_ADVANCEMENT_RUNTIME.schedule_worker(
			host, existing_meal_order,
		)
	return host._decorate_command_result(
		OCCUPATION_SERVICE_REQUEST_RUNTIME.reused_dining_order(
			host._work.tasks,
			existing_meal_order,
		),
	)


static func hold_until_service(
	host,
	request_id: String,
	requester_id: String,
	request_context: Dictionary,
	definition: Dictionary,
	now: int,
) -> Dictionary:
	PRODUCTION_TASK_COORDINATION_RUNTIME.sync_meal_period(host, now)
	var wait_reason := (
		"食堂当前不在供餐时间"
		if host._work.meal_period_for_minute(now).is_empty()
		else (
			"当前餐次尚未开始供餐"
			if not host._work.meal_service_is_open(now)
			else "当前餐次尚未完成备餐"
		)
	)
	var result: Dictionary = OCCUPATION_SERVICE_REQUEST_RUNTIME.hold_dining_order(
		host._work.services,
		host._work.tasks,
		request_id,
		wait_reason,
		"meal-preparation:%s" % host._work.meal_period_source_ref(now),
	)
	result["task"] = host.WORK_TASK_PUBLIC_RUNTIME.reserve(
		host,
		result.get("task", {}) as Dictionary,
		"occupation_dining_operator",
	)
	host.CUSTOMER_SERVICE_WAIT_RUNTIME.begin(host,
		requester_id,
		request_id,
		String(definition.get("placeId", "")),
		request_context,
	)
	host.CARGO_COMMAND_RUNTIME.schedule_occupation_decisions(
		host, "occupation_dining_operator",
	)
	return host._decorate_command_result(result)
