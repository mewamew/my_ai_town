class_name TownWorldEventDeliveryRuntime
extends RefCounted


const PROJECTION := preload(
	"res://world/runtime/event/TownWorldEventDeliveryProjection.gd"
)
const RESIDENT_EVENT_QUEUE_RUNTIME := preload(
	"res://world/runtime/event/TownResidentEventQueueRuntime.gd"
)
const ACTION_VALIDATION := preload(
	"res://world/runtime/action/TownActionValidation.gd"
)
const CONFLICT_KNOWLEDGE_PROJECTOR := preload(
	"res://world/runtime/conflict/TownConflictKnowledgeProjector.gd"
)
const CONVERSATION_RUNTIME := preload(
	"res://world/runtime/conversation/TownConversationRuntime.gd"
)
const AGENT_WAKE_STATE_RUNTIME := preload(
	"res://world/runtime/TownAgentWakeStateRuntime.gd"
)
const ANNOUNCEMENT_RESIDENT_RUNTIME := preload(
	"res://world/runtime/social/TownAnnouncementResidentRuntime.gd"
)


static func broadcast(host, source: Dictionary) -> void:
	var event := materialize(host, source)
	for resident_id: String in host.resident_registry.order:
		var resident := host.resident_registry.records[resident_id] as Dictionary
		if not host.resident_is_present(resident):
			continue
		enqueue(
			host,
			resident_id,
			event,
			PROJECTION.should_schedule_broadcast(
				event,
				String(resident.get("spaceId", "")),
			),
		)


static func queue(
	host,
	resident_id: String,
	source: Dictionary,
) -> Dictionary:
	return enqueue(host, resident_id, materialize(host, source))


static func queue_for_person(
	host,
	person_id: String,
	source: Dictionary,
) -> Dictionary:
	if not host.resident_registry.records.has(person_id):
		return {}
	return queue(host, person_id, source)


static func materialize(
	host,
	source: Dictionary,
	reserved_event_id: String = "",
) -> Dictionary:
	var event_id: String = (
		reserved_event_id
		if not reserved_event_id.is_empty()
		else host.world_log_domain.journal.next_world_event_id()
	)
	var event := PROJECTION.materialized_event(
		source,
		event_id,
		host.get_time(),
	) as Dictionary
	host.WORLD_LOG_COMMIT_RUNTIME.append_public(
		host,
		String(event["event_id"]),
		"world_event",
		"",
		"",
		String(event.get("placeName", event.get("place_name", ""))),
		event,
	)
	return event


static func enqueue(
	host,
	resident_id: String,
	event: Dictionary,
	schedule_event: bool = true,
) -> Dictionary:
	var resident := host.resident_registry.records[resident_id] as Dictionary
	ACTION_VALIDATION.clear_rejected_action_streak(resident)
	if CONFLICT_KNOWLEDGE_PROJECTOR.is_injury_subject(event, resident_id):
		host.ACTION_SETTLEMENT_RUNTIME.interrupt(host, resident_id, "刚刚遭遇冲突，当前行动中止")
		var active_conversation := CONVERSATION_RUNTIME._active_conversation_for_person(
			host,
			resident_id,
		)
		if not active_conversation.is_empty():
			CONVERSATION_RUNTIME._end_conversation(
				host,
				host._traveler_relationship_state,
				String(active_conversation.get("conversationId", "")),
				"一方离开",
				"interrupted",
			)
	var delivery := PROJECTION.delivery_views(event, resident_id) as Dictionary
	var identified_event := delivery.get("identifiedEvent", {}) as Dictionary
	var agent_event := delivery.get("agentEvent", {}) as Dictionary
	RESIDENT_EVENT_QUEUE_RUNTIME.append_pending_world_event(resident, agent_event)
	if bool(resident.get("decisionPending", false)):
		AGENT_WAKE_STATE_RUNTIME.mark_dirty(resident)
	host.world_event_created.emit(
		host.resident_display_name(resident_id),
		identified_event,
	)
	if not schedule_event:
		return identified_event
	if ANNOUNCEMENT_RESIDENT_RUNTIME.schedule_player_priority_decision(
		host,
		resident_id,
		event,
	):
		return identified_event
	var wake := PROJECTION.wake_policy(event, host.URGENT_EVENT_TYPES) as Dictionary
	host._schedule_decision(
		resident_id,
		bool(wake.get("invalidate", false)),
		false,
		bool(wake.get("allowCurrentActivityInterrupt", false)),
		false,
		bool(wake.get("wakeWhileCurrentAction", false)),
	)
	return identified_event
