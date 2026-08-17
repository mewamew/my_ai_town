class_name TownActivityLifecycleCommitRuntime
extends RefCounted


const BULLETIN_EFFECT_PLANNER := preload(
	"res://world/runtime/activity/TownBulletinActivityEffectPlanner.gd"
)
const LIFECYCLE_EVENT_PROJECTION := preload(
	"res://world/runtime/log/TownActivityLifecycleEventProjection.gd"
)
const WORK_SETTLEMENT := preload(
	"res://world/runtime/work/TownWorkSettlement.gd"
)


static func emit(
	host,
	lifecycle: String,
	resident_id: String,
	execution: Dictionary,
	reason: String,
	_error_code := "",
) -> void:
	if execution.is_empty():
		return
	if lifecycle == "started":
		host.SOCIAL_ASSIGNMENT_RESULT_RUNTIME.start_matching_activity(host, resident_id, execution)
		host.CLINIC_SERVICE_COORDINATION_RUNTIME.record_started_request(host, resident_id, execution)
	elif lifecycle in ["completed", "interrupted", "failed"]:
		if lifecycle == "completed":
			WORK_SETTLEMENT.settle_completed_activity(host, resident_id, execution)
		host.activity_work_task_bindings.release_task_from_activity(
			resident_id,
			execution,
			lifecycle,
			host._work.tasks,
		)
		var bulletin_effect := {}
		if lifecycle == "completed":
			bulletin_effect = complete_bulletin_effect(
				host,
				resident_id,
				execution,
			)
		host.SOCIAL_ASSIGNMENT_RESULT_RUNTIME.record_matching_activity_result(host,
			resident_id,
			execution,
			host.SOCIAL_GOAL_MATCHING_RUNTIME.execution_status(lifecycle),
			reason,
			bulletin_effect,
		)
		if lifecycle == "completed":
			host.PLACE_SERVICE_COMMAND_RUNTIME.apply_activity_completion(host, execution)
	var event := LIFECYCLE_EVENT_PROJECTION.event(
		lifecycle,
		execution,
		reason,
		host.get_time(),
	) as Dictionary
	if event.is_empty():
		return
	var activity_event_sequence := int(host.world_log_domain.journal.next_sequence())
	host.WORLD_LOG_COMMIT_RUNTIME.append_public(
		host,
		"resident-activity:%d" % activity_event_sequence,
		"resident_activity",
		resident_id,
		host.resident_display_name(resident_id),
		String(execution.get("placeId", "")),
		event,
	)
	match lifecycle:
		"started":
			host.resident_activity_started.emit(resident_id, event.duplicate(true))
		"completed":
			host.resident_activity_completed.emit(resident_id, event.duplicate(true))
		"interrupted":
			host.resident_activity_interrupted.emit(resident_id, event.duplicate(true))
		"failed":
			host.resident_activity_failed.emit(resident_id, event.duplicate(true))


static func complete_bulletin_effect(
	host,
	resident_id: String,
	execution: Dictionary,
) -> Dictionary:
	var active_statuses: Array[String] = ["assigned", "executing"]
	var assignments: Array[Dictionary] = host.SOCIAL_GOAL_MATCHING_RUNTIME.active_assignments(host,
		resident_id,
		active_statuses,
	)
	var plan := BULLETIN_EFFECT_PLANNER.plan(
		resident_id,
		execution,
		assignments,
		host.SOCIAL_MATTER_ACTIVITY_PROJECTION.first_unread_announcement_id(host, resident_id),
	) as Dictionary
	if plan.is_empty() or plan.get("ok") == false:
		return plan
	match String(plan.get("operation", "")):
		"read":
			var read_result: Dictionary = host.read_announcement(
				resident_id,
				String(plan.get("announcementId", "")),
			)
			if read_result.get("ok") != true:
				return BULLETIN_EFFECT_PLANNER.failure_from_result(
					read_result,
					"公告已经失效",
				)
			return BULLETIN_EFFECT_PLANNER.success(
				String(plan.get("successResultId", "")),
			)
		"publish":
			var matter_id := String(plan.get("matterId", ""))
			var publish_result: Dictionary = host.publish_resident_announcement(
				resident_id,
				String(plan.get("text", "")),
				matter_id,
			)
			if publish_result.get("ok") != true:
				return BULLETIN_EFFECT_PLANNER.failure_from_result(
					publish_result,
					"公告内容没有成功张贴",
				)
			var announcement := publish_result.get("announcement", {}) as Dictionary
			var announcement_id := String(announcement.get("announcement_id", ""))
			host.PLACE_SERVICE_COMMAND_RUNTIME.record_staffing_trial(host,
				resident_id,
				"occupation_town_manager",
				{"announcementId": announcement_id, "matterId": matter_id},
			)
			return BULLETIN_EFFECT_PLANNER.success(
				"bulletin-publish:%s" % announcement_id,
			)
	return {}
