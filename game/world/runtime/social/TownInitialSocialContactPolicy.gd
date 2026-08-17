class_name TownInitialSocialContactPolicy
extends RefCounted


static func source_id(method: String, source_state: Dictionary) -> String:
	for event_value: Variant in source_state.get("source_event_ids", []) as Array:
		if event_value is String:
			var event_id := String(event_value).strip_edges()
			if not event_id.is_empty():
				return event_id
	if method == "sync_place_service_pressure":
		return String(source_state.get("pressure_id", ""))
	if method == "sync_job_vacancy":
		return String(source_state.get("vacancy_id", ""))
	return String(source_state.get(
		"request_id",
		source_state.get("animal_id", ""),
	))


static func source_resident_ids(
	method: String,
	source_state: Dictionary,
	include_creator: bool,
	resident_order: Array[String],
	residents: Dictionary,
	resident_id_by_name: Dictionary,
) -> Array[String]:
	var result: Array[String] = []
	var place_id := String(source_state.get("place_id", ""))
	if method in ["sync_place_service_pressure", "sync_animal_attention"]:
		for resident_id: String in resident_order:
			if String((residents.get(resident_id, {}) as Dictionary).get(
				"currentPlace",
				"",
			)) == place_id:
				result.append(resident_id)
	if method == "sync_place_service_pressure":
		_append_resident_ref(
			result,
			source_state.get("owner_id"),
			residents,
			resident_id_by_name,
		)
	elif method == "sync_resident_request":
		for recipient: Variant in source_state.get("recipient_ids", []) as Array:
			_append_resident_ref(
				result,
				recipient,
				residents,
				resident_id_by_name,
			)
		if include_creator:
			_append_resident_ref(
				result,
				source_state.get("requester_id"),
				residents,
				resident_id_by_name,
			)
	elif method == "sync_job_vacancy":
		for candidate: Variant in source_state.get(
			"candidate_resident_ids",
			[],
		) as Array:
			_append_resident_ref(
				result,
				candidate,
				residents,
				resident_id_by_name,
			)
	result.sort()
	return result


static func _append_resident_ref(
	result: Array[String],
	value: Variant,
	residents: Dictionary,
	resident_id_by_name: Dictionary,
) -> void:
	var resident_ref := String(value).strip_edges()
	var resident_id := (
		resident_ref
		if residents.has(resident_ref)
		else String(resident_id_by_name.get(resident_ref, ""))
	)
	if not resident_id.is_empty() and not result.has(resident_id):
		result.append(resident_id)


static func operations(
	method: String,
	source_state: Dictionary,
	now: int,
	resident_ids: Array[String],
	requester_id: String,
	promisor_id: String,
	beneficiary_id: String,
	owner_id: String,
	clue: String,
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var source_ref := source_id(method, source_state)
	if method == "sync_resident_request":
		if not requester_id.is_empty():
			result.append(_involvement(requester_id, "creator", now))
		for resident_id: String in resident_ids:
			result.append(_awareness(
				resident_id,
				"direct_request",
				source_ref,
				now,
			))
		return result
	if method == "sync_conversation_commitment":
		_append_direct_conversation(
			result,
			promisor_id,
			"participant",
			source_ref,
			now,
		)
		_append_direct_conversation(
			result,
			beneficiary_id,
			"affected",
			source_ref,
			now,
		)
		return result
	if method == "sync_job_vacancy":
		for resident_id: String in resident_ids:
			result.append(_involvement(resident_id, "affected", now))
			result.append(_awareness(
				resident_id,
				"direct_request",
				source_ref,
				now,
			))
		return result
	if method == "sync_place_service_pressure" and not owner_id.is_empty():
		result.append(_involvement(owner_id, "affected", now))
		result.append(_awareness(owner_id, "witnessed", source_ref, now))
	var expires_at := int(source_state.get("expires_at", now + 1))
	for resident_id: String in resident_ids:
		if resident_id == owner_id:
			continue
		result.append({
			"kind": "exposure",
			"residentId": resident_id,
			"channel": "visible",
			"clue": clue,
			"sourceId": source_ref,
			"createdAt": now,
			"expiresAt": expires_at,
		})
		result.append({"kind": "schedule_decision", "residentId": resident_id})
	return result


static func _append_direct_conversation(
	result: Array[Dictionary],
	resident_id: String,
	role: String,
	source_id_value: String,
	now: int,
) -> void:
	if resident_id.is_empty():
		return
	result.append(_involvement(resident_id, role, now))
	result.append(_awareness(
		resident_id,
		"direct_conversation",
		source_id_value,
		now,
	))


static func _involvement(
	resident_id: String,
	role: String,
	now: int,
) -> Dictionary:
	return {
		"kind": "involvement",
		"residentId": resident_id,
		"role": role,
		"updatedAt": now,
	}


static func _awareness(
	resident_id: String,
	acquired_via: String,
	source_id_value: String,
	now: int,
) -> Dictionary:
	return {
		"kind": "awareness",
		"residentId": resident_id,
		"awareness": "known",
		"acquiredVia": acquired_via,
		"sourceId": source_id_value,
		"updatedAt": now,
	}
