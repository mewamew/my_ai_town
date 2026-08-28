class_name TownWorldRestoreSocialState
extends RefCounted


const SAVE_SCALARS_UTIL := preload(
	"res://world/presentation/session/TownSaveScalars.gd"
)
const SAVE_CODEC := preload(
	"res://world/runtime/persistence/TownWorldSaveCodec.gd"
)
const RESTORE_LAYOUT := preload(
	"res://world/runtime/persistence/TownWorldRestoreLayout.gd"
)
# 与 TownWorldRuntime.DEFAULT_PLAYER_AVATAR_ID 保持一致。
const DEFAULT_PLAYER_AVATAR_ID := "person_7f3a91c2d8e4"
const SYSTEM_BULLETIN_PUBLISHER_ID := "world"
const PUBLIC_EVENT_KINDS := [
	"action_result",
	"player_place",
	"resident_activity",
	"resident_place",
	"story_event",
	"world_event",
]


static func prepare(
	world_data: Dictionary,
	state: Dictionary,
	residents: Dictionary,
	player_avatar: Dictionary,
) -> Dictionary:
	var errors: Array[String] = []
	var known_places := {}
	var public_places := {}
	var home_places := {}
	for place_value: Variant in world_data.get("places", []) as Array:
		var place := place_value as Dictionary
		var place_name := String(place.get("name", ""))
		known_places[place_name] = true
		var place_type := String(place.get("type", ""))
		if place_type == "公共地点":
			public_places[place_name] = true
		elif place_type == "住家":
			home_places[place_name] = true
	var owners_value: Variant = state.get("owners")
	if not owners_value is Dictionary:
		errors.append("世界存档 owners 必须是对象")
	var owners := owners_value as Dictionary if owners_value is Dictionary else {}
	_validate_saved_owners(
		owners,
		known_places,
		public_places,
		home_places,
		residents,
		errors,
	)
	var home_owners: Dictionary = {}
	for home_name_value: Variant in home_places:
		var home_name := String(home_name_value)
		if owners.has(home_name):
			home_owners[home_name] = owners.get(home_name)
	var announcements_value: Variant = state.get("announcements")
	if not announcements_value is Array:
		errors.append("世界存档 announcements 必须是数组")
	var announcements := _validate_saved_announcements(
		announcements_value as Array if announcements_value is Array else [],
		errors,
	)
	var conversations_value: Variant = state.get("conversations")
	if not conversations_value is Array:
		errors.append("世界存档 conversations 必须是数组")
	var conversations := _validate_saved_conversations(
		conversations_value as Array if conversations_value is Array else [],
		residents,
		player_avatar,
		errors,
	)
	var event_log_value: Variant = state.get("eventLog")
	if not event_log_value is Array:
		errors.append("世界存档 eventLog 必须是数组")
	var event_log := _validate_saved_event_log(
		event_log_value as Array if event_log_value is Array else [],
		residents,
		known_places,
		errors,
	)
	_validate_conversation_links(residents, player_avatar, conversations, errors)
	var sequences_value: Variant = state.get("sequences")
	if not sequences_value is Dictionary:
		errors.append("世界存档 sequences 必须是对象")
	var sequences := sequences_value as Dictionary if sequences_value is Dictionary else {}
	_validate_exact_keys(sequences, ["event", "announcement", "conversation", "worldRevision"], "世界存档 sequences", errors)
	for key in ["event", "announcement", "conversation", "worldRevision"]:
		if _nonnegative_int_or_minus_one(sequences.get(key)) < 0:
			errors.append("世界存档序号不能为负数：%s" % key)
	_validate_sequence_floor(
		"announcement",
		_nonnegative_int_or_minus_one(sequences.get("announcement")),
		_max_sequence(announcements, "announcement_id", "announcement-"),
		errors,
	)
	_validate_sequence_floor(
		"conversation",
		_nonnegative_int_or_minus_one(sequences.get("conversation")),
		_max_sequence((conversations as Dictionary).values(), "conversationId", "conversation-"),
		errors,
	)
	_validate_sequence_floor(
		"event",
		_nonnegative_int_or_minus_one(sequences.get("event")),
		maxi(
			_max_pending_event_sequence(residents),
			_max_event_log_sequence(event_log),
		),
		errors,
	)
	_validate_sequence_floor(
		"worldRevision",
		_nonnegative_int_or_minus_one(sequences.get("worldRevision")),
		_max_event_log_world_revision(event_log),
		errors,
	)
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	return {
		"ok": true,
		# 旧存档可以含铺面归属，但恢复后只保留住家归属。铺面职责由
		# 职业岗位从当前居民数据重建。
		"owners": home_owners,
		"announcements": announcements,
		"conversations": conversations,
		"eventLog": event_log,
		"sequences": sequences.duplicate(true),
	}


static func _validate_saved_event_log(
	values: Array,
	residents: Dictionary,
	known_places: Dictionary,
	errors: Array[String],
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var ids := {}
	var previous_event_minute := -1
	var previous_event_sequence := 0
	var previous_world_revision := -1
	if values.size() > 200:
		errors.append("世界存档 eventLog 最多保留 200 条")
	for index in values.size():
		if not values[index] is Dictionary:
			errors.append("世界存档 eventLog[%d] 必须是对象" % index)
			continue
		var item := values[index] as Dictionary
		_validate_exact_keys(
			item,
			[
				"eventId",
				"kind",
				"time",
				"worldRevision",
				"residentId",
				"residentName",
				"placeName",
				"payload",
			],
			"世界存档 eventLog[%d]" % index,
			errors,
		)
		var event_id := _string_or_empty(item.get("eventId"))
		if not item.get("eventId") is String:
			errors.append("世界存档 eventLog.eventId 必须是文本")
		var kind := _string_or_empty(item.get("kind"))
		var event_sequence := _event_sequence_from_id(event_id, kind)
		if event_sequence <= 0 or ids.has(event_id):
			errors.append("世界存档 eventLog 编号格式无效或重复：%s" % event_id)
		ids[event_id] = true
		if not item.get("kind") is String:
			errors.append("世界存档 eventLog.kind 必须是文本：%s" % event_id)
		if kind not in PUBLIC_EVENT_KINDS:
			errors.append("世界存档 eventLog.kind 不受支持：%s" % event_id)
		_append_time_errors(
			item.get("time"),
			"世界存档 eventLog[%d].time" % index,
			errors,
		)
		var event_minute := _absolute_minute(item.get("time"))
		if (
			previous_event_minute >= 0
			and event_minute >= 0
			and event_minute < previous_event_minute
		):
			errors.append("世界存档 eventLog 必须按发生时间排列：%s" % event_id)
		if (
			previous_event_sequence > 0
			and event_sequence > 0
			and event_sequence <= previous_event_sequence
		):
			errors.append("世界存档 eventLog 必须按事件编号稳定排列：%s" % event_id)
		if (
			typeof(item.get("worldRevision")) != TYPE_INT
			or int(item.get("worldRevision", -1)) < 0
		):
			errors.append("世界存档 eventLog.worldRevision 无效：%s" % event_id)
		var world_revision := (
			int(item.get("worldRevision"))
			if typeof(item.get("worldRevision")) == TYPE_INT
			else -1
		)
		if (
			previous_world_revision >= 0
			and world_revision >= 0
			and world_revision < previous_world_revision
		):
			errors.append("世界存档 eventLog 的世界版本不能倒退：%s" % event_id)
		if not item.get("payload") is Dictionary:
			errors.append("世界存档 eventLog.payload 必须是对象：%s" % event_id)
		var resident_id := _string_or_empty(item.get("residentId"))
		if not item.get("residentId") is String:
			errors.append("世界存档 eventLog.residentId 必须是文本：%s" % event_id)
		if not resident_id.is_empty() and not residents.has(resident_id):
			errors.append("世界存档 eventLog 引用未知居民：%s" % resident_id)
		var resident_name := _string_or_empty(item.get("residentName"))
		if not item.get("residentName") is String:
			errors.append("世界存档 eventLog.residentName 必须是文本：%s" % event_id)
		elif resident_id.is_empty() and not resident_name.is_empty():
			errors.append(
				"世界存档 eventLog 没有居民 ID 却保存了居民姓名：%s"
				% event_id
			)
		elif not resident_id.is_empty() and resident_name.is_empty():
			errors.append(
				"世界存档 eventLog 居民姓名不能为空：%s" % event_id
			)
		# eventLog 是发生当时的历史快照。居民补位会复用住宅席位
		# 的稳定 residentId，但不应把旧事件的 residentName 改成新居民。
		# 因此这里只校验席位存在且历史姓名非空，不再要求与当前姓名相同。
		var place_name := _string_or_empty(item.get("placeName"))
		if not item.get("placeName") is String:
			errors.append("世界存档 eventLog.placeName 必须是文本：%s" % event_id)
		elif not place_name.is_empty() and not known_places.has(place_name):
			errors.append("世界存档 eventLog 引用未知地点：%s" % place_name)
		result.append(item.duplicate(true))
		if event_minute >= 0:
			previous_event_minute = event_minute
		if event_sequence > 0:
			previous_event_sequence = event_sequence
		if world_revision >= 0:
			previous_world_revision = world_revision
	return result


static func _max_event_log_sequence(values: Array[Dictionary]) -> int:
	var maximum := 0
	for item in values:
		maximum = maxi(
			maximum,
			_event_sequence_from_id(
				_string_or_empty(item.get("eventId")),
				_string_or_empty(item.get("kind")),
			),
		)
	return maximum


static func _event_sequence_from_id(event_id: String, kind: String) -> int:
	if kind == "resident_activity":
		return _sequence_from_id(event_id, "resident-activity:")
	return _sequence_from_id(event_id, "world-event-")


static func _max_event_log_world_revision(values: Array[Dictionary]) -> int:
	var maximum := 0
	for item in values:
		var revision_value: Variant = item.get("worldRevision")
		if typeof(revision_value) == TYPE_INT and int(revision_value) >= 0:
			maximum = maxi(maximum, int(revision_value))
	return maximum


static func _validate_saved_owners(
	owners: Dictionary,
	known_places: Dictionary,
	public_places: Dictionary,
	home_places: Dictionary,
	residents: Dictionary,
	errors: Array[String],
) -> void:
	var resident_ids: Array[String] = []
	var resident_by_home: Dictionary = {}
	for resident_id_value: Variant in residents:
		var resident_id := String(resident_id_value)
		resident_ids.append(resident_id)
		var resident := residents.get(resident_id, {}) as Dictionary
		var home_name := String(
			(resident.get("socialState", {}) as Dictionary).get("home", ""),
		).strip_edges()
		if not home_places.has(home_name):
			errors.append(
				"世界存档居民 %s 的住家不是合法住家：%s"
				% [resident_id, home_name],
			)
		elif resident_by_home.has(home_name):
			errors.append("世界存档住家被多名居民占用：%s" % home_name)
		else:
			resident_by_home[home_name] = resident_id
	for place_name_value: Variant in owners:
		if not place_name_value is String or not owners[place_name_value] is String:
			errors.append("世界存档归属的地点与居民 ID 必须是文本")
		var place_name := String(place_name_value) if place_name_value is String else ""
		if not known_places.has(place_name):
			errors.append("世界存档归属引用未知地点：%s" % place_name)
		elif public_places.has(place_name):
			errors.append("世界存档不能为公共地点分配归属人：%s" % place_name)
		var owner_value: Variant = owners.get(place_name)
		var owner_id := owner_value as String if owner_value is String else ""
		if not resident_ids.has(owner_id):
			errors.append("世界存档地点归属人不是当前居民：%s" % place_name)
	for home_name_value: Variant in resident_by_home:
		var home_name := String(home_name_value)
		var resident_id := String(resident_by_home[home_name])
		if (
			not owners.has(home_name)
			or String(owners.get(home_name, "")) != resident_id
		):
			errors.append("世界存档已入住住家缺少合法归属人：%s" % home_name)
	for place_name_value: Variant in home_places:
		var place_name := String(place_name_value)
		if owners.has(place_name) and not resident_by_home.has(place_name):
			errors.append("世界存档空置住家不能分配归属人：%s" % place_name)


static func _validate_saved_announcements(
	values: Array,
	errors: Array[String],
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var ids := {}
	var previous_announcement_minute := -1
	var previous_announcement_sequence := 0
	for index in values.size():
		if typeof(values[index]) != TYPE_DICTIONARY:
			errors.append("世界存档 announcements[%d] 必须是对象" % index)
			continue
		var announcement := values[index] as Dictionary
		_validate_exact_keys(announcement, ["announcement_id", "text", "time"], "世界存档 announcements[%d]" % index, errors)
		var announcement_id := String(announcement.get("announcement_id", "")) if announcement.get("announcement_id") is String else ""
		var announcement_sequence := _sequence_from_id(
			announcement_id,
			"announcement-",
		)
		if announcement_sequence <= 0 or ids.has(announcement_id):
			errors.append("世界存档公告编号缺失或重复：%s" % announcement_id)
		ids[announcement_id] = true
		if not _nonempty_string(announcement.get("text")):
			errors.append("世界存档公告内容不能为空")
		_append_time_errors(
			announcement.get("time"),
			"世界存档 announcements[%d].time" % index,
			errors,
		)
		var announcement_minute := _absolute_minute(announcement.get("time"))
		if (
			previous_announcement_minute >= 0
			and announcement_minute >= 0
			and announcement_minute < previous_announcement_minute
		):
			errors.append("世界存档公告必须按发布时间排列：%s" % announcement_id)
		if (
			previous_announcement_sequence > 0
			and announcement_sequence > 0
			and announcement_sequence <= previous_announcement_sequence
		):
			errors.append("世界存档公告必须按编号稳定排列：%s" % announcement_id)
		result.append(announcement.duplicate(true))
		if announcement_minute >= 0:
			previous_announcement_minute = announcement_minute
		if announcement_sequence > 0:
			previous_announcement_sequence = announcement_sequence
	return result


static func _validate_saved_conversations(
	values: Array,
	residents: Dictionary,
	player_avatar: Dictionary,
	errors: Array[String],
) -> Dictionary:
	var result := {}
	var people: Array = residents.keys()
	var player_id := _string_or_empty(player_avatar.get("residentId"))
	if player_id.is_empty():
		player_id = "player-avatar"
	people.append(player_id)
	var display_names := {}
	for resident_id_value: Variant in residents:
		var resident_id := str(resident_id_value)
		var resident_value: Variant = residents[resident_id_value]
		if not resident_value is Dictionary:
			continue
		var attributes_value: Variant = (resident_value as Dictionary).get("attributes")
		if attributes_value is Dictionary:
			display_names[resident_id] = _string_or_empty(
				(attributes_value as Dictionary).get("name")
			)
	display_names[player_id] = _string_or_empty(player_avatar.get("name"))
	for index in values.size():
		if typeof(values[index]) != TYPE_DICTIONARY:
			errors.append("世界存档 conversations[%d] 必须是对象" % index)
			continue
		var conversation := values[index] as Dictionary
		_validate_allowed_keys(
			conversation,
			[
				"conversationId", "participants", "initiator", "turns", "waitingFor",
				"status", "startedAt", "updatedAt", "placeName", "endReason", "endedAt",
				"medicalRequestId", "medicalTaskId",
			],
			"世界存档 conversations[%d]" % index,
			errors,
		)
		_validate_required_keys(
			conversation,
			[
				"conversationId",
				"participants",
				"initiator",
				"turns",
				"waitingFor",
				"status",
				"startedAt",
				"updatedAt",
				"endReason",
			],
			"世界存档 conversations[%d]" % index,
			errors,
		)
		var conversation_id := String(conversation.get("conversationId", "")) if conversation.get("conversationId") is String else ""
		if _sequence_from_id(conversation_id, "conversation-") <= 0 or result.has(conversation_id):
			errors.append("世界存档对话编号缺失或重复：%s" % conversation_id)
			continue
		var participants_value: Variant = conversation.get("participants")
		if not participants_value is Array:
			errors.append("世界存档对话参与者必须是数组：%s" % conversation_id)
		var participants := participants_value as Array if participants_value is Array else []
		if participants.size() != 2 or not participants.all(func(value: Variant) -> bool: return value is String and not String(value).strip_edges().is_empty()) or String(participants[0]) == String(participants[1]):
			errors.append("世界存档对话必须有两名不同参与者：%s" % conversation_id)
		for participant_value: Variant in participants:
			if not participant_value is String:
				errors.append("世界存档对话参与者必须是文本：%s" % conversation_id)
				continue
			if not people.has(participant_value):
				errors.append("世界存档对话引用未知人物：%s" % participant_value)
		if not conversation.get("initiator") is String or not participants.has(conversation.get("initiator")):
			errors.append("世界存档对话发起者不是参与者：%s" % conversation_id)
		var status := String(conversation.get("status", "")) if conversation.get("status") is String else ""
		if status not in ["active", "ended"]:
			errors.append("世界存档对话状态无效：%s" % conversation_id)
		var has_medical_request := conversation.has("medicalRequestId")
		var has_medical_task := conversation.has("medicalTaskId")
		if has_medical_request != has_medical_task:
			errors.append("世界存档医患对话必须同时保存请求和任务编号：%s" % conversation_id)
		elif has_medical_request and (
			not _nonempty_string(conversation.get("medicalRequestId"))
			or not _nonempty_string(conversation.get("medicalTaskId"))
		):
			errors.append("世界存档医患对话的请求或任务编号无效：%s" % conversation_id)
		if typeof(conversation.get("turns")) != TYPE_ARRAY:
			errors.append("世界存档对话轮次必须是数组：%s" % conversation_id)
		else:
			_validate_turns(
				conversation_id,
				conversation.get("turns", []) as Array,
				participants,
				_string_or_empty(conversation.get("initiator")),
				display_names,
				status,
				errors,
			)
		_append_time_errors(
			conversation.get("startedAt"),
			"世界存档 conversations[%d].startedAt" % index,
			errors,
		)
		_append_time_errors(
			conversation.get("updatedAt"),
			"世界存档 conversations[%d].updatedAt" % index,
			errors,
		)
		var started_minute := _absolute_minute(conversation.get("startedAt"))
		var updated_minute := _absolute_minute(conversation.get("updatedAt"))
		if (
			started_minute >= 0
			and updated_minute >= 0
			and updated_minute < started_minute
		):
			errors.append("世界存档对话更新时间早于开始时间：%s" % conversation_id)
		if status == "active":
			if not conversation.get("waitingFor") is String or not participants.has(conversation.get("waitingFor")):
				errors.append("活动对话等待对象不是参与者：%s" % conversation_id)
			var turns_value: Variant = conversation.get("turns")
			if turns_value is Array and not (turns_value as Array).is_empty():
				var last_turn_value: Variant = (turns_value as Array).back()
				if last_turn_value is Dictionary:
					var last_speaker := _string_or_empty(
						(last_turn_value as Dictionary).get(
							"speaker_resident_id"
						)
					)
					var expected_waiting_for := _other_participant(
						participants,
						last_speaker,
					)
					if (
						not expected_waiting_for.is_empty()
						and conversation.get("waitingFor")
						!= expected_waiting_for
					):
						errors.append(
							"活动对话必须等待最后发言者之外的参与者：%s"
							% conversation_id
						)
			if conversation.get("endReason") != null or conversation.has("endedAt"):
				errors.append("活动对话不能保存结束状态：%s" % conversation_id)
		elif status == "ended":
			_validate_required_keys(
				conversation,
				["endedAt"],
				"世界存档 conversations[%d]" % index,
				errors,
			)
			_append_time_errors(
				conversation.get("endedAt"),
				"世界存档 conversations[%d].endedAt" % index,
				errors,
			)
			var ended_minute := _absolute_minute(conversation.get("endedAt"))
			if (
				updated_minute >= 0
				and ended_minute >= 0
				and ended_minute < updated_minute
			):
				errors.append("世界存档对话结束时间早于更新时间：%s" % conversation_id)
			if conversation.get("waitingFor") != null or not _nonempty_string(conversation.get("endReason")):
				errors.append("已结束对话缺少完整结束状态：%s" % conversation_id)
		result[conversation_id] = conversation.duplicate(true)
	return result


static func _validate_conversation_links(
	residents: Dictionary,
	player_avatar: Dictionary,
	conversations: Dictionary,
	errors: Array[String],
) -> void:
	var display_names := _person_display_names(
		residents,
		player_avatar,
	)
	for resident_name_value: Variant in residents:
		var resident_value: Variant = residents[resident_name_value]
		if not resident_value is Dictionary:
			errors.append("世界存档居民状态必须为对象：%s" % str(resident_name_value))
			continue
		_validate_person_conversation_link(
			str(resident_name_value),
			resident_value as Dictionary,
			conversations,
			display_names,
			errors,
		)
	var avatar_id := _string_or_empty(player_avatar.get("residentId"))
	if avatar_id.is_empty():
		avatar_id = "player-avatar"
	_validate_person_conversation_link(
		avatar_id,
		player_avatar,
		conversations,
		display_names,
		errors,
	)
	for conversation_id_value: Variant in conversations:
		var conversation_id := str(conversation_id_value)
		var conversation_value: Variant = conversations[conversation_id_value]
		if not conversation_value is Dictionary:
			continue
		var conversation := conversation_value as Dictionary
		if _string_or_empty(conversation.get("status")) != "active":
			continue
		var participants_value: Variant = conversation.get("participants")
		if not participants_value is Array:
			continue
		for participant_value: Variant in participants_value as Array:
			if not participant_value is String:
				continue
			var participant_name := participant_value as String
			var person_value: Variant = residents.get(participant_name)
			var person := person_value as Dictionary if person_value is Dictionary else {}
			if participant_name == avatar_id:
				person = player_avatar
			if _string_or_empty(person.get("conversationId")) != conversation_id:
				errors.append("活动对话与人物状态不一致：%s" % conversation_id)


static func _validate_person_conversation_link(
	person_name: String,
	person: Dictionary,
	conversations: Dictionary,
	display_names: Dictionary,
	errors: Array[String],
) -> void:
	var conversation_id_value: Variant = person.get("conversationId")
	if not conversation_id_value is String:
		errors.append("人物 conversationId 必须是文本：%s" % person_name)
		return
	if not person.has("conversation"):
		errors.append("人物缺少 conversation 字段：%s" % person_name)
		return
	var conversation_id := String(conversation_id_value)
	if conversation_id.is_empty():
		if person.get("conversation") != null:
			errors.append("人物没有活动对话却保存了对话快照：%s" % person_name)
		return
	if not conversations.has(conversation_id):
		errors.append("人物引用了不存在的对话：%s" % person_name)
		return
	var conversation := conversations[conversation_id] as Dictionary
	var participants_value: Variant = conversation.get("participants")
	var participants := participants_value as Array if participants_value is Array else []
	if _string_or_empty(conversation.get("status")) != "active" or not participants.has(person_name):
		errors.append("人物引用的对话不是自己的活动对话：%s" % person_name)
	if typeof(person.get("conversation")) != TYPE_DICTIONARY:
		errors.append("活动对话人物缺少对话快照：%s" % person_name)
	else:
		var snapshot := person.get("conversation") as Dictionary
		var snapshot_fields := [
			"conversation_id", "with_resident_id", "with", "turns",
		]
		if snapshot.has("medical_context"):
			snapshot_fields.append("medical_context")
		if snapshot.has("traveler_relationship"):
			snapshot_fields.append("traveler_relationship")
		_validate_exact_keys(snapshot, snapshot_fields, "人物 %s 的对话快照" % person_name, errors)
		if _string_or_empty(snapshot.get("conversation_id")) != conversation_id:
			errors.append("人物对话快照编号与活动对话不一致：%s" % person_name)
		var other_id := ""
		for participant_value: Variant in participants:
			if participant_value is String and participant_value != person_name:
				other_id = participant_value
		if (
			not snapshot.get("with_resident_id") is String
			or _string_or_empty(snapshot.get("with_resident_id")) != other_id
		):
			errors.append("人物对话快照对象与活动对话不一致：%s" % person_name)
		var expected_name := _string_or_empty(display_names.get(other_id))
		if (
			not snapshot.get("with") is String
			or expected_name.is_empty()
			or _string_or_empty(snapshot.get("with")) != expected_name
		):
			errors.append("人物对话快照对象姓名与活动对话不一致：%s" % person_name)
		if (
			not snapshot.get("turns") is Array
			or snapshot.get("turns") != conversation.get("turns")
		):
			errors.append("人物对话快照轮次与活动对话不一致：%s" % person_name)
		if snapshot.has("medical_context"):
			var medical_value: Variant = snapshot.get("medical_context")
			if medical_value != null and not medical_value is Dictionary:
				errors.append("人物医患对话快照必须是对象或 null：%s" % person_name)
			elif medical_value is Dictionary and not conversation.has("medicalRequestId"):
				errors.append("普通对话不能保存医患上下文：%s" % person_name)
			elif medical_value is Dictionary and _string_or_empty(
				(medical_value as Dictionary).get("request_id"),
			) != _string_or_empty(conversation.get("medicalRequestId")):
				errors.append("人物医患对话快照请求编号不一致：%s" % person_name)
		if snapshot.has("traveler_relationship"):
			_validate_traveler_relationship_snapshot(
				snapshot.get("traveler_relationship"),
				"人物 %s 的旅行者关系快照" % person_name,
				errors,
			)


static func _validate_traveler_relationship_snapshot(
	value: Variant,
	label: String,
	errors: Array[String],
) -> void:
	if not value is Dictionary:
		errors.append("%s 必须是对象" % label)
		return
	var relationship := value as Dictionary
	_validate_exact_keys(
		relationship,
		[
			"affinity", "affinity_label", "familiarity_level",
			"familiarity_label", "conversation_count", "attack_count", "last_change",
		],
		label,
		errors,
	)
	var affinity: Variant = relationship.get("affinity")
	if typeof(affinity) != TYPE_INT or int(affinity) < 0 or int(affinity) > 100:
		errors.append("%s.affinity 必须是 0 到 100 的整数" % label)
	for field_name in ["affinity_label", "familiarity_label", "last_change"]:
		if typeof(relationship.get(field_name)) != TYPE_STRING:
			errors.append("%s.%s 必须是文本" % [label, field_name])
	var familiarity_level: Variant = relationship.get("familiarity_level")
	if (
		typeof(familiarity_level) != TYPE_INT
		or int(familiarity_level) < 0
		or int(familiarity_level) > 5
	):
		errors.append("%s.familiarity_level 必须是 0 到 5 的整数" % label)
	for field_name in ["conversation_count", "attack_count"]:
		var count: Variant = relationship.get(field_name)
		if typeof(count) != TYPE_INT or int(count) < 0:
			errors.append("%s.%s 必须是非负整数" % [label, field_name])


static func _validate_turns(
	conversation_id: String,
	turns: Array,
	participants: Array,
	initiator: String,
	display_names: Dictionary,
	conversation_status: String,
	errors: Array[String],
) -> void:
	if turns.is_empty():
		errors.append("世界存档对话至少需要一轮：%s" % conversation_id)
	elif (
		turns[0] is Dictionary
		and _string_or_empty(
			(turns[0] as Dictionary).get("speaker_resident_id")
		) != initiator
	):
		errors.append("世界存档对话首轮必须由发起者说话：%s" % conversation_id)
	for index in turns.size():
		var turn_value: Variant = turns[index]
		if not turn_value is Dictionary:
			errors.append("世界存档对话轮次必须是对象：%s[%d]" % [conversation_id, index])
			continue
		var turn := turn_value as Dictionary
		_validate_exact_keys(turn, ["turn_id", "speaker_resident_id", "speaker", "say", "narration", "photos"], "世界存档对话轮次 %s[%d]" % [conversation_id, index], errors)
		if typeof(turn.get("turn_id")) != TYPE_INT or int(turn.get("turn_id")) != index + 1:
			errors.append("世界存档对话轮次编号必须从 1 连续递增：%s" % conversation_id)
		var speaker_id := _string_or_empty(turn.get("speaker_resident_id"))
		if not participants.has(speaker_id):
			errors.append("世界存档对话轮次引用非参与者：%s" % conversation_id)
		elif _string_or_empty(turn.get("speaker")) != _string_or_empty(display_names.get(speaker_id)):
			errors.append("世界存档对话轮次的 ID 与显示名称不一致：%s" % conversation_id)
		if typeof(turn.get("say")) != TYPE_STRING or typeof(turn.get("narration")) != TYPE_STRING:
			errors.append("世界存档对话轮次文本字段无效：%s" % conversation_id)
		elif String(turn.get("say", "")).strip_edges().is_empty() and String(turn.get("narration", "")).strip_edges().is_empty():
			errors.append("世界存档对话轮次内容不能为空：%s" % conversation_id)
		if (
			index > 0
			and turns[index - 1] is Dictionary
			and turn.get("speaker_resident_id")
			== (turns[index - 1] as Dictionary).get("speaker_resident_id")
			and not _is_terminal_action_only_turn(
				turn,
				index,
				turns.size(),
				conversation_status,
			)
		):
			errors.append("世界存档对话轮次必须由双方交替发言：%s" % conversation_id)
		if typeof(turn.get("photos")) != TYPE_ARRAY:
			errors.append("世界存档对话轮次照片必须是数组：%s" % conversation_id)
		else:
			for photo_index in (turn.get("photos") as Array).size():
				var photo_value: Variant = (turn.get("photos") as Array)[photo_index]
				if not photo_value is Dictionary:
					errors.append("世界存档对话照片必须是对象：%s[%d]" % [conversation_id, photo_index])
					continue
				var photo := photo_value as Dictionary
				_validate_exact_keys(photo, ["ref", "mime_type"], "世界存档对话照片 %s[%d]" % [conversation_id, photo_index], errors)
				if not _nonempty_string(photo.get("ref")) or not _nonempty_string(photo.get("mime_type")):
					errors.append("世界存档对话照片引用无效：%s[%d]" % [conversation_id, photo_index])


static func _is_terminal_action_only_turn(
	turn: Dictionary,
	index: int,
	turn_count: int,
	conversation_status: String,
) -> bool:
	return (
		conversation_status == "ended"
		and index == turn_count - 1
		and _string_or_empty(turn.get("say")).strip_edges().is_empty()
		and not _string_or_empty(turn.get("narration")).strip_edges().is_empty()
		and turn.get("photos") is Array
		and (turn.get("photos") as Array).is_empty()
	)


static func _other_participant(
	participants: Array,
	person_name: String,
) -> String:
	if person_name.is_empty() or not participants.has(person_name):
		return ""
	for participant_value: Variant in participants:
		if participant_value is String and participant_value != person_name:
			return participant_value
	return ""


static func _person_display_names(
	residents: Dictionary,
	player_avatar: Dictionary,
) -> Dictionary:
	var result := {}
	for resident_id_value: Variant in residents:
		if not resident_id_value is String:
			continue
		var resident_value: Variant = residents.get(resident_id_value)
		if not resident_value is Dictionary:
			continue
		var attributes_value: Variant = (
			resident_value as Dictionary
		).get("attributes")
		if attributes_value is Dictionary:
			result[resident_id_value] = _string_or_empty(
				(attributes_value as Dictionary).get("name")
			)
	var avatar_id := _string_or_empty(player_avatar.get("residentId"))
	if avatar_id.is_empty():
		avatar_id = "player-avatar"
	result[avatar_id] = _string_or_empty(player_avatar.get("name"))
	return result


static func _validate_sequence_floor(
	name: String,
	actual: int,
	required: int,
	errors: Array[String],
) -> void:
	if actual >= 0 and actual < required:
		errors.append("世界存档序号 %s 小于已保存对象的最大编号 %d" % [name, required])


static func _max_sequence(
	values: Array,
	id_key: String,
	prefix: String,
) -> int:
	var result := 0
	for value: Variant in values:
		if not value is Dictionary:
			continue
		var id := _string_or_empty((value as Dictionary).get(id_key))
		result = maxi(result, _sequence_from_id(id, prefix))
	return result


static func _sequence_from_id(id: String, prefix: String) -> int:
	return SAVE_SCALARS_UTIL.sequence_from_id(id, prefix)


static func _max_pending_event_sequence(residents: Dictionary) -> int:
	var values: Array = []
	for resident_value: Variant in residents.values():
		if not resident_value is Dictionary:
			continue
		var queue_value: Variant = (resident_value as Dictionary).get("eventQueue")
		if queue_value is Array:
			values.append_array(queue_value as Array)
	return _max_sequence(values, "event_id", "world-event-")


static func _validate_exact_keys(
	value: Dictionary,
	expected: Array,
	label: String,
	errors: Array[String],
) -> void:
	_validate_allowed_keys(value, expected, label, errors)
	_validate_required_keys(value, expected, label, errors)


static func _validate_allowed_keys(
	value: Dictionary,
	allowed: Array,
	label: String,
	errors: Array[String],
) -> void:
	for key_value: Variant in value:
		if not key_value is String or not allowed.has(key_value):
			errors.append("%s 包含未知字段：%s" % [label, str(key_value)])


static func _validate_required_keys(
	value: Dictionary,
	required: Array,
	label: String,
	errors: Array[String],
) -> void:
	for key_value: Variant in required:
		if not value.has(key_value):
			errors.append("%s 缺少字段：%s" % [label, str(key_value)])


static func _append_time_errors(
	value: Variant,
	label: String,
	errors: Array[String],
) -> void:
	errors.append_array(SAVE_CODEC.validate_time_snapshot(value, label))


static func _absolute_minute(value: Variant) -> int:
	if not value is Dictionary:
		return -1
	var snapshot := value as Dictionary
	if not SAVE_CODEC.validate_time_snapshot(snapshot).is_empty():
		return -1
	var clock := snapshot.get("clock") as String
	return (
		(int(snapshot.get("day")) - 1) * 24 * 60
		+ int(clock.substr(0, 2)) * 60
		+ int(clock.substr(3, 2))
	)


static func _nonempty_string(value: Variant) -> bool:
	return value is String and not String(value).strip_edges().is_empty()


static func _string_or_empty(value: Variant) -> String:
	return value as String if value is String else ""


static func _nonnegative_int_or_minus_one(value: Variant) -> int:
	if typeof(value) != TYPE_INT or value < 0:
		return -1
	return value


static func validate_restore_references(
	social_runtime: RefCounted,
	bulletin_runtime: RefCounted,
	world_data: Dictionary,
	residents: Dictionary,
	player_avatar: Dictionary,
	conversations: Variant,
	event_log: Array,
	event_sequence: int,
	animal_facts: Dictionary,
) -> Array[String]:
	var errors: Array[String] = []
	var resident_ids := {}
	for resident_value: Variant in residents:
		resident_ids[String(resident_value)] = true
	var player_id := String(
		player_avatar.get("residentId", "")
	).strip_edges()
	if player_id.is_empty():
		player_id = DEFAULT_PLAYER_AVATAR_ID
	var people := resident_ids.duplicate()
	people[player_id] = true
	var conversation_ids := {}
	if conversations is Dictionary:
		for conversation_id_value: Variant in conversations:
			conversation_ids[String(conversation_id_value)] = true
	elif conversations is Array:
		for conversation_value: Variant in conversations:
			var conversation := conversation_value as Dictionary
			conversation_ids[String(
				conversation.get("conversationId", "")
			)] = true
	var bulletin_snapshot := bulletin_runtime.create_save_snapshot() as Dictionary
	var announcement_ids := {}
	var announcements_by_id := {}
	for announcement_value: Variant in bulletin_snapshot.get(
		"announcements",
		[],
	) as Array:
		var announcement := announcement_value as Dictionary
		var announcement_id := String(
			announcement.get("announcement_id", ""),
		)
		announcement_ids[announcement_id] = true
		announcements_by_id[announcement_id] = announcement
	for matter_value: Variant in social_runtime.list_matters(true,) as Array:
		var matter := matter_value as Dictionary
		var matter_id := String(matter.get("matter_id", ""))
		var source_state_ref := (
			matter.get("source_state_ref", {}) as Dictionary
		)
		if String(
			source_state_ref.get("source_kind", "")
		) == "animal_attention":
			var source_animal_id := String(
				source_state_ref.get("source_id", "")
			)
			if not animal_facts.has(source_animal_id):
				errors.append(
					"社会事项 %s 引用未知动物：%s"
					% [matter_id, source_animal_id]
				)
		var creator_id := String(matter.get("creator_id", ""))
		if not creator_id.is_empty() and not people.has(creator_id):
			errors.append(
				"社会事项 %s 引用未知创建者：%s"
				% [matter_id, creator_id]
			)
		var place_id := String(matter.get("place_id", ""))
		if (
			not place_id.is_empty()
			and not RESTORE_LAYOUT.world_data_has_place(world_data, place_id)
		):
			errors.append(
				"社会事项 %s 引用未知地点：%s"
				% [matter_id, place_id]
			)
		_validate_goal_references(
			matter.get("source_action_goal", {}) as Dictionary,
			"社会事项 %s 的来源目标" % matter_id,
			world_data,
			people,
			conversation_ids,
			announcement_ids,
			errors,
		)
		for awareness_id: Variant in (
			matter.get("awareness", {}) as Dictionary
		):
			if not people.has(String(awareness_id)):
				errors.append(
					"社会事项 %s 引用未知知情者：%s"
					% [matter_id, String(awareness_id)]
				)
		for participant_id: Variant in (
			matter.get("participants", {}) as Dictionary
		):
			if not resident_ids.has(String(participant_id)):
				errors.append(
					"社会事项 %s 引用未知参与居民：%s"
					% [matter_id, String(participant_id)]
				)
			var participant := (
				(matter.get("participants", {}) as Dictionary).get(
					participant_id,
					{},
				) as Dictionary
			)
			_validate_goal_references(
				participant.get("action_goal", {}) as Dictionary,
				"社会事项 %s 的参与目标" % matter_id,
				world_data,
				people,
				conversation_ids,
				announcement_ids,
				errors,
			)
		for candidate_value: Variant in matter.get(
			"fixed_candidates",
			[],
		) as Array:
			var candidate := candidate_value as Dictionary
			var candidate_id := String(
				candidate.get("resident_id", "")
			)
			if not resident_ids.has(candidate_id):
				errors.append(
					"社会事项 %s 引用未知回应候选：%s"
					% [matter_id, candidate_id]
				)
			for option_value: Variant in candidate.get(
				"options",
				[],
			) as Array:
				_validate_goal_references(
					(option_value as Dictionary).get(
						"action_goal",
						{},
					) as Dictionary,
					"社会事项 %s 的候选目标" % matter_id,
					world_data,
					people,
					conversation_ids,
					announcement_ids,
					errors,
				)
	var knowledge_by_resident := bulletin_snapshot.get(
		"knowledge_by_resident",
		{},
	) as Dictionary
	for resident_value: Variant in knowledge_by_resident:
		if not people.has(String(resident_value)):
			errors.append(
				"社区公告知情记录引用未知居民：%s"
				% String(resident_value)
			)
		for knowledge_value: Variant in (
			knowledge_by_resident.get(resident_value, {}) as Dictionary
		).values():
			var knowledge := knowledge_value as Dictionary
			if (
				String(knowledge.get("acquired_via", "")) == "relayed"
				and not people.has(String(knowledge.get("source_id", "")))
			):
				errors.append(
					"社区公告转告记录引用未知居民：%s"
					% String(knowledge.get("source_id", ""))
				)
	for announcement_value: Variant in bulletin_snapshot.get(
		"announcements",
		[],
	) as Array:
		var announcement := announcement_value as Dictionary
		var announcement_id := String(
			announcement.get("announcement_id", "")
		)
		var publisher_id := String(
			announcement.get("publisher_id", "")
		)
		if (
			publisher_id not in [
				"legacy-player",
				SYSTEM_BULLETIN_PUBLISHER_ID,
			]
			and not people.has(publisher_id)
		):
			errors.append(
				"社区公告 %s 引用未知发布者：%s"
				% [announcement_id, publisher_id]
			)
		var matter_id := String(announcement.get("matter_id", ""))
		if (
			not matter_id.is_empty()
			and (
				social_runtime.get_matter(matter_id,) as Dictionary
			).is_empty()
		):
				errors.append(
					"社区公告 %s 引用不存在的社会事项：%s"
					% [announcement_id, matter_id]
				)
	_validate_announcement_references(
		announcements_by_id,
		knowledge_by_resident,
		residents,
		event_log,
		event_sequence,
		social_runtime,
		errors,
	)
	return errors


static func _validate_announcement_references(
	announcements_by_id: Dictionary,
	knowledge_by_resident: Dictionary,
	residents: Dictionary,
	event_log: Array,
	event_sequence: int,
	social_runtime: RefCounted,
	errors: Array[String],
) -> void:
	for announcement_id_value: Variant in announcements_by_id:
		var announcement_id := String(announcement_id_value)
		var announcement := (
			announcements_by_id.get(announcement_id, {}) as Dictionary
		)
		var publish_event_id := String(
			announcement.get("publish_event_id", ""),
		)
		if publish_event_id.is_empty():
			continue
		var publish_sequence := SAVE_CODEC.sequence_from_prefixed_id(
			publish_event_id,
			"world-event-",
		)
		if publish_sequence <= 0 or publish_sequence > event_sequence:
			errors.append(
				"社区公告 %s 的发布事件编号无效" % announcement_id
			)
		var matter_id := String(announcement.get("matter_id", ""))
		var matter := (
			social_runtime.get_matter(matter_id) as Dictionary
			if not matter_id.is_empty()
			else {}
		)
		for resident_id_value: Variant in residents:
			var resident_id := String(resident_id_value)
			var resident_knowledge := (
				knowledge_by_resident.get(resident_id, {}) as Dictionary
			)
			var knowledge := (
				resident_knowledge.get(announcement_id, {}) as Dictionary
			)
			var is_publisher := resident_id == String(
				announcement.get("publisher_id", ""),
			)
			var expected_source := (
				resident_id if is_publisher else announcement_id
			)
			var expected_via := (
				"publisher" if is_publisher else "announcement_broadcast"
			)
			if (
				String(knowledge.get("acquired_via", "")) != expected_via
				or String(knowledge.get("source_id", "")) != expected_source
				or int(knowledge.get("updated_at", -1))
				!= int(announcement.get("published_at", -2))
			):
				errors.append(
					"居民 %s 缺少公告 %s 的全局知情记录"
					% [resident_id, announcement_id]
				)
			if (
				not matter_id.is_empty()
				and not (matter.get("awareness", {}) as Dictionary).has(
					resident_id,
				)
			):
				errors.append(
					"居民 %s 缺少公告事项 %s 的知情记录"
					% [resident_id, matter_id]
				)
	var logged_announcements := {}
	var announcements_by_publish_event_id := {}
	for announcement_id_value: Variant in announcements_by_id:
		var announcement := (
			announcements_by_id.get(announcement_id_value, {}) as Dictionary
		)
		var publish_event_id := String(
			announcement.get("publish_event_id", ""),
		)
		if not publish_event_id.is_empty():
			announcements_by_publish_event_id[publish_event_id] = announcement
	for record_value: Variant in event_log:
		var record := record_value as Dictionary
		var payload := record.get("payload", {}) as Dictionary
		var record_event_id := String(record.get("eventId", ""))
		var announcement_for_event := (
			announcements_by_publish_event_id.get(
				record_event_id,
				{},
			) as Dictionary
		)
		if String(payload.get("type", "")) != "公告发布":
			if not announcement_for_event.is_empty():
				errors.append(
					"公共发布记录与公告不一致：%s"
					% String(
						announcement_for_event.get(
							"announcement_id",
							"",
							)
						)
				)
			continue
		var announcement_id := String(
			payload.get("announcement_id", ""),
		)
		if logged_announcements.has(announcement_id):
			errors.append("同一公告存在多条公共发布记录：%s" % announcement_id)
			continue
		logged_announcements[announcement_id] = true
		var announcement := (
			announcements_by_id.get(announcement_id, {}) as Dictionary
		)
		if announcement.is_empty():
			errors.append(
				"公共发布记录引用不存在的公告：%s" % announcement_id,
			)
			continue
		var stored_event_id := String(
			announcement.get("publish_event_id", ""),
		)
		if (
			String(record.get("kind", "")) != "world_event"
			or not _announcement_publish_payload_keys_valid(payload)
			or not String(record.get("residentId", "")).is_empty()
			or not String(record.get("residentName", "")).is_empty()
			or not String(record.get("placeName", "")).is_empty()
			or record.get("time") != payload.get("time")
			or String(record.get("eventId", ""))
			!= String(payload.get("event_id", ""))
			or not _announcement_event_content_matches(
				payload,
				announcement,
			)
			or (
				not stored_event_id.is_empty()
				and String(payload.get("event_id", "")) != stored_event_id
			)
		):
			errors.append("公共发布记录与公告不一致：%s" % announcement_id)
	for resident_id_value: Variant in residents:
		var resident_id := String(resident_id_value)
		var resident := residents.get(resident_id, {}) as Dictionary
		for event_value: Variant in resident.get("eventQueue", []) as Array:
			var event := event_value as Dictionary
			if String(event.get("type", "")) != "公告发布":
				continue
			var announcement_id := String(
				event.get("announcement_id", ""),
			)
			var announcement := (
				announcements_by_id.get(announcement_id, {}) as Dictionary
			)
			if announcement.is_empty():
				errors.append(
					"居民 %s 的待交付公告引用不存在的公告：%s"
					% [resident_id, announcement_id],
				)
				continue
			if not _announcement_event_matches(event, announcement):
				errors.append(
					"居民 %s 的待交付公告与公告记录不一致：%s"
					% [resident_id, announcement_id]
				)


static func _announcement_event_matches(
	event: Dictionary,
	announcement: Dictionary,
) -> bool:
	var stored_event_id := String(
		announcement.get("publish_event_id", ""),
	)
	return (
		(
			stored_event_id.is_empty()
			or String(event.get("event_id", "")) == stored_event_id
		)
		and _announcement_event_content_matches(event, announcement)
	)


static func _announcement_publish_payload_keys_valid(
	payload: Dictionary,
) -> bool:
	var required := [
		"type",
		"announcement_id",
		"publisher_resident_id",
		"text",
		"matter_id",
		"time",
		"event_id",
	]
	var allowed := required.duplicate()
	allowed.append_array([
		"publisher_name",
		"announcement_priority",
		"scheduled_absolute_minute",
		"scheduled_time_label",
	])
	for key: Variant in payload:
		if not key is String or key not in allowed:
			return false
	for key: String in required:
		if not payload.has(key):
			return false
	return true


static func _announcement_event_content_matches(
	event: Dictionary,
	announcement: Dictionary,
) -> bool:
	var matter_id := String(announcement.get("matter_id", ""))
	var expected_matter: Variant = matter_id if not matter_id.is_empty() else null
	return (
		String(event.get("announcement_id", ""))
		== String(announcement.get("announcement_id", ""))
		and String(event.get("publisher_resident_id", ""))
		== String(announcement.get("publisher_id", ""))
		and String(event.get("text", ""))
		== String(announcement.get("text", ""))
		and event.get("matter_id") == expected_matter
		and event.get("time") == announcement.get("time")
	)


static func _validate_goal_references(
	action_goal: Dictionary,
	label: String,
	world_data: Dictionary,
	people: Dictionary,
	conversation_ids: Dictionary,
	announcement_ids: Dictionary,
	errors: Array[String],
) -> void:
	if action_goal.is_empty():
		return
	var capability_id := String(
		action_goal.get("capability_id", "")
	)
	var target_refs := action_goal.get(
		"target_refs",
		{},
	) as Dictionary
	var place_id := String(target_refs.get("place_id", ""))
	if (
		not place_id.is_empty()
		and not RESTORE_LAYOUT.world_data_has_place(world_data, place_id)
	):
		errors.append("%s 引用未知地点：%s" % [label, place_id])
	var resident_id := String(target_refs.get("resident_id", ""))
	if not resident_id.is_empty() and not people.has(resident_id):
		errors.append("%s 引用未知居民：%s" % [label, resident_id])
	if capability_id == "world.perform_activity":
		var activity_id := String(
			target_refs.get("activity_id", "")
		)
		if not RESTORE_LAYOUT.world_data_has_activity_at_place(
			world_data,
			activity_id,
			place_id,
		):
			errors.append("%s 引用无效地点活动" % label)
	elif capability_id == "world.reply_conversation":
		var conversation_id := String(
			target_refs.get("conversation_id", "")
		)
		if not conversation_ids.has(conversation_id):
			errors.append("%s 引用未知对话：%s" % [label, conversation_id])
	elif capability_id == "bulletin.read":
		var announcement_id := String(
			target_refs.get("announcement_id", "")
		)
		if not announcement_ids.has(announcement_id):
			errors.append("%s 引用未知公告：%s" % [label, announcement_id])
