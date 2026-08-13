extends RefCounted


const AGENT_WAKE_STATE_RUNTIME := preload(
	"res://world/runtime/TownAgentWakeStateRuntime.gd"
)
const PROP_QUERY := preload("res://world/data/town/TownWorldPropQuery.gd")
const ROUTE_QUERY := preload("res://world/data/town/TownWorldRouteQuery.gd")
const CONVERSATION_RUNTIME := preload(
	"res://world/runtime/conversation/TownConversationRuntime.gd"
)
const DINING_SERVICE := preload(
	"res://world/runtime/work/TownDiningServiceRuntime.gd"
)
const ACTION_PRESENTATION := preload(
	"res://world/runtime/presentation/TownActionPresentationSemantics.gd"
)

var _preparations: Dictionary = {}
var _visible_props_cache: Dictionary = {}
var _conversation_service_route_cache: Dictionary = {}


func clear() -> void:
	_preparations.clear()
	_visible_props_cache.clear()
	_conversation_service_route_cache.clear()


func clear_resident(resident_id: String, decision_id: String = "") -> void:
	if resident_id.is_empty():
		return
	if not decision_id.is_empty():
		_preparations.erase("%s|%s" % [resident_id, decision_id])
		return
	for key_value: Variant in _preparations.keys():
		var key := String(key_value)
		if key.begins_with("%s|" % resident_id):
			_preparations.erase(key)


func advance(world, resident_ref: String, decision_id: String) -> Dictionary:
	var resident_id: String = world._resident_key(resident_ref)
	if (
		resident_id.is_empty()
		or not world._running
		or not world._residents.has(resident_id)
	):
		clear_resident(resident_id, decision_id)
		return {"ok": false, "stale": true}
	var resident := world._residents[resident_id] as Dictionary
	if (
		not world._resident_is_present(resident)
		or not bool(resident.get("decisionPending", false))
		or String(resident.get("validDecisionId", "")) != decision_id
	):
		clear_resident(resident_id, decision_id)
		return {"ok": false, "stale": true}
	var preparation_key := "%s|%s" % [resident_id, decision_id]
	for existing_key_value: Variant in _preparations.keys():
		var existing_key := String(existing_key_value)
		if existing_key.begins_with("%s|" % resident_id) and existing_key != preparation_key:
			_preparations.erase(existing_key)
	var preparation := _preparations.get(preparation_key, {}) as Dictionary
	if (
		preparation.is_empty()
		or String(preparation.get("decisionId", "")) != decision_id
	):
		preparation = _new_preparation(world, resident_id, resident, decision_id)
		_preparations[preparation_key] = preparation
	var step_result := _advance_preparation(world, preparation)
	if not bool(step_result.get("ready", false)):
		_preparations[preparation_key] = preparation
		return {
			"ok": true,
			"stale": false,
			"preparationPending": true,
			"stage": String(step_result.get("stage", preparation.get("stage", ""))),
		}
	resident["pendingWake"] = (
		preparation.get("wakePacket", {}) as Dictionary
	).duplicate(true)
	_preparations.erase(preparation_key)
	AGENT_WAKE_STATE_RUNTIME.mark_built(
		resident,
		int(world._environment.get_absolute_minute()),
		world.get_weather(),
	)
	return {
		"ok": true,
		"stale": false,
		"residentId": resident_id,
		"decisionId": decision_id,
		"wakePacket": (resident.get("pendingWake", {}) as Dictionary).duplicate(true),
	}


func _new_preparation(
	world,
	resident_id: String,
	resident: Dictionary,
	decision_id: String,
) -> Dictionary:
	var resident_snapshot := resident.duplicate(true)
	var pending_wake := resident_snapshot.get("pendingWake", {}) as Dictionary
	var perception_resident := resident_snapshot
	var prefetch_arrival_context: bool = bool(
		resident_snapshot.get("decisionPrefetch", false)
	) and bool(world._go_action_can_prefetch_decision(
		resident_snapshot.get("currentAction", {}) as Dictionary,
	))
	if prefetch_arrival_context:
		var arrival_projection: Dictionary = world._go_action_arrival_projection(resident_snapshot) as Dictionary
		if not arrival_projection.is_empty():
			perception_resident = resident_snapshot.duplicate(true)
			perception_resident["spaceId"] = arrival_projection.get("spaceId", "")
			perception_resident["regionId"] = arrival_projection.get("regionId", "")
			perception_resident["currentPlace"] = arrival_projection.get("currentPlace", "")
			perception_resident["position"] = arrival_projection.get("position", Vector2.ZERO)
			perception_resident["currentAction"] = {}
	var events_source := resident_snapshot.get("inflightEvents", []) as Array
	if pending_wake.get("events") is Array:
		events_source = pending_wake.get("events", []) as Array
	var results_source := resident_snapshot.get("inflightResults", []) as Array
	if pending_wake.get("action_results") is Array:
		results_source = pending_wake.get("action_results", []) as Array
	return {
		"residentId": resident_id,
		"decisionId": decision_id,
		"resident": resident_snapshot,
		"perceptionResident": perception_resident,
		"events": events_source.duplicate(true),
		"results": results_source.duplicate(true),
		"socialResults": AGENT_WAKE_STATE_RUNTIME.preserved_social_results(pending_wake),
		"frameBudgeted": true,
		"prefetchArrivalContext": prefetch_arrival_context,
		"absoluteMinute": int(world._environment.get_absolute_minute()),
		"weather": world.get_weather(),
		"time": world.get_time(),
		"stage": "nearby",
		"nearby": [],
		"publicEvents": [],
		"publicResults": [],
		"lifeDestinationOptions": [],
		"travelDestinations": [],
		"visibleProps": [],
		"availableProps": [],
		"activities": [],
		"placeSnapshot": {},
		"conversationFollowUpOptions": [],
		"conversationSnapshot": {},
		"conversationTravelDestinations": [],
		"conversationActivities": [],
		"conversationServiceStates": [],
		"conversationServiceStatesInitialized": false,
		"conversationServiceIndex": 0,
		"conversationServiceOfferings": [],
		"conversationServiceCandidate": {},
		"conversationContext": {},
		"conversationCandidates": [],
		"nearbyIds": [],
		"conflictSnapshot": {},
		"socialMatters": [],
		"socialExposures": [],
		"postInjuryReaction": {},
		"wakePacket": {},
	}


func _advance_preparation(world, preparation: Dictionary) -> Dictionary:
	var resident_id := String(preparation.get("residentId", ""))
	var resident := preparation.get("resident", {}) as Dictionary
	var perception_resident := preparation.get("perceptionResident", {}) as Dictionary
	var decision_id := String(preparation.get("decisionId", ""))
	var events := preparation.get("events", []) as Array
	var stage := String(preparation.get("stage", "nearby"))
	match stage:
		"nearby":
			var nearby: Array[Dictionary] = []
			for other_name_value: Variant in resident.get("nearby", []) as Array:
				var other_name := String(other_name_value)
				var other: Dictionary = world._person_state(other_name) as Dictionary
				nearby.append({
					"resident_id": world._person_id_for_name(other_name),
					"name": world._person_name_for_id(world._person_id_for_name(other_name)),
					"doing": String(other.get("doing", "")),
					"available_for_conversation": CONVERSATION_RUNTIME._active_conversation_for_person(world, other_name).is_empty(),
				})
			preparation["nearby"] = nearby
			preparation["publicEvents"] = world._agent_fact_payloads(events)
			preparation["publicResults"] = world._agent_fact_payloads(
				preparation.get("results", []) as Array,
			)
			var social_results_value: Variant = preparation.get("socialResults")
			if social_results_value is Array:
				preparation["socialResults"] = (social_results_value as Array).duplicate(true)
			else:
				preparation["socialResults"] = world._social_agent_adapter.take_social_response_results(
					resident_id,
				) as Array[Dictionary]
			preparation["stage"] = "travel"
		"travel":
			preparation["travelDestinations"] = world._agent_travel_destinations(perception_resident)
			preparation["stage"] = "life"
		"life":
			preparation["lifeDestinationOptions"] = world._agent_life_destination_options(
				perception_resident,
				preparation.get("travelDestinations", []) as Array[String],
			)
			preparation["stage"] = "visible_props"
		"visible_props":
			preparation["visibleProps"] = visible_props(world, perception_resident)
			preparation["stage"] = "available_props"
		"available_props":
			preparation["availableProps"] = world._agent_available_props(perception_resident)
			preparation["stage"] = "activities"
		"activities":
			preparation["activities"] = world._agent_available_activities(
				perception_resident,
				true,
			)
			preparation["stage"] = "place"
		"place":
			var place_snapshot := {
				"name": String(perception_resident.get("currentPlace", "")),
				"destinations": preparation.get("travelDestinations", []) as Array,
				"visible_props": preparation.get("visibleProps", []) as Array,
				"props": preparation.get("availableProps", []) as Array,
				"activities": preparation.get("activities", []) as Array,
				"service_control": world._service_control_for_resident(perception_resident),
				"message_recipients": world._ordinary_private_message_recipients(resident_id),
			}
			DINING_SERVICE.attach_capacity_status(
				world,
				place_snapshot,
				String(perception_resident.get("residentId", "")),
				String(perception_resident.get("currentPlace", "")),
				int(preparation.get("absoluteMinute", 0)),
			)
			var priority_service_task: Dictionary = world._priority_onsite_service_task_for_resident(
				String(resident.get("residentId", "")),
			)
			if not priority_service_task.is_empty():
				world._focus_agent_place_snapshot_on_service_task(
					perception_resident,
					place_snapshot,
					priority_service_task,
				)
			preparation["placeSnapshot"] = place_snapshot
			preparation["stage"] = "conversation_context"
		"conversation_context":
			if bool(preparation.get("prefetchArrivalContext", false)):
				preparation["conversationTravelDestinations"] = world._agent_travel_destinations(resident)
				preparation["conversationActivities"] = world._agent_available_activities(
					resident,
					true,
				)
			else:
				preparation["conversationTravelDestinations"] = preparation.get(
					"travelDestinations",
					[],
				) as Array
				preparation["conversationActivities"] = preparation.get(
					"activities",
					[],
				) as Array
			preparation["stage"] = "conversation"
		"conversation":
			preparation["conversationSnapshot"] = CONVERSATION_RUNTIME._active_conversation_for_person(
				world,
				resident_id,
			)
			preparation["conversationFollowUpOptions"] = world._conversation_follow_up_options(
				resident_id,
				resident,
				preparation.get("publicEvents", []) as Array,
				true,
				{
					"travelDestinations": preparation.get("conversationTravelDestinations", []) as Array,
					"activities": preparation.get("conversationActivities", []) as Array,
					"skipNormalize": true,
					"skipServiceOfferings": true,
				},
			)
			preparation["stage"] = "conversation_services"
		"conversation_services":
			var partner_ref := CONVERSATION_RUNTIME._other_conversation_participant(
				world,
				preparation.get("conversationSnapshot", {}) as Dictionary,
				resident_id,
			)
			if world._person_id_for_name(partner_ref).is_empty():
				preparation["stage"] = (
					"social"
					if (preparation.get("conversationFollowUpOptions", []) as Array).is_empty()
					else "conversation_adapt"
				)
				return {"ready": false, "stage": String(preparation.get("stage", "social"))}
			if not bool(preparation.get("conversationServiceStatesInitialized", false)):
				preparation["conversationServiceStates"] = world._place_service_states.values()
				preparation["conversationServiceStatesInitialized"] = true
			var service_states := preparation.get("conversationServiceStates", []) as Array
			var service_index := int(preparation.get("conversationServiceIndex", 0))
			if service_index < service_states.size():
				var service_state := service_states[service_index] as Dictionary
				preparation["conversationServiceIndex"] = service_index + 1
				preparation["conversationServiceCandidate"] = conversation_service_candidate(
					world,
					resident,
					service_state,
				)
				preparation["stage"] = "conversation_service_route"
				return {"ready": false, "stage": "conversation_services"}
			var service_options := conversation_service_options_from_offerings(
				world,
				resident_id,
				resident,
				preparation.get("conversationSnapshot", {}) as Dictionary,
				preparation.get("conversationServiceOfferings", []) as Array,
			) as Array[Dictionary]
			(preparation.get("conversationFollowUpOptions", []) as Array).append_array(service_options)
			if (preparation.get("conversationFollowUpOptions", []) as Array).is_empty():
				preparation["stage"] = "social"
			else:
				preparation["stage"] = "conversation_adapt"
		"conversation_service_route":
			var candidate := preparation.get("conversationServiceCandidate", {}) as Dictionary
			if candidate.is_empty():
				preparation["stage"] = "conversation_services"
				return {"ready": false, "stage": "conversation_services"}
			var route_result := conversation_service_route_available(
				world,
				resident,
				String(candidate.get("place_id", "")),
			)
			if (
				not bool(route_result.get("ok", false))
				or (route_result.get("action", {}) as Dictionary).is_empty()
			):
				preparation["stage"] = "conversation_services"
				return {"ready": false, "stage": "conversation_service_route"}
			(preparation.get("conversationServiceOfferings", []) as Array).append(candidate)
			preparation["stage"] = "conversation_services"
			return {"ready": false, "stage": "conversation_service_route"}
		"conversation_adapt":
			var adapted := adapt_conversation_options(
				world,
				resident_id,
				preparation.get("conversationSnapshot", {}) as Dictionary,
				preparation.get("conversationFollowUpOptions", []) as Array,
			) as Dictionary
			if not bool(adapted.get("ok", false)):
				preparation["conversationFollowUpOptions"] = []
				preparation["stage"] = "social"
			else:
				preparation["conversationContext"] = adapted.get("context", {}) as Dictionary
				preparation["conversationCandidates"] = adapted.get("candidates", []) as Array
				preparation["stage"] = "conversation_query"
		"conversation_query":
			preparation["conversationFollowUpOptions"] = query_conversation_options(
				world,
				resident_id,
				preparation.get("conversationContext", {}) as Dictionary,
				preparation.get("conversationCandidates", []) as Array,
			)
			preparation["stage"] = "social"
		"social":
			var nearby_ids: Array[String] = []
			for nearby_value: Variant in preparation.get("nearby", []) as Array:
				var nearby_id := String((nearby_value as Dictionary).get("resident_id", "")).strip_edges()
				if not nearby_id.is_empty():
					nearby_ids.append(nearby_id)
			preparation["nearbyIds"] = nearby_ids
			preparation["conflictSnapshot"] = world._agent_conflict_snapshot(
				resident_id,
				resident,
				nearby_ids,
			)
			preparation["socialMatters"] = world._social_agent_adapter.build_social_matters(
				resident_id,
				int(preparation.get("absoluteMinute", 0)),
			) as Array[Dictionary]
			preparation["socialExposures"] = (
				[] if world._inflight_requires_reply(events)
				else world.get_agent_social_exposures(resident_id)
			)
			preparation["postInjuryReaction"] = world._post_injury_reaction_for_events(
				resident_id,
				events,
			)
			preparation["stage"] = "finalize"
		"finalize":
			var conflict_snapshot := preparation.get("conflictSnapshot", {}) as Dictionary
			preparation["wakePacket"] = {
				"decision_id": decision_id,
				"snapshot": {
					"time": (preparation.get("time", {}) as Dictionary).duplicate(true),
					"weather": String(preparation.get("weather", "")),
					"weather_context": world._activity_runtime.weather_context(
						String(preparation.get("weather", "")),
						String(perception_resident.get("currentPlace", "")),
					),
					"me": {
						"doing": String(perception_resident.get("doing", "")),
						"current_action": ACTION_PRESENTATION._agent_current_action(
							world,
							perception_resident.get("currentAction", {}) as Dictionary,
						),
						"body": (perception_resident.get("body", {}) as Dictionary).duplicate(true),
						"activityNeeds": (perception_resident.get("activityState", world._empty_activity_state()) as Dictionary).duplicate(true),
						"conditions": world._resident_conditions.get_conditions(resident_id,) as Array,
						"activeNeeds": world._resident_conditions.get_active_needs(resident_id,) as Array,
					},
					"nearby": preparation.get("nearby", []) as Array,
					"place": preparation.get("placeSnapshot", {}) as Dictionary,
					"rhythm": world._life_rhythm_snapshot(resident),
					"work_tasks": world.get_work_tasks_for_resident(resident_id),
					"life_destination_options": preparation.get("lifeDestinationOptions", []) as Array,
					"known_announcements": world._agent_known_announcements(resident_id),
					"conversation": world._duplicate_optional_dictionary(resident.get("conversation")),
					"conversation_follow_up_options": preparation.get("conversationFollowUpOptions", []) as Array,
					"social_matters": preparation.get("socialMatters", []) as Array,
					"social_exposures": preparation.get("socialExposures", []) as Array,
					"conflicts": (conflict_snapshot.get("conflicts", []) as Array).duplicate(true),
					"conflict_injuries": (conflict_snapshot.get("conflict_injuries", []) as Array).duplicate(true),
					"conflict_tension_options": (conflict_snapshot.get("conflict_tension_options", []) as Array).duplicate(true),
					"medical_follow_up": (conflict_snapshot.get("medical_follow_up", {}) as Dictionary).duplicate(true),
					"post_injury_reaction": preparation.get("postInjuryReaction", {}) as Dictionary,
				},
				"events": preparation.get("publicEvents", []) as Array,
				"action_results": preparation.get("publicResults", []) as Array,
				"social_response_results": preparation.get("socialResults", []) as Array,
			}
			return {"ready": true}
		_:
			preparation["stage"] = "nearby"
	return {"ready": false, "stage": stage}


func visible_props(world, resident: Dictionary) -> Array[String]:
	var place := String(resident.get("currentPlace", ""))
	var cache_key := "%s|%s" % [place, str(world._dynamic_props)]
	if _visible_props_cache.has(cache_key):
		return (_visible_props_cache[cache_key] as Array[String]).duplicate()
	var result: Array[String] = []
	for prop_value: Variant in PROP_QUERY.agent_props_at_place(
		world._prop_query_data(),
		place,
	):
		var prop_name := String((prop_value as Dictionary).get("name", "")).strip_edges()
		if not prop_name.is_empty() and not result.has(prop_name):
			result.append(prop_name)
	result.sort()
	_visible_props_cache[cache_key] = result.duplicate()
	return result


func adapt_conversation_options(
	world,
	resident_id: String,
	conversation: Dictionary,
	legacy_options: Array,
) -> Dictionary:
	var context := {
		"context_type": "conversation",
		"context_id": String(conversation.get("conversationId", "")),
		"context_revision": (conversation.get("turns", []) as Array).size(),
	}
	var adapted := world._action_option_sources.adapt_legacy_options(
		resident_id,
		context,
		legacy_options,
		"promisor",
		0,
	) as Dictionary
	if adapted.get("ok") != true:
		return {"ok": false}
	return {
		"ok": true,
		"context": context,
		"candidates": (
			(adapted.get("value", {}) as Dictionary).get("candidates", []) as Array
		),
	}


func conversation_service_options_from_offerings(
	world,
	resident_id: String,
	resident: Dictionary,
	conversation: Dictionary,
	offerings: Array,
) -> Array[Dictionary]:
	var partner_ref := CONVERSATION_RUNTIME._other_conversation_participant(
		world,
		conversation,
		resident_id,
	)
	var partner_id: String = world._person_id_for_name(partner_ref)
	if partner_id.is_empty():
		return []
	var requested_place_ids: Array[String] = world._conversation_requested_place_ids(
		conversation,
		resident_id,
	)
	var result: Array[Dictionary] = []
	for offering_value: Variant in offerings:
		if not offering_value is Dictionary:
			continue
		var offering := offering_value as Dictionary
		var service_place := String(offering.get("place_id", ""))
		if not requested_place_ids.is_empty() and not requested_place_ids.has(service_place):
			continue
		var service_activity := String(offering.get("activity_id", ""))
		var service_label := String(offering.get("service_label", ""))
		result.append({
			"option_id": "fetch-service:%s:%s:%s" % [partner_id, service_place, service_activity],
			"meaning": "请%s等候，前往%s取得%s后返回对方身边" % [world._person_name_for_id(partner_id), service_place, service_label],
			"capability_id": "world.fetch_service_for_person",
			"target_refs": {
				"person_id": partner_id,
				"service_place_id": service_place,
				"service_activity_id": service_activity,
				"service_label": service_label,
			},
			"success_result_id": "conversation-service-delivered",
			"place_id": service_place,
		})
	return result


func conversation_service_candidate(
	world,
	resident: Dictionary,
	state: Dictionary,
) -> Dictionary:
	if not bool(state.get("open", false)):
		return {}
	var place_id := String(state.get("place_id", ""))
	if place_id.is_empty() or world._closed_service_place_for_visitor(
		resident,
		place_id,
	):
		return {}
	var detail: Dictionary = world.get_place_detail(place_id) as Dictionary
	var capabilities := detail.get("capabilities", {}) as Dictionary
	var activity_id := ""
	var service_label := ""
	if bool(capabilities.get("food.prepare", false)):
		for request_value: Variant in state.get(
			"request_activity_ids",
			[],
		) as Array:
			var request_id := String(request_value)
			if world._world_data_has_activity_at_place(
				world._world_data,
				request_id,
				place_id,
			):
				activity_id = request_id
				break
		service_label = "一份饭菜"
	elif (
		bool(capabilities.get("drink.prepare", false))
		and world._world_data_has_activity_at_place(
			world._world_data,
			"activity_cafe_eat_pastry",
			place_id,
		)
	):
		activity_id = "activity_cafe_eat_pastry"
		service_label = "一份点心"
	if activity_id.is_empty() or service_label.is_empty():
		return {}
	return {
		"place_id": place_id,
		"activity_id": activity_id,
		"service_label": service_label,
	}


func conversation_service_route_available(
	world,
	resident: Dictionary,
	target_place: String,
) -> Dictionary:
	var from_place := String(resident.get("currentPlace", ""))
	if target_place.is_empty() or target_place == from_place:
		return {
			"ok": target_place == from_place,
			# 同地点不需要构造寻路动作，但仍是可用的服务选项。
			"action": {"samePlace": true} if target_place == from_place else {},
		}
	var dining_failure := DINING_SERVICE.go_admission_failure(
		world,
		resident,
		target_place,
		int(world._environment.get_absolute_minute()),
	) as Dictionary
	if not dining_failure.is_empty():
		return {"ok": false, "action": {}, "errors": dining_failure.get("errors", [])}
	var connector := resident.get("routeConnector", []) as Array
	var data := world._world_data as Dictionary
	# 唤醒阶段只需要决定服务选项是否值得提供。无运行时连接器时，使用
	# 已建好的地点级路网判断，避免在 Agent 准备阶段冷启动室外落点寻路。
	# 真正执行“去”动作时仍由 World._prepare_go_action 使用居民当前位置
	# 重新做完整的 find_route_from_state 校验，不改变实际寻路和失败语义。
	if connector.is_empty():
		var place_route_exists := ROUTE_QUERY.place_route_exists(
			data,
			from_place,
			target_place,
		)
		return {
			"ok": place_route_exists,
			"action": {"placeRouteAvailable": true} if place_route_exists else {},
		}
	var cache_key := "%s|%s|%s|%s|%s|%s|%s|%s|%s" % [
		str(data.get("worldId", "")),
		str(data.get("schemaVersion", "")),
		str(data.get("dataVersion", "")),
		from_place,
		target_place,
		str(resident.get("position", Vector2.ZERO)),
		str(resident.get("spaceId", "")),
		str(resident.get("regionId", "")),
		str(connector),
	]
	var route: Dictionary
	if _conversation_service_route_cache.has(cache_key):
		route = _conversation_service_route_cache[cache_key] as Dictionary
	else:
		route = ROUTE_QUERY.find_route_from_state(
		data,
		{
			"position": resident.get("position", Vector2.ZERO),
			"spaceId": resident.get("spaceId", ""),
			"regionId": resident.get("regionId", ""),
			"currentPlace": from_place,
		},
		target_place,
		connector,
		) as Dictionary
		_conversation_service_route_cache[cache_key] = route.duplicate(true)
	return {"ok": not route.is_empty(), "action": route}


func query_conversation_options(
	world,
	resident_id: String,
	context: Dictionary,
	candidates: Array,
) -> Array[Dictionary]:
	var queried := world._action_options.query_options(
		resident_id,
		context,
		candidates,
		int(world._environment.get_absolute_minute()),
		maxi(candidates.size(), 1),
	) as Dictionary
	if queried.get("ok") != true:
		return []
	var result: Array[Dictionary] = []
	for value: Variant in (queried.get("value", {}) as Dictionary).get("items", []) as Array:
		if not value is Dictionary:
			continue
		var option := (value as Dictionary).duplicate(true)
		var target_refs := option.get("target_refs", {}) as Dictionary
		var result_contract := option.get("result_contract", {}) as Dictionary
		option["meaning"] = String(option.get("label", ""))
		option["success_result_id"] = String(result_contract.get("success_result_id", ""))
		option["place_id"] = String(target_refs.get(
			"place_id",
			target_refs.get("service_place_id", ""),
		))
		result.append(option)
	return result


func travel_destinations(world, resident: Dictionary) -> Array[String]:
	var current_place := String(resident.get("currentPlace", ""))
	var result: Array[String] = []
	for place_name: String in world.get_place_names():
		if (
			place_name.is_empty()
			or place_name == current_place
			or world._closed_service_place_for_visitor(resident, place_name)
			or not DINING_SERVICE.travel_destination_available(
				world,
				resident,
				place_name,
				int(world._environment.get_absolute_minute()),
			)
		):
			continue
		result.append(place_name)
	return result
