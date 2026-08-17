class_name TownClinicInterviewRuntime
extends RefCounted


const CONVERSATION_RUNTIME := preload(
	"res://world/runtime/conversation/TownConversationRuntime.gd"
)
const CONTENT_CATALOG := preload(
	"res://world/data/town/TownWorkContentCatalog.gd"
)


static func binding_for_pair(
	host,
	clinician_resident_id: String,
	patient_resident_id: String,
) -> Dictionary:
	var clinician := host.resident_registry.records.get(clinician_resident_id, {}) as Dictionary
	var patient := host.resident_registry.records.get(patient_resident_id, {}) as Dictionary
	if (
		clinician.is_empty()
		or patient.is_empty()
		or String(clinician.get("currentPlace", "")) != CONTENT_CATALOG.PLACE_CLINIC
		or String(patient.get("currentPlace", "")) != CONTENT_CATALOG.PLACE_CLINIC
	):
		return {}
	for task_value: Variant in host.get_work_tasks_for_resident(
		clinician_resident_id,
	):
		var task := task_value as Dictionary
		var service_request := task.get("service_request", {}) as Dictionary
		var medical_dialogue := service_request.get("medical_dialogue", {}) as Dictionary
		if (
			String(service_request.get("kind", "")) == "clinic"
			and String(service_request.get("requester_resident_id", ""))
			== patient_resident_id
			and String(medical_dialogue.get("status", ""))
			in ["required", "interrupted"]
		):
			return {
				"requestId": String(service_request.get("request_id", "")),
				"taskId": String(task.get("task_id", "")),
			}
	return {}


static func projection_for_participant(
	host,
	conversation: Dictionary,
	participant_resident_id: String,
) -> Variant:
	var linked := CONVERSATION_RUNTIME._clinic_interview_for_conversation(
		host,
		conversation,
	)
	if linked.is_empty():
		return null
	var interview := linked.get("context", {}) as Dictionary
	var role := (
		"patient"
		if String(interview.get("patientResidentId", "")) == participant_resident_id
		else "clinician"
	)
	return (
		host._clinic_interviews.projection_for_role(interview, role) as Dictionary
	).duplicate(true)


static func record_response(
	host,
	conversation: Dictionary,
	speaker_resident_id: String,
	action: Dictionary,
	turn_id: int,
) -> void:
	var response_value: Variant = action.get("medical_response")
	if response_value == null or not response_value is Dictionary:
		return
	var linked := CONVERSATION_RUNTIME._clinic_interview_for_conversation(
		host,
		conversation,
	)
	if linked.is_empty():
		return
	var interview := linked.get("context", {}) as Dictionary
	if String(interview.get("patientResidentId", "")) != speaker_resident_id:
		return
	var response := response_value as Dictionary
	var recorded := host._clinic_interviews.record_patient_response(
		interview,
		String(conversation.get("conversationId", "")),
		String(response.get("response_kind", "")),
		turn_id,
	) as Dictionary
	if recorded.get("ok") != true:
		return
	var request := linked.get("request", {}) as Dictionary
	host._work.services.merge_request_context(
		String(request.get("requestId", "")),
		{"medicalInterview": recorded.get("context", {})},
	)
	host._bump_world_revision(false)


static func validate_response(
	host,
	resident_id: String,
	action: Dictionary,
) -> String:
	if not action.has("medical_response") or action.get("medical_response") == null:
		return ""
	var response_value: Variant = action.get("medical_response")
	if not response_value is Dictionary:
		return "medical_response 必须是对象或 null"
	var response := response_value as Dictionary
	if (
		response.size() != 2
		or not response.has("request_id")
		or not response.has("response_kind")
	):
		return "medical_response 只能包含 request_id 和 response_kind"
	if (
		not response.get("request_id") is String
		or String(response.get("request_id", "")).strip_edges().is_empty()
		or not response.get("response_kind") is String
		or String(response.get("response_kind", "")).strip_edges().is_empty()
	):
		return "medical_response 缺少合法的请求编号或回应类型"
	var conversation: Dictionary = CONVERSATION_RUNTIME._active_conversation_for_person(
		host,
		resident_id,
	)
	var medical: Dictionary = projection_for_participant(
		host,
		conversation,
		resident_id,
	)
	if medical.is_empty():
		return "medical_response 只能在当前医患对话中提交"
	if String(medical.get("role", "")) != "patient":
		return "只有患者本人能提交 medical_response"
	if String(response.get("request_id", "")) != String(medical.get("request_id", "")):
		return "medical_response 的请求编号与当前医患对话不一致"
	if not (medical.get("response_options", []) as Array).has(
		String(response.get("response_kind", "")),
	):
		return "medical_response 的回应类型不在当前选项中"
	return ""
