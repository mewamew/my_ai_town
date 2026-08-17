class_name TownBulletinActivityEffectPlanner
extends RefCounted


const SOCIAL_JUDGMENTS := preload(
	"res://world/runtime/social/TownSocialJudgments.gd"
)


static func plan(
	resident_id: String,
	execution: Dictionary,
	active_assignments: Array[Dictionary],
	fallback_unread_announcement_id: String,
) -> Dictionary:
	if String(execution.get("placeId", "")) != (
		SOCIAL_JUDGMENTS.COMMUNITY_BULLETIN_PLACE_ID
	):
		return {}
	var activity_id := String(execution.get("activityId", ""))
	if activity_id == SOCIAL_JUDGMENTS.BULLETIN_READ_ACTIVITY_ID:
		var assignment := _assignment_for_capability(
			active_assignments,
			"bulletin.read",
		)
		var announcement_id := String(
			((assignment.get("action_goal", {}) as Dictionary).get(
				"target_refs", {},
			) as Dictionary).get("announcement_id", ""),
		).strip_edges()
		if announcement_id.is_empty():
			announcement_id = fallback_unread_announcement_id.strip_edges()
		if announcement_id.is_empty():
			return failure("公告栏当前没有可阅读的新公告")
		return {
			"handled": true,
			"operation": "read",
			"announcementId": announcement_id,
			"successResultId": "bulletin-read:%s:%s"
				% [resident_id, announcement_id],
		}
	if activity_id == SOCIAL_JUDGMENTS.BULLETIN_PUBLISH_ACTIVITY_ID:
		var assignment := _assignment_for_capability(
			active_assignments,
			"bulletin.publish",
		)
		if assignment.is_empty():
			return failure("没有已确认的公告内容，不能空贴公告")
		var target_refs := (
			(assignment.get("action_goal", {}) as Dictionary).get(
				"target_refs", {},
			) as Dictionary
		)
		return {
			"handled": true,
			"operation": "publish",
			"text": String(target_refs.get("text", "")).strip_edges(),
			"matterId": String(target_refs.get(
				"matter_id",
				assignment.get("matter_id", ""),
			)).strip_edges(),
		}
	return {}


static func failure(reason: String) -> Dictionary:
	return {
		"handled": true,
		"ok": false,
		"reason": reason,
	}


static func failure_from_result(
	result: Dictionary,
	fallback_reason: String,
) -> Dictionary:
	var errors := result.get("errors", [fallback_reason]) as Array
	return failure(String(errors[0]) if not errors.is_empty() else fallback_reason)


static func success(result_id: String) -> Dictionary:
	return {
		"handled": true,
		"ok": true,
		"result_id": result_id,
	}


static func _assignment_for_capability(
	assignments: Array[Dictionary],
	capability_id: String,
) -> Dictionary:
	for assignment: Dictionary in assignments:
		if String(
			(assignment.get("action_goal", {}) as Dictionary).get(
				"capability_id", "",
			)
		) == capability_id:
			return assignment
	return {}
