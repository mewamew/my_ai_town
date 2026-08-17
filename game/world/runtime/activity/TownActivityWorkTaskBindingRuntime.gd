class_name TownActivityWorkTaskBindingRuntime
extends RefCounted


var _bindings: Dictionary = {}


func reset() -> void:
	_bindings.clear()


func snapshot() -> Dictionary:
	return _bindings.duplicate(true)


func restore(value: Dictionary) -> void:
	_bindings = value.duplicate(true)


func bind(resident_id: String, action_id: String, task_id: String) -> void:
	var key := binding_key(resident_id, action_id)
	var normalized_task_id := task_id.strip_edges()
	if not key.ends_with(":") and not normalized_task_id.is_empty():
		_bindings[key] = normalized_task_id


static func claim_for_execution(
	host,
	resident_id: String,
	execution: Dictionary,
) -> void:
	if String(execution.get("role", "")) != "worker":
		return
	var activity_id := String(execution.get("activityId", ""))
	var occupation_id: String = host.OCCUPATION_RESIDENT_CONTEXT_RUNTIME.id_for_activity(host,
		resident_id,
		activity_id,
	)
	if occupation_id.is_empty() or activity_id.is_empty():
		return
	var candidates := host._work.tasks.tasks_for_activity(
		occupation_id,
		activity_id,
		resident_id,
	) as Array
	candidates = host._work.available_work_tasks(
		candidates,
		host.resident_registry.records,
	)
	if candidates.is_empty():
		return
	var physical_target := host._activity_runtime.execution_physical_target(
		execution,
	) as Dictionary
	var execution_targets: Array[Dictionary] = []
	if not physical_target.is_empty():
		execution_targets.append(physical_target)
	candidates = host.ACTIVITY_SCALARS.matching_work_tasks_for_targets(candidates, execution_targets)
	if candidates.is_empty():
		return
	var claimed: Dictionary = host._work.claim_specific_work_task(
		candidates[0] as Dictionary,
		occupation_id,
		resident_id,
		host.resident_registry.records,
	)
	if claimed.get("ok") != true:
		return
	var action_id := String(execution.get("actionId", ""))
	if action_id.is_empty():
		return
	host.activity_work_task_bindings.bind(
		resident_id,
		action_id,
		String((claimed.get("task", {}) as Dictionary).get("taskId", "")),
	)


func resolved_key(resident_id: String, action_id: String) -> String:
	var exact_key := binding_key(resident_id, action_id)
	if _bindings.has(exact_key):
		return exact_key
	var resident_prefix := "%s:" % resident_id
	var resident_bindings: Array[String] = []
	for key_value: Variant in _bindings:
		var candidate_key := String(key_value)
		if candidate_key.begins_with(resident_prefix):
			resident_bindings.append(candidate_key)
	return resident_bindings[0] if resident_bindings.size() == 1 else ""


func task_id_for_key(key: String) -> String:
	return String(_bindings.get(key, ""))


func task_id_for(resident_id: String, action_id: String) -> String:
	return task_id_for_key(resolved_key(resident_id, action_id))


func erase_key(key: String) -> void:
	_bindings.erase(key)


func release_task_from_activity(
	resident_id: String,
	execution: Dictionary,
	lifecycle: String,
	work_tasks: TownWorkTaskRuntime,
) -> void:
	var binding := resolved_key(
		resident_id,
		String(execution.get("actionId", "")),
	)
	if binding.is_empty():
		return
	var task_id := task_id_for_key(binding)
	erase_key(binding)
	var task := work_tasks.task(task_id) as Dictionary
	if task.is_empty() or String(task.get("state", "")) != "in_progress":
		return
	var reason := (
		"活动过程已完成，等待 World 提交实际结果"
		if lifecycle == "completed"
		else "活动过程%s，任务保留等待重新决定"
		% ("被中断" if lifecycle == "interrupted" else "失败")
	)
	work_tasks.wait_task(
		task_id,
		resident_id,
		int(task.get("revision", 0)),
		reason,
	)


static func binding_key(resident_id: String, action_id: String) -> String:
	return "%s:%s" % [resident_id, action_id]
