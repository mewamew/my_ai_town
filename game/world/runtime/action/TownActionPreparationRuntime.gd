class_name TownActionPreparationRuntime
extends RefCounted


const ACTION_PREPARATION_POLICY := preload(
	"res://world/runtime/action/TownActionPreparationPolicy.gd"
)
const IDLE_ACTION_PREPARATION_RUNTIME := preload(
	"res://world/runtime/action/TownIdleActionPreparationRuntime.gd"
)
const WORLD_PERFORMANCE_PROBE := preload(
	"res://world/runtime/TownWorldPerformanceProbe.gd"
)
const DINING_SERVICE := preload(
	"res://world/runtime/work/TownDiningServiceRuntime.gd"
)
const CONTENT_CATALOG := preload(
	"res://world/data/town/TownWorkContentCatalog.gd"
)
const ROUTE_QUERY := preload(
	"res://world/data/town/TownWorldRouteQuery.gd"
)
const CONVERSATION_RUNTIME := preload(
	"res://world/runtime/conversation/TownConversationRuntime.gd"
)
const PERCEPTION_RUNTIME := preload(
	"res://world/runtime/perception/TownPerceptionRuntime.gd"
)


static func prepare(
	host,
	resident: Dictionary,
	action: Dictionary,
	allow_used_action_id := false,
	issued_snapshot: Dictionary = {},
	allow_closed_clinic_for_injury := false,
) -> Dictionary:
	var entry_failure: Dictionary = ACTION_PREPARATION_POLICY.entry_failure(
		action,
		resident.get("usedActionIds", {}) as Dictionary,
		allow_used_action_id,
	)
	if not entry_failure.is_empty():
		return entry_failure
	var action_type := String(action.get("type", "")).strip_edges()
	match action_type:
		"去":
			return prepare_go_action(
				host,
				resident,
				action,
				allow_closed_clinic_for_injury,
			)
		"用道具", "做活动":
			return ACTION_PREPARATION_POLICY.delegated_action_failure(action_type)
		"调整营业":
			return ACTION_PREPARATION_POLICY.service_adjustment(
				action,
				host.PLACE_SERVICE_COMMAND_RUNTIME.service_control(host, resident),
				int(host._environment.get_absolute_minute()),
			)
		"托人传话":
			var recipient_id := String(
				action.get("recipient_resident_id", ""),
			).strip_edges()
			var sender_id := String(resident.get("residentId", ""))
			return ACTION_PREPARATION_POLICY.private_message(
				action,
				sender_id,
				host.resident_registry.records.has(recipient_id),
				host.private_message_runtime.pending_count_from_sender(sender_id),
				int(host._environment.get_absolute_minute()),
			)
		"搭话":
			return prepare_talk_action(host, String(resident.get("residentId", "")), resident, action)
		"答话":
			return prepare_reply_action(host, String(resident.get("residentId", "")), action)
		"争执", "攻击", "回应冲突", "介入冲突", "离开冲突":
			if host._conflict_agent_world_bridge == null:
				return {"ok": false, "errors": ["冲突系统尚未准备好"]}
			var conflict_preparation: Dictionary = host._conflict_agent_world_bridge.prepare_action(String(resident.get("residentId", "")),
				action,
				issued_snapshot,) as Dictionary
			if conflict_preparation.get("ok") != true:
				return ACTION_PREPARATION_POLICY.conflict_failure(String(
					conflict_preparation.get(
						"errorCode",
						"CONFLICT_ACTION_REJECTED",
					),
				))
			return conflict_preparation
		"待着":
			var prepared: Dictionary = (
				ACTION_PREPARATION_POLICY.wait_action(
					action,
					int(host._environment.get_absolute_minute()),
					int(host._environment.minutes_until_next_period()),
					host.CONTINUITY_WAIT_MAX_MINUTES,
					host.WAIT_ACTION_MAX_MINUTES,
				).get("action", {}) as Dictionary
			)
			DINING_SERVICE.cap_full_wait(host, resident, prepared)
			if host.SOCIAL_GOAL_MATCHING_RUNTIME.has_current_animal_wait_assignment(host,
				String(resident.get("residentId", "")),
				prepared,
			):
				return {"ok": true, "action": prepared}
			var wait_probe_usec: int = WORLD_PERFORMANCE_PROBE.start_lap()
			var parking_attached: bool = (
				IDLE_ACTION_PREPARATION_RUNTIME.attach_parking_route(
					host,
					resident,
					prepared,
				)
			)
			wait_probe_usec = WORLD_PERFORMANCE_PROBE.record_lap(wait_probe_usec, "wait_parking")
			# 室内工作点暂时拥挤时，保留“待着”比把居民改成随机公共地点
			# 的“去”更稳定。后者会先经过建筑门口，看起来像碰撞后专门去
			# 门口逛；下一次决定仍会重新选择可用的室内站位。
			if (
				not parking_attached
				and String(resident.get("spaceId", "")) == "town_outdoor"
			):
				var departure: Dictionary = IDLE_ACTION_PREPARATION_RUNTIME.prepare_departure_action(
					host,
					resident,
					prepared,
				)
				WORLD_PERFORMANCE_PROBE.record_lap(wait_probe_usec, "wait_departure")
				if departure.get("ok") == true:
					return departure
			return {"ok": true, "action": prepared}
		_:
			return ACTION_PREPARATION_POLICY.unknown_action_failure(action_type)



static func prepare_go_action(
	host,
	resident: Dictionary,
	action: Dictionary,
	allow_closed_clinic_for_injury := false,
) -> Dictionary:
	var from_place := String(resident.get("currentPlace", ""))
	var target_place := String(action.get("place", "")).strip_edges()
	if target_place.is_empty() or target_place == from_place:
		return {"ok": false, "errors": ["目标地点必须存在且不同于当前地点"]}
	if (
		host.PLACE_SERVICE_COMMAND_RUNTIME.closed_for_visitor(host, resident, target_place)
		and not (
			allow_closed_clinic_for_injury
			and target_place == CONTENT_CATALOG.PLACE_CLINIC
		)
	):
		return {
			"ok": false,
			"errors": ["%s今天没有营业，不能进去" % target_place],
		}
	var dining_failure: Dictionary = DINING_SERVICE.go_admission_failure(
		host,
		resident,
		target_place,
		int(host._environment.get_absolute_minute()),
	)
	if not dining_failure.is_empty(): return dining_failure
	var route: Dictionary = ROUTE_QUERY.find_route_from_state(
		host.world_definition.world_data,
		{
			"position": resident.get("position", Vector2.ZERO),
			"spaceId": resident.get("spaceId", ""),
			"regionId": resident.get("regionId", ""),
			"currentPlace": from_place,
		},
		target_place,
		resident.get("routeConnector", []) as Array,
	) as Dictionary
	if route.is_empty():
		return {"ok": false, "errors": ["当前没有从 %s 到 %s 的固定路线" % [from_place, target_place]]}
	var prepared: Dictionary = action.duplicate(true)
	prepared["startedAbsoluteMinute"] = int(host._environment.get_absolute_minute())
	prepared["durationMinutes"] = int(route.get("durationMinutes", 0))
	prepared["route"] = route.duplicate(true)
	prepared["completionEffects"] = (
		route.get("completionEffects", route.get("effects", {})) as Dictionary
	).duplicate(true)
	prepared["consumeRouteConnector"] = not (resident.get("routeConnector", []) as Array).is_empty()
	return {"ok": true, "action": prepared}



static func prepare_talk_action(host, resident_name: String, resident: Dictionary, action: Dictionary) -> Dictionary:
	if not CONVERSATION_RUNTIME._active_conversation_for_person(host, resident_name).is_empty():
		return {"ok": false, "errors": ["居民已经在参与另一段对话"]}
	var target_resident_id := String(action.get("target_resident_id", "")).strip_edges()
	var target_ref := target_resident_id
	var target: Dictionary = host._person_state(target_ref)
	if target_ref.is_empty() or target_ref == resident_name or target.is_empty():
		return {"ok": false, "errors": ["搭话对象必须是附近的其他人物"]}
	var postal_delivery: Dictionary = host._private_message_delivery_task_for_talk(
		resident_name,
		target_ref,
		String(action.get("say", "")),
	)
	var medical_binding: Dictionary = host.CLINIC_INTERVIEW_RUNTIME.binding_for_pair(host,
		resident_name,
		target_ref,
	)
	if medical_binding.is_empty():
		medical_binding = host.CLINIC_INTERVIEW_RUNTIME.binding_for_pair(host,
			target_ref,
			resident_name,
		)
	if (
		not PERCEPTION_RUNTIME._are_nearby(host, resident, target)
		and postal_delivery.is_empty()
		and medical_binding.is_empty()
	):
		return {"ok": false, "errors": ["搭话对象已经不在感知范围内"]}
	if not CONVERSATION_RUNTIME._active_conversation_for_person(host, target_ref).is_empty():
		return {"ok": false, "errors": ["搭话对象正在参与其他对话"]}
	if medical_binding.is_empty() and CONVERSATION_RUNTIME._resident_pair_conversation_on_cooldown(host,
		resident_name,
		target_ref,
	):
		return {"ok": false, "errors": ["双方刚结束交谈，稍后再聊"]}
	var turn_error: String = CONVERSATION_RUNTIME._validate_conversation_turn_action(host, resident_name, action, false)
	if not turn_error.is_empty():
		return {"ok": false, "errors": [turn_error]}
	var prepared: Dictionary = action.duplicate(true)
	prepared["target"] = host.person_name_for_id(target_ref)
	prepared["target_resident_id"] = target_ref
	prepared["startedAbsoluteMinute"] = int(host._environment.get_absolute_minute())
	if not medical_binding.is_empty():
		prepared["medicalRequestId"] = String(
			medical_binding.get("requestId", ""),
		)
		prepared["medicalTaskId"] = String(
			medical_binding.get("taskId", ""),
		)
	if not postal_delivery.is_empty() and not PERCEPTION_RUNTIME._are_nearby(host, resident, target):
		prepared["privateMessageId"] = String(
			postal_delivery.get("messageId", ""),
		)
		return host._prepare_postal_talk_approach(
			resident,
			target,
			prepared,
		)
	return {"ok": true, "action": prepared}



static func prepare_reply_action(host, resident_name: String, action: Dictionary) -> Dictionary:
	var conversation: Dictionary = CONVERSATION_RUNTIME._active_conversation_for_person(host, resident_name)
	if conversation.is_empty():
		return {"ok": false, "errors": ["居民当前没有可以答话的对话"]}
	var conversation_id := String(action.get("conversation_id", "")).strip_edges()
	if conversation_id != String(conversation.get("conversationId", "")):
		return {"ok": false, "errors": ["答话的 conversation_id 与当前对话不一致"]}
	if String(conversation.get("waitingFor", "")) != resident_name:
		return {"ok": false, "errors": ["当前对话还没有轮到本居民答话"]}
	var turn_error: String = CONVERSATION_RUNTIME._validate_conversation_turn_action(host, resident_name, action, true)
	if not turn_error.is_empty():
		return {"ok": false, "errors": [turn_error]}
	var prepared: Dictionary = action.duplicate(true)
	prepared["startedAbsoluteMinute"] = int(host._environment.get_absolute_minute())
	return {"ok": true, "action": prepared}
