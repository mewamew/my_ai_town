class_name TownWorldDomainLogProjection
extends RefCounted


const RUNTIME_LOG_TEXT := preload("res://world/runtime/log/TownRuntimeLogText.gd")
const ACTION_SUPPORT := preload("res://world/runtime/action/TownActionSupport.gd")


static func work_task_event(
	task: Dictionary,
	assigned_resident_name: String,
) -> Dictionary:
	var task_id := String(task.get("taskId", "")).strip_edges()
	var revision := int(task.get("revision", 0))
	if task_id.is_empty() or revision < 1:
		return {}
	var state := String(task.get("state", "open"))
	var payload := {
		"type": RUNTIME_LOG_TEXT.work_task_log_event_type(state, revision),
		"taskId": task_id,
		"taskRevision": revision,
		"status": state,
		"capability": String(task.get("capability", "")),
		"sourceKind": String(task.get("sourceKind", "")),
		"sourceRef": String(task.get("sourceRef", "")),
		"requestedResultKind": String(task.get("requestedResultKind", "")),
		"waitReason": String(task.get("waitReason", "")),
		"targets": (task.get("targets", []) as Array).duplicate(true),
		"result": (task.get("result", {}) as Dictionary).duplicate(true),
	}
	var assigned_resident_id := String(
		task.get("assignedResidentId", ""),
	).strip_edges()
	var participant_ids: Array[String] = []
	if not assigned_resident_id.is_empty():
		participant_ids.append(assigned_resident_id)
	var place_name := ""
	for target_value: Variant in task.get("targets", []) as Array:
		if not target_value is Dictionary:
			continue
		var target := target_value as Dictionary
		var target_kind := String(target.get("kind", ""))
		var target_ref := String(target.get("ref", "")).strip_edges()
		match target_kind:
			"resident":
				_append_unique_id(participant_ids, target_ref)
			"service_request":
				payload["requestId"] = target_ref
			"cargo_lot":
				payload["cargoLotId"] = target_ref
			"public_matter":
				payload["matterId"] = target_ref
			"place", "region", "route", "audience_area":
				if place_name.is_empty():
					place_name = target_ref
	ACTION_SUPPORT.apply_work_task_log_associations(payload, task)
	payload["participantIds"] = participant_ids
	return _event(
		"work-task:%s:revision:%d" % [task_id, revision],
		"work_task",
		assigned_resident_id,
		assigned_resident_name,
		place_name,
		payload,
	)


static func cargo_event(
	event_type: String,
	lot: Dictionary,
	actor_resident_id: String,
	actor_name: String,
	carrier_name: String,
	status: String,
) -> Dictionary:
	var lot_id := String(lot.get("lotId", "")).strip_edges()
	if lot_id.is_empty():
		return {}
	var carrier_resident_id := String(lot.get("carrierResidentId", ""))
	var participant_ids: Array[String] = []
	_append_unique_id(participant_ids, actor_resident_id)
	_append_unique_id(participant_ids, carrier_resident_id)
	var source_place_id := String(lot.get("sourcePlaceId", ""))
	var destination_place_id := String(lot.get("destinationPlaceId", ""))
	return _event(
		"",
		"cargo_event",
		actor_resident_id,
		actor_name,
		destination_place_id if event_type in ["货批到货", "货批入库"] else source_place_id,
		{
			"type": event_type,
			"cargoLotId": lot_id,
			"status": status,
			"participantIds": participant_ids,
			"itemId": String(lot.get("itemId", "")),
			"quantity": int(lot.get("quantity", 0)),
			"sourcePlaceId": source_place_id,
			"destinationPlaceId": destination_place_id,
			"carrierResidentId": carrier_resident_id,
			"carrierName": carrier_name,
			"cargoState": String(lot.get("state", "")),
		},
	)


static func service_event(
	request: Dictionary,
	task: Dictionary,
	worker_resident_id: String,
	worker_name: String,
	requester_name: String,
	status: String,
	outcome: Dictionary,
) -> Dictionary:
	var request_id := String(request.get("requestId", "")).strip_edges()
	if request_id.is_empty():
		return {}
	var service_kind := String(request.get("kind", "")).strip_edges()
	var requester_id := String(request.get("requesterResidentId", "")).strip_edges()
	var participant_ids: Array[String] = []
	_append_unique_id(participant_ids, requester_id)
	_append_unique_id(participant_ids, worker_resident_id)
	var audience_value: Variant = outcome.get("audienceResidentIds", [])
	if audience_value is Array:
		for resident_id_value: Variant in audience_value as Array:
			_append_unique_id(participant_ids, String(resident_id_value))
	return _event(
		"",
		"service_result",
		worker_resident_id,
		worker_name,
		String(request.get("placeId", "")),
		{
			"type": RUNTIME_LOG_TEXT.service_log_event_type(service_kind),
			"requestId": request_id,
			"taskId": String(task.get("taskId", "")),
			"serviceKind": service_kind,
			"status": status,
			"participantIds": participant_ids,
			"requesterResidentId": requester_id,
			"requesterName": requester_name,
			"workerResidentId": worker_resident_id,
			"workerName": worker_name,
			"itemId": String(request.get("itemId", "")),
			"outcome": outcome.duplicate(true),
		},
	)


static func private_message_event(
	event_type: String,
	message: Dictionary,
	status: String,
	delivered_by_resident_id: String,
	sender_name: String,
	recipient_name: String,
	delivered_by_name: String,
) -> Dictionary:
	var message_id := String(message.get("messageId", "")).strip_edges()
	if message_id.is_empty():
		return {}
	var sender_id := String(message.get("senderResidentId", ""))
	var recipient_id := String(message.get("recipientResidentId", ""))
	var participant_ids: Array[String] = []
	_append_unique_id(participant_ids, sender_id)
	_append_unique_id(participant_ids, recipient_id)
	_append_unique_id(participant_ids, delivered_by_resident_id)
	return _event(
		"",
		"private_message",
		sender_id,
		sender_name,
		"",
		{
			"type": event_type,
			"messageId": message_id,
			"taskId": String(message.get("taskId", "")),
			"status": status,
			"participantIds": participant_ids,
			"senderResidentId": sender_id,
			"senderName": sender_name,
			"recipientResidentId": recipient_id,
			"recipientName": recipient_name,
			"deliveredByResidentId": delivered_by_resident_id,
			"deliveredByName": delivered_by_name,
			"content": String(message.get("content", "")),
			"messageKind": String(message.get("messageKind", "private")),
			"announcementId": String(message.get("announcementId", "")),
			"sourceRef": String(message.get("sourceRef", "")),
			"reason": String(message.get("reason", "")),
		},
	)


static func animal_event(
	event_type: String,
	fact: Dictionary,
	actor_resident_id: String,
	actor_name: String,
) -> Dictionary:
	var animal_id := String(fact.get("animal_id", "")).strip_edges()
	if animal_id.is_empty():
		return {}
	return _event(
		"",
		"animal_event",
		actor_resident_id,
		actor_name,
		String(fact.get("place_id", "")),
		{
			"type": event_type,
			"animalId": animal_id,
			"animalName": String(fact.get("display_name", "")).strip_edges(),
			"species": String(fact.get("species", "")),
			"exists": bool(fact.get("exists", false)),
			"placeId": String(fact.get("place_id", "")),
			"generation": int(fact.get("generation", 0)),
			"publicAttention": bool(fact.get("public_attention", false)),
			"status": "completed",
		},
	)


static func social_matter_event(
	matter: Dictionary,
	creator_name: String,
) -> Dictionary:
	var matter_id := String(matter.get("matter_id", "")).strip_edges()
	var revision := int(matter.get("revision", 0))
	if matter_id.is_empty() or revision < 1:
		return {}
	var participant_ids: Array[String] = []
	_append_unique_id(participant_ids, String(matter.get("creator_id", "")))
	for resident_id_value: Variant in matter.get("subject_ids", []) as Array:
		_append_unique_id(participant_ids, String(resident_id_value))
	for resident_id_value: Variant in (
		matter.get("participants", {}) as Dictionary
	).keys():
		_append_unique_id(participant_ids, String(resident_id_value))
	for candidate_value: Variant in matter.get("fixed_candidates", []) as Array:
		if not candidate_value is Dictionary:
			continue
		var candidate := candidate_value as Dictionary
		_append_unique_id(
			participant_ids,
			String(candidate.get("resident_id", candidate.get("residentId", ""))),
		)
	var state := String(matter.get("state", "open"))
	var creator_id := String(matter.get("creator_id", "")).strip_edges()
	return _event(
		"social-matter:%s:revision:%d" % [matter_id, revision],
		"social_matter",
		creator_id,
		creator_name,
		String(matter.get("place_id", "")),
		{
			"type": RUNTIME_LOG_TEXT.social_matter_log_event_type(state, revision),
			"matterId": matter_id,
			"matterKind": String(matter.get("kind", "")),
			"matterRevision": revision,
			"status": (
				"completed"
				if state == "closed"
				else ("waiting" if state == "collecting" else "ongoing")
			),
			"participantIds": participant_ids,
			"attentionLevel": String(matter.get("attention_level", "daily")),
			"reasonSummary": String(matter.get("reason_summary", "")),
			"closeReason": String(matter.get("close_reason", "")),
			"sourceStateRef": (
				matter.get("source_state_ref", {}) as Dictionary
			).duplicate(true),
			"sourceEventIds": (
				matter.get("source_event_ids", []) as Array
			).duplicate(true),
			"resultRefs": (
				matter.get("result_refs", []) as Array
			).duplicate(true),
		},
	)


static func conflict_event(
	event: Dictionary,
	source_actor_name: String,
) -> Dictionary:
	var event_id := String(event.get("eventId", "")).strip_edges()
	var conflict_id := String(
		event.get("rootConflictId", event.get("conflictId", ""))
	).strip_edges()
	var source_type := String(event.get("type", "")).strip_edges()
	if event_id.is_empty() or conflict_id.is_empty() or source_type.is_empty():
		return {}
	var source_actor_id := String(event.get("sourceActorId", "")).strip_edges()
	return _event(
		event_id,
		"conflict_event",
		source_actor_id,
		source_actor_name,
		String(event.get("placeId", "")),
		{
			"type": RUNTIME_LOG_TEXT.conflict_log_event_type(source_type),
			"conflictId": conflict_id,
			"conflictEventType": source_type,
			"status": (
				"completed"
				if source_type in [
					"conflict_apologized",
					"conflict_disengaged",
					"conflict_ended",
				]
				else "ongoing"
			),
			"participantIds": RUNTIME_LOG_TEXT.conflict_event_actor_ids(event),
			"sourceActorId": source_actor_id,
			"subjectId": String(event.get("subjectId", "")),
			"severity": String(event.get("severity", "")),
			"reason": String(event.get("reason", "")),
			"causeId": String(event.get("causeId", "")),
			"causeSummary": String(event.get("causeSummary", "")),
			"sourceConversationId": String(event.get("sourceConversationId", "")),
			"causedByEventIds": (
				event.get("sourceEventIds", []) as Array
			).duplicate(true),
			"occurredAtMinute": int(event.get("occurredAtMinute", -1)),
			"summary": RUNTIME_LOG_TEXT.conflict_log_summary(event),
		},
	)


static func payload_with_participant_snapshots(
	payload: Dictionary,
	resident_id: String,
	resident_name: String,
	resident_names_by_id: Dictionary,
	player_id: String,
	player_name: String,
) -> Dictionary:
	var result := payload.duplicate(true)
	var participant_ids: Array[String] = []
	_append_unique_id(participant_ids, resident_id)
	for key in [
		"participant_resident_ids",
		"participantIds",
		"resident_ids",
	]:
		var values: Variant = result.get(key, [])
		if not values is Array:
			continue
		for value: Variant in values as Array:
			_append_unique_id(participant_ids, String(value))
	var snapshots: Array[Dictionary] = []
	for participant_id: String in participant_ids:
		var display_name := String(resident_names_by_id.get(participant_id, ""))
		if display_name.is_empty() and participant_id == player_id:
			display_name = player_name
		if display_name.is_empty() and participant_id == resident_id:
			display_name = resident_name
		if display_name.is_empty():
			display_name = participant_id
		snapshots.append({
			"residentId": participant_id,
			"displayName": display_name,
		})
	result["participantSnapshots"] = snapshots
	return result


static func _event(
	event_id: String,
	kind: String,
	resident_id: String,
	resident_name: String,
	place_name: String,
	payload: Dictionary,
) -> Dictionary:
	return {
		"eventId": event_id,
		"kind": kind,
		"residentId": resident_id,
		"residentName": resident_name,
		"placeName": place_name,
		"payload": payload,
	}


static func _append_unique_id(target: Array[String], value: String) -> void:
	var normalized := value.strip_edges()
	if not normalized.is_empty() and not target.has(normalized):
		target.append(normalized)
