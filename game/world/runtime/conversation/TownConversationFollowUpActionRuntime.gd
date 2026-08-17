class_name TownConversationFollowUpActionRuntime
extends RefCounted


const PERCEPTION_RUNTIME := preload(
	"res://world/runtime/perception/TownPerceptionRuntime.gd"
)
const ACTION_PRESENTATION := preload(
	"res://world/runtime/presentation/TownActionPresentationSemantics.gd"
)
const ESCORT_RETURN_AFTER_MINUTES := 3


static func decorate(
	host,
	action: Dictionary,
	mode: String,
	phase: String,
	target_refs: Dictionary,
) -> void:
	var now := int(host._environment.get_absolute_minute())
	action["conversationFollowUpMode"] = mode
	action["followUpPhase"] = phase
	action["followUpPersonId"] = String(target_refs.get("person_id", ""))
	action["followUpDestinationPlace"] = String(target_refs.get("place_id", ""))
	action["followUpServicePlace"] = String(target_refs.get("service_place_id", ""))
	action["followUpServiceActivityId"] = String(target_refs.get("service_activity_id", ""))
	action["followUpServiceLabel"] = String(target_refs.get("service_label", ""))
	action["followUpDeadlineMinute"] = now + host.CONVERSATION_FOLLOW_UP_TIMEOUT_MINUTES
	action["followUpLastAdvanceMinute"] = now
	action["followUpLagStartedMinute"] = -1
	action["followUpServiceCollected"] = false
	action["followUpCollectUntilMinute"] = (
		now + host.SERVICE_FETCH_DURATION_MINUTES if phase == "collecting" else -1
	)


static func install_resident_follower(
	host,
	guide_resident_id: String,
	action_goal: Dictionary,
) -> void:
	var target_refs := action_goal.get("target_refs", {}) as Dictionary
	var follower_id := String(target_refs.get("person_id", ""))
	if follower_id.is_empty() or not host.resident_registry.records.has(follower_id):
		return
	var follower := host.resident_registry.records.get(follower_id, {}) as Dictionary
	var destination := String(target_refs.get("place_id", ""))
	var prepared: Dictionary = host.ACTION_PREPARATION_RUNTIME.prepare_go_action(host, follower, {
		"action_id": "escort-follower:%s" % String(action_goal.get("goal_id", "")),
		"type": "去",
		"place": destination,
		"line": "我跟着带路人走",
	})
	if prepared.get("ok") != true:
		begin_reconsideration(
			host,
			guide_resident_id,
			"同行者当前无法沿安全路线跟上，需要重新决定",
		)
		return
	var follower_action := (
		prepared.get("action", {}) as Dictionary
	).duplicate(true)
	decorate(
		host,
		follower_action,
		"escort_follower",
		"following",
		{"person_id": guide_resident_id, "place_id": destination},
	)
	(follower.get("usedActionIds", {}) as Dictionary)[String(
		follower_action.get("action_id", ""),
	)] = true
	install(
		host,
		follower_id,
		follower,
		follower_action,
		"正跟着%s前往%s" % [
			host.person_name_for_id(guide_resident_id),
			destination,
		],
	)


static func service_available(host, action: Dictionary) -> bool:
	var place_id := String(action.get("followUpServicePlace", ""))
	var activity_id := String(action.get("followUpServiceActivityId", ""))
	var state: Dictionary = host._work.place_services.state(place_id)
	return (
		not state.is_empty()
		and bool(state.get("open", false))
		and host.ACTION_SUPPORT.world_data_has_activity_at_place(
			host.world_definition.world_data,
			activity_id,
			place_id,
		)
	)


static func begin_service_collection(
	host,
	resident_id: String,
	resident: Dictionary,
	previous_action: Dictionary,
) -> bool:
	if not service_available(host, previous_action):
		begin_reconsideration(
			host,
			resident_id,
			"到达后发现服务地点已经停业或不再提供这项服务",
		)
		return true
	var now := int(host._environment.get_absolute_minute())
	var next_action := {
		"action_id": String(previous_action.get("action_id", "")),
		"type": "待着",
		"line": "正在取%s" % String(
			previous_action.get("followUpServiceLabel", "东西"),
		),
		"startedAbsoluteMinute": now,
		"completeAbsoluteMinute": now + host.SERVICE_FETCH_DURATION_MINUTES,
	}
	host.ACTION_PROJECTION_MODULE.copy_conversation_follow_up_state(previous_action, next_action)
	next_action["followUpPhase"] = "collecting"
	next_action["followUpCollectUntilMinute"] = (
		now + host.SERVICE_FETCH_DURATION_MINUTES
	)
	install(
		host,
		resident_id,
		resident,
		next_action,
		"正在%s取%s" % [
			String(previous_action.get("followUpServicePlace", "服务地点")),
			String(previous_action.get("followUpServiceLabel", "东西")),
		],
	)
	return true


static func install(
	host,
	resident_id: String,
	resident: Dictionary,
	action: Dictionary,
	doing: String,
) -> void:
	resident["currentAction"] = action
	if bool(action.get("consumeRouteConnector", false)):
		resident["routeConnector"] = []
	resident["actionSuspendedAbsoluteMinute"] = -1
	resident["doing"] = doing
	host.SOCIAL_ASSIGNMENT_RESULT_RUNTIME.start_matching_action(host, resident_id, action)
	host._bump_world_revision(false)
	host._emit_resident_state_changed(resident_id)
	var presented_action: Dictionary = ACTION_PRESENTATION.public_action(host, action)
	presented_action["residentId"] = resident_id
	host.resident_action_started.emit(
		host.resident_display_name(resident_id),
		presented_action,
	)
	host.resident_action_phase_changed.emit(
		resident_id,
		ACTION_PRESENTATION._resident_action_phase_projection(host, resident),
	)


static func timed_out(
	host,
	resident_id: String,
	action: Dictionary,
	absolute_minute: int,
) -> bool:
	if String(action.get("conversationFollowUpMode", "")).is_empty():
		return false
	var deadline := int(action.get("followUpDeadlineMinute", -1))
	if deadline < 0 or absolute_minute <= deadline:
		return false
	host.ACTION_SETTLEMENT_RUNTIME.interrupt(host,
		resident_id,
		"约定持续太久仍未完成，居民结束等待并恢复自己的生活",
	)
	return true


static func pause_active_for_reconsideration(host, reason: String) -> void:
	for resident_id: String in host.resident_registry.order:
		var resident := host.resident_registry.records.get(resident_id, {}) as Dictionary
		var action := resident.get("currentAction", {}) as Dictionary
		if (
			action.is_empty()
			or String(action.get("conversationFollowUpMode", "")).is_empty()
			or String(action.get("conversationFollowUpMode", "")) in [
				"reconsideration_wait",
				"escort_follower",
			]
		):
			continue
		begin_reconsideration(host, resident_id, reason)


static func pause_for_service(
	host,
	place_id: String,
	reason: String,
) -> void:
	for resident_id: String in host.resident_registry.order:
		var resident := host.resident_registry.records.get(resident_id, {}) as Dictionary
		var action := resident.get("currentAction", {}) as Dictionary
		if (
			String(action.get("conversationFollowUpMode", "")) != "fetch_service"
			or String(action.get("followUpServicePlace", "")) != place_id
		):
			continue
		begin_reconsideration(host, resident_id, reason)


static func begin_reconsideration(
	host,
	resident_id: String,
	reason: String,
	queue_fact: bool = true,
) -> void:
	var resident := host.resident_registry.records.get(resident_id, {}) as Dictionary
	var action := resident.get("currentAction", {}) as Dictionary
	if (
		resident.is_empty()
		or action.is_empty()
		or String(action.get("conversationFollowUpMode", "")).is_empty()
		or bool(action.get("followUpPausedForReconsideration", false))
	):
		return
	var normalized_reason := reason.strip_edges()
	if normalized_reason.is_empty():
		normalized_reason = "约定途中的情况已经变化"
	action["followUpPausedForReconsideration"] = true
	action["followUpReconsiderationReason"] = normalized_reason
	action["followUpReconsiderationSinceMinute"] = int(
		host._environment.get_absolute_minute(),
	)
	resident["currentAction"] = action
	resident["doing"] = "正在重新考虑怎样履行刚才的约定"
	if queue_fact:
		host.WORLD_EVENT_DELIVERY_RUNTIME.queue(host, resident_id, {
			"type": "承诺条件变化",
			"summary": normalized_reason,
			"commitment_action_id": String(action.get("action_id", "")),
			"time": host.get_time(),
		})
	host._schedule_decision(resident_id, true, false, true)
	host._bump_world_revision(false)
	host._emit_resident_state_changed(resident_id)


static func resume_after_wait(
	host,
	resident_id: String,
	resident: Dictionary,
	wait_action: Dictionary,
) -> bool:
	var resume_action := (
		wait_action.get("followUpResumeAction", {}) as Dictionary
	).duplicate(true)
	if resume_action.is_empty():
		host.ACTION_SETTLEMENT_RUNTIME.interrupt(host,
			resident_id,
			"等待结束后没有找到可以继续的原约定",
		)
		return true
	var now := int(host._environment.get_absolute_minute())
	if timed_out(host, resident_id, resume_action, now):
		return true
	resume_action["startedAbsoluteMinute"] = now
	resume_action["followUpLastAdvanceMinute"] = now
	install(
		host,
		resident_id,
		resident,
		resume_action,
		"继续履行刚才的约定",
	)
	if (
		String(resume_action.get("conversationFollowUpMode", "")) == "fetch_service"
		and not service_available(host, resume_action)
	):
		begin_reconsideration(
			host,
			resident_id,
			"等待后服务仍不可用，需要再次决定",
		)
	return true


static func resume_reconsideration(host, resident: Dictionary) -> void:
	var action := resident.get("currentAction", {}) as Dictionary
	if not bool(action.get("followUpPausedForReconsideration", false)):
		return
	var now := int(host._environment.get_absolute_minute())
	var paused_at := int(action.get("followUpReconsiderationSinceMinute", now))
	var paused_minutes := maxi(0, now - paused_at)
	for field: String in ["startedAbsoluteMinute", "completeAbsoluteMinute"]:
		if action.has(field):
			action[field] = int(action.get(field, now)) + paused_minutes
	action["followUpLastAdvanceMinute"] = now
	action.erase("followUpPausedForReconsideration")
	action.erase("followUpReconsiderationReason")
	action.erase("followUpReconsiderationSinceMinute")
	resident["currentAction"] = action
	resident["doing"] = host.ACTION_PROJECTION_MODULE.default_doing(host, action)


static func hold_or_return_for_companion(
	host,
	resident_id: String,
	resident: Dictionary,
	action: Dictionary,
	absolute_minute: int,
) -> bool:
	var person_id := String(action.get("followUpPersonId", ""))
	var companion: Dictionary = host._person_state(person_id)
	if (
		companion.is_empty()
		or (
			person_id == host.player_avatar_id()
			and not host.actor_presentation_state.player_avatar_present
		)
	):
		host.ACTION_SETTLEMENT_RUNTIME.interrupt(host, resident_id, "同行者已经离开当前小镇现场")
		return true
	var last_advance := int(
		action.get("followUpLastAdvanceMinute", absolute_minute),
	)
	var step_minutes := maxi(0, absolute_minute - last_advance)
	action["followUpLastAdvanceMinute"] = absolute_minute
	if PERCEPTION_RUNTIME._are_nearby(host, resident, companion):
		action["followUpLagStartedMinute"] = -1
		resident["currentAction"] = action
		resident["doing"] = "正带%s前往%s" % [
			host.person_name_for_id(person_id),
			String(action.get("followUpDestinationPlace", "")),
		]
		return false
	if step_minutes > 0:
		action["startedAbsoluteMinute"] = int(
			action.get("startedAbsoluteMinute", absolute_minute),
		) + step_minutes
	var lag_started := int(action.get("followUpLagStartedMinute", -1))
	if lag_started < 0:
		lag_started = absolute_minute
		action["followUpLagStartedMinute"] = lag_started
	resident["currentAction"] = action
	if absolute_minute - lag_started < ESCORT_RETURN_AFTER_MINUTES:
		resident["doing"] = "停下来等%s跟上" % host.person_name_for_id(person_id)
		host._emit_resident_state_changed(resident_id)
		return true
	return begin_person_approach(
		host,
		resident_id,
		resident,
		action,
		"returning_to_companion",
	)


static func hold_resident_follower(
	host,
	resident_id: String,
	resident: Dictionary,
	action: Dictionary,
	absolute_minute: int,
) -> bool:
	var guide_id := String(action.get("followUpPersonId", ""))
	var guide := host.resident_registry.records.get(guide_id, {}) as Dictionary
	var guide_action := guide.get("currentAction", {}) as Dictionary
	if (
		guide.is_empty()
		or String(guide_action.get("conversationFollowUpMode", "")) != "escort"
		or String(guide_action.get("followUpPersonId", "")) != resident_id
	):
		host.ACTION_SETTLEMENT_RUNTIME.interrupt(host,
			resident_id,
			"带路已经结束，同行者恢复自己的生活",
		)
		return true
	var last_advance := int(
		action.get("followUpLastAdvanceMinute", absolute_minute),
	)
	var step_minutes := maxi(0, absolute_minute - last_advance)
	action["followUpLastAdvanceMinute"] = absolute_minute
	if bool(guide_action.get("followUpPausedForReconsideration", false)):
		if step_minutes > 0:
			action["startedAbsoluteMinute"] = int(
				action.get("startedAbsoluteMinute", absolute_minute),
			) + step_minutes
		resident["currentAction"] = action
		resident["doing"] = "等带路人决定是否继续"
		return true
	resident["currentAction"] = action
	resident["doing"] = "正跟着%s前往%s" % [
		host.person_name_for_id(guide_id),
		String(action.get("followUpDestinationPlace", "")),
	]
	return false


static func continue_after_step(
	host,
	resident_id: String,
	resident: Dictionary,
	action: Dictionary,
) -> bool:
	var mode := String(action.get("conversationFollowUpMode", ""))
	var phase := String(action.get("followUpPhase", ""))
	if mode.is_empty():
		return false
	if mode == "reconsideration_wait":
		return resume_after_wait(host, resident_id, resident, action)
	var person_id := String(action.get("followUpPersonId", ""))
	var person: Dictionary = host._person_state(person_id)
	if (
		person.is_empty()
		or (
			person_id == host.player_avatar_id()
			and not host.actor_presentation_state.player_avatar_present
		)
	):
		host.ACTION_SETTLEMENT_RUNTIME.interrupt(host,
			resident_id,
			"约定的同行者已经离开当前小镇现场",
		)
		return true
	if mode == "escort":
		var destination := String(action.get("followUpDestinationPlace", ""))
		if (
			String(resident.get("currentPlace", "")) == destination
			and String(person.get("currentPlace", "")) == destination
			and PERCEPTION_RUNTIME._are_nearby(host, resident, person)
		):
			action["followUpPhase"] = "arrived"
			resident["currentAction"] = action
			return false
		if (
			phase == "returning_to_companion"
			and PERCEPTION_RUNTIME._are_nearby(host, resident, person)
		):
			return begin_escort_destination_route(
				host,
				resident_id,
				resident,
				action,
			)
		return begin_person_approach(
			host,
			resident_id,
			resident,
			action,
			"returning_to_companion",
		)
	if mode == "fetch_service":
		if phase == "going_to_source":
			return begin_service_collection(
				host,
				resident_id,
				resident,
				action,
			)
		if phase == "collecting":
			action["followUpServiceCollected"] = true
			if PERCEPTION_RUNTIME._are_nearby(host, resident, person):
				action["followUpPhase"] = "delivered"
				resident["currentAction"] = action
				return false
			return begin_person_approach(
				host,
				resident_id,
				resident,
				action,
				"returning_to_person",
			)
		if phase == "returning_to_person":
			if PERCEPTION_RUNTIME._are_nearby(host, resident, person):
				action["followUpPhase"] = "delivered"
				resident["currentAction"] = action
				return false
			return begin_person_approach(
				host,
				resident_id,
				resident,
				action,
				"returning_to_person",
			)
	return false


static func begin_escort_destination_route(
	host,
	resident_id: String,
	resident: Dictionary,
	previous_action: Dictionary,
) -> bool:
	var destination := String(
		previous_action.get("followUpDestinationPlace", ""),
	)
	if String(resident.get("currentPlace", "")) == destination:
		return begin_person_approach(
			host,
			resident_id,
			resident,
			previous_action,
			"returning_to_companion",
		)
	var prepared: Dictionary = host.ACTION_PREPARATION_RUNTIME.prepare_go_action(host, resident, {
		"action_id": String(previous_action.get("action_id", "")),
		"type": "去",
		"place": destination,
		"line": "跟紧我，我们继续走",
	})
	if prepared.get("ok") != true:
		begin_reconsideration(
			host,
			resident_id,
			"重新带路时，前往目的地的路线已经失效",
		)
		return true
	var next_action := (
		prepared.get("action", {}) as Dictionary
	).duplicate(true)
	host.ACTION_PROJECTION_MODULE.copy_conversation_follow_up_state(previous_action, next_action)
	next_action["followUpPhase"] = "leading"
	next_action["followUpLagStartedMinute"] = -1
	next_action["followUpLastAdvanceMinute"] = int(
		host._environment.get_absolute_minute(),
	)
	install(
		host,
		resident_id,
		resident,
		next_action,
		"等到同行者后继续带路",
	)
	return true


static func begin_person_approach(
	host,
	resident_id: String,
	resident: Dictionary,
	previous_action: Dictionary,
	phase: String,
) -> bool:
	var person_id := String(previous_action.get("followUpPersonId", ""))
	var target: Dictionary = host._person_state(person_id)
	if target.is_empty():
		host.ACTION_SETTLEMENT_RUNTIME.interrupt(host,
			resident_id,
			"无法找到约定同行者的有效位置",
		)
		return true
	if PERCEPTION_RUNTIME._are_nearby(host, resident, target):
		if phase == "returning_to_companion":
			return begin_escort_destination_route(
				host,
				resident_id,
				resident,
				previous_action,
			)
		previous_action["followUpPhase"] = "delivered"
		resident["currentAction"] = previous_action
		return false
	var approach_action := {
		"action_id": String(previous_action.get("action_id", "")),
		"type": "搭话",
		"target_resident_id": person_id,
		"target": host.person_name_for_id(person_id),
		"say": "",
		"narration": "我沿安全路线返回约定同行者身边",
		"photos": [],
		"startedAbsoluteMinute": int(host._environment.get_absolute_minute()),
	}
	var prepared: Dictionary = host._prepare_postal_talk_approach(
		resident,
		target,
		approach_action,
	)
	if prepared.get("ok") != true:
		begin_reconsideration(
			host,
			resident_id,
			"无法沿真实路线回到约定同行者身边",
		)
		return true
	var next_action := (
		prepared.get("action", {}) as Dictionary
	).duplicate(true)
	host.ACTION_PROJECTION_MODULE.copy_conversation_follow_up_state(previous_action, next_action)
	next_action["followUpPhase"] = phase
	install(
		host,
		resident_id,
		resident,
		next_action,
		(
			"我回来找你了，跟上来"
			if phase == "returning_to_companion"
			else "正把东西送回约定对象身边"
		),
	)
	return true
