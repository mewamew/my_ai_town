class_name AgentContractEvents
extends RefCounted
## AgentContract 拆分模块(批次C之4,纯搬运+跨模块调用改类前缀)。


static func _validate_events(events: Array, errors: Array[String]) -> void:
	var event_ids := {}
	for index in events.size():
		var path := "events[%d]" % index
		var value: Variant = events[index]
		if typeof(value) != TYPE_DICTIONARY:
			errors.append("%s 必须是对象" % path)
			continue
		var event := value as Dictionary
		AgentContractSocial._validate_optional_world_revision(event, path, errors)
		var event_id := AgentContract._require_non_empty_string(event, "event_id", "%s.event_id" % path, errors)
		if not event_id.is_empty() and event_ids.has(event_id):
			errors.append("%s.event_id 在本次事件中重复" % path)
		event_ids[event_id] = true
		var time := AgentContract._require_dictionary(event, "time", "%s.time" % path, errors)
		if not time.is_empty():
			AgentContractEnvironment._validate_time(time, "%s.time" % path, errors)
		var event_type := AgentContract._require_non_empty_string(event, "type", "%s.type" % path, errors)
		if not event_type.is_empty() and not AgentContract.EVENT_TYPES.has(event_type):
			errors.append("%s.type 不是合法事件类型" % path)
			continue
		_validate_event_fields(event, event_type, path, errors)


static func _validate_event_fields(
	event: Dictionary,
	event_type: String,
	path: String,
	errors: Array[String],
) -> void:
	if event_type == "冲突见闻":
		for field in ["conflict_id", "conflict_event_id", "conflict_event_type", "knowledge_kind", "summary"]:
			AgentContract._require_non_empty_string(event, field, "%s.%s" % [path, field], errors)
		return
	if event_type == "搭话" or event_type == "对方答话":
		AgentContract._require_non_empty_string(event, "conversation_id", "%s.conversation_id" % path, errors)
		AgentContractConversation._validate_turn(event.get("turn"), "%s.turn" % path, errors)
		if event.has("response_required") and typeof(event.get("response_required")) != TYPE_BOOL:
			errors.append("%s.response_required 必须是布尔值" % path)
	elif event_type == "有人来了" or event_type == "有人走了":
		AgentContractIdentity._validate_resident_id(event, "who_resident_id", "%s.who_resident_id" % path, errors)
		AgentContract._require_non_empty_string(event, "who", "%s.who" % path, errors)
	elif event_type == "天气变了":
		var weather := AgentContract._require_non_empty_string(event, "weather", "%s.weather" % path, errors)
		if not weather.is_empty() and not AgentContract.WEATHER_TYPES.has(weather):
			errors.append("%s.weather 不是合法天气" % path)
	elif event_type in ["公告发布", "公告阅读", "公告转告", "公告到点"]:
		AgentContract._require_non_empty_string(
			event,
			"announcement_id",
			"%s.announcement_id" % path,
			errors,
		)
		AgentContract._require_non_empty_string(event, "text", "%s.text" % path, errors)
		if (
			event.has("announcement_priority")
			and String(event.get("announcement_priority", ""))
			not in ["player", "ordinary"]
		):
			errors.append("%s.announcement_priority 不是合法公告优先级" % path)
		if event_type == "公告阅读":
			AgentContract._require_string(
				event,
				"publisher_resident_id",
				"%s.publisher_resident_id" % path,
				errors,
			)
		elif event_type == "公告转告":
			AgentContractIdentity._validate_resident_id(
				event,
				"speaker_resident_id",
				"%s.speaker_resident_id" % path,
				errors,
			)
		elif event_type == "公告到点":
			AgentContract._require_non_empty_string(
				event,
				"scheduled_time_label",
				"%s.scheduled_time_label" % path,
				errors,
			)
	elif event_type == "营业状态变化":
		AgentContract._require_non_empty_string(
			event,
			"place_id",
			"%s.place_id" % path,
			errors,
		)
		if typeof(event.get("open")) != TYPE_BOOL:
			errors.append("%s.open 必须是布尔值" % path)
		AgentContract._require_non_empty_string(
			event,
			"summary",
			"%s.summary" % path,
			errors,
		)
	elif event_type == "身体状况变化":
		AgentContract._require_non_empty_string(event, "eventId", "%s.eventId" % path, errors)
		var condition_event_type := AgentContract._require_non_empty_string(
			event,
			"eventType",
			"%s.eventType" % path,
			errors,
		)
		if condition_event_type not in [
			"condition_started",
			"condition_changed",
			"condition_recovering",
			"condition_resolved",
		]:
			errors.append("%s.eventType 不是合法身体状况事件" % path)
		AgentContract._require_non_empty_string(
			event,
			"conditionId",
			"%s.conditionId" % path,
			errors,
		)
		AgentContract._require_non_empty_string(
			event,
			"conditionKind",
			"%s.conditionKind" % path,
			errors,
		)
		AgentContract._require_non_empty_string(event, "label", "%s.label" % path, errors)
		var severity := AgentContract._require_non_empty_string(
			event,
			"severity",
			"%s.severity" % path,
			errors,
		)
		if severity not in ["minor", "noticeable", "serious"]:
			errors.append("%s.severity 不是合法身体状况程度" % path)
		var condition_state := AgentContract._require_non_empty_string(
			event,
			"state",
			"%s.state" % path,
			errors,
		)
		if condition_state not in ["active", "recovering"]:
			errors.append("%s.state 不是合法身体状况状态" % path)
		if (
			typeof(event.get("atMinute")) != TYPE_INT
			or int(event.get("atMinute", -1)) < 0
		):
			errors.append("%s.atMinute 必须是非负整数" % path)
		AgentContract._require_non_empty_string(
			event,
			"sourceRef",
			"%s.sourceRef" % path,
			errors,
		)
	elif event_type == "旁听":
		AgentContract._require_non_empty_string(event, "conversation_id", "%s.conversation_id" % path, errors)
		var speaker_ids := AgentContract._require_array(
			event,
			"speaker_resident_ids",
			"%s.speaker_resident_ids" % path,
			errors,
		)
		var speakers := AgentContract._require_array(event, "speakers", "%s.speakers" % path, errors)
		if speaker_ids.size() != speakers.size():
			errors.append("%s.speaker_resident_ids 必须与 speakers 一一对应" % path)
		var used_speaker_ids := {}
		for speaker_index in speaker_ids.size():
			var speaker_id_value: Variant = speaker_ids[speaker_index]
			var speaker_id := String(speaker_id_value) if typeof(speaker_id_value) == TYPE_STRING else ""
			if speaker_id.is_empty() or not AgentContractIdentity._resident_id_is_safe(speaker_id):
				errors.append(
					"%s.speaker_resident_ids[%d] 必须是合法 resident_id"
					% [path, speaker_index],
				)
			elif used_speaker_ids.has(speaker_id):
				errors.append("%s.speaker_resident_ids[%d] 重复" % [path, speaker_index])
			used_speaker_ids[speaker_id] = true
		for speaker_index in speakers.size():
			if (
				typeof(speakers[speaker_index]) != TYPE_STRING
				or String(speakers[speaker_index]).strip_edges().is_empty()
			):
				errors.append("%s.speakers[%d] 必须是非空文本" % [path, speaker_index])
		AgentContractConversation._validate_turn(event.get("turn"), "%s.turn" % path, errors)
	elif event_type == "对话结束":
		AgentContract._require_non_empty_string(event, "conversation_id", "%s.conversation_id" % path, errors)
		var turns := AgentContract._require_array(event, "turns", "%s.turns" % path, errors)
		for turn_index in turns.size():
			AgentContractConversation._validate_turn(turns[turn_index], "%s.turns[%d]" % [path, turn_index], errors)
			if typeof(turns[turn_index]) == TYPE_DICTIONARY:
				var turn := turns[turn_index] as Dictionary
				if typeof(turn.get("turn_id")) == TYPE_INT and int(turn["turn_id"]) != turn_index + 1:
					errors.append("%s.turns[%d].turn_id 必须从 1 开始递增" % [path, turn_index])
		var reason := AgentContract._require_non_empty_string(event, "reason", "%s.reason" % path, errors)
		if not reason.is_empty() and not AgentContract.CONVERSATION_END_REASONS.has(reason):
			errors.append("%s.reason 不是合法对话结束原因" % path)


static func _validate_action_results(action_results: Array, errors: Array[String]) -> void:
	var action_ids := {}
	for index in action_results.size():
		var path := "action_results[%d]" % index
		var value: Variant = action_results[index]
		if typeof(value) != TYPE_DICTIONARY:
			errors.append("%s 必须是对象" % path)
			continue
		var result := value as Dictionary
		AgentContractSocial._validate_optional_world_revision(result, path, errors)
		var action_id := AgentContract._require_non_empty_string(result, "action_id", "%s.action_id" % path, errors)
		if not action_id.is_empty() and action_ids.has(action_id):
			errors.append("%s.action_id 在本次动作结果中重复" % path)
		action_ids[action_id] = true
		var status := AgentContract._require_non_empty_string(result, "status", "%s.status" % path, errors)
		if not status.is_empty() and not AgentContract.ACTION_RESULT_STATUSES.has(status):
			errors.append("%s.status 不是合法动作结果状态" % path)
		AgentContract._require_non_empty_string(result, "reason", "%s.reason" % path, errors)
		var time := AgentContract._require_dictionary(result, "time", "%s.time" % path, errors)
		if not time.is_empty():
			AgentContractEnvironment._validate_time(time, "%s.time" % path, errors)
