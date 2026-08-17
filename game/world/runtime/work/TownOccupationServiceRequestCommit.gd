class_name TownOccupationServiceRequestCommit
extends RefCounted


const REQUEST_RUNTIME := preload(
	"res://world/runtime/work/TownOccupationServiceRequestRuntime.gd"
)

var _occupation_services: TownOccupationServiceRuntime
var _work_tasks: TownWorkTaskRuntime
var _clinic_interviews: TownClinicInterviewPolicy


func _init(
	occupation_services: TownOccupationServiceRuntime,
	work_tasks: TownWorkTaskRuntime,
	clinic_interviews: TownClinicInterviewPolicy,
) -> void:
	_occupation_services = occupation_services
	_work_tasks = work_tasks
	_clinic_interviews = clinic_interviews


func create_task(
	prepared: Dictionary,
	request: Dictionary,
	task: Dictionary,
	absolute_minute: int,
) -> Dictionary:
	var request_id := String(request.get("requestId", ""))
	if not task.is_empty():
		return {"ok": true, "task": task, "createdNonPlaceTask": false}
	var definition := prepared.get("definition", {}) as Dictionary
	var task_result := REQUEST_RUNTIME.create_non_place_task(
		_work_tasks,
		request,
		definition,
		String(prepared.get("requesterResidentId", "")),
		absolute_minute,
	) as Dictionary
	if task_result.get("ok") != true:
		return {
			"ok": false,
			"failure": REQUEST_RUNTIME.cancelled_failure(
				_occupation_services,
				request_id,
				"职业任务创建失败",
				task_result,
			),
		}
	return {
		"ok": true,
		"task": task_result.get("task", {}) as Dictionary,
		"createdNonPlaceTask": true,
	}


func configure_task(
	prepared: Dictionary,
	task: Dictionary,
	request_id: String,
) -> Dictionary:
	return REQUEST_RUNTIME.configure_and_attach_task(
		_occupation_services,
		_work_tasks,
		_clinic_interviews,
		prepared,
		task,
		request_id,
	) as Dictionary
