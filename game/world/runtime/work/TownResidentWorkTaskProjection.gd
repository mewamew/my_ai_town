class_name TownResidentWorkTaskProjection
extends RefCounted


const ACTION_SUPPORT := preload(
	"res://world/runtime/action/TownActionSupport.gd"
)
const DINING_SERVICE := preload(
	"res://world/runtime/work/TownDiningServiceRuntime.gd"
)


static func query(
	resident_id: String,
	occupation_ids: Array[String],
	work_tasks: TownWorkTaskRuntime,
	cargo_inventory: TownCargoInventoryRuntime,
	private_messages: TownPrivateMessageRuntime,
	occupation_services: TownOccupationServiceRuntime,
	clinic_interviews: TownClinicInterviewPolicy,
	residents: Dictionary,
	resident_names: Dictionary,
	world_data: Dictionary,
	absolute_minute: int,
	authorized_capabilities: Dictionary = {},
) -> Array[Dictionary]:
	if resident_id.is_empty() or occupation_ids.is_empty():
		return []
	var tasks_by_id := _tasks_by_id(
		resident_id,
		occupation_ids,
		work_tasks,
	)
	var result: Array[Dictionary] = []
	var task_ids: Array[String] = []
	for task_id_value: Variant in tasks_by_id:
		task_ids.append(String(task_id_value))
	task_ids.sort()
	for task_id: String in task_ids:
		var task := tasks_by_id.get(task_id, {}) as Dictionary
		if (
			not (task.get("eligibleResidentIds", []) as Array).has(resident_id)
			and not authorized_capabilities.has(String(task.get("capability", "")))
		):
			continue
		if not _is_currently_available(
			task,
			occupation_services,
			residents,
		):
			continue
		result.append(_project_task(
			task,
			cargo_inventory,
			private_messages,
			occupation_services,
			clinic_interviews,
			residents,
			resident_names,
			world_data,
			absolute_minute,
		))
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_priority := int(left.get("priority", 0))
		var right_priority := int(right.get("priority", 0))
		if left_priority != right_priority:
			return left_priority > right_priority
		return String(left.get("task_id", "")) < String(
			right.get("task_id", ""),
		)
	)
	return result


static func _tasks_by_id(
	resident_id: String,
	occupation_ids: Array[String],
	work_tasks: TownWorkTaskRuntime,
) -> Dictionary:
	var result: Dictionary = {}
	for occupation_id: String in occupation_ids:
		for value: Variant in work_tasks.tasks_for_occupation(
			occupation_id,
			resident_id,
		) as Array:
			var task := value as Dictionary
			result[String(task.get("taskId", ""))] = task
	for value: Variant in work_tasks.tasks_for_resident(resident_id) as Array:
		var task := value as Dictionary
		result[String(task.get("taskId", ""))] = task
	return result


static func _is_currently_available(
	task: Dictionary,
	occupation_services: TownOccupationServiceRuntime,
	residents: Dictionary,
) -> bool:
	var request := occupation_services.request(
		String(task.get("sourceRef", "")),
	) as Dictionary
	if request.is_empty():
		return true
	if String(request.get("state", "")) in ["completed", "cancelled"]:
		return false
	if not ACTION_SUPPORT.occupation_service_request_requires_presence(request):
		return true
	var requester := residents.get(
		String(request.get("requesterResidentId", "")),
		{},
	) as Dictionary
	return (
		not requester.is_empty()
		and String(requester.get("currentPlace", ""))
		== String(request.get("placeId", ""))
	)


static func _project_task(
	task: Dictionary,
	cargo_inventory: TownCargoInventoryRuntime,
	private_messages: TownPrivateMessageRuntime,
	occupation_services: TownOccupationServiceRuntime,
	clinic_interviews: TownClinicInterviewPolicy,
	residents: Dictionary,
	resident_names: Dictionary,
	world_data: Dictionary,
	absolute_minute: int,
) -> Dictionary:
	var projected := {
		"task_id": String(task.get("taskId", "")),
		"capability": String(task.get("capability", "")),
		"source_kind": String(task.get("sourceKind", "")),
		"source_ref": String(task.get("sourceRef", "")),
		"targets": _public_targets(
			task.get("targets", []) as Array,
			world_data,
		),
		"expected_result": String(task.get("requestedResultKind", "")),
		"state": String(task.get("state", "")),
		"priority": int(task.get("priority", 0)),
		"process_stage": String(task.get("processStage", "ready")),
	}
	_decorate_cargo(task, projected, cargo_inventory)
	_decorate_message(
		task,
		projected,
		private_messages,
		residents,
		resident_names,
	)
	DINING_SERVICE.decorate_projected_meal_task(
		task,
		projected,
		absolute_minute,
	)
	_decorate_service_request(
		task,
		projected,
		occupation_services,
		clinic_interviews,
		residents,
		resident_names,
	)
	return projected


static func _public_targets(
	targets: Array,
	world_data: Dictionary,
) -> Array[Dictionary]:
	var region_places: Dictionary = {}
	for region_value: Variant in world_data.get(
		"perceptionRegions",
		[],
	) as Array:
		var region := region_value as Dictionary
		region_places[String(region.get("id", ""))] = String(
			region.get("placeName", region.get("id", "")),
		)
	var result: Array[Dictionary] = []
	for value: Variant in targets:
		var target := (value as Dictionary).duplicate(true)
		if String(target.get("kind", "")) in ["region", "audience_area"]:
			var region_id := String(target.get("ref", ""))
			if region_places.has(region_id):
				target["ref"] = String(region_places.get(region_id, region_id))
		result.append(target)
	return result


static func _decorate_cargo(
	task: Dictionary,
	projected: Dictionary,
	cargo_inventory: TownCargoInventoryRuntime,
) -> void:
	if String(task.get("capability", "")) != "cargo.deliver":
		return
	var lot := cargo_inventory.cargo_lot(
		String(task.get("sourceRef", "")),
	) as Dictionary
	if lot.is_empty():
		return
	var cargo_state := String(lot.get("state", ""))
	var next_place := (
		String(lot.get("destinationPlaceId", ""))
		if cargo_state == "in_transit"
		else String(lot.get("sourcePlaceId", ""))
	)
	projected["next_step"] = {
		"place_id": next_place,
		"instruction": (
			"把已经领取的货送到%s" % next_place
			if cargo_state == "in_transit"
			else "先到%s领取货批" % next_place
		),
	}


static func _decorate_message(
	task: Dictionary,
	projected: Dictionary,
	private_messages: TownPrivateMessageRuntime,
	residents: Dictionary,
	resident_names: Dictionary,
) -> void:
	var source_ref := String(task.get("sourceRef", ""))
	if (
		String(task.get("sourceKind", "")) not in [
			"resident_message",
			"formal_notice",
		]
		or String(task.get("processStage", "")) != "out_for_delivery"
		or not private_messages.has(source_ref)
	):
		return
	var message := private_messages.message(source_ref)
	var sender_id := String(message.get("senderResidentId", ""))
	var recipient_id := String(message.get("recipientResidentId", ""))
	var recipient := residents.get(recipient_id, {}) as Dictionary
	projected["message"] = {
		"kind": String(message.get("messageKind", "private")),
		"announcement_id": String(message.get("announcementId", "")),
		"sender_resident_id": sender_id,
		"sender_name": String(resident_names.get(sender_id, "")),
		"recipient_resident_id": recipient_id,
		"recipient_name": String(resident_names.get(recipient_id, "")),
		"recipient_current_place": String(recipient.get("currentPlace", "")),
		"content": String(message.get("content", "")),
	}
	projected["next_step"] = {
		"place_id": String(recipient.get("currentPlace", "")),
		"instruction": "前往收件人所在处，并当面对收件人说出原文",
	}


static func _decorate_service_request(
	task: Dictionary,
	projected: Dictionary,
	occupation_services: TownOccupationServiceRuntime,
	clinic_interviews: TownClinicInterviewPolicy,
	residents: Dictionary,
	resident_names: Dictionary,
) -> void:
	var request := occupation_services.request(
		String(task.get("sourceRef", "")),
	) as Dictionary
	if request.is_empty():
		return
	var requester_id := String(request.get("requesterResidentId", ""))
	var requester := residents.get(requester_id, {}) as Dictionary
	var projected_request := {
		"request_id": String(request.get("requestId", "")),
		"kind": String(request.get("kind", "")),
		"requester_resident_id": requester_id,
		"requester_name": String(resident_names.get(requester_id, "")),
		"requester_current_place": String(requester.get("currentPlace", "")),
		"subject_ref": String(request.get("subjectRef", "")),
		"item_id": String(request.get("itemId", "")),
		"place_id": String(request.get("placeId", "")),
		"state": String(request.get("state", "")),
		"wait_reason": String(request.get("waitReason", "")),
	}
	var medical_interview := (
		request.get("context", {}) as Dictionary
	).get("medicalInterview", {}) as Dictionary
	if not medical_interview.is_empty():
		projected_request["medical_dialogue"] = (
			clinic_interviews.projection_for_role(
				medical_interview,
				"clinician",
			) as Dictionary
		).duplicate(true)
	projected["service_request"] = projected_request
	projected["next_step"] = {
		"place_id": String(request.get("placeId", "")),
		"instruction": "到服务地点处理这位顾客的真实请求",
	}
