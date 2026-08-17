class_name TownWorkTaskCommandRuntime
extends RefCounted


static func create(
	work_tasks: TownWorkTaskRuntime,
	spec: Dictionary,
	absolute_minute: int,
	resident_order: Array[String],
	occupation_ids_by_resident: Dictionary,
) -> Dictionary:
	var prepared := spec.duplicate(true)
	if not prepared.has("createdAtMinute"):
		prepared["createdAtMinute"] = absolute_minute
	var created := work_tasks.create_task(prepared) as Dictionary
	if created.get("ok") != true:
		return created
	var task := created.get("task", {}) as Dictionary
	var eligible_occupations := task.get(
		"eligibleOccupationIds",
		[],
	) as Array
	var eligible_residents := task.get(
		"eligibleResidentIds",
		[],
	) as Array
	var scheduled: Array[String] = []
	for resident_id: String in resident_order:
		var occupation_ids := occupation_ids_by_resident.get(
			resident_id,
			[],
		) as Array
		var occupation_eligible := false
		for occupation_value: Variant in occupation_ids:
			if eligible_occupations.has(String(occupation_value)):
				occupation_eligible = true
				break
		if occupation_eligible or eligible_residents.has(resident_id):
			scheduled.append(resident_id)
	return {
		"ok": true,
		"changed": true,
		"task": task.duplicate(true),
		"scheduleResidentIds": scheduled,
	}


static func reserve(
	work_tasks: TownWorkTaskRuntime,
	task: Dictionary,
	preferred_occupation_id: String,
	candidates: Array[Dictionary],
) -> Dictionary:
	if (
		task.is_empty()
		or String(task.get("state", "")) not in ["open", "waiting"]
		or not String(task.get("assignedResidentId", "")).is_empty()
	):
		return {"task": task.duplicate(true), "selectedResidentId": ""}
	var selected: Dictionary = {}
	var selected_task_count := 2147483647
	for candidate: Dictionary in candidates:
		var resident_id := String(candidate.get("residentId", ""))
		var active_task_count := 0
		for value: Variant in work_tasks.tasks_for_resident(resident_id) as Array:
			var active_task := value as Dictionary
			if String(active_task.get("state", "")) in [
				"accepted",
				"in_progress",
				"waiting",
			]:
				active_task_count += 1
		if active_task_count < selected_task_count:
			selected = candidate
			selected_task_count = active_task_count
	if selected.is_empty():
		return {"task": task.duplicate(true), "selectedResidentId": ""}
	var resident_id := String(selected.get("residentId", ""))
	var occupation_id := String(selected.get("acceptanceOccupationId", ""))
	if bool(selected.get("canUsePreferredOccupation", false)):
		occupation_id = preferred_occupation_id
	var accepted := work_tasks.accept_task(
		String(task.get("taskId", "")),
		resident_id,
		occupation_id,
		int(task.get("revision", 0)),
	) as Dictionary
	if accepted.get("ok") != true:
		return {"task": task.duplicate(true), "selectedResidentId": ""}
	return {
		"task": (
			accepted.get("task", {}) as Dictionary
		).duplicate(true),
		"selectedResidentId": resident_id,
	}
