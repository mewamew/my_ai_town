class_name TownStaffingAssignmentSubmissionRuntime
extends RefCounted


const STAFFING_ASSIGNMENT_POLICY := preload(
	"res://world/runtime/work/TownStaffingAssignmentPolicy.gd"
)
const STAFFING_ASSIGNMENT_COMMIT := preload(
	"res://world/runtime/work/TownStaffingAssignmentCommit.gd"
)
const PLACE_SERVICE_COMMAND_RUNTIME := preload(
	"res://world/runtime/work/TownPlaceServiceCommandRuntime.gd"
)


static func apply(
	host,
	matter_id: String,
	resident_id: String,
	action_goal: Dictionary,
) -> void:
	var target := STAFFING_ASSIGNMENT_POLICY.target(action_goal)
	var target_occupation_id := String(target.get("occupationId", ""))
	var assignment_kind := String(target.get("assignmentKind", ""))
	var resident := host.resident_registry.records.get(resident_id, {}) as Dictionary
	var current_occupation_id: String = host.OCCUPATION_RESIDENT_CONTEXT_RUNTIME.primary_id(host, resident)
	var target_post := host._work.staffing.post_for_occupation(
		target_occupation_id
	) as Dictionary
	var target_occupation: Dictionary = host.OCCUPATION_RESIDENT_CONTEXT_RUNTIME.definition(host,
		target_occupation_id
	)
	var assignment_minute := int(host._environment.get_absolute_minute())
	var started := host._social_matters.start_execution(
		matter_id,
		resident_id,
		String(action_goal.get("goal_id", "")),
		assignment_minute,
	) as Dictionary
	if started.get("ok") != true:
		return
	var failure_reason := STAFFING_ASSIGNMENT_POLICY.failure_reason(
		target,
		current_occupation_id,
		target_post,
		target_occupation,
		host._work.staffing.allowed_assignment_modes(
			resident_id,
			target_occupation_id,
		) as Array,
	)
	var assignment := STAFFING_ASSIGNMENT_POLICY.assignment(matter_id, action_goal)
	if not failure_reason.is_empty():
		host.SOCIAL_ASSIGNMENT_RESULT_RUNTIME.record_result(host,
			assignment,
			resident_id,
			STAFFING_ASSIGNMENT_POLICY.rejection_result(
				matter_id,
				resident_id,
				failure_reason,
			),
			"failed",
		)
		return
	if assignment_kind != "transfer":
		var arrangement_result := STAFFING_ASSIGNMENT_COMMIT.create_arrangement(
			host._work.staffing,
			host.resident_registry.records,
			resident_id,
			target,
			assignment_minute,
		) as Dictionary
		if arrangement_result.get("ok") != true:
			host.SOCIAL_ASSIGNMENT_RESULT_RUNTIME.record_result(host,
				assignment,
				resident_id,
				STAFFING_ASSIGNMENT_POLICY.rejection_result(
					matter_id,
					resident_id,
					"兼职、轮班或试岗安排发生冲突",
				),
				"failed",
			)
			return
		PLACE_SERVICE_COMMAND_RUNTIME.refresh_staffing(host)
		host._bump_world_revision(false)
		var arrangement := arrangement_result.get("arrangement", {}) as Dictionary
		host.SOCIAL_ASSIGNMENT_RESULT_RUNTIME.record_result(host,
			assignment,
			resident_id,
			STAFFING_ASSIGNMENT_POLICY.arrangement_result(
				arrangement,
				target_occupation_id,
				assignment_kind,
			),
			"completed",
		)
		host.OCCUPATION_RESIDENT_CONTEXT_RUNTIME.sync_staffing_matters(host)
		host._schedule_decision(resident_id, true)
		host._notify_world_revision()
		return
	host.ACTION_SETTLEMENT_RUNTIME.interrupt(host, resident_id, "居民自愿转岗，原工作已经交回待办")
	host._work.tasks.release_tasks_for_resident(
		resident_id,
		"原负责人已经转岗，任务等待重新接取",
	)
	STAFFING_ASSIGNMENT_COMMIT.transfer(
		host._work.staffing,
		host.resident_registry.records,
		resident,
		target,
		target_occupation,
		assignment_minute,
	)
	PLACE_SERVICE_COMMAND_RUNTIME.refresh_staffing(host)
	host._bump_world_revision(false)
	host._emit_resident_state_changed(resident_id)
	host.SOCIAL_ASSIGNMENT_RESULT_RUNTIME.record_result(host,
		assignment,
		resident_id,
		STAFFING_ASSIGNMENT_POLICY.transfer_result(
			matter_id,
			resident_id,
			target_occupation_id,
			assignment_kind,
		),
		"completed",
	)
	host.OCCUPATION_RESIDENT_CONTEXT_RUNTIME.sync_staffing_matters(host)
	host._schedule_decision(resident_id, true)
	host._notify_world_revision()
