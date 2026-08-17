class_name TownClinicServiceCoordinationRuntime
extends RefCounted


const SERVICE_REQUEST_POLICY := preload(
	"res://world/runtime/work/TownClinicServiceRequestPolicy.gd"
)


static func request_needs_basic_care(
	host,
	patient_resident_id: String,
	request_context: Dictionary,
) -> bool:
	if bool(request_context.get("conflictInjuryRequiresTreatment", false)):
		return true
	var requested_ids: Array = request_context.get("conditionIds", []) as Array
	if requested_ids.is_empty():
		return false
	for condition_value: Variant in host._resident_conditions.get_conditions(
		patient_resident_id,
	) as Array:
		if not condition_value is Dictionary:
			continue
		var condition := condition_value as Dictionary
		var condition_id := String(condition.get("conditionId", ""))
		if (
			requested_ids.has(condition_id)
			and bool(host._resident_conditions.condition_accepts_relief(
				patient_resident_id,
				condition_id,
				"basic_care",
			))
		):
			return true
	return false


static func begin_conflict_injury_treatment(
	host,
	resident_id: String,
	place_id: String,
) -> Dictionary:
	if host._conflict_controller == null:
		return {
			"ok": false,
			"errorCode": "CONFLICT_CONTROLLER_NOT_CONFIGURED",
		}
	return host._conflict_controller.begin_treatment(
		resident_id,
		place_id,
	) as Dictionary


static func apply_visitor_activity_availability(
	host,
	resident_id: String,
	option: Dictionary,
) -> void:
	if not bool(option.get("available", false)):
		return
	var activity_id := String(option.get("activityId", ""))
	if activity_id not in [
		"activity_clinic_consult",
		"activity_clinic_examination",
	]:
		return
	var request: Dictionary = host._work.active_clinic_request_for_resident(
		resident_id,
	)
	if activity_id == "activity_clinic_consult":
		if request.is_empty():
			return
		option["available"] = false
		option["disabledReason"] = "CLINIC_REQUEST_ALREADY_ACTIVE"
		return
	if request.is_empty():
		option["available"] = false
		option["disabledReason"] = "CLINIC_REQUEST_REQUIRED"
		return
	var interview := (
		(request.get("context", {}) as Dictionary).get("medicalInterview", {})
		as Dictionary
	)
	var task := host._work.tasks.task(String(request.get("taskId", ""))) as Dictionary
	if (
		String(interview.get("status", "")) != "completed"
		or String(task.get("processStage", "")) != "ready_examination"
	):
		option["available"] = false
		option["disabledReason"] = "CLINIC_EXAMINATION_NOT_READY"


static func apply_practitioner_request_priority(
	host,
	resident_id: String,
	option: Dictionary,
) -> void:
	if not bool(option.get("available", false)):
		return
	var task := active_consult_task_for_practitioner(host, resident_id)
	if task.is_empty():
		return
	var activity_id := String(option.get("activityId", ""))
	if not activity_id.begins_with("activity_clinic_"):
		return
	var service_request := task.get("service_request", {}) as Dictionary
	var medical_dialogue := service_request.get("medical_dialogue", {}) as Dictionary
	var interview_status := String(medical_dialogue.get("status", ""))
	var allowed_activity_id := (
		"activity_clinic_receive_patient"
		if interview_status == "completed"
		else ""
	)
	if activity_id == allowed_activity_id:
		return
	option["available"] = false
	option["disabledReason"] = (
		"CLINIC_EXAMINATION_HAS_PRIORITY"
		if interview_status == "completed"
		else "CLINIC_INTERVIEW_HAS_PRIORITY"
	)


static func active_consult_task_for_practitioner(
	host,
	resident_id: String,
) -> Dictionary:
	if host.OCCUPATION_RESIDENT_CONTEXT_RUNTIME.primary_id(host,
		host.resident_registry.records.get(resident_id, {}) as Dictionary,
	) != "occupation_clinic_practitioner":
		return {}
	for task: Dictionary in host.get_work_tasks_for_resident(resident_id):
		var service_request := task.get("service_request", {}) as Dictionary
		if (
			String(task.get("capability", "")) == "care.consult"
			and String(service_request.get("kind", "")) == "clinic"
			and String(service_request.get("state", ""))
			in ["pending", "waiting", "in_progress"]
		):
			return task.duplicate(true)
	return {}


static func record_started_request(
	host,
	resident_id: String,
	execution: Dictionary,
) -> void:
	if (
		String(execution.get("role", "")) != "visitor"
		or String(execution.get("activityId", "")) != "activity_clinic_consult"
		or not host._work.active_clinic_request_for_resident(resident_id).is_empty()
	):
		return
	var spec: Dictionary = host.PLACE_SERVICE_COMMAND_RUNTIME.visitor_occupation_service_spec(
		host,
		resident_id,
		"activity_clinic_consult",
	)
	if not spec.is_empty():
		host.create_occupation_service_request(spec)


static func resident_is_completing_bound_work(
	host,
	resident_id: String,
	resident: Dictionary,
) -> bool:
	var action := resident.get("currentAction", {}) as Dictionary
	if action.is_empty():
		return false
	var execution := host._activity_runtime.execution_for_action(
		resident_id,
		String(action.get("action_id", "")),
	) as Dictionary
	if String(execution.get("activityId", "")) not in [
		"activity_clinic_receive_patient",
		"activity_clinic_prepare_medicine",
	]:
		return false
	for occupation_id: String in host.OCCUPATION_RESIDENT_CONTEXT_RUNTIME.ids_for_resident(host, resident_id):
		for task_value: Variant in host._work.tasks.tasks_for_occupation(
			occupation_id,
			resident_id,
		) as Array:
			var task := task_value as Dictionary
			if (
				String(task.get("assignedResidentId", "")) == resident_id
				and String(task.get("state", "")) == "in_progress"
				and String(task.get("capability", ""))
				in ["care.consult", "care.treatment"]
			):
				return true
	return false


static func request_has_active_execution(host, request: Dictionary) -> bool:
	var task := host._work.tasks.task(String(request.get("taskId", ""))) as Dictionary
	var assigned_id := String(task.get("assignedResidentId", ""))
	var assigned := host.resident_registry.records.get(assigned_id, {}) as Dictionary
	var action := assigned.get("currentAction", {}) as Dictionary
	var action_id := String(action.get("action_id", ""))
	var medical_interview := (
		(request.get("context", {}) as Dictionary).get("medicalInterview", {})
		as Dictionary
	)
	var conversation_id := String(medical_interview.get("conversationId", ""))
	return SERVICE_REQUEST_POLICY.request_has_active_execution(
		task,
		executable_practitioner_ids(host),
		host.activity_work_task_bindings.task_id_for(assigned_id, action_id)
		if not action_id.is_empty() else "",
		medical_interview,
		String(
			(host.conversation_state.records.get(conversation_id, {}) as Dictionary).get(
				"status",
				"",
			),
		),
	)


static func executable_practitioner_ids(host) -> Array[String]:
	var result: Array[String] = []
	for resident_id: String in host.resident_registry.order:
		var resident := host.resident_registry.records.get(resident_id, {}) as Dictionary
		if (
			host.OCCUPATION_RESIDENT_CONTEXT_RUNTIME.available_for_work(host, resident)
			and host.OCCUPATION_RESIDENT_CONTEXT_RUNTIME.can_work_occupation(host,
				resident_id,
				"occupation_clinic_practitioner",
			)
		):
			result.append(resident_id)
	return result


static func request_has_executable_practitioner(
	host,
	request: Dictionary,
) -> bool:
	var task := host._work.tasks.task(String(request.get("taskId", ""))) as Dictionary
	return SERVICE_REQUEST_POLICY.request_has_executable_practitioner(
		task,
		executable_practitioner_ids(host),
	)
