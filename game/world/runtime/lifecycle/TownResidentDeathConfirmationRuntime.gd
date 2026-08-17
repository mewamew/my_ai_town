class_name TownResidentDeathConfirmationRuntime
extends RefCounted


const RESIDENT_DEATH_POLICY := preload(
	"res://world/runtime/lifecycle/TownResidentDeathPolicy.gd"
)
const CONVERSATION_RUNTIME := preload(
	"res://world/runtime/conversation/TownConversationRuntime.gd"
)
const ANNOUNCEMENT_COMMAND_RUNTIME := preload(
	"res://world/runtime/social/TownAnnouncementCommandRuntime.gd"
)
const PLACE_SERVICE_COMMAND_RUNTIME := preload(
	"res://world/runtime/work/TownPlaceServiceCommandRuntime.gd"
)

const SYSTEM_BULLETIN_PUBLISHER_ID := "world"


static func confirm(
	host,
	resident_ref: String,
	reason: String,
	expected_lifecycle_revision: int = -1,
	expected_world_instance_token: String = "",
) -> Dictionary:
	var resident_id: String = host._resident_key(resident_ref)
	var prepared := RESIDENT_DEATH_POLICY.prepare_confirmation(
		host._running,
		str(host.get_instance_id()),
		expected_world_instance_token,
		resident_id,
		host.get_resident_lifecycle_state(resident_id),
		expected_lifecycle_revision,
		reason,
	)
	if prepared.get("ok") != true:
		return host._decorate_command_result(prepared)
	if bool(prepared.get("alreadyConfirmed", false)):
		return host._decorate_command_result({
			"ok": true,
			"changed": false,
			"state": prepared.get("state", {}) as Dictionary,
			"event": prepared.get("event", {}) as Dictionary,
		})
	var normalized_reason := String(prepared.get("normalizedReason", ""))
	var event_id: String = host.world_log_domain.journal.next_world_event_id()
	var resident := host.resident_registry.records[resident_id] as Dictionary
	var previous_place := String(resident.get("currentPlace", ""))
	var confirmed := host._resident_lifecycle.confirm_death(
		resident_id,
		normalized_reason,
		event_id,
		host.get_time(),
		RESIDENT_DEATH_POLICY.death_location(resident),
		false,
	) as Dictionary
	if confirmed.get("ok") != true:
		return host._decorate_command_result(confirmed)
	var event := confirmed.get("event", {}) as Dictionary
	host.WORLD_LOG_COMMIT_RUNTIME.append_public(
		host,
		event_id,
		"world_event",
		resident_id,
		host.resident_display_name(resident_id),
		previous_place,
		event,
	)
	var conversation := CONVERSATION_RUNTIME._active_conversation_for_person(
		host,
		resident_id,
	)
	if not conversation.is_empty():
		CONVERSATION_RUNTIME._end_conversation(
			host,
			host._traveler_relationship_state,
			String(conversation.get("conversationId", "")),
			"无法继续",
			"interrupted",
		)
	if not (resident.get("currentAction", {}) as Dictionary).is_empty():
		host.ACTION_SETTLEMENT_RUNTIME.interrupt(host, resident_id, "居民已经死亡，当前行动中止")
	resident["confirmedActionPreview"] = {}
	if host.actor_presentation_state.observed_action_preview_resident_id == resident_id:
		host.actor_presentation_state.observed_action_preview_resident_id = ""
	for matter_id: String in RESIDENT_DEATH_POLICY.release_social_participation(
		host._social_matters,
		resident_id,
		int(host._environment.get_absolute_minute()),
	):
		host.SOCIAL_MATTER_COMMAND_RUNTIME.emit_summary(host, matter_id)
	if host._conflict_controller != null:
		for conflict_id: String in RESIDENT_DEATH_POLICY.active_conflict_ids(
			host.get_public_conflict_projection(),
			resident_id,
		):
			host._conflict_controller.leave_conflict(conflict_id, resident_id, "death")
	for message_id: String in RESIDENT_DEATH_POLICY.pending_private_message_ids(
		host.private_message_runtime,
		resident_id,
	):
		host.PRIVATE_MESSAGE_DELIVERY_RUNTIME.cancel_pending(host,
			message_id,
			"消息的一方已经死亡，投递取消",
		)
	host._work.tasks.release_tasks_for_resident(
		resident_id,
		"原负责人已经死亡，任务等待重新接取",
	)
	RESIDENT_DEATH_POLICY.apply_terminal_resident_state(resident)
	host._agent_wake_preparation_runtime.clear_resident(resident_id)
	host._work.staffing.rebuild(
		host.OCCUPATION_RESIDENT_CONTEXT_RUNTIME.living_residents_for_staffing(host),
		int(host._environment.get_absolute_minute()),
	)
	PLACE_SERVICE_COMMAND_RUNTIME.refresh_staffing(host)
	var death_announcement: Dictionary = ANNOUNCEMENT_COMMAND_RUNTIME.publish(
		host,
		SYSTEM_BULLETIN_PUBLISHER_ID,
		RESIDENT_DEATH_POLICY.announcement_text(event),
		"",
		"board",
	)
	if death_announcement.get("ok") != true:
		push_error(
			"居民死亡公告发布失败：%s"
			% String(death_announcement.get("errorCode", "UNKNOWN"))
		)
	for recipient_id: String in host.resident_registry.order:
		if host._resident_is_alive(recipient_id):
			host._schedule_decision(recipient_id, true)
	host._bump_world_revision(false)
	host.RESIDENT_POSITION_COMMIT_RUNTIME.emit_place_change(host, resident_id, previous_place)
	host.OCCUPATION_RESIDENT_CONTEXT_RUNTIME.sync_staffing_matters(host)
	host._notify_world_revision()
	host._emit_resident_state_changed(resident_id)
	return host._decorate_command_result({
		"ok": true,
		"changed": true,
		"state": host.get_resident_lifecycle_state(resident_id),
		"event": event.duplicate(true),
	})
