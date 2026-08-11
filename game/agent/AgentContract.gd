class_name AgentContract
extends RefCounted


const INTERESTS := preload(
	"res://world/data/town/TownInterestCatalog.gd"
)
const CONFLICT_CONTRACT := preload("res://agent/conflict/AgentConflictContract.gd")
const CONFLICT_INTENT := preload("res://agent/conflict/AgentConflictIntent.gd")
const PLACE_TYPES := ["公共地点", "住家", "铺面"]
const PERIODS := ["清晨", "上午", "中午", "下午", "傍晚", "夜里"]
const WEATHER_TYPES := ["晴天", "阴天", "小雨", "中雨", "大雨", "雷暴", "下雪"]
const BODY_STATE_VALUES := {
	"困": ["不困", "有点困", "很困"],
	"饿": ["不饿", "有点饿", "很饿"],
	"累": ["不累", "有点累", "很累"],
}
const ACTION_TYPES := [
	"去",
	"用道具",
	"做活动",
	"调整营业",
	"托人传话",
	"待着",
	"搭话",
	"答话",
	"争执",
	"攻击",
	"回应冲突",
	"介入冲突",
	"离开冲突",
]
const EVENT_TYPES := [
	"搭话",
	"有人来了",
	"有人走了",
	"天气变了",
	"公告发布",
	"公告到点",
	"公告阅读",
	"公告转告",
	"营业状态变化",
	"身体状况变化",
	"承诺条件变化",
	"旁听",
	"对方答话",
	"对话结束",
	"冲突见闻",
]
const ACTION_RESULT_STATUSES := [
	"completed", "interrupted", "rejected", "replaced", "failed",
]
const SOCIAL_RESPONSE_RESULT_STATUSES := [
	"recorded",
	"selected",
	"not_selected",
	"stale",
	"rejected",
]
const SOCIAL_RESPONSE_FIELDS := [
	"response_id",
	"matter_id",
	"matter_revision",
	"response_round_id",
	"option_id",
	"public_text",
]
const SOCIAL_RESPONSE_TEXT_MAX_LENGTH := 80
const SOCIAL_ATTENTION_FIELDS := [
	"exposure_id",
	"matter_id",
	"matter_revision",
	"option_id",
]
const SOCIAL_REQUEST_FIELDS := [
	"recipient_id",
	"place_id",
	"reason_summary",
]
const SOCIAL_REQUEST_TEXT_MAX_LENGTH := 80
const CONVERSATION_FOLLOW_UP_FIELDS := ["option_id"]
const REACTION_RESULT_STATUSES := [
	"completed", "interrupted", "rejected", "failed",
]
const REACTION_FIELDS := ["source_action_id", "text"]
const ANNOUNCEMENT_REACTION_FIELDS := ["source_event_id", "text"]
const REACTION_TEXT_MAX_LENGTH := 32
const CONVERSATION_END_REASONS := ["主动结束", "拒绝接话", "一方离开", "无法继续"]
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
	"争执": ["action_id", "type", "tension_option_id", "line"],
	"攻击": ["action_id", "type", "target_resident_id", "attack_kind", "cause_id", "line"],
	"回应冲突": ["action_id", "type", "conflict_id", "response_kind", "line"],
	"介入冲突": ["action_id", "type", "conflict_id", "intervention_kind", "line"],
	"离开冲突": ["action_id", "type", "conflict_id", "reason", "line"],
}
const VISIBLE_FEATURE_ALIASES := {
	"长椅": [],
	"公告栏": ["公告栏", "告示牌"],
	"露天摊位": ["露天摊位", "摊位", "摊子"],
	"环形步道": ["环形步道"],
	"木栈道": ["木栈道", "栈道"],
	"泊船": ["泊船", "小船"],
}
const ENVIRONMENT_OBJECT_FAMILIES := {
	"长椅类": ["长椅"],
	"椅子类": ["椅", "座位"],
	"桌子类": ["桌"],
	"餐桌类": ["餐桌"],
	"写作桌类": ["写作桌", "写字桌"],
	"阅读桌类": ["阅读桌"],
	"工作台类": ["工作台", "工作桌"],
	"问诊桌类": ["问诊桌"],
	"议事桌类": ["议事桌"],
	"柜台类": ["柜台", "窗口"],
	"储物类": ["货架", "书架", "柜子", "药柜", "档案柜", "备餐柜", "糕点柜", "餐具架"],
	"货架类": ["货架"],
	"书架类": ["书架"],
	"药柜类": ["药柜"],
	"档案柜类": ["档案柜"],
	"备餐柜类": ["备餐柜"],
	"糕点柜类": ["糕点柜"],
	"餐具架类": ["餐具架"],
	"木料架类": ["木料架"],
	"床类": ["床"],
	"灶具类": ["灶台", "炉灶", "烤炉"],
	"水槽类": ["水槽"],
	"机器类": ["咖啡机", "打磨机"],
	"喷泉类": ["喷泉"],
	"雕像类": ["雕像"],
	"沙发类": ["沙发"],
	"秋千类": ["秋千"],
	"凉亭类": ["凉亭", "亭子"],
	"水井类": ["水井"],
	"池塘类": ["池塘"],
}


static func validate_initialization(value: Variant) -> Array[String]:
	var errors: Array[String] = []
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("初始化资料必须是对象")
		return errors

	var data := value as Dictionary
	AgentContractIdentity._validate_allowed_fields(data, ["me", "residents", "places"], "initialization", errors)
	var me := _require_dictionary(data, "me", "me", errors)
	if not me.is_empty():
		AgentContractIdentity._validate_me(me, errors)

	var residents := _require_array(data, "residents", "residents", errors)
	var places := _require_array(data, "places", "places", errors)
	AgentContractIdentity._validate_residents(residents, me, errors)
	AgentContractIdentity._validate_places(places, errors)
	return errors


static func validate_wake_packet(value: Variant) -> Array[String]:
	var errors: Array[String] = []
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("唤醒包必须是对象")
		return errors
	var wake := value as Dictionary
	AgentContractIdentity._validate_allowed_fields(
		wake,
		[
			"decision_id",
			"snapshot",
			"events",
			"action_results",
			"social_response_results",
		],
		"wake",
		errors,
	)
	_require_non_empty_string(wake, "decision_id", "decision_id", errors)
	var snapshot := _require_dictionary(wake, "snapshot", "snapshot", errors)
	if not snapshot.is_empty():
		AgentContractSnapshot._validate_snapshot(snapshot, errors)
	AgentContractEvents._validate_events(_require_array(wake, "events", "events", errors), errors)
	AgentContractEvents._validate_action_results(
		_require_array(wake, "action_results", "action_results", errors),
		errors,
	)
	if wake.has("social_response_results"):
		AgentContractSocial._validate_social_response_results(
			_require_array(
				wake,
				"social_response_results",
				"social_response_results",
				errors,
			),
			errors,
		)
	return errors

static func validate_decision(
	value: Variant,
	initialization: Dictionary,
	wake_packet: Dictionary,
	used_action_ids: Dictionary,
) -> Array[String]:
	var errors: Array[String] = []
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("决定必须是对象")
		return errors
	var decision := value as Dictionary
	var decision_id := _require_non_empty_string(decision, "decision_id", "decision_id", errors)
	if not decision_id.is_empty() and decision_id != String(wake_packet.get("decision_id", "")):
		errors.append("decision_id 必须与当前唤醒包一致")
	var handling := _require_non_empty_string(decision, "handling", "handling", errors)
	var decision_fields: Array = ["decision_id", "handling"]
	if handling == "replace_current":
		decision_fields.append("action")
	if decision.has("reaction"):
		decision_fields.append("reaction")
	if decision.has("announcement_reactions"):
		decision_fields.append("announcement_reactions")
	if decision.has("social_response"):
		decision_fields.append("social_response")
	if decision.has("social_attention"):
		decision_fields.append("social_attention")
	if decision.has("social_request"):
		decision_fields.append("social_request")
	if decision.has("conversation_follow_up"):
		decision_fields.append("conversation_follow_up")
	if decision.has("conflict_intent"):
		decision_fields.append("conflict_intent")
	AgentContractIdentity._validate_allowed_fields(decision, decision_fields, "decision", errors)
	if decision.has("reaction"):
		AgentContractSnapshot._validate_reaction(
			_require_dictionary(decision, "reaction", "reaction", errors),
			wake_packet,
			errors,
		)
	if decision.has("announcement_reactions"):
		AgentContractSnapshot._validate_announcement_reactions(
			decision.get("announcement_reactions"),
			wake_packet,
			errors,
		)
	if decision.has("social_response"):
		AgentContractSocial._validate_social_response(
			_require_dictionary(
				decision,
				"social_response",
				"social_response",
				errors,
			),
			wake_packet,
			errors,
		)
	if decision.has("social_attention"):
		AgentContractSocial._validate_social_attention(
			_require_dictionary(
				decision,
				"social_attention",
				"social_attention",
				errors,
			),
			wake_packet,
			errors,
		)
	if decision.has("social_request"):
		_validate_social_request(
			decision.get("social_request"),
			initialization,
			wake_packet,
			(
				decision.get("action", {}) as Dictionary
				if decision.get("action") is Dictionary
				else {}
			),
			errors,
		)
	if decision.has("conversation_follow_up"):
		_validate_conversation_follow_up(
			decision.get("conversation_follow_up"),
			wake_packet,
			(
				decision.get("action", {}) as Dictionary
				if decision.get("action") is Dictionary
				else {}
			),
			errors,
		)
	if decision.has("conflict_intent"):
		var intent := _require_dictionary(
			decision,
			"conflict_intent",
			"conflict_intent",
			errors,
		)
		var reply_action := (
			decision.get("action", {}) as Dictionary
			if decision.get("action") is Dictionary
			else {}
		)
		if handling != "replace_current" or String(reply_action.get("type", "")) != "答话":
			errors.append("conflict_intent 必须随答话动作提交")
		elif not bool(reply_action.get("end", false)):
			errors.append("conflict_intent 必须随结束对话的答话提交")
		if not wake_allows_reply(wake_packet):
			errors.append("当前唤醒没有可结束的对话，不能提交 conflict_intent")
		if not intent.is_empty():
			errors.append_array(CONFLICT_INTENT.validate(intent, wake_packet))
	if wake_requires_reply(wake_packet):
		if handling != "replace_current":
			errors.append("收到必须回应的搭话或对方答话时必须提交新的答话动作")
		elif typeof(decision.get("action")) != TYPE_DICTIONARY:
			errors.append("收到必须回应的搭话或对方答话时必须提交新的答话动作")
		elif String((decision["action"] as Dictionary).get("type", "")) != "答话":
			errors.append("收到必须回应的搭话或对方答话时必须提交新的答话动作")
	elif (
		handling == "replace_current"
		and decision.get("action") is Dictionary
		and String((decision["action"] as Dictionary).get("type", "")) == "答话"
		and not wake_allows_reply(wake_packet)
	):
		errors.append("只有当前唤醒包含匹配的搭话或对方答话事件时才能提交答话动作")
	if handling == "continue_current":
		if decision.has("action"):
			errors.append("continue_current 不允许 action")
		if wake_has_player_priority_announcement(wake_packet):
			errors.append("玩家公告必须停止普通工作并提交新的实际行动")
		var current_action: Variant = (wake_packet.get("snapshot", {}) as Dictionary) \
			.get("me", {}).get("current_action")
		if current_action == null:
			errors.append("没有当前动作时不能 continue_current")
	elif handling == "replace_current":
		var action := _require_dictionary(decision, "action", "action", errors)
		AgentContractAction._validate_action(action, initialization, wake_packet, used_action_ids, errors)
	elif not handling.is_empty():
		errors.append("handling 必须是 continue_current 或 replace_current")
	return errors


static func validate_social_response(
	value: Variant,
	wake_packet: Dictionary,
) -> Array[String]:
	var errors: Array[String] = []
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("social_response 必须是对象")
		return errors
	AgentContractSocial._validate_social_response(
		value as Dictionary,
		wake_packet,
		errors,
	)
	return errors


static func validate_social_attention(
	value: Variant,
	wake_packet: Dictionary,
) -> Array[String]:
	var errors: Array[String] = []
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("social_attention 必须是对象")
		return errors
	AgentContractSocial._validate_social_attention(
		value as Dictionary,
		wake_packet,
		errors,
	)
	return errors


static func canonicalize_decision(value: Dictionary) -> Dictionary:
	var canonical := {
		"decision_id": value["decision_id"],
		"handling": value["handling"],
	}
	if value.has("reaction"):
		var reaction := value["reaction"] as Dictionary
		canonical["reaction"] = {
			"source_action_id": reaction["source_action_id"],
			"text": reaction["text"],
		}
	if value.has("announcement_reactions"):
		var canonical_announcement_reactions: Array[Dictionary] = []
		for reaction_value: Variant in value["announcement_reactions"] as Array:
			var announcement_reaction := reaction_value as Dictionary
			canonical_announcement_reactions.append({
				"source_event_id": announcement_reaction["source_event_id"],
				"text": announcement_reaction["text"],
			})
		canonical["announcement_reactions"] = canonical_announcement_reactions
	if value.has("social_response"):
		var social_response := value["social_response"] as Dictionary
		var canonical_social_response := {}
		for field: String in SOCIAL_RESPONSE_FIELDS:
			if social_response.has(field):
				canonical_social_response[field] = social_response[field]
		if canonical_social_response.has("matter_revision"):
			canonical_social_response["matter_revision"] = int(
				canonical_social_response["matter_revision"]
			)
		canonical["social_response"] = canonical_social_response
	if value.has("social_attention"):
		canonical["social_attention"] = canonicalize_social_attention(
			value["social_attention"] as Dictionary
		)
	if value.has("social_request"):
		canonical["social_request"] = canonicalize_social_request(
			value["social_request"] as Dictionary
		)
	if value.has("conversation_follow_up"):
		canonical["conversation_follow_up"] = canonicalize_conversation_follow_up(
			value["conversation_follow_up"] as Dictionary
		)
	if value.has("conflict_intent"):
		canonical["conflict_intent"] = CONFLICT_INTENT.canonicalize(
			value["conflict_intent"] as Dictionary
		)
	if value["handling"] != "replace_current":
		return canonical
	var action := value["action"] as Dictionary
	var action_type := String(action["type"])
	var canonical_action := {}
	for field: String in ACTION_FIELDS[action_type]:
		if action.has(field):
			canonical_action[field] = action[field]
	if canonical_action.has("photos"):
		var canonical_photos: Array = []
		for photo: Dictionary in canonical_action["photos"]:
			canonical_photos.append({"ref": photo["ref"], "mime_type": photo["mime_type"]})
		canonical_action["photos"] = canonical_photos
	canonical["action"] = canonical_action
	return canonical


static func normalize_model_decision_references(
	value: Dictionary,
	wake_packet: Dictionary,
) -> Dictionary:
	return CONFLICT_CONTRACT.normalize_model_decision_references(value, wake_packet)


static func canonicalize_social_response(value: Dictionary) -> Dictionary:
	var canonical := {}
	for field: String in SOCIAL_RESPONSE_FIELDS:
		if value.has(field):
			canonical[field] = value[field]
	if canonical.has("matter_revision"):
		canonical["matter_revision"] = int(canonical["matter_revision"])
	return canonical


static func canonicalize_social_attention(value: Dictionary) -> Dictionary:
	var canonical := {}
	for field: String in SOCIAL_ATTENTION_FIELDS:
		if value.has(field):
			canonical[field] = value[field]
	if canonical.has("matter_revision"):
		canonical["matter_revision"] = int(canonical["matter_revision"])
	return canonical


static func validate_social_request(
	value: Variant,
	initialization: Dictionary,
	wake_packet: Dictionary,
	action: Dictionary,
) -> Array[String]:
	var errors: Array[String] = []
	if not value is Dictionary:
		errors.append("social_request 必须是对象")
		return errors
	_validate_social_request(
		value as Dictionary,
		initialization,
		wake_packet,
		action,
		errors,
	)
	return errors


static func _validate_social_request(
	request: Dictionary,
	initialization: Dictionary,
	wake_packet: Dictionary,
	action: Dictionary,
	errors: Array[String],
) -> void:
	AgentContractIdentity._validate_allowed_fields(
		request,
		SOCIAL_REQUEST_FIELDS,
		"social_request",
		errors,
	)
	var recipient_id := _require_non_empty_string(
		request,
		"recipient_id",
		"social_request.recipient_id",
		errors,
	)
	var place_id := _require_non_empty_string(
		request,
		"place_id",
		"social_request.place_id",
		errors,
	)
	var reason_summary := _require_non_empty_string(
		request,
		"reason_summary",
		"social_request.reason_summary",
		errors,
	)
	if (
		reason_summary.contains("\n")
		or reason_summary.contains("\r")
		or reason_summary.contains("\t")
		or reason_summary.length() > SOCIAL_REQUEST_TEXT_MAX_LENGTH
	):
		errors.append(
			"social_request.reason_summary 必须是最多 %d 字的单行文字"
			% SOCIAL_REQUEST_TEXT_MAX_LENGTH
		)
	if (
		String(action.get("type", "")) != "搭话"
		or String(action.get("target_resident_id", ""))
		!= recipient_id
	):
		errors.append("social_request 必须随对同一居民的搭话动作提交")
	var nearby_ids: Array[String] = []
	for nearby_value: Variant in (
		(wake_packet.get("snapshot", {}) as Dictionary).get(
			"nearby",
			[],
		) as Array
	):
		if nearby_value is Dictionary:
			nearby_ids.append(
				String(
					(nearby_value as Dictionary).get(
						"resident_id",
						"",
					)
				)
			)
	if not recipient_id.is_empty() and not nearby_ids.has(recipient_id):
		errors.append("social_request.recipient_id 必须是当前附近居民")
	var known_places: Array[String] = []
	for place_value: Variant in initialization.get("places", []) as Array:
		if place_value is Dictionary:
			known_places.append(
				String((place_value as Dictionary).get("name", ""))
			)
	if not place_id.is_empty() and not known_places.has(place_id):
		errors.append("social_request.place_id 必须来自初始化地点表")


static func canonicalize_social_request(value: Dictionary) -> Dictionary:
	var canonical := {}
	for field: String in SOCIAL_REQUEST_FIELDS:
		if value.has(field):
			canonical[field] = value[field]
	return canonical


static func validate_conversation_follow_up(
	value: Variant,
	wake_packet: Dictionary,
	action: Dictionary,
) -> Array[String]:
	var errors: Array[String] = []
	_validate_conversation_follow_up(value, wake_packet, action, errors)
	return errors


static func canonicalize_conversation_follow_up(value: Dictionary) -> Dictionary:
	return {"option_id": String(value.get("option_id", ""))}


static func validate_conversation_follow_up_speech(
	action: Dictionary,
	has_valid_follow_up: bool,
) -> Array[String]:
	var errors: Array[String] = []
	if String(action.get("type", "")) != "答话":
		return errors
	var say := String(action.get("say", "")).strip_edges()
	var promises_action := _dialogue_promises_follow_up_action(say)
	if promises_action and not has_valid_follow_up:
		errors.append(
			"答话作出了对话后的行动承诺，但没有合法 conversation_follow_up",
		)
	elif has_valid_follow_up and not promises_action:
		errors.append(
			"conversation_follow_up 必须在 action.say 中明确答应对应行动",
		)
	return errors


static func _dialogue_promises_follow_up_action(text: String) -> bool:
	var normalized := text.replace(" ", "").replace("\n", "")
	if normalized.is_empty():
		return false
	for explicit_promise in [
		"交给我",
		"包在我身上",
		"我答应",
		"我负责",
		"我来办",
		"我会处理",
		"我跑一趟",
		"我去一趟",
		"跟我走",
		"跟着我走",
		"跟我来",
		"我带你",
		"我领你",
		"我带路",
		"我领路",
		"咱俩一块走",
		"咱俩一块儿走",
		"咱们一起走",
		"我们一起走",
		"一起走吧",
		"一块走吧",
		"一块儿走吧",
		"行，走吧",
		"行走吧",
		"好，走吧",
		"好走吧",
		"那就走吧",
		"我会去",
		"我会来",
		"我会帮",
		"我愿意去",
		"我愿意来",
		"我愿意帮",
	]:
		if normalized.contains(explicit_promise):
			return true
	var companion_matcher := RegEx.new()
	if (
		companion_matcher.compile(
			"(?:一起|一块儿?|一道|一同|同行|同去|结伴)(?:去|走|过去|出发)",
		) == OK
		and companion_matcher.search(normalized) != null
	):
		return true
	var guide_matcher := RegEx.new()
	if (
		guide_matcher.compile(
			"(?:带|领)(?:你|他|她|他们|她们)(?:去|过去|走|到)",
		) == OK
		and guide_matcher.search(normalized) != null
		and not (
			normalized.contains("不能带")
			or normalized.contains("没法带")
			or normalized.contains("带不了")
			or normalized.contains("不带")
		)
	):
		return true
	var has_future_marker := false
	for future_marker in [
		"现在", "马上", "这就", "待会", "等会", "随后", "之后", "聊完",
	]:
		if normalized.contains(future_marker):
			has_future_marker = true
			break
	if not has_future_marker:
		return false
	var matcher := RegEx.new()
	if matcher.compile(
		"我(?:现在|马上|这就|待会儿?|等会儿?|随后|之后|聊完(?:以后)?)(?:就|会|再|可以|愿意|来)?(?:去|来|帮|带|拿|送|找|问|做|处理|给)",
	) != OK:
		return false
	var search_from := 0
	while search_from < normalized.length():
		var matched := matcher.search(normalized, search_from)
		if matched == null:
			return false
		var end_index := matched.get_end()
		if end_index >= normalized.length() or normalized.substr(end_index, 1) != "过":
			return true
		search_from = maxi(end_index + 1, search_from + 1)
	return false


static func _validate_conversation_follow_up(
	value: Variant,
	wake_packet: Dictionary,
	action: Dictionary,
	errors: Array[String],
) -> void:
	if not value is Dictionary:
		errors.append("conversation_follow_up 必须是对象")
		return
	var follow_up := value as Dictionary
	AgentContractIdentity._validate_allowed_fields(
		follow_up,
		CONVERSATION_FOLLOW_UP_FIELDS,
		"conversation_follow_up",
		errors,
	)
	var option_id := _require_non_empty_string(
		follow_up,
		"option_id",
		"conversation_follow_up.option_id",
		errors,
	)
	if String(action.get("type", "")) != "答话":
		errors.append("conversation_follow_up 必须随当前答话提交")
	if not wake_allows_reply(wake_packet):
		errors.append("当前唤醒没有可以形成后续承诺的对话")
	var known_option_ids: Array[String] = []
	for option_value: Variant in (
		(wake_packet.get("snapshot", {}) as Dictionary).get(
			"conversation_follow_up_options",
			[],
		) as Array
	):
		if option_value is Dictionary:
			known_option_ids.append(
				String((option_value as Dictionary).get("option_id", "")),
			)
	if known_option_ids.is_empty():
		errors.append("当前对话没有可执行的后续行动选项")
	elif not option_id.is_empty() and not known_option_ids.has(option_id):
		errors.append("conversation_follow_up.option_id 必须来自当前对话选项")


static func wake_requires_reply(wake_packet: Dictionary) -> bool:
	return AgentContractWake._wake_requires_reply(wake_packet)


static func wake_requires_initial_invitation_reply(wake_packet: Dictionary) -> bool:
	return AgentContractWake._wake_requires_initial_invitation_reply(wake_packet)


static func wake_allows_reply(wake_packet: Dictionary) -> bool:
	return AgentContractWake._wake_allows_reply(wake_packet)


static func reaction_source_action_id(wake_packet: Dictionary) -> String:
	if wake_requires_reply(wake_packet):
		return ""
	var results := wake_packet.get("action_results", []) as Array
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


static func reaction_source_event_id(wake_packet: Dictionary) -> String:
	var event_ids := announcement_reaction_source_event_ids(wake_packet)
	return event_ids[event_ids.size() - 1] if not event_ids.is_empty() else ""


static func announcement_reaction_source_event_ids(
	wake_packet: Dictionary,
) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in wake_packet.get("events", []) as Array:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var event := value as Dictionary
		if String(event.get("type", "")) not in ["公告发布", "公告到点"]:
			continue
		var event_id := String(event.get("event_id", "")).strip_edges()
		if not event_id.is_empty() and not result.has(event_id):
			result.append(event_id)
	return result


static func wake_has_player_priority_announcement(
	wake_packet: Dictionary,
) -> bool:
	for value: Variant in wake_packet.get("events", []) as Array:
		if value is not Dictionary:
			continue
		var event := value as Dictionary
		if (
			String(event.get("type", "")) in ["公告发布", "公告到点"]
			and String(event.get("announcement_priority", "")) == "player"
		):
			return true
	return false


static func current_action_id(wake_packet: Dictionary) -> String:
	return AgentContractWake._current_action_id(wake_packet)


static func period_for_clock(clock: String) -> String:
	var hour := int(clock.substr(0, 2))
	if hour >= 5 and hour <= 7:
		return "清晨"
	if hour >= 8 and hour <= 11:
		return "上午"
	if hour >= 12 and hour <= 13:
		return "中午"
	if hour >= 14 and hour <= 17:
		return "下午"
	if hour >= 18 and hour <= 20:
		return "傍晚"
	return "夜里"


static func _require_dictionary(
	data: Dictionary,
	key: String,
	path: String,
	errors: Array[String],
) -> Dictionary:
	if not data.has(key):
		errors.append("%s 缺失" % path)
		return {}
	if typeof(data[key]) != TYPE_DICTIONARY:
		errors.append("%s 必须是对象" % path)
		return {}
	return data[key] as Dictionary


static func _require_array(
	data: Dictionary,
	key: String,
	path: String,
	errors: Array[String],
) -> Array:
	if not data.has(key):
		errors.append("%s 缺失" % path)
		return []
	if typeof(data[key]) != TYPE_ARRAY:
		errors.append("%s 必须是数组" % path)
		return []
	return data[key] as Array


static func _require_non_empty_string(
	data: Dictionary,
	key: String,
	path: String,
	errors: Array[String],
) -> String:
	if not data.has(key):
		errors.append("%s 缺失" % path)
		return ""
	if typeof(data[key]) != TYPE_STRING or String(data[key]).strip_edges().is_empty():
		errors.append("%s 必须是非空文本" % path)
		return ""
	return String(data[key])


static func _require_string(
	data: Dictionary,
	key: String,
	path: String,
	errors: Array[String],
) -> String:
	if not data.has(key):
		errors.append("%s 缺失" % path)
		return ""
	if typeof(data[key]) != TYPE_STRING:
		errors.append("%s 必须是文本" % path)
		return ""
	return String(data[key])
