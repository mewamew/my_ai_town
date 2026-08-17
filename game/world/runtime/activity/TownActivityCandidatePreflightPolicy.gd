class_name TownActivityCandidatePreflightPolicy
extends RefCounted


static func ordered_candidates(validated: Dictionary) -> Array:
	var candidates := validated.get("candidates", []) as Array
	var has_region_candidates := candidates.any(
		func(value: Variant) -> bool:
			return (
				value is Dictionary
				and String((value as Dictionary).get("targetType", "")) == "region"
			)
	)
	if has_region_candidates:
		var result := candidates.duplicate()
		if result.size() > 1:
			var rotation := posmod(
				hash("%s:%s" % [
					String(validated.get("residentId", "")),
					String(validated.get("actionId", "")),
				]),
				result.size(),
			)
			result = result.slice(rotation) + result.slice(0, rotation)
		return result
	if bool(validated.get("preferredRequested", false)):
		return candidates.slice(0, mini(2, candidates.size()))
	for candidate_value: Variant in candidates:
		var candidate := candidate_value as Dictionary
		if bool(candidate.get("memberAvailable", false)):
			return [candidate]
	return []


static func prioritize_cached(
	candidates: Array,
	reachability_cache: TownActivityReachabilityCache,
	absolute_minute: int,
	resident: Dictionary,
) -> Array:
	var cached_candidates: Array = []
	var uncached_candidates: Array = []
	for candidate_value: Variant in candidates:
		var candidate := candidate_value as Dictionary
		if reachability_cache.cached_prepared_action(
			absolute_minute,
			resident,
			candidate,
		).is_empty():
			uncached_candidates.append(candidate)
		else:
			cached_candidates.append(candidate)
	return (
		cached_candidates + uncached_candidates
		if not cached_candidates.is_empty()
		else candidates
	)


static func reservation_conflict(candidates: Array) -> Dictionary:
	if candidates.is_empty():
		return _reservation_conflict_result()
	for candidate_value: Variant in candidates:
		if bool((candidate_value as Dictionary).get("memberAvailable", false)):
			return {}
	return _reservation_conflict_result()


static func candidate_action(
	validated: Dictionary,
	candidate: Dictionary,
) -> Dictionary:
	return {
		"action_id": String(validated.get("actionId", "")),
		"type": "用道具",
		"prop": String(candidate.get("targetPropName", "")),
		"verb": String(candidate.get("targetActionVerb", "")),
		"line": String(validated.get("activityLabel", "")),
	}


static func prepared_from_cache(
	cached_action: Dictionary,
	action: Dictionary,
) -> Dictionary:
	var prepared_action := cached_action.duplicate(true)
	for field: String in ["action_id", "type", "prop", "verb", "line"]:
		prepared_action[field] = action.get(field)
	return {"ok": true, "action": prepared_action}


static func candidate_result(
	candidate: Dictionary,
	prepared_action: Dictionary,
	layout_override_action: bool,
) -> Dictionary:
	var member_position := candidate.get("memberPosition", []) as Array
	if member_position.size() != 2:
		return {}
	var expected := Vector2(
		float(member_position[0]),
		float(member_position[1]),
	)
	if not (
		(prepared_action.get("targetPosition", Vector2.ZERO) as Vector2)
		.is_equal_approx(expected)
	) and not layout_override_action:
		return {}
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"slotId": String(candidate.get("slotId", "")),
		"memberAnchorId": String(candidate.get("memberAnchorId", "")),
		"action": prepared_action.duplicate(true),
	}


static func target_failure(target_unreachable: bool) -> Dictionary:
	return {
		"ok": false,
		"errorCode": (
			"ACTIVITY_TARGET_UNREACHABLE"
			if target_unreachable
			else "ACTIVITY_SLOT_REFERENCE_INVALID"
		),
		"retryable": target_unreachable,
		"errors": [
			(
				"活动目标当前不可到达"
				if target_unreachable
				else "活动 slot/member 与权威 prop anchor 不一致"
			)
		],
	}


static func _reservation_conflict_result() -> Dictionary:
	return {
		"ok": false,
		"errorCode": "ACTIVITY_RESERVATION_CONFLICT",
		"retryable": true,
		"errors": ["当前活动的确定性 slot/member 已被预约"],
	}
