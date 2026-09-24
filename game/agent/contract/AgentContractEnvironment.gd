class_name AgentContractEnvironment
extends RefCounted
## AgentContract 拆分模块(批次C之4,纯搬运+跨模块调用改类前缀)。


static func _validate_weather_context(
	value: Variant,
	errors: Array[String],
) -> void:
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("snapshot.weather_context 必须是对象")
		return
	var context := value as Dictionary
	AgentContractIdentity._validate_allowed_fields(
		context,
		[
			"impact",
			"outdoorPolicy",
			"summary",
			"indoorAlternatives",
		],
		"snapshot.weather_context",
		errors,
	)
	var impact := AgentContract._require_non_empty_string(
		context,
		"impact",
		"snapshot.weather_context.impact",
		errors,
	)
	if not impact.is_empty() and impact not in [
		"none",
		"mild",
		"strong",
		"dangerous",
	]:
		errors.append("snapshot.weather_context.impact 不是合法影响程度")
	var outdoor_policy := AgentContract._require_non_empty_string(
		context,
		"outdoorPolicy",
		"snapshot.weather_context.outdoorPolicy",
		errors,
	)
	if not outdoor_policy.is_empty() and outdoor_policy not in [
		"preferred",
		"normal",
		"discouraged",
		"unavailable",
	]:
		errors.append(
			"snapshot.weather_context.outdoorPolicy 不是合法户外策略"
		)
	AgentContract._require_non_empty_string(
		context,
		"summary",
		"snapshot.weather_context.summary",
		errors,
	)
	var alternatives := AgentContract._require_array(
		context,
		"indoorAlternatives",
		"snapshot.weather_context.indoorAlternatives",
		errors,
	)
	if alternatives.size() > 6:
		errors.append("snapshot.weather_context.indoorAlternatives 最多 6 项")
	for index in alternatives.size():
		if (
			typeof(alternatives[index]) != TYPE_STRING
			or String(alternatives[index]).strip_edges().is_empty()
		):
			errors.append(
				"snapshot.weather_context.indoorAlternatives[%d] 必须是非空文本"
				% index
			)


static func _validate_time(time: Dictionary, path: String, errors: Array[String]) -> void:
	if not time.has("day"):
		errors.append("%s.day 缺失" % path)
	elif typeof(time["day"]) != TYPE_INT or int(time["day"]) <= 0:
		errors.append("%s.day 必须是正整数" % path)
	var clock := AgentContract._require_non_empty_string(time, "clock", "%s.clock" % path, errors)
	if not clock.is_empty() and not AgentContractWake._is_valid_clock(clock):
		errors.append("%s.clock 必须使用 HH:MM 格式" % path)
	var period := AgentContract._require_non_empty_string(time, "period", "%s.period" % path, errors)
	if not period.is_empty() and not AgentContract.PERIODS.has(period):
		errors.append("%s.period 不是合法时段" % path)
	elif not clock.is_empty() and AgentContractWake._is_valid_clock(clock) and AgentContract.period_for_clock(clock) != period:
		errors.append("%s.period 与 clock 不对应" % path)


static func _validate_current_action(value: Variant, errors: Array[String]) -> void:
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("snapshot.me.current_action 必须是对象或 null")
		return
	var action := value as Dictionary
	AgentContract._require_non_empty_string(action, "action_id", "snapshot.me.current_action.action_id", errors)
	var action_type := AgentContract._require_non_empty_string(
		action,
		"type",
		"snapshot.me.current_action.type",
		errors,
	)
	if not action_type.is_empty() and not AgentContract.ACTION_TYPES.has(action_type):
		errors.append("snapshot.me.current_action.type 不是合法动作类型")


static func _validate_condition_projections(
	conditions: Array,
	errors: Array[String],
) -> void:
	var condition_ids := {}
	for index in conditions.size():
		var path := "snapshot.me.conditions[%d]" % index
		if not conditions[index] is Dictionary:
			errors.append("%s 必须是对象" % path)
			continue
		var condition := conditions[index] as Dictionary
		AgentContractIdentity._validate_allowed_fields(
			condition,
			[
				"conditionId",
				"kind",
				"label",
				"severity",
				"sourceKind",
				"sourceRef",
				"startedAtMinute",
				"lastChangedAtMinute",
				"state",
				"nextChangeAtMinute",
			],
			path,
			errors,
		)
		var condition_id := AgentContract._require_non_empty_string(
			condition,
			"conditionId",
			"%s.conditionId" % path,
			errors,
		)
		if not condition_id.is_empty() and condition_ids.has(condition_id):
			errors.append("%s.conditionId 重复" % path)
		condition_ids[condition_id] = true
		for field_name in ["kind", "label", "sourceKind", "sourceRef"]:
			AgentContract._require_non_empty_string(
				condition,
				field_name,
				"%s.%s" % [path, field_name],
				errors,
			)
		var severity := AgentContract._require_non_empty_string(
			condition,
			"severity",
			"%s.severity" % path,
			errors,
		)
		if severity not in ["minor", "noticeable", "serious"]:
			errors.append("%s.severity 不是合法身体状况程度" % path)
		var state := AgentContract._require_non_empty_string(
			condition,
			"state",
			"%s.state" % path,
			errors,
		)
		if state not in ["active", "recovering"]:
			errors.append("%s.state 不是合法身体状况状态" % path)
		for field_name in [
			"startedAtMinute",
			"lastChangedAtMinute",
			"nextChangeAtMinute",
		]:
			if (
				typeof(condition.get(field_name)) != TYPE_INT
				or int(condition.get(field_name, -1)) < 0
			):
				errors.append("%s.%s 必须是非负整数" % [path, field_name])


static func _validate_condition_need_projections(
	needs: Array,
	errors: Array[String],
) -> void:
	var need_ids := {}
	for index in needs.size():
		var path := "snapshot.me.activeNeeds[%d]" % index
		if not needs[index] is Dictionary:
			errors.append("%s 必须是对象" % path)
			continue
		var need := needs[index] as Dictionary
		AgentContractIdentity._validate_allowed_fields(
			need,
			[
				"needId",
				"kind",
				"label",
				"urgency",
				"conditionId",
				"conditionKind",
				"responseRequirements",
			],
			path,
			errors,
		)
		var need_id := AgentContract._require_non_empty_string(
			need,
			"needId",
			"%s.needId" % path,
			errors,
		)
		if not need_id.is_empty() and need_ids.has(need_id):
			errors.append("%s.needId 重复" % path)
		need_ids[need_id] = true
		for field_name in ["kind", "label", "conditionId", "conditionKind"]:
			AgentContract._require_non_empty_string(
				need,
				field_name,
				"%s.%s" % [path, field_name],
				errors,
			)
		var urgency := AgentContract._require_non_empty_string(
			need,
			"urgency",
			"%s.urgency" % path,
			errors,
		)
		if urgency not in ["low", "medium", "high"]:
			errors.append("%s.urgency 不是合法紧迫程度" % path)
		var requirements := AgentContract._require_array(
			need,
			"responseRequirements",
			"%s.responseRequirements" % path,
			errors,
		)
		if requirements.is_empty():
			errors.append("%s.responseRequirements 不能为空" % path)
		for requirement_index in requirements.size():
			if (
				not requirements[requirement_index] is String
				or String(requirements[requirement_index]).strip_edges().is_empty()
			):
				errors.append(
					"%s.responseRequirements[%d] 必须是非空文本"
					% [path, requirement_index]
				)


static func _validate_nearby(nearby: Array, errors: Array[String]) -> void:
	var resident_ids := {}
	for index in nearby.size():
		var path := "snapshot.nearby[%d]" % index
		var value: Variant = nearby[index]
		if typeof(value) != TYPE_DICTIONARY:
			errors.append("%s 必须是对象" % path)
			continue
		var person := value as Dictionary
		var resident_id := AgentContractIdentity._validate_resident_id(
			person,
			"resident_id",
			"%s.resident_id" % path,
			errors,
		)
		AgentContract._require_non_empty_string(person, "name", "%s.name" % path, errors)
		AgentContract._require_non_empty_string(person, "doing", "%s.doing" % path, errors)
		if (
			person.has("available_for_conversation")
			and typeof(person.get("available_for_conversation")) != TYPE_BOOL
		):
			errors.append("%s.available_for_conversation 必须是布尔值" % path)
		if not resident_id.is_empty() and resident_ids.has(resident_id):
			errors.append("%s.resident_id 在 nearby 中重复" % path)
		resident_ids[resident_id] = true


static func _validate_snapshot_place(place: Dictionary, errors: Array[String]) -> void:
	AgentContract._require_non_empty_string(place, "name", "snapshot.place.name", errors)
	if place.has("required_work_task_id"):
		AgentContract._require_non_empty_string(
			place,
			"required_work_task_id",
			"snapshot.place.required_work_task_id",
			errors,
		)
	if place.has("message_recipients"):
		var message_recipients := AgentContract._require_array(
			place,
			"message_recipients",
			"snapshot.place.message_recipients",
			errors,
		)
		for index in message_recipients.size():
			var recipient: Variant = message_recipients[index]
			if not recipient is Dictionary:
				errors.append(
					"snapshot.place.message_recipients[%d] 必须是对象" % index
				)
				continue
			AgentContractIdentity._validate_resident_id(
				recipient as Dictionary,
				"resident_id",
				"snapshot.place.message_recipients[%d].resident_id" % index,
				errors,
			)
			AgentContract._require_non_empty_string(
				recipient as Dictionary,
				"name",
				"snapshot.place.message_recipients[%d].name" % index,
				errors,
			)
	if place.has("destinations"):
		var destinations := AgentContract._require_array(
			place,
			"destinations",
			"snapshot.place.destinations",
			errors,
		)
		var destination_names := {}
		for index in destinations.size():
			var value: Variant = destinations[index]
			if (
				typeof(value) != TYPE_STRING
				or String(value).strip_edges().is_empty()
			):
				errors.append(
					"snapshot.place.destinations[%d] 必须是非空文本"
					% index,
				)
				continue
			var destination_name := String(value)
			if destination_names.has(destination_name):
				errors.append(
					"snapshot.place.destinations[%d] 重复" % index,
				)
			destination_names[destination_name] = true
	if place.has("visible_props"):
		var visible_props := AgentContract._require_array(
			place,
			"visible_props",
			"snapshot.place.visible_props",
			errors,
		)
		var visible_names := {}
		for index in visible_props.size():
			var value: Variant = visible_props[index]
			if (
				typeof(value) != TYPE_STRING
				or String(value).strip_edges().is_empty()
			):
				errors.append(
					"snapshot.place.visible_props[%d] 必须是非空文本"
					% index
				)
				continue
			var visible_name := String(value)
			if visible_names.has(visible_name):
				errors.append(
					"snapshot.place.visible_props[%d] 重复"
					% index
				)
			visible_names[visible_name] = true
	var props := AgentContract._require_array(place, "props", "snapshot.place.props", errors)
	var prop_names := {}
	for index in props.size():
		var path := "snapshot.place.props[%d]" % index
		var value: Variant = props[index]
		if typeof(value) != TYPE_DICTIONARY:
			errors.append("%s 必须是对象" % path)
			continue
		var prop := value as Dictionary
		var name := AgentContract._require_non_empty_string(prop, "name", "%s.name" % path, errors)
		var verbs := AgentContract._require_array(prop, "verbs", "%s.verbs" % path, errors)
		for verb_index in verbs.size():
			if typeof(verbs[verb_index]) != TYPE_STRING or String(verbs[verb_index]).strip_edges().is_empty():
				errors.append("%s.verbs[%d] 必须是非空文本" % [path, verb_index])
		if not name.is_empty() and prop_names.has(name):
			errors.append("%s.name 在 props 中重复" % path)
		prop_names[name] = true
	if place.has("activities"):
		var activities := AgentContract._require_array(
			place,
			"activities",
			"snapshot.place.activities",
			errors,
		)
		var activity_ids := {}
		for index in activities.size():
			var path := "snapshot.place.activities[%d]" % index
			var value: Variant = activities[index]
			if typeof(value) != TYPE_DICTIONARY:
				errors.append("%s 必须是对象" % path)
				continue
			var activity := value as Dictionary
			var activity_id := AgentContract._require_non_empty_string(
				activity,
				"activity_id",
				"%s.activity_id" % path,
				errors,
			)
			AgentContract._require_non_empty_string(
				activity,
				"label",
				"%s.label" % path,
				errors,
			)
			if not activity_id.is_empty() and activity_ids.has(activity_id):
				errors.append("%s.activity_id 在 activities 中重复" % path)
			activity_ids[activity_id] = true
	if place.has("service_control"):
		var control := AgentContract._require_dictionary(
			place,
			"service_control",
			"snapshot.place.service_control",
			errors,
		)
		if not control.is_empty():
			AgentContract._require_non_empty_string(
				control,
				"place_id",
				"snapshot.place.service_control.place_id",
				errors,
			)
			if typeof(control.get("open")) != TYPE_BOOL:
				errors.append(
					"snapshot.place.service_control.open 必须是布尔值"
				)
