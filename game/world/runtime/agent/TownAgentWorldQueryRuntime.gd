class_name TownAgentWorldQueryRuntime
extends RefCounted


const LIFE_DESTINATION_QUERY := preload(
	"res://world/runtime/agent/TownAgentLifeDestinationQuery.gd"
)
const ANNOUNCEMENT_RESIDENT_RUNTIME := preload(
	"res://world/runtime/social/TownAnnouncementResidentRuntime.gd"
)
const ACTIVITY_SCALARS := preload(
	"res://world/runtime/activity/TownActivityScalars.gd"
)
const ACTION_SUPPORT := preload(
	"res://world/runtime/action/TownActionSupport.gd"
)
const CONFLICT_TENSION_OPTION_PROJECTION := preload(
	"res://world/runtime/conflict/TownConflictTensionOptionProjection.gd"
)
const CONVERSATION_RUNTIME := preload(
	"res://world/runtime/conversation/TownConversationRuntime.gd"
)
const CONTENT_CATALOG := preload(
	"res://world/data/town/TownWorkContentCatalog.gd"
)

const MAX_KNOWN_ANNOUNCEMENTS := 12


static func conflict_snapshot(
	host,
	resident_id: String,
	resident: Dictionary,
	nearby_ids: Array[String],
) -> Dictionary:
	if host._conflict_agent_world_bridge == null:
		return {
			"conflicts": [],
			"conflict_injuries": [],
			"conflict_tension_options": [],
			"medical_follow_up": {},
		}
	var snapshot := host._conflict_agent_world_bridge.snapshot_for_actor(
		resident_id,
		nearby_ids,
	) as Dictionary
	var profile := {}
	var profiles := host.world_definition.opening.get(
		"agentSoulProfiles",
		{},
	) as Dictionary
	if profiles.get(resident_id, {}) is Dictionary:
		profile = (profiles.get(resident_id, {}) as Dictionary).duplicate(true)
	snapshot["conflict_tension_options"] = CONFLICT_TENSION_OPTION_PROJECTION.decorate(
		resident_id,
		resident,
		snapshot.get("conflict_tension_options", []) as Array,
		host.player_avatar_id(),
		profile,
		not CONVERSATION_RUNTIME._active_conversation_for_person(
			host,
			resident_id,
		).is_empty(),
	)
	if host._conflict_controller == null:
		snapshot["medical_follow_up"] = {}
		return snapshot
	var follow_up := host._conflict_controller.get_follow_up(resident_id) as Dictionary
	if bool(follow_up.get("required", false)):
		snapshot["medical_follow_up"] = {
			"required": true,
			"kind": String(follow_up.get("kind", "go_to_clinic")),
			"priority": String(follow_up.get("priority", "urgent")),
			"reason": String(follow_up.get("reason", "heavy_injury")),
			"place_id": CONTENT_CATALOG.PLACE_CLINIC,
			"at_required_place": (
				String(resident.get("currentPlace", ""))
				== CONTENT_CATALOG.PLACE_CLINIC
			),
		}
	else:
		snapshot["medical_follow_up"] = {}
	return snapshot


static func travel_destinations(host, resident: Dictionary) -> Array[String]:
	return host._agent_wake_preparation_runtime.travel_destinations(host, resident)


static func life_destination_options(
	host,
	resident: Dictionary,
	travel_destination_values: Variant = null,
) -> Array[Dictionary]:
	var resident_id := String(resident.get("residentId", ""))
	var destinations: Array = (
		travel_destination_values
		if travel_destination_values is Array
		else travel_destinations(host, resident)
	)
	return LIFE_DESTINATION_QUERY.options(
		resident,
		destinations,
		not host.get_work_tasks_for_resident(resident_id).is_empty(),
		host.ACTIVITY_AVAILABILITY_RUNTIME.resident_sleep_needed(resident),
		int(host._environment.get_absolute_minute()),
		host.get_weather(),
		host._activity_runtime,
	)


static func known_announcements(host, resident_id: String) -> Array[Dictionary]:
	return ANNOUNCEMENT_RESIDENT_RUNTIME.known_announcements(
		host,
		host._community_bulletin,
		resident_id,
		MAX_KNOWN_ANNOUNCEMENTS,
	)


static func life_rhythm(host, resident: Dictionary = {}) -> Dictionary:
	var minute_of_day := posmod(
		int(host._environment.get_absolute_minute()),
		1440,
	)
	var social_state := resident.get("socialState", {}) as Dictionary
	var schedule_context := host._activity_runtime.schedule_context(
		social_state,
		minute_of_day,
	) as Dictionary
	return ACTIVITY_SCALARS.life_rhythm_snapshot(
		resident,
		minute_of_day,
		schedule_context,
	)


static func fact_payloads(values: Array) -> Array[Dictionary]:
	return ACTION_SUPPORT.agent_fact_payloads(values)
