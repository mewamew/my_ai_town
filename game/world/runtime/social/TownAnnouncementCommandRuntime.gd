class_name TownAnnouncementCommandRuntime
extends RefCounted


const PUBLICATION_PROJECTION := preload(
	"res://world/runtime/social/TownAnnouncementPublicationProjection.gd"
)
const RESIDENT_RUNTIME := preload(
	"res://world/runtime/social/TownAnnouncementResidentRuntime.gd"
)
const RESIDENT_MESSAGE_CONTENT := preload(
	"res://world/runtime/social/TownResidentMessageContent.gd"
)
const SOCIAL_GOAL_MATCHING_RUNTIME := preload(
	"res://world/runtime/social/TownSocialGoalMatchingRuntime.gd"
)


static func publish_resident(
	host,
	resident_ref: String,
	text: String,
	matter_id := "",
	delivery_mode := "",
) -> Dictionary:
	var resident_id: String = host._resident_key(resident_ref)
	if resident_id.is_empty():
		return host._command_failure(
			"WORLD_RESIDENT_UNKNOWN",
			["未知居民：%s" % resident_ref],
		)
	var resolved_delivery_mode := delivery_mode.strip_edges()
	if resolved_delivery_mode.is_empty():
		resolved_delivery_mode = (
			resident_delivery_mode(host, matter_id)
			if (
				not matter_id.strip_edges().is_empty()
				and host.OCCUPATION_RESIDENT_CONTEXT_RUNTIME.primary_id(host,
					host.resident_registry.records.get(resident_id, {}) as Dictionary,
				) == "occupation_town_manager"
			)
			else "board"
		)
	return publish(host, resident_id, text, matter_id, resolved_delivery_mode)


static func unread_count(host, resident_ref: String) -> int:
	var resident_id: String = host._resident_key(resident_ref)
	if resident_id.is_empty():
		return 0
	return int(host._community_bulletin.unread_count(resident_id))


static func knowledge_for(host, resident_ref: String) -> Array[Dictionary]:
	var resident_id: String = host._resident_key(resident_ref)
	if resident_id.is_empty():
		return []
	return host._community_bulletin.knowledge_for(
		resident_id,
	) as Array[Dictionary]


static func announcement_publish_event_id(host, announcement_id: String) -> String:
	return PUBLICATION_PROJECTION.publish_event_id(
		announcement_id,
		host._community_bulletin.get_announcement(announcement_id),
		host.world_log_domain.journal.public_events(),
	)


static func publish(
	host,
	publisher_id: String,
	text: String,
	matter_id: String,
	delivery_mode: String,
) -> Dictionary:
	if not host._running:
		return host._command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	var social_snapshot := host._social_matters.create_save_snapshot() as Dictionary
	var bulletin_snapshot := host._community_bulletin.create_save_snapshot() as Dictionary
	var event_sequence_before: int = host.world_log_domain.journal.event_sequence()
	var announcement_event_id: String = host.world_log_domain.journal.next_world_event_id()
	var schedule_context := PUBLICATION_PROJECTION.schedule_context(
		text,
		int(host._environment.get_absolute_minute()),
	) as Dictionary
	var announcement_schedule := schedule_context.get("schedule", {}) as Dictionary
	var time_expression_detected := bool(
		schedule_context.get("timeExpressionDetected", false),
	)
	var result := host._community_bulletin.publish(
		publisher_id,
		text,
		matter_id,
		int(host._environment.get_absolute_minute()),
		host.get_time(),
		delivery_mode,
		announcement_event_id,
		announcement_schedule,
	) as Dictionary
	if result.get("ok") != true:
		host.world_log_domain.journal.set_event_sequence(event_sequence_before)
		var invalid_failure := PUBLICATION_PROJECTION.invalid_publish_failure(
			result,
		)
		if not invalid_failure.is_empty():
			return host._command_failure(
				String(invalid_failure.get("errorCode", "")),
				invalid_failure.get("errors", []) as Array,
			)
		return host.SOCIAL_MATTER_COMMAND_RUNTIME.command_result(
			host, result, "ANNOUNCEMENT_INVALID",
		)
	var announcement := PUBLICATION_PROJECTION.published_announcement(result)
	var broadcast_result := record_broadcast_knowledge(
		host,
		announcement,
	) as Dictionary
	if broadcast_result.get("ok") != true:
		host.world_log_domain.journal.set_event_sequence(event_sequence_before)
		host._social_matters.restore_save_snapshot(social_snapshot)
		host._community_bulletin.restore_save_snapshot(bulletin_snapshot)
		var broadcast_failure := PUBLICATION_PROJECTION.broadcast_failure(
			broadcast_result,
		)
		return host._command_failure(
			String(broadcast_failure.get("errorCode", "")),
			broadcast_failure.get("errors", []) as Array,
		)
	var event_publisher_id := String(
		announcement.get("publisher_id", publisher_id),
	)
	var announcement_event: Dictionary = host.WORLD_EVENT_DELIVERY_RUNTIME.materialize(host,
		PUBLICATION_PROJECTION.event_spec(
			announcement,
			publisher_id,
			RESIDENT_RUNTIME.publisher_name(host, event_publisher_id),
			RESIDENT_RUNTIME.priority_for_publisher(host, publisher_id),
			host.get_time(),
		),
		announcement_event_id,
	)
	for resident_value: Variant in broadcast_result.get(
		"reaction_resident_ids",
		[],
	) as Array:
		host.WORLD_EVENT_DELIVERY_RUNTIME.enqueue(host, String(resident_value), announcement_event)
	var broadcast_event_id := ""
	match String(announcement.get("delivery_mode", "board")):
		"town_bell":
			broadcast_event_id = deliver_town_bell(
				host,
				announcement,
				String(announcement_event.get("event_id", "")),
			)
		"postal_notice":
			queue_postal_notices(host, announcement)
	host._bump_world_revision(false)
	if host.resident_registry.records.has(publisher_id):
		var capability_completion := PUBLICATION_PROJECTION.capability_completion(
			announcement,
		)
		SOCIAL_GOAL_MATCHING_RUNTIME.complete_direct_capability(
			host,
			publisher_id,
			"bulletin.publish",
			capability_completion.get("payload", {}) as Dictionary,
			String(capability_completion.get("resultId", "")),
		)
	host.announcement_published.emit(announcement.duplicate(true))
	host._notify_world_revision()
	return host._decorate_command_result(
		PUBLICATION_PROJECTION.success_result(
			announcement,
			String(announcement_event.get("event_id", "")),
			broadcast_event_id,
			announcement_schedule,
			time_expression_detected,
		),
	)


static func read(
	host,
	resident_ref: String,
	announcement_id: String,
) -> Dictionary:
	if not host._running:
		return host._command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	var resident_id: String = host._resident_key(resident_ref)
	if resident_id.is_empty():
		return host._command_failure(
			"WORLD_RESIDENT_UNKNOWN",
			["未知居民：%s" % resident_ref],
		)
	var result := host._community_bulletin.read_announcement(
		resident_id,
		announcement_id,
		int(host._environment.get_absolute_minute()),
	) as Dictionary
	if result.get("ok") != true:
		return host.SOCIAL_MATTER_COMMAND_RUNTIME.command_result(host, result)
	var value := result.get("value", {}) as Dictionary
	var event := value.get("event", {}) as Dictionary
	if not event.is_empty():
		var publish_event_id: String = announcement_publish_event_id(
			host,
			announcement_id,
		)
		if not publish_event_id.is_empty():
			event["causedByEventIds"] = [publish_event_id]
			event["storyRootEventIds"] = [publish_event_id]
		host._bump_world_revision(false)
		host.WORLD_EVENT_DELIVERY_RUNTIME.queue(host, resident_id, event)
	SOCIAL_GOAL_MATCHING_RUNTIME.complete_direct_capability(
		host,
		resident_id,
		"bulletin.read",
		{"announcement_id": announcement_id},
		"bulletin-read:%s:%s" % [resident_id, announcement_id],
	)
	host._notify_world_revision()
	return host._decorate_command_result({
		"ok": true,
		"newKnowledge": bool(value.get("new_knowledge", false)),
		"announcement": (
			value.get("announcement", {}) as Dictionary
		).duplicate(true),
	})


static func relay(
	host,
	speaker_ref: String,
	listener_ref: String,
	announcement_id: String,
) -> Dictionary:
	if not host._running:
		return host._command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	var speaker_id: String = host._resident_key(speaker_ref)
	var listener_id: String = host._resident_key(listener_ref)
	if speaker_id.is_empty() or listener_id.is_empty():
		return host._command_failure(
			"WORLD_RESIDENT_UNKNOWN",
			["公告转告者或接收者不是当前居民"],
		)
	var result := host._community_bulletin.relay_announcement(
		speaker_id,
		listener_id,
		announcement_id,
		int(host._environment.get_absolute_minute()),
	) as Dictionary
	if result.get("ok") != true:
		return host.SOCIAL_MATTER_COMMAND_RUNTIME.command_result(host, result)
	var value := result.get("value", {}) as Dictionary
	if bool(value.get("new_knowledge", false)):
		var announcement := value.get("announcement", {}) as Dictionary
		var publish_event_id: String = announcement_publish_event_id(
			host,
			announcement_id,
		)
		var relay_event := {
			"type": "公告转告",
			"announcement_id": announcement_id,
			"speaker_resident_id": speaker_id,
			"text": String(announcement.get("text", "")),
			"matter_id": _optional_matter_id(announcement),
		}
		if not publish_event_id.is_empty():
			relay_event["causedByEventIds"] = [publish_event_id]
			relay_event["storyRootEventIds"] = [publish_event_id]
		host._bump_world_revision(false)
		host.WORLD_EVENT_DELIVERY_RUNTIME.queue(host, listener_id, relay_event)
		host._notify_world_revision()
	return host._decorate_command_result({
		"ok": true,
		"newKnowledge": bool(value.get("new_knowledge", false)),
		"announcement": (
			value.get("announcement", {}) as Dictionary
		).duplicate(true),
	})


static func withdraw(host, announcement_id: String) -> Dictionary:
	if not host._running:
		return host._command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	var result := host._community_bulletin.withdraw_announcement(
		announcement_id,
		int(host._environment.get_absolute_minute()),
	) as Dictionary
	if result.get("ok") != true:
		return host.SOCIAL_MATTER_COMMAND_RUNTIME.command_result(host, result)
	var announcement := (
		result.get("value", {}) as Dictionary
	).duplicate(true)
	host._bump_world_revision(false)
	host._notify_world_revision()
	return host._decorate_command_result({
		"ok": true,
		"announcement": announcement,
	})


static func resident_delivery_mode(host, matter_id: String) -> String:
	var matter := host._social_matters.get_matter(matter_id) as Dictionary
	return (
		"town_bell"
		if String(matter.get("attention_level", "daily")) == "major"
		else "postal_notice"
	)


static func record_broadcast_knowledge(
	host,
	announcement: Dictionary,
) -> Dictionary:
	var announcement_id := String(
		announcement.get("announcement_id", ""),
	).strip_edges()
	var absolute_minute := int(host._environment.get_absolute_minute())
	var resident_ids: Array[String] = []
	var reaction_resident_ids: Array[String] = []
	var publisher_id := String(
		announcement.get("publisher_id", ""),
	).strip_edges()
	for resident_id: String in host.resident_registry.order:
		if not host.resident_registry.records.has(resident_id):
			continue
		var received := host._community_bulletin.receive_directly(
			resident_id,
			announcement_id,
			"announcement_broadcast",
			announcement_id,
			absolute_minute,
		) as Dictionary
		if received.get("ok") != true:
			return {
				"ok": false,
				"reason": String(received.get(
					"reason",
					"居民公告知情登记失败",
				)),
			}
		resident_ids.append(resident_id)
		if resident_id != publisher_id and host._resident_is_alive(resident_id):
			reaction_resident_ids.append(resident_id)
	return {
		"ok": true,
		"resident_ids": resident_ids,
		"reaction_resident_ids": reaction_resident_ids,
	}


static func deliver_town_bell(
	host,
	announcement: Dictionary,
	publish_event_id: String,
) -> String:
	var caused_by: Array[String] = (
		[publish_event_id] as Array[String]
		if not publish_event_id.is_empty()
		else [] as Array[String]
	)
	var bell_event: Dictionary = host.WORLD_EVENT_DELIVERY_RUNTIME.materialize(host, {
		"type": "钟声公告",
		"announcement_id": String(announcement.get("announcement_id", "")),
		"publisher_resident_id": String(announcement.get("publisher_id", "")),
		"text": String(announcement.get("text", "")),
		"matter_id": _optional_matter_id(announcement),
		"delivery_mode": "town_bell",
		"causedByEventIds": caused_by,
		"storyRootEventIds": caused_by,
	})
	return String(bell_event.get("event_id", ""))


static func queue_postal_notices(host, announcement: Dictionary) -> void:
	var publisher_id := String(announcement.get("publisher_id", ""))
	var announcement_id := String(
		announcement.get("announcement_id", ""),
	).strip_edges()
	var matter_id := String(announcement.get("matter_id", ""))
	var matter := host._social_matters.get_matter(matter_id) as Dictionary
	if publisher_id.is_empty() or announcement_id.is_empty() or matter.is_empty():
		return
	for recipient_id: String in _matter_recipient_ids(matter):
		if (
			recipient_id == publisher_id
			or not host.resident_registry.records.has(recipient_id)
			or resident_knows(host._community_bulletin, recipient_id, announcement_id)
		):
			continue
		var message_payload := RESIDENT_MESSAGE_CONTENT.announcement_notice(
			publisher_id,
			recipient_id,
			String(announcement.get("text", "")),
			announcement_id,
			-1,
		)
		host.create_private_message(
			publisher_id,
			recipient_id,
			String(message_payload.get("content", "")),
			"announcement_notice",
			announcement_id,
			int(message_payload.get("expiresAtMinute", -1)),
			String(message_payload.get("sourceRef", "")),
		)


static func apply_delivered_notice(
	host,
	message_id: String,
	message: Dictionary,
	postal_resident_id: String,
	recipient_id: String,
	delivered_at: int,
) -> void:
	if String(message.get("messageKind", "private")) != "announcement_notice":
		return
	var announcement_id := String(
		message.get("announcementId", ""),
	).strip_edges()
	var announcement := host._community_bulletin.get_announcement(
		announcement_id,
	) as Dictionary
	if (
		announcement.is_empty()
		or String(announcement.get("delivery_mode", "board")) != "postal_notice"
	):
		return
	host._community_bulletin.receive_directly(
		postal_resident_id,
		announcement_id,
		"postal_notice",
		message_id,
		delivered_at,
	)
	var received := host._community_bulletin.receive_directly(
		recipient_id,
		announcement_id,
		"postal_notice",
		message_id,
		delivered_at,
	) as Dictionary
	if received.get("ok") != true:
		return
	host.WORLD_EVENT_DELIVERY_RUNTIME.queue(host, recipient_id, {
		"type": "正式通知送达",
		"announcement_id": announcement_id,
		"speaker_resident_id": postal_resident_id,
		"message_id": message_id,
		"text": String(announcement.get("text", "")),
		"matter_id": _optional_matter_id(announcement),
	})


static func resident_knows(
	bulletin,
	resident_id: String,
	announcement_id: String,
) -> bool:
	for value: Variant in bulletin.knowledge_for(resident_id) as Array:
		if String((value as Dictionary).get("announcement_id", "")) == announcement_id:
			return true
	return false


static func _matter_recipient_ids(matter: Dictionary) -> Array[String]:
	var recipients := {}
	for resident_value: Variant in matter.get("subject_ids", []) as Array:
		recipients[String(resident_value)] = true
	var creator_id := String(matter.get("creator_id", ""))
	if not creator_id.is_empty():
		recipients[creator_id] = true
	for candidate_value: Variant in matter.get("fixed_candidates", []) as Array:
		if candidate_value is Dictionary:
			recipients[String(
				(candidate_value as Dictionary).get("resident_id", ""),
			)] = true
	for participant_value: Variant in matter.get("participants", {}) as Dictionary:
		recipients[String(participant_value)] = true
	var result: Array[String] = []
	for recipient_value: Variant in recipients:
		var recipient_id := String(recipient_value)
		if not recipient_id.is_empty():
			result.append(recipient_id)
	return result


static func _optional_matter_id(announcement: Dictionary) -> Variant:
	var matter_id := String(announcement.get("matter_id", ""))
	return matter_id if not matter_id.is_empty() else null
