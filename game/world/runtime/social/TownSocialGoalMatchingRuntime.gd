class_name TownSocialGoalMatchingRuntime
extends RefCounted


const ACTIVITY_SCALARS := preload(
	"res://world/runtime/activity/TownActivityScalars.gd"
)
const SOCIAL_JUDGMENTS := preload(
	"res://world/runtime/social/TownSocialJudgments.gd"
)


static func complete_direct_capability(
	host,
	resident_id: String,
	capability_id: String,
	target_refs: Dictionary,
	result_id: String,
) -> void:
	for assignment: Dictionary in active_assignments(
		host,
		resident_id,
		["assigned"],
	):
		var action_goal := assignment.get("action_goal", {}) as Dictionary
		if (
			String(action_goal.get("capability_id", "")) != capability_id
			or not target_refs_match(
				action_goal.get("target_refs", {}) as Dictionary,
				target_refs,
			)
		):
			continue
		var matter_id := String(assignment.get("matter_id", ""))
		var goal_id := String(action_goal.get("goal_id", ""))
		var started := host._social_matters.start_execution(
			matter_id,
			resident_id,
			goal_id,
			int(host._environment.get_absolute_minute()),
		) as Dictionary
		if started.get("ok") != true:
			continue
		host.SOCIAL_ASSIGNMENT_RESULT_RUNTIME.record_result(host,
			assignment,
			resident_id,
			{"result_id": result_id, "capability_id": capability_id},
			"completed",
		)


static func target_refs_match(expected: Dictionary, actual: Dictionary) -> bool:
	return ACTIVITY_SCALARS.target_refs_match(expected, actual)


static func active_assignments(
	host,
	resident_id: String,
	statuses: Array[String],
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for matter_value: Variant in host._social_matters.list_matters(false) as Array:
		var matter := matter_value as Dictionary
		var participant := (
			(matter.get("participants", {}) as Dictionary).get(resident_id, {})
			as Dictionary
		)
		if (
			participant.is_empty()
			or String(participant.get("status", "")) not in statuses
		):
			continue
		result.append({
			"matter_id": String(matter.get("matter_id", "")),
			"action_goal": (
				participant.get("action_goal", {}) as Dictionary
			).duplicate(true),
		})
	return result


static func active_commitment_count(host, resident_id: String) -> int:
	return active_assignments(
		host,
		resident_id,
		["assigned", "executing"],
	).size()


static func has_active_capability(
	host,
	resident_id: String,
	capability_id: String,
) -> bool:
	for assignment: Dictionary in active_assignments(
		host,
		resident_id,
		["assigned", "executing"],
	):
		if String(
			(assignment.get("action_goal", {}) as Dictionary).get(
				"capability_id",
				"",
			)
		) == capability_id:
			return true
	return false


static func resident_available_at(host, resident_id: String, now: int) -> int:
	return SOCIAL_JUDGMENTS.resident_social_available_at(host, resident_id, now)


static func goal_matches_action(
	host,
	action_goal: Dictionary,
	action: Dictionary,
	resident_id: String = "",
) -> bool:
	if not action_type_matches(action_goal, action):
		return false
	var capability_id := String(action_goal.get("capability_id", ""))
	var target_refs := action_goal.get("target_refs", {}) as Dictionary
	match capability_id:
		"world.go_to_place":
			return String(action.get("place", "")) == String(target_refs.get("place_id", ""))
		"world.start_conversation":
			return String(action.get("target_resident_id", "")) == String(target_refs.get("resident_id", ""))
		"world.escort_person_to_place":
			return (
				String(action.get("conversationFollowUpMode", "")) == "escort"
				and String(action.get("followUpPersonId", "")) == String(target_refs.get("person_id", ""))
				and String(action.get("followUpDestinationPlace", "")) == String(target_refs.get("place_id", ""))
				and String(action.get("followUpPhase", "")) in ["leading", "returning_to_companion", "arrived"]
			)
		"world.fetch_service_for_person":
			return (
				String(action.get("conversationFollowUpMode", "")) == "fetch_service"
				and String(action.get("followUpPersonId", "")) == String(target_refs.get("person_id", ""))
				and String(action.get("followUpServicePlace", "")) == String(target_refs.get("service_place_id", ""))
				and String(action.get("followUpServiceActivityId", "")) == String(target_refs.get("service_activity_id", ""))
				and String(action.get("followUpPhase", "")) in ["going_to_source", "collecting", "returning_to_person", "delivered"]
			)
		"world.reply_conversation":
			return String(action.get("conversation_id", "")) == String(target_refs.get("conversation_id", ""))
		"world.wait":
			return wait_target_is_current(host, target_refs, resident_id)
	return false


static func action_type_matches(action_goal: Dictionary, action: Dictionary) -> bool:
	return SOCIAL_JUDGMENTS.social_goal_action_type_matches(action_goal, action)


static func wait_target_is_current(
	host,
	target_refs: Dictionary,
	resident_id: String,
) -> bool:
	var animal_id := String(target_refs.get("animal_id", "")).strip_edges()
	if animal_id.is_empty():
		return true
	var place_id := String(target_refs.get("place_id", "")).strip_edges()
	var resident := host.resident_registry.records.get(resident_id, {}) as Dictionary
	var animal: Dictionary = host._animal_fact_runtime.fact(animal_id)
	if (
		place_id.is_empty()
		or resident.is_empty()
		or animal.is_empty()
		or not host.resident_is_present(resident)
		or not bool(animal.get("exists", false))
		or not bool(animal.get("public_attention", false))
		or String(resident.get("spaceId", "")) != "town_outdoor"
		or String(resident.get("currentPlace", "")) != place_id
		or String(animal.get("place_id", "")) != place_id
	):
		return false
	var resident_position := resident.get("position", Vector2.INF) as Vector2
	var animal_position := animal.get("position", Vector2.INF) as Vector2
	return (
		resident_position.is_finite()
		and animal_position.is_finite()
		and resident_position.distance_to(animal_position)
		<= float(host.world_definition.world_data.get("perceptionRange", 0.0))
	)


static func has_current_animal_wait_assignment(
	host,
	resident_id: String,
	action: Dictionary,
) -> bool:
	for assignment: Dictionary in active_assignments(host, resident_id, ["assigned"]):
		var action_goal := assignment.get("action_goal", {}) as Dictionary
		var target_refs := action_goal.get("target_refs", {}) as Dictionary
		if (
			not String(target_refs.get("animal_id", "")).is_empty()
			and goal_matches_action(host, action_goal, action, resident_id)
		):
			return true
	return false


static func goal_matches_activity(
	action_goal: Dictionary,
	execution: Dictionary,
) -> bool:
	return SOCIAL_JUDGMENTS.social_goal_matches_activity(action_goal, execution)


static func matter_has_active_participants(matter: Dictionary) -> bool:
	return SOCIAL_JUDGMENTS.matter_has_active_social_participants(matter)


static func execution_status(status: String) -> String:
	return SOCIAL_JUDGMENTS.social_execution_status(status)
