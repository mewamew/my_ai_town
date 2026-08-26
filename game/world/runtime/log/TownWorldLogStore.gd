class_name TownWorldLogStore
extends RefCounted


const RESULT_SHAPES := preload(
	"res://world/contract/TownWorldResultShapes.gd"
)
const CAPTURE_POLICY := preload(
	"res://world/runtime/log/TownWorldLogCapturePolicy.gd"
)
const STORY_POLICY := preload(
	"res://world/runtime/log/TownWorldLogStoryPolicy.gd"
)
const PRESENTATION := preload(
	"res://world/runtime/log/TownWorldLogPresentation.gd"
)
const SCHEMA := "town-world-log-snapshot"
const SCHEMA_VERSION := 1
const DEFAULT_TIMELINE_ID := "world-log-timeline-1"
# 会写入 session manifest 的 timelineId 必须保持在安全标识符边界内。
# 恢复分支仍保留完整 parentTimelineId 作为证据，但子时间线不能无限拼接
# `-branch-数字`，否则多次恢复后会让 manifest 无法发布。
const MAX_TIMELINE_ID_LENGTH := 128
# 聚集线程判定为"热闹"的最小到场人数(与表现层影子引擎 isHot 阈值一致)。
const GATHERING_HOT_PARTICIPANT_COUNT := 3

var _timeline_id := DEFAULT_TIMELINE_ID
var _parent_timeline_id := ""
var _sequence := 0
var _records: Array[Dictionary] = []
var _threads: Dictionary = {}
var _read_through: Dictionary = {}
var _log_item_ids: Dictionary = {}
# threadId -> 该线程的记录列表（与 _records 共享同一批字典引用），
# 未读投影不再对全量记录做 O(threads×records) 扫描。
var _records_by_thread: Dictionary = {}


func reset(timeline_id := DEFAULT_TIMELINE_ID) -> Dictionary:
	var normalized := String(timeline_id).strip_edges()
	if normalized.is_empty():
		normalized = DEFAULT_TIMELINE_ID
	_timeline_id = normalized
	_parent_timeline_id = ""
	_sequence = 0
	_records.clear()
	_threads.clear()
	_read_through.clear()
	_log_item_ids.clear()
	_records_by_thread.clear()
	return _success()


func append_public_event(source: Dictionary) -> Dictionary:
	var event_id := String(source.get("eventId", "")).strip_edges()
	if event_id.is_empty():
		return _failure("WORLD_LOG_SOURCE_ID_MISSING")
	var payload_value: Variant = source.get("payload", {})
	var payload := (
		(payload_value as Dictionary).duplicate(true)
		if payload_value is Dictionary
		else {}
	)
	var event_type := String(
		payload.get(
			"type",
			payload.get("eventType", source.get("kind", "世界事件")),
		),
	).strip_edges()
	if not CAPTURE_POLICY.should_capture_source(source, payload):
		return _excluded()
	var reference := _root_reference(source, payload)
	var thread_id := "%s:%s" % [
		String(reference.get("kind", "event")),
		String(reference.get("id", event_id)),
	]
	var participant_ids := _participant_ids(source, payload)
	var participant_snapshots := _participant_snapshots(
		source,
		payload,
		participant_ids,
	)
	var time := _time_value(source.get("time", payload.get("time", {})))
	var place_id := String(
		source.get(
			"placeName",
			payload.get("placeId", payload.get("place_name", "")),
		),
	).strip_edges()
	var record := {
		"schemaVersion": SCHEMA_VERSION,
		"timelineId": _timeline_id,
		"threadId": thread_id,
		"logItemId": "public_event:%s:%s" % [
			String(source.get("kind", "world_event")),
			event_id,
		],
		"sourceRefs": [{
			"sourceKind": String(source.get("kind", "world_event")),
			"sourceId": event_id,
			"mutationId": event_id,
		}],
		"kind": _record_kind(source, payload, reference),
		"kindTag": _thread_kind(source, payload, reference),
		"worldRevision": int(source.get("worldRevision", 0)),
		"residentId": String(source.get("residentId", "")).strip_edges(),
		"residentName": String(source.get("residentName", "")).strip_edges(),
		"time": time,
		"participantIds": participant_ids,
		"participantSnapshots": participant_snapshots,
		"placeId": place_id,
		"placeSnapshot": {
			"placeId": place_id,
			"displayName": place_id,
		},
		"title": _title(source, payload, event_type),
		"text": _text(payload),
		"status": _record_status(source, payload),
		"attention": _attention(source, payload),
		"references": _references(source, payload, reference),
		"payload": _sanitize_payload_for_log(payload),
		"attachmentRefs": _attachment_refs(payload),
	}
	return append_batch([record])


func should_capture_public_event(source: Dictionary) -> bool:
	var payload_value: Variant = source.get("payload", {})
	var payload := payload_value as Dictionary if payload_value is Dictionary else {}
	return CAPTURE_POLICY.should_capture_source(source, payload)


func append_batch(values: Array) -> Dictionary:
	var pending: Array[Dictionary] = []
	var pending_ids: Dictionary = {}
	for value: Variant in values:
		if not value is Dictionary:
			return _failure("WORLD_LOG_RECORD_INVALID")
		var record := (value as Dictionary).duplicate(true)
		var validation := _validate_record(record)
		if validation.get("ok") != true:
			return validation
		var log_item_id := String(record.get("logItemId", ""))
		if _log_item_ids.has(log_item_id):
			continue
		if pending_ids.has(log_item_id):
			return _failure("WORLD_LOG_DUPLICATE_BATCH_ITEM")
		pending_ids[log_item_id] = true
		pending.append(record)
	if pending.is_empty():
		return {
			"ok": true,
			"errorCode": "",
			"retryable": false,
			"changed": false,
			"appended": 0,
		}
	for record: Dictionary in pending:
		_sequence += 1
		record["sequence"] = _sequence
		record["recordId"] = "%s:world-log-%d" % [
			_timeline_id,
			_sequence,
		]
		record["timelineId"] = _timeline_id
		_records.append(record)
		_index_record_by_thread(record)
		_log_item_ids[String(record.get("logItemId", ""))] = true
		_apply_record_to_thread(record)
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"changed": true,
		"appended": pending.size(),
		"latestSequence": _sequence,
	}


func query_threads(filters: Dictionary = {}) -> Dictionary:
	var cursor_value: Variant = filters.get("cursor", {})
	if not cursor_value is Dictionary:
		return _failure("WORLD_LOG_CURSOR_INVALID")
	var cursor := cursor_value as Dictionary
	var upper_bound := _sequence
	var after_sequence := -1
	var after_thread_id := ""
	if not cursor.is_empty():
		if (
			String(cursor.get("timelineId", "")) != _timeline_id
			or typeof(cursor.get("upperBoundSequence")) != TYPE_INT
			or typeof(cursor.get("afterLatestSequence")) != TYPE_INT
			or not cursor.get("afterThreadId", "") is String
		):
			return _failure("WORLD_LOG_CURSOR_INVALID")
		upper_bound = int(cursor.get("upperBoundSequence", -1))
		after_sequence = int(cursor.get("afterLatestSequence", -1))
		after_thread_id = String(cursor.get("afterThreadId", ""))
		if (
			upper_bound < 0
			or upper_bound > _sequence
			or after_sequence < 0
			or after_sequence > upper_bound
			or after_thread_id.is_empty()
		):
			return _failure("WORLD_LOG_CURSOR_INVALID")
	var rows: Array[Dictionary] = []
	var resident_id := String(filters.get("residentId", "")).strip_edges()
	var kind_tag := String(filters.get("kindTag", "")).strip_edges()
	var place_id := String(filters.get("placeId", "")).strip_edges()
	var day := int(filters.get("day", 0))
	var unread_only := bool(filters.get("unreadOnly", false))
	var source_threads := _threads_at_sequence(upper_bound)
	for value: Variant in source_threads.values():
		var thread := value as Dictionary
		if (
			not resident_id.is_empty()
			and not (thread.get("participantIds", []) as Array).has(resident_id)
		):
			continue
		if (
			not kind_tag.is_empty()
			and not (thread.get("kindTags", []) as Array).has(kind_tag)
		):
			continue
		if (
			not place_id.is_empty()
			and not (thread.get("placeIds", []) as Array).has(place_id)
		):
			continue
		if day > 0 and not (thread.get("days", []) as Array).has(day):
			continue
		var projected := _project_thread_read_state(thread, upper_bound)
		if unread_only and not bool(projected.get("unread", false)):
			continue
		rows.append(projected)
	rows.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_sequence := int(left.get("latestSequence", 0))
		var right_sequence := int(right.get("latestSequence", 0))
		if left_sequence != right_sequence:
			return left_sequence > right_sequence
		return String(left.get("threadId", "")) > String(right.get("threadId", ""))
	)
	var total := rows.size()
	if after_sequence >= 0:
		var remaining: Array[Dictionary] = []
		for row: Dictionary in rows:
			var row_sequence := int(row.get("latestSequence", 0))
			var row_thread_id := String(row.get("threadId", ""))
			if (
				row_sequence < after_sequence
				or (
					row_sequence == after_sequence
					and row_thread_id < after_thread_id
				)
			):
				remaining.append(row)
		rows = remaining
	var limit := clampi(int(filters.get("limit", 50)), 1, 200)
	var offset := (
		0
		if not cursor.is_empty()
		else maxi(0, int(filters.get("offset", 0)))
	)
	var page: Array[Dictionary] = []
	for index in range(offset, mini(rows.size(), offset + limit)):
		page.append(rows[index].duplicate(true))
	var has_more := offset + page.size() < rows.size()
	var next_cursor: Dictionary = {}
	if has_more and not page.is_empty():
		var last := page[-1] as Dictionary
		next_cursor = {
			"timelineId": _timeline_id,
			"upperBoundSequence": upper_bound,
			"afterLatestSequence": int(last.get("latestSequence", 0)),
			"afterThreadId": String(last.get("threadId", "")),
		}
	var sanitized_rows: Array[Dictionary] = []
	for row: Dictionary in page:
		sanitized_rows.append(_sanitize_record_output(row))
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"rows": sanitized_rows,
		"total": total,
		"hasMore": has_more,
		"nextOffset": offset + page.size(),
		"nextCursor": next_cursor,
		"timelineId": _timeline_id,
		"upperBoundSequence": upper_bound,
	}


func get_thread_detail(
	thread_id: String,
	options: Dictionary = {},
) -> Dictionary:
	var normalized := thread_id.strip_edges()
	var timeline_id := String(options.get("timelineId", _timeline_id))
	var upper_bound := int(options.get("upperBoundSequence", _sequence))
	if (
		timeline_id != _timeline_id
		or upper_bound < 0
		or upper_bound > _sequence
	):
		return _failure("WORLD_LOG_CURSOR_INVALID")
	var source_threads := _threads_at_sequence(upper_bound)
	if normalized.is_empty() or not source_threads.has(normalized):
		return _failure("WORLD_LOG_THREAD_NOT_FOUND")
	var after_sequence := maxi(0, int(options.get("afterSequence", 0)))
	var limit := clampi(int(options.get("limit", 100)), 1, 500)
	var result: Array[Dictionary] = []
	var has_more := false
	for record: Dictionary in _records:
		if (
			String(record.get("threadId", "")) != normalized
			or int(record.get("sequence", 0)) <= after_sequence
			or int(record.get("sequence", 0)) > upper_bound
		):
			continue
		if result.size() >= limit:
			has_more = true
			break
		result.append(record.duplicate(true))
	var sanitized_records: Array[Dictionary] = []
	for record_value: Variant in result:
		if not record_value is Dictionary:
			continue
		sanitized_records.append(_sanitize_record_output(record_value as Dictionary))
	var thread := _sanitize_record_output(
		_project_thread_read_state(
			source_threads[normalized] as Dictionary,
			upper_bound,
		),
	)
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"thread": thread,
		"records": sanitized_records,
		"hasMore": has_more,
		"nextSequence": (
			int(result[-1].get("sequence", after_sequence))
			if not result.is_empty()
			else after_sequence
		),
		"timelineId": _timeline_id,
		"upperBoundSequence": upper_bound,
	}


func mark_thread_read(thread_id: String, displayed_through_sequence: int) -> Dictionary:
	var normalized := thread_id.strip_edges()
	if normalized.is_empty() or not _threads.has(normalized):
		return _failure("WORLD_LOG_THREAD_NOT_FOUND")
	var thread := _threads[normalized] as Dictionary
	var latest := int(thread.get("latestSequence", 0))
	var next_value := clampi(displayed_through_sequence, 0, latest)
	var current := int(_read_through.get(normalized, 0))
	if next_value <= current:
		return _success(false)
	_read_through[normalized] = next_value
	return _success(true)


func get_filter_catalog() -> Dictionary:
	var residents_by_id: Dictionary = {}
	var days_by_value: Dictionary = {}
	for record: Dictionary in _records:
		for snapshot_value: Variant in record.get(
			"participantSnapshots",
			[],
		) as Array:
			if not snapshot_value is Dictionary:
				continue
			var snapshot := snapshot_value as Dictionary
			var resident_id := String(
				snapshot.get("residentId", ""),
			).strip_edges()
			var display_name := String(
				snapshot.get("displayName", ""),
			).strip_edges()
			if resident_id.is_empty():
				continue
			var resident := (
				(residents_by_id.get(resident_id, {}) as Dictionary).duplicate(true)
			)
			if resident.is_empty():
				resident = {
					"residentId": resident_id,
					"displayName": display_name if not display_name.is_empty() else resident_id,
					"historicalNames": [],
				}
			if (
				not display_name.is_empty()
				and not (resident["historicalNames"] as Array).has(display_name)
			):
				(resident["historicalNames"] as Array).append(display_name)
				resident["displayName"] = display_name
			residents_by_id[resident_id] = resident
		var day := int((record.get("time", {}) as Dictionary).get("day", 0))
		if day > 0:
			days_by_value[day] = true
	var kind_counts: Dictionary = {}
	var attention_unread_count := 0
	var total_unread_count := 0
	for thread_value: Variant in _threads.values():
		var thread := thread_value as Dictionary
		for kind_value: Variant in thread.get("kindTags", []) as Array:
			var kind := String(kind_value)
			kind_counts[kind] = int(kind_counts.get(kind, 0)) + 1
		var projected := _project_thread_read_state(thread)
		if not bool(projected.get("unread", false)):
			continue
		total_unread_count += 1
		if String(projected.get("attention", "archive_only")) in [
			"normal",
			"important",
		]:
			attention_unread_count += 1
	var residents: Array[Dictionary] = []
	for resident_value: Variant in residents_by_id.values():
		residents.append((resident_value as Dictionary).duplicate(true))
	residents.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var name_order := String(left.get("displayName", "")).naturalnocasecmp_to(
			String(right.get("displayName", "")),
		)
		return (
			name_order < 0
			if name_order != 0
			else String(left.get("residentId", ""))
				< String(right.get("residentId", ""))
		)
	)
	var kinds: Array[Dictionary] = []
	for kind_value: Variant in kind_counts:
		var kind := String(kind_value)
		kinds.append({"kindTag": kind, "threadCount": int(kind_counts[kind])})
	kinds.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left.get("kindTag", "")) < String(right.get("kindTag", ""))
	)
	var days: Array[int] = []
	for day_value: Variant in days_by_value:
		days.append(int(day_value))
	days.sort()
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"residents": residents,
		"kindTags": kinds,
		"days": days,
		"attentionUnreadThreadCount": attention_unread_count,
		"totalUnreadThreadCount": total_unread_count,
		"timelineId": _timeline_id,
	}


func find_thread_by_source_event(event_id: String) -> Dictionary:
	var normalized := event_id.strip_edges()
	if normalized.is_empty():
		return _failure("WORLD_LOG_SOURCE_ID_MISSING")
	for record: Dictionary in _records:
		for ref_value: Variant in record.get("sourceRefs", []) as Array:
			if not ref_value is Dictionary:
				continue
			if String((ref_value as Dictionary).get("sourceId", "")) == normalized:
				return {
					"ok": true,
					"errorCode": "",
					"retryable": false,
					"threadId": String(record.get("threadId", "")),
					"recordId": String(record.get("recordId", "")),
					"sequence": int(record.get("sequence", 0)),
				}
	return _failure("WORLD_LOG_SOURCE_EVENT_NOT_FOUND")


func get_causal_chain(thread_id: String, options: Dictionary = {}) -> Dictionary:
	var normalized := thread_id.strip_edges()
	var timeline_id := String(options.get("timelineId", _timeline_id))
	if timeline_id != _timeline_id:
		return _failure("WORLD_LOG_CURSOR_INVALID")
	if normalized.is_empty() or not _records_by_thread.has(normalized):
		return _failure("WORLD_LOG_THREAD_NOT_FOUND")
	var ordered: Array[String] = []
	var visited: Dictionary = {}
	_collect_causal_threads(
		normalized,
		ordered,
		visited,
		clampi(int(options.get("maxDepth", 16)), 1, 64),
	)
	var nodes: Array[Dictionary] = []
	if ordered.size() > 1:
		for chain_thread_id: String in ordered:
			nodes.append(_sanitize_record_output(_causal_chain_node(
				chain_thread_id,
				chain_thread_id == normalized,
			)))
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"currentThreadId": normalized,
		"nodes": nodes,
		"hasEarlier": false,
		"hasLater": false,
	}


func query_place_observations(
	place_id: String,
	options: Dictionary = {},
) -> Dictionary:
	var normalized := place_id.strip_edges()
	if normalized.is_empty():
		return _failure("WORLD_LOG_PLACE_ID_MISSING")
	var per_kind_limit := clampi(int(options.get("perKindLimit", 1)), 1, 20)
	var kinds_value: Variant = options.get(
		"kinds",
		["action", "dialogue", "important"],
	)
	var kinds: Array[String] = []
	for kind_value: Variant in kinds_value as Array:
		var kind := String(kind_value).strip_edges()
		if not kind.is_empty() and not kinds.has(kind):
			kinds.append(kind)
	var by_kind: Dictionary = {}
	for index in range(_records.size() - 1, -1, -1):
		var record := _records[index] as Dictionary
		if String(record.get("placeId", "")) != normalized:
			continue
		var kind := observation_kind_for(record)
		if not kinds.has(kind):
			continue
		var bucket: Array = by_kind.get(kind, [])
		if bucket.size() >= per_kind_limit:
			continue
		bucket.append({
			"threadId": String(record.get("threadId", "")),
			"recordId": String(record.get("recordId", "")),
			"observationKind": kind,
			"time": (record.get("time", {}) as Dictionary).duplicate(true),
			"title": String(record.get("title", "")),
			"text": String(record.get("text", "")),
			"residentId": String(record.get("residentId", "")),
			"participantIds": (
				record.get("participantIds", []) as Array
			).duplicate(),
		})
		by_kind[kind] = bucket
	var observations: Array[Dictionary] = []
	for kind: String in kinds:
		for entry_value: Variant in by_kind.get(kind, []) as Array:
			observations.append(entry_value as Dictionary)
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"observations": observations,
	}


static func observation_kind_for(record: Dictionary) -> String:
	if String(record.get("attention", "")) == "important":
		return "important"
	var record_kind := String(record.get("kind", ""))
	if (
		String(record.get("kindTag", "")) == "conversation"
		or record_kind.begins_with("conversation_")
	):
		return "dialogue"
	if String(record.get("kindTag", "")) in [
		"daily_activity",
		"production",
		"service",
		"commerce",
	]:
		return "action"
	return ""


func _collect_causal_threads(
	thread_id: String,
	ordered: Array[String],
	visited: Dictionary,
	depth: int,
) -> void:
	if visited.has(thread_id) or depth <= 0:
		return
	visited[thread_id] = true
	for record: Dictionary in _records_by_thread.get(thread_id, []) as Array:
		for cause_id: String in _record_caused_by(record):
			var found := find_thread_by_source_event(cause_id)
			if (
				found.get("ok") == true
				and String(found.get("threadId", "")) != thread_id
			):
				_collect_causal_threads(
					String(found.get("threadId", "")),
					ordered,
					visited,
					depth - 1,
				)
	ordered.append(thread_id)


func _record_caused_by(record: Dictionary) -> Array[String]:
	var payload := record.get("payload", {}) as Dictionary
	var raw: Variant = payload.get(
		"causedByEventIds",
		payload.get("causedBy", []),
	)
	var result: Array[String] = []
	if not raw is Array:
		return result
	for value: Variant in raw as Array:
		var cause_id := String(value).strip_edges()
		if not cause_id.is_empty() and not result.has(cause_id):
			result.append(cause_id)
	return result


func _causal_chain_node(thread_id: String, is_current: bool) -> Dictionary:
	var thread := _threads.get(thread_id, {}) as Dictionary
	return {
		"threadId": thread_id,
		"title": String(thread.get("title", "")),
		"time": (
			thread.get("updatedAt", {}) as Dictionary
		).duplicate(true),
		"placeLabel": String(thread.get("placeLabel", "")),
		"isCurrent": is_current,
		"participantIds": (
			thread.get("participantIds", []) as Array
		).duplicate(),
		"attention": String(thread.get("attention", "archive_only")),
	}


func create_save_snapshot(world_revision: int) -> Dictionary:
	return {
		"schema": SCHEMA,
		"schemaVersion": SCHEMA_VERSION,
		"timelineId": _timeline_id,
		"parentTimelineId": _parent_timeline_id,
		"maxSequence": _sequence,
		"worldRevision": world_revision,
		"records": _records.duplicate(true),
		"readState": _read_through.duplicate(true),
	}


func restore_save_snapshot(
	snapshot: Dictionary,
	legacy_world_state: Dictionary = {},
) -> Dictionary:
	if snapshot.is_empty():
		return migrate_legacy_world_state(legacy_world_state)
	if (
		String(snapshot.get("schema", "")) != SCHEMA
		or int(snapshot.get("schemaVersion", 0)) != SCHEMA_VERSION
		or not snapshot.get("records") is Array
		or not snapshot.get("readState") is Dictionary
	):
		return _failure("WORLD_LOG_SNAPSHOT_INVALID")
	var restored_records: Array[Dictionary] = []
	var validated_ids: Dictionary = {}
	var restored_ids: Dictionary = {}
	var restored_read_through: Dictionary = {}
	var original_read_through := snapshot.get("readState", {}) as Dictionary
	var expected_sequence := 0
	for value: Variant in snapshot.get("records", []) as Array:
		if not value is Dictionary:
			return _failure("WORLD_LOG_SNAPSHOT_INVALID")
		var record := (value as Dictionary).duplicate(true)
		expected_sequence += 1
		var payload_value: Variant = record.get("payload", {})
		if payload_value is Dictionary:
			record["payload"] = _sanitize_payload_for_log(payload_value as Dictionary)
		var sequence := int(record.get("sequence", 0))
		if sequence != expected_sequence:
			return _failure("WORLD_LOG_SNAPSHOT_INVALID")
		if _validate_record(record).get("ok") != true:
			return _failure("WORLD_LOG_SNAPSHOT_INVALID")
		_normalize_restored_title(record)
		var log_item_id := String(record.get("logItemId", ""))
		if validated_ids.has(log_item_id):
			return _failure("WORLD_LOG_SNAPSHOT_INVALID")
		validated_ids[log_item_id] = true
		if not _is_player_meaningful_record(record):
			continue
		var original_sequence := int(record.get("sequence", 0))
		var next_sequence := restored_records.size() + 1
		record["sequence"] = next_sequence
		restored_ids[log_item_id] = true
		restored_records.append(record)
		var thread_id := String(record.get("threadId", ""))
		if original_sequence <= int(original_read_through.get(thread_id, 0)):
			restored_read_through[thread_id] = next_sequence
	var parent := String(snapshot.get("timelineId", DEFAULT_TIMELINE_ID))
	_parent_timeline_id = parent
	_timeline_id = _branch_timeline_id(
		parent,
		int(snapshot.get("maxSequence", restored_records.size())) + 1,
	)
	_sequence = restored_records.size()
	_records = restored_records
	_log_item_ids = restored_ids
	_read_through = restored_read_through
	_rebuild_thread_record_index()
	_rebuild_threads()
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"changed": true,
		"timelineId": _timeline_id,
		"parentTimelineId": _parent_timeline_id,
		"recordCount": _records.size(),
	}


func _branch_timeline_id(parent: String, branch_sequence: int) -> String:
	var expanded := "%s-branch-%d" % [parent, branch_sequence]
	if expanded.length() <= MAX_TIMELINE_ID_LENGTH:
		return expanded
	# 保留 parentTimelineId 原文用于追溯；新的活动时间线用完整摘要建立
	# 稳定且有界的身份，避免恢复次数继续增长导致存档清单无法发布。
	return "world-log-branch-%s-%d" % [
		parent.sha256_text(),
		branch_sequence,
	]


func migrate_legacy_world_state(state: Dictionary) -> Dictionary:
	reset()
	var migrated_conversation_ids := _migrate_legacy_conversations(
		state.get("conversations", []),
	)
	var values_value: Variant = state.get("eventLog", [])
	if values_value is Array:
		for value: Variant in values_value as Array:
			if not value is Dictionary:
				continue
			var legacy_payload := (
				(value as Dictionary).get("payload", {}) as Dictionary
			)
			var legacy_conversation_id := String(
				legacy_payload.get(
					"conversation_id",
					legacy_payload.get("conversationId", ""),
				),
			).strip_edges()
			if migrated_conversation_ids.has(legacy_conversation_id):
				continue
			var appended := append_public_event(value as Dictionary)
			if appended.get("ok") != true:
				return appended
	for thread_id_value: Variant in _threads.keys():
		var thread_id := String(thread_id_value)
		_read_through[thread_id] = int(
			(_threads[thread_id] as Dictionary).get("latestSequence", 0),
		)
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"changed": true,
		"migrated": true,
		"recordCount": _records.size(),
	}


func _migrate_legacy_conversations(value: Variant) -> Dictionary:
	var migrated_ids: Dictionary = {}
	var conversations: Array = []
	if value is Array:
		conversations = value as Array
	elif value is Dictionary:
		conversations = (value as Dictionary).values()
	for conversation_value: Variant in conversations:
		if not conversation_value is Dictionary:
			continue
		var conversation := conversation_value as Dictionary
		var conversation_id := String(
			conversation.get("conversationId", ""),
		).strip_edges()
		var turns_value: Variant = conversation.get("turns", [])
		if conversation_id.is_empty() or not turns_value is Array:
			continue
		var turns := turns_value as Array
		if turns.is_empty():
			continue
		var participant_ids: Array[String] = []
		for participant_value: Variant in conversation.get(
			"participants",
			[],
		) as Array:
			var participant_id := String(participant_value).strip_edges()
			if not participant_id.is_empty() and not participant_ids.has(participant_id):
				participant_ids.append(participant_id)
		var participant_snapshots: Array[Dictionary] = []
		for turn_value: Variant in turns:
			if not turn_value is Dictionary:
				continue
			var turn := turn_value as Dictionary
			var speaker_id := String(
				turn.get("speaker_resident_id", ""),
			).strip_edges()
			var speaker_name := String(turn.get("speaker", "")).strip_edges()
			if speaker_id.is_empty():
				continue
			_append_snapshot_unique(
				participant_snapshots,
				{
					"residentId": speaker_id,
					"displayName": speaker_name if not speaker_name.is_empty() else speaker_id,
				},
				"residentId",
			)
		var started_at := _time_value(conversation.get("startedAt", {}))
		var updated_at := _time_value(
			conversation.get("updatedAt", started_at),
		)
		var valid_turn_count := 0
		for turn_value: Variant in turns:
			if not turn_value is Dictionary:
				continue
			valid_turn_count += 1
			var turn := (turn_value as Dictionary).duplicate(true)
			var speaker_id := String(
				turn.get("speaker_resident_id", ""),
			).strip_edges()
			var speaker_name := String(turn.get("speaker", "")).strip_edges()
			var appended := append_public_event({
				"eventId": "legacy-conversation:%s:turn:%d" % [
					conversation_id,
					valid_turn_count,
				],
				"kind": "world_event",
				"time": started_at if valid_turn_count == 1 else updated_at,
				"worldRevision": 0,
				"residentId": speaker_id,
				"residentName": speaker_name,
				"placeName": "",
				"payload": {
					"type": "搭话" if valid_turn_count == 1 else "对方答话",
					"conversation_id": conversation_id,
					"participant_resident_ids": participant_ids,
					"participantSnapshots": participant_snapshots,
					"turn": turn,
					"status": "ongoing",
					"legacyImported": true,
				},
			})
			if appended.get("ok") != true:
				continue
		if String(conversation.get("status", "")) != "active":
			append_public_event({
				"eventId": "legacy-conversation:%s:end" % conversation_id,
				"kind": "world_event",
				"time": _time_value(
					conversation.get("endedAt", updated_at),
				),
				"worldRevision": 0,
				"residentId": "",
				"residentName": "",
				"placeName": "",
				"payload": {
					"type": "对话结束",
					"conversation_id": conversation_id,
					"participant_resident_ids": participant_ids,
					"participantSnapshots": participant_snapshots,
					"status": "completed",
					"reason": String(conversation.get("endReason", "")),
					"legacyImported": true,
				},
			})
		migrated_ids[conversation_id] = true
	return migrated_ids


func get_record_count() -> int:
	return _records.size()


func get_timeline_id() -> String:
	return _timeline_id


func _validate_record(record: Dictionary) -> Dictionary:
	for key in ["threadId", "logItemId", "kind", "kindTag"]:
		if String(record.get(key, "")).strip_edges().is_empty():
			return _failure("WORLD_LOG_RECORD_INVALID")
	if not record.get("time", {}) is Dictionary:
		return _failure("WORLD_LOG_RECORD_INVALID")
	if not record.get("participantIds", []) is Array:
		return _failure("WORLD_LOG_RECORD_INVALID")
	if not record.get("references", {}) is Dictionary:
		return _failure("WORLD_LOG_RECORD_INVALID")
	return _success()


func _apply_record_to_thread(record: Dictionary) -> void:
	_apply_record_to_thread_map(_threads, record)


func _apply_record_to_thread_map(
	thread_map: Dictionary,
	record: Dictionary,
) -> void:
	var thread_id := String(record.get("threadId", ""))
	var sequence := int(record.get("sequence", 0))
	var time := (record.get("time", {}) as Dictionary).duplicate(true)
	var thread := (
		(thread_map[thread_id] as Dictionary).duplicate(true)
		if thread_map.has(thread_id)
		else {
			"schemaVersion": SCHEMA_VERSION,
			"timelineId": _timeline_id,
			"threadId": thread_id,
			"kind": String(record.get("kindTag", "world_change")),
			"kindTags": [],
			"subkind": String(record.get("kind", "world_event")),
			"title": String(record.get("title", "世界事件")),
			"participantIds": [],
			"participantSnapshots": [],
			"placeIds": [],
			"placeLabel": "",
			"startedAt": time,
			"updatedAt": time,
			"status": "ongoing",
			"attention": "archive_only",
			"preview": "",
			"latestText": "",
			"latestUpdate": "",
			"latestSequence": sequence,
			"recordCount": 0,
			"days": [],
			"relatedThreadIds": [],
			"sourceEventIds": [],
		}
	)
	_append_unique(thread["kindTags"] as Array, String(record.get("kindTag", "")))
	if String(record.get("kindTag", "")) == "mail":
		_append_unique(thread["kindTags"] as Array, "message")
	for resident_id_value: Variant in record.get("participantIds", []) as Array:
		_append_unique(thread["participantIds"] as Array, String(resident_id_value))
	for snapshot_value: Variant in record.get("participantSnapshots", []) as Array:
		if snapshot_value is Dictionary:
			_append_snapshot_unique(
				thread["participantSnapshots"] as Array,
				snapshot_value as Dictionary,
				"residentId",
			)
	var payload := record.get("payload", {}) as Dictionary
	for role_field: String in [
		"senderResidentId",
		"recipientResidentId",
		"deliveredByResidentId",
	]:
		var role_resident_id := String(payload.get(role_field, "")).strip_edges()
		if not role_resident_id.is_empty():
			thread[role_field] = role_resident_id
	var source_ref := String(payload.get("sourceRef", "")).strip_edges()
	if not source_ref.is_empty():
		thread["sourceRef"] = source_ref
	var place_id := String(record.get("placeId", ""))
	if not place_id.is_empty():
		_append_unique(thread["placeIds"] as Array, place_id)
		thread["placeLabel"] = place_id
	for route_field: String in ["sourcePlaceId", "destinationPlaceId"]:
		var route_place_id := String(payload.get(route_field, "")).strip_edges()
		if not route_place_id.is_empty():
			thread[route_field] = route_place_id
			_append_unique(thread["placeIds"] as Array, route_place_id)
	var source_place_id := String(thread.get("sourcePlaceId", ""))
	var destination_place_id := String(thread.get("destinationPlaceId", ""))
	if not source_place_id.is_empty() and not destination_place_id.is_empty():
		thread["placeLabel"] = "%s → %s" % [
			source_place_id,
			destination_place_id,
		]
	for ref_value: Variant in record.get("sourceRefs", []) as Array:
		if not ref_value is Dictionary:
			continue
		var source_id := String(
			(ref_value as Dictionary).get("sourceId", ""),
		).strip_edges()
		if not source_id.is_empty():
			_append_unique(thread["sourceEventIds"] as Array, source_id)
	var day := int(time.get("day", 0))
	if day > 0:
		_append_unique(thread["days"] as Array, day)
	thread["updatedAt"] = time
	thread["latestSequence"] = sequence
	thread["recordCount"] = int(thread.get("recordCount", 0)) + 1
	thread["title"] = _thread_title(thread, record)
	thread["status"] = _thread_status(record)
	thread["attention"] = String(record.get("attention", "archive_only"))
	var record_text := String(record.get("text", "")).strip_edges()
	if not record_text.is_empty():
		thread["latestText"] = record_text
	thread["latestUpdate"] = _record_update(record)
	thread["preview"] = (
		String(thread.get("latestText", ""))
		if not String(thread.get("latestText", "")).is_empty()
		else String(thread.get("latestUpdate", ""))
	)
	thread_map[thread_id] = thread


func _index_record_by_thread(record: Dictionary) -> void:
	var thread_id := String(record.get("threadId", ""))
	if not _records_by_thread.has(thread_id):
		var bucket: Array[Dictionary] = []
		_records_by_thread[thread_id] = bucket
	(_records_by_thread[thread_id] as Array).append(record)


func _rebuild_thread_record_index() -> void:
	_records_by_thread.clear()
	for record: Dictionary in _records:
		_index_record_by_thread(record)


func _rebuild_threads() -> void:
	_threads.clear()
	for record: Dictionary in _records:
		_apply_record_to_thread(record)


func _threads_at_sequence(upper_bound: int) -> Dictionary:
	if upper_bound >= _sequence:
		return _threads
	var result: Dictionary = {}
	for record: Dictionary in _records:
		if int(record.get("sequence", 0)) > upper_bound:
			break
		_apply_record_to_thread_map(result, record)
	return result


func _project_thread_read_state(
	source: Dictionary,
	upper_bound := -1,
) -> Dictionary:
	var thread := source.duplicate(true)
	var thread_id := String(thread.get("threadId", ""))
	var read_through := int(_read_through.get(thread_id, 0))
	var latest := int(thread.get("latestSequence", 0))
	thread["unread"] = read_through < latest
	var unread_count := 0
	var unread_attention := "archive_only"
	var normalized_upper_bound := (
		_sequence if int(upper_bound) < 0 else int(upper_bound)
	)
	for record: Dictionary in _records_by_thread.get(thread_id, []) as Array:
		if (
			int(record.get("sequence", 0)) <= read_through
			or int(record.get("sequence", 0)) > normalized_upper_bound
		):
			continue
		unread_count += 1
		unread_attention = _higher_attention(
			unread_attention,
			String(record.get("attention", "archive_only")),
		)
	thread["unreadRecordCount"] = unread_count
	if unread_count > 0:
		thread["attention"] = unread_attention
	return thread


func _root_reference(source: Dictionary, payload: Dictionary) -> Dictionary:
	if _string_or_empty(payload.get("type")) == "天气变了":
		var event_time := _time_value(
			source.get("time", payload.get("time", {})),
		)
		var day := maxi(1, int(event_time.get("day", 1)))
		return {"kind": "environment", "id": "weather-day-%d" % day}
	if _string_or_empty(payload.get("type")) == "营业状态变化":
		var service_place_id := _string_or_empty(
			payload.get("place_id", payload.get("placeId", "")),
		).strip_edges()
		if not service_place_id.is_empty():
			return {"kind": "service_state", "id": service_place_id}
	if String(source.get("kind", "")) == "story_event":
		if _string_or_empty(payload.get("storyType")) == "gathering_arrival":
			var gathering_roots := _story_root_event_ids(payload)
			if not gathering_roots.is_empty():
				var gathering_place := _string_or_empty(
					payload.get("to", source.get("placeName", "")),
				).strip_edges()
				return {
					"kind": "gathering",
					"id": "%s:%s" % [gathering_roots[0], gathering_place],
				}
	if String(source.get("kind", "")) == "resident_attendance":
		var attendance_resident_id := String(
			source.get("residentId", payload.get("residentId", "")),
		).strip_edges()
		if not attendance_resident_id.is_empty():
			return {"kind": "attendance", "id": attendance_resident_id}
	if String(source.get("kind", "")) == "private_message":
		var message_source_ref := _string_or_empty(payload.get("sourceRef")).strip_edges()
		if message_source_ref.begins_with("performance-event:"):
			return {"kind": "performance_invitation", "id": message_source_ref}
	var candidates := [
		["conversation", ["conversation_id", "conversationId"]],
		["animal", ["animal_id", "animalId"]],
		[
			"lifecycle",
			[
				"lifecycle_id",
				"lifecycleId",
				"deceased_resident_id",
				"deceasedResidentId",
			],
		],
		["condition", ["condition_id", "conditionId"]],
		["request", ["request_id", "requestId", "service_request_id"]],
		["matter", ["matter_id", "matterId"]],
		["announcement", ["announcement_id", "announcementId"]],
		["message", ["message_id", "messageId"]],
		["cargo", ["cargo_lot_id", "cargoLotId"]],
		["conflict", ["conflict_id", "conflictId"]],
		["task", ["task_id", "taskId", "action_id"]],
		["activity", ["activity_execution_id", "executionId"]],
	]
	for candidate: Array in candidates:
		for key: String in candidate[1] as Array:
			var value := _string_or_empty(payload.get(key)).strip_edges()
			if not value.is_empty():
				return {"kind": candidate[0], "id": value}
	return {
		"kind": "event",
		"id": String(source.get("eventId", "")),
	}


func _thread_kind(
	source: Dictionary,
	payload: Dictionary,
	reference: Dictionary,
) -> String:
	var root_kind := String(reference.get("kind", "event"))
	var capability := _string_or_empty(payload.get("capability"))
	if (
		String(source.get("kind", "")) == "private_message"
		or root_kind == "message"
		or capability.begins_with("message.")
	):
		return "mail"
	if root_kind == "conversation":
		return "conversation"
	if root_kind == "animal":
		return "animal"
	if root_kind == "cargo":
		return "cargo"
	if root_kind in ["announcement", "matter"]:
		return "public_matter"
	if root_kind == "conflict":
		return "world_change"
	var service_kind := _string_or_empty(
		payload.get("serviceKind", payload.get("service_kind", "")),
	)
	if service_kind in ["cafe_order", "dining_order", "grocer_sale", "flower_sale"]:
		return "commerce"
	if root_kind == "request":
		return "service"
	if root_kind in ["task", "activity"]:
		return "production"
	if String(source.get("kind", "")) == "action_result":
		return "daily_activity"
	return "world_change"


func _record_kind(
	source: Dictionary,
	payload: Dictionary,
	reference: Dictionary,
) -> String:
	var event_type := _string_or_empty(
		payload.get("type", payload.get("eventType", "")),
	).strip_edges()
	if String(reference.get("kind", "")) == "conversation":
		if event_type == "对话结束":
			return "conversation_ended"
		return "conversation_turn" if payload.has("turn") else "conversation_started"
	if not event_type.is_empty():
		return event_type
	return String(source.get("kind", "world_event"))


func _participant_ids(source: Dictionary, payload: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var source_resident := String(source.get("residentId", "")).strip_edges()
	if not source_resident.is_empty():
		result.append(source_resident)
	for key in [
		"participant_resident_ids",
		"participantIds",
		"resident_ids",
	]:
		var values: Variant = payload.get(key, [])
		if not values is Array:
			continue
		for value: Variant in values as Array:
			var resident_id := String(value).strip_edges()
			if not resident_id.is_empty() and not result.has(resident_id):
				result.append(resident_id)
	return result


func _participant_snapshots(
	source: Dictionary,
	payload: Dictionary,
	participant_ids: Array[String],
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var source_id := String(source.get("residentId", "")).strip_edges()
	var source_name := String(source.get("residentName", "")).strip_edges()
	var explicit_by_id: Dictionary = {}
	var explicit: Variant = payload.get("participantSnapshots", [])
	if explicit is Array:
		for value: Variant in explicit as Array:
			if not value is Dictionary:
				continue
			var snapshot := value as Dictionary
			var explicit_id := String(
				snapshot.get("residentId", ""),
			).strip_edges()
			if not explicit_id.is_empty():
				explicit_by_id[explicit_id] = snapshot.duplicate(true)
	for resident_id: String in participant_ids:
		var explicit_snapshot := (
			explicit_by_id.get(resident_id, {}) as Dictionary
		)
		var explicit_name := String(
			explicit_snapshot.get("displayName", ""),
		).strip_edges()
		result.append({
			"residentId": resident_id,
			"displayName": (
				explicit_name
				if not explicit_name.is_empty()
				else source_name
				if resident_id == source_id and not source_name.is_empty()
				else resident_id
			),
		})
	if explicit is Array:
		for value: Variant in explicit as Array:
			if value is Dictionary:
				_append_snapshot_unique(result, value as Dictionary, "residentId")
	return result


func _references(
	source: Dictionary,
	payload: Dictionary,
	reference: Dictionary,
) -> Dictionary:
	var result := {
		"conversationIds": [],
		"requestIds": [],
		"taskIds": [],
		"cargoLotIds": [],
		"messageIds": [],
		"matterIds": [],
		"announcementIds": [],
		"conflictIds": [],
		"eventIds": [String(source.get("eventId", ""))],
	}
	var key_by_kind := {
		"conversation": "conversationIds",
		"request": "requestIds",
		"task": "taskIds",
		"cargo": "cargoLotIds",
		"message": "messageIds",
		"matter": "matterIds",
		"announcement": "announcementIds",
		"conflict": "conflictIds",
	}
	var root_kind := String(reference.get("kind", ""))
	if key_by_kind.has(root_kind):
		(result[String(key_by_kind[root_kind])] as Array).append(
			String(reference.get("id", "")),
		)
	var reference_fields := {
		"conversationIds": ["conversation_id", "conversationId"],
		"requestIds": ["request_id", "requestId", "service_request_id"],
		"taskIds": ["task_id", "taskId", "action_id"],
		"cargoLotIds": ["cargo_lot_id", "cargoLotId"],
		"messageIds": ["message_id", "messageId"],
		"matterIds": ["matter_id", "matterId"],
		"announcementIds": ["announcement_id", "announcementId"],
		"conflictIds": ["conflict_id", "conflictId"],
	}
	for result_key: String in reference_fields:
		for payload_key: String in reference_fields[result_key] as Array:
			var reference_id := _string_or_empty(
				payload.get(payload_key),
			).strip_edges()
			if not reference_id.is_empty():
				_append_unique(result[result_key] as Array, reference_id)
	return result


func _record_status(source: Dictionary, payload: Dictionary) -> String:
	var payload_status := _string_or_empty(payload.get("status"))
	if not payload_status.is_empty():
		return payload_status
	var event_type := _string_or_empty(payload.get("type"))
	if event_type == "对话结束":
		return "completed"
	if event_type in ["搭话", "对方答话"]:
		return "ongoing"
	var condition_event_type := _string_or_empty(payload.get("eventType"))
	if condition_event_type.begins_with("condition_"):
		if condition_event_type == "condition_resolved":
			return "completed"
		return "ongoing"
	var source_status := _string_or_empty(source.get("status"))
	return source_status if not source_status.is_empty() else "confirmed"


func _thread_status(record: Dictionary) -> String:
	var status := String(record.get("status", "")).to_lower()
	if status in ["completed", "delivered", "ended", "closed", "confirmed"]:
		return "completed"
	if status in ["failed", "rejected", "expired"]:
		return "failed"
	if status in ["cancelled", "canceled"]:
		return "cancelled"
	if status in ["interrupted", "replaced"]:
		return "interrupted"
	if status in ["waiting", "pending", "blocked"]:
		return "waiting"
	return "ongoing"


func _attention(source: Dictionary, payload: Dictionary) -> String:
	var status := _string_or_empty(
		payload.get("status", source.get("status", "")),
	).to_lower()
	if status in ["failed", "rejected", "expired", "cancelled", "canceled"]:
		return "important"
	var event_type := _string_or_empty(payload.get("type"))
	if event_type in [
		"有人来了",
		"有人走了",
		"居民抵达",
		"居民离开",
		"对话结束",
		"公告发布",
	]:
		return "important"
	if String(source.get("kind", "")) == "social_matter":
		return (
			"important"
			if _string_or_empty(payload.get("attentionLevel")) == "major"
			else "normal"
		)
	if String(source.get("kind", "")) == "resident_attendance":
		return "normal" if bool(payload.get("available", true)) else "important"
	if _string_or_empty(payload.get("type")) == "营业状态变化":
		return "normal" if bool(payload.get("open", false)) else "important"
	if String(source.get("kind", "")) == "conflict_event":
		return "important"
	if String(source.get("kind", "")) == "work_task":
		return "normal" if status == "completed" else "archive_only"
	if String(source.get("kind", "")) in [
		"action_result",
		"world_event",
		"cargo_event",
		"service_result",
		"private_message",
	]:
		return "normal"
	return "archive_only"


func _title(source: Dictionary, payload: Dictionary, event_type: String) -> String:
	var resident_name := String(source.get("residentName", "")).strip_edges()
	var source_kind := String(source.get("kind", "")).strip_edges()
	var display_event_type := PRESENTATION.event_type_label(
		source_kind,
		event_type,
		payload,
	)
	var specific_title := _specific_event_title(
		resident_name,
		payload,
		event_type,
	)
	if not specific_title.is_empty():
		return specific_title
	if source_kind == "social_matter":
		var matter_summary := String(
			payload.get("reasonSummary", ""),
		).strip_edges()
		if not matter_summary.is_empty():
			return matter_summary
	if event_type == "营业状态变化":
		var service_summary := String(payload.get("summary", "")).strip_edges()
		if not service_summary.is_empty():
			return service_summary
	if String(source.get("kind", "")) == "resident_attendance":
		var attendance_summary := String(payload.get("summary", "")).strip_edges()
		if not attendance_summary.is_empty():
			return attendance_summary
	if event_type in ["搭话", "对方答话", "对话结束"]:
		return "居民交谈"
	if event_type == "居民公开反应":
		return (
			"%s的回应" % resident_name
			if not resident_name.is_empty()
			else "居民回应"
		)
	if source_kind == "story_event":
		var story_action_label := PRESENTATION.story_action_label(payload)
		if not story_action_label.is_empty():
			return (
				"%s：%s" % [resident_name, story_action_label]
				if not resident_name.is_empty()
				else story_action_label
			)
	match _string_or_empty(payload.get("capability")):
		"message.sort":
			return "%s分拣信件" % resident_name if not resident_name.is_empty() else "信件分拣"
		"message.prepare":
			return "%s整理邮袋" % resident_name if not resident_name.is_empty() else "整理邮袋"
		"message.deliver":
			return "%s投递口信" % resident_name if not resident_name.is_empty() else "口信投递"
	if event_type.begins_with("工作任务"):
		var service_title := _service_request_title(payload)
		if not service_title.is_empty():
			return (
				"%s取消" % service_title
				if _request_failure_is_meaningful(payload)
				else service_title
			)
		return (
			"%s的工作进展" % resident_name
			if not resident_name.is_empty()
			else "工作进展"
		)
	if not resident_name.is_empty() and not display_event_type.is_empty():
		return "%s：%s" % [resident_name, display_event_type]
	return display_event_type if not display_event_type.is_empty() else "世界变化"


func _specific_event_title(
	resident_name: String,
	payload: Dictionary,
	event_type: String,
) -> String:
	if event_type in [
		"公告发布",
		"公告阅读",
		"公告转告",
		"钟声公告",
		"公告到点",
		"正式通知送达",
		"公告撤回",
	]:
		var announcement_text := _string_or_empty(payload.get("text")).strip_edges()
		var announcement_title := event_type
		if not announcement_text.is_empty():
			announcement_title = "%s：%s" % [event_type, announcement_text]
		return _with_resident_name(resident_name, announcement_title)
	if event_type == "身体状况变化" or event_type.begins_with("condition_"):
		var condition_label := _string_or_empty(payload.get("label")).strip_edges()
		if not condition_label.is_empty():
			return _with_resident_name(resident_name, condition_label)
	if event_type in ["冲突见闻", "承诺条件变化"]:
		var summary := _string_or_empty(
			payload.get("summary", payload.get("reasonSummary", "")),
		).strip_edges()
		if not summary.is_empty():
			return _with_resident_name(resident_name, summary)
	if event_type == "居民死亡":
		var deceased_name := _string_or_empty(
			payload.get("deceased_resident_name", "")
		).strip_edges()
		if deceased_name.is_empty():
			deceased_name = _string_or_empty(
				payload.get("deceasedResidentName", "")
			).strip_edges()
		if deceased_name.is_empty():
			deceased_name = resident_name
		var death_reason := _string_or_empty(
			payload.get("reason", "")
		).strip_edges()
		if death_reason.is_empty():
			death_reason = _string_or_empty(
				payload.get("deathReason", "")
			).strip_edges()
		var death_title := (
			"%s去世" % deceased_name
			if not deceased_name.is_empty()
			else "居民死亡"
		)
		return (
			"%s：%s" % [death_title, death_reason]
			if not death_reason.is_empty()
			else death_title
		)
	return ""


func _with_resident_name(resident_name: String, title: String) -> String:
	return (
		"%s：%s" % [resident_name, title]
		if not resident_name.is_empty()
		else title
	)


func _normalize_restored_title(record: Dictionary) -> void:
	var title := String(record.get("title", "")).strip_edges()
	if not PRESENTATION.title_contains_internal_token(title):
		return
	var source_kind := ""
	var source_refs := record.get("sourceRefs", []) as Array
	if not source_refs.is_empty() and source_refs[0] is Dictionary:
		source_kind = String((source_refs[0] as Dictionary).get("sourceKind", ""))
	var payload := record.get("payload", {}) as Dictionary
	var event_type := String(
		payload.get("type", payload.get("eventType", source_kind)),
	).strip_edges()
	record["title"] = _title(
		{
			"kind": source_kind,
			"residentName": String(record.get("residentName", "")),
		},
		payload,
		event_type,
	)


func _thread_title(thread: Dictionary, record: Dictionary) -> String:
	if String(thread.get("threadId", "")).begins_with("announcement:"):
		var current_title := String(thread.get("title", "")).strip_edges()
		# 公告发布是整条事件链的根。到点提醒和居民回应只追加
		# 节点，不应把列表标题反复改成“公告到点”或某位居民的反应。
		if not current_title.is_empty():
			return current_title
		return String(record.get("title", current_title))
	if String(thread.get("threadId", "")).begins_with("environment:weather-day-"):
		var day := maxi(1, int((record.get("time", {}) as Dictionary).get("day", 1)))
		return "第%d天天气变化" % day
	if String(thread.get("threadId", "")).begins_with("service_state:"):
		var service_place := String(thread.get("placeLabel", "")).strip_edges()
		if service_place.is_empty():
			service_place = String(
				(record.get("payload", {}) as Dictionary).get("place_id", ""),
			).strip_edges()
		if service_place.is_empty():
			service_place = String(thread.get("threadId", "")).trim_prefix(
				"service_state:",
			)
		return "%s营业情况" % service_place
	if String(thread.get("threadId", "")).begins_with("attendance:"):
		var attendance_name := String(record.get("residentName", "")).strip_edges()
		return (
			"%s的出勤变化" % attendance_name
			if not attendance_name.is_empty()
			else "居民出勤变化"
		)
	if String(thread.get("kind", "")) == "conversation":
		var names: Array[String] = []
		for value: Variant in thread.get("participantSnapshots", []) as Array:
			if not value is Dictionary:
				continue
			var name := String((value as Dictionary).get("displayName", ""))
			if not name.is_empty() and not names.has(name):
				names.append(name)
		if not names.is_empty():
			return "%s的交谈" % "与".join(names)
	if String(thread.get("kind", "")) == "mail":
		var mail_source_ref := String(thread.get("sourceRef", "")).strip_edges()
		if mail_source_ref.is_empty():
			mail_source_ref = String(
				(record.get("payload", {}) as Dictionary).get("sourceRef", "")
			).strip_edges()
		var mail_topic := _mail_thread_topic(mail_source_ref)
		if not mail_topic.is_empty():
			if mail_source_ref.begins_with("performance-event:"):
				return mail_topic
			var sender_name := _thread_participant_name(
				thread,
				String(thread.get("senderResidentId", "")),
			)
			var recipient_name := _thread_participant_name(
				thread,
				String(thread.get("recipientResidentId", "")),
			)
			if (
				not sender_name.is_empty()
				and not recipient_name.is_empty()
			):
				return "%s给%s的%s" % [sender_name, recipient_name, mail_topic]
			return mail_topic
		var sender_name := _thread_participant_name(
			thread,
			String(thread.get("senderResidentId", "")),
		)
		var recipient_name := _thread_participant_name(
			thread,
			String(thread.get("recipientResidentId", "")),
		)
		if not sender_name.is_empty() and not recipient_name.is_empty():
			return "%s给%s的口信" % [sender_name, recipient_name]
		var current_title := String(thread.get("title", "")).strip_edges()
		if (
			not current_title.is_empty()
			and current_title != String(record.get("title", "")).strip_edges()
		):
			return current_title
		var mail_names: Array[String] = []
		for value: Variant in thread.get("participantSnapshots", []) as Array:
			if not value is Dictionary:
				continue
			var name := String((value as Dictionary).get("displayName", ""))
			if not name.is_empty() and not mail_names.has(name):
				mail_names.append(name)
		if mail_names.size() >= 2:
			return "%s给%s的口信" % [mail_names[0], mail_names[1]]
	if String(thread.get("kind", "")) == "cargo":
		var source_place_id := String(thread.get("sourcePlaceId", ""))
		var destination_place_id := String(thread.get("destinationPlaceId", ""))
		if not source_place_id.is_empty() and not destination_place_id.is_empty():
			return "%s至%s的货物搬运" % [
				source_place_id,
				destination_place_id,
			]
		return "货物搬运"
	if (thread.get("kindTags", []) as Array).has("commerce"):
		var commerce_payload := record.get("payload", {}) as Dictionary
		var event_type := String(commerce_payload.get("type", "")).strip_edges()
		if (
			event_type.begins_with("工作任务")
			and _request_failure_is_meaningful(commerce_payload)
		):
			var legacy_service_title := _service_request_title(commerce_payload)
			if not legacy_service_title.is_empty():
				return "%s取消" % legacy_service_title
		if (
			event_type in ["杂货售卖", "鲜花售卖", "咖啡交付", "供餐完成"]
			or event_type.ends_with("取消")
		):
			return event_type
		var current_title := String(thread.get("title", "")).strip_edges()
		if current_title in ["杂货售卖", "鲜花售卖", "咖啡交付", "供餐完成"]:
			return current_title
		return "经营服务"
	var event_type := String(
		(record.get("payload", {}) as Dictionary).get("type", ""),
	).strip_edges()
	if not event_type.is_empty() and not event_type.begins_with("工作任务"):
		return String(record.get("title", event_type))
	return String(thread.get("title", record.get("title", "世界事件")))


func _mail_thread_topic(source_ref: String) -> String:
	var normalized_ref := source_ref.strip_edges()
	if normalized_ref.begins_with("announcement-notice:"):
		return "公告口信"
	if normalized_ref.begins_with("announcement-"):
		return "公告口信"
	if normalized_ref.begins_with("preorder:"):
		return "预订到货口信"
	if normalized_ref.begins_with("repair-pickup:"):
		return "修理取件口信"
	if normalized_ref.begins_with("library-return:"):
		return "书籍归还口信"
	if normalized_ref.begins_with("clinic-follow-up:"):
		return "复诊提醒口信"
	if normalized_ref.begins_with("library-assist:"):
		return "资料协助口信"
	if normalized_ref.begins_with("research-accession:"):
		return "研究入藏口信"
	if normalized_ref.begins_with("civic-request:"):
		return "镇务处理口信"
	if normalized_ref.begins_with("performance-event:"):
		return "演出邀请口信"
	return ""


func _is_player_meaningful_record(record: Dictionary) -> bool:
	return CAPTURE_POLICY.should_capture_record(record)


func _request_failure_is_meaningful(payload: Dictionary) -> bool:
	return CAPTURE_POLICY.request_failure_is_meaningful(payload)


func _is_player_meaningful_story_event(payload: Dictionary) -> bool:
	return STORY_POLICY.should_capture(payload)


func _story_root_event_ids(payload: Dictionary) -> Array[String]:
	return CAPTURE_POLICY.story_root_event_ids(payload)


func _thread_participant_name(thread: Dictionary, resident_id: String) -> String:
	var normalized_id := resident_id.strip_edges()
	if normalized_id.is_empty():
		return ""
	for value: Variant in thread.get("participantSnapshots", []) as Array:
		if not value is Dictionary:
			continue
		var snapshot := value as Dictionary
		if String(snapshot.get("residentId", "")) != normalized_id:
			continue
		return String(snapshot.get("displayName", "")).strip_edges()
	return ""


func _service_request_title(payload: Dictionary) -> String:
	var capability := _string_or_empty(payload.get("capability")).strip_edges()
	return PRESENTATION.capability_label(capability)


func _record_update(record: Dictionary) -> String:
	var payload := record.get("payload", {}) as Dictionary
	var capability := _string_or_empty(payload.get("capability"))
	var status := _string_or_empty(payload.get("status")).to_lower()
	var resident_name := String(record.get("residentName", "")).strip_edges()
	if resident_name.is_empty():
		for value: Variant in record.get("participantSnapshots", []) as Array:
			if not value is Dictionary:
				continue
			resident_name = String(
				(value as Dictionary).get("displayName", ""),
			).strip_edges()
			if not resident_name.is_empty():
				break
	var actor := resident_name if not resident_name.is_empty() else "投递人"
	var source_kind := ""
	var source_refs := record.get("sourceRefs", []) as Array
	if not source_refs.is_empty() and source_refs[0] is Dictionary:
		source_kind = String(
			(source_refs[0] as Dictionary).get("sourceKind", ""),
		)
	if source_kind in ["resident_attendance", "social_matter"]:
		var summary := String(
			payload.get("summary", payload.get("reasonSummary", "")),
		).strip_edges()
		if not summary.is_empty():
			return summary
	if String(payload.get("type", "")) == "营业状态变化":
		var service_summary := String(payload.get("summary", "")).strip_edges()
		if not service_summary.is_empty():
			return service_summary
	if String(payload.get("type", "")) == "天气变了":
		var weather_text := _text(payload)
		if not weather_text.is_empty():
			return weather_text
	if (
		source_kind == "work_task"
		and _request_failure_is_meaningful(payload)
	):
		var legacy_service_title := _service_request_title(payload)
		if not legacy_service_title.is_empty():
			return "%s取消" % legacy_service_title
	if (
		capability.begins_with("message.")
		and status in ["failed", "cancelled", "canceled", "rejected", "expired"]
	):
		var reason := String(
			payload.get("reason", payload.get("waitReason", "")),
		).strip_edges()
		var prefix := (
			"口信投递已取消"
			if status in ["cancelled", "canceled"]
			else "口信投递未完成"
		)
		return "%s：%s" % [prefix, reason] if not reason.is_empty() else prefix
	if capability.begins_with("message."):
		var labels := {
			"message.sort": {
				"completed": "信件已经分拣完成",
				"in_progress": "%s正在分拣信件" % actor,
				"accepted": "%s已经接下分拣工作" % actor,
				"waiting": "信件正在等待分拣",
			},
			"message.prepare": {
				"completed": "口信已经装入邮袋",
				"in_progress": "%s正在整理邮袋" % actor,
				"accepted": "%s正在准备出发" % actor,
				"waiting": "口信正在等待装袋",
			},
			"message.deliver": {
				"completed": "%s已经当面送达口信" % actor,
				"in_progress": "%s正在前往送信" % actor,
				"accepted": "%s已经接下这封口信" % actor,
				"waiting": "口信正在等待投递",
			},
		}
		var by_state := labels.get(capability, {}) as Dictionary
		if by_state.has(status):
			return String(by_state[status])
	if String(payload.get("type", "")) == "居民公开反应":
		var reaction_text := String(payload.get("text", "")).strip_edges()
		if not reaction_text.is_empty():
			return "居民回应：%s" % reaction_text
	var event_type := _string_or_empty(payload.get("type")).strip_edges()
	if not event_type.is_empty():
		return PRESENTATION.event_type_label(source_kind, event_type, payload)
	return String(record.get("title", "事件状态已更新"))


func _text(payload: Dictionary) -> String:
	if payload.get("turn") is Dictionary:
		var turn := payload.get("turn") as Dictionary
		var say := String(turn.get("say", "")).strip_edges()
		var narration := String(turn.get("narration", "")).strip_edges()
		return say if not say.is_empty() else narration
	for key in ["text", "content", "reason", "summary", "reasonSummary", "line"]:
		var value := _string_or_empty(payload.get(key)).strip_edges()
		if not value.is_empty():
			return value
	if _string_or_empty(payload.get("eventType")).begins_with("condition_"):
		return _string_or_empty(payload.get("label")).strip_edges()
	if _string_or_empty(payload.get("type")) == "天气变了":
		var weather := _string_or_empty(payload.get("weather")).strip_edges()
		if not weather.is_empty():
			return "天气转为%s" % weather
	return ""


func _attachment_refs(payload: Dictionary) -> Array:
	var photos: Variant = payload.get("photos", [])
	return (photos as Array).duplicate(true) if photos is Array else []


func _sanitize_payload_for_log(payload: Dictionary) -> Dictionary:
	var sanitized := payload.duplicate(true)
	sanitized.erase("storyEventId")
	sanitized.erase("storyType")
	sanitized.erase("storyRootEventIds")
	return sanitized


func _sanitize_record_output(record: Dictionary) -> Dictionary:
	var sanitized := record.duplicate(true)
	var payload_value: Variant = sanitized.get("payload", {})
	if payload_value is Dictionary:
		sanitized["payload"] = _sanitize_payload_for_log(
			payload_value as Dictionary,
		)
	return sanitized


func _time_value(value: Variant) -> Dictionary:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}


func _string_or_empty(value: Variant) -> String:
	return value as String if value is String else ""


func _higher_attention(left: String, right: String) -> String:
	var rank := {"archive_only": 0, "normal": 1, "important": 2}
	return right if int(rank.get(right, 0)) > int(rank.get(left, 0)) else left


func _append_unique(target: Array, value: Variant) -> void:
	if not target.has(value):
		target.append(value)


func _append_snapshot_unique(
	target: Array,
	value: Dictionary,
	id_key: String,
) -> void:
	var item_id := String(value.get(id_key, "")).strip_edges()
	if item_id.is_empty():
		return
	for existing_value: Variant in target:
		if (
			existing_value is Dictionary
			and String((existing_value as Dictionary).get(id_key, "")) == item_id
		):
			return
	target.append(value.duplicate(true))


func _success(changed := false) -> Dictionary:
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"changed": changed,
	}


func _excluded() -> Dictionary:
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"changed": false,
		"excluded": true,
	}


func _failure(error_code: String) -> Dictionary:
	return RESULT_SHAPES.failure(error_code)
