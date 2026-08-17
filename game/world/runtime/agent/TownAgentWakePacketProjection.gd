class_name TownAgentWakePacketProjection
extends RefCounted


static func perception_resident(
	resident: Dictionary,
	arrival_projection: Dictionary,
) -> Dictionary:
	if arrival_projection.is_empty():
		return resident
	var projected := resident.duplicate(true)
	projected["spaceId"] = arrival_projection.get("spaceId", "")
	projected["regionId"] = arrival_projection.get("regionId", "")
	projected["currentPlace"] = arrival_projection.get("currentPlace", "")
	projected["position"] = arrival_projection.get("position", Vector2.ZERO)
	projected["currentAction"] = {}
	return projected


static func resident_ids(nearby: Array[Dictionary]) -> Array[String]:
	var result: Array[String] = []
	for nearby_resident: Dictionary in nearby:
		var resident_id := String(nearby_resident.get("resident_id", "")).strip_edges()
		if not resident_id.is_empty():
			result.append(resident_id)
	return result


static func public_social_results(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if value is not Array:
		return result
	for item: Variant in value as Array:
		if item is Dictionary:
			result.append((item as Dictionary).duplicate(true))
	return result


static func packet(
	decision_id: String,
	context: Dictionary,
	events: Array,
	results: Array,
	social_results: Array[Dictionary],
) -> Dictionary:
	var resident := context.get("resident", {}) as Dictionary
	var conflict_snapshot := context.get("conflictSnapshot", {}) as Dictionary
	return {
		"decision_id": decision_id,
		"snapshot": {
			"time": context.get("time", {}) as Dictionary,
			"weather": String(context.get("weather", "")),
			"weather_context": context.get("weatherContext", {}) as Dictionary,
			"me": {
				"doing": String(resident.get("doing", "")),
				"current_action": context.get("currentAction"),
				"body": (resident.get("body", {}) as Dictionary).duplicate(true),
				"activityNeeds": (
					resident.get("activityState", context.get("emptyActivityState", {}))
					as Dictionary
				).duplicate(true),
				"conditions": context.get("conditions", []) as Array,
				"activeNeeds": context.get("activeNeeds", []) as Array,
			},
			"nearby": context.get("nearby", []) as Array,
			"place": context.get("place", {}) as Dictionary,
			"rhythm": context.get("rhythm", {}) as Dictionary,
			"work_tasks": context.get("workTasks", []) as Array,
			"life_destination_options": context.get("lifeDestinationOptions", []) as Array,
			"known_announcements": context.get("knownAnnouncements", []) as Array,
			"conversation": context.get("conversation"),
			"conversation_follow_up_options": context.get("conversationFollowUpOptions", []) as Array,
			"social_matters": context.get("socialMatters", []) as Array,
			"social_exposures": context.get("socialExposures", []) as Array,
			"conflicts": (conflict_snapshot.get("conflicts", []) as Array).duplicate(true),
			"conflict_injuries": (
				conflict_snapshot.get("conflict_injuries", []) as Array
			).duplicate(true),
			"conflict_tension_options": (
				conflict_snapshot.get("conflict_tension_options", []) as Array
			).duplicate(true),
			"medical_follow_up": (
				conflict_snapshot.get("medical_follow_up", {}) as Dictionary
			).duplicate(true),
			"post_injury_reaction": context.get("postInjuryReaction", {}) as Dictionary,
		},
		"events": events,
		"action_results": results,
		"social_response_results": social_results,
	}
