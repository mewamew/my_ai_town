class_name TownWorldEventJournalRuntime
extends RefCounted


const MAX_PUBLIC_EVENTS := 200


var _public_events: Array[Dictionary] = []
var _event_sequence := 0
var _consistency_error := ""
var _action_story_contexts: Dictionary = {}
var _conversation_story_contexts: Dictionary = {}


func reset() -> void:
	_public_events.clear()
	_event_sequence = 0
	_consistency_error = ""
	_action_story_contexts.clear()
	_conversation_story_contexts.clear()


func public_events() -> Array[Dictionary]:
	return _public_events.duplicate(true)


func external_public_events() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record: Dictionary in _public_events:
		var copy := record.duplicate(true)
		copy["payload"] = sanitize_public_payload(
			copy.get("payload", {}) as Dictionary,
		)
		result.append(copy)
	return result


func restore_public_events(values: Array) -> void:
	_public_events.clear()
	for value: Variant in values:
		if value is Dictionary:
			_public_events.append((value as Dictionary).duplicate(true))


func append_public_event(
	event_id: String,
	kind: String,
	time: Dictionary,
	world_revision: int,
	resident_id: String,
	resident_name: String,
	place_name: String,
	payload: Dictionary,
) -> Dictionary:
	var normalized_id := event_id.strip_edges()
	var normalized_kind := kind.strip_edges()
	if normalized_id.is_empty() or normalized_kind.is_empty():
		return {"ok": false, "changed": false}
	for existing: Dictionary in _public_events:
		if String(existing.get("eventId", "")) == normalized_id:
			return {"ok": true, "changed": false}
	var normalized_resident_id := resident_id.strip_edges()
	var normalized_resident_name := resident_name.strip_edges()
	if normalized_resident_id.is_empty():
		normalized_resident_name = ""
	var record := {
		"eventId": normalized_id,
		"kind": normalized_kind,
		"time": time.duplicate(true),
		"worldRevision": world_revision,
		"residentId": normalized_resident_id,
		"residentName": normalized_resident_name,
		"placeName": place_name.strip_edges(),
		"payload": payload.duplicate(true),
	}
	_public_events.append(record)
	if _public_events.size() > MAX_PUBLIC_EVENTS:
		_public_events.pop_front()
	return {"ok": true, "changed": true, "record": record.duplicate(true)}


func append_story_event(
	story_event_id: String,
	story_type: String,
	time: Dictionary,
	world_revision: int,
	resident_id: String,
	resident_name: String,
	place_name: String,
	payload: Dictionary,
) -> Dictionary:
	var existing_event_id := public_story_event_record_id(story_event_id)
	if not existing_event_id.is_empty():
		return {"ok": true, "changed": false, "eventId": existing_event_id}
	var story_payload := payload.duplicate(true)
	story_payload["storyEventId"] = story_event_id
	story_payload["storyType"] = story_type
	story_payload["time"] = time.duplicate(true)
	story_payload["worldRevision"] = world_revision
	var public_event_id := next_world_event_id()
	var appended := append_public_event(
		public_event_id,
		"story_event",
		time,
		world_revision,
		resident_id,
		resident_name,
		place_name,
		story_payload,
	) as Dictionary
	var record := appended.get("record", {}) as Dictionary
	var emitted_record := record.duplicate(true)
	emitted_record["payload"] = sanitize_public_payload(story_payload)
	return {
		"ok": true,
		"changed": bool(appended.get("changed", false)),
		"eventId": public_event_id,
		"record": record,
		"emittedRecord": emitted_record,
	}


func event_sequence() -> int:
	return _event_sequence


func set_event_sequence(value: int) -> void:
	_event_sequence = maxi(value, 0)


func next_world_event_id() -> String:
	_event_sequence += 1
	return "world-event-%d" % _event_sequence


func next_sequence() -> int:
	_event_sequence += 1
	return _event_sequence


func consistency_error() -> String:
	return _consistency_error


func clear_consistency_error() -> void:
	_consistency_error = ""


func set_consistency_error(value: String) -> void:
	_consistency_error = value.strip_edges()


func story_root_ids_for_world_event(event_id: String) -> Array:
	if event_id.is_empty():
		return []
	for reverse_index in _public_events.size():
		var index := _public_events.size() - reverse_index - 1
		var record := _public_events[index] as Dictionary
		if String(record.get("eventId", "")) != event_id:
			continue
		return (
			(record.get("payload", {}) as Dictionary).get(
				"storyRootEventIds",
				[],
			) as Array
		).duplicate(true)
	return []


func decision_story_provenance(
	events: Array,
	action_results: Array,
) -> Dictionary:
	var source_event_ids: Array[String] = []
	var root_event_ids: Array[String] = []
	for event_value: Variant in events:
		if not event_value is Dictionary:
			continue
		var event := event_value as Dictionary
		if String(event.get("type", "")) not in [
			"公告发布",
			"公告阅读",
			"公告转告",
			"天气变了",
			"搭话",
			"对方答话",
			"对话结束",
		]:
			continue
		_append_unique_ids(source_event_ids, [event.get("event_id", "")])
		var event_id := String(event.get("event_id", ""))
		var inherited_roots := story_root_ids_for_world_event(event_id)
		_append_unique_ids(
			root_event_ids,
			[event_id] if inherited_roots.is_empty() else inherited_roots,
		)
	for result_value: Variant in action_results:
		if not result_value is Dictionary:
			continue
		var context := action_story_context(String(
			(result_value as Dictionary).get("action_id", ""),
		))
		_append_unique_ids(
			source_event_ids,
			context.get("sourceEventIds", []) as Array,
		)
		_append_unique_ids(
			root_event_ids,
			context.get("rootEventIds", []) as Array,
		)
	return {
		"sourceEventIds": source_event_ids,
		"rootEventIds": root_event_ids,
	}


func action_story_context(action_id: String) -> Dictionary:
	if action_id.is_empty() or not _action_story_contexts.has(action_id):
		return {}
	return (_action_story_contexts[action_id] as Dictionary).duplicate(true)


func set_action_story_context(action_id: String, context: Dictionary) -> void:
	if not action_id.is_empty():
		_action_story_contexts[action_id] = context.duplicate(true)


func conversation_story_context(conversation_id: String) -> Dictionary:
	if conversation_id.is_empty():
		return {}
	return (
		_conversation_story_contexts.get(conversation_id, {}) as Dictionary
	).duplicate(true)


func set_conversation_story_context(
	conversation_id: String,
	context: Dictionary,
) -> void:
	if not conversation_id.is_empty():
		_conversation_story_contexts[conversation_id] = context.duplicate(true)


func erase_conversation_story_context(conversation_id: String) -> void:
	_conversation_story_contexts.erase(conversation_id)


func public_story_event_record_id(story_event_id: String) -> String:
	var normalized_id := story_event_id.strip_edges()
	if normalized_id.is_empty():
		return ""
	for record: Dictionary in _public_events:
		if String(record.get("kind", "")) != "story_event":
			continue
		var payload := record.get("payload", {}) as Dictionary
		if String(payload.get("storyEventId", "")) == normalized_id:
			return String(record.get("eventId", ""))
	return ""


func rebuild_story_contexts() -> void:
	_action_story_contexts.clear()
	_conversation_story_contexts.clear()
	for record: Dictionary in _public_events:
		var payload := record.get("payload", {}) as Dictionary
		if String(record.get("kind", "")) == "story_event":
			var story_type := String(payload.get("storyType", ""))
			if story_type == "gathering_arrival":
				var arrival_action_id := String(payload.get("actionId", ""))
				if (
					not arrival_action_id.is_empty()
					and _action_story_contexts.has(arrival_action_id)
				):
					var arrival_context := (
						_action_story_contexts[arrival_action_id] as Dictionary
					).duplicate(true)
					arrival_context["sourceEventIds"] = [
						String(record.get("eventId", "")),
					]
					_action_story_contexts[arrival_action_id] = arrival_context
				continue
			if story_type != "action_started":
				continue
			var action_id := String(payload.get("actionId", ""))
			if action_id.is_empty():
				continue
			_action_story_contexts[action_id] = {
				"sourceEventIds": [String(record.get("eventId", ""))],
				"rootEventIds": (
					payload.get("storyRootEventIds", []) as Array
				).duplicate(true),
				"directCauseEventIds": (
					payload.get("causedByEventIds", []) as Array
				).duplicate(true),
				"actionType": String(payload.get("actionType", "")),
				"line": String(payload.get("line", "")),
				"prop": String(payload.get("prop", "")),
				"verb": String(payload.get("verb", "")),
				"place": String(payload.get("place", "")),
				"residentId": String(record.get("residentId", "")),
			}
			continue
		if String(record.get("kind", "")) != "world_event":
			continue
		var conversation_id := String(payload.get("conversation_id", ""))
		if conversation_id.is_empty():
			continue
		_conversation_story_contexts[conversation_id] = {
			"rootEventIds": (
				payload.get("storyRootEventIds", []) as Array
			).duplicate(true),
			"lastEventId": String(payload.get("event_id", "")),
		}


static func _append_unique_ids(target: Array[String], values: Array) -> void:
	for value: Variant in values:
		var normalized := String(value).strip_edges()
		if not normalized.is_empty() and not target.has(normalized):
			target.append(normalized)


static func sanitize_public_payload(payload: Dictionary) -> Dictionary:
	var sanitized := payload.duplicate(true)
	sanitized.erase("storyEventId")
	sanitized.erase("storyType")
	sanitized.erase("storyRootEventIds")
	return sanitized
