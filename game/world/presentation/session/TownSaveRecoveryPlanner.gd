class_name TownSaveRecoveryPlanner
extends RefCounted


const INSPECTION_VERSION := 1
const PLAN_VERSION := 1
const REPUBLISH_ACTION := "restore_complete_pair_and_publish"
const EXPORT_ACTION := "export_save_diagnostic"


static func plan_id(
	slot_id: String,
	source_revision: int,
	damaged_revision: int,
) -> String:
	return "%s:%d:%d" % [slot_id, source_revision, damaged_revision]


static func inspection_report(slot: Dictionary) -> Dictionary:
	var recovery_state := String(slot.get("recoveryState", "none"))
	var classification := recovery_state
	if String(slot.get("state", "")) == "healthy":
		classification = "healthy"
	elif String(slot.get("state", "")) == "empty":
		classification = "empty"
	var report := {
		"version": INSPECTION_VERSION,
		"slotId": String(slot.get("slotId", "")),
		"classification": classification,
		"errorCode": String(slot.get("errorCode", "")),
		"latestEvidenceRevision": int(
			slot.get("latestEvidenceRevision", -1),
		),
		"latestCompleteRevision": int(
			slot.get("latestCompleteRevision", -1),
		),
		"repairable": recovery_state == "older_complete_revision_available",
	}
	report["diagnosticId"] = _diagnostic_id(report)
	return report


static func recovery_plan(
	slot: Dictionary,
	report: Dictionary,
) -> Dictionary:
	var reconciliation := slot.get("reconciliationPlan", {}) as Dictionary
	if not reconciliation.is_empty():
		return reconciliation.duplicate(true)
	if (
		String(report.get("classification", ""))
		!= "older_complete_revision_available"
		or not bool(report.get("repairable", false))
	):
		if String(report.get("classification", "")) in [
			"healthy",
			"empty",
			"version_not_supported",
		]:
			return {}
		return {
			"version": PLAN_VERSION,
			"planId": String(report.get("diagnosticId", "")),
			"diagnosticId": String(report.get("diagnosticId", "")),
			"action": EXPORT_ACTION,
			"slotId": String(report.get("slotId", "")),
			"repairable": false,
			"confirmationRequired": false,
			"items": [{
				"classification": String(report.get("classification", "")),
				"errorCode": String(report.get("errorCode", "")),
				"latestEvidenceRevision": int(
					report.get("latestEvidenceRevision", -1),
				),
			}],
		}
	var summary := slot.get("summary", {}) as Dictionary
	var damage := slot.get("damageDetails", {}) as Dictionary
	var slot_id := String(slot.get("slotId", ""))
	var source_session_id := String(summary.get("sessionId", ""))
	var source_revision := int(summary.get("saveRevision", -1))
	var damaged_revision := int(damage.get("damagedSaveRevision", -1))
	if (
		slot_id.is_empty()
		or source_session_id.is_empty()
		or source_revision < 1
		or damaged_revision <= source_revision
	):
		return {}
	return {
		"version": PLAN_VERSION,
		"planId": plan_id(slot_id, source_revision, damaged_revision),
		"action": REPUBLISH_ACTION,
		"slotId": slot_id,
		"sourceSessionId": source_session_id,
		"sourceSaveRevision": source_revision,
		"damagedSaveRevision": damaged_revision,
		"damageCode": String(damage.get("damageCode", "")),
		"progressRollback": bool(damage.get("progressRollback", false)),
		"confirmationRequired": true,
	}


static func _diagnostic_id(report: Dictionary) -> String:
	return "SAVE-%s" % JSON.stringify({
		"slotId": String(report.get("slotId", "")),
		"classification": String(report.get("classification", "")),
		"errorCode": String(report.get("errorCode", "")),
		"latestEvidenceRevision": int(report.get("latestEvidenceRevision", -1)),
		"latestCompleteRevision": int(report.get("latestCompleteRevision", -1)),
	}).sha256_text().left(16).to_upper()
