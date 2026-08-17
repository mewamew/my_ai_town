class_name TownWaitActionAdvancementRuntime
extends RefCounted


const FOLLOW_UP_ACTION_RUNTIME := preload(
	"res://world/runtime/conversation/TownConversationFollowUpActionRuntime.gd"
)


const CONVERSATION_FOLLOW_UP_ACTION_RUNTIME := preload(
	"res://world/runtime/conversation/TownConversationFollowUpActionRuntime.gd"
)
const PERCEPTION_RUNTIME := preload(
	"res://world/runtime/perception/TownPerceptionRuntime.gd"
)
const ACTION_GEOMETRY := preload(
	"res://world/runtime/action/TownActionGeometry.gd"
)


static func advance(
	host,
	resident_name: String,
	resident: Dictionary,
	action: Dictionary,
	absolute_minute: int,
) -> void:
	var service_request_id := String(
		action.get("serviceRequestId", ""),
	)
	if not service_request_id.is_empty():
		var service_request: Dictionary = host._work.services.request(
			service_request_id,
		) as Dictionary
		if String(service_request.get("state", "")) in [
			"pending",
			"waiting",
			"in_progress",
		]:
			action["completeAbsoluteMinute"] = maxi(
				int(action.get("completeAbsoluteMinute", absolute_minute)),
				absolute_minute + 5,
			)
			_extend_meal_routine_for_service_wait(
				host,
				resident_name,
				absolute_minute,
			)
			return
	if CONVERSATION_FOLLOW_UP_ACTION_RUNTIME.timed_out(
		host, resident_name, action, absolute_minute,
	):
		return
	if (
		String(action.get("conversationFollowUpMode", "")) == "fetch_service"
		and String(action.get("followUpPhase", "")) == "collecting"
		and not FOLLOW_UP_ACTION_RUNTIME.service_available(host, action)
	):
		CONVERSATION_FOLLOW_UP_ACTION_RUNTIME.begin_reconsideration(
			host,
			resident_name,
			"答应前往的服务地点已经停止营业或不再提供这项服务",
		)
		return
	var move_duration := int(action.get("idleMoveDurationMinutes", 0))
	var elapsed := maxi(
		0,
		absolute_minute
			- int(action.get("startedAbsoluteMinute", absolute_minute)),
	)
	if (
		move_duration > 0
		and elapsed <= move_duration
		and action.get("idlePathPoints") is Array
	):
		var wait_move_lap_usec: int = (
			Time.get_ticks_usec() if host.telemetry.advance_profile_enabled else 0
		)
		var path_points: Array[Vector2] = []
		path_points.assign(action.get("idlePathPoints", []) as Array)
		var ratio := clampf(
			float(elapsed) / float(move_duration),
			0.0,
			1.0,
		)
		# idlePathPoints 只由正式室外 movementNetwork 或室内导航查询生成，
		# 路径本身已经满足对应空间的可行走合同。逐分钟再次做最近安全点
		# 径向搜索会让所有居民在同一秒重复扫描碰撞数据，造成周期卡顿。
		var next_position: Vector2 = ACTION_GEOMETRY.point_along_polyline(
			path_points,
			ratio,
		)
		wait_move_lap_usec = host.telemetry.lap(
			host.telemetry.advance_profile_scratch,
			"actionsWaitPathSampleUsec",
			wait_move_lap_usec,
		)
		var previous_place := String(resident.get("currentPlace", ""))
		var membership: Dictionary = PERCEPTION_RUNTIME._membership(host,
			String(resident.get("spaceId", "")),
			next_position,
		)
		wait_move_lap_usec = host.telemetry.lap(
			host.telemetry.advance_profile_scratch,
			"actionsWaitMembershipUsec",
			wait_move_lap_usec,
		)
		var position_changed: bool = host.RESIDENT_POSITION_COMMIT_RUNTIME.apply_authoritative_resident_position(
			resident,
			next_position,
			String(resident.get("spaceId", "")),
			String(
				membership.get(
					"regionId",
					resident.get("regionId", ""),
				)
			),
			String(
				membership.get(
					"placeName",
					resident.get("currentPlace", ""),
				)
			),
		)
		wait_move_lap_usec = host.telemetry.lap(
			host.telemetry.advance_profile_scratch,
			"actionsWaitApplyPositionUsec",
			wait_move_lap_usec,
		)
		var place_changed: bool = host.RESIDENT_POSITION_COMMIT_RUNTIME.emit_place_change(host,
			resident_name,
			previous_place,
			true,
		)
		# C1(docs/居民状态通知链减负方案.md):表现真变化才发。
		if position_changed and not place_changed:
			# 权威位置已经在本分钟写入；画面刷新按帧预算发送，避免 15 位
			# 正在闲逛的居民在同一主线程帧里依次重建表现状态。
			host.frame_budget_runtime.queue_resident_state_refresh(resident_name)
		host.telemetry.lap(
			host.telemetry.advance_profile_scratch,
			"actionsWaitStateQueueUsec",
			wait_move_lap_usec,
		)
	if absolute_minute >= int(action.get("completeAbsoluteMinute", INF)):
		host.ACTION_SETTLEMENT_RUNTIME.finish(host, resident_name, "已经停留了一会儿")


static func _extend_meal_routine_for_service_wait(
	host,
	resident_name: String,
	absolute_minute: int,
) -> void:
	if not host.activity_routine_state.records.has(resident_name):
		return
	var routine := host.activity_routine_state.records[resident_name] as Dictionary
	if String(routine.get("group", "")) != "meal":
		return
	routine["endAbsoluteMinute"] = maxi(
		int(routine.get("endAbsoluteMinute", absolute_minute)),
		absolute_minute
		+ int(host.ACTIVITY_ROUTINE_DURATION_MINUTES.get("meal", 30)),
	)
	host.activity_routine_state.records[resident_name] = routine
