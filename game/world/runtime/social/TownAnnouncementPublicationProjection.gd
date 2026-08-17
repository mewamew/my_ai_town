class_name TownAnnouncementPublicationProjection
extends RefCounted


const TIME_PARSER := preload(
	"res://world/runtime/social/TownAnnouncementTimeParser.gd"
)


static func schedule_context(text: String, absolute_minute: int) -> Dictionary:
	return {
		"schedule": TIME_PARSER.parse(text, absolute_minute) as Dictionary,
		"timeExpressionDetected": TIME_PARSER.has_time_expression(text),
	}


static func published_announcement(result: Dictionary) -> Dictionary:
	return (
		(result.get("value", {}) as Dictionary).get("announcement", {})
		as Dictionary
	).duplicate(true)


static func publish_event_id(
	announcement_id: String,
	announcement: Dictionary,
	public_events: Array[Dictionary],
) -> String:
	var normalized_id := announcement_id.strip_edges()
	if normalized_id.is_empty():
		return ""
	var stored_event_id := String(
		announcement.get("publish_event_id", ""),
	).strip_edges()
	if not stored_event_id.is_empty():
		return stored_event_id
	for reverse_index in public_events.size():
		var record := public_events[public_events.size() - reverse_index - 1]
		if String(record.get("kind", "")) != "world_event":
			continue
		var payload := record.get("payload", {}) as Dictionary
		if (
			String(payload.get("type", "")) == "公告发布"
			and String(payload.get("announcement_id", "")) == normalized_id
		):
			return String(record.get("eventId", ""))
	return ""


static func invalid_publish_failure(result: Dictionary) -> Dictionary:
	if String(result.get("error_code", "")) != "BULLETIN_ANNOUNCEMENT_INVALID":
		return {}
	return {
		"errorCode": "ANNOUNCEMENT_INVALID",
		"errors": [String(result.get("reason", "公告内容无效"))],
	}


static func capability_completion(announcement: Dictionary) -> Dictionary:
	return {
		"payload": {
			"text": String(announcement.get("text", "")),
			"matter_id": String(announcement.get("matter_id", "")),
		},
		"resultId": "bulletin-publish:%s" % String(
			announcement.get("announcement_id", ""),
		),
	}


static func broadcast_failure(result: Dictionary) -> Dictionary:
	return {
		"errorCode": "ANNOUNCEMENT_TRANSACTION_INVARIANT_BROKEN",
		"errors": [String(result.get(
			"reason",
			"合法公告提交后未能完成全体交付",
		))],
	}


static func event_spec(
	announcement: Dictionary,
	publisher_id: String,
	publisher_name: String,
	publisher_priority: String,
	default_time: Dictionary,
) -> Dictionary:
	var matter_id := String(announcement.get("matter_id", ""))
	return {
		"type": "公告发布",
		"announcement_priority": publisher_priority,
		"announcement_id": String(announcement.get("announcement_id", "")),
		"publisher_resident_id": String(
			announcement.get("publisher_id", publisher_id),
		),
		"publisher_name": publisher_name,
		"text": String(announcement.get("text", "")),
		"matter_id": matter_id if not matter_id.is_empty() else null,
		"time": (
			announcement.get("time", default_time) as Dictionary
		).duplicate(true),
		"scheduled_absolute_minute": int(
			announcement.get("scheduled_absolute_minute", -1),
		),
		"scheduled_time_label": String(
			announcement.get("scheduled_time_label", ""),
		),
	}


static func success_result(
	announcement: Dictionary,
	event_id: String,
	broadcast_event_id: String,
	announcement_schedule: Dictionary,
	time_expression_detected: bool,
) -> Dictionary:
	return {
		"ok": true,
		"announcement": announcement,
		"eventId": event_id,
		"broadcastEventId": broadcast_event_id,
		"scheduleRecognized": not announcement_schedule.is_empty(),
		"scheduleWarning": (
			time_expression_detected and announcement_schedule.is_empty()
		),
	}
