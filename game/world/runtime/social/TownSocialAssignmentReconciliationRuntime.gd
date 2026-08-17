class_name TownSocialAssignmentReconciliationRuntime
extends RefCounted


static func reconcile(host, matter_id: String) -> void:
	var matter := host._social_matters.get_matter(matter_id) as Dictionary
	if matter.is_empty():
		return
	for resident_value: Variant in (matter.get("participants", {}) as Dictionary):
		var resident_id := String(resident_value)
		var participant := (
			(matter.get("participants", {}) as Dictionary).get(
				resident_id,
				{},
			) as Dictionary
		)
		if (
			String(participant.get("status", "")) != "assigned"
			or not host.resident_registry.records.has(resident_id)
		):
			continue
		var resident := host.resident_registry.records.get(resident_id, {}) as Dictionary
		var action_goal := participant.get("action_goal", {}) as Dictionary
		if String(action_goal.get("capability_id", "")) == "staffing.apply_assignment":
			host.STAFFING_ASSIGNMENT_SUBMISSION_RUNTIME.apply(host,
				matter_id,
				resident_id,
				action_goal,
			)
			continue
		if (
			String(action_goal.get("capability_id", "")) == "world.go_to_place"
			and String(resident.get("currentPlace", ""))
			== String(
				(action_goal.get("target_refs", {}) as Dictionary).get(
					"place_id",
					"",
				)
			)
		):
			var assignment := {
				"matter_id": matter_id,
				"action_goal": action_goal.duplicate(true),
			}
			var started := host._social_matters.start_execution(
				matter_id,
				resident_id,
				String(action_goal.get("goal_id", "")),
				int(host._environment.get_absolute_minute()),
			) as Dictionary
			if started.get("ok") == true:
				host.SOCIAL_ASSIGNMENT_RESULT_RUNTIME.record_result(host,
					assignment,
					resident_id,
					{
						"result_id": "already-at-place:%s:%s" % [matter_id, resident_id],
						"capability_id": "world.go_to_place",
						"place_id": String(resident.get("currentPlace", "")),
					},
					"completed",
				)
			continue
		var action := resident.get("currentAction", {}) as Dictionary
		if action.is_empty():
			continue
		var execution := host._activity_runtime.execution_for_action(
			resident_id,
			String(action.get("action_id", "")),
		) as Dictionary
		if not execution.is_empty():
			host.SOCIAL_ASSIGNMENT_RESULT_RUNTIME.start_matching_activity(host, resident_id, execution)
		else:
			host.SOCIAL_ASSIGNMENT_RESULT_RUNTIME.start_matching_action(host, resident_id, action)
