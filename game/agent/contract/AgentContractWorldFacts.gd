class_name AgentContractWorldFacts
extends RefCounted
## AgentContract 拆分模块(批次C之4,纯搬运+跨模块调用改类前缀)。


static func _validate_life_destination_options(
	options: Array,
	errors: Array[String],
) -> void:
	if options.size() > 8:
		errors.append("snapshot.life_destination_options 每轮最多 8 项")
	for index in options.size():
		var path := "snapshot.life_destination_options[%d]" % index
		if not options[index] is Dictionary:
			errors.append("%s 必须是对象" % path)
			continue
		var option := options[index] as Dictionary
		AgentContractIdentity._validate_allowed_fields(
			option,
			["place_id", "activities"],
			path,
			errors,
		)
		AgentContract._require_non_empty_string(
			option,
			"place_id",
			"%s.place_id" % path,
			errors,
		)
		var activities := AgentContract._require_array(
			option,
			"activities",
			"%s.activities" % path,
			errors,
		)
		if activities.is_empty() or activities.size() > 3:
			errors.append("%s.activities 必须有 1 到 3 项" % path)
		for activity_index in activities.size():
			var activity_path := "%s.activities[%d]" % [path, activity_index]
			if not activities[activity_index] is Dictionary:
				errors.append("%s 必须是对象" % activity_path)
				continue
			var activity := activities[activity_index] as Dictionary
			AgentContractIdentity._validate_allowed_fields(
				activity,
				[
					"activity_id",
					"label",
					"interest_match",
					"matched_interests",
				],
				activity_path,
				errors,
			)
			AgentContract._require_non_empty_string(
				activity,
				"activity_id",
				"%s.activity_id" % activity_path,
				errors,
			)
			AgentContract._require_non_empty_string(
				activity,
				"label",
				"%s.label" % activity_path,
				errors,
			)
			if typeof(activity.get("interest_match")) != TYPE_BOOL:
				errors.append("%s.interest_match 必须是布尔值" % activity_path)
			var matched := AgentContract._require_array(
				activity,
				"matched_interests",
				"%s.matched_interests" % activity_path,
				errors,
			)
			for interest_value: Variant in matched:
				if (
					not interest_value is String
					or String(interest_value).is_empty()
				):
					errors.append(
						"%s.matched_interests 只能包含非空文本" % activity_path
					)


static func _validate_known_announcements(
	announcements: Array,
	errors: Array[String],
) -> void:
	var seen := {}
	for index in announcements.size():
		var path := "snapshot.known_announcements[%d]" % index
		var value: Variant = announcements[index]
		if not value is Dictionary:
			errors.append("%s 必须是对象" % path)
			continue
		var announcement := value as Dictionary
		AgentContractIdentity._validate_allowed_fields(
			announcement,
			[
				"announcement_id",
				"text",
				"publisher_resident_id",
				"publisher_name",
				"acquired_via",
				"active",
				"scheduled_absolute_minute",
				"scheduled_time_label",
				"schedule_triggered",
			],
			path,
			errors,
		)
		var announcement_id := AgentContract._require_non_empty_string(
			announcement,
			"announcement_id",
			"%s.announcement_id" % path,
			errors,
		)
		if seen.has(announcement_id):
			errors.append("%s.announcement_id 重复" % path)
		seen[announcement_id] = true
		for field in ["text", "acquired_via"]:
			AgentContract._require_non_empty_string(
				announcement,
				field,
				"%s.%s" % [path, field],
				errors,
			)
		AgentContract._require_string(
			announcement,
			"publisher_resident_id",
			"%s.publisher_resident_id" % path,
			errors,
		)
		if typeof(announcement.get("active")) != TYPE_BOOL:
			errors.append("%s.active 必须是布尔值" % path)
		if announcement.has("publisher_name") and not announcement.get("publisher_name") is String:
			errors.append("%s.publisher_name 必须是文本" % path)
		if announcement.has("scheduled_absolute_minute") and typeof(announcement.get("scheduled_absolute_minute")) != TYPE_INT:
			errors.append("%s.scheduled_absolute_minute 必须是整数" % path)
		if announcement.has("scheduled_time_label") and not announcement.get("scheduled_time_label") is String:
			errors.append("%s.scheduled_time_label 必须是文本" % path)
		if announcement.has("schedule_triggered") and not announcement.get("schedule_triggered") is bool:
			errors.append("%s.schedule_triggered 必须是布尔值" % path)
