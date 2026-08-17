class_name TownCustomerServiceWaitRuntime
extends RefCounted

const ACTION_SETTLEMENT_RUNTIME := preload(
	"res://world/runtime/action/TownActionSettlementRuntime.gd"
)
const ROUTINE_SETTLEMENT_RUNTIME := preload(
	"res://world/runtime/activity/TownActivityRoutineSettlementRuntime.gd"
)


static func can_begin(
	request: Dictionary,
	resident: Dictionary,
	place_id: String,
	context: Dictionary,
) -> bool:
	return (
		String(context.get("customerServiceMode", "")) == "onsite_wait"
		and String(request.get("state", "")) in ["pending", "waiting"]
		and not resident.is_empty()
		and String(resident.get("currentPlace", "")) == place_id
		and (resident.get("currentAction", {}) as Dictionary).is_empty()
	)


static func resident_is_waiting_for_active_onsite_service(
	host,
	resident_id: String,
) -> bool:
	var resident := host.resident_registry.records.get(resident_id, {}) as Dictionary
	var action := resident.get("currentAction", {}) as Dictionary
	var request_id := String(action.get("serviceRequestId", ""))
	if String(action.get("type", "")) != "待着" or request_id.is_empty():
		return false
	var request := host._work.services.request(request_id) as Dictionary
	return (
		String(request.get("state", "")) in ["pending", "waiting", "in_progress"]
		and String((request.get("context", {}) as Dictionary).get(
			"customerServiceMode", "",
		)) == "onsite_wait"
	)


static func install(
	resident: Dictionary,
	request_id: String,
	context: Dictionary,
	absolute_minute: int,
) -> void:
	resident["currentAction"] = {
		"type": "待着",
		"action_id": "service-wait:%s" % request_id,
		"line": "在这里等待服务",
		"startedAbsoluteMinute": absolute_minute,
		"completeAbsoluteMinute": int(
			context.get("onsiteWaitUntilMinute", absolute_minute + 30),
		),
		"serviceRequestId": request_id,
	}
	(resident.get("usedActionIds", {}) as Dictionary)[
		"service-wait:%s" % request_id
	] = true
	resident["doing"] = "正在等待服务"


static func begin(
	host,
	resident_id: String,
	request_id: String,
	place_id: String,
	context: Dictionary,
) -> void:
	var request := host._work.services.request(request_id) as Dictionary
	var resident := host.resident_registry.records.get(resident_id, {}) as Dictionary
	if not can_begin(request, resident, place_id, context):
		return
	# 服务请求经常在访客动作的 completed 回调中创建。切换到现场等待前，
	# 先把尚未派发的上一条动作结果放回事实队列。
	if bool(resident.get("decisionPending", false)):
		host._agent_wake_preparation_runtime.clear_resident(
			String(resident.get("residentId", resident_id)),
			String(resident.get("validDecisionId", "")),
		)
		host.RESIDENT_EVENT_QUEUE_RUNTIME.restore_inflight_facts(resident)
		resident["decisionPending"] = false
		resident["validDecisionId"] = ""
		resident["pendingWake"] = {}
		resident["wakeDispatchQueued"] = false
	install(
		resident,
		request_id,
		context,
		host._authoritative_absolute_minute(),
	)
	host._bump_world_revision(false)
	host._emit_resident_state_changed(resident_id)


static func onsite_queue_is_advancing(
	host,
	request: Dictionary,
) -> bool:
	var task: Dictionary = host._work.service_task(request)
	var assigned_resident_id := String(task.get("assignedResidentId", ""))
	if assigned_resident_id.is_empty():
		return false
	if host.ACTION_SUPPORT.resident_is_heading_to_service_request(host,
		assigned_resident_id,
		request,
	):
		return true
	var projected_tasks: Array[Dictionary] = host.get_work_tasks_for_resident(
		assigned_resident_id,
	)
	var active_task_ids: Dictionary = {}
	for projected_task: Dictionary in projected_tasks:
		var task_id := String(projected_task.get("task_id", ""))
		if host.WORK_TASK_PUBLIC_RUNTIME.resident_is_actively_processing(host,
			assigned_resident_id,
			task_id,
		):
			active_task_ids[task_id] = true
	return host._work.onsite_service_queue_is_advancing(
		request,
		projected_tasks,
		active_task_ids,
	)


static func wait_deadline_applies(host, request: Dictionary) -> bool:
	var task_id := String(request.get("taskId", ""))
	var task: Dictionary = host._work.service_task(request)
	var assigned_resident_id := String(task.get("assignedResidentId", ""))
	return host._work.occupation_service_wait_deadline_applies(
		request,
		host.CLINIC_SERVICE_COORDINATION_RUNTIME.request_has_active_execution(host, request),
		host.WORK_TASK_PUBLIC_RUNTIME.resident_is_actively_processing(host,
			assigned_resident_id,
			task_id,
		),
		host.ACTION_SUPPORT.resident_is_heading_to_service_request(host,
			assigned_resident_id,
			request,
		),
	)


static func finish(
	host,
	resident_id: String,
	request_id: String,
	reason: String,
	resume_activity_routine: bool,
) -> void:
	var resident := host.resident_registry.records.get(resident_id, {}) as Dictionary
	var action := resident.get("currentAction", {}) as Dictionary
	if (
		String(action.get("type", "")) != "待着"
		or String(action.get("serviceRequestId", "")) != request_id
	):
		return
	ACTION_SETTLEMENT_RUNTIME.finish(host, resident_id, reason)
	if resume_activity_routine:
		ROUTINE_SETTLEMENT_RUNTIME.continue_routine(host, resident_id)
	elif host.activity_routine_state.records.has(resident_id):
		ROUTINE_SETTLEMENT_RUNTIME.close_routine(
			host, resident_id, "interrupted", reason,
		)
