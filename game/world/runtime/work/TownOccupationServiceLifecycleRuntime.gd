class_name TownOccupationServiceLifecycleRuntime
extends RefCounted


static func matching_binding_keys(
	task_id: String,
	assigned_resident_id: String,
	bindings: Dictionary,
) -> Array[String]:
	var result: Array[String] = []
	if task_id.is_empty() or assigned_resident_id.is_empty():
		return result
	for binding_key_value: Variant in bindings:
		var binding_key := String(binding_key_value)
		if (
			String(bindings.get(binding_key, "")) == task_id
			and binding_key.begins_with("%s:" % assigned_resident_id)
		):
			result.append(binding_key)
	result.sort()
	return result


static func pause_after_interruption(
	occupation_services: TownOccupationServiceRuntime,
	work_tasks: TownWorkTaskRuntime,
	request: Dictionary,
) -> void:
	var task := work_tasks.task(
		String(request.get("taskId", "")),
	) as Dictionary
	if task.is_empty():
		return
	var assigned_id := String(task.get("assignedResidentId", ""))
	if (
		not assigned_id.is_empty()
		and String(task.get("state", "")) in ["accepted", "in_progress"]
	):
		work_tasks.release_task(
			String(task.get("taskId", "")),
			assigned_id,
			int(task.get("revision", 0)),
			"请求人尚未到达服务地点",
		)
	occupation_services.mark_waiting(
		String(request.get("requestId", "")),
		"请求人尚未到达服务地点",
	)


static func cancellation_plan(
	request: Dictionary,
	task: Dictionary,
	bindings: Dictionary,
	conversations: Dictionary,
	definition: Dictionary,
) -> Dictionary:
	var medical_interview := (
		request.get("context", {}) as Dictionary
	).get("medicalInterview", {}) as Dictionary
	var conversation_id := String(
		medical_interview.get("conversationId", ""),
	)
	if String(
		(conversations.get(conversation_id, {}) as Dictionary).get(
			"status",
			"",
		),
	) != "active":
		conversation_id = ""
	var task_id := String(task.get("taskId", ""))
	var assigned_id := String(task.get("assignedResidentId", ""))
	return {
		"requestId": String(request.get("requestId", "")),
		"requesterResidentId": String(
			request.get("requesterResidentId", ""),
		),
		"taskId": task_id,
		"assignedResidentId": assigned_id,
		"medicalConversationId": conversation_id,
		"bindingKeys": matching_binding_keys(
			task_id,
			assigned_id,
			bindings,
		),
		"placeService": bool(definition.get("placeService", false)),
		"placeId": String(request.get("placeId", "")),
		"preorder": String(
			(request.get("context", {}) as Dictionary).get(
				"customerServiceMode",
				"",
			),
		) == "preorder",
	}


static func commit_cancellation(
	occupation_services: TownOccupationServiceRuntime,
	work_tasks: TownWorkTaskRuntime,
	request_id: String,
	task: Dictionary,
	reason: String,
) -> void:
	if not task.is_empty() and String(task.get("state", "")) not in [
		"completed",
		"failed",
		"cancelled",
	]:
		work_tasks.cancel_task(String(task.get("taskId", "")), reason)
	occupation_services.cancel_request(request_id, reason)
