class_name TownActivityRoutinePolicy
extends RefCounted


static func legacy_activation(
	mapping: Dictionary,
	descriptor: Dictionary,
	candidates: Array[Dictionary],
) -> Dictionary:
	if descriptor.is_empty():
		return {}
	var has_next_activity := candidates.any(
		func(candidate: Dictionary) -> bool:
			return (
				bool(candidate.get("available", false))
				and String(candidate.get("activityId", ""))
				!= String(mapping.get("activityId", ""))
			)
	)
	if not has_next_activity:
		return {}
	var planned_mapping := mapping.duplicate(true)
	var planned_descriptor := descriptor.duplicate(true)
	if (
		String(descriptor.get("group", "")) == "meal"
		and String(descriptor.get("phase", "")) != "collect"
	):
		for candidate: Dictionary in candidates:
			if (
				bool(candidate.get("available", false))
				and String(candidate.get("phase", "")) == "collect"
			):
				planned_mapping["activityId"] = String(candidate.get("activityId", ""))
				planned_mapping.erase("preferredSlotId")
				planned_descriptor = candidate.duplicate(true)
				planned_descriptor["group"] = "meal"
				break
	return {
		"mapping": planned_mapping,
		"descriptor": planned_descriptor,
	}


static func continuation_entry(
	routine: Dictionary,
	current_action: Dictionary,
	current_place: String,
	absolute_minute: int,
	max_steps: int,
	completion_text: String,
) -> Dictionary:
	if not current_action.is_empty():
		return _close(
			"interrupted",
			"居民改做另一件事，刚才的活动安排先收尾了",
		)
	if current_place != String(routine.get("placeId", "")):
		return _close("interrupted", "离开地点，手头的事情先停下了")
	if absolute_minute >= int(routine.get("endAbsoluteMinute", 0)):
		return _close("completed", completion_text)
	if int(routine.get("sequence", 0)) + 1 >= max_steps:
		return _close("completed", completion_text)
	var expected_phase := ""
	if String(routine.get("group", "")) == "meal":
		match String(routine.get("lastPhase", "")):
			"collect":
				expected_phase = "consume"
			"consume":
				expected_phase = "cleanup"
			_:
				return _close("completed", completion_text)
	return {
		"kind": "select",
		"expectedPhase": expected_phase,
	}


static func candidate_plan(
	routine: Dictionary,
	candidates: Array[Dictionary],
	expected_phase: String,
) -> Dictionary:
	var group := String(routine.get("group", ""))
	var visited_activity_ids := routine.get("visitedActivityIds", []) as Array
	var usable: Array[Dictionary] = []
	for candidate: Dictionary in candidates:
		var activity_id := String(candidate.get("activityId", ""))
		if not bool(candidate.get("available", false)):
			continue
		if activity_id == String(routine.get("lastActivityId", "")):
			continue
		if group == "work" and visited_activity_ids.has(activity_id):
			continue
		if (
			not expected_phase.is_empty()
			and String(candidate.get("phase", "")) != expected_phase
		):
			continue
		usable.append(candidate)
	usable.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			return String(left.get("activityId", "")) < String(
				right.get("activityId", ""),
			)
	)
	var next_sequence := int(routine.get("sequence", 0)) + 1
	if usable.is_empty():
		return {"nextSequence": next_sequence, "candidates": []}
	var start_index := posmod(
		int(routine.get("choiceSeed", 0)) + next_sequence * 1103515245,
		usable.size(),
	)
	var ordered: Array[Dictionary] = []
	for offset in usable.size():
		ordered.append(usable[(start_index + offset) % usable.size()])
	return {"nextSequence": next_sequence, "candidates": ordered}


static func continuation_step(
	routine: Dictionary,
	candidate: Dictionary,
	next_sequence: int,
) -> Dictionary:
	return {
		"stepId": "step-%d-%s" % [
			next_sequence,
			String(candidate.get("activityId", "")),
		],
		"operation": "activity.perform",
		"target": {
			"activityId": String(candidate.get("activityId", "")),
			"placeId": String(routine.get("placeId", "")),
		},
		"params": {"reason": String(candidate.get("label", ""))},
	}


static func advanced_routine(
	routine: Dictionary,
	candidate: Dictionary,
	next_sequence: int,
) -> Dictionary:
	var advanced := routine.duplicate(true)
	var activity_id := String(candidate.get("activityId", ""))
	advanced["sequence"] = next_sequence
	advanced["lastActivityId"] = activity_id
	advanced["lastPhase"] = String(candidate.get("phase", ""))
	var visited := advanced.get("visitedActivityIds", []) as Array
	if not visited.has(activity_id):
		visited.append(activity_id)
	advanced["visitedActivityIds"] = visited
	return advanced


static func _close(status: String, reason: String) -> Dictionary:
	return {"kind": "close", "status": status, "reason": reason}
