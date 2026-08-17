class_name TownPeriodicServiceRequestRuntime
extends RefCounted


const CONTENT_CATALOG := preload(
	"res://world/data/town/TownWorkContentCatalog.gd"
)
const RESIDENT_MESSAGE_POLICY := preload(
	"res://world/runtime/social/TownResidentMessagePolicy.gd"
)
const RESIDENT_MESSAGE_CONTENT := preload(
	"res://world/runtime/social/TownResidentMessageContent.gd"
)


static func due_library_return_loans(
	absolute_minute: int,
	occupation_services: TownOccupationServiceRuntime,
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for loan_value: Variant in occupation_services.borrowed_loans_due_by(
		absolute_minute,
	):
		var loan := loan_value as Dictionary
		if occupation_services.has_active_request(
			"library_return",
			String(loan.get("loanId", "")),
		):
			continue
		result.append(loan.duplicate(true))
	return result


static func notify_library_return(
	world: Object,
	loan: Dictionary,
	message_created_at: int,
	distribution_token: String,
) -> void:
	var loan_id := String(loan.get("loanId", ""))
	var borrower_id := String(loan.get("borrowerResidentId", ""))
	var librarian_id := RESIDENT_MESSAGE_POLICY.sender_for_source(
		world,
		"occupation_librarian",
		"library-return:%s" % loan_id,
		borrower_id,
		distribution_token,
	)
	if librarian_id.is_empty():
		return
	RESIDENT_MESSAGE_POLICY.send(
		world,
		RESIDENT_MESSAGE_CONTENT.library_due(
			librarian_id,
			borrower_id,
			loan_id,
			message_created_at + 1440,
		),
	)


static func clinic_follow_up_request_spec(follow_up: Dictionary) -> Dictionary:
	return {
		"kind": "clinic",
		"requesterResidentId": String(
			follow_up.get("patientResidentId", ""),
		),
		"subjectRef": "%s（复诊）" % String(
			follow_up.get("complaint", "身体不适"),
		),
		"context": {
			"generatedFromFollowUp": true,
			"followUpId": String(follow_up.get("followUpId", "")),
			"originalRequestId": String(
				follow_up.get("originalRequestId", ""),
			),
		},
	}


static func notify_clinic_follow_up(
	world: Object,
	follow_up: Dictionary,
	message_created_at: int,
	distribution_token: String,
	patient_display_name: String,
) -> Dictionary:
	var follow_up_id := String(follow_up.get("followUpId", ""))
	var patient_id := String(follow_up.get("patientResidentId", ""))
	var practitioner_id := RESIDENT_MESSAGE_POLICY.sender_for_source(
		world,
		"occupation_clinic_practitioner",
		"clinic-follow-up:%s" % follow_up_id,
		patient_id,
		distribution_token,
	)
	if practitioner_id.is_empty():
		return {}
	RESIDENT_MESSAGE_POLICY.send(
		world,
		RESIDENT_MESSAGE_CONTENT.clinic_follow_up(
			practitioner_id,
			patient_id,
			String(follow_up.get("complaint", "身体不适")),
			follow_up_id,
			message_created_at + 360,
		),
	)
	return {
		"request_id": "clinic-return:%s" % follow_up_id,
		"source_revision": 1,
		"requester_id": practitioner_id,
		"submitted": true,
		"active": true,
		"reason_summary": "诊所请%s按时回来复诊" % patient_display_name,
		"subject_ids": [practitioner_id, patient_id],
		"place_id": CONTENT_CATALOG.PLACE_CLINIC,
		"capability_id": "world.go_to_place",
		"target_refs": {"place_id": CONTENT_CATALOG.PLACE_CLINIC},
		"success_result_id": "clinic-follow-up-arrived",
		"expires_at": message_created_at + 360,
		"capacity": 1,
		"source_event_ids": [follow_up_id],
	}
