class_name TownOccupationServiceCancellationRuntime
extends RefCounted


const CONVERSATION_RUNTIME := preload(
	"res://world/runtime/conversation/TownConversationRuntime.gd"
)
const SOCIAL_MATTER_COMMAND_RUNTIME := preload(
	"res://world/runtime/social/TownSocialMatterCommandRuntime.gd"
)


static func pause_absent(host, request: Dictionary) -> void:
	var plan: Dictionary = host._work.absent_service_pause_plan(
		request,
		host.activity_work_task_bindings.snapshot(),
	)
	if plan.is_empty():
		return
	var assigned_id := String(plan.get("assignedResidentId", ""))
	if not assigned_id.is_empty():
		var binding_keys := plan.get("bindingKeys", []) as Array
		if not binding_keys.is_empty():
			host.ACTION_SETTLEMENT_RUNTIME.interrupt(host, assigned_id, "顾客已经离开，服务暂时停下")
	host._work.commit_absent_service_pause(request)


static func cancel(host, request: Dictionary, reason: String) -> void:
	var plan := host._work.occupation_service_cancellation_plan(
		request,
		host.activity_work_task_bindings.snapshot(),
		host.conversation_state.records,
	) as Dictionary
	var conversation_id := String(plan.get("medicalConversationId", ""))
	if not conversation_id.is_empty():
		CONVERSATION_RUNTIME._end_conversation(
			host,
			host._traveler_relationship_state,
			conversation_id,
			"无法继续",
			"interrupted",
		)
	var assigned_id := String(plan.get("assignedResidentId", ""))
	for binding_value: Variant in plan.get("bindingKeys", []) as Array:
		var assigned_action := (
			host.resident_registry.records.get(assigned_id, {}) as Dictionary
		).get("currentAction", {}) as Dictionary
		if not assigned_action.is_empty():
			host.ACTION_SETTLEMENT_RUNTIME.interrupt(host, assigned_id, reason)
		host.activity_work_task_bindings.erase_key(String(binding_value))
	var request_id := String(plan.get("requestId", ""))
	host._work.commit_occupation_service_cancellation(request_id, reason)
	if bool(plan.get("placeService", false)):
		host.record_place_service_request(
			String(plan.get("placeId", "")),
			request_id,
			false,
		)
	if bool(plan.get("preorder", false)):
		host.PRIVATE_MESSAGE_DELIVERY_RUNTIME.cancel_for_source(host, "preorder:%s" % request_id, reason)
		SOCIAL_MATTER_COMMAND_RUNTIME.close_resident_request_source(
			host,
			"preorder-pickup:%s" % request_id,
			"preorder-cancelled",
		)
	host.CUSTOMER_SERVICE_WAIT_RUNTIME.finish(host,
		String(plan.get("requesterResidentId", "")),
		request_id,
		"没有等到服务，这次请求已经取消",
		false,
	)
	if not assigned_id.is_empty() and host.resident_registry.records.has(assigned_id):
		host._schedule_decision(assigned_id, true)
