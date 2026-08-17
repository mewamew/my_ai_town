class_name TownActivityRoutineSettlementRuntime
extends RefCounted


const ACTIVITY_STEP_EXECUTION_RUNTIME := preload(
	"res://world/runtime/activity/TownActivityStepExecutionRuntime.gd"
)
const ROUTINE_POLICY := preload(
	"res://world/runtime/activity/TownActivityRoutinePolicy.gd"
)
const ACTION_PRESENTATION := preload(
	"res://world/runtime/presentation/TownActionPresentationSemantics.gd"
)
const ACTION_PROJECTION := preload(
	"res://world/runtime/action/TownActionProjection.gd"
)
const ACTION_RESULT_RUNTIME := preload(
	"res://world/runtime/action/TownActionResultRuntime.gd"
)
const DINING_SERVICE := preload(
	"res://world/runtime/work/TownDiningServiceRuntime.gd"
)


static func continue_routine(host, resident_id: String) -> bool:
	if not host.activity_routine_state.records.has(resident_id):
		return false
	var resident := host.resident_registry.records[resident_id] as Dictionary
	var routine := host.activity_routine_state.records[resident_id] as Dictionary
	var group := String(routine.get("group", ""))
	var completion_text := ACTION_PROJECTION.activity_routine_completion_text(group)
	var entry := ROUTINE_POLICY.continuation_entry(
		routine,
		resident.get("currentAction", {}) as Dictionary,
		String(resident.get("currentPlace", "")),
		int(host._environment.get_absolute_minute()),
		int(host.ACTIVITY_ROUTINE_MAX_STEPS.get(group, 1)),
		completion_text,
	)
	if String(entry.get("kind", "")) == "close":
		close_routine(
			host,
			resident_id,
			String(entry.get("status", "completed")),
			String(entry.get("reason", "")),
		)
		return false
	var candidates := host._activity_runtime.routine_candidates(
		resident.get("socialState", {}) as Dictionary,
		String(resident.get("currentPlace", "")),
		group,
	) as Array[Dictionary]
	var candidate_plan := ROUTINE_POLICY.candidate_plan(
		routine,
		candidates,
		String(entry.get("expectedPhase", "")),
	)
	var ordered_candidates := candidate_plan.get("candidates", []) as Array
	if ordered_candidates.is_empty():
		close_routine(host, resident_id, "completed", completion_text)
		return false
	var next_sequence := int(candidate_plan.get("nextSequence", 0))
	for candidate_value: Variant in ordered_candidates:
		var candidate := candidate_value as Dictionary
		var performed: Dictionary = ACTIVITY_STEP_EXECUTION_RUNTIME.perform(
			host,
			resident_id,
			String(routine.get("routineId", "")),
			0,
			ROUTINE_POLICY.continuation_step(routine, candidate, next_sequence),
			ACTION_PROJECTION.ACTIVITY_SOURCE_DIRECT,
			"",
			int(host.ACTIVITY_ROUTINE_STEP_CAP_MINUTES.get(group, 15)),
		)
		if performed.get("ok") != true:
			continue
		host.activity_routine_state.records[resident_id] = ROUTINE_POLICY.advanced_routine(
			routine,
			candidate,
			next_sequence,
		)
		return true
	close_routine(host, resident_id, "completed", completion_text)
	return false


static func close_routine(
	host,
	resident_id: String,
	status: String,
	reason: String,
) -> void:
	if not host.activity_routine_state.records.has(resident_id):
		return
	var routine := host.activity_routine_state.records[resident_id] as Dictionary
	host.activity_routine_state.records.erase(resident_id)
	DINING_SERVICE.settle_closed_meal_routine(
		host,
		resident_id,
		routine,
		status,
	)
	var resident := host.resident_registry.records[resident_id] as Dictionary
	resident["doing"] = reason
	var last_activity_id := String(routine.get("lastActivityId", "")).strip_edges()
	var presentation: Dictionary = (
		ACTION_PRESENTATION._preview_action_presentation(
			host,
			resident,
			{"action": {"type": "做活动", "activity_id": last_activity_id}},
		)
		if not last_activity_id.is_empty()
		else {}
	)
	ACTION_RESULT_RUNTIME.queue(
		host,
		resident_id,
		String(routine.get("sourceActionId", "")),
		status,
		reason,
		true,
		true,
		presentation,
	)
