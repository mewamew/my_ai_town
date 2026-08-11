class_name TownWorldLogCapturePolicy
extends RefCounted

const STORY_POLICY := preload("res://world/runtime/log/TownWorldLogStoryPolicy.gd")
const WORK_POLICY := preload("res://world/runtime/log/TownWorldLogWorkPolicy.gd")
const EXCLUDED_EVENT_TYPES: Array[String] = [
	"移动", "等待", "闲逛", "路过", "进入地点", "离开地点", "有人来了", "有人走了", "旁听",
]
const EXCLUDED_SOURCE_KINDS: Array[String] = ["player_place", "resident_place", "action_result"]


static func should_capture_source(source: Dictionary, payload: Dictionary) -> bool:
	var event_type := _text(
		payload.get("type", payload.get("eventType", source.get("kind", "世界事件")))
	)
	if event_type in EXCLUDED_EVENT_TYPES or _text(source.get("kind", "")) in EXCLUDED_SOURCE_KINDS:
		return false
	match _text(source.get("kind", "")):
		"private_message":
			return not _id(payload, ["messageId", "message_id"]).is_empty()
		"cargo_event":
			return not _id(payload, ["cargoLotId", "cargo_lot_id"]).is_empty()
		"service_result":
			return not _id(payload, ["requestId", "request_id"]).is_empty()
		"conflict_event":
			return not _id(payload, ["conflictId", "conflict_id"]).is_empty()
		"resident_activity":
			return false
		"resident_attendance":
			return not _text(payload.get("summary")).is_empty()
		"work_task":
			return WORK_POLICY.should_capture(source, payload)
		"social_matter":
			return _social_matter(payload)
		"resident_lifecycle":
			var lifecycle_resident_id := _text(source.get("residentId", ""))
			if lifecycle_resident_id.is_empty():
				lifecycle_resident_id = _text(payload.get("residentId", ""))
			return not lifecycle_resident_id.is_empty()
		"animal_event":
			return event_type in ["抚摸动物", "居民抚摸动物"]
		"story_event":
			return STORY_POLICY.should_capture(payload)
		"world_event":
			return _world_event(payload, event_type)
	return false


static func should_capture_record(record: Dictionary) -> bool:
	var refs := record.get("sourceRefs", []) as Array
	var source_kind := ""
	if not refs.is_empty() and refs[0] is Dictionary:
		source_kind = _text((refs[0] as Dictionary).get("sourceKind", ""))
	var payload := record.get("payload", {}) as Dictionary
	return should_capture_source({
		"kind": source_kind,
		"residentId": _text(record.get("residentId", "")),
	}, payload)


static func request_failure_is_meaningful(payload: Dictionary) -> bool:
	return WORK_POLICY.request_failure_is_meaningful(payload)


static func story_root_event_ids(payload: Dictionary) -> Array[String]:
	return STORY_POLICY.story_root_event_ids(payload)


static func _social_matter(payload: Dictionary) -> bool:
	var kind := _text(payload.get("matterKind"))
	if kind == "job_vacancy":
		return _text(payload.get("status")) == "completed" and not (payload.get("resultRefs", []) as Array).is_empty()
	if kind in ["animal_attention", "place_service_pressure"]:
		return _text(payload.get("attentionLevel", "daily")) == "major"
	return true


static func _world_event(payload: Dictionary, event_type: String) -> bool:
	if event_type in ["搭话", "对方答话", "对话结束"]:
		return not _id(payload, ["conversation_id", "conversationId"]).is_empty()
	if event_type in ["天气变了", "公告发布", "公告阅读", "公告转告", "钟声公告", "公告到点", "居民死亡", "公告撤回"]:
		return true
	if event_type == "居民公开反应":
		return not _id(payload, ["announcement_id", "announcementId"]).is_empty()
	if event_type == "营业状态变化":
		return bool(payload.get("playerMeaningful", false))
	return event_type.begins_with("condition_") and _text(payload.get("severity", "minor")) in ["noticeable", "serious"]


static func _id(payload: Dictionary, fields: Array[String]) -> String:
	for field: String in fields:
		var value := _text(payload.get(field))
		if not value.is_empty():
			return value
	return ""


static func _text(value: Variant) -> String:
	return (value as String).strip_edges() if value is String else str(value).strip_edges()
