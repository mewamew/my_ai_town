class_name TownActivityExecutionProjection
extends RefCounted


const ACTIVITY_SCALARS := preload(
	"res://world/runtime/activity/TownActivityScalars.gd"
)
const ACTION_PROJECTION := preload(
	"res://world/runtime/action/TownActionProjection.gd"
)


static func valid_source(source_contract: String, source_action_id: String) -> bool:
	if source_contract == ACTION_PROJECTION.ACTIVITY_SOURCE_DIRECT:
		return source_action_id.is_empty()
	if source_contract in [
		ACTION_PROJECTION.ACTIVITY_SOURCE_LEGACY_PROP,
		ACTION_PROJECTION.ACTIVITY_SOURCE_AGENT_ACTIVITY,
	]:
		return (
			not source_action_id.is_empty()
			and source_action_id == source_action_id.strip_edges()
		)
	return false


static func attach_source(
	validated: Dictionary,
	source_contract: String,
	source_action_id: String,
) -> void:
	validated["sourceContract"] = source_contract
	validated["sourceActionId"] = source_action_id


static func validate_with_source(
	activity_runtime: TownWorldActivityRuntime,
	resident_id: String,
	plan_id: String,
	plan_revision: int,
	step: Dictionary,
	social_state: Dictionary,
	current_place: String,
	weather: String,
	source_contract: String,
	source_action_id: String,
) -> Dictionary:
	var validated := activity_runtime.validate_step(
		resident_id,
		plan_id,
		plan_revision,
		step,
		social_state,
		current_place,
		weather,
	) as Dictionary
	if validated.get("ok") == true:
		attach_source(validated, source_contract, source_action_id)
	return validated


static func requested_activity_id(step: Dictionary) -> String:
	var target := (
		step.get("target", {}) as Dictionary
		if step.get("target") is Dictionary
		else {}
	)
	return String(target.get("activityId", ""))


static func bulletin_unavailable_failure(activity_id: String) -> Dictionary:
	return {
		"ok": false,
		"errorCode": "ACTIVITY_NOT_ELIGIBLE",
		"retryable": false,
		"errors": [
			(
				"公告栏当前没有可阅读的新公告"
				if activity_id == "activity_bulletin_read"
				else "没有已确认的公告内容，不能张贴"
			)
		],
	}


static func first_candidate_is_visitor(validated: Dictionary) -> bool:
	var candidates := validated.get("candidates", []) as Array
	return (
		not candidates.is_empty()
		and String((candidates[0] as Dictionary).get("role", "")) == "visitor"
	)


static func work_task_requirement(
	validated: Dictionary,
	occupation_id: String,
	resident_id: String,
	work_tasks: TownWorkTaskRuntime,
) -> Dictionary:
	var candidates := validated.get("candidates", []) as Array
	if candidates.is_empty():
		return {
			"ok": false,
			"errorCode": "ACTIVITY_NOT_ELIGIBLE",
			"retryable": true,
			"errors": ["当前活动没有合法目标"],
		}
	if String((candidates[0] as Dictionary).get("role", "")) != "worker":
		return {"ok": true}
	var activity_id := String(validated.get("activityId", ""))
	if work_tasks.capabilities_for_activity(activity_id).is_empty():
		return {"ok": true}
	if not work_tasks.tasks_for_activity(
		occupation_id,
		activity_id,
		resident_id,
	).is_empty():
		return {"ok": true}
	return {
		"ok": false,
		"errorCode": "WORK_TASK_REQUIRED",
		"retryable": true,
		"errors": ["当前没有需要处理的真实职业任务"],
	}


static func idempotent_result(validated: Dictionary) -> Dictionary:
	return {
		"ok": true,
		"changed": false,
		"idempotent": true,
		"execution": ACTIVITY_SCALARS.safe_activity_execution(
			validated.get("execution", {}) as Dictionary
		),
	}


static func activation_action(
	preflight_action: Dictionary,
	execution: Dictionary,
	duration_cap_minutes: int,
) -> Dictionary:
	var action := preflight_action.duplicate(true)
	var public_action_thought := String(execution.get("reason", "")).strip_edges()
	if not public_action_thought.is_empty():
		action["line"] = public_action_thought
	var duration_minutes := int(execution.get("remainingTicks", 0))
	if duration_cap_minutes > 0:
		duration_minutes = mini(duration_minutes, duration_cap_minutes)
	action["durationMinutes"] = duration_minutes
	# Activity effects are committed by the activity runtime exactly once. The
	# reused prop action must not apply the compatibility effect table again.
	action["effects"] = {}
	action["sourceContract"] = String(execution.get("sourceContract", ""))
	action["sourceActionId"] = String(execution.get("sourceActionId", ""))
	return action


static func activate_resident(
	resident: Dictionary,
	action: Dictionary,
	execution: Dictionary,
) -> void:
	resident["currentAction"] = action
	(resident.get("usedActionIds", {}) as Dictionary)[
		String(action.get("action_id", ""))
	] = true
	if bool(action.get("consumeRouteConnector", false)):
		resident["routeConnector"] = []
	resident["actionSuspendedAbsoluteMinute"] = -1
	resident["doing"] = "正在%s" % String(execution.get("activityLabel", ""))


static func success_result(execution: Dictionary) -> Dictionary:
	return {
		"ok": true,
		"changed": true,
		"execution": ACTIVITY_SCALARS.safe_activity_execution(execution),
	}
