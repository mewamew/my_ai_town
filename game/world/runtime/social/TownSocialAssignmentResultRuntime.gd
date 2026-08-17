class_name TownSocialAssignmentResultRuntime
extends RefCounted


static func start_matching_action(
	host,
	resident_id: String,
	action: Dictionary,
) -> void:
	var active_statuses: Array[String] = ["assigned"]
	for assignment: Dictionary in host.SOCIAL_GOAL_MATCHING_RUNTIME.active_assignments(host,
		resident_id,
		active_statuses,
	):
		var action_goal := assignment.get("action_goal", {}) as Dictionary
		if not host.SOCIAL_GOAL_MATCHING_RUNTIME.goal_matches_action(host, action_goal, action, resident_id):
			continue
		var result := host._social_matters.start_execution(
			String(assignment.get("matter_id", "")),
			resident_id,
			String(action_goal.get("goal_id", "")),
			int(host._environment.get_absolute_minute()),
		) as Dictionary
		if result.get("ok") == true:
			host.SOCIAL_MATTER_COMMAND_RUNTIME.emit_summary(
				host,
				String(assignment.get("matter_id", "")),
			)


static func record_matching_action_result(
	host,
	resident_id: String,
	action: Dictionary,
	status: String,
	reason: String,
) -> void:
	var active_statuses: Array[String] = ["executing"]
	for assignment: Dictionary in host.SOCIAL_GOAL_MATCHING_RUNTIME.active_assignments(host,
		resident_id,
		active_statuses,
	):
		var action_goal := assignment.get("action_goal", {}) as Dictionary
		if not host.SOCIAL_GOAL_MATCHING_RUNTIME.action_type_matches(action_goal, action):
			continue
		var result_status := status
		var result_reason := reason
		if (
			status == "completed"
			and not host.SOCIAL_GOAL_MATCHING_RUNTIME.goal_matches_action(host,
				action_goal,
				action,
				resident_id,
			)
		):
			result_status = "failed"
			result_reason = "观察目标已经不在居民当前可感知范围内"
		record_result(
			host,
			assignment,
			resident_id,
			{
				"result_id": "action:%s" % String(action.get("action_id", "")),
				"action_id": String(action.get("action_id", "")),
				"reason": result_reason,
			},
			result_status,
		)


static func start_matching_activity(
	host,
	resident_id: String,
	execution: Dictionary,
) -> void:
	var active_statuses: Array[String] = ["assigned"]
	for assignment: Dictionary in host.SOCIAL_GOAL_MATCHING_RUNTIME.active_assignments(host,
		resident_id,
		active_statuses,
	):
		var action_goal := assignment.get("action_goal", {}) as Dictionary
		if not host.SOCIAL_GOAL_MATCHING_RUNTIME.goal_matches_activity(action_goal, execution):
			continue
		var result := host._social_matters.start_execution(
			String(assignment.get("matter_id", "")),
			resident_id,
			String(action_goal.get("goal_id", "")),
			int(host._environment.get_absolute_minute()),
		) as Dictionary
		if result.get("ok") == true:
			host.SOCIAL_MATTER_COMMAND_RUNTIME.emit_summary(
				host,
				String(assignment.get("matter_id", "")),
			)


static func record_matching_activity_result(
	host,
	resident_id: String,
	execution: Dictionary,
	status: String,
	reason: String,
	bulletin_effect: Dictionary = {},
) -> void:
	var active_statuses: Array[String] = ["executing"]
	for assignment: Dictionary in host.SOCIAL_GOAL_MATCHING_RUNTIME.active_assignments(host,
		resident_id,
		active_statuses,
	):
		var action_goal := assignment.get("action_goal", {}) as Dictionary
		if not host.SOCIAL_GOAL_MATCHING_RUNTIME.goal_matches_activity(action_goal, execution):
			continue
		var result_status := status
		var result_reason := reason
		if (
			status == "completed"
			and bool(bulletin_effect.get("handled", false))
			and bulletin_effect.get("ok") != true
		):
			result_status = "failed"
			result_reason = String(
				bulletin_effect.get("reason", "公告栏操作没有形成有效世界结果")
			)
		record_result(
			host,
			assignment,
			resident_id,
			{
				"result_id": "activity:%s" % String(execution.get("actionId", "")),
				"action_id": String(execution.get("actionId", "")),
				"activity_id": String(execution.get("activityId", "")),
				"bulletin_result_id": String(
					bulletin_effect.get("result_id", "")
				),
				"reason": result_reason,
			},
			result_status,
		)


static func record_result(
	host,
	assignment: Dictionary,
	resident_id: String,
	result_ref: Dictionary,
	status: String,
) -> void:
	var matter_id := String(assignment.get("matter_id", ""))
	var action_goal := assignment.get("action_goal", {}) as Dictionary
	var result := host._social_matters.record_action_result(
		matter_id,
		resident_id,
		String(action_goal.get("goal_id", "")),
		result_ref,
		status,
		int(host._environment.get_absolute_minute()),
	) as Dictionary
	if result.get("ok") != true:
		return
	var matter := host._social_matters.get_matter(matter_id) as Dictionary
	var source_ref := matter.get("source_state_ref", {}) as Dictionary
	if status == "completed":
		if String(source_ref.get("source_kind", "")) == "animal_attention":
			_resolve_animal_attention_source(host, matter)
		elif (
			not host.SOCIAL_GOAL_MATCHING_RUNTIME.matter_has_active_participants(matter)
			and String(source_ref.get("source_kind", "")) != "place_service_pressure"
		):
			host._social_matters.close_matter(
				matter_id,
				"social.resolve.goal_completed",
				String(action_goal.get("success_result_id", "")),
				[result_ref],
				int(host._environment.get_absolute_minute()),
			)
	elif (
		String(source_ref.get("source_kind", "")) == "conversation_commitment"
		and not host.SOCIAL_GOAL_MATCHING_RUNTIME.matter_has_active_participants(matter)
	):
		# 对话承诺只有明确承诺者；失败、退出或中断后直接关闭，避免
		# 旧承诺重新开放成无人负责的公共求助并阻断后续行动。
		host._social_matters.close_matter(
			matter_id,
			"social.resolve.cancelled",
			"commitment_failed",
			[result_ref],
			int(host._environment.get_absolute_minute()),
		)
	host.SOCIAL_MATTER_COMMAND_RUNTIME.emit_summary(host, matter_id)


static func _resolve_animal_attention_source(host, matter: Dictionary) -> void:
	var fact: Dictionary = host._animal_fact_runtime.clear_public_attention(
		String((matter.get("source_state_ref", {}) as Dictionary).get("source_id", "")),
		int(host._environment.get_absolute_minute()),
	)
	if fact.is_empty():
		return
	host.ANIMAL_COMMAND_RUNTIME.sync_attention_fact(host, fact)
