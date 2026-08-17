class_name TownClinicServiceRequestPolicy
extends RefCounted


static func build_condition_context(
	conditions: Array,
	conflict_snapshot: Dictionary,
) -> Dictionary:
	var condition_ids: Array[String] = []
	var labels: Array[String] = []
	for condition_value: Variant in conditions:
		if not condition_value is Dictionary:
			continue
		var condition := condition_value as Dictionary
		var condition_id := String(
			condition.get("conditionId", ""),
		).strip_edges()
		if condition_id.is_empty():
			continue
		condition_ids.append(condition_id)
		labels.append(String(condition.get("label", "身体不适")))
	var conflict_injury_ids: Array[String] = []
	var conflict_labels: Array[String] = []
	var conflict_injury_requires_treatment := false
	for injury_value: Variant in conflict_snapshot.get(
		"conflict_injuries",
		[],
	) as Array:
		if injury_value is not Dictionary:
			continue
		var injury := injury_value as Dictionary
		var injury_id := String(injury.get("injury_id", "")).strip_edges()
		if injury_id.is_empty():
			continue
		conflict_injury_ids.append(injury_id)
		var severity := String(injury.get("severity", ""))
		var source_name := String(injury.get("source_actor_name", "对方"))
		conflict_labels.append(
			"冲突造成的%s（来源%s）" % [
				"重伤" if severity == "heavy" else "轻伤",
				source_name if not source_name.is_empty() else "对方",
			]
		)
		if severity == "heavy":
			conflict_injury_requires_treatment = true
	if condition_ids.is_empty() and conflict_injury_ids.is_empty():
		return {}
	var requested_condition_ids: Array[String] = condition_ids.duplicate()
	requested_condition_ids.append_array(conflict_injury_ids)
	var subject_labels: Array[String] = labels.duplicate()
	subject_labels.append_array(conflict_labels)
	return {
		"subjectRef": "；".join(subject_labels),
		"context": {
			"conditionIds": requested_condition_ids,
			"generatedFromResidentCondition": not condition_ids.is_empty(),
			"conflictInjuryIds": conflict_injury_ids,
			"generatedFromConflictInjury": not conflict_injury_ids.is_empty(),
			"conflictInjuryRequiresTreatment": (
				conflict_injury_requires_treatment
			),
		},
	}


static func request_has_active_execution(
	task: Dictionary,
	executable_practitioner_ids: Array[String],
	bound_task_id: String,
	medical_interview: Dictionary,
	conversation_status: String,
) -> bool:
	var task_id := String(task.get("taskId", ""))
	var assigned_id := String(task.get("assignedResidentId", ""))
	if (
		task_id.is_empty()
		or assigned_id.is_empty()
		or not executable_practitioner_ids.has(assigned_id)
	):
		return false
	if bound_task_id == task_id:
		return true
	return (
		String(medical_interview.get("clinicianResidentId", ""))
		== assigned_id
		and not String(
			medical_interview.get("conversationId", ""),
		).is_empty()
		and conversation_status == "active"
	)


static func request_has_executable_practitioner(
	task: Dictionary,
	executable_practitioner_ids: Array[String],
) -> bool:
	if executable_practitioner_ids.is_empty():
		return false
	var assigned_id := String(task.get("assignedResidentId", ""))
	return (
		assigned_id.is_empty()
		or executable_practitioner_ids.has(assigned_id)
	)
