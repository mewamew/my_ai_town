class_name TownStaffingAssignmentCommit
extends RefCounted


const ASSIGNMENT_POLICY := preload(
	"res://world/runtime/work/TownStaffingAssignmentPolicy.gd"
)


static func create_arrangement(
	staffing: TownStaffingRuntime,
	residents: Dictionary,
	resident_id: String,
	target: Dictionary,
	absolute_minute: int,
) -> Dictionary:
	var refs := target.get("refs", {}) as Dictionary
	var result := staffing.create_arrangement(
		resident_id,
		String(target.get("occupationId", "")),
		String(target.get("assignmentKind", "")),
		absolute_minute,
		int(refs.get("shift_start_minute", 0)),
		int(refs.get("shift_end_minute", 1440)),
	) as Dictionary
	if result.get("ok") == true:
		staffing.rebuild(residents, absolute_minute)
	return result


static func transfer(
	staffing: TownStaffingRuntime,
	residents: Dictionary,
	resident: Dictionary,
	target: Dictionary,
	target_occupation: Dictionary,
	absolute_minute: int,
) -> void:
	staffing.end_active_arrangements_for_occupation(
		String(target.get("occupationId", "")),
		absolute_minute,
		"岗位已有正式负责人",
	)
	resident["socialState"] = ASSIGNMENT_POLICY.transfer_social_state(
		resident.get("socialState", {}) as Dictionary,
		target_occupation,
	)
	staffing.rebuild(residents, absolute_minute)
