class_name TownActivityStepExecutionRuntime
extends RefCounted


const ACTIVITY_WORK_TASK_BINDING_RUNTIME := preload(
	"res://world/runtime/activity/TownActivityWorkTaskBindingRuntime.gd"
)
const ACTIVITY_ATTENDANCE_RUNTIME := preload(
	"res://world/runtime/activity/TownActivityAttendanceRuntime.gd"
)


const WORLD_PERFORMANCE_PROBE := preload(
	"res://world/runtime/TownWorldPerformanceProbe.gd"
)
const ACTIVITY_EXECUTION_PROJECTION := preload(
	"res://world/runtime/activity/TownActivityExecutionProjection.gd"
)
const DINING_SERVICE := preload(
	"res://world/runtime/work/TownDiningServiceRuntime.gd"
)
const CLINIC_CONTINUITY := preload(
	"res://world/runtime/condition/TownClinicContinuityRuntime.gd"
)
const PUBLIC_PLACE_CONTINUITY := preload(
	"res://world/runtime/work/TownPublicPlaceContinuityRuntime.gd"
)
const SOCIAL_JUDGMENTS := preload(
	"res://world/runtime/social/TownSocialJudgments.gd"
)

const SLEEP_ACTIVITY_ID := "activity_home_sleep"


static func perform(
	host,
	resident_id: String,
	plan_id: String,
	plan_revision: int,
	step: Dictionary,
	source_contract: String,
	source_action_id: String,
	duration_cap_minutes := -1,
	allow_current_activity_interrupt := false,
) -> Dictionary:
	var probe_lap_usec := WORLD_PERFORMANCE_PROBE.start_lap()
	if not host._running:
		return host._command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	if not ACTIVITY_EXECUTION_PROJECTION.valid_source(
		source_contract,
		source_action_id,
	):
		return host._command_failure(
			"ACTIVITY_STATE_CHANGED",
			["activity.perform 内部来源合同无效"],
		)
	var normalized_resident_id := resident_id.strip_edges()
	if normalized_resident_id.is_empty() or not host.resident_registry.records.has(
		normalized_resident_id
	):
		return host._command_failure(
			"ACTIVITY_STATE_CHANGED",
			["activity.perform 必须使用稳定 residentId"],
		)
	var resident := host.resident_registry.records[normalized_resident_id] as Dictionary
	var accepted := accept_request(
		host,
		normalized_resident_id,
		resident,
		plan_id,
		plan_revision,
		step,
		source_contract,
		source_action_id,
		probe_lap_usec,
	)
	if accepted.has("result"):
		return accepted.get("result", {}) as Dictionary
	probe_lap_usec = int(accepted.get("probeLapUsec", probe_lap_usec))
	var activity_social_state := accepted.get("socialState", {}) as Dictionary
	var validated := accepted.get("validated", {}) as Dictionary
	var preflight_stage := prepare_replacement(
		host,
		normalized_resident_id,
		resident,
		plan_id,
		plan_revision,
		step,
		activity_social_state,
		validated,
		source_contract,
		source_action_id,
		allow_current_activity_interrupt,
	)
	if preflight_stage.has("result"):
		return preflight_stage.get("result", {}) as Dictionary
	validated = preflight_stage.get("validated", {}) as Dictionary
	var preflight := preflight_stage.get("preflight", {}) as Dictionary
	var reservation := host._activity_runtime.reserve_execution(
		validated,
		String(preflight.get("slotId", "")),
		String(preflight.get("memberAnchorId", "")),
	) as Dictionary
	probe_lap_usec = WORLD_PERFORMANCE_PROBE.record_lap(
		probe_lap_usec,
		"activity_preflight_and_reserve",
	)
	if reservation.get("ok") != true:
		return host._decorate_command_result(reservation)
	var execution := reservation.get("execution", {}) as Dictionary
	ACTIVITY_WORK_TASK_BINDING_RUNTIME.claim_for_execution(
		host, normalized_resident_id, execution,
	)
	var action := ACTIVITY_EXECUTION_PROJECTION.activation_action(
		preflight.get("action", {}) as Dictionary,
		execution,
		duration_cap_minutes,
	)
	if duration_cap_minutes > 0:
		host._activity_runtime.sync_remaining_ticks(
			normalized_resident_id,
			host.ACTION_SUPPORT.prop_approach_duration_minutes(host, action)
			+ int(action.get("durationMinutes", 0)),
		)
	ACTIVITY_EXECUTION_PROJECTION.activate_resident(resident, action, execution)
	ACTIVITY_ATTENDANCE_RUNTIME.start_sleep_leave(
		host, resident, action, execution,
	)
	host._bump_world_revision()
	probe_lap_usec = WORLD_PERFORMANCE_PROBE.record_lap(
		probe_lap_usec,
		"activity_revision",
	)
	host.ACTIVITY_LIFECYCLE_COMMIT_RUNTIME.emit(host,
		"started",
		normalized_resident_id,
		execution,
		"",
	)
	probe_lap_usec = WORLD_PERFORMANCE_PROBE.record_lap(
		probe_lap_usec,
		"activity_lifecycle",
	)
	host._emit_resident_state_changed(normalized_resident_id)
	WORLD_PERFORMANCE_PROBE.record_lap(probe_lap_usec, "activity_resident_emit")
	return host._decorate_command_result(
		ACTIVITY_EXECUTION_PROJECTION.success_result(execution)
	)


static func accept_request(
	host,
	resident_id: String,
	resident: Dictionary,
	plan_id: String,
	plan_revision: int,
	step: Dictionary,
	source_contract: String,
	source_action_id: String,
	probe_lap_usec: int,
) -> Dictionary:
	var requested_activity_id := ACTIVITY_EXECUTION_PROJECTION.requested_activity_id(
		step,
	)
	if requested_activity_id == SLEEP_ACTIVITY_ID and not host.ACTIVITY_AVAILABILITY_RUNTIME.resident_sleep_needed(resident):
		return {"result": host._command_failure(
			"ACTIVITY_NOT_ELIGIBLE", ["当前精力还足，不需要睡觉"]
		)}
	if requested_activity_id == "activity_dining_collect_meal":
		var dining_full_failure := DINING_SERVICE.collect_full_failure(
			host,
			resident_id,
			int(host._environment.get_absolute_minute()),
		)
		if not dining_full_failure.is_empty():
			return {"result": dining_full_failure}
	var activity_social_state: Dictionary = host.OCCUPATION_RESIDENT_CONTEXT_RUNTIME.activity_social_state(host,
		resident_id,
		requested_activity_id,
	)
	if (
		requested_activity_id
		in [SOCIAL_JUDGMENTS.BULLETIN_READ_ACTIVITY_ID, SOCIAL_JUDGMENTS.BULLETIN_PUBLISH_ACTIVITY_ID]
		and not host.ACTIVITY_AVAILABILITY_RUNTIME.bulletin_available(host,
			resident_id,
			requested_activity_id,
		)
	):
		return {"result": host._decorate_command_result(
			ACTIVITY_EXECUTION_PROJECTION.bulletin_unavailable_failure(
				requested_activity_id,
			)
		)}
	var validated := host._activity_runtime.validate_step(
		resident_id,
		plan_id,
		plan_revision,
		step,
		activity_social_state,
		String(resident.get("currentPlace", "")),
		host.get_weather(),
	) as Dictionary
	probe_lap_usec = WORLD_PERFORMANCE_PROBE.record_lap(
		probe_lap_usec,
		"activity_validate",
	)
	if validated.get("ok") != true:
		return {"result": host._decorate_command_result(validated)}
	var visitor_request_spec: Dictionary = host.PLACE_SERVICE_COMMAND_RUNTIME.visitor_occupation_service_spec(
		host,
		resident_id,
		requested_activity_id,
	)
	var visitor_service_staffed := CLINIC_CONTINUITY.visitor_service_is_staffed(
		host,
		requested_activity_id,
		visitor_request_spec,
	)
	if (
		ACTIVITY_EXECUTION_PROJECTION.first_candidate_is_visitor(validated)
		and not visitor_service_staffed
	):
		return {"result": host._command_failure(
			"OCCUPATION_SERVICE_UNSTAFFED",
			["对应岗位当前无人值守，不能开始这项服务活动"],
		)}
	var requested_place_id := String(
		(step.get("target", {}) as Dictionary).get("placeId", ""),
	)
	if (
		ACTIVITY_EXECUTION_PROJECTION.first_candidate_is_visitor(validated)
		and PUBLIC_PLACE_CONTINUITY.activity_blocked_when_unstaffed(
			host,
			requested_place_id,
			requested_activity_id,
		)
	):
		return {"result": host._command_failure(
			"OCCUPATION_SERVICE_UNSTAFFED",
			["对应岗位当前无人值守，这项活动已经暂停"],
		)}
	if validated.get("idempotent") == true:
		if not bool(host._activity_runtime.execution_source_matches(
			resident_id,
			plan_id,
			plan_revision,
			step,
			source_contract,
			source_action_id,
		)):
			return {"result": host._command_failure(
				"ACTIVITY_STATE_CHANGED",
				["相同 activity 幂等键不能跨执行来源合同复用"],
			)}
		return {"result": host._decorate_command_result(
			ACTIVITY_EXECUTION_PROJECTION.idempotent_result(validated)
		)}
	var task_requirement := ACTIVITY_EXECUTION_PROJECTION.work_task_requirement(
		validated,
		String(activity_social_state.get("occupationId", "")),
		resident_id,
		host._work.tasks,
	)
	if task_requirement.get("ok") != true:
		return {"result": host._decorate_command_result(task_requirement)}
	ACTIVITY_EXECUTION_PROJECTION.attach_source(
		validated,
		source_contract,
		source_action_id,
	)
	return {
		"validated": validated,
		"socialState": activity_social_state,
		"probeLapUsec": probe_lap_usec,
	}


static func prepare_replacement(
	host,
	resident_id: String,
	resident: Dictionary,
	plan_id: String,
	plan_revision: int,
	step: Dictionary,
	activity_social_state: Dictionary,
	validated: Dictionary,
	source_contract: String,
	source_action_id: String,
	allow_current_activity_interrupt: bool,
) -> Dictionary:
	var current_action := resident.get("currentAction", {}) as Dictionary
	var current_activity_execution := {}
	if not current_action.is_empty():
		current_activity_execution = host._activity_runtime.execution_for_action(
			resident_id,
			String(current_action.get("action_id", "")),
		) as Dictionary
	var preflight := {}
	if not current_activity_execution.is_empty():
		if not allow_current_activity_interrupt:
			return {"result": host._command_failure(
				"ACTIVITY_STATE_CHANGED",
				["居民已有活动正在执行，普通 activity.perform 必须等当前活动完成"],
			)}
		host.ACTION_SETTLEMENT_RUNTIME.interrupt(host, resident_id, "被新的 activity.perform 替换")
		validated = ACTIVITY_EXECUTION_PROJECTION.validate_with_source(
			host._activity_runtime,
			resident_id,
			plan_id,
			plan_revision,
			step,
			activity_social_state,
			String(resident.get("currentPlace", "")),
			host.get_weather(),
			source_contract,
			source_action_id,
		)
		if validated.get("ok") != true:
			return {"result": host._decorate_command_result(validated)}
		preflight = host.ACTIVITY_CANDIDATE_PREFLIGHT_RUNTIME.preflight(host, resident, validated)
		if preflight.get("ok") != true:
			return {"result": host._decorate_command_result(preflight)}
	else:
		preflight = host.ACTIVITY_CANDIDATE_PREFLIGHT_RUNTIME.preflight(host, resident, validated)
		if preflight.get("ok") != true:
			return {"result": host._decorate_command_result(preflight)}
		if not current_action.is_empty():
			host._append_action_result_without_schedule(
				resident_id,
				String(current_action.get("action_id", "")),
				"replaced",
				"居民开始执行新的 activity.perform",
			)
			resident["currentAction"] = {}
			resident["actionSuspendedAbsoluteMinute"] = -1
			validated = ACTIVITY_EXECUTION_PROJECTION.validate_with_source(
				host._activity_runtime,
				resident_id,
				plan_id,
				plan_revision,
				step,
				activity_social_state,
				String(resident.get("currentPlace", "")),
				host.get_weather(),
				source_contract,
				source_action_id,
			)
			if validated.get("ok") != true:
				return {"result": host._decorate_command_result(validated)}
			preflight = host.ACTIVITY_CANDIDATE_PREFLIGHT_RUNTIME.preflight(host, resident, validated)
			if preflight.get("ok") != true:
				return {"result": host._decorate_command_result(preflight)}
	return {"validated": validated, "preflight": preflight}
