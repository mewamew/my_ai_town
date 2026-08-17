class_name TownStaffingAssignmentPolicy
extends RefCounted


const ASSIGNMENT_KINDS := ["transfer", "part_time", "shift", "trial"]


static func target(action_goal: Dictionary) -> Dictionary:
	var target_refs := action_goal.get("target_refs", {}) as Dictionary
	return {
		"refs": target_refs,
		"occupationId": String(target_refs.get("occupation_id", "")),
		"assignmentKind": String(target_refs.get("assignment_kind", "")),
		"fromOccupationId": String(target_refs.get("from_occupation_id", "")),
	}


static func failure_reason(
	target: Dictionary,
	current_occupation_id: String,
	target_post: Dictionary,
	target_occupation: Dictionary,
	allowed_modes: Array,
) -> String:
	var assignment_kind := String(target.get("assignmentKind", ""))
	if (
		assignment_kind not in ASSIGNMENT_KINDS
		or target_post.is_empty()
		or target_occupation.is_empty()
	):
		return "岗位调整目标无效"
	if assignment_kind not in allowed_modes:
		return "居民当前没有以这种方式接手该岗位的资格"
	var assigned_resident_ids := target_post.get("assignedResidentIds", []) as Array
	if assignment_kind == "transfer" and not assigned_resident_ids.is_empty():
		return "岗位已经有正式负责人"
	if assignment_kind != "transfer" and not assigned_resident_ids.is_empty():
		return "岗位已有正式负责人，本次空缺协商已经失效"
	var from_occupation_id := String(target.get("fromOccupationId", ""))
	if (
		not from_occupation_id.is_empty()
		and from_occupation_id != current_occupation_id
	):
		return "居民职业已经发生变化，本次申请失效"
	return ""


static func assignment(matter_id: String, action_goal: Dictionary) -> Dictionary:
	return {"matter_id": matter_id, "action_goal": action_goal}


static func rejection_result(
	matter_id: String,
	resident_id: String,
	reason: String,
) -> Dictionary:
	return {
		"result_id": "staffing-rejected:%s:%s" % [matter_id, resident_id],
		"reason": reason,
	}


static func arrangement_result(
	arrangement: Dictionary,
	occupation_id: String,
	assignment_kind: String,
) -> Dictionary:
	return {
		"result_id": "staffing-arrangement:%s" % String(
			arrangement.get("arrangementId", ""),
		),
		"occupation_id": occupation_id,
		"assignment_kind": assignment_kind,
		"covers_post": bool(arrangement.get("coversPost", false)),
	}


static func transfer_social_state(
	social_state: Dictionary,
	target_occupation: Dictionary,
) -> Dictionary:
	var updated := social_state.duplicate(true)
	updated["job"] = String(target_occupation.get("label", ""))
	updated["workplace"] = String(
		target_occupation.get("primaryWorkplacePlace", ""),
	)
	return updated


static func transfer_result(
	matter_id: String,
	resident_id: String,
	occupation_id: String,
	assignment_kind: String,
) -> Dictionary:
	return {
		"result_id": "staffing-transfer:%s:%s:%s" % [
			matter_id,
			resident_id,
			occupation_id,
		],
		"occupation_id": occupation_id,
		"assignment_kind": assignment_kind,
	}
