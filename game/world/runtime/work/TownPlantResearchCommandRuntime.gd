class_name TownPlantResearchCommandRuntime
extends RefCounted


const PRODUCTION_TASK_COORDINATION_RUNTIME := preload(
	"res://world/runtime/work/TownProductionTaskCoordinationRuntime.gd"
)


static func create(
	host,
	requester_ref: String,
	question: String,
	source_kind: String,
) -> Dictionary:
	if not host._running:
		return host._command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	var requester_id: String = host._resident_key(requester_ref)
	if requester_id.is_empty():
		return host._command_failure(
			"PLANT_RESEARCH_REQUESTER_INVALID",
			["植物研究必须来自真实居民或正式请求方"],
		)
	var begun: Dictionary = host._work.production.begin_plant_research(
		question,
		source_kind,
		requester_id,
		int(host._environment.get_absolute_minute()),
	)
	if begun.get("ok") != true:
		return host._decorate_command_result(begun)
	var project := begun.get("project", {}) as Dictionary
	var task_result: Dictionary = (
		PRODUCTION_TASK_COORDINATION_RUNTIME.create_plant_research_stage_task(
			host,
			project,
			"observe",
		)
	)
	if task_result.get("ok") != true:
		return host._decorate_command_result(task_result)
	host._bump_world_revision()
	return host._decorate_command_result({
		"ok": true,
		"changed": true,
		"project": project.duplicate(true),
		"task": (task_result.get("task", {}) as Dictionary).duplicate(true),
	})
