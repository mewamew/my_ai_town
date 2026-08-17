class_name TownActionAdvancementRuntime
extends RefCounted


const CONVERSATION_RUNTIME := preload(
	"res://world/runtime/conversation/TownConversationRuntime.gd"
)
const FOLLOW_UP_RUNTIME := preload(
	"res://world/runtime/conversation/TownConversationFollowUpActionRuntime.gd"
)
const PERCEPTION_RUNTIME := preload(
	"res://world/runtime/perception/TownPerceptionRuntime.gd"
)
const GO_ACTION_PREFETCH_RUNTIME := preload(
	"res://world/runtime/movement/TownGoActionPrefetchRuntime.gd"
)
const PLACE_SERVICE_COMMAND_RUNTIME := preload(
	"res://world/runtime/work/TownPlaceServiceCommandRuntime.gd"
)


static func advance_all(host, absolute_minute: int) -> void:
	for resident_id: String in host.resident_registry.order:
		var resident := host.resident_registry.records[resident_id] as Dictionary
		if not host.resident_is_present(resident):
			continue
		var action := resident.get("currentAction", {}) as Dictionary
		if bool(resident.get("decisionPending", false)) and action.is_empty():
			continue
		if bool(action.get("followUpPausedForReconsideration", false)):
			continue
		if int(resident.get("actionSuspendedAbsoluteMinute", -1)) >= 0:
			if not CONVERSATION_RUNTIME._active_conversation_for_person(
				host,
				resident_id,
			).is_empty():
				continue
			host.ACTION_TIMING.resume_suspended_action(host, resident)
			action = resident.get("currentAction", {}) as Dictionary
		var complete_minute := int(action.get("completeAbsoluteMinute", -1))
		if (
			not action.is_empty()
			and not bool(resident.get("decisionPending", false))
			and (
				String(action.get("type", "")) != "去"
				or GO_ACTION_PREFETCH_RUNTIME.can_prefetch(action)
			)
			and String(action.get("conversationFollowUpMode", "")).is_empty()
			and String(action.get("serviceRequestId", "")).is_empty()
			and complete_minute >= absolute_minute
			and complete_minute - absolute_minute
				<= host.ACTION_DECISION_PREFETCH_MINUTES
		):
			host._schedule_decision(resident_id, false, true)
			action = resident.get("currentAction", {}) as Dictionary
		var probe_lap_usec := (
			Time.get_ticks_usec()
			if host.telemetry.advance_profile_enabled
			else 0
		)
		if not action.is_empty() and not host.ACTION_VALIDITY_POLICY.is_valid(host, resident, action):
			var activity_execution := host._activity_runtime.execution_for_action(
				resident_id,
				String(action.get("action_id", "")),
			) as Dictionary
			if (
				activity_execution.is_empty()
				and not String(
					action.get("conversationFollowUpMode", ""),
				).is_empty()
			):
				FOLLOW_UP_RUNTIME.begin_reconsideration(
					host,
					resident_id,
					"行动条件已经变化，需要重新决定怎样履行约定",
				)
			elif activity_execution.is_empty():
				host.ACTION_SETTLEMENT_RUNTIME.interrupt(host, resident_id, "动作执行条件已经失效")
			else:
				host.ACTIVITY_ACTION_SETTLEMENT_RUNTIME.fail(host,
					resident_id,
					"ACTIVITY_STATE_CHANGED",
					"活动执行条件已经失效",
				)
			continue
		match String(action.get("type", "")):
			"去":
				host.GO_ACTION_ADVANCEMENT_RUNTIME.advance(host,
					resident_id,
					resident,
					action,
					absolute_minute,
				)
			"用道具":
				host.PROP_ACTION_ADVANCEMENT_RUNTIME.advance(host,
					resident_id,
					resident,
					action,
					absolute_minute,
				)
			"调整营业":
				if absolute_minute >= int(
					action.get("completeAbsoluteMinute", INF),
				):
					PLACE_SERVICE_COMMAND_RUNTIME.finish_control_action(
						host, resident_id, action,
					)
			"托人传话":
				if absolute_minute >= int(
					action.get("completeAbsoluteMinute", INF),
				):
					host.PRIVATE_MESSAGE_DELIVERY_RUNTIME.finish_sender_action(host, resident_id, action)
			"搭话":
				if not String(action.get("approachMode", "")).is_empty():
					advance_postal_talk_approach(
						host,
						resident_id,
						resident,
						action,
						absolute_minute,
					)
			"待着":
				host.WAIT_ACTION_ADVANCEMENT_RUNTIME.advance(host,
					resident_id,
					resident,
					action,
					absolute_minute,
				)
		if host.telemetry.advance_profile_enabled:
			var probe_type := String(action.get("type", "无"))
			host.telemetry.lap(
				host.telemetry.advance_profile_scratch,
				"actions:%sUsec" % probe_type,
				probe_lap_usec,
			)
			host.telemetry.count_advance_profile("actions:%sCount" % probe_type, 1)


static func advance_postal_talk_approach(
	host,
	resident_id: String,
	resident: Dictionary,
	action: Dictionary,
	absolute_minute: int,
) -> void:
	var target_id := String(action.get("target_resident_id", ""))
	var target: Dictionary = host._person_state(target_id)
	if target.is_empty():
		host.ACTION_SETTLEMENT_RUNTIME.interrupt(host, resident_id, "收件人已经不在小镇中")
		return
	var elapsed := maxi(
		0,
		absolute_minute - int(
			action.get("startedAbsoluteMinute", absolute_minute),
		),
	)
	var duration := maxi(0, int(action.get("durationMinutes", 0)))
	var approach_mode := String(action.get("approachMode", ""))
	if approach_mode == "same_space_path":
		var path: Array[Vector2] = []
		path.assign(action.get("pathPoints", []) as Array)
		if path.is_empty():
			host.ACTION_SETTLEMENT_RUNTIME.interrupt(host,
				resident_id,
				"到收件人身边的路线已经失效",
			)
			return
		var ratio := (
			1.0
			if duration <= 0
			else clampf(float(elapsed) / float(duration), 0.0, 1.0)
		)
		var next_position: Vector2 = host.ACTION_GEOMETRY.point_along_polyline(path, ratio)
		var previous_place := String(resident.get("currentPlace", ""))
		var membership := PERCEPTION_RUNTIME._membership(
			host,
			String(resident.get("spaceId", "")),
			next_position,
		)
		var position_changed: bool = host.RESIDENT_POSITION_COMMIT_RUNTIME.apply_authoritative_resident_position(
			resident,
			next_position,
			String(resident.get("spaceId", "")),
			String(membership.get("regionId", resident.get("regionId", ""))),
			String(
				membership.get("placeName", resident.get("currentPlace", "")),
			),
		)
		host.RESIDENT_POSITION_COMMIT_RUNTIME.emit_place_change(host, resident_id, previous_place)
		if position_changed:
			host._emit_resident_state_changed(resident_id)
	elif approach_mode == "place_route":
		var route := action.get("approachRoute", {}) as Dictionary
		var positions := route.get("minutePositions", []) as Array
		if positions.is_empty():
			host.ACTION_SETTLEMENT_RUNTIME.interrupt(host,
				resident_id,
				"到收件人所在地点的路线已经失效",
			)
			return
		var sample_index := mini(elapsed, positions.size() - 1)
		var previous_place := String(resident.get("currentPlace", ""))
		var position_changed: bool = host.RESIDENT_POSITION_COMMIT_RUNTIME.apply_route_sample(host,
			resident,
			positions[sample_index] as Dictionary,
		)
		host.RESIDENT_POSITION_COMMIT_RUNTIME.emit_place_change(host, resident_id, previous_place)
		if position_changed:
			host._emit_resident_state_changed(resident_id)
	else:
		host.ACTION_SETTLEMENT_RUNTIME.interrupt(host, resident_id, "邮差接近收件人的动作状态无效")
		return
	if elapsed < duration:
		return
	if not String(action.get("conversationFollowUpMode", "")).is_empty():
		host.ACTION_SETTLEMENT_RUNTIME.finish(host, resident_id, "已经回到约定同行者身边")
		return
	if PERCEPTION_RUNTIME._are_nearby(host, resident, target):
		for field: String in [
			"approachMode",
			"approachRoute",
			"pathPoints",
			"targetPosition",
			"targetSpaceId",
			"targetRegionId",
			"targetPlace",
			"expectedTargetPosition",
			"durationMinutes",
			"returnRouteConnector",
			"consumeRouteConnector",
		]:
			action.erase(field)
		resident["currentAction"] = action
		CONVERSATION_RUNTIME._start_conversation(
			host,
			host._traveler_relationship_state,
			resident_id,
			action,
		)
		return
	var refreshed: Dictionary = host._prepare_postal_talk_approach(
		resident,
		target,
		action,
	)
	if refreshed.get("ok") != true:
		host.ACTION_SETTLEMENT_RUNTIME.interrupt(host,
			resident_id,
			"没能继续接近正在移动的收件人",
		)
		return
	var next_action := (
		refreshed.get("action", {}) as Dictionary
	).duplicate(true)
	next_action["startedAbsoluteMinute"] = absolute_minute
	resident["currentAction"] = next_action
	resident["doing"] = "正在接近收件人并转达口信"
