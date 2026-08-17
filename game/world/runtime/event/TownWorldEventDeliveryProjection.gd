class_name TownWorldEventDeliveryProjection
extends RefCounted


const CONFLICT_KNOWLEDGE_PROJECTOR := preload(
	"res://world/runtime/conflict/TownConflictKnowledgeProjector.gd"
)
const SYSTEM_ONLY_AGENT_EVENT_KEYS := [
	"participant_resident_ids",
	"causedByEventIds",
	"storyRootEventIds",
	"placeName",
]


static func materialized_event(
	source: Dictionary,
	event_id: String,
	time: Dictionary,
) -> Dictionary:
	var event := source.duplicate(true)
	event["event_id"] = event_id
	event["time"] = (source.get("time", time) as Dictionary).duplicate(true)
	return event


static func delivery_views(
	event: Dictionary,
	resident_id: String,
) -> Dictionary:
	var identified_event := event.duplicate(true)
	identified_event["residentId"] = resident_id
	var agent_event := identified_event.duplicate(true)
	for system_key: String in SYSTEM_ONLY_AGENT_EVENT_KEYS:
		agent_event.erase(system_key)
	return {
		"identifiedEvent": identified_event,
		"agentEvent": agent_event,
	}


static func should_schedule_broadcast(
	event: Dictionary,
	resident_space_id: String,
) -> bool:
	return (
		String(event.get("type", "")) != "天气变了"
		or resident_space_id == "town_outdoor"
	)


static func wake_policy(event: Dictionary, urgent_event_types: Array) -> Dictionary:
	var event_type := String(event.get("type", ""))
	var urgent := urgent_event_types.has(event_type)
	return {
		"invalidate": urgent,
		"allowCurrentActivityInterrupt": urgent,
		"wakeWhileCurrentAction": event_type in [
			"有人来了",
			"有人走了",
			"公告到点",
		],
	}


static func post_injury_reaction(
	resident_id: String,
	events: Array,
	resident_names_by_id: Dictionary,
	player_id: String,
	player_name: String,
) -> Dictionary:
	var latest: Dictionary = {}
	for value: Variant in events:
		if value is not Dictionary:
			continue
		var event := value as Dictionary
		if not CONFLICT_KNOWLEDGE_PROJECTOR.is_injury_subject(event, resident_id):
			continue
		var actor_ids := event.get("actor_ids", []) as Array
		var attacker_id := String(event.get("source_actor_id", "")).strip_edges()
		if attacker_id.is_empty() or attacker_id == resident_id:
			for actor_value: Variant in actor_ids:
				var actor_id := String(actor_value).strip_edges()
				if not actor_id.is_empty() and actor_id != resident_id:
					attacker_id = actor_id
					break
		latest = {
			"required": true,
			"conflict_id": String(event.get("conflict_id", "")),
			"injury_event_id": String(
				event.get("conflict_event_id", event.get("event_id", "")),
			),
			"severity": String(event.get("severity", "")),
			"attacker_resident_id": attacker_id,
			"attacker_name": _person_name(
				attacker_id,
				resident_names_by_id,
				player_id,
				player_name,
			),
		}
	return latest


static func post_injury_reaction_for_host(
	host,
	resident_id: String,
	events: Array,
) -> Dictionary:
	return post_injury_reaction(
		resident_id,
		events,
		host.resident_registry.name_by_id,
		host.player_avatar_id(),
		String(host.actor_presentation_state.player_avatar.get("name", "")),
	)


static func _person_name(
	person_id: String,
	resident_names_by_id: Dictionary,
	player_id: String,
	player_name: String,
) -> String:
	if resident_names_by_id.has(person_id):
		return String(resident_names_by_id[person_id])
	return player_name if person_id == player_id else ""
