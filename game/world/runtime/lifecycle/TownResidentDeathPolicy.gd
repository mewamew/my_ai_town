class_name TownResidentDeathPolicy
extends RefCounted


static func prepare_confirmation(
	running: bool,
	current_instance_token: String,
	expected_instance_token: String,
	resident_id: String,
	existing_lifecycle: Dictionary,
	expected_lifecycle_revision: int,
	reason: String,
) -> Dictionary:
	if not running:
		return _failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	if (
		not expected_instance_token.is_empty()
		and current_instance_token != expected_instance_token
	):
		return _failure(
			"RESIDENT_DEATH_SESSION_STALE",
			["当前小镇已经切换，请重新选择居民后再确认"],
			{"stale": true},
		)
	if resident_id.is_empty():
		return _failure(
			"RESIDENT_NOT_FOUND",
			["找不到要确认死亡的居民"],
		)
	if (
		expected_lifecycle_revision >= 0
		and int(existing_lifecycle.get("revision", -1))
			!= expected_lifecycle_revision
	):
		return _failure(
			"RESIDENT_DEATH_REQUEST_STALE",
			["居民状态已经变化，请重新选择后再确认"],
			{"stale": true},
		)
	if String(existing_lifecycle.get("status", "")) == "dead":
		return {
			"ok": true,
			"alreadyConfirmed": true,
			"changed": false,
			"state": existing_lifecycle.duplicate(true),
			"event": (
				existing_lifecycle.get("deathEvent", {}) as Dictionary
			).duplicate(true),
		}
	var normalized_reason := reason.strip_edges()
	if normalized_reason.is_empty():
		return _failure(
			"RESIDENT_DEATH_REASON_REQUIRED",
			["死亡必须使用 World 已确认的原因"],
		)
	return {
		"ok": true,
		"alreadyConfirmed": false,
		"normalizedReason": normalized_reason,
	}


static func death_location(resident: Dictionary) -> Dictionary:
	return {
		"spaceId": String(resident.get("spaceId", "")),
		"regionId": String(resident.get("regionId", "")),
		"placeName": String(resident.get("currentPlace", "")),
		"position": resident.get("position", Vector2.ZERO) as Vector2,
	}


static func apply_terminal_resident_state(resident: Dictionary) -> void:
	resident["doing"] = "已经死亡"
	resident["movementRevision"] = int(
		resident.get("movementRevision", 1),
	) + 1
	resident["routeConnector"] = []
	resident["currentAction"] = {}
	resident["actionSuspendedAbsoluteMinute"] = -1
	resident["conversationId"] = ""
	resident["conversation"] = null
	resident["eventQueue"] = []
	resident["resultQueue"] = []
	resident["inflightEvents"] = []
	resident["inflightResults"] = []
	resident["decisionPending"] = false
	resident["validDecisionId"] = ""
	resident["decisionMayInterruptCurrent"] = false
	resident["pendingWake"] = {}
	resident["wakeDispatchQueued"] = false


static func release_social_participation(
	social_matters,
	resident_id: String,
	absolute_minute: int,
) -> Array[String]:
	var released_matter_ids: Array[String] = []
	for matter_value: Variant in social_matters.list_matters(false) as Array:
		var matter := matter_value as Dictionary
		if String(matter.get("state", "")) not in ["assigned", "executing"]:
			continue
		var participant := (
			(matter.get("participants", {}) as Dictionary).get(
				resident_id,
				{},
			) as Dictionary
		)
		if String(participant.get("status", "")) not in ["assigned", "executing"]:
			continue
		var matter_id := String(matter.get("matter_id", ""))
		var released := social_matters.release_participant(
			matter_id,
			resident_id,
			"居民已经死亡",
			absolute_minute,
		) as Dictionary
		if released.get("ok") == true:
			released_matter_ids.append(matter_id)
	return released_matter_ids


static func active_conflict_ids(
	conflict_projection: Dictionary,
	resident_id: String,
) -> Array[String]:
	var result: Array[String] = []
	for conflict_value: Variant in conflict_projection.get(
		"activeConflicts",
		[],
	) as Array:
		var conflict := conflict_value as Dictionary
		if (conflict.get("participantIds", []) as Array).has(resident_id):
			result.append(String(conflict.get("conflictId", "")))
	return result


static func pending_private_message_ids(
	private_message_runtime,
	resident_id: String,
) -> Array[String]:
	var result: Array[String] = []
	for message_id: String in private_message_runtime.sorted_message_ids():
		var message: Dictionary = private_message_runtime.message(message_id) as Dictionary
		if String(message.get("state", "")) != "pending":
			continue
		if (
			String(message.get("senderResidentId", "")) == resident_id
			or String(message.get("recipientResidentId", "")) == resident_id
		):
			result.append(message_id)
	result.sort()
	return result


static func announcement_text(event: Dictionary) -> String:
	var death_time := event.get("time", {}) as Dictionary
	var resident_name := String(
		event.get("deceased_resident_name", "居民"),
	).strip_edges()
	var day := int(death_time.get("day", 0))
	var clock := String(death_time.get("clock", "")).strip_edges()
	if day > 0 and not clock.is_empty():
		return "%s于第%d天%s死亡。" % [resident_name, day, clock]
	if not clock.is_empty():
		return "%s于%s死亡。" % [resident_name, clock]
	return "%s已经死亡。" % resident_name


static func _failure(
	error_code: String,
	errors: Array,
	extra: Dictionary = {},
) -> Dictionary:
	var result := {
		"ok": false,
		"errorCode": error_code,
		"errors": errors.duplicate(true),
	}
	result.merge(extra, true)
	return result
