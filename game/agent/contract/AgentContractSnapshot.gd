class_name AgentContractSnapshot
extends RefCounted
## AgentContract 拆分模块(批次C之4,纯搬运+跨模块调用改类前缀)。


static func _validate_reaction(
	reaction: Dictionary,
	wake_packet: Dictionary,
	errors: Array[String],
) -> void:
	if reaction.is_empty():
		return
	AgentContractIdentity._validate_allowed_fields(reaction, AgentContract.REACTION_FIELDS, "reaction", errors)
	var source_action_id := AgentContract._require_non_empty_string(
		reaction,
		"source_action_id",
		"reaction.source_action_id",
		errors,
	)
	var text := AgentContract._require_non_empty_string(
		reaction,
		"text",
		"reaction.text",
		errors,
	)
	var expected_action_id := AgentContract.reaction_source_action_id(wake_packet)
	if not expected_action_id.is_empty():
		if source_action_id != expected_action_id:
			errors.append("reaction.source_action_id 必须指向本次最新的可回应动作结果")
	else:
		errors.append("本次唤醒没有可回应的动作结果，不允许 reaction")
	if text.contains("\n") or text.contains("\r") or text.contains("\t"):
		errors.append("reaction.text 必须是单行文字")
	if text.length() > AgentContract.REACTION_TEXT_MAX_LENGTH:
		errors.append(
			"reaction.text 最多 %d 个字符"
			% AgentContract.REACTION_TEXT_MAX_LENGTH
		)


static func _validate_announcement_reactions(
	value: Variant,
	wake_packet: Dictionary,
	errors: Array[String],
) -> void:
	if value is not Array:
		errors.append("announcement_reactions 必须是数组")
		return
	var expected_ids := AgentContract.announcement_reaction_source_event_ids(
		wake_packet,
	)
	var seen: Dictionary = {}
	for index: int in (value as Array).size():
		var reaction_value: Variant = (value as Array)[index]
		if reaction_value is not Dictionary:
			errors.append("announcement_reactions[%d] 必须是对象" % index)
			continue
		var reaction := reaction_value as Dictionary
		AgentContractIdentity._validate_allowed_fields(
			reaction,
			AgentContract.ANNOUNCEMENT_REACTION_FIELDS,
			"announcement_reactions[%d]" % index,
			errors,
		)
		var source_event_id := AgentContract._require_non_empty_string(
			reaction,
			"source_event_id",
			"announcement_reactions[%d].source_event_id" % index,
			errors,
		)
		var text := AgentContract._require_non_empty_string(
			reaction,
			"text",
			"announcement_reactions[%d].text" % index,
			errors,
		)
		if not source_event_id.is_empty():
			if not expected_ids.has(source_event_id):
				errors.append(
					"announcement_reactions[%d].source_event_id 不属于本轮公告"
					% index
				)
			elif seen.has(source_event_id):
				errors.append("同一公告不能重复提交回应：%s" % source_event_id)
			seen[source_event_id] = true
		if text.contains("\n") or text.contains("\r") or text.contains("\t"):
			errors.append("announcement_reactions[%d].text 必须是单行文字" % index)
		if text.length() > AgentContract.REACTION_TEXT_MAX_LENGTH:
			errors.append(
				"announcement_reactions[%d].text 最多 %d 个字符"
				% [index, AgentContract.REACTION_TEXT_MAX_LENGTH]
			)


static func _validate_snapshot(snapshot: Dictionary, errors: Array[String]) -> void:
	AgentContract.CONFLICT_CONTRACT.validate_snapshot(snapshot, errors)
	var time := AgentContract._require_dictionary(snapshot, "time", "snapshot.time", errors)
	if not time.is_empty():
		AgentContractEnvironment._validate_time(time, "snapshot.time", errors)
	var weather := AgentContract._require_non_empty_string(snapshot, "weather", "snapshot.weather", errors)
	if not weather.is_empty() and not AgentContract.WEATHER_TYPES.has(weather):
		errors.append("snapshot.weather 不是合法天气")
	if snapshot.has("weather_context"):
		AgentContractEnvironment._validate_weather_context(
			snapshot.get("weather_context"),
			errors,
		)
	var me := AgentContract._require_dictionary(snapshot, "me", "snapshot.me", errors)
	if not me.is_empty():
		AgentContract._require_non_empty_string(me, "doing", "snapshot.me.doing", errors)
		if not me.has("current_action"):
			errors.append("snapshot.me.current_action 缺失")
		elif me["current_action"] != null:
			AgentContractEnvironment._validate_current_action(me["current_action"], errors)
		var body := AgentContract._require_dictionary(me, "body", "snapshot.me.body", errors)
		for state_name: String in AgentContract.BODY_STATE_VALUES:
			if not body.has(state_name):
				errors.append("snapshot.me.body.%s 缺失" % state_name)
				continue
			var state_value: Variant = body[state_name]
			if typeof(state_value) != TYPE_STRING or not (AgentContract.BODY_STATE_VALUES[state_name] as Array).has(String(state_value)):
				errors.append("snapshot.me.body.%s 不是合法程度" % state_name)
		for state_name: Variant in body:
			if typeof(state_name) != TYPE_STRING or not AgentContract.BODY_STATE_VALUES.has(String(state_name)):
				errors.append("snapshot.me.body.%s 不是合法身体状态" % String(state_name))
		if me.has("conditions"):
			AgentContractEnvironment._validate_condition_projections(
				AgentContract._require_array(
					me,
					"conditions",
					"snapshot.me.conditions",
					errors,
				),
				errors,
			)
		if me.has("activeNeeds"):
			AgentContractEnvironment._validate_condition_need_projections(
				AgentContract._require_array(
					me,
					"activeNeeds",
					"snapshot.me.activeNeeds",
					errors,
				),
				errors,
			)
	AgentContractEnvironment._validate_nearby(AgentContract._require_array(snapshot, "nearby", "snapshot.nearby", errors), errors)
	var place := AgentContract._require_dictionary(snapshot, "place", "snapshot.place", errors)
	if not place.is_empty():
		AgentContractEnvironment._validate_snapshot_place(place, errors)
	if snapshot.has("rhythm"):
		if typeof(snapshot.get("rhythm")) != TYPE_DICTIONARY:
			errors.append("snapshot.rhythm 必须是对象")
		else:
			var rhythm := snapshot.get("rhythm", {}) as Dictionary
			AgentContract._require_non_empty_string(
				rhythm,
				"id",
				"snapshot.rhythm.id",
				errors,
			)
			AgentContract._require_non_empty_string(
				rhythm,
				"label",
				"snapshot.rhythm.label",
				errors,
			)
			if typeof(rhythm.get("flexible")) != TYPE_BOOL:
				errors.append("snapshot.rhythm.flexible 必须是布尔值")
			if typeof(rhythm.get("work_expected")) != TYPE_BOOL:
				errors.append("snapshot.rhythm.work_expected 必须是布尔值")
			for field_name in ["workplace", "schedule_label"]:
				if typeof(rhythm.get(field_name)) != TYPE_STRING:
					errors.append(
						"snapshot.rhythm.%s 必须是文本" % field_name
					)
	if snapshot.has("work_tasks"):
		AgentContractWorkTasks._validate_work_tasks(
			AgentContract._require_array(
				snapshot,
				"work_tasks",
				"snapshot.work_tasks",
				errors,
			),
			errors,
		)
	if snapshot.has("life_destination_options"):
		AgentContractWorldFacts._validate_life_destination_options(
			AgentContract._require_array(
				snapshot,
				"life_destination_options",
				"snapshot.life_destination_options",
				errors,
			),
			errors,
		)
	if snapshot.has("social_matters"):
		AgentContractSocial._validate_social_matters(
			AgentContract._require_array(
				snapshot,
				"social_matters",
				"snapshot.social_matters",
				errors,
			),
			errors,
		)
	if snapshot.has("known_announcements"):
		AgentContractWorldFacts._validate_known_announcements(
			AgentContract._require_array(
				snapshot,
				"known_announcements",
				"snapshot.known_announcements",
				errors,
			),
			errors,
		)
	if snapshot.has("social_exposures"):
		AgentContractSocial._validate_social_exposures(
			AgentContract._require_array(
				snapshot,
				"social_exposures",
				"snapshot.social_exposures",
				errors,
			),
			errors,
		)
	if not snapshot.has("conversation"):
		errors.append("snapshot.conversation 缺失")
	elif snapshot["conversation"] != null:
		if typeof(snapshot["conversation"]) != TYPE_DICTIONARY:
			errors.append("snapshot.conversation 必须是对象或 null")
		else:
			AgentContractConversation._validate_conversation(snapshot["conversation"], errors)
