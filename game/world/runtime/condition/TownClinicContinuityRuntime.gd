class_name TownClinicContinuityRuntime
extends RefCounted


const CLINIC_COORDINATION := preload(
	"res://world/runtime/condition/TownClinicServiceCoordinationRuntime.gd"
)
const OCCUPATION_SERVICE_DEFINITION := preload(
	"res://world/runtime/work/TownOccupationServiceDefinition.gd"
)
const OCCUPATION_SERVICE_STAFFING_RUNTIME := preload(
	"res://world/runtime/work/TownOccupationServiceStaffingRuntime.gd"
)
const CLINIC_PLACE_ID := "诊所"
const SELF_CARE_ACTIVITY_ID := "activity_clinic_self_care"
const WAIT_ACTIVITY_ID := "activity_clinic_wait"
const EXTERNAL_MEDICAL_AID_PLACE_ID := "镇外医疗援助"
const EXTERNAL_AID_WAIT_MINUTES := 120
const EXTERNAL_AID_RETURN_DELAY_MINUTES := 1
const FORMAL_VISITOR_ACTIVITY_IDS := [
	"activity_clinic_consult",
	"activity_clinic_examination",
]


static func has_executable_practitioner(host) -> bool:
	return not CLINIC_COORDINATION.executable_practitioner_ids(host).is_empty()


static func visitor_service_is_staffed(
	host,
	activity_id: String,
	request_spec: Dictionary,
) -> bool:
	if activity_id in FORMAL_VISITOR_ACTIVITY_IDS:
		return has_executable_practitioner(host)
	if request_spec.is_empty():
		return true
	return OCCUPATION_SERVICE_STAFFING_RUNTIME.service_has_executable_worker(
		host,
		OCCUPATION_SERVICE_DEFINITION.definition(
			String(request_spec.get("kind", "")),
		),
	)


static func active_needs_for_resident(host, resident: Dictionary) -> Array:
	var resident_id := String(resident.get("residentId", "")).strip_edges()
	if resident_id.is_empty():
		return []
	return (
		(host.get_resident_state(resident_id) as Dictionary).get(
			"activeNeeds",
			[],
		) as Array
	).duplicate(true)


static func needs_basic_self_care(active_needs: Array) -> bool:
	return _needs_requirement(active_needs, "basic_care")


static func needs_quiet_rest(active_needs: Array) -> bool:
	return _needs_requirement(active_needs, "rest")


static func has_clinic_care_need(active_needs: Array) -> bool:
	return (
		needs_basic_self_care(active_needs)
		or needs_quiet_rest(active_needs)
	)


static func activity_matches_need(
	activity_id: String,
	active_needs: Array,
) -> bool:
	if activity_id == SELF_CARE_ACTIVITY_ID:
		return needs_basic_self_care(active_needs)
	if activity_id == WAIT_ACTIVITY_ID:
		return needs_quiet_rest(active_needs)
	return false


static func can_admit_without_practitioner(
	host,
	resident: Dictionary,
	place_id: String,
) -> bool:
	return (
		place_id == CLINIC_PLACE_ID
		and not has_executable_practitioner(host)
		and has_clinic_care_need(active_needs_for_resident(host, resident))
	)


static func apply_activity_availability(
	host,
	resident: Dictionary,
	option: Dictionary,
) -> void:
	var activity_id := String(option.get("activityId", ""))
	if activity_id not in [SELF_CARE_ACTIVITY_ID, WAIT_ACTIVITY_ID]:
		return
	if has_executable_practitioner(host):
		if activity_id == SELF_CARE_ACTIVITY_ID:
			option["available"] = false
			option["disabledReason"] = "CLINIC_SELF_CARE_NOT_NEEDED"
		return
	var active_needs := active_needs_for_resident(host, resident)
	var available := activity_matches_need(activity_id, active_needs)
	option["available"] = available
	option["disabledReason"] = (
		""
		if available
		else "CLINIC_SELF_CARE_NOT_NEEDED"
	)


static func advance_external_aid(
	host,
	conflict_controller,
	absolute_minute: int,
) -> Dictionary:
	if (
		conflict_controller == null
		or absolute_minute < 0
		or has_executable_practitioner(host)
	):
		return {"changed": false, "residentIds": []}
	var departed_ids: Array[String] = []
	for injury_value: Variant in (
		conflict_controller.get_public_projection().get("injuries", []) as Array
	):
		if injury_value is not Dictionary:
			continue
		var injury := injury_value as Dictionary
		var resident_id := String(injury.get("actorId", "")).strip_edges()
		if (
			resident_id.is_empty()
			or String(injury.get("severity", "")) != "heavy"
			or String(injury.get("treatmentStatus", "")) != "required"
			or absolute_minute - int(injury.get("appliedAtMinute", absolute_minute))
			< EXTERNAL_AID_WAIT_MINUTES
			or not host.resident_registry.records.has(resident_id)
		):
			continue
		var resident := host.resident_registry.records.get(
			resident_id,
			{},
		) as Dictionary
		if not host.resident_is_present(resident):
			continue
		var treatment := conflict_controller.begin_external_treatment(
			resident_id,
		) as Dictionary
		if treatment.get("ok") != true:
			continue
		_prepare_resident_departure(
			host,
			resident_id,
			resident,
			treatment.get("injury", {}) as Dictionary,
			absolute_minute,
		)
		departed_ids.append(resident_id)
	if departed_ids.is_empty():
		return {"changed": false, "residentIds": []}
	host.work_domain.staffing.rebuild(
		host.OCCUPATION_RESIDENT_CONTEXT_RUNTIME.living_residents_for_staffing(host),
		absolute_minute,
	)
	host.PLACE_SERVICE_COMMAND_RUNTIME.refresh_staffing(host)
	host.OCCUPATION_RESIDENT_CONTEXT_RUNTIME.sync_staffing_matters(host)
	return {
		"changed": true,
		"residentIds": departed_ids,
	}


static func _prepare_resident_departure(
	host,
	resident_id: String,
	resident: Dictionary,
	injury: Dictionary,
	absolute_minute: int,
) -> void:
	var previous_place := String(resident.get("currentPlace", ""))
	var conversation := host.CONVERSATION_RUNTIME._active_conversation_for_person(
		host,
		resident_id,
	) as Dictionary
	if not conversation.is_empty():
		host.CONVERSATION_RUNTIME._end_conversation(
			host,
			host._traveler_relationship_state,
			String(conversation.get("conversationId", "")),
			"一方离开",
			"interrupted",
		)
	if not (resident.get("currentAction", {}) as Dictionary).is_empty():
		host.ACTION_SETTLEMENT_RUNTIME.interrupt(
			host,
			resident_id,
			"重伤等待已超过处理时限，居民离镇接受医疗援助",
		)
	_cancel_active_clinic_requests(host, resident_id)
	host.work_domain.tasks.release_tasks_for_resident(
		resident_id,
		"居民已经离镇就医，任务等待重新接取",
	)
	var return_minute := (
		int(injury.get("treatmentDueAtMinute", absolute_minute))
		+ EXTERNAL_AID_RETURN_DELAY_MINUTES
	)
	resident["arrivalState"] = {
		"status": "pending",
		"scheduledAbsoluteMinute": return_minute,
		"arrivedAbsoluteMinute": -1,
	}
	resident["attendanceState"] = {
		"status": "on_leave",
		"untilMinute": return_minute,
	}
	resident["currentAction"] = {}
	resident["confirmedActionPreview"] = {}
	resident["actionSuspendedAbsoluteMinute"] = -1
	resident["routeConnector"] = []
	resident["doing"] = "离镇接受外部医疗援助"
	resident["movementRevision"] = int(
		resident.get("movementRevision", 1),
	) + 1
	host.ACTION_SUPPORT.consume_valid_request(resident)
	host.bump_world_revision(false)
	host.WORLD_LOG_COMMIT_RUNTIME.append_public(
		host,
		host.world_log_domain.journal.next_world_event_id(),
		"world_event",
		resident_id,
		host.resident_display_name(resident_id),
		previous_place,
		{
			"type": "外出就医",
			"status": "in_progress",
			"participantIds": [resident_id],
			"treatmentPlaceId": EXTERNAL_MEDICAL_AID_PLACE_ID,
			"departedAtMinute": absolute_minute,
			"scheduledReturnMinute": return_minute,
		},
	)
	host.resident_state_changed.emit(host.get_resident_state(resident_id))


static func _cancel_active_clinic_requests(host, resident_id: String) -> void:
	for request_value: Variant in (
		host.get_occupation_service_snapshot().get("requests", []) as Array
	):
		if request_value is not Dictionary:
			continue
		var request := request_value as Dictionary
		if (
			String(request.get("kind", "")) != "clinic"
			or String(request.get("requesterResidentId", "")) != resident_id
			or String(request.get("state", ""))
			not in ["pending", "waiting", "in_progress"]
		):
			continue
		host.OCCUPATION_SERVICE_CANCELLATION_RUNTIME.cancel(
			host,
			request,
			"居民已经离镇接受外部医疗援助",
		)


static func _needs_requirement(active_needs: Array, requirement: String) -> bool:
	for need_value: Variant in active_needs:
		if (
			need_value is Dictionary
			and ((need_value as Dictionary).get(
				"responseRequirements",
				[],
			) as Array).has(requirement)
		):
			return true
	return false
