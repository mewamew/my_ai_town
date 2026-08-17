class_name TownOccupationServicePresenceAdvancementRuntime
extends RefCounted


const DINING_SERVICE := preload(
	"res://world/runtime/work/TownDiningServiceRuntime.gd"
)
const CONTENT_CATALOG := preload(
	"res://world/data/town/TownWorkContentCatalog.gd"
)


static func schedule_worker(host, request: Dictionary) -> void:
	var context: Dictionary = host._work.service_worker_schedule_context(
		request,
		host.PRIORITY_INTERRUPT_THRESHOLD,
	)
	var task_id := String(context.get("taskId", ""))
	var can_interrupt := bool(context.get("canInterrupt", false))
	var assigned_resident_id := String(context.get("assignedResidentId", ""))
	if not assigned_resident_id.is_empty():
		if host.WORK_TASK_PUBLIC_RUNTIME.resident_is_actively_processing(host,
			assigned_resident_id,
			task_id,
		):
			return
		host._schedule_decision(
			assigned_resident_id, can_interrupt, false, can_interrupt,
		)
		return
	var occupation_id := String(context.get("occupationId", ""))
	if occupation_id.is_empty():
		return
	for resident_id: String in host.resident_registry.order:
		if host.OCCUPATION_RESIDENT_CONTEXT_RUNTIME.can_work_occupation(host, resident_id, occupation_id):
			host._schedule_decision(
				resident_id, can_interrupt, false, can_interrupt,
			)


static func sync(host, absolute_minute: int) -> void:
	for request: Dictionary in host._work.active_presence_requests():
		var kind := String(request.get("kind", ""))
		var mode: String = host._work.occupation_service_presence_mode(
			request,
			absolute_minute,
		)
		var plan := host._work.evaluate_presence_plan(
			request,
			host.resident_registry.records.get(String(request.get("requesterResidentId", "")), {}) as Dictionary,
			absolute_minute,
			host.resident_registry.records,
			host.CLINIC_SERVICE_COORDINATION_RUNTIME.request_has_executable_practitioner(host, request) if kind == "clinic" else true,
			(
				host.CUSTOMER_SERVICE_WAIT_RUNTIME.onsite_queue_is_advancing(host, request)
				if mode == "onsite_wait" and kind != "dining_order"
				else false
			),
			host.CUSTOMER_SERVICE_WAIT_RUNTIME.wait_deadline_applies(host, request) if mode == "onsite_wait" else false,
		) as Dictionary
		match String(plan.get("action", "")):
			"schedule_worker":
				schedule_worker(host, request)
			"notify_preorder":
				host.SERVICE_READY_NOTIFICATION_RUNTIME.maybe_notify_preorder(host, request, absolute_minute)
			"takeaway":
				DINING_SERVICE.complete_as_takeaway(
					host,
					request,
					absolute_minute,
					"等待超过半小时，已经领取打包餐",
				)
			"pause":
				host.OCCUPATION_SERVICE_CANCELLATION_RUNTIME.pause_absent(host, request)
			"pause_and_cancel":
				host.OCCUPATION_SERVICE_CANCELLATION_RUNTIME.pause_absent(host, request)
				host.OCCUPATION_SERVICE_CANCELLATION_RUNTIME.cancel(host,
					request,
					String(plan.get("cancelReason", "")),
				)
			"cancel":
				host.OCCUPATION_SERVICE_CANCELLATION_RUNTIME.cancel(host,
					request,
					String(plan.get("cancelReason", "")),
				)


static func activate_waiting_dining_orders(host) -> void:
	var now := int(host._environment.get_absolute_minute())
	if not host._work.meal_service_is_open(now) or not host._work.meal_period_is_prepared(now):
		return
	for request_value: Variant in (
		host._work.services.snapshot() as Dictionary
	).get("requests", []) as Array:
		var request := request_value as Dictionary
		if (
			String(request.get("kind", "")) != "dining_order"
			or String(request.get("state", "")) != "waiting"
			or String(request.get("waitReason", "")) not in [
				"当前餐次尚未完成备餐",
				"当前餐次尚未开始供餐",
				"食堂当前不在供餐时间",
			]
		):
			continue
		var request_id := String(request.get("requestId", ""))
		var service_result: Dictionary = host.record_place_service_request(
			CONTENT_CATALOG.PLACE_DINING_HALL,
			request_id,
			true,
		)
		if service_result.get("ok") != true:
			continue
		var task := host._work.tasks.active_task_for_source("meal_demand", request_id) as Dictionary
		if task.is_empty():
			continue
		task = host.WORK_TASK_PUBLIC_RUNTIME.reserve(
			host, task, "occupation_dining_operator",
		)
		host._work.services.attach_follow_up_task(request_id, String(task.get("taskId", "")))
		var refreshed_context := (request.get("context", {}) as Dictionary).duplicate(true)
		var wait_until := DINING_SERVICE.wait_deadline(host, now)
		refreshed_context["onsiteWaitUntilMinute"] = wait_until
		refreshed_context["customerAbsentSinceMinute"] = -1
		host._work.services.merge_request_context(
			request_id,
			{"onsiteWaitUntilMinute": wait_until, "customerAbsentSinceMinute": -1},
		)
		host.CUSTOMER_SERVICE_WAIT_RUNTIME.begin(host,
			String(request.get("requesterResidentId", "")),
			request_id,
			CONTENT_CATALOG.PLACE_DINING_HALL,
			refreshed_context,
		)
		schedule_worker(
			host,
			host._work.services.request(request_id) as Dictionary,
		)
