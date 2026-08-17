class_name TownWorkTaskPublicRuntime
extends RefCounted


const RESIDENT_WORK_TASK_PROJECTION := preload(
	"res://world/runtime/work/TownResidentWorkTaskProjection.gd"
)
const WORK_TASK_COMMAND_RUNTIME := preload(
	"res://world/runtime/work/TownWorkTaskCommandRuntime.gd"
)


static func create(host, spec: Dictionary) -> Dictionary:
	if not host._running:
		return host._command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	var occupations_by_resident: Dictionary = {}
	for resident_id: String in host.resident_registry.order:
		occupations_by_resident[resident_id] = (
			host.OCCUPATION_RESIDENT_CONTEXT_RUNTIME.ids_for_resident(host, resident_id)
		)
	var result: Dictionary = WORK_TASK_COMMAND_RUNTIME.create(
		host._work.tasks,
		spec,
		int(host._environment.get_absolute_minute()),
		host.resident_registry.order,
		occupations_by_resident,
	)
	if result.get("ok") != true:
		return host._decorate_command_result(result)
	host._bump_world_revision()
	for resident_value: Variant in result.get("scheduleResidentIds", []) as Array:
		host._schedule_decision(
			String(resident_value),
			true,
			false,
			allows_current_activity_interrupt(
				result.get("task", {}) as Dictionary,
				host.PRIORITY_INTERRUPT_THRESHOLD,
			),
		)
	result.erase("scheduleResidentIds")
	return host._decorate_command_result(result)


static func query_for_resident(host, resident_ref: String) -> Array[Dictionary]:
	var resident_id: String = host._resident_key(resident_ref)
	var occupation_ids: Array[String] = (
		host.OCCUPATION_RESIDENT_CONTEXT_RUNTIME.ids_for_resident(host, resident_id)
	)
	return RESIDENT_WORK_TASK_PROJECTION.query(
		resident_id,
		occupation_ids,
		host._work.tasks,
		host._work.cargo,
		host.private_message_runtime,
		host._work.services,
		host._clinic_interviews,
		host.resident_registry.records,
		host.resident_registry.name_by_id,
		host.world_definition.world_data,
		int(host._environment.get_absolute_minute()),
	)


static func reserve(
	host,
	task: Dictionary,
	preferred_occupation_id: String,
) -> Dictionary:
	var present_resident_ids: Array[String] = []
	for resident_id: String in host.resident_registry.order:
		if host.resident_is_present(
			host.resident_registry.records.get(resident_id, {}) as Dictionary,
		):
			present_resident_ids.append(resident_id)
	var reserved: Dictionary = host._work.reserve_work_task(
		task,
		preferred_occupation_id,
		host.resident_registry.order,
		host.resident_registry.records,
		host.world_definition.world_data,
		present_resident_ids,
		int(host._environment.get_absolute_minute()),
	)
	var selected_resident_id := String(reserved.get("selectedResidentId", ""))
	if not selected_resident_id.is_empty():
		host._schedule_decision(
			selected_resident_id,
			true,
			false,
			allows_current_activity_interrupt(
				task, host.PRIORITY_INTERRUPT_THRESHOLD,
			),
		)
	return (reserved.get("task", task) as Dictionary).duplicate(true)


static func allows_current_activity_interrupt(task: Dictionary, threshold: int) -> bool:
	return int(task.get("priority", 0)) >= threshold


static func resident_is_actively_processing(
	host,
	resident_id: String,
	task_id: String,
) -> bool:
	if resident_id.is_empty() or task_id.is_empty():
		return false
	var resident := host.resident_registry.records.get(resident_id, {}) as Dictionary
	var current_action_id := String(
		(resident.get("currentAction", {}) as Dictionary).get("action_id", ""),
	)
	if current_action_id.is_empty():
		return false
	return host.activity_work_task_bindings.task_id_for_key(
		host.ACTIVITY_WORK_TASK_BINDING_RUNTIME.binding_key(
			resident_id,
			current_action_id,
		),
	) == task_id


static func natural_bulletin_task_for_resident(
	host,
	resident_id: String,
) -> Dictionary:
	if host.OCCUPATION_RESIDENT_CONTEXT_RUNTIME.primary_id(
		host,
		host.resident_registry.records.get(resident_id, {}) as Dictionary,
	) != "occupation_town_manager":
		return {}
	for task_value: Variant in host._work.tasks.tasks_for_occupation(
		"occupation_town_manager",
		resident_id,
	) as Array:
		var task := task_value as Dictionary
		if (
			String(task.get("capability", "")) == "bulletin.publish"
			and String(task.get("state", "")) in [
				"open", "waiting", "accepted", "in_progress",
			]
		):
			return task.duplicate(true)
	return {}


static func complete(
	host,
	task_id: String,
	resident_ref: String,
	result_kind: String,
	evidence: Dictionary,
) -> Dictionary:
	if not host._running:
		return host._command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	var resident_id: String = host._resident_key(resident_ref)
	if resident_id.is_empty():
		return host._command_failure(
			"RESIDENT_NOT_FOUND",
			["找不到提交工作结果的居民"],
		)
	var task := host._work.tasks.task(task_id) as Dictionary
	if task.is_empty():
		return host._command_failure("WORK_TASK_NOT_FOUND", ["工作任务不存在"])
	var result: Dictionary = host._work.tasks.complete_task(
		task_id,
		resident_id,
		int(task.get("revision", 0)),
		result_kind,
		evidence,
	)
	if result.get("ok") != true:
		return host._decorate_command_result(result)
	host._bump_world_revision()
	return host._decorate_command_result({
		"ok": true,
		"changed": true,
		"task": (result.get("task", {}) as Dictionary).duplicate(true),
	})
