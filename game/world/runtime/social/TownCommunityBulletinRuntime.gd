class_name TownCommunityBulletinRuntime
extends RefCounted


const WORLD_SCALARS := preload("res://world/data/town/TownWorldScalars.gd")
const RESULT_ENVELOPE := preload(
	"res://world/runtime/TownRuntimeResultEnvelope.gd"
)
const MAX_TEXT_LENGTH := 280
const MAX_SAFE_DAY := 6254999482459
const MAX_SAFE_INTEGER := 9007199254740991
const MAX_SAFE_ABSOLUTE_MINUTE := MAX_SAFE_DAY * 1440 - 1
const DELIVERY_MODES := ["board", "town_bell", "postal_notice"]
const SYSTEM_PUBLISHER_IDS := ["world"]
const PERIODS := [
	"清晨",
	"早晨",
	"上午",
	"中午",
	"下午",
	"傍晚",
	"晚上",
	"夜晚",
	"夜里",
]
const DIRECT_KNOWLEDGE_SOURCES := [
	"announcement_broadcast",
	"town_bell",
	"postal_notice",
]
const KNOWLEDGE_SOURCES := [
	"publisher",
	"announcement_broadcast",
	"town_bell",
	"postal_notice",
	"bulletin_read",
	"relayed",
	"legacy_broadcast",
]
const SAVE_V2_FIELDS := [
	"schema",
	"schema_version",
	"announcement_sequence",
	"announcements",
	"knowledge_by_resident",
]
const SAVE_V3_FIELDS := [
	"schema",
	"schema_version",
	"announcement_sequence",
	"history_start_sequence",
	"announcements",
	"knowledge_by_resident",
]
const ANNOUNCEMENT_FIELDS := [
	"announcement_id",
	"publisher_id",
	"text",
	"matter_id",
	"published_at",
	"active",
	"time",
	"publish_event_id",
	"legacy_broadcast",
	"withdrawn_at",
	"delivery_mode",
	"scheduled_absolute_minute",
	"scheduled_time_label",
	"schedule_triggered_at",
]
const KNOWLEDGE_RECORD_FIELDS := [
	"announcement_id",
	"acquired_via",
	"source_id",
	"updated_at",
]
const TIME_FIELDS := ["day", "clock", "period"]

var _social_runtime: RefCounted
var _announcements: Array[Dictionary] = []
var _announcements_by_id: Dictionary = {}
var _knowledge_by_resident: Dictionary = {}
var _announcement_sequence := 0
var _history_start_sequence := 1


func bind_social_runtime(runtime: RefCounted) -> void:
	_social_runtime = runtime


func reset() -> void:
	_announcements.clear()
	_announcements_by_id.clear()
	_knowledge_by_resident.clear()
	_announcement_sequence = 0
	_history_start_sequence = 1


func publish(
	publisher_id: String,
	text: String,
	matter_id: String,
	published_at: int,
	published_time: Dictionary = {},
	delivery_mode: String = "board",
	publish_event_id: String = "",
	schedule: Dictionary = {},
) -> Dictionary:
	var normalized_publisher := publisher_id.strip_edges()
	var normalized_text := text.strip_edges()
	var normalized_matter := matter_id.strip_edges()
	var normalized_delivery_mode := delivery_mode.strip_edges()
	var normalized_event_id := publish_event_id.strip_edges()
	var scheduled_absolute_minute := int(
		schedule.get("scheduled_absolute_minute", -1),
	)
	var scheduled_time_label := String(
		schedule.get("scheduled_time_label", ""),
	).strip_edges()
	if (
		normalized_publisher.is_empty()
		or normalized_text.is_empty()
		or normalized_text.length() > MAX_TEXT_LENGTH
		or published_at < 0
		or published_at > MAX_SAFE_ABSOLUTE_MINUTE
		or _announcement_sequence >= MAX_SAFE_INTEGER
		or normalized_delivery_mode not in DELIVERY_MODES
		or (
			not published_time.is_empty()
			and not _time_matches_minute(published_time, published_at)
		)
		or (
			not normalized_event_id.is_empty()
			and _world_event_id_sequence(normalized_event_id) <= 0
		)
		or (
			not schedule.is_empty()
			and (
				scheduled_absolute_minute <= published_at
				or scheduled_absolute_minute > MAX_SAFE_ABSOLUTE_MINUTE
				or scheduled_time_label.is_empty()
			)
		)
	):
		return _failure(
			"BULLETIN_ANNOUNCEMENT_INVALID",
			"公告发布者、正文或发布时间无效",
		)
	if not normalized_matter.is_empty():
		if _social_runtime == null:
			return _failure(
				"BULLETIN_SOCIAL_RUNTIME_MISSING",
				"绑定社会事项的公告需要社会事项运行时",
			)
		var matter := _social_runtime.get_matter(normalized_matter,) as Dictionary
		if matter.is_empty() or String(matter.get("state", "")) == "closed":
			return _failure(
				"BULLETIN_MATTER_INVALID",
				"需要回应的公告必须引用活跃社会事项",
			)
	_announcement_sequence += 1
	var announcement_id := "announcement-%d" % _announcement_sequence
	var announcement := {
		"announcement_id": announcement_id,
		"publisher_id": normalized_publisher,
		"text": normalized_text,
		"matter_id": normalized_matter,
		"published_at": published_at,
		"active": true,
		"delivery_mode": normalized_delivery_mode,
	}
	if not published_time.is_empty():
		announcement["time"] = published_time.duplicate(true)
	if not normalized_event_id.is_empty():
		announcement["publish_event_id"] = normalized_event_id
	if not schedule.is_empty():
		announcement["scheduled_absolute_minute"] = scheduled_absolute_minute
		announcement["scheduled_time_label"] = scheduled_time_label
	if not normalized_matter.is_empty():
		var channel_result := _social_runtime.add_channel(normalized_matter,
			{
				"channel_kind": "bulletin",
				"source_id": announcement_id,
				"active": true,
				"updated_at": published_at,
			},) as Dictionary
		if not bool(channel_result.get("ok", false)):
			_announcement_sequence -= 1
			return _failure(
				"BULLETIN_CHANNEL_REJECTED",
				String(channel_result.get("reason", "")),
			)
		var awareness_result := _social_runtime.record_awareness(normalized_matter,
			normalized_publisher,
			"known",
			"witnessed",
			announcement_id,
			published_at,) as Dictionary
		if not bool(awareness_result.get("ok", false)):
			_social_runtime.add_channel(normalized_matter,
				{
					"channel_kind": "bulletin",
					"source_id": announcement_id,
					"active": false,
					"updated_at": published_at,
				},)
			_announcement_sequence -= 1
			return _failure(
				"BULLETIN_AWARENESS_REJECTED",
				String(awareness_result.get("reason", "")),
			)
	_announcements.append(announcement)
	_announcements_by_id[announcement_id] = announcement
	if normalized_publisher not in SYSTEM_PUBLISHER_IDS:
		_record_knowledge(
			normalized_publisher,
			announcement_id,
			"publisher",
			normalized_publisher,
			published_at,
		)
	return _success({
		"announcement": announcement.duplicate(true),
		"resident_event": {},
	})


func receive_directly(
	resident_id: String,
	announcement_id: String,
	acquired_via: String,
	source_id: String,
	acquired_at: int,
) -> Dictionary:
	var normalized_resident := resident_id.strip_edges()
	var normalized_source := source_id.strip_edges()
	var announcement := _announcement(announcement_id)
	if (
		normalized_resident.is_empty()
		or normalized_source.is_empty()
		or acquired_via not in DIRECT_KNOWLEDGE_SOURCES
		or announcement.is_empty()
		or not bool(announcement.get("active", false))
		or acquired_at < 0
	):
		return _failure(
			"BULLETIN_DIRECT_RECEIPT_INVALID",
			"公告、接收者、传播来源或时间无效",
		)
	var resident_records := _knowledge_by_resident.get(
		normalized_resident,
		{},
	) as Dictionary
	var previous_record := (
		resident_records.get(announcement_id, {}) as Dictionary
	).duplicate(true)
	if not previous_record.is_empty():
		return _success({
			"new_knowledge": false,
			"announcement": announcement.duplicate(true),
		})
	_record_knowledge(
		normalized_resident,
		announcement_id,
		acquired_via,
		normalized_source,
		acquired_at,
	)
	var matter_id := String(announcement.get("matter_id", ""))
	if not matter_id.is_empty():
		var awareness_result := _social_runtime.record_awareness(matter_id,
			normalized_resident,
			"known",
			acquired_via,
			normalized_source,
			acquired_at,) as Dictionary
		if not bool(awareness_result.get("ok", false)):
			_forget_knowledge(normalized_resident, announcement_id)
			return _failure(
				"BULLETIN_AWARENESS_REJECTED",
				String(awareness_result.get("reason", "")),
			)
	return _success({
		"new_knowledge": true,
		"announcement": announcement.duplicate(true),
	})


func read_announcement(
	resident_id: String,
	announcement_id: String,
	read_at: int,
) -> Dictionary:
	var normalized_resident := resident_id.strip_edges()
	var announcement := _announcement(announcement_id)
	if (
		normalized_resident.is_empty()
		or announcement.is_empty()
		or not bool(announcement.get("active", false))
		or read_at < 0
	):
		return _failure(
			"BULLETIN_READ_INVALID",
			"居民、公告或阅读时间无效",
		)
	if _resident_knows(normalized_resident, announcement_id):
		return _success({
			"new_knowledge": false,
			"event": {},
			"announcement": announcement.duplicate(true),
		})
	_record_knowledge(
		normalized_resident,
		announcement_id,
		"bulletin_read",
		announcement_id,
		read_at,
	)
	var matter_id := String(announcement.get("matter_id", ""))
	if not matter_id.is_empty():
		var awareness_result := _social_runtime.record_awareness(matter_id,
			normalized_resident,
			"known",
			"bulletin_read",
			announcement_id,
			read_at,) as Dictionary
		if not bool(awareness_result.get("ok", false)):
			_forget_knowledge(normalized_resident, announcement_id)
			return _failure(
				"BULLETIN_AWARENESS_REJECTED",
				String(awareness_result.get("reason", "")),
			)
	var event := {
		"type": "公告阅读",
		"announcement_id": String(
			announcement.get("announcement_id", "")
		),
		"publisher_resident_id": String(
			announcement.get("publisher_id", "")
		),
		"text": String(announcement.get("text", "")),
		"matter_id": (
			matter_id
			if not matter_id.is_empty()
			else null
		),
		"read_at": read_at,
	}
	return _success({
		"new_knowledge": true,
		"event": event,
		"announcement": announcement.duplicate(true),
	})


func relay_announcement(
	speaker_id: String,
	listener_id: String,
	announcement_id: String,
	heard_at: int,
) -> Dictionary:
	var normalized_speaker := speaker_id.strip_edges()
	var normalized_listener := listener_id.strip_edges()
	var announcement := _announcement(announcement_id)
	if (
		normalized_speaker.is_empty()
		or normalized_listener.is_empty()
		or normalized_speaker == normalized_listener
		or announcement.is_empty()
		or heard_at < 0
	):
		return _failure(
			"BULLETIN_RELAY_INVALID",
			"转告参与者、公告或时间无效",
		)
	if not _resident_knows(normalized_speaker, announcement_id):
		return _failure(
			"BULLETIN_RELAY_SOURCE_UNKNOWN",
			"转告者本人尚不知道这条公告",
		)
	if _resident_knows(normalized_listener, announcement_id):
		return _success({
			"new_knowledge": false,
			"announcement": announcement.duplicate(true),
		})
	_record_knowledge(
		normalized_listener,
		announcement_id,
		"relayed",
		normalized_speaker,
		heard_at,
	)
	var matter_id := String(announcement.get("matter_id", ""))
	if not matter_id.is_empty():
		var awareness_result := _social_runtime.record_awareness(matter_id,
			normalized_listener,
			"known",
			"relayed",
			normalized_speaker,
			heard_at,) as Dictionary
		if not bool(awareness_result.get("ok", false)):
			_forget_knowledge(normalized_listener, announcement_id)
			return _failure(
				"BULLETIN_AWARENESS_REJECTED",
				String(awareness_result.get("reason", "")),
			)
	return _success({
		"new_knowledge": true,
		"announcement": announcement.duplicate(true),
	})


func withdraw_announcement(
	announcement_id: String,
	withdrawn_at: int,
) -> Dictionary:
	var announcement := _announcement(announcement_id)
	if (
		announcement.is_empty()
		or withdrawn_at < int(announcement.get("published_at", 0))
	):
		return _failure(
			"BULLETIN_WITHDRAW_INVALID",
			"公告或撤下时间无效",
		)
	if not bool(announcement.get("active", false)):
		return _success(announcement.duplicate(true))
	announcement["active"] = false
	announcement["withdrawn_at"] = withdrawn_at
	var matter_id := String(announcement.get("matter_id", ""))
	if not matter_id.is_empty() and _social_runtime != null:
		var matter := _social_runtime.get_matter(matter_id,) as Dictionary
		if not matter.is_empty() and String(matter.get("state", "")) != "closed":
			_social_runtime.add_channel(matter_id,
				{
					"channel_kind": "bulletin",
					"source_id": announcement_id,
					"active": false,
					"updated_at": withdrawn_at,
				},)
	return _success(announcement.duplicate(true))


func get_announcements(include_withdrawn: bool = true) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for announcement: Dictionary in _announcements:
		if include_withdrawn or bool(announcement.get("active", false)):
			result.append(announcement.duplicate(true))
	return result


func due_scheduled_announcements(
	absolute_minute: int,
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for announcement: Dictionary in _announcements:
		if (
			bool(announcement.get("active", false))
			and int(announcement.get("scheduled_absolute_minute", -1)) >= 0
			and int(announcement.get("scheduled_absolute_minute", -1)) <= absolute_minute
			and not announcement.has("schedule_triggered_at")
		):
			result.append(announcement.duplicate(true))
	return result


func mark_schedule_triggered(
	announcement_id: String,
	absolute_minute: int,
) -> Dictionary:
	var announcement := _announcement(announcement_id)
	if (
		announcement.is_empty()
		or int(announcement.get("scheduled_absolute_minute", -1)) < 0
		or absolute_minute < int(
			announcement.get("scheduled_absolute_minute", -1),
		)
	):
		return _failure(
			"BULLETIN_SCHEDULE_TRIGGER_INVALID",
			"公告或到点时间无效",
		)
	if announcement.has("schedule_triggered_at"):
		return _success(announcement.duplicate(true))
	announcement["schedule_triggered_at"] = absolute_minute
	return _success(announcement.duplicate(true))


func unread_count(resident_id: String) -> int:
	var count := 0
	for announcement: Dictionary in _announcements:
		if (
			bool(announcement.get("active", false))
			and not _resident_knows(
				resident_id.strip_edges(),
				String(announcement.get("announcement_id", "")),
			)
		):
			count += 1
	return count


func knowledge_for(resident_id: String) -> Array[Dictionary]:
	var resident_records := _knowledge_by_resident.get(
		resident_id.strip_edges(),
		{},
	) as Dictionary
	var announcement_ids: Array[String] = []
	for id_value: Variant in resident_records:
		announcement_ids.append(String(id_value))
	announcement_ids.sort()
	var result: Array[Dictionary] = []
	for announcement_id: String in announcement_ids:
		result.append(
			(
				resident_records.get(announcement_id, {}) as Dictionary
			).duplicate(true)
		)
	return result


func create_save_snapshot() -> Dictionary:
	return {
		"schema": "town-community-bulletin",
		"schema_version": 3,
		"announcement_sequence": _announcement_sequence,
		"history_start_sequence": _history_start_sequence,
		"announcements": _announcements.duplicate(true),
		"knowledge_by_resident": _knowledge_by_resident.duplicate(true),
	}


func legacy_broadcast_snapshot(maximum_count: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var start_index := maxi(0, _announcements.size() - maximum_count)
	for index in range(start_index, _announcements.size()):
		var announcement := _announcements[index]
		result.append({
			"announcement_id": String(
				announcement.get("announcement_id", ""),
			),
			"text": String(announcement.get("text", "")),
			"time": (
				announcement.get("time", {}) as Dictionary
			).duplicate(true),
		})
	return result


func announcement_sequence() -> int:
	return _announcement_sequence


func restore_save_snapshot(snapshot: Dictionary) -> Dictionary:
	var validation := _validate_save_snapshot(snapshot)
	if not bool(validation.get("ok", false)):
		return validation
	var value := validation.get("value", {}) as Dictionary
	var announcements := value.get("announcements", []) as Array
	_announcements.clear()
	_announcements_by_id.clear()
	for announcement_value: Variant in announcements:
		var announcement := (
			announcement_value as Dictionary
		).duplicate(true)
		_announcements.append(announcement)
		_announcements_by_id[
			String(announcement.get("announcement_id", ""))
		] = announcement
	_knowledge_by_resident = (
		value.get("knowledge_by_resident", {}) as Dictionary
	).duplicate(true)
	_announcement_sequence = int(
		value.get("announcement_sequence", 0)
	)
	_history_start_sequence = int(
		value.get("history_start_sequence", 1)
	)
	return _success({
		"announcement_count": _announcements.size(),
		"resident_knowledge_count": _knowledge_by_resident.size(),
	})


func migrate_legacy_broadcasts(
	legacy_announcements: Array,
	resident_ids: Array,
) -> Dictionary:
	if not _announcements.is_empty():
		return _failure(
			"BULLETIN_MIGRATION_STATE_INVALID",
			"旧公告只能迁移到空公告栏",
		)
	var normalized_residents: Array[String] = []
	for resident_value: Variant in resident_ids:
		if typeof(resident_value) != TYPE_STRING:
			return _failure(
				"BULLETIN_MIGRATION_INVALID",
				"旧公告居民编号无效",
			)
		var resident_id := String(resident_value).strip_edges()
		if resident_id.is_empty():
			return _failure(
				"BULLETIN_MIGRATION_INVALID",
				"旧公告居民编号不能为空",
			)
		if not normalized_residents.has(resident_id):
			normalized_residents.append(resident_id)
	normalized_residents.sort()
	var migrated: Array[Dictionary] = []
	var max_sequence := 0
	var seen_legacy_ids := {}
	for value: Variant in legacy_announcements:
		if typeof(value) != TYPE_DICTIONARY:
			return _failure(
				"BULLETIN_MIGRATION_INVALID",
				"旧公告必须是对象",
			)
		var legacy := value as Dictionary
		if (
			typeof(legacy.get("announcement_id")) != TYPE_STRING
			or typeof(legacy.get("text")) != TYPE_STRING
			or typeof(legacy.get("time")) != TYPE_DICTIONARY
		):
			return _failure(
				"BULLETIN_MIGRATION_INVALID",
				"旧公告字段无效",
			)
		var announcement_id := String(
			legacy.get("announcement_id", "")
		).strip_edges()
		var text := String(legacy.get("text", "")).strip_edges()
		var sequence := _announcement_id_sequence(announcement_id)
		var legacy_time := legacy.get("time", {}) as Dictionary
		var published_at := _absolute_minute(legacy_time)
		if (
			announcement_id.is_empty()
			or text.is_empty()
			or sequence <= 0
			or published_at < 0
			or not _time_matches_minute(legacy_time, published_at)
			or seen_legacy_ids.has(announcement_id)
		):
			return _failure(
				"BULLETIN_MIGRATION_INVALID",
				"旧公告编号、正文或时间无效",
			)
		seen_legacy_ids[announcement_id] = true
		max_sequence = maxi(max_sequence, sequence)
		migrated.append({
			"announcement_id": announcement_id,
			"publisher_id": "legacy-player",
			"text": text,
			"matter_id": "",
			"published_at": published_at,
			"active": true,
			"legacy_broadcast": true,
			"delivery_mode": "town_bell",
			"time": (
				legacy.get("time", {}) as Dictionary
			).duplicate(true),
		})
	migrated.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			var left_time := int(left.get("published_at", 0))
			var right_time := int(right.get("published_at", 0))
			if left_time != right_time:
				return left_time < right_time
			return String(left.get("announcement_id", "")) < String(
				right.get("announcement_id", "")
			)
	)
	for announcement: Dictionary in migrated:
		var announcement_id := String(
			announcement.get("announcement_id", "")
		)
		_announcements.append(announcement)
		_announcements_by_id[announcement_id] = announcement
		for resident_id: String in normalized_residents:
			_record_knowledge(
				resident_id,
				announcement_id,
				"legacy_broadcast",
				announcement_id,
				int(announcement.get("published_at", 0)),
			)
	_announcement_sequence = max_sequence
	_history_start_sequence = (
		_announcement_sequence + 1
		if migrated.is_empty()
		else _minimum_announcement_sequence(migrated)
	)
	return _success({
		"announcement_count": migrated.size(),
		"aware_resident_count": normalized_residents.size(),
	})


func _validate_save_snapshot(snapshot: Dictionary) -> Dictionary:
	var schema_version := (
		int(snapshot.get("schema_version"))
		if typeof(snapshot.get("schema_version")) == TYPE_INT
		else -1
	)
	var expected_snapshot_fields := (
		SAVE_V3_FIELDS
		if schema_version == 3
		else SAVE_V2_FIELDS
	)
	if (
		snapshot.get("schema") != "town-community-bulletin"
		or schema_version not in [2, 3]
		or not _has_exact_keys(snapshot, expected_snapshot_fields)
		or typeof(snapshot.get("announcement_sequence")) != TYPE_INT
		or int(snapshot.get("announcement_sequence", -1)) < 0
		or int(snapshot.get("announcement_sequence", -1)) > MAX_SAFE_INTEGER
		or (
			schema_version == 3
			and (
				typeof(snapshot.get("history_start_sequence")) != TYPE_INT
				or int(snapshot.get("history_start_sequence", 0)) <= 0
			)
		)
		or typeof(snapshot.get("announcements")) != TYPE_ARRAY
		or typeof(snapshot.get("knowledge_by_resident")) != TYPE_DICTIONARY
	):
		return _failure(
			"BULLETIN_SAVE_INVALID",
			"社区公告栏存档外壳无效",
		)
	var announcements: Array[Dictionary] = []
	var seen_ids := {}
	var seen_publish_event_ids := {}
	var max_sequence := 0
	var previous_sequence := 0
	var previous_published_at := -1
	for value: Variant in snapshot.get("announcements", []) as Array:
		if typeof(value) != TYPE_DICTIONARY:
			return _failure(
				"BULLETIN_SAVE_INVALID",
				"保存的公告必须是对象",
			)
		var announcement := (value as Dictionary).duplicate(true)
		if not _has_only_keys(announcement, ANNOUNCEMENT_FIELDS):
			return _failure(
				"BULLETIN_SAVE_INVALID",
				"保存公告包含未知字段",
			)
		if not announcement.has("delivery_mode"):
			announcement["delivery_mode"] = (
				"town_bell"
				if bool(announcement.get("legacy_broadcast", false))
				else "board"
			)
		for text_field in [
			"announcement_id",
			"publisher_id",
			"text",
			"matter_id",
		]:
			if typeof(announcement.get(text_field)) != TYPE_STRING:
				return _failure(
					"BULLETIN_SAVE_INVALID",
					"保存公告 %s 字段无效" % text_field,
				)
		var announcement_id := String(
			announcement.get("announcement_id", "")
		)
		var publisher_id := String(
			announcement.get("publisher_id", "")
		)
		var text := String(announcement.get("text", ""))
		var matter_id := String(announcement.get("matter_id", ""))
		var published_at_value: Variant = announcement.get("published_at")
		var published_at := (
			int(published_at_value)
			if typeof(published_at_value) == TYPE_INT
			else -1
		)
		var sequence := _announcement_id_sequence(announcement_id)
		if (
			sequence <= 0
			or seen_ids.has(announcement_id)
			or announcement_id != announcement_id.strip_edges()
			or publisher_id.is_empty()
			or publisher_id != publisher_id.strip_edges()
			or text.is_empty()
			or text != text.strip_edges()
			or text.length() > MAX_TEXT_LENGTH
			or matter_id != matter_id.strip_edges()
			or typeof(announcement.get("published_at")) != TYPE_INT
			or published_at < 0
			or published_at > MAX_SAFE_ABSOLUTE_MINUTE
			or typeof(announcement.get("active")) != TYPE_BOOL
			or String(announcement.get("delivery_mode", ""))
			not in DELIVERY_MODES
		):
			return _failure(
				"BULLETIN_SAVE_INVALID",
				"保存公告字段或编号无效",
			)
		if sequence <= previous_sequence or published_at < previous_published_at:
			return _failure(
				"BULLETIN_SAVE_INVALID",
				"保存的公告顺序无效",
			)
		previous_sequence = sequence
		previous_published_at = published_at
		if (
			announcement.has("time")
			and (
				typeof(announcement.get("time")) != TYPE_DICTIONARY
				or not _time_matches_minute(
					announcement.get("time", {}) as Dictionary,
					published_at,
				)
			)
		):
			return _failure(
				"BULLETIN_SAVE_INVALID",
				"保存公告时间无效",
			)
		if announcement.has("legacy_broadcast"):
			if (
				typeof(announcement.get("legacy_broadcast")) != TYPE_BOOL
				or not bool(announcement.get("legacy_broadcast"))
				or publisher_id != "legacy-player"
				or announcement.has("publish_event_id")
				or String(announcement.get("delivery_mode", ""))
				!= "town_bell"
			):
				return _failure(
					"BULLETIN_SAVE_INVALID",
					"旧公告迁移标记无效",
				)
		var has_withdrawn_at := announcement.has("withdrawn_at")
		if (
			has_withdrawn_at
			and (
					typeof(announcement.get("withdrawn_at")) != TYPE_INT
					or int(announcement.get("withdrawn_at", -1)) < published_at
					or int(announcement.get("withdrawn_at", -1))
					> MAX_SAFE_ABSOLUTE_MINUTE
					or bool(announcement.get("active", true))
			)
		) or (
			not has_withdrawn_at
			and not bool(announcement.get("active", false))
		):
			return _failure(
				"BULLETIN_SAVE_INVALID",
				"保存公告撤下状态无效",
			)
		if announcement.has("publish_event_id"):
			var publish_event_id: Variant = announcement.get(
				"publish_event_id",
			)
			if (
				typeof(publish_event_id) != TYPE_STRING
				or _world_event_id_sequence(String(publish_event_id)) <= 0
				or seen_publish_event_ids.has(String(publish_event_id))
			):
				return _failure(
					"BULLETIN_SAVE_INVALID",
					"保存公告发布事件编号无效或重复",
				)
			seen_publish_event_ids[String(publish_event_id)] = true
		var has_schedule := announcement.has("scheduled_absolute_minute")
		if has_schedule:
			if (
				typeof(announcement.get("scheduled_absolute_minute")) != TYPE_INT
				or int(announcement.get("scheduled_absolute_minute", -1)) <= published_at
				or int(announcement.get("scheduled_absolute_minute", -1)) > MAX_SAFE_ABSOLUTE_MINUTE
				or typeof(announcement.get("scheduled_time_label")) != TYPE_STRING
				or String(announcement.get("scheduled_time_label", "")).strip_edges().is_empty()
			):
				return _failure("BULLETIN_SAVE_INVALID", "保存公告约定时间无效")
			if announcement.has("schedule_triggered_at") and (
				typeof(announcement.get("schedule_triggered_at")) != TYPE_INT
				or int(announcement.get("schedule_triggered_at", -1))
				< int(announcement.get("scheduled_absolute_minute", 0))
				or int(announcement.get("schedule_triggered_at", -1)) > MAX_SAFE_ABSOLUTE_MINUTE
			):
				return _failure("BULLETIN_SAVE_INVALID", "保存公告到点状态无效")
		elif announcement.has("scheduled_time_label") or announcement.has("schedule_triggered_at"):
			return _failure("BULLETIN_SAVE_INVALID", "保存公告时间字段不完整")
		seen_ids[announcement_id] = announcement
		max_sequence = maxi(max_sequence, sequence)
		announcements.append(announcement.duplicate(true))
	var announcement_sequence := int(
		snapshot.get("announcement_sequence", 0)
	)
	var history_start_sequence := (
		int(snapshot.get("history_start_sequence", 1))
		if schema_version == 3
		else _contiguous_history_start(
			seen_ids,
			announcement_sequence,
		)
	)
	if (
		announcement_sequence != max_sequence
		or history_start_sequence > announcement_sequence + 1
	):
		return _failure(
			"BULLETIN_SAVE_INVALID",
			"公告序列落后于已保存编号",
		)
	var expected_canonical_history_size := maxi(
		announcement_sequence - history_start_sequence + 1,
		0,
	)
	var canonical_history_size := 0
	for announcement: Dictionary in announcements:
		if _announcement_id_sequence(String(
			announcement.get("announcement_id", ""),
		)) >= history_start_sequence:
			canonical_history_size += 1
	if canonical_history_size != expected_canonical_history_size:
		return _failure(
			"BULLETIN_SAVE_INVALID",
			"保存的公告历史编号不连续",
		)
	for sequence in range(
		history_start_sequence,
		announcement_sequence + 1,
	):
		if not seen_ids.has("announcement-%d" % sequence):
			return _failure(
				"BULLETIN_SAVE_INVALID",
				"保存的公告历史编号不连续",
			)
	var knowledge_result := _validate_saved_knowledge(
		snapshot.get("knowledge_by_resident", {}) as Dictionary,
		seen_ids,
	)
	if not bool(knowledge_result.get("ok", false)):
		return knowledge_result
	return _success({
		"announcement_sequence": announcement_sequence,
		"history_start_sequence": history_start_sequence,
		"announcements": announcements,
		"knowledge_by_resident": knowledge_result.get("value", {}),
	})


func _validate_saved_knowledge(
	knowledge: Dictionary,
	announcement_ids: Dictionary,
) -> Dictionary:
	var normalized := {}
	for resident_value: Variant in knowledge:
		if typeof(resident_value) != TYPE_STRING:
			return _failure(
				"BULLETIN_SAVE_INVALID",
				"公告知情居民编号无效",
			)
		var resident_id := String(resident_value).strip_edges()
		var records_value: Variant = knowledge.get(resident_value)
		if (
			resident_id.is_empty()
			or resident_id != String(resident_value)
			or typeof(records_value) != TYPE_DICTIONARY
		):
			return _failure(
				"BULLETIN_SAVE_INVALID",
				"公告知情记录无效",
			)
		var records := records_value as Dictionary
		var stored := {}
		for announcement_value: Variant in records:
			if typeof(announcement_value) != TYPE_STRING:
				return _failure(
					"BULLETIN_SAVE_INVALID",
					"公告知情记录编号无效",
				)
			var announcement_id := String(announcement_value)
			var record_value: Variant = records.get(announcement_value)
			if (
				not announcement_ids.has(announcement_id)
				or typeof(record_value) != TYPE_DICTIONARY
			):
				return _failure(
					"BULLETIN_SAVE_INVALID",
					"公告知情记录引用不存在的公告",
				)
			var record := record_value as Dictionary
			var announcement := (
				announcement_ids.get(announcement_id, {}) as Dictionary
			)
			if (
				not _has_exact_keys(record, KNOWLEDGE_RECORD_FIELDS)
				or record.get("announcement_id") != announcement_id
				or typeof(record.get("acquired_via")) != TYPE_STRING
				or typeof(record.get("source_id")) != TYPE_STRING
				or typeof(record.get("updated_at")) != TYPE_INT
			):
				return _failure(
					"BULLETIN_SAVE_INVALID",
					"公告知情字段无效",
				)
			var acquired_via := String(record.get("acquired_via", ""))
			var source_id := String(record.get("source_id", ""))
			var updated_at := int(record.get("updated_at", -1))
			if (
				acquired_via not in KNOWLEDGE_SOURCES
				or source_id.is_empty()
				or source_id != source_id.strip_edges()
				or updated_at < int(announcement.get("published_at", 0))
				or updated_at > MAX_SAFE_ABSOLUTE_MINUTE
			):
				return _failure(
					"BULLETIN_SAVE_INVALID",
					"公告知情字段无效",
				)
			if (
				acquired_via == "publisher"
				and (
					resident_id != String(announcement.get("publisher_id", ""))
					or source_id != resident_id
					or updated_at != int(announcement.get("published_at", -1))
				)
			) or (
				acquired_via in [
					"announcement_broadcast",
					"legacy_broadcast",
				]
				and (
					source_id != announcement_id
					or updated_at != int(announcement.get("published_at", -1))
					or (
						acquired_via == "legacy_broadcast"
						and not bool(
							announcement.get("legacy_broadcast", false)
						)
					)
				)
			) or (
				acquired_via == "bulletin_read"
				and source_id != announcement_id
			) or (
				acquired_via == "relayed"
				and source_id == resident_id
			) or (
				acquired_via == "town_bell"
				and String(announcement.get("delivery_mode", ""))
				!= "town_bell"
			) or (
				acquired_via == "postal_notice"
				and String(announcement.get("delivery_mode", ""))
				!= "postal_notice"
			):
				return _failure(
					"BULLETIN_SAVE_INVALID",
					"公告知情来源与公告不一致",
				)
			stored[announcement_id] = record.duplicate(true)
		normalized[resident_id] = stored
	return _success(normalized)


func _announcement_id_sequence(announcement_id: String) -> int:
	if not announcement_id.begins_with("announcement-"):
		return -1
	var suffix := announcement_id.trim_prefix("announcement-")
	if not suffix.is_valid_int():
		return -1
	var sequence := int(suffix)
	return sequence if sequence > 0 and suffix == str(sequence) else -1


func _has_exact_keys(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size():
		return false
	return _has_only_keys(value, expected)


func _has_only_keys(value: Dictionary, allowed: Array) -> bool:
	for key_value: Variant in value:
		if not key_value is String or key_value not in allowed:
			return false
	return true


func _minimum_announcement_sequence(announcements: Array[Dictionary]) -> int:
	var minimum := 0
	for announcement: Dictionary in announcements:
		var sequence := _announcement_id_sequence(
			String(announcement.get("announcement_id", "")),
		)
		if sequence > 0:
			minimum = sequence if minimum == 0 else mini(minimum, sequence)
	return minimum


func _contiguous_history_start(
	announcements_by_id: Dictionary,
	announcement_sequence: int,
) -> int:
	var sequence := announcement_sequence
	while sequence > 0 and announcements_by_id.has(
		"announcement-%d" % sequence,
	):
		sequence -= 1
	return sequence + 1


func _world_event_id_sequence(event_id: String) -> int:
	if not event_id.begins_with("world-event-"):
		return -1
	var suffix := event_id.trim_prefix("world-event-")
	if not suffix.is_valid_int():
		return -1
	var sequence := int(suffix)
	return (
		sequence
		if sequence > 0 and sequence <= MAX_SAFE_INTEGER and suffix == str(sequence)
		else -1
	)


func _absolute_minute(time: Dictionary) -> int:
	var day := int(time.get("day", 0))
	var clock := String(time.get("clock", ""))
	if (
		typeof(time.get("day")) != TYPE_INT
		or day <= 0
		or day > MAX_SAFE_DAY
		or typeof(time.get("clock")) != TYPE_STRING
		or not _is_valid_clock(clock)
	):
		return -1
	return (
		(day - 1) * 1440
		+ int(clock.substr(0, 2)) * 60
		+ int(clock.substr(3, 2))
	)


func _is_valid_clock(clock: String) -> bool:
	return WORLD_SCALARS.is_valid_clock(clock)


func _time_matches_minute(time: Dictionary, absolute_minute: int) -> bool:
	var period: Variant = time.get("period")
	return (
		_has_exact_keys(time, TIME_FIELDS)
		and period is String
		and String(period) in PERIODS
		and _absolute_minute(time) == absolute_minute
	)


func _record_knowledge(
	resident_id: String,
	announcement_id: String,
	acquired_via: String,
	source_id: String,
	updated_at: int,
) -> void:
	var resident_records := _knowledge_by_resident.get(
		resident_id,
		{},
	) as Dictionary
	resident_records[announcement_id] = {
		"announcement_id": announcement_id,
		"acquired_via": acquired_via,
		"source_id": source_id,
		"updated_at": updated_at,
	}
	_knowledge_by_resident[resident_id] = resident_records


func _forget_knowledge(
	resident_id: String,
	announcement_id: String,
) -> void:
	var resident_records := _knowledge_by_resident.get(
		resident_id,
		{},
	) as Dictionary
	resident_records.erase(announcement_id)


func _resident_knows(
	resident_id: String,
	announcement_id: String,
) -> bool:
	var resident_records := _knowledge_by_resident.get(
		resident_id,
		{},
	) as Dictionary
	return resident_records.has(announcement_id)


func _announcement(announcement_id: String) -> Dictionary:
	return _announcements_by_id.get(
		announcement_id.strip_edges(),
		{},
	) as Dictionary


func _success(value: Variant) -> Dictionary:
	return RESULT_ENVELOPE.success(value)


func _failure(error_code: String, reason: String) -> Dictionary:
	return RESULT_ENVELOPE.failure(error_code, reason)
