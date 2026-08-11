class_name TownAnnouncementResidentRuntime
extends RefCounted

const ACTION_VALIDATION := preload(
	"res://world/runtime/action/TownActionValidation.gd"
)
const SYSTEM_BULLETIN_PUBLISHER_ID := "world"


static func priority_for_publisher(
	host: TownWorldRuntime,
	publisher_id: String,
) -> String:
	return (
		"player"
		if publisher_id.strip_edges() == host._player_avatar_id()
		else "ordinary"
	)


static func has_player_priority(events: Array) -> bool:
	for value: Variant in events:
		if value is not Dictionary:
			continue
		var event := value as Dictionary
		if (
			String(event.get("type", "")) in ["公告发布", "公告到点"]
			and String(event.get("announcement_priority", "")) == "player"
		):
			return true
	return false


static func player_priority_handling_error(
	decision: Dictionary,
	events: Array,
) -> Dictionary:
	if (
		String(decision.get("handling", "")) != "continue_current"
		or not has_player_priority(events)
	):
		return {}
	return {
		"ok": false,
		"stale": false,
		"consumed": false,
		"errorCode": "PLAYER_ANNOUNCEMENT_ACTION_REQUIRED",
		"retryable": true,
		"errors": ["玩家公告必须停止普通工作并提交新的实际行动"],
	}


static func schedule_player_priority_decision(
	host: TownWorldRuntime,
	resident_id: String,
	event: Dictionary,
) -> bool:
	if not has_player_priority([event]):
		return false
	# 直接对话由对话合同负责轮流答话；公告先留在事件队列，不能把
	# 对话中的居民唤醒成一轮普通公告决定，否则会留下未结束的对话。
	if resident_in_active_conversation(host, resident_id):
		return false
	# 玩家公告可替换普通工作；对话和受伤后的强制回应仍由决定合同优先。
	host._schedule_decision(resident_id, true, false, true, false, true)
	return true


static func resident_in_active_conversation(
	host: TownWorldRuntime,
	resident_id: String,
) -> bool:
	for conversation: Dictionary in host.get_active_conversations():
		if (conversation.get("participants", []) as Array).has(resident_id):
			return true
	return false


static func emit_reactions(
	host: TownWorldRuntime,
	resident_id: String,
	decision_id: String,
	reaction: Dictionary,
	announcement_reactions: Array,
	inflight_events: Array,
	inflight_results: Array,
) -> void:
	var resolved_reaction := reaction.duplicate(true)
	if resolved_reaction.is_empty():
		resolved_reaction = _required_reaction(inflight_results)
	if not resolved_reaction.is_empty():
		var payload := {
			"reactionId": "%s::reaction" % decision_id,
			"decisionId": decision_id,
			"sourceActionId": String(
				resolved_reaction.get("source_action_id", ""),
			).strip_edges(),
			"sourceEventId": "",
			"residentId": resident_id,
			"text": String(resolved_reaction.get("text", "")).strip_edges(),
			"time": host.get_time(),
			"worldRevision": host._world_revision,
			"reactionKind": "action_result",
		}
		host.emit_signal(
			"resident_reaction_created",
			host._resident_display_name(resident_id),
			payload.duplicate(true),
		)
	_emit_announcement_reactions(
		host,
		resident_id,
		decision_id,
		announcement_reactions,
		inflight_events,
	)


static func known_announcements(
	host: TownWorldRuntime,
	bulletin: TownCommunityBulletinRuntime,
	resident_id: String,
	maximum: int,
) -> Array[Dictionary]:
	var records := {}
	for value: Variant in bulletin.knowledge_for(resident_id) as Array:
		var record := value as Dictionary
		records[String(record.get("announcement_id", ""))] = record
	var result: Array[Dictionary] = []
	for announcement: Dictionary in bulletin.get_announcements(true) as Array[Dictionary]:
		var announcement_id := String(announcement.get("announcement_id", ""))
		if not records.has(announcement_id):
			continue
		var record := records.get(announcement_id, {}) as Dictionary
		result.append({
			"announcement_id": announcement_id,
			"text": String(announcement.get("text", "")),
			"publisher_resident_id": String(announcement.get("publisher_id", "")),
			"publisher_name": publisher_name(
				host,
				String(announcement.get("publisher_id", "")),
			),
			"acquired_via": String(record.get("acquired_via", "")),
			"active": bool(announcement.get("active", false)),
			"scheduled_absolute_minute": int(
				announcement.get("scheduled_absolute_minute", -1),
			),
			"scheduled_time_label": String(
				announcement.get("scheduled_time_label", ""),
			),
			"schedule_triggered": announcement.has("schedule_triggered_at"),
		})
	if result.size() > maximum:
		return result.slice(result.size() - maximum) as Array[Dictionary]
	return result


static func publisher_name(host: TownWorldRuntime, publisher_id: String) -> String:
	var normalized := publisher_id.strip_edges()
	if normalized == host._player_avatar_id():
		return String(
			host._player_avatar.get("name", "旅行者"),
		).strip_edges()
	if host._residents.has(normalized):
		return host._resident_display_name(normalized)
	return (
		"小镇"
		if normalized == SYSTEM_BULLETIN_PUBLISHER_ID
		else normalized
	)


static func advance_schedules(
	host: TownWorldRuntime,
	bulletin: TownCommunityBulletinRuntime,
	absolute_minute: int,
) -> void:
	for announcement: Dictionary in bulletin.due_scheduled_announcements(
		absolute_minute,
	) as Array[Dictionary]:
		var announcement_id := String(
			announcement.get("announcement_id", ""),
		).strip_edges()
		if announcement_id.is_empty():
			continue
		var marked := bulletin.mark_schedule_triggered(
			announcement_id,
			absolute_minute,
		) as Dictionary
		if marked.get("ok") != true:
			continue
		var publisher_id := String(
			announcement.get("publisher_id", ""),
		).strip_edges()
		var due_event := host._materialize_world_event({
			"type": "公告到点",
			"announcement_priority": priority_for_publisher(host, publisher_id),
			"announcement_id": announcement_id,
			"publisher_resident_id": publisher_id,
			"publisher_name": publisher_name(host, publisher_id),
			"text": String(announcement.get("text", "")),
			"matter_id": announcement.get("matter_id", null),
			"scheduled_absolute_minute": int(
				announcement.get("scheduled_absolute_minute", absolute_minute),
			),
			"scheduled_time_label": String(
				announcement.get("scheduled_time_label", ""),
			),
			"status": "due",
		}) as Dictionary
		for resident_value: Variant in host._resident_order:
			var resident_id := String(resident_value)
			if (
				resident_id == publisher_id
				or not host._residents.has(resident_id)
				or not host._resident_is_alive(resident_id)
			):
				continue
			host._enqueue_world_event(resident_id, due_event)


static func _emit_announcement_reactions(
	host: TownWorldRuntime,
	resident_id: String,
	decision_id: String,
	provided_reactions: Array,
	inflight_events: Array,
) -> void:
	var provided_by_event: Dictionary = {}
	for value: Variant in provided_reactions:
		if value is Dictionary:
			var event_id := String(
				(value as Dictionary).get("source_event_id", ""),
			).strip_edges()
			if not event_id.is_empty():
				provided_by_event[event_id] = (value as Dictionary).duplicate(true)
	for value: Variant in inflight_events:
		if value is not Dictionary:
			continue
		var event := value as Dictionary
		if String(event.get("type", "")) not in ["公告发布", "公告到点"]:
			continue
		var source_event_id := String(event.get("event_id", "")).strip_edges()
		var announcement_id := String(
			event.get("announcement_id", ""),
		).strip_edges()
		if source_event_id.is_empty() or announcement_id.is_empty():
			continue
		var resolved := provided_by_event.get(source_event_id, {}) as Dictionary
		var text := String(resolved.get("text", "")).strip_edges()
		var used_fallback := text.is_empty()
		if used_fallback:
			text = (
				"时间到了，我再看看该怎么做。"
				if String(event.get("type", "")) == "公告到点"
				else "这条公告我听见了。"
			)
		_emit_announcement_reaction(
			host,
			resident_id,
			decision_id,
			event,
			source_event_id,
			announcement_id,
			text,
			used_fallback,
		)


static func _emit_announcement_reaction(
	host: TownWorldRuntime,
	resident_id: String,
	decision_id: String,
	event: Dictionary,
	source_event_id: String,
	announcement_id: String,
	text: String,
	used_fallback: bool,
) -> void:
	var reaction_id := "%s::announcement::%s" % [decision_id, source_event_id]
	var phase := "due" if String(event.get("type", "")) == "公告到点" else "received"
	var payload := {
		"reactionId": reaction_id,
		"decisionId": decision_id,
		"sourceActionId": "",
		"sourceEventId": source_event_id,
		"announcementId": announcement_id,
		"residentId": resident_id,
		"text": text,
		"time": host.get_time(),
		"worldRevision": host._world_revision,
		"reactionKind": "announcement",
		"announcementPhase": phase,
		"fallback": used_fallback,
	}
	var resident_name := host._resident_display_name(resident_id)
	var resident := host._residents.get(
		resident_id,
		{},
	) as Dictionary
	host._append_world_log_event(
		reaction_id,
		"world_event",
		resident_id,
		resident_name,
		String(resident.get("currentPlace", "")),
		{
			"type": "居民公开反应",
			"announcement_id": announcement_id,
			"sourceEventId": source_event_id,
			"decisionId": decision_id,
			"residentId": resident_id,
			"text": text,
			"status": "completed",
			"phase": phase,
			"fallback": used_fallback,
		},
	)
	host.emit_signal(
		"resident_reaction_created",
		resident_name,
		payload.duplicate(true),
	)


static func _required_reaction(results: Array) -> Dictionary:
	var source_action_id := ACTION_VALIDATION.reaction_source_action_id(results)
	if source_action_id.is_empty():
		return {}
	for index in range(results.size() - 1, -1, -1):
		var value: Variant = results[index]
		if value is not Dictionary:
			continue
		var result := value as Dictionary
		if String(result.get("action_id", "")).strip_edges() != source_action_id:
			continue
		var text := {
			"completed": "这件事总算做完了。",
			"interrupted": "刚才被打断了。",
			"rejected": "这次没能办成。",
			"failed": "这次没能办成。",
		}.get(String(result.get("status", "")), "") as String
		return {} if text.is_empty() else {
			"source_action_id": source_action_id,
			"text": text,
		}
	return {}
