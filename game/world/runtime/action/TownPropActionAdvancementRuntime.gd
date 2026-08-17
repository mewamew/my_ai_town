class_name TownPropActionAdvancementRuntime
extends RefCounted


const ACTION_GEOMETRY := preload(
	"res://world/runtime/action/TownActionGeometry.gd"
)
const PERCEPTION_RUNTIME := preload(
	"res://world/runtime/perception/TownPerceptionRuntime.gd"
)
const ACTIVITY_SCALARS := preload(
	"res://world/runtime/activity/TownActivityScalars.gd"
)


static func advance(
	host,
	resident_name: String,
	resident: Dictionary,
	action: Dictionary,
	absolute_minute: int,
) -> void:
	var duration := int(action.get("durationMinutes", 0))
	var elapsed := maxi(0, absolute_minute - int(action.get("startedAbsoluteMinute", absolute_minute)))
	var approach_duration: int = host.ACTION_SUPPORT.prop_approach_duration_minutes(host, action)
	var ratio := (
		1.0
		if approach_duration <= 0
		else clampf(float(elapsed) / float(approach_duration), 0.0, 1.0)
	)
	# Dictionary/save restoration preserves Vector2 values but not the typed-array
	# element tag. Rebuild the typed boundary before calling the movement helpers.
	var path_points: Array[Vector2] = []
	path_points.assign(action.get("pathPoints", []) as Array)
	var next_position: Vector2 = ACTION_GEOMETRY.point_along_polyline(
		path_points,
		ratio,
	)
	if not bool(action.get("pathClearanceVerified", false)):
		next_position = host.RESIDENT_POSITION_COMMIT_RUNTIME.clearance_safe_position(host,
			String(resident.get("spaceId", "")),
			next_position,
		)
	resident["routeConnector"] = host.ACTION_GEOMETRY.reverse_polyline_to_ratio(path_points, ratio)
	var previous_place := String(resident.get("currentPlace", ""))
	var space_id := String(resident.get("spaceId", ""))
	var region_id := String(resident.get("regionId", ""))
	var place_name := String(resident.get("currentPlace", ""))
	var membership: Dictionary = PERCEPTION_RUNTIME._membership(
		host,
		space_id,
		next_position,
	)
	if not membership.is_empty():
		region_id = String(membership.get("regionId", region_id))
		place_name = String(membership.get("placeName", place_name))
	var position_changed: bool = host.RESIDENT_POSITION_COMMIT_RUNTIME.apply_authoritative_resident_position(
		resident,
		next_position,
		space_id,
		region_id,
		place_name,
	)
	host.RESIDENT_POSITION_COMMIT_RUNTIME.emit_place_change(host, resident_name, previous_place)
	var activity_execution := host._activity_runtime.execution_for_action(
		resident_name,
		String(action.get("action_id", "")),
	) as Dictionary
	if (
		not activity_execution.is_empty()
		and String(resident.get("currentPlace", ""))
		!= String(activity_execution.get("placeId", ""))
		and (
			String(activity_execution.get("targetType", ""))
				!= "region"
			or elapsed >= approach_duration
		)
	):
		host.ACTIVITY_ACTION_SETTLEMENT_RUNTIME.fail(host,
			resident_name,
			"ACTIVITY_STATE_CHANGED",
			"居民离开活动地点",
		)
		return
	var sleep_started := false
	if (
		not activity_execution.is_empty()
		and elapsed >= approach_duration
	):
		sleep_started = _ensure_resident_sleep_started(
			host,
			resident_name,
			action,
			activity_execution,
		)
		resident["doing"] = ACTIVITY_SCALARS.activity_progress_doing(
			activity_execution,
			maxi(0, elapsed - approach_duration),
		)
	# C1(docs/居民状态通知链减负方案.md):表现真变化才发——位置变化、activityCue
	# 阶段边界(approaching→performing)、睡眠实际开始;doing 轮换不在表现合同内。
	if (
		position_changed
		or sleep_started
		or (elapsed >= approach_duration and elapsed - 1 < approach_duration)
	):
		host._emit_resident_state_changed(resident_name)
	if not activity_execution.is_empty():
		host._activity_runtime.sync_remaining_ticks(
			resident_name,
			maxi(0, approach_duration + duration - elapsed),
		)
	if elapsed >= approach_duration + duration:
		if activity_execution.is_empty():
			ACTIVITY_SCALARS.apply_body_effects(
				resident,
				action.get("effects", {}) as Dictionary,
				host.BODY_LEVELS,
			)
			host.ACTION_SETTLEMENT_RUNTIME.finish(host,
				resident_name,
				"已完成%s·%s" % [
					action.get("prop", "道具"),
					action.get("verb", "动作"),
				],
			)
		else:
			host.ACTIVITY_ACTION_SETTLEMENT_RUNTIME.finish(host, resident_name)


static func _ensure_resident_sleep_started(
	host,
	resident_id: String,
	action: Dictionary,
	execution: Dictionary,
) -> bool:
	if String(execution.get("activityId", "")) != "activity_home_sleep":
		return false
	var action_id := String(action.get("action_id", "")).strip_edges()
	if action_id.is_empty():
		return false
	var active := host._resident_sleep.get_active_sleep(resident_id) as Dictionary
	if not active.is_empty():
		return false
	var sleep_started_at: int = int(action.get("startedAbsoluteMinute", 0)) + (
		host.ACTION_SUPPORT.prop_approach_duration_minutes(host, action)
	)
	host._resident_sleep.start_sleep(
		resident_id,
		action_id,
		sleep_started_at,
		maxi(1, int(action.get("durationMinutes", 0))),
	)
	return true
