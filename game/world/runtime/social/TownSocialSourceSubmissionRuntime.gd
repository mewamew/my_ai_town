class_name TownSocialSourceSubmissionRuntime
extends RefCounted


const INITIAL_SOCIAL_CONTACT_POLICY := preload(
	"res://world/runtime/social/TownInitialSocialContactPolicy.gd"
)
const RUNTIME_LOG_TEXT := preload(
	"res://world/runtime/log/TownRuntimeLogText.gd"
)
const SOURCE_REFERENCE_VALIDATOR := preload(
	"res://world/runtime/social/TownSocialSourceReferenceValidator.gd"
)


static func sync(
	host,
	method: String,
	source_state: Dictionary,
) -> Dictionary:
	if not host._running:
		return host._command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	var reference_errors: Array[String] = source_reference_errors(
		host,
		method,
		source_state,
	)
	if not reference_errors.is_empty():
		return host._command_failure(
			"SOCIAL_SOURCE_REFERENCE_INVALID",
			reference_errors,
		)
	var sync_minute := int(host._environment.get_absolute_minute())
	var result: Dictionary
	match method:
		"sync_place_service_pressure":
			result = host._social_sources.sync_place_service_pressure(source_state, sync_minute)
		"sync_resident_request":
			result = host._social_sources.sync_resident_request(source_state, sync_minute)
		"sync_conversation_commitment":
			result = host._social_sources.sync_conversation_commitment(source_state, sync_minute)
		"sync_animal_attention":
			result = host._social_sources.sync_animal_attention(source_state, sync_minute)
		"sync_job_vacancy":
			result = host._social_sources.sync_job_vacancy(source_state, sync_minute)
		_:
			# 五个同名门面固定传入这些方法，按构造不可达。
			push_error("未知社会事项来源方法:%s" % method)
			result = host._command_failure(
				"SOCIAL_SOURCE_REFERENCE_INVALID",
				["未知社会事项来源方法:%s" % method],
			)
	var matter_id := ""
	if result.get("value") is Dictionary:
		var matter := (
			(result.get("value", {}) as Dictionary).get("matter", {}) as Dictionary
		)
		matter_id = String(matter.get("matter_id", ""))
	if result.get("ok") == true and not matter_id.is_empty():
		prepare_initial_contacts(host, method, source_state, matter_id)
		host.SOCIAL_RESPONSE_ROUND_RUNTIME.begin_initial(
			host,
			method,
			source_state,
			matter_id,
		)
		# 对话承诺已经由 conversation_follow_up 明确选定；这里再次开启
		# 回应轮会把同一个承诺变成第二次待答复并阻断执行。
		if method != "sync_conversation_commitment":
			host.SOCIAL_RESPONSE_ROUND_RUNTIME.maybe_begin_after_exposures(host, matter_id)
	return host.SOCIAL_MATTER_COMMAND_RUNTIME.finalize_mutation(host, result, matter_id)


static func source_reference_errors(
	host,
	method: String,
	source_state: Dictionary,
) -> Array[String]:
	var announcement_ids: Array[String] = []
	for announcement: Dictionary in host._community_bulletin.get_announcements(
		true,
	) as Array[Dictionary]:
		announcement_ids.append(String(announcement.get("announcement_id", "")))
	return SOURCE_REFERENCE_VALIDATOR.errors(
		method,
		source_state,
		host.world_definition.world_data,
		host.resident_registry.records,
		host.resident_registry.id_by_name,
		host.conversation_state.records,
		announcement_ids,
	)


static func prepare_initial_contacts(
	host,
	method: String,
	source_state: Dictionary,
	matter_id: String,
) -> void:
	var now := int(host._environment.get_absolute_minute())
	var residents: Array[String] = INITIAL_SOCIAL_CONTACT_POLICY.source_resident_ids(
		method,
		source_state,
		method == "sync_resident_request",
		host.resident_registry.order,
		host.resident_registry.records,
		host.resident_registry.id_by_name,
	)
	var requester_id: String = host._resident_key(
		String(source_state.get("requester_id", ""))
	)
	var promisor_id: String = host._resident_key(
		String(source_state.get("promisor_id", ""))
	)
	var beneficiary_id: String = host.person_id_for_name(
		String(source_state.get("beneficiary_id", ""))
	)
	var owner_id: String = host._resident_key(
		String(source_state.get("owner_id", ""))
	)
	var operations: Array[Dictionary] = INITIAL_SOCIAL_CONTACT_POLICY.operations(
		method,
		source_state,
		now,
		residents,
		requester_id,
		promisor_id,
		beneficiary_id,
		owner_id,
		RUNTIME_LOG_TEXT.initial_social_exposure_clue(method, source_state),
	)
	for operation: Dictionary in operations:
		var resident_id := String(operation.get("residentId", ""))
		match String(operation.get("kind", "")):
			"involvement":
				host._social_matters.record_involvement(
					matter_id,
					resident_id,
					String(operation.get("role", "")),
					int(operation.get("updatedAt", now)),
				)
			"awareness":
				host._social_matters.record_awareness(
					matter_id,
					resident_id,
					String(operation.get("awareness", "")),
					String(operation.get("acquiredVia", "")),
					String(operation.get("sourceId", "")),
					int(operation.get("updatedAt", now)),
				)
			"exposure":
				host._social_matters.offer_exposure(
					matter_id,
					resident_id,
					String(operation.get("channel", "")),
					String(operation.get("clue", "")),
					String(operation.get("sourceId", "")),
					int(operation.get("createdAt", now)),
					int(operation.get("expiresAt", now + 1)),
				)
			"schedule_decision":
				host._schedule_decision(resident_id, false)


static func submit_optional_request(
	host,
	resident_id: String,
	action: Dictionary,
	request: Dictionary,
) -> void:
	if request.is_empty() or String(action.get("type", "")) != "搭话":
		return
	var recipient_id: String = host._resident_key(
		String(request.get("recipient_id", ""))
	)
	var target_id: String = host._resident_key(
		String(action.get("target_resident_id", ""))
	)
	var place_id := String(request.get("place_id", "")).strip_edges()
	var reason_summary := String(request.get("reason_summary", "")).strip_edges()
	if (
		recipient_id.is_empty()
		or recipient_id != target_id
		or place_id.is_empty()
		or host.get_place_detail(place_id).is_empty()
		or reason_summary.is_empty()
		or reason_summary.length() > 80
		or reason_summary.contains("\n")
		or reason_summary.contains("\r")
		or reason_summary.contains("\t")
	):
		return
	var now := int(host._environment.get_absolute_minute())
	host.sync_resident_request({
		"request_id": "resident-request:%s:%s" % [
			resident_id,
			String(action.get("action_id", "")),
		],
		"source_revision": 1,
		"requester_id": resident_id,
		"recipient_ids": [recipient_id],
		"submitted": true,
		"active": true,
		"reason_summary": reason_summary,
		"subject_ids": [resident_id],
		"place_id": place_id,
		"capability_id": "world.go_to_place",
		"target_refs": {
			"place_id": place_id,
			"resident_id": resident_id,
		},
		"success_result_id": "helper-arrived",
		"expires_at": now + 180,
		"capacity": 1,
		"source_event_ids": [
			"direct-request:%s" % String(action.get("action_id", "")),
		],
	})
