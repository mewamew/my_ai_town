class_name TownConversationFollowUpOptionRuntime
extends RefCounted


const CONVERSATION_RUNTIME := preload(
	"res://world/runtime/conversation/TownConversationRuntime.gd"
)
const FOLLOW_UP_OPTION_PROJECTION := preload(
	"res://world/runtime/conversation/TownConversationFollowUpOptionProjection.gd"
)
const AGENT_WORLD_QUERY_RUNTIME := preload(
	"res://world/runtime/agent/TownAgentWorldQueryRuntime.gd"
)

const MAX_ACTIVE_SOCIAL_COMMITMENTS_PER_RESIDENT := 1


static func options(
	host,
	resident_id: String,
	resident: Dictionary,
	events: Array,
	frame_budgeted := false,
	place_data: Dictionary = {},
) -> Array[Dictionary]:
	var conversation := CONVERSATION_RUNTIME._active_conversation_for_person(
		host,
		resident_id,
	)
	if (
		conversation.is_empty()
		or String(conversation.get("waitingFor", "")) != resident_id
		or not host.ACTION_SUPPORT.inflight_allows_conversation_reply(
			events,
			String(conversation.get("conversationId", "")),
		)
		or host.SOCIAL_GOAL_MATCHING_RUNTIME.active_commitment_count(host, resident_id)
			>= MAX_ACTIVE_SOCIAL_COMMITMENTS_PER_RESIDENT
	):
		return []
	var partner_ref := CONVERSATION_RUNTIME._other_conversation_participant(
		host,
		conversation,
		resident_id,
	)
	var partner_id: String = host.person_id_for_name(partner_ref)
	var requested_place_ids: Array[String] = host.ACTION_SUPPORT.conversation_requested_place_ids(host,
		conversation,
		resident_id,
	)
	var destinations: Array = AGENT_WORLD_QUERY_RUNTIME.travel_destinations(
		host, resident,
	)
	if place_data.has("travelDestinations"):
		destinations = place_data.get("travelDestinations", []) as Array
	var activities: Array = host.AGENT_WAKE_CONTEXT_RUNTIME.available_activities(host, resident, frame_budgeted)
	if place_data.has("activities"):
		activities = place_data.get("activities", []) as Array
	var nearby: Array[Dictionary] = []
	if requested_place_ids.is_empty():
		for nearby_value: Variant in resident.get("nearby", []) as Array:
			var nearby_id: String = host._resident_key(String(nearby_value))
			nearby.append({
				"residentId": nearby_id,
				"displayName": host.resident_display_name(nearby_id),
			})
	var skip_service_offerings := bool(place_data.get("skipServiceOfferings", false))
	var service_offerings: Array[Dictionary] = []
	if not skip_service_offerings and not partner_id.is_empty():
		service_offerings = service_fetch_offerings(host, resident)
	var legacy_options := FOLLOW_UP_OPTION_PROJECTION.legacy_options({
		"residentId": resident_id,
		"partnerId": partner_id,
		"partnerRef": partner_ref,
		"partnerName": host.person_name_for_id(partner_id),
		"currentPlace": String(resident.get("currentPlace", "")),
		"requestedPlaceIds": requested_place_ids,
		"destinations": destinations,
		"activities": activities,
		"nearby": nearby,
		"skipServiceOfferings": skip_service_offerings,
		"serviceOfferings": service_offerings,
	}) as Array[Dictionary]
	if bool(place_data.get("skipNormalize", false)):
		return legacy_options
	return normalize(host, resident_id, conversation, legacy_options)


static func normalize(
	host,
	resident_id: String,
	conversation: Dictionary,
	legacy_options: Array,
) -> Array[Dictionary]:
	var context_ref := {
		"context_type": "conversation",
		"context_id": String(conversation.get("conversationId", "")),
		"context_revision": (conversation.get("turns", []) as Array).size(),
	}
	var adapted := host._action_option_sources.adapt_legacy_options(
		resident_id,
		context_ref,
		legacy_options,
		"promisor",
		0,
	) as Dictionary
	if adapted.get("ok") != true:
		return []
	var candidates := (
		(adapted.get("value", {}) as Dictionary).get("candidates", []) as Array
	)
	var queried := host._action_options.query_options(
		resident_id,
		context_ref,
		candidates,
		int(host._environment.get_absolute_minute()),
		maxi(candidates.size(), 1),
	) as Dictionary
	if queried.get("ok") != true:
		return []
	var result: Array[Dictionary] = []
	for value: Variant in (queried.get("value", {}) as Dictionary).get("items", []) as Array:
		if value is not Dictionary:
			continue
		var option := (value as Dictionary).duplicate(true)
		var target_refs := option.get("target_refs", {}) as Dictionary
		var result_contract := option.get("result_contract", {}) as Dictionary
		option["meaning"] = String(option.get("label", ""))
		option["success_result_id"] = String(result_contract.get("success_result_id", ""))
		option["place_id"] = String(
			target_refs.get("place_id", target_refs.get("service_place_id", ""))
		)
		result.append(option)
	return result


static func service_fetch_offerings(host, resident: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for state_value: Variant in host._work.place_services.values_snapshot():
		var state := state_value as Dictionary
		if not bool(state.get("open", false)):
			continue
		var place_id := String(state.get("place_id", ""))
		if place_id.is_empty() or host.PLACE_SERVICE_COMMAND_RUNTIME.closed_for_visitor(host, resident, place_id):
			continue
		var detail: Dictionary = host.get_place_detail(place_id)
		var capabilities := detail.get("capabilities", {}) as Dictionary
		var activity_id := ""
		var service_label := ""
		if bool(capabilities.get("food.prepare", false)):
			for request_value: Variant in state.get("request_activity_ids", []) as Array:
				var request_id := String(request_value)
				if host.ACTION_SUPPORT.world_data_has_activity_at_place(
					host.world_definition.world_data, request_id, place_id,
				):
					activity_id = request_id
					break
			service_label = "一份饭菜"
		elif (
			bool(capabilities.get("drink.prepare", false))
			and host.ACTION_SUPPORT.world_data_has_activity_at_place(
				host.world_definition.world_data,
				"activity_cafe_eat_pastry",
				place_id,
			)
		):
			activity_id = "activity_cafe_eat_pastry"
			service_label = "一份点心"
		if activity_id.is_empty() or service_label.is_empty():
			continue
		var route_available := (
			place_id == String(resident.get("currentPlace", ""))
			or not (
				host.ACTION_PREPARATION_RUNTIME.prepare_go_action(host,
					resident,
					{
						"action_id": "conversation-service-query",
						"type": "去",
						"place": place_id,
						"line": "查询服务地点",
					},
				).get("action", {}) as Dictionary
			).is_empty()
		)
		if route_available:
			result.append({
				"place_id": place_id,
				"activity_id": activity_id,
				"service_label": service_label,
			})
	result.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			return String(left.get("place_id", "")) < String(right.get("place_id", ""))
	)
	return result
