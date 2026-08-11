extends RefCounted


# O 域迁移第二件:动作校验族(纯函数五件)+T1 字段白名单权威表随族归位。

const ACTION_FIELDS := {
	"去": ["action_id", "type", "place", "line"],
	"用道具": ["action_id", "type", "prop", "verb", "line"],
	"做活动": ["action_id", "type", "activity_id", "line"],
	"调整营业": ["action_id", "type", "place_id", "open", "line"],
	"托人传话": [
		"action_id",
		"type",
		"recipient_resident_id",
		"content",
		"line",
	],
	"待着": ["action_id", "type", "line"],
	"搭话": ["action_id", "type", "target_resident_id", "say", "narration", "photos"],
	"答话": [
		"action_id",
		"type",
		"conversation_id",
		"say",
		"narration",
		"photos",
		"end",
		"medical_response",
	],
	"争执": [
		"action_id",
		"type",
		"tension_option_id",
		"line",
	],
	"攻击": [
		"action_id",
		"type",
		"target_resident_id",
		"attack_kind",
		"cause_id",
		"line",
	],
	"回应冲突": [
		"action_id",
		"type",
		"conflict_id",
		"response_kind",
		"line",
	],
	"介入冲突": [
		"action_id",
		"type",
		"conflict_id",
		"intervention_kind",
		"line",
	],
	"离开冲突": [
		"action_id",
		"type",
		"conflict_id",
		"reason",
		"line",
	],
}

static func require_action_texts(action: Dictionary, fields: Array[String], action_type: String) -> String:
	for field_name in fields:
		if not action.get(field_name) is String or String(action.get(field_name)).strip_edges().is_empty():
			return "%s 动作 %s 必须是非空文本" % [action_type, field_name]
	return ""

static func validate_action_shape(action: Dictionary) -> String:
	if not action.get("action_id") is String or String(action.get("action_id")).strip_edges().is_empty():
		return "动作 action_id 必须是非空文本"
	if not action.get("type") is String or String(action.get("type")).strip_edges().is_empty():
		return "动作 type 必须是非空文本"
	var action_type := String(action.get("type"))
	if not ACTION_FIELDS.has(action_type):
		return "当前运行层尚未接入动作类型：%s" % action_type
	var allowed_fields := ACTION_FIELDS[action_type] as Array
	for key_value: Variant in action:
		if not key_value is String or not allowed_fields.has(key_value):
			return "%s 动作包含未知字段：%s" % [action_type, str(key_value)]
	match action_type:
		"去":
			return require_action_texts(action, ["place", "line"], action_type)
		"用道具":
			return require_action_texts(action, ["prop", "verb", "line"], action_type)
		"做活动":
			return require_action_texts(
				action,
				["activity_id", "line"],
				action_type,
			)
		"调整营业":
			var service_error := require_action_texts(
				action,
				["place_id", "line"],
				action_type,
			)
			if not service_error.is_empty():
				return service_error
			if not action.get("open") is bool:
				return "调整营业动作 open 必须是布尔值"
			return ""
		"托人传话":
			var message_error := require_action_texts(
				action,
				["recipient_resident_id", "content", "line"],
				action_type,
			)
			if not message_error.is_empty():
				return message_error
			if String(action.get("content", "")).length() > 240:
				return "托人传话动作 content 最多 240 字"
			return ""
		"待着":
			return require_action_texts(action, ["line"], action_type)
		"搭话":
			var target_id_present := action.has("target_resident_id")
			var target_name_present := action.has("target")
			if not target_id_present and not target_name_present:
				return "搭话动作必须包含 target_resident_id"
			if target_id_present and (not action.get("target_resident_id") is String or String(action.get("target_resident_id")).strip_edges().is_empty()):
				return "搭话动作 target_resident_id 必须是非空文本"
			if target_name_present and (not action.get("target") is String or String(action.get("target")).strip_edges().is_empty()):
				return "搭话动作 target 必须是非空文本"
			if action.has("line") and (not action.get("line") is String or String(action.get("line")).strip_edges().is_empty()):
				return "搭话动作 line 必须是非空文本"
		"答话":
			var field_error := require_action_texts(action, ["conversation_id"], action_type)
			if not field_error.is_empty():
				return field_error
	return ""

static func validate_conversation_follow_up_shape(value: Variant) -> String:
	if value is not Dictionary:
		return "conversation_follow_up 必须是对象"
	var follow_up := value as Dictionary
	if (
		follow_up.size() != 1
		or not follow_up.has("option_id")
		or follow_up.get("option_id") is not String
		or String(follow_up.get("option_id", "")).strip_edges().is_empty()
	):
		return "conversation_follow_up 只能包含非空 option_id"
	return ""

static func invalid_action_fingerprint(action: Dictionary, reason: String) -> String:
	var action_type := String(action.get("type", "")).strip_edges()
	var structural_target := ""
	match action_type:
		"去":
			structural_target = String(action.get("place", "")).strip_edges()
		"用道具":
			structural_target = "%s|%s" % [
				String(action.get("prop", "")).strip_edges(),
				String(action.get("verb", "")).strip_edges(),
			]
		"搭话":
			structural_target = String(
				action.get("target_resident_id", "")
			).strip_edges()
		"答话":
			structural_target = "%s|%s" % [
				String(action.get("conversation_id", "")).strip_edges(),
				str(bool(action.get("end", false))),
			]
		_:
			structural_target = String(
				action.get("operation", action.get("activityId", ""))
			).strip_edges()
	return "%s\n%s\n%s" % [
		action_type,
		structural_target,
		reason.strip_edges(),
	]

static func is_continuity_wait_action(action: Dictionary) -> bool:
	return (
		String(action.get("type", "")) == "待着"
		and String(action.get("action_id", "")).ends_with("-continuity")
	)


const REACTION_TEXT_MAX_LENGTH := 32
const REACTION_RESULT_STATUSES := [
	"completed", "interrupted", "rejected", "failed",
]

static func clear_rejected_action_streak(resident: Dictionary) -> void:
	resident["lastRejectedActionFingerprint"] = ""
	resident["consecutiveRejectedActionCount"] = 0

static func inflight_requires_reply(events: Array) -> bool:
	var requires_reply := false
	for value: Variant in events:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var event := value as Dictionary
		var event_type := String(event.get("type", ""))
		if (
			event_type == "搭话"
			and bool(event.get("response_required", false))
		):
			requires_reply = true
		elif event_type == "对方答话":
			requires_reply = true
		elif event_type == "对话结束":
			requires_reply = false
	return requires_reply

static func reaction_source_action_id(results: Array) -> String:
	for index in range(results.size() - 1, -1, -1):
		var value: Variant = results[index]
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var result := value as Dictionary
		if String(result.get("status", "")) not in REACTION_RESULT_STATUSES:
			continue
		var action_id := String(result.get("action_id", "")).strip_edges()
		if not action_id.is_empty():
			return action_id
	return ""

static func reaction_source_event_id(events: Array) -> String:
	var event_ids := announcement_reaction_source_event_ids(events)
	return event_ids[event_ids.size() - 1] if not event_ids.is_empty() else ""

static func announcement_reaction_source_event_ids(events: Array) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in events:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var event := value as Dictionary
		if String(event.get("type", "")) not in ["公告发布", "公告到点"]:
			continue
		var event_id := String(event.get("event_id", "")).strip_edges()
		if not event_id.is_empty() and not result.has(event_id):
			result.append(event_id)
	return result

static func validate_reaction_shape(
	value: Variant,
	inflight_events: Array,
	inflight_results: Array,
) -> String:
	if typeof(value) != TYPE_DICTIONARY:
		return "决定 reaction 必须是对象"
	var reaction := value as Dictionary
	for key_value: Variant in reaction:
		if (
			not key_value is String
			or not ["source_action_id", "text"].has(key_value)
		):
			return "reaction 包含未知字段：%s" % str(key_value)
	var source_action_id := String(
		reaction.get("source_action_id", "")
	).strip_edges() if reaction.get("source_action_id", "") is String else ""
	if source_action_id.is_empty():
		return "reaction.source_action_id 必须是非空文本"
	if (
		not reaction.get("text") is String
		or String(reaction.get("text")).strip_edges().is_empty()
	):
		return "reaction.text 必须是非空文本"
	var text := String(reaction.get("text")).strip_edges()
	if text.contains("\n") or text.contains("\r") or text.contains("\t"):
		return "reaction.text 必须是单行文字"
	if text.length() > REACTION_TEXT_MAX_LENGTH:
		return "reaction.text 最多 %d 个字符" % REACTION_TEXT_MAX_LENGTH
	if inflight_requires_reply(inflight_events):
		return "当前需要答话，不允许同时提交动作结果 reaction"
	var expected_action_id := reaction_source_action_id(inflight_results)
	if expected_action_id.is_empty():
		return "本次决定没有可回应的动作结果"
	if source_action_id != expected_action_id:
		return "reaction.source_action_id 必须指向本次最新的可回应动作结果"
	return ""

static func validate_announcement_reactions_shape(
	value: Variant,
	inflight_events: Array,
) -> String:
	if value is not Array:
		return "announcement_reactions 必须是数组"
	var expected_ids := announcement_reaction_source_event_ids(inflight_events)
	var seen: Dictionary = {}
	for index: int in (value as Array).size():
		var reaction_value: Variant = (value as Array)[index]
		if reaction_value is not Dictionary:
			return "announcement_reactions[%d] 必须是对象" % index
		var reaction := reaction_value as Dictionary
		for key_value: Variant in reaction:
			if (
				not key_value is String
				or not ["source_event_id", "text"].has(key_value)
			):
				return "announcement_reactions[%d] 包含未知字段：%s" % [index, str(key_value)]
		var source_event_id := String(
			reaction.get("source_event_id", "")
		).strip_edges() if reaction.get("source_event_id", "") is String else ""
		if source_event_id.is_empty() or not expected_ids.has(source_event_id):
			return "announcement_reactions[%d].source_event_id 不属于本轮公告" % index
		if seen.has(source_event_id):
			return "同一公告不能重复提交回应：%s" % source_event_id
		seen[source_event_id] = true
		if (
			not reaction.get("text") is String
			or String(reaction.get("text")).strip_edges().is_empty()
		):
			return "announcement_reactions[%d].text 必须是非空文本" % index
		var text := String(reaction.get("text")).strip_edges()
		if text.contains("\n") or text.contains("\r") or text.contains("\t"):
			return "announcement_reactions[%d].text 必须是单行文字" % index
		if text.length() > REACTION_TEXT_MAX_LENGTH:
			return "announcement_reactions[%d].text 最多 %d 个字符" % [index, REACTION_TEXT_MAX_LENGTH]
	return ""

static func validate_decision_shape(
	decision: Dictionary,
	inflight_events: Array = [],
	inflight_results: Array = [],
) -> String:
	if not decision.get("decision_id") is String or String(decision.get("decision_id")).strip_edges().is_empty():
		return "决定 decision_id 必须是非空文本"
	if not decision.get("handling") is String:
		return "决定 handling 必须是文本"
	var handling := String(decision.get("handling"))
	var allowed_fields := ["decision_id", "handling"]
	if handling == "replace_current":
		allowed_fields.append("action")
	if decision.has("reaction"):
		allowed_fields.append("reaction")
	if decision.has("announcement_reactions"):
		allowed_fields.append("announcement_reactions")
	if decision.has("social_response"):
		allowed_fields.append("social_response")
	if decision.has("social_attention"):
		allowed_fields.append("social_attention")
	if decision.has("social_request"):
		allowed_fields.append("social_request")
	if decision.has("conversation_follow_up"):
		allowed_fields.append("conversation_follow_up")
	if decision.has("conflict_intent"):
		allowed_fields.append("conflict_intent")
	for key_value: Variant in decision:
		if not key_value is String or not allowed_fields.has(key_value):
			return "决定包含未知字段：%s" % str(key_value)
	if handling == "continue_current":
		if decision.has("action"):
			return "continue_current 不允许携带 action"
	elif handling != "replace_current":
		return "决定 handling 必须是 continue_current 或 replace_current"
	elif not decision.get("action") is Dictionary:
		return "replace_current 必须携带动作对象"
	else:
		var action_shape_error := validate_action_shape(
			decision.get("action") as Dictionary
		)
		if not action_shape_error.is_empty():
			return action_shape_error
	if decision.has("reaction"):
		var reaction_error := validate_reaction_shape(
			decision.get("reaction"),
			inflight_events,
			inflight_results,
		)
		if not reaction_error.is_empty():
			return reaction_error
	if decision.has("announcement_reactions"):
		var announcement_reaction_error := validate_announcement_reactions_shape(
			decision.get("announcement_reactions"),
			inflight_events,
		)
		if not announcement_reaction_error.is_empty():
			return announcement_reaction_error
	# 对话后续是可选附件。它写坏时只忽略承诺，不能把一轮合法答话
	# 一起判失败；具体 option_id 在本轮 World 快照中另行核对。
	return ""

static func append_or_replace_action_result(
	queue: Array,
	result: Dictionary,
) -> void:
	var action_id := String(result.get("action_id", "")).strip_edges()
	if action_id.is_empty():
		queue.append(result.duplicate(true))
		return
	for index in queue.size():
		var existing_value: Variant = queue[index]
		if (
			existing_value is Dictionary
			and String(
				(existing_value as Dictionary).get("action_id", "")
			).strip_edges()
			== action_id
		):
			# World exposes at most one terminal fact per action in a wake. If
			# multiple subsystems settle the same action before dispatch, the
			# latest authoritative outcome replaces the older queued outcome.
			queue[index] = result.duplicate(true)
			return
	queue.append(result.duplicate(true))

static func deduplicated_action_results(values: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value: Variant in values:
		if not value is Dictionary:
			continue
		append_or_replace_action_result(result, value as Dictionary)
	return result
