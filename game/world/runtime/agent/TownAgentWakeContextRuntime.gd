class_name TownAgentWakeContextRuntime
extends RefCounted


const INTERESTS := preload("res://world/data/town/TownInterestCatalog.gd")
const PROP_QUERY := preload("res://world/data/town/TownWorldPropQuery.gd")
const WAKE_PACKET_PROJECTION := preload(
	"res://world/runtime/agent/TownAgentWakePacketProjection.gd"
)
const CONVERSATION_RUNTIME := preload(
	"res://world/runtime/conversation/TownConversationRuntime.gd"
)
const ACTION_PRESENTATION := preload(
	"res://world/runtime/presentation/TownActionPresentationSemantics.gd"
)
const ACTION_VALIDATION := preload(
	"res://world/runtime/action/TownActionValidation.gd"
)
const DINING_SERVICE := preload(
	"res://world/runtime/work/TownDiningServiceRuntime.gd"
)
const AGENT_WORLD_QUERY_RUNTIME := preload(
	"res://world/runtime/agent/TownAgentWorldQueryRuntime.gd"
)
const GO_ACTION_PREFETCH_RUNTIME := preload(
	"res://world/runtime/movement/TownGoActionPrefetchRuntime.gd"
)


static func wake_packet(
	host,
	resident_name: String,
	resident: Dictionary,
	decision_id: String,
	events: Array,
	results: Array,
	social_results_value: Variant = null,
	prefetch_arrival_context: bool = false,
	frame_budgeted := false,
) -> Dictionary:
	var perception_resident := resident
	if prefetch_arrival_context:
		perception_resident = WAKE_PACKET_PROJECTION.perception_resident(
			resident,
			GO_ACTION_PREFETCH_RUNTIME.arrival_projection(host, resident),
		)
	var nearby: Array[Dictionary] = []
	for other_name_value: Variant in resident.get("nearby", []) as Array:
		var other_name := String(other_name_value)
		var other: Dictionary = host._person_state(other_name) as Dictionary
		nearby.append({
			"resident_id": host.person_id_for_name(other_name),
			"name": host.person_name_for_id(host.person_id_for_name(other_name)),
			"doing": String(other.get("doing", "")),
			"available_for_conversation": CONVERSATION_RUNTIME._active_conversation_for_person(host, other_name).is_empty(),
		})
	var public_events: Array[Dictionary] = AGENT_WORLD_QUERY_RUNTIME.fact_payloads(events)
	var public_results: Array[Dictionary] = AGENT_WORLD_QUERY_RUNTIME.fact_payloads(results)
	var social_results := WAKE_PACKET_PROJECTION.public_social_results(
		social_results_value if social_results_value is Array else (
			host._social_agent_adapter.take_social_response_results(resident_name)
		),
	)
	var life_destination_options: Array[Dictionary] = (
		AGENT_WORLD_QUERY_RUNTIME.life_destination_options(
			host, perception_resident,
		)
	)
	var place_snapshot := {
		"name": String(perception_resident.get("currentPlace", "")),
		"destinations": AGENT_WORLD_QUERY_RUNTIME.travel_destinations(
			host, perception_resident,
		),
		"visible_props": host._agent_wake_preparation_runtime.visible_props(
			host.world_definition.world_data,
			host._dynamic_prop_runtime,
			perception_resident,
		),
		"props": available_props(host, perception_resident),
		"activities": available_activities(
			host,
			perception_resident,
			frame_budgeted,
		),
		"service_control": host.PLACE_SERVICE_COMMAND_RUNTIME.service_control(host, perception_resident),
		"message_recipients": host.PRIVATE_MESSAGE_DELIVERY_RUNTIME.ordinary_recipients(host,
			resident_name,
		),
	}
	DINING_SERVICE.attach_capacity_status(host, place_snapshot, String(perception_resident.get("residentId", "")), String(perception_resident.get("currentPlace", "")), int(host._environment.get_absolute_minute()))
	var priority_service_task: Dictionary = host._work.priority_onsite_service_task(
		String(resident.get("residentId", "")),
		host.get_work_tasks_for_resident(resident_name),
	)
	if not priority_service_task.is_empty():
		host.ACTION_SUPPORT.focus_agent_place_snapshot_on_service_task(
			perception_resident,
			place_snapshot,
			priority_service_task,
		)
	var conflict_snapshot: Dictionary = AGENT_WORLD_QUERY_RUNTIME.conflict_snapshot(
		host, resident_name, resident, WAKE_PACKET_PROJECTION.resident_ids(nearby),
	)
	var post_injury_reaction: Dictionary = host.WORLD_EVENT_DELIVERY_PROJECTION.post_injury_reaction_for_host(host,
		resident_name,
		events,
	)
	return WAKE_PACKET_PROJECTION.packet(
		decision_id,
		{
			"resident": perception_resident,
			"time": host.get_time(),
			"weather": host.get_weather(),
			"weatherContext": host._activity_runtime.weather_context(
				host.get_weather(),
				String(perception_resident.get("currentPlace", "")),
			),
			"currentAction": ACTION_PRESENTATION._agent_current_action(
				host,
				perception_resident.get("currentAction", {}) as Dictionary,
			),
			"emptyActivityState": host.ACTIVITY_SCALARS.empty_activity_state(),
			"conditions": host._resident_conditions.get_conditions(resident_name) as Array,
			"activeNeeds": host._resident_conditions.get_active_needs(resident_name) as Array,
			"nearby": nearby,
			"place": place_snapshot,
			"rhythm": AGENT_WORLD_QUERY_RUNTIME.life_rhythm(host, resident),
			"workTasks": host.get_work_tasks_for_resident(resident_name),
			"lifeDestinationOptions": life_destination_options,
			"knownAnnouncements": AGENT_WORLD_QUERY_RUNTIME.known_announcements(
				host, resident_name,
			),
			"conversation": host.ACTIVITY_SCALARS.duplicate_optional_dictionary(resident.get("conversation")),
			"conversationFollowUpOptions": host.CONVERSATION_FOLLOW_UP_OPTION_RUNTIME.options(host,
				resident_name,
				resident,
				public_events,
				frame_budgeted,
			),
			"socialMatters": host._social_agent_adapter.build_social_matters(
				resident_name,
				int(host._environment.get_absolute_minute()),
			) as Array[Dictionary],
			"socialExposures": (
				[]
				if ACTION_VALIDATION.inflight_requires_reply(events)
				else host.get_agent_social_exposures(resident_name)
			),
			"conflictSnapshot": conflict_snapshot,
			"postInjuryReaction": post_injury_reaction,
		},
		public_events,
		public_results,
		social_results,
	)



static func available_props(host, resident: Dictionary) -> Array:
	var result: Array = []
	var resident_id := String(resident.get("residentId", ""))
	for prop_value: Variant in PROP_QUERY.agent_props_at_place(
		host.PROP_ACTION_PREPARER.query_data(host),
		String(resident.get("currentPlace", "")),
	):
		var prop := prop_value as Dictionary
		var prop_name := String(prop.get("name", ""))
		var available_verbs: Array = []
		for verb_value: Variant in prop.get("verbs", []) as Array:
			var verb := String(verb_value)
			if verb == "睡觉" and not host.ACTIVITY_AVAILABILITY_RUNTIME.resident_sleep_needed(resident):
				continue
			var action := {
				"prop": prop_name,
				"verb": verb,
			}
			if host._dynamic_prop_runtime.is_dynamic_action(resident, action):
				if (
					host.ACTION_SUPPORT.direct_prop_action_available(host,
						resident_id,
						resident,
						action,
					)
					and host.PROP_ACTION_PREPARER.prepare_for_host(host,
						resident,
						{
							"action_id": "prop-query-preflight",
							"type": "用道具",
							"prop": prop_name,
							"verb": verb,
							"line": verb,
						},
					).get("ok") == true
				):
					available_verbs.append(verb)
				continue
			var availability := host._activity_runtime.legacy_activity_candidates(
				resident.get("socialState", {}) as Dictionary,
				String(resident.get("currentPlace", "")),
				prop_name,
				verb,
			) as Dictionary
			if availability.get("ok") != true:
				if (
					host.PROP_ACTION_PREPARER.is_layout_override_action(host, resident, action)
					and host.ACTION_SUPPORT.direct_prop_action_available(host,
						resident_id,
						resident,
						action,
					)
					and host.PROP_ACTION_PREPARER.prepare_for_host(host,
						resident,
						{
							"action_id": "prop-query-preflight",
							"type": "用道具",
							"prop": prop_name,
							"verb": verb,
							"line": verb,
						},
					).get("ok") == true
				):
					available_verbs.append(verb)
				continue
			for candidate_value: Variant in availability.get(
				"candidates",
				[],
			) as Array:
				var candidate := candidate_value as Dictionary
				var activity_id := String(
					candidate.get("activityId", ""),
				)
				if not host.ACTIVITY_AVAILABILITY_RUNTIME.work_task_available(host,
					resident_id,
					resident,
					activity_id,
					String(candidate.get("role", "")),
				):
					continue
				var weather_availability := host._activity_runtime.activity_weather_availability(
					activity_id,
					String(
						candidate.get("placeId", "")
					),
					String(candidate.get("role", "")),
					host.get_weather(),
				) as Dictionary
				if (
					bool(
						weather_availability.get(
							"available",
							false,
						)
					)
					and
					bool(candidate.get("memberAvailable", false))
					and host.ACTIVITY_CANDIDATE_PREFLIGHT_RUNTIME.candidate_reachable(host,
						resident,
						candidate,
						verb,
					)
				):
					available_verbs.append(verb)
					break
		if not available_verbs.is_empty():
			result.append({
				"name": prop_name,
				"verbs": available_verbs,
			})
	return result




static func available_activities(
	host,
	resident: Dictionary,
	frame_budgeted := false,
	priority_activity_id := "",
	max_uncached_route_checks_override := -2,
) -> Array:
	var resident_id := String(resident.get("residentId", ""))
	var current_place := String(resident.get("currentPlace", ""))
	var service_state: Dictionary = host._work.place_services.state(current_place)
	var query: Dictionary = host.query_activity_options(
		resident_id,
		resident,
		(
			max_uncached_route_checks_override
			if max_uncached_route_checks_override >= -1
			else host.MAX_AGENT_ACTIVITY_ROUTE_CHECKS_PER_WAKE
			if frame_budgeted
			else -1
		),
		priority_activity_id,
	)
	if query.get("ok") != true:
		return []
	var result: Array[Dictionary] = []
	var attributes := resident.get("attributes", {}) as Dictionary
	for option_value: Variant in query.get("options", []) as Array:
		var option := option_value as Dictionary
		var route_check_deferred := bool(
			option.get("routeCheckDeferred", false)
		)
		if not bool(option.get("available", false)) and not route_check_deferred:
			continue
		var activity_id := String(option.get("activityId", ""))
		if (
			not service_state.is_empty()
			and not bool(service_state.get("open", true))
			and (
				(service_state.get("request_activity_ids", []) as Array).has(
					activity_id
				)
				or activity_id
				== String(service_state.get("helper_activity_id", ""))
			)
		):
			continue
		var matched_interests := INTERESTS.matched_labels_for_activity(
			attributes.get("interests", []),
			host._activity_runtime.activity_tags(activity_id),
		)
		var role := String(option.get("role", ""))
		var matching_task_ids: Array[String] = []
		var matching_task_capabilities: Array[String] = []
		if role == "worker":
			var occupation_id: String = host.OCCUPATION_RESIDENT_CONTEXT_RUNTIME.id_for_activity(host,
				resident_id,
				activity_id,
			)
			if not occupation_id.is_empty():
				var tasks := host._work.tasks.tasks_for_activity(occupation_id,
					activity_id,
					resident_id,) as Array
				for task_value: Variant in host._work.available_work_tasks(
					tasks,
					host.resident_registry.records,
				):
					if not task_value is Dictionary:
						continue
					var task := task_value as Dictionary
					var task_id := String(task.get("taskId", ""))
					var capability := String(task.get("capability", ""))
					if not task_id.is_empty() and not matching_task_ids.has(task_id):
						matching_task_ids.append(task_id)
					if (
						not capability.is_empty()
						and not matching_task_capabilities.has(capability)
					):
						matching_task_capabilities.append(capability)
		matching_task_ids.sort()
		matching_task_capabilities.sort()
		result.append({
			"activity_id": activity_id,
			"label": String(option.get("label", "")),
			"role": role,
			"route_check_deferred": route_check_deferred,
			"advances_current_work_task": not matching_task_ids.is_empty(),
			"work_task_ids": matching_task_ids,
			"work_task_capabilities": matching_task_capabilities,
			"interest_match": not matched_interests.is_empty(),
			"matched_interests": matched_interests,
	})
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_work := bool(left.get("advances_current_work_task", false))
		var right_work := bool(right.get("advances_current_work_task", false))
		if left_work != right_work:
			return left_work
		var left_match := bool(left.get("interest_match", false))
		var right_match := bool(right.get("interest_match", false))
		if left_match != right_match:
			return left_match
		return String(left.get("activity_id", "")) < String(
			right.get("activity_id", "")
		)
	)
	return result
