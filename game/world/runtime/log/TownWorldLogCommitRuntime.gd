class_name TownWorldLogCommitRuntime
extends RefCounted


const DOMAIN_LOG_PROJECTION := preload(
	"res://world/runtime/log/TownWorldDomainLogProjection.gd"
)
const STORY_EVENT_PROJECTION := preload(
	"res://world/runtime/log/TownStoryEventProjection.gd"
)


static func work_task_committed(host, task: Dictionary) -> void:
	if not host._running:
		return
	var assigned_resident_id := String(
		task.get("assignedResidentId", ""),
	).strip_edges()
	append_domain(host, DOMAIN_LOG_PROJECTION.work_task_event(
		task,
		host.resident_display_name(assigned_resident_id),
	))


static func append_cargo(
	host,
	event_type: String,
	lot: Dictionary,
	actor_resident_id: String,
	status: String,
) -> void:
	var carrier_resident_id := String(lot.get("carrierResidentId", ""))
	append_domain(host, DOMAIN_LOG_PROJECTION.cargo_event(
		event_type,
		lot,
		actor_resident_id,
		host.resident_display_name(actor_resident_id),
		host.resident_display_name(carrier_resident_id),
		status,
	))


static func append_service(
	host,
	request: Dictionary,
	task: Dictionary,
	worker_resident_id: String,
	outcome: Dictionary,
) -> void:
	var request_id := String(request.get("requestId", "")).strip_edges()
	var requester_id := String(request.get("requesterResidentId", "")).strip_edges()
	var completed_request := host._work.services.request(request_id) as Dictionary
	append_domain(host, DOMAIN_LOG_PROJECTION.service_event(
		request,
		task,
		worker_resident_id,
		host.resident_display_name(worker_resident_id),
		host.resident_display_name(requester_id),
		String(completed_request.get("state", "completed")),
		outcome,
	))


static func append_private_message(
	host,
	event_type: String,
	message: Dictionary,
	status: String,
	delivered_by_resident_id := "",
) -> void:
	var sender_id := String(message.get("senderResidentId", ""))
	var recipient_id := String(message.get("recipientResidentId", ""))
	append_domain(host, DOMAIN_LOG_PROJECTION.private_message_event(
		event_type,
		message,
		status,
		delivered_by_resident_id,
		host.resident_display_name(sender_id),
		host.resident_display_name(recipient_id),
		host.resident_display_name(delivered_by_resident_id),
	))


static func append_animal(
	host,
	event_type: String,
	fact: Dictionary,
	actor_resident_id := "",
	actor_name := "",
) -> void:
	append_domain(host, DOMAIN_LOG_PROJECTION.animal_event(
		event_type,
		fact,
		actor_resident_id,
		actor_name,
	))


static func record_player_animal_pet(host, animal_id: String) -> Dictionary:
	var normalized := animal_id.strip_edges()
	var fact: Dictionary = host._animal_fact_runtime.fact(normalized)
	if normalized.is_empty() or fact.is_empty() or not bool(fact.get("exists", false)):
		return host._command_failure(
			"ANIMAL_FACT_UNKNOWN",
			["只能记录当前确实存在的动物互动"],
		)
	append_animal(host, "抚摸动物", fact, "", "玩家")
	return host._decorate_command_result({
		"ok": true,
		"changed": true,
		"status": "recorded",
		"animalId": normalized,
	})


static func record_story_action_started(
	host,
	resident_id: String,
	action: Dictionary,
	provenance: Dictionary,
) -> void:
	var event := STORY_EVENT_PROJECTION.action_started(
		resident_id,
		host.resident_display_name(resident_id),
		String((host.resident_registry.records[resident_id] as Dictionary).get("currentPlace", "")),
		action,
		provenance,
		host.ACTION_PROJECTION_MODULE.default_doing(host, action),
	) as Dictionary
	if event.is_empty():
		return
	var public_story_event_id := append_story_spec(host, event)
	var action_id := String(event.get("actionId", ""))
	var context := (event.get("context", {}) as Dictionary).duplicate(true)
	context["sourceEventIds"] = [public_story_event_id]
	host.world_log_domain.journal.set_action_story_context(action_id, context)


static func record_story_action_outcome(
	host,
	resident_id: String,
	action_id: String,
	status: String,
	reason: String,
) -> void:
	var context: Dictionary = host.world_log_domain.journal.action_story_context(
		action_id,
	)
	var event := STORY_EVENT_PROJECTION.action_outcome(
		resident_id,
		host.resident_display_name(resident_id),
		String((host.resident_registry.records[resident_id] as Dictionary).get("currentPlace", "")),
		action_id,
		status,
		reason,
		context,
	) as Dictionary
	if not event.is_empty():
		append_story_spec(host, event)


static func append_story_spec(host, event: Dictionary) -> String:
	return append_story(
		host,
		String(event.get("storyEventId", "")),
		String(event.get("storyType", "")),
		String(event.get("residentId", "")),
		String(event.get("placeName", "")),
		event.get("payload", {}) as Dictionary,
	)


static func append_domain(host, event: Dictionary) -> void:
	if event.is_empty():
		return
	var event_id := String(event.get("eventId", ""))
	append_event(
		host,
		event_id if not event_id.is_empty() else host.world_log_domain.journal.next_world_event_id(),
		String(event.get("kind", "")),
		String(event.get("residentId", "")),
		String(event.get("residentName", "")),
		String(event.get("placeName", "")),
		event.get("payload", {}) as Dictionary,
	)


static func append_public(
	host,
	event_id: String,
	kind: String,
	resident_id: String,
	resident_name: String,
	place_name: String,
	payload: Dictionary,
) -> void:
	var appended := host.world_log_domain.journal.append_public_event(
		event_id,
		kind,
		host.get_time(),
		host._world_revision,
		resident_id,
		resident_name,
		place_name,
		payload,
	) as Dictionary
	if appended.get("changed") == true:
		append_source(host, appended.get("record", {}) as Dictionary)


static func append_event(
	host,
	event_id: String,
	kind: String,
	resident_id: String,
	resident_name: String,
	place_name: String,
	payload: Dictionary,
) -> void:
	var normalized_id := event_id.strip_edges()
	var normalized_kind := kind.strip_edges()
	if normalized_id.is_empty() or normalized_kind.is_empty():
		return
	append_source(host, {
		"eventId": normalized_id,
		"kind": normalized_kind,
		"time": host.get_time(),
		"worldRevision": host._world_revision,
		"residentId": resident_id.strip_edges(),
		"residentName": resident_name.strip_edges(),
		"placeName": place_name.strip_edges(),
		"payload": payload.duplicate(true),
	})


static func append_source(host, source: Dictionary) -> void:
	if not host.world_log_domain.capture_enabled:
		return
	if not host.world_log_domain.store.should_capture_public_event(source):
		return
	var world_log_record := source.duplicate(true)
	var payload := world_log_record.get("payload", {}) as Dictionary
	world_log_record["payload"] = DOMAIN_LOG_PROJECTION.payload_with_participant_snapshots(
		payload,
		String(world_log_record.get("residentId", "")),
		String(world_log_record.get("residentName", "")),
		host.resident_registry.name_by_id,
		host.player_avatar_id(),
		String(host.actor_presentation_state.player_avatar.get("name", "")),
	)
	var result := host.world_log_domain.store.append_public_event(world_log_record) as Dictionary
	if result.get("ok") != true:
		host.world_log_domain.journal.set_consistency_error(String(
			result.get("errorCode", "WORLD_LOG_RECORD_INVALID"),
		))
		return
	if result.get("changed") != true:
		return
	host.world_log_changed.emit({
		"sourceEventId": String(world_log_record.get("eventId", "")),
		"sourceKind": String(world_log_record.get("kind", "")),
		"appended": int(result.get("appended", 0)),
		"latestSequence": int(result.get("latestSequence", 0)),
	})


static func append_story(
	host,
	event_id: String,
	story_type: String,
	resident_id: String,
	place_name: String,
	payload: Dictionary,
) -> String:
	var appended := host.world_log_domain.journal.append_story_event(
		event_id,
		story_type,
		host.get_time(),
		host._world_revision,
		resident_id,
		host.resident_display_name(resident_id),
		place_name,
		payload,
	) as Dictionary
	if appended.get("changed") == true:
		append_source(host, appended.get("record", {}) as Dictionary)
		host.story_event_created.emit(
			appended.get("emittedRecord", {}) as Dictionary,
		)
	return String(appended.get("eventId", ""))
