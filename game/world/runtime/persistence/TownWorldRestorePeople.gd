class_name TownWorldRestorePeople
extends RefCounted


const SAVE_SCALARS_UTIL := preload(
	"res://world/presentation/session/TownSaveScalars.gd"
)
const OPENING_CONFIG := preload("res://world/runtime/TownWorldOpeningConfig.gd")
const INTERESTS := preload(
	"res://world/data/town/TownInterestCatalog.gd"
)
const SAVE_CODEC := preload("res://world/runtime/persistence/TownWorldSaveCodec.gd")
const CHARACTER_MOVEMENT_QUERY := preload(
	"res://world/data/town/TownWorldCharacterMovementQuery.gd"
)
const RESIDENT_CONDITION_RUNTIME := preload(
	"res://world/runtime/condition/TownResidentConditionRuntime.gd"
)
const RESIDENT_SLEEP_RUNTIME := preload(
	"res://world/runtime/condition/TownResidentSleepRuntime.gd"
)
const RESIDENT_LIFECYCLE_RUNTIME := preload(
	"res://world/runtime/lifecycle/TownResidentLifecycleRuntime.gd"
)
const BODY_LEVELS := {
	"困": ["不困", "有点困", "很困"],
	"饿": ["不饿", "有点饿", "很饿"],
	"累": ["不累", "有点累", "很累"],
}
const WEATHER_TYPES := ["晴天", "阴天", "小雨", "中雨", "大雨", "雷暴", "下雪"]
const CONDITION_EVENT_TYPES := [
	"condition_started",
	"condition_changed",
	"condition_recovering",
	"condition_resolved",
]

const CONFLICT_EVENT_TYPES := [
	"conflict_challenged",
	"conflict_threatened",
	"conflict_apologized",
	"conflict_disengaged",
	"avatar_area_attack_cast",
	"unilateral_hit_confirmed",
	"injury_applied",
	"brawl_started",
	"conflict_intervened",
	"conflict_joined",
	"conflict_left",
	"conflict_ended",
	"treatment_started",
	"treatment_completed",
	"injury_recovered",
]
const ACTIVITY_STATE_KEYS := [
	"energy",
	"satiety",
	"stress",
	"socialNeed",
	"solitudeNeed",
]
const SAVED_RESIDENT_FIELDS := [
	"residentId", "name", "movementRevision", "profileAttributes", "socialState", "position", "spaceId", "regionId",
	"currentPlace", "doing", "body", "currentAction", "routeConnector",
	"conversationId", "conversation", "pendingEvents", "pendingActionResults",
	"usedActionIds", "confirmedActionPreview", "actionSuspendedAbsoluteMinute",
]
const SAVED_AVATAR_FIELDS := [
	"residentId", "name", "position", "spaceId", "regionId", "currentPlace",
	"doing", "nearby", "conversationId", "conversation",
]
const SAVED_ACTION_FIELDS := {
	"去": ["action_id", "type", "place", "line", "startedAbsoluteMinute", "durationMinutes", "route", "completionEffects", "consumeRouteConnector"],
	"用道具": ["action_id", "type", "prop", "verb", "line", "startedAbsoluteMinute", "sourcePlace", "durationMinutes", "pathPoints", "effects", "targetPosition", "returnRouteConnector", "consumeRouteConnector", "dynamicPropId"],
	"托人传话": ["action_id", "type", "recipient_resident_id", "content", "line", "startedAbsoluteMinute", "completeAbsoluteMinute"],
	"待着": ["action_id", "type", "line", "startedAbsoluteMinute", "completeAbsoluteMinute"],
	"搭话": ["action_id", "type", "target", "target_resident_id", "say", "narration", "photos", "startedAbsoluteMinute", "conversationId"],
	"答话": ["action_id", "type", "conversation_id", "say", "narration", "photos", "end", "startedAbsoluteMinute"],
}
const CONVERSATION_FOLLOW_UP_ACTION_FIELDS := [
	"conversationFollowUpMode",
	"followUpPhase",
	"followUpPersonId",
	"followUpDestinationPlace",
	"followUpServicePlace",
	"followUpServiceActivityId",
	"followUpServiceLabel",
	"followUpDeadlineMinute",
	"followUpLastAdvanceMinute",
	"followUpLagStartedMinute",
	"followUpServiceCollected",
	"followUpCollectUntilMinute",
]
const SAVED_EVENT_FIELDS := {
	"天气变了": ["event_id", "time", "type", "weather", "residentId"],
	"公告发布": [
		"event_id", "time", "type", "announcement_id", "publisher_resident_id",
		"text", "matter_id", "residentId",
	],
	"公告到点": [
		"event_id", "time", "type", "announcement_id", "publisher_resident_id",
		"text", "matter_id", "scheduled_absolute_minute", "scheduled_time_label",
		"status", "residentId",
	],
	"公告阅读": [
		"event_id", "time", "type", "announcement_id", "publisher_resident_id",
		"text", "matter_id", "read_at", "residentId",
	],
	"公告转告": [
		"event_id", "time", "type", "announcement_id", "speaker_resident_id",
		"text", "matter_id", "residentId",
	],
	"钟声公告": [
		"event_id", "time", "type", "announcement_id", "publisher_resident_id",
		"text", "matter_id", "delivery_mode", "residentId",
	],
	"正式通知送达": [
		"event_id", "time", "type", "announcement_id", "speaker_resident_id",
		"message_id", "text", "matter_id", "residentId",
	],
	"承诺条件变化": [
		"event_id", "time", "type", "summary", "commitment_action_id", "residentId",
	],
	"搭话": ["event_id", "time", "type", "conversation_id", "turn", "residentId"],
	"对方答话": ["event_id", "time", "type", "conversation_id", "turn", "residentId"],
	"对话结束": ["event_id", "time", "type", "conversation_id", "turns", "reason", "residentId"],
	"旁听": ["event_id", "time", "type", "conversation_id", "speaker_resident_ids", "speakers", "turn", "residentId"],
	"有人来了": ["event_id", "time", "type", "who_resident_id", "who", "residentId"],
	"有人走了": ["event_id", "time", "type", "who_resident_id", "who", "residentId"],
	"营业状态变化": [
		"event_id", "time", "type", "place_id", "open", "summary",
		"changed_by_resident_id", "residentId",
	],
	"身体状况变化": [
		"event_id", "time", "type", "eventId", "eventType", "residentId",
		"conditionId", "conditionKind", "label", "severity", "state",
		"atMinute", "sourceRef",
	],
	"冲突见闻": [
		"event_id", "time", "type", "conflict_id", "conflict_event_id",
		"conflict_event_type", "knowledge_kind", "source_resident_id",
		"actor_ids", "place_id", "severity", "summary", "residentId",
	],
	"居民死亡": [
		"event_id", "time", "type", "deceased_resident_id",
		"deceased_resident_name", "reason", "location", "residentId",
	],
}


static func prepare(
	world_data: Dictionary,
	opening_config: Dictionary,
	state: Dictionary,
) -> Dictionary:
	var errors: Array[String] = []
	var known_places := {}
	for place_value: Variant in world_data.get("places", []) as Array:
		var place := place_value as Dictionary
		known_places[String(place.get("name", ""))] = true
	var known_spaces := {}
	for space_value: Variant in world_data.get("mapSpaces", []) as Array:
		known_spaces[String((space_value as Dictionary).get("id", ""))] = true
	var expected_ids := OPENING_CONFIG.resident_ids(opening_config)
	var known_people := {}
	for resident_value: Variant in opening_config.get("residents", []) as Array:
		var opening_resident := resident_value as Dictionary
		known_people[String(opening_resident.get("residentId", ""))] = String(
			(opening_resident.get("attributes", {}) as Dictionary).get(
				"name",
				"",
			),
		)
	var avatar_record := opening_config.get("playerAvatar", {}) as Dictionary
	known_people[String(avatar_record.get("residentId", ""))] = String(
		avatar_record.get("name", ""),
	)
	var restored_residents := {}
	var restored_ids: Array[String] = []
	var saved_residents_value: Variant = state.get("residents")
	if not saved_residents_value is Array:
		errors.append("世界存档 residents 必须是数组")
	var saved_residents := (
		saved_residents_value as Array if saved_residents_value is Array else []
	)
	var requires_activity_state := state.has("activityRuntime")
	for index in saved_residents.size():
		var resident_value: Variant = saved_residents[index]
		if typeof(resident_value) != TYPE_DICTIONARY:
			errors.append("世界存档 residents[%d] 必须是对象" % index)
			continue
		var saved := resident_value as Dictionary
		var expected_resident_fields := SAVED_RESIDENT_FIELDS.duplicate()
		if requires_activity_state:
			expected_resident_fields.append("activityState")
		if saved.has("attendanceState"):
			expected_resident_fields.append("attendanceState")
		if saved.has("arrivalState"):
			expected_resident_fields.append("arrivalState")
		_validate_exact_keys(
			saved,
			expected_resident_fields,
			"世界存档 residents[%d]" % index,
			errors,
		)
		var resident_id := String(saved.get("residentId", "")).strip_edges() if saved.get("residentId") is String else ""
		if not expected_ids.has(resident_id):
			errors.append("世界存档包含未知居民 ID：%s" % resident_id)
			continue
		if restored_residents.has(resident_id):
			errors.append("世界存档居民 ID 重复：%s" % resident_id)
			continue
		var opening_record := OPENING_CONFIG.resident_record(opening_config, resident_id)
		var resident_name := String(opening_record.get("attributes", {}).get("name", ""))
		if not saved.get("name") is String or saved.get("name") != resident_name:
			errors.append("世界存档居民 %s 的显示名称与恢复配置不一致" % resident_id)
		var resident_error_count := errors.size()
		_validate_saved_resident(
			resident_id,
			saved,
			world_data,
			known_places,
			known_spaces,
			known_people,
			requires_activity_state,
			errors,
		)
		if errors.size() == resident_error_count:
			restored_residents[resident_id] = _resident_runtime(
				opening_record,
				saved,
				resident_id,
			)
		restored_ids.append(resident_id)
	restored_ids.sort()
	if restored_ids != expected_ids:
		errors.append("世界存档居民 ID 集合与恢复配置不一致")
	var player_saved_value: Variant = state.get("playerAvatar")
	if not player_saved_value is Dictionary:
		errors.append("世界存档 playerAvatar 必须是对象")
	var player_saved := (
		player_saved_value as Dictionary
		if player_saved_value is Dictionary
		else {}
	)
	var avatar_error_count := errors.size()
	_validate_saved_avatar(player_saved, opening_config, world_data, known_places, known_spaces, errors)
	var restored_avatar := {}
	if errors.size() == avatar_error_count:
		restored_avatar = _avatar_runtime(
			opening_config.get("playerAvatar", {}) as Dictionary,
			player_saved,
		)
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	return {
		"ok": true,
		"residents": restored_residents,
		"residentOrder": restored_ids,
		"playerAvatar": restored_avatar,
	}


static func _validate_saved_resident(
	resident_id: String,
	saved: Dictionary,
	world_data: Dictionary,
	known_places: Dictionary,
	known_spaces: Dictionary,
	known_people: Dictionary,
	requires_activity_state: bool,
	errors: Array[String],
) -> void:
	if typeof(saved.get("movementRevision")) != TYPE_INT or int(saved.get("movementRevision", 0)) <= 0:
		errors.append("世界存档居民 %s 的 movementRevision 无效" % resident_id)
	if not (saved.get("position") is Vector2) or not _finite_vector(saved.get("position")):
		errors.append("世界存档居民 %s 的位置无效" % resident_id)
	if not _nonempty_string(saved.get("spaceId")) or not known_spaces.has(saved.get("spaceId")):
		errors.append("世界存档居民 %s 位于未知地图空间" % resident_id)
	if not _nonempty_string(saved.get("regionId")):
		errors.append("世界存档居民 %s 缺少感知区域" % resident_id)
	if not _nonempty_string(saved.get("currentPlace")) or not known_places.has(saved.get("currentPlace")):
		errors.append("世界存档居民 %s 位于未知地点" % resident_id)
	if (
		saved.get("position") is Vector2
		and saved.get("spaceId") is String
		and saved.get("regionId") is String
		and saved.get("currentPlace") is String
	):
		_validate_membership(resident_id, saved, world_data, errors)
		for movement_error in CHARACTER_MOVEMENT_QUERY.validate_position_state(
			world_data,
			{
				"position": saved.get("position"),
				"spaceId": saved.get("spaceId"),
				"regionId": saved.get("regionId"),
				"place": saved.get("currentPlace"),
			},
		):
			errors.append(
				"世界存档居民 %s 的权威位置无效：%s"
				% [resident_id, movement_error]
			)
	if not _nonempty_string(saved.get("doing")):
		errors.append("世界存档居民 %s 缺少当前行为" % resident_id)
	if saved.has("arrivalState"):
		_validate_arrival_state(
			resident_id,
			saved.get("arrivalState"),
			errors,
		)
	var social_value: Variant = saved.get("socialState")
	if not social_value is Dictionary:
		errors.append("世界存档居民 %s 的 socialState 必须是对象" % resident_id)
	var social := social_value as Dictionary if social_value is Dictionary else {}
	_validate_exact_keys(social, ["home", "job", "workplace"], "世界存档居民 %s 的 socialState" % resident_id, errors)
	for key in ["home", "workplace"]:
		if not _nonempty_string(social.get(key)) or not known_places.has(social.get(key)):
			errors.append("世界存档居民 %s 的 %s 不是已知地点" % [resident_id, key])
	if not _nonempty_string(social.get("job")):
		errors.append("世界存档居民 %s 缺少职业" % resident_id)
	if saved.has("profileAttributes"):
		var profile_value: Variant = saved.get("profileAttributes")
		if not profile_value is Dictionary:
			errors.append("世界存档居民 %s 的 profileAttributes 必须是对象" % resident_id)
		else:
			var profile := profile_value as Dictionary
			var expected_profile_keys: Array[String] = [
				"gender",
				"age",
				"appearance",
				"desire",
				"personality",
				"speech",
				"interests",
				"customInterests",
			]
			# 历代存档共 6 组合法键集,穷举等价于:核心五键必填、
			# appearance/interests 可选、customInterests 仅可伴随 interests。
			var core_profile_keys: Array[String] = [
				"gender",
				"age",
				"desire",
				"personality",
				"speech",
			]
			var profile_keys_valid := true
			for profile_key: Variant in profile:
				if (
					not profile_key is String
					or not expected_profile_keys.has(String(profile_key))
				):
					profile_keys_valid = false
			for core_key in core_profile_keys:
				if not profile.has(core_key):
					profile_keys_valid = false
			if (
				profile.has("customInterests")
				and not profile.has("interests")
			):
				profile_keys_valid = false
			if not profile_keys_valid:
				errors.append(
					"世界存档居民 %s 的 profileAttributes 字段不完整"
					% resident_id,
				)
			if _string_or_empty(profile.get("gender")) not in ["男", "女"]:
				errors.append("世界存档居民 %s 的性别无效" % resident_id)
			var profile_age_value: Variant = profile.get("age")
			if (
				typeof(profile_age_value) != TYPE_INT
				or int(profile_age_value) < 1
				or int(profile_age_value) > 120
			):
				errors.append("世界存档居民 %s 的年龄无效" % resident_id)
			for key in ["desire", "personality", "speech"]:
				if not _nonempty_string(profile.get(key)):
					errors.append(
						"世界存档居民 %s 的 %s 资料为空" % [resident_id, key],
					)
			var interest_error := INTERESTS.profile_validation_error(
				profile.get("interests", []),
				profile.get("customInterests", []),
			)
			if not interest_error.is_empty():
				errors.append(
					"世界存档居民 %s 的兴趣无效：%s"
					% [resident_id, interest_error],
				)
			if profile.has("appearance"):
				var appearance_value: Variant = profile.get("appearance")
				if (
					not appearance_value is String
					or (
						not String(appearance_value).is_empty()
						and not String(appearance_value).begins_with(
							"resident_wardrobe_v1:",
						)
					)
				):
					errors.append("世界存档居民 %s 的正式外观无效" % resident_id)
	var body_value: Variant = saved.get("body")
	if not body_value is Dictionary:
		errors.append("世界存档居民 %s 的 body 必须是对象" % resident_id)
	var body := body_value as Dictionary if body_value is Dictionary else {}
	for body_name: String in BODY_LEVELS:
		if not (BODY_LEVELS[body_name] as Array).has(
			_string_or_empty(body.get(body_name))
		):
			errors.append("世界存档居民 %s 的身体状态无效：%s" % [resident_id, body_name])
	for body_name_value: Variant in body:
		if not body_name_value is String or not BODY_LEVELS.has(body_name_value as String):
			errors.append("世界存档居民 %s 包含未知身体状态：%s" % [resident_id, str(body_name_value)])
	if requires_activity_state:
		var activity_state_value: Variant = saved.get("activityState")
		if not activity_state_value is Dictionary:
			errors.append(
				"世界存档居民 %s 的 activityState 必须是对象"
				% resident_id
			)
		else:
			var activity_state := activity_state_value as Dictionary
			_validate_exact_keys(
				activity_state,
				ACTIVITY_STATE_KEYS,
				"世界存档居民 %s 的 activityState" % resident_id,
				errors,
			)
			for key in ACTIVITY_STATE_KEYS:
				if typeof(activity_state.get(key)) != TYPE_INT:
					errors.append(
						"世界存档居民 %s 的 activityState.%s 必须是整数"
						% [resident_id, key]
					)
				elif (
					int(activity_state.get(key, -1)) < 0
					or int(activity_state.get(key, 101)) > 100
				):
					errors.append(
						"世界存档居民 %s 的 activityState.%s 必须在 0..100"
						% [resident_id, key]
					)
	if saved.has("attendanceState"):
		var attendance_value: Variant = saved.get("attendanceState")
		if not attendance_value is Dictionary:
			errors.append(
				"世界存档居民 %s 的 attendanceState 必须是对象"
				% resident_id,
			)
		else:
			var attendance := attendance_value as Dictionary
			_validate_exact_keys(
				attendance,
				["status", "untilMinute"],
				"世界存档居民 %s 的 attendanceState" % resident_id,
				errors,
			)
			if String(attendance.get("status", "")) not in [
				"available",
				"on_leave",
			]:
				errors.append(
					"世界存档居民 %s 的 attendanceState.status 无效"
					% resident_id,
				)
			if typeof(attendance.get("untilMinute")) != TYPE_INT:
				errors.append(
					"世界存档居民 %s 的 attendanceState.untilMinute 必须是整数"
					% resident_id,
				)
			elif (
				String(attendance.get("status", "")) == "on_leave"
				and int(attendance.get("untilMinute", -1)) < 0
			) or (
				String(attendance.get("status", "")) == "available"
				and int(attendance.get("untilMinute", -1)) != -1
			):
				errors.append(
					"世界存档居民 %s 的 attendanceState 时间关系无效"
					% resident_id,
				)
	var current_action_value: Variant = saved.get("currentAction")
	var current_action := (
		current_action_value as Dictionary
		if current_action_value is Dictionary
		else {}
	)
	if not current_action_value is Dictionary:
		errors.append("世界存档居民 %s 的当前动作必须是对象" % resident_id)
	else:
		_validate_saved_action(
			resident_id,
			current_action,
			known_people,
			errors,
		)
	var preview := (
		saved.get("confirmedActionPreview", {}) as Dictionary
		if saved.get("confirmedActionPreview") is Dictionary
		else {}
	)
	if saved.has("confirmedActionPreview") and not saved.get("confirmedActionPreview") is Dictionary:
		errors.append("世界存档居民 %s 的确认动作预告必须是对象" % resident_id)
	else:
		var preview_error_count := errors.size()
		_validate_saved_action_preview(
			resident_id,
			preview,
			known_people,
			errors,
		)
		if (
			errors.size() == preview_error_count
			and not preview.is_empty()
			and _string_or_empty(preview.get("handling")) == "replace_current"
			and preview.get("action") is Dictionary
			and saved.get("routeConnector") is Array
			and _route_inputs_have_valid_containers(
				preview.get("action") as Dictionary
			)
		):
			var preview_route_state := saved.duplicate(true)
			preview_route_state["currentAction"] = (
				preview.get("action", {}) as Dictionary
			).duplicate(true)
			for movement_error in CHARACTER_MOVEMENT_QUERY.validate_saved_route(
				world_data,
				resident_id,
				preview_route_state,
			):
				errors.append(String(movement_error))
	var suspended_minute := -1
	if (
		saved.has("actionSuspendedAbsoluteMinute")
		and typeof(saved.get("actionSuspendedAbsoluteMinute")) != TYPE_INT
	):
		errors.append("世界存档居民 %s 的动作挂起时间必须是整数" % resident_id)
	else:
		suspended_minute = int(saved.get("actionSuspendedAbsoluteMinute", -1))
		if suspended_minute < -1:
			errors.append("世界存档居民 %s 的动作挂起时间无效" % resident_id)
		elif (
			current_action.is_empty()
			and suspended_minute >= 0
		):
			errors.append("世界存档居民 %s 没有当前动作却保留了挂起时间" % resident_id)
	if typeof(saved.get("routeConnector")) != TYPE_ARRAY:
		errors.append("世界存档居民 %s 的返程路径必须是数组" % resident_id)
	else:
		for point_value: Variant in saved.get("routeConnector", []) as Array:
			if not (point_value is Vector2) or not _finite_vector(point_value):
				errors.append("世界存档居民 %s 的返程路径包含无效坐标" % resident_id)
	if (
		current_action_value is Dictionary
		and saved.get("routeConnector") is Array
		and _route_inputs_have_valid_containers(current_action)
	):
		for movement_error in CHARACTER_MOVEMENT_QUERY.validate_saved_route(
			world_data,
			resident_id,
			saved,
		):
			errors.append(String(movement_error))
	var pending_result_action_ids: Array[String] = []
	for key in ["pendingEvents", "pendingActionResults"]:
		if typeof(saved.get(key)) != TYPE_ARRAY:
			errors.append("世界存档居民 %s 的 %s 必须是数组" % [resident_id, key])
			continue
		var pending_ids := {}
		for value: Variant in saved.get(key, []) as Array:
			if typeof(value) != TYPE_DICTIONARY:
				errors.append("世界存档居民 %s 的 %s 包含非对象" % [resident_id, key])
			elif key == "pendingEvents":
				var event := value as Dictionary
				var event_id := _string_or_empty(event.get("event_id"))
				if pending_ids.has(event_id):
					errors.append("世界存档居民 %s 的待交付事件编号重复：%s" % [resident_id, event_id])
				pending_ids[event_id] = true
				_validate_pending_event(
					resident_id,
					event,
					known_places,
					known_people,
					errors,
				)
			else:
				var action_result := value as Dictionary
				var action_id := _string_or_empty(action_result.get("action_id"))
				pending_result_action_ids.append(action_id)
				if pending_ids.has(action_id):
					errors.append("世界存档居民 %s 的待交付动作结果编号重复：%s" % [resident_id, action_id])
				pending_ids[action_id] = true
				_validate_pending_action_result(resident_id, action_result, errors)
	if typeof(saved.get("usedActionIds")) != TYPE_ARRAY:
		errors.append("世界存档居民 %s 的 usedActionIds 必须是数组" % resident_id)
	else:
		var seen_action_ids := {}
		for action_id_value: Variant in saved.get("usedActionIds", []) as Array:
			var action_id := String(action_id_value).strip_edges() if action_id_value is String else ""
			if action_id.is_empty() or seen_action_ids.has(action_id):
				errors.append("世界存档居民 %s 的 usedActionIds 无效或重复" % resident_id)
			else:
				seen_action_ids[action_id] = true
		if (
			not current_action.is_empty()
			and not seen_action_ids.has(
				_string_or_empty(current_action.get("action_id"))
			)
		):
			errors.append("世界存档居民 %s 的当前动作未登记在 usedActionIds" % resident_id)
		if (
			not preview.is_empty()
			and _string_or_empty(preview.get("handling")) == "replace_current"
			and not seen_action_ids.has(
				_string_or_empty(preview.get("actionId"))
			)
		):
			errors.append("世界存档居民 %s 的确认预告动作未登记在 usedActionIds" % resident_id)
		for pending_action_id in pending_result_action_ids:
			if not seen_action_ids.has(pending_action_id):
				errors.append(
					"世界存档居民 %s 的待交付动作结果未登记在 usedActionIds：%s"
					% [resident_id, pending_action_id]
				)
	if typeof(saved.get("conversation")) not in [TYPE_NIL, TYPE_DICTIONARY]:
		errors.append("世界存档居民 %s 的对话快照无效" % resident_id)
	if not saved.get("conversationId") is String:
		errors.append("世界存档居民 %s 的 conversationId 必须是文本" % resident_id)
	elif not current_action.is_empty():
		var saved_conversation_id := String(saved.get("conversationId", ""))
		var action_type := _string_or_empty(current_action.get("type"))
		var action_conversation_id := (
			_string_or_empty(current_action.get("conversationId"))
			if action_type == "搭话"
			else _string_or_empty(current_action.get("conversation_id"))
			if action_type == "答话"
			else ""
		)
		if (
			action_type in ["搭话", "答话"]
			and saved_conversation_id != action_conversation_id
		):
			errors.append(
				"世界存档居民 %s 的当前对话动作与 conversationId 不一致"
				% resident_id
			)


static func _validate_saved_avatar(
	saved: Dictionary,
	opening_config: Dictionary,
	world_data: Dictionary,
	known_places: Dictionary,
	known_spaces: Dictionary,
	errors: Array[String],
) -> void:
	_validate_exact_keys(saved, SAVED_AVATAR_FIELDS, "世界存档 playerAvatar", errors)
	var expected_name := String((opening_config.get("playerAvatar", {}) as Dictionary).get("name", ""))
	if not saved.get("name") is String or saved.get("name") != expected_name:
		errors.append("世界存档化身名字与恢复配置不一致")
	if not saved.get("residentId") is String or saved.get("residentId") != String((opening_config.get("playerAvatar", {}) as Dictionary).get("residentId", "person_7f3a91c2d8e4")):
		errors.append("世界存档化身 residentId 与恢复配置不一致")
	if not (saved.get("position") is Vector2) or not _finite_vector(saved.get("position")):
		errors.append("世界存档化身位置无效")
	if not _nonempty_string(saved.get("spaceId")) or not known_spaces.has(saved.get("spaceId")):
		errors.append("世界存档化身位于未知地图空间")
	if not _nonempty_string(saved.get("regionId")):
		errors.append("世界存档化身缺少感知区域")
	if not _nonempty_string(saved.get("currentPlace")) or not known_places.has(saved.get("currentPlace")):
		errors.append("世界存档化身位于未知地点")
	_validate_membership("player-avatar", saved, world_data, errors)
	if not _nonempty_string(saved.get("doing")):
		errors.append("世界存档化身缺少当前状态")
	if typeof(saved.get("conversation")) not in [TYPE_NIL, TYPE_DICTIONARY]:
		errors.append("世界存档化身对话快照无效")
	if not saved.get("conversationId") is String:
		errors.append("世界存档化身 conversationId 必须是文本")
	if typeof(saved.get("nearby")) != TYPE_ARRAY:
		errors.append("世界存档化身 nearby 必须是数组")


static func _validate_saved_action(
	resident_id: String,
	action: Dictionary,
	known_people: Dictionary,
	errors: Array[String],
) -> void:
	if action.is_empty():
		return
	var action_type := String(action.get("type", "")) if action.get("type") is String else ""
	if not SAVED_ACTION_FIELDS.has(action_type):
		errors.append("世界存档居民 %s 的当前动作类型无效" % resident_id)
		return
	var expected_fields := (
		SAVED_ACTION_FIELDS[action_type] as Array
	).duplicate()
	var postal_talk_approach_mode := (
		String(action.get("approachMode", ""))
		if action_type == "搭话"
		else ""
	)
	var is_talk_approach := postal_talk_approach_mode in [
		"same_space_path",
		"place_route",
	]
	var is_conversation_follow_up_approach := (
		is_talk_approach
		and not String(action.get("conversationFollowUpMode", "")).is_empty()
	)
	var is_postal_talk_approach := (
		is_talk_approach
		and not is_conversation_follow_up_approach
	)
	if is_talk_approach:
		expected_fields.erase("conversationId")
		expected_fields.append_array([
			"approachMode",
			"targetSpaceId",
			"targetRegionId",
			"targetPlace",
			"expectedTargetPosition",
			"durationMinutes",
			"consumeRouteConnector",
		])
		if is_postal_talk_approach:
			expected_fields.append("privateMessageId")
		if postal_talk_approach_mode == "same_space_path":
			expected_fields.append_array([
				"pathPoints",
				"targetPosition",
				"returnRouteConnector",
			])
		else:
			expected_fields.append("approachRoute")
	if action_type == "搭话" and (
		action.has("medicalRequestId")
		or action.has("medicalTaskId")
	):
		expected_fields.append_array([
			"medicalRequestId",
			"medicalTaskId",
		])
	if action_type == "答话" and action.has("medical_response"):
		expected_fields.append("medical_response")
	if action.has("conversationFollowUpMode"):
		expected_fields.append_array(
			CONVERSATION_FOLLOW_UP_ACTION_FIELDS,
		)
	var has_idle_parking := (
		action_type == "待着"
		and (
			action.has("idlePathPoints")
			or action.has("idleTargetPosition")
			or action.has("idleMoveDurationMinutes")
		)
	)
	if has_idle_parking:
		expected_fields.append_array([
			"idlePathPoints",
			"idleTargetPosition",
			"idleMoveDurationMinutes",
		])
	var is_service_wait := (
		action_type == "待着"
		and String(action.get("action_id", "")).begins_with(
			"service-wait:",
		)
	)
	if is_service_wait:
		expected_fields.append("serviceRequestId")
	if action_type == "待着" and action.has("decisionBridge"):
		expected_fields.append("decisionBridge")
	if action_type == "用道具" and action.has("pathClearanceVerified"):
		expected_fields.append("pathClearanceVerified")
	var is_performance_wait := (
		action_type == "待着"
		and String(action.get("action_id", "")).begins_with(
			"performance-listen:",
		)
	)
	if is_performance_wait:
		expected_fields.append_array([
			"performanceDayIndex",
			"performanceEventId",
		])
	var is_activity_action := (
		action_type == "用道具"
		and action.has("sourceContract")
	)
	if is_activity_action:
		expected_fields.append_array([
			"sourceContract",
			"sourceActionId",
		])
	if (
		action_type == "搭话"
		and action.has("line")
		and _dictionary_has_exact_keys(
			action,
			expected_fields + ["line"],
		)
	):
		# Compatibility with early schema-v1 saves.  The formal talk action no
		# longer carries the redundant line field; say/narration are authoritative.
		pass
	else:
		_validate_exact_keys(
			action,
			expected_fields,
			"世界存档居民 %s 的当前动作" % resident_id,
			errors,
		)
	if not _nonempty_string(action.get("action_id")):
		errors.append("世界存档居民 %s 的当前动作缺少 action_id" % resident_id)
	if typeof(action.get("startedAbsoluteMinute")) != TYPE_INT or int(action.get("startedAbsoluteMinute", -1)) < 0:
		errors.append("世界存档居民 %s 的当前动作开始时间无效" % resident_id)
	if action_type in ["去", "用道具", "待着"] and not _nonempty_string(action.get("line")):
		errors.append("世界存档居民 %s 的当前动作缺少 line" % resident_id)
	if is_service_wait and not _nonempty_string(action.get("serviceRequestId")):
		errors.append("世界存档居民 %s 的服务等待动作缺少请求编号" % resident_id)
	if is_performance_wait:
		if (
			typeof(action.get("performanceDayIndex")) != TYPE_INT
			or int(action.get("performanceDayIndex", -1)) < 0
		):
			errors.append("世界存档居民 %s 的演出等待日期无效" % resident_id)
		if not _nonempty_string(action.get("performanceEventId")):
			errors.append("世界存档居民 %s 的演出等待事件无效" % resident_id)
	if action.has("decisionBridge") and typeof(action.get("decisionBridge")) != TYPE_BOOL:
		errors.append("世界存档居民 %s 的决策过渡标记无效" % resident_id)
	if action.has("pathClearanceVerified") and typeof(action.get("pathClearanceVerified")) != TYPE_BOOL:
		errors.append("世界存档居民 %s 的路径净空标记无效" % resident_id)
	match action_type:
		"去":
			if not _nonempty_string(action.get("place")):
				errors.append("世界存档居民 %s 的移动目标无效" % resident_id)
			if typeof(action.get("durationMinutes")) != TYPE_INT or int(action.get("durationMinutes", 0)) <= 0:
				errors.append("世界存档居民 %s 的移动时长无效" % resident_id)
			if typeof(action.get("route")) != TYPE_DICTIONARY or typeof(action.get("completionEffects")) != TYPE_DICTIONARY:
				errors.append("世界存档居民 %s 的移动路线或效果无效" % resident_id)
			elif action.get("completionEffects") is Dictionary:
				_validate_body_effects(
					resident_id,
					action.get("completionEffects") as Dictionary,
					errors,
				)
			if typeof(action.get("consumeRouteConnector")) != TYPE_BOOL:
				errors.append("世界存档居民 %s 的移动连接标记无效" % resident_id)
		"用道具":
			if is_activity_action:
				var source_contract := String(
					action.get("sourceContract", "")
				)
				var source_action_id := String(
					action.get("sourceActionId", "")
				)
				if (
					not action.get("sourceContract") is String
					or not action.get("sourceActionId") is String
					or (
						source_contract == "activity.perform"
						and not source_action_id.is_empty()
					)
						or (
							source_contract == "legacy.agent.use_prop"
							and (
								source_action_id.is_empty()
								or source_action_id
								!= source_action_id.strip_edges()
							)
						)
						or (
							source_contract == "agent.activity"
							and (
								source_action_id.is_empty()
								or source_action_id
								!= source_action_id.strip_edges()
							)
						)
						or source_contract not in [
							"activity.perform",
							"legacy.agent.use_prop",
							"agent.activity",
						]
					):
					errors.append(
						"世界存档居民 %s 的活动来源合同无效"
						% resident_id
					)
			for key in ["prop", "verb", "sourcePlace"]:
				if not _nonempty_string(action.get(key)):
					errors.append("世界存档居民 %s 的道具动作 %s 无效" % [resident_id, key])
			if not action.get("dynamicPropId") is String:
				errors.append("世界存档居民 %s 的动态道具 ID 必须是文本" % resident_id)
			if typeof(action.get("durationMinutes")) != TYPE_INT or int(action.get("durationMinutes", 0)) <= 0:
				errors.append("世界存档居民 %s 的道具动作时长无效" % resident_id)
			if (
				typeof(action.get("pathPoints")) != TYPE_ARRAY
				or (action.get("pathPoints", []) as Array).is_empty()
				or typeof(action.get("returnRouteConnector")) != TYPE_ARRAY
			):
				errors.append("世界存档居民 %s 的道具动作路径无效" % resident_id)
			if not action.get("targetPosition") is Vector2 or not _finite_vector(action.get("targetPosition")):
				errors.append("世界存档居民 %s 的道具目标坐标无效" % resident_id)
			elif (
				action.get("pathPoints") is Array
				and not (action.get("pathPoints", []) as Array).is_empty()
				and (action.get("pathPoints", []) as Array)[-1] is Vector2
				and (
					(action.get("pathPoints", []) as Array)[-1] as Vector2
				).distance_to(action.get("targetPosition") as Vector2) > 0.01
			):
				errors.append("世界存档居民 %s 的道具路径终点与目标坐标不一致" % resident_id)
			if (
				typeof(action.get("effects")) != TYPE_DICTIONARY
				or typeof(action.get("consumeRouteConnector")) != TYPE_BOOL
			):
				errors.append("世界存档居民 %s 的道具动作效果无效" % resident_id)
			elif action.get("effects") is Dictionary:
				_validate_body_effects(
					resident_id,
					action.get("effects") as Dictionary,
					errors,
				)
		"待着":
			if typeof(action.get("completeAbsoluteMinute")) != TYPE_INT or int(action.get("completeAbsoluteMinute", -1)) <= int(action.get("startedAbsoluteMinute", -1)):
				errors.append("世界存档居民 %s 的等待结束时间无效" % resident_id)
			if has_idle_parking:
				var path_value: Variant = action.get("idlePathPoints")
				var target_value: Variant = action.get(
					"idleTargetPosition"
				)
				var duration_value: Variant = action.get(
					"idleMoveDurationMinutes"
				)
				var path_valid := (
					path_value is Array
					and not (path_value as Array).is_empty()
				)
				if path_valid:
					for point_value: Variant in path_value as Array:
						if (
							point_value is not Vector2
							or not _finite_vector(point_value)
						):
							path_valid = false
							break
				if (
					not path_valid
					or target_value is not Vector2
					or not _finite_vector(target_value)
					or typeof(duration_value) != TYPE_INT
					or int(duration_value) <= 0
				):
					errors.append(
						"世界存档居民 %s 的门口退让路径无效"
						% resident_id
					)
				elif (
					(path_value as Array)[-1] as Vector2
				).distance_to(target_value as Vector2) > 0.01:
					errors.append(
						"世界存档居民 %s 的门口退让终点无效"
						% resident_id
					)
		"搭话", "答话":
			if typeof(action.get("say")) != TYPE_STRING or typeof(action.get("narration")) != TYPE_STRING:
				errors.append("世界存档居民 %s 的对话动作文本无效" % resident_id)
			_validate_photos(
				resident_id,
				action.get("photos"),
				"对话动作",
				errors,
			)
			if action_type == "搭话":
				var has_medical_request := action.has("medicalRequestId")
				var has_medical_task := action.has("medicalTaskId")
				if has_medical_request != has_medical_task:
					errors.append(
						"世界存档居民 %s 的医患搭话缺少请求或任务编号"
						% resident_id
					)
				elif has_medical_request and (
					not _nonempty_string(action.get("medicalRequestId"))
					or not _nonempty_string(action.get("medicalTaskId"))
				):
					errors.append(
						"世界存档居民 %s 的医患搭话编号无效"
						% resident_id
					)
				var target_id := _string_or_empty(
					action.get("target_resident_id")
				)
				if (
					target_id == resident_id
					or not known_people.has(target_id)
					or action.get("target") != known_people.get(target_id)
				):
					errors.append(
						"世界存档居民 %s 的搭话对象身份无效"
						% resident_id
					)
				if not is_talk_approach and (
					_sequence_from_id(
						_string_or_empty(action.get("conversationId")),
						"conversation-",
					) <= 0
				):
					errors.append(
						"世界存档居民 %s 的搭话 conversationId 无效"
						% resident_id
					)
				if is_talk_approach and (
					typeof(action.get("durationMinutes")) != TYPE_INT
					or int(action.get("durationMinutes", -1)) < 0
					or typeof(action.get("consumeRouteConnector")) != TYPE_BOOL
				):
					errors.append(
						"世界存档居民 %s 的接近动作无效" % resident_id
					)
				if (
					is_postal_talk_approach
					and not _nonempty_string(action.get("privateMessageId"))
				):
					errors.append(
						"世界存档居民 %s 的邮差接近动作缺少口信编号" % resident_id
					)
				if (
					is_talk_approach
					and postal_talk_approach_mode == "same_space_path"
					and (
						typeof(action.get("pathPoints")) != TYPE_ARRAY
						or (action.get("pathPoints", []) as Array).is_empty()
						or action.get("targetPosition") is not Vector2
						or typeof(action.get("returnRouteConnector")) != TYPE_ARRAY
					)
				):
					errors.append(
						"世界存档居民 %s 的邮差接近路径无效" % resident_id
					)
				if (
					is_talk_approach
					and postal_talk_approach_mode == "place_route"
					and typeof(action.get("approachRoute")) != TYPE_DICTIONARY
				):
					errors.append(
						"世界存档居民 %s 的邮差跨地点路线无效" % resident_id
					)
			if action_type == "答话" and (
				_sequence_from_id(
					_string_or_empty(action.get("conversation_id")),
					"conversation-",
				) <= 0
				or typeof(action.get("end")) != TYPE_BOOL
			):
				errors.append("世界存档居民 %s 的答话上下文无效" % resident_id)
			if action_type == "答话" and action.has("medical_response"):
				var medical_response: Variant = action.get("medical_response")
				if (
					not medical_response is Dictionary
					or (medical_response as Dictionary).size() != 2
					or not _nonempty_string(
						(medical_response as Dictionary).get("request_id"),
					)
					or String(
						(medical_response as Dictionary).get(
							"response_kind",
							"",
						),
					) not in ["describe", "decline"]
				):
					errors.append(
						"世界存档居民 %s 的医患答话回应无效"
						% resident_id
					)


static func _validate_saved_action_preview(
	resident_id: String,
	preview: Dictionary,
	known_people: Dictionary,
	errors: Array[String],
) -> void:
	if preview.is_empty():
		return
	_validate_exact_keys(
		preview,
		[
			"previewId",
			"decisionId",
			"actionId",
			"handling",
			"summary",
			"confirmedRevision",
			"confirmedAt",
			"displaySeconds",
			"holdSeconds",
			"remainingSeconds",
			"conversationEndReason",
			"action",
		],
		"世界存档居民 %s 的确认动作预告" % resident_id,
		errors,
	)
	for key in [
		"previewId",
		"decisionId",
		"actionId",
		"handling",
		"summary",
		"conversationEndReason",
	]:
		if not preview.get(key) is String:
			errors.append("世界存档居民 %s 的确认动作预告 %s 必须是文本" % [resident_id, key])
	var decision_id := _string_or_empty(preview.get("decisionId"))
	var action_id := _string_or_empty(preview.get("actionId"))
	if decision_id.strip_edges().is_empty() or action_id.strip_edges().is_empty():
		errors.append("世界存档居民 %s 的确认动作预告缺少稳定决定或动作编号" % resident_id)
	if _string_or_empty(preview.get("previewId")) != "%s::%s" % [decision_id, action_id]:
		errors.append("世界存档居民 %s 的确认动作预告编号与决定/动作不一致" % resident_id)
	if _string_or_empty(preview.get("handling")) not in ["continue_current", "replace_current"]:
		errors.append("世界存档居民 %s 的确认动作预告 handling 无效" % resident_id)
	var summary := _string_or_empty(preview.get("summary"))
	if summary.strip_edges().is_empty() or summary.length() > 48:
		errors.append("世界存档居民 %s 的确认动作预告摘要无效" % resident_id)
	if (
		typeof(preview.get("confirmedRevision")) != TYPE_INT
		or int(preview.get("confirmedRevision", 0)) <= 0
	):
		errors.append("世界存档居民 %s 的确认动作预告 revision 无效" % resident_id)
	errors.append_array(
		SAVE_CODEC.validate_time_snapshot(
			preview.get("confirmedAt"),
			"世界存档居民 %s 的确认动作预告确认时间" % resident_id,
		),
	)
	for key in ["displaySeconds", "holdSeconds", "remainingSeconds"]:
		if (
			typeof(preview.get(key)) not in [TYPE_INT, TYPE_FLOAT]
			or not is_finite(float(preview.get(key, NAN)))
		):
			errors.append("世界存档居民 %s 的确认动作预告 %s 无效" % [resident_id, key])
	var hold_seconds := _finite_number_or_zero(preview.get("holdSeconds"))
	var display_seconds := _finite_number_or_zero(preview.get("displaySeconds"))
	var remaining_seconds := _finite_number_or_zero(
		preview.get("remainingSeconds")
	)
	if (
		not is_finite(display_seconds)
		or display_seconds <= 0.0
		or hold_seconds <= 0.0
		or remaining_seconds <= 0.0
		or remaining_seconds > display_seconds
	):
		errors.append("世界存档居民 %s 的确认动作预告剩余时长无效" % resident_id)
	if not preview.get("action") is Dictionary:
		errors.append("世界存档居民 %s 的确认动作预告缺少已确认动作" % resident_id)
		return
	var action := preview.get("action", {}) as Dictionary
	_validate_saved_action(resident_id, action, known_people, errors)
	if _string_or_empty(action.get("action_id")) != action_id:
		errors.append("世界存档居民 %s 的确认动作预告 actionId 与动作不一致" % resident_id)


static func _validate_body_effects(
	resident_id: String,
	effects: Dictionary,
	errors: Array[String],
) -> void:
	for key_value: Variant in effects:
		if (
			not key_value is String
			or not BODY_LEVELS.has(key_value as String)
			or typeof(effects[key_value]) != TYPE_INT
			or int(effects[key_value]) < -2
			or int(effects[key_value]) > 2
		):
			errors.append(
				"世界存档居民 %s 的身体效果无效：%s"
				% [resident_id, str(key_value)]
			)


static func _validate_photos(
	resident_id: String,
	photos_value: Variant,
	label: String,
	errors: Array[String],
) -> void:
	if not photos_value is Array:
		errors.append(
			"世界存档居民 %s 的%s照片必须是数组"
			% [resident_id, label]
		)
		return
	for photo_index in (photos_value as Array).size():
		var photo_value: Variant = (photos_value as Array)[photo_index]
		if not photo_value is Dictionary:
			errors.append(
				"世界存档居民 %s 的%s照片[%d] 必须是对象"
				% [resident_id, label, photo_index]
			)
			continue
		var photo := photo_value as Dictionary
		_validate_exact_keys(
			photo,
			["ref", "mime_type"],
			"世界存档居民 %s 的%s照片[%d]"
			% [resident_id, label, photo_index],
			errors,
		)
		if (
			not _nonempty_string(photo.get("ref"))
			or not _nonempty_string(photo.get("mime_type"))
		):
			errors.append(
				"世界存档居民 %s 的%s照片[%d] 无效"
				% [resident_id, label, photo_index]
			)


static func _validate_arrival_state(
	resident_id: String,
	value: Variant,
	errors: Array[String],
) -> void:
	if not value is Dictionary:
		errors.append(
			"世界存档居民 %s 的 arrivalState 必须是对象"
			% resident_id
		)
		return
	var arrival := value as Dictionary
	_validate_exact_keys(
		arrival,
		[
			"status",
			"scheduledAbsoluteMinute",
			"arrivedAbsoluteMinute",
		],
		"世界存档居民 %s 的 arrivalState" % resident_id,
		errors,
	)
	var status := String(arrival.get("status", ""))
	var scheduled_value: Variant = arrival.get(
		"scheduledAbsoluteMinute",
	)
	var arrived_value: Variant = arrival.get(
		"arrivedAbsoluteMinute",
	)
	if (
		status not in ["pending", "arrived"]
		or typeof(scheduled_value) != TYPE_INT
		or typeof(arrived_value) != TYPE_INT
	):
		errors.append(
			"世界存档居民 %s 的 arrivalState 字段无效"
			% resident_id
		)
		return
	var scheduled := int(scheduled_value)
	var arrived := int(arrived_value)
	if (
		(status == "pending" and (scheduled < 0 or arrived != -1))
		or (
			status == "arrived"
			and (
				scheduled < -1
				or arrived < -1
				or (
					scheduled >= 0
					and arrived < scheduled
				)
			)
		)
	):
		errors.append(
			"世界存档居民 %s 的 arrivalState 时间关系无效"
			% resident_id
		)


static func _resident_runtime(record: Dictionary, saved: Dictionary, resident_id: String) -> Dictionary:
	var social_state := saved.get("socialState", {}) as Dictionary if saved.get("socialState") is Dictionary else {}
	var attributes := (record.get("attributes", {}) as Dictionary).duplicate(true)
	if saved.get("profileAttributes") is Dictionary:
		for key_value: Variant in saved.get("profileAttributes", {}) as Dictionary:
			attributes[String(key_value)] = (
				saved.get("profileAttributes", {}) as Dictionary
			)[key_value]
	var body := saved.get("body", {}) as Dictionary if saved.get("body") is Dictionary else {}
	var activity_state := (
		saved.get("activityState", {}) as Dictionary
		if saved.get("activityState") is Dictionary
		else _activity_state_from_body(body)
	)
	var current_action := saved.get("currentAction", {}) as Dictionary if saved.get("currentAction") is Dictionary else {}
	var attendance_state := (
		saved.get("attendanceState", {}) as Dictionary
		if saved.get("attendanceState") is Dictionary
		else {"status": "available", "untilMinute": -1}
	)
	var confirmed_preview := (
		saved.get("confirmedActionPreview", {}) as Dictionary
		if saved.get("confirmedActionPreview") is Dictionary
		else {}
	)
	var route_connector := saved.get("routeConnector", []) as Array if saved.get("routeConnector") is Array else []
	var pending_events := saved.get("pendingEvents", []) as Array if saved.get("pendingEvents") is Array else []
	var pending_results := saved.get("pendingActionResults", []) as Array if saved.get("pendingActionResults") is Array else []
	var used_action_ids := saved.get("usedActionIds", []) as Array if saved.get("usedActionIds") is Array else []
	return {
		"residentId": resident_id,
		"movementRevision": int(saved.get("movementRevision", 1)),
		"attributes": attributes,
		"socialState": social_state.duplicate(true),
		"arrivalState": (
			(saved.get("arrivalState", {}) as Dictionary).duplicate(true)
			if saved.get("arrivalState") is Dictionary
			else {
				"status": "arrived",
				"scheduledAbsoluteMinute": -1,
				"arrivedAbsoluteMinute": -1,
			}
		),
		"position": saved.get("position") as Vector2 if saved.get("position") is Vector2 else Vector2.ZERO,
		"spaceId": String(saved.get("spaceId", "")),
		"regionId": String(saved.get("regionId", "")),
		"currentPlace": String(saved.get("currentPlace", "")),
		"doing": String(saved.get("doing", "")),
		"body": body.duplicate(true),
		"activityState": activity_state.duplicate(true),
		"attendanceState": attendance_state.duplicate(true),
		"nearby": [],
		"currentAction": current_action.duplicate(true),
		"confirmedActionPreview": confirmed_preview.duplicate(true),
		"actionSuspendedAbsoluteMinute": int(
			saved.get("actionSuspendedAbsoluteMinute", -1),
		),
		"routeConnector": route_connector.duplicate(true),
		"conversationId": String(saved.get("conversationId", "")),
		"conversation": _duplicate_optional_dictionary(saved.get("conversation")),
		"eventQueue": pending_events.duplicate(true),
		"resultQueue": pending_results.duplicate(true),
		"usedActionIds": _action_id_set(used_action_ids),
		"lastRejectedActionFingerprint": "",
		"consecutiveRejectedActionCount": 0,
		"decisionSequence": 0,
		"decisionPending": false,
		"validDecisionId": "",
		"pendingWake": {},
		"pendingWakeDirty": false,
		"pendingWakeRefreshOnTake": false,
		"wakeDispatchQueued": false,
		"inflightEvents": [],
		"inflightResults": [],
	}


static func _avatar_runtime(record: Dictionary, saved: Dictionary) -> Dictionary:
	return {
		"residentId": String(record.get("residentId", "person_7f3a91c2d8e4")),
		"name": String(record.get("name", "")),
		"position": saved.get("position") as Vector2 if saved.get("position") is Vector2 else Vector2.ZERO,
		"spaceId": String(saved.get("spaceId", "")),
		"regionId": String(saved.get("regionId", "")),
		"currentPlace": String(saved.get("currentPlace", "")),
		"doing": String(saved.get("doing", "")),
		"nearby": [],
		"conversationId": String(saved.get("conversationId", "")),
		"conversation": _duplicate_optional_dictionary(saved.get("conversation")),
	}


static func _activity_state_from_body(body: Dictionary) -> Dictionary:
	return {
		"energy": _need_value_for_body_level(
			String(body.get("累", "不累")),
		),
		"satiety": _need_value_for_body_level(
			String(body.get("饿", "不饿")),
		),
		"stress": 50,
		"socialNeed": 50,
		"solitudeNeed": 50,
	}


static func _need_value_for_body_level(level: String) -> int:
	if level.begins_with("很"):
		return 20
	if level.begins_with("有点"):
		return 35
	return 50


static func _duplicate_optional_dictionary(value: Variant) -> Variant:
	return (value as Dictionary).duplicate(true) if typeof(value) == TYPE_DICTIONARY else null


static func _action_id_set(values: Array) -> Dictionary:
	var result := {}
	for value: Variant in values:
		if value is String:
			result[value] = true
	return result


static func _validate_pending_event(
	resident_id: String,
	event: Dictionary,
	known_places: Dictionary,
	known_people: Dictionary,
	errors: Array[String],
) -> void:
	var event_type := String(event.get("type", "")) if event.get("type") is String else ""
	if not SAVED_EVENT_FIELDS.has(event_type):
		errors.append("世界存档居民 %s 的事件类型无效：%s" % [resident_id, event_type])
		return
	var optional_event_fields: Array = []
	# Conversation invitations gained this delivery hint after schema v2.
	# It is optional so older saves remain restorable, but when present it
	# must still be a real boolean (validated below).
	if event_type == "搭话":
		optional_event_fields.append("response_required")
	if event_type in ["公告发布", "公告到点"]:
		optional_event_fields.append("publisher_name")
		optional_event_fields.append("announcement_priority")
	if event_type == "公告发布":
		optional_event_fields.append("scheduled_absolute_minute")
		optional_event_fields.append("scheduled_time_label")
	_validate_exact_keys(
		event,
		SAVED_EVENT_FIELDS[event_type] as Array,
		"世界存档居民 %s 的待交付事件" % resident_id,
		errors,
		optional_event_fields,
	)
	if (
		event_type in ["公告发布", "公告到点"]
		and event.has("announcement_priority")
		and String(event.get("announcement_priority", ""))
		not in ["player", "ordinary"]
	):
		errors.append(
			"世界存档居民 %s 的公告优先级无效" % resident_id
		)
	if _sequence_from_id(_string_or_empty(event.get("event_id")), "world-event-") <= 0:
		errors.append("世界存档居民 %s 的事件缺少 event_id" % resident_id)
	if not event.get("residentId") is String or event.get("residentId") != resident_id:
		errors.append("世界存档居民 %s 的事件接收者不一致" % resident_id)
	if not _valid_saved_time(event.get("time")):
		errors.append("世界存档居民 %s 的事件缺少合法 time" % resident_id)
	match event_type:
		"天气变了":
			if (
				not event.get("weather") is String
				or not WEATHER_TYPES.has(event.get("weather"))
			):
				errors.append("世界存档居民 %s 的天气事件缺少天气" % resident_id)
		"公告发布":
			if _sequence_from_id(_string_or_empty(event.get("announcement_id")), "announcement-") <= 0 or not _nonempty_string(event.get("text")):
				errors.append("世界存档居民 %s 的公告事件无效" % resident_id)
		"公告到点":
			if (
				_sequence_from_id(_string_or_empty(event.get("announcement_id")), "announcement-") <= 0
				or not _nonempty_string(event.get("text"))
				or typeof(event.get("scheduled_absolute_minute")) != TYPE_INT
				or not _nonempty_string(event.get("scheduled_time_label"))
				or String(event.get("status", "")) != "due"
			):
				errors.append("世界存档居民 %s 的公告到点事件无效" % resident_id)
		"公告阅读":
			if (
				_sequence_from_id(
					_string_or_empty(event.get("announcement_id")),
					"announcement-",
				) <= 0
				or not _nonempty_string(event.get("text"))
				or not known_people.has(
					_string_or_empty(event.get("publisher_resident_id"))
				)
				or not _valid_optional_matter_id(event.get("matter_id"))
				or typeof(event.get("read_at")) != TYPE_INT
				or int(event.get("read_at", -1)) < 0
			):
				errors.append("世界存档居民 %s 的公告阅读事件无效" % resident_id)
		"公告转告":
			var speaker_id := _string_or_empty(
				event.get("speaker_resident_id")
			)
			if (
				_sequence_from_id(
					_string_or_empty(event.get("announcement_id")),
					"announcement-",
				) <= 0
				or not _nonempty_string(event.get("text"))
				or speaker_id == resident_id
				or not known_people.has(speaker_id)
				or not _valid_optional_matter_id(event.get("matter_id"))
			):
				errors.append("世界存档居民 %s 的公告转告事件无效" % resident_id)
		"钟声公告":
			var publisher_id := _string_or_empty(event.get("publisher_resident_id"))
			if (
				_sequence_from_id(
					_string_or_empty(event.get("announcement_id")),
					"announcement-",
				) <= 0
				or not _nonempty_string(event.get("text"))
				or not known_people.has(publisher_id)
				or not _valid_optional_matter_id(event.get("matter_id"))
				or event.get("delivery_mode") != "town_bell"
			):
				errors.append("世界存档居民 %s 的钟声公告事件无效" % resident_id)
		"正式通知送达":
			var notice_speaker_id := _string_or_empty(
				event.get("speaker_resident_id")
			)
			if (
				_sequence_from_id(
					_string_or_empty(event.get("announcement_id")),
					"announcement-",
				) <= 0
				or not _nonempty_string(event.get("message_id"))
				or not _nonempty_string(event.get("text"))
				or notice_speaker_id == resident_id
				or not known_people.has(notice_speaker_id)
				or not _valid_optional_matter_id(event.get("matter_id"))
			):
				errors.append("世界存档居民 %s 的正式通知送达事件无效" % resident_id)
		"承诺条件变化":
			if (
				not _nonempty_string(event.get("summary"))
				or not _nonempty_string(event.get("commitment_action_id"))
			):
				errors.append("世界存档居民 %s 的承诺条件变化事件无效" % resident_id)
		"搭话", "对方答话":
			if event_type == "搭话" and event.has("response_required") and not event.get("response_required") is bool:
				errors.append("世界存档居民 %s 的搭话事件 response_required 必须是布尔值" % resident_id)
			if _sequence_from_id(_string_or_empty(event.get("conversation_id")), "conversation-") <= 0:
				errors.append("世界存档居民 %s 的对话事件缺少 conversation_id" % resident_id)
			_validate_saved_turn(
				resident_id,
				event.get("turn"),
				known_people,
				errors,
			)
		"对话结束":
			if _sequence_from_id(_string_or_empty(event.get("conversation_id")), "conversation-") <= 0 or not _nonempty_string(event.get("reason")):
				errors.append("世界存档居民 %s 的对话结束事件无效" % resident_id)
			if not event.get("turns") is Array or (event.get("turns", []) as Array).is_empty():
				errors.append("世界存档居民 %s 的对话结束事件缺少 turns" % resident_id)
			else:
				for turn_value: Variant in event.get("turns", []) as Array:
					_validate_saved_turn(
						resident_id,
						turn_value,
						known_people,
						errors,
					)
		"有人来了", "有人走了":
			var who_id := _string_or_empty(event.get("who_resident_id"))
			if (
				who_id == resident_id
				or not known_people.has(who_id)
				or event.get("who") != known_people.get(who_id)
			):
				errors.append("世界存档居民 %s 的人物感知事件无效" % resident_id)
		"居民死亡":
			var deceased_id := _string_or_empty(
				event.get("deceased_resident_id"),
			)
			if (
				deceased_id.is_empty()
				or deceased_id == resident_id
				or not known_people.has(deceased_id)
				or not _nonempty_string(event.get("deceased_resident_name"))
				or not _nonempty_string(event.get("reason"))
				or event.get("location") is not Dictionary
				or not _nonempty_string(
					(event.get("location") as Dictionary).get("placeName"),
				)
			):
				errors.append("世界存档居民 %s 的死亡事件无效" % resident_id)
		"营业状态变化":
			var changed_by_id := _string_or_empty(
				event.get("changed_by_resident_id")
			)
			if (
				not _nonempty_string(event.get("place_id"))
				or not known_places.has(event.get("place_id"))
				or typeof(event.get("open")) != TYPE_BOOL
				or not _nonempty_string(event.get("summary"))
				or (
					not changed_by_id.is_empty()
					and not known_people.has(changed_by_id)
				)
			):
				errors.append(
					"世界存档居民 %s 的营业状态变化事件无效"
					% resident_id
				)
		"身体状况变化":
			if (
				not _nonempty_string(event.get("eventId"))
				or String(event.get("eventType", ""))
					not in CONDITION_EVENT_TYPES
				or not _nonempty_string(event.get("conditionId"))
				or not _nonempty_string(event.get("conditionKind"))
				or not _nonempty_string(event.get("label"))
				or String(event.get("severity", ""))
					not in ["minor", "noticeable", "serious"]
				or String(event.get("state", ""))
					not in ["active", "recovering"]
				or typeof(event.get("atMinute")) != TYPE_INT
				or int(event.get("atMinute", -1)) < 0
				or not _nonempty_string(event.get("sourceRef"))
			):
				errors.append(
					"世界存档居民 %s 的身体状况事件无效"
					% resident_id
				)
		"冲突见闻":
			var conflict_knowledge_kind := String(event.get("knowledge_kind", ""))
			var conflict_source_id := _string_or_empty(event.get("source_resident_id"))
			var conflict_actor_ids_value: Variant = event.get("actor_ids", [])
			var conflict_actor_ids := (
				conflict_actor_ids_value as Array
				if conflict_actor_ids_value is Array
				else []
			)
			var conflict_actors_valid := (
				conflict_actor_ids_value is Array
				and not conflict_actor_ids.is_empty()
			)
			var seen_conflict_actors := {}
			for actor_id_value: Variant in conflict_actor_ids:
				var actor_id := _string_or_empty(actor_id_value)
				if (
					actor_id.is_empty()
					or not known_people.has(actor_id)
					or seen_conflict_actors.has(actor_id)
				):
					conflict_actors_valid = false
				seen_conflict_actors[actor_id] = true
			var conflict_source_valid := (
				(
					conflict_knowledge_kind == "hearsay"
					and not conflict_source_id.is_empty()
					and conflict_source_id != resident_id
					and known_people.has(conflict_source_id)
				)
				or (
					conflict_knowledge_kind in ["participant", "witness"]
					and conflict_source_id.is_empty()
				)
			)
			var conflict_role_valid := (
				(
					conflict_knowledge_kind == "participant"
					and conflict_actor_ids.has(resident_id)
				)
				or (
					conflict_knowledge_kind in ["witness", "hearsay"]
					and not conflict_actor_ids.has(resident_id)
				)
			)
			if (
				not _nonempty_string(event.get("conflict_id"))
				or not _nonempty_string(event.get("conflict_event_id"))
				or String(event.get("conflict_event_type", ""))
					not in CONFLICT_EVENT_TYPES
				or conflict_knowledge_kind not in ["participant", "witness", "hearsay"]
				or not conflict_source_valid
				or not conflict_actors_valid
				or not conflict_role_valid
				or (
					not String(event.get("place_id", "")).is_empty()
					and not known_places.has(event.get("place_id"))
				)
				or String(event.get("severity", "")) not in ["", "light", "heavy"]
				or not _nonempty_string(event.get("summary"))
			):
				errors.append("世界存档居民 %s 的冲突见闻事件无效" % resident_id)
		"旁听":
			if (
				_sequence_from_id(
					_string_or_empty(event.get("conversation_id")),
					"conversation-",
				) <= 0
			):
				errors.append(
					"世界存档居民 %s 的旁听事件缺少 conversation_id"
					% resident_id
				)
			for key in ["speaker_resident_ids", "speakers"]:
				if (
					typeof(event.get(key)) != TYPE_ARRAY
					or (event.get(key, []) as Array).size() != 2
					or not (event.get(key, []) as Array).all(
						func(value: Variant) -> bool: return _nonempty_string(value)
					)
				):
					errors.append("世界存档居民 %s 的旁听事件缺少 %s" % [resident_id, key])
			var speaker_ids_value: Variant = event.get("speaker_resident_ids")
			var speaker_names_value: Variant = event.get("speakers")
			if (
				speaker_ids_value is Array
				and speaker_names_value is Array
				and (speaker_ids_value as Array).size() == 2
				and (speaker_names_value as Array).size() == 2
			):
				var speaker_ids := speaker_ids_value as Array
				var speaker_names := speaker_names_value as Array
				var seen_speakers := {}
				for speaker_index in range(2):
					var speaker_id := _string_or_empty(
						speaker_ids[speaker_index]
					)
					if (
						seen_speakers.has(speaker_id)
						or not known_people.has(speaker_id)
						or speaker_names[speaker_index]
						!= known_people.get(speaker_id)
					):
						errors.append(
							"世界存档居民 %s 的旁听人物身份无效"
							% resident_id
						)
					seen_speakers[speaker_id] = true
			_validate_saved_turn(
				resident_id,
				event.get("turn"),
				known_people,
				errors,
			)


static func _validate_pending_action_result(
	resident_id: String,
	result: Dictionary,
	errors: Array[String],
) -> void:
	var expected_fields := [
		"residentId", "action_id", "status", "reason", "time",
	]
	# 动作结果只在命中正式图标语义时整组携带表现字段。
	if result.has("baseIconKey"):
		expected_fields.append_array([
			"baseIconKey", "label", "sourceActivityId", "phase",
		])
	_validate_exact_keys(
		result,
		expected_fields,
		"世界存档居民 %s 的待交付动作结果" % resident_id,
		errors,
	)
	if not result.get("residentId") is String or result.get("residentId") != resident_id:
		errors.append("世界存档居民 %s 的动作结果接收者不一致" % resident_id)
	if not _nonempty_string(result.get("action_id")):
		errors.append("世界存档居民 %s 的动作结果缺少 action_id" % resident_id)
	if not result.get("status") is String or result.get("status") not in ["rejected", "replaced", "interrupted", "completed"]:
		errors.append("世界存档居民 %s 的动作结果状态无效" % resident_id)
	if not _nonempty_string(result.get("reason")):
		errors.append("世界存档居民 %s 的动作结果缺少 reason" % resident_id)
	if not _valid_saved_time(result.get("time")):
		errors.append("世界存档居民 %s 的动作结果缺少合法 time" % resident_id)


static func _validate_saved_turn(
	resident_id: String,
	turn_value: Variant,
	known_people: Dictionary,
	errors: Array[String],
) -> void:
	if not turn_value is Dictionary:
		errors.append("世界存档居民 %s 的对话事件缺少合法 turn" % resident_id)
		return
	var turn := turn_value as Dictionary
	_validate_exact_keys(
		turn,
		["turn_id", "speaker_resident_id", "speaker", "say", "narration", "photos"],
		"世界存档居民 %s 的待交付对话轮次" % resident_id,
		errors,
	)
	if typeof(turn.get("turn_id")) != TYPE_INT or int(turn.get("turn_id", 0)) <= 0:
		errors.append("世界存档居民 %s 的对话轮次编号无效" % resident_id)
	for key in ["speaker_resident_id", "speaker"]:
		if not _nonempty_string(turn.get(key)):
			errors.append("世界存档居民 %s 的对话轮次缺少 %s" % [resident_id, key])
	var speaker_id := _string_or_empty(turn.get("speaker_resident_id"))
	if (
		not known_people.has(speaker_id)
		or turn.get("speaker") != known_people.get(speaker_id)
	):
		errors.append("世界存档居民 %s 的对话轮次说话人身份无效" % resident_id)
	for key in ["say", "narration"]:
		if not turn.get(key) is String:
			errors.append("世界存档居民 %s 的对话轮次 %s 必须是文本" % [resident_id, key])
	_validate_photos(resident_id, turn.get("photos"), "对话轮次", errors)


static func _valid_saved_time(value: Variant) -> bool:
	return SAVE_CODEC.validate_time_snapshot(value).is_empty()


static func _route_inputs_have_valid_containers(action: Dictionary) -> bool:
	if action.is_empty():
		return true
	var action_type := _string_or_empty(action.get("type"))
	if action_type == "去":
		return action.get("route") is Dictionary
	if action_type == "用道具":
		return action.get("pathPoints") is Array
	return true


static func _validate_membership(
	person_id: String,
	state: Dictionary,
	world_data: Dictionary,
	errors: Array[String],
) -> void:
	if not state.get("position") is Vector2:
		return
	var space_id := _string_or_empty(state.get("spaceId"))
	var region_id := _string_or_empty(state.get("regionId"))
	var place_name := _string_or_empty(state.get("currentPlace"))
	var position := state.get("position", Vector2.ZERO) as Vector2
	for region_value: Variant in world_data.get("perceptionRegions", []) as Array:
		if not region_value is Dictionary:
			continue
		var region := region_value as Dictionary
		if (
			String(region.get("id", "")) == region_id
			and String(region.get("spaceId", "")) == space_id
			and String(region.get("placeName", "")) == place_name
			and _position_in_shape(position, region.get("shape", {}) as Dictionary)
		):
			return
	errors.append("世界存档人物 %s 的位置、区域与地点归属不一致" % person_id)


static func _sequence_from_id(id: String, prefix: String) -> int:
	return SAVE_SCALARS_UTIL.sequence_from_id(id, prefix)


static func _position_in_shape(position: Vector2, shape: Dictionary) -> bool:
	if String(shape.get("type", "")) == "grid_cells":
		var cell_size := int(shape.get("cellSize", 0))
		if cell_size <= 0:
			return false
		var expected := Vector2i(
			floori(position.x / float(cell_size)),
			floori(position.y / float(cell_size)),
		)
		for value: Variant in shape.get("cells", []) as Array:
			if value is Array and (value as Array).size() == 2:
				var pair := value as Array
				if Vector2i(int(pair[0]), int(pair[1])) == expected:
					return true
		return false
	if String(shape.get("type", "")) == "rect":
		return Rect2(
			float(shape.get("x", 0.0)),
			float(shape.get("y", 0.0)),
			float(shape.get("width", 0.0)),
			float(shape.get("height", 0.0)),
		).has_point(position)
	return false


static func _validate_exact_keys(
	value: Dictionary,
	allowed: Array,
	label: String,
	errors: Array[String],
	optional: Array = [],
) -> void:
	for key_value: Variant in value:
		if (
			not key_value is String
			or (
				not allowed.has(key_value)
				and not optional.has(key_value)
			)
		):
			errors.append("%s 包含未知字段：%s" % [label, str(key_value)])
	for key_value: Variant in allowed:
		if not value.has(key_value):
			errors.append("%s 缺少字段：%s" % [label, str(key_value)])


static func _dictionary_has_exact_keys(
	value: Dictionary,
	expected: Array[String],
) -> bool:
	if value.size() != expected.size():
		return false
	for key_value: Variant in value:
		if not key_value is String or not expected.has(String(key_value)):
			return false
	return true


static func _nonempty_string(value: Variant) -> bool:
	return value is String and not String(value).strip_edges().is_empty()


static func _valid_optional_matter_id(value: Variant) -> bool:
	if value == null:
		return true
	if not value is String:
		return false
	var matter_id := String(value)
	if not matter_id.begins_with("matter-"):
		return false
	var suffix := matter_id.trim_prefix("matter-")
	return (
		suffix.length() == 6
		and suffix.is_valid_int()
		and not suffix.begins_with("+")
		and int(suffix) > 0
		and matter_id == "matter-%06d" % int(suffix)
	)


static func _string_or_empty(value: Variant) -> String:
	return value as String if value is String else ""


static func _finite_number_or_zero(value: Variant) -> float:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return 0.0
	var number := float(value)
	return number if is_finite(number) else 0.0


static func _finite_vector(value: Variant) -> bool:
	return value is Vector2 and is_finite((value as Vector2).x) and is_finite((value as Vector2).y)


static func resident_condition_seed(resident_id: String) -> int:
	return ("%s:resident-conditions" % resident_id).hash()


static func prepare_resident_conditions(
	prepared: Dictionary,
) -> Dictionary:
	var resident_ids: Array[String] = []
	for resident_id_value: Variant in (
		prepared.get("residents", {}) as Dictionary
	):
		resident_ids.append(String(resident_id_value))
	resident_ids.sort()
	var conditions: RefCounted = RESIDENT_CONDITION_RUNTIME.new()
	var configured := conditions.configure() as Dictionary
	if configured.get("ok") != true:
		return {
			"ok": false,
			"errors": ["居民临时状况目录无法配置"],
		}
	var condition_snapshot_value: Variant = prepared.get("residentConditions")
	if condition_snapshot_value is Dictionary:
		var restored := conditions.restore_from_snapshot(condition_snapshot_value as Dictionary,) as Dictionary
		if restored.get("ok") != true:
			return {
				"ok": false,
				"errors": ["居民临时状况存档内容无效"],
			}
	else:
		for resident_id in resident_ids:
			var initialized := conditions.initialize_resident(resident_id,
				resident_condition_seed(resident_id),) as Dictionary
			if initialized.get("ok") != true:
				return {
					"ok": false,
					"errors": ["居民临时状况旧存档迁移失败"],
				}
	var sleep: RefCounted = RESIDENT_SLEEP_RUNTIME.new()
	var sleep_snapshot_value: Variant = prepared.get("residentSleep")
	if sleep_snapshot_value is Dictionary:
		var restored_sleep := sleep.restore_from_snapshot(sleep_snapshot_value as Dictionary,) as Dictionary
		if restored_sleep.get("ok") != true:
			return {
				"ok": false,
				"errors": ["居民睡眠存档内容无效"],
			}
	else:
		for resident_id in resident_ids:
			var initialized_sleep := sleep.initialize_resident(resident_id,) as Dictionary
			if initialized_sleep.get("ok") != true:
				return {
					"ok": false,
					"errors": ["居民睡眠旧存档迁移失败"],
				}
	var condition_resident_ids: Array[String] = []
	condition_resident_ids.assign(conditions.resident_ids() as Array)
	var sleep_resident_ids: Array[String] = []
	sleep_resident_ids.assign(sleep.resident_ids() as Array)
	if condition_resident_ids != resident_ids or sleep_resident_ids != resident_ids:
		return {
			"ok": false,
			"errors": ["居民临时状况或睡眠存档名单与世界居民不一致"],
		}
	return {
		"ok": true,
		"conditions": conditions,
		"sleep": sleep,
	}


# world 只用于取居民家宅锚点（TownWorldRuntime._resident_home_anchor），
# 该逻辑同时服务开局初始化与恢复应用，保留在世界运行时里。
static func prepare_resident_lifecycle(
	world: RefCounted,
	world_data: Dictionary,
	residents: Dictionary,
	snapshot_value: Variant,
) -> Dictionary:
	var lifecycle: RefCounted = RESIDENT_LIFECYCLE_RUNTIME.new()
	for resident_value: Variant in residents.values():
		var resident := resident_value as Dictionary
		var resident_id := String(resident.get("residentId", "")).strip_edges()
		var profile_attributes := resident.get("profileAttributes", {}) as Dictionary
		var runtime_attributes := resident.get("attributes", {}) as Dictionary
		var resident_name := String(
			resident.get(
				"name",
				profile_attributes.get("name", runtime_attributes.get("name", "")),
			),
		).strip_edges()
		var initialized := lifecycle.initialize_resident(resident_id,
			resident_name,
			world.call("_resident_home_anchor", world_data, resident),) as Dictionary
		if initialized.get("ok") != true:
			return {"ok": false, "errors": initialized.get("errors", ["居民生命状态初始化失败"])}
	if snapshot_value is Dictionary:
		var restored := lifecycle.restore_save_snapshot(snapshot_value as Dictionary) as Dictionary
		if restored.get("ok") != true:
			return {"ok": false, "errors": restored.get("errors", ["居民生命状态恢复失败"])}
	var living_residents := {}
	for resident_id_value: Variant in residents:
		var resident_id := String(resident_id_value)
		if bool(lifecycle.is_alive(resident_id)):
			living_residents[resident_id] = (residents[resident_id_value] as Dictionary).duplicate(true)
	return {
		"ok": true,
		"snapshot": lifecycle.create_save_snapshot() as Dictionary,
		"livingResidents": living_residents,
	}
