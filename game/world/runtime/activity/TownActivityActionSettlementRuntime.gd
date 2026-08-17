class_name TownActivityActionSettlementRuntime
extends RefCounted
const ACTIVITY_ATTENDANCE_RUNTIME := preload(
	"res://world/runtime/activity/TownActivityAttendanceRuntime.gd"
)
const ROUTINE_SETTLEMENT_RUNTIME := preload(
	"res://world/runtime/activity/TownActivityRoutineSettlementRuntime.gd"
)


const COMPLETION_PROJECTION := preload(
	"res://world/runtime/activity/TownActivityCompletionProjection.gd"
)
const ACTION_PRESENTATION := preload(
	"res://world/runtime/presentation/TownActionPresentationSemantics.gd"
)
const ACTION_PROJECTION := preload(
	"res://world/runtime/action/TownActionProjection.gd"
)
const ACTION_SETTLEMENT := preload(
	"res://world/runtime/action/TownActionSettlementRuntime.gd"
)
const ACTION_RESULT_RUNTIME := preload(
	"res://world/runtime/action/TownActionResultRuntime.gd"
)
const SLEEP_ACTIVITY_ID := "activity_home_sleep"


static func finish(host, resident_id: String) -> void:
	var resident := host.resident_registry.records[resident_id] as Dictionary
	var action := resident.get("currentAction", {}) as Dictionary
	if action.is_empty():
		return
	var action_id := String(action.get("action_id", ""))
	var activity_execution := host._activity_runtime.execution_for_action(
		resident_id,
		action_id,
	) as Dictionary
	var source_action_id := ACTION_PROJECTION.activity_source_action_id(
		action,
		activity_execution,
	)
	var presentation: Dictionary = ACTION_PRESENTATION._preview_action_presentation(
		host,
		resident,
		{"action": action},
	)
	var completed := host._activity_runtime.complete_action(
		resident_id,
		action_id,
	) as Dictionary
	if completed.get("ok") != true:
		fail(
			host,
			resident_id,
			String(completed.get("errorCode", "ACTIVITY_STATE_CHANGED")),
			"活动完成提交失败",
		)
		return
	var applied_effects := completed.get("effects", {}) as Dictionary
	var resident_effects := COMPLETION_PROJECTION.resident_effects(
		applied_effects,
		host.activity_routine_state.records.get(resident_id, {}) as Dictionary,
	)
	var next_activity_state: Dictionary = host.ACTIVITY_SCALARS.next_activity_state(
		resident,
		resident_effects,
		host.ACTIVITY_STATE_KEYS,
	)
	var committed := host._activity_runtime.commit_completion(
		resident_id,
		action_id,
		applied_effects,
	) as Dictionary
	if committed.get("ok") != true:
		fail(
			host,
			resident_id,
			String(committed.get("errorCode", "ACTIVITY_STATE_CHANGED")),
			"活动效果提交失败",
		)
		return
	resident["activityState"] = next_activity_state
	host.ACTIVITY_SCALARS.sync_body_from_activity_needs(resident, next_activity_state)
	var execution := COMPLETION_PROJECTION.completed_execution(
		activity_execution,
		committed.get("execution", {}) as Dictionary,
		int(action.get("durationMinutes", 1)),
	) as Dictionary
	if String(execution.get("activityId", "")) == SLEEP_ACTIVITY_ID:
		ACTIVITY_ATTENDANCE_RUNTIME.clear_sleep_leave(host, resident)
	ACTION_SETTLEMENT.restore_route_connector(resident, action)
	resident["currentAction"] = {}
	resident["actionSuspendedAbsoluteMinute"] = -1
	var completion_text := COMPLETION_PROJECTION.completion_text(execution)
	resident["doing"] = completion_text
	host._bump_world_revision(false)
	if not source_action_id.is_empty():
		ACTION_RESULT_RUNTIME.queue(
			host,
			resident_id,
			source_action_id,
			"completed",
			completion_text,
			true,
			true,
			presentation,
		)
	host._notify_world_revision()
	host.ACTIVITY_LIFECYCLE_COMMIT_RUNTIME.emit(host,
		"completed",
		resident_id,
		execution,
		"完成",
	)
	host.RESIDENT_CONDITION_SETTLEMENT_RUNTIME.settle_activity(host,
		resident_id,
		resident,
		action,
		execution,
		"completed",
		"完成",
	)
	var action_after_lifecycle := (
		resident.get("currentAction", {}) as Dictionary
	)
	if not String(
		action_after_lifecycle.get("serviceRequestId", ""),
	).is_empty():
		return
	if ROUTINE_SETTLEMENT_RUNTIME.continue_routine(host, resident_id):
		return
	host._emit_resident_state_changed(resident_id)


static func fail(
	host,
	resident_id: String,
	error_code: String,
	reason: String,
) -> void:
	var resident := host.resident_registry.records[resident_id] as Dictionary
	var action := resident.get("currentAction", {}) as Dictionary
	if action.is_empty():
		return
	var action_id := String(action.get("action_id", ""))
	var execution := host._activity_runtime.execution_for_action(
		resident_id,
		action_id,
	) as Dictionary
	var source_action_id := ACTION_PROJECTION.activity_source_action_id(
		action,
		execution,
	)
	var presentation: Dictionary = ACTION_PRESENTATION._preview_action_presentation(
		host,
		resident,
		{"action": action},
	)
	var failed := host._activity_runtime.fail_action(
		resident_id,
		action_id,
		error_code,
	) as Dictionary
	host.RESIDENT_CONDITION_SETTLEMENT_RUNTIME.settle_activity(host,
		resident_id,
		resident,
		action,
		execution,
		"failed",
		reason,
	)
	resident["currentAction"] = {}
	resident["actionSuspendedAbsoluteMinute"] = -1
	resident["doing"] = reason
	if host.activity_routine_state.records.has(resident_id):
		ROUTINE_SETTLEMENT_RUNTIME.close_routine(
			host, resident_id, "rejected", reason,
		)
	host._bump_world_revision(false)
	if not source_action_id.is_empty():
		ACTION_RESULT_RUNTIME.queue(
			host,
			resident_id,
			source_action_id,
			"rejected",
			reason,
			true,
			true,
			presentation,
		)
	host._notify_world_revision()
	host.ACTIVITY_LIFECYCLE_COMMIT_RUNTIME.emit(host,
		"failed",
		resident_id,
		failed.get("execution", execution) as Dictionary,
		reason,
		error_code,
	)
	host._emit_resident_state_changed(resident_id)
