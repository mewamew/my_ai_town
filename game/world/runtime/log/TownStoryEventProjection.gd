class_name TownStoryEventProjection
extends RefCounted


static func action_started(
	resident_id: String,
	resident_name: String,
	current_place: String,
	action: Dictionary,
	provenance: Dictionary,
	doing_line: String,
) -> Dictionary:
	var root_event_ids := (
		provenance.get("rootEventIds", []) as Array
	).duplicate(true)
	var action_type := String(action.get("type", ""))
	var action_id := String(action.get("action_id", ""))
	if root_event_ids.is_empty() or action_type == "待着" or action_id.is_empty():
		return {}
	var direct_cause_ids := (
		provenance.get("sourceEventIds", []) as Array
	).duplicate(true)
	return {
		"storyEventId": "story-action:%s:%s" % [resident_id, action_id],
		"storyType": "action_started",
		"residentId": resident_id,
		"placeName": current_place,
		"actionId": action_id,
		"context": {
			"sourceEventIds": [],
			"rootEventIds": root_event_ids.duplicate(true),
			"directCauseEventIds": direct_cause_ids.duplicate(true),
			"actionType": action_type,
			"line": doing_line,
			"prop": String(action.get("prop", "")),
			"verb": String(action.get("verb", "")),
			"place": String(action.get("place", "")),
			"residentId": resident_id,
		},
		"payload": {
			"actionId": action_id,
			"actionType": action_type,
			"line": doing_line,
			"prop": String(action.get("prop", "")),
			"verb": String(action.get("verb", "")),
			"place": String(action.get("place", "")),
			"participantLabels": [resident_name],
			"causedByEventIds": direct_cause_ids,
			"storyRootEventIds": root_event_ids,
		},
	}


static func action_outcome(
	resident_id: String,
	resident_name: String,
	current_place: String,
	action_id: String,
	status: String,
	reason: String,
	context: Dictionary,
) -> Dictionary:
	if context.is_empty() or String(context.get("actionType", "")) in [
		"去",
		"待着",
		"搭话",
		"答话",
	]:
		return {}
	return {
		"storyEventId": "story-result:%s:%s:%s" % [
			resident_id,
			action_id,
			status,
		],
		"storyType": "action_outcome",
		"residentId": resident_id,
		"placeName": current_place,
		"payload": {
			"actionId": action_id,
			"actionType": String(context.get("actionType", "")),
			"line": String(context.get("line", "")),
			"prop": String(context.get("prop", "")),
			"verb": String(context.get("verb", "")),
			"place": String(context.get("place", "")),
			"status": status,
			"reason": reason,
			"participantLabels": [resident_name],
			"causedByEventIds": (
				context.get("sourceEventIds", []) as Array
			).duplicate(true),
			"storyRootEventIds": (
				context.get("rootEventIds", []) as Array
			).duplicate(true),
		},
	}
